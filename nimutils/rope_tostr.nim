## A rope abstraction that's meant to help keep track of extensible
## formatting data, isolating the formatting from the text to
## format. This will help tremendously for being able to properly wrap
## text, etc.
##
## Units of a rope we're calling 'segments'.

## The most basic segment I'm calling an atom. An atom needs to be
## embeddable in any other unit... it must simply be text that has a
## size, with no line breaks. It *can* have formatting preferences.
##
## A hard line break is its own rope segment type.
##
## Paragraphs should be able to contain any other kind of segment.
##
## The only critical item:
## TODO: Tables.
##
## Other items:
## TODO: Make it possible to add an extra space before headings
##       via style (extra pad params)
## TODO: padding on generic breaking containers, etc.
## TODO: Apply color to bullets.
## TODO: Alignment for block styles.
## TODO: <width>...</width> That forces aligning to a width, as long as the
##       width (would take an argument); OR, allow custom tags to
##       add a style that pads to a width.
## TODO: Spacing around specific elements like li or ol
## TODO: < tag id=foo > to be able to style individual elements.
## TODO: Links should add URLs in params if the href starts w/ 'http' and
##       http doesn't appear in the contents.
## TODO: Currently ignoring table captions.
## TODO: Column alignments in tables.
## TODO: Flexible pad on table cells
## TODO: Always take up all available width.
##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import os, unicode, unicodedb, unicodedb/widths, unicodeid, sugar, markdown,
       htmlparse, tables, std/terminal, parseutils, options, colortable,
       rope_base, rope_styles, rope_construct
from strutils import join, startswith, endswith, replace

template setAtomLength(r: Rope) =
  if r.length == 0:
    for ch in r.text:
      r.length += ch.runeWidth()

type
  FormattedOutput* = object
    contents:        seq[string]
    maxWidth:        int
    lineWidths:      seq[int]
    startsWithBreak: bool
    finalBreak:      bool
    tdStyleCache:    FmtStyle
  FmtState* = object
    availableWidth: int
    totalWidth:     int
    curStyle:       FmtStyle
    styleStack:     seq[FmtStyle]


proc getFgColor(s: FmtState): Option[string] =
  return s.curStyle.textColor

proc getBgColor(s: FmtState): Option[string] =
  return s.curStyle.bgColor

proc getOverflow(s: FmtState): OverflowPreference =
  return s.curStyle.overflow.get(OWrap)

proc getWrapIndent(s: FmtState): int =
  return s.curStyle.wrapIndent.get(0)

proc getLpad(s: FmtState): int =
  return s.curStyle.lpad.get(0)

proc getRpad(s: FmtState): int =
  return s.curStyle.lpad.get(0)

proc getLpadChar(s: FmtState): Rune =
  return s.curStyle.lpadChar.get(Rune(' '))

proc getRpadChar(s: FmtState): Rune =
  return s.curStyle.lpadChar.get(Rune(' '))

proc getCasing(s: FmtState): TextCasing =
  return s.curStyle.casing.get(CasingAsIs)

proc getParagraphSpacing(s: FmtState): int =
  return s.curStyle.paragraphSpacing.get(1)

proc getBold(s: FmtState): bool =
  return s.curStyle.bold.get(false)

proc getInverse(s: FmtState): bool =
  return s.curStyle.inverse.get(false)

proc getStrikethrough(s: FmtState): bool =
  return s.curStyle.strikethrough.get(false)

proc getItalic(s: FmtState): bool =
  return s.curStyle.italic.get(false)

proc getUnderlineStyle(s: FmtState): UnderlineStyle =
  return s.curStyle.underlineStyle.get(UnderlineNone)

proc getBulletChar(s: FmtState): Option[Rune] =
  return s.curStyle.bulletChar

proc getUseTopBorder(s: FmtState): bool =
  return s.curStyle.useTopBorder.get(false)

proc getUseBottomBorder(s: FmtState): bool =
  return s.curStyle.useBottomBorder.get(false)

proc getUseLeftBorder(s: FmtState): bool =
  return s.curStyle.useLeftBorder.get(false)

proc getUseRightBorder(s: FmtState): bool =
  return s.curStyle.useRightBorder.get(false)

proc getUseVerticalSeparator(s: FmtState): bool =
  return s.curStyle.useVerticalSeparator.get(false)

proc getUseHorizontalSeparator(s: FmtState): bool =
  return s.curStyle.useHorizontalSeparator.get(false)

proc getBoxStyle(s: FmtState): BoxStyle =
  return s.curStyle.boxStyle.get(BoxStyleBoldDash2)  #BoldDash)

