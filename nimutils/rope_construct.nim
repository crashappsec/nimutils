## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import  unicode, markdown, htmlparse, tables, parseutils, colortable, rope_base,
        macros

from strutils import startswith, replace

var breakingStyles*: Table[string, bool] = {
    "container"  : true,
    "basic"      : true,
    "caption"    : true,
    "pre"        : true,
    "p"          : true,
    "div"        : true,
    "ol"         : true,
    "ul"         : true,
    "li"         : true,
    "blockquote" : true,
    "q"          : true,
    "small"      : true,
    "td"         : true,
    "th"         : true,
    "title"      : true,
    "h1"         : true,
    "h2"         : true,
    "h3"         : true,
    "h4"         : true,
    "h5"         : true,
    "h6"         : true,
    "left"       : true,
    "right"      : true,
    "center"     : true,
    "justify"    : true,
    "flush"      : true
    }.toTable()


proc noBoxRequired*(r: Rope): bool =
  ## Generally, this call is only meant to be used either internally,
  ## or by a renderer (the ansi renderer being the only one we
  ## currently have).
  ##
  ## Returns true if we have paragraph text that does NOT require any
  ## sort of box... so no alignment, padding, tables, lists, ...
  ##
  ## However, we DO allow break objects, as they don't require boxing,
  ## so it isn't quite non-breaking text.
  ##
  ## This has gotten a bit more complicated with the styling
  ## API. Previously we relied on the tag being in 'breaking
  ## styles'. However, with the style API, one can easily set
  ## properties that change whether a box is implied. So, while we
  ## still check the list of tags that imply a box, we also check the
  ## boolean `noTextExtract`.
  ##
  ## This boolean isn't meant to be definitive; it's only to be added
  ## to nodes that will short-circuit text extraction, so that box
  ## properties get applied, and we don't bother to set it when the
  ## tag already iplies it.

  # This will be used to test containers that may contain some basic
  # content, some not.

  if r == nil:
    return true
  if r.tag in breakingStyles or r.noTextExtract:
    return false
  case r.kind
  of RopeList, RopeTable, RopeTableRow, RopeTableRows:
    return false
  of RopeAtom:
    result = true
  of RopeLink:
    result = r.toHighlight.noBoxRequired()
  of RopeFgColor, RopeBgColor:
    result = r.toColor.noBoxRequired()
  of RopeBreak:
    result = r.guts == Rope(nil)
  of RopeTaggedContainer:
    result = r.contained.noBoxRequired()

  if result != false:
    for item in r.siblings:
      if not item.noBoxRequired():
        return false

proc boxText*(r: Rope): Rope =
  ## Place text that needs to be boxed in an unstyled box.
  result = Rope(kind: RopeTaggedContainer, noTextExtract: true,
                contained: r)

proc textRope*(s: string, pre = false): Rope =
  ## Converts a plain string to a rope object.  By default, white
  ## space is treated as if you stuck the string in an HTML document,
  ## which is to mean, line spacing is mostly ignored; spacing between
  ## elements is handled by the relationship between adjacent items,
  ## like it would be in HTML.
  ##
  ## To skip this processing, specify `pre = true`, which acts like
  ## an HTML <pre> block.
  ##
  ## In both modes, we always replace tabs with four spaces, as
  ## behavior based on tab-stops isn't supported (much better to use
  ## table elements and skip tabs all-together). If you don't like it,
  ## process it before sending it here.
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
        curStr.add("    ")
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
    brk:  Rope
    cur:  Rope

  for line in lines:
    cur  = Rope(kind: RopeAtom, text: line.toRunes())
    if result == Rope(nil):
      result = cur
    else:
      result.siblings.add(Rope(kind: RopeBreak, breakType: BrHardLine))
      result.siblings.add(cur)

