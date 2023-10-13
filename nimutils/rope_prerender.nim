## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

# TODO:
# 1) Add html tags for justify and full

import tables, options, unicodedb/properties, std/terminal,
       rope_base, rope_styles, unicodeid, unicode, misc

type
  RenderBoxKind* = enum RbText, RbBoxes

  RenderBox* = ref object
    contents*:   TextPlane
    tmargin*:    int
    bmargin*:    int
    width*:      int
    nextRope*:   Rope

  FmtState = object
    totalWidth:   int
    curStyle:     FmtStyle
    styleStack:   seq[FmtStyle]
    colStack:     seq[seq[int]]


proc `$`*(plane: TextPlane): string =
  for line in plane.lines:
    for ch in line:
      if ch <= 0x10ffff:
        result.add(Rune(ch))
      else:
        result &= "<<" & $(ch) & ">>"
    result.add('\n')

proc `$`*(box: RenderBox): string =
    result &= $(box.contents)
    result &= "\n"

template styleRunes(state: FmtState, runes: seq[uint32]): seq[uint32] =
  @[state.curStyle.getStyleId()] & runes & @[StylePop]

proc applyCurrentStyleToPlane(state: FmtState, p: TextPlane) =
  for i in 0 ..< p.lines.len():
    p.lines[i] = state.styleRunes(p.lines[i])

template pad(state: FmtState, w: int): seq[uint32] =
  state.styleRunes(uint32(Rune(' ')).repeat(w))

proc applyAlignment(state: FmtState, box: RenderBox, w: int) =
  for i in 0 ..< box.contents.lines.len():
    let
      toFill =  w - box.contents.lines[i].u32LineLength()

    if toFill <= 0: continue
    case state.curStyle.alignStyle.getOrElse(AlignIgnore)
    of AlignL:
      box.contents.lines[i] &= state.pad(toFill)
    of AlignR:
      box.contents.lines[i] = state.pad(toFill) & box.contents.lines[i]
    of AlignC:
      var
        leftAmt = toFill div 2
        toAdd   = state.pad(leftAmt)

      box.contents.lines[i] = toAdd & box.contents.lines[i] & toAdd

      if w mod 2 != 0:
        box.contents.lines[i].add(state.pad(1))
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
    if toFill >= lpad + rpad:
      extra = state.pad(toFill)
      box.contents.lines[i] = lpadTxt & box.contents.lines[i] & rpadTxt & extra

proc alignAndPad(state: FmtState, box: RenderBox) =
  let
    lpad    = state.curStyle.lpad.getOrElse(0)
    rpad    = state.curStyle.rpad.getOrElse(0)

  state.applyAlignment(box, state.totalWidth - lpad - rpad)
  state.applyLeftRightPadding(box, state.totalWidth)

proc collapseColumn(state: FmtState, boxes: seq[RenderBox]): RenderBox =
  ## Combine renderboxes at the same level into one renderbox.  These
  ## boxes are expected to all be the same width after padding, and
  ## each contain only a single TextPlane, but margins between these
  ## need to be respected.

  var plane: TextPlane = TextPlane()

  for i, box in boxes:
    if i != 0:
      for j in 0 ..< box.tmargin:
        plane.lines.add(state.pad(state.totalWidth))

    state.alignAndPad(box)

    plane.lines &= box.contents.lines

    if i != len(boxes) - 1:
      for j in 0 ..< box.bmargin:
        plane.lines.add(@[])

  result = RenderBox(contents: plane, nextRope: boxes[^1].nextRope,
                     tmargin: boxes[0].tmargin, bmargin: boxes[^1].bmargin)

proc collapsedBoxToTextPlane(state: FmtState, box: RenderBox): TextPlane =
  assert box.nextRope == nil
  result       = box.contents
  result.width = box.width
  for i in 0 ..< box.tmargin:
    result.lines = @[state.pad(result.width)] & result.lines
  for i in 0 ..< box.bmargin:
    result.lines &= @[state.pad(result.width)]

proc pushTableWidths(state: var FmtState, widths: seq[int]) =
  state.colStack.add(widths)

proc popTableWidths(state: var FmtState) =
  discard state.colStack.pop()

proc pushStyle(state: var FmtState, style: FmtStyle): uint32 {.discardable.} =
  state.styleStack.add(state.curStyle)
  state.curStyle = style
  return style.getStyleId()

proc popStyle(state: var FmtState) =
  state.curStyle = state.styleStack.pop()

proc preRender*(state: var FmtState, r: Rope): seq[RenderBox]

type TextExtraction = object
  plane:    TextPlane
  nextRope: Rope

