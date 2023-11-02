## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

# Pretty basic table formatting. Works with fixed width unicode, though
# I don't factor out non-printable spaces right now, I just count runes.

import rope_construct, rope_ansirender, markdown, unicode, std/terminal,
       unicodeid

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

proc instantTable*(cells: seq[string], html = false): string =
  var
    remainingWidth         = terminalWidth()
    numcol                 = 0
    maxWidth               = 0
    row:  seq[string]      = @[]
    rows: seq[seq[string]]

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
      rows.add(row)
      row = @[]
    row.add(item.strip())

  var n = len(cells)
  while n mod numcol != 0:
    row.add("")
    n = n + 1

  rows.add(row)

  result = rows.formatCellsAsHtmlTable()

  if not html:
    result = result.stylizeHtml()

proc instantTableWithHeaders*(cells: seq[seq[string]]): string =
  let
    headers = cells[0]
    rest    = cells[1 .. ^1]

  return rest.formatCellsAsHtmlTable(headers).stylizeHtml()
