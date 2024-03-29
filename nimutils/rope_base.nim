import unicode, tables, options, unicodeid, unicodedb/properties, misc
const
 defaultTextWidth* {.intdefine.}    = 80
 bareMinimumColWidth* {.intdefine.} = 2
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
    BorderLeft         = 3,
    BorderRight        = 4,
    HorizontalInterior = 5,
    VerticalInterior   = 6,
    BorderTypical      = 7,
    BorderAll          = 8

  FmtStyle* = ref object  # For terminal formatting.
    textColor*:              Option[string]
    bgColor*:                Option[string]
    overflow*:               Option[OverflowPreference]
    hang*:                   Option[int]
    lpad*:                   Option[int]
    rpad*:                   Option[int]
    tmargin*:                Option[int]
    bmargin*:                Option[int]
    casing*:                 Option[TextCasing]
    bold*:                   Option[bool]
    inverse*:                Option[bool]
    strikethrough*:          Option[bool]
    italic*:                 Option[bool]
    underlineStyle*:         Option[UnderlineStyle]
    bulletChar*:             Option[Rune]
    minTableColWidth*:       Option[int]   # Currently not used.
    maxTableColWidth*:       Option[int]   # Currently not used.
    useTopBorder*:           Option[bool]
    useBottomBorder*:        Option[bool]
    useLeftBorder*:          Option[bool]
    useRightBorder*:         Option[bool]
    useVerticalSeparator*:   Option[bool]
    useHorizontalSeparator*: Option[bool]
    boxStyle*:               Option[BoxStyle]
    alignStyle*:             Option[AlignStyle]

  BoxStyle* = ref object
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
    RopeFgColor, RopeBgColor, RopeLink, RopeTaggedContainer,
    RopeAlignedContainer

  BreakKind* = enum
    # For us, a single new line translates to a soft line break that
    # we might or might not want to output. Two newlines we count as
    # a 'hard' line break; the user definitely wanted a line break, but
    # it might also be a paragraph break depending on the context.
    BrSoftLine, BrHardLine, BrParagraph, BrPage

  ColInfo* = object
    span*:     int
    widthPct*: int

  Rope* = ref object
    next*:       Rope
    cycle*:      bool
    tag*:        string
    id*:         string
    class*:      string
    width*:      int       # Requested width in columns for a container

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
    of RopeTaggedContainer, RopeAlignedContainer:
      contained*: Rope
    of RopeTable:
      colInfo*: seq[ColInfo]
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

