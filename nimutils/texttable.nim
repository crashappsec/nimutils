## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import rope_base, rope_construct, rope_prerender, rope_styles, markdown,
       unicode, unicodeid, std/terminal

proc formatCellsAsMarkdownList*(base: seq[seq[string]],
                                toEmph: openarray[string],
                                firstCellPrefix = "\n## "): string =
  ## Deprecated; old code.  Kept for short term due to compatability.
  for row in base:
    result &= "\n"
    if firstCellPrefix != "":
      result &= firstCellPrefix
      if len(toEmph) != 0 and toEmph[0] != "":
        result &= "**" & toEmph[0] & "** "

    for i, cell in row:
      if i == 0:
        result &= row[0] & "\n\n"
      else:
        result &= "- "
        if i < len(toEmph) and toEmph[i] != "":
          result &= "**" & toEmph[i] & "** "
          result &= cell & "\n"

    result &= "\n"

  result &= "\n"

proc formatCellsAsHtmlTable*(base:            seq[seq[string]],
                             headers:         openarray[string] = [],
                             mToHtml         = true,
                             verticalHeaders = false): string =
  ## Deprecated; old code.  Kept for short term due to compatability.
  if len(base) == 0:
    raise newException(ValueError, "Table is empty.")

  if verticalHeaders:
    for row in base:
      if len(headers) != len(row):
        raise newException(ValueError, "Can't omit headers when doing " &
          "one cell per table")

      result &= "<table><tbody>"
      for i, cell in row:
        result &= "<tr><th>" & headers[i] & "</th><td>"
        if mToHtml:
          result &= cell.markdownToHtml()
        else:
          result &= cell
        result &= "</td></tr>"
      result &= "</tbody></table>"
  else:
    result &= "<table>"
    if len(headers) != 0:
      result &= "<thead><tr>"
      for item in headers:
        result &= "<th>" & item & "</th>"
      result &= "</tr></thead><tbody>"
    else:
      result &= "<tbody>"

    for row in base:
      result &= "<tr>"
      for cell in row:
        result &= "<td>"
        if mToHtml:
          result &= cell.markdownToHtml()
        else:
          result &= cell
        result &= "</td>"
      result &= "</tr>"
    result &= "</tbody></table>"

proc filterEmptyColumns*(inrows: seq[seq[string]],
                         headings: openarray[string],
                         emptyVals = ["", "None", "<em>None</em>", "[]"]):
 (seq[seq[string]], seq[string]) =
  ## Deprecated. From the pre-rope days.
  var
    columnHasValues: seq[bool]
    returnedHeaders: seq[string]
    newRows:         seq[seq[string]]

  for item in headings:
    columnHasValues.add(false)

  for row in inrows:
    if len(row) != len(headings):
      raise newException(ValueError, "headings.len() != row.len()")
    for i, value in row:
      if value.strip() notin emptyVals:
        columnHasValues[i] = true

  for row in inrows:
    var newRow: seq[string]
    for i, value in row:
      if columnHasValues[i]:
        newRow.add(value)
    newRows.add(newRow)

  for i, header in headings:
    if columnHasValues[i]:
      returnedHeaders.add(header)

  return (newRows, returnedHeaders)

proc instantTable*[T: string|Rope](cells: openarray[T], tableCaption = Rope(nil),
                                    width = -1, borders = BorderAll,
                                    boxStyle = BoxStyleDouble): Rope =
  ## Given a flat list of items to format into a table, figures out how
  ## many equal-sized columns fit cleanly into the available width, given
  ## the text, and formats it all into a table.
  var
    remainingWidth: int
    numcol                 = 0
    maxWidth               = 0
    row:  seq[Rope]        = @[]
    rows: seq[Rope]        = @[]
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

  result = table(tbody(rows), caption = tableCaption)
  result = result.setBorders(borders).boxStyle(boxStyle)
  result = result.setWidth(remainingWidth)

template instantTableNoHeaders[T: string|Rope](cells: seq[seq[T]],
                                               tableCaption: Rope): Rope =
  var
    row:  seq[Rope] = @[]
    rows: seq[Rope] = @[]

  for cellrow in cells:
    for item in cellrow:
      row.add(td(item))
    rows.add(tr(row))
    row = @[]

  colors(table(tbody(rows), thead(@[]), caption = tableCaption))

template instantTableHorizontalHeaders[T: string|Rope](cells: seq[seq[T]],
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

  table(tbody(rows), caption = tableCaption)

template instantTableVerticalHeaders[T: string|Rope](cells: seq[seq[T]],
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

  table(tbody(rows), caption = tableCaption)

proc quickTable*[T: string|Rope](cells: seq[seq[T]], verticalHeaders = false,
         noheaders = false, caption = Rope(nil), width = -1,
         borders = BorderAll, boxStyle = BoxStyleDouble,
                   colPcts: seq[int] = @[]): Rope =
  if cells.len() == 0:
    raise newException(ValueError, "No cells passed")

  if noHeaders:
    result = colors(cells.instantTableNoHeaders(caption))
  elif not verticalHeaders:
    result = colors(cells.instantTableHorizontalHeaders(caption))
  else:
    result = colors(cells.instantTableVerticalHeaders(caption))

  result.setBorders(borders).boxStyle(boxStyle)

  if cells.len() == 1 and cells[0].len() == 1:
    # Special treatment for callouts.
    result.setClass("callout", recurse = true)

  if colPcts.len() != 0:
    result.colPcts(colPcts)

  if width >= 0:
    result = result.setWidth(width)


template instantTableWithHeaders*(cells: seq[seq[string]], horizontal = true,
                                  caption = Rope(nil)): string =
  ## Deprecated, for compatability with older con4m.
  $(instantTable(cells, horizontal, true, caption))


proc callOut*[T: string | Rope](contents: T, width = -1, borders = BorderAll,
                                                     boxStyle = BoxStyleDouble): Rope =
    result = quickTable(@[@[contents.center()]], false, false, Rope(nil),
                         width, borders, boxStyle)
