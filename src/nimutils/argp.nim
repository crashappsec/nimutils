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
##    some flexibility on messing up, e.g., on where they put flags,
##    whether they use one or two dashes for flags, whether flag
##    arguments use --foo=bar, --foo:bar or --foo bar (or --foo:bar,
##    --foo : bar or --foo :bar).
##
## 4) Allow me to have a 'default' command, if no command is provided.
##
## I'm only implementing what we need so far.  No int arguments, no
## count arguments, no multiple flags, etc.  I also skip stuff I
## do not like.  Specifically:
##
##   - Optional flag values (too unintuitive for me as a user)
##
## You can do things such as have commands that supress all flag
## checking (passing them through the command as arguments), or allow
## for unrecognized flags.
##
## To construct an argument parsing context, start with
## newCmdLineSpec(), then add commands, flags and arg specs.
##
## Then, in most cases, you will want to call parse().
##
## To access the results of the parse, you have three options:
##
## 1) You can use API calls to access (the calls starting with get)
## 2) You can use the callbacks you supply when setting up the spec
## 3) You can query the ArgResult data structure directly.

import unicode, options, sugar, tables, os, misc, sequtils
import strutils except strip

const errNoArg = "Expected a command but didn't find one"

type
  ArgFlagKind*    = enum afBinary, afPair, afChoice, afStrArg
  BinaryCallback* = ()            -> void
  PairCallback*   = (bool)        -> void
  StrCallback*    = (string)      -> void
  StrArrCallback* = (seq[string]) -> void
  CmdCallback*    = (ArgResult)   -> void
  DeferredFlags*  = Table[string, Option[string]]
  FlagSpec* = ref object
    properName:       string
    clobberOk:        bool
    allNames:         seq[string]
    case kind:        ArgFlagKind
    of afBinary:
      linkedChoice:   Option[FlagSpec]
      binCallback:    BinaryCallback
    of afPair:
      positive:       bool
      pairedFlag:     FlagSpec
      pairCallback:   PairCallback
    of afChoice:
      choices:        seq[string]
      choiceCallback: StrCallback
    of afStrArg:
      strCallback:    StrCallback
  CommandSpec* = ref object
    commands:          Table[string, CommandSpec]
    properName:        string
    allNames:          seq[string]
    flags:             Table[string, FlagSpec]
    minArgs:           int
    maxArgs:           int
    subOptional:       bool
    unknownFlagsOk:    bool
    noFlags:           bool
    argCallback:       StrArrCallback
    cmdCallback:       CmdCallback
    parent:            Option[CommandSpec]
    allPossibleFlags:  Table[string, FlagSpec]
    finishedComputing: bool
  ArgResult* = ref object
    command*:    string
    args*:       Table[string, seq[string]]
    flags*:      Table[string, string]
    parseCtx:    ParseCtx
  ParseCtx = ref object
    args:     seq[string]
    curArgs:  seq[string]
    res:      ArgResult
    i:        int
    flagCbs:  seq[FlagSpec]
    finalCmd: CommandSpec

proc flagSpecEq(f1, f2: FlagSpec): bool =
  if f1 == f2:           return true   # They're literally the same ref
  if f1.kind != f2.kind: return false
  if f1.kind == afChoice:
    if len(f1.choices) != len(f2.choices): return false
    for item in f1.choices:
      if item notin f2.choices: return false
  return true

proc newSpecObj(properName: string          = "",
                allNames: openarray[string] = [],
                minArgs                     = 0,
                maxArgs                     = 0,
                subOptional                 = false,
                unknownFlagsOk              = false,
                noFlags                     = false,
                cmdCallback: CmdCallback    = nil,
                parent                      = none(CommandSpec)): CommandSpec =
  if noFlags and unknownFlagsOk:
    raise newException(ValueError, "Can't have noFlags and unknownFlagsOk")
  return CommandSpec(properName:     properName,
                     allNames:       allNames.toSeq(),
                     minArgs:        minArgs,
                     maxArgs:        maxArgs,
                     subOptional:    subOptional,
                     unknownFlagsOk: unknownFlagsOk,
                     noFlags:        noFlags,
                     argCallback:    nil,
                     cmdCallback:    cmdCallback,
                     parent:         parent)

