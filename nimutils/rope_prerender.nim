## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

# TODO:
#
# 1) Support column spans.
#
# 2) Support absolute column sizes (right now if specified it's pct, and
#    if it's not every column is sized evenly).

import tables, options, std/terminal, rope_base, rope_styles, unicodeid,
       unicode, misc

type
  RenderBoxKind* = enum RbText, RbBoxes

  RenderBox* = ref object
    contents*:   TextPlane
    width*:      int

  FmtState = object
    totalWidth:      int
    showLinkTarg:    bool
    curStyle:        FmtStyle
    styleStack:      seq[uint32]
    colStack:        seq[seq[int]]
    colorStack:      seq[bool]
    tableEven:       seq[bool]
    curPlane:        TextPlane
    curContainer:    Rope
    curTableSep:     Option[seq[uint32]]
    renderStack:     seq[Rope]

proc `$`*(box: RenderBox): string =
    result &= $(box.contents)
    result &= "\n"

template styleRunes(state: FmtState, runes: seq[uint32]): seq[uint32] =
  @[state.curStyle.getStyleId()] & runes & @[StylePop]

template pad(state: FmtState, w: int): seq[uint32] =
  @[state.curStyle.getStyleId()] & uint32(Rune(' ')).repeat(w) & @[StylePop]


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
  ##
  ## This has gotten a bit more complicated with the styling
  ## API. Previously we relied on the tag being in 'breaking
  ## styles'. However, with the style API, one can easily set
  ## properties that change whether a box is implied. So, while we
  ## still check the list of tags that imply a box, we also check the
  ## boolean `noTextExtract`.
  ##
  ## This boolean isn't meant to be definitive; it's only to be added
  ## to nodes that will short-circuit text extraction, so that box
  ## properties get applied, and we don't bother to set it when the
  ## tag already iplies it.

  # This will be used to test containers that may contain some basic
  # content, some not.

  if r == nil:
    return true
  if r.tag in breakingStyles or r.noTextExtract:
    return false
  case r.kind
  of RopeList, RopeTable, RopeTableRow, RopeTableRows:
    return false
  of RopeAtom:
    result = true
  of RopeLink:
    result = r.toHighlight.noBoxRequired()
  of RopeFgColor, RopeBgColor:
    result = r.toColor.noBoxRequired()
  of RopeBreak:
    result = r.guts == Rope(nil)
  of RopeTaggedContainer:
    result = r.contained.noBoxRequired()

  if result != false:
    result = r.next.noBoxRequired()

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

proc applyAlignment(state: FmtState, box: RenderBox) =
  let w = state.totalWidth

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

proc applyPadding(state: FmtState, box: RenderBox, lpad, rpad: int) =
  ## When we're applying a container style, the contents are rendered
  ## to a width calculated after subtracting out the padding.
  ##
  ## When this is called, the state object is at the end of applying
  ## the style, and we're going to go ahead and make sure each line
  ## is exactly the right width (to the best of our ability due to
  ## unicode issues), then add the padding on.
  var
    lpadTxt = state.pad(lpad)
    rpadTxt = state.pad(rpad)
    w       = state.totalWidth
    toFill: int

  for i in 0 ..< len(box.contents.lines):
    toFill = (w - box.contents.lines[i].u32LineLength())

    if toFill < 0:
      box.contents.lines[i] = box.contents.lines[i].truncateToWidth(w)
    elif toFill > 0:
      box.contents.lines[i] = box.contents.lines[i] & state.pad(toFill)

    
    box.contents.lines[i] = lpadTxt & box.contents.lines[i] & rpadTxt

proc wrapTextPlane(p: TextPlane, lineStart, lineEnd: seq[uint32]) =
  for i in 0 ..< p.lines.len():
    p.lines[i] = lineStart & p.lines[i] & lineEnd

