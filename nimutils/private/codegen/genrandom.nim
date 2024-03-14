##
## This preprocesses the free 12 dicts "2 of 12 full" word list,
## paring it down to an exact power of two, and then generating a nim
## source file the resulting word list, as well as a basic secureRand
## library.
##
## Excess items are removed at random, so unless the list is an exact
## power of two in size once filtered, you're not likely to get the
## same results twice.
##
## This is meant to be run once only :)
##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022

import std/[streams, tables, strutils, strformat, sysrand, algorithm]

const
  fullFileName = "2of12full.txt"
  sigFileName = "signature.txt"
  outFileName = "../../random.nim"
  allowedLetters = "abcdefghijklmnopqrstuvwxyz"
  filterNonAmerican = true
  removeVariants = false
  removeSignature = true
  minSize = 4
  maxSize = 13
  minDicts = 3
  echoExclusions = false
  echoStatus = true

template secureRand*[T](): T =
  ## Returns a uniformly distributed random value of any _sized_ type.
  runnableExamples:
    echo secureRand[uint64]()
    echo secureRand[int32]()
    echo secureRand[float]()
    echo secureRand[array[6, byte]]()
    # secureRand[str]() should crash w/ a string dereference, since str is nil

  var randBytes: array[sizeof(T), byte]

  discard(urandom(randBytes))

  cast[T](randBytes)

proc randInt*(): int =
  return secureRand[int] and (not (1 shl 63))

proc clzll*(argc: uint): cint {.cdecl, importc: "__builtin_clzll".}

proc log2*(s: uint): int = 63 - clzll(s)

type
  Filters = enum
    TooFewDicts, BadLetters, NonAmerican, Variant, Signature, TooSmall, TooBig

  WordEntry = object
    word: string
    numDicts: uint
    nonVariantEntries: uint
    variantEntries: uint
    nonAmericanEntries: uint
    secondClassEntries: uint
    isSignature: bool
    filters: set[Filters]

var allEntries = newOrderedTable[string, WordEntry]()

proc parseFullFile(): int =
  var
    count = 0
    sigs = newTable[string, bool]()

  let
    f = newFileStream(fullFileName)
    txt = f.readAll()
    lines = txt.split("\n")
    sf = newFileStream(sigFileName)
    sigtxt = sf.readAll()
    sigRaw = sigtxt.split("\n")

  f.close()
  sf.close()

  for item in sigRaw:
    sigs[item.strip()] = true

  for i, line in lines:
    var entry = WordEntry()

    try:
      if len(line) <= 20:
        break
      let
        n1 = line[0 ..< 2].strip()
        n2 = line[4 ..< 6].strip()
        n3 = line[7 ..< 9].strip()
        n4 = line[11 ..< 13].strip()
        n5 = line[15 ..< 17].strip()
        word = line[21 .. ^1].strip()
      entry.numDicts = parseUInt(n1)
      entry.nonVariantEntries = if n2 == "-": 0'u else: parseUInt(n2)
      entry.variantEntries = if n3 == "-": 0'u else: parseUInt(n3)
      entry.nonAmericanEntries = if n4 == "-": 0'u else: parseUInt(n4)
      entry.secondClassEntries = if n5 == "-": 0'u else: parseUInt(n5)
      entry.word = word.strip()
      entry.filters = {}
      if entry.numDicts < minDicts:
        incl(entry.filters, TooFewDicts)
      if len(entry.word) < minSize:
        incl(entry.filters, TooSmall)
      elif len(entry.word) > maxSize:
        incl(entry.filters, TooBig)
      if sigs.contains(entry.word):
        entry.isSignature = true
        when removeSignature:
          incl(entry.filters, Signature)
      else:
        entry.isSignature = false
      when filterNonAmerican:
        if entry.nonAmericanEntries != 0:
          incl(entry.filters, NonAmerican)
      when removeVariants:
        if entry.variantEntries != 0:
          incl(entry.filters, Variant)
      for ch in word:
        if not allowedLetters.contains(ch):
          incl(entry.filters, BadLetters)
          break

      allEntries[word] = entry

      if entry.filters.card() == 0:
        count += 1
    except:
      stderr.writeLine (fmt"Error in line {i+1}")
      raise
  return count

