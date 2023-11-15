## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

# TODO:
#
# 1) There's a padding bug that I haven't been able to find. There's a
#    very small note in the code where I work around it in
#    applyLeftRightPadding noting it's presence. I've got another
#    branch where I did fix the issue, but the branches have diverged
#    a lot and cannot for the life of me find the issue even w/ that.
#
# 2) Support column spans.
#
# 3) Support absolute column sizes (right now if specified it's pct, and
#    if it's not every column is sized evenly).
#
# 4) Fix jusfication and add <justify/> and <full/> tags.
#
# Plus there are definitely plenty of little bits I haven't made work,
# like almost anything that not gets done in a style sheet that could
# be an attribute.
#
# There are also probably many subtleties I've overlooked too...
#
# Oh, and this doesn't matter for chalk, but I'm currently making a
# single-threaded assumption until I bring in my lock-free hash
# tables.

import tables, options, unicodedb/properties, std/terminal, rope_base,
       rope_styles, unicodeid, unicode, misc

type
  RenderBoxKind* = enum RbText, RbBoxes

  RenderBox* = ref object
    contents*:   TextPlane
    tmargin*:    int
    bmargin*:    int
    width*:      int

  FmtState = object
    totalWidth:   int
    showLinkTarg: bool
    curStyle:     FmtStyle
    styleStack:   seq[uint32]
    colStack:     seq[seq[int]]
    colorStack:   seq[bool]
    nextRope:     Rope
    savedRopes:   seq[Rope]
    processed:    seq[Rope] # For text items b/c I have a bug :/
    tableEven:    seq[bool]

proc `$`*(box: RenderBox): string =
    result &= $(box.contents)
    result &= "\n"

template styleRunes(state: FmtState, runes: seq[uint32]): seq[uint32] =
  @[state.curStyle.getStyleId()] & runes & @[StylePop]

proc applyCurrentStyleToPlane*(state: FmtState, p: TextPlane) =
  for i in 0 ..< p.lines.len():
    p.lines[i] = state.styleRunes(p.lines[i])

template pad(state: FmtState, w: int): seq[uint32] =
  state.styleRunes(uint32(Rune(' ')).repeat(w))

proc noBoxRequired*(r: Rope): bool =
  ## Generally, this call is only meant to be used either internally,
  ## or by a renderer (the ansi renderer being the only one we
  ## currently have).
  ##
  ## Returns true if we have paragraph text that does NOT require any
  ## sort of box... so no alignment, padding, tables, lists, ...
  ##
  ## However, we DO allow break objects, as they don't require boxing,
  ## so it isn't quite non-breaking text.

  # This will be used to test containers that may contain some basic
  # content, some not.

  var subItem: Rope

  case r.kind
  of RopeList, RopeAlignedContainer, RopeTable, RopeTableRow, RopeTableRows:
    return false
  of RopeAtom, RopeLink:
    return true
  of RopeFgColor, RopeBgColor:
    # If our contained item is basic, we need to check the
    # subsequent items too.
    # Assign to subItem and drop down to the loop below.
    subItem = r.toColor
  of RopeBreak:
    return r.guts == Rope(nil)
  of RopeTaggedContainer:
    if r.tag in breakingStyles:
      return false
    subItem = r.contained

  while subItem != Rope(nil):
    if not subItem.noBoxRequired():
      return false
    subItem = subItem.next

  return true

proc unboxedRunelength*(r: Rope): int =
  ## Returns the approximate display-width of a rope, without
  ## considering the size of 'box' we're going to try to fit it into.
  ##
  ## That is, this call returns how many characters of fixed-sized
  ## width we think we need to render the given rope.
  ##
  ## Note that we cannot ultimately know how a terminal will render a
  ## given string, especially when it comes to Emoji. Under the hood,
  ## we do our best, but stick to expected values provided in the
  ## Unicode standard. But there may occasionally be length
  ## calculation issues due to local fonts, etc.

  if r == Rope(nil):
    return 0
  case r.kind
  of RopeAtom:
    return cast[seq[uint32]](r.text).u32LineLength() +
                             r.next.unboxedRuneLength()
  of RopeLink:

    result = r.url.runeLength() + r.toHighlight.unboxedRuneLength() +
             r.next.unboxedRuneLength()
  of RopeTaggedContainer:
    if r.tag in breakingStyles:
      return 0
    result = r.contained.unBoxedRuneLength() + r.next.unboxedRuneLength()
  of RopeFgColor, RopeBgColor:
    result = r.toColor.unBoxedRuneLength() + r.next.unboxedRuneLength()
  else:
    return 0

