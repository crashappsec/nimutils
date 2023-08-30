#
#          Nim's Unofficial Library
#        (c) Copyright 2015 Huy Doan
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.
#

import strutils
import nimSHA2 except toHex

proc hash_sha224*(s: string): SHA224Digest {.procvar.} = computeSHA224(s)

proc hash_sha256*(s: string): SHA256Digest {.procvar.} = computeSHA256(s)

proc hash_sha384*(s: string): SHA384Digest {.procvar.} = computeSHA384(s)

proc hash_sha512*(s: string): SHA512Digest {.procvar.} = computeSHA512(s)

proc toHex*[T](x: T): string {.inline.} =
  result = toLowerAscii(nimSHA2.toHex(x))

template hmac_x[T](key, data: string, hash: proc(s: string): T, digest_size: int, block_size = 64, opad = 0x5c, ipad = 0x36) =
  var keyA: seq[uint8] = @[]
  var o_key_pad = newString(block_size + digest_size)
  var i_key_pad = newString(block_size)

  if key.len > block_size:
    for n in hash(key):
        keyA.add(n.uint8)
  else:
    for n in key:
       keyA.add(n.uint8)

  while keyA.len < block_size:
    keyA.add(0x00'u8)

  for i in 0..block_size-1:
    o_key_pad[i] = char(keyA[i].ord xor opad)
    i_key_pad[i] = char(keyA[i].ord xor ipad)
  var i = 0
  for x in hash(i_key_pad & data):
    o_key_pad[block_size + i] = char(x)
    inc(i)
  result = hash(o_key_pad)

proc hmac_sha224*(key, data: string, block_size = 64, opad = 0x5c, ipad = 0x36): Sha224Digest =
   hmac_x(key, data, hash_sha224, 32, block_size, opad, ipad)

proc hmac_sha256*(key, data: string, block_size = 64, opad = 0x5c, ipad = 0x36): SHA256Digest =
  hmac_x(key, data, hash_sha256, 32, block_size, opad, ipad)

proc hmac_sha384*(key, data: string, block_size = 64, opad = 0x5c, ipad = 0x36): SHA384Digest =
   hmac_x(key, data, hash_sha384, 64, block_size, opad, ipad)

proc hmac_sha512*(key, data: string, block_size = 128, opad = 0x5c, ipad = 0x36): SHA512Digest =
  hmac_x(key, data, hash_sha512, 64, block_size, opad, ipad)
