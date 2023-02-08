## I've been using argParse(), but I've been fighting with its
## abstraction.  So instead of starting out with one thing trying to
## be everything to everybody, I'm going to build something focused on
## suiting my needs, particularly:
##
## 1) Give me the ability to automatically handle checking for boolean
##    flags.  Like, if I ask for "color", I should get --color and
##    --no-color.
##
## 2) Similarly, I don't just want --log-level to be a "choice" flag,
##    I want it to also generate --info, --verbose, --warn, etc.
##
## 3) Allow me to have a modern "command" style but let people have
##    some flexibility on messing up, e.g., on where they put flags
##    when there is no ambiguity, how many -'s they user, etc.
##
## 4) Allow me to have a 'default' command.
##
## 5) Do all possible checking before we 'commit' the flags, via
##    callbacks. Basically, I want to be able to hand the config file
##    evaluation control over the behavior of some flags, so I need to
##    know their values before we decide to commit.
##
## 6) Should be able to do a style where flags may be aliased and
##    overridden, OR enforce no conflicts on the command line.
##
## I'm only implementing what I need so far.  No int arguments, no
## count arguments, no multiple flags, etc.  I also skip stuff I
## do not like:
##
##   - Optional flag values (too unintuitive for me as a user)

import unicode, options, sugar, tables, os, misc
import strutils except strip

type
  ArgFlagKind* = enum afBinary, afPair, afChoice, afStrArg
  BinaryCallback* = ()            -> void
  PairCallback*   = (bool)        -> void
  StrCallback*    = (string)      -> void
  StrArrCallback* = (seq[string]) -> void
  CmdCallback*    = (ArgResult)   -> void
  DeferredFlags*  = Table[string, Option[string]]
  FlagInfo = ref object
    seen:  bool
    long:  string
    short: Option[Rune]
    case kind: ArgFlagKind
    of afBinary:
      linkedChoice:   Option[FlagInfo]
      binCallback:    BinaryCallback
    of afPair:
      positive:       bool
      negativeFlag:   FlagInfo
      pairCallback:   PairCallback
    of afChoice:
      choices:        seq[string]
      chosen:         string
      choiceCallback: StrCallback
    of afStrArg:
      value:          string
      strCallback:    StrCallback
  ArgSpec = ref object
    commandName:  Option[string]
    commands:     Table[string, ArgSpec]
    flags:        Table[string, FlagInfo]
    minArgs:      int
    maxArgs:      int
    defaultCmd:   bool
    subOptional:  bool
    argCallback:  StrArrCallback
    cmdCallback:  CmdCallback
  ArgResult* = ref object
    command:       Option[string]
    subresult:     Option[ArgResult]
    flags:         Table[string, FlagInfo]
    args:          seq[string]
    origArgs:      seq[string]
    linkedSpec:    ArgSpec
    noExplicitSub: bool
    implicitStart: int
    startIx:       int # arg index where this command starts...
    endIx:         int # arg index where this command ends...
    stash:         ParseCtx
  ParseCtx = ref object
    args:           seq[string]
    curCmdSpec:     ArgSpec
    curCmdResult:   ArgResult
    topCmdResult:   ArgResult
    clobberOk:      bool
    curIx:          int
    unmatchedFlags: DeferredFlags

template addFlag(ctx: ArgSpec, name: string, fi: FlagInfo) =
  if name in ctx.flags:
    let msg = if len(name) == 1:
                "Duplicate flag: -" & name
              else:
                "Duplicate flag: --" & name
    raise newException(ValueError, msg)
  ctx.flags[name] = fi

proc newArgSpec*(subOptional = false, defaultCmd = false): ArgSpec =
  ArgSpec(commands:    default(Table[string, ArgSpec]),
          flags:       default(Table[string, FlagInfo]),
          minArgs:     0,
          maxArgs:     0,
          subOptional: subOptional,
          defaultCmd:  defaultCmd,
          commandName: none(string),
          argCallback: nil,
          cmdCallback: nil)

proc addBinaryFlag*(ctx:      ArgSpec,
                    short:    Rune,
                    long:     string,
                    callback: BinaryCallback = nil): ArgSpec {.discardable.} =
  let
    shortAsStr = $(short)
    fi         = FlagInfo(seen:         false,
                          long:         long,
                          short:        some(short),
                          kind:         afBinary,
                          linkedChoice: none(FlagInfo),
                          binCallback:  callback)
  ctx.addFlag(shortAsStr, fi)
  ctx.addFlag(long,       fi)

  return ctx

