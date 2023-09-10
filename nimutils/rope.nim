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
## TODO: padding on generic breaking containers, etc.
## TODO: Apply color to bullets.
## TODO: Tables.
## TODO: Alignment for block styles.
## TODO: Spacing around specific elements like li or ol
## TODO: Add back cycle check
## TODO: Test indentation
##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import os, unicode, unicodedb, unicodedb/widths, unicodeid, sugar,
       htmlparse, tables, std/terminal, parseutils, options, colortable
# Remove these when done enough.
import managedtmp, posix
from strutils import join, startswith, replace

let sigNameMap = { 1: "SIGHUP", 2: "SIGINT", 3: "SIGQUIT", 4: "SIGILL",
                   6: "SIGABRT",7: "SIGBUS", 9: "SIGKILL", 11: "SIGSEGV",
                   15: "SIGTERM" }.toTable()

proc regularTerminationSignal(signal: cint) {.noconv.} =
  try:
   echo("Aborting due to signal: " & sigNameMap[signal] & "(" & $(signal) &
      ")")
   echo "Stack trace: \n" & getStackTrace()

  except:
    discard

  var sigset:  SigSet

  discard sigemptyset(sigset)

  for signal in [SIGHUP, SIGINT, SIGQUIT, SIGILL, SIGABRT, SIGBUS, SIGKILL,
                 SIGSEGV, SIGTERM]:
    discard sigaddset(sigset, signal)
  discard sigprocmask(SIG_SETMASK, sigset, sigset)

  tmpfile_on_exit()
  exitnow(signal + 128)

proc setupSignalHandlers*() =
  var handler: SigAction

  handler.sa_handler = regularTerminationSignal
  handler.sa_flags   = 0

  for signal in [SIGHUP, SIGINT, SIGQUIT, SIGILL, SIGABRT, SIGBUS, SIGKILL,
                 SIGSEGV, SIGTERM]:
    discard sigaction(signal, handler, nil)

setupSignalHandlers()

const defaultTextWidth* {.intdefine.} = 80

type
  FmtKind* = enum
    FmtTerminal, FmtHtml

  OverflowPreference* = enum
    OIgnore, OTruncate, ODots, Overflow, OWrap, OIndent, OHardWrap

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

  FormattedOutput* = object
    contents:        seq[string]
    maxWidth:        int
    lineWidths:      seq[int]
    startsWithBreak: bool
    finalBreak:      bool

  FmtStyle* = ref object  # For terminal formatting.
    textColor:        Option[string]
    bgColor:          Option[string]
    overflow:         Option[OverflowPreference]
    wrapIndent:       Option[int]
    lpad:             Option[int]
    rpad:             Option[int]
    lpadChar:         Option[Rune]
    rpadChar:         Option[Rune]
    casing:           Option[TextCasing]
    paragraphSpacing: Option[int]
    bold:             Option[bool]
    inverse:          Option[bool]
    strikethrough:    Option[bool]
    italic:           Option[bool]
    underlineStyle:   Option[UnderlineStyle]
    bulletChar:       Option[Rune]
    bulletTextColor:  Option[string]
    bulletTextBg:     Option[string]

  FmtState* = object
    availableWidth: int
    totalWidth:     int
    curStyle:       FmtStyle
    styleStack:     seq[FmtStyle]

  RopeKind* = enum
    RopeAtom, RopeBreak, RopeList, RopeTable, RopeTableRow, RopeTableRows,
    RopeFgColor, RopeBgColor, RopeLink, RopeTaggedContainer,
    RopeAlignedContainer, RopeCustom

  BreakKind* = enum
    # For us, a single new line translates to a soft line break that
    # we might or might not want to output. Two newlines we count as
    # a 'hard' line break; the user definitely wanted a line break, but
    # it might also be a paragraph break depending on the context.
    BrSoftLine, BrHardLine, BrParagraph, BrPage

  Rope* = ref object
    next:        Rope
    prev:        Rope
    cycle:       bool
    style*:      FmtStyle  # Style options for this node
    tag*:        string
    inherited:   FmtStyle

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
      thead*:   Rope # RopeTableRows
      tbody*:   Rope # RopeTableRows
      tfoot*:   Rope # RopeTableRows
      caption*: Rope # RopeTaggedContainer
    of RopeTableRow, RopeTableRows:
      cells*: seq[Rope]
    of RopeFgColor, RopeBgColor:
      color*: string
      toColor*: Rope
    of RopeCustom:
      contents*: RootRef
      toString*: (Rope) -> string
      ropeCopy*: (var Rope, Rope) -> void

