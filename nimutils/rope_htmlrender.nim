## Initial, very basic verion. Currently does NOT preserve colors,
## fixed width, classes, IDs, custom tags, etc. Not even doing column
## width yet.

const tagsToConvert = ["h1", "h2", "h3", "h4", "h5", "h6", "p", "td", "th",
                       "em", "italic", "i", "u", "inverse", "underline",
                       "strong", "code", "caption", "pre"]

import unicode, rope_base, strutils

proc element(name, contents: string): string =
  result = "\n<" & name & ">\n" & contents & "</" & name & ">\n"

proc nobreak(name, contents: string): string =
  result = "<" & name & ">" & contents  & "</" & name & ">"
  
proc toHtml*(r: Rope, indent = 0): string =
  if r == nil:
    return ""

  case r.kind
  of RopeAtom:
    result = $(r.text) 
  of RopeBreak:
    if r.guts != nil:
      result = element("p", r.guts.toHtml())
    else:
      result = "<br>\n" 
  of RopeLink:
    result = "<a href=" & r.url & ">" & r.toHighlight.toHtml() & "</a>"
  of RopeList:
    var listitems: seq[string]

    for item in r.items:
      listitems.add(nobreak("li", item.toHtml()))

    result = element(r.tag, listitems.join("\n"))

  of RopeTaggedContainer:
    var tag: string
    if r.tag in tagsToConvert:
      tag = r.tag
    else:
      tag = "div"
    result = element(tag, r.contained.toHtml())

  of RopeFgColor, RopeBgColor:
    result = r.toColor.toHtml()

  of RopeTable:
    var title, thead, tbody, tfoot, caption : string

    if r.thead != nil:
      thead = element("thead", r.thead.toHtml())
    if r.tbody != nil:
      tbody = element("tbody", r.tbody.toHtml())
    if r.tfoot != nil:
      tfoot = element("tfoot", r.tfoot.toHtml())
    if r.title != nil:
      title = r.title.toHtml()
    if r.caption != nil:
      caption = r.caption.toHtml()

    if title != "" and caption != "":
      title = element("h2", title)
    elif title != "":
      caption = element("caption", title)
      title   = ""
    else:
      caption = element("caption", caption)

    result = element("table", thead & tbody & tfoot & caption)

  of RopeTableRows:
    var rows: seq[string]
    if r.cells.len() != 0:
      for item in r.cells:
        rows.add(item.toHtml())
      result = rows.join("\n")

  of RopeTableRow:
    var cells: seq[string]
    if r.cells.len() != 0:
      for item in r.cells:
        var cell = item.toHtml()
        if cell.startswith("<td>") or cell.startswith("<th>"):
          cells.add(cell)
        else: 
          cells.add(element("td", cell))
      result = cells.join("\n")

  result &= r.next.toHtml()
      