proc combineFormattedOutput(a: var FormattedOutput, b: FormattedOutput) =
  if b.startsWithBreak:
    a.finalBreak = true
  if a.finalBreak:
    a.contents   &= b.contents
    a.lineWidths &= b.lineWidths
    if b.maxWidth > a.maxWidth:
      a.maxWidth = b.maxWidth
    a.finalBreak = b.finalBreak

  elif len(a.contents) != 0 and len(b.contents) != 0:
    a.contents[^1] &= b.contents[0]
    a.lineWidths[^1] = a.lineWidths[^1] + b.lineWidths[0]
    if a.maxWidth < a.lineWidths[^1]:
      a.maxWidth = a.lineWidths[^1]
    if len(b.contents) > 1:
      a.contents   &= b.contents[1 .. ^1]
      a.lineWidths &= b.lineWidths[1 .. ^1]
      if b.maxWidth > a.maxWidth:
        a.maxWidth = b.maxWidth
    a.finalBreak = b.finalBreak
  elif len(a.contents) == 0:
    a = b

template withStyle(state: var FmtState, style: FmtStyle, code: untyped) =
  # This is used when converting a rope back to a string to output.
  state.styleStack.add(state.curStyle)
  state.curStyle = state.curStyle.mergeStyles(style)
  code
  state.curStyle = state.styleStack.pop()

template withStyleAndTag(state: var FmtState, style: FmtStyle, tag: string,
                         code: untyped) =
  state.styleStack.add(state.curStyle)
  if tag in styleMap:
    var newStyle   = state.curStyle.mergeStyles(styleMap[tag])
    state.curStyle = newStyle.mergeStyles(style)
  else:
    state.curStyle = state.curStyle.mergeStyles(style)
  code
  state.curStyle = state.styleStack.pop()

template withTag(state: var FmtState, tag: string, code: untyped) =
  if tag in styleMap:
    state.styleStack.add(state.curStyle)
    state.curStyle = state.curStyle.mergeStyles(styleMap[tag])
    code
    state.curStyle = state.styleStack.pop()
  else:
    code


proc prRopeMaxWidth(r: Rope, soFarThisSubRope: int,
                                curLargest: int) : (int, int) =
  if r == nil:
    if soFarThisSubRope > curLargest:
      return (soFarThisSubRope, soFarThisSubrope)
    else:
      return (soFarThisSubRope, curLargest)

  var
    newSize:    int
    newLargest: int = curLargest
    t:          int # Throw-away; ignored item.

  case r.kind
  of RopeAtom:
    r.setAtomLength() # just in case
    newSize    = soFarThisSubRope + r.length
    newLargest = if curLargest < newSize: newSize else: curLargest

  of RopeBreak:
    (t, newLargest) = r.guts.prRopeMaxWidth(0, curLargest)
    newSize         = 0

  of RopeLink:
    (newSize, newLargest) = r.guts.prRopeMaxWidth(soFarThisSubrope, curLargest)

  of RopeFgColor, RopeBgColor:
    (newSize, newLargest) = r.toColor.prRopeMaxWidth(soFarThisSubrope,
                                                     curLargest)

  of RopeList:
    # TODO: should probably add width for the bullet and padding.
    for item in r.items:
      (t, newLargest) = item.prRopeMaxWidth(0, newLargest)
      newSize         = 0

  of RopeTaggedContainer, RopeAlignedContainer:
    if r.tag in breakingStyles:
      (t, newLargest) = r.contained.prRopeMaxWidth(0, curLargest)
      newSize         = 0
    else:
      (newSize, newLargest) = r.contained.prRopeMaxWidth(soFarThisSubrope,
                                                         curLargest)

  of RopeTable:
    # Currently ignores padding, which is fine since it usually
    # produces such a gross over-estimate anyway.
    (t, newLargest) = r.thead.prRopeMaxWidth(0, newLargest)
    (t, newLargest) = r.tbody.prRopeMaxWidth(0, newLargest)
    (t, newLargest) = r.tfoot.prRopeMaxWidth(0, newLargest)
    newSize         = 0

  of RopeTableRows:
    # This will generally be a gross over-estimation, as RopeTableRow
    # will get the longest from each cell, and add them up.
    for item in r.cells:
      (t, newLargest) = item.prRopeMaxWidth(0, newLargest)

    # Rows can't have nexts.
    return (0, newLargest)

  of RopeTableRow:
    # Here, we calculate the largest per-cell, and then add the values up.
    var cellSize: int

    newSize = 0

    for item in r.cells:
      (cellSize, t) = item.prRopeMaxWidth(0, 0)
      newSize += cellSize

    if newSize > curLargest:
      newLargest = newSize    # else... current is already set.

    return (newSize, newLargest)


  var substatus: bool
  (newSize, newLargest) = r.next.prRopeMaxWidth(newSize, newLargest)


  return (newSize, newLargest)

proc largestWidthInRope(r: Rope): int =
  var ignore: int

  (ignore, result) = r.prRopeMaxWidth(0, 0)

# iterator segments*(s: Rope): Rope =
#   var cur = s