proc addBinaryFlag*(ctx:      ArgSpec,
                    short:    char,
                    long:     string,
                    callback: BinaryCallback = nil): ArgSpec {.discardable.} =
    return addBinaryFlag(ctx, Rune(short), long, callback)

proc addPairedFlag*(ctx:      ArgSpec,
                    short:    Rune,
                    negShort: Rune,
                    long:     string,
                    callback: PairCallback = nil): ArgSpec {.discardable.} =
  var
    shortAsStr = $(short)
    negAsStr   = $(negShort)
    negLong    = "no-" & long
    posi       = FlagInfo(seen:         false,
                          long:         long,
                          short:        some(short),
                          kind:         afPair,
                          positive:     true,
                          pairCallback: callback)
    negi       = FlagInfo(seen:         false,
                          long:         negLong,
                          short:        some(short),
                          kind:         afPair,
                          positive:     false,
                          pairCallback: callback)
  ctx.addFlag(shortAsStr, posi)
  ctx.addFlag(long,       posi)
  ctx.addFlag(negAsStr,   negi)
  ctx.addFlag(negLong,    negi)

  posi.negativeFlag = negi
  negi.negativeFlag = posi
  return ctx

proc addPairedFlag*(ctx:      ArgSpec,
                    short:    char,
                    negShort: char,
                    long:     string,
                    callback: PairCallback = nil): ArgSpec {.discardable.} =
  return addPairedFlag(ctx, Rune(short), Rune(negShort), long, callback)

proc addChoiceFlag*(ctx:           ArgSpec,
                    short:         Rune,
                    long:          string,
                    choices:       openarray[string],
                    flagPerChoice: bool,
                    callback:      StrCallback = nil): ArgSpec {.discardable.} =
  # We won't worry about validating that there are enough choices.
  # Dupe entries won't hurt us either.
  let
    shortAsStr = $(short)
    choicefi   = FlagInfo(seen:           false,
                          long:           long,
                          short:          some(short),
                          kind:           afChoice,
                          choices:        @choices,
                          chosen:         "",
                          choiceCallback: callback)

  ctx.addFlag(shortAsStr, choicefi)
  ctx.addFlag(long,       choicefi)

  if flagPerChoice:
    for item in choices:
      let fi = FlagInfo(seen:         false,
                        kind:         afBinary,
                        long:         item,
                        short:        none(Rune),
                        linkedChoice: some(choicefi))
      ctx.addFlag(item, fi)

  return ctx

proc addChoiceFlag*(ctx:           ArgSpec,
                    short:         char,
                    long:          string,
                    choices:       openarray[string],
                    flagPerChoice: bool,
                    callback:      StrCallback = nil): ArgSpec {.discardable.} =
  return addChoiceFlag(ctx, Rune(short), long, choices, flagPerChoice, callback)

proc addFlagWithStrArg*(ctx:      ArgSpec,
                        short:    Rune,
                        long:     string,
                        callback: StrCallback = nil): ArgSpec {.discardable.} =
  let
    shortAsStr = $(short)
    fi         = FlagInfo(seen:        false,
                          long:        long,
                          short:       some(short),
                          kind:        afStrArg,
                          strCallback: callback)

  ctx.addFlag(shortAsStr, fi)
  ctx.addFlag(long,       fi)
  return ctx

proc addFlagWithStrArg*(ctx:      ArgSpec,
                        short:    char,
                        long:     string,
                        callback: StrCallback = nil): ArgSpec {.discardable.} =
  return addFlagWithStrArg(ctx, Rune(short), long, callback)

proc addCommand*(ctx:          ArgSpec,
                 name:         string,
                 aliases:      openarray[string] = [],
                               callback:     CmdCallback = nil,
                 allowDefault: bool = false): ArgSpec {.discardable.} =
    result  = ArgSpec(commandName: some(name),
                      flags:       default(Table[string, FlagInfo]),
                      minArgs:     0,
                      maxArgs:     0,
                      defaultCmd:  allowDefault,
                      cmdCallback: callback)

    if name in ctx.commands:
      raise newException(ValueError, "Duplicate command name: " & name)
    ctx.commands[name] = result
    for alias in aliases:
      if alias in ctx.commands:
        raise newException(ValueError, "Duplicate command name: " & alias)
      ctx.commands[alias] = result

