## We're going to make a PRP using the Luby-Rackoff construction. The
## easiest thing for us to do is to break the input into two 'halves',
## one being 128 bits (the width of AES, which we will call the 'left
## half'), and the other the rest of the remaining width of the input
## (the 'right half').
##
## The nonce is better off random, and the nonce parameter is
## therefore set as part of the call to the encrypt function (not to
## the decrypt function). However, there's an optional flag if you
## want to use the passed nonce, in which case you may NOT consider
## the very first two bits of the input to be part of the nonce; we
## will throw an error if either of the bits are set.
##
## We first take the key passed in and, use it to generate pre-round keys.
##
## The pre-round keys work by running a PRF in counter mode, where the
## starting value of the counter is the nonce. We use this to get the
## actual round keys (the nonce is not necessary in the ruby-lackoff
## proof, but helps prevent dictionary attacks if they're viable in
## the threat model.
##
## Each round of luby-rackoff requires a PRF.
##
## One is AES-CTR mode. We key with the round key, and use the left
## half as the starting position of the counter. We use that to
## generate a key stream, that we XOR into the right half.
##
## The other PRF is HMAC-3. We take the round key, HMAC the right
## side, truncate the result to 128 bits, then XOR into the left half.
##
## The PRFs are used in a feistel cipher, so we alternate PRFs through
## our four feistel rounds.
##
## While three-round Luby-Rackoff is secure against some use cases, we
## go through the full four rounds.
##
## PRPs are reversable, and with feistel contstructions, it's by
## running the rounds backward. But instead of calling them 'encrypt'
## and 'decrypt', we use reversed (horizontally) and mirrored names...
## `brb` seems like a good function name for decryption.

import aes, sha, random


type PrpCtx = object
  contents: string
  round1, round2, round3, round4: string

proc initPrpContext(key, nonce, msg: string): PrpCtx =
  if key.len() notin [16, 24, 32]:
    raise newException(ValueError, "Invalid AES key size")

  if nonce.len() != 16:
    raise newException(ValueError, "Nonce must be 16 bytes.")

  let ks = aesPrfOneShot(key, 16*4, nonce)

  result = PrpCtx(
    contents: msg,
    round1: ks[0  ..< 16],
    round2: ks[16 ..< 32],
    round3: ks[32 ..< 48],
    round4: ks[48 ..< 64],
  )

proc xorInPlace(a: var string, b: string, n: int) =
  assert a.len >= n
  assert b.len >= n
  for i in 0 ..< n:
    a[i] = char(a[i].uint8 xor b[i].uint8)

proc runHmacPrf(ctx: var PrpCtx, key: string) =
  let toXor = key.hmacSha3(ctx.contents[16..^1])
  xorInPlace(ctx.contents, toXor, 16)

proc runCtrPrf(ctx: PrpCtx, key: string) =
  aesCtrInPlaceOneShot(key, addr ctx.contents[16], cint(len(ctx.contents) - 16))

proc round1(ctx: var PrpCtx) =
  ctx.runHmacPrf(ctx.round1)

proc round2(ctx: var PrpCtx) =
  ctx.runCtrPrf(ctx.round2)

proc round3(ctx: var PrpCtx) =
  ctx.runHmacPrf(ctx.round3)

proc round4(ctx: var PrpCtx) =
  ctx.runCtrPrf(ctx.round4)

proc prp*(key, toEncrypt: string, nonce: var string, randomNonce = true):
        string =
  ## Implements a 4-round Luby Rackoff PRP, which accepts inputs to
  ## permute of 24 bytes or more.
  ##
  ## As long as we do not duplicate messages, this function will allow
  ## us to do authenticated encryption without message expansion, with
  ## no issues with nonce reuse, or bit-flipping attacks.
  ##
  ## This function is intended more for encrypted storage, where it's
  ## a better option for most use cases than something based on
  ## GCM.
  ##
  ## The practical downsides are:
  ##
  ## 1. It doesn't support streaming, so the whole message needs to be
  ##    in memory.
  ## 2. It uses more crypto operations, and rekeys AES more.
  ## 3. The fact that we didn't bother tweak for small messages.

  if toEncrypt.len() < 24:
    raise newException(ValueError, "Minimum supported length for " &
      "messages encrypted with our PRP is 24 bytes")
  if randomNonce:
    nonce = randString(16)
  elif nonce.len() == 16:
    if (uint8(nonce[0]) and uint8(0xc0)) != 0:
      raise newException(ValueError, "User-supplied nonces must not have " &
        "the two upper bits set. If you want a random nonce (recommended) " &
        "then please pass in randomNonce = true")

  var ctx = key.initPrpContext(nonce, toEncrypt)
  ctx.round1()
  ctx.round2()
  ctx.round3()
  ctx.round4()

  return ctx.contents

proc brb*(key, toDecrypt: string, nonce: string): string =
  ## The reverse permutation for our 4-round Luby Rackoff PRP.

  if toDecrypt.len() < 24:
    raise newException(ValueError, "Minimum supported length for " &
      "messages encrypted with our PRP is 24 bytes")

  var ctx = key.initPrpContext(nonce, toDecrypt)
  ctx.round4()
  ctx.round3()
  ctx.round2()
  ctx.round1()

  return ctx.contents
