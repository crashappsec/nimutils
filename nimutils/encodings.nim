## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import misc, tables, random, macros

const goodB32Map    = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
                       'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K',
                       'M', 'N', 'P', 'Q', 'R', 'S', 'T', 'V', 'W', 'X',
                       'Y', 'Z']
const goodB32revMap = [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
                        16, 17, 255, 18, 19, 255, 20, 21, 255, 22, 23, 24, 25,
                        26, 255, 27, 28, 29, 30, 31 ]
const stdB32Map     = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
                       'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
                       'U', 'V', 'W', 'X', 'Y', 'Z', '2', '3', '4', '5',
                       '6', '7']
const stdB32revMap  = [ 255, 255, 26, 27, 28, 29, 30, 31, 255, 255, 0, 1, 2, 3,
                        4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
                        19, 20, 21, 22, 23, 24, 25 ]


proc chop(i: uint): char = char(i and 0xff)

macro declB32Encoder(modifier: static[string], mapname: untyped): untyped =
  var
    fun  = ident("base32" & modifier & "Encode")
    e32  = ident("e32" & modifier)

  return quote do:
      proc `e32`(c: int): char {.inline.} =
        return `mapname`[c and 0x1f]

      proc `fun`*(s: openarray[char], pad = false): string =
        result = newStringOfCap(s.len() * 2)
        var
          n  = s.len() div 5
          i  :  int = 0
          tmp1: int
          tmp2: int

        while n != 0:
          n    = n - 1
          tmp1 = int(s[i])
          i    = i + 1
          result.add(`e32`(tmp1 shr 3))
          tmp2 = int(s[i])
          i    = i + 1
          result.add(`e32`((tmp1 shl 2) or (tmp2 shr 6)))
          result.add(`e32`(tmp2 shr 1))
          tmp1 = tmp2 shl 4
          tmp2 = int(s[i])
          i    = i + 1
          result.add(`e32`(tmp1 or (tmp2 shr 4)))
          tmp1 = tmp2 shl 1
          tmp2 = int(s[i])
          i    = i + 1
          result.add(`e32`(tmp1 or (tmp2 shr 7)))
          result.add(`e32`(tmp2 shr 2))
          tmp1 = tmp2 shl 3
          tmp2 = int(s[i])
          i    = i + 1
          result.add(`e32`(tmp1 or (tmp2 shr 5)))
          result.add(`e32`(tmp2))


        if i == s.len(): return
        tmp1 = int(s[i])
        i    = i + 1
        result.add(`e32`(tmp1 shr 3))
        if i == s.len():
          result.add(`e32`(tmp1 shl 2))
          if pad:
            return result & "======"
          return
        tmp2 = int(s[i])
        i    = i + 1
        result.add(`e32`((tmp1 shl 2) or (tmp2 shr 6)))
        result.add(`e32`(tmp2 shr 1))
        tmp1 = tmp2 shl 4
        if i == s.len():
          result.add(`e32`(tmp1))
          if pad:
            return result & "===="
          return
        tmp2 = int(s[i])
        i    = i + 1
        result.add(`e32`(tmp1 or (tmp2 shr 4)))
        tmp1 = tmp2 shl 1
        if i == s.len():
          result.add(`e32`(tmp1))
          if pad:
            return result & "==="
          return
        tmp2 = int(s[i])
        i    = i + 1
        result.add(`e32`(tmp1 or (tmp2 shr 7)))
        result.add(`e32`(tmp2 shr 2))
        tmp1 = tmp2 shl 3
        result.add(`e32`(tmp1))
        if pad:
          return result & "="