#   while cur != nil:
#     yield cur
#     cur = cur.next

# template forAll*(s: Rope, code: untyped) =
#   for item in s.segments():
#     code

proc hexColorTo24Bit*(hex: int): (int, int, int) =
  var color: int
  if hex > 0xffffff:
    result = (-1, -1, -1)
  else:
    result = (hex shr 16, (hex shr 8 and 0xff), hex and 0xff)

proc hexColorTo8Bit*(hex: string): int =
  # Returns -1 if invalid.
  var color: int

  if parseHex(hex, color) != 6:
    return -1

  let
    blue  = color          and 0xff
    green = (color shr 8)  and 0xff
    red   = (color shr 16) and 0xff

  result = int(red * 7 / 255) shl 5 or
           int(green * 7 / 255) shl 2 or
           int(blue * 3 / 255)

proc colorNameToHex*(name: string): (int, int, int) =
  let colorTable = getColorTable()
  var color: int

  if name in colorTable:
    color = colorTable[name]
  elif parseHex(name, color) != 6:
      result = (-1, -1, -1)
  result = (color shr 16, (color shr 8) and 0xff, color and 0xff)

proc colorNameToVga*(name: string): int =
  let color8Bit = get8BitTable()

  if name in color8Bit:
    return color8Bit[name]
  else:
    return hexColorTo8Bit(name)

proc getBreakOpps(s: seq[Rune]): seq[int] =
  # Should eventually upgrade this to full Annex 14 at some point.
  # Just basic acceptability.
  var lastWasSpace = false
  for i, rune in s[0 ..< ^1]:
    if lastWasSpace:
      result.add(i)
    if rune.isWhiteSpace():
      result.add(i)
      lastWasSpace = true
    else:
      lastWasSpace = false


proc wrapOne(s: seq[Rune], cIx, mIx: int, bps: seq[int], available: int):
         (int, int) =

  # With no regard for the current container, this gives us the breakpoint
  # To which we should wrap, or returns -1 if there's no valid breakpoint.
  var
    breakpoint = -1
    widthAtBp  = -1
    widthUsed  = s[cIx].runeWidth()

  # We assume we trimmed leading spaces, so never break on the first char.
  for i in (cIx + 1) ..< mIx:
    if i in bps:
      breakpoint = i
      widthAtBp  = widthUsed
    let w = s[i].runeWidth()
    if w + widthUsed > available:
      if breakpoint == -1:
        return (i, widthUsed)
      else:
        return (breakpoint, widthAtBp)
    widthUsed += w

  if widthUsed <= available:
    return (mIx, widthUsed)
  else:
    return (breakpoint, widthAtBp)

proc wrapToWidth(s: seq[Rune], runeLen: int, state: var FmtState): string =
  # This should never have any hard breaks in it.

  if runeLen <= state.availableWidth:
    state.availableWidth -= runeLen
    return $(s)

  case state.getOverflow()
  of Overflow:
    state.availableWidth = state.totalWidth
    return $(s) & "\u2028"
  of OIgnore, OTruncate:
    state.availableWidth = state.totalWidth
    return $(s[0 ..< state.availableWidth]) & "\u2028"
  of ODots:
    state.availableWidth = state.totalWidth
    return $(s[0 ..< (state.availableWidth - 1)]) & "\u2026\u2028" # "…"
  of OHardWrap:
    state.availableWidth = state.totalWidth
    result &= $(s[0 ..< state.availableWidth]) & "\u2028"
    var
      curIndex     = state.availableWidth
      remainingLen = runeLen - state.availableWidth
    while remainingLen > state.totalWidth:
      result &= $(s[curIndex ..< (curIndex + state.totalWidth)]) & "\u2028"
      remainingLen -= state.totalWidth
      curIndex += state.totalWidth

    state.availableWidth = state.totalWidth - remainingLen
    result &= $(s[curIndex .. ^1])
  of OIndent, OWrap:
    discard

  let
    maxIx = s.len()
    opps  = s.getBreakOpps()

  var
    lastBp:  int = 0
    newBp:   int
    width:   int
    oneWidh: int
    available = state.availableWidth

  while lastBp < maxIx:
    (newBp, width) = s.wrapOne(lastBp, maxIx, opps, available)
    result &= $(s[lastBp ..< newBp])
    if newBp < (maxIx - 1):
      result &= "\u2028"
    available = state.totalWidth
    lastBp    = newBp
    if state.getOverflow() == OIndent and available > state.getWrapIndent():
      let
        padChar = state.getLpadChar()
        padAmt  = state.getWrapIndent()

      result &= padChar.repeat(padAmt)
      available -= padChar.runeWidth()
    while lastBp < maxIx and s[lastBp].isWhiteSpace():
      lastBp += 1

  if not result.endswith("\u2028"):
    state.availableWidth = state.totalWidth - width