proc copy*(r: Rope): Rope =
  ## Makes a recursive copy of a Rope object.

  if r == nil or r.cycle:
    return

  r.cycle = true

  result = Rope(kind: r.kind, noTextExtract: r.noTextExtract,
                 tag: r.tag, class: r.class)

  if r.id != "" and r.id in perIdStyles:
    result.ensureUniqueId()
    perIdStyles[result.id] = perIdStyles[r.id]

  case r.kind
  of RopeAtom:
    result.length      = r.length
    result.text        = r.text
  of RopeBreak:
    result.breakType   = r.breakType
    result.guts        = r.guts.copy()
  of RopeLink:
    result.url         = r.url
    result.toHighlight = r.toHighlight.copy()
  of RopeList:
    for item in r.items:
      result.items.add(item.copy())
  of RopeTaggedContainer:
    result.width      = r.width
    result.contained  = r.contained.copy()
  of RopeTable:
    result.colInfo    = r.colInfo
    result.thead      = r.thead.copy()
    result.tbody      = r.tbody.copy()
    result.tfoot      = r.tfoot.copy()
    result.title      = r.title.copy()
    result.caption    = r.caption.copy()
  of RopeTableRow, RopeTableRows:
    for item in r.cells:
      result.cells.add(item.copy())
  of RopeFgColor, RopeBgColor:
    result.color      = r.color
    result.toColor    = r.tocolor.copy()

  for item in r.siblings:
    result.siblings.add(item.copy())

  r.cycle = false

template canMergeTextRopes(r1, r2: Rope): bool =
  if r1 == nil or r2 == nil: false
  elif   r1.kind != RopeAtom: false
  elif r2.kind != RopeAtom: false
  elif r1.siblings.len() > 0: false
  elif r2.siblings.len() > 0: false
  elif r1.id != "": false
  elif r2.id != "": false
  else: true

proc `+`*(r1: Rope, r2: Rope): Rope =
  ## Returns a concatenation of two rope objects, *copying* the
  ## elements in the rope. This is really only necessary if you might
  ## end up with cycles in your ropes, or might mutate properties of
  ## nodes.
  ##
  ## Typically, `+=` is probably a better bet.
  var
    dupe1 = r1.copy()
    dupe2 = r2.copy()

  if r1 == nil and r2 == nil:
    return nil
  elif r1 == nil:
    return dupe2
  elif dupe1.canMergeTextRopes(dupe2):
    dupe1.text &= dupe2.text
    return dupe1
  else:
    let
      noBox1 = dupe1.noBoxRequired()
      noBox2 = dupe2.noBoxRequired()

    if noBox1 == noBox2:
      result = dupe1
      result.siblings.add(dupe2)
    elif noBox1 == true:
      result = dupe1.boxText()
      result.siblings.add(dupe2)
    else:
      result = dupe1
      dupe1.siblings.add(dupe2.boxText())


proc link*(r1: Rope, r2: Rope): Rope =
  ## Returns the concatenation of two ropes, but WITHOUT copying them.
  ##
  ## In many cases, the object in the first operand will also be
  ## returned, but not always:
  ##
  ## 1) The first parameter might end up getting boxed, since boxed
  ## content cannot live next to unboxed content.
  ##
  ## 2), if the first parameter is nil, the second param will be
  ## returned.
  ##
  ##
  ## But generally, this links the two Ropes (modulo our box
  ## constraint), as opposed to `+=`, which links a copy of the rhs to
  ## the lhs, or `+` which copies both operands.
  ##
  ## We did it this way, because copying is rarely the right thing.
  ##
  ## However, we currently are NOT checking for cycles here. Use +=
  ## if there might be a cycle; it will deep-copy the RHS.
  ##

  if r1 == nil:
    return r2
  if r2 == nil:
    return r1

  var
    lastOnL: Rope

  if r1.siblings.len() == 0:
    lastOnL = r1
  else:
    lastOnL = r1.siblings[^1]

  if lastOnL.canMergeTextRopes(r2):
    lastOnL.text &= r2.text
    result = r1
  else:
    let
      noBox1 = r1.noBoxRequired()
      noBox2 = r2.noBoxRequired()

    if noBox1 == noBox2:
      result = r1
      result.siblings.add(r2)
    elif noBox1:
      result = r1.boxText()
      result.siblings.add(r2)
    else:
      result = r1
      result.siblings.add(r2.boxText())

