import random, openssl, options

const badNonceError =  "GCM nonces should be exactly 12 bytes. If " &
                       "you want more, consider SHA256-hashing it, and " &
                       "using 12 bytes of the output."

{.emit: """
// This is just a lot easier to do in straight C.
// We're going to assume headers aren't available and declare what we use.

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

extern char *
chex(void *ptr, unsigned int len, unsigned int start_offset,
     unsigned int width);

static void bump_nonce(nonce_ctx_t *ctx) {
  #if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
      ctx->lownonce++;
  #else
      ctx->lownonce = bswap_64(bswap_64(ctx->lownonce) + 1);
  #endif
}

N_CDECL(int, do_gcm_encrypt)(gcm_ctx_t *ctx, void *tocast) {
  char tag[16];
  char *outbuf = (char *)tocast;
  char *p      = outbuf + ctx->mlen;
  int outlen;

  if (ctx->num_ops) {
    bump_nonce((nonce_ctx_t *)ctx);
    if (!EVP_CipherInit_ex2(ctx->aes_ctx, NULL, NULL, ctx->nonce, 1, NULL)) {
      return 0;
    }
  }
  if (++ctx->num_ops >= (1 << 20)) {
    return 0;
  }
  if (ctx->alen > 0) {
    if (!EVP_EncryptUpdate(ctx->aes_ctx, NULL, &outlen, ctx->aad, ctx->alen)) {
      return 0;
    }
  }
  if (!EVP_EncryptUpdate(ctx->aes_ctx, outbuf, &outlen, ctx->msg, ctx->mlen)) {
    return 0;
  }
  if (!EVP_EncryptFinal(ctx->aes_ctx, outbuf + ctx->mlen, &outlen)) {
    return 0;
  }
  if (EVP_CIPHER_CTX_ctrl(ctx->aes_ctx, EVP_CTRL_GCM_GET_TAG, 16, p) != 1) {
    return 0;
  }

  return 1;
}

N_CDECL(int, get_keystream)(void *ctx, void *outbuf, int len) {
  char *to_encrypt = calloc(len, 1);
  int   outlen;

  return EVP_EncryptUpdate((EVP_CIPHER_CTX *)ctx, (char *)outbuf, &outlen,
                           to_encrypt, len);

  free(to_encrypt);
}

N_CDECL(int, run_ctr_mode)(void *ctx, void *outbuf, void *to_encrypt, int len) {
  int   outlen;

  return EVP_EncryptUpdate((EVP_CIPHER_CTX *)ctx, (char *)outbuf, &outlen,
                           (char *)to_encrypt, len);

  free(to_encrypt);
}

extern int EVP_EncryptUpdate(EVP_CIPHER_CTX *ctx, unsigned char *out,
                             int *outl, const unsigned char *in, int inl);


N_CDECL(int, do_gcm_decrypt)(gcm_ctx_t *ctx, void *tocast) {
  int outlen;
  int inlen    = (ctx->mlen - 16);
  char *outbuf = (char *)tocast;
  char *tag    = ctx->msg + inlen;

  ctx->num_ops++;

  if (!EVP_CipherInit_ex2(ctx->aes_ctx, NULL, NULL, ctx->nonce, 0, NULL)) {
    return 0;
  }

  if (ctx->alen > 0) {
    if (!EVP_DecryptUpdate(ctx->aes_ctx, NULL, &outlen, ctx->aad, ctx->alen)) {
      return 0;
    }
  }
  if (!EVP_DecryptUpdate(ctx->aes_ctx, outbuf, &outlen, ctx->msg, inlen)) {
    return 0;
  }

  if (!EVP_CIPHER_CTX_ctrl(ctx->aes_ctx, EVP_CTRL_GCM_SET_TAG, 16, tag)) {
    goto err;
  }

  int ret = EVP_DecryptFinal_ex(ctx->aes_ctx, outbuf + outlen, &outlen);

  if (ret <= 0) {
    goto err;
  }

  return 1;

  err:
    memset(outbuf, 0, ctx->mlen);
    return 0;
}


""".}

{.pragma: lcrypto, cdecl, dynlib: DLLUtilName, importc.}

type
  CipherStruct {.final,pure.} = object
  CipherPtr*      = ptr CipherStruct
  EVP_CIPHER_CTX* = ptr CipherStruct
  EVP_CIPHER*     = CipherPtr


proc EVP_CIPHER_CTX_new(): EVP_CIPHER_CTX {.lcrypto.}
proc EVP_CIPHER_CTX_free(ctx: EVP_CIPHER_CTX) {.lcrypto.}
proc EVP_CIPHER_fetch(unused: CipherPtr, name: cstring, unusedToo: CipherPtr):
                     EVP_CIPHER {.lcrypto.}