proc newCmdLineSpec*(callback: CmdCallback = nil): CommandSpec =
  ## Creates a top-level argument parsing specification instance.
  result = newSpecObj(cmdCallback = callback)

proc addCommand*(spec:           CommandSpec,
                 name:           string,
                 aliases:        openarray[string] = [],
                 subOptional:    bool              = false,
                 unknownFlagsOk: bool              = false,
                 noFlags:        bool              = false,
                 callback:       CmdCallback       = nil):
                   CommandSpec {.discardable.} =
  ## Creates a command under the top-level argument parsing spec,
  ## or a sub-command under some other command.
  ## The `name` field is the 'official' name of the command, which
  ## will be used in referencing the command programatically, and
  ## when producing error messages.
  ##
  ## The values in `aliases` can be used at the command line in
  ##
  ## place of the official name.
  ##
  ## If there are sub-commands, then the `subOptional` flag indicates
  ## whether it's okay for the sub-command to not be provided.
  ##
  ## If `unknownFlagsOk` is provided, then you can still add flags
  ## for that section, but if the user does provide flags that wouldn't
  ## be valid in any section, then they will still be accepted.  In
  ## this mode, unknown flags are put into the command arguments.
  ##
  ## If `noFlags` is provided, then the rest of the input will be
  ## treated as arguments, even if they start with dashes.  If this
  ## flag is set, unknownFlagsOk cannot be set, and there may not
  ## be further sub-commands.
  ##
  ## The `callback`, if provided, will get called when `parse()`
  ## finishes.
  ##
  ## Note that, when using `ambiguousParse()`, if the parse is
  ## actually ambigous (i.e., multiple defaults might be accepted),
  ## then no callbacks run; you must call `runCallbacks()` explicitly
  ## once you select which option to accept.
  ##
  ## Note that, if you have sub-commands that are semantically the
  ## same, you still should NOT re-use objects. The algorithm for
  ## validating flags assumes that each command object to be unique,
  ## and you could definitely end up accepting invalid flags.
  result = newSpecObj(properName     = name,
                      allNames       = aliases,
                      subOptional    = subOptional,
                      unknownFlagsOk = unknownFlagsOk,
                      noFlags        = noFlags,
                      cmdCallback    = callback,
                      parent         = some(spec))

  if name notin result.allNames: result.allNames.add(name)
  for oneName in result.allNames:
    if oneName in spec.commands:
      raise newException(ValueError, "Duplicate command: " & name)
    spec.commands[oneName] = result

proc addArgs*(cmd:      CommandSpec,
              min:      int = 0,
              max:      int = high(int),
              callback: StrArrCallback = nil): CommandSpec {.discardable.} =
  ## Adds an argument specification to a CommandSpec.  Without adding
  ## it, arguments won't be allowed, only flags.  If a callback is
  ## provided, when the command is definitively matched, the callback
  ## will get run with any arguments passed to that command.
  ##
  ## This returns the command spec object passed in, so that you can
  ## chain multiple calls to addArgs / flag add calls.

  result = cmd
  if min < 0 or max < 0 or min > max:
    raise newException(ValueError, "Invalid arguments")

  cmd.minArgs     = min
  cmd.maxArgs     = max
  cmd.argCallback = callback

proc aliasFlag(cmd: CommandSpec, flag: FlagSpec, aliases: openarray[string]) =
  for item in aliases:
    # Be tolerant if the same name is given twice for the same flag.
    if item in flag.allNames: continue
    flag.allNames.add(item)
    if item in cmd.flags:
      raise newException(ValueError, "Duplicate flag: --" & item)
    cmd.flags[item] = flag

proc newFlag(cmd:     CommandSpec,
             kind:    ArgFlagKind,
             name:    string,
             clOk:    bool,
             aliases: openarray[string]): FlagSpec =
  if cmd.noFlags:
    raise newException(ValueError,
                       "Cannot add a flag for a spec where noFlags is true")
  result = FlagSpec(properName: name, kind: kind, clobberOk: clOk)
  cmd.flags[name] = result
  cmd.aliasFlag(result, aliases)

