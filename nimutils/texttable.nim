## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

# Pretty basic table formatting. Works with fixed width unicode, though
# I don't factor out non-printable spaces right now, I just count runes.

import rope_base, rope_construct, markdown, unicode, unicodeid, std/terminal

proc formatCellsAsMarkdownList*(base: seq[seq[string]],
                                toEmph: openarray[string],
                                firstCellPrefix = "\n## "): string =
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

proc instantTable*(cells: openarray[string], tableCaption = Rope(nil)): Rope =
  var
    remainingWidth         = terminalWidth()
    numcol                 = 0
    maxWidth               = 0
    row:  seq[Rope]        = @[]
    rows: seq[Rope]        = @[]
  # This gives every column equal width, and assumes space for borders
  # and pad.

  for item in cells:
    let w = item.strip().runeLength()
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

  return table(tbody(rows), caption = tableCaption)

template instantTableNoHeaders(cells: seq[seq[string]], tableCaption: Rope):
         Rope =
  var
    row:  seq[Rope] = @[]
    rows: seq[Rope] = @[]

  for cellrow in cells:
    for item in cellrow:
      row.add(td(item))
    rows.add(tr(row))
    row = @[]

  table(tbody(rows), thead(@[]), caption = tableCaption)

template instantTableHorizontalHeaders(cells: seq[seq[string]],
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

template instantTableVerticalHeaders(cells: seq[seq[string]],
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


proc instantTable*(cells: seq[seq[string]], verticalHeaders = false,
                   noheaders = false, caption = Rope(nil)): Rope =
  if noHeaders:
    return cells.instantTableNoHeaders(caption)
  elif not verticalHeaders:
    return cells.instantTableHorizontalHeaders(caption)
  else:
    return cells.instantTableVerticalHeaders(caption)

template instantTableWithHeaders*(cells: seq[seq[string]], horizontal = true,
                                  caption = Rope(nil)): string =
  ## Deprecated, for compatability with older con4m.
  $(instantTable(cells, horizontal, true, caption))
