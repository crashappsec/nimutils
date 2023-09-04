import markdown, htmlparse, strutils, tables

let
    cBlack   = "30"
    cRed     = "31"
    cGreen   = "32"
    cYellow  = "33"
    cBlue    = "34"
    cMagenta = "35"
    cCyan    = "36"
    cWhite   = "37"
    cBrown   = "38;5;94"
    cPurple  = "38;2;94"

    cBGBlack   = "40"
    cBGRed     = "41"
    cBgGreen   = "42"
    cBGYellow  = "43"
    cBGBlue    = "44"
    cBGMagenta = "45"
    cBGCyan    = "46"
    cBGWhite   = "47"

type
  FormattingInfo = ref object
    fgCode:    string
    bgCode:    string
    bold:      bool
    underline: bool
    invert:    bool
    prefix:    string
    postfix:   string

  TableInfo = ref object
    # Rows, columns, cells (which can have multiple lines
    cells:   seq[seq[seq[string]]]
    curRow:  int
    curCell: int

  ConversionCtx = object
    curFormatting: seq[FormattingInfo]
    bulletStack:   seq[int]
    tableStack:    seq[TableInfo]

var
  # Todo... move this stuff into an object.
  h1Info*   = FormattingInfo(fgCode: cCyan, bold: true, underline: true,
                             postfix: "\n")
  h2Info*   = FormattingInfo(fgCode: cGreen, postfix: "\n")
  h3Info*   = FormattingInfo(fgCode: cBgCyan, postfix: "\n")
  h4Info*   = FormattingInfo(fgCode: cBlue, bold: true,
                             prefix: "  [ ", postfix: " ]\n")
  h5Info*   = FormattingInfo(fgCode: cBlue, underline: true,
                             prefix: "  [ ", postfix: " ]\n")
  h6Info*   = FormattingInfo(fgCode: cBlue, invert: true,
                             prefix: "  [ ", postfix: " ]\n")
  thInfo*   = FormattingInfo(fgCode: cCyan, bold: true, underline: true)
  trInfo1*  = FormattingInfo(fgCode: cCyan, bgCode: cBGBlack)
  trInfo2*  = FormattingInfo(fgCode: cBlack, bgCode: cBGCyan)
  emFormat* = FormattingInfo(underline: true)
  bFormat*  = FormattingInfo(bold: true)

proc getFormatCodes(info: FormattingInfo): string =
  var
    codes: seq[string]

  if info.fgCode != "":
    codes.add(info.fgCode)
  if info.bgCode != "":
    codes.add(info.bgCode)
  if info.bold:
    codes.add("1")
  if info.underline:
    codes.add("4")
  if info.invert:
    codes.add("7")

  result = "\e[" & codes.join(";") & "m"

template getReset(): string = "\e[0;22;24;27m"

template withFormat(ctx: var ConversionCtx,
                    fmt: FormattingInfo,
                    code: untyped) =
  ctx.curFormatting.add(fmt)
  let tmp: string = code
  result = fmt.getFormatCodes() & fmt.prefix & tmp & fmt.postfix & getReset()

  discard ctx.curFormatting.pop()
  if len(ctx.curFormatting) != 0:
    result &= getFormatCodes(ctx.curFormatting[^1])

proc formatText(ctx: var ConversionCtx, text: string,
                fmt: FormattingInfo): string =
    ctx.withFormat(fmt, text)

proc toTerminalText(n: HtmlNode, ctx: var ConversionCtx): string
proc mdToTermText*(s: string): string

proc descend(n: HtmlNode, ctx: var ConversionCtx): string =
  for item in n.children:
    result &= item.toTerminalText(ctx)

proc padAndFormatCell(ctx: var ConversionCtx, contents: string, width: int,
                      rowNum: int): string =
  result = " " & contents
  while len(result) <= width:
    # Currently, we're just left-justifying.
    # The <= adds one pad space.
    result &= " "
  if rowNum == 0:
    result = ctx.formatText(result, thInfo)
  elif (rowNum mod 2) != 0:
    result = ctx.formatText(result, trInfo1)
  else:
    result = ctx.formatText(result, trInfo2)

