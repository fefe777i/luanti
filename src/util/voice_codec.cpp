// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "voice_codec.h"

#include <algorithm>
#include <cstdlib>

namespace voicecodec
{

namespace
{

const int8_t index_table[16] = {
	-1, -1, -1, -1, 2, 4, 6, 8,
	-1, -1, -1, -1, 2, 4, 6, 8
};

const int16_t step_table[89] = {
	7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
	50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230,
	253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963,
	1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327,
	3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442,
	11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794,
	32767
};

struct State
{
	int predictor;
	int index;
};

inline uint8_t encodeSample(State &st, int sample)
{
	int step = step_table[st.index];
	int diff = sample - st.predictor;
	uint8_t code = 0;
	if (diff < 0) {
		code = 8;
		diff = -diff;
	}
	int vpdiff = step >> 3;
	if (diff >= step) {
		code |= 4;
		diff -= step;
		vpdiff += step;
	}
	step >>= 1;
	if (diff >= step) {
		code |= 2;
		diff -= step;
		vpdiff += step;
	}
	step >>= 1;
	if (diff >= step) {
		code |= 1;
		vpdiff += step;
	}
	st.predictor += (code & 8) ? -vpdiff : vpdiff;
	st.predictor = std::clamp(st.predictor, -32768, 32767);
	st.index = std::clamp(st.index + index_table[code], 0, 88);
	return code;
}

inline int decodeSample(State &st, uint8_t code)
{
	int step = step_table[st.index];
	int vpdiff = step >> 3;
	if (code & 4)
		vpdiff += step;
	if (code & 2)
		vpdiff += step >> 1;
	if (code & 1)
		vpdiff += step >> 2;
	st.predictor += (code & 8) ? -vpdiff : vpdiff;
	st.predictor = std::clamp(st.predictor, -32768, 32767);
	st.index = std::clamp(st.index + index_table[code], 0, 88);
	return st.predictor;
}

} // namespace

void encodeFrame(const int16_t *pcm, uint8_t *out)
{
	// Pick the starting step index from how loud the frame is so the first
	// samples are not coded with a badly adapted step size.
	int peak = 0;
	for (int i = 1; i < FRAME_SAMPLES; i++)
		peak = std::max(peak, std::abs((int)pcm[i] - (int)pcm[i - 1]));
	State st;
	st.predictor = pcm[0];
	st.index = 0;
	while (st.index < 88 && step_table[st.index] * 2 < peak)
		st.index++;

	out[0] = (uint8_t)(pcm[0] & 0xff);
	out[1] = (uint8_t)((pcm[0] >> 8) & 0xff);
	out[2] = (uint8_t)st.index;
	out[3] = 0;

	uint8_t *dst = out + 4;
	for (int i = 1; i < FRAME_SAMPLES; i += 2) {
		uint8_t lo = encodeSample(st, pcm[i]);
		uint8_t hi = (i + 1 < FRAME_SAMPLES) ? encodeSample(st, pcm[i + 1]) : 0;
		*dst++ = lo | (hi << 4);
	}
}

bool decodeFrame(const uint8_t *in, size_t len, int16_t *pcm)
{
	if (len != ENCODED_SIZE)
		return false;
	State st;
	st.predictor = (int16_t)(in[0] | (in[1] << 8));
	st.index = in[2];
	if (st.index > 88)
		return false;

	pcm[0] = (int16_t)st.predictor;
	const uint8_t *src = in + 4;
	for (int i = 1; i < FRAME_SAMPLES; i += 2) {
		uint8_t b = *src++;
		pcm[i] = (int16_t)decodeSample(st, b & 15);
		if (i + 1 < FRAME_SAMPLES)
			pcm[i + 1] = (int16_t)decodeSample(st, b >> 4);
	}
	return true;
}

} // namespace voicecodec
