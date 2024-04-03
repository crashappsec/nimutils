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

import nimutils/[box, random, unicodeid, pubsub, sinks, auth, misc, texttable],
       nimutils/[file, filetable, encodings, advisory_lock, progress],
       nimutils/[sha, aes, prp, hexdump, markdown, htmlparse, net],
       nimutils/[switchboard, subproc, int128_t, dict, list, libwrap, grid]
export box, random, unicodeid, pubsub, sinks, auth, misc, random, texttable,
       file, filetable, encodings, advisory_lock, progress, sha,
       aes, prp, hexdump, markdown, htmlparse, net, switchboard, subproc, int128_t,
       dict, list, c4str, libwrap, grid

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
  install_default_styles()

  proc basic_subproc_tests() =
    print(r("Run: /bin/cat /etc/passwd /etc/file_that_doesnt_exist; " &
             "show output."))
    let res = runCmdGetEverything("/bin/cat", @["/etc/passwd",
                                                "/etc/file_that_doesnt_exist"],
                                  passthrough = true)
    print(r("[atomic lime]PID was:       [/][i]" & $(res.getPid())))
    print(r("[atomic lime]Exit code was:[/][i]  " & $(res.getExit())))
    print(r("[atomic lime]Stdout was:[/]"))
    print(c4(res.getStdout()))
    print(r("[atomic lime]Stderr was:[/]    "))
    print(c4(res.getStderr()))
    print(c4(strdump(res.getStderr())))

  proc dictTests() =
    print(r("[h2]Dictionary tests"))

    var
      x: Dict[int, string] = {42: "bar", 1000 : "zork", 17 : "foo",
                              500: "boz"}.toDict()
      y: Dict[int, string] = newDict[int, string]()

    echo "assigns"
    y[500]  = "boz"
    y[1000] = "zork"
    y[17]   = "foo"
    y[42]   = "bar"

    echo x[42]
    echo x[17]
    x[17] = "blah"
    y[17] = "blah"
    echo x[17], " == 'blah'"
    for i in 1..1000:
      x[17] = $i
      y[17] = x[17]
      if i mod 2 == 1:
        x.del(17)
        y.del(17)

    echo "X's Keys: ", x.keys()
    echo "X's Values: ", x.values()
    echo "X's Items: ", x.items()

    echo "Y's Keys: ", y.keys()
    echo "Y's Values: ", y.values()
    echo "Y's Items: ", y.items()

    var d2: Dict[string, int] = newDict[string, int]()
    var seqstr = ["ay", "bee", "cee", "dee", "e", "eff", "gee", "h", "i", "j"]

    for i, item in seqstr:
      d2[item] = i

    echo d2.keys()
    echo d2.values()
    echo d2.items()
    echo d2.keys(sort = true)
    echo d2.values(sort = true)
    echo d2.items(sort = true)


  proc treeTest() =
    var
      t: Tree = new_tree(c4str("Test"))
      n1 = t.add_node(c4str("Level 1, Child 1"))
      n2 = t.add_node(c4str("Level 1, Child 2"))
      n3 = t.add_node(c4str("Level 1, Child 3"))
      n4 = n1.add_node(c4str("Level 2 under child 1"))
      n6 = n4.add_node(c4str("Level 3"))
      g  = grid_tree(t)

    print(toRich(g))

  proc instantTableTests() =
    print(r("Instant table tests"))
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
    let tbl = horizontal_flow(mess1, "Auto-arranged into columns",
                           maxcols = 6,
                           borders = false)

    print(toRich(tbl))

    var mess2 = @[@["1, 1", "Column 2", "Column 3", "Column 4"],
                  @["Row 2", "has some medium length strings",
"""This has one string that's pretty long, but the rest are short. But this one is really long. I mean, really long, long enough to drive the other column into oblivion.""", "Row 2"],
                  @["Row 3", "has some medium length strings", "Row 3", "Row 3"],
                  @["Row 4", "has some medium length strings", "Row 4", "Row 4"]]

    let
      wi = [(12, true), (40, false), (0, false), (12, true)]
      t2 = table(mess2, title = "Table with horizontal header",
                      caption = "Table with horizontal header")

    print(toRich(t2))

    # let t3 = quickTable(mess2, verticalHeaders = true,
    #                   title = h2("Table with vertical header"),
    #                   caption = h2("Table with vertical header"))
    # print(t3.typicalBorders())

    # let t4 = quickTable(mess2, noheaders = true,
    #                      title = "Table w/o header",
    #                      caption = "Table w/o header").
    #         bpad(1).boldBorders().allBorders()
    # print(t4)
    # let t5 = t4.highlightMatches(@["medium", "the"])
    # print(t5)

    # let t6 = atom("This has one string that's pretty long, ")  +
    #         atom("but the rest are short. But this one is ") +
    #         atom("really long. I mean, really long, long ") +
    #         atom("enough to drive the other column into oblivion.")

    # print(callout(t6.highlightMatches(@["one", "other"])))


  # proc calloutTest() =
  #   let
  #     st  = "This is a test of something I'd really like to know about, " &
  #           "I think??"
  #     txt = nocolors(callout(st, boxStyle = BoxStyleAscii))

  #   print(txt)

  #   var sometest = container(callout(center(pre(txt)))).lpad(10).rpad(10)
  #   print(center(sometest), width = -30)

#   proc nestedTableTest() =
#     let mdText = """
# # Here's a markdown file!

# It's got some body text in it. The first paragraph really isn't
# particularly long, but it is certainly quite a bit longer than the
# second paragraph. So it should wrap, as long as your terminal is not
# insanely wide.

# Oh look, here comes a table!

# | Example | Table    |
# | ------- | -------- |
# | foo     | bar      |
# | crash   | override |

# ## Some list
# - Hello, there.
# - This is an example list.
# - This bullet will be long enough that it can show how we wrap bulleted text intelligently.
# """
#     let crazyTable = @[
#       @[markdown(mdText), markdown(mdText)],
#       @[markdown(mdText), markdown(mdText)]
#     ]
#     let toPrint = quickTable(crazyTable, noheaders = true)
#     print(toPrint)

  import nimutils/logging
  print(r("[h1]Testing Nimutils functionality."))
  basic_subproc_tests()
  instantTableTests()

  var c1 = cell("Heading 1", "h1")
  var c2 = cell("Heading 2", "h2")
  var c3 = cell("Heading 3", "h3")
  var c4 = cell("Heading 4", "h4")
  var c5 = cell("Heading 5", "h5")
  var c6 = cell("Heading 6", "h6")
  var g = grid_new(td_tag = "")

  print(toRich(flow(@[c1, c2, c3, c4, c5, c6])))

  var f = horizontal_flow(@["hello", "this", "is", "a", "test", "of", "the",
                         "emergency", "broadcast", "system.", "Do", "not",
                         "adjust", "your", "dial,", "for", "it", "is",
                         "only", "a", "test."], title = "Hello, table!",
                       caption = "Yup, it's a caption.", borders = false)

  print(toRich(f))

  treeTest()

  print(r("[jazzberry]Goodbye!!"))