proc `+=`*(r1: var Rope, r2: Rope) =
  ## Concatenate two ropes, making a copy of the right-hand rope.

  r1 = r1.link(r2.copy())

proc htmlTreeToRope(n: HtmlNode, pre: var seq[bool]): Rope

proc doDescend(n: HtmlNode, pre: var seq[bool]): Rope =
  for item in n.children:
    result = result + item.htmlTreeToRope(pre)

template descend(n: HtmlNode): Rope =
  n.doDescend(pre)

proc extractColumnInfo(n: HtmlNode): seq[ColInfo] =
  # This only extracts % at this point.
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

    result.add(ColInfo(span: span, wValue: pct))

proc noTextExtract(r: Rope): Rope =
  r.noTextExtract = true
  result          = r

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
      result = Rope(kind: RopeTaggedContainer, tag: "right",
                    contained: n.descend())
    of "center":
      result = Rope(kind: RopeTaggedContainer, tag: "center",
                    contained: n.descend())
    of "left":
      result = Rope(kind: RopeTaggedContainer, tag: "left",
                    contained: n.descend())
    of "justify":
      result = Rope(kind: RopeTaggedContainer, tag: "justify",
                    contained: n.descend())
    of "flush":
      result = Rope(kind: RopeTaggedContainer, tag: "flush",
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
          if asRope.tag == "title":
            result.title = asRope
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
    of "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote", "div", "basic",
       "code", "ins", "del", "kbd", "mark", "p", "q", "s", "small", "td", "th",
       "sub", "sup", "title", "em", "i", "b", "strong", "u", "caption",
       "text", "plain", "var", "italic", "strikethrough", "strikethru",
        "underline", "bold":
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
    result = n.contents.textRope(pre[^1])
  else:
    discard

proc htmlTreeToRope(n: HtmlNode): Rope =
  var pre = @[false]

  n.htmlTreeToRope(pre)

proc htmlStringToRope*(s: string, markdown = true, add_div = true): Rope =
  ## Convert text that is either in HTML or in Markdown into a Rope
  ## object. If `markdown = false` it will only do HTML conversion.
  ##
  ## If `add_div` is true, it will encapsulate the result in a 'div'
  ## object.
  ##
  ## Markdown conversion works by using MD4C to convert markdown to an
  ## HTML DOM, and then uses gumbo to produce a tree, which we then
  ## convert to a Rope (which is itself a tree).
  ##
  ## If your input is not well-formed, what you get is
  ## undefined. Basically, we seem to always get trees of some sort
  ## from the underlying library, but it may not map to what you want.


  let html = if markdown: markdownToHtml(s) else: s
  let tree = parseDocument(html).children[1]

  if len(tree.children) == 2 and
     tree.children[1].kind == HtmlWhiteSpace and
     tree.children[0].contents == "p" and
     tree.children[1].contents == "\n" and
     tree.children[0].children.len() == 1:
    result = tree.children[0].children[0].htmlTreeToRope()
  else:
    result = tree.htmlTreeToRope()

  if add_div:
    result = Rope(kind: RopeTaggedContainer, tag: "div", contained: result)

template html*(s: string): Rope =
  ## Converts HTML into a Rope object.
  ##
  ## If your input is not well-formed, what you get is
  ## undefined. Basically, we seem to always get trees of some sort
  ## from the underlying library, but it may not map to what you want.
  s.strip().htmlStringToRope(markdown = false, add_div = true)

proc markdown*(s: string, add_div = true): Rope =
  ## Process the text as markdown.
  s.strip().htmlStringToRope(markdown = true, add_div = true)

proc text*(s: string, pre = true, detect = false): Rope =
  if detect:
    let n = s.strip(trailing = false)
    if n.len() != 0:
      case n[0]
      of '#':
        return s.markdown()
      of '<':
        return s.html()
      else:
        discard
  return s.textRope(pre)

macro basicTagGen(ids: static[openarray[string]]): untyped =
  result = newStmtList()

  for id in ids:
    let
      strNode = newLit(id)
      idNode  = newIdentNode(id)
      decl    = quote do:
        proc `idNode`*(r: Rope): Rope =
          ## Apply the style at the point of a rope node.  Sub-nodes
          ## may override this, but at the time applied, it will
          ## take priority for the node itself.
          if r == nil:
            return r
          else:
            return Rope(kind: RopeTaggedContainer, tag: `strNode`,
                        contained: r)
        proc `idNode`*(s: string, pre = true): Rope =
          ## Turn a string into a rope, styled with this tag.
          if s == "":
            return Rope(nil)
          else:
            return `idNode`(s.textRope(pre))
    result.add(decl)

macro tagGenRename(id: static[string], rename: static[string]): untyped =
  result = newStmtList()

  let
    strNode = newLit(id)
    idNode  = newIdentNode(rename)
    decl    = quote do:
      proc `idNode`*(r: Rope): Rope =
        ## Apply the style at the point of a rope node.  Sub-nodes
        ## may override this, but at the time applied, it will
        ## take priority for the node itself.
        return Rope(kind: RopeTaggedContainer, tag: `strNode`,
                    contained: r)
      proc `idNode`*(s: string, pre = true): Rope =
        ## Turn a string into a rope, styled with this tag.
        return `idNode`(s.textRope(pre))
  result.add(decl)

macro trSetGen(ids: static[openarray[string]]): untyped =
  result = newStmtList()

  for id in ids:
    let
      strNode = newLit(id)
      idNode  = newIdentNode(id)
      decl    = quote do:
        proc `idNode`*(l: seq[Rope]): Rope =
          ## Converge a set of tr() objects into the proper
          ## structure expected by table() (which takes only
          ## one Rope object for this).
          return Rope(kind: RopeTableRows, tag: `strNode`,
                      cells: l)

    result.add(decl)

proc tr*(l: seq[Rope]): Rope =
  ## Converge the passed td() / th() sells into a single row object.
  ## Pass this to thead(), tbody() or tfoot() only.
  return Rope(kind: RopeTableRow, tag: "tr", cells: l)

proc pre*(r: Rope): Rope =
  ## This is generally a no-op on a rope object; pre-formatting
  ## happens when text is initially imported. If you add special
  ## styling for 'pre' though, it will get applied.
  return Rope(kind: RopeTaggedContainer, tag: "pre", contained: r)

proc pre*(s: string): Rope =
  ## Creates a new rope from text, without removing spacing.  This is
  ## essentially an abbreviation for s.textRope(pre = true), though
  ## it does also add a `pre` container node, which will pick up
  ## any styling you choose to apply to that tag.
  return pre(s.textRope(pre = true))

proc atom*(s: string, pre = true): Rope =
  ## Text rope with absolutely no formatting at all, other than the
  ## choice of leaving newlines intact or not (default is to do so).
  if s == "":
    return Rope(nil)
  else:
    return s.textRope(pre)

proc ensureNewline*(r: Rope): Rope {.discardable.} =
  ## Used to wrap terminal output when ensureNl is true, but the
  ## content is not enclosed in a basic block. This is done using
  ## a special 'basic' tag.
  return Rope(kind: RopeTaggedContainer, tag: "basic", contained: r)

proc setWidth*(r: Rope, i: int): Rope =
  ## Returns a rope that constrains the passed Rope to be formatted
  ## within a particular width, as long as the context in which the
  ## rope's being evaluated has at least that much width available.
  let w = Rope(kind: RopeTaggedContainer, tag: "width", contained: r,
               width: i, noTextExtract: true)
  result = Rope(kind: RopeTaggedContainer, tag: "div", contained: w,
                noTextExtract: true)

proc setWidth*(s: string, i: int): Rope =
  ## Returns a rope that constrains the passed string to be formatted
  ## within a particular width, as long as the context in which the
  ## rope's being evaluated has at least that much width available.
  result = noTextExtract(pre(s)).setWidth(i)

proc container*(r: Rope): Rope =
  ## Returns a container with no formatting info; will inherit whatever.
  result = Rope(kind: RopeTaggedContainer, tag: "", contained: r,
                noTextExtract: true)

proc container*(s: string): Rope =
  ## Returns a container with no formatting info; will inherit whatever.
  result = container(atom(s))

proc table*(tbody: Rope, thead: Rope = nil, tfoot: Rope = nil,
            title: Rope = nil, caption: Rope = nil,
             columnInfo: seq[ColInfo] = @[]): Rope =
  ## Generates a Rope that outputs a table. The content parameters
  ## must be created by tbody(), thead() or tfoot(), or else you will
  ## get an error from the internals (we do not explicitly check for
  ## this mistake right now).
  ##
  ## For the title/caption, you *should* provide a title/caption()
  ## object if you want it to be styled appropriately, but this one
  ## should not error if you don't.
  ##
  ## The `columnInfo` field can be set by calling `colPcts`
  ## (currently, we only support percentage based widths, and do not
  ## support column spans or row spans).
  ##
  ## Note that, for various reasons, table style often will not get
  ## applied the way you might expect. To counter that, We wrapped
  ## tables in a generic `container()` node.
  result = container(Rope(kind: RopeTable, tag: "table", tbody: tbody,
                          thead: thead, tfoot: tfoot, title: title,
                          caption: caption, colInfo: columnInfo))


proc colWidthInfo*(input: openarray[(int, bool)]): seq[ColInfo] =
  ## This takes column information and returns what you need
  ## to pass to `table()`.
  ##
  ## The inputs are two-tuples. If the boolean is true, then the
  ## integer is interpreted as an absolute column width. If it's
  ## false, then it's interpreted as a percent.
  ##
  ## Use a percentage of 0 to signal flexible with, based on available
  ## space. If multiple columns have this value, they'll be given
  ## equal space.
  ##
  ## Note that, if you do not specify any values for a table at all,
  ## the system will try to do more intelligent auto-sizing.

  for (v, b) in input:
    result.add(ColInfo(span: 0, wValue: v, absVal: b))

proc colPcts*(pcts: openarray[int]): seq[ColInfo] =
  ## This takes a list of column percentages and returns what you need
  ## to pass to `table()`.
  ##
  ## You can alternately call colPcts() on an existing rope object where
  ## no pcts had been applied before.
  ##
  ## Column widths are determined dynamically when rendering, based on
  ## the available size that we're asked to render into. The given
  ## percentage is used to calculate how much space to use for a
  ## column.
  ##
  ## Percents do not need to add up to 100.
  ##
  ## If you specify a column's with to be 0, this is taken to be the
  ## 'default' width, which we calculate by dividing any space not
  ## allocated to other columns evenly, and giving the same amount to
  ## each column (rounding down if there's no even division).
  ##
  ## However, if there is no room for a default column, we give it a
  ## minimum size of two characters. There is currently no facility
  ## for hiding columns. However, any columns that extend to the right
  ## of the available width will end up truncated.
  ##
  ## Specified percents can also go above 100, but you will see
  ## truncation there as well.
  for item in pcts:
    result.add(ColInfo(wValue: item, span: 1))

proc colors*(r: Rope, removeNested = true): Rope =
  ## Unless no-color is off, use coloring for this item, when
  ## available. The renderer determines what this means.
  ##
  ## This is specifically meant for the terminal, where this gets
  ## interpreted as "don't show any ansi codes at all".
  ##
  ## This does NOT suspend other style processing.
  result = Rope(kind: RopeTaggedContainer, tag: "colors", contained: r)
  if removeNested:
    for item in r.search("nocolors"):
      item.tag = "colors"

proc nocolors*(r: Rope, removeNested = true): Rope =
  ## Explicitly turns off any coloring for this item. However, this is
  ## loosely interpreted; on a terminal it will also turn off any other
  ## ansi codes being used.
  ##
  ## This is specifically meant for the terminal, where this gets
  ## interpreted as "don't show any ansi codes at all".
  ##
  ## This does NOT suspend other style processing.
  result = Rope(kind: RopeTaggedContainer, tag: "nocolors", contained: r)
  if removeNested:
    for item in r.search("colors"):
      item.tag = "nocolors"

basicTagGen(["h1", "h2", "h3", "h4", "h5", "h6",
             "li", "blockquote", "div", "code", "ins", "del", "kbd", "mark",
             "small", "sub", "sup", "width", "title", "em", "strong",
             "caption", "td", "th", "plain"])

tagGenRename("p",   "paragraph")
tagGenRename("q",   "quote")
tagGenRename("u",   "unstructured")
tagGenRename("var", "variable")
trSetGen(["thead", "tbody", "tfoot"])

proc ol*(l: seq[Rope]): Rope =
  ## Taking a list of li() Ropes, returns a Rope for an ordered (i.e.,
  ## numbered) list. Currently, there is no way to change the
  ## numbering style, or to continue numbering from previous lists.
  return Rope(kind: RopeList, tag: "ol", items: l)

proc ol*(l: seq[string]): Rope =
  ## Taking a list of strings, it creates a rope for an ordered list.
  ## The list items are automatically wrapped in li() nodes, but are
  ## otherwise unprocessed.
  var listItems: seq[Rope]
  for item in l:
    listItems.add(li(item))
  return ol(listItems)

proc ul*(l: seq[Rope]): Rope =
  ## Taking a list of li() Ropes, returns a Rope for an unordered
  ## (i.e., bulleted) list.
  return Rope(kind: RopeList, tag: "ul", items: l)

proc ul*(l: seq[string]): Rope =
  ## Taking a list of strings, it creates a rope for a bulleted list.
  ## The list items are automatically wrapped in li() nodes, but are
  ## otherwise unprocessed.
  var listItems: seq[Rope]
  for item in l:
    listItems.add(li(item))
  return ul(listItems)

proc inlineCode*(s: string): Rope =
  ## For formatting code w/o line breaks.
  if s == "":
    return Rope(nil)
  else:
    return Rope(kind: RopeTaggedContainer, tag: "inline",
                contained: s.text(pre = false))

proc join*(l: seq[Rope], s: Rope): Rope =
  ## Works like a regular old join(), but with stylized text.
  if l.len() == 0:
    return

  result = l[0].copy()
  var cur = result

  for i in 1 ..< l.len():
    var next = l[i]
    cur += s.copy()
    cur += next
    next = cur


proc copyToBreakInternal(r: Rope, truncated: var bool,
                         enterOk: var bool): Rope =
  # Copy to a break only.
  if r == nil or r.cycle:
    return

  r.cycle = true

  result = Rope(kind: r.kind, tag: r.tag, class: r.class)

  if r.id != "" and r.id in perIdStyles:
    result.ensureUniqueId()
    perIdStyles[result.id] = perIdStyles[r.id]

  case r.kind
  of RopeAtom:
    result.length = r.length
    for ch in r.text:
      if ch == Rune('\n'):
        break
      result.text.add(ch)
  of RopeBreak, RopeList, RopeTable, RopeTableRow, RopeTableRows:
    truncated = true
    result = nil
    return
  of RopeLink:
    result.url = r.url
    result.toHighlight = r.toHighlight.copyToBreakInternal(truncated, enterOk)
  of RopeFgColor, RopeBgColor:
    result.color   = r.color
    result.toColor = r.toColor.copyToBreakInternal(truncated, enterOk)
  of RopeTaggedContainer:
    if r.tag in breakingStyles or r.noTextExtract:
      if enterOk:
        enterOk = false
      else:
        truncated = true
        result = nil
        return

    result.width = r.width
    result.contained = r.contained.copyToBreakInternal(truncated, enterOk)

  if not truncated:
    for item in r.siblings:
      let newsib = item.copyToBreakInternal(truncated, enterOk)
      if truncated:
        break
      result.siblings.add(newsib)

proc copyToBreak*(r: Rope, addDots = true): Rope =
  ## Copies a rope up until the first break. Thie will NOT go into
  ## tables or lists.
  var
    truncated: bool
    okToEnterContainer = true

  result = r.copyToBreakInternal(truncated, okToEnterContainer)

  if truncated and addDots:
    result = result.link(atom("…"))

proc newBreak*(): Rope =
  ## Return a Rope that forces a line break.
  result = Rope(kind: RopeBreak, breakType: BrHardLine)
