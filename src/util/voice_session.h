// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Glue shared by the voice chat client and server: key schedule and the
// authenticated packet formats.
//
// Handshake (both messages are sent over the normal game connection):
//   client -> server  TOSERVER_VOICE_HELLO   client public key (X25519)
//   server -> client  TOCLIENT_VOICE_HELLO   server public key + settings
// Both sides derive two keys from the shared secret, one per direction.
// The server relays voice, so it decrypts a speaker's frame and seals it
// again for every listener with that listener's own key.

#pragma once

#include "util/voice_codec.h"
#include "util/voice_crypto.h"

#include <cstdint>
#include <string>

namespace voicesession
{

constexpr uint8_t PROTOCOL_VERSION = 1;

// Maximum number of encrypted frames a client may send per second
// (normal speech is 50).
constexpr int MAX_FRAMES_PER_SECOND = 120;

// Plaintext of an uplink packet is exactly one codec frame.
constexpr size_t UPLINK_PLAIN_SIZE = voicecodec::ENCODED_SIZE;
// Plaintext of a downlink packet is the speaker's sequence number + one frame.
constexpr size_t DOWNLINK_PLAIN_SIZE = 4 + voicecodec::ENCODED_SIZE;

struct Keys
{
	uint8_t c2s[32]; // client -> server
	uint8_t s2c[32]; // server -> client
};

Keys deriveKeys(const uint8_t shared[32], const uint8_t client_pub[32],
		const uint8_t server_pub[32]);

// Position of the speaker in hundredths of a node.
struct Pos
{
	int32_t x, y, z;
};

// Returns ciphertext + tag.
std::string sealUplink(const uint8_t key[32], uint32_t ctr,
		const uint8_t *frame, size_t frame_len);
// `out` receives UPLINK_PLAIN_SIZE bytes. Does not touch the replay window.
[[nodiscard]] bool openUplink(const uint8_t key[32], uint32_t ctr,
		const std::string &ct, uint8_t *out);

// plain = DOWNLINK_PLAIN_SIZE bytes: u32 LE speaker sequence + frame
std::string sealDownlink(const uint8_t key[32], uint16_t speaker, const Pos &pos,
		uint32_t ctr, const uint8_t *plain, size_t plain_len);
[[nodiscard]] bool openDownlink(const uint8_t key[32], uint16_t speaker,
		const Pos &pos, uint32_t ctr, const std::string &ct, uint8_t *out);

} // namespace voicesession