template runelength*(r: Rope): int = r.unboxedRuneLength()

proc applyAlignment(state: FmtState, box: RenderBox, w: int) =
  for i in 0 ..< box.contents.lines.len():
    let
      toFill =  w - box.contents.lines[i].u32LineLength()

    if toFill <= 0:
      continue
    case state.curStyle.alignStyle.getOrElse(AlignIgnore)
    of AlignL:
      box.contents.lines[i] &= state.pad(toFill)
    of AlignR:
      box.contents.lines[i] = state.pad(toFill) & box.contents.lines[i]
    of AlignC:
      var
        leftAmt = toFill div 2
        toAddL  = state.pad(leftAmt)
        toAddR  = if w mod 2 != 0: state.pad(leftAmt + 1) else: toAddL
      box.contents.lines[i] = toAddL & box.contents.lines[i] & toAddR

    of AlignF:
      box.contents.lines[i] = justify(box.contents.lines[i], w)
    of AlignJ:
      if i == len(box.contents.lines) - 1:
        for j in 0 ..< toFill:
          box.contents.lines[i].add(state.pad(1))
      else:
        box.contents.lines[i] = justify(box.contents.lines[i], w)
    else:
      discard

proc applyLeftRightPadding(state: FmtState, box: RenderBox, w: int) =
  var
    lpad    = state.curStyle.lpad.getOrElse(0)
    rpad    = state.curStyle.rpad.getOrElse(0)
    lpadTxt = state.pad(lpad)
    rpadTxt = state.pad(rpad)
    extra: seq[uint32]

  for i in 0 ..< len(box.contents.lines):
    var toFill = (w - box.contents.lines[i].u32LineLength())
    extra = state.pad(toFill)
    box.contents.lines[i] = lpadTxt & box.contents.lines[i] & rpadTxt & extra
    # There's a bug if this is needed.
    box.contents.lines[i] = box.contents.lines[i].truncateToWidth(w)

proc alignAndPad(state: FmtState, box: RenderBox) =
  let
    lpad    = state.curStyle.lpad.getOrElse(0)
    rpad    = state.curStyle.rpad.getOrElse(0)

  state.applyAlignment(box, state.totalWidth - (lpad - rpad))
  state.applyLeftRightPadding(box, state.totalWidth)

proc collapseColumn(state: FmtState, boxes: seq[RenderBox]): RenderBox =
  ## Combine renderboxes at the same level into one renderbox.  These
  ## boxes are expected to all be the same width after padding, and
  ## each contain only a single TextPlane, but margins between these
  ## need to be respected.

  var plane: TextPlane = TextPlane()
  let
    style   = state.curStyle
    lineLen = state.totalWidth - style.lpad.get(0) - style.rpad.get(0)
    blank   = state.pad(lineLen)
    tmargin = if boxes.len() != 0: boxes[0].tmargin  else: 0
    bmargin = if boxes.len() != 0: boxes[^1].bmargin else: 0

  for i, box in boxes:
    if i != 0:
      for j in 0 ..< box.tmargin:
        plane.lines.add(blank)

    plane.lines &= box.contents.lines

    if i != len(boxes) - 1:
      for j in 0 ..< box.bmargin:
        plane.lines.add(blank)

  result = RenderBox(contents: plane, tmargin: tmargin, bmargin: bmargin)

proc collapsedBoxToTextPlane(state: FmtState, box: RenderBox,
                             outerPad = true): TextPlane =
  result       = box.contents
  result.width = box.width
  if outerPad:
    for i in 0 ..< box.tmargin:
      result.lines = @[state.pad(result.width)] & result.lines
    for i in 0 ..< box.bmargin:
      result.lines &= @[state.pad(result.width)]

proc pushTableWidths(state: var FmtState, widths: seq[int]) =
  state.colStack.add(widths)

