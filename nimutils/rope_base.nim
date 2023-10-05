import unicode, tables, options

const
 defaultTextWidth* {.intdefine.}    = 80
 bareMinimumColWidth* {.intdefine.} = 2
 StylePop*                          = 0xffffffff'u32

type
  FmtKind* = enum
    FmtTerminal, FmtHtml

  OverflowPreference* = enum
    OIgnore, OTruncate, ODots, Overflow, OWrap, OHardWrap

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
    wrapIndent*:             Option[int]
    lpad*:                   Option[int]
    rpad*:                   Option[int]
    tmargin*:                Option[int]
    bmargin*:                Option[int]
    lpadChar*:               Option[Rune]
    rpadChar*:               Option[Rune]
    casing*:                 Option[TextCasing]
    paragraphSpacing*:       Option[int]
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
    style*:      FmtStyle  # Style options for this node
    tag*:        string
    id*:         string
    class*:      string

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

  TextPlane* = object
    styleMap*: Table[uint32, FmtStyle]
    lines*:    seq[seq[uint32]]
    width*:    int # Advisory.

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
                    wrapIndent:             inStyle.wrapIndent,
                    lpad:                   inStyle.lpad,
                    rpad:                   inStyle.rpad,
                    lpadChar:               inStyle.lpadChar,
                    rpadChar:               inStyle.rpadChar,
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

let DefaultBoxStyle* = BoxStyleDouble
