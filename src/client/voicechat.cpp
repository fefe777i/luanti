// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "voicechat.h"

#include "debug.h"
#include "gettext.h"
#include "log.h"
#include "porting.h"
#include "settings.h"
#include "util/numeric.h"
#include "util/voice_codec.h"

#ifdef __ANDROID__
#include "porting_android.h"
#endif

#include <algorithm>
#include <cmath>
#include <cstring>
#include <vector>

namespace
{

// Voices are inaudible beyond the radius. Up to 2 nodes they are at full
// volume, further away they get quieter (-6 dB per doubling of the distance)
// and fade out completely over the last stretch before the radius.
float voiceGain(float dist, float radius)
{
	if (dist >= radius)
		return 0.0f;
	constexpr float NEAR_DIST = 2.0f;
	float g = dist <= NEAR_DIST ? 1.0f : NEAR_DIST / dist;
	float fade_len = std::min(1.5f, radius * 0.15f);
	if (dist > radius - fade_len)
		g *= (radius - dist) / fade_len;
	return g;
}

} // namespace

VoiceChat::VoiceChat() : Thread("VoiceChat")
{
}

VoiceChat::~VoiceChat()
{
	if (isRunning()) {
		stop();
		wait();
	}
	// don't leave key material lying around
	memset(m_priv, 0, sizeof(m_priv));
	memset(m_key_c2s, 0, sizeof(m_key_c2s));
	memset(m_key_s2c, 0, sizeof(m_key_s2c));
}

/*
	Main thread
*/

std::string VoiceChat::createHello()
{
	if (m_have_keypair) // repeated hello: the answer may belong to the first one
		return std::string((const char *)m_pub, sizeof(m_pub));
	if (!porting::secure_rand_fill_buf(m_priv, sizeof(m_priv))) {
		errorstream << "VoiceChat: no secure random numbers, voice chat disabled"
			<< std::endl;
		return "";
	}
	voicecrypto::x25519Public(m_pub, m_priv);
	m_have_keypair = true;
	return std::string((const char *)m_pub, sizeof(m_pub));
}

void VoiceChat::onServerHello(bool enabled, const uint8_t *server_pub, float radius)
{
	if (m_hello_answered && m_active)
		return;
	m_hello_answered = true;

	if (!enabled) {
		pushStatus(N_("Voice chat is turned off on this server."));
		return;
	}
	uint8_t shared[32];
	if (!m_have_keypair || !voicecrypto::x25519Shared(shared, m_priv, server_pub)) {
		warningstream << "VoiceChat: key agreement failed" << std::endl;
		return;
	}
	voicesession::Keys keys = voicesession::deriveKeys(shared, m_pub, server_pub);
	memcpy(m_key_c2s, keys.c2s, 32);
	memcpy(m_key_s2c, keys.s2c, 32);
	memset(shared, 0, sizeof(shared));
	memset(m_priv, 0, sizeof(m_priv));
	m_have_keypair = false;

	m_radius = std::max(1.0f, radius);
	m_keys_ready = true;
	m_active = true;
	start();

	switch (m_mode.load()) {
	case MODE_PTT:
		pushStatus(N_("Voice chat connected. Hold the voice key to talk."));
		break;
	case MODE_VAD:
		pushStatus(N_("Voice chat connected. Just speak to talk."));
		break;
	default:
		pushStatus(N_("Voice chat connected (listen only)."));
		break;
	}
}

void VoiceChat::onHelloTimeout()
{
	pushStatus(N_("This server does not support voice chat."));
}