proc addBinaryFlag*(cmd:       CommandSpec,
                    name:      string,
                    aliases:   openarray[string] = [],
                    callback:  BinaryCallback   = nil,
                    clobberOk: bool             = false):
                      CommandSpec {.discardable.} =
  ## Adds a flag to `cmd` that represents a true/false value, true if
  ## the flag is provided, or false if it is not.
  ##
  ## The `name` field will be the proper name for the flag, and will
  ## be a value usable at the command like: --flag-name
  ##
  ## The `aliases` field will allow alternative names.
  ##
  ## If provided, the `callback` will be called if a single parse is
  ## accepted.
  ##
  ## If `clobberOk` is true, then the system will allow flags to
  ## appear multiple times, including conflicting flags. It will
  ## accept the last instance seen.

  result = cmd

  let flag          = newFlag(cmd, afBinary, name, clobberOk, aliases)
  flag.linkedChoice = none(FlagSpec)
  flag.binCallback  = callback

proc addYesNoFlag*(cmd:       CommandSpec,
                   name:      string,
                   singleYes: Option[char]      = none(char),
                   singleNo:  Option[char]      = none(char),
                   callback:  PairCallback      = nil,
                   aliases:   openarray[string] = [],
                   clobberOk: bool              = false):
                     CommandSpec {.discardable.} =
  ## This creates a linked pair of flags for a command (`cmd`) that
  ## create a single boolean.  The `name` field will be the name of
  ## the 'true' flag, and 'no-' will be automatically appended for the
  ## 'false' value of the flag.
  ##
  ## Any `aliases` added also get a 'no-' version.  But you can add
  ## single-value aliases for true and false by passing them to
  ## `singleYes` and/or `singleNo`.  Currently, unicode code points
  ## that require multi-byte UTF-8 encoding are not accepted as
  ## single-character values.
  ##
  ## Callback and clobber works the same way as for `addBinaryFlag()`.
  result = cmd

  var
    yesFlag   = newFlag(cmd, afPair, name, clobberOk, aliases)
    noAliases = seq[string](@[])

  for item in aliases: noAliases.add("no-" & item)
  var noFlag  = newFlag(cmd, afPair, "no-" & name, clobberOk, noAliases)
  yesFlag.positive     = true
  noFlag.positive      = false
  yesFlag.pairedFlag   = noFlag
  noFlag.pairedFlag    = yesFlag
  yesFlag.pairCallback = callback

  if singleYes.isSome(): cmd.aliasFlag(yesFlag, [$(singleYes.get())])
  if singleNo.isSome():  cmd.aliasFlag(noFlag,  [$(singleNo.get())])

proc addChoiceFlag*(cmd:           CommandSpec,
                    name:          string,
                    choices:       openarray[string],
                    flagPerChoice: bool              = false,
                    aliases:       openarray[string] = [],
                    callback:      StrCallback       = nil,
                    clobberOk:     bool              = false):
                      CommandSpec {.discardable.} =
  ## This creates a flag for `cmd` that requires a string argument if
  ## provided, but the string argument must be from a fixed set of
  ## choices, as specified in the `choices` field.
  ##
  ## If `flagPerChoice` is provided, then we add a yes/no flag for
  ## each choice, which, on the command-line, acts as a 'boolean'.
  ## But, the value will be reflected in this field, instead.
  ##
  ## For instance, if you add a '--log-level' choice flag with values
  ## of ['info', 'warn', 'error'], then these two things would be
  ## equal:
  ##
  ## --log-level= warn
  ##
  ## --warn
  ##
  ## And you would still check the value after parsing via the name
  ## 'log-level'.
  ##
  ## The `name`, `aliases`, `callback` and `clobberOk` fields work
  ## as with other flag types.

  result              = cmd
  var flag            = newFlag(cmd, afChoice, name, clobberOk, aliases)
  flag.choices        = choices.toSeq()
  flag.choiceCallback = callback
  if flagPerChoice:
    for item in choices:
      var oneFlag = newFlag(cmd, afBinary, item, clobberOk, @[])
      oneFlag.linkedChoice = some(flag)

proc addFlagWithArg*(cmd:       CommandSpec,
                     name:      string,
                     aliases:   openarray[string] = [],
                     callback:  StrCallback       = nil,
                     clobberOk: bool              = false):
                       CommandSpec {.discardable.} =
  ## This simply adds a flag that takes a required string argument.
  ## The arguments are identical in semantics as for other flag types.

  result           = cmd
  let flag         = newFlag(cmd, afStrArg, name, clobberOk, aliases)
  flag.strCallback = callback

