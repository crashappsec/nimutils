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
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import os, unicode, unicodedb, unicodedb/widths, sugar, htmlparse,
       tables, std/terminal, parseutils, options, managedtmp, posix
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


# Taken from:HTML color list as found at:
# https://en.wikipedia.org/wiki/Web_colors
let colorTable* = {
  "mediumvioletred"      : 0xc71585,
  "deeppink"             : 0xff1493,
  "palevioletred"        : 0xdb7093,
  "hotpink"              : 0xff69b4,
  "lightpink"            : 0xffb6c1,
  "pink"                 : 0xffc0cb,
  "darkred"              : 0x8b0000,
  "red"                  : 0xff0000,
  "firebrick"            : 0xb22222,
  "crimson"              : 0xdc143c,
  "indianred"            : 0xcd5c5c,
  "lightcoral"           : 0xf08080,
  "salmon"               : 0xfa8072,
  "darksalmon"           : 0xe9967a,
  "lightsalmon"          : 0xffa07a,
  "orangered"            : 0xff4500,
  "tomato"               : 0xff6347,
  "darkorange"           : 0xff8c00,
  "coral"                : 0xff7f50,
  "orange"               : 0xffa500,
  "darkkhaki"            : 0xbdb76b,
  "gold"                 : 0xffd700,
  "khaki"                : 0xf0e68c,
  "peachpuff"            : 0xffdab9,
  "yellow"               : 0xffff00,
  "palegoldenrod"        : 0xeee8aa,
  "moccasin"             : 0xffe4b5,
  "papayawhip"           : 0xffefd5,
  "lightgoldenrodyellow" : 0xfafad2,
  "lemonchiffon"         : 0xfffacd,
  "lightyellow"          : 0xffffe0,
  "maroon"               : 0x800000,
  "brown"                : 0xa52a2a,
  "saddlebrown"          : 0x8b4513,
  "sienna"               : 0xa0522d,
  "chocolate"            : 0xd2691e,
  "darkgoldenrod"        : 0xb8860b,
  "peru"                 : 0xcd853f,
  "rosybrown"            : 0xbc8f8f,
  "goldenrod"            : 0xdaa520,
  "sandybrown"           : 0xfaa460,
  "tan"                  : 0xd2b48c,
  "burlywood"            : 0xdeb887,
  "wheat"                : 0xf5deb3,
  "navajowhite"          : 0xffdead,
  "bisque"               : 0xffe4c4,
  # If I 'fix' the last letter, kitty turns it black??
  "blanchedalmond"       : 0xffebcc,
  "cornsilk"             : 0xfff8cd,
  "indigo"               : 0x4b0082,
  "purple"               : 0x800080,
  "darkmagenta"          : 0x8b008b,
  "darkviolet"           : 0x9400d3,
  "darkslateblue"        : 0x483d8b,
  "blueviolet"           : 0x8a2be2,
  "darkorchid"           : 0x9932cc,
  "fuchsia"              : 0xff00ff,
  "magenta"              : 0xff00ff,
  "slateblue"            : 0x6a5acd,
  "mediumslateblue"      : 0x7b68ee,
  "mediumorchid"         : 0xba55d3,
  "mediumpurple"         : 0x9370db,
  "orchid"               : 0xda70d6,
  "violet"               : 0xee82ee,
  "plum"                 : 0xdda0dd,
  "thistle"              : 0xd8bfd8,
  "lavender"             : 0xe6e6fa,
  "midnightblue"         : 0x191970,
  "navy"                 : 0x000080,
  "darkblue"             : 0x00008b,
  "mediumblue"           : 0x0000cd,
  "blue"                 : 0x0000ff,
  "royalblue"            : 0x4169e1,
  "steelblue"            : 0x4682b4,
  "dodgerblue"           : 0x1e90ff,
  "deepskyblue"          : 0x00bfff,
  "cornflowerblue"       : 0x6495ed,
  "skyblue"              : 0x87ceeb,
  "lightskyblue"         : 0x87cefa,
  "lightsteelblue"       : 0xb0c4de,
  "lightblue"            : 0xadd8e6,
  "powderblue"           : 0xb0e0e6,
  "teal"                 : 0x008080,
  "darkcyan"             : 0x008b8b,
  "lightseagreen"        : 0x20b2aa,
  "cadetblue"            : 0x5f9ea0,
  "darkturquoise"        : 0x00ced1,
  "mediumturquoise"      : 0x48d1cc,
  "turquoise"            : 0x40e0d0,
  "aqua"                 : 0x00ffff,
  "cyan"                 : 0x00ffff,
  "aquamarine"           : 0x7fffd4,
  "paleturquoise"        : 0xafeeee,
  "lightcyan"            : 0xe0ffff,
  "darkgreen"            : 0x006400,
  "green"                : 0x008000,
  "darkolivegreen"       : 0x556b2f,
  "forestgreen"          : 0x228b22,
  "seagreen"             : 0x2e8b57,
  "olive"                : 0x808000,
  "olivedrab"            : 0x6b8e23,
  "mediumseagreen"       : 0x3cb371,
  "limegreen"            : 0x32cd32,
  "lime"                 : 0x00ff00,
  "springgreen"          : 0x00ff7f,
  "mediumspringgreen"    : 0x00fa9a,
  "darkseagreen"         : 0x8fbc8f,
  "mediumaquamarine"     : 0x66cdaa,
  "yellowgreen"          : 0x9acd32,
  "lawngreen"            : 0x7cfc00,
  "chartreuse"           : 0x7fff00,
  "lightgreen"           : 0x90ee90,
  "greenyellow"          : 0xadff2f,
  "palegreen"            : 0x98fb98,
  "mistyrose"            : 0xffe4e1,
  "antiquewhite"         : 0xfaebd7,
  "linen"                : 0xfaf0e6,
  "beige"                : 0xf5f5dc,
  "whitesmoke"           : 0xf5f5f5,
  "lavenderblush"        : 0xfff0f5,
  "oldlace"              : 0xfdf5e6,
  "aliceblue"            : 0xf0f8ff,
  "seashell"             : 0xfff5ee,
  "ghostwhite"           : 0xf8f8ff,
  "honeydew"             : 0xf0fff0,
  "floaralwhite"         : 0xfffaf0,
  "azure"                : 0xf0ffff,
  "mintcream"            : 0xf5fffa,
  "snow"                 : 0xfffafa,
  "ivory"                : 0xfffff0,
  "white"                : 0xffffff,
  "black"                : 0x000000,
  "darkslategray"        : 0x2f4f4f,
  "dimgray"              : 0x696969,
  "slategray"            : 0x708090,
  "gray"                 : 0x808080,
  "lightslategray"       : 0x778899,
  "darkgray"             : 0xa9a9a9,
  "silver"               : 0xc0c0c0,
  "lightgray"            : 0xd3d3d3,
  "gainsboro"            : 0xdcdcdc
}.toOrderedTable()

