# Pretty basic table formatting. Works with fixed width unicode, though
# I don't factor out non-printable spaces right now, I just count runes.

import options, unicode, std/terminal, std/wordwrap, misc, ansi

type
  ColAlignType* = enum AlignLeft, AlignCenter, AlignRight
                      
  ColInfo* = ref object
    align*:           ColAlignType
    minChr*:          int
    maxChr*:          int
    minAct, maxAct:   int
    table:            TextTable

  TextTable* = ref object
    colWidths:       seq[ColInfo]
    rows:            seq[seq[string]]
    sepFmt:          string                # Ansi codes only.
    headerRowFmt:    string
    headerColFmt:    string
    evenRowFmt:      string
    oddRowFmt:       string
    evenColFmt:      string
    oddColFmt:       string
    headerRowAlign:  Option[ColAlignType]
    numColumns:      int
    leftCellMargin:  string
    rightCellMargin: string
    rowHeaderSep:    Option[Rune]
    rowSep:          Option[Rune]
    colHeaderSep:    Option[Rune]
    colSep:          Option[Rune]
    intersectionSep: Option[Rune]
    flexColumns:     bool # Are the alloc'd columns firm, or ragged?
    fillWidth:       bool
    defaultWrap:     bool
    addTopBorder:    bool
    addLeftBorder:   bool
    addBottomBorder: bool
    addRightBorder:  bool
    maxCellBytes:    int

const
  resetText        = "\e[0m"
  ellipsisRune     = Rune(0x2026)
  bareMinimumWidth = 1
  
# This one applies formatting to the text of a cell.  It assumes the
# cell is fully paddded already, including the margin addition.
proc paddedCellFormat(t: TextTable,
                      text: string,
                      col: int,
                      row: int): string {.inline.} =
  var format: string
  
  if row == 0 and len(t.headerRowFmt) > 0:
    format = t.headerRowFmt
  elif col == 0 and len(t.headerColFmt) > 0:
    format = t.headerColFmt 
  elif len(t.evenRowFmt) > 0 and (row mod 2) == 0:
    format = t.evenRowFmt
  elif len(t.oddRowFmt) > 0 and (row mod 2) != 0:
    format = t.oddRowFmt
  else:
    return text
       
  return format & text & resetText


proc separatorFormat(t: TextTable, sep: string): string =
  if len(t.sepFmt) > 0:
    return t.sepFmt & sep & resetText
  else:
    return sep
    
# We're generally going to call these functions for each cell, from 0
# to len(cols), inclusive.  Meaning, we call for the column that
# doesn't actually exist to the right of the table, as that writes the
# 'r' margin for the cell before, and the right table border if it's
# desired.
#    
# c == current column ix, n == len() columns, so one past the last index.
# returns what to write, including "" if nothing.
proc getColSep(t: TextTable, col: int, n: int): string =
  if t.colSep.isNone() and t.colHeaderSep.isNone():
    return ""
  elif col == 0:
    if not t.addLeftBorder: return ""
  elif col == n:
    if not t.addRightBorder: return ""
    
  if col <= 1:
    # By default, if no col header sep is explicitly provided we use
    # the non-header one.
    if t.colHeaderSep.isSome():
      result = $(t.colHeaderSep.get())
    else:
      result = $(t.colSep.get())
  else:
    if t.colSep.isSome():
      result = $(t.colSep.get())
    else:
      result = " "  # They only wanted something specifically in the header.

  result = separatorFormat(t, result)

proc computeTableOverhead(t: TextTable): int =
  let
    numCol      = len(t.colWidths)
    # Each cell has t.leftCellMargin and t.rightCellMargin as overhead.
    cellMargin  = len(t.leftCellMargin) + len(t.rightCellMargin)
    totalMargin = cellMargin * numCol

  # If columns aren't separated, we are done.
  if t.colSep.isNone() and t.colHeaderSep.isNone():
    return totalMargin

  # Every column except the left definitely has a 1 char separator on
  # its left.
  var sepChars = numCol - 1

  # If this is true, then there's additionally a left border.
  if t.addLeftBorder: sepChars = sepChars + 1

  # Same logic for right border.
  if t.addRightBorder: sepChars = sepChars + 1

  return sepChars + totalMargin
  

proc addMargin(t: TextTable, contents: string): string =
  result = t.leftCellMargin & contents & t.rightCellMargin

proc padAndAlignCell(t: TextTable,
                     contents: string,
                     row, col, colwidth: int): string =
    let numRunes: int = len(contents.toRunes())
    
    if numRunes >= colwidth:
      return contents
    # colwidth does NOT include the cell margins.
    var align: ColAlignType
    if row == 0 and t.headerRowAlign.isSome():
      align = t.headerRowAlign.get()
    else:
      align = t.colwidths[col].align

    case align
    of AlignLeft:
      return alignLeft(contents, colwidth)
    of AlignRight:
      return align(contents, colwidth)
    of AlignCenter:
      let
        rightPad    = int((colwidth - numRunes)/2)
        leftAlignTo = colwidth - rightPad
      
      return align(alignLeft(contents, leftAlignTo), colwidth)