template argpError(msg: string) =
  var fullError = msg

  if ctx.res.command != "":
    fullError = "When parsing command '" & ctx.res.command & "': " & msg

  raise newException(ValueError, fullError)

proc validateOneFlag(ctx:     var ParseCtx,
                     name:    string,
                     inspec:  FlagSpec,
                     foundArg = none(string)) =
  var
    argCrap = foundArg
    spec    = inspec

  if ctx.i < len(ctx.args) and ctx.args[ctx.i][0] in [':', '=']:
    if argCrap.isNone():
      argCrap = some(ctx.args[ctx.i][1 .. ^1].strip())
      ctx.i = ctx.i + 1
      if argCrap.get() == "":
        if ctx.i < len(ctx.args):
          argCrap = some(ctx.args[ctx.i])
          ctx.i = ctx.i + 1
        else:
          argpError("Flag '--" & name & "' requires an argument.")

  if spec.kind in [afBinary, afPair]:
    if argCrap.isSome():
      argpError("Flag '--" & name & "' takes no argument.")
    if spec.kind == afBinary and spec.linkedChoice.isSome():
      spec    = spec.linkedChoice.get()
      argCrap = some(name)
  elif argCrap.isNone():
    if ctx.i == len(ctx.args) or ctx.args[ctx.i][0] == '-':
      argpError("Flag '--" & name & "' requires an argument.")
    argCrap = some(ctx.args[ctx.i].strip())
    ctx.i  = ctx.i + 1

  if not spec.clobberOk and spec.properName in ctx.res.flags:
    argpError("Redundant flag specification for '--" & name & "' not allowed")

  case spec.kind
  of afBinary:
    ctx.res.flags[spec.properName] = ""
    if spec notin ctx.flagCbs: ctx.flagCbs.add(spec)
  of afPair:
    if spec.pairedFlag.properName in ctx.res.flags:
      if not spec.clobberOk:
        argpError("Cannot provide '--" & name &
                  "' when its opposite has been previously provided.")
      ctx.res.flags.del(spec.pairedFlag.properName)
    ctx.res.flags[spec.properName] = ""
    if not spec.positive: spec = spec.pairedFlag
    if spec notin ctx.flagCbs: ctx.flagCbs.add(spec)
  of afChoice:
    let arg = argCrap.get()
    if arg notin spec.choices:
      argpError("Invalid choice for flag '--" & name & "': '" & arg & "'")
    ctx.res.flags[spec.properName] = arg
    if spec notin ctx.flagCbs: ctx.flagCbs.add(spec)
  of afStrArg:
    ctx.res.flags[spec.properName] = argCrap.get()
    if spec notin ctx.flagCbs: ctx.flagCbs.add(spec)

proc parseOneFlag(ctx: var ParseCtx, spec: CommandSpec) =
  var
    orig        = ctx.args[ctx.i]
    cur         = orig[1 .. ^1]
    singleDash  = true
    definiteArg = none(string)

  ctx.i = ctx.i + 1

  if cur[0] == '-':
    cur        = cur[1 .. ^1]
    singleDash = false

  var
    colonix = cur.find(':')
    eqix    = cur.find('=')
    theIx   = colonix

  if theIx == -1:
    theIx = eqIx
  else:
    if eqIx != -1 and eqIx < theIx:
      theIx = eqIx
  if theIx != -1:
    let rest    = cur[theIx+1 .. ^1].strip()
    cur         = cur[0 ..< theIx].strip()

    if len(rest) != 0:
      definiteArg = some(rest)
    elif ctx.i != len(ctx.args):
      definiteArg = some(ctx.args[ctx.i])
      ctx.i = ctx.i + 1

  if cur in spec.allPossibleFlags:
    ctx.validateOneFlag(cur, spec.allPossibleFlags[cur], definiteArg)
  elif not singleDash:
    if spec.unknownFlagsOk:
      ctx.curArgs.add(orig)
      if ':' in orig or '=' in orig:
        ctx.i = ctx.i - 1
    else:
      argpError("Invalid flag: " & cur)
  else:
    # Single-dash flags bunched together cannot have arguments.
    if definiteArg.isSome():
      argpError("Invalid flag: " & cur)
    for i, c in cur:
      let oneCharFlag = $(c)
      if oneCharFlag in spec.allPossibleFlags:
        ctx.validateOneFlag(oneCharFlag, spec.allPossibleFlags[cur])
      elif  spec.unknownFlagsOk: continue
      elif i == 0: argpError("Invalid flag: " & cur)
      else:
        argpError("-" & cur & ": Couldn't process all characters as flags")
    if spec.unknownFlagsOk: ctx.curArgs.add(orig)

