## Unit tests.

import std/[unittest, tables, json, os]
import nimutils
import nimutils/[box, unicodeid]
import nimutils/randwords # large code size, not imported by default.
import nimutils/either    # Not working well, not imported by default.


proc removeSpaces(s: string): string =
  for c in s:
    if c != ' ' and c != '\n':
      result.add(c)

type TestObj = ref object of RootRef
  value: int

proc customPack(x: TestObj): Box =
  return Box(kind: MkObj, o: x)

proc customUnpack(x: Box, v: var TestObj) =
  v = cast[TestObj](x.o)

suite "boxing":
  setup:
    var
      l1 = @["a", "b", "c"]
      l2 = @["d", "e", "f"]
      l3 = @["g", "h", "i"]
      l123 = @[l1, l2, l3]
      b1, b123: Box
      o123: seq[seq[string]] = @[]
      oMy: seq[Box] = @[]

  test "basics":
    b1 = pack(l1)
    check unpack[seq[string]](b1) == l1
    b123 = pack(l123)
    check typeof(b123) is Box
    check removeSpaces(boxToJson(b123)) == $(%*(l123))

  test "typing":
    b123 = pack(l123)
    var t123: seq[seq[string]]
    var v123: seq[Box]
    var x123: seq[seq[Box]] = @[]
    var z123: seq[seq[string]] = @[]

    t123 = unpack[typeof(t123)](b123)
    v123 = unpack[typeof(v123)](b123)
    for item in v123:
      x123.add(unpack[seq[Box]](item))
    for item in x123:
      var l: seq[string] = @[]
      for s in item:
        l.add(unpack[string](s))
      z123.add(l)
    check z123 == l123

  test "tables":
    var
      myDict = newTable[string, seq[string]]()
      newDict: TableRef[string, seq[string]]

    myDict["foo"] = @["a", "b"]
    myDict["bar"] = @["b"]
    myDict["boz"] = @["c"]
    myDict["you"] = @["d"]
    let
      dictBox = pack(myDict)
      listbox = pack(l1)
    var outlist: l1.type
    unpack(listbox, outlist)

    check $(listbox) == "box[a, b, c]"
    check $(outlist) == """@["a", "b", "c"]"""
    unpack(dictBox, newDict)
    check $(dictBox) ==
      "{bar : box[b], you : box[d], foo : box[a, b], boz : box[c]}"
    check $(newDict) ==
      """{"bar": @["b"], "you": @["d"], "foo": @["a", "b"], "boz": @["c"]}"""
    check boxToJson(dictBox) ==
      """{ "bar" : ["b"], "you" : ["d"], "foo" : ["a", "b"], "boz" : ["c"] }"""

  test "custom pack":
    let
      n = TestObj(value: 666)
      p = pack(n)
      r = unpack[TestObj](p)

    check r == n
    check r.value == 666

EitherDecl(EitherTest, string, int)

suite "either":
  setup:
    let
      x = 5
      y = "test"

  test "or?":
    var z: EitherTest = x

    var a = EitherTest(x)

    check z == a
    check z == x
    check not z.isA(string)
    check z.isA(int)

    var m: EitherTest = z.get(int)

    z = y

    check z != a

    check $(z) == "either(\"test\")"
    check $(a) == "either(5)"

    check z.isA(string) == true

    var n: string = z.get(string)

    check n == "test"
    check m == EitherTest(5)
    check m == 5
    check m == x

suite "encodings":
  test "b32_padded":
    var s = "This is a string that we're going to use to test base32."
    for i in 0 ..< len(s):
      check(base32Decode(base32Encode(s[0 .. i], true)) == s[0 .. i])
    for i in 0 ..< len(s):
      check(base32vDecode(base32vEncode(s[0 .. i], true)) == s[0 .. i])
  test "b32_unpadded":
    var s = "This is a string that we're going to use to test base32."
    for i in 0 ..< len(s):
      check(base32Decode(base32Encode(s[0 .. i])) == s[0 .. i])
    for i in 0 ..< len(s):
      check(base32vDecode(base32vEncode(s[0 .. i])) == s[0 .. i])
  test "kat":
    let
      kat1 = "KRUGS4ZANFZSA43PNVSSA43UOJUW4ZZO"
      kat2 = "KRUGS4ZANFZSA43PNVSSA43UOJUW4ZY"
      kat3 = "KRUGS4ZANFZSA43PNVSSA43UOJUW4"
      kat4 = "KRUGS4ZANFZSA43PNVSSA43UOJUQ"
      kat5 = "KRUGS4ZANFZSA43PNVSSA43UOI"
      kat6 = "KRUGS4ZANFZSA43PNVSSA43UOJUW4ZZO"
      kat7 = "KRUGS4ZANFZSA43PNVSSA43UOJUW4ZY="
      kat8 = "KRUGS4ZANFZSA43PNVSSA43UOJUW4==="
      kat9 = "KRUGS4ZANFZSA43PNVSSA43UOJUQ===="
      kat0 = "KRUGS4ZANFZSA43PNVSSA43UOI======"

    check(base32Encode("This is some string.") == kat1)
    check(base32Encode("This is some string")  == kat2)
    check(base32Encode("This is some strin")   == kat3)
    check(base32Encode("This is some stri")    == kat4)
    check(base32Encode("This is some str")     == kat5)
    check(base32Encode("This is some string.", true) == kat6)
    check(base32Encode("This is some string", true)  == kat7)
    check(base32Encode("This is some strin", true)   == kat8)
    check(base32Encode("This is some stri", true)    == kat9)
    check(base32Encode("This is some str", true)     == kat0)

suite "misc":
  test "i got ids":
    check isValidId("ª")
    check isValidId("ilikeπ2")
    check not isValidId("💩")
    echo "  💩"
  test "path":
    let
      home = getenv("HOME") # This test assumes HOME is properly set.
      base = if home[^1] != '/': splitPath(home).head
             else: splitPath(home[0 ..< ^1]).head

    check resolvePath("~") == (if home[^1] == '/': home[0 ..< ^1] else: home)
    check resolvePath("") == getCurrentDir()
    check resolvePath("~fred") == joinPath(base, "fred")

    const
      expectedDir = currentSourcePath() / ".." / ".." / ".." / ".." / ".."

    check resolvePath("../../src/../../eoeoeo") == expectedDir / "eoeoeo"
  test "random":
    let
      words = getRandomWords(3)
      bits = wordsToInt(words).get()
      back = intToWords(bits)

    check back == words
    echo "  Your words were: ", back

  test "flatten":
    var
      x = @[@[@[1, 2, 3], @[4,5,6]], @[@[7, 8, 9], @[10 ,11, 12]]]
      y: seq[int]
      z = @[["hello", "world"]]

    flatten(x, y)
    check y == @[1,2,3,4,5,6,7,8,9,10,11,12]
    y = flatten[int](x)
    check y == @[1,2,3,4,5,6,7,8,9,10,11,12]
    check not compiles(y = flatten[int](z))
