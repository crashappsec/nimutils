# Pretty basic table formatting. Works with fixed width unicode, though
# I don't factor out non-printable spaces right now, I just count runes.

import options, unicode, ansi, std/terminal, std/wordwrap, misc

type
  ColAlignType = enum AlignLeft, AlignCenter, AlignRight
                      
  ColInfo* = ref object
    align*:           ColAlignType
    minChr*:          int
    maxChr*:          int
    wrap*:            bool         # If not wrap, then truncate.
    minAct, maxAct:   int
    table:            TextTable

  TextTable* = ref object
    colWidths:       seq[ColInfo]
    rows:            seq[seq[seq[Rune]]]
    headerRowFmt:    seq[AnsiCode]
    headerColFmt:    seq[AnsiCode]
    evenRowFmt:      seq[AnsiCode]
    oddRowFmt:       seq[AnsiCode]
    numColumns:      int
    cellPadLen:      int
    rowHeaderSep:    Option[Rune]
    rowSep:          Option[Rune]
    colHeaderSep:    Option[Rune]
    colSep:          Option[Rune]
    intersectionSep: Option[Rune]
    flexColumns:     bool # Are the alloc'd columns firm, or ragged?
    fillWidth:       bool
    defaultWrap:     bool


proc toRunes(formatSpec: seq[AnsiCode]): seq[Rune] =
  if len(formatSpec) == 0: return @[]

  result = @[Rune('\e'), Rune('[')]

  for i, code in formatSpec:
    let codeStr = $(code)
    for item in codeStr:
      result.add(Rune(item))
    if i != len(codeStr) - 1:
      result.add(Rune(';'))
      
  result.add(Rune('m'))
  
const
  resetString      = $(toRunes(@[acReset]))
  bareMinimumWidth = 1

proc formatRowSeparator(t: TextTable, widths: seq[int], rownum: int): string =
  var
    thisRowSep: Rune
    interSep:   Rune
  
  if rownum == 0:
    if t.rowHeaderSep.isSome():
      thisRowSep = t.rowHeaderSep.get()
    elif t.rowSep.isSome():
      thisRowSep = t.rowHeaderSep.get()
    else:
      return ""
  else:
    if t.rowSep.isSome():
      thisRowSep = t.rowSep.get()
    else:
      return ""
      
  interSep = getOrElse(t.intersectionSep, thisRowSep)
  result   = ""
  
  for i, width in widths:
    let pad = if i < len(widths) - 1:
                # We pad the cell edge but don't add the sep.
                t.cellPadLen * 2 - 1  
              else:
                t.cellPadLen
    result &= thisRowSep.repeat(width + pad)
    if i != len(widths) - 1:
      result &= interSep
      
  result &= "\n"
                        
proc getFormattingCodes(t: TextTable, row, col: int): seq[AnsiCode] =
  if row == 0 and len(t.headerRowFmt) != 0:
    return t.headerRowFmt
  elif col == 0 and len(t.headerColFmt) != 0:
    return t.headerColFmt
  elif row mod 2 == 0:
    return t.evenRowFmt
  else:
    return t.oddRowFmt

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
                 maxAct: 0,
                 wrap:   table.defaultWrap)
                      
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
    wMax   = if maxWidth > 0: maxWidth else: terminalWidth() + maxWidth
    sepLen = if t.colSep.isSome() or t.colHeaderSep.isSome():
               2 * t.cellPadLen + 1
             else:
               2 * t.cellPadLen
  var
    xtra:        int  # How much space we have left that might need
                      # feeding.
    mostThisRnd: int  # Based on what we know, the most space we will
                      # give out to a cel this round.
    numHungry:   int  # How many cells need more space for their text
    numWilling:  int  # Num of cells that haven't reached max width.
    xtraLast:    int  # Detect fixedpoint if any.
    aMin    = -sepLen # Actual minimum width we could render. We add
                      # sepLen one too many times below, thus start at
                      # -sepLen if there's a sep.
  result = @[]

  xtraLast  = high(int)
  numHungry = 0

  for i, obj in t.colWidths:
    if obj.minChr != obj.maxChr and obj.minChr < obj.maxAct:
      numHungry += 1
    if obj.minChr != high(int):
      aMin += obj.minChr
    else:
      aMin += bareMinimumWidth
      obj.minChr = bareMinimumWidth
    result.add(obj.minChr)
      
    aMin += sepLen

  xtra = wMax - aMin

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

  # If we still have characters we could give out, we check the value
  # of 'fillWidth'.  If it's true, then we will give out characters
  # to any column still 'willing' to take more characters, until
  # we are either out of characters or out of willing columns.

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

proc padAndAlign(contents: seq[Rune],
                 colwidth: int,
                 widthInfo: ColInfo): string =
    let padsize = colwidth - len(contents)

    if padsize <= 0:
      return $(contents)
      
    case widthInfo.align
    of AlignLeft:
      return alignLeft($(contents), colwidth)
    of AlignRight:
      return align($(contents), colwidth)
    of AlignCenter:
      let
        leftpad  = int(padsize / 2)
        rightpad = padsize - leftpad

      result = alignLeft($(contents), colwidth - rightpad)
      result = align(result, colwidth)
      

const ellipsisRune = Rune(0x2026)

proc truncateCell(contents: seq[Rune],
                  colwidth: int): string =
    var res = contents[0 .. colwidth - 1]
    res.add(ellipsisRune)

    return $(res)

