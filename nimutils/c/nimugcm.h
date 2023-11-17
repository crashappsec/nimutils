#ifndef __NIMU_GCM_H__
#define __NIMU_GCM_H__

#include <limits.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#ifndef EVP_CTRL_GCM_GET_TAG
#define EVP_CIPHER_CTX void
#define EVP_CTRL_GCM_GET_TAG 0x10
#define EVP_CTRL_GCM_SET_TAG 0x11
#endif

typedef void *GCM128_CONTEXT;

extern int EVP_EncryptUpdate(void *ctx, unsigned char *out,
                             int *outl, const unsigned char *in, int inl);
extern int EVP_EncryptFinal(EVP_CIPHER_CTX *ctx, unsigned char *out,
                             int *outl);
extern int EVP_CIPHER_CTX_ctrl(EVP_CIPHER_CTX *ctx, int type, int arg,
                                   void *ptr);
extern int EVP_EncryptInit_ex2(EVP_CIPHER_CTX *ctx, const void *type,
                              const unsigned char *key, const unsigned char *iv,
                              void *params);
extern int EVP_CipherInit_ex2(EVP_CIPHER_CTX *ctx, const void *type,
                       const unsigned char *key, const unsigned char *iv,
                       int enc, void *params);
extern int EVP_DecryptUpdate(EVP_CIPHER_CTX *ctx, unsigned char *out,
                             int *outl, const unsigned char *in, int inl);
extern int EVP_DecryptFinal_ex(EVP_CIPHER_CTX *ctx, unsigned char *outm,
                               int *outl);
extern int EVP_DecryptInit_ex(EVP_CIPHER_CTX *ctx, void *type,
                              void *impl, const unsigned char *key,
                              const unsigned char *iv);

extern int bswap_64(int);

typedef struct gcm_ctx {
  EVP_CIPHER_CTX *aes_ctx;
  int            num_ops;
  char           *msg;
  int            mlen;
  char           *aad;
  int            alen;
  uint8_t        nonce[12];
} gcm_ctx_t;

typedef struct gcm_ctx_for_nonce_bump {
  EVP_CIPHER_CTX *aes_ctx;
  int            num_ops;
  char           *msg;
  int            mlen;
  char           *aad;
  int            alen;
  uint32_t       highnonce;
  uint64_t       lownonce;
} nonce_ctx_t;

#endif
