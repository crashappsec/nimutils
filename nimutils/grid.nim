## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import std/terminal, libwrap


proc horizontal_flow*[T: string|Rich](cells: openarray[T], title: string = "",
                                   caption: string = "", width = 0,
                                   maxcols = 8, borders = true): Grid =
    var
      toPass: seq[Rich]
      ctag: cstring
      width = width

    when T is string:
      for item in cells:
        toPass.add(cast[Rich](c4str(item)))
    else:
      for item in cells:
        toPass.add(item)

    if width < 20:
      width = terminalWidth()

    if borders == true:
      ctag = cstring("table")
    else:
      ctag = cstring("flow")

    var l: Xlist[Rich] = toXList[Rich](toPass)

    var g: Grid = grid_horizontal_flow(l, maxcols,
                                       width, ctag, cstring("td"))

    if title == "" and caption == "":
      return g.grid_to_str(width)

    var flow_items: seq[Grid]

    if title != "":
      flow_items.add(cell(title, "h2"))
    flow_items.add(g)
    if caption != "":
      flow_items.add(cell(caption, "h4"))

    return flow(flow_items)

proc table*[T: string|Rich](cells: seq[seq[T]],
                            title = "",
                            caption = "",
                            table_style = "table",
                            cell_style = "td",
                            heading_style = "th",
                            header_rows = 1,
                            header_cols = 0,
                            borders = true,
                            stripe = true): Grid =
    var
      row:   seq[Rich]
      t:     Grid
      flow:  Grid
      ncols  = 1
      st     = 0

    if stripe:
      st = 1

    for row in cells:
      if len(row) > ncols:
        ncols = len(row)

    t = con4m_grid(cint(len(cells)), cint(ncols), table_style, cell_style,
                   heading_style, cint(header_rows), cint(header_cols),
                   cint(st))

    for inrow in cells:
      when T is string:
        row = @[]
        for item in inrow:
          row.add(cast[Rich](c4str(item)))
      else:
        row = inrow
      var xrow: XList[Rich] = toXList[Rich](row)
      add_row(t, xrow)

    if title == "" and caption == "":
      return t.grid_to_str(terminalWidth())

    var flow_items: seq[Grid]

    if title != "":
      flow_items.add(cell(title, "h2"))
    flow_items.add(t)
    if caption != "":
      flow_items.add(cell(caption, "h4"))

    return flow(flow_items)

proc toRich*(g: Grid, w = terminalWidth()): Rich =
  return g.grid_to_str(w)
