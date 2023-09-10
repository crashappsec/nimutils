## This module has morphed into a set of "missing" unicode
## functionality.  The "ID" at the end of the file name now stands for
## "is dope", at least until I figure out what to rename the file to!
##
## Several of the functions are improvements on the Nim
## functions. Particularly, we work on grapheme lengths, instead of
## codepoints or characters.  And, where Nim's unicode does work on
## graphemes (particularly their wrap function), we properly do not
## count the zero-width space as a space.
##
## We then use that fact to make it easy for ourselves to deal with
## strings that have ANSI formatting; we have a type called SpaceSaver
## that allows us to replace an ANSI-formatted string with a
## non-formatted string, leaving in zero-width spaces, and then do
## things like wrap, truncate or align, and then restore the
## formatting.
##
## All of this is currently a little bit janky; I wasn't sure whether
## to make the ANSI-skipping a flag per call, and I wanted to be able
## to not restore strings immediately for when I want to make multiple
## calls.
##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022

import streams, unicode, strutils, std/terminal, misc
import unicodedb/properties, unicodedb/widths

const magicRune* = Rune(0x200b)

type AlignmentType* = enum AlignLeft, AlignCenter, AlignRight

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
    str = newString(4)
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

type SpaceSaver* = ref object
  pre*:       string
  postRunes*: seq[Rune]
  stash*:     seq[seq[Rune]]

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

  case r.unicodeWidth()
  of uwdtFull, uwdtWide:
    return 2
  else:
    return 1

proc runeLength*(s: string): int =
  for r in s.toRunes():
    result += r.runeWidth()

proc toSaver*(orig: string): (SpaceSaver, string) =
  ## This method stashes data drom a string that will impact width
  ## calculations, so that we can do those width calculations and any
  ## associated (order-preserving) transformations, and then replace
  ## these values later.
  ##
  ## Right now, we only stash ANSI color/graphics mode sequences. The
  ## thinking is that, in the face of things like cursor movement, it
  ## makes little sense to try to get an accurate sense of spacing, so
  ## just do the things we explicitly need to handle.
  ##
  ## For now, we assume here that all sequences starting with '\e' are
  ## well formed, and end with the letter 'm'.

  var
    res   = SpaceSaver(pre: orig, stash: @[], postRunes: @[])
    s     = orig.toRunes()
    escIx = 0
    zwsIx = 0

  while len(s) != 0:
    escIx = s.find(Rune('\e'))
    zwsIx = s.find(magicRune)
    if escIx == -1 and zwsIx == -1:
      res.postRunes &= s
      return (res, $(res.postRunes))
    elif zwsIx >= 0 and (escIx == -1 or escIx > zwsIx):
      # Include the zwsIx in the copy, instead of adding it ourselves.
      res.postRunes &= s[0 .. zwsIx]
      res.stash.add(@[magicRune])
      s = s[zwsIx + 1 .. ^1]
    else:
      res.postRunes &= s[0 ..< escIx]
      res.postRunes.add(magicRune)
      s = s[escIx .. ^1]
      let mIx = s.find(Rune('m'))
      if mIx == -1:
        raise newException(ValueError, "Invalid ANSI color/graphics mode escape")
      res.stash.add(s[0 .. mIx])
      s = s[mIx + 1 .. ^1]

  return (res, $(res.postRunes))

proc restoreSaver*(s: string, saver: SpaceSaver, errOk: bool = false): string =
  var nDbg = 0

  if len(saver.stash) == 0:
    return s

  var
    outRunes: seq[Rune]
    toProcess = s.toRunes()

  for item in saver.stash:
    let ix = toProcess.find(magicRune)
    if ix == -1:
      if not errOk:
        raise newException(ValueError,
                           "Input string doesn't preserve save points")
      else:
        outRunes.add(toProcess)
        return $(outRunes)

    outRunes.add(toProcess[0 ..< ix])
    outRunes.add(item)
    toProcess = toProcess[ix + 1 .. ^1]

  outRunes.add(toProcess)

  return $(outRunes)

proc count*[T](list: seq[T], target: T): int =
  result = 0
  for item in list:
    if item == target:
      result = result + 1

proc count*(s: string, target: Rune): int =
  return s.toRunes().count(target)