proc popTableWidths(state: var FmtState) =
  discard state.colStack.pop()

proc pushStyle(state: var FmtState, style: FmtStyle): uint32 {.discardable.} =
  result = style.getStyleId()
  state.styleStack.add(result)
  state.curStyle = style

proc popStyle(state: var FmtState) =
  discard state.styleStack.pop()
  if state.styleStack.len() != 0:
    state.curStyle = state.styleStack[^1].idToStyle()
  else:
    state.curStyle = defaultStyle

proc getNewStartStyle(state: FmtState, r: Rope,
                      otherTag = ""): Option[FmtStyle] =
  # First, apply any style object associated with the rope's html tag.
  # Second, if the rope has a class, apply any style object associated w/ that.
  # Third, do the same w/ ID.
  # Finally, if the rope itself has a specified style, it takes
  # precedence.
  var
    styleChange = false
    newStyle    = state.curStyle

  if otherTag != "" and otherTag in styleMap:
    styleChange = true
    newStyle = newStyle.mergeStyles(styleMap[otherTag])
  elif r != nil and r.tag != "" and r.tag in styleMap:
    styleChange = true
    newStyle = newStyle.mergeStyles(styleMap[r.tag])
  if r != nil and r.class != "" and r.class in perClassStyles:
    styleChange = true
    newStyle = newStyle.mergeStyles(perClassStyles[r.class])
  if r != nil and r.id != "" and r.id in perIdStyles:
    styleChange = true
    newStyle = newStyle.mergeStyles(perIdStyles[r.id])

  if r != nil and r.kind == RopeFgColor:
    styleChange = true
    newStyle = newStyle.mergeStyles(FmtStyle(textColor: some("")))
  elif r != nil and r.kind == RopeBgColor:
    styleChange = true
    newStyle = newStyle.mergeStyles(FmtStyle(bgColor: some("")))

  if styleChange:
    return some(newStyle)

template boxContent(state: var FmtState, style: FmtStyle, symbol: untyped,
                    code: untyped) =
  state.pushStyle(style)

  let
    lpad     = style.lpad.getOrElse(0)
    rpad     = style.rpad.getOrElse(0)
    p        = lpad + rpad

  state.totalWidth -= p
  code
  state.totalWidth += p

  for item in symbol:
    if style.tmargin.isSome():
      item.tmargin = style.tmargin.get()
    if style.bmargin.isSome():
      item.bmargin = style.bmargin.get()

  let collapsed = state.collapseColumn(symbol)
  state.alignAndPad(collapsed)
  state.popStyle()

  symbol = @[collapsed]

template fmtBox(styleTweak: Option[FmtStyle], code: untyped) =
  var style: FmtStyle

  if styleTweak.isSome():
    style = state.curStyle.mergeStyles(styleTweak.get())
  else:
    style = state.curStyle
  state.boxContent(style, result, code)

template taggedBox(tag: string, code: untyped) =
  let
    styleOpt   = state.getNewStartStyle(r, tag)
    style      = styleOpt.getOrElse(state.curStyle)
    lpad       = style.lpad.getOrElse(0)
    rpad       = style.rpad.getOrElse(0)
    p          = lpad + rpad

  state.pushStyle(style)

  state.totalWidth -= p
  code
  state.totalWidth += p
  for item in result:
    if style.tmargin.isSome():
      item.tmargin = style.tmargin.get()
    if style.bmargin.isSome():
      item.bmargin = style.bmargin.get()

  let collapsed = state.collapseColumn(result)
  state.alignAndPad(collapsed)
  state.popStyle()

  result = @[collapsed]

template withStyle(tag: string, code: untyped) =
  let
    styleOpt   = state.getNewStartStyle(nil, tag)
    style      = styleOpt.getOrElse(state.curStyle)

  state.pushStyle(style)
  code
  state.popStyle()

template withWidth(w: int, code: untyped) =
  let oldWidth = state.totalWidth

  if w < oldwidth:
    state.totalWidth = w

  code

  state.totalWidth = oldWidth


template standardBox(code: untyped) =
  taggedBox("", code)

proc preRender*(state: var FmtState, r: Rope): seq[RenderBox]

