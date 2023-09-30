## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import os, unicode, unicodedb, unicodedb/widths, unicodeid, sugar, markdown,
       htmlparse, tables, std/terminal, parseutils, options, colortable,
       rope_base, rope_styles

from strutils import startswith, replace


proc rawStrToRope*(instr: string): Rope =
  var s = instr

  s = s.replace("\n\n", $(0x2028))
  s = s.replace("\n", " ")
  s = s.replace("\t", " ")

  var
    lines = s.split(Rune(0x2028))
    prev: Rope
    brk:  Rope
    cur:  Rope

  for line in lines:
    prev = cur
    cur  = Rope(kind: RopeAtom, text: line.toRunes())

    if prev == nil:
      result = cur
    else:
      brk       = Rope(kind: RopeBreak, breakType: BrHardLine)
      prev.next = brk
      brk.next  = cur

proc refCopy*(dst: var Rope, src: Rope) =
  dst.kind = src.kind
  dst.tag  = src.tag

  case src.kind
  of RopeAtom:
    dst.length = src.length
    dst.text   = src.text

  of RopeBreak:
    dst.breakType = src.breakType
    dst.guts      = Rope()
    refCopy(dst.guts, src.guts)

  of RopeLink:
    dst.url = src.url
    var sub: Rope = Rope()
    refCopy(sub, src.toHighlight)
    dst.toHighlight = sub

  of RopeList:
    var
      sub: Rope
      l:   seq[Rope]
    for item in src.items:
      sub = Rope()
      refCopy(sub, item)
      l.add(sub)
    dst.items = l

  of RopeTaggedContainer, RopeAlignedContainer:
    var sub: Rope = Rope()
    refCopy(sub, src.contained)
    dst.contained = sub

  of RopeTable:
    if src.thead != nil:
      dst.thead = Rope()
      refCopy(dst.thead, src.thead)
    if src.tbody != nil:
      dst.tbody = Rope()
      refCopy(dst.tbody, src.tbody)
    if src.tfoot != nil:
      dst.tfoot = Rope()
      refCopy(dst.tfoot, src.tfoot)
    if src.caption != nil:
      dst.caption = Rope()
      refCopy(dst.caption, src.caption)

  of RopeTableRow, RopeTableRows:
    for cell in src.cells:
      var r = Rope()
      refCopy(r, cell)
      dst.cells.add(r)

  of RopeFgColor, RopeBgColor:
    dst.color   = src.color
    dst.toColor = Rope()
    refCopy(dst.toColor, src.toColor)

  if src.next != nil:
    var f = Rope()
    refCopy(f, src.next)
    dst.next = f

proc `&`*(r1: Rope, r2: Rope): Rope =
  var
    dupe1: Rope = Rope()
    dupe2: Rope = Rope()
    probe: Rope

  if r1 == nil and r2 == nil:
    return nil
  elif r1 == nil:
    refCopy(dupe1, r2)
    return dupe1
  elif r2 == nil:
    refCopy(dupe1, r1)
    return dupe1

  refCopy(dupe1, r1)
  refCopy(dupe2, r2)
  probe = dupe1
  while probe.next != nil:
    probe = probe.next

  probe.next = dupe2

  return dupe1

proc `+`*(r1: Rope, r2: Rope): Rope =
  if r1 == nil:
    return r2
  if r2 == nil:
    return r1

  var
    probe: Rope = r1
    last:  Rope

  while true:
    probe.cycle = true
    if probe.next == nil:
      break
    probe = probe.next

  last  = probe
  probe = r2

  while probe != nil:
    if probe.cycle:
       raise newException(ValueError, "Addition would cause a cycle")
    else:
      probe = probe.next

  probe = r1
  while probe != nil:
    probe.cycle = false
    probe = probe.next

  last.next = r2

  return r1

proc htmlTreeToRope(n: HtmlNode): Rope

proc descend(n: HtmlNode): Rope =
  for item in n.children:
    result = result + item.htmlTreeToRope()