template setAtomLength(r: Rope) =
  if r.length == 0:
    for ch in r.text:
      r.length += ch.runeWidth()

proc copyStyle*(inStyle: FmtStyle): FmtStyle =
  result = FmtStyle(textColor:       inStyle.textColor,
                    bgColor:         inStyle.bgColor,
                    overflow:        inStyle.overFlow,
                    wrapIndent:      inStyle.wrapIndent,
                    lpad:            inStyle.lpad,
                    rpad:            inStyle.rpad,
                    lpadChar:        inStyle.lpadChar,
                    rpadChar:        inStyle.rpadChar,
                    casing:          inStyle.casing,
                    bold:            inStyle.bold,
                    inverse:         inStyle.inverse,
                    strikethrough:   inStyle.strikethrough,
                    italic:          inStyle.italic,
                    underlineStyle:  inStyle.underlineStyle,
                    bulletChar:      inStyle.bulletChar,
                    bulletTextColor: inStyle.bulletTextColor,
                    bulletTextBg:    inStyle.bulletTextBg)

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
  if changes.bulletTextColor.isSome():
    result.bulletTextColor = changes.bulletTextColor
  if changes.bulletTextBg.isSome():
    result.bulletTextBg = changes.bulletTextBg

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

proc getBulletTextColor(s: FmtState): Option[string] =
  return s.curStyle.bulletTextColor

proc getBulletTextBg(s: FmtState): Option[string] =
  return s.curStyle.bulletTextBg

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

proc newStyle*(fgColor = "", bgColor = "", overflow = OIgnore,
               wrapIndent = -1, lpad = -1, rpad = -1, lPadChar = Rune(0x0000),
               rpadChar = Rune(0x0000), casing = CasingIgnore,
               paragraphSpacing = -1, bold = BoldIgnore,
               inverse = InverseIgnore, strikethru = StrikeThruIgnore,
               italic = ItalicIgnore, underline = UnderlineIgnore): FmtStyle =
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