proc preRenderUnorderedList(state: var FmtState, r: Rope): seq[RenderBox] =
  standardBox:
    let
      bulletChar = state.curStyle.bulletChar.getOrElse(Rune(0x2022))
      bullet     = state.styleRunes(@[uint32(bulletChar)])
      bulletLen  = bullet.u32LineLength()
      hangPrefix = state.styleRunes(state.pad(bulletLen))
    var
      subedWidth = true

    if bullet.u32LineLength() < state.totalWidth:
      state.totalWidth -= bulletLen
    else:
      subedWidth = false

    for n, item in r.items:
      var oneItem = state.preRender(item)[0]

      for i in 0 ..< oneItem.contents.lines.len():
        if i == 0:
          oneItem.contents.lines[0] = bullet & oneItem.contents.lines[0]
        else:
          oneItem.contents.lines[i] = hangPrefix & oneItem.contents.lines[i]

      result.add(oneItem)

    if subedWidth:
      state.totalWidth += bulletLen

proc toNumberBullet(state: FmtState, n, maxdigits: int): seq[uint32] =
  # Formats a number n that's meant to be in a bulleted list, where the
  # left is padded if the number is smaller than the max digits for a
  # bullet number, and the right gets any explicit bullet character
  # (such as a dot or right paren.)
  let codepoints = toRunes($(n))

  let pad = state.pad(maxdigits - len(codepoints))
  result &= cast[seq[uint32]](codepoints)

  if state.curStyle.bulletChar.isSome():
    result.add(uint32(state.curStyle.bulletChar.get()))

  result = pad & state.styleRunes(result)

proc preRenderOrderedList(state: var FmtState, r: Rope): seq[RenderBox] =
  standardBox:
    var
      hangPrefix:  seq[uint32]
      maxDigits  = 0
      n          = len(r.items)
      subedWidth = true

    while true:
      maxDigits += 1
      n          = n div 10
      hangPrefix.add(uint32(Rune(' ')))
      if n == 0:
        break

    if state.curStyle.bulletChar.isSome():
      hangPrefix &= state.pad(state.curStyle.bulletChar.get().runeWidth())

    hangPrefix = state.styleRunes(hangPrefix)

    if hangPrefix.len() < state.totalWidth:
      state.totalWidth -= hangPrefix.len()
    else:
      subedWidth = false

    for n, item in r.items:
      var oneItem = state.preRender(item)[0]
      let
        bulletText = state.toNumberBullet(n + 1, maxDigits)
        styled     = state.styleRunes(bulletText)

      oneItem.contents.lines[0] = styled & oneItem.contents.lines[0]
      for i in 1 ..< oneItem.contents.lines.len():
        oneItem.contents.lines[i] = hangPrefix & oneItem.contents.lines[i]

      result.add(oneItem)

    if subedWidth:
      state.totalWidth += hangPrefix.len()

proc percentToActualColumns(state: var FmtState, pcts: seq[int]): seq[int] =
  if len(pcts) == 0: return

  let style    = state.curStyle
  var overhead = 0

  if style.useLeftBorder.getOrElse(false):
    overhead += 1
  if style.useRightBorder.getOrElse(false):
    overhead += 1
  if style.useVerticalSeparator.getOrElse(false):
    overhead += (len(pcts) - 1)

  let availableWidth = state.totalWidth - overhead

  for item in pcts:
    var colwidth = (item * availableWidth) div 100
    result.add(if colwidth == 0: 1 else: colwidth)

proc getGenericBorder(state: var FmtState, colWidths: seq[int],
                      style: FmtStyle, horizontal: Rune,
                      leftBorder: Rune, rightBorder: Rune,
                      sep: Rune): RenderBox =
  withStyle("tborder"):
    let
      useLeft  = style.useLeftBorder.getOrElse(false)
      useRight = style.useRightBorder.getOrElse(false)
      useSep   = style.useVerticalSeparator.getOrElse(false)

    var
      plane = TextPlane(lines: @[@[]])

    if useLeft:
      plane.lines[0] &= @[uint32(leftBorder)]

    for i, width in colWidths:
      for j in 0 ..< width:
        withStyle("table"):
          plane.lines[0].add(uint32(horizontal))
      if useSep and i != len(colWidths) - 1:
        plane.lines[0].add(uint32(sep))

    if useRight:
      plane.lines[0].add(uint32(rightBorder))
      plane.lines[0] = state.styleRunes(plane.lines[0])

    result = RenderBox(contents: plane)