let
  BoxStylePlain* =     BoxStyle(horizontal: Rune(0x2500),
                                vertical:   Rune(0x2502),
                                upperLeft:  Rune(0x250c),
                                upperRight: Rune(0x2510),
                                lowerLeft:  Rune(0x2514),
                                lowerRight: Rune(0x2518),
                                cross:      Rune(0x253c),
                                topT:       Rune(0x252c),
                                bottomT:    Rune(0x2534),
                                leftT:      Rune(0x251c),
                                rightT:     Rune(0x2524))
  BoxStyleBold* =      BoxStyle(horizontal: Rune(0x2501),
                                vertical:   Rune(0x2503),
                                upperLeft:  Rune(0x250f),
                                upperRight: Rune(0x2513),
                                lowerLeft:  Rune(0x2517),
                                lowerRight: Rune(0x251b),
                                cross:      Rune(0x254b),
                                topT:       Rune(0x2533),
                                bottomT:    Rune(0x253b),
                                leftT:      Rune(0x2523),
                                rightT:     Rune(0x252b))
  BoxStyleDouble* =    BoxStyle(horizontal: Rune(0x2550),
                                vertical:   Rune(0x2551),
                                upperLeft:  Rune(0x2554),
                                upperRight: Rune(0x2557),
                                lowerLeft:  Rune(0x255a),
                                lowerRight: Rune(0x255d),
                                cross:      Rune(0x256c),
                                topT:       Rune(0x2566),
                                bottomT:    Rune(0x2569),
                                leftT:      Rune(0x2560),
                                rightT:     Rune(0x2563))
  BoxStyleDash* =      BoxStyle(horizontal: Rune(0x2554),
                                vertical:   Rune(0x2556),
                                upperLeft:  Rune(0x250c),
                                upperRight: Rune(0x2510),
                                lowerLeft:  Rune(0x2514),
                                lowerRight: Rune(0x2518),
                                cross:      Rune(0x253c),
                                topT:       Rune(0x252c),
                                bottomT:    Rune(0x2534),
                                leftT:      Rune(0x251c),
                                rightT:     Rune(0x2524))
  BoxStyleDash2* =     BoxStyle(horizontal: Rune(0x2558),
                                vertical:   Rune(0x255a),
                                upperLeft:  Rune(0x250c),
                                upperRight: Rune(0x2510),
                                lowerLeft:  Rune(0x2514),
                                lowerRight: Rune(0x2518),
                                cross:      Rune(0x253c),
                                topT:       Rune(0x252c),
                                bottomT:    Rune(0x2534),
                                leftT:      Rune(0x251c),
                                rightT:     Rune(0x2524))
  BoxStyleBoldDash* =  BoxStyle(horizontal: Rune(0x2505),
                                vertical:   Rune(0x2507),
                                upperLeft:  Rune(0x250f),
                                upperRight: Rune(0x2513),
                                lowerLeft:  Rune(0x2517),
                                lowerRight: Rune(0x251b),
                                cross:      Rune(0x254b),
                                topT:       Rune(0x2533),
                                bottomT:    Rune(0x253b),
                                leftT:      Rune(0x2523),
                                rightT:     Rune(0x252b))
  BoxStyleBoldDash2* = BoxStyle(horizontal: Rune(0x2509),
                                vertical:   Rune(0x250b),
                                upperLeft:  Rune(0x250f),
                                upperRight: Rune(0x2513),
                                lowerLeft:  Rune(0x2517),
                                lowerRight: Rune(0x251b),
                                cross:      Rune(0x254b),
                                topT:       Rune(0x2533),
                                bottomT:    Rune(0x253b),
                                leftT:      Rune(0x2523),
                                rightT:     Rune(0x252b))


proc copyStyle*(inStyle: FmtStyle): FmtStyle =
  result = FmtStyle(textColor:              inStyle.textColor,
                    bgColor:                inStyle.bgColor,
                    overflow:               inStyle.overFlow,
                    tmargin:                inStyle.tmargin,
                    bmargin:                inStyle.bmargin,
                    casing:                 inStyle.casing,
                    bold:                   inStyle.bold,
                    inverse:                inStyle.inverse,
                    strikethrough:          inStyle.strikethrough,
                    italic:                 inStyle.italic,
                    underlineStyle:         inStyle.underlineStyle,
                    bulletChar:             inStyle.bulletChar,
                    minTableColWidth:       inStyle.minTableColWidth,
                    maxTableColWidth:       inStyle.maxTableColWidth,
                    useTopBorder:           inStyle.useTopBorder,
                    useBottomBorder:        inStyle.useBottomBorder,
                    useLeftBorder:          inStyle.useLeftBorder,
                    useRightBorder:         inStyle.useRightBorder,
                    useVerticalSeparator:   inStyle.useVerticalSeparator,
                    useHorizontalSeparator: inStyle.useHorizontalSeparator,
                    boxStyle:               inStyle.boxStyle,
                    alignStyle:             inStyle.alignStyle)


let DefaultBoxStyle* = BoxStyleDouble

proc `$`*(plane: TextPlane): string =
  # This is more intended for rebugging.
  for line in plane.lines:
    for ch in line:
      if ch <= 0x10ffff:
        result.add(Rune(ch))
      else:
        result &= "<<" & $(ch) & ">>"
    result.add('\n')

proc mergeTextPlanes*(dst: var TextPlane, append: TextPlane) =
  if len(dst.lines) == 0:
    dst.lines = append.lines
  elif len(append.lines) != 0:
    dst.lines[^1].add(append.lines[0])
    dst.lines &= append.lines[1 .. ^1]

proc mergeTextPlanes*(planes: seq[TextPlane]): TextPlane =
  result = TextPlane()
  for plane in planes:
    result.mergeTextPlanes(plane)

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
  for i, ch in input:
    if ch > 0x10ffff:
      result.add(ch)
    elif not Rune(ch).isWhiteSpace():
      result &= input[i .. ^1]
      return

proc stripSpacesButNotFormattersFromEnd*(input: seq[uint32]): seq[uint32] =
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
