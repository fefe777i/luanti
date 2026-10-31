// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Proximity voice chat, client side.
//
// Records the microphone (OpenAL capture), encodes and encrypts it, and plays
// what other nearby players say from the position of their character
// (OpenAL, with distance attenuation and a low-pass filter that makes distant
// voices sound muffled).
//
// Threading: the network handlers and step() run on the main thread. All
// OpenAL work happens in this class' own thread.

#pragma once

#include "config.h"
#include "irr_v3d.h"
#include "irrlichttypes.h"
#include "threading/thread.h"
#include "util/voice_crypto.h"
#include "util/voice_session.h"

#include <array>
#include <atomic>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

#if USE_SOUND
#include "client/sound/al_helpers.h"
#endif

class VoiceChat final : public Thread
{
public:
	struct OutPacket
	{
		u32 counter;
		std::string data;
	};

	VoiceChat();
	~VoiceChat() override;

	// Handshake. Returns the 32 byte public key to send to the server.
	std::string createHello();
	void onServerHello(bool enabled, const uint8_t *server_pub, float radius);
	// Server never answered (older server).
	void onHelloTimeout();

	// Decrypts and queues a voice frame of another player.
	void onVoicePacket(u16 speaker, const voicesession::Pos &pos, u32 ctr,
			const std::string &ct);

	// Main thread, once per frame: settings, microphone permission.
	void step(float dtime);

	void setPushToTalk(bool down) { m_ptt = down; }
	bool popOutgoing(OutPacket &out);
	// Message for the player, localized by the caller. Returns false if none.
	bool popStatus(std::string &msg);

	bool isActive() const { return m_active; }
	bool isTransmitting() const { return m_transmitting; }
	// The hello is sent a moment after joining (the server has to be ready for
	// it) and repeated a few times if nobody answers.
	bool isHelloPending() const { return m_hello_pending && m_start_delay <= 0.0f; }
	void markHelloSent() { m_hello_pending = false; m_hello_age = 0.0f; m_hello_tries++; }

protected:
	void *run() override;

private:
	enum Mode : int { MODE_OFF = 0, MODE_LISTEN = 1, MODE_PTT = 2, MODE_VAD = 3 };

	struct RxFrame
	{
		u16 speaker;
		v3f pos;
		u32 seq;
		std::array<s16, voicecodec::FRAME_SAMPLES> pcm;
	};

	void pushStatus(const std::string &msg);

	// --- main thread state
	uint8_t m_priv[32] = {};
	uint8_t m_pub[32] = {};
	bool m_have_keypair = false;
	uint8_t m_key_c2s[32] = {};
	uint8_t m_key_s2c[32] = {};
	voicecrypto::ReplayWindow m_rx_window;
	float m_settings_timer = 100.0f; // read settings immediately
	float m_perm_timer = 100.0f;
	bool m_perm_requested = false;
	float m_hello_age = 0.0f;
	float m_start_delay = 1.0f;
	int m_hello_tries = 0;
	bool m_hello_pending = true;
	bool m_hello_answered = false;

	// --- shared state
	std::atomic<bool> m_active{false}; // handshake done, voice chat in use
	std::atomic<bool> m_keys_ready{false};
	std::atomic<bool> m_ptt{false};
	std::atomic<bool> m_transmitting{false};
	std::atomic<bool> m_mic_permitted{false};
	std::atomic<int> m_mode{MODE_OFF};
	std::atomic<float> m_mic_gain{1.0f};
	std::atomic<float> m_vad_threshold{0.02f};
	std::atomic<float> m_volume{1.0f};
	std::atomic<float> m_radius{10.0f};

	std::mutex m_mutex; // protects the queues below
	std::deque<OutPacket> m_out_queue;
	std::deque<RxFrame> m_rx_queue;
	std::deque<std::string> m_status_queue;

#if USE_SOUND
	static constexpr int NUM_BUFFERS = 8;
	static constexpr int MAX_STREAMS = 16;

	struct Stream
	{
		ALuint source = 0;
		ALuint buffers[NUM_BUFFERS] = {};
		std::array<ALuint, NUM_BUFFERS> free_buffers = {};
		int free_count = 0;
		std::deque<std::array<s16, voicecodec::FRAME_SAMPLES>> pending;
		std::array<s16, voicecodec::FRAME_SAMPLES> last_frame = {};
		u32 last_seq = 0;
		bool have_seq = false;
		v3f pos;
		u64 last_rx_ms = 0;
		float lp1 = 0.0f, lp2 = 0.0f; // low-pass filter state
		float gain = 0.0f;
	};

	// --- voice thread only
	ALCdevice *m_capture = nullptr;
	u64 m_capture_retry_ms = 0;
	bool m_capture_failed_reported = false;
	std::deque<s16> m_capture_buf;
	std::array<std::array<s16, voicecodec::FRAME_SAMPLES>, 4> m_preroll = {};
	int m_preroll_count = 0;
	int m_hangover = 0;
	u32 m_tx_counter = 0;
	std::unordered_map<u16, Stream> m_streams;

	void updateCapture();
	void processCaptureFrame(s16 *frame);
	void sendFrame(const s16 *frame);
	void closeCapture();

	void handleRxFrame(const RxFrame &rx);
	bool createStream(Stream &st);
	void destroyStream(Stream &st);
	void updateStreams(u64 now_ms);
	void pushPending(Stream &st, const std::array<s16, voicecodec::FRAME_SAMPLES> &f);
#endif
};
