import tables, options

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


proc toAnsiCode*(codes: seq[AnsiCode]): string =
  if len(codes) == 0:
    return
  result = "\e["

  for i, item in codes:
    if i != 0: result.add(";")
    result.add($(item))

  result.add("m")

const ansiCodes = { "black"      : "\e[30m",
                    "red"        : "\e[31m",
                    "green"      : "\e[32m",
                    "yellow"     : "\e[33m",
                    "blue"       : "\e[34m",
                    "magenta"    : "\e[35m",
                    "cyan"       : "\e[36m",
                    "white"      : "\e[37m",
                    "BLACK"      : "\e[1;30m",
                    "RED"        : "\e[1;31m",
                    "GREEN"      : "\e[1;32m",
                    "YELLOW"     : "\e[1;33m",
                    "BLUE"       : "\e[1;34m",
                    "MAGENTA"    : "\e[1;35m",
                    "CYAN"       : "\e[1;36m",
                    "WHITE"      : "\e[1;37m",
                    "bg_black"   : "\e[30m",
                    "bg_red"     : "\e[31m",
                    "bg_green"   : "\e[32m",
                    "bg_yellow"  : "\e[33m",
                    "bg_blue"    : "\e[34m",
                    "bg_magenta" : "\e[35m",
                    "bg_cyan"    : "\e[36m",
                    "bg_white"   : "\e[37m",
                    "bold"       : "\e[1m",
                    "unbold"     : "\e[22m",
                    "invert"     : "\e[7m",
                    "uninvert"   : "\e[27m",
                    "strikethru" : "\e[9m",
                    "nostrike"   : "\e29m",
                    "font0"      : "\e[10m",
                    "font1"      : "\e[11m",
                    "font2"      : "\e[12m",
                    "font3"      : "\e[13m",
                    "font4"      : "\e[14m",
                    "font5"      : "\e[15m",
                    "font6"      : "\e[16m",
                    "font7"      : "\e[17m",
                    "font8"      : "\e[18m",
                    "font9"      : "\e[19m",
                    "reset"      : "\e[0m" }.toTable()

proc ansi*(s: varargs[string]): Option[string] =
  var res = ""
  
  for item in s:
    if item in ansiCodes: res &= ansiCodes[item]
    else: return none(string)

  return some(res)