proc collapseColumn(state: FmtState, boxes: seq[RenderBox],
                    topPad: int, bottomPad: int): RenderBox =
  ## Combine renderboxes at the same level into one renderbox.  These
  ## boxes are expected to all be the same width after padding, and
  ## each contain only a single TextPlane, but pads between these
  ## need to be respected.

  var
    plane: TextPlane = TextPlane()
    blank: seq[uint32]

  if topPad != 0 or bottomPad != 0:
      blank = state.pad(state.totalWidth)

  for i in 0 ..< topPad:
      plane.lines.add(blank)

  for box in boxes:
    plane.lines &= box.contents.lines

  for i in 0 ..< bottomPad:
      plane.lines.add(blank)

  result = RenderBox(contents: plane)

proc collapsedBoxToTextPlane(state: FmtState, box: RenderBox): TextPlane =
  result       = box.contents
  result.width = box.width

proc pushTableWidths(state: var FmtState, widths: seq[int]) =
  state.colStack.add(widths)

proc popTableWidths(state: var FmtState) =
  discard state.colStack.pop()

proc pushStyle(state: var FmtState, style: FmtStyle): uint32 {.discardable.} =
  state.curStyle = style
  state.styleStack.add(state.curStyle.getStyleId())

proc popStyle(state: var FmtState) =
  discard state.styleStack.pop().idToStyle()
  state.curStyle = state.styleStack[^1].idToStyle()

proc getNewStartStyle(state: FmtState, r: Rope): FmtStyle =
  if r == nil:
    return state.curStyle
  
  # If there's an explicit style set, and no tweak, we are ok.
  if r.style != nil and r.tweak == nil:
    return r.style
  
  # First, apply any style object associated with the rope's html tag.
  # Second, if the rope has a class, apply any style object associated w/ that.
  # Third, do the same w/ ID.
  # Finally, if the rope itself has a specified style, it takes
  # precedence.
  var
    newStyle    = state.curStyle

  # Apply the tweak BEFORE the actual node style; it overrides the tweak.
  # For instance, when the tweak is tr.even or tr.odd, the striping applies
  # UNLESS the th or td explicitly sets a color.
  if r.tweak != nil:
    newStyle = newStyle.mergeStyles(r.tweak)
  if r.tag != "" and r.tag in styleMap:
    newStyle = newStyle.mergeStyles(styleMap[r.tag])
  if r.class != "" and r.class in perClassStyles:
    newStyle = newStyle.mergeStyles(perClassStyles[r.class])
  if r.id != "" and r.id in perIdStyles:
    newStyle = newStyle.mergeStyles(perIdStyles[r.id])

  if r.kind == RopeFgColor:
    newStyle = newStyle.mergeStyles(FmtStyle(textColor: some("")))
  elif r.kind == RopeBgColor:
    newStyle = newStyle.mergeStyles(FmtStyle(bgColor: some("")))

  result = newStyle

  if r.tweak == nil:
    r.style = result

template withRopeStyle(code: untyped) =
  let style = state.getNewStartStyle(r)
  state.pushStyle(style)
  code
  state.popStyle()

template withWidth(w: int, code: untyped) =
  let oldWidth = state.totalWidth

  if w < 0:
    w = 0
  elif w < oldwidth:
    state.totalWidth = w

  code

  state.totalWidth = oldWidth

template flushCurPlane(boxvar: untyped) =
  if state.curPlane.lines.len() != 0:
    state.curPlane.wrapToWidth(state.curStyle, state.totalWidth)
    boxvar.add(RenderBox(contents: state.curPlane))
    state.curPlane = TextPlane(lines: @[])

template enterContainer(boxvar, code: untyped) =
  flushCurPlane(boxvar)
  var savedContainer = state.curContainer
  code
  while state.renderStack.len() != 0:
    result &= state.preRender(state.renderStack.pop())
  state.curContainer = savedContainer

template applyContainerStyle(boxvar: untyped, code: untyped) =
  var
    style = state.getNewStartStyle(r)
    lpad  = style.lpad.getOrElse(0)
    rpad  = style.rpad.getOrElse(0)
    tpad  = style.tpad.getOrElse(0)
    bpad  = style.bpad.getOrElse(0)
    w     = state.totalWidth - lpad - rpad
    collapsed: RenderBox

  state.pushStyle(style)
  withWidth(w):
    code
    flushCurPlane(boxvar)
    collapsed = state.collapseColumn(boxvar, tpad, bpad)
    state.applyAlignment(collapsed)
    state.applyPadding(collapsed, lpad, rpad)
  boxvar = @[collapsed]
  state.popStyle()    