proc EVP_EncryptInit_ex(ctx: EVP_CIPHER_CTX, cipher: EVP_CIPHER,
                        engine: pointer, key: cstring, nonce: pointer):
                           cint {.lcrypto,discardable.}
proc EVP_DecryptInit_ex2(ctx: EVP_CIPHER_CTX, cipher: EVP_CIPHER,
                         key: cstring, nonce: pointer, params: pointer):
                       cint {.lcrypto,discardable.}
proc EVP_EncryptUpdate(ctx: EVP_CIPHER_CTX, outbuf: pointer, outlen: ptr cint,
                       inbuf: cstring, inlen: cint): cint
                        {.lcrypto,discardable,nodecl.}
proc EVP_DecryptUpdate(ctx: EVP_CIPHER_CTX, outbuf: pointer, outlen: ptr cint,
                       inbuf: cstring, inlen: cint): cint
                        {.lcrypto,discardable,nodecl.}
type
  AesCtx* = object
    aesCtx: EVP_CIPHER_CTX

  GcmCtx* {.importc: "gcm_ctx_t".} = object
    aes_ctx:  EVP_CIPHER_CTX
    num_ops:  cint
    msg:      cstring
    mlen:     cint
    aad:      cstring
    alen:     cint
    nonce*:  array[12, uint8]

proc do_gcm_encrypt(ctx: ptr GcmCtx, outbuf: pointer): cint {.cdecl,importc.}
proc do_gcm_decrypt(ctx: ptr GcmCtx, outbuf: pointer): cint {.cdecl,importc.}
proc get_keystream(ctx: pointer, outbuf: pointer, buflen: cint):
                       cint {.cdecl,importc.}
proc run_ctr_mode(ctx, outbuf, inbuf: pointer, buflen: cint):
                       cint {.cdecl,importc.}

proc `=destroy`*(ctx: AesCtx) =
    EVP_CIPHER_CTX_free(ctx.aesCtx)

proc `=destroy`*(ctx: GcmCtx) =
    EVP_CIPHER_CTX_free(ctx.aesCtx)

template getCipher(mode: string, key: string): EVP_CIPHER =
  case len(key)
  of 16:
    EVP_CIPHER_fetch(nil, "AES-128-" & mode, nil)
  of 24:
    EVP_CIPHER_fetch(nil, "AES-192-" & mode, nil)
  of 32:
    EVP_CIPHER_fetch(nil, "AES-256" & mode, nil)
  else:
    raise newException(ValueError, "AES keys must be 16, 24 or 32 bytes.")

proc initAesPRP*(ctx: var AesCtx, key: string) =
  ctx.aesCtx = EVP_CIPHER_CTX_new()

  let cipher = getCipher("ECB", key)

  discard EVP_EncryptInit_ex(ctx.aesCtx, cipher, nil, cstring(key), nil)

proc aesPrp*(ctx: AesCtx, input: string): string =
  var i: cint
  if len(input) != 16:
    raise newException(ValueError, "The AES PRP operates on 16 byte strings.")

  result = newStringOfCap(16)
  ctx.aesCtx.EVP_EncryptUpdate(addr result[0], addr i, cstring(input),
                               cint(16))

proc aesBrb*(ctx: AesCtx, input: string): string =
  var i: cint
  if len(input) != 16:
    raise newException(ValueError, "The AES BRB operates on 16 byte strings.")

  result = newStringOfCap(16)
  ctx.aesCtx.EVP_DecryptUpdate(addr result[0], addr i, cstring(input),
                               cint(16))

proc gcmInitEncrypt*(ctx: var GcmCtx, key: string, nonce = ""):
            string {.discardable} =

  ctx.aesCtx = EVP_CIPHER_CTX_new()
  let cipher = getCipher("GCM", key)
  result     = nonce

  if result == "":
    result = randString(12)
  elif len(nonce) != 12:
    raise newException(ValueError, badNonceError)

  for i, ch in result:
    ctx.nonce[i] = uint8(ch)

  discard EVP_EncryptInit_ex(ctx.aesCtx, cipher, nil, cstring(key),
                              addr ctx.nonce[0])
proc gmacInit*(ctx: var GcmCtx, key: string, nonce = ""):
             string {.discardable} =

  return gcmInitEncrypt(ctx, key, nonce)