proc pickItemsToRm(numItems: int, maxItem: int): seq[int] =
  var
    hash: Table[int, bool]
    i = numItems

  let
    nextPow2 = 1 shl (log2(cast[uint](maxItem)) + 1)
    mask = nextPow2 - 1

  while i != 0:
    let n = randInt() and mask
    if n >= maxItem:
      continue
    if hash.contains(n):
      continue
    hash[n] = true
    i -= 1

  for item in hash.keys:
    result.add(item)

  result.sort(order = SortOrder.Descending)



proc getFilteredList(): seq[string] =
  let
    count = parseFullFile()
    numbits = log2(cast[uint](count))
    ourPow2 = 1 shl numbits
    toRemove = count - ourPow2

  when echoStatus:
    stdErr.write(fmt"""
Total dictionary has {len(allEntries)} entries.
We've filtered that list down to {count} items.
That gives us a {numbits} bit word list.
We should remove {toRemove} entries.  Add to {sigFileName} to do it manually.
""")

  var
    rmlist = pickItemsToRm(toRemove, count)
    i = 0
    nextSkip = rmlist.pop()

  for word, entry in allEntries:
    if entry.filters.card() != 0:
      continue
    if i == nextSkip:
      i = i + 1
      if len(rmlist) != 0:
        nextSkip = rmlist.pop()
        when echoExclusions:
          echo word
      else:
        nextSkip = -1
      continue
    else:
      i = i + 1
      result.add(word)

  result.sort()

when isMainModule:
  var
    list = getFilteredList()
    s: seq[string] = @[]
    outstream = newFileStream(outFileName, fmWrite)

  when echoStatus:
    stderr.writeLine(fmt"Resulting list has {len(list)} entries.")


  for item in list:
    s.add(fmt""""{item}"""")


  let outstr = fmt"""
import std/[sysrand, strutils, strformat, algorithm, options]

template secureRand*[T](): T =
  ## Returns a uniformly distributed random value of any _sized_ type.
  runnableExamples:
    echo secureRand[uint64]()
    echo secureRand[int32]()
    echo secureRand[float]()
    echo secureRand[array[6, byte]]()
    # secureRand[str]() should crash w/ a string dereference, since str is nil

  var randBytes: array[sizeof(T), byte]

  discard(urandom(randBytes))

  cast[T](randBytes)

proc randInt*(): int =
  return secureRand[int] and (not (1 shl 63))

const binDict = [ {s.join(", ")} ]
const binIndexMask = {len(list)-1}

proc getRandomWords*(number = 4): string =
  ## Generates random bits, and maps them to dictionary words,
  ## mapping {len(list)} bits of random output to a single word.

  var words: seq[string] = @[]

  for i in 0 ..< number:
    words.add(binDict[randInt() and binIndexMask])

  return words.join("-")

when not defined(release):
  const errStr = "Can't convert high bits to words; we " &
          "process 16-bit chunks, but the wordlist is only a " &
          fmt"{log2(cast[uint](len(list)))} bit list."

proc intToWords*(i: int, elideLeadingZeros=true): string =
  ## Given an integer, maps it to a set of dictionary words,
  ## each of {len(list)} bites.
  ##
  ## If elideLeadingZeros is true, smaller ints will avoid
  ## producing words at the end that just map to 0 bits.

  var
    words: seq[string] = @[]
    n = i
    ix: int

  for i in 0 ..< (sizeof(int) shr 1):
    if elideLeadingZeros and n == 0:
      break
    ix = n and binIndexMask
    when not defined(release):
      assert ix == (n and 0xffff), errStr

    words.add(binDict[ix])
    n = n shr 16

  return words.join("-")

proc wordsToInt*(s: string): Option[int] =
  ## Given a sequence of up to 4 words coming from our dictionary, map
  ## them to their respective bits, outputting integers

  var
    l = s.split("-")
    res = 0

  assert len(l) <= sizeof(int) shl 1, "Cannot accept more than 4 words per call"

  while len(l) != 0:
    let
      word = l.pop()
      n = binarySearch(binDict, word)
    if n == -1:
      return none(int)
    res = res shl 16
    res = res or n

  return some(res)

when isMainModule:
  echo getRandomWords()
  echo getRandomWords(3)
"""

  outstream.write(outstr)
  outstream.close()
