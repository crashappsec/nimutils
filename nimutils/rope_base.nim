import unicode, options, unicodeid, unicodedb/properties, misc, strutils


const
 defaultTextWidth* {.intdefine.}    = 80
 bareMinimumColWidth* {.intdefine.} = 2
 StyleColorPop*                     = 0xfffffffd'u32
 StyleColor*                        = 0xfffffffd'u32
 StyleNoColor*                      = 0xfffffffe'u32
 StylePop*                          = 0xffffffff'u32

type
  FmtKind* = enum
    FmtTerminal, FmtHtml

  OverflowPreference* = enum
    OIgnore, OTruncate, ODots, Overflow, OWrap, OHardWrap, OIndentWrap

  TextCasing* = enum
    CasingIgnore, CasingAsIs, CasingLower, CasingUpper, CasingTitle

  BoldPref* = enum
    BoldIgnore, BoldOn, BoldOff

  InversePref* = enum
    InverseIgnore, InverseOn, InverseOff

  StrikeThruPref* = enum
    StrikeThruIgnore, StrikeThruOn, StrikeThruOff

  ItalicPref* = enum
    ItalicIgnore, ItalicOn, ItalicOff

  UnderlineStyle* = enum
    UnderlineIgnore, UnderlineNone, UnderlineSingle, UnderlineDouble

  AlignStyle* = enum
    AlignIgnore, AlignL, AlignC, AlignR, AlignJ, AlignF
    # J == Normal justify, where the last line (even if it is the
    #      first line) will be left-justified. If a line only
    #      has one word, it will also be left-justified.
    # F == Full Justify, meaning that the final line of a box
    #      will fully justify to the available width.
    #
    # Otherwise, no munging of spaces inside a line is done.
    # For centering, if spaces do not divide evenly, we add the
    # single extra space to the right.

  BorderOpts* = enum
    BorderNone         = 0,
    BorderTop          = 1,
    BorderBottom       = 2,
    BorderLeft         = 4,
    BorderRight        = 8,
    HorizontalInterior = 16,
    VerticalInterior   = 32,
    BorderTypical      = 64,
    BorderAll          = 128

  FmtStyle* = ref object  # For terminal formatting.
    ## Style objects are all expressed as deltas from a currently
    ## active style. When combining styles (with `mergeStyle()`),
    ## anything that is a `some()` object will take priority,
    ## replacing any set value.
    textColor*:              Option[string]
    bgColor*:                Option[string]
    overflow*:               Option[OverflowPreference]
    hang*:                   Option[int]
    lpad*:                   Option[int]
    rpad*:                   Option[int]
    tpad*:                   Option[int]
    bpad*:                   Option[int]
    casing*:                 Option[TextCasing]
    bold*:                   Option[bool]
    inverse*:                Option[bool]
    strikethrough*:          Option[bool]
    italic*:                 Option[bool]
    underlineStyle*:         Option[UnderlineStyle]
    bulletChar*:             Option[Rune]
    useTopBorder*:           Option[bool]
    useBottomBorder*:        Option[bool]
    useLeftBorder*:          Option[bool]
    useRightBorder*:         Option[bool]
    useVerticalSeparator*:   Option[bool]
    useHorizontalSeparator*: Option[bool]
    boxStyle*:               Option[BoxStyle]
    alignStyle*:             Option[AlignStyle]

  BoxStyle* = ref object
    ## This data structure specifies what Unicode characters to use
    ## for different styles of box. Generally, you should not need to
    ## do anything custom, as we provide all the standard options in
    ## the unicode set. Some of them (particularly the dashed ones)
    ## are not universally provided, so should be avoided if you're
    ## not providing some sort of accomidation.
    horizontal*: Rune
    vertical*:   Rune
    upperLeft*:  Rune
    upperRight*: Rune
    lowerLeft*:  Rune
    lowerRight*: Rune
    cross*:      Rune
    topT*:       Rune
    bottomT*:    Rune
    leftT*:      Rune
    rightT*:     Rune

  RopeKind* = enum
    RopeAtom, RopeBreak, RopeList, RopeTable, RopeTableRow, RopeTableRows,
    RopeFgColor, RopeBgColor, RopeLink, RopeTaggedContainer

  BreakKind* = enum
    # For us, a single new line translates to a soft line break that
    # we might or might not want to output. Two newlines we count as
    # a 'hard' line break; the user definitely wanted a line break, but
    # it might also be a paragraph break depending on the context.
    BrSoftLine, BrHardLine, BrParagraph, BrPage

  ColInfo* = object
    ## Spans are not yet implemented.
    span*:   int
    wValue*: int
    absVal*: bool

  Rope* = ref object
    ## The core rope object.  Generally should only access via API.
    next*:          Rope
    cycle*:         bool
    noTextExtract*: bool
    id*:            string
    tag*:           string
    class*:         string
    style*:         FmtStyle  # Cached 
    tweak*:         FmtStyle  # temporary
    processed*:     bool

    case kind*: RopeKind
    of RopeAtom:
      length*: int
      text*: seq[Rune]
    of RopeBreak:
      breakType*: BreakKind
      guts*:        Rope
    of RopeLink:
      url*: string
      toHighlight*: Rope
    of RopeList:
      items*: seq[Rope]
    of RopeTaggedContainer:
      contained*: Rope
      width*:      int  # Requested width in columns for a container.
    of RopeTable:
      colInfo*: seq[ColInfo]
      numCols*: int
      thead*:   Rope # RopeTableRows
      tbody*:   Rope # RopeTableRows
      tfoot*:   Rope # RopeTableRows
      caption*: Rope # RopeTaggedContainer
    of RopeTableRow, RopeTableRows:
      cells*: seq[Rope]
    of RopeFgColor, RopeBgColor:
      color*: string
      toColor*: Rope

  TextPlane* = ref object
    lines*:     seq[seq[uint32]]
    width*:     int # Advisory.
    softBreak*: bool