void VoiceChat::onVoicePacket(u16 speaker, const voicesession::Pos &pos, u32 ctr,
		const std::string &ct)
{
	if (!m_active || m_mode.load() == MODE_OFF)
		return;
	if (!m_rx_window.check(ctr))
		return;

	uint8_t plain[voicesession::DOWNLINK_PLAIN_SIZE];
	if (!voicesession::openDownlink(m_key_s2c, speaker, pos, ctr, ct, plain))
		return;
	m_rx_window.commit(ctr);

	RxFrame rx;
	rx.speaker = speaker;
	rx.pos = v3f(pos.x * 0.01f, pos.y * 0.01f, pos.z * 0.01f);
	rx.seq = (u32)plain[0] | ((u32)plain[1] << 8) | ((u32)plain[2] << 16) |
			((u32)plain[3] << 24);
	if (!voicecodec::decodeFrame(plain + 4, voicecodec::ENCODED_SIZE, rx.pcm.data()))
		return;

	std::lock_guard<std::mutex> lock(m_mutex);
	if (m_rx_queue.size() >= 100)
		m_rx_queue.pop_front();
	m_rx_queue.push_back(rx);
}

void VoiceChat::step(float dtime)
{
	if (m_start_delay > 0.0f)
		m_start_delay -= dtime;

	// Ask again a few times, then assume it is an older server that never
	// answers.
	if (!m_hello_pending && !m_hello_answered) {
		m_hello_age += dtime;
		if (m_hello_age > 3.0f) {
			if (m_hello_tries < 3) {
				m_hello_pending = true;
			} else {
				m_hello_answered = true;
				onHelloTimeout();
			}
		}
	}

	m_settings_timer += dtime;
	if (m_settings_timer >= 1.0f) {
		m_settings_timer = 0.0f;
		const std::string mode = g_settings->get("voice_chat_mode");
		if (mode == "ptt")
			m_mode = MODE_PTT;
		else if (mode == "vad")
			m_mode = MODE_VAD;
		else if (mode == "listen")
			m_mode = MODE_LISTEN;
		else
			m_mode = MODE_OFF;
		m_mic_gain = rangelim(g_settings->getFloat("voice_chat_mic_gain"), 0.1f, 4.0f);
		m_vad_threshold = rangelim(
				g_settings->getFloat("voice_chat_vad_threshold"), 0.001f, 0.5f);
		m_volume = rangelim(g_settings->getFloat("voice_chat_volume"), 0.0f, 2.0f);
	}

	const int mode = m_mode.load();
	const bool needs_mic = mode == MODE_PTT || mode == MODE_VAD;
#ifdef __ANDROID__
	// Android asks the player for microphone access the first time it is needed.
	if (needs_mic && !m_mic_permitted) {
		m_perm_timer += dtime;
		if (m_perm_timer >= 0.5f) {
			m_perm_timer = 0.0f;
			if (porting::hasMicrophonePermission()) {
				m_mic_permitted = true;
			} else if (!m_perm_requested) {
				m_perm_requested = true;
				porting::requestMicrophonePermission();
			}
		}
	}
#else
	// Desktop systems ask (or silently allow) when the device is opened.
	m_mic_permitted = needs_mic;
#endif
}

bool VoiceChat::popOutgoing(OutPacket &out)
{
	std::lock_guard<std::mutex> lock(m_mutex);
	if (m_out_queue.empty())
		return false;
	out = std::move(m_out_queue.front());
	m_out_queue.pop_front();
	return true;
}

bool VoiceChat::popStatus(std::string &msg)
{
	std::lock_guard<std::mutex> lock(m_mutex);
	if (m_status_queue.empty())
		return false;
	msg = std::move(m_status_queue.front());
	m_status_queue.pop_front();
	return true;
}

void VoiceChat::pushStatus(const std::string &msg)
{
	std::lock_guard<std::mutex> lock(m_mutex);
	if (m_status_queue.size() < 8)
		m_status_queue.push_back(msg);
}

/*
	Voice thread
*/

void *VoiceChat::run()
{
	BEGIN_DEBUG_EXCEPTION_HANDLER

#if USE_SOUND
	while (!stopRequested()) {
		updateCapture();

		std::deque<RxFrame> rx;
		{
			std::lock_guard<std::mutex> lock(m_mutex);
			rx.swap(m_rx_queue);
		}
		for (const RxFrame &frame : rx)
			handleRxFrame(frame);

		updateStreams(porting::getTimeMs());
		sleep_ms(5);
	}

	for (auto &it : m_streams)
		destroyStream(it.second);
	m_streams.clear();
	closeCapture();
#else
	while (!stopRequested())
		sleep_ms(100);
#endif

	END_DEBUG_EXCEPTION_HANDLER
	return nullptr;
}