proc formatCurrentTable(ctx: var ConversionCtx): string =
  var
    colWidths:  seq[int]
    rowHeights: seq[int]
    rowLines:   int
    numCols:    int
    lineSeqs:   seq[seq[string]]

  let tbl = ctx.tableStack.pop()

  # First, calculate the # of columns, the # of rows, and:
  # 1) For each row, calculate the number of lines.
  # 2) For each column, calculate the maximum width (colWidths).

  for row in tbl.cells:
    rowLines = 0
    if len(row) > numCols:
      numCols = len(row)
      while len(colWidths) < numCols:
        colWidths.add(0)
    for i, col in row:
      if len(col) > rowLines:
        rowLines = len(col)
      for line in col:
        if len(line) > colWidths[i]:
          colWidths[i] = len(line)
    rowHeights.add(rowLines)

  # Now, use that info to align the columns and rows.

  # Outermost loop is the rows.
  for i in 0 ..< len(rowHeights):
    let
      row       = tbl.cells[i]
      rowHeight = rowHeights[i]

    # Now, iterate over the lines in the row.
    for j in 0 ..< rowHeight:
      # Now iterate on each column in the row. The cell might
      # not exist, and the line might not exist.
      for k in 0 ..< numCols:
        let width = colWidths[k]
        try:
          result &= ctx.padAndFormatCell(row[k][j], width, i)
        except:
          result &= ctx.padAndFormatCell("", width, i)
      result &= "\n"


proc toTerminalText(n: HtmlNode, ctx: var ConversionCtx): string =
  case n.kind:
    of HtmlDocument:
      result = ""
      result &= n.descend(ctx)
    of HtmlElement, HtmlTemplate:
      case n.contents
      of "br":
        result &= n.descend(ctx)
        result &= "\n"
      of "p", "div":
        result = "\n"
        result &= n.descend(ctx)
        result &= "\n"
      of "h1":
        result = "\n"
        ctx.withFormat(h1Info):
          n.descend(ctx)
        result &= "\n"
      of "h2":
        result = "\n"
        ctx.withFormat(h2Info):
          n.descend(ctx)
        result &= "\n"
      of "h3":
        result = "\n"
        ctx.withFormat(h3Info):
          n.descend(ctx)
        result &= "\n"
      of "h4":
        result = "\n"
        ctx.withFormat(h4Info):
          n.descend(ctx)
        result &= "\n"
      of "h5":
        result = "\n"
        ctx.withFormat(h5Info):
          n.descend(ctx)
        result &= "\n"
      of "h6":
        result = "\n"
        ctx.withFormat(h6Info):
          n.descend(ctx)
        result &= "\n"
      of "em":
        ctx.withFormat(emFormat):
          n.descend(ctx)
      of "b", "strong":
        ctx.withFormat(bFormat):
          n.descend(ctx)
      of "a":
        result &= n.descend(ctx)
        if "href" in n.attrs:
          if len(result) != 0:
            result &= "(" & n.attrs["href"] & ")"
          else:
            result &= n.attrs["href"]
      of "li":
        result &= n.descend(ctx)

        var listNum = ctx.bulletStack.pop()

        if listNum == -1:
          result = "\n- " & result.strip()
          ctx.bulletStack.add(-1)
        else:
          listNum = listNum + 1
          result  = "\n" & $(listNum) & ". " & result.strip()
          ctx.bulletStack.add(listNum)

        result &= "\n"
      of "ol":
        ctx.bulletStack.add(0)
        result &= n.descend(ctx)
        discard ctx.bulletStack.pop()
      of "ul":
        ctx.bulletStack.add(-1)
        result &= n.descend(ctx)
        discard ctx.bulletStack.pop()
      of "blockquote":
        result = "\n"
        result &= n.descend(ctx)
        var lines = result.split("\n")
        for i in 0 ..< len(lines):
          lines[i] = "> " & lines[i]
      of "code":
        result = "\n"
        if "class" in n.attrs and n.attrs["class"].endswith("html"):
          result &= descend(n, ctx) # TODO: segv here. .mdToTermText()
        else:
          result &= descend(n, ctx)
        result &= "\n"
      of "table":
        ctx.tableStack.add(TableInfo(curRow: -1))
        discard n.descend(ctx)
        result &= ctx.formatCurrentTable()
      of "tr":
        add(ctx.tableStack[^1].cells, seq[seq[string]](@[]))
        ctx.tableStack[^1].curRow += 1
        discard n.descend(ctx)
      of "th":
        # Eventually deal w/ colspan, rowspan, etc.
        result &= n.descend(ctx)
        result = result.strip()
        ctx.tableStack[^1].cells[^1].add(result.split("\n"))
        ctx.tableStack[^1].curCell += 1
      of "td":
        result &= n.descend(ctx)
        result = result.strip()
        ctx.tableStack[^1].cells[^1].add(result.split("\n"))
        ctx.tableStack[^1].curCell += 1
      # Things to definitely not descend on.
      of "button", "head":
        return ""
      else:
        result &= n.descend(ctx)
    of HtmlText, HtmlCdata:
      return n.contents.replace("\n", " ")
    of HtmlComment, HtmlWhitespace:
      return ""


proc mdToTermText*(s: string): string =
  let
    html = s.markdownToHtml(opts = [MdRenderUnsafe, MdSmart, MdFootnotes])
    tree = html.parseDocument()

  var
    ctx: ConversionCtx

  return tree.toTerminalText(ctx)