proc getTopBorder(state: var FmtState, s: BoxStyle): RenderBox =
  result = state.getGenericBorder(state.colStack[^1], state.curStyle,
           s.horizontal, s.upperLeft, s.upperRight, s.topT)

proc getHorizontalSep(state: var FmtState, s: BoxStyle): RenderBox =
  result = state.getGenericBorder(state.colStack[^1], state.curStyle,
           s.horizontal, s.leftT, s.rightT, s.cross)

proc getBottomBorder(state: var FmtState, s: BoxStyle): RenderBox =
  result = state.getGenericBorder(state.colStack[^1], state.curStyle,
           s.horizontal, s.lowerLeft, s.lowerRight, s.bottomT)

proc preRenderTable(state: var FmtState, r: Rope): seq[RenderBox] =
  taggedBox("table"):
   taggedBox("tborder"):
    var
      colWidths: seq[int]
      boxStyle  = state.curStyle.boxStyle.getOrElse(DefaultBoxStyle)

    if r.colInfo.len() != 0:
      var
        sum:              int
        defaultWidthCols: int

      for item in r.colInfo:
        for i in 0 ..< item.span:
          colWidths.add(item.widthPct)
          if item.widthPct == 0:
            defaultWidthCols += 1
          else:
            sum += item.widthPct

      # If sum < 100 then we divide remaining width equally.
      if defaultWidthCols != 0 and sum < 100:
        let defaultWidth = (100 - sum) div defaultWidthCols

        if defaultWidth > 0:
          for i, width in colWidths:
            if width == 0:
              colWidths[i] = defaultWidth

      # For anything still 0 or 1, we set it to a minimum width of 2. It
      # might result in us getting cropped.
      for i, width in colWidths:
        if width < 2:
          colWidths[i] = 2

    state.pushTableWidths(state.percentToActualColumns(colWidths))

    if r.thead != Rope(nil):
      result &= state.preRender(r.thead)
    if r.tbody != Rope(nil):
      result &= state.preRender(r.tbody)
    if r.tfoot != Rope(nil):
      result &= state.preRender(r.tfoot)

    var
      topBorder = state.getTopBorder(boxStyle)
      midBorder = state.getHorizontalSep(boxStyle)
      lowBorder = state.getBottomBorder(boxStyle)

    if state.curStyle.useHorizontalSeparator.getOrElse(false):
      var newBoxes: seq[RenderBox]

      for i, item in result:
        newBoxes.add(item)
        if (i + 1) != len(result):
          newBoxes.add(midBorder)

      result = newBoxes

    if state.curStyle.useBottomBorder.getOrElse(false):
      result.add(lowBorder)

    if state.curStyle.useTopBorder.getOrElse(false):
      result = @[topBorder] & result

    state.popTableWidths()
    if r.caption != Rope(nil):
      result &= state.preRender(r.caption)

proc emptyTableCell(state: var FmtState): seq[RenderBox] =
  var styleId: uint32
  # This probably should use "th" if we are in thead, but hey,
  # don't give us empty cells.
  if "td" in styleMap:
    styleId = state.curStyle.mergeStyles(styleMap["td"]).getStyleId()
  else:
    styleId = state.curStyle.getStyleId()

  let pane = TextPlane(lines: @[@[styleId, StylePop]])

  return @[ RenderBox(width: state.totalWidth, contents: pane) ]

