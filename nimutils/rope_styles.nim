##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import os, unicode, unicodedb, unicodedb/widths, unicodeid, sugar, markdown,
       htmlparse, tables, std/terminal, parseutils, options, colortable,
       rope_base


var
  defaultStyle* = newStyle(overflow = OWrap, rpad = 1, lpadChar = Rune(' '),
                           lpad = 0, rpadChar = Rune(' '), paragraphSpacing = 1)
  # To figure out what you're not properly formatting yet, add this to the default style:
  # bgcolor = "thunder", fgcolor = "black",
  #
  # Then, anything not selected is not yet done!


  styleMap*: Table[string, FmtStyle] = {
    "title" : newStyle(fgColor = "jazzberry", bold = BoldOn,
                    italic = ItalicOn, casing = CasingUpper),
    "h1" : newStyle(fgColor = "atomiclime", bold = BoldOn,
                    italic = ItalicOn, casing = CasingUpper),
    "h2" : newStyle(bgColor = "white", fgColor = "jazzberry", bold = BoldOn,
                    italic = ItalicOn, inverse = InverseOn),
    "h3" : newStyle(fgColor = "fandango", italic = ItalicOn,
                    underline = UnderlineDouble, casing = CasingUpper),
    "h4" : newStyle(fgColor = "jazzberry", italic = ItalicOn,
                    underline = UnderlineSingle, casing = CasingTitle),
    "h5" : newStyle(fgColor = "atomiclime", bgColor = "black",
                              italic = ItalicOn, casing = CasingTitle),
    "h6" : newStyle(fgColor = "fandango", bgColor = "white",
                    underline = UnderlineSingle, casing = CasingTitle),
    "ol" : newStyle(bulletChar = Rune('.'), lpad = 2),
    "ul" : newStyle(bulletChar = Rune(0x2022), lpad = 2), #•
    "table" : newStyle(borders = [BorderTypical]),
    "th"    : newStyle(fgColor = "black", bgColor = "atomiclime"),
    "tr.even": newStyle(fgColor = "white", bgColor = "jazzberry"),
    "tr.odd" : newStyle(fgColor = "white", bgColor = "fandango")

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
