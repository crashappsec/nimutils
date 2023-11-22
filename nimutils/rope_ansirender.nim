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
    result.ansiStart = "\e[0m\e[" & codes.join(";") & "m"
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
    colorStack: seq[bool]
    shouldTitle  = false
    foundNoColor = false

  for line in b.lines:
    for i, ch in line:
      if ch > 0x10ffff:
        if ch == StylePop:
          if canColor():
            result &= ansiReset()
        elif ch == StyleColor:
          colorStack.add(foundNoColor)
          foundNoColor = false
        elif ch == StyleNoColor:
          colorStack.add(foundNoColor)
          foundNoColor = true
        elif ch == StyleColorPop:
          if len(colorStack) != 0:
            foundNoColor = colorStack.pop()
        else:
          styleInfo = b.ansiStyleInfo(ch)
        if canColor():
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
      if canColor():
        result &= ansiReset() & "\r\n"
      elif canColor():
        result &= ansiReset()
  if canColor():
    result &= ansiReset()


template render(r: Rope, width: int, showLinks: bool, style: FmtStyle,
                ensureNl: bool, noColor: bool): string =
  var toRender: Rope
  if ensureNl and r.noBoxRequired():
    toRender = ensureNewline(r)
  else:
    toRender = r
  toRender.preRender(width, showLinks, style).preRenderBoxToAnsiString(noColor)

proc setvbuf(f: File, buf: pointer, t: cint, s: cint): cint {. importc,
                                                    header: "<stdio.h>" .}

proc unbufferIo*() =
  once:
    discard setvbuf(stdout, nil, cint(2), 0)
    discard setvbuf(stderr, nil, cint(2), 0)
    discard setvbuf(stdin, nil, cint(2), 0)

proc `$`*(r: Rope, width = 0, ensureNl = false, showLinks = false,
           noColor = false, style = defaultStyle): string =
  ## The default rope-to-string output function.
  ## 
  ## `width` sets the output width to render into. If it's zero or
  ## less, then it's interpreted as an offset from the current
  ## terminal width. Tho generally you should just create a box with
  ## the padding you'd like.
  ##
  ## `ensureNl` will put a newline at the end of the result if the
  ## output wouldn't otherwise have one.
  ##
  ## If there are links (e.g., from html), `showLinks` will output
  ## them as if in a markdown doc.
  ## 
  ## The `noColor` flag will inhibit any ansi codes, despite any
  ## global settings allowing color.
  ##
  ## The `style` parameter allows you to override elements of the
  ## default starting style. However, it does NOT override any style
  ## formatting set. To do that, use the style API.
  return r.render(width, showLinks, style, ensureNl, noColor)

proc print*(r: Rope, file = stdout, width = 0, ensureNl = true,
            showLinks = false, noColor = false, style = defaultStyle) =
  ## `width` sets the output width to render into. If it's zero or
  ## less, then it's interpreted as an offset from the current
  ## terminal width. Tho generally you should just create a box with
  ## the padding you'd like.
  ##
  ## `ensureNl` will put a newline at the end of the result if the
  ## output wouldn't otherwise have one.
  ##
  ## If there are links (e.g., from html), `showLinks` will output
  ## them as if in a markdown doc.
  ## 
  ## The `noColor` flag will inhibit any ansi codes, despite any
  ## global settings allowing color.
  ##
  ## The `style` parameter allows you to override elements of the
  ## default starting style. However, it does NOT override any style
  ## formatting set. To do that, use the style API.

  unbufferIo()
  file.write(r.render(width, showLinks, style, ensureNl, noColor))

proc print*(s: string, file = stdout, forceMd = false, forceHtml = false,
            width = 0, ensureNl = true, showLinks = false, detect = true, 
            noColor = false, pre = true, style = defaultStyle) =
  unbufferIo()
  ## Much like `echo()`, but more capable in terms of the processing
  ## you can do.
  ##
  ## Particularly, `print()` can accept Markdown or HTML, and render
  ## it for the terminal to the current terminal width. It can also
  ## apply foreground/background colors, and other styling.
  ##
  ## If a string to print starts with '#' (it's first non-space
  ## character), it's assumed to be Markdown (HTML if it starts with
  ## '<'). To always skip conversion, then set `detect = false`.
  ##
  ## If you know your string might contain Markdown or HTML, but might
  ## not start with a special character, you can instead set
  ## `forceMd = true`, or `forceHtml = true`.
  ##
  ## Generally, the terminal width is automatically queried at the
  ## time you call `print()`, but the `width` parameter allows you
  ## to render to a particular width.
  ##
  ## If you pass the `ensureNl` flag, you're asking to ensure that the
  ## output a trailing new line, even if the input doesn't end with a
  ## break.
  ##
  ## When true, `showLinks` currently will render both the URL and the
  ## text in an html <a> element, using a markdown-like syntax.
  ##
  ## Unlike `echo()`, where inputs to print can be comma separated,
  ## and are automatically converted to strings, `print()` only
  ## accepts strings in the first parameter (there's a variant that
  ## supports Ropes, essentially strings already
  ##
  ## The `noColor` flag will inhibit any ansi codes, despite any
  ## global settings allowing color.
  ##
  ## When `pre` is true, newlines in the input will be
  ## preserved. Otherwise, the text is treated like html, where the
  ## text is expected to be wrapped-- in this mode, you need TWO
  ## consecutive newlines to get a newline in the output.
  ##
  ## In both cases, tabs are *always* converted to four spaces. Giving
  ## semantics based on tab stops would increase complexity a lot and
  ## we don't want to support it.
  ##
  ## The `style` parameter allows you to override elements of the
  ## default starting style. However, it does NOT override any style
  ## formatting set. To do that, use the style API.
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

  var toRender: Rope

  if forceMd:
    toRender = markdown(s)
  elif forceHtml:
    toRender = html(s)
  else:
    toRender = text(s, pre, detect)
   
  file.write(toRender.render(width, showLinks, style, ensureNl, noColor))