proc formatAtom(r: Rope, state: var FmtState): FormattedOutput =
  let pretext = r.text.wrapToWidth(r.length, state)
  result = FormattedOutput(contents: pretext.split(Rune(0x2028)),
                           finalBreak: false)

  for item in result.contents:
    let l = item.runeLength()
    if l > result.maxWidth:
      result.maxWidth = l
    result.lineWidths.add(l)

  var codes: seq[string]

  for i, line in result.contents:
    case state.getCasing()
    of CasingAsIs, CasingIgnore:
      discard
    of CasingLower:
      result.contents[i] = line.toLower()
    of CasingUpper:
      result.contents[i] = line.toUpper()
    of CasingTitle:
      var
        title = true
        res: string

      for rune in line.runes():
        if rune.isWhiteSpace():
          title = true
          res.add(rune)
          continue
        if title:
          res.add(rune.toTitle())
          title = false
        else:
          res.add(rune.toLower())
      result.contents[i] = res

    # We can't reuse 'line' down here because we may
    # have already replaced contents[i].
    case state.getUnderlineStyle()
    of UnderlineNone, UnderlineIgnore:
      discard
    of UnderlineSingle:
      if getUnicodeOverAnsi():
        var newres: string
        for ch in result.contents[i]:
          newres.add(ch)
          newres.add(Rune(0x0332))
        result.contents[i] = newres
      else:
        codes.add("4")
    of UnderlineDouble:
      codes.add("21")

    if state.getBold():
      codes.add("1")

    if state.getItalic():
      codes.add("3")

    if state.getInverse():
      codes.add("7")

    if state.getStrikethrough():
      if getUnicodeOverAnsi():
        var newRes: string
        for ch in result.contents[i]:
          newRes.add(ch)
          newRes.add(Rune(0x0336))
        result.contents[i] = newRes
      else:
        codes.add("9")

    let
      fgOpt = state.getFgColor()
      bgOpt = state.getBgColor()

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

    result.contents[i] = "\e[" & codes.join(";") & "m" &
      result.contents[i] & "\e[0m"

proc internalRopeToString(r: Rope, state: var FmtState): FormattedOutput

proc quickAtomFormat(s: string, l: int, state: var FmtState): string =
  let rope = Rope(kind: RopeAtom, text: s.toRunes(), length: l)

  return rope.internalRopeToString(state).contents[0]

# s here should be a number for ordered lists.
proc formatPaddedBullet(state: var FmtState, s = ""): (string, string, int) =
  let
      lpadChar  = state.getLpadChar()
      rpadChar  = state.getRpadChar()
      bullet    = state.getBulletChar().get(Rune(0x2022))
      lpad      = state.getLpad()
      rpad      = state.getRpad()
      totallen  = lpad + s.runeLength() + bullet.runeWidth() + rpad
      line1     = lpadChar.repeat(lpad) & s & $(bullet) & rpadChar.repeat(rpad)
      wrapLine  = lpadChar.repeat(totalLen)
      rope1     = Rope(kind: RopeAtom, text: line1.toRunes(), length: totallen)
      rope2     = Rope(kind: RopeAtom, text: wrapLine.toRunes(),
                       length: totallen)

  return (line1.quickAtomFormat(totallen, state),
          wrapLine.quickAtomFormat(totallen, state),
          totallen)

proc formatUnorderedList(r: Rope, state: var FmtState): FormattedOutput =
  state.withTag("ul"):
    var
      savedTW = state.totalWidth
      preStr:  string  # Really, first line str.
      wrapStr: string  # Remaining lines in container.
      preLen:  int

    (preStr, wrapStr, preLen) = state.formatPaddedBullet()
    state.totalWidth -= preLen
    for item in r.items:
      state.availableWidth = state.totalWidth
      var oneRes = item.internalRopeToString(state)
      for i, line in oneRes.contents:
        if i == 0:
          oneRes.contents[i] = preStr & line
        else:
          oneRes.contents[i] = wrapStr & line
        oneRes.lineWidths[i] = oneRes.lineWidths[i] + preLen
      oneRes.maxWidth += preLen

      combineFormattedOutput(result, oneRes)

    state.totalWidth       = savedTw
    result.startsWithBreak = true
    result.finalBreak      = true

proc getMaxUnwrappedWidthsPerColumn(r: Rope): seq[int] =
  # each of thead, tbody and tfoot have a RopeTableRows item that
  # contains a seq[Rope].
  #
  # Each of the ropes in thise requence is a RopeTableRow item, which
  # ALSO contains a seq[Rope] with individual cells.
  #
  # Right now, we are not paying any attention to column spans, etc.

  for part in [r.thead, r.tbody, r.tfoot]:
    if part == nil:
      continue

    let rows = part.cells

    for rowRope in rows:
      if rowRope == nil:
        continue
      let cells = rowRope.cells

      for i, cell in cells:
        let oneWidth = cell.largestWidthInRope()

        if len(result) == i:
          result.add(oneWidth)

        elif result[i] < oneWidth:
          result[i] = oneWidth

