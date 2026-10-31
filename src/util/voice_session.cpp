// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "voice_session.h"

#include "util/hashing.h"

#include <cstring>

namespace voicesession
{

namespace
{

void deriveOne(uint8_t out[32], const char *label, const uint8_t shared[32],
		const uint8_t client_pub[32], const uint8_t server_pub[32])
{
	std::string input = label;
	input.append((const char *)shared, 32);
	input.append((const char *)client_pub, 32);
	input.append((const char *)server_pub, 32);
	std::string digest = hashing::sha256(input);
	memcpy(out, digest.data(), 32);
}

size_t buildDownlinkAad(uint8_t aad[19], uint16_t speaker, const Pos &pos, uint32_t ctr)
{
	size_t n = 0;
	aad[n++] = 2; // direction label
	aad[n++] = speaker & 0xff;
	aad[n++] = speaker >> 8;
	for (int32_t v : {pos.x, pos.y, pos.z}) {
		uint32_t u = (uint32_t)v;
		aad[n++] = u;
		aad[n++] = u >> 8;
		aad[n++] = u >> 16;
		aad[n++] = u >> 24;
	}
	aad[n++] = ctr;
	aad[n++] = ctr >> 8;
	aad[n++] = ctr >> 16;
	aad[n++] = ctr >> 24;
	return n; // 19
}

} // namespace

Keys deriveKeys(const uint8_t shared[32], const uint8_t client_pub[32],
		const uint8_t server_pub[32])
{
	Keys k;
	deriveOne(k.c2s, "luanti-voice-v1 c2s", shared, client_pub, server_pub);
	deriveOne(k.s2c, "luanti-voice-v1 s2c", shared, client_pub, server_pub);
	return k;
}

std::string sealUplink(const uint8_t key[32], uint32_t ctr,
		const uint8_t *frame, size_t frame_len)
{
	uint8_t nonce[voicecrypto::NONCE_SIZE];
	voicecrypto::makeNonce(nonce, ctr);
	const uint8_t aad[1] = {1};
	std::string out(frame_len + voicecrypto::TAG_SIZE, '\0');
	voicecrypto::aeadSeal(key, nonce, aad, sizeof(aad), frame, frame_len,
			(uint8_t *)out.data());
	return out;
}

bool openUplink(const uint8_t key[32], uint32_t ctr, const std::string &ct, uint8_t *out)
{
	if (ct.size() != UPLINK_PLAIN_SIZE + voicecrypto::TAG_SIZE)
		return false;
	uint8_t nonce[voicecrypto::NONCE_SIZE];
	voicecrypto::makeNonce(nonce, ctr);
	const uint8_t aad[1] = {1};
	return voicecrypto::aeadOpen(key, nonce, aad, sizeof(aad),
			(const uint8_t *)ct.data(), ct.size(), out);
}

std::string sealDownlink(const uint8_t key[32], uint16_t speaker, const Pos &pos,
		uint32_t ctr, const uint8_t *plain, size_t plain_len)
{
	uint8_t nonce[voicecrypto::NONCE_SIZE];
	voicecrypto::makeNonce(nonce, ctr);
	uint8_t aad[19];
	size_t aad_len = buildDownlinkAad(aad, speaker, pos, ctr);
	std::string out(plain_len + voicecrypto::TAG_SIZE, '\0');
	voicecrypto::aeadSeal(key, nonce, aad, aad_len, plain, plain_len,
			(uint8_t *)out.data());
	return out;
}

bool openDownlink(const uint8_t key[32], uint16_t speaker, const Pos &pos,
		uint32_t ctr, const std::string &ct, uint8_t *out)
{
	if (ct.size() != DOWNLINK_PLAIN_SIZE + voicecrypto::TAG_SIZE)
		return false;
	uint8_t nonce[voicecrypto::NONCE_SIZE];
	voicecrypto::makeNonce(nonce, ctr);
	uint8_t aad[19];
	size_t aad_len = buildDownlinkAad(aad, speaker, pos, ctr);
	return voicecrypto::aeadOpen(key, nonce, aad, aad_len,
			(const uint8_t *)ct.data(), ct.size(), out);
}

} // namespace voicesession