proc adjacentCellsToRow(state: var FmtState, cells: seq[TextPlane],
                        widths: seq[int]): TextPlane =
  var
    style    = state.curStyle
    boxStyle = style.boxStyle.getOrElse(DefaultBoxStyle)
    leftBorder:  seq[uint32]
    sep:         seq[uint32]
    rightBorder: seq[uint32]
    rowLines:    int

  if style.useLeftBorder.getOrElse(false):
    leftBorder = state.styleRunes(@[uint32(boxStyle.vertical)])

  if style.useRightBorder.getOrElse(false):
    rightBorder = state.styleRunes(@[uint32(boxStyle.vertical)])

  if style.useVerticalSeparator.getOrElse(false):
    sep = state.styleRunes(@[uint32(boxStyle.vertical)])

  # Determine how many text lines high this row is by examining the
  # height of each cell.
  for col in cells:
    let l = col.lines.len()
    if l > rowLines:
      rowLines = l

  # Any cells not of the max height, pad them with spaces.
  # Carry over the start / end style from the first line.
  for i, col in cells:
    if col.lines.len() < rowLines:
      var blankLine = uint32(Rune(' ')).repeat(widths[i])
      let l = col.lines
      if l.len() > 0 and l[0].len() >= 1 and l[0][0] > 0x01ffff:
        blankLine = @[l[0][0]] & blankLine & @[StylePop]

      while col.lines.len() < rowLines:
        col.lines.add(blankLine)

  # Now we go left to right, line-by-line and assemble the result.  We
  # do this by mutating boxes[0]'s state; we'll end up returning it.
  for n in 0 ..< rowLines:
    if len(cells) == 1:
      cells[0].lines[n] = leftBorder & cells[0].lines[n]
    else:
      cells[0].lines[n] = leftBorder & cells[0].lines[n] & sep

  for i, col in cells[1 .. ^1]:
    for n in 0 ..< rowLines:
      cells[0].lines[n] &= col.lines[n]
      if i < len(cells) - 2:
        cells[0].lines[n] &= sep

  if len(rightBorder) != 0:
    for n in 0 ..< rowLines:
      cells[0].lines[n] &= rightBorder

  result = cells[0]

proc preRenderRow(state: var FmtState, r: Rope): seq[RenderBox] =
  # This is the meat of the table implementation.
  # 1) If the table colWidths array is 0, then we need to
  #    set it based on our # of columns.
  # 2) Pre-render the individual cells to the required width.
  #    This will return a seq[RenderBox]
  # 3) Flatten into a TextPlane.
  # 4) Combine the textplanes horizontally, adding vertical borders.
  #
  # This will result in our table being one TextPlane in a single
  # RenderBox.
  var tag = if state.tableEven[^1]: "tr.even" else: "tr.odd"

  taggedBox(tag):
    var
      widths = state.colStack[^1]

    # Step 1, make sure col widths are right
    if widths.len() == 0:
      state.popTableWidths()
      let pct = 100 div len(r.cells)
      for i in 0 ..< len(r.cells):
        widths.add(pct)
      widths = state.percentToActualColumns(widths)
      state.pushTableWidths(widths)

    var
      cellBoxes: seq[RenderBox]
      rowPlanes: seq[TextPlane]
      savedWidth = state.totalWidth

    # This loop does steps 2-3
    for i, width in widths:
      # Step 2, pre-render the cell.
      if i >= len(r.cells):
        cellBoxes = state.emptyTableCell()
      else:
        state.totalWidth = width
        cellBoxes = state.preRender(r.cells[i])

      for cell in cellBoxes:
        cell.tmargin = 0
        cell.bmargin = 0
      let boxes = state.collapseColumn(cellBoxes)
      rowPlanes.add(state.collapsedBoxToTextPlane(boxes))

  # Step 4, Combine the cells horizontally into a single RbText
  # object. This involves adding any vertical borders, and filling
  # in any blank lines if individual cells span multiple lines.
  let resPlane     = state.adjacentCellsToRow(rowPlanes, widths)
  result           = @[RenderBox(contents: resPlane, width: savedWidth)]
  state.totalWidth = savedWidth

proc preRenderRows(state: var FmtState, r: Rope): seq[RenderBox] =
  # Each row returns a single item.
  state.tableEven.add(false)
  for item in r.cells:
    result &= state.preRender(item)
    state.tableEven.add(not state.tableEven.pop())
  discard state.tableEven.pop()

proc addRunesToExtraction(extraction: TextPlane, runes: seq[Rune]) =
  if extraction.lines.len() == 0:
    extraction.lines = @[@[]]

  if Rune('\n') notin runes:
    extraction.lines[^1] &= cast[seq[uint32]](runes)
  else:
    for rune in runes:
      if rune == Rune('\n'):
        extraction.lines.add(@[])
      else:
        extraction.lines[^1].add(uint32(rune))

