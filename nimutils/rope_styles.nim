##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import unicode, tables, rope_base, options


proc newStyle*(fgColor = "", bgColor = "", overflow = OIgnore,
               wrapIndent = -1, lpad = -1, rpad = -1, lPadChar = Rune(0x0000),
               rpadChar = Rune(0x0000), casing = CasingIgnore,
               paragraphSpacing = -1, bold = BoldIgnore,
               inverse = InverseIgnore, strikethru = StrikeThruIgnore,
               italic = ItalicIgnore, underline = UnderlineIgnore,
               bulletChar = Rune(0x0000), minColWidth = -1, maxColWidth = -1,
               borders: openarray[BorderOpts] = [], boxStyle: BoxStyle = nil,
               align = AlignIgnore): FmtStyle =
    result = FmtStyle()

    if fgColor != "":
      result.textColor = some(fgColor)
    if bgColor != "":
      result.bgColor   = some(bgColor)
    if overflow != OIgnore:
      result.overFlow = some(overflow)
    if wrapIndent >= 0:
      result.wrapIndent = some(wrapIndent)
    if lpad >= 0:
      result.lpad = some(lpad)
    if rpad >= 0:
      result.rpad = some(rpad)
    if lpadChar != Rune(0x0000):
      result.lpadChar = some(lpadChar)
    if rpadChar != Rune(0x0000):
      result.rpadChar = some(rpadChar)
    if casing != CasingIgnore:
      result.casing = some(casing)
    if paragraphSpacing > 0:
      result.paragraphSpacing = some(paragraphSpacing)
    case bold
    of BoldOn:
      result.bold = some(true)
    of BoldOff:
      result.bold = some(false)
    else:
      discard
    case inverse
    of InverseOn:
      result.inverse = some(true)
    of InverseOff:
      result.inverse = some(false)
    else:
      discard
    case strikethru
    of StrikeThruOn:
      result.strikethrough = some(true)
    of StrikeThruOff:
      result.strikethrough = some(false)
    else:
      discard
    case italic
    of ItalicOn:
      result.italic = some(true)
    of ItalicOff:
      result.italic = some(false)
    else:
      discard
    if underline != UnderlineIgnore:
      result.underlineStyle = some(underline)
    if bulletChar != Rune(0x0000):
      result.bulletChar = some(bulletChar)
    if minColWidth != -1:
      result.minTableColWidth = some(minColWidth)
    if maxColWidth != -1:
      result.maxTableColWidth = some(maxColWidth)

    if len(borders) != 0:
      for item in borders:
        case item
        of BorderTop:
          result.useTopBorder = some(true)
        of BorderBottom:
          result.useBottomBorder = some(true)
        of BorderLeft:
          result.useLeftBorder = some(true)
        of BorderRight:
          result.useRightBorder = some(true)
        of HorizontalInterior:
          result.useHorizontalSeparator = some(true)
        of VerticalInterior:
          result.useVerticalSeparator = some(true)
        of BorderTypical:
          result.useTopBorder = some(true)
          result.useBottomBorder = some(true)
          result.useLeftBorder = some(true)
          result.useRightBorder = some(true)
          result.useVerticalSeparator = some(true)
        of BorderAll:
          result.useTopBorder = some(true)
          result.useBottomBorder = some(true)
          result.useLeftBorder = some(true)
          result.useRightBorder = some(true)
          result.useVerticalSeparator = some(true)
          result.useHorizontalSeparator = some(true)
    if boxStyle != nil:
      result.boxStyle = some(boxStyle)
    if align != AlignIgnore:
      result.alignStyle = some(align)

