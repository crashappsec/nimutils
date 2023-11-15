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
  else:
    result.ansiStart = "\e[0m"

template canColor(): bool =
  if noColor or foundNoColor or not getShowColor():
    false
  else:
    true

proc preRenderBoxToAnsiString*(b: TextPlane, noColor = false): string =
  ## Low-level interface for taking our lowest-level internal
  ## representation, where the exact layout of the output is fully
  ## specified, and converting it into ansi codes for the terminal.
  # TODO: Add back in unicode underline, etc.
  var
    styleInfo:  AnsiStyleInfo
    shouldTitle  = false
    foundNoColor = false
    colorNest    = 0

  for line in b.lines:
    for ch in line:
      if ch > 0x10ffff:
        if ch == StylePop:
          if canColor():
            result &= ansiReset()
        elif ch == StyleColor:
          if colorNest == 0:
            foundNoColor = false
          colorNest += 1
        elif ch == StyleNoColor:
          if colorNest == 0:
            foundNoColor = true
          colorNest += 1
        elif ch == StyleColorPop:
          colorNest -= 1
        else:
          styleInfo = b.ansiStyleInfo(ch)
        if canColor():
          result &= ansiReset()
          result &= styleInfo.ansiStart
        if styleInfo.casing == CasingTitle:
          shouldTitle = true
      else:
        if ch == uint32('\e'):
          raise newException(ValueError, "ANSI escape codes are not allowed " &
            "in text in this API")
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
    if canColor():
      result &= ansiReset()

template render(r: Rope, width: int, showLinks: bool, style: FmtStyle,
                ensureNl: bool, noColor: bool, outerPad: bool): string =
  var toRender: Rope
  if ensureNl and r.noBoxRequired():
    toRender = ensureNewline(r)
  else:
    toRender = r
  toRender.preRender(width, showLinks, style, outerPad).
           preRenderBoxToAnsiString(noColor)

template stylizeMd*(s: string, width = -1, showLinks = false,
                    ensureNl = true, style = defaultStyle,
                               noColor = false, outerPad = true): string =
  s.htmlStringToRope().
    render(width, showLinks, style, ensureNl, noColor, outerPad)

template stylizeHtml*(s: string, width = -1, showLinks = false,
                      ensureNl = true, style = defaultStyle,
                                 noColor = false, outerPad = true): string =
  s.htmlStringToRope(false).
    render(width, showLinks, style, ensureNl, noColor, outerPad)

proc stylize*(s: string, width = -1, showLinks = false, ensureNl = true,
              style = defaultStyle, noColor = false, outerPad = true): string =
  ## Apply a full style object to a string, using the passed style.
  ## Does not process Markdown or HTML.
  ##
  ## Deprecated; use the style API instead.
  ##
  ## Returns a string.
  ##
  ## Note that you should never pass strings with control codes to
  ## this API. It will not get considered in the state machine /
  ## processing done. Not only should you avoid manually adding
  ## control codes, this also means you should never feed the output
  ## of this API back into the API.
  return pre(s).render(width, showLinks, style, ensureNl, noColor, outerPad)

proc stylize*(s: string, tag: string, width = -1, showLinks = false,
              ensureNl = true, style = defaultStyle, noColor = false,
              outerPad = true): string =
  ## Apply a full style object to a string, specifying a `tag` to
  ## use (an html tag) for the style. Does not process Markdown or
  ## HTML.
  ##
  ## Deprecated; use the style API instead.
  ##
  ## If passed, `style` should be a style object that will be the
  ## starting style (after layering it on top of the default style).
  ##
  ## Any stored style associated with the `tag` parameter will get
  ## applied AFTER the style object.
  ##
  ## Returns a string.
  ##
  ## Note that you should never pass strings with control codes to
  ## this API. It will not get considered in the state machine /
  ## processing done. Not only should you avoid manually adding
  ## control codes, this also means you should never feed the output
  ## of this API back into the API.
  var r: Rope

  if tag != "":
    r = Rope(kind: RopeTaggedContainer, tag: tag,
                 contained: Rope(kind: RopeAtom, text: s.toRunes()))
  else:
    r = Rope(kind: RopeAtom, text: s.toRunes())

  return r.render(width, showLinks, style, ensureNl, noColor, outerPad)

