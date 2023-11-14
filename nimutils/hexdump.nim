## :Author: John Viega (john@viega.org)
## Wrapping a C implementation I've done in the past.  Oddly, the main
## C function (now called chex) was always declared uint64_t, but the
## only way I could make Nim happy was if I changed them to `unsigned
## int`, which is okay on all the machines I care about anyway.

import strutils, os

static:
  {.compile: joinPath(splitPath(currentSourcePath()).head, "c/hex.c").}

proc hex*(s: string): string =
  ## Like toHex() in strutils, but uses lowercase letters, as nature
  ## intended.
  return s.toHex().toLowerAscii()

proc rawHexDump(x: pointer, sz: cuint, offset: uint64, width: cuint):
               cstring {.importc: "chex", cdecl.}

proc hexDump*(x: pointer, sz: uint, offset: int = -1, width = 0): string =
  ## Produce a nice hex dump that is sized properly for the terminal
  ## (or, alternately, sized to the width provided in the `width`
  ## parameter).
  ##
  ## - The first parameter should be a memory address, generally taken
  ##   with `addr somevar`
  ## - The second parameter is the number of bytes to dump.
  ## - The third parameter indicates the start value for the offset
  ##   printed. The default is to use the pointer value, but you
  ##   can start it anywhere.


  var
    realOffset = if offset < 0: cast[uint64](x) else: uint64(offset)
    tofree = rawHexDump(x, cuint(sz), realOffset, cuint(width))
  result = $(tofree)
  dealloc(tofree)

template strAddr*(s: string): pointer =
  ## Somewhere I wrote code that replicates the string's data structure,
  ## and does the needed casting to get to this value, but both have a
  ## potential race condition, so this is at least simple, though
  ## it's identical to arrAddr here.
  if s.len() == 0: nil else: addr s[0]

template listAddr*[T](x: openarray[T]): pointer =
  ## Return a pointer to an array or sequence, without crashing if the
  ## array is empty.
  if x.len() == 0: nil else: addr x[0]

proc strDump*(s: string): string =
  ## Produces a hex dump of the
  result = hexDump(listAddr(s), uint(len(s)))