proc preRender*(state: var FmtState, r: Rope): seq[RenderBox]

proc preRenderUnorderedList(state: var FmtState, r: Rope): seq[RenderBox] =
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
      var oneItem  = state.preRender(item)[0]

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
                      sep: Rune): seq[uint32] =
    let
      useLeft  = style.useLeftBorder.getOrElse(false)
      useRight = style.useRightBorder.getOrElse(false)
      useSep   = style.useVerticalSeparator.getOrElse(false)

    if useLeft:
       result &= @[uint32(leftBorder)]

    for i, width in colWidths:
      for j in 0 ..< width:
        result &= uint32(horizontal)
        
      if useSep and i != len(colWidths) - 1:
        result &= uint32(sep)

    if useRight:
      result &= uint32(rightBorder)


proc getTopBorder(state: var FmtState, s: BoxStyle): seq[uint32] =
  result = state.getGenericBorder(state.colStack[^1], state.curStyle,
           s.horizontal, s.upperLeft, s.upperRight, s.topT)

proc getHorizontalSep(state: var FmtState, s: BoxStyle): seq[uint32] =
  result = state.getGenericBorder(state.colStack[^1], state.curStyle,
           s.horizontal, s.leftT, s.rightT, s.cross)

proc getBottomBorder(state: var FmtState, s: BoxStyle): seq[uint32] =
  result = state.getGenericBorder(state.colStack[^1], state.curStyle,
           s.horizontal, s.lowerLeft, s.lowerRight, s.bottomT)

proc preRenderTable(state: var FmtState, r: Rope): seq[RenderBox] =
    var
      colWidths: seq[int]
      savedSep  = state.curTableSep
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
    else:
      let rows = r.search("tr", first = true)
      if len(rows) != 0:
        let
          row = rows[0]
          pct = 100 div len(row.cells)
        for i in 0 ..< len(row.cells):
          colWidths.add(pct)

    # Mutate to be widths; above this point it was percentages.
    colWidths = state.percentToActualColumns(colWidths)
    
    state.pushTableWidths(colWidths)

    var
      topBorder = state.getTopBorder(boxStyle)
      midBorder = state.getHorizontalSep(boxStyle)
      lowBorder = state.getBottomBorder(boxStyle)

    if state.curStyle.useHorizontalSeparator.getOrElse(false):
      state.curTableSep = some(midBorder)
    else:
      state.curTableSep = none(seq[uint32])

    if r.thead != Rope(nil):
      result &= state.preRender(r.thead)
    if r.tbody != Rope(nil):
      result &= state.preRender(r.tbody)
    if r.tfoot != Rope(nil):
      result &= state.preRender(r.tfoot)

    state.curTableSep = savedSep

    if state.curStyle.useTopBorder.getOrElse(false):
      let toAdd = state.styleRunes(topBorder)
      result[0].contents.lines = @[toAdd] & result[0].contents.lines

    if r.caption != Rope(nil):
      # Need to constrain the caption's width to not overhang the border.
      var borderLen = 0
      for c in colWidths:
        borderLen += c
      if state.curStyle.useLeftBorder.getOrElse(false):
        borderLen += 1
      if state.curStyle.useVerticalSeparator.getOrElse(false):
        borderLen += colWidths.len() - 1
      if state.curStyle.useRightBorder.getOrElse(false):
        borderLen += 1
      withWidth(borderLen):
        result = state.preRender(r.caption) & result
      
    if state.curStyle.useBottomBorder.getOrElse(false):
      let toAdd = state.styleRunes(lowBorder)
      result[^1].contents.lines.add(toAdd)
      
    state.popTableWidths()

