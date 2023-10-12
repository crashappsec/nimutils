## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

# TODO:
# 1) When merging text boxes either horizontally or vertically, if the
#    styles are not the same, then we need to add pushes and pops as
#    appropriate.
# 2) CombineTextColumn should do the same so that the lines and style
#    map are all we need to render.
# 3) Can skip insertion of the style placeholders if there are no
#    changes to ansi-relevant items.
# 4) Add links
# 5) Add html tags for justify and full

import tables, options, unicodedb/properties, std/terminal,
       rope_base, rope_styles, unicodeid, unicode, misc

type
  RenderBoxKind* = enum RbText, RbBoxes

  RenderBox* = ref object
    ## We don't want to actually write things like ANSI codes into
    ## strings until pretty late in the game, as we want to do the
    ## right thing in the face of wrapping and padding. Particularly,
    ## we might want to output to ansi chars, or we might want to
    ## output via some other API to feed into a windowing system
    ## (particularly thinking about notcurses).
    ##
    ## The RenderBox abstraction handles padding and wrapping. It
    ## also STORES formatting information; it just doesn't apply it.
    ##
    ## Lines are kept as sequences of uint32 characters. The
    ## characters are either unicode codepoints, or references to
    ## 'style' instructions.  The maximum Unicode codepoint is
    ## 0x10FFFF; we start our 'formatting' values at 0x1fffff and
    ## increment across the whole system; the IDs are atomically
    ## incremented.
    ##
    ## We do this so that we can map back a int to a style with:
    ## `x >> 21`
    ##
    ## Styles are basically in a stack; the start-style will
    ## get applied at the beginning, but anything inlined will
    ## be a 'push', and then we denote `pops` in the stream with
    ## 0xffffffff.
    ##
    ## For each line in a box, we keep a count of the actual display
    ## length of the screen, as best as we can count it anyway.
    ## Runes, of course, may not render correctly; we may not always
    ## have control over that, but we do the best we reasonably can.

    lpad*:       int
    rpad*:       int
    tmargin*:    int
    bmargin*:    int
    width*:      int
    align*:      AlignStyle
    startStyle*: FmtStyle
    case kind*:  RenderBoxKind
    of RbText:
      lines*:    seq[seq[uint32]]
      nextRope*: Rope
    of RbBoxes:
      boxes*:    seq[RenderBox]

  FmtState = object
    totalWidth:   int
    curStyle:     FmtStyle
    styleStack:   seq[FmtStyle]
    padStack:     seq[int]
    colStack:     seq[seq[int]]


proc `$`*(box: RenderBox, indent = 0): string =
  let prefix = $(Rune(' ').repeat(indent))
  case box.kind
  of RbBoxes:
    for item in box.boxes:
      result &= `$`(item, indent + 2)
  else:
    for line in box.lines:
      result &= prefix
      for ch in line:
        if ch <= 0x10ffff:
          result.add(Rune(ch))
      result &= "\n"

proc `$`*(plane: TextPlane, indent = 0): string =
  result = ">>\n"
  for line in plane.lines:
    for ch in line:
      if ch <= 0x10ffff:
        result.add(Rune(ch))
      else:
        result.add("<<" & $ch & ">>")
    result.add('\n')
  result.add("<<\n")

proc pushTableWidths(state: var FmtState, widths: seq[int]) =
  state.colStack.add(widths)

proc popTableWidths(state: var FmtState) =
  discard state.colStack.pop()

proc pushStyle(state: var FmtState, style: FmtStyle): uint32 {.discardable.} =
  state.styleStack.add(state.curStyle)
  state.curStyle = style
  return  style.getStyleId()

proc popStyle(state: var FmtState) =
  state.curStyle = state.styleStack.pop()

proc mergePaddingFrom(dst: RenderBox, toAdd: RenderBox, nested: bool) =
  if not nested:
    dst.lpad += toAdd.lpad
    dst.rpad += toAdd.rpad

  if len(dst.lines) != 0:
    dst.lines[^1].add(toAdd.startStyle.getStyleId())

