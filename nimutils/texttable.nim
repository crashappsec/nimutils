## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import rope_base, rope_construct, rope_prerender, rope_styles, markdown,
       unicode, unicodeid, std/terminal, tables

proc instantTable*[T: string|Rope](cells: openarray[T], caption = Rope(nil),
                                    width = 0, borders = defaultBorderStyle(),
                                    boxStyle = defaultBoxStyle()): Rope =
  ## Given a flat list of items to format into a table, figures out how
  ## many equal-sized columns fit cleanly into the available width, given
  ## the text, and formats it all into a table.
  var
    remainingWidth: int
    numcol                 = 0
    maxWidth               = 0
    row:  seq[Rope]        = @[]
    rows: seq[Rope]        = @[]
    pcts: seq[int]         = @[]
  # This gives every column equal width, and assumes space for borders
  # and pad.

  if width <= 0:
    remainingWidth = terminalWidth() + width

  else:
    remainingWidth = width

  for item in cells:
    let w = item.runeLength()
    if  w > maxWidth:
      maxWidth = w

  numcol = remainingWidth div (maxWidth + 3)
  
  if numcol == 0: numcol = 1
  if numcol > cells.len():
    numcol = cells.len()
    

  for i, item in cells:
    if i != 0 and i mod numcol == 0:
      rows.add(tr(row))
      row = @[]
    row.add(td(item))

  var n = len(cells)
  while n mod numcol != 0:
    row.add(td(""))
    n = n + 1

  rows.add(tr(row))

  for col in 0 ..< numcol:
    pcts.add(0)

  result = table(tbody(rows), caption = caption(caption))
  result.setBorders(borders).boxStyle(boxStyle).colPcts(pcts)
  result = result.setWidth(remainingWidth)
  
proc instantTable*[T: string|Rope](cells: openarray[T], caption: string,
                                    width = 0, borders = defaultBorderStyle(),
                                    boxStyle = defaultBoxStyle()): Rope =
  result = instantTable[T](cells, atom(caption), width, borders, boxStyle)  
template quickTableNoHeaders[T: string|Rope](cells: seq[seq[T]],
                                               tableCaption: Rope): Rope =
  var
    row:  seq[Rope] = @[]
    rows: seq[Rope] = @[]

  for cellrow in cells:
    for item in cellrow:
      row.add(td(item))
    rows.add(tr(row))
    row = @[]

  colors(table(tbody(rows), thead(@[]), caption = caption(tableCaption)))

template quickTableHorizontalHeaders[T: string|Rope](cells: seq[seq[T]],
                                                    tableCaption: Rope): Rope =
  var
    row:  seq[Rope] = @[]
    rows: seq[Rope] = @[]

  for i, cellrow in cells:
    if i == 0:
      for item in cellrow:
        row.add(th(item))
    else:
      for item in cellrow:
        row.add(td(item))
    rows.add(tr(row))
    row = @[]

  table(tbody(rows), caption = caption(tableCaption))

template quickTableVerticalHeaders[T: string|Rope](cells: seq[seq[T]],
                                                   tableCaption: Rope): Rope =
  var
    row:  seq[Rope] = @[]
    rows: seq[Rope] = @[]

  for cellrow in cells:
    for i, item in cellrow:
      if i == 0:
        row.add(th(item))
      else:
        row.add(td(item))
    rows.add(tr(row))
    row = @[]

  table(tbody(rows), caption = caption(tableCaption))

proc quickTable*[T: string|Rope](cells: seq[seq[T]], verticalHeaders = false,
         noheaders = false, caption = Rope(nil), width = 0,
         borders = BorderAll, boxStyle = BoxStyleDouble,
                     colPcts: seq[int] = @[]): Rope =
  if cells.len() == 0:
    raise newException(ValueError, "No cells passed")

  if noHeaders:
    result = colors(cells.quickTableNoHeaders(caption))

  elif not verticalHeaders:
    result = colors(cells.quickTableHorizontalHeaders(caption))
  else:
    result = colors(cells.quickTableVerticalHeaders(caption))

  result.setBorders(borders).boxStyle(boxStyle)

  if colPcts.len() != 0:
    result.colPcts(colPcts)

  if width != 0:
    result = result.setWidth(width)

proc quickTable*[T: string|Rope](cells: seq[seq[T]], caption: string,
         verticalHeaders = false, noheaders = false, width = 0,
         borders = defaultBorderStyle(), boxStyle = defaultBoxStyle(),
                     colPcts: seq[int] = @[]): Rope =
  return quickTable[T](cells, verticalHeaders, noheaders,
                       atom(caption), width, borders, boxStyle, colPcts)

proc callOut*[T: string | Rope](contents: T, width = 0, borders = BorderAll,
                                boxStyle = BoxStyleDouble): Rope =
  var box = container(contents)

  box.center.tpad(1).bpad(1).lpad(1).rpad(1)
  
  result = quickTable(@[@[box]], false, false, Rope(nil), width, borders,
                      boxStyle)

  result.searchOne(@["th", "td"]).get().tpad(0).bpad(0)
  
  for item in result.ropeWalk():
    item.class = "callout"
