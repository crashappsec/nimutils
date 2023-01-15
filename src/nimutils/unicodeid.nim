## Nim is actually very flexible on identifiers; too flexible!  Our
## lexer accepts based on the Unicode standard for identifiers.
## Unfortunately, neither Nim itself or the unicode character database
## package implements this check, which we use in con4m tokenization.
##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022

import streams, unicode, strutils, std/terminal
import unicodedb/properties

proc isPatternSyntax*(r: Rune): bool =
  ## Returns true if the codepoint is part of the Unicode
  ## Pattern_Syntax class.
  case r.ord()
  of 0x0021 .. 0x002f, 0x003a .. 0x0040, 0x005b .. 0x005e, 0x0060,
     0x007b .. 0x007e, 0x00a1 .. 0x00a7, 0x00a9, 0x00ab .. 0x00ac, 0x00ae,
     0x00b0 .. 0x00b1, 0x00b6, 0x00bb, 0x00bf, 0x00d7, 0x00f7,
     0x2010 .. 0x2027, 0x2030 .. 0x203e, 0x2041 .. 0x2053, 0x2055 .. 0x205e,
     0x2190 .. 0x245f, 0x2500 .. 0x2775, 0x2794 .. 0x2bff, 0x2e00 .. 0x2e7f,
     0x3001 .. 0x3003, 0x3008 .. 0x3020, 0x3030, 0xfd3e .. 0xfd3f,
     0xfe45 .. 0xfe46:
    return true
  else:
    return false

proc isPatternWhiteSpace*(r: Rune): bool =
  ## Returns true if the codepoint is part of the Unicode
  ## Pattern_White_Space class.
  case r.ord()
  of 0x0009 .. 0x000d, 0x0020, 0x0085, 0x200e, 0x200f, 0x2028, 0x2029:
    return true
  else:
    return false

proc isOtherIdStart*(r: Rune): bool =
  ## Returns true if the codepoint is part of the Unicode
  ## Other_ID_Start class.
  case r.ord()
  of 0x1885 .. 0x1886, 0x2118, 0x212e, 0x309b .. 0x309c:
    return true
  else:
    return false

proc isOtherIdContinue*(r: Rune): bool =
  ## Returns true if the codepoint is part of the Unicode
  ## Other_ID_Continue class.
  case r.ord()
  of 0x00b7, 0x0387, 0x1369 .. 0x1371, 0x19DA:
    return true
  else:
    return false

# \p{L}\p{Nl}\p{Other_ID_Start}-\p{Pattern_Syntax}-\p{Pattern_White_Space}
proc isIdStart*(r: Rune, underscoreOk: bool = true): bool =
  if underscoreOk and r.ord == 0x005f:
    return true
  if (r.unicodeCategory() in ctgL+ctgNl) or r.isOtherIdStart():
    if not (r.isPatternSyntax() or r.isPatternWhiteSpace()):
      return true

  return false


# [\p{ID_Start}\p{Mn}\p{Mc}\p{Nd}\p{Pc}\p{Other_ID_Continue}-\p{Pattern_Syntax}
#  -\p{Pattern_White_Space}]
proc isIdContinue*(r: Rune): bool =
  ## Returns true if the passed codepoint is acceptable as any
  ## character, other than the first, within an identifier, per
  ## the unicode standard.
  if (r.unicodeCategory() in ctgL+ctgNl+ctgMn+ctgMc+ctgNd+ctgPc) or
     r.isOtherIdStart() or r.isOtherIdContinue():
    if not (r.isPatternSyntax() or r.isPatternWhiteSpace()):
      return true

  return false

proc isValidId*(s: string): bool =
  ## Return true if the input string is a valid identifier per the
  ## unicode spec.
  if s.len() == 0:
    return false

  let l = s.runeLenAt(0)

  if not s.runeAt(0).isIdStart():
    return false

  for rune in s[l .. ^1].runes():
    if not rune.isIdContinue():
      return false

  return true

proc readRune*(s: Stream): Rune =
  ## Read a single rune from a stream.
  var str = newString(4)
  let c = s.readChar()
  str[0] = c
  if (uint(c) and 0x80) != 0:
    let c = s.readChar()
    str[1] = c
    if (uint(c) and 0x80) != 0:
      let c = s.readChar()
      str[2] = c
      if (uint(c) and 0x80) != 0:
        str[3] = s.readChar()
  str.fastRuneAt(0, result, false)

proc peekRune*(s: Stream): Rune =
  ## Return the current rune from a stream, without advancing the
  ## pointer.  Not thread safe, of course.
  let n = s.getPosition()
  result = s.readRune()
  s.setPosition(n)


# This is hacked from the Nim std library to add indentation for
# hanging lines.
  
proc olen(s: string; start, lastExclusive: int): int =
  var i = start
  result = 0
  while i < lastExclusive:
    inc result
    let L = graphemeLen(s, i)
    inc i, L

proc indentWrap*( s: string,
                  startingMaxLineWidth = -1,
                  hangingIndent = 2,
                  splitLongWords = true,
                  seps: set[char] = Whitespace,
                  newLine = "\n"): string {.noSideEffect.} =
    
  result           = newStringOfCap(s.len + s.len shr 6)
  var spaceLeft    = startingMaxLineWidth
  var lastSep      = ""
  var maxLineWidth = startingMaxLineWidth

  var i = 0
  while true:
    var j = i
    let isSep = j < s.len and s[j] in seps
    while j < s.len and (s[j] in seps) == isSep: inc(j)
    if j <= i: break
    #yield (substr(s, i, j-1), isSep)
    if isSep:
      lastSep.setLen 0
      for k in i..<j:
        if s[k] notin {'\L', '\C'}: lastSep.add s[k]
      if lastSep.len == 0:
        lastSep.add ' '
        dec spaceLeft
      else:
        spaceLeft = spaceLeft - olen(lastSep, 0, lastSep.len)
    else:
      let wlen = olen(s, i, j)
      if wlen > spaceLeft:
        if splitLongWords and wlen > maxLineWidth:
          var k = 0
          while k < j - i:
            if spaceLeft <= 0:
              spaceLeft = maxLineWidth
              result.add newLine
              result.add repeat(Rune(' '), hangingIndent)
              maxLineWidth = startingMaxLineWidth - hangingIndent
            dec spaceLeft
            let L = graphemeLen(s, k+i)
            for m in 0 ..< L: result.add s[i+k+m]
            inc k, L
        else:
          spaceLeft = maxLineWidth - wlen
          result.add(newLine)
          result.add repeat(Rune(' '), hangingIndent)
          maxLineWidth = startingMaxLineWidth - hangingIndent
          for k in i..<j: result.add(s[k])
      else:
        spaceLeft = spaceLeft - wlen
        result.add(lastSep)
        for k in i..<j: result.add(s[k])
    i = j