proc flattenRecursively(parent: RenderBox, kid: RenderBox,
                        nested: bool): seq[RenderBox] =
  # All renderboxes in the result will be text only.
  if kid.kind == RbText:
    kid.mergePaddingFrom(parent, nested)
    if len(kid.lines) != 0:
      result.add(kid)
      kid.lines[^1].add(StylePop)
  else:
    for item in kid.boxes:
      result &= kid.flattenRecursively(item, nested)

    for item in result:
      if len(item.lines) != 0:
        item.mergePaddingFrom(parent, nested)
        item.lines[^1].add(StylePop)

  if len(result) != 0:
    result[0].tmargin  = parent.tmargin
    result[^1].bmargin = parent.bmargin

proc u32LineLength(line: seq[uint32]): int =
  for item in line:
    if item <= 0x10ffff:
      result += item.runeWidth()

proc toWords(line: seq[uint32]): seq[seq[uint32]] =
  var cur: seq[uint32]

  for item in line:
    if item < 0x10ffff and Rune(item).isWhiteSpace():
      if len(cur) != 0:
        result.add(cur)
        cur = @[]
    else:
      cur.add(item)

  if len(cur) != 0:
    result.add(cur)

proc justify(line: seq[uint32], width: int): seq[uint32] =
  let actual = line.u32LineLength()

  if actual >= width:
    return line

  var
    words = line.toWords()
    sum   = 0

  if len(words) == 1:
    return words[0]

  for word in words:
    sum += word.u32LineLength()

  var
    base = sum div (len(words) - 1)
    rem  = sum mod (len(words) - 1)

  for i, word in words:
    result &= word

    if i == len(words) - 1:
      break

    for j in 0 ..< base:
      result.add(uint32(Rune(' ')))

    if rem != 0:
      result.add(uint32(Rune(' ')))
      rem -= 1

proc flattenRenderBox(box: RenderBox, nested: bool): RenderBox =
  # When we flatten boxes, they are to make a column. We don't ever
  # flatten things in a grid (Only tables, which handle themselves).
  #
  # So any pad we've set needs to nest. We work our way down to the
  # bottom layer to flatten, and as we come back up, we merge all
  # our left-right padding values.

  result = RenderBox(kind: RbBoxes, startStyle: box.startStyle,
                     width: box.width)

  if box.kind == RbText:
    result.boxes.add(box)

  else:
    for item in box.boxes:
      result.boxes &= result.flattenRecursively(item, nested)

proc doAlignment(box: RenderBox) =
  let w = box.width

  for i in 0 ..< len(box.lines):
    let toFill =  w - box.lines[i].u32LineLength()
    if toFill <= 0: continue
    case box.align
    of AlignL:
      for j in 0 ..< toFill:
        box.lines[i].add(uint32(Rune(' ')))
    of AlignR:
      var toAdd: seq[uint32]
      for j in 0 ..< toFill:
        toAdd.add(uint32(Rune(' ')))
        box.lines[i] = toAdd & box.lines[i]
    of AlignC:
      var
        toAdd:  seq[uint32]
        leftAmt  = toFill div 2

      for j in 0 ..< leftAmt:
        toAdd.add(uint32(Rune(' ')))

      box.lines[i] = toAdd & box.lines[i] & toAdd

      if w mod 2 != 0:
        box.lines[i].add(uint32(Rune(' ')))
    of AlignF:
      box.lines[i] = justify(box.lines[i], w)
    of AlignJ:
      if i == len(box.lines) - 1:
        for j in 0 ..< toFill:
          box.lines[i].add(uint32(Rune(' ')))
      else:
        box.lines[i] = justify(box.lines[i], w)
    else:
      discard

proc addPadding(box: RenderBox, ensureWidth = box.width) =
  var
    lpad: seq[uint32]
    rpad: seq[uint32]

  for i in 0 ..< box.lpad:
    lpad.add(uint32(Rune(' ')))
  for i in 0 ..< box.rpad:
    rpad.add(uint32(Rune(' ')))

  for i in 0 ..< len(box.lines):
    box.lines[i] = lpad & box.lines[i]
    let l = ensureWidth - box.lines[i].u32LineLength()
    for j in 0 ..< l:
      box.lines[i].add(uint32(Rune(' ')))

    box.lines[i].add(rpad)

  box.width = ensureWidth + box.lpad + box.rpad
  box.lpad  = 0
  box.rpad  = 0