proc truncate*(contents: string, width: int): string =
  let asRunes = contents.toRunes()
  if len(asRunes) <= width:
    return contents

  result = $(asRunes[0 ..< (width - 1)])
  result.add(ellipsisRune)

proc wrapLines(contents: string, colwidth: int): seq[string] =
  return wrapwords(contents, colwidth).split(Rune('\n'))
  
proc getRowSeparator(t:         TextTable,
                     forHeader: bool,
                     colwidths: seq[int]): string =
    var ourSep, crossSep: Rune
      
    if not t.rowSep.isSome():
      if not forHeader or not t.rowHeaderSep.isSome():
        return ""
      ourSep = t.rowHeaderSep.get()
    else:
      ourSep = t.rowSep.get()
    if t.intersectionSep.isSome():
      crossSep = t.intersectionSep.get()
    else:
      crossSep = ourSep

    for i, colWidth in colwidths:
      # Add the separator to the left of this cell's contents.
      if i > 0  or t.addLeftBorder:
        result.add(crossSep)
        
      # Add the contents at the full width including margins.
      let
        n   = colWidths[i] + len(t.leftCellMargin) + len(t.rightCellMargin)
      result.add(ourSep.repeat(n))

    if t.addRightBorder:
      result.add(crossSep)

    if len(t.sepFmt) > 0:
      result = t.sepFmt & result & resetText

    result.add("\n")

proc formatOneLine(t:         TextTable,
                   rownum:    int,
                   colWidths: seq[int],
                   rowData:   seq[string]): string =
  let n = len(colWidths)
  
  for colnum, col in colWidths:
    # getColSep figures out whether or not to write a left border.
    result.add(t.getColSep(colnum, n))
    var
      contents = if colnum > len(rowdata): "" else: rowData[colnum]
      
    contents = truncate(contents, colwidths[colnum])
    contents = t.padAndAlignCell(contents, rownum, colnum, colwidths[colnum])
    contents = t.addMargin(contents)
    result.add(t.paddedCellFormat(contents, colnum, rownum))

  # possibly add a right border.
  result.add(t.getColSep(n, n))
  result.add("\n")
    
proc getOneRow(t: TextTable, rownum: int, colWidths: seq[int]): string =
  return t.formatOneLine(rownum, colWidths, t.rows[rownum])
  
proc getOneRowWrap(t: TextTable, rownum: int, colWidths: seq[int]): string =
  let
    rawRowData = t.rows[rownum]
    n          = len(colWidths)
  var
    rowData:  seq[seq[string]] = @[]
    numLines: int = 0

  for colnum, item in rawRowData:
    var
      thisCell = wrapLines(item, colwidths[colnum])
      maxRows  = high(int)
    
    # We only apply this when wrapping.
    if len(item) > t.maxCellBytes:
      maxRows = int(t.maxCellBytes/colwidths[colnum])
      thisCell = thisCell[0 .. maxRows]
      if len(thisCell[^1]) == colwidths[colnum]:
        thisCell[^1] = truncate(thisCell[^1] & " ", len(thisCell[^1]))
      else:
        thisCell[^1] = thisCell[^1] & $(ellipsisRune)
    rowData.add(thisCell)
    if len(thisCell) > numLines:
      numLines = len(thisCell)

  for i in 0 ..< numLines:
    var oneLine: seq[string] = @[]
    for colnum in 0 ..< n:
      if colnum >= len(rowdata):
        oneLine.add("")
      elif len(rowdata[colnum]) <= i:
        oneLine.add("")
      else:
        oneLine.add(rowdata[colnum][i])
        
    result.add(formatOneLine(t, rownum, colwidths, oneLine))

proc newColSpec*(table: TextTable,
                 align = AlignLeft,
                 minChr = 3,
                 maxChr = high(int)): ColInfo =

  if minChr > maxChr:
    raise newException(ValueError, "minChr can't be > maxChr")
    
  return ColInfo(table:  table,
                 minChr: minChr,
                 maxChr: maxChr,
                 align:  align,
                 minAct: high(int),
                 maxAct: 0)
                      