#if USE_SOUND

/*
	Capture
*/

void VoiceChat::closeCapture()
{
	if (m_capture) {
		alcCaptureStop(m_capture);
		alcCaptureCloseDevice(m_capture);
		m_capture = nullptr;
	}
	m_capture_buf.clear();
	m_preroll_count = 0;
	m_hangover = 0;
	m_transmitting = false;
}

void VoiceChat::updateCapture()
{
	const int mode = m_mode.load();
	const bool want = m_keys_ready && m_mic_permitted &&
			(mode == MODE_PTT || mode == MODE_VAD);
	if (!want) {
		if (m_capture)
			closeCapture();
		return;
	}

	if (!m_capture) {
		const u64 now = porting::getTimeMs();
		if (now < m_capture_retry_ms)
			return;
		m_capture = alcCaptureOpenDevice(nullptr, voicecodec::SAMPLE_RATE,
				AL_FORMAT_MONO16, voicecodec::SAMPLE_RATE / 2);
		if (!m_capture) {
			m_capture_retry_ms = now + 5000;
			if (!m_capture_failed_reported) {
				m_capture_failed_reported = true;
				pushStatus(N_("Voice chat: the microphone could not be opened."));
			}
			return;
		}
		alcCaptureStart(m_capture);
		m_capture_failed_reported = false;
		infostream << "VoiceChat: microphone opened" << std::endl;
	}

	ALCint available = 0;
	alcGetIntegerv(m_capture, ALC_CAPTURE_SAMPLES, 1, &available);
	std::vector<s16> tmp;
	while (available > 0) {
		ALCint n = std::min<ALCint>(available, 2048);
		tmp.resize(n);
		alcCaptureSamples(m_capture, tmp.data(), n);
		m_capture_buf.insert(m_capture_buf.end(), tmp.begin(), tmp.end());
		available -= n;
	}

	// Never lag more than a second behind the microphone.
	while (m_capture_buf.size() > (size_t)voicecodec::SAMPLE_RATE)
		m_capture_buf.erase(m_capture_buf.begin(),
				m_capture_buf.begin() + voicecodec::FRAME_SAMPLES);

	std::array<s16, voicecodec::FRAME_SAMPLES> frame;
	while (m_capture_buf.size() >= (size_t)voicecodec::FRAME_SAMPLES) {
		std::copy(m_capture_buf.begin(),
				m_capture_buf.begin() + voicecodec::FRAME_SAMPLES, frame.begin());
		m_capture_buf.erase(m_capture_buf.begin(),
				m_capture_buf.begin() + voicecodec::FRAME_SAMPLES);
		processCaptureFrame(frame.data());
	}
}

void VoiceChat::processCaptureFrame(s16 *frame)
{
	const int mode = m_mode.load();
	const float gain = m_mic_gain.load();

	double sum = 0.0;
	for (int i = 0; i < voicecodec::FRAME_SAMPLES; i++) {
		float v = std::clamp((float)frame[i] * gain, -32767.0f, 32767.0f);
		frame[i] = (s16)v;
		sum += (double)v * v;
	}
	const float level = std::sqrt(sum / voicecodec::FRAME_SAMPLES) / 32768.0f;

	bool trigger;
	int hangover_frames;
	if (mode == MODE_PTT) {
		trigger = m_ptt.load();
		hangover_frames = 8; // 160 ms, don't cut off the end of the last word
	} else {
		// the key/touch button also works in this mode, to force talking
		trigger = level > m_vad_threshold.load() || m_ptt.load();
		hangover_frames = 20; // 400 ms
	}

	bool transmit = false;
	if (trigger) {
		m_hangover = hangover_frames;
		transmit = true;
	} else if (m_hangover > 0) {
		m_hangover--;
		transmit = true;
	}

	if (!transmit) {
		m_transmitting = false;
		// remember the last frames, voice activation sends them when speech
		// starts so the first syllable isn't lost
		if (m_preroll_count == (int)m_preroll.size()) {
			for (size_t i = 1; i < m_preroll.size(); i++)
				m_preroll[i - 1] = m_preroll[i];
			m_preroll_count--;
		}
		memcpy(m_preroll[m_preroll_count].data(), frame,
				sizeof(s16) * voicecodec::FRAME_SAMPLES);
		m_preroll_count++;
		return;
	}

	if (!m_transmitting && mode == MODE_VAD) {
		for (int i = 0; i < m_preroll_count; i++)
			sendFrame(m_preroll[i].data());
	}
	m_preroll_count = 0;
	m_transmitting = true;
	sendFrame(frame);
}