# These, on the other hand, I tried to eyeball match by printing next
# to the 24-bit value above and adjusting manually.
#
# Google doesn't help here, but my terminals seem pretty consistent,
# even though I don't think there's an explicit standard, and
# different terminals have definitely done different things in the
# past.
#
# Someone should script up some A/B testing to hone in on some of
# these better, but this all looks good enough for now.

let color8Bit =  {
  "mediumvioletred"      : 126,
  "deeppink"             : 206, # Pretty off still. 201, 199
  "palevioletred"        : 167, # Still kinda off. 210, 211
  "hotpink"              : 205,
  "lightpink"            : 217,
  "pink"                 : 218,
  "darkred"              : 88,
  "red"                  : 9,
  "firebrick"            : 124,
  "crimson"              : 160, # Meh. 88, 124,
  "indianred"            : 167,
  "lightcoral"           : 210,
  "salmon"               : 210, # 217, 216,
  "darksalmon"           : 173,
  "lightsalmon"          : 209,
  "orangered"            : 202,
  "tomato"               : 202, # 166,, 196
  "darkorange"           : 208,
  "coral"                : 210, # 203,
  "orange"               : 214,
  "darkkhaki"            : 143,
  "gold"                 : 220,
  "khaki"                : 228,
  "peachpuff"            : 223,
  "yellow"               : 11, # 3
  "palegoldenrod"        : 230, # 228, #178, 143
  "moccasin"             : 230, # 229, # 143, # 217, #
  "papayawhip"           : 230, # 143, # 224,
  "lightgoldenrodyellow" : 230, # 227,
  "lemonchiffon"         : 230, # 178,
  "lightyellow"          : 230, # 231+194 (some green), # 187,
  "maroon"               : 88, # 1,
  "brown"                : 94, # 130, # 166,
  "saddlebrown"          : 95, # 94,
  "sienna"               : 95, # 96, # 137,
  "chocolate"            : 172, # 166, # 131,
  "darkgoldenrod"        : 136,
  "peru"                 : 137, #96, #172, # 137, #
  "rosybrown"            : 138,
  "goldenrod"            : 172, #138, # 227,
  "sandybrown"           : 215,
  "tan"                  : 180, #180
  "burlywood"            : 180, #
  "wheat"                : 223, # 229,
  "navajowhite"          : 223, # 229, # 144,
  "bisque"               : 223, #224-- too salmony
  "blanchedalmond"       : 223, # 223,
  "cornsilk"             : 230,
  "indigo"               : 57, # 56, # 54,
  "purple"               : 91, # 53, # 52, # 55, # 53,
  "darkmagenta"          : 91,
  "darkviolet"           : 91, # 99, # 128,
  "darkslateblue"        : 61, # 17,
  "blueviolet"           : 99, # 91, # 62, # 57,
  "darkorchid"           : 91, # 55, # 92,
  "fuchsia"              : 5,
  "magenta"              : 5,
  "slateblue"            : 62,
  "mediumslateblue"      : 62, # 99,
  "mediumorchid"         : 134,
  "mediumpurple"         : 104,
  "orchid"               : 170,
  "violet"               : 177,
  "plum"                 : 219,
  "thistle"              : 225,
  "lavender"             : 189,
  "midnightblue"         : 17,
  "navy"                 : 18,
  "darkblue"             : 19,
  "mediumblue"           : 20,
  "blue"                 : 21,
  "royalblue"            : 12,
  "steelblue"            : 67,
  "dodgerblue"           : 33,
  "deepskyblue"          : 39,
  "cornflowerblue"       : 69,
  "skyblue"              : 117,
  "lightskyblue"         : 153,
  "lightsteelblue"       : 153, #37, #180, #253, # 147,
  "lightblue"            : 152, # 117,
  "powderblue"           : 152, # 117, #116,
  "teal"                 : 37,
  "darkcyan"             : 37,
  "lightseagreen"        : 37,
  "cadetblue"            : 73,
  "darkturquoise"        : 44,
  "mediumturquoise"      : 80,
  "turquoise"            : 44, #43
  "aqua"                 : 6,
  "cyan"                 : 6,
  "aquamarine"           : 122,
  "paleturquoise"        : 159,
  "lightcyan"            : 195,
  "darkgreen"            : 22,
  "green"                : 28,
  "darkolivegreen"       : 108, #58,
  "forestgreen"          : 28,
  "seagreen"             : 29, #23, # 35,
  "olive"                : 100,
  "olivedrab"            : 100, #58,
  "mediumseagreen"       : 35, # 37,
  "limegreen"            : 40,
  "lime"                 : 10,
  "springgreen"          : 48,
  "mediumspringgreen"    : 49,
  "darkseagreen"         : 108,
  "mediumaquamarine"     : 79,
  "yellowgreen"          : 148,
  "lawngreen"            : 119,
  "chartreuse"           : 118,
  "lightgreen"           : 120,
  "greenyellow"          : 154,
  "palegreen"            : 120, # 156,
  "mistyrose"            : 224, # 212,
  "antiquewhite"         : 230,
  "linen"                : 230, #224,
  "beige"                : 230, #229,
  "whitesmoke"           : 230, # 116,
  "lavenderblush"        : 231, #225,
  "oldlace"              : 231,
  "aliceblue"            : 231, #81,
  "seashell"             : 231, # 223,
  "ghostwhite"           : 231, # 189,
  "honeydew"             : 231, # 194,
  "floaralwhite"         : 231,
  "azure"                : 231,
  "mintcream"            : 231,
  "snow"                 : 231,
  "ivory"                : 7,
  "white"                : 15,
  "black"                : 0,
  "darkslategray"        : 236, # 8,
  "dimgray"              : 242,
  "slategray"            : 245,
  "gray"                 : 8,
  "lightslategray"       : 245,
  "darkgray"             : 247,
  "silver"               : 250,
  "lightgray"            : 250,
  "gainsboro"            : 252
}.toOrderedTable()