proc combineTextColumn(inbox: RenderBox): RenderBox =
  if len(inbox.boxes) == 0:
    return inbox

  result = inbox.boxes[0]

  result.doAlignment()
  result.addPadding()

  var blankLine: seq[uint32]

  for i in 0 ..< result.width:
    blankLine.add(uint32(Rune(' ')))

  for i in 1 ..< len(inbox.boxes):
    # For each box, the width plus the padding should be the same.  If
    # we *do* end up with ragged boxes, that's probably an error.

    # Still, if the boxes are short relative to the first box, we
    # right pad.

    inbox.boxes[i].doAlignment()
    inbox.boxes[i].addPadding(ensureWidth = result.width)

    for j in 0 ..< inbox.boxes[i - 1].bmargin:
      result.lines.add(blankLine)
    for j in 0 ..< inbox.boxes[i].tmargin:
      result.lines.add(blankLine)

    result.lines &= inbox.boxes[i].lines

  result.bmargin = inbox.boxes[^1].bmargin

proc fitsInTextBox(r: Rope): bool =
  ## Returns true if we have paragraph text that does NOT require any
  ## sort of box... so no alignment, padding, tables, lists, ...
  ##
  ## However, we DO allow break objects, as they don't require boxing.

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
    if not subItem.fitsInTextBox():
      return false
    subItem = subItem.next

  return true

template applyStyleToBox(state:   var FmtState,
                         box:     RenderBox,
                         toApply: FmtStyle,
                         code:    untyped) =

  let id = state.pushStyle(state.curStyle.mergeStyles(toApply))

  box.lines[^1].add(id)

  code

  result.lines[^1].add(StylePop)
  state.popStyle()

proc preRender*(state: var FmtState, r: Rope): RenderBox

proc getBreakOpps(s: seq[uint32]): seq[int] =
  # Should eventually upgrade this to full Annex 14 at some point.
  # This is just basic acceptability. If the algorithm finds no
  # breakpoints, then the soft wrap can decide what to do (we hard
  # wrap only for now).

  # Basically, we should only generate one opp for a group of spaces,
  # and we should generally be willing to wrap at a dash, but then we
  # will be conservative on the rest for now. Note that for us, the
  # 'break' point is always the first character that would NOT appear
  # on a given line, but if it's spaces, it'll end up getting stripped
  # as part of the wrap (currently, we're not supporting a hanging
  # indent).

  # We don't want to break at the front of a line, and once we see a
  # breakpoint, we want to not generate another one until we've seen
  # at least ONE character that has width.
  var
    canGenerateBreakpoint  = false
    breakThereIfNotNumeric = false

  for i, rune in s[0 ..< ^1]:
    if not canGenerateBreakpoint:
      if rune > 0x10ffff or Rune(rune).isWhiteSpace():
        continue
      if Rune(rune).isPostBreakingChar():
        result.add(i + 1)
      else:
        canGenerateBreakpoint = true
      continue

    if not rune.isPossibleBreakingChar():
      if breakThereIfNotNumeric:
        if Rune(rune).unicodeCategory() in ctgN:
          result.add(i)
          # Can generate a breakpoint at the next char too.
        breakThereIfNotNumeric = false
      continue

    if breakThereIfNotNumeric:
      result.add(i)
      continue

    if Rune(rune).isPostBreakingChar():
      if Rune(rune).isPreBreakingChar():
        result.add(i)

      result.add(i + 1)
      canGenerateBreakpoint = false
      continue

    elif Rune(rune) == Rune('-'):
      breakThereIfNotNumeric = true
      continue

    else: # is pre-breaking char.
      result.add(i)
      canGenerateBreakpoint = false
      continue

  # Finally, the last character should never be a breakpoint, nor
  # should the index one past the end of the input.
  while len(result) != 0 and result[^1] >= s.len() - 1:
    result = result[0 ..< ^1]

proc stripSpacesButNotFormatters(input: seq[uint32]): seq[uint32] =
  for i, ch in input:
    if ch > 0x10ffff:
      result.add(ch)
    elif not Rune(ch).isWhiteSpace():
      result &= input[i .. ^1]
      return