proc addArgs*(ctx:      ArgSpec,
              min:      int = 0,
              max:      int = high(int),
              callback: StrArrCallback = nil): ArgSpec {.discardable.} =
  if min < 0 or max < 0 or min > max:
    raise newException(ValueError, "Invalid arguments")

  ctx.minArgs     = min
  ctx.maxArgs     = max
  ctx.argCallback = callback

  return ctx

proc getCmdErrorPrefix(ctx: ParseCtx, i: int): string =
  if ctx.topCmdResult.subresult.isNone():
    return ""

  var
    cmdCtx    =  ctx.topCmdResult
    atTop     = true

  if cmdCtx.endIx > i:
    return ""

  result = ""

  while cmdCtx.endIx < i:
    if atTop:
      result &= "In command " & cmdCtx.command.get()
      atTop   = false
    else:
      result &= ", in subcommand: " & cmdCtx.command.get()
    cmdCtx = cmdCtx.subresult.get()

  result &= ": "

proc noMoreArgsInCmdCheck(ctx: ParseCtx, locIfError: int) =
  if ctx.curCmdSpec.minArgs > ctx.curCmdResult.args.len():
    raise newException(ValueError,
                       ctx.getCmdErrorPrefix(locIfError) &
                         "Not enough arguments given.")

proc parseArgError(ctx: ParseCtx, index: int) =
  # It's a bad command or sub-command name, or spurious args.
  if ctx.curCmdSpec.maxArgs == 0:
    if len(ctx.curCmdSpec.commands) != 0:
      raise newException(ValueError,
                         ctx.getCmdErrorPrefix(index) &
                           "Unknown command: " & ctx.args[index])
    else:
      raise newException(ValueError,
                         ctx.getCmdErrorPrefix(index) &
                           "No arguments expected")
  else:
    if len(ctx.curCmdSpec.commands) != 0:
      raise newException(ValueError,
                         ctx.getCmdErrorPrefix(index) &
                           "Unknown command: " & ctx.args[index])
    else:
      raise newException(ValueError,
                         ctx.getCmdErrorPrefix(index) & "Too many arguments")

proc setCommandBoundaries(ctx: ParseCtx, ix: int) =
  # We start out by identifying commands and subcommands.
  # We only consider valid subcommands for matched commands.
  ctx.curCmdResult.startIx = ix
  # If there are no possible sub-commands, the rest of the args belong
  # to us.
  if ctx.curCmdSpec.commands.len() == 0:
    ctx.curCmdResult.endIx = len(ctx.args)
    return
  # Search until we find one of our valid sub-commands.
  for i in ix ..< len(ctx.args):
    let cmd = ctx.args[i]
    if cmd in ctx.curCmdSpec.commands:
      ctx.curCmdResult.command = some(cmd)
      ctx.curCmdResult.endIx   = i
      let
        newSub = ArgResult(flags:         default(Table[string, FlagInfo]),
                           args:          @[],
                           subresult:     none(ArgResult),
                           command:       none(string),
                           noExplicitSub: false,
                           implicitStart: -1,
                           linkedSpec:    ctx.curCmdSpec.commands[cmd])
        savedSpec = ctx.curCmdSpec
        savedRes  = ctx.curCmdResult

      ctx.curCmdResult.subresult = some(newSub)
      ctx.curCmdResult           = newSub
      ctx.curCmdSpec             = newSub.linkedSpec

      setCommandBoundaries(ctx, i + 1)

      ctx.curCmdSpec   = savedSpec
      ctx.curCmdResult = savedRes
      return
  # We found none of our valid sub-commands.  If we allow a default
  # command (that, in SAMI, we fully resolve after reading the config
  # file), then we mark that's what we got.  Otherwise, we error.

  if ctx.curCmdSpec.defaultCmd:
    ctx.curCmdResult.noExplicitSub = true
  elif not ctx.curCmdSpec.subOptional:
    var s: seq[string] = @[]
    for _, v in ctx.curCmdSpec.commands:
      let name = v.commandName.get()
      if name notin s:
        s.add(name)
    raise newException(ValueError,
                       ctx.getCmdErrorPrefix(len(ctx.args)) &
                         "No command found. Expected one of " & s.join(", "))

  ctx.curCmdResult.endIx = len(ctx.args)

