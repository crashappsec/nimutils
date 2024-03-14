import std/[openssl, options]
import "."/random

const badNonceError =  "GCM nonces should be exactly 12 bytes. If " &
                       "you want more, consider SHA256-hashing it, and " &
                       "using 12 bytes of the output."

{.emit: """
// This is just a lot easier to do in straight C.
// We assume we don't have full headers; nimugcm.h is a slimmed down version.
#include "nimugcm.h"

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

  GcmCtx* {.importc: "gcm_ctx_t", header: "nimugcm.h" .} = object
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
  ## This sets a key for an AES context.
  ctx.aesCtx = EVP_CIPHER_CTX_new()

  let cipher = getCipher("ECB", key)

  discard EVP_EncryptInit_ex(ctx.aesCtx, cipher, nil, cstring(key), nil)

proc aesPrp*(ctx: AesCtx, input: string): string =
  ## This is for using AES a a basic PRP (pseudo-random permutation).
  ## Only use this interface if you know what you're doing.
  var i: cint
  if len(input) != 16:
    raise newException(ValueError, "The AES PRP operates on 16 byte strings.")

  result = newStringOfCap(16)
  ctx.aesCtx.EVP_EncryptUpdate(addr result[0], addr i, cstring(input),
                               cint(16))

proc aesBrb*(ctx: AesCtx, input: string): string =
  ## This is for using AES a a basic PRP (pseudo-random permutation).
  ## Only use this interface if you know what you're doing.
  ##
  ## Specifically, this is the inverse of the primary permutation.
  var i: cint
  if len(input) != 16:
    raise newException(ValueError, "The AES BRB operates on 16 byte strings.")

  result = newStringOfCap(16)
  ctx.aesCtx.EVP_DecryptUpdate(addr result[0], addr i, cstring(input),
                               cint(16))

proc gcmInitEncrypt*(ctx: var GcmCtx, key: string, nonce = ""):
            string {.discardable} =
  ## Initialize authenticated encryption using AES-GCM. Nonces are
  ## (intentionally) constrained to always be 12 bytes, and if you do
  ## not pass in a nonce, you will get a random value.
  ##
  ## The nonce used is always returned.

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
  ## This runs AES as a pseudo-random function with a fixed-size (16
  ## byte) input yielding an output of the length specified (in
  ## bytes).
  ##
  ## The `start` parameter is essentially the nonce; do not reuse it.
  ##
  ## This is an `expert mode` interface.

  var
    ctx:    AesCtx
    nonce:  pointer = nil
    outbuf: pointer = alloc(outlen)

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
  ## This also is an `expert mode` interface, don't use counter mode
  ## unless you know exactly what you're doing. GCM mode is more
  ## appropriate.
  ##
  ## This runs counter mode, modifying a buffer in-place.
  ##
  ## The final parameter is a nonce.

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
  ## This also is an `expert mode` interface, don't use counter mode
  ## unless you know exactly what you're doing. GCM mode is more
  ## appropriate.
  ##
  ## This runs counter mode, modifying a buffer in-place.
  ##
  ## The final parameter is a nonce.
  aesCtrInPlaceOneshot(key, addr instr[0], cint(instr.len()), start)

proc gcmInitDecrypt*(ctx: var GcmCtx, key: string) =
  ## Initializes the decryption side of GCM.

  ctx.aesCtx = EVP_CIPHER_CTX_new()
  let cipher = getCipher("GCM", key)

  EVP_DecryptInit_ex2(ctx.aesCtx, cipher, cstring(key), nil, nil)

proc gcmEncrypt*(ctx: var GcmCtx, msg: string, aad = ""): string =
  ## GCM-encrypts a single message in a session, using the
  ## state setup by gcmEncryptInit()
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
  ## Runs the GMAC message authentication code algorithm on a single
  ## message, for a session set up via gcmInitEncrypt().  This is the
  ## same as passing a null message, but providing additional data to
  ## authenticate.
  ##
  ## The receiver should always use gcmDecrypt() to validate.
  return gcmEncrypt(ctx, msg = "", aad = msg)

proc gcmGetNonce*(ctx: var GcmCtx): string =
  ## Returns the sessions nonce.
  for i, ch in ctx.nonce:
    result.add(char(ctx.nonce[i]))

proc gmacGetNonce*(ctx: var GcmCtx): string =
  ## Returns the sessions nonce.
  return gcmGetNonce(ctx)

proc gcmDecrypt*(ctx: var GcmCtx, msg: string, nonce: string,
                    aad = ""): Option[string] =
  ## Performs validation and decryption of an encrypted message for a session
  ## initialized via `gcmInitDecrypt()`
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