proc computeColWidths(t: var TextTable, maxWidth: int): seq[int] =
  # Currently, we don't try to do anything too fancy. First, we assume
  # every cell starts at the minimum width.
  #
  # Then, while there's room to go wider, we give out the same number
  # of chars every time, until they all have enough to display their
  # widest actual text.
  #
  # After that, if fillWidth is true, we give out any leftover
  # characters to whoever's max hasn't been reached, evenly.
  
  let
    wMax     = if maxWidth > 0: maxWidth else: terminalWidth() + maxWidth
    overhead = t.computeTableOverHead()

  var
    xtra:        int  # How much space we have left that might need
                      # feeding.
    mostThisRnd: int  # Based on what we know, the most space we will
                      # give out to a cel this round.
    numHungry:   int  # How many cells need more space for their text
    numWilling:  int  # Num of cells that haven't reached max width.
    xtraLast:    int  # Detect fixedpoint if any.
    aMin =       0    # Actual minimum USABLE width we can render.
                      # Specifically, when we're considering the
                      # non-margin, non-separator chars in a row,
                      # what's the minimum we "need" to meet the
                      # row.minChr constraints that have been
                      # specified?
  result = @[]

  xtraLast  = high(int)
  numHungry = 0

  # This loop does two things:
  # 1) It computes aMin, which is the number of usable chars each column
  #    MUST have.
  # 2) It determines which columns have text that cannot be rendered
  #    if the column's width is the minimum width.  These columns
  #    are deemed 'hungry', as long as the allocated width of the
  #    column is less than the maximum allowable width.
  for i, obj in t.colWidths:
    if obj.minChr != obj.maxChr and obj.minChr < obj.maxAct:
      numHungry += 1
    if obj.minChr != high(int):
      aMin += obj.minChr
    else:
      aMin += bareMinimumWidth
      obj.minChr = bareMinimumWidth
    result.add(obj.minChr)

  # We're giving everyone their actual minimum requiredments (aMin),
  # even if it's > wMax.  We also have overhead that is required.  So
  # the number of extra characters we have is what's left when we take
  # the width we're given, and subtract out these two values.
  xtra = wMax - overhead - aMin

  # This loops allocates extra space, but only to HUNGRY columns, and
  # only up to their configured maximum column width (if any). That
  # means this loop allocates space to columns, but only up to the
  # minimum size that would allow it to render the cell in that column
  # that is longest.  And, if that number is longer than the maximum
  # width set for that cel, then it won't allocate past that maximum
  # width.

  # This loop is mostly fair, in that, for each loop, it reserves bytes for each 'hungry' column, equal to xtra / the # of hungry columns.
  #
  # If all columns need that many bytes and still won't get enough
  # space to render their longest string without wrapping or
  # truncating, they're all going to get the same amount.
  #
  # But, if we give a column enough to make it not hungry, xtra can
  # easily be non-zero coming out of the loop, and this could happen
  # once per column in the worst case.
  #
  # And, when we don't have enough allocation for each hungry cell to
  # get a single extra character, then we give out one character at a
  # time until we run out.
  while xtra > 0 and numHungry != 0:
    mostThisRnd = int(xtra / numHungry)
    for i, info in t.colWidths:
      let cellWSoFar = result[i]
      if cellWSoFar >= info.maxAct: continue
      let fullEnoughThreshold = min(info.maxAct, info.maxChr) - cellWSoFar
      var toAdd               = min(xtra, fullEnoughThreshold)

      toAdd = min(toAdd, if mostThisRnd == 0: 1 else: mostThisRnd)
      xtra -= toAdd
      result[i] = cellWSoFar + toAdd
      if result[i] == info.maxAct: numHungry -= 1
      if result[i] == info.maxChr: numWilling -= 1

  # If we still have characters we could give out after feeding
  # "hungry" cells, we check the value of 'fillWidth' to see if there
  # are still columns that would appreciate more space. If we find
  # some, then we will give out characters to any column still
  # 'willing' to take more characters, until we are either out of
  # characters or out of willing columns.
  #
  # Note that we could improve this loop by ignoring columns that
  # don't have text that would wrap (unless no columns have text that
  # would wrap).  That's a minor TODO item.
  if t.fillWidth:
    while xtra > 0 and numWilling != 0:
      mostThisRnd = int(xtra / numWilling)
      for i, info in t.colWidths:
        let
          cellWSoFar = result[i]
          desired    = info.maxChr - cellWSoFar
        var
          toAdd      = min(xtra, desired)

        toAdd = min(toAdd, if mostThisRnd == 0: 1 else: mostThisRnd)
        xtra -= toAdd
        result[i] = cellWSoFar + toAdd
        if result[i] == info.maxChr: numWilling -= 1

proc render*(t: var TextTable, maxWidth = -2): string =
  let
    colWidths = computeColWidths(t, maxWidth)
  var
    hdrSep    = getRowSeparator(t, true,  colWidths)
    rowSep    = getRowSeparator(t, false, colWidths)

  for i in 0 .. len(t.rows):
    if i == 0:
      if t.addTopBorder: result.add(hdrSep)
    elif i == len(t.rows):
      if t.addBottomBorder: result.add(hdrSep)
    elif i == 1:
      result.add(hdrSep)
    else:
      result.add(rowSep)

    if t.defaultWrap and i != len(t.rows):
      result.add(t.getOneRowWrap(i, colWidths))
    elif i != len(t.rows):
      result.add(t.getOneRow(i, colWidths))
      