proc getNewStartStyle(state: FmtState, r: Rope,
                      otherTag = ""): Option[FmtStyle] =
  # First, apply any style object associated with the rope's html tag.
  # Second, if the rope has a class, apply any style object associated w/ that.
  # Third, do the same w/ ID.
  var
    styleChange = false
    newStyle    = state.curStyle

  if otherTag != "" and otherTag in styleMap:
      styleChange = true
      newStyle = newStyle.mergeStyles(styleMap[otherTag])
  elif r.tag != "" and r.tag in styleMap:
      styleChange = true
      newStyle = newStyle.mergeStyles(styleMap[r.tag])
  if r.class != "" and r.class in perClassStyles:
    styleChange = true
    newStyle = newStyle.mergeStyles(perClassStyles[r.class])
  if r.id != "" and r.id in perIdStyles:
    styleChange = true
    newStyle = newStyle.mergeStyles(perIdStyles[r.id])

  if r.kind == RopeFgColor:
    styleChange = true
    newStyle = newStyle.mergeStyles(FmtStyle(textColor: some(r.color)))
  elif r.kind == RopeBgColor:
    styleChange = true
    newStyle = newStyle.mergeStyles(FmtStyle(bgColor: some(r.color)))

  if styleChange:
    return some(newStyle)

proc annotatePaddingAndAlignment(b: RenderBox, style: FmtStyle) =
  # Here we're going to add to the width of the box, not
  # just denote the padding for later rendering.

  if style.tmargin.isSome():
    b.tmargin = style.tmargin.get()

  if style.bmargin.isSome():
    b.bmargin = style.bmargin.get()

proc preRenderUnorderedList(state: var FmtState, r: Rope): seq[RenderBox] =
  let
    bulletChar = state.curStyle.bulletChar.getOrElse(Rune(0x2022))
    bullet     = state.styleRunes(@[uint32(bulletChar)])
    bulletLen  = bullet.u32LineLength()
    hangPrefix = state.styleRunes(state.pad(bulletLen))
  var
    bullets: seq[RenderBox]
    subedWidth = true

  if bullet.u32LineLength() < state.totalWidth:
    state.totalWidth -= bulletLen
  else:
    subedWidth = false

  for n, item in r.items:
    var oneItem = state.collapseColumn(state.preRender(item))

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

  result  = state.pad(maxdigits - len(codepoints))
  result &= cast[seq[uint32]](codepoints)

  if state.curStyle.bulletChar.isSome():
    result.add(uint32(state.curStyle.bulletChar.get()))

proc preRenderOrderedList(state: var FmtState, r: Rope): seq[RenderBox] =
  var
    hangPrefix:  seq[uint32]
    maxDigits  = 0
    n          = len(r.items)
    subedWidth = true
    listItems: seq[RenderBox]

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
    var oneItem = state.collapseColumn(state.preRender(item))
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
  let
    useLeft  = style.useLeftBorder.getOrElse(false)
    useRight = style.useRightBorder.getOrElse(false)
    useSep   = style.useVerticalSeparator.getOrElse(false)

  var plane = TextPlane(lines: @[@[]])

  if useLeft:
    plane.lines[0] &= @[uint32(leftBorder)]

  for i, width in colWidths:
    for j in 0 ..< width:
      plane.lines[0].add(uint32(horizontal))
    if useSep and i != len(colWidths) - 1:
      plane.lines[0].add(uint32(sep))

  if useRight:
    plane.lines[0].add(uint32(rightBorder))

  state.applyCurrentStyleToPlane(plane)

  result = RenderBox(contents: plane)

template getTopBorder(state: var FmtState, s: BoxStyle): RenderBox =
  state.getGenericBorder(state.colStack[^1], state.curStyle, s.horizontal,
                         s.upperLeft, s.upperRight, s.topT)

template getHorizontalSep(state: var FmtState, s: BoxStyle): RenderBox =
  state.getGenericBorder(state.colStack[^1], state.curStyle, s.horizontal,
                         s.leftT, s.rightT, s.cross)

template getBottomBorder(state: var FmtState, s: BoxStyle): RenderBox =
  state.getGenericBorder(state.colStack[^1], state.curStyle, s.horizontal,
                         s.lowerLeft, s.lowerRight, s.bottomT)

