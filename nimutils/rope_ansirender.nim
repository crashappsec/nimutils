## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import options, unicode, misc, colortable, rope_construct, rope_base,
       rope_prerender, rope_styles

from strutils import join, endswith

template ansiReset(): string = "\e[0m"

type AnsiStyleInfo = object
  ansiStart: string
  casing:    TextCasing

proc ansiStyleInfo(b: TextPlane, ch: uint32): AnsiStyleInfo =
  var codes: seq[string]
  let style = ch.idToStyle()

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
    if fgOpt.isSome() and fgOpt.get() != "":
      let fgCode = fgOpt.get().colorNameToHex()
      if fgCode[0] != -1:
        codes.add("38;2;" & $(fgCode[0]) & ";" & $(fgCode[1]) & ";" &
                  $(fgCode[2]))

    if bgOpt.isSome() and bgOpt.get() != "":
      let bgCode = bgOpt.get().colorNameToHex()
      if bgCode[0] != -1:
        codes.add("48;2;" & $(bgCode[0]) & ";" & $(bgCode[1]) & ";" &
                  $(bgCode[2]))
  else:
    if fgOpt.isSome() and fgOpt.get() != "":
      let fgCode = fgOpt.get().colorNameToVga()
      if fgCode != -1:
        codes.add("38;5;" & $(fgCode))

    if bgOpt.isSome() and bgOpt.get() != "":
      let bgCode = bgOpt.get().colorNameToVga()
      if bgCode != -1:
        codes.add("48;5;" & $(bgCode))

  if len(codes) > 0:
    result.ansiStart = "\e[" & codes.join(";") & "m"

proc preRenderBoxToAnsiString*(b: TextPlane, ensureNl = true): string =
  # TODO: Add back in unicode underline, etc.
  var
    styleInfo:  AnsiStyleInfo
    shouldTitle = false

  for line in b.lines:
    for ch in line:
      if ch > 0x10ffff:
        if ch == StylePop:
          continue
        else:
          styleInfo = b.ansiStyleInfo(ch)
        if styleInfo.ansiStart.len() > 0 and getShowColor():
          result &= ansiReset()
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
    if not b.softBreak:
      result &= "\n"
    if getShowColor():
      result &= ansiReset()

  if ensureNl and not result.endswith("\n"):
    if styleInfo.ansiStart.len() > 0 and getShowColor():
      result &= ansiReset() & styleInfo.ansiStart & "\n" & ansiReset()
    else:
      result = "\n"

template stylizeMd*(s: string, width = -1, showLinks = false,
                    ensureNl = true, style = defaultStyle): string =
  s.htmlStringToRope().
    preRender(width, showLinks, style).
    preRenderBoxToAnsiString(ensureNl)

template stylizeHtml*(s: string, width = -1, showLinks = false,
                      ensureNl = true, style = defaultStyle): string =
  s.htmlStringToRope(false).
    preRender(width, showLinks, style).
    preRenderBoxToAnsiString(ensureNl)

proc stylize*(s: string, width = -1, showLinks = false,
              ensureNl = true, style = defaultStyle): string =
  let r = Rope(kind: RopeAtom, text: s.toRunes())
  return r.preRender(width, showLinks, style).
           preRenderBoxToAnsiString(ensureNl)

proc stylize*(s: string, tag: string, width = -1, showLinks = false,
              ensureNl = true, style = defaultStyle): string =
  var r: Rope

  if tag != "":
    r = Rope(kind: RopeTaggedContainer, tag: tag,
                 contained: Rope(kind: RopeAtom, text: s.toRunes()))
  else:
    r = Rope(kind: RopeAtom, text: s.toRunes())

  return r.preRender(width, showLinks, style).
           preRenderBoxToAnsiString(ensureNl)

proc withColor*(s: string, fg: string, bg = ""): string =
  if fg == "" and bg == "":
    result = s
  else:
    result =  s.stylize(ensureNl = false, style = newStyle(fgColor = fg,
                        bgColor = bg))

  result = result.strip()

proc print*(s: string, file = stdout, md = true, width = -1, ensureNl = true,
           showLinks = false, style = defaultStyle) =
  var toWrite: string
  if md:
    toWrite = s.stylizeMd(width, showLinks, ensureNl, style)
  else:
    toWrite = s.stylizeHtml(width, showLinks, ensureNl, style)

  file.write(toWrite)