proc parseCmd(ctx: var ParseCtx, spec: CommandSpec) =
  # If we are here, we know we're parsing for the spec passed in; it matched.
  # We accept that arguments and flags might be intertwined. We basically
  # will scan till we hit the end or hit a valid command that isn't
  # part of a flag argument.
  #
  # Then, we validate the number of arguments against the spec, handle
  # recursing if there's a sub-command, and decide if we're allowed to
  # finish if we have no more arguments to parse.
  var lookingForFlags = if spec.noFlags: false
                        else:            true

  ctx.curArgs = @[]

  # Check that any flags we happened to accept in a parent context
  # are still valid now that we have more info about our subcommand
  for k, _ in ctx.res.flags:
    if k notin spec.allPossibleFlags:
      argpError("Flag '" & k & "' is invalid for this command")

  while ctx.i != len(ctx.args):
    let cur = ctx.args[ctx.i]
    # If len is 1, we pass it through, usually means 'use stdout'
    if lookingForFlags and cur[0] == '-' and len(cur) != 1:
      if cur == "--":
        lookingForFlags = false
        ctx.i           = ctx.i + 1
        continue
      ctx.parseOneFlag(spec)
      continue
    if cur in spec.commands:
      ctx.i = ctx.i + 1
      if len(ctx.curArgs) < spec.minArgs:
        argpError("Too few arguments (expected " & $(spec.minArgs) & ")")
      if len(ctx.curArgs) > spec.maxArgs:
        argpError("Too many arguments provided (max = " & $(spec.maxArgs) & ")")
      ctx.res.args[ctx.res.command] = ctx.curArgs
      let nextSpec = spec.commands[cur]
      if ctx.res.command != "":
        ctx.res.command &= "." & nextSpec.properName
      else:
        ctx.res.command = nextSpec.properName
      ctx.parseCmd(nextSpec)
      return

    ctx.curArgs.add(ctx.args[ctx.i])
    ctx.i = ctx.i + 1

  # If we exited the loop, we need to make sure the parse ended up in
  # a valid final state.
  if len(spec.commands) != 0 and not spec.subOptional:
    argpError(errNoArg)
  if len(ctx.curArgs) < spec.minArgs:
    argpError("Too few arguments (expected " & $(spec.minArgs) & ")")
  if len(ctx.curArgs) > spec.maxArgs:
    argpError("Too many arguments provided (max = " & $(spec.maxArgs) & ")")
  ctx.res.args[ctx.res.command] = ctx.curArgs
  ctx.finalCmd = spec

proc computePossibleFlags(spec: CommandSpec) =
  # Because we want to allow for flags for commands being passed to us
  # before we know whether they're valid (e.g., in a subcommand), we are
  # going to keep multiple flag states, one for each possible combo of
  # subcommands. To do this, we will flatten the tree of possible
  # subcommands, and then for each tree, we will compute all flags we
  # might see.
  #
  # The top of the tree will have all possible flags, but as we descend
  # we need to keep re-checking to see if we accepted flags that we
  # actually shouldn't have accepted.
  #
  # Note that we do not allow flag conflicts where the flag specs are
  # not FULLY compatible.  And, we do not allow subcommands to
  # re-define a flag that is defined already by a higher-level command.
  #
  # Note that, as we parse, we will accept flags we MIGHT smack down
  # later, depending on the command. We will validate what we've accepted
  # so far every time we enter a new subcommand.
  if spec.finishedComputing:
    return
  if spec.parent.isSome():
    let parentFlags = spec.parent.get().allPossibleFlags
    for k, v in parentFlags: spec.allPossibleFlags[k] = v
  for k, v in spec.flags:
    if k in spec.allPossibleFlags:
      raise newException(ValueError, "command flag names cannot " &
        "conflict with parent flag names or top-level flag names")
    spec.allPossibleFlags[k] = v

  var flagsToAdd: Table[string, FlagSpec]
  for _, kid in spec.commands:
    kid.computePossibleFlags()
    for k, v in kid.allPossibleFlags:
      if k in spec.allPossibleFlags: continue
      if k notin flagsToAdd:
        flagsToAdd[k] = v
        continue
      if not flagSpecEq(flagsToAdd[k], v):
        raise newException(ValueError, "Sub-commands with flags of the " &
          "same name must have identical specifications (flag name: " & k & ")")
  for k, v in flagsToAdd:
    spec.allPossibleFlags[k] = v
  spec.finishedComputing = true