proc calculateColumnWidths(r: Rope, state: FmtState): seq[int] =
  let
    style       = state.getBoxStyle()
    widestLines = r.getMaxUnwrappedWidthsPerColumn()

  # We need to figure out how much horizontal padding the style demands.
  # For this, we need to know:
  #  a) If there's a border we're adding between columns (if not, we rely
  #     on internal pad)
  #  b) How many columns.
  #
  # We then add border.runeWidth() * (num_cols) - 1
  var
    availableSpace = state.totalWidth
    fullColumns    = 0
    numCols        = len(widestLines)

  if state.getUseVerticalSeparator():
    availableSpace -= style.vertical.runeWidth() * (numCols - 1)

  if state.getUseLeftBorder():
    availableSpace -= style.vertical.runeWidth()

  if state.getUseRightBorder():
    availableSpace -= style.vertical.runeWidth()

  for column in widestLines:
    result.add(bareMinimumColWidth + 2) # + 2 for forced padding.
    availableSpace -= (bareMinimumColWidth + 2)
    if bareMinimumColWidth >= (column + 2):
      fullColumns += 1

  # Now, add one character per column, until the column width is <=
  # widestLines, at which point we stop, even if we're not using the
  # whole width.
  while (fullColumns != len(widestLines)) and availableSpace > 0:
    for i in 0 ..< len(widestLines):
      if result[i] == (widestLines[i] + 2):
        continue
      result[i] += 1
      availableSpace -= 1
      if result[i] == (widestLines[i] + 2):
        fullColumns += 1
      if availableSpace == 0:
        break

proc formatOrderedList(r: Rope, state: var FmtState): FormattedOutput =
  var
    placeholder = ""
    maxDigits   = 0
    n           = len(r.items)

  while true:
    maxDigits  += 1
    n           = n div 10
    placeholder = placeholder & "0"
    if n == 0:
      break

  state.withTag("ol"):
    var
      savedTW   = state.totalWidth
      templ8:  string
      wrapStr: string
      prelen:  int

    (templ8, wrapStr, preLen) = state.formatPaddedBullet(placeholder)
    state.totalWidth -= prelen

    for n, item in r.items:
      state.availableWidth  = state.totalWidth

      var oneRes = item.internalRopeToString(state)
      for i, line in oneRes.contents:
        if i == 0:
          var
            nAsStr  = $(n + 1)
          while nAsStr.runeLen() != placeholder.runeLen():
            nAsStr = ' ' & nAsStr
          let
            prefix = templ8.replace(placeholder)

          oneRes.contents[i] = prefix & line
        else:
          oneRes.contents[i] = wrapStr & line
        oneRes.lineWidths[i] = oneRes.lineWidths[i] + preLen
      oneRes.maxWidth += preLen

      combineFormattedOutput(result, oneRes)

    state.totalWidth       = savedTw
    result.startsWithBreak = true
    result.finalBreak      = true

proc getEmptyCellOfWidth(w: int, state: var FmtState): FormattedOutput =
  let savedWidth = state.totalWidth
  state.totalWidth     = w
  state.availableWidth = w
  let
    s = Rune(' ').repeat(w).toRunes()
    r = Rope(style: state.curStyle, kind: RopeAtom, length: w,
               text: s)

  result = r.internalRopeToString(state)
  state.totalWidth     = savedWidth
  state.availableWidth = savedWidth

proc getEmptyLineOfWidth(w: int, state: var FmtState): string =
  let cell = getEmptyCellOfWidth(w, state)
  result = cell.contents[0]

