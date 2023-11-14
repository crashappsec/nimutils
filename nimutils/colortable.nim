# Taken from:HTML color list as found at:
# https://en.wikipedia.org/wiki/Web_colors
import tables, os, parseUtils

## This array contains all names we recognize for full 24-bit color.
## APIs that accept color names will also accept #abc123 style hex
## codes, but the algorithm for converting down to 256 colors may
## not be awesome, depending on your terminal, so color names are
## preferable when possible (all colors here should have a 'close'
## equal in the 256-color (8-bit) version below.
var colorTable* = {
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
  "jazzberry"            : 0xff2f8e,
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
  "fandango"             : 0x523AA4,
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
  "atomiclime"           : 0xb3ff00,
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
  "thunder"              : 0xe6e2dc,
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

## 8-bit color mappings for our named colors.
var color8Bit* =  {
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
  "jazzberry"            : 204,
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
  "fandango"             : 99,
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
  "atomiclime"           : 118,
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
  "thunder"              : 7,
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

var
  showColor              = if existsEnv("NO_COLOR"): false else: true
  unicodeOverAnsi:  bool = true
  color24Bit:       bool = false

template getColorTable*(): OrderedTable = colorTable
template get8BitTable*(): OrderedTable  = color8Bit

proc setShowColor*(val: bool) =
  ## If this is set to `false`, then rope "rendering" will not apply
  ## any ansi codes whatsoever.
  ##
  ## All output should otherwise look the same as it would with color,
  ## meaning there will be no variations in width.
  showColor = val

proc getShowColor*(): bool =
  ## Returns whether color will be output.
  return showColor

proc setUnicodeOverAnsi*(val: bool) =
  ## In some cases, we can use Unicode to attempt to draw some features,
  ## like underlining. This is generally good because people might turn
  ## colors off, in which case we interpret that as *no ansi codes*.
  ## Plus, some terminals may not support these things.
  ##
  ## Unfortunately, not all fonts render unicode underlining well either.
  ## Thus, the toggle.
  unicodeOverAnsi = val

proc getUnicodeOverAnsi*(): bool =
  ## Returns whether we're preferring unicode over ansi, when possible.
  return unicodeOverAnsi

proc setColor24Bit*(val: bool) =
  ## Sets whether to use 24-bit color. If the terminal doesn't support
  ## it, you won't like the results. If you turn this off, you'll only
  ## get 256 colors, but you can be sure the terminal will render
  ## okay.
  ##
  ## We do have limited auto-detection based on environment variables,
  ## but it isn't very good at this point.
  color24Bit = val

proc getColor24Bit*(): bool =
  ## Returns true for 24-bit output, false for 8-bit.
  return color24Bit

proc autoDetectTermPrefs*() =
  ## Does very limited detection of terminal capabilities.  We'd
  ## eventually like to do deeper terminal queries.  For now, you're
  ## mainly on your own, sorry :/
  ##
  ## This is run once automatically when importing colortable, But you
  ## can call it again if you like! I don't know why you would, since
  ## you're in control of any environment variable changes, though :)
  # TODO: if on a TTY, query the terminal for trycolor support,
  # per the `Checking for colorterm` section of:
  # https://github.com/termstandard/colors
  let
    truecolor = getenv("TRUECOLOR")
    term      = getenv("TERM")
    termprog  = getenv("TERM_PROGRAM")

  if truecolor in ["trucolor", "24bit"]:
    color24Bit = true

  elif term in ["xterm-kitty", "iterm", "linux-truecolor", "screen-truecolor",
                "tmux-truecolor", "xterm-truecolor", "vte"]:
    color24Bit = true

  if term in ["xterm-kitty"] or termprog == "WezTerm":
    unicodeOverAnsi = false

proc hexColorTo8Bit*(hex: string): int =
  ## Implements the algorithmic mapping of the 24-bit color space to 8
  ## bit color. Returns -1 if the input was invalid.
  ##
  ## Since terminals will generally use a pallate for 256 colors, the
  ## mappings usually aren't exact, and can occasionally be WAY off
  ## what is expected.
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
  ## Looks up a color name, and converts it to the three raw (r, g, b)
  ## values that we need for ANSI codes.
  let colorTable = getColorTable()
  var color: int

  if name in colorTable:
    color = colorTable[name]
  elif parseHex(name, color) != 6:
      result = (-1, -1, -1)
  result = (color shr 16, (color shr 8) and 0xff, color and 0xff)

proc colorNameToVga*(name: string): int =
  ## Looks up a color name, and converts it to the 8-bit color value
  ## mapped to that name.
  let color8Bit = get8BitTable()

  if name in color8Bit:
    return color8Bit[name]
  else:
    return hexColorTo8Bit(name)

once:
  autoDetectTermPrefs()
