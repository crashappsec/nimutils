## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import rope_base, rope_construct, rope_prerender, rope_styles, unicode,
       unicodeid, std/terminal, tables, sugar

proc instantTable*[T: string|Rope](cells: openarray[T], title = Rope(nil),
                                    caption = Rope(nil),
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
    row.add(td(text("")))
    n = n + 1

  rows.add(tr(row))

  for col in 0 ..< numcol:
    pcts.add(0)

  result = table(tbody(rows), title = title(title), caption = caption(caption))
  result.setBorders(borders).boxStyle(boxStyle).colPcts(pcts)
  result = result.setWidth(remainingWidth)

proc instantTable*[T: string|Rope](cells: openarray[T], title: string,
                                   caption = "", width = 0,
                                   borders = defaultBorderStyle(),
                                   boxStyle = defaultBoxStyle()): Rope =
  result = instantTable[T](cells, atom(title), atom(caption), width, borders,
                            boxStyle)

template quickTableNoHeaders[T: string|Rope](cells: seq[seq[T]],
                              tableTitle: Rope, tableCaption: Rope): Rope =
  var
    row:  seq[Rope] = @[]
    rows: seq[Rope] = @[]

  for cellrow in cells:
    for item in cellrow:
      row.add(td(item))
    rows.add(tr(row))
    row = @[]

  colors(table(tbody(rows), thead(@[]), title = title(tableTitle),
               caption = caption(tableCaption)))

template quickTableHorizontalHeaders[T: string|Rope](cells: seq[seq[T]],
                               tableTitle: Rope, tableCaption: Rope): Rope =
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

  table(tbody(rows), title = title(tableTitle), caption = caption(tableCaption))

template quickTableVerticalHeaders[T: string|Rope](cells: seq[seq[T]],
                               tableTitle: Rope, tableCaption: Rope): Rope =
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

  table(tbody(rows), title = title(tableTitle), caption = caption(tableCaption))

proc quickTable*[T: string|Rope](cells: seq[seq[T]], verticalHeaders = false,
         noheaders = false, title = Rope(nil), caption = Rope(nil), width = 0,
         borders = defaultBorderStyle(), boxStyle = defaultBoxStyle(),
                     colPcts: seq[int] = @[], class = ""): Rope =
  if cells.len() == 0:
    raise newException(ValueError, "No cells passed")

  if noHeaders:
    result = colors(cells.quickTableNoHeaders(title, caption))

  elif not verticalHeaders:
    result = colors(cells.quickTableHorizontalHeaders(title, caption))
  else:
    result = colors(cells.quickTableVerticalHeaders(title, caption))

  result.setBorders(borders).boxStyle(boxStyle)

  if colPcts.len() != 0:
    result.colPcts(colPcts)

  if width != 0:
    result = result.setWidth(width)

  if class != "":
    for item in result.ropeWalk():
      if item.tag != "" and item.class == "":
        item.class = item.tag & "." & class
      elif item.class == "":
        item.class = class

proc quickTable*[T: string|Rope](cells: seq[seq[T]], title: string,
         caption = "", verticalHeaders = false, noheaders = false, width = 0,
         borders = defaultBorderStyle(), boxStyle = defaultBoxStyle(),
         colPcts: seq[int] = @[], class = ""): Rope =
  return quickTable[T](cells, verticalHeaders, noheaders, atom(title),
                       atom(caption), width, borders, boxStyle, colPcts, class)

proc callOut*[T: string | Rope](contents: T, width = 0, borders = BorderAll,
                                boxStyle = BoxStyleDouble): Rope =
  var box = container(contents)

  box.center.tpad(1).bpad(1).lpad(1).rpad(1)

  result = quickTable(@[@[box]], false, false, Rope(nil), Rope(nil), width,
                      borders, boxStyle)

  result.searchOne(@["th", "td"]).get().tpad(0).bpad(0)

  for item in result.ropeWalk():
    item.class = "callout"

type
  TreeRopeWalker*[T] = (T) -> (Rope, seq[T])
  WalkState[T] = object
    walker:     TreeRopeWalker[T]
    tChar:      Rune
    lChar:      Rune
    hChar:      Rune
    vChar:      Rune
    vpad:       int
    padStr:     seq[Rune]
    noNewLines: bool

proc quickTree[T](cur: T, state: var WalkState): Rope =
  var (myRepr, kids) = state.walker(cur)

  if state.noNewLines:
      myRepr = myRepr.copyToBreak(addDots = true)

  result = li(Rope(kind: RopeAtom, text: state.padstr) + myRepr).tpad(0).bpad(0)

  if len(kids) == 0:
    return

  var
    padStr:  seq[Rune]
    lastPad: seq[Rune]

  for ch in state.padStr:
    if ch == state.tChar or ch == state.vChar:
      padStr.add(state.vChar)
    else:
      padStr.add(Rune(' '))

  lastPad = padStr
  padStr.add(state.tChar)
  lastPad.add(state.lChar)

  for i in 0 ..< state.vpad:
    padstr.add(state.hChar)
    lastPad.add(state.hChar)

  for i, kid in kids:
    if i == kids.len() - 1:
      state.padStr = lastPad
    else:
      state.padStr = padStr

    result += quickTree[T](kid, state)


proc quickTree*[T](root: T, walker: TreeRopeWalker[T], tChar = Rune(0x251c),
                   lChar = Rune(0x2514), hChar = Rune(0x2500),
                   vChar = Rune(0x2502), vpad = 2, noNewlines = true): Rope =
  var state = WalkState[T](walker: walker, tChar: tChar, lChar: lChar,
                           hChar: hChar, vChar: vChar, vpad: vpad,
                           noNewlines: noNewlines)

  result = quickTree[T](root, state).overflow(ODots)
