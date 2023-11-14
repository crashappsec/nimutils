## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022, 2023, Crash Override, Inc.

import std/sysrand, openssl, misc

# This used to be in here.
export bytesToString

template secureRand*[T](): T =
  ## Returns a uniformly distributed random value of any _sized_ type without
  ## pointers in it (you'll generate garbage otherwise).
  var randBytes: array[sizeof(T), byte]

  discard(urandom(randBytes))

  cast[T](randBytes)

proc randInt*(): int =
  ## Returns a uniformly distributed integer across 63 bits... meaning
  ## it is guaranteed to be positive.
  return secureRand[int] and (not (1 shl 63))

# I'm hitting what seems to be a nim 2.0 bug w/ urandom() to a
# dynamically alloc'd value.
# The openSSL PRNG is good for this case.

proc RAND_bytes(p: pointer, i: cint): cint {.cdecl, dynlib: DLLUtilName,
                                              importc.}

proc randString*(l: int): string =
  ## Get a random binary string of a particular length.
  var b = cast[pointer](alloc(l))

  discard RAND_bytes(b, cint(l))
  result = bytesToString(b, l)
  dealloc(b)