var  showColor = if existsEnv("NO_COLOR"): false else: true

proc setShowColor*(val: bool) =
  showColor = val

proc getShowColor*(): bool =
  return showColor

const defaultTextWidth* {.intdefine.} = 80

proc isPrintable*(r: Rune): bool =
  return r.unicodeCategory() in ctgL + ctgM + ctgN + ctgP + ctgS + ctgZs

template isLineBreak*(r: Rune): bool =
  r in [Rune(0x000d), Rune(0x000a), Rune(0x0085),
        Rune(0x000b), Rune(0x2028)]

template isParagraphBreak*(r: Rune): bool =
  r == Rune(0x2029)

template isPageBreak*(r: Rune): bool =
  r == Rune(0x000c)

template isSeparator*(r: Rune): bool =
  r in [Rune(0x000d), Rune(0x000a), Rune(0x0085), Rune(0x000b),
        Rune(0x2028), Rune(0x2029), Rune(0x000c)]

proc runeWidth*(r: Rune): int =
  let category = r.unicodeCategory()

  if category in ctgMn + ctgMe + ctgCf:
    return 0

  if r == Rune(0x200b):
    return 0

  if int(r) >= int(Rune(0x1160)) and int(r) <= int(Rune(0x11ff)):
    return 0

  if r == Rune(0x00ad):
    return 1

  case r.unicodeWidth
  of uwdtFull, uwdtWide:
    return 2
  else:
    return 1