proc `$`*(s: FmtStyle): string =
  if s == nil:
    return "<none>"
  if s.textColor.isSome():
    result &= "fg=" & s.textColor.get() & "; "
  if s.bgColor.isSome():
    result &= "bg=" & s.bgColor.get() & "; "
  if s.overflow.isSome():
    case s.overflow.get()
    of OIgnore:
      discard
    of OTruncate:
      result &= "truncate; "
    of ODots:
      result &= "dot truncate; "
    of Overflow:
      result &= "nowrap; "
    of OWrap:
      result &= "wrap; "
    of OHardWrap:
      result &= "hard wrap; "
    of OIndentWrap:
      result &= "wrap indent=" & $(s.hang.getOrElse(0)) & "; "
  if s.lpad.isSome() or s.rpad.isSome() or s.tpad.isSome() or
     s.bpad.isSome():
    result &= "pads: l=" & $(s.lpad.get(0)) & "; r=" & $(s.rpad.get(0))
    result &= " ;t=" & $(s.tpad.get(0)) & " ;b=" & $(s.bpad.get(0)) & "; "
  if s.casing.isSome():
    case s.casing.get()
    of CasingIgnore:
      discard
    of CasingAsIs:
      result &= "casing=asis; "
    of CasingLower:
      result &= "casing=lower; "
    of CasingUpper:
      result &= "casing=upper; "
    of CasingTitle:
      result &= "casing=title; "
  if s.bold.isSome():
    case s.bold.get()
    of true:
      result &= "bold=y; "
    else:
      result &= "bold=n; "
  if s.inverse.isSome():
    case s.inverse.get()
    of true:
      result &= "inverse=y; "
    else:
      result &= "inverse=n; "
  if s.strikethrough.isSome():
    case s.strikethrough.get()
    of true:
      result &= "strikethru=y; "
    else:
      result &= "strikethru=n; "
  if s.italic.isSome():
    case s.italic.get()
    of true:
      result &= "italic=y; "
    else:
      result &= "italic=n; "
  if s.underlineStyle.isSome():
    case s.underlineStyle.get()
    of UnderlineSingle:
      result &= "uline=yes; "
    of UnderlineDouble:
      result &= "uline=double; "
    of UnderlineNone:
      result &= "uline=no; "
    else:
      discard
  if s.alignStyle.isSome():
    case s.alignStyle.get()
    of AlignL:
      result &= "align=left; "
    of AlignR:
      result &= "align=right; "      
    of AlignC:
      result &= "align=center; "      
    of AlignJ:
      result &= "align=justify; "      
    of AlignF:
      result &= "align=flush; "
    else:
      discard
    