proc preRenderTable(state: var FmtState, r: Rope): seq[RenderBox] =
  var
    colWidths: seq[int]
    boxStyle = state.curStyle.boxStyle.getOrElse(DefaultBoxStyle)

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
  if r.caption != Rope(nil):
    result &= state.preRender(r.caption)

  if state.curStyle.useHorizontalSeparator.getOrElse(false):
    var newBoxes: seq[RenderBox]

    for i, item in result:
      newBoxes.add(item)
      if (i + 1) != len(result):
        newBoxes.add(state.getHorizontalSep(boxStyle))

    result = newBoxes

  if state.curStyle.useTopBorder.getOrElse(false):
    result = @[state.getTopBorder(boxStyle)] & result

  if state.curStyle.useBottomBorder.getOrElse(false):
    result.add(state.getBottomBorder(boxStyle))

  state.popTableWidths()

  result = @[state.collapseColumn(result)]

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

proc adjacentCellsToRow(state: var FmtState, cells: seq[TextPlane]): TextPlane =
  var
    style    = state.curStyle
    boxStyle = style.boxStyle.getOrElse(DefaultBoxStyle)
    leftBorder:  seq[uint32]
    sep:         seq[uint32]
    rightBorder: seq[uint32]
    rowLines:    int

  if style.useLeftBorder.getOrElse(false):
    leftBorder.add(uint32(boxStyle.vertical))

  if style.useRightBorder.getOrElse(false):
    rightBorder.add(uint32(boxStyle.vertical))

  if style.useVerticalSeparator.getOrElse(false):
    sep.add(uint32(boxStyle.vertical))

  # Determine how many text lines high this row is by examining the
  # height of each cell.
  for col in cells:
    let l = col.lines.len()
    if l > rowLines:
      rowLines = l

  # Any cells not of the max height, pad them with spaces.
  for col in cells:
    if col.lines.len() < rowLines:
      var blankLine = state.pad(col.width)
      while true:
        col.lines.add(blankLine)
        if col.lines.len() == rowLines:
          break

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

  var
    widths = state.colStack[^1]
    cell: seq[RenderBox]

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
    if i > len(r.cells):
      cellBoxes = state.emptyTableCell()
    else:
      state.totalWidth = width
      cellBoxes = state.preRender(r.cells[i])

    let boxes = state.collapseColumn(cellBoxes)
    rowPlanes.add(state.collapsedBoxToTextPlane(boxes))

  # Step 4, Combine the cells horizontally into a single RbText
  # object. This involves adding any vertical borders, and filling
  # in any blank lines if individual cells span multiple lines.
  let resPlane     = state.adjacentCellsToRow(rowPlanes)
  result           = @[RenderBox(contents: resPlane, width: savedWidth)]
  state.totalWidth = savedWidth

proc preRenderRows(state: var FmtState, r: Rope): seq[RenderBox] =
  # Each row returns a single item.
  for item in r.cells:
    result &= state.preRender(item)

proc noBoxRequired(r: Rope): bool =
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

proc addRunesToExtraction(extraction: var TextExtraction, runes: seq[Rune]) =
  if extraction.plane.lines.len() == 0:
    extraction.plane.lines = @[@[]]

  if Rune('\n') notin runes:
    extraction.plane.lines[^1] &= cast[seq[uint32]](runes)
  else:
    for rune in runes:
      if rune == Rune('\n'):
        extraction.plane.lines.add(@[])
      else:
        extraction.plane.lines[^1].add(uint32(rune))

template addRunesToExtraction(extraction: var TextExtraction,
                              runes:      seq[uint32]) =
  extraction.addRunesToExtraction(cast[seq[Rune]](runes))

template subextract(subExtractField: untyped) =
  state.extractText(subExtractField, extract)

template addStyledText(code: untyped) =
  extract.addRunesToExtraction(@[state.curStyle.getStyleId()])
  code
  extract.addRunesToExtraction(@[StylePop])

proc extractText(state: var FmtState, r: Rope, extract: var TextExtraction) =
  case r.kind
  of RopeAtom:
    addStyledText(extract.addRunesToExtraction(r.text))
  of RopeLink:
    let urlRunes = @[Rune('(')] & r.url.toRunes() & @[Rune(')')]

    subextract(r.toHighlight)
    addStyledText(extract.addRunestoExtraction(urlRunes))
  else:
    if r.noBoxRequired() == false:
      extract.nextRope = r
      return
    else:
      case r.kind
      of RopeFgColor:
        let tweak = FmtStyle(textColor: some(r.color))
        state.pushStyle(state.curStyle.mergeStyles(tweak))
        addStyledText(subextract(r.toColor))
        state.popStyle()
      of RopeBgColor:
        let tweak = FmtStyle(bgColor: some(r.color))
        state.pushStyle(state.curStyle.mergeStyles(tweak))
        addStyledText(subextract(r.toColor))
        state.popStyle()
      of RopeBreak:
        # For now, we don't care about kind of break.
        extract.plane.lines.add(@[])
      of RopeTaggedContainer:
        let styleOpt = state.getNewStartStyle(r)
        if styleOpt.isSome():
          state.pushStyle(styleOpt.get())
          addStyledText(subextract(r.contained))
          state.popStyle()
        else:
          subextract(r.contained)
      else:
        assert false

  if r.next != nil:
    state.extractText(r.next, extract)