proc runeLength*(s: string): int =
  for r in s.toRunes():
    result += r.runeWidth()

type
  FmtKind* = enum
    FmtTerminal, FmtHtml

  OverflowPreference* = enum
    OIgnore, OTruncate, ODots, Overflow, OWrap, OIndent, OHardWrap

  TextCasing* = enum
    CasingAsIs, CasingLower, CasingUpper, CasingTitle

  UnderlineStyle* = enum
    UlNone, UlSingle, UlDouble

  FormattedOutput* = object
    contents:        seq[string]
    maxWidth:        int
    lineWidths:      seq[int]
    startsWithBreak: bool
    finalBreak:      bool

  FmtStyle* = ref object  # For terminal formatting.
    textColor*:        string   # "" inherits.
    bgColor*:          string
    overflow*:         OverflowPreference = OIndent
    wrapIndent*:       int        = 2
    lpad*:             int        = 0
    rpad*:             int        = 0
    lpadChar*:         Rune       = Rune(' ') # Assumed to be width 1.
    rpadChar*:         Rune       = Rune(' ') # Assumed to be width 1.
    casing*:           TextCasing
    paragraphSpacing*: int        = 1
    lineSep*:          string     = "\n"
    bold*:             bool
    inverse*:          bool
    strikethrough*:    bool
    italic*:           bool
    underlineStyle*:   UnderlineStyle
    unicodeOverAnsi*:  bool = true
    color24Bit*:       bool = false

  FmtState* = object
    availableWidth: int
    totalWidth: int
    curStyle:   FmtStyle

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
    breakPoint:  bool
    style*:      FmtStyle  # Style options for this node
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
      ordered*: bool
      prefBullet*: string
      items*: seq[Rope]
    of RopeTable:
      thead*:   Rope # RopeTableRows
      tbody*:   Rope # RopeTableRows
      tfoot*:   Rope # RopeTableRows
      caption*: Rope # RopeTaggedContainer
    of RopeTableRow, RopeTableRows:
      cells*: seq[Rope]
    of RopeTaggedContainer, RopeAlignedContainer:
      tag*: string
      contained*: Rope
    of RopeCustom:
      contents*: RootRef
      toString*: (Rope) -> string
      ropeCopy*: (var Rope, Rope) -> void
    of RopeFgColor, RopeBgColor:
      color*: string
      toColor*: Rope

