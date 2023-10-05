##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import unicode, tables, rope_base

var
  defaultStyle* = newStyle(overflow = OWrap, rpad = 1, lpadChar = Rune(' '),
                           lpad = 0, rpadChar = Rune(' '), paragraphSpacing = 1)
  # To figure out what you're not properly formatting yet, add this to the default style:
  # bgcolor = "thunder", fgcolor = "black",
  #
  # Then, anything not selected is not yet done!


  styleMap*: Table[string, FmtStyle] = {
    "title" : newStyle(fgColor = "jazzberry", bold = BoldOn,
          align = AlignC, italic = ItalicOn, casing = CasingUpper),
    "h1" : newStyle(fgColor = "atomiclime", bold = BoldOn,
           align = AlignC, italic = ItalicOn, casing = CasingUpper),
    "h2" : newStyle(bgColor = "jazzberry", fgColor = "white", bold = BoldOn,
                    italic = ItalicOn),
    "h3" : newStyle(bgColor = "fandango", fgColor = "white", italic = ItalicOn,
                    underline = UnderlineDouble, casing = CasingUpper),
    "h4" : newStyle(fgColor = "jazzberry", italic = ItalicOn,
                    underline = UnderlineSingle, casing = CasingTitle),
    "h5" : newStyle(fgColor = "atomiclime", bgColor = "black",
                              italic = ItalicOn, casing = CasingTitle),
    "h6" : newStyle(fgColor = "fandango", bgColor = "white",
                    underline = UnderlineSingle, casing = CasingTitle),
    "ol" : newStyle(bulletChar = Rune('.'), lpad = 2),
    "ul" : newStyle(bulletChar = Rune(0x2022), lpad = 2), #•
    "table" : newStyle(borders = [BorderTypical], overflow = OWrap),
    "th"    : newStyle(fgColor = "black", bold = BoldOn,
                                 bgColor = "atomiclime"),
    "tr.even": newStyle(fgColor = "white", bgColor = "jazzberry"),
    "tr.odd" : newStyle(fgColor = "white", bgColor = "fandango"),
    "em" : newStyle(fgColor = "atomiclime", bold = BoldOn),
    "strong" : newStyle(inverse = InverseOn, italic = ItalicOn, lpad=1, rpad=1),
    "code" : newStyle(inverse = InverseOn, italic = ItalicOn)
    }.toTable()

  perClassStyles* = Table[string, FmtStyle]()
  perIdStyles*    = Table[string, FmtStyle]()

  breakingStyles*: Table[string, bool] = {
    "p"          : true,
    "div"        : true,
    "ol"         : true,
    "ul"         : true,
    "li"         : true,
    "blockquote" : true,
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