proc softWrapLine(input: seq[uint32], width: int): seq[seq[uint32]] =
  # After any line wrap, we will want to just drop trailing spaces,
  # but keep in formatting.
  var line = input

  while true:
    if len(line) == 0:
      break

    var
      breakOps      = line.getBreakOpps()
      curBpIx       = 0
      curWidth      = 0
      bestBp        = -1

    for i, ch in line:
      if curWidth + ch.runeWidth() > width:
        if bestBp == -1:
          # Hard break here, sorry.
          result.add(line[0 ..< i])
          line = line[i .. ^1].stripSpacesButNotFormatters()
          break
      curWidth += ch.runeWidth()

      if curBpIx < len(breakOps) and breakOps[curBpIx] == i:
        bestBp   = i
        curBpIx += 1

    if len(line) == 0:
      break
    if curWidth <= width:
      result.add(line)
      break

    result.add(line[0 ..< bestBp])
    line = line[bestBp .. ^1].stripSpacesButNotFormatters()

proc findTruncationIndex(s: seq[uint32], width: int): int =
  var remaining = width

  for i, ch in s:
    remaining -= ch.runeWidth()
    if remaining < 0:
      return i

  return len(s)

proc applyWrappingToRenderBox(state: var FmtState, r: RenderBox) =
  # We assume that we're only ever going to be asked to wrap each
  # RenderBox of text once. If we see line breaks in here at this
  # point, we assume they're hard line breaks.

  let w = state.totalWidth

  case state.curStyle.overFlow.getOrElse(OIgnore):
    of OverFlow, OIgnore:
      return
    of OTruncate:
      for i in 0 ..< r.lines.len():
        let ix = r.lines[i].findTruncationIndex(w)
        if ix < len(r.lines[i]):
          r.lines[i] = r.lines[i][0 ..< ix]
    of ODots:
      for i in 0 ..< r.lines.len():
        let ix = r.lines[i].findTruncationIndex(w - 1)
        if ix < len(r.lines[i]):
          r.lines[i] = r.lines[i][0 ..< ix]
          r.lines[i].add(0x2026) # "…"
    of OHardWrap:
      var newLines: seq[seq[uint32]]
      for i in 0 ..< r.lines.len():
        var line = r.lines[i]
        while true:
          let ix = line.findTruncationIndex(w)
          if ix == line.len():
            newLines.add(line)
            break
          else:
            newlines.add(line[0 ..< ix])
            line = line[ix .. ^1]
      r.lines = newLines
    of OWrap:
      var newLines: seq[seq[uint32]]
      for line in r.lines:
        newLines &= line.softWrapLine(w)
      r.lines = newLines

template addRunesToBox(arr: seq[Rune], where: RenderBox) =
  if Rune('\n') notin arr:
    where.lines[^1] &= cast[seq[uint32]](arr)
    return

  for item in arr:
    if item == Rune('\n'):
      where.lines.add(@[])
    else:
      where.lines[^1].add(uint32(item))

proc basicMerge(dst: RenderBox, src: RenderBox) =
  var cur = src

  while true:
    case cur.kind
    of RbText:
      break
    else:
      assert len(cur.boxes) == 1
      cur = cur.boxes[0]

  if len(cur.lines) != 0:
    dst.lines[^1] &= cur.lines[0]

    for line in cur.lines[1 .. ^1]:
      dst.lines.add(line)

proc createTextBox(state: var FmtState, r: Rope): RenderBox =
  result = RenderBox(width:       state.totalWidth,
                     startStyle:  state.curStyle,
                     kind:        RbText,
                     lines:       @[@[]])

  var cur = r
  while cur != Rope(nil):
    case cur.kind
    of RopeAtom:
      addRunesToBox(cur.text, result)
    of RopeLink:
      result.basicMerge(state.prerender(r.toHighlight))
      let toAdd = @[Rune('(')] & r.url.toRunes() & @[Rune(')')]
      addRunesToBox(toAdd, result)
    else:
      if cur.fitsInTextBox() == false:
        break
      else:
        case cur.kind
        of RopeFgColor:
          state.applyStyleToBox(result, FmtStyle(textColor: some(r.color))):
            result.basicMerge(state.prerender(r.toColor))
        of RopeBgColor:
          state.applyStyleToBox(result, FmtStyle(bgColor: some(r.color))):
            result.basicMerge(state.prerender(r.toColor))
        of RopeBreak:
          # For now, we don't care about kind of break.
          result.lines.add(@[])
        of RopeTaggedContainer:
          result.basicMerge(state.prerender(r.contained))
        else:
          assert false
    cur = cur.next

  state.applyWrappingToRenderBox(result)
  result.nextRope = cur


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

