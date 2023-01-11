import tables, options

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
