## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022 - 2023, Crash Override, Inc.
##
## We're also directly pulling in Nim code that does not have a wide
## user base; some of it is abandoned, and for the rest, it's easier
## for us to have control over upstream dependencies that might go
## away.
##
## NimAWS code is abandoned, so currently taking over it. Originally
## written by "Gooseus" and made available under an MIT license.  My
## few fixes have all been for compatability and are made under the
## same license. I also migrated the crypto to openssl.

import nimutils/[box, random, unicodeid, pubsub, sinks, misc, texttable, dict],
       nimutils/[file, filetable, encodings, advisory_lock, progress],
       nimutils/[sha, aes, prp, hexdump, markdown, htmlparse, net],
       nimutils/[colortable, rope_base, rope_styles, rope_construct],
       nimutils/[rope_prerender, rope_ansirender, switchboard, subproc]
export box, random, unicodeid, pubsub, sinks, misc, random, texttable,
       file, filetable, encodings, advisory_lock, progress, sha,
       aes, prp, hexdump, markdown, htmlparse, net, colortable, rope_base,
       rope_styles, rope_construct, rope_prerender, rope_ansirender,
       switchboard, subproc, dict

when defined(macosx):
  import nimutils/macproc
  export macproc

## Things we don't want to force people to consume need to be imported
## manually. Currently, that's:
##
## `logging`    because importing it sets up data structures that you might
##              not use; you should explicitly choose to import it.
## `managedtmp` because it adds a destructor you might not want.
## `randwords`  because it does have a huge data structure embedded, which
##              isn't worth it if you're not using it.