proc pushPadding(state: var FmtState) =
  let
    style      = state.curStyle
    toSubtract = style.lpad.getOrElse(0) + style.rpad.getOrElse(0)

  if toSubtract == 0:
    return

  if state.totalWidth <= toSubtract:
    # Nah. But push a 0.
    state.padStack.add(0)
  else:
    echo "push pad: ", state.totalWidth, " -> ", state.totalWidth - toSubtract
    state.totalWidth -= toSubtract
    state.padStack.add(toSubtract)


proc popPadding(state: var FmtState) =
  if state.curStyle.lpad.isSome() or state.curStyle.rpad.isSome():
    let toAdd = state.padStack.pop()
    echo "pop pad: ", state.totalWidth, " -> ", state.totalWidth + toAdd
    state.totalWidth += toAdd

proc annotatePaddingAndAlignment(b: RenderBox, style: FmtStyle) =
  # Here we're going to add to the width of the box, not
  # just denote the padding for later rendering.

  if style.lpad.isSome():
    b.lpad   = style.lpad.get()
    b.width += b.lpad

  if style.rpad.isSome():
    b.rpad   = style.rpad.get()
    b.width += b.rpad

  if style.tmargin.isSome():
    b.tmargin = style.tmargin.get()

  if style.bmargin.isSome():
    b.bmargin = style.bmargin.get()

  # If the second condition isn't true, then this is a
  # RopedAlignedContainer, in which case that trumps what we inherited
  # from a style, being explicit.
  if style.alignStyle.isSome() and b.align == AlignIgnore:
    b.align = style.alignStyle.get()

proc preRenderUnorderedList(state: var FmtState, r: Rope): RenderBox =
  let
    bulletChar = state.curStyle.bulletChar.getOrElse(Rune(0x2022))
    bullet     = @[uint32(bulletChar)]
    bulletLen  = bullet.u32LineLength()
    spacing    = uint32(' ').repeat(bulletLen)
  var
    bullets: seq[RenderBox]
    subedWidth = true

  if bullet.u32LineLength() < state.totalWidth:
    state.totalWidth -= bulletLen
  else:
    subedWidth = false

  for line in r.items:
    var liContents = state.preRender(line).flattenRenderBox(false)

    for box in liContents.boxes:
      box.addPadding()
      if len(box.lines) != 0:
        box.lines[0] = bullet & box.lines[0]

      for i in 1 ..< len(box.lines):
        box.lines[i] = spacing & box.lines[i]

    liContents.lpad = 0
    bullets.add(liContents)

  if subedWidth:
    state.totalWidth += bulletLen

  result = RenderBox(width: state.totalWidth, startStyle: state.curStyle,
                     kind: RbBoxes, boxes: bullets)
  result = result.flattenRenderBox(true)

proc toNumberBullet(n, maxdigits: int, bulletChar: Option[Rune]): seq[uint32] =
  # Formats a number n that's meant to be in a bulleted list, where the
  # left is padded if the number is smaller than the max digits for a
  # bullet number, and the right gets any explicit bullet character
  # (such as a dot or right paren.)
  let codepoints = toRunes($(n))

  for i in len(codepoints) .. maxdigits:
    result.add(uint32(Rune(' ')))

  result &= cast[seq[uint32]](codepoints)

  if bulletChar.isSome():
    result.add(uint32(bulletChar.get()))