proc parseOne(ctx: var ParseCtx, spec: CommandSpec) =
  ctx.i   = 0
  ctx.res = ArgResult(parseCtx: ctx)
  ctx.parseCmd(spec)

proc runCallbacks*(res: ArgResult) =
  ## This explicitly runs any callbacks you added on an ArgResult
  ## object.  This is intended to be used if you allow a default
  ## command, when the command line might be ambiguous when the
  ## top-level command is omitted.
  ##
  ## For instance, chalk allows the default command to be
  ## disambiguated via config file, but the config file doesn't get
  ## read until the command-line flags get parsed... since the
  ## config-file location gets passed in a top-level arg, the results
  ## will be the same in any valid parse.
  ##
  ## Once we read the default to fill in, then we can throw away the
  ## other parses, and run callbacks.
  var
    cur:     CommandSpec      = res.parseCtx.finalCmd
    cmdList: seq[CommandSpec] = @[cur]
    name:    string

  while cur.parent.isSome():
    cur     = cur.parent.get()
    cmdList = @[cur] & cmdList

  for i, item in cmdList:
    case i
    of 0: name = ""
    of 1: name = item.propername
    else: name &= "." & item.propername

    for k, v in item.allPossibleFlags:
      let ix = res.parseCtx.flagCbs.find(v)
      if ix != -1:
        res.parseCtx.flagCbs.del(ix)
        case v.kind
        of afBinary:
          if v.binCallback != nil and k in res.flags: v.binCallback()
        of afPair:
          if v.pairCallback != nil:
            if k in res.flags:
              v.pairCallback(true)
            elif ("no-" & k) in res.flags:
              v.pairCallback(false)
        of afChoice:
          if v.choiceCallback != nil and k in res.flags:
            v.choiceCallback(res.flags[k])
        of afStrArg:
          if v.strCallback != nil and k in res.flags:
            v.strCallback(res.flags[k])
    if item.argCallback != nil: item.argCallback(res.args[name])
    if item.cmdCallback != nil: item.cmdCallback(res)

proc ambiguousParse*(spec:          CommandSpec,
                     inargs:        openarray[string] = [],
                     defaultCmd:    Option[string]    = none(string),
                     runCallbacks:  bool              = true): seq[ArgResult] =
  ## This parse function accepts multiple parses, if a parse is
  ## ambiguous.
  ##
  ## First, it attempts to parse `inargs` as-is, based on the
  ## specification passed in `spec`.  If that fails because there was
  ## no command provided, what happens is based on the value of the
  ## `defaultCmd` field-- if it's none(string), then no further action
  ## is taken.  If there's a default command provided, it's re-parsed
  ## with that default command.
  ##
  ## However, you provide "" as the default command (i.e., some("")),
  ## then this will try all possible commands and return any that
  ## successfully parse.
  ##
  ## If there is only one and exactly one accepted parse, this will
  ## run callbacks automatically when provided, unless you set
  ## the `runCallbacks` command to false, at which point you can
  ## control when they run.
  ##
  ## If `inargs` is not provided, it is taken from the system-provided
  ## arguments.  In nim, this is commandLineParams(), but would be
  ## argv[1 .. ] elsewhere.

  if defaultCmd.isSome() and spec.subOptional:
    raise newException(ValueError,
             "Can't have a default command when commands aren't required")
  var
    validParses   = seq[ParseCtx](@[])
    firstError    = ""
    args          = if len(inargs) != 0: inargs.toSeq()
                    else:                commandLineParams()

  # First, try to see if no inferencing results in a full parse
  spec.computePossibleFlags()

  try:
    var ctx = ParseCtx(args: args)
    ctx.parseOne(spec)
    if runCallbacks: ctx.res.runCallbacks()
    return @[ctx.res]
  except ValueError:
    if getCurrentExceptionMsg() != errNoArg: raise
    if defaultCmd.isNone():                  raise
    # else, ignore.

  let default = defaultCmd.get()
  if default != "":
    try:    return spec.ambiguousParse(@[default] & args)
    except: firstError = getCurrentExceptionMsg()

  for cmd, ss in spec.commands:
    if ss.properName != cmd: continue
    var ctx = ParseCtx(args: @[cmd] & args)
    try:
      ctx.parseOne(spec)
      validParses.add(ctx)
    except:
      discard

  result = @[]
  for item in validParses: result.add(item.res)
  
  case len(result)
  of 0:  raise newException(ValueError, firstError)
  of 1:
    if runCallbacks: result[0].runCallbacks()
  else:  discard

