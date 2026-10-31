// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Small self-contained crypto toolbox for the voice chat:
//   * X25519 key agreement (RFC 7748)
//   * ChaCha20-Poly1305 AEAD (RFC 8439)
//   * a sliding replay window
// No dependencies besides the C++ standard library, so it can be unit-tested
// on its own. Random bytes and hashing are supplied by the caller.

#pragma once

#include <cstddef>
#include <cstdint>

namespace voicecrypto
{

constexpr size_t KEY_SIZE = 32;
constexpr size_t NONCE_SIZE = 12;
constexpr size_t TAG_SIZE = 16;

// Computes the public key for a (random) 32 byte private key.
void x25519Public(uint8_t pub[32], const uint8_t priv[32]);

// Computes the shared secret. Returns false if the peer key is invalid
// (low-order point, result is all zeros); `out` must then not be used.
[[nodiscard]] bool x25519Shared(uint8_t out[32], const uint8_t priv[32],
		const uint8_t peer_pub[32]);

// Encrypts `pt_len` bytes and writes `pt_len + TAG_SIZE` bytes to `out`.
void aeadSeal(const uint8_t key[32], const uint8_t nonce[12],
		const uint8_t *aad, size_t aad_len,
		const uint8_t *pt, size_t pt_len, uint8_t *out);

// `ct_len` includes the tag. Writes `ct_len - TAG_SIZE` bytes to `out`.
// Returns false (and writes nothing useful) if authentication fails.
[[nodiscard]] bool aeadOpen(const uint8_t key[32], const uint8_t nonce[12],
		const uint8_t *aad, size_t aad_len,
		const uint8_t *ct, size_t ct_len, uint8_t *out);

// Builds the 12 byte nonce for a 32 bit packet counter.
// (Every key is only used in one direction, so the counter alone is unique.)
void makeNonce(uint8_t nonce[12], uint32_t counter);

/*
	Replay protection for authenticated packets (window of 64).
	Usage: if (w.check(ctr)) { decrypt...; if (ok) w.commit(ctr); }
	Never commit before the packet authenticated, or forged counters could
	lock out the real sender.
*/
class ReplayWindow
{
public:
	bool check(uint32_t ctr) const
	{
		if (!m_any || ctr > m_max)
			return true;
		uint32_t diff = m_max - ctr;
		return diff < 64 && !((m_mask >> diff) & 1);
	}

	void commit(uint32_t ctr)
	{
		if (!m_any || ctr > m_max) {
			uint32_t shift = m_any ? ctr - m_max : 0;
			m_mask = (shift >= 64) ? 0 : (m_mask << shift);
			m_mask |= 1;
			m_max = ctr;
			m_any = true;
		} else {
			m_mask |= (uint64_t)1 << (m_max - ctr);
		}
	}

private:
	uint32_t m_max = 0;
	uint64_t m_mask = 0;
	bool m_any = false;
};

} // namespace voicecrypto