template addRunesToExtraction(extraction: TextPlane,
                              runes:      seq[uint32]) =
  extraction.addRunesToExtraction(cast[seq[Rune]](runes))

template subextract(subExtractField: untyped) =
  state.extractText(subExtractField, extract)

template addStyledText(code: untyped) =
  extract.addRunesToExtraction(@[state.curStyle.getStyleId()])
  code
  extract.addRunesToExtraction(@[StylePop])

proc extractText(state: var FmtState, r: Rope, extract: TextPlane) =
  var cur: Rope = r
  while cur != nil:
    if r in state.processed:
      return
    state.processed.add(r)
    case cur.kind
    of RopeAtom:
      let styleOpt = state.getNewStartStyle(cur)
      state.pushStyle(styleOpt.get(state.curStyle))
      addStyledText(extract.addRunesToExtraction(cur.text))
      state.popStyle()
    of RopeLink:
      let urlRunes = if state.showLinkTarg:
                       @[Rune('(')] & cur.url.toRunes() & @[Rune(')')]
                     else:
                       @[]

      subextract(cur.toHighlight)
      addStyledText(extract.addRunestoExtraction(urlRunes))
    else:
      if not cur.noBoxRequired():
        state.savedRopes.add(state.nextRope)
        state.nextRope = cur
        return
      case cur.kind
      of RopeFgColor:
        let tweak = FmtStyle(textColor: some(cur.color))
        let style = state.curStyle.mergeStyles(tweak)
        state.pushStyle(style)
        subextract(r.toColor)
        state.popStyle()
      of RopeBgColor:
        let tweak = FmtStyle(bgColor: some(cur.color))
        state.pushStyle(state.curStyle.mergeStyles(tweak))
        addStyledText(subextract(cur.toColor))
        state.popStyle()
      of RopeBreak:
        # For now, we don't care about kind of break.
        extract.lines.add(@[])
      of RopeTaggedContainer:
        case cur.tag
        of "width":
          withWidth(cur.width):
            subextract(cur.contained)
        of "colors":
          extract.addRunesToExtraction(@[StyleColor])
          subextract(cur.contained)
          extract.addRunesToExtraction(@[StyleColorPop])
        of "nocolors":
          extract.addRunesToExtraction(@[StyleNoColor])
          subextract(cur.contained)
          extract.addRunesToExtraction(@[StyleColorPop])
        else:
          let styleOpt = state.getNewStartStyle(cur)
          state.pushStyle(styleOpt.getOrElse(state.curStyle))
          subextract(cur.contained)
          state.popStyle()
      else:
        assert false

    cur = cur.next

proc extractText(state: var FmtState, r: Rope): TextPlane =
  result = TextPlane(lines: @[@[]])
  state.extractText(r, result)

proc preRenderTextBox(state: var FmtState, p: seq[TextPlane]): seq[RenderBox] =
  state.boxContent(state.curStyle, result):
    var merged = p.mergeTextPlanes()
    merged.wrapToWidth(state.curStyle, state.totalWidth)
    result = @[RenderBox(contents: merged, width: state.totalWidth)]

template planesToBox() =
  if len(consecutivePlanes) != 0:
    result &= state.preRenderTextBox(consecutivePlanes)
    consecutivePlanes = @[]

proc preRenderAligned(state: var FmtState, r: Rope): seq[RenderBox] =
  var tweak: Option[FmtStyle]

  case r.tag[0]
  of 'l':
    tweak = some(FmtStyle(alignStyle: some(AlignL)))
  of 'c':
    tweak = some(FmtStyle(alignStyle: some(AlignC)))
  of 'r':
    tweak = some(FmtStyle(alignStyle: some(AlignR)))
  of 'j':
    tweak = some(FmtStyle(alignStyle: some(AlignJ)))
  of 'f':
    tweak = some(FmtStyle(alignStyle: some(AlignF)))
  else:
    discard

  fmtBox(tweak):
    result = state.preRender(r.contained)

proc preRenderBreak(state: var FmtState, r: Rope): seq[RenderBox] =
  standardBox:
    result = state.preRender(r.guts)

