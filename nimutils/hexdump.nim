# Wrapping a C implementation I've done in the past.  Oddly, the main
# C function (now called chex) was always declared uint64_t, but the
# only way I could make Nim happy was if I changed them to `unsigned
# int`, which is okay on all the machines I care about anyway.
#
# :Author: John Viega (john@viega.org)

import strutils, os, system/nimscript

static:

  {.compile: joinPath(splitPath(currentSourcePath()).head, "c/hex.c").}

proc hex*(s: string): string =
  return s.toHex().toLowerAscii()

proc rawHexDump(x: pointer, sz: cuint, offset: cuint, width: cuint):
               cstring {.importc: "chex", cdecl.}

proc hexDump*(x: pointer, sz: uint, offset: uint = 0, width = 0): string =
  # Hex dump memory from the
  var tofree = rawHexDump(x, cuint(sz), cuint(offset), cuint(width))
  result = $(tofree)
  dealloc(tofree)

proc strDump*(s: string): string =
  result = hexDump(addr s[0], uint(len(s)))

when isMainModule:
  var
    buf: array[128, byte] = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
    21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,
    39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56,
    57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74,
    75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92,
    93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108,
    109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122,
    123, 124, 125, 126, 127 ]

  echo hexDump(addr buf[0], 128, width = 80)
