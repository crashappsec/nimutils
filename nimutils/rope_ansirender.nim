## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import tables, options, unicode, misc, colortable, rope_base, rope_prerender

from strutils import join

template ansiReset(): string = "\e[0m"

type AnsiStyleInfo = object
  ansiStart: string
  casing:    TextCasing

proc ansiStyleInfo(b: TextPlane, ch: uint32): AnsiStyleInfo =
  var codes: seq[string]
  let style = b.styleMap[ch]

  result.casing = style.casing.getOrElse(CasingIgnore)

  if not getShowColor():
    return

  case style.underlineStyle.getOrElse(UnderlineNone)
  of UnderlineSingle:
    codes.add("4")
  of UnderlineDouble:
    codes.add("21")
  else:
    discard

  if style.bold.getOrElse(false):
    codes.add("1")

  if style.italic.getOrElse(false):
    codes.add("3")

  if style.inverse.getOrElse(false):
    codes.add("7")

  if style.strikethrough.getOrElse(false):
    codes.add("9")

  let
    fgOpt = style.textColor
    bgOpt = style.bgColor

  if getColor24Bit():
    if fgOpt.isSome():
      let fgCode = fgOpt.get().colorNameToHex()
      if fgCode[0] != -1:
        codes.add("38;2;" & $(fgCode[0]) & ";" & $(fgCode[1]) & ";" &
                  $(fgCode[2]))

    if bgOpt.isSome():
      let bgCode = bgOpt.get().colorNameToHex()
      if bgCode[0] != -1:
        codes.add("48;2;" & $(bgCode[0]) & ";" & $(bgCode[1]) & ";" &
                  $(bgCode[2]))
  else:
    if fgOpt.isSome():
      let fgCode = fgOpt.get().colorNameToVga()
      if fgCode != -1:
        codes.add("38;5;" & $(fgCode))

    if bgOpt.isSome():
      let bgCode = bgOpt.get().colorNameToVga()
      if bgCode != -1:
        codes.add("48;5;" & $(bgCode))

  if len(codes) > 0:
    result.ansiStart = "\e[" & codes.join(";") & "m"

proc preRenderBoxToAnsiString*(b: TextPlane): string =
  # TODO: Add back in unicode underline, etc.
  var
    styleStack: seq[uint32]
    styleInfo:  AnsiStyleInfo
    shouldTitle = false

  for line in b.lines:
    for ch in line:
      if ch > 0x10ffff:
        if len(styleStack) > 0:
          result &= ansiReset()
        if ch == StylePop:
          discard styleStack.pop()
        else:
          styleStack.add(ch)
        styleInfo = b.ansiStyleInfo(ch)
        if styleInfo.ansiStart.len() > 0:
          result &= styleInfo.ansiStart
        if styleInfo.casing == CasingTitle:
          shouldTitle = true
      else:
        case styleInfo.casing
        of CasingTitle:
          if Rune(ch).isAlpha():
            if shouldTitle:
              result &= $(Rune(ch).toUpper())
              shouldTitle = false
            else:
              result &= $(Rune(ch))
              shouldTitle = false
          else:
            shouldTitle = true
            result &= $(Rune(ch))
        of CasingUpper:
          result &= $(Rune(ch).toUpper())
        of CasingLower:
          result &= $(Rune(ch).toLower())
        else:
          result &= $(Rune(ch))
    result &= "\n"

template stylize*(r: Rope, width = -1): string =
  r.preRender(width).preRenderBoxToAnsiString()


template withColor*(s: string, c: string): string =
  stylize("<" & c & ">" & s & "</" & c & ">")

proc print*(r: Rope = nil, file = stdout, width = -1) =
  if r == nil:
    file.write("\n")
  else:
    file.write(stylize(r, width))