var
  defaultStyle* = newStyle(overflow = OWrap, rpad = 1, lpadChar = Rune(' '),
                           lpad = 0, rpadChar = Rune(' '), paragraphSpacing = 1)
  # To figure out what you're not properly formatting yet, add this to the default style:
  # bgcolor = "thunder", fgcolor = "black",
  #
  # Then, anything not selected is not yet done!


  styleMap*: Table[string, FmtStyle] = {
    "title" : newStyle(fgColor = "jazzberry", bold = BoldOn,
          align = AlignC, italic = ItalicOn, casing = CasingUpper),
    "h1" : newStyle(fgColor = "atomiclime", bold = BoldOn,
           align = AlignC, italic = ItalicOn, casing = CasingUpper),
    "h2" : newStyle(bgColor = "jazzberry", fgColor = "white", bold = BoldOn,
                    italic = ItalicOn),
    "h3" : newStyle(bgColor = "fandango", fgColor = "white", italic = ItalicOn,
                    underline = UnderlineDouble, casing = CasingUpper),
    "h4" : newStyle(fgColor = "jazzberry", italic = ItalicOn,
                    underline = UnderlineSingle, casing = CasingTitle),
    "h5" : newStyle(fgColor = "atomiclime", bgColor = "black",
                              italic = ItalicOn, casing = CasingTitle),
    "h6" : newStyle(fgColor = "fandango", bgColor = "white",
                    underline = UnderlineSingle, casing = CasingTitle),
    "ol" : newStyle(bulletChar = Rune('.'), lpad = 2),
    "ul" : newStyle(bulletChar = Rune(0x2022),lpad = 2), #•
    "li" : newStyle(lpad = 1),
    "table" : newStyle(borders = [BorderTypical], overflow = OWrap),
    "th"    : newStyle(fgColor = "black", bold = BoldOn,
                                 bgColor = "atomiclime"),
    "tr.even": newStyle(fgColor = "white", bgColor = "jazzberry"),
    "tr.odd" : newStyle(fgColor = "white", bgColor = "fandango"),
    "em" : newStyle(fgColor = "atomiclime", bold = BoldOn),
    "strong" : newStyle(inverse = InverseOn, italic = ItalicOn),
    "code" : newStyle(inverse = InverseOn, italic = ItalicOn)
    }.toTable()

  perClassStyles* = Table[string, FmtStyle]()
  perIdStyles*    = Table[string, FmtStyle]()

  breakingStyles*: Table[string, bool] = {
    "p"          : true,
    "div"        : true,
    "ol"         : true,
    "ul"         : true,
    "li"         : true,
    "blockquote" : true,
    "pre"        : true,
    "q"          : true,
    "small"      : true,
    "td"         : true,
    "th"         : true,
    "title"      : true,
    "h1"         : true,
    "h2"         : true,
    "h3"         : true,
    "h4"         : true,
    "h5"         : true,
    "h6"         : true
    }.toTable()

{.emit: """
#include <stdatomic.h>
#include <stdint.h>

_Atomic(uint32_t) next_id = ATOMIC_VAR_INIT(0x1ffffff);

uint32_t
next_style_id() {
  return atomic_fetch_add(&next_id, 1);
}

""" .}

# I'd love for each style is going to get one unique ID that we can
# look up in both directions. Currently this won't work in a
# multi-threaded world, but I'm going to soon migrate it to my
# lock-free, wait-free hash tables.

proc next_style_id(): cuint {.importc, nodecl.}

var
  idToStyleMap: Table[uint32, FmtStyle]
  styleToIdMap: Table[FmtStyle, uint32]

proc getStyleId*(s: FmtStyle): uint32 =
  if s in styleToIdMap:
    return styleToIdMap[s]

  result = uint32(next_style_id())

  idToStyleMap[result] = s
  styleToIdMap[s]      = result

proc idToStyle*(n: uint32): FmtStyle =
  result = idToStyleMap[n]

proc mergeStyles*(base: FmtStyle, changes: FmtStyle): FmtStyle =
  result = base.copyStyle()
  if changes == nil:
    return
  if changes.textColor.isSome():
    result.textColor = changes.textColor
  if changes.bgColor.isSome():
    result.bgColor = changes.bgColor
  if changes.overflow.isSome():
    result.overflow = changes.overflow
  if changes.wrapIndent.isSome():
    result.wrapIndent = changes.wrapIndent
  if changes.lpad.isSome():
    result.lpad = changes.lpad
  if changes.rpad.isSome():
    result.rpad = changes.rpad
  if changes.lpadChar.isSome():
    result.lpadChar = changes.lpadChar
  if changes.rpadChar.isSome():
    result.rpadChar = changes.rpadChar
  if changes.casing.isSome():
    result.casing = changes.casing
  if changes.bold.isSome():
    result.bold = changes.bold
  if changes.inverse.isSome():
    result.inverse = changes.inverse
  if changes.strikethrough.isSome():
    result.strikethrough = changes.strikethrough
  if changes.italic.isSome():
    result.italic = changes.italic
  if changes.underlineStyle.isSome():
    result.underlineStyle = changes.underlineStyle
  if changes.bulletChar.isSome():
    result.bulletChar = changes.bulletChar
  if changes.minTableColWidth.isSome():
    result.minTableColWidth = changes.minTableColWidth
  if changes.maxTableColWidth.isSome():
    result.maxTableColWidth = changes.maxTableColWidth
  if changes.useTopBorder.isSome():
    result.useTopBorder = changes.useTopBorder
  if changes.useBottomBorder.isSome():
    result.useBottomBorder = changes.useBottomBorder
  if changes.useLeftBorder.isSome():
    result.useLeftBorder = changes.useLeftBorder
  if changes.useRightBorder.isSome():
    result.useRightBorder = changes.useRightBorder
  if changes.useVerticalSeparator.isSome():
    result.useVerticalSeparator = changes.useVerticalSeparator
  if changes.useHorizontalSeparator.isSome():
    result.useHorizontalSeparator = changes.useHorizontalSeparator
  if changes.boxStyle.isSome():
    result.boxStyle = changes.boxStyle
  if changes.alignStyle.isSome():
    result.alignStyle = changes.alignStyle
