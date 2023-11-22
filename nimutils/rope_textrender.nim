import rope_base, rope_prerender, rope_construct, unicode

proc toUtf8*(r: Rope, width = high(int)): string =
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