proc extractText(state: var FmtState, r: Rope): TextExtraction =
  let styleOpt = state.getNewStartStyle(r)

  if styleOpt.isSome():
    state.pushStyle(styleOpt.get())

  result.plane = TextPlane(lines: @[@[]])
  state.extractText(r, result)

  state.applyCurrentStyleToPlane(result.plane)

  if styleOpt.isSome():
    state.popStyle()

template planesToBox() =
  if len(consecutivePlanes) != 0:
    var merged = consecutivePlanes.mergeTextPlanes()
    state.applyCurrentStyleToPlane(merged)
    merged.wrapToWidth(state.curStyle, state.totalWidth)
    result.add(RenderBox(contents: merged, width: state.totalWidth))
    consecutivePlanes = @[]

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
    newBoxes:          seq[RenderBox]
    curRope = r

  while curRope != nil:
    if curRope.noBoxRequired():
      let textBox = state.extractText(r)
      consecutivePlanes.add(textBox.plane)
      curRope = textBox.nextRope
    else:
      planesToBox()

      let styleOpt = state.getNewStartStyle(curRope)
      var
        curRenderBox: RenderBox

      if styleOpt.isSome():
        state.pushStyle(styleOpt.get())
        # The way we handle padding, is by looking at the current
        # style's padding value. We subtract from the total width, and
        # let the resulting box come back. Then, ad the end, we add
        # the padding values associated with the current style to the
        # box.
      case curRope.kind
      of RopeList:
        if curRope.tag == "ul":
          newBoxes = state.preRenderUnorderedList(curRope)
        else:
          newBoxes = state.preRenderOrderedList(curRope)
      of RopeTable:
        newBoxes = state.preRenderTable(curRope)
      of RopeTableRow:
        newBoxes = state.preRenderRow(curRope)
      of RopeTableRows:
        newBoxes = state.preRenderRows(curRope)
      of RopeAlignedContainer:
        var tweak: Option[AlignStyle]

        case curRope.tag[0]
        of 'l':
          tweak = some(AlignL)
        of 'c':
          tweak = some(AlignC)
        of 'r':
          tweak = some(AlignR)
        of 'j':
          tweak = some(AlignJ)
        of 'f':
          tweak = some(AlignF)
        else:
          discard
        if tweak.isSome():
          let tweakedStyle = FmtStyle(alignStyle: tweak)
          state.pushStyle(state.curStyle.mergeStyles(tweakedStyle))

        newBoxes = state.preRender(curRope)

        if tweak.isSome():
          state.popStyle()

      of RopeBreak:
        newBoxes = state.preRender(curRope.guts)
      of RopeTaggedContainer:
        newBoxes = state.preRender(curRope.contained)
      of RopeFgColor, RopeBgColor:
        newBoxes = state.preRender(curRope.toColor)
      else:
        discard

      for box in newBoxes:
        box.annotatePaddingAndAlignment(state.curStyle)

      result   &= newBoxes
      newBoxes  = @[]
      curRope   = curRope.next

      if styleOpt.isSome():
        state.popStyle()

  planesToBox()
  for item in result:
    state.alignAndPad(item)

proc preRender*(r: Rope, width = -1): TextPlane =
  ## Denoted in the stream of characters to output, what styles
  ## should be applied, when. We do this by dropping in unique
  ## values into the uint32 stream that cannot be codepoints.  This
  ## instructs the rendering implementation what style to push.
  ##
  ## There's a value for pop as well.
  ##
  ## Note that if you don't pass a width in, we end up calling an
  ## ioctl to query the terminal width. That does seem a bit
  ## excessive, and we could certainly register to handle
  ## SIGWINCH. However, signal delivery isn't even guaranteed, so
  ## until this becomes a problem in the real world, we'll just
  ## leave it.

  var
    state = FmtState(curStyle: defaultStyle)

  if width <= 0:
    state.totalWidth = terminalWidth() - 1
  else:
    state.totalWidth = width

  if state.totalWidth <= 0:
    state.totalWidth = defaultTextWidth

  let preRender = state.collapseColumn(state.preRender(r))
  result        = state.collapsedBoxToTextPlane(preRender)
  result.width  = state.totalWidth
