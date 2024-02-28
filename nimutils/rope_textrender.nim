import std/unicode
import "."/[rope_base, rope_prerender, rope_construct]

proc toUtf8*(r: Rope, width = high(int)): string =
  ## Convert a rope to UTF8 with no styling other than line wrap, if a
  ## value is passed in for `width`.

  let box = nocolors(r).preRender(width)
  for i, line in box.lines:
    if i != 0:
      result.add("\n")
    for i32 in line:
      if i32 > 0x10ffff:
        continue
      result.add($(Rune(i32)))
  if not box.softBreak:
    result.add("\n")

proc toUtf32*(r: Rope, width = high(int)): seq[Rune] =
  ## Convert a rope to UTF8 with no styling other than line wrap, if a
  ## value is passed in for `width`.

  let box = nocolors(r).preRender(width)
  for i, line in box.lines:
    if i != 0:
      result.add(Rune('\n'))
    for i32 in line:
      if i32 > 0x10ffff:
        continue
      result.add(Rune(i32))
  if not box.softBreak:
    result.add(Rune('\n'))