template setAtomLength(r: Rope) =
  if r.length == 0:
    for ch in r.text:
      r.length += ch.runeWidth()

var
  defaultStyle* = FmtStyle()
  styleMap*: Table[string, FmtStyle] = {
    "title" : FmtStyle(bgColor: "white", textColor: "blue", italic: true,
                       casing: CasingTitle),
    "h1" : FmtStyle(textColor: "blue", bgColor: "white", bold: true,
                    italic: true, casing: CasingTitle),
    "h2" : FmtStyle(textColor: "dodgerblue", italic: true,
                    underlineStyle: UlDouble, casing: CasingTitle),
    "h3" : FmtStyle(textColor: "skyblue", italic: true,
                    underlineStyle: UlSingle, casing: CasingTitle),
    "h4" : FmtStyle(textColor: "powderblue", bgColor: "black", italic: true,
                    casing: CasingTitle),
    "h5" : FmtStyle(textColor: "powderblue", bgColor: "black",
                    underlineStyle: UlSingle, casing: CasingTitle),
    "h6" : FmtStyle(textColor: "powderblue", bgColor: "black",
                    casing: CasingTitle)
    }.toTable()

proc refCopy*(dst: var Rope, src: Rope) =
  dst.kind = src.kind
  case src.kind
  of RopeAtom:
    dst.length = src.length
    dst.text   = src.text

  of RopeBreak:
    dst.breakType = src.breakType

  of RopeList:
    dst.ordered = src.ordered
    dst.prefBullet = src.prefBullet
    var
      sub: Rope
      l:   seq[Rope]
    for item in src.items:
      sub = Rope()
      refCopy(sub, item)
      l.add(sub)
    dst.items = l

  of RopeLink:
    dst.url = src.url
    var sub: Rope = Rope()
    refCopy(sub, src.toHighlight)
    dst.toHighlight = sub

  of RopeTaggedContainer, RopeAlignedContainer:
    var sub: Rope = Rope()
    refCopy(sub, src.contained)
    dst.contained    = sub
    dst.tag          = src.tag

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

  of RopeTableRow, RopeTableRows:
    for cell in src.cells:
      var r = Rope()
      refCopy(r, cell)
      dst.cells.add(r)

  of RopeFgColor, RopeBgColor:
    dst.color   = src.color
    var r = Rope()
    refCopy(r, src.toColor)
    dst.toColor = r

  of RopeCustom:
    src.ropeCopy(dst, src)

  if src.next != nil:
    var f = Rope()
    refCopy(f, src.next)
    dst.next = f

  dst.breakPoint = src.breakPoint

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
      probe = r1
      while probe != nil:
        probe.cycle = false
        probe = probe.next
      raise newException(ValueError, "Addition would cause a cycle")
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
      result = Rope(kind: RopeBreak, breakType: BrHardLine, breakPoint: true)
    of "p":
      result = Rope(kind: RopeBreak, breakType: BrParagraph,
                    guts: n.descend(), breakPoint: true)
    of "div":
      result = Rope(kind: RopeBreak, breakType: BrPage,
                    guts: n.descend(), breakPoint: true)
    of "h1", "h2", "h3", "h4", "h5", "h6":
      result = Rope(kind: RopeTaggedContainer, tag: n.contents,
                    contained: n.descend(), breakPoint: true)
    of "a":
      let url = if "href" in n.attrs: n.attrs["href"] else: "https://unknown"
      result = Rope(kind: RopeLink, url: url, toHighlight: n.descend())
    of "li":
      result = n.descend()
    of "ol", "ul":
      let ordered = if n.contents == "ol": true else: false
      result = Rope(kind: RopeList, ordered: ordered, breakPoint: true)
      for item in n.children:
        result.items.add(item.htmlTreeToRope())
    of "blockquote":
      result = Rope(kind: RopeTaggedContainer, tag: "blockquote",
                    contained: n.descend(), breakPoint: true)
    of "code":
      result = Rope(kind:  RopeTaggedContainer, tag: "code",
                    contained: n.descend(), breakPoint: true)
    of "ins":
      result = Rope(kind:  RopeTaggedContainer, tag: "inserted",
                    contained: n.descend())
    of "del":
      result = Rope(kind:  RopeTaggedContainer, tag: "deleted",
                    contained: n.descend())
    of "kbd":
      result = Rope(kind:  RopeTaggedContainer, tag: "keyboard",
                    contained: n.descend())
    of "mark":
      result = Rope(kind:  RopeTaggedContainer, tag: "highlighted",
                    contained: n.descend())
    of "pre":
      result = Rope(kind:  RopeTaggedContainer, tag: "preformatted",
                    contained: n.descend(), breakPoint: true)
    of "q":
      result = Rope(kind:  RopeTaggedContainer, tag: "quotation",
                    contained: n.descend(), breakPoint: true)
    of "s":
      result = Rope(kind:  RopeTaggedContainer, tag: "strikethrough",
                    contained: n.descend())
    of "small":
      result = Rope(kind:  RopeTaggedContainer, tag: "aside",
                    contained: n.descend(), breakPoint: true)
    of "sub":
      result = Rope(kind:  RopeTaggedContainer, tag: "subscript",
                    contained: n.descend())
    of "sup":
      result = Rope(kind:  RopeTaggedContainer, tag: "superscript",
                    contained: n.descend())
    of "title":
      result = Rope(kind:  RopeTaggedContainer, tag: "superscript",
                    contained: n.descend(), breakPoint: true)
    of "em":
      result = Rope(kind:  RopeTaggedContainer, tag: "em",
                    contained: n.descend())
    of "i":
      result = Rope(kind:  RopeTaggedContainer, tag: "italic",
                    contained: n.descend())
    of "b":
      result = Rope(kind:  RopeTaggedContainer, tag: "bold",
                    contained: n.descend())
    of "strong":
      result = Rope(kind:  RopeTaggedContainer, tag: "strong",
                    contained: n.descend())
    of "u":
      result = Rope(kind:  RopeTaggedContainer, tag: "underline",
                    contained: n.descend())
    of "caption":
      result = Rope(kind:  RopeTaggedContainer, tag: "caption",
                    contained: n.descend())
    of "var":
      result = Rope(kind:  RopeTaggedContainer, tag: "variable",
                    contained: n.descend())
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
      result = Rope(kind:  RopeTableRows)
      for item in n.children:
        result.cells.add(item.htmlTreeToRope())
    of "tr":
      result = Rope(kind: RopeTableRow)
      for item in n.children:
        result.cells.add(item.htmlTreeToRope())
    of "table":
      result = Rope(kind: RopeTable, breakPoint: true)
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
            result.tbody = Rope(kind: RopeTableRows)
          result.cells.add(asRope)
        else: # colgroup; currently not handling.
          discard
    else:
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
        result = Rope(kind: RopeTaggedContainer, tag: n.contents)
        result.contained = n.descend()
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
  var color: int
  if name in colorTable:
    color = colorTable[name]
  elif parseHex(name, color) != 6:
      result = (-1, -1, -1)
  result = (color shr 16, (color shr 8) and 0xff, color and 0xff)

