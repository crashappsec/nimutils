## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import  unicode, markdown, htmlparse, tables, parseutils, colortable, rope_base,
        macros

from strutils import startswith, replace


proc rawStrToRope*(s: string, pre: bool): Rope =
  var
    curStr = ""
    lines: seq[string]

  if pre:
    for c in s:
      if c == '\n':
        lines.add(curStr)
        curStr = ""
      elif c == '\t':
        curStr.add("    ")
      else:
        curStr.add(c)
  else:
    var skipNewline = false

    for i, c in s:
      if c == '\t':
        curStr.add(c)
      elif c == '\n':
        if skipNewline:
          skipNewLine = false
        elif i + 1 != s.len() and s[i + 1] == '\n':
          lines.add(curStr)
          curStr = ""
          skipNewLine = true
        else:
          curStr.add(' ')
      else:
        curStr.add(c)

  lines.add(curStr)

  var
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
  dst = Rope(kind: src.kind, tag: src.tag)

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
    dst.colInfo = src.colInfo
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

proc `+=`*(r1: var Rope, r2: Rope) =
  if r1 == nil:
    r1 = r2
    return
  r1 = r1 + r2


proc htmlTreeToRope(n: HtmlNode, pre: var seq[bool]): Rope

proc doDescend(n: HtmlNode, pre: var seq[bool]): Rope =
  for item in n.children:
    result = result + item.htmlTreeToRope(pre)

template descend(n: HtmlNode): Rope =
  n.doDescend(pre)

proc extractColumnInfo(n: HtmlNode): seq[ColInfo] =
  for item in n.children:
    var
      span: int
      pct:  int

    if "span" in item.attrs:
      discard parseInt(item.attrs["span"], span)

    if span <= 0:
      span = 1

    if "width" in item.attrs:
      discard parseInt(item.attrs["width"], pct)

    if pct < 0:
      pct = 0

    result.add(ColInfo(span: span, widthPct: pct))

