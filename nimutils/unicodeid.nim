## This module has morphed into a set of "missing" unicode
## functionality.  The "ID" at the end of the file name now stands for
## "is dope", at least until I figure out what to rename the file to!

## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022

import streams, unicode, strutils, std/terminal, misc
import unicodedb/properties, unicodedb/widths

const magicRune* = Rune(0x200b)

type AlignmentType* = enum AlignLeft, AlignCenter, AlignRight

proc repeat*(ch: uint32, n: int): seq[uint32] =
  for i in 0 ..< n:
    result.add(ch)
  #cast[seq[uint32]](Rune(ch).repeat(n))

proc isPostBreakingChar*(r: Rune): bool =
  ## Returns true if the codepoint is a hyphen break point.  Note that
  ## this does NOT return true for the good ol' minus (U+002D) because
  ## that only is supposed to be a break point if the character prior
  ## or after is not a numeric character.
  case r.ord()
  of 0x00ad, 0x058a, 0x2010, 0x2012 .. 0x2014, '_'.ord():
    return true
  else:
    return false

proc isPreBreakingChar*(r: Rune): bool =
  if r.isWhiteSpace():
    return true
  case r.ord()
  of 0x1806, 0x2014:
    return true
  else:
    return false

proc isPossibleBreakingChar*(n: uint32): bool =
  if n > 0x10ffff:
    return false
  let r = Rune(n)
  if r.isPostBreakingChar() or r.isPreBreakingChar() or r == Rune('-'):
    return true

proc isPatternSyntax*(r: Rune): bool =
  ## Returns true if the codepoint is part of the Unicode
  ## Pattern_Syntax class.
  case r.ord()
  # I can't figure out how to format this case statement in a way that
  # doesn't annoy the hell out of me.  I've been thinking about making
  # the single characters ranges just so it will all line up nicely :)
  # Right now, single characters are always the last thing on a line.
  of 0x0021 .. 0x002f, 0x003a .. 0x0040, 0x005b .. 0x005e, 0x0060,
     0x007b .. 0x007e, 0x00a1 .. 0x00a7, 0x00a9,
     0x00ab .. 0x00ac, 0x00ae,
     0x00b0 .. 0x00b1, 0x00b6, 0x00bb, 0x00bf, 0x00d7, 0x00f7,
     0x2010 .. 0x2027, 0x2030 .. 0x203e, 0x2041 .. 0x2053, 0x2055 .. 0x205e,
     0x2190 .. 0x245f, 0x2500 .. 0x2775, 0x2794 .. 0x2bff, 0x2e00 .. 0x2e7f,
     0x3001 .. 0x3003, 0x3008 .. 0x3020, 0x3030,
     0xfd3e .. 0xfd3f, 0xfe45 .. 0xfe46:
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
  ## Nim is actually very flexible on identifiers; too flexible!  The
  ## con4m lexer accepts based on the Unicode standard for identifiers.
  ## Unfortunately, neither Nim itself or the unicode character database
  ## package implements this check, which we use in con4m tokenization.
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
  var
    c   = s.readChar()
    n: uint
  case clzll((not uint(c)) shl 56)
  of 0:
    return Rune(c)
  of 2:
     n = (uint(c) and 0x1f) shl 6
     n = n or (uint(s.readChar()) and 0x3f)
  of 3:
     n = (uint(c) and 0x0f) shl 12
     n = n or ((uint(s.readChar()) and 0x3f) shl 6)
     n = n or (uint(s.readChar()) and 0x3f)
  of 4:
     n = uint(c) and (0x07 shl 18)
     n = n or ((uint(s.readChar()) and 0x3f) shl 12)
     n = n or ((uint(s.readChar()) and 0x3f) shl 6)
     n = n or (uint(s.readChar()) and 0x3f)
  else:
    raise newException(ValueError, "Invalid UTF8 sequence")
  return Rune(n)