proc aesPrfOneShot*(key: string, outlen: int, start: string = ""): string =
  var
    ctx:    AesCtx
    nonce:  pointer = nil
    outbuf: ptr char = cast[ptr char](alloc(outlen))

  ctx.aesCtx = EVP_CIPHER_CTX_new()

  if start != "":
    if len(start) != 16:
      raise newException(ValueError, "Starting value must be 16 bytes.")
    nonce = addr start[0]

  let cipher = getCipher("CTR", key)

  discard EVP_Encrypt_Init_ex(ctx.aesCtx, cipher, nil, cstring(key), nonce)

  if ctx.aesCtx.get_keystream(outbuf, cint(outlen)) == 0:
    raise newException(IoError, "Could not generate keystream")

  result = bytesToString(outbuf, outlen)
  dealloc(outbuf)

proc aesCtrInPlaceOneshot*(key: string, instr: pointer, l: cint,
                           start: string = "") =
  var
    ctx:    AesCtx
    nonce:  pointer = nil

  ctx.aesCtx = EVP_CIPHER_CTX_new()

  if start != "":
    if len(start) != 16:
      raise newException(ValueError, "Starting value must be 16 bytes.")
    nonce = addr start[0]

  let cipher = getCipher("CTR", key)

  discard EVP_Encrypt_Init_ex(ctx.aesCtx, cipher, nil, cstring(key), nonce)

  if ctx.aesCtx.run_ctr_mode(instr, instr, l) == 0:
    raise newException(IoError, "Could not generate keystream")

proc aesCtrInPlaceOneshot*(key, instr: string, start: string = "") =
  aesCtrInPlaceOneshot(key, addr instr[0], cint(instr.len()), start)

proc gcmInitDecrypt*(ctx: var GcmCtx, key: string) =

  ctx.aesCtx = EVP_CIPHER_CTX_new()
  let cipher = getCipher("GCM", key)

  EVP_DecryptInit_ex2(ctx.aesCtx, cipher, cstring(key), nil, nil)

proc gcmEncrypt*(ctx: var GcmCtx, msg: string, aad = ""): string =
  var outbuf: ptr char = cast[ptr char](alloc(len(msg) + 16))

  ctx.aad  = cstring(aad)
  ctx.msg  = cstring(msg)
  ctx.mlen = cint(msg.len())
  ctx.alen = cint(aad.len())

  if doGcmEncrypt(addr ctx, outbuf) == 0:
    raise newException(IoError, "Encryption failed.")

  result = bytesToString(outbuf, len(msg) + 16)
  dealloc(outbuf)

proc gmac*(ctx: var GcmCtx, msg: string): string =
  return gcmEncrypt(ctx, msg = "", aad = msg)

proc gcmGetNonce*(ctx: var GcmCtx): string =
  for i, ch in ctx.nonce:
    result.add(char(ctx.nonce[i]))

proc gmacGetNonce*(ctx: var GcmCtx): string =
  return gcmGetNonce(ctx)

proc gcmDecrypt*(ctx: var GcmCtx, msg: string, nonce: string,
                    aad = ""): Option[string] =
  if len(msg) < 16:
    raise newException(ValueError, "Invalid GCM Ciphertext (too short)")

  if len(nonce) != 12:
    raise newException(ValueError, badNonceError)

  var outbuf: ptr char = cast[ptr char](alloc(len(msg) - 16))

  ctx.aad  = cstring(aad)
  ctx.msg  = cstring(msg)
  ctx.mlen = cint(msg.len())
  ctx.alen = cint(aad.len())

  for i, ch in nonce:
    ctx.nonce[i] = uint8(ch)

  if doGcmDecrypt(addr ctx, outbuf) == 0:
    dealloc(outbuf)
    return none(string)

  result = some(bytesToString(outbuf, len(msg) - 16))
  dealloc(outbuf)

when isMainModule:
  import strutils, hexdump

  var
    encCtx: GcmCtx
    decCtx: GcmCtx
    nonce:  string
    ct:     string
    pt    = "This is a test between disco and death"
    key   = "0123456789abcdef"
  gcmInitEncrypt(encCtx, key)
  gcmInitDecrypt(decCtx, key)

  echo "Initial pt: ", pt

  for i in 1 .. 3:
    ct    = encCtx.gcmEncrypt(pt)
    nonce = encCtx.gcmGetNonce()
    pt    = decCtx.gcmDecrypt(ct, nonce).get("<error>")

    echo "Nonce: ", nonce.toHex().toLowerAscii()
    echo "CT: "
    echo strDump(ct)
    echo "Decrypted: ", pt

  echo "Keystream test: "

  let
    stream1 = aesPrfOneShot(key, 200)
    stream2 = aesPrfOneShot(key, 200)

  echo stream1.toHex()
  assert len(stream1) == 200
  assert stream1 == stream2

  let text = "This is a test, yo, dawg"

  aesCtrInPlaceOneshot(key, text)

  echo "Covered dog: ", text.hex()

  aesCtrInPlaceOneshot(key, text)

  echo text
