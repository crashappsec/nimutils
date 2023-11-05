import misc, sugar, rope_ansirender, terminal, strformat, unicode

type
  ProgressWinchCb = () -> bool
  ProgressBar* = object
    totalItems*: int
    curItems*:   int
    totalWidth*: int
    lastWidth*:  int
    showPct*:    bool
    showBars*:   bool
    showTime*:   bool
    eraseAtEnd*: bool
    color*:      string
    winchCb*:    ProgressWinchCb
    startTime*:  uint64
    progChar*:   Rune
    curChar*:    Rune
    timeColor*:  string
    progColor*:  string
    curColor*:   string
    pctColor*:   string
    barColor*:   string


proc secToDuration*(duration: uint64): string =
  var
    sec = duration mod 60
    mi  = (duration div 60) mod 60
    hr  = duration div 3600

  result = fmt"{mi:02}:{sec:02}"

  if hr != 0:
    result = $(hr) & ":" & result


template updateBar(txt: string) =
    eraseLine()
    stdout.write("\r")
    stdout.write(txt)
    stdout.flushFile()

proc update*(ctx: var ProgressBar, newCur: int): bool {.discardable.} =
  var gotWinch = false

  if newCur == ctx.curItems:
    if ctx.winchCb == ProgressWinchCb(nil):
      return
    if not ctx.winchCb():
      return
    else:
      gotWinch = true

  ctx.curItems = newCur

  var
   (w, _)              = terminalSize()
   elapsedSec          = (unixTimeInMs() - ctx.startTime) div 1000
   curProgress: float  = newCur / ctx.totalItems
   intPct:      int    = int(curProgress * 100.0 )
   pctStr:      string = fmt"{intPct:3}% "
   usedLen:     int    = 0
   bar:         string
   timeStr:     string

  if ctx.showPct:
    usedLen = len(pctStr)
    pctStr  = withColor(pctStr, ctx.pctColor)
  if ctx.showBars:
    usedLen += 2
    bar = withColor("|", ctx.barColor)
  if ctx.showTime:
    timeStr  = " " & elapsedSec.secToDuration() & " "
    usedLen += len(timeStr)
    timeStr  = withColor(timestr, ctx.timeColor)

  let availableLen = w - usedLen

  if availableLen >= 4:
    let
      shownProgress = int(float(availableLen - 1) * curProgress)
      nonProgress   = (availableLen - 1) - shownProgress
      curStr        = withColor($(ctx.curChar), ctx.curColor)
      nonPr         = $(Rune(' ').repeat(nonProgress))
      progRaw       = $(ctx.progChar.repeat(shownProgress))
      progStr       = withColor(progRaw, ctx.progColor)

    updateBar(pctStr & bar & progStr & curStr & nonPr & bar & timeStr)
  else:
    updateBar(pctStr & timeStr)

  if newCur == ctx.totalItems:
    return true
  else:
    showCursor()
    return false

proc initProgress*(ctx: var ProgressBar, totalItems: int, showTime = true,
                   showPct = true, showBars = true, progChar = Rune('-'),
                   winchCb = ProgressWinchCb(nil), eraseAtEnd = false,
                   curChar = Rune('>'), timeColor = "atomiclime",
                   progColor = "jazzberry", curColor = "jazzberry",
                   pctColor = "atomiclime", barColor = "jazzberry") =
  hideCursor()

  ctx.totalItems = totalItems
  ctx.showTime   = showTime
  ctx.showPct    = showPct
  ctx.showBars   = showBars
  ctx.curItems   = -1
  ctx.winchCb    = winchCb
  ctx.startTime  = unixTimeInMs()
  ctx.progChar   = progChar
  ctx.curChar    = curChar
  ctx.timeColor  = timeColor
  ctx.progColor  = progColor
  ctx.curColor   = curColor
  ctx.pctColor   = pctColor
  ctx.barColor   = barColor
  ctx.update(0)