when isMainModule:
  import tables, streams, algorithm, strutils

  when defined(macosx):
    proc psSorter(x, y: ProcessInfo): int =
      return cmp(x.pid, y.pid)

    proc macProcTest() =
      print("<h2>Mac proc test</h2>")
      var
        psInfo = listProcesses()
        cap    = h3("found " & $(psInfo.len()) & " processes.")
        head   = @[tr(@[th("Pid"), th("Command"), th("Arguments"), th("User")])]
        widths = colPcts([10, 35, 40, 15])

      psInfo.sort(psSorter)
      var body: seq[Rope]
      for pr in psInfo:
        body.add(tr(@[td(fgColor($(pr.getPid()), "blue")),
                      td(pr.getExePath()),
                       td(pr.getArgv().join(" ")),
                       td(fgColor(pr.getUserName(), "fandango"))]))

      print(table(tbody(body), thead = thead(head), caption = cap,
                                       columnInfo = widths))

  proc basic_subproc_tests() =
    print(h2("Run: /bin/cat /etc/passwd /etc/file_that_doesnt_exist; " & 
             "show output."))
    let res = runCmdGetEverything("/bin/cat", @["/etc/passwd",
                                                "/etc/file_that_doesnt_exist"],
                                  passthrough = true)
    print(fgColor("PID was:       ", "atomiclime") + em($(res.getPid())))
    print(fgColor("Exit code was: ", "atomiclime") + em($(res.getExit())))
    print(fgColor("Stdout was:    ", "atomiclime") + code(res.getStdout()))
    print(fgColor("Stderr was:    ", "atomiclime") + text(res.getStderr()))
    print(strdump(res.getStderr()))

  proc boxTest() =
    print("<h2>Box tests</h2>")
    var
        i1 = "a"
        l1 = @["a", "b", "c"]
        l2 = @["d", "e", "f"]
        l3 = @["g", "h", "i"]
        l123 = @[l1, l2, l3]
        b1, b123: Box
        o123: seq[seq[string]] = @[]
        oMy: seq[Box] = @[]
        a1 = pack(i1)

    echo typeof(a1)
    echo unpack[string](a1)
    b1 = pack(l1)
    echo b1
    echo unpack[seq[string]](b1)
    b123 = pack(l123)
    echo b123
    echo typeof(b123)
    echo typeof(o123)
    o123 = unpack[seq[seq[string]]](b123)
    echo o123
    oMy = unpack[seq[Box]](b123)
    echo oMy

    var myDict = newTable[string, seq[string]]()

    myDict["foo"] = @["a", "b"]
    myDict["bar"] = @["b"]
    myDict["boz"] = @["c"]
    myDict["you"] = @["d"]
    let
        f = newFileStream("nimutils.nim", fmRead)
        contents = f.readAll()[0 .. 20]

    myDict["file"] = @[contents]

    let
        dictBox = pack(myDict)
        listbox = pack(l1)

    var outlist: l1.type
    unpack(listbox, outlist)

    echo "Here's the listbox: ", listbox
    echo "Here it is unpacked: ", outlist

    var newDict: TableRef[string, seq[string]]

    unpack(dictBox, newDict)

    echo "Here's the dictbox(nothing should be quoted): ", dictBox
    echo "Here it is unpacked (should have quotes): ", newDict
    echo "Here it is, boxed, as Json: ", boxToJson(dictBox)

    # This shouldn't work w/o a custom handler.
    # import sugar
    # var v: ()->int
    # unpack[()->int](b123, v)

  proc ulidTests() =
    print(h2("Ulid Encode / decode tests"))
    let x = getUlid()
    echo unixTimeInMs()
    echo x, " ", x.ulidToTimeStamp()
    let y = getUlid()
    echo y, " ", y.ulidToTimeStamp()
    echo unixTimeInMs()
    echo base32Encode("This is some string.")
    echo "KRUGS4ZANFZSA43PNVSSA43UOJUW4ZZO (is the answer)"
    echo base32Encode("This is some string")
    echo "KRUGS4ZANFZSA43PNVSSA43UOJUW4ZY  (is the answer)"
    echo base32Encode("This is some strin")
    echo "KRUGS4ZANFZSA43PNVSSA43UOJUW4    (is the answer)"
    echo base32Encode("This is some stri")
    echo "KRUGS4ZANFZSA43PNVSSA43UOJUQ     (is the answer)"
    echo base32Encode("This is some str")
    echo "KRUGS4ZANFZSA43PNVSSA43UOI       (is the answer)"


    echo "-----"
    echo base32vEncode("This is some string.")
    echo base32vDecode(base32vEncode("1his is some string."))
    echo base32vEncode("This is some string")
    echo base32vDecode(base32vEncode("2his is some string"))
    echo base32vEncode("This is some strin")
    echo base32vDecode(base32vEncode("3his is some strin"))
    echo base32vEncode("This is some stri")
    echo base32vDecode(base32vEncode("4his is some stri"))
    echo base32vEncode("This is some str")
    echo base32vDecode(base32vEncode("5his is some str"))

    echo "-----"
    echo base32Encode("This is some string.")
    echo base32Decode(base32Encode("1his is some string."))
    echo base32Encode("This is some string")
    echo base32Decode(base32Encode("2his is some string"))
    echo base32Encode("This is some strin")
    echo base32Decode(base32Encode("3his is some strin"))
    echo base32Encode("This is some stri")
    echo base32Decode(base32Encode("4his is some stri"))
    echo base32Encode("This is some str")
    echo base32Decode(base32Encode("5his is some str"))

  proc hexTests() =
    var buf: array[128, byte] = [
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
      21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,
      39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56,
      57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74,
      75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92,
      93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108,
      109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122,
      123, 124, 125, 126, 127 ]

    print(h2("Basic hexdump"))
    print(pre(hexDump(listAddr(buf), 128, width = 80)))

  proc prpTests() =
    print(h2("Luby-Rackoff PRP"))
    var
      nonce: string = ""
      key = "0123456789abcdef"
      pt  = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" &
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      ct  =  prp(key, pt,  nonce)
      pt2 =  brb(key, ct, nonce)

    print(h3("Plaintext:"))
    print(pre(strdump(pt)))
    print(pre("Encrypt:"))
    print(pre(strdump(ct)))
    print(h3("Decrypt:"))
    print(pre(strdump(pt2)))
    print(h2("Random number generation"))
    let rows = @[
      tr(@[th("uint64"), td($(secureRand[uint64]()))]),
      tr(@[th("uint32"), td($(secureRand[uint32]()))]),
      tr(@[th("float"),  td($(secureRand[float]()))]),
      tr(@[th("array[6, byte]"), td($(secureRand[array[6, byte]]()))]),
      tr(@[th("string of 12 bytes (hex encoded)"),
           td($(randString(12).hex()))])]

    print(table(tbody(rows)))

  proc shaTests() =
    print(h3("SHA-256"))
    var
      text = newFileStream("nimutils.nim").readAll()
      ctx: Sha256ctx

    initSha256(ctx)
    ctx.update(text)
    print(em(ctx.final().hex()))
    print(em(sha256(text).hex()))
    print(em(hmacSha256("foo", "bar").hex()))
    print(em(hmacSha256Hex("foo", "bar")))

  proc aesGcmTests() =
    print(h3("AES"))
    var
      encCtx: GcmCtx
      decCtx: GcmCtx
      pt    = "This is a test between disco and death"
      key   = "0123456789abcdef"
    gcmInitEncrypt(encCtx, key)
    gcmInitDecrypt(decCtx, key)

    print(h3("Initial pt:"))
    print(em(pt))

    for i in 1 .. 3:
      var
        ct    = encCtx.gcmEncrypt(pt)
        nonce = encCtx.gcmGetNonce()
        pt    = decCtx.gcmDecrypt(ct, nonce).get("<error>")

      print(h3("Nonce:"))
      print(em(nonce.hex()))
      print(h3("CT: "))
      print(pre(strDump(ct)))
      print(h3("Decrypted:"))
      print(em(pt))

  proc keyStreamTest() =
    print(h2("Keystream test"))

    let
      key     = "0123456789abcdef"
      stream1 = aesPrfOneShot(key, 200)
      stream2 = aesPrfOneShot(key, 200)

    print(code(stream1.hex()))
    assert len(stream1) == 200
    assert stream1 == stream2

    var text = "This is a test, yo, dawg"

    aesCtrInPlaceOneshot(key, text)

    print(h3("PT:"))
    print(em(text.hex()))

    aesCtrInPlaceOneshot(key, text)

    print(h3("Decrypted:"))
    print(em(text))

  proc dictTests() =
    print(h2("Dictionary tests"))

    var
      x: DictRef[int, string] = {42: "bar", 1000 : "zork", 17 : "foo",
                                 500: "boz"}.toDict()
      y: Dict[int, string]

    y[500]  = "boz"
    y[1000] = "zork"
    y[17]   = "foo"
    y[42]   = "bar"

    echo x[42]
    echo x[17]
    x[17] = "blah"
    y[17] = "blah"
    echo x[17]
    for i in 1..1000:
      x[17] = $i
      y[17] = x[17]
      if i mod 2 == 1:
        x.del(17)
        y.del(17)

    echo x.keys()
    echo x.values()
    echo x.items()

    echo y.keys()
    echo y.values()
    echo y.items()
    var d2: DictRef[string, int] = newDict[string, int]()
    var seqstr = ["ay", "bee", "cee", "dee", "e", "eff", "gee", "h", "i", "j"]

    for i, item in seqstr:
      d2[item] = i

    echo d2.keys()
    echo d2.values()
    echo d2.items()
    echo d2.keys(sort = true)
    echo d2.values(sort = true)
    echo d2.items(sort = true)

    var d3 = newDict[string, array[10, string]]()
    for item in seqstr:
      d3[item] = seqstr

    echo d3[seqstr[0]]

    echo x
    echo y
    echo d2
    echo d3

  proc instantTableTests() =
    print(h2("Instant table tests"))
    var mess1 = @["a.out.dSYM", "encodings.nim", "managedtmp.nim",
                  "random.nim", "sinks.nim", "advisory_lock.nim", "file.nim",
                  "markdown.nim", "randwords.nim", "subproc.c",
                  "aes.nim", "filetable.nim", "misc", "rope_ansirender.nim",
                  "subproc.nim", "awsclient.nim", "hex.c", "misc.nim",
                  "rope_base.nim", "switchboard.c", "box.nim", "hexdump",
                  "net.nim", "rope_construct.nim", "switchboard.nim", "c",
                  "hexdump.nim", "private", "rope_prerender.nim",
                  "switchboard.o", "colortable.nim", "htmlparse.nim",
                  "process", "rope_styles.nim", "test.c", "crownhash.nim",
                  "logging.nim", "progress.nim", "s3client.nim", "test.o",
                  "dict.nim", "macproc.c", "prp.nim", "sha.nim",
                  "texttable.nim", "either.nim", "macproc.nim", "pubsub.nim",
                  "sigv4.nim", "unicodeid.nim"]
    mess1.sort()
    let tbl = instantTable(mess1, h2("Auto-arranged into columns")).
                           noBorders().tpad(2)

    print(tbl)

    var mess2 = @[@["1, 1", "Column 2", "Column 3", "Column 4"],
                  @["Row 2", "has some medium length strings", 
"""This has one string that's pretty long, but the rest are short. But this one is really long. I mean, really long, long enough to drive the other column into oblivion.""", "Row 2"],
                  @["Row 3", "has some medium length strings", "Row 3", "Row 3"],
                  @["Row 4", "has some medium length strings", "Row 4", "Row 4"]]

    let
      wi = [(12, true), (40, false), (0, false), (12, true)]
      t2 = quickTable(mess2, title = h2("Table with horizontal header"),
                      caption = h2("Table with horizontal header")).
             tpad(1).typicalBorders().colWidths(wi)
    print(t2)

    let t3 = quickTable(mess2, verticalHeaders = true,
                       title = h2("Table with vertical header"),
                       caption = h2("Table with vertical header"))
    print(t3.typicalBorders())

    let t4 = quickTable(mess2, noheaders = true,
                          title = "Table w/o header",
                          caption = "Table w/o header").
             bpad(1).boldBorders().allBorders()
    print(t4)

  proc calloutTest() =
    let
      st  = "This is a test of something I'd really like to know about, " &
            "I think??"
      txt = nocolors(callout(st, boxStyle = BoxStyleAscii))
      res = txt.search(text = "test")

    print(txt)

    var sometest = container(callout(center(pre(txt)))).lpad(10).rpad(10)
    print(center(sometest), width = -30)

  proc nestedTableTest() =
    let mdText = """
# Here's a markdown file!

It's got some body text in it. The first paragraph really isn't
particularly long, but it is certainly quite a bit longer than the
second paragraph. So it should wrap, as long as your terminal is not
insanely wide.

Oh look, here comes a table!

| Example | Table    |
| ------- | -------- |
| foo     | bar      |
| crash   | override |

## Some list
- Hello, there.
- This is an example list.
- This bullet will be long enough that it can show how we wrap bulleted text intelligently.
"""
    let crazyTable = @[
      @[markdown(mdText), markdown(mdText)],
      @[markdown(mdText), markdown(mdText)]
    ]
    let toPrint = quickTable(crazyTable, noheaders = true)
    print(toPrint)

  import nimutils/logging
  print(h1("Testing Nimutils functionality."))

  hexTests()
  boxTest()
  ulidTests()
  prpTests()
  shaTests()
  aesGcmTests()
  keyStreamTest()
  dictTests()
  #when defined(macosx):
  #  macProcTest()
  info(em("This is a test message."))
  error(italic(underline(("So is this."))))
  nestedTableTest()
  basic_subproc_tests()
  instantTableTests()
  calloutTest()
  
  var baddie = h1("hello") + fgColor(atom("Sup,"), "lime") + atom(" dawg!")
  print(pre(repr(baddie)))
  print(baddie)

  print h1("Heading 1")
  print h2("Heading 2")
  print h3("Heading 3")
  print h4("Heading 4")
  print h5("Heading 5")
  print h6("Heading 6")
  print(defaultBg(fgColor("Goodbye!!", "jazzberry")))
