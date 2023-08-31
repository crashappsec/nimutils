# Edited from
#            
#           Nim's Runtime Library
#        (c) Copyright 2017 Nim contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#  
#  (c) Copyright 2022 G. Bareigts
#

import strformat, parseutils, macros

export formatValue


type
  FmtHelper {.shallow.} = object
    s: string
    pos, i: int
    notNumber: bool
    argPos, argLen: int
    namedArgs: bool
    argString: string
    spec: string
    result: string
  SyntaxError* = object of ValueError


proc initFmtHelper(s: string, argLen: int, namedArgs = false): FmtHelper =
  result = FmtHelper(s: s,
                     i: 0,
                     notNumber: false,
                     pos: 0,
                     argPos: -1,
                     argLen: argLen,
                     spec: newStringOfCap(10),
                     result: newStringOfCap(s.len),
                     namedArgs: namedArgs
    )

proc getSpecifier(v: string, pos: int, spec: var string) =
  var ix = pos
  if ix >= v.len-1:
    spec = ""
    return
  for i in 0..<v.len:
    if v[i] == ':':
      ix = i+1
      break
  setLen(spec, v.len-ix)
  for i in 0..(v.len-1-ix):
    spec[i] = v[i+ix]

proc nextFmt*(s: var FmtHelper): bool =
  result = false
  const speChars = {'\\', '{', '}'}
  var fs: string
  s.argString.setLen(0)
  var i = s.pos
  while i < s.s.len:
    case s.s[i]
    of '\\':
      if i + 1 >= s.s.len:
        s.result.add s.s[i]
        i += 1
      else:
        case s.s[i+1]
        of '{', '}':
          s.result.add s.s[i+1]
          i += 2
        else:
          s.result.add s.s[i]
          i += 1
    of '{':
      var pos: int
      let p = parseUntil(s.s, fs, '}', i+1)
      let pt = if s.namedArgs: parseUntil(fs, s.argString, ':', 0) else: parseInt(fs, pos)
      if not s.namedArgs:
        if pt <= 0:
          if s.notNumber: raise newException(SyntaxError, "Cannot use unnumbered format argument after first numbered ones")
          pos = s.i
          inc(s.i)
        else:
          dec(pos)
          s.notNumber = true
        if pos < 0 or pos >= s.argLen:
          raise newException(SyntaxError, $pos & ": Incorrect position of argument")
      getSpecifier(fs, pt, s.spec)
      i += p+2
      s.pos = i
      s.argPos = pos
      return true
    of '}':
      raise newException(SyntaxError, fmt"Incorrect format at char {i} on {s}")
    else:
      let p = parseUntil(s.s, fs, speChars, i)
      if p == 0:
        raise newException(ValueError, "Unexpected error in format string.")
      s.result.add fs
      i += p


template callFormatValue(res, arg, option) {.dirty.} =
  when compiles(formatValue(res, arg, option)):
    formatValue(res, arg, option)
  else:
    formatValue(res, $arg, option)

proc unpackArgs(args: varargs[NimNode]): (seq[NimNode], seq[NimNode]) =
  for argList in args:
    for arg in argList:
      if arg.kind == nnkTableConstr:
        for exp in arg:
          expectKind(exp, nnkExprColonExpr)
          if exp[0].kind != nnkStrLit:
            error("formatstr.format(): a string literal is expected for named arguments" , exp[0])
          result[1].add(exp[0])
          result[0].add(exp[1])
      else:
        result[1].add(newEmptyNode())
        result[0].add(arg)

macro format*(pattern: string, args: varargs[untyped]): string =
  ## Format string `pattern` from `args`
  let (args, argStrings) = unpackArgs(args)
  var namedArgs = false
  for arg in argStrings:
    if arg.kind != nnkEmpty:
      namedArgs = true
      break
  let
    fmtHelper = ident("fmtHelper")
    pos = nnkDotExpr.newTree(fmtHelper, ident("argPos"))
    res = nnkDotExpr.newTree(fmtHelper, ident("result"))
    spec = nnkDotExpr.newTree(fmtHelper, ident("spec"))
    argStr = nnkDotExpr.newTree(fmtHelper, ident("argString"))
    optNamedArgs = newLit(namedArgs)
  var caseBrs: NimNode
  if namedArgs:
    caseBrs = newTree(nnkCaseStmt, argStr)
    for i in 0..<argStrings.len:
      if argStrings[i].kind != nnkEmpty:
        caseBrs.add newTree(nnkOfBranch,
          argStrings[i], getAst(callFormatValue(res, args[i], spec)))

    let caseStringElse = quote do:
      raise newException(ValueError, "formatstr.format(): invalid argument name: '" & `argStr` & "'" )
    caseBrs.add newTree(nnkElse, caseStringElse)
  else:
    caseBrs = newTree(nnkCaseStmt, pos)
    for i in 0..<args.len:
      caseBrs.add newTree(nnkOfBranch,
                          newLit(i), getAst(callFormatValue(res, args[i], spec)))
    caseBrs.add newTree(nnkElse, newTree(nnkDiscardStmt, newEmptyNode()))

  let aLen = newLit(args.len)
  let fmtEval = quote do:
    var `fmtHelper` = initFmtHelper(`pattern`, `aLen`, `optNamedArgs`)
    while `fmtHelper`.nextFmt:
      `caseBrs`
    `fmtHelper`.result
  result = newBlockStmt(newStmtList(fmtEval))
