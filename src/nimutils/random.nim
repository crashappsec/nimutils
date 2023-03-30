import std/sysrand

template secureRand*[T](): T =
  ## Returns a uniformly distributed random value of any _sized_ type without
  ## pointers in it (you'll generate garbage otherwise).
  var randBytes: array[sizeof(T), byte]

  discard(urandom(randBytes))

  cast[T](randBytes)

proc randInt*(): int =
  return secureRand[int] and (not (1 shl 63))

when isMainModule:
    echo secureRand[uint64]()
    echo secureRand[int32]()
    echo secureRand[float]()
    echo secureRand[array[6, byte]]()
