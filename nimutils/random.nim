## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022, 2023, Crash Override, Inc.

import std/sysrand, openssl

template secureRand*[T](): T =
  ## Returns a uniformly distributed random value of any _sized_ type without
  ## pointers in it (you'll generate garbage otherwise).
  var randBytes: array[sizeof(T), byte]

  discard(urandom(randBytes))

  cast[T](randBytes)

proc randInt*(): int =
  return secureRand[int] and (not (1 shl 63))

# I'm hitting what seems to be a nim 2.0 bug w/ urandom() to a
# dynamically alloc'd value.
# The openSSL PRNG is good for this case.

proc RAND_bytes(p: pointer, i: cint): cint {.cdecl, dynlib: DLLUtilName,
                                              importc.}

proc bytesToString*(b: ptr UncheckedArray[char], l: int): string =
  for i in 0 ..< l:
    result.add(b[i])

template bytesToString*(b: ptr char, l: int): string =
  bytesToString(cast[ptr UncheckedArray[char]](b), l)

proc randString*(l: int): string =
  ## Get a random binary string of a particular length.
  var b = cast[ptr char](alloc(l))

  discard RAND_bytes(b, cint(l))
  result = bytesToString(cast[ptr UncheckedArray[char]](b), l)
  dealloc(b)