template genericRopeWalk*(r: Rope, someFunc: untyped, someData: untyped) =
  # This doesn't invoke r.next so that the caller can do things after 
  # descending but before calling the next item.
  if r != nil:
    case r.kind
    of RopeBreak:
      r.guts.somefunc(someData)
    of RopeLink:
      r.toHighlight.somefunc(someData)
    of RopeList:
      for item in r.items:
        item.somefunc(someData)
    of RopeTaggedContainer:
      r.contained.somefunc(someData)
    of RopeTable:
      r.thead.somefunc(someData)
      r.tbody.somefunc(someData)
      r.tfoot.somefunc(someData)
      r.caption.somefunc(someData)
    of RopeTableRow, RopeTableRows:
      for item in r.cells:
        item.somefunc(someData)
    of RopeFgColor, RopeBgColor:
      r.toColor.somefunc(someData)
    else:
      discard

proc buildWalk(r: Rope, results: var seq[Rope]) =
  # Probably should rewrite to use a stack; this could get called
  # on some big ropes.
  if r != nil:
    results.add(r)  
    r.genericRopeWalk(buildWalk, results)
    r.next.buildWalk(results)    

proc ropeWalk*(r: Rope): seq[Rope] =
 r.buildWalk(result)

proc search*(r: Rope,
             tags    = openarray[string]([]),
             classes = openarray[string]([]),
             ids     = openarray[string]([]),
             text    = openarray[string]([]),
             first   = false): seq[Rope] =

  for item in r.ropeWalk():
    if item.tag != "" and len(tags) != 0 and item.tag in tags:
      result.add(item)
    elif item.class != "" and len(classes) != 0 and item.class in classes:
      result.add(item)
    elif item.id != "" and len(ids) != 0 and item.id in ids:
      result.add(item)
    elif text.len() != 0 and item.kind == RopeAtom:
      for s in text:
        if s in $(item.text):
          result.add(item)
          break
    if result.len() == 1 and first:
      return

proc search*(r: Rope, tag = "", class = "", id = "", text = "",
             first = false): seq[Rope] =
  var tags, classes, ids, texts: seq[string]

  if tag != "":
    tags.add(tag)
  if class != "":
    classes.add(tag)
  if id != "":
    ids.add(ids)
  if text != "":
    texts.add(text)

  return r.search(tags, classes, ids, texts)

proc searchOne*(r: Rope, tags = @[""], class = @[""], id = @[""], text = @[""]):
              Option[Rope] =
  let preResult = r.search(tags, class, id, text, true)

  if len(preResult) == 1:
    return some(preResult[0])

proc `$`*(plane: TextPlane): string =
  ## Produce a debug representation of a TextPlane object.
  for line in plane.lines:
    for ch in line:
      if ch <= 0x10ffff:
        result.add(Rune(ch))
      else:
        result &= "<<" & $(ch) & ">>"
    result.add('\n')

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
    if rune > 0x10ffff:
      continue
    if not canGenerateBreakpoint:
      if Rune(rune).isWhiteSpace():
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

proc stripSpacesButNotFormatters*(input: seq[uint32]): seq[uint32] =
  ## Given a sequence of 32-bit integers that contains a combination of
  ## runes and formatting markers, strips white space off both sides,
  ## but without removing any formatting markers.
  ##
  ## While subsequent format markers *can* be elided, we haven't
  ## bothered yet.
  for i, ch in input:
    if ch > 0x10ffff:
      result.add(ch)
    elif not Rune(ch).isWhiteSpace():
      result &= input[i .. ^1]
      return

proc stripSpacesButNotFormattersFromEnd*(input: seq[uint32]): seq[uint32] =
  ## Same as `stripSpacesButNotFormatters`, but does only removes
  ## white space from the end.
  var n = len(input)
  while n > 0:
    n -= 1
    if input[n] > 0x10ffff or not Rune(input[n]).isWhiteSpace():
      break

  while n > 0:
    n -= 1
    let ch = input[n]
    if ch > 0x10ffff:
      result = @[ch] & result
    else:
      return input[0 ..< n] & result