proc htmlTreeToRope(n: HtmlNode, pre: var seq[bool]): Rope =
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
    of "a":
      let url = if "href" in n.attrs: n.attrs["href"] else: "https://unknown"
      result = Rope(kind: RopeLink, url: url, toHighlight: n.descend(),
                    tag: "a")
    of "ol", "ul":
      result = Rope(kind: RopeList, tag: n.contents)
      for item in n.children:
        if item.kind == HtmlWhiteSpace:
          continue
        result.items.add(item.htmlTreeToRope(pre))
    of "right":
      result = Rope(kind: RopeAlignedContainer, tag: "right",
                    contained: n.descend())
    of "center":
      result = Rope(kind: RopeAlignedContainer, tag: "center",
                    contained: n.descend())
    of "left":
      result = Rope(kind: RopeAlignedContainer, tag: "left",
                    contained: n.descend())
    of "justify":
      result = Rope(kind: RopeAlignedContainer, tag: "justify",
                    contained: n.descend())
    of "flush":
      result = Rope(kind: RopeAlignedContainer, tag: "flush",
                    contained: n.descend())
    of "thead", "tbody", "tfoot":
      result = Rope(kind:  RopeTableRows, tag: n.contents)
      for item in n.children:
        if item.kind == HtmlWhiteSpace:
          continue
        result.cells.add(item.htmlTreeToRope(pre))
    of "tr":
      result = Rope(kind: RopeTableRow, tag: n.contents)
      for item in n.children:
        if item.kind == HtmlWhiteSpace:
          continue
        result.cells.add(item.htmlTreeToRope(pre))
    of "table":
      result = Rope(kind: RopeTable, tag: "table")
      for item in n.children:
        if item.kind == HtmlWhiteSpace:
          continue
        if item.contents == "colgroup":
          result.colInfo = item.extractColumnInfo()
          continue
        let asRope = item.htmlTreeToRope(pre)
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
    of "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote", "div",
       "code", "ins", "del", "kbd", "mark", "p", "q", "s", "small", "td", "th",
       "sub", "sup", "title", "em", "i", "b", "strong", "u", "caption",
       "var", "italic", "strikethrough", "strikethru", "underline", "bold":
      # Since we know about this list, short-circuit the color checking code,
      # even though if no color matches, the same thing happens as happens
      # in this branch...
      result = Rope(kind: RopeTaggedContainer, tag: n.contents,
                    contained: n.descend())
    of "pre":
      pre.add(true)
      result = Rope(kind: RopeTaggedContainer, tag: n.contents,
                    contained: n.descend())
      discard pre.pop()
    else:
      let colorTable = getColorTable()
      let below      = n.descend()
      if n.contents in colorTable:
        result = Rope(kind: RopeFgColor, color: n.contents, toColor: below)
      elif n.contents.startsWith("bg-") and n.contents[3 .. ^1] in colorTable:
        result = Rope(kind: RopeBgColor, color: n.contents[3 .. ^1],
                      toColor: below)
      elif n.contents.startsWith("#") and len(n.contents) == 7:
        result = Rope(kind: RopeFgColor, color: n.contents[1 .. ^1],
                      toColor: below)
      elif n.contents.startsWith("bg#") and len(n.contents) == 10:
        result = Rope(kind: RopeBgColor, color: n.contents[3 .. ^1],
                      toColor: below)
      elif n.contents in ["default", "none", "off", "nocolor"]:
        result = Rope(kind: RopeFgColor, color: "", toColor: below)
      elif n.contents in ["bg-default", "bg-none", "bg-off", "bg-nocolor"]:
        result = Rope(kind: RopeBgColor, color: "", toColor: below)
      else:
        result = Rope(kind: RopeTaggedContainer, contained: below)
      result.tag = n.contents

    # No branches should have returned, but some might not have set a result.
    if result != Rope(nil):
      if "id" in n.attrs:
        result.id = n.attrs["id"]
      if "class" in n.attrs:
        result.class = n.attrs["class"]
      if "width" in n.attrs:
        var width: int
        discard parseInt(n.attrs["width"], width)
        result.width = width
  of HtmlText, HtmlCData:
    result = n.contents.rawStrToRope(pre[^1])
  else:
    discard

proc htmlTreeToRope(n: HtmlNode): Rope =
  var pre = @[false]

  n.htmlTreeToRope(pre)

proc htmlStringToRope*(s: string, markdown = true): Rope =
  let html = if markdown: markdownToHtml(s) else: s
  let tree = parseDocument(html).children[1]

  if len(tree.children) == 2 and
     tree.children[1].kind == HtmlWhiteSpace and
     tree.children[0].contents == "p" and
     tree.children[1].contents == "\n" and
     tree.children[0].children.len() == 1:
    return tree.children[0].children[0].htmlTreeToRope()
  else:
    return tree.htmlTreeToRope()

macro basicTagGen(ids: static[openarray[string]]): untyped =
  result = newStmtList()

  for id in ids:
    let
      strNode = newLit(id)
      idNode  = newIdentNode(id)
      hidNode = newIdentNode("html" & id)
      decl    = quote do:
        proc `idNode`*(r: Rope): Rope =
          return Rope(kind: RopeTaggedContainer, tag: `strNode`,
                      contained: r)
        proc `idNode`*(s: string): Rope =
          return `idNode`(s.rawStrToRope(pre = false))
    result.add(decl)

macro tagGenRename(id: static[string], rename: static[string]): untyped =
  result = newStmtList()

  let
    strNode = newLit(id)
    idNode  = newIdentNode(rename)
    hidNode = newIdentNode("html" & id)
    decl    = quote do:
      proc `idNode`*(r: Rope): Rope =
        return Rope(kind: RopeTaggedContainer, tag: `strNode`,
                    contained: r)
      proc `idNode`*(s: string): Rope =
        return `idNode`(s.rawStrToRope(pre = false))
  result.add(decl)