var
  defaultStyle* = newStyle(overflow = OWrap, rpad = 1, lpadChar = Rune(' '),
                           lpad = 0, rpadChar = Rune(' '), paragraphSpacing = 1)

  styleMap*: Table[string, FmtStyle] = {
    "h1" : FmtStyle(bgColor: some("white"), textColor: some("blue"),
                       bold: some(true), italic: some(true),
                       casing: some(CasingUpper)),
    "h2" : FmtStyle(textColor: some("blue"), bgColor: some("white"),
                    bold: some(true), italic: some(true),
                    casing: some(CasingTitle)),
    "h3" : FmtStyle(textColor: some("dodgerblue"), italic: some(true),
                    underlineStyle: some(UnderlineDouble), casing:
                      some(CasingTitle)),
    "h4" : FmtStyle(textColor: some("skyblue"), italic: some(true),
                    underlineStyle: some(UnderlineSingle),
                    casing: some(CasingTitle)),
    "h5" : FmtStyle(textColor: some("powderblue"), bgColor: some("black"),
                    italic: some(true), casing: some(CasingTitle)),
    "h6" : FmtStyle(textColor: some("powderblue"), bgColor: some("black"),
                    underlineStyle: some(UnderlineSingle),
                    casing: some(CasingTitle)),
    "ol" : FmtStyle(bulletChar: some(Rune('.')), lpad: some(2)),
    "ul" : FmtStyle(bulletchar: some(Rune(0x2022)), lpad: some(2)) #•
    }.toTable()

  breakingStyles*: Table[string, bool] = {
    "p"          : true,
    "div"        : true,
    "ol"         : true,
    "ul"         : true,
    "li"         : true,
    "blockquote" : true,
    "code"       : true,
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

proc refCopy*(dst: var Rope, src: Rope) =
  dst.kind = src.kind
  dst.tag  = src.tag

  case src.kind
  of RopeAtom:
    dst.length = src.length
    dst.text   = src.text

  of RopeBreak:
    dst.breakType = src.breakType
    dst.guts      = Rope()
    refCopy(dst.guts, src.guts)

  of RopeLink:
    dst.url = src.url
    var sub: Rope = Rope()
    refCopy(sub, src.toHighlight)
    dst.toHighlight = sub

  of RopeList:
    var
      sub: Rope
      l:   seq[Rope]
    for item in src.items:
      sub = Rope()
      refCopy(sub, item)
      l.add(sub)
    dst.items = l

  of RopeTaggedContainer, RopeAlignedContainer:
    var sub: Rope = Rope()
    refCopy(sub, src.contained)
    dst.contained = sub

  of RopeTable:
    if src.thead != nil:
      dst.thead = Rope()
      refCopy(dst.thead, src.thead)
    if src.tbody != nil:
      dst.tbody = Rope()
      refCopy(dst.tbody, src.tbody)
    if src.tfoot != nil:
      dst.tfoot = Rope()
      refCopy(dst.tfoot, src.tfoot)
    if src.caption != nil:
      dst.caption = Rope()
      refCopy(dst.caption, src.caption)

  of RopeTableRow, RopeTableRows:
    for cell in src.cells:
      var r = Rope()
      refCopy(r, cell)
      dst.cells.add(r)

  of RopeFgColor, RopeBgColor:
    dst.color   = src.color
    dst.toColor = Rope()
    refCopy(dst.toColor, src.toColor)

  of RopeCustom:
    src.ropeCopy(dst, src)

  if src.next != nil:
    var f = Rope()
    refCopy(f, src.next)
    dst.next = f

proc `&`*(r1: Rope, r2: Rope): Rope =
  var
    dupe1: Rope = Rope()
    dupe2: Rope = Rope()
    probe: Rope

  if r1 == nil and r2 == nil:
    return nil
  elif r1 == nil:
    refCopy(dupe1, r2)
    return dupe1
  elif r2 == nil:
    refCopy(dupe1, r1)
    return dupe1

  refCopy(dupe1, r1)
  refCopy(dupe2, r2)
  probe = dupe1
  while probe.next != nil:
    probe = probe.next

  probe.next = dupe2

  return dupe1

proc `+`*(r1: Rope, r2: Rope): Rope =
  if r1 == nil:
    return r2
  if r2 == nil:
    return r1

  var
    probe: Rope = r1
    last:  Rope

  while true:
    probe.cycle = true
    if probe.next == nil:
      break
    probe = probe.next

  last  = probe
  probe = r2

  while probe != nil:
    if probe.cycle:
       raise newException(ValueError, "Addition would cause a cycle")
    else:
      probe = probe.next

  probe = r1
  while probe != nil:
    probe.cycle = false
    probe = probe.next

  last.next = r2

  return r1

proc rawStrToRope*(s: string): Rope =
  result = Rope(kind: RopeAtom)
  var
    prev: Rope
    cur : Rope = result

  for r in s.runes():
    if r.isSeparator():
      if r.isPageBreak():
        prev      = cur
        cur       = Rope(kind: RopeBreak, breakType: BrPage)
        prev.next = cur
      elif r.isParagraphBreak():
        prev      = cur
        cur       = Rope(kind: RopeBreak, breakType: BrParagraph)
        prev.next = cur
      elif r == Rune('\r'):
        # This is either followed by an '\n' or it's spurious.
        continue
      else:
        if cur.kind == RopeBreak and cur.breakType in [BrSoftLine, BrHardLine]:
          cur.breakType = BrHardLine
        else:
          prev = cur
          if r == Rune(0x2028):
            cur = Rope(kind: RopeBreak, breakType: BrHardLine)
          else:
            cur = Rope(kind: RopeBreak, breakType: BrSoftLine)
    else:
      if r.isPrintable():
        if cur.kind != RopeAtom:
          prev      = cur
          cur       = Rope(kind: RopeAtom)
          prev.next = cur

        cur.text.add(r)
        cur.length += r.runeWidth()
      else:
        raise newException(ValueError, "Non-printable text in string")
  if len(result.text) == 0 and result.next != nil:
    result = result.next

iterator segments*(s: Rope): Rope =
  var cur = s

  while cur != nil:
    yield cur
    cur = cur.next

template forAll*(s: Rope, code: untyped) =
  for item in s.segments():
    code

# Only used for things we don't hardcode.
# var converters*: Table[string, (HtmlNode) -> string]

proc htmlTreeToRope(n: HtmlNode): Rope

proc descend(n: HtmlNode): Rope =
  for item in n.children:
    result = result + item.htmlTreeToRope()

proc htmlTreeToRope(n: HtmlNode): Rope =
  case n.kind
  of HtmlDocument:
    result = n.descend()
  of HtmlElement, HtmlTemplate:
    if n.contents.startswith('<') and n.contents[^1] == '>':
      n.contents = n.contents[1 ..< ^1]
    case n.contents
    of "html", "body", "head":
      result = n.descend()
    of "br":
      result = Rope(kind: RopeBreak, breakType: BrHardLine, tag: "br")
    of "p":
      result = Rope(kind: RopeBreak, breakType: BrParagraph,
                    guts: n.descend(), tag: "p")
    of "div":
      result = Rope(kind: RopeBreak, breakType: BrPage,
                    guts: n.descend(), tag: "div")
    of "a":
      let url = if "href" in n.attrs: n.attrs["href"] else: "https://unknown"
      result = Rope(kind: RopeLink, url: url, toHighlight: n.descend(),
                    tag: "a")
    of "ol", "ul":
      result = Rope(kind: RopeList, tag: n.contents)
      for item in n.children:
        result.items.add(item.htmlTreeToRope())
    of "right":
      result = Rope(kind: RopeAlignedContainer, tag: "ralign",
                    contained: n.descend())
    of "center":
      result = Rope(kind: RopeAlignedContainer, tag: "calign",
                    contained: n.descend())
    of "left":
      result = Rope(kind: RopeAlignedContainer, tag: "lalign",
                    contained: n.descend())
    of "thead", "tbody", "tfoot":
      result = Rope(kind:  RopeTableRows, tag: n.contents)
      for item in n.children:
        result.cells.add(item.htmlTreeToRope())
    of "tr":
      result = Rope(kind: RopeTableRow, tag: n.contents)
      for item in n.children:
        result.cells.add(item.htmlTreeToRope())
    of "table":
      result = Rope(kind: RopeTable, tag: "table")
      for item in n.children:
        let asRope = item.htmlTreeToRope()
        case asRope.kind
        of RopeTaggedContainer:
          if asRope.tag == "caption":
            result.caption = asRope
          else:
            discard
        of RopeTable:
          if item.contents == "thead":
            result.thead = asRope
          elif item.contents == "tfoot":
            result.tfoot = asRope
          else:
            result.tbody = asRope
        of RopeTableRow:
          if result.tbody == nil:
            result.tbody = Rope(kind: RopeTableRows, tag: "tbody")
          result.cells.add(asRope)
        else: # colgroup; currently not handling.
          discard
    of "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote",
       "code", "ins", "del", "kbd", "mark", "pre", "q", "s", "small",
       "sub", "sup", "title", "em", "i", "b", "strong", "u", "caption",
       "td", "th", "var", "italic", "strikethrough", "strikethru",
       "underline", "bold":
      # Since we know about this list, short-circuit the color checking code,
      # even though if no color matches, the same thing happens as happens
      # in this branch...
      result = Rope(kind: RopeTaggedContainer, tag: n.contents,
                    contained: n.descend())
    else:
      let colorTable = getColorTable()
      if n.contents in colorTable:
        result = Rope(kind: RopeFgColor, color: n.contents)
        result.toColor = n.descend()
      elif n.contents.startsWith("bg-") and n.contents[3 .. ^1] in colorTable:
        result = Rope(kind: RopeBgColor, color: n.contents[3 .. ^1])
        result.toColor = n.descend()
      elif n.contents.startsWith("#") and len(n.contents) == 7:
        result = Rope(kind: RopeFgColor, color: n.contents[1 .. ^1])
      elif n.contents.startsWith("bg#") and len(n.contents) == 10:
        result = Rope(kind: RopeBgColor, color: n.contents[3 .. ^1])
      else:
        result = Rope(kind: RopeTaggedContainer)
        result.contained = n.descend()
      result.tag = n.contents
  of HtmlText, HtmlCData:
    result = Rope(kind: RopeAtom, text: n.contents.toRunes())
  else:
    discard

converter htmlStringToRope*(s: string): Rope =
  let tree = parseDocument(s)

  return tree.htmlTreeToRope()

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
    if rune.isWhiteSpace:
      result.add(i)
      lastWasSpace = true
    else:
      lastWasSpace = false

proc wrapToWidth(s: seq[Rune], runeLen: int, state: var FmtState): string =
  # This should never have any hard breaks in it.

  case state.getOverflow()
  of Overflow:
    return $(s)
  of OIgnore, OTruncate:
    return $(s[0 ..< state.availableWidth])
  of ODots:
    return $(s[0 ..< (state.availableWidth - 1)]) & "\u2026" # "…"
  of OHardWrap:
    result &= $(s[0 ..< state.availableWidth]) & "\u2028"
    var
      curIndex     = state.availableWidth
      remainingLen = runeLen - state.availableWidth
    while remainingLen > state.totalWidth:
      result &= $(s[curIndex ..< (curIndex + state.totalWidth)]) & "\u2028"
      remainingLen -= state.totalWidth
      curIndex += state.totalWidth

    state.availableWidth = state.totalWidth - remainingLen
    return result & $(s[curIndex .. ^1])
  of OIndent, OWrap:
    discard

  let
    maxIx = s.len()
  var
    currentStart = 0
    remainingLen = runeLen
    probe        = 0
    probeLen     = 0
    lastOp       = 0
    breakPoint: int

  let opps = s.getBreakOpps()
  while true:
    if remainingLen <= state.availableWidth:
      state.availableWidth -= remainingLen
      result &= $(s[currentStart .. ^1])
      break

    probeLen = probe - currentStart
    lastOp   = -1

    while probe < state.availableWidth and probe < maxIx:
      if probe != currentStart and probe in opps:
        lastOp = probe

      probeLen += s[probe].runeWidth()
      if probeLen >= remainingLen:
        break

    if lastOp == -1:
      # No break point?  Just hard break here and shrug.
      breakPoint = currentStart + state.availableWidth
    else:
      breakPoint = lastOp
    result &= $(s[currentStart ..< breakPoint])
    remainingLen        -= (breakPoint - currentStart)
    state.availableWidth = state.totalWidth
    currentStart         = breakPoint
    lastOp               = -1
    if state.getOverflow() == OIndent and
       state.totalWidth > state.getWrapIndent():
      let
        padChar = state.getLpadChar()
        padAmt  = state.getWrapIndent()

      result &= padChar.repeat(padAmt)
      state.availableWidth -= padChar.runeWidth()

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

proc formatUnorderedList(r: Rope, state: var FmtState): FormattedOutput =
  state.withTag("ul"):
    let
      lpadChar  = state.getLpadChar()
      rpadChar  = state.getRpadChar()
      bullet    = state.getBulletChar().get(Rune(0x2022))
      lpad      = state.getLpad()
      rpad      = state.getRpad()
      preStr    = lpadChar.repeat(lpad) & $(bullet) & rpadChar.repeat(rpad)
      preLen    = preStr.runeLength()
      wrapStr   = lpadChar.repeat(preLen)
      savedTW   = state.totalWidth

    if lpadChar.runeWidth() != 1:
      raise newException(ValueError,
                        "Left padding character for lists must be 1 char wide")

    state.totalWidth     -= preLen
    state.availableWidth  = state.totalWidth

    for item in r.items:
      var oneRes = item.internalRopeToString(state)
      for i, line in oneRes.contents:
        if i == 0:
          oneRes.contents[i] = preStr & line
        else:
          oneRes.contents[i] = wrapStr & line
        oneRes.lineWidths[i] = oneRes.lineWidths[i] + preLen
      oneRes.maxWidth += preLen

      combineFormattedOutput(result, oneRes)

    state.totalWidth = savedTw

proc formatOrderedList(r: Rope, state: var FmtState): FormattedOutput =
  var
    maxDigits = 0
    n         = len(r.items)

  while true:
    maxDigits += 1
    n          = n div 10
    if n == 0:
      break

  state.withTag("ol"):
    let
      lpadChar  = state.getLpadChar()
      rpadChar  = state.getRpadChar()
      bullet    = state.getBulletChar().get(Rune(0x200D))
      lpad      = state.getLpad()
      rpad      = state.getRpad()
      preStr    = lpadChar.repeat(lpad)
      postStr   = $(bullet) & rpadChar.repeat(rpad)
      widthLoss = preStr.runeLength() + postStr.runeLength() + maxDigits
      wrapStr   = lpadChar.repeat(widthLoss)
      savedTW   = state.totalWidth

    if lpadChar.runeWidth() != 1:
      raise newException(ValueError,
                         "Left padding character for lists must be 1 char wide")

    state.totalWidth     -= widthLoss
    state.availableWidth  = state.totalWidth

    for n, item in r.items:
      var oneRes = item.internalRopeToString(state)
      for i, line in oneRes.contents:
        if i == 0:
          let
            nAsStr  = $(n + 1)
            fullPre = preStr & lpadChar.repeat(maxDigits - len(nAsStr)) & nAsStr

          oneRes.contents[i] = fullPre & postStr & line
        else:
          oneRes.contents[i] = wrapStr & line
        oneRes.lineWidths[i] = oneRes.lineWidths[i] + widthLoss
      oneRes.maxWidth += widthLoss

      combineFormattedOutput(result, oneRes)

    state.totalWidth = savedTw

proc internalRopeToString(r: Rope, state: var FmtState): FormattedOutput =
  case r.kind
  of RopeAtom:
    r.setAtomLength()
    result = r.formatAtom(state)
  of RopeBreak:
    if r.breakType == BrPage:
      result = FormattedOutput(contents: @["\f"], maxWidth: 0,
                               lineWidths: @[0], finalBreak: true)

    else:
      result = FormattedOutput(contents: @[""], maxWidth: 0,
                               lineWidths: @[0], finalBreak: true)

    if r.guts != nil:
      # TODO: apply formatting.
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
      if state.totalWidth != state.availableWidth:
        raise newException(ValueError, "Alignment tags should appear only " &
          "at the start of paragraph-level elements.")
      result = r.contained.internalRopeToString(state)
      for i, line in result.contents:
        let w = state.totalWidth - result.lineWidths[i]
        if w > 0:
          result.contents[i]   = Rune(' ').repeat(w) & line
          result.lineWidths[i] = state.totalWidth
      state.availableWidth = 0
    of 'c':
      if state.totalWidth != state.availableWidth:
        raise newException(ValueError, "Alignment tags should appear only " &
          "at the start of paragraph-level elements.")

      result = r.contained.internalRopeToString(state)
      for i, line in result.contents:
        let w = state.totalWidth - result.lineWidths[i]
        if w > 0:
          let lpad = if w == 1: "" else: Rune(' ').repeat(w div 2)
          let rpad = if (w and 0x01) == 0: lpad else: lpad & " "
          result.contents[i]   = lpad & line & rpad
          result.lineWidths[i] = state.totalWidth
      state.availableWidth = 0
    else:
      discard
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

    state.withStyleAndTag(newStyle, r.tag):
      result = r.contained.internalRopeToString(state)

    if r.tag in breakingStyles:
      result.finalBreak      = true
      result.startsWithBreak = true
  else:
    discard

  if r.next != nil:
    let next = r.next.internalRopeToString(state)
    combineFormattedOutput(result, next)

proc ropeToString*(r: Rope, width = -1): string =
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

  echo "Starting with width: ", curState.totalWidth

  curState.availableWidth = curState.totalWidth
  curState.curStyle       = defaultStyle

  let preResult = r.internalRopeToString(curstate)
  result = preResult.contents.join("\n")
  if '\f' in result:
    result = result.replace("\f\n", "\f")

proc printOne*(r: Rope) =
  echo ropeToString(r)

proc print*(contents: varargs[Rope]) =
  case len(contents)
  of 0:
    discard
  of 1:
    printOne(contents[0])
  else:
    var toPrint: Rope = contents[0]
    for item in contents[1 .. ^1]:
      toPrint = toPrint & item
    printOne(toPrint)