proc softWrapLine(input: seq[uint32], maxWidth, hang: int): seq[seq[uint32]] =
  # After any line wrap, we will want to just drop trailing spaces,
  # but keep in formatting.
  var
    line       = input
    lineWidth  = line.u32LineLength()
    width      = if maxWidth < 1: 1 else: maxWidth

  while true:
    if len(line) == 0:
      break

    var
      breakOps      = line.getBreakOpps()
      curBpIx       = 0
      curWidth      = 0
      bestBp        = -1

    for i, ch in line:
      if (curWidth + ch.runeWidth()) > width:
        if bestBp == -1:
          # Hard break here, sorry.
          bestBp = i
          break
        else:
          break

      curWidth += ch.runeWidth()

      if curBpIx < len(breakOps) and breakOps[curBpIx] == i:
        bestBp   = i
        curBpIx += 1

    if len(line) == 0:
      break
    if bestBp == -1 or curWidth < width:
      result.add(line)
      break

    lineWidth -= curWidth

    result.add(line[0 ..< bestBp])
    line = line[bestBp .. ^1].stripSpacesButNotFormatters()
    if hang < width:
      line = uint32(Rune(' ')).repeat(hang) & line

proc findTruncationIndex(s: seq[uint32], width: int): int =
  var remaining = width

  for i, ch in s:
    remaining -= ch.runeWidth()
    if remaining < 0:
      return i

  return len(s)

proc ensureFormattingIsPerLine(plane: var TextPlane) =
  var
    nextStart: uint32
    n: int


  for i in 0 ..< len(plane.lines):
    if i != 0:
      if plane.lines.len() == 0:
        plane.lines[i] = @[nextStart]
      else:
        plane.lines[i] = @[nextStart] & plane.lines[i]
    n = len(plane.lines[i])
    while n != 0:
      n         = n - 1
      nextStart = plane.lines[i][n]

      if nextStart > 0x10ffff:
        break
    if i + 1 != len(plane.lines):
      plane.lines[i] &= @[StylePop]

proc wrapToWidth*(plane: var TextPlane, style: FmtStyle, w: int) =
  ## Wraps the text that's already laid out in a TextPlane object,
  ## using the given overflow strategy. Generally, this should
  ## probably only be used internally; see `truncateToWidth()` for
  ## something that will operate on UTF-32 (arrays of codepoints).
  # First, we're going to do a basic wrap, without regard to style
  # indicators. But then we want each line to have the correct stack
  # state, so we'll go back through and figure out when we need to add
  # pops to the end of one line, which will cause us to add
  # corresponding pushes to the start of the next line.
  #
  # Ideally, we'd be able to optimize that some, but not going to
  # bother.
  var newLines: seq[seq[uint32]]

  case style.overFlow.getOrElse(OIgnore):
    of OverFlow, OIgnore:
      discard
    of OTruncate:
      for i in 0 ..< plane.lines.len():
        plane.lines[i] = plane.lines[i].truncateToWidth(w)
    of ODots:
      for i in 0 ..< plane.lines.len():
        let ix = plane.lines[i].findTruncationIndex(w - 1)
        if ix < len(plane.lines[i]):
          let truncating = plane.lines[i][ix .. ^1]
          plane.lines[i] = plane.lines[i][0 ..< ix]
          plane.lines[i].add(0x2026) # "…"
          for ch in truncating:
            if ch > 0x10ffff:
              plane.lines[i].add(ch)
    of OHardWrap:
      var newLines: seq[seq[uint32]]
      for i in 0 ..< plane.lines.len():
        var line = plane.lines[i]
        while true:
          let ix = line.findTruncationIndex(w)
          if ix == line.len():
            newLines.add(line)
            break
          else:
            newlines.add(line[0 ..< ix])
            line = line[ix .. ^1]
      plane.lines = newLines
    of OWrap:
      for line in plane.lines:
        newLines &= line.softWrapLine(w, 0)
      plane.lines = newLines
    of OIndentWrap:
      let hang = style.hang.getOrElse(2)
      for line in plane.lines:
        newLines &= line.softWrapLine(w, hang)
      plane.lines = newLines

  plane.ensureFormattingIsPerLine()