proc findBestSpec(ctx: ParseCtx,
                  name: string,
                  soFar: Option[FlagInfo]): Option[FlagInfo] =
  var
    res  = ctx.curCmdResult
    spec = ctx.curCmdSpec

  if name notin spec.flags:
    # Look to the next subcommand.
    if res.subresult.isNone():
      return soFar
    else:
      ctx.curCmdResult = res.subresult.get()
      ctx.curCmdspec   = ctx.curCmdResult.linkedSpec
      return ctx.findBestSpec(name, soFar)

  if res.endIx < ctx.curIx:
    # Flag found in a command from before the current context. If
    # it's the only thing spec'd, it's right.
    ctx.curCmdResult = res.subresult.get()
    ctx.curCmdspec   = ctx.curCmdResult.linkedSpec
    return ctx.findBestSpec(name, some(spec.flags[name]))
  elif res.startIx >= ctx.curIx:
    # No flag found IN our context, but one found in a subcommand.
    # Check to see if there's a conflict w/ a parent context.
    if soFar.isNone():
      return some(spec.flags[name])
    else:
      raise newException(ValueError, "Ambiguous flag provided: '" & name &
                          "' (Doesn't exist in its current command, but does " &
                           "exist for both parent and children commands.")
  else:
    # Exact match found in the right context.
    return some(spec.flags[name])

proc findFlagInfo(ctx: ParseCtx, name: string): Option[FlagInfo] =
  let
    savedSpec   = ctx.curCmdSpec
    savedResult = ctx.curCmdResult

  ctx.curCmdResult = ctx.topCmdResult
  ctx.curCmdSpec   = ctx.topCmdResult.linkedSpec

  result = ctx.findBestSpec(name, none(FlagInfo))

  ctx.curCmdSpec   = savedSpec
  ctx.curCmdResult = savedResult

proc setFlagValue(ctx: ParseCtx, spec: FlagInfo, value: string) =
  if spec.seen and not ctx.clobberOk:
    # Note this might be a little unclear if we did --log-level=info
    # and then go on to do --warn, but ok for now.
    raise newException(ValueError, "Duplicate flag value: " & spec.long)

  spec.seen = true

  case spec.kind
  of afChoice:
    if value notin spec.choices:
      raise newException(ValueError, "For flag: " & spec.long & ", '" &
        value & "' is not a valid choice.  Valid choices are: " &
        spec.choices.join(", "))
    spec.chosen = value
  of afStrArg:
    spec.value = value
  else:
    raise newException(ValueError, "For flag: " & spec.long &
      "': string argument is not allowed.")


proc setFlagValue(ctx: ParseCtx, spec: FlagInfo) =
  case spec.kind
  of afBinary:
    if spec.linkedChoice.isSome():
      let realSpec = spec.linkedChoice.get()
      ctx.setFlagValue(realSpec, spec.long)
    else:
      if spec.seen and not ctx.clobberOk:
        raise newException(ValueError, "Duplicate flag: " & spec.long)
      spec.seen = true
  of afPair:
    if not ctx.clobberOk:
      if spec.seen:
        raise newException(ValueError, "Duplicate flag: '" & spec.long & "'")
      elif spec.negativeFlag.seen:
        raise newException(ValueError, "Conflicting flags: '" & spec.long &
          "' and '" & spec.negativeFlag.long & "'")
      else:
        spec.seen = true
    else:
      spec.seen              = true
      spec.negativeFlag.seen = false
  else:
    unreachable

proc setUnmatchedFlag(ctx: ParseCtx, name: string, value: Option[string]) =
  if name in ctx.unmatchedFlags:
    if ctx.clobberOk:
      ctx.unmatchedFlags[name] = value
    else:
      raise newException(ValueError, "Duplicate flag provided: " & name)
  ctx.unmatchedFlags[name] = value

proc setFlagValue(ctx: ParseCtx, name: string, value: string) =
  let `spec?` = ctx.findFlagInfo(name)
  if `spec?`.isNone():
    ctx.setUnmatchedFlag(name, some(value))
  else:
    ctx.setFlagValue(`spec?`.get(), value)

