import tables, options, streams, topics, sinks, ansi

type LogLevel* = enum
  ## LogLevel describes what kind of messages you want to see.
  llNone, llError, llWarn, llInfo, llTrace

addDefaultSinks()

const toLogLevelMap* = { "none"    : llNone,
                         "silent"  : llNone,
                         "error"   : llError,
                         "warn"    : llWarn,
                         "warning" : llWarn,
                         "info"    : llInfo,
                         "inform"  : llInfo,
                         "verbose" : llTrace,
                         "trace"   : llTrace }.toTable()

const llToStrMap = { llNone: "none",
                     llError: "error",
                     llWarn: "warn",
                     llInfo: "info",
                     llTrace: "trace" }.toTable()

var logLevelColors = { llNone  : "",
                       llError : toAnsiCode(@[acBRed]),
                       llWarn  : toAnsiCode(@[acBYellow]),
                       llInfo  : toAnsiCode(@[acBGreen]),
                       llTrace : toAnsiCode(@[acBCyan]), }.toTable()

var logLevelPrefixes = { llNone:  "",
                         llError: "error: ",
                         llWarn: "warn: ",
                         llInfo: "info: ",
                         llTrace: "trace: " }.toTable()

const keyLogLevel*  = "loglevel"
var currentLogLevel = llInfo

proc `$`*(ll: LogLevel): string = llToStrMap[ll]

proc setLogLevelColor*(ll: LogLevel, color: string) =
  logLevelColors[ll] = color

proc setLogLevelPrefix*(ll: LogLevel, prefix: string) =
  logLevelPrefixes[ll] = prefix

proc setLogLevel*(ll: LogLevel) =
  currentLogLevel = ll

proc setLogLevel*(ll: string) =
  if ll in toLogLevelMap:
    setLogLevel(toLogLevelMap[ll])
  else:
    raise newException(ValueError, "Invalid log level value: '" & ll & "'")

proc getLogLevel*(): LogLevel = currentLogLevel

proc logPrefixFilter*(msg: string, info: StringTable): (string, bool) =
  const reset = toAnsiCode(@[acReset])

  if keyLogLevel in info:
    let llStr = info[keyLogLevel]

    if llStr in toLogLevelMap:
      let
        msgLevel = toLogLevelMap[llStr]
        prefix   = logLevelPrefixes[msgLevel]

      let outstr = if getShowColors():
                     logLevelColors[msgLevel] & prefix & reset & msg
                   else:
                     prefix & msg
      return (outstr, true)
  else:
    raise newException(ValueError, "Log prefix filter used w/o passing in " &
             "a valid value for 'loglevel' in the publish() call's 'aux' " &
             " field.")

var suspendLogging = false

proc toggleLoggingEnabled*() =
  suspendLogging = not suspendLogging

template getSuspendLogging*(): bool = suspendLogging
    
proc logLevelFilter*(msg: string, info: StringTable): (string, bool) =
  if suspendLogging: return ("", false)
  
  if keyLogLevel in info:
    let llStr = info[keyLogLevel]

    if llStr in toLogLevelMap:
      let msgLevel = toLogLevelMap[llStr]
      if msgLevel > currentLogLevel:
        return ("", false) # Log level says, don't print!
      else:
        return (msg, true)
  else:
    raise newException(ValueError, "Log Level Filter used w/o passing in " &
             "a valid value for 'loglevel' in the publish() call's 'aux' " &
             " field.")

let
  logTopic        = registerTopic("logs")
  `cfg?`          = configSink(getSink("stderr").get(),
                               filters = @[MsgFilter(logLevelFilter),
                                           MsgFilter(logPrefixFilter)])
  defaultLogHook* = `cfg?`.get()

subscribe(logTopic, defaultLogHook)


proc log*(level: LogLevel, msg: string) =
  discard publish(logTopic,
                  msg & "\n",
                        newOrderedTable({ keyLogLevel: llToStrMap[level] }))

proc log*(level: string, msg: string) =
  discard publish(logTopic,
                  msg & "\n",
                        newOrderedTable({ keyLogLevel: level }))

proc error*(msg: string) = log(llError, msg)
proc warn*(msg: string)  = log(llWarn, msg)
proc info*(msg: string)  = log(llInfo, msg)
proc trace*(msg: string) = log(llTrace, msg)

when not defined(release):
  let
    debugTopic        = registerTopic("debug")
    `debugHook?`      = configSink(getSink("stderr").get())
    defaultDebugHook* = `debugHook?`.get()

  proc debug*(msg: string) =
    discard publish(debugTopic, msg)