proc parse*(spec:       CommandSpec,
            inargs:     openarray[string] = [],
            defaultCmd: Option[string]    = none(string)): ArgResult =
  ## This parses the command line specified via `inargs` as-is using
  ## the `spec` for validation, and if that parse fails because no
  ## command was provided, then tries a single default command, if it
  ## is provided.
  ##
  ## If `inargs` is not provided, it is taken from the system-provided
  ## arguments.  In nim, this is commandLineParams(), but would be
  ## argv[1 .. ] elsewhere.
  ##
  ## Any callbacks will be run before a successful return.
  ##
  ## The return value of type ArgResult can have its fields queried
  ## directly, or you can use getBoolValue(), getValue(), getCommand()
  ## and getArgs() to access the results.
  ##
  ## Note that these values can similarly be accessed via callbacks.

  let allParses = spec.ambiguousParse(inargs, defaultCmd)
  if len(allParses) != 1:
    raise newException(ValueError, "Ambiguous arguments: please provide an " &
                                   "explicit command name")
  result = allParses[0]

proc getBoolValue*(res: ArgResult, flagname: string): Option[bool] =
  ## Extracts a boolean value of the name specified in `flagname`
  ## from the parse result stored in `res`, if it was provided.
  ##
  ## The name used must be the same one given when specifying the
  ## flag.  It will return true or false in an Option if present, or
  ## the option will be empty if not.
  if flagName notin res.flags and "no-" & flagName notin res.flags:
    return none(bool)

  return if flagName in res.flags: some(true) else: some(false)

proc getValue*(res: ArgResult, flagname: string): Option[string] =
  ## Extracts a string value from the flag name specified in
  ## `flagname` from the parse result stored in `res`, if it was
  ## provided.
  ##
  ## The name used must be the same as the one given when specifying
  ## the flag.  The value is placed in an option, so the caller can
  ## know definitively when it is not provided.
  if flagname notin res.flags: return none(string)
  return some(res.flags[flagname])

proc getCommand*(res: ArgResult): string =
  ## Returns the full-path of matched commands. If there is no
  ## command matched, but the parse was successful, then the
  ## value will be the empty string.
  ##
  ## If there are sub-commands, they will be dot-separated.
  ##
  ## The dotted version is the correct one to use when calling
  ## getArgs() to retrieve arguments specific to sub-commands.

  return res.command

proc getArgs*(res: ArgResult, cmd: string): Option[seq[string]] =
  ## Returns the arguments associated with the provided command or
  ## sub-command.  To access the top-level args (any args before
  ## any command, or if no command is used), pass in the empty
  ## string for the command.
  ##
  ## If accessing a sub-command, use the fully-dotted path to it.  You
  ## can query the full path to the deepest sub-command with
  ## `getCommand()`, and then query one level at a time.  Or, use
  ## callbacks at each level.
  if cmd in res.args: return some(res.args[cmd])