proc withColor*(s: string, fg: string, bg = ""): string =
  ## Deprecated.
  ##
  ## The style API allows you to apply color, chaining the results,
  ## but has more extensive options than color.
  ##
  ## To replace both the fg color and bg color, do:
  ## s.fgColor("red").bgColor("white")
  ##
  ## Or, clear the colors with defaultFg() and defaultBg()
  ##
  ## Note that you should never pass strings with control codes to
  ## this API. It will not get considered in the state machine /
  ## processing done. Not only should you avoid manually adding
  ## control codes, this also means you should never feed the output
  ## of this API back into the API.


  if fg == "" and bg == "":
    result = s
  else:
    result =  s.stylize(ensureNl = false, style = newStyle(fgColor = fg,
                        bgColor = bg))

proc `$`*(r: Rope, width = -1, ensureNl = false, showLinks = false,
          style = defaultStyle, noColor = false, outerPad = true): string =
  ## Default rope-to-string output function.
  return r.render(width, showLinks, style, ensureNl, noColor, outerPad)

proc setvbuf(f: File, buf: pointer, t: cint, s: cint): cint {. importc,
                                                    header: "<stdio.h>" .}

proc unbufferIo*() =
  once:
    discard setvbuf(stdout, nil, cint(2), 0)
    discard setvbuf(stderr, nil, cint(2), 0)
    discard setvbuf(stdin, nil, cint(2), 0)

proc print*(s: string, file = stdout, forceMd = false, width = -1,
            ensureNl = true, showLinks = false, style = defaultStyle,
            noAutoDetect = false, noColor = false, outerPad = true) =
  unbufferIo()
  ## Much like `echo()`, but more capable in terms of the processing
  ## you can do.
  ##
  ## Particularly, `print()` can accept Markdown or HTML, and render
  ## it for the terminal to the current terminal width. It can also
  ## apply foreground/background colors, and other styling.
  ##
  ## If a string to print starts with '#', it's assumed to be Markdown
  ## (HTML if it starts with '<'). To always skip conversion, then set
  ## `noAutoDetect = true`.
  ##
  ## If you know your string might contain Markdown or HTML, but might
  ## not start with a special character, you can instead set
  ## `forceMd = true`.
  ##
  ## Generally, the terminal width is automatically queried at the
  ## time you call `print()`, but the `width` parameter allows you
  ## to render to a particular width.
  ##
  ## When true, `showLinks` currently will render both the URL and the
  ## text in an html <a> element, using a markdown-like syntax.
  ##
  ## The `style` parameter allows you to override elements of the
  ## default starting style. However, it does NOT override any style
  ## formatting set. To do that, use the style API.
  ##
  ## Unlike `echo()`, where inputs to print can be comma separated,
  ## and are automatically converted to strings, `print()` only
  ## accepts strings in the first parameter (there's a variant that
  ## supports Ropes, essentially strings already
  ##
  ## The `noColor` flag will inhibit any ansi codes, despite any
  ## global settings allowing color.
  ##
  ## Do not pass strings with control codes as inputs.
  ##
  ## Markdown is processed by MD4C (which converts it to HTML), and
  ## HTML is processd by gumbo. If you use this feature, but pass
  ## text that the underlying processor doesn't accept, the result is
  ## undefined. Assume you won't get what you want, anyway!

  if s[0] == '\e':
    # If it starts with an Ansi code, fall back to echo, as it was
    # probably generated with one of the above functions.
    #
    # But we avoid a linear scan of the entire string.
    file.write(s)
    return
  var toWrite: string

  if forceMd or ((not noAutoDetect) and len(s) > 1 and s[0] == '#'):
    toWrite = s.stylizeMd(width, showLinks, ensureNl, style, noColor, outerPad)
  elif len(s) >= 1 and s[0] == '<':
    toWrite = s.stylizeHtml(width, showLinks, ensureNl, style, noColor, outerPad)
  else:
    toWrite = pre(s).render(width, showLinks, style, ensureNl, noColor, outerPad)
  file.write(toWrite)

proc print*(r: Rope, file = stdout, width = -1, ensureNl = true,
            showLinks = false, style = defaultStyle, noColor = false,
            outerPad = true) =
  unbufferIo()
  file.write(r.render(width, showLinks, style, ensureNl, noColor, outerPad))
