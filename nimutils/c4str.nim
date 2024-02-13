import os, posix

static:
  {.compile: joinPath(splitPath(currentSourcePath()).head, "c/strcontainer.c").}

type C4Str* = pointer

proc newC4Str*(l: int64): C4Str {.importc: "c4string_new", cdecl.}
proc newC4Str*(s: cstring): C4Str {.importc: "c4string_from_cstr", cdecl.}
proc c4str_len*(s: C4Str): int64 {.importc: "c4string_len", cdecl.}
proc c4str_from_file*(name: cstring, err: var cint): C4Str {.importc, cdecl.}
proc free*(s: C4Str) {.importc: "c4string_free", cdecl.}

template len*(s: C4Str): int = int(s.c4str_len())

proc newC4Str*(s: string): C4Str {.cdecl, exportc.} =
  let l = s.len()
  result = newC4Str(l)
  if l != 0:
    copyMem(cast[pointer](result), addr s[0], l)

proc toNimStr*(s: C4Str): string =
  if s == nil:
    return ""
  let l  = s.len()
  result = newString(l)
  copyMem(addr result[0], cast[pointer](s), l)

proc newC4StrFromFile*(fn: string): C4Str {.cdecl, exportc.} =
  var err: cint
  result = c4str_from_file(cstring(fn), err)

  if result == nil:
    raise newException(ValueError, $(strerror(err)))

proc c4str_eq*(s1, s2: C4Str): bool {.cdecl, exportc.} =
  if s1.len() != s2.len():
    return false
  return cast[cstring](s1) == cast[cstring](s2)

proc c4str_lt*(s1, s2: C4Str): bool {.cdecl, exportc.} =
  return cast[cstring](s1) < cast[cstring](s2)

proc c4str_gt*(s1, s2: C4Str): bool {.cdecl, exportc.} =
  return cast[cstring](s1) > cast[cstring](s2)

proc c4str_add*(s1, s2: C4Str): C4Str {.cdecl, exportc.} =
  let
    l1   = s1.len()
    l2   = s2.len()

  result = newC4Str(l1 + l2)

  # Where to start writing the 2nd string.
  let p = cast[pointer](cast[uint](cast[pointer](result)) + uint(l1))

  copyMem(cast[pointer](result), cast[pointer](s1), l1)
  copyMem(p, cast[pointer](s2), l2)

proc c4str_write_offset*(large, small: C4Str, offset: int) {.cdecl, exportc.} =
  let p = cast[pointer](cast[uint](cast[pointer](large)) + uint(offset))

  copyMem(p, cast[pointer](small), small.len())

proc c4str_copy*(s1: C4Str): C4Str {.cdecl, exportc.} =
  let l = s1.len()

  result = newC4Str(l)
  copyMem(cast[pointer](result), cast[pointer](s1), l)