proc preRenderOrderedList(state: var FmtState, r: Rope): RenderBox =
  var
    wrapPrefix:  seq[uint32]
    maxDigits  = 0
    n          = len(r.items)
    subedWidth = true
    bullets: seq[RenderBox]

  while true:
    maxDigits += 1
    n          = n div 10
    wrapPrefix.add(uint32(Rune(' ')))
    if n == 0:
      break

  if state.curStyle.bulletChar.isSome():
    for i in 0 ..< state.curStyle.bulletChar.get().runeWidth():
      wrapPrefix.add(uint32(Rune(' ')))

  if wrapPrefix.len() < state.totalWidth:
    state.totalWidth -= wrapPrefix.len()
  else:
    subedWidth = false

  for line in r.items:
    let oneItem = state.preRender(line).flattenRenderBox(false)
    bullets.add(oneItem)


  for n, bullet in bullets:
    for i, box in bullet.boxes:
      let s = toNumberBullet(n + 1, maxDigits, state.curStyle.bulletChar)
      box.addPadding()
      if i == 0:
        if len(box.lines) != 0:
          box.lines[0] = s & box.lines[0]
        else:
          box.lines = @[s]
        for j in 1 ..< len(box.lines):
          box.lines[j] = wrapPrefix & box.lines[j]
      else:
        for j in 0 ..< len(box.lines):
          box.lines[j] = wrapPrefix & box.lines[j]

  if subedWidth:
    state.totalWidth += len(wrapPrefix)

  result = RenderBox(width: state.totalWidth, startStyle: state.curStyle,
                     kind: RbBoxes, boxes: bullets)
  result = result.flattenRenderBox(true)

proc percentToActualColumns(state: var FmtState, pcts: seq[int]): seq[int] =
  if len(pcts) == 0: return

  let style    = state.curStyle
  var overhead = 0

  if style.useLeftBorder.getOrElse(false):
    overhead -= 1
  if style.useRightBorder.getOrElse(false):
    overhead -= 1
  if style.useVerticalSeparator.getOrElse(false):
    overhead -= (len(pcts) - 1)

  let availableWidth = state.totalWidth - overhead

  for item in pcts:
    var colwidth = (item * availableWidth) div 100
    result.add(if colwidth == 0: 1 else: colwidth)

proc getGenericBorder(colWidths: seq[int], style: FmtStyle,
                      horizontal: Rune, leftBorder: Rune,
                      rightBorder: Rune, sep: Rune): RenderBox =
  let
    useLeft  = style.useLeftBorder.getOrElse(false)
    useRight = style.useRightBorder.getOrElse(false)
    useSep   = style.useVerticalSeparator.getOrElse(false)

  result = RenderBox(kind: RbText, startStyle: style, lines: @[@[]])

  if useLeft:
    result.lines[0] = @[uint32(leftBorder)]

  for i, width in colWidths:
    for j in 0 ..< width:
      result.lines[0].add(uint32(horizontal))
    if useSep and i != len(colWidths) - 1:
      result.lines[0].add(uint32(sep))

  if useRight:
    result.lines[0].add(uint32(rightBorder))

template getTopBorder(state: var FmtState, s: BoxStyle): RenderBox =
  getGenericBorder(state.colStack[^1], state.curStyle, s.horizontal,
                   s.upperLeft, s.upperRight, s.topT)

template getHorizontalSep(state: var FmtState, s: BoxStyle): RenderBox =
  getGenericBorder(state.colStack[^1], state.curStyle, s.horizontal,
                   s.leftT, s.rightT, s.cross)

template getBottomBorder(state: var FmtState, s: BoxStyle): RenderBox =
  getGenericBorder(state.colStack[^1], state.curStyle, s.horizontal,
                   s.lowerLeft, s.lowerRight, s.bottomT)

proc preRenderTable(state: var FmtState, r: Rope): RenderBox =
  var
    colWidths: seq[int]
    boxes:     seq[RenderBox]
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
    boxes &= state.preRender(r.thead).boxes
  if r.tbody != Rope(nil):
    boxes &= state.preRender(r.tbody).boxes
  if r.tfoot != Rope(nil):
    boxes &= state.preRender(r.tfoot).boxes
  if r.caption != Rope(nil):
    boxes &= state.preRender(r.caption).boxes

  if state.curStyle.useHorizontalSeparator.getOrElse(false):
    var newBoxes: seq[RenderBox]

    for i, item in boxes:
      newBoxes.add(item)
      if (i + 1) != len(boxes):
        newBoxes.add(state.getHorizontalSep(boxStyle))

    boxes = newBoxes

  if state.curStyle.useTopBorder.getOrElse(false):
    boxes = @[state.getTopBorder(boxStyle)] & boxes

  if state.curStyle.useBottomBorder.getOrElse(false):
    boxes.add(state.getBottomBorder(boxStyle))

  state.popTableWidths()

  result = RenderBox(width: state.totalWidth, boxes: boxes, kind: RbBoxes)