proc parseFlag(ctx: ParseCtx, name: string): string =
  # Return "" if fully parsed, the name if we're waiting on an argument.
  var
    s = name.strip()
    ix: int

  if s == "-":
    return # One dash alone is a no-op, needed to allow null strings in flags.

  while s[0] == '-':
    s = s[1 .. ^1]
    if len(s) == 0:
      raise newException(ValueError, "All-dash args only allowed for - and -- ")

  ix = s.find('=')
  if ix == -1:
    ix = s.find(':')

  if ix != -1:
    let val = s[(ix + 1) .. ^1]
    s = s[0 ..< ix]
    ctx.setFlagValue(s, val)
    return

  let `spec?` = ctx.findFlagInfo(s)
  if `spec?`.isNone():
    # Assume it's some flag we haven't matched from an implicit command.
    # Because we don't have enough info, in this one circumstance we have
    # to adhere to the tradition that "--flag foo" should not be allowed.
    ctx.setUnmatchedFlag(s, none(string))
    return ""
  else:
      let spec = `spec?`.get()
      if spec.kind in [afBinary, afPair]:
        ctx.setFlagValue(spec)
        return ""
      else:
        # Got afChoice or afStrArg, so waiting on an argument.
        return s

proc parseCurrentCommand(ctx: ParseCtx) =
  var
    flagsDone   = false # We have not seen -- this command / subcommand.
    curFlagName = ""    # State for when we get --flag arg or --flag=arg
  let
    curResult = ctx.curCmdResult
    startIx   = curResult.startIx
    endIx     = curResult.endIx
    curSpec   = curResult.linkedSpec

  for i in startIx ..< endIx:
    if curFlagName != "":
      ctx.curIx = i
      ctx.setFlagValue(curFlagName, ctx.args[i])
      curFlagName = ""
    elif ctx.args[i][0] == '-' and not flagsDone:
      if ctx.args[i] == "--":
        flagsDone = true
      else:
        # Will set to "" if the flag is fully parsed.
        ctx.curIx = i
        curFlagName = ctx.parseFlag(ctx.args[i])
    elif len(ctx.args[i]) != 0:  # ignore empty args.
      if curSpec.maxArgs != curResult.args.len():
        curResult.args.add(ctx.args[i])
      else:
        if curResult.noExplicitSub:
          curResult.implicitStart = i
          curResult.endIx = i
          return
        else:
          ctx.parseArgError(i)

  if curFlagName != "":
    raise newException(ValueError,
              ctx.getCmdErrorPrefix(startIx) &
                "Expecting an argument for flag: '" & curFlagName & "'")

  ctx.noMoreArgsInCmdCheck(startIx)
  if curResult.subresult.isSome():
    ctx.curCmdResult = curResult.subresult.get()
    ctx.curCmdSpec   = ctx.curCmdResult.linkedSpec
    ctx.parseCurrentCommand()

proc sanityCheckUnmatchedFlags(ctx: ParseCtx): bool =
  # We can only have at most one default context, and it will
  # be the last command.
  var ambiguousCmd = ctx.topCmdResult

  while ambiguousCmd.subresult.isSome():
    ambiguousCmd = ambiguousCmd.subresult.get()

  if len(ctx.unmatchedFlags) == 0:
    if not ambiguousCmd.noExplicitSub:
      # The bottom section is explicit and we have no unmatched
      # flags, so we are done.
      return true
    return false

  var linkedSpec = ambiguousCmd.linkedSpec

  if not ambiguousCmd.noExplicitSub:
    # The bottom section was explicit; we just have unknown flag(s).
    # This results in an error being rased.
    var msg = "Invalid flag"
    if len(ctx.unmatchedFlags) > 1:
      msg &= "s: "
      var arr: seq[string] = @[]
      for k, _ in ctx.unmatchedFlags:
        arr.add(k)

      msg &= arr.join(", ")
    else:
      msg &= ": "
      for k, _ in ctx.unmatchedFlags:
        msg &= k
    raise newException(ValueError, msg)

  for flag, `val?` in ctx.unmatchedFlags:
    var found = false

    for cmd, spec in linkedSpec.commands:
      if flag in spec.flags:
        let flagInfo = spec.flags[flag]
        if flagInfo.kind in [afBinary, afPair]:
          if `val?`.isNone():
            found = true
            break
        else:
          if `val?`.isSome():
            found = true
            break

    if not found:
      if `val?`.isNone():
        raise newException(ValueError, "Invalid flag: --" & flag)
      else:
        raise newException(ValueError, "Invalid flag: --" & flag &
          "= " & `val?`.get())

  return false # Still have resolution that needs to happen.

