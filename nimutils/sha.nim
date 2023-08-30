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
proc SHA256_raw(s: cstring, count: csize_t, md_buf: cstring) {.cdecl, dynLib:DLLUtilName,importc: "SHA256".}
proc SHA512_raw(s: cstring, count: csize_t, md_buf: cstring) {.cdecl, dynLib:DLLUtilName,importc: "SHA512".}

type
  SHA256ctx = object
    evpCtx: EVP_MD_CTX
  SHA512ctx = object
    evpCtx: EVP_MD_CTX
  SHA3ctx = object
    evpCtx: EVP_MD_CTX
  SHA256Digest = array[32, uint8]
  SHA512Digest = array[64, uint8]
  SHA3Digest   = array[64, uint8]

proc `=destroy`*(ctx: SHA256ctx|SHA512Ctx|SHA3ctx) =
  EVP_MD_CTX_free(ctx.evpCtx)

proc initSHA*[T:SHA256ctx|SHA512ctx|SHA3ctx](ctx: var T) =
  ctx.evpCtx = EVP_MD_CTX_new()
  let md =
    when T is SHA256ctx:
      EVP_sha256()
    elif T is SHA512ctx:
      EVP_sha512()
    elif T is SHA3ctx:
      EVP_sha3_512()
  discard EVP_DigestInit_ex2(ctx.evpCtx, md, nil)

proc update*(ctx: var (SHA256ctx|SHA512ctx|SHA3ctx), data: openarray[char]) =
  if len(data) != 0:
    discard EVP_DigestUpdate(ctx.evpCtx, addr data[0], cuint(len(data)))

proc finalRaw*(ctx: var SHA256ctx): SHA256Digest =
  var i: cuint

  discard EVP_DigestFinal_ex(ctx.evpCtx, addr result[0], addr i)

proc finalRaw*(ctx: var SHA512ctx): SHA512Digest =
  var i: cuint

  discard EVP_DigestFinal_ex(ctx.evpCtx, addr result[0], addr i)

proc finalRaw*(ctx: var SHA3ctx): SHA3Digest =
  var i: cuint

  discard EVP_DigestFinal_ex(ctx.evpCtx, addr result[0], addr i)

proc final*(ctx: var SHA256ctx): string =
  tagToString(finalRaw(ctx))

proc final*(ctx: var SHA512ctx): string =
  tagToString(finalRaw(ctx))

proc final*(ctx: var SHA3ctx): string =
  tagToString(finalRaw(ctx))

template final_hex*[T](ctx: var T): string =
  final(ctx).toHex().toLowerAscii()

proc `$`*(tag: SHA256Digest|SHA512Digest|SHA3Digest): string =
  tagToString(tag)

proc SHA256*(s: string): string =
  var raw: SHA256Digest

  SHA256_raw(cstring(s), csize_t(s.len()), cast[cstring](addr raw))

  return tagToString(raw)

proc SHA512*(s: string): string =
  var raw: SHA512Digest

  SHA512_raw(cstring(s), csize_t(s.len()), cast[cstring](addr raw))

  return tagToString(raw)

proc SHA3*(s: string): string =
  var ctx: SHA3ctx

  initSHA[SHA3ctx](ctx)
  ctx.update(s)
  return ctx.final()

template SHA256_hex*(s: string): string =
  SHA256(s).toHex().toLowerAscii()

template SHA512_hex*(s: string): string =
  SHA512(s).toHex().toLowerAscii()

template SHA3_hex*(s: string): string =
  SHA3(s).toHex().toLowerAscii()

proc HMAC_sha256*(key: string, s: string): string =
  var
    tag: SHA256Digest
    i:   cuint
  discard HMAC(EVP_sha256(), addr key[0], cint(key.len()),
                     cstring(s), csize_t(s.len()), cast[cstring](addr tag),
                     addr i)
  result = tagToString(tag)

proc HMAC_sha512*(key: string, s: string): string =
  var
    tag: SHA512Digest
    i:   cuint
  discard HMAC(EVP_sha512(), addr key[0], cint(key.len()), cstring(s),
                csize_t(s.len()), cast[cstring](addr tag), addr i)
  result = tagToString(tag)

proc HMAC_sha3*(key: string, s: string): string =
  var
    tag: SHA3Digest
    i:   cuint
  discard HMAC(EVP_sha3_512(), addr key[0], cint(key.len()), cstring(s),
                csize_t(s.len()), cast[cstring](addr tag), addr i)

  result = tagToString(tag)

template HMAC_sha256_hex*(key: string, s: string): string =
  HMAC_sha256(key, s).toHex().toLowerAscii()

template HMAC_sha512_hex*(key: string, s: string): string =
  HMAC_sha512(key, s).toHex().toLowerAscii()

template HMAC_sha3_hex*(key: string, s: string): string =
  HMAC_sha3(key, s).toHex().toLowerAscii()

when isMainModule:
  import streams
  let text = newFileStream("logging.nim").readAll()
  var ctx: SHA256ctx

  initSHA[SHA256ctx](ctx)
  ctx.update(text)
  echo ctx.final().toHex().toLowerAscii()
  echo SHA256(text).toHex().toLowerAscii()
  echo HMAC_sha256("foo", "bar").toHex().toLowerAscii()
  echo HMAC_sha256_hex("foo", "bar")