proc truncate*(instr: string, w: int): string =
  let
    (ss, contents) = instr.toSaver()

  if len(contents) <= w:
    return instr

  var
    ix    = 0
    count = 0

  while count < w:
    let chrlen = graphemeLen(contents, ix)
    if runeAt(contents, ix) != magicRune:
      count = count + 1
    ix += chrlen
    if ix >= len(contents):
      return instr

  let truncated = contents[0 ..< ix]

  return truncated.restoreSaver(ss, true)

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

proc width*(pre: string): int =
  ## Return one version of a length of a string. This is an attempt to
  ## get the printable length on a fixed width terminal in a unicode
  ## environment.
  ##
  ## We look at full graphemes, instead of bytes or runes.  And, if
  ## you want to skip ANSI formatting sequences when calculating
  ## width, use toSaver(), and calculate width on the string part of
  ## the output.
  ##
  ## Note well:
  ##
  ## 1) We do not take into account ANSI sequences that aren't about
  ##    formatting (that is, we only process ones that end in 'm').
  ## 2) We don't take into account how things might get rendered...
  ##    we assume we have a fixed-width font, and ignore the fact
  ##    that some characters in the Unicode standard are 'wide' or
  ##    'narrow' (or even, 'ambiguous').
  ##
  ## There is no correct, universal algorithm here.  Especially
  ## because there are some unicode sequences that can be displayed as
  ## a single character, or four, depending on the environment (e.g.,
  ## 'family' emojis).
  ##
  ## Still, our approach should be good enough for a lot of use cases,
  ## especially when in a terminal.
  ##
  ## This (and some of the other functions here) should eventually be
  ## rewritten to not go through the overhead of the space saver.  Not
  ## every important right now.
  let (x, s) = pre.toSaver()

  return olen(s, 0, len(s))

proc colWidth*(pre: string): int =
  ## Look at a multi-line string, and return the longest line.  It's
  ## called colWidth because we use it when we have a set of lines in
  ## a column to figure out the widest line.
  ##
  ## Note that this implementation does NOT ignore ANSI characters;
  ## use toSaver() before, and restoreSaver() on the output.  It does
  ## handle zws though.
  let (x, s) = pre.toSaver()

  var
    i    = 0
    last = len(s)

  result = 0
  while i < last:
    var n = i
    while n < last and s[n] != '\n':
      n = n + 1
    let linelen = olen(s, i, n)
    if linelen > result:
      result = linelen
    i = n + 1

proc align*(s: string, w: int, kind: AlignmentType): string =
  ## Align a unicode string to a particular width.
  ##
  ## Note that this implementation does NOT ignore ANSI characters;
  ## use toSaver() before, and restoreSaver() on the output.  It does
  ## handle zws though.
  let
    sWidth = width(s)
    padLen = w - sWidth

  if sWidth > w:
    return s

  case kind
  of AlignLeft:
    let pad = repeat(Rune(' '), padLen)
    return s & pad
  of AlignRight:
    let pad = repeat(Rune(' '), padLen)
    return pad & s
  else:
    let
      lpadlen = int(padLen/2)
      rpadlen = padlen - lPadLen
      lpad    = repeat(Rune(' '), lpadlen)
      rpad    = repeat(Rune(' '), rpadlen)
    return lpad & s & rpad

proc indentWrap*( s: string,
                  startingMaxLineWidth = -1,
                  hangingIndent = 2,
                  splitLongWords = true,
                  seps: set[char] = Whitespace,
                  newLine = "\n"): string =
  ## This wraps text.  Handles zws right, and can indent hanging lines.
  ## But if you want to ignore ANSI sequences, use the saver object.

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

proc perLineWrap*(s: string,
                  startingMaxLineWidth = -1,
                  firstHangingIndent   = 2,
                  remainingIndents     = 0,
                  splitLongWords       = true,
                  seps: set[char]      = Whitespace,
                  newLine              = "\n"): string =
    let lines             = split(s, "\n")
    var parts:seq[string] = @[]

    for i, line in lines:
      let
        (saver, str) = line.toSaver()
        wrapped      = str.indentWrap(startingMaxLineWidth,
                                      if i == 0:
                                        firstHangingIndent
                                      else:
                                        remainingIndents,
                                      splitLongWords,
                                      seps,
                                      newLine)
      parts.add(wrapped.restoreSaver(saver))
    return parts.join("\n")