proc mostlyParse*(ctx:            ArgSpec,
                  passedArgs:     openarray[string] = [],
                  topHasDefault = false,
                  clobberOk     = false): (ArgResult, bool) =
  ## You probably don't want this version of parsing.
  ##
  ## This version of parse allows for some last-minute ambiguity.
  ## Specifically, it's designed to return if the final sub-command
  ## (which can be the top level command) is not explicitly specified.
  ##
  ## I built things this way because of SAMI; the start-up sequence
  ## runs an embedded (but user supplied) configuration file, where I
  ## want them to be able to do different things based on command or
  ## the flags supplied, but if no command is supplied, then the
  ## config file should be able to set a default value.
  ##
  ## The reason that's valuable is because we want people to be able
  ## to distribute versions of the command that do NOT need any
  ## outside configuration, and want them to be able to, from the
  ## config, even disable functionality they don't want to expose, so
  ## as to remove complexity.
  ##
  ## I could also imagine wanting to try to infer best fit if people
  ## omit a command.
  ##
  ## In both of those cases, we ideally want to resolve anything that
  ## isn't ambiguous on first parse, and then finish when remaining
  ## information is supplied.
  ##
  ## Right now, that's not quite what happens.  If we find that
  ## there's a non-explicit command, we currently defer any decisions
  ## about the flags and arguments that we can't attach to a parent
  ## command.
  ##
  ## Specifically, we could (but do not):
  ##
  ## 1. Try to rule out possible commands based on arguments provided.
  ## 2. Try to rule out possible commands based on flags provided.
  ##
  ## The only check we *do* is to make sure that, for each flag not
  ## recognized by some parent section, we look to see if there is ANY
  ## valid possible command that would recognize the flag.  It could
  ## be the case that this check passes, but the unmatched flags could
  ## never be seen together in a legitimate command line.
  ##
  ## However, there *are* circumstances where this version will be
  ## able to fully parse and validate:
  ##
  ## 1. If implicit (default) commands are not allowed, up-front.
  ## 2. If the default command name is passed up-front, allowing us to
  ##    resolve it.
  ## 3. If the user only supplies explicit commands.
  ##
  ## Therefore, this function returns a tuple consisting of the
  ## partial result (which stashes the parse context and the remaining
  ## flags) and a boolean indicating that the parse is finalized (if
  ## it's finalized, there will not be ambiguous flags).
  ##
  ## Note that, if you use this version of the parser, you're then
  ## responsible for properly ensuring the parse is finished off.  You
  ## can call applyDefault() yourself, with the necessary
  ## information.
  ##
  ## Additionally, this version of the parser relies on you to call
  ## "commit" yourself, if you want to use the callback mechanism to
  ## set values. The default parser does that for you.
  var
    inargs = if len(passedArgs) != 0: @passedArgs else: commandLineParams()
    argRes = ArgResult(flags:         default(Table[string, FlagInfo]),
                       args:          @[],
                       subresult:     none(ArgResult),
                       command:       none(string),
                       noExplicitSub: topHasDefault,
                       linkedSpec:    ctx)
    args: seq[string] = @[]

  # This preamble ensures any spacing in --flag=x is treated uniformly.
  # The only way to get an empty string is with: --f= - (or --)
  for i, item in inargs:
    if len(item) == 0: continue
    if item[0] == '-':
      args.add(item)
    elif item[0] in ['=', ':']:
      if len(args[^1]) > 0 and args[^1][0] == '-':
        if '=' notin args[^1] and ':' notin args[^1]:
          args[^1] = args[^1] & item
          continue
      args.add(item)
    elif len(args) > 0 and len(args[^1]) > 0 and args[^1][^1] in [':', '=']:
      args[^1] = args[^1] & item
    else:
      args.add(item)

  argRes.origArgs = args

  var ctx = ParseCtx(args:           args,
                     curCmdSpec:     ctx,
                     curCmdResult:   argRes,
                     topCmdResult:   argRes,
                     clobberOk:      clobberOk,
                     unmatchedFlags: default(DeferredFlags))

  ctx.setCommandBoundaries(0)
  parseCurrentCommand(ctx)

  var `areWeDone?` = ctx.sanityCheckUnmatchedFlags()
  # So far, flag results went into the ArgSpecs, we need to get them
  # loaded into the actual results.
  var res = argRes

  while true:
    for k, v in res.linkedSpec.flags:
      if v.seen:
        res.flags[v.long] = v
    if res.subresult.isNone():
      break
    res = res.subresult.get()

  res.stash = ctx # Keep this around.

  return (argRes, `areWeDone?`)