proc emptyTableCell(state: var FmtState): seq[RenderBox] =
  var styleId: uint32
  # This probably should use "th" if we are in thead, but hey,
  # don't give us empty cells.
  if "td" in styleMap:
    styleId = state.curStyle.mergeStyles(styleMap["td"]).getStyleId()
  else:
    styleId = state.curStyle.getStyleId()

  let pane = TextPlane(lines: @[@[styleId,
                                  StylePop]])

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
  for i, col in cells:
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
  # However, there's one hitch, which is that, if padding got added to
  # a cell, we did that by appending a newline.
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
  #
  # 1) Pre-render the individual cells to the required width.
  #    This will return a seq[RenderBox]
  # 2) Flatten into a TextPlane.
  # 3) Combine the textplanes horizontally, adding vertical borders.
  #
  # This will result in our table being one TextPlane in a single
  # RenderBox.
  var
    widths     = state.colStack[^1]
    savedWidth = state.totalWidth
    cellBoxes: seq[RenderBox]
    rowPlanes: seq[TextPlane]

  # This loop does steps 1-2
  for i, width in widths:
    # Pre-render the cell.
    if i >= len(r.cells):
      cellBoxes = state.emptyTableCell()
    else:
      state.totalWidth = width
      cellBoxes = state.preRender(r.cells[i])

    let boxes = state.collapseColumn(cellBoxes, 0, 0)
    rowPlanes.add(state.collapsedBoxToTextPlane(boxes))

  # Step 3, Combine the cells horizontally into a single RbText
  # object. This involves adding any vertical borders, and filling
  # in any blank lines if individual cells span multiple lines.
  let resPlane     = state.adjacentCellsToRow(rowPlanes, widths)
  result           = @[RenderBox(contents: resPlane, width: savedWidth)]
  state.totalWidth = savedWidth

proc preRenderRows(state: var FmtState, r: Rope): seq[RenderBox] =
  # Each row returns a single item. # We need to make sure to combine
  # rows properly; if there's a horizontal border in the state,
  # we add it after all but the last row.
  for i, item in r.cells:
    result &= state.preRender(item)
    if i != r.cells.len() - 1 and state.curTableSep.isSome():
      let styled = state.styleRunes(state.curTableSep.get())
      result[^1].contents.lines.add(styled)

    state.tableEven.add(not state.tableEven.pop())

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

proc preRenderAtom(state: var FmtState, r: Rope) =
  withRopeStyle:
    var text = cast[seq[Rune]](state.styleRunes(cast[seq[uint32]](r.text)))
    state.curPlane.addRunesToExtraction(text)

proc preRenderLink(state: var FmtState, r: Rope) =
  if not r.noBoxRequired():
    raise newException(ValueError, "Only styled text is allowed in links")

  discard state.preRender(r.toHighlight)
  if state.showLinkTarg:
    var text = cast[seq[Rune]](state.styleRunes(cast[seq[uint32]](r.text)))
    let runes = @[Rune('(')] & r.url.toRunes() & @[Rune(')')]
    state.curPlane.addRunesToExtraction(runes)

template textExit(old: Rope) =
    var next = old.next
    while next != nil:
      if next.isContainer():
        state.renderStack.add(next)
        return
      else:
        result &= state.preRender(next)
        next = next.next
    return
  