proc htmlTreeToRope(n: HtmlNode): Rope =

  case n.kind
  of HtmlDocument:
    result = n.descend()
  of HtmlElement, HtmlTemplate:
    if n.contents.startswith('<') and n.contents[^1] == '>':
      n.contents = n.contents[1 ..< ^1]

    case n.contents
    of "html", "body", "head":
      result = n.descend()
    of "br":
      result = Rope(kind: RopeBreak, breakType: BrHardLine, tag: "br")
    of "p":
      result = Rope(kind: RopeBreak, breakType: BrParagraph,
                    guts: n.descend(), tag: "p")
    of "div":
      result = Rope(kind: RopeBreak, breakType: BrPage,
                    guts: n.descend(), tag: "div")
    of "a":
      let url = if "href" in n.attrs: n.attrs["href"] else: "https://unknown"
      result = Rope(kind: RopeLink, url: url, toHighlight: n.descend(),
                    tag: "a")
    of "ol", "ul":
      result = Rope(kind: RopeList, tag: n.contents)
      for item in n.children:
        result.items.add(item.htmlTreeToRope())
    of "right":
      result = Rope(kind: RopeAlignedContainer, tag: "ralign",
                    contained: n.descend())
    of "center":
      result = Rope(kind: RopeAlignedContainer, tag: "calign",
                    contained: n.descend())
    of "left":
      result = Rope(kind: RopeAlignedContainer, tag: "lalign",
                    contained: n.descend())
    of "thead", "tbody", "tfoot":
      result = Rope(kind:  RopeTableRows, tag: n.contents)
      for item in n.children:
        if item.kind == HtmlWhiteSpace:
          continue
        result.cells.add(item.htmlTreeToRope())
    of "tr":
      result = Rope(kind: RopeTableRow, tag: n.contents)
      for item in n.children:
        if item.kind == HtmlWhiteSpace:
          continue
        result.cells.add(item.htmlTreeToRope())
    of "table":
      result = Rope(kind: RopeTable, tag: "table")
      for item in n.children:
        if item.kind == HtmlWhiteSpace:
          continue
        let asRope = item.htmlTreeToRope()
        case asRope.kind
        of RopeTaggedContainer:
          if asRope.tag == "caption":
            result.caption = asRope
          else:
            discard
        of RopeTableRows:
          if item.contents == "thead":
            result.thead = asRope
          elif item.contents == "tfoot":
            result.tfoot = asRope
          else:
            result.tbody = asRope
        of RopeTableRow:
          if result.tbody == nil:
            result.tbody = Rope(kind: RopeTableRows, tag: "tbody")
          result.cells.add(asRope)
        else: # whitespace colgroup; currently not handling.
          discard
    of "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote",
       "code", "ins", "del", "kbd", "mark", "pre", "q", "s", "small",
       "sub", "sup", "title", "em", "i", "b", "strong", "u", "caption",
       "var", "italic", "strikethrough", "strikethru", "underline", "bold":
      # Since we know about this list, short-circuit the color checking code,
      # even though if no color matches, the same thing happens as happens
      # in this branch...
      result = Rope(kind: RopeTaggedContainer, tag: n.contents,
                    contained: n.descend())
    of "td", "th":
      result = Rope(kind: RopeTaggedContainer, tag: n.contents,
                         contained: n.descend())
    else:
      let colorTable = getColorTable()
      if n.contents in colorTable:
        result = Rope(kind: RopeFgColor, color: n.contents)
        result.toColor = n.descend()
      elif n.contents.startsWith("bg-") and n.contents[3 .. ^1] in colorTable:
        result = Rope(kind: RopeBgColor, color: n.contents[3 .. ^1])
        result.toColor = n.descend()
      elif n.contents.startsWith("#") and len(n.contents) == 7:
        result = Rope(kind: RopeFgColor, color: n.contents[1 .. ^1])
      elif n.contents.startsWith("bg#") and len(n.contents) == 10:
        result = Rope(kind: RopeBgColor, color: n.contents[3 .. ^1])
      else:
        result = Rope(kind: RopeTaggedContainer)
        result.contained = n.descend()

      result.tag = n.contents

    # No branches should have returned, but some might not have set a result.
    if result != Rope(nil):
      if "id" in n.attrs:
        result.id = n.attrs["id"]
      if "class" in n.attrs:
        result.class = n.attrs["class"]

  of HtmlText, HtmlCData:
    result = n.contents.rawStrToRope()
  else:
    discard

converter htmlStringToRope*(s: string): Rope =
  let html = markdownToHtml(s)
  let tree = parseDocument(html)

  return tree.htmlTreeToRope()