proc addRow*(t: var TextTable, row: seq[string]) =
  if not t.flexColumns:
    if len(row) != t.numColumns:
      raise newException(ValueError, "Bad number of items in row")
  while len(t.colWidths) < len(row):
    let spec = newColSpec(t)
    t.colWidths.add(spec)
    
  for i, item in row:
    let
      l     = len(item.toRunes())     
      w     = t.colWidths[i]
    if w.table == nil:
      raise newException(ValueError,
                         "Col spec must be allocated through newColSpec")
    elif w.table != t:
      raise newException(ValueError,
                         "Col specs cannot be reused across tables")
    if l < t.colWidths[i].minAct:
      t.colWidths[i].minAct = l
    if l > t.colWidths[i].maxAct:
      t.colWidths[i].maxAct = l
  t.rows.add(row)

proc getColSpecs*(t: TextTable): seq[ColInfo] =
  return t.colWidths

# 0 == flexible or autodetect; negative numbers measure from the back.
proc newTextTable*(numColumns: int           = 0, 
                   fillWidth                 = false,
                   rowHeaderSep              = some(Rune('-')),
                   colHeaderSep              = some(Rune(' ')),
                   rowSep                    = none(Rune),
                   colSep                    = some(Rune(' ')),
                   interSectionSep           = some(Rune('-')),
                   rows:    seq[seq[string]] = @[],
                   sepFmt:  seq[AnsiCode]    = @[], 
                   rHdrFmt: seq[AnsiCode]    = @[],
                   cHdrFmt: seq[AnsiCode]    = @[],
                   eRowFmt: seq[AnsiCode]    = @[],
                   oRowFmt: seq[AnsiCode]    = @[],
                   eColFmt: seq[AnsiCode]    = @[],
                   oColFmt: seq[AnsiCode]    = @[],                            
                   cSpecs:  seq[ColInfo]     = @[],
                   leftMargin                = " ",
                   rightMargin               = " ",
                   addTopBorder              = false,
                   addBottomBorder           = false,
                   addLeftBorder             = false,
                   addRightBorder            = false,
                   headerRowAlign            = none(ColAlignType),
                   wrapByDefault             = true,
                   maxCellBytes              = 0): TextTable =
  if len(cSpecs) != 0: 
    if numColumns != 0 and len(cSpecs) != numColumns:
      raise newException(ValueError, "Provided column count != # of col specs")
    result = TextTable(flexColumns: false,
                       numColumns: numColumns,
                       colWidths: cSpecs)
  elif numColumns == 0:
    result = TextTable(flexColumns: true, numColumns: 0)
  else:
    result = TextTable(flexColumns: false, numColumns: numColumns)

  if not result.flexColumns:
    for row in rows:
      if len(row) != numColumns:
        raise newException(ValueError, "Found row w/ non-conforming # of cols")

  result.rowHeaderSep    = rowHeaderSep
  result.colHeaderSep    = colHeaderSep
  result.rowSep          = rowSep
  result.colSep          = colSep
  result.intersectionSep = intersectionSep
  result.sepFmt          = toAnsiCode(sepFmt)
  result.headerRowFmt    = toAnsiCode(rHdrFmt)
  result.headerColFmt    = toAnsiCode(cHdrFmt)
  result.evenRowFmt      = toAnsiCode(eRowFmt)
  result.oddRowFmt       = toAnsiCode(oRowFmt)
  result.evenColFmt      = toAnsiCode(eColFmt)  
  result.oddColFmt       = toAnsiCode(oColFmt)
  result.colWidths       = cSpecs
  result.leftCellMargin  = leftMargin
  result.rightCellMargin = rightMargin
  result.defaultWrap     = wrapByDefault
  result.headerRowAlign  = headerRowAlign
  result.addTopBorder    = addTopBorder
  result.addBottomBorder = addBottomBorder
  result.addLeftBorder   = addLeftBorder
  result.addRightBorder  = addRightBorder
  result.maxCellBytes    = maxCellBytes

  for row in rows: addRow(result, row)


when isMainModule:
  var testTable = newTextTable(0, true, rHdrFmt = @[acFont2, acBgCyan],
                               wrapByDefault = true)

  testTable.addRow(@["Col 0", "Col 1", "Col 2"])
  testTable.addRow(@["color", "true", "set the color"])
  testTable.addRow(@["allow_external_config", "true", "This is a really long string that we're really going to want to either truncate or wrap. Let's see what happens."])

  echo testTable.render()
  