proc formatRowsForOneTag(r: Rope, tagName: string, widths: seq[int],
                         state: var FmtState): seq[seq[FormattedOutput]] =
    var realTotalWidth = state.totalWidth

    # We automatically pad cells by enclosing them in a left alignment tag rn.
    if r == nil:
      return
    state.withTag(tagName):
      for i, inRow in r.cells:
        if inRow == nil: continue  # Shouldn't happen but jik
        var
          oneRow: seq[FormattedOutput] = @[]
          rowTagToUse                  = inrow.tag

        if (i and 0x01) == 0:
          if styleMap.contains(inrow.tag & ".even"):
            rowTagToUse = inrow.tag & ".even"
        else:
          if styleMap.contains(inrow.tag & ".odd"):
            rowTagToUse = inrow.tag & ".odd"

        state.withTag(rowTagToUse):
            for j, cell in inRow.cells:
                if cell == nil: continue
                var colTagToUse = cell.tag

                if (j and 0x01) == 0:
                  if styleMap.contains(cell.tag & ".even"):
                    colTagToUse = cell.tag & ".even"
                else:
                  if styleMap.contains(cell.tag & ".odd"):
                    colTagToUse = cell.tag & ".odd"

                # TODO: We need to add a style here NOT to wrap, but to collect
                # breakpoints along w/ the style at those breakpoints (which
                # would be cached in the atom).

                state.withTag(colTagToUse):
                  let curWidth         = widths[j] - 2 # Hardcode padding
                  state.totalWidth     = curWidth
                  state.availableWidth = state.totalWidth
                  var prePad           = cell.internalRopeToString(state)
                  for k, line in prePad.contents:
                      let
                        l = getEmptyLineOfWidth(1, state)
                        r = getEmptyLineOfWidth(1, state)
                      prePad.contents[k]    = l & line & r
                      prePad.lineWidths[k] += 2
                      if prePad.maxWidth < prePad.lineWidths[k]:
                          prePad.maxWidth = prePad.lineWidths[k]
                      prePad.startsWithBreak = true
                      prePad.finalBreak      = true

                  # Save the current style so we can format any blank lines.
                  prePad.tdStyleCache = state.curStyle

                  oneRow.add(prePad)

            var n = len(inRow.cells)
            while n < len(widths):
                oneRow.add(getEmptyCellOfWidth(widths[n], state))
                n += 1

        result.add(oneRow)

proc constructTopBorder(state: var FmtState, cwidths: seq[int],
                        style: BoxStyle): string =
  var
    topT       = ""
    horizontal = style.horizontal

  if state.getUseLeftBorder():
    result.add($(style.upperLeft))

  if state.getUseVerticalSeparator():
    topT = $(style.topT)

  for i, width in cwidths:
    result &= horizontal.repeat(width)
    if i != len(cwidths) - 1:
      result &= topT

  if state.getUseRightBorder():
    result.add($(style.upperRight))

proc constructRowSep(state: var FmtState, cwidths: seq[int], style: BoxStyle):
                    string =
  var
    cross      = ""
    horizontal = style.horizontal

  if state.getUseLeftBorder():
    result.add($(style.leftT))

  if state.getUseVerticalSeparator():
    cross = $(style.cross)

  for i, width in cwidths:
    result &= horizontal.repeat(width)
    if i != len(cwidths) - 1:
      result &= cross

  if state.getUseRightBorder():
    result.add($(style.rightT))

proc constructBottomBorder(state: var FmtState, cwidths: seq[int],
                           style: BoxStyle): string =
  var
    bottomT    = ""
    horizontal = style.horizontal

  if state.getUseLeftBorder():
    result.add($(style.lowerLeft))

  if state.getUseVerticalSeparator():
    bottomT = $(style.bottomT)

  for i, width in cwidths:
    result &= horizontal.repeat(width)
    if i != len(cwidths) - 1:
      result &= bottomT

  if state.getUseRightBorder():
    result.add($(style.lowerRight))


proc `$`(x: FormattedOutput): string =
  return $(x.contents)