proc preRender(state: var FmtState, r: Rope): seq[RenderBox] =
  # This is the actual main worker for rendering. Generally, these
  # ropes are trees that may be concatenated, so we need to go down
  # first, and then over.
  #
  # When individual pieces of a tree have text, that text gets
  # extracted, and is 'formatted' based on the style of the active
  # style (as determined by parent containers). This basically means
  # keeping track of the style and injecting start/end markers.
  #
  # Instead of injecting markers only when styles change, we currenly
  # make life easy on ourselves, and wrap each text atom in
  # markers. It's much easier to reason about this way.
  #
  # Every time we hit a box boundary, we commit the current text
  # extraction (a TextPlane) and shove it in a RenderBox.
  #
  # Note that, because of contatenation that can link in above us, it
  # would take some accounting for a node to know for sure whether
  # it's going to be the last thing to write into a TextPlane, so we
  # always check when we enter a container to see if we need to
  # render, before we switch the active style.

  if r == nil or r.processed:
    return

  r.processed = true
  
  case r.kind
  of RopeAtom:
    state.preRenderAtom(r)
    r.textExit()
  of RopeLink:
    state.preRenderLink(r)
    r.textExit()    
  of RopeFgColor, RopeBgColor:
    withRopeStyle:
      result = state.preRender(r.toColor)
  of RopeBreak:
    if r.guts != nil:
      # It's a <p> or similar, so a box.
      result.enterContainer:
        result &= state.preRender(r.guts)
    else:
      state.curPlane.lines.add(@[])
      r.textExit()
  of RopeTaggedContainer:
    case r.tag
    of "width":
      var w = r.width
      # This is not going to be a tagged container forever.
      if w <= 0:
        w = state.totalWidth + w
      withWidth(w):
        result.enterContainer:
          result &= state.preRender(r.contained)
    of "colors":
      # Also will stop being a tagged container.
      let tmp = state.preRender(r.contained)
      for item in tmp:
        item.contents.wrapTextPlane(@[StyleColor], @[StyleColorPop])
      if state.curPlane.lines.len() > 1 or
        (state.curPlane.lines.len() != 0 and
         len(state.curPlane.lines[0]) != 0):
        state.curPlane.wrapTextPlane(@[StyleColor], @[StyleColorPop])
      result &= tmp
    of "nocolors":
      # Also will stop being a tagged container.
      let tmp = state.preRender(r.contained)
      for item in tmp:
        item.contents.wrapTextPlane(@[StyleNoColor], @[StyleColorPop])
      if state.curPlane.lines.len() > 1 or
        (state.curPlane.lines.len() != 0 and
         len(state.curPlane.lines[0]) != 0):
        state.curPlane.wrapTextPlane(@[StyleNoColor], @[StyleColorPop])
      result &= tmp
    else:
      if r.isContainer():
        result.enterContainer:
          applyContainerStyle(result):
            result &= state.preRender(r.contained)
      else:
        withRopeStyle:
          result &= state.preRender(r.contained)
        r.textExit()
  of RopeList:
    result.enterContainer:
      applyContainerStyle(result):
         if r.tag == "ul":
           result &= state.preRenderUnorderedList(r)
         else:
           result &= state.preRenderOrderedList(r)
  of RopeTable:
    state.tableEven.add(false)    
    result.enterContainer:
      applyContainerStyle(result):
          result &= state.preRenderTable(r)
    discard state.tableEven.pop()
  of RopeTableRow:
    result.enterContainer:
      var rowTag = if state.tableEven[^1]: "tr.even" else: "tr.odd"
      if rowTag in styleMap:
        for item in r.cells:
          item.tweak = styleMap[rowTag]
      applyContainerStyle(result):
        result &= state.preRenderRow(r)
        r.tag = "tr"
        var next = r.next
        while next != nil:
          next.tweak = styleMap[rowTag]
          result &= state.preRender(next)
          next = next.next
  of RopeTableRows:
    result.enterContainer:
      applyContainerStyle(result):
        result &= state.preRenderRows(r)

  result &= state.preRender(r.next)
  
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

  var state = FmtState(curStyle: nil,
                       showLinkTarg: showLinkTargets,
                       curPlane: TextPlane(lines: @[]))

  state.pushStyle(defaultStyle.mergeStyles(style))
    
  if width <= 0:
    state.totalWidth = terminalWidth() + width
  else:
    state.totalWidth = width
      
  var
    preRenderBoxes = state.preRender(r)    
    noBox: bool

  while state.renderStack.len() != 0:
    preRenderBoxes &= state.preRender(state.renderStack.pop())
    
  # If we had text linked at the end that started after the last container
  # closed, then we will need to get that in here. We can check here to see
  # if there were any breaks, and if there weren't, skip the collapse.
  flushCurPlane(preRenderBoxes)
  
  if preRenderBoxes.len() == 0:
    nobox = true

  if noBox:
    return state.curPlane

  let preRender = state.collapseColumn(preRenderBoxes, 0, 0)
  result        = state.collapsedBoxToTextPlane(preRender)
  result.width  = state.totalWidth
  for item in r.ropeWalk():
    item.processed = false
  
