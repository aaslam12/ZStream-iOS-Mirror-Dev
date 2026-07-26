#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// SHA-256
void zs_sha256(const uint8_t* data, size_t len, uint8_t out[32]);

// HMAC-SHA-256
void zs_hmac_sha256(const uint8_t* key, size_t key_len,
                    const uint8_t* data, size_t data_len,
                    uint8_t out[32]);

// AES-256-GCM encrypt: out = iv(12) || ciphertext || tag(16)
// out_buf must be at least pt_len + 28 bytes
// aad/aad_len: additional authenticated data (may be null/0)
void zs_aes_gcm_encrypt(const uint8_t key[32], const uint8_t* pt, size_t pt_len,
                        const uint8_t* aad, size_t aad_len,
                        uint8_t* out, size_t* out_len);

// AES-256-GCM decrypt: returns false on authentication failure
// aad/aad_len must match what was passed to encrypt
bool zs_aes_gcm_decrypt(const uint8_t key[32], const uint8_t* in, size_t in_len,
                        const uint8_t* aad, size_t aad_len,
                        uint8_t* pt, size_t* pt_len);

// Cryptographically random bytes
void zs_rand_bytes(uint8_t* buf, size_t len);

#ifdef __cplusplus
}
#endif