proc formatTable(r: Rope, state: var FmtState): FormattedOutput =
    let
      colWidths          = r.calculateColumnWidths(state)
      fullAvailableWidth = state.totalWidth
      boxStyle           = state.getBoxStyle()
      verticalBorder     = $(boxStyle.vertical)

    var cellContents: seq[seq[FormattedOutput]]

    cellContents  = r.thead.formatRowsForOneTag("thead", colWidths, state)
    cellContents &= r.tbody.formatRowsForOneTag("tbody", colWidths, state)
    cellContents &= r.tfoot.formatRowsForOneTag("tfoot", colWidths, state)

    # What we do have are a bunch of perfectly aligned and formatted
    # individual cells.  We now need to slap them together, along with
    # any borders that need doing.
    #
    # First, we will go row by row, and pad all cell heights to the
    # same value.  Then, we will add in vertical borders to each cell
    # in that row. Then, we combine the cells in the row, and stick
    # the result into mergedRows.
    var mergedRows: seq[FormattedOutput] = @[]

    for rownum, row in cellContents:
      var rowHeight: int = 1
      # Inner Loop 1, calculate row height.
      for item in row:
        let l = item.contents.len()
        if  l > rowHeight:
          rowHeight = l

      # Inner Loop 2, go back through and pad the text for any row we
      # added.  Look to the first row for the style. If they managed
      # to sneak in a totally empty row, then oh well.
      for cellnum, item in row:
        let style = if item.contents.len() != 0:
                      item.tdStyleCache
                    else:
                      state.curStyle
        state.withStyle(style):
          for lineno in 0 ..< cellContents[rownum][cellnum].contents.len():
            var diff = colWidths[cellnum]
            diff -= cellContents[rownum][cellnum].lineWidths[lineno]
            if diff > 0:
              let s = getEmptyLineOfWidth(diff, state)
              cellContents[rownum][cellnum].contents[lineno]   &= s
              cellContents[rownum][cellnum].lineWidths[lineno] += diff

          while cellContents[rownum][cellnum].contents.len() < rowHeight:
            # item isn't mutable directly via the iterator?
            let s = getEmptyLineOfWidth(colWidths[cellnum], state)
            cellContents[rownum][cellnum].contents.add(s)
            cellContents[rownum][cellnum].lineWidths.add(colWidths[cellnum])

      # We could merge w/ the above loop but don't for clarity.  Here,
      # we add interior vertical borders to the table, if they're turned
      # on.
      if state.getUseVerticalSeparator():
        var newLines: string

        for colnum, item in cellContents[rownum]:
          if (colnum + 1) == len(cellContents[rownum]):
            break
          for k, line in item.contents:
            cellContents[rownum][colnum].contents[k]    = line & verticalBorder
            cellContents[rownum][colnum].lineWidths[k] += 1

      # Now, we combine all the cells in the whole row into a single
      # FormattedOutput object.  Start with column 0's info and append to it.
      var thisRow = cellContents[rownum][0]
      for colnum in 1 ..< cellContents[rownum].len():
        let nextCell = cellContents[rownum][colnum]
        for k, line in nextCell.contents:
          thisRow.contents[k]   &= line
          thisRow.lineWidths[k] += nextCell.lineWidths[k]
      # Now, we're going to add borders to the left and right if
      # they're desired.
      let
        useLeft  = state.getUseLeftBorder()
        useRight = state.getUseRightBorder()
      if useLeft or useRight:
        let
          leftc  = if useLeft:  verticalBorder else: ""
          rightc = if useRight: verticalBorder else: ""

        for i, line in thisRow.contents:
          thisRow.contents[i] = leftc & line & rightc

      # Fix up other values, then add row[0] to merged rows
      thisRow.maxWidth        = fullAvailableWidth
      thisRow.startsWithBreak = true
      thisRow.finalBreak      = true

      mergedRows.add(thisRow)


    # At this point, mergedRows are a bunch of individual row objects.
    # We need to add horizontal borders, and combine all the row
    # objects into a single object.
    var
      rowSep:       string
      bottomBorder: string

    if state.getUseTopBorder():
      let topBorder = state.constructTopBorder(colWidths, boxStyle)
      result.contents.add(topBorder)
      result.lineWidths.add(fullAvailableWidth)

    if state.getUseHorizontalSeparator():
      let rowSep = state.constructRowSep(colWidths, boxStyle)

      for item in mergedRows[0 ..< ^1]:
        result.contents   &= item.contents
        result.lineWidths &= item.lineWidths
        result.contents.add(rowSep)
        result.lineWidths.add(fullAvailableWidth)

      if len(mergedRows) != 0:
        result.contents   &= mergedRows[^1].contents
        result.lineWidths &= mergedRows[^1].lineWidths
    else:
      for item in mergedRows:
        result.contents   &= item.contents
        result.lineWidths &= item.lineWidths

    if state.getUseBottomBorder():
      bottomBorder = state.constructBottomBorder(colWidths, boxStyle)
      result.contents.add(bottomBorder)
      result.lineWidths.add(fullAvailableWidth)

    # TODO: Format the caption, if any.
    # Yes, we're currently ignoring the caption. The horrors!

    # Step the last is to set state to reflect we always fully break
    # around tables.
    state.totalWidth       = fullAvailableWidth
    state.availableWidth   = state.totalWidth
    result.maxWidth        = state.totalWidth
    result.startsWithBreak = true
    result.finalBreak      = true

