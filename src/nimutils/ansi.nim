import os

var showColors = if existsEnv("NO_COLOR"): false else: true

proc setShowColors*(val: bool) =
  showColors = val

proc getShowColors*(): bool =
  return showColors


type AnsiCode* = enum
  acBlack =        "30"
  acRed =          "31"
  acGreen =        "32"
  acYellow =       "33"
  acBlue =         "34"
  acMagenta =      "35"
  acCyan =         "36"
  acWhite =        "37"
  acBBlack =       "1;30"
  acBrown =        "38;5;94"
  acPurple =       "38;2;94"
  acBRed =         "1;31"
  acBGreen =       "1;32"
  acBYellow =      "1;33"
  acBBlue =        "1;34"
  acBMagenta =     "1;35"
  acBCyan =        "1;36"
  acBWhite =       "1;37"
  acBGBlack =      "40"
  acBGRed =        "41"
  acBgGreen =      "42"
  acBGYellow =     "43"
  acBGBlue =       "44"
  acBGMagenta =    "45"
  acBGCyan =       "46"
  acBGWhite =      "47"
  acBold =         "1"
  acUnbold =       "22"
  acInvert =       "7"
  acUninvert =     "27"
  acStrikethru =   "9"
  acNostrikethru = "9"
  acFont0 =        "10"
  acFont1 =        "11"
  acFont2 =        "12"
  acFont3 =        "13"
  acFont4 =        "14"
  acFont5 =        "15"
  acFont6 =        "16"
  acFont7 =        "17"
  acFont8 =        "18"
  acFont9 =        "19"
  acReset =        "0"


proc toAnsiCode*(codes: openarray[AnsiCode]): string =
  when nimvm:
    discard
  else:
    if not showColors: return ""

  if len(codes) == 0:
    return
  result = "\e["

  for i, item in codes:
    if i != 0: result.add(";")
    result.add($(item))

  result.add("m")

proc toAnsiCode*(code: AnsiCode): string = toAnsiCode([code])