macro declB32Decoder(modifier: static[string], mapname: untyped): untyped =
  var
    fun = ident("base32" & modifier & "Decode")
    d32 = ident("d32" & modifier)

  return quote do:
    proc `d32`*(c: char): uint {.inline.} =
      if int(c) > 90 or int(c) < 48:
        raise newException(ValueError, "Invalid b32 char")
      let ix = if int(c) >= 65: int(c) - 55 else: int(c) - 48
      result = uint(`mapname`[ix])
      if result == 255:
        raise newException(ValueError, "Invalid b32 char")

    proc `fun`*(s: string): string =
      var
        n = s.len() div 8
        i = 0
        decodes: array[8, uint]

      result = newStringOfCap((s.len() * 3) div 4)

      # Last block might have padding so don't go through it, even if aligned.
      if s.len() mod 8 == 0: n = n - 1

      while n != 0:
        n = n - 1
        decodes[0] = `d32`(s[i])
        i          = i + 1
        decodes[1] = `d32`(s[i])
        i          = i + 1
        decodes[2] = `d32`(s[i])
        i          = i + 1
        decodes[3] = `d32`(s[i])
        i          = i + 1
        decodes[4] = `d32`(s[i])
        i          = i + 1
        decodes[5] = `d32`(s[i])
        i          = i + 1
        decodes[6] = `d32`(s[i])
        i          = i + 1
        decodes[7] = `d32`(s[i])
        i          = i + 1
        result.add(chop((decodes[0] shl 3) or (decodes[1] shr 2)))
        result.add(chop((decodes[1] shl 6) or
                        (decodes[2] shl 1) or
                        (decodes[3] shr 4)))
        result.add(chop((decodes[3] shl 4) or decodes[4] shr 1))
        result.add(chop((decodes[4] shl 7) or (decodes[5] shl 2) or
                        (decodes[6] shr 3)))
        result.add(chop((decodes[6] shl 5) or decodes[7]))

      if i == s.len(): return
      decodes[0] = `d32`(s[i])
      i          = i + 1
      decodes[1] = `d32`(s[i])
      i          = i + 1
      result.add(chop((decodes[0] shl 3) or (decodes[1] shr 2)))
      if i == s.len() or s[i] == '=': return

      decodes[2] = `d32`(s[i])
      i          = i + 1
      decodes[3] = `d32`(s[i])
      i          = i + 1
      result.add(chop((decodes[1] shl 6) or
                      (decodes[2] shl 1) or
                      (decodes[3] shr 4)))
      if i == s.len() or s[i] == '=': return

      decodes[4] = `d32`(s[i])
      i          = i + 1

      result.add(chop((decodes[3] shl 4) or decodes[4] shr 1))
      if i == s.len() or s[i] == '=': return

      decodes[5] = `d32`(s[i])
      i          = i + 1
      decodes[6] = `d32`(s[i])
      i          = i + 1

      result.add(chop((decodes[4] shl 7) or (decodes[5] shl 2) or
                      (decodes[6] shr 3)))
      if i == s.len() or s[i] == char('='): return

      decodes[7] = `d32`(s[i])
      result.add(chop((decodes[6] shl 5) or decodes[7]))

declB32Encoder("",  stdB32Map)
declB32Encoder("v", goodB32Map)
declB32Decoder("",  stdB32revMap)
declB32Decoder("v", goodB32revMap)

template oneChrTS() =
  str.add(goodB32Map[(ts and mask64) shr bits])
  bits -= 5
  mask64 = mask64 shr 5

proc encodeUlid*(ts: uint64, randbytes: openarray[char], dash = true): string =
  ## encode a ULID, passing in the specific non-timestamp
  ## bytes. Generally, you should instead use `getUlid()`, which uses
  ## random bytes, as is typical.
  var
    str      = ""
    mask64   = 0x3e00000000000'u64
    bits     = 45

  oneChrTS(); oneChrTS(); oneChrTS(); oneChrTS(); oneChrTS()
  oneChrTS(); oneChrTS(); oneChrTS(); oneChrTS(); oneChrTS()
  if dash: str.add('-')

  result = str & base32vEncode(randbytes[0 ..< 10])

proc getUlid*(dash = true): string =
  ## Returns a unique ULID, per the standard.
  var
    randbytes = secureRand[array[10, char]]()
    ts        = unixTimeInMs()

  encodeUlid(ts, randbytes)

proc ulidToTimeStamp*(s: string): uint64 =
  ## Extracts a timestamp from a ULID, measured in miliseconds since
  ## the start of 1970 UTC.
  ##
  ## We do no error checking; if you don't pass in an actual ULID, you
  ## won't like your results.
  result = uint64(d32v(s[0])) shl 45
  result = result or uint64(d32v(s[1])) shl 40
  result = result or uint64(d32v(s[2])) shl 35
  result = result or uint64(d32v(s[3])) shl 30
  result = result or uint64(d32v(s[4])) shl 25
  result = result or uint64(d32v(s[5])) shl 20
  result = result or uint64(d32v(s[6])) shl 15
  result = result or uint64(d32v(s[7])) shl 10
  result = result or uint64(d32v(s[8])) shl 5
  result = result or uint64(d32v(s[9]))