proc commit*(result: ArgResult) =
  ## Goes through parse results and invokes any set callbacks.
  ## does this from the top down, first flags, then args, then
  ## finally the command callback.
  ##
  ## If there are subcommands, we then descend into the selected
  ## subcommand and start over.
  var cur = result

  while true:
    for flag, spec in cur.flags:
      case spec.kind
      of afBinary:
        if spec.binCallback != nil:
          spec.binCallback()
      of afPair:
        if spec.pairCallback != nil:
          if spec.positive:
            spec.pairCallback(true)
          else:
            spec.pairCallback(false)
      of afChoice:
        if spec.choiceCallback != nil:
          spec.choiceCallback(spec.chosen)
      of afStrArg:
        if spec.strCallback != nil:
          spec.strCallback(spec.value)
    if cur.linkedSpec.argCallback != nil:
      cur.linkedSpec.argCallback(cur.args)
    if cur.linkedSpec.cmdCallback != nil:
      cur.linkedSpec.cmdCallback(cur)
    if cur.subresult.isNone():
      break
    cur = cur.subresult.get()

proc applyDefault*(argRes: ArgResult, cmd: string) =
  ## This completes a parse, once a default command is supplied.
  var
    ctx          = argRes.stash
    ambiguousArg = ctx.topCmdResult

  while ambiguousArg.subresult.isSome():
    ambiguousArg = ambiguousArg.subresult.get()

  if cmd notin ambiguousArg.linkedSpec.commands:
    var possibleCmds: seq[string] = @[]
    for k, _ in ambiguousArg.linkedSpec.commands:
      possibleCmds.add(k)

    raise newException(ValueError, "Missing command.  Expected one of: " &
                       possibleCmds.join(", "))

  var
    flags  = ctx.unmatchedFlags
    slice  = argRes.origArgs[ambiguousArg.implicitStart .. ^1]
    spec   = ambiguousArg.linkedSpec.commands[cmd]
    newArg = ArgResult(command:    none(string),
                       subresult:  none(ArgResult),
                       flags:      default(Table[string, FlagInfo]),
                       args:       slice,
                       linkedSpec: spec)

  if len(slice) != 0:
    ambiguousArg.args = argRes.origArgs[0 ..< ambiguousArg.implicitStart]

  if len(slice) > spec.maxArgs:
    raise newException(ValueError, "Too many arguments for default command '" &
      cmd & "'")
  if len(slice) < spec.minArgs:
    raise newException(ValueError, "Too few arguments for default command '" &
      cmd & "'")

  ambiguousArg.command = some(cmd)

  for flag, `value?` in flags:
    if flag notin spec.flags:
      raise newException(ValueError, "Invalid flag for command '" & cmd &
        "': --" & flag)
    let fi = spec.flags[flag]
    if `value?`.isNone():
      ctx.setFlagValue(fi)
    else:
      let value = `value?`.get()
      ctx.setFlagValue(fi, value)
    newArg.flags[fi.long] = fi

  ambiguousArg.subresult = some(newArg)

proc parse*(ctx:             ArgSpec,
            inargs:          openarray[string] = [],
            topHasDefault = false,
            clobberOk     = false,
            defaultCmd    = ""): ArgResult =

    var (res, done) = ctx.mostlyParse(inargs, topHasDefault, clobberOk)

    result = res

    if done:
      return

    if defaultCmd != "":
      res.applyDefault(defaultCmd)
      return

    case len(res.stash.unmatchedFlags)
    of 0:
      discard
    of 1:
      for k, _ in res.stash.unmatchedFlags:
        raise newException(ValueError, "Invalid flag: " & k)
    else:
      var arr: seq[string] = @[]
      for k, _ in res.stash.unmatchedFlags:
        arr.add(k)
      raise newException(ValueError, "Invalid flags: " & arr.join(", "))

    # Else, we're missing a command / subcommand.
    while res.subresult.isSome():
      res = res.subresult.get()

    var possibleCmds: seq[string] = @[]
    for k, _ in res.linkedSpec.commands:
      possibleCmds.add(k)

    raise newException(ValueError, "Missing command.  Expected one of: " &
                                   possibleCmds.join(", "))

proc getBoolValue*(res: ArgResult, flagname: string): Option[bool] =
  if flagname notin res.flags:
    return none(bool)

  let fi = res.flags[flagname]

  case fi.kind
  of afBinary:
    return some(true)
  of afPair:
    if fi.positive:
      return some(true)
    return some(false)
  else:
    raise newException(ValueError, "Flag '" & flagname & "' is not a t/f value")