proc emptyTableCell(state: var FmtState): RenderBox =
  result = RenderBox(kind: RbText, width: state.totalWidth,
                     startStyle: state.curStyle)
  # This probably should use "th" if we are in thead, but hey,
  # don't give us empty cells.
  if "td" in styleMap:
    result.startStyle = result.startStyle.mergeStyles(styleMap["td"])

proc adjacentCellsToRowBox(state: var FmtState, boxes: seq[RenderBox]):
                          RenderBox =
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
  for col in boxes:
    let l = col.lines.len()
    if l > rowLines:
      rowLines = l

  # Any cells not of the max height, pad them with spaces.
  for col in boxes:
    if col.lines.len() < rowLines:
      var blankLine: seq[uint32]
      for i in 0 ..< col.width:
        blankLine.add(uint32(Rune(' ')))
      while true:
        col.lines.add(blankLine)
        if col.lines.len() == rowLines:
          break

  # Now we go left to right, line-by-line and assemble the result.  We
  # do this by mutating boxes[0]'s state; we'll end up returning it.

  for n in 0 ..< rowLines:
    if len(boxes) == 1:
      boxes[0].lines[n] = leftBorder & boxes[0].lines[n]
    else:
      boxes[0].lines[n] = leftBorder & boxes[0].lines[n] & sep

  for i, col in boxes[1 .. ^1]:
    for n in 0 ..< rowLines:
      boxes[0].lines[n] &= col.lines[n]
      if i < len(boxes) - 2:
        boxes[0].lines[n] &= sep

  if len(rightBorder) != 0:
    for n in 0 ..< rowLines:
      boxes[0].lines[n] &= rightBorder

  return boxes[0]

proc preRenderRow(state: var FmtState, r: Rope): RenderBox =
  # This is the meat of the table implementation.
  # 1) If the table colWidths array is 0, then we need to
  #    set it based on our # of columns.
  # 2) Pre-render the individual cells to the required width.
  # 3) Flatten cells down, first to a list of render boxes
  #    where all the items are of kind RbText.
  # 4) Merge each cell into a single RbText item that add lines when
  #    there are inter-box margins, and add actual characters to the
  #    lines in order to pad to the cell width. This also needs
  #    to do alignment.
  # 5) Combine the cells horizontally, adding vertical borders.

  var
    widths = state.colStack[^1]
    cell: RenderBox

  # Step 1, make sure col widths are right
  if widths.len() == 0:
    state.popTableWidths()
    let pct = 100 div len(r.cells)
    for i in 0 ..< len(r.cells):
      widths.add(pct)
    state.pushTableWidths(state.percentToActualColumns(widths))

  var
    cellBoxes: seq[RenderBox]
    savedWidth = state.totalWidth

  # This loop does steps 2-4
  for i, width in widths:
    # Step 2, pre-render the cell.
    if i > len(r.cells):
      cell = state.emptyTableCell()
    else:
      state.totalWidth = width
      cell = state.preRender(r.cells[i])

    cell.annotatePaddingAndAlignment(state.curStyle)

    # Step 3, flatten to a render box where the type is RbBoxes, but
    # each item in that is of type RbText
    let flatBox = cell.flattenRenderBox(false)

    # Step 4, Combine the RbText items, ACTUALLY aligning,
    # adding padding and margins to text.
    cellBoxes.add(flatBox.combineTextColumn())

  # Step 5, Combine the cells horizontally into a single RbText
  # object. This involves adding any vertical borders, and filling
  # in any blank lines if individual cells span multiple lines.
  result           = state.adjacentCellsToRowBox(cellBoxes)
  result.width     = savedWidth
  state.totalWidth = savedWidth

proc preRenderRows(state: var FmtState, r: Rope): RenderBox =
  result = RenderBox(kind:       RbBoxes,
                     width:      state.totalWidth,
                     startStyle: state.curStyle)

  for item in r.cells:
    result.boxes.add(state.preRender(item))