proc colorNameToVga*(name: string): int =
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

  case state.curStyle.overflow
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
      state.totalWidth -= remainingLen
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
    if state.curStyle.overflow == OIndent and
       state.totalWidth > state.curStyle.wrapIndent:
      let
        padChar = state.curStyle.lpadChar
        padAmt  = state.curStyle.wrapIndent

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
    case state.curStyle.casing
    of CasingAsIs:
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
    case state.curStyle.underlineStyle
    of UlNone:
      discard
    of UlSingle:
      if state.curStyle.unicodeOverAnsi:
        var newres: string
        for ch in result.contents[i]:
          newres.add(ch)
          newres.add(Rune(0x0332))
        result.contents[i] = newres
      else:
        codes.add("4")
    of UlDouble:
      codes.add("21")

    if state.curStyle.bold:
      codes.add("1")

    if state.curStyle.italic:
      codes.add("3")

    if state.curStyle.inverse:
      codes.add("7")

    if state.curStyle.strikethrough:
      if state.curStyle.unicodeOverAnsi:
        var newRes: string
        for ch in result.contents[i]:
          newRes.add(ch)
          newRes.add(Rune(0x0336))
        result.contents[i] = newRes
      else:
        codes.add("9")

    if state.curStyle.color24Bit:
      let
        fgCode = state.curStyle.textColor.colorNameToHex()
        bgCode = state.curStyle.bgColor.colorNameToHex()

      if fgCode[0] != -1:
        codes.add("38;2;" & $(fgCode[0]) & ";" & $(fgCode[1]) & ";" &
                   $(fgCode[2]))
      if bgCode[0] != -1:
        codes.add("48;2;" & $(bgCode[0]) & ";" & $(bgCode[1]) & ";" &
                            $(bgCode[2]))
    else:
      let
        fgCode  = state.curStyle.textColor.colorNameToVga()
        bgCode  = state.curStyle.bgColor.colorNameToVga()
      if fgCode != -1:
        codes.add("38;5;" & $(fgCode))
      if bgCode != -1:
        codes.add("48;5;" & $(bgCode))

    result.contents[i] = "\e[" & codes.join(";") & "m" &
      result.contents[i] & "\e[1m"