macro hidTagGen(ids: static[openarray[string]]): untyped =
  result = newStmtList()

  for id in ids:
    let
      strNode = newLit(id)
      hidNode = newIdentNode("html" & id)
      decl    = quote do:
        proc `hidNode`*(s: string): string =
          return "<" & `strNode` & ">" & s & "</" & `strNode` & ">"

    result.add(decl)

macro alignedGen(ids: static[openarray[string]]): untyped =
  result = newStmtList()

  for id in ids:
    let
      strNode = newLit(id)
      idNode  = newIdentNode(id)
      hidNode = newIdentNode("html" & id)
      decl    = quote do:
        proc `idNode`*(r: Rope): Rope =
          return Rope(kind: RopeAlignedContainer, tag: `strNode`,
                      contained: r)
        proc `idNode`*(s: string): Rope =
          return `idNode`(s.rawStrToRope(pre = false))
    result.add(decl)

macro trSetGen(ids: static[openarray[string]]): untyped =
  result = newStmtList()

  for id in ids:
    let
      strNode = newLit(id)
      idNode  = newIdentNode(id)
      decl    = quote do:
        proc `idNode`*(l: seq[Rope]): Rope =
          return Rope(kind: RopeTableRows, tag: `strNode`,
                      cells: l)

    result.add(decl)

proc tr*(l: seq[Rope]): Rope =
  return Rope(kind: RopeTableRow, tag: "tr", cells: l)

proc table*(tbody: Rope, thead: Rope = nil, tfoot: Rope = nil,
            caption: Rope = nil, columnInfo: seq[ColInfo] = @[]): Rope =
  result = Rope(kind: RopeTable, tag: "table", tbody: tbody, thead: thead,
                tfoot: tfoot, caption: caption, colInfo: columnInfo)

proc colPcts*(pcts: openarray[int]): seq[ColInfo] =
  for item in pcts:
    result.add(ColInfo(widthPct: item, span: 1))

basicTagGen(["h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote", "div",
             "code", "ins", "del", "kbd", "mark", "small", "sub", "sup",
             "title", "em", "strong", "caption", "td", "th", "italic",
             "strikethru", "underline", "bold"])

tagGenRename("p",   "paragraph")
tagGenRename("q",   "quote")
tagGenRename("u",   "unstructured")
tagGenRename("var", "variable")

alignedGen(["right", "center", "left", "justify", "flush"])

trSetGen(["thead", "tbody", "tfoot"])

hidTagGen(["a", "abbr", "address", "article", "aside", "b", "base", "bdi",
           "bdo", "blockquote", "br", "caption", "center", "cite", "code",
           "col", "colgroup", "data", "datalist", "dd", "details", "dfn",
           "dialog", "dl", "dt", "em", "embed", "fieldset", "figcaption",
           "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6",
           "header", "hr", "i", "ins", "kbd", "label", "legend", "li",
           "link", "main", "mark", "menu", "meta", "meter", "nav", "ol",
           "optgroup", "output", "p", "param", "pre", "progress", "q", "s",
           "samp", "search", "section", "select", "span", "strong", "style",
           "sub", "summary", "sup", "table", "tbody", "td", "tfoot",
           "th", "thead", "title", "tr", "u", "ul"])

proc pre*(r: Rope): Rope =
  return Rope(kind: RopeTaggedContainer, tag: "pre", contained: r)

proc pre*(s: string): Rope =
  return pre(s.rawStrToRope(pre = true))

proc ol*(l: seq[Rope]): Rope =
  return Rope(kind: RopeList, tag: "ol", items: l)

proc ol*(l: seq[string]): Rope =
  var listItems: seq[Rope]
  for item in l:
    listItems.add(li(item))
  return ol(listItems)

proc ul*(l: seq[Rope]): Rope =
  return Rope(kind: RopeList, tag: "ul", items: l)

proc ul*(l: seq[string]): Rope =
  var listItems: seq[Rope]
  for item in l:
    listItems.add(li(item))
  return ul(listItems)

template textRope*(l: string, pre = false): Rope = rawStrToRope(l, pre)