proc getStrValue*(res: ArgResult, flagname: string): Option[string] =
  if flagname notin res.flags:
    return none(string)

  let fi = res.flags[flagname]

  case fi.kind
  of afChoice:
    return some(fi.chosen)
  of afStrArg:
    return some(fi.value)
  else:
    raise newException(ValueError, "Flag '" & flagname &
      "' doesn't take a string argument.")

proc getCurrentCommandName*(res: ArgResult): Option[string] =
  if res.command.isSome():
    return res.subresult.get().linkedSpec.commandName
  else:
    return none(string)

proc getArgs*(res: ArgResult): seq[string] =
  return res.args

proc getFlags*(res: ArgResult, recursive=true): TableRef[string, string] =
  result  = newTable[string, string]()
  var cur = res

  while true:
    for key, value in res.flags:
      case value.kind
      of afBinary, afPair:
        result[key] = ""
      of afChoice:
        result[key] = value.chosen
      of afStrArg:
        result[key] = value.value
    if not recursive: return
    if cur.subresult.isNone(): return
    cur = cur.subresult.get()

proc getSubcommand*(res: ArgResult): Option[ArgResult] =
  return res.subresult

when isMainModule:
  proc setColor(s: bool) =
    echo "Set color = ", s

  proc setDryRun(s: bool) =
    echo "Set dry run = ", s

  proc setPublishDefaults(s: bool) =
    echo "Set publish defaults = ", s

  proc gotHelpFlag() =
    echo "help!"

  proc setLogLevel(s: string) =
    echo "Set log level = ", s

  proc setConfigFile(s: string) =
    echo "Set Config file = ", s

  proc setRecursive(s: bool) =
    echo "Set recursive = ", s

  proc addArtPath(s: seq[string]) =
    echo "Add artifact path: ", s

  proc setArgv(s: seq[string]) =
    echo "Set argv = ", s

  proc cmdInsert(s: ArgResult) =
    echo "run insert"

  proc cmdExtract(s: ArgResult) =
    echo "run extract"

  proc cmdDelete(s: ArgResult) =
    echo "run delete"

  proc cmdDefaults(s: ArgResult) =
    echo "run defaults"

  proc cmdDump(s: ArgResult) =
    echo "run dump"

  proc cmdLoad(s: ArgResult) =
    echo "run load"

  proc cmdVersion(s: ArgResult) =
    echo "run version"

  proc cmdHelp(s: ArgResult) =
    echo "run help!"

  var top = newArgSpec(defaultCmd = true).
            addPairedFlag('c', 'C', "color", setColor).
            addPairedFlag('d', 'D', "dry-run", setDryRun).
            addPairedFlag('p', 'P', "publish-defaults", setPublishDefaults).
            addBinaryFlag('h', "help", gotHelpFlag).
            addChoiceFlag('l', "log-level", @["verbose", "trace", "info",
                                              "warn", "error", "none"],
                          true,
                          setlogLevel).
            addFlagWithStrArg('f', "config-file", setConfigFile)
  top.addCommand("insert", ["inject", "ins", "in", "i"], cmdInsert).
            addArgs(callback = addArtPath).
            addPairedFlag('r', 'R', "recursive", setRecursive)
  top.addCommand("extract", ["ex", "e"], cmdExtract).
            addArgs(callback = addArtPath).
            addPairedFlag('r', 'R', "recursive", setRecursive)
  top.addCommand("delete", ["del"], cmdDelete).
            addArgs(callback = addArtPath).
            addPairedFlag('r', 'R', "recursive", setRecursive)
  top.addCommand("defaults", ["def"], cmdDefaults)
  top.addCommand("confdump", ["dump"], cmdDump).
            addArgs(min = 1, callback = setArgv)
  top.addCommand("confload", ["load"], cmdLoad).
            addArgs(min = 1, max = 1, callback = setArgv)
  top.addCommand("version", ["vers", "v"], cmdVersion)
  top.addCommand("help", ["h"], cmdHelp).
            addArgs(min = 0, max = 1, callback = setArgv)

  let
    x = top.parse(@["--no-color", "--log-level", "=", "info", "extract",
                    "--recursive", "--config-file=foo",
                    "--no-publish-defaults", "foo"])

  x.commit()