proc preRender*(state: var FmtState, r: Rope): RenderBox =
  result = RenderBox(width:      state.totalWidth,
                     startStyle: state.curStyle,
                     kind:       RbBoxes)
  var curRope = r

  while curRope != nil:
    if curRope.fitsInTextBox():
      let textBox = state.createTextBox(r)
      result.boxes.add(textBox)
      curRope = textBox.nextRope
    else:
      let styleOpt = state.getNewStartStyle(curRope)
      var
        style:        FmtStyle
        curRenderBox: RenderBox

      if styleOpt.isSome():
        style = styleOpt.get()

        state.pushStyle(style)
        state.pushPadding()
        # The way we handle padding, is by looking at the current
        # style's padding value. We subtract from the total width, and
        # let the resulting box come back. Then, ad the end, we add
        # the padding values associated with the current style to the
        # box.
      case curRope.kind
      of RopeList:
        if curRope.tag == "ul":
          curRenderBox = state.preRenderUnorderedList(curRope)
        else:
          curRenderBox = state.preRenderOrderedList(curRope)
      of RopeTable:
        curRenderBox = state.preRenderTable(curRope)
      of RopeTableRow:
        curRenderBox = state.preRenderRow(curRope)
      of RopeTableRows:
        curRenderBox =  state.preRenderRows(curRope)
      of RopeAlignedContainer:
        curRenderBox = state.preRender(curRope)
        case curRope.tag[0]
        of 'l':
          curRenderBox.align = AlignL
        of 'c':
          curRenderBox.align = AlignC
        of 'r':
          curRenderBox.align = AlignR
        of 'j':
          curRenderBox.align = AlignJ
        of 'f':
          curRenderBox.align = AlignF
        else:
          discard
      of RopeBreak:
        curRenderBox = state.preRender(curRope.guts)
      of RopeTaggedContainer:
        curRenderBox = state.preRender(curRope.contained)
      of RopeFgColor, RopeBgColor:
        curRenderBox = state.preRender(curRope.toColor)
      else:
        discard

      curRenderBox.annotatePaddingAndAlignment(state.curStyle)
      result.boxes.add(curRenderBox)
      curRope = curRope.next

      if styleOpt.isSome():
        state.popPadding()
        state.popStyle()

  result = result.flattenRenderBox(false)

  for box in result.boxes:
     for i in 0 ..< len(box.lines):
       box.lines[i] = box.lines[i].truncateToWidth(box.width)

proc preRender*(r: Rope, width = -1): TextPlane =
  ## This function takes a rope, and returns a pre-render box, which
  ## will have all formatting applied that
  ##
  ## 1. Applied any padding, alignment and wrapping / cropping that is
  ##    explict in the formatting. This is done by putting values in
  ##    for number of pad chars, not by adding chars into the content.

  ##    the approach here is to defer the actual padding until we go
  ##    to render when possible. If we get the width of a character
  ##    wrong relative to what actually gets printed due to some font
  ##    issue, the terminal may be able to tell us our position, and
  ##    we may be able to correct by adding extra padding to the
  ##    right.
  ##

  ## 2. Denoted in the stream of characters to output, what styles
  ##    should be applied, when. We do this by dropping in unique
  ##    values into the uint32 stream that cannot be codepoints.  This
  ##    instructs the rendering implementation what style to push.
  ##
  ##    There's a value for pop as well.
  ##
  ##    Plus, boxes have a 'start' style that gets pushed at the start
  ##    of a box, and popped at the end, implicitly.
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
    # The -1 shouldn't be necessary...
    state.totalWidth = terminalWidth() - 1
  else:
    state.totalWidth = width

  if state.totalWidth <= 0:
    state.totalWidth = defaultTextWidth

  echo "Width = ", state.totalWidth

  let
    preRender = state.preRender(r)
    prePlane  = preRender.combineTextColumn()

  result.lines    = prePlane.lines
  result.width    = prePlane.width

  if len(result.lines) != 0:
    result.lines[0] = @[prePlane.startStyle.getStyleId()] & result.lines[0]
    result.lines[^1].add(StylePop)