void VoiceChat::sendFrame(const s16 *frame)
{
	if (m_tx_counter == 0xffffffffu)
		return; // out of nonces, a new connection gets fresh keys

	uint8_t encoded[voicecodec::ENCODED_SIZE];
	voicecodec::encodeFrame(frame, encoded);
	const u32 ctr = m_tx_counter++;
	OutPacket out;
	out.counter = ctr;
	out.data = voicesession::sealUplink(m_key_c2s, ctr, encoded, sizeof(encoded));

	std::lock_guard<std::mutex> lock(m_mutex);
	if (m_out_queue.size() >= 25)
		m_out_queue.pop_front();
	m_out_queue.push_back(std::move(out));
}

/*
	Playback
*/

bool VoiceChat::createStream(Stream &st)
{
	alGenSources(1, &st.source);
	if (!alIsSource(st.source)) {
		st.source = 0;
		return false;
	}
	alGenBuffers(NUM_BUFFERS, st.buffers);
	if (!alIsBuffer(st.buffers[0])) {
		alDeleteSources(1, &st.source);
		st.source = 0;
		return false;
	}
	for (int i = 0; i < NUM_BUFFERS; i++)
		st.free_buffers[i] = st.buffers[i];
	st.free_count = NUM_BUFFERS;

	alSourcei(st.source, AL_LOOPING, AL_FALSE);
	alSourcei(st.source, AL_SOURCE_RELATIVE, AL_FALSE);
	// Attenuation is done by us (see voiceGain), OpenAL only does the panning.
	alSourcef(st.source, AL_ROLLOFF_FACTOR, 0.0f);
	alSourcef(st.source, AL_GAIN, 0.0f);
	return true;
}

void VoiceChat::destroyStream(Stream &st)
{
	if (st.source) {
		alSourceStop(st.source);
		alSourcei(st.source, AL_BUFFER, 0); // detach all buffers
		alDeleteSources(1, &st.source);
		alDeleteBuffers(NUM_BUFFERS, st.buffers);
		st.source = 0;
	}
}

void VoiceChat::pushPending(Stream &st,
		const std::array<s16, voicecodec::FRAME_SAMPLES> &f)
{
	st.pending.push_back(f);
	// Keep the delay bounded if frames arrive in a burst.
	while (st.pending.size() > 4)
		st.pending.pop_front();
}