proc copyStyle(inStyle: FmtStyle): FmtStyle =
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
                    unicodeOverAnsi: inStyle.unicodeOverAnsi,
                    color24Bit:      inStyle.color24Bit)

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

proc internalRopeToString(r: Rope, state: var FmtState): FormattedOutput =
  var
    oldStyle: FmtStyle
    newStyle: FmtStyle = state.curStyle

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
    if showColor:
      newStyle = state.curStyle.copyStyle()
      newStyle.textColor = r.color
      oldStyle       = state.curStyle
      state.curStyle = newStyle
      result = r.toColor.internalRopeToString(state)
      state.curStyle = oldStyle
    else:
      result = r.toColor.internalRopeToString(state)
  of RopeBgColor:
    if showColor:
      newStyle = state.curStyle.copyStyle()
      newStyle.bgColor = r.color
      oldStyle       = state.curStyle
      state.curStyle = newStyle
      result = r.toColor.internalRopeToString(state)
      state.curStyle = oldStyle
    else:
      result = r.toColor.internalRopeToString(state)
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
    case r.tag
    of "strikethrough":
      newStyle = state.curStyle.copyStyle()
      newStyle.strikethrough = true
    of "italic":
      newStyle = state.curStyle.copyStyle()
      newStyle.italic = true
    of "underline":
      newStyle = state.curStyle.copyStyle()
      newStyle.underlineStyle = UlSingle
    of "bold":
      newStyle = state.curStyle.copyStyle()
      newStyle.bold = true
    of "other":
      raise newException(ValueError, "Not implemented yet.")
    else:
      if r.tag in styleMap:
        newStyle = styleMap[r.tag]

    oldStyle       = state.curStyle
    state.curStyle = newStyle
    result = r.contained.internalRopeToString(state)
    state.curStyle = oldStyle

    if r.breakPoint:
      result.finalBreak      = true
      result.startsWithBreak = true
    # TODO: be able to bad these containers!!!
  else:
    discard

  if r.next != nil:
    let next = r.next.internalRopeToString(state)
    combineFormattedOutput(result, next)

proc evalParagraph(r: Rope, state: var FmtState): FormattedOutput =
  var
    oldStyle      = state.curStyle
    newStyle      = oldStyle
    oldTotalWidth = state.totalWidth

  result = r.internalRopeToString(state)
  if not result.finalBreak:
      result.finalBreak = true

  for i in 0 ..< newStyle.paragraphSpacing:
    result.contents.add("")
    result.lineWidths.add(0)

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

  curState.availableWidth = curState.totalWidth
  curState.curStyle       = defaultStyle

  let preResult = r.evalParagraph(curstate)
  result = preResult.contents.join(curState.curStyle.lineSep)
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