proc internalRopeToString(r: Rope, state: var FmtState): FormattedOutput =
  if r == nil:
    return FormattedOutput(contents: @[], maxWidth: 0, lineWidths: @[])

  case r.kind
  of RopeAtom:
    r.setAtomLength()
    result = r.formatAtom(state)
  of RopeBreak:
    if r.breakType == BrPage:
      result = FormattedOutput(contents: @["\f"], maxWidth: 0,
                               lineWidths: @[0], finalBreak: true)
    elif r.breakType == BrParagraph:
      result = FormattedOutput(contents: @[""], maxWidth: 0,
                               lineWidths: @[0], finalBreak: true)
    else:
      result = FormattedOutput(contents: @[""], maxWidth: 0,
                               lineWidths: @[0], finalBreak: true)

    state.availableWidth = state.totalWidth

    if r.guts != nil:
      let sub = r.guts.internalRopeToString(state)
      combineFormattedOutput(result, sub)

  of RopeFgColor:
    if getShowColor():
      state.withStyle(FmtStyle(textColor: some(r.color))):
        result = r.toColor.internalRopeToString(state)
    else:
      result = r.toColor.internalRopeToString(state)
  of RopeBgColor:
    if getShowColor():
      state.withStyle(FmtStyle(bgColor: some(r.color))):
        result = r.toColor.internalRopeToString(state)
    else:
      result = r.toColor.internalRopeToString(state)
  of RopeList:
    if r.tag == "ol":
      result = r.formatOrderedList(state)
    else:
      result = r.formatUnorderedList(state)

  of RopeAlignedContainer:
    case r.tag[0]
    of 'r':
      result = r.contained.internalRopeToString(state)
      for i, line in result.contents:
        let w = state.totalWidth - result.lineWidths[i]
        if w > 0:
          var
            padRope = Rope(kind: RopeAtom, text: Rune(' ').repeat(w).toRunes(),
                           length: w)
            padRes  = padRope.internalRopeToString(state)
            padStr  = if len(padRes.contents) > 0:
                        padRes.contents[0]
                      else:
                        ""

          result.contents[i]   = padStr & line
          result.lineWidths[i] = state.totalWidth

      state.availableWidth = 0
    of 'c':
      result = r.contained.internalRopeToString(state)
      for i, line in result.contents:
        let w = state.totalWidth - result.lineWidths[i]
        if w > 0:
          let
            len1     = w div 2
            len2     = if (w and 0x01) == 1: len1 + 1 else: len1
            lbase    = Rune(' ').repeat(len1).toRunes()
            rbase    = Rune(' ').repeat(len2).toRunes()
            lpadRope = Rope(kind: RopeAtom, text: lbase, length: len1)
            rpadRope = Rope(kind: RopeAtom, text: rbase, length: len2)
            lpadRes  = lpadRope.internalRopeToString(state)
            rpadRes  = rpadRope.internalRopeToString(state)
            lpadStr  = if len(lpadRes.contents) > 0:
                         lpadRes.contents[0]
                       else:
                         ""
            rpadStr  = if len(rpadRes.contents) > 0:
                         rpadRes.contents[0]
                       else:
                         ""

          result.contents[i]   = lpadStr & line & rpadStr
          result.lineWidths[i] = state.totalWidth
      state.availableWidth = 0
    of 'l':
      result = r.contained.internalRopeToString(state)
      for i, line in result.contents:
        let w = state.totalWidth - result.lineWidths[i]
        if w > 0:
          var
            padRope = Rope(kind: RopeAtom, text: Rune(' ').repeat(w).toRunes(),
                           length: w)
            padRes  = padRope.internalRopeToString(state)
            padStr  = if len(padRes.contents) > 0:
                        padRes.contents[0]
                      else:
                        ""

          result.contents[i]   = line & padStr
          result.lineWidths[i] = state.totalWidth
      state.availableWidth = 0

    else:
      discard
  of RopeLink:
    result = r.toHighLight.internalRopeToString(state)
  of RopeTaggedContainer:
    var newStyle: FmtStyle
    case r.tag
    of "s", "strikethrough", "strikethru":
      newStyle = FmtStyle(strikethrough: some(true))
    of "i", "italic":
      newStyle = FmtStyle(italic: some(true))
    of "u", "underline":
      newStyle = FmtStyle(underlineStyle: some(UnderlineSingle))
    of "b", "bold":
      newStyle = FmtStyle(bold: some(true))
    of "other":
      raise newException(ValueError, "Not implemented yet.")
    else:
      discard

    if r.tag in breakingStyles:
      state.availableWidth = state.totalWidth

    state.withStyleAndTag(newStyle, r.tag):
      result = r.contained.internalRopeToString(state)

    if r.tag in breakingStyles:
      result.startsWithBreak = true
      result.finalBreak      = true
  of RopeTable:
    state.withTag("table"):
      result = r.formatTable(state)
  else:
    discard

  if r.next != nil:
    let next = r.next.internalRopeToString(state)
    combineFormattedOutput(result, next)

proc stylize*(r: Rope, stripFront = false, stripEnd = false, width = -1): string =
  var
    curState: FmtState

  if width <= 0:
    let tw = terminalWidth()
    if tw > 0:
      curState.totalWidth = tw
    else:
      curState.totalWidth = defaultTextWidth

  if curState.totalWidth < 0:
    curState.totalWidth = defaultTextWidth

  curState.availableWidth = curState.totalWidth
  curState.curStyle       = defaultStyle

  let preResult = r.internalRopeToString(curstate)
  result = preResult.contents.join("\n")
  if '\f' in result:
    result = result.replace("\f\n", "\f")

  if stripFront and stripEnd:
    result = result.strip()
  elif stripEnd:
    result = result.strip(leading = false)
  elif stripFront:
    result = result.strip(trailing = false)
  elif result.len() != 0 and result[^1] != '\n':
    result &= "\n"

proc print*(r: Rope = nil, file = stdout, stripFront = false, stripEnd = false,
                                                       width = -1) =
  if r == nil:
    echo ""
  else:
    file.write(stylize(r, stripFront, stripEnd, width))
