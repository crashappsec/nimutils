## Markdown to HTML conversion, via the MD4C library.
##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022 - 2023, Crash Override, Inc.

include "headers/md4c.nim"
import random, strutils

type MdOpts* = enum
  MdCommonMark              = 0x00000000,
  MdCollapseWhiteSpace      = 0x00000001,
  MdPermissiveAtxHeaders    = 0x00000002,
  MdPermissiveUrlAutoLinks  = 0x00000004,
  MdPermissiveMailAutoLinks = 0x00000008,
  MdNoIndentedCodeBlocks    = 0x00000010,
  MdNoHtmlBlocks            = 0x00000020,
  MdNoHtmlpans              = 0x00000040,
  MdNoHtml                  = 0x00000060,
  MdTables                  = 0x00000100,
  MdStrikeThrough           = 0x00000200,
  MdPermissiveWwwAutoLinks  = 0x00000400,
  MdPermissiveAutoLinks     = 0x0000040c,
  MdTaskLists               = 0x00000800,
  MdLatexMathSpans          = 0x00001000,
  MdWikiLinks               = 0x00002000,
  MdUnderline               = 0x00004000,
  MdHeaderSelfLinks         = 0x00008000,
  MdGithub                  = 0x00008f0c,
  MdCodeLinks               = 0x00010000,
  MdHtmlDebugOut            = 0x10000000,
  MdHtmlVerbatimEntries     = 0x20000000,
  MdHtmlSkipBom             = 0x40000000,
  MdHtmlXhtml               = 0x80000000


type HtmlOutputContainer = ref object
    s: string

proc nimu_process_markdown(s: ptr UncheckedArray[char], n: cuint, p: pointer) {.cdecl,exportc.} =

  var x: HtmlOutputContainer = (cast[ptr HtmlOutputContainer](p))[]
  x.s.add(bytesToString(s, int(n)))

proc c_markdown_to_html(s: cstring, l: cuint, o: pointer,
                        f: cint): cint {.importc, cdecl,nodecl.}

proc markdownToHtml*(s: string, opts: openarray[MdOpts] = [MdGithub]): string =
  var
    container = HtmlOutputContainer()
    res:       cint
    flags:     cint

  for item in opts:
    flags  = flags or cast[cint](item)

  res = c_markdown_to_html(cstring(s), cuint(s.len()), addr container, flags)
  result = container.s

  # TODO: these should move to HTML tags.
  result = result.replace(":exclaim:", "❗")
  result = result.replace(":smiley:", "☺")
  result = result.replace(":warn:", "⚠️")

when isMainModule:
  echo markdownToHtml("""
# Hello world!

| Example | Table |
| ------- | ----- |
| foo     | bar  |
""")
