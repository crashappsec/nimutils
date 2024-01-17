import os

static:
  {.compile: joinPath(splitPath(currentSourcePath()).head, "c/strcontainer.c").}

type C4Str = pointer

proc newC4Str*(l: int64): C4Str {.importc: "c4string_new", cdecl.}
proc newC4Str*(s: cstring): C4Str {.importc: "c4string_from_cstr", cdecl.}
proc len*(s: C4Str): int64 {.importc: "c4string_len", cdecl.}
proc free*(s: C4Str) {.importc: "c4string_free", cdecl.}

proc newC4Str*(s: string): C4Str =
  let l = s.len()
  result = newC4Str(l)
  if l != 0:
    copyMem(cast[pointer](result), addr s[0], l)
