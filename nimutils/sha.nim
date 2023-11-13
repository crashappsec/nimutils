import openssl, strutils

{.pragma: lcrypto, cdecl, dynlib: DLLUtilName, importc.}

proc tagToString[T](input: T): string =
  result = newString(len(input))
  for i in 0 ..< len(input):
    result[i] = char(input[i])

proc EVP_MD_CTX_new(): EVP_MD_CTX {.lcrypto.}
proc EVP_MD_CTX_free(ctx: EVP_MD_CTX) {.lcrypto.}
proc EVP_DigestInit_ex2(ctx: EVP_MD_CTX, typ: EVP_MD, engine: SslPtr = nil):
                       cint {.lcrypto.}
proc EVP_sha3_512(): EVP_MD {.lcrypto.}
proc sha256_raw(s: cstring, count: csize_t, md_buf: cstring) {.cdecl, dynLib:DLLUtilName,importc: "SHA256".}
proc sha512_raw(s: cstring, count: csize_t, md_buf: cstring) {.cdecl, dynLib:DLLUtilName,importc: "SHA512".}

type
  Sha256ctx* = object
    evpCtx: EVP_MD_CTX
  Sha512ctx* = object
    evpCtx: EVP_MD_CTX
  Sha3ctx* = object
    evpCtx: EVP_MD_CTX
  Sha256Digest* = array[32, uint8]
  Sha512Digest* = array[64, uint8]
  Sha3Digest*   = array[64, uint8]

proc `=destroy`*(ctx: Sha256ctx) =
  EVP_MD_CTX_free(ctx.evpCtx)

proc `=destroy`*(ctx: Sha512ctx) =
  EVP_MD_CTX_free(ctx.evpCtx)

proc `=destroy`*(ctx: Sha3ctx) =
  EVP_MD_CTX_free(ctx.evpCtx)

proc initSha256*(ctx: var Sha256CTX) =
  ctx.evpCtx = EVP_MD_CTX_new()
  discard EVP_Digest_Init_ex2(ctx.evpCtx, EVP_sha256(), nil)

proc initSha512*(ctx: var Sha512CTX) =
  ctx.evpCtx = EVP_MD_CTX_new()
  discard EVP_Digest_Init_ex2(ctx.evpCtx, EVP_sha512(), nil)

proc initSha3*(ctx: var Sha3CTX) =
  ctx.evpCtx = EVP_MD_CTX_new()
  discard EVP_Digest_Init_ex2(ctx.evpCtx, EVP_sha3_512(), nil)

proc initSha256*(): Sha256Ctx =
  initSha256(result)

proc initSha512*(): Sha512Ctx =
  initSha512(result)

proc initSha3*(): Sha3Ctx =
  initSha3(result)

proc update*(ctx: var (Sha256ctx|Sha512ctx|Sha3ctx), data: openarray[char]) =
  if len(data) != 0:
    discard EVP_DigestUpdate(ctx.evpCtx, addr data[0], cuint(len(data)))

proc finalRaw(ctx: var Sha256ctx): Sha256Digest =
  var i: cuint

  discard EVP_DigestFinal_ex(ctx.evpCtx, addr result[0], addr i)

proc finalRaw(ctx: var Sha512ctx): Sha512Digest =
  var i: cuint

  discard EVP_DigestFinal_ex(ctx.evpCtx, addr result[0], addr i)

proc finalRaw(ctx: var Sha3ctx): Sha3Digest =
  var i: cuint

  discard EVP_DigestFinal_ex(ctx.evpCtx, addr result[0], addr i)

proc final*(ctx: var Sha256ctx): string =
  tagToString(finalRaw(ctx))

proc final*(ctx: var Sha512ctx): string =
  tagToString(finalRaw(ctx))

proc final*(ctx: var Sha3ctx): string =
  tagToString(finalRaw(ctx))

template finalHex*[T](ctx: var T): string =
  final(ctx).toHex().toLowerAscii()

proc `$`*(tag: Sha256Digest|Sha512Digest|Sha3Digest): string =
  tagToString(tag)

proc sha256*(s: string): string =
  var raw: Sha256Digest

  sha256_raw(cstring(s), csize_t(s.len()), cast[cstring](addr raw))

  return tagToString(raw)

proc sha512*(s: string): string =
  var raw: Sha512Digest

  sha512_raw(cstring(s), csize_t(s.len()), cast[cstring](addr raw))

  return tagToString(raw)

proc sha3*(s: string): string =
  var ctx: Sha3ctx

  initSha3(ctx)
  ctx.update(s)
  return ctx.final()

template sha256Hex*(s: string): string =
  sha256(s).toHex().toLowerAscii()

template sha512Hex*(s: string): string =
  sha512(s).toHex().toLowerAscii()

template sha3Hex*(s: string): string =
  sha3(s).toHex().toLowerAscii()

proc hmacSha256*(key: string, s: string): string =
  var
    tag: Sha256Digest
    i:   cuint
  discard HMAC(EVP_sha256(), addr key[0], cint(key.len()),
               cstring(s), csize_t(s.len()), cast[cstring](addr tag),
               addr i)
  result = tagToString(tag)

proc hmacSha512*(key: string, s: string): string =
  var
    tag: Sha512Digest
    i:   cuint
  discard HMAC(EVP_sha512(), addr key[0], cint(key.len()), cstring(s),
                csize_t(s.len()), cast[cstring](addr tag), addr i)
  result = tagToString(tag)

proc hmacSha3*(key: string, s: string): string =
  var
    tag: Sha3Digest
    i:   cuint
  discard HMAC(EVP_sha3_512(), addr key[0], cint(key.len()), cstring(s),
                csize_t(s.len()), cast[cstring](addr tag), addr i)

  result = tagToString(tag)

template hmacSha256Hex*(key: string, s: string): string =
  hmacSha256(key, s).toHex().toLowerAscii()

template hmacSha512Hex*(key: string, s: string): string =
  hmacSha512(key, s).toHex().toLowerAscii()

template hmacSha3Hex*(key: string, s: string): string =
  hmacSha3(key, s).toHex().toLowerAscii()