proc peekRune*(s: Stream): Rune =
  ## Return the current rune from a stream, without advancing the
  ## pointer.  Not thread safe, of course.
  let n = s.getPosition()
  result = s.readRune()
  s.setPosition(n)

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

  if int(r) in [0xfe0f]:
    return 1
  if category in ctgMn + ctgMe + ctgCf:
    return 0

  if r == Rune(0x200b):
    return 0

  if int(r) >= int(Rune(0x1160)) and int(r) <= int(Rune(0x11ff)):
    return 0

  if r == Rune(0x00ad):
    return 1

  case r.unicodeWidth()
  of uwdtFull, uwdtWide:
    return 2
  else:
    return 1

template runeWidth*(r: uint32): int =
  if r > 0x0010ffff:
    0
  else:
    Rune(r).runeWidth()

proc runeLength*(s: string): int =
  for r in s.toRunes():
    result += r.runeWidth()

proc truncateToWidth*(l: seq[uint32], width: int): seq[uint32] =
  var total = 0

  for ch in l:
    if ch > 0x0010ffff:
      result.add(ch)
    else:
      let w = ch.runeWidth()
      total += w
      if total <= width:
        result.add(ch)

proc count*[T](list: seq[T], target: T): int =
  result = 0
  for item in list:
    if item == target:
      result = result + 1

# This function, and indentWrap below, are from the Nim wordwrap
# implementation, but are changed to 1) add indentation for hanging
# lines as an options, and 2) not count zws toward width.
proc olen(s: string, start, lastExclusive: int): int =
  var i = start
  result = 0
  while i < lastExclusive:
    if  runeAt(s, i) != magicRune:
      inc result
    let L = graphemeLen(s, i)
    inc i, L

proc indentWrap*( s: string,
                  startingMaxLineWidth = -1,
                  hangingIndent = 2,
                  splitLongWords = true,
                  seps: set[char] = Whitespace,
                  newLine = "\n"): string =
  result           = newStringOfCap(s.len + s.len shr 6)
  var startWidth   = if startingMaxLineWidth < 1:
                      terminalWidth() + startingMaxLineWidth
                     else:
                       startingMaxLineWidth

  var spaceLeft    = startWidth
  var lastSep      = ""
  var maxLineWidth = startWidth

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
              maxLineWidth = startWidth - hangingIndent
            dec spaceLeft
            let L = graphemeLen(s, k+i)
            for m in 0 ..< L: result.add s[i+k+m]
            inc k, L
        else:
          spaceLeft = maxLineWidth - wlen
          result.add(newLine)
          result.add repeat(Rune(' '), hangingIndent)
          maxLineWidth = startWidth - hangingIndent
          for k in i..<j: result.add(s[k])
      else:
        spaceLeft = spaceLeft - wlen
        result.add(lastSep)
        for k in i..<j: result.add(s[k])
    i = j

proc u32LineLength*(line: seq[uint32]): int =
  for item in line:
    if item <= 0x10ffff:
      result += item.runeWidth()

proc toWords*(line: seq[uint32]): seq[seq[uint32]] =
  var cur: seq[uint32]

  for item in line:
    if item < 0x10ffff and Rune(item).isWhiteSpace():
      if len(cur) != 0:
        result.add(cur)
        cur = @[]
    else:
      cur.add(item)

  if len(cur) != 0:
    result.add(cur)

proc justify*(line: seq[uint32], width: int): seq[uint32] =
  let actual = line.u32LineLength()

  if actual >= width:
    return line

  var
    words = line.toWords()
    sum   = 0

  if len(words) == 1:
    return words[0]

  for word in words:
    sum += word.u32LineLength()

  var
    base = sum div (len(words) - 1)
    rem  = sum mod (len(words) - 1)

  for i, word in words:
    result &= word

    if i == len(words) - 1:
      break

    for j in 0 ..< base:
      result.add(uint32(Rune(' ')))

    if rem != 0:
      result.add(uint32(Rune(' ')))
      rem -= 1