when isMainModule:
  proc setColor(s: bool) =            echo "Set color = ", s
  proc setDryRun(s: bool) =           echo "Set dry run = ", s
  proc setPublishDefaults(s: bool) =  echo "Set publish defaults = ", s
  proc gotHelpFlag() =                echo "help!"
  proc setLogLevel(s: string) =       echo "Set log level = ", s
  proc setConfigFile(s: string) =     echo "Set Config file = ", s
  proc setRecursive(s: bool) =        echo "Set recursive = ", s
  proc addArtPath(s: seq[string]) =   echo "Add artifact path: ", s
  proc cmdTestCb(s: seq[string]) =    echo "Test args: ", s
  proc setArgv(s: seq[string]) =      echo "Set argv = ", s
  proc dockerCb(s: seq[string]) =     echo "Docker = ", s
  proc cmdInsert(s: ArgResult) =      echo "run insert"
  proc cmdExtract(s: ArgResult) =     echo "run extract"
  proc cmdDelete(s: ArgResult) =      echo "run delete"
  proc cmdDefaults(s: ArgResult) =    echo "run defaults"
  proc cmdDump(s: ArgResult) =        echo "run dump"
  proc cmdLoad(s: ArgResult) =        echo "run load"
  proc cmdVersion(s: ArgResult) =     echo "run version"
  proc cmdHelp(s: ArgResult) =        echo "run help!"
  proc cmdTest(s: ArgResult) =        echo "run test sub-command!"

  var top = newCmdLineSpec().
            addYesNoFlag("color", some('c'), some('C'), callback = setColor).
            addYesNoFlag("dry-run", some('d'), some('D'), callback = setDryRun).
            addYesNoFlag("publish-defaults", some('p'), some('P'),
                         setPublishDefaults).
            addBinaryFlag("help", ["h"], gotHelpFlag).
            addChoiceFlag("log-level",
                          ["verbose", "trace", "info", "warn", "error", "none"],
                          true,
                          ["l"],
                          setlogLevel).
            addFlagWithArg("config-file", ["f"], setConfigFile)
  top.addCommand("insert", ["inject", "ins", "in", "i"], callback = cmdInsert).
            addArgs(callback = addArtPath).
            addYesNoFlag("recursive", some('r'), some('R'),
                         callback = setRecursive)
  top.addCommand("extract", ["ex", "e"], callback = cmdExtract).
            addArgs(callback = addArtPath).
            addYesNoFlag("recursive", some('r'), some('R'),
                         callback = setRecursive).
           addCommand("test", ["testy"], callback = cmdTest).
                 addArgs(callback = cmdTestCb)

  top.addCommand("delete", ["del"], callback = cmdDelete, unknownFlagsOk = true).
            addArgs(callback = addArtPath).
            addYesNoFlag("recursive", some('r'), some('R'),
                         callback = setRecursive)
  top.addCommand("defaults", ["def"], callback = cmdDefaults)
  top.addCommand("confdump", ["dump"], callback = cmdDump).
            addArgs(min = 1, callback = setArgv)
  top.addCommand("confload", ["load"], callback = cmdLoad).
            addArgs(min = 1, max = 1, callback = setArgv)
  top.addCommand("version", ["vers", "v"], callback = cmdVersion)
  top.addCommand("docker", noFlags = true).addArgs(callback = dockerCb)
  top.addCommand("help", ["h"], callback = cmdHelp).
            addArgs(min = 0, max = 1, callback = setArgv)

  when false:
    let x = top.parse(@["ex", "--no-color", "--log-level", "=", "info",
                        "defaults", "--recursive", "--config-file=foo",
                        "--no-publish-defaults", "testy",
                        "these", "are", "my", "test", "args"],
                      defaultCmd = some("extract"))
  elif false:
    let x = top.parse(@["--no-color", "docker", "--log-level", "=", "info",
                        "defaults", "--recursive", "--config-file=foo",
                        "--no-publish-defaults", "testy",
                        "these", "are", "my", "test", "args"],
                      defaultCmd = some("extract"))
  else:
    let x = top.parse(@["--no-color", "delete", "--log-level", "=", "info",
                        "defaults", "--recursive", "--unknown-flag=", "foo",
                        "--no-publish-defaults", "testy",
                        "these", "are", "my", "test", "args"],
                      defaultCmd = some("extract"))

  echo "cmd = ", x.getCommand()
  echo "args = ", x.getArgs(x.getCommand())
  echo x.getBoolValue("color")
  echo x.getValue("log-level")
  echo x.getBoolValue("recursive")
  echo x.getBoolValue("publish-defaults")
  echo x.getValue("config-file")
  echo x.getArgs("delete")