proc preRenderTagged(state: var FmtState, r: Rope): seq[RenderBox] =
  case r.tag
  of "width":
    withWidth(r.width):
      result = state.preRender(r.contained)
  of "colors":
    result = state.preRender(r.contained)
    result[0].contents.lines[0] = @[StyleColor] &
      result[0].contents.lines[0]

    result[0].contents.lines[^1] = @[StyleColorPop] &
      result[0].contents.lines[^1]
  of "nocolors":
    result = state.preRender(r.contained)
    result[0].contents.lines[0] = @[StyleNoColor] &
      result[0].contents.lines[0]

    result[0].contents.lines[^1] = @[StyleColorPop] &
      result[0].contents.lines[^1]
  else:
    standardBox:
      result = state.preRender(r.contained)

proc preRenderColor(state:  var FmtState, r: Rope): seq[RenderBox] =
  standardBox:
    result = state.preRender(r.toColor)

proc preRender(state: var FmtState, r: Rope): seq[RenderBox] =
  ## This version of prerender returns a COLUMN of boxes of one single
  ## width.  But generally, there should only be one item in the
  ## column when possible, which itself should consist of one
  ## TextPlane item.
  ##
  ## The exception to that is RopeTableRows, which leaves it to
  ## RopeTable to do the combination.

  var
    consecutivePlanes: seq[TextPlane]
    curRope = r

  while curRope != nil:
    if curRope.noBoxRequired():
      let textBox = state.extractText(curRope)
      consecutivePlanes.add(textBox)
    else:
      planesToBox()

      case curRope.kind
      of RopeList:
        if curRope.tag == "ul":
          result &= state.preRenderUnorderedList(curRope)
        else:
          result &= state.preRenderOrderedList(curRope)
      of RopeTable:
        result &= state.preRenderTable(curRope)
      of RopeTableRow:
        result &= state.preRenderRow(curRope)
      of RopeTableRows:
        result &= state.preRenderRows(curRope)
      of RopeAlignedContainer:
        result &= state.preRenderAligned(curRope)
      of RopeBreak:
        result &= state.preRenderBreak(curRope)
      of RopeTaggedContainer:
        result &= state.preRenderTagged(curRope)
      of RopeFgColor, RopeBgColor:
        result &= state.preRenderColor(curRope)
      else:
        discard

    while curRope != nil:
      if state.nextRope != nil:
        curRope        = state.nextRope
        state.nextRope = state.savedRopes.pop()
      else:
        curRope = curRope.next
      if curRope in state.processed:
        continue
      else:
        break

  planesToBox()

proc preRender*(r: Rope, width = -1, showLinkTargets = false,
                style = defaultStyle, outerPad = true): TextPlane =
  ## This takes a Rope that is essentially stored as a tree annotated
  ## with style information, and produce a representation that is an
  ## array of lines of unicode characters, interspersed with 32-bit
  ## values outside the range of Unicode codepoints that allow for
  ## lookup of styling information from the tree.
  ##
  ## Note that if you don't pass a width in, we end up calling an
  ## ioctl to query the terminal width. That does seem a bit
  ## excessive, and we could certainly register to handle
  ## SIGWINCH. However, signal delivery isn't even guaranteed, so
  ## until this becomes a problem in the real world, we'll just
  ## leave it.

  var
    state = FmtState(curStyle: style.mergeStyles(defaultStyle),
                     showLinkTarg: showLinkTargets)
    strip = false

  if width <= 0:
    state.totalWidth = terminalWidth() + width
  else:
    state.totalWidth = width

  if state.totalWidth <= 0:
    state.totalWidth = defaultTextWidth

  if r.noBoxRequired():
    state.totalWidth = r.unboxedRuneLength() + 1
    strip            = true

  let preRender = state.collapseColumn(state.preRender(r))
  result        = state.collapsedBoxToTextPlane(preRender, outerPad)
  result.width  = state.totalWidth

  if strip:
    var n            = len(result.lines)
    result.softBreak = true

    while n != 0:
      n -= 1
      result.lines[n] = result.lines[n].stripSpacesButNotFormattersFromEnd()
      if result.lines[n].u32LineLength() != 0:
        break
    while len(result.lines) != 0:
      if result.lines[^1].u32LineLength() == 0:
        result.lines = result.lines[0 ..< ^1]
      else:
        break