proc renderCell(contents:   seq[Rune],
                colwidth:   int,
                widthInfo:  ColInfo,
                formatSpec: seq[AnsiCode]): seq[string] =
  var r: seq[string] # The cell as a series of lines.
  
  # If too long, truncate w/ ellipsis or wrap.
  if len(contents) > colwidth:
    if widthInfo.wrap:
      r = @[]
      let
        wrapped    = $(wrapWords($(contents), colwidth).toRunes())
        preAligned = split(wrapped, Rune('\n'))
      for item in preAligned:
        if len(item) == colwidth:
          r.add(item)
        else:
          r.add(padAndAlign(item.toRunes(), colwidth, widthInfo))
    else:
      r = @[truncateCell(contents, colwidth)]
  # If too short, pad and align.
  elif len(contents) < colwidth:
    r = @[padAndAlign(contents, colwidth, widthInfo)]
  # If it's just right,convert back to string.
  else:
    r = @[$(contents)]

  # If no codes, result = r.  Else, add codes to each line.
  if len(formatSpec) == 0:
    return r

  result = @[]
  for line in r:
    result.add($(toRunes(formatSpec)) & line & resetString)
  
proc render*(t: var TextTable, maxWidth = -2): string =
  let
    cellPad   = repeat(Rune(' '), t.cellPadLen)
    colWidths = computeColWidths(t, maxWidth)
  var
    renderedRows: seq[seq[seq[string]]] = @[]
    rowHeights:   seq[int]

  # For each row, render each cell, computing the height.
  for rownum, row in t.rows:
    var
      renderedRow: seq[seq[string]] = @[]
      height:      int              = 1 
      
    for colnum, cell in row:
      var
        myFormat = t.getFormattingCodes(rownum, colnum)
        cel      = renderCell(cell,
                              colwidths[colnum],
                              t.colWidths[colnum],
                              myFormat)
      if len(cel) > height:
        height = len(cel)
      renderedRow.add(cel)
    
    renderedRows.add(renderedRow)
    rowHeights.add(height)

  # Now it's time to go print crap out.  For each row, we have to
  # consider wrapping.  If the height isn't 1, and there is
  # formatting, then we apply the formatting to a bunch of spaces.
  result = ""
  
  for rownum, row in renderedRows:
    var height = rowHeights[rownum]
    for lineno in 0 ..< height:
      for colnum, cell in row:
        if lineno >= len(cell):
          # Need to fill in the right empty space.
          result &= $(t.getFormattingCodes(rownum, colnum).toRunes())
          result &= repeat(Rune(' '), colwidths[colnum])
          result &= resetString
        else:
          result &= cell[lineno]
          
        if colnum == 0:
          result &= cellpad
          if t.colHeaderSep.isSome():
            result &= t.colHeaderSep.get()
            result &= cellpad            
          elif t.colSep.isSome():
            result &= t.colSep.get()
            result &= cellpad            
        elif colnum != len(colWidths) - 1:
            result &= cellpad          
            if t.colSep.isSome():
              result &= t.colSep.get()
            elif t.colHeaderSep.isSome():
              result &= ' '
            result &= cellpad              
        else:
          result &= "\n"
    if rownum != len(renderedRows) - 1:
      result &= formatRowSeparator(t, colwidths, rownum)
    
proc addRow*(t: var TextTable, rowAsStr: seq[string]) =
  var row: seq[seq[Rune]] = @[]
  
  for cell in rowAsStr:
     row.add(cell.toRunes())
       
  if not t.flexColumns:
    if len(row) != t.numColumns:
      raise newException(ValueError, "Bad number of items in row")
  while len(t.colWidths) < len(row):
    let spec = newColSpec(t)
    t.colWidths.add(spec)
    
  for i, item in row:
    let
      l = len(item)
      w = t.colWidths[i]
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
                   rowSepH                   = some(Rune('-')),
                   colSepH                   = some(Rune(' ')),
                   rowSep                    = none(Rune),
                   colSep                    = some(Rune(' ')),
                   interSectionSep           = some(Rune('-')),
                   rows:    seq[seq[string]] = @[],
                   rHdrFmt: seq[AnsiCode]    = @[],
                   cHdrFmt: seq[AnsiCode]    = @[],
                   eRowFmt: seq[AnsiCode]    = @[],
                   oRowFmt: seq[AnsiCode]    = @[],
                   cSpecs:  seq[ColInfo]     = @[],
                   cellPadLen                = 1,
                   wrapByDefault             = true): TextTable =
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
         
  result.rowHeaderSep    = rowSepH
  result.colHeaderSep    = colSepH
  result.rowSep          = rowSep
  result.colSep          = colSep
  result.intersectionSep = intersectionSep
  result.headerRowFmt    = rHdrFmt
  result.headerColFmt    = cHdrFmt
  result.evenRowFmt      = eRowFmt
  result.oddRowFmt       = oRowFmt
  result.colWidths       = cSpecs
  result.cellPadLen      = cellPadLen
  result.defaultWrap     = wrapByDefault

  for row in rows: addRow(result, row)


when isMainModule:
  var testTable = newTextTable(0, true, rHdrFmt = @[acFont2, acBgCyan],
                               wrapByDefault = true)

  testTable.addRow(@["Col 0", "Col 1", "Col 2"])
  testTable.addRow(@["color", "true", "set the color"])
  testTable.addRow(@["allow_external_config", "true", "This is a really long string that we're really going to want to either truncate or wrap. Let's see what happens."])

  echo testTable.render()
  
  