void VoiceChat::handleRxFrame(const RxFrame &rx)
{
	auto it = m_streams.find(rx.speaker);
	if (it == m_streams.end()) {
		if (m_streams.size() >= (size_t)MAX_STREAMS)
			return;
		Stream fresh;
		if (!createStream(fresh))
			return;
		it = m_streams.emplace(rx.speaker, std::move(fresh)).first;
	}
	Stream &st = it->second;
	const u64 now = porting::getTimeMs();

	if (st.have_seq) {
		const s32 diff = (s32)(rx.seq - st.last_seq);
		if (diff <= 0 && diff > -1000)
			return; // late or duplicate frame
		if (diff > 1 && diff <= 4) {
			// Lost frames: repeat the last one quietly once, then silence.
			for (int g = 1; g < diff; g++) {
				std::array<s16, voicecodec::FRAME_SAMPLES> fill = {};
				if (g == 1) {
					for (int i = 0; i < voicecodec::FRAME_SAMPLES; i++)
						fill[i] = st.last_frame[i] / 2;
				}
				pushPending(st, fill);
			}
		}
	}
	st.have_seq = true;
	st.last_seq = rx.seq;
	st.pos = rx.pos;
	st.last_rx_ms = now;

	// Far away voices sound muffled: low-pass filter (two poles) whose cutoff
	// drops with the distance.
	ALfloat lx = 0, ly = 0, lz = 0;
	alGetListener3f(AL_POSITION, &lx, &ly, &lz);
	const float dist = (rx.pos - v3f(lx, ly, lz)).getLength();
	const float radius = m_radius.load();
	const float t = std::clamp(dist / radius, 0.0f, 1.0f);
	const float cutoff = 7500.0f - (7500.0f - 1500.0f) * t;
	constexpr float TWO_PI = 6.2831853f;
	const float a = 1.0f - std::exp(-TWO_PI * cutoff / voicecodec::SAMPLE_RATE);
	// volumes above 1 can't be done with AL_GAIN, boost the samples instead
	const float boost = std::max(1.0f, m_volume.load());

	std::array<s16, voicecodec::FRAME_SAMPLES> out;
	for (int i = 0; i < voicecodec::FRAME_SAMPLES; i++) {
		st.lp1 += a * ((float)rx.pcm[i] - st.lp1);
		st.lp2 += a * (st.lp1 - st.lp2);
		out[i] = (s16)std::clamp(st.lp2 * boost, -32767.0f, 32767.0f);
	}
	st.last_frame = out;
	pushPending(st, out);
}

void VoiceChat::updateStreams(u64 now_ms)
{
	ALfloat lx = 0, ly = 0, lz = 0;
	alGetListener3f(AL_POSITION, &lx, &ly, &lz);
	const v3f listener(lx, ly, lz);
	const float radius = m_radius.load();
	const float volume = std::min(1.0f, m_volume.load());

	for (auto it = m_streams.begin(); it != m_streams.end();) {
		Stream &st = it->second;

		// position and loudness
		const float dist = (st.pos - listener).getLength();
		const float target = voiceGain(dist, radius) * volume;
		st.gain += (target - st.gain) * 0.5f;
		alSourcef(st.source, AL_GAIN, st.gain);
		alSource3f(st.source, AL_POSITION, st.pos.X, st.pos.Y, st.pos.Z);

		// take back buffers that were played
		ALint processed = 0;
		alGetSourcei(st.source, AL_BUFFERS_PROCESSED, &processed);
		while (processed-- > 0) {
			ALuint b = 0;
			alSourceUnqueueBuffers(st.source, 1, &b);
			if (st.free_count < NUM_BUFFERS)
				st.free_buffers[st.free_count++] = b;
		}

		// hand over new audio
		while (!st.pending.empty() && st.free_count > 0) {
			ALuint b = st.free_buffers[--st.free_count];
			const auto &f = st.pending.front();
			alBufferData(b, AL_FORMAT_MONO16, f.data(),
					sizeof(s16) * voicecodec::FRAME_SAMPLES, voicecodec::SAMPLE_RATE);
			alSourceQueueBuffers(st.source, 1, &b);
			st.pending.pop_front();
		}

		ALint state = 0, queued = 0;
		alGetSourcei(st.source, AL_SOURCE_STATE, &state);
		alGetSourcei(st.source, AL_BUFFERS_QUEUED, &queued);
		if (state != AL_PLAYING && queued > 0) {
			// Wait for a little audio to be buffered against network jitter,
			// but don't hold back the tail of a sentence forever.
			if (queued >= 3 || now_ms - st.last_rx_ms > 60)
				alSourcePlay(st.source);
		}

		if (now_ms - st.last_rx_ms > 3000 && queued == 0 && st.pending.empty()) {
			destroyStream(st);
			it = m_streams.erase(it);
		} else {
			++it;
		}
	}
}

#endif // USE_SOUND
