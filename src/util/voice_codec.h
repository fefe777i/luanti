// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Voice codec: IMA ADPCM, 16 kHz mono, 20 ms frames.
// Every frame carries its own predictor/step index, so a lost packet never
// corrupts the following ones. 164 bytes per frame (about 6.5 KB/s).

#pragma once

#include <cstddef>
#include <cstdint>

namespace voicecodec
{

constexpr int SAMPLE_RATE = 16000;
constexpr int FRAME_MS = 20;
constexpr int FRAME_SAMPLES = SAMPLE_RATE * FRAME_MS / 1000; // 320
// 4 byte header + one nibble for each of the remaining FRAME_SAMPLES - 1 samples
constexpr size_t ENCODED_SIZE = 4 + FRAME_SAMPLES / 2; // 164

// Encodes FRAME_SAMPLES samples into ENCODED_SIZE bytes.
void encodeFrame(const int16_t *pcm, uint8_t *out);

// Decodes one frame. Returns false if the data is malformed.
[[nodiscard]] bool decodeFrame(const uint8_t *in, size_t len, int16_t *pcm);

} // namespace voicecodec
