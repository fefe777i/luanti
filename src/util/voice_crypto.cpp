// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// X25519 follows the public domain TweetNaCl design (small, constant time
// field arithmetic), ChaCha20-Poly1305 follows RFC 8439.

#include "voice_crypto.h"

#include <cstring>
#include <vector>

namespace voicecrypto
{

/*
	X25519
*/

namespace
{

typedef int64_t i64;
typedef i64 gf[16];

const gf _121665 = {0xDB41, 1};

void car25519(gf o)
{
	for (int i = 0; i < 16; i++) {
		o[i] += (1LL << 16);
		i64 c = o[i] >> 16;
		o[(i + 1) * (i < 15)] += c - 1 + 37 * (c - 1) * (i == 15);
		o[i] -= c << 16;
	}
}

void sel25519(gf p, gf q, int b)
{
	i64 c = ~((i64)b - 1);
	for (int i = 0; i < 16; i++) {
		i64 t = c & (p[i] ^ q[i]);
		p[i] ^= t;
		q[i] ^= t;
	}
}

void pack25519(uint8_t *o, const gf n)
{
	gf m, t;
	for (int i = 0; i < 16; i++)
		t[i] = n[i];
	car25519(t);
	car25519(t);
	car25519(t);
	for (int j = 0; j < 2; j++) {
		m[0] = t[0] - 0xffed;
		for (int i = 1; i < 15; i++) {
			m[i] = t[i] - 0xffff - ((m[i - 1] >> 16) & 1);
			m[i - 1] &= 0xffff;
		}
		m[15] = t[15] - 0x7fff - ((m[14] >> 16) & 1);
		int b = (m[15] >> 16) & 1;
		m[14] &= 0xffff;
		sel25519(t, m, 1 - b);
	}
	for (int i = 0; i < 16; i++) {
		o[2 * i] = t[i] & 0xff;
		o[2 * i + 1] = t[i] >> 8;
	}
}

void unpack25519(gf o, const uint8_t *n)
{
	for (int i = 0; i < 16; i++)
		o[i] = n[2 * i] + ((i64)n[2 * i + 1] << 8);
	o[15] &= 0x7fff;
}

void fa(gf o, const gf a, const gf b)
{
	for (int i = 0; i < 16; i++)
		o[i] = a[i] + b[i];
}

void fz(gf o, const gf a, const gf b)
{
	for (int i = 0; i < 16; i++)
		o[i] = a[i] - b[i];
}

void fm(gf o, const gf a, const gf b)
{
	i64 t[31];
	for (int i = 0; i < 31; i++)
		t[i] = 0;
	for (int i = 0; i < 16; i++)
		for (int j = 0; j < 16; j++)
			t[i + j] += a[i] * b[j];
	for (int i = 0; i < 15; i++)
		t[i] += 38 * t[i + 16];
	for (int i = 0; i < 16; i++)
		o[i] = t[i];
	car25519(o);
	car25519(o);
}

void fs(gf o, const gf a)
{
	fm(o, a, a);
}

void inv25519(gf o, const gf i)
{
	gf c;
	for (int a = 0; a < 16; a++)
		c[a] = i[a];
	for (int a = 253; a >= 0; a--) {
		fs(c, c);
		if (a != 2 && a != 4)
			fm(c, c, i);
	}
	for (int a = 0; a < 16; a++)
		o[a] = c[a];
}

void scalarmult(uint8_t *q, const uint8_t *n, const uint8_t *p)
{
	uint8_t z[32];
	i64 x[80];
	gf a, b, c, d, e, f;

	for (int i = 0; i < 31; i++)
		z[i] = n[i];
	z[31] = (n[31] & 127) | 64;
	z[0] &= 248;

	unpack25519(x, p);
	for (int i = 0; i < 16; i++) {
		b[i] = x[i];
		d[i] = a[i] = c[i] = 0;
	}
	a[0] = d[0] = 1;

	for (int i = 254; i >= 0; --i) {
		int r = (z[i >> 3] >> (i & 7)) & 1;
		sel25519(a, b, r);
		sel25519(c, d, r);
		fa(e, a, c);
		fz(a, a, c);
		fa(c, b, d);
		fz(b, b, d);
		fs(d, e);
		fs(f, a);
		fm(a, c, a);
		fm(c, b, e);
		fa(e, a, c);
		fz(a, a, c);
		fs(b, a);
		fz(c, d, f);
		fm(a, c, _121665);
		fa(a, a, d);
		fm(c, c, a);
		fm(a, d, f);
		fm(d, b, x);
		fs(b, e);
		sel25519(a, b, r);
		sel25519(c, d, r);
	}
	for (int i = 0; i < 16; i++) {
		x[i + 16] = a[i];
		x[i + 32] = c[i];
		x[i + 48] = b[i];
		x[i + 64] = d[i];
	}
	inv25519(x + 32, x + 32);
	fm(x + 16, x + 16, x + 32);
	pack25519(q, x + 16);
}

} // namespace

void x25519Public(uint8_t pub[32], const uint8_t priv[32])
{
	uint8_t base[32] = {9};
	scalarmult(pub, priv, base);
}

bool x25519Shared(uint8_t out[32], const uint8_t priv[32], const uint8_t peer_pub[32])
{
	scalarmult(out, priv, peer_pub);
	uint8_t acc = 0;
	for (int i = 0; i < 32; i++)
		acc |= out[i];
	return acc != 0;
}

/*
	ChaCha20
*/

namespace
{

inline uint32_t rotl32(uint32_t v, int c)
{
	return (v << c) | (v >> (32 - c));
}

inline uint32_t load32(const uint8_t *p)
{
	return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
			((uint32_t)p[3] << 24);
}

inline void store32(uint8_t *p, uint32_t v)
{
	p[0] = v;
	p[1] = v >> 8;
	p[2] = v >> 16;
	p[3] = v >> 24;
}

inline void store64(uint8_t *p, uint64_t v)
{
	store32(p, (uint32_t)v);
	store32(p + 4, (uint32_t)(v >> 32));
}

#define QR(a, b, c, d) \
	a += b; d ^= a; d = rotl32(d, 16); \
	c += d; b ^= c; b = rotl32(b, 12); \
	a += b; d ^= a; d = rotl32(d, 8); \
	c += d; b ^= c; b = rotl32(b, 7);

void chachaBlock(const uint8_t key[32], uint32_t counter, const uint8_t nonce[12],
		uint8_t out[64])
{
	uint32_t s[16] = {
		0x61707865, 0x3320646e, 0x79622d32, 0x6b206574,
		load32(key), load32(key + 4), load32(key + 8), load32(key + 12),
		load32(key + 16), load32(key + 20), load32(key + 24), load32(key + 28),
		counter, load32(nonce), load32(nonce + 4), load32(nonce + 8)
	};
	uint32_t x[16];
	memcpy(x, s, sizeof(x));
	for (int i = 0; i < 10; i++) {
		QR(x[0], x[4], x[8], x[12]);
		QR(x[1], x[5], x[9], x[13]);
		QR(x[2], x[6], x[10], x[14]);
		QR(x[3], x[7], x[11], x[15]);
		QR(x[0], x[5], x[10], x[15]);
		QR(x[1], x[6], x[11], x[12]);
		QR(x[2], x[7], x[8], x[13]);
		QR(x[3], x[4], x[9], x[14]);
	}
	for (int i = 0; i < 16; i++)
		store32(out + 4 * i, x[i] + s[i]);
}

#undef QR

void chachaXor(const uint8_t key[32], uint32_t counter, const uint8_t nonce[12],
		const uint8_t *in, size_t len, uint8_t *out)
{
	uint8_t block[64];
	while (len > 0) {
		chachaBlock(key, counter++, nonce, block);
		size_t n = len < 64 ? len : 64;
		for (size_t i = 0; i < n; i++)
			out[i] = in[i] ^ block[i];
		in += n;
		out += n;
		len -= n;
	}
}

/*
	Poly1305 (17 limb schoolbook version, constant time)
*/

void add1305(uint32_t *h, const uint32_t *c)
{
	uint32_t u = 0;
	for (int j = 0; j < 17; j++) {
		u += h[j] + c[j];
		h[j] = u & 255;
		u >>= 8;
	}
}

void poly1305(uint8_t out[16], const uint8_t *m, size_t n, const uint8_t k[32])
{
	static const uint32_t minusp[17] = {5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 252};
	uint32_t s, u, x[17], r[17], h[17], c[17], g[17];

	for (int j = 0; j < 17; j++)
		r[j] = h[j] = 0;
	for (int j = 0; j < 16; j++)
		r[j] = k[j];
	r[3] &= 15;
	r[4] &= 252;
	r[7] &= 15;
	r[8] &= 252;
	r[11] &= 15;
	r[12] &= 252;
	r[15] &= 15;

	while (n > 0) {
		for (int j = 0; j < 17; j++)
			c[j] = 0;
		size_t j;
		for (j = 0; j < 16 && j < n; ++j)
			c[j] = m[j];
		c[j] = 1;
		m += j;
		n -= j;
		add1305(h, c);
		for (int i = 0; i < 17; i++) {
			x[i] = 0;
			for (int jj = 0; jj < 17; jj++)
				x[i] += h[jj] * ((jj <= i) ? r[i - jj] : 320 * r[i + 17 - jj]);
		}
		for (int i = 0; i < 17; i++)
			h[i] = x[i];
		u = 0;
		for (int jj = 0; jj < 16; jj++) {
			u += h[jj];
			h[jj] = u & 255;
			u >>= 8;
		}
		u += h[16];
		h[16] = u & 3;
		u = 5 * (u >> 2);
		for (int jj = 0; jj < 16; jj++) {
			u += h[jj];
			h[jj] = u & 255;
			u >>= 8;
		}
		u += h[16];
		h[16] = u;
	}

	for (int j = 0; j < 17; j++)
		g[j] = h[j];
	add1305(h, minusp);
	s = -(h[16] >> 7);
	for (int j = 0; j < 17; j++)
		h[j] ^= s & (g[j] ^ h[j]);
	for (int j = 0; j < 16; j++)
		c[j] = k[j + 16];
	c[16] = 0;
	add1305(h, c);
	for (int j = 0; j < 16; j++)
		out[j] = h[j];
}

// tag = Poly1305(otk, aad | pad | ct | pad | len(aad) | len(ct))
void aeadTag(const uint8_t otk[32], const uint8_t *aad, size_t aad_len,
		const uint8_t *ct, size_t ct_len, uint8_t tag[16])
{
	size_t aad_pad = (16 - aad_len % 16) % 16;
	size_t ct_pad = (16 - ct_len % 16) % 16;
	std::vector<uint8_t> buf(aad_len + aad_pad + ct_len + ct_pad + 16, 0);
	uint8_t *p = buf.data();
	if (aad_len)
		memcpy(p, aad, aad_len);
	p += aad_len + aad_pad;
	if (ct_len)
		memcpy(p, ct, ct_len);
	p += ct_len + ct_pad;
	store64(p, aad_len);
	store64(p + 8, ct_len);
	poly1305(tag, buf.data(), buf.size(), otk);
}

} // namespace

void aeadSeal(const uint8_t key[32], const uint8_t nonce[12],
		const uint8_t *aad, size_t aad_len,
		const uint8_t *pt, size_t pt_len, uint8_t *out)
{
	uint8_t block0[64];
	chachaBlock(key, 0, nonce, block0);
	chachaXor(key, 1, nonce, pt, pt_len, out);
	aeadTag(block0, aad, aad_len, out, pt_len, out + pt_len);
}

bool aeadOpen(const uint8_t key[32], const uint8_t nonce[12],
		const uint8_t *aad, size_t aad_len,
		const uint8_t *ct, size_t ct_len, uint8_t *out)
{
	if (ct_len < TAG_SIZE)
		return false;
	size_t pt_len = ct_len - TAG_SIZE;

	uint8_t block0[64];
	chachaBlock(key, 0, nonce, block0);
	uint8_t tag[16];
	aeadTag(block0, aad, aad_len, ct, pt_len, tag);

	uint8_t diff = 0;
	for (size_t i = 0; i < TAG_SIZE; i++)
		diff |= tag[i] ^ ct[pt_len + i];
	if (diff != 0)
		return false;

	chachaXor(key, 1, nonce, ct, pt_len, out);
	return true;
}

void makeNonce(uint8_t nonce[12], uint32_t counter)
{
	memset(nonce, 0, 12);
	store32(nonce + 8, counter);
}

} // namespace voicecrypto
