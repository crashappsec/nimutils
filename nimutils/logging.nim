## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import tables, options, streams, pubsub, sinks, rope_construct, rope_ansirender,
       strutils

type LogLevel* = enum
  ## LogLevel describes what kind of messages you want to see.
  llNone, llError, llWarn, llInfo, llTrace

addDefaultSinks()

const
  toLogLevelMap* = { "none"    : llNone,
                     "silent"  : llNone,
                     "error"   : llError,
                     "warn"    : llWarn,
                     "warning" : llWarn,
                     "info"    : llInfo,
                     "inform"  : llInfo,
                     "verbose" : llTrace,
                     "trace"   : llTrace }.toTable()

  llToStrMap = { llNone:  "none",
                 llError: "error",
                 llWarn:  "warn",
                 llInfo:  "info",
                 llTrace: "trace" }.toTable()

  pre        = "<bg-default>"
  post       = "</bg-default>"
  errPrefix  = pre & "<red>error: </red>" & post
  warnPrefix = pre & "<yellow>warn:  </yellow>" & post
  infoPrefix = pre & "<atomiclime>info:  </atomiclime>" & post
  trPrefix   = pre & "<jazzberry>trace: </jazzberry>" & post


var logLevelPrefixes = {
  llNone:  "",
  llError: errPrefix,
  llWarn:  warnPrefix,
  llInfo:  infoPrefix,
  llTrace: trPrefix,
}.toTable()

const keyLogLevel*  = "loglevel"
var currentLogLevel = llInfo

proc `$`*(ll: LogLevel): string = llToStrMap[ll]

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
  if keyLogLevel in info:
    let llStr = info[keyLogLevel]

    if llStr in toLogLevelMap:
      let
        msgLevel = toLogLevelMap[llStr]
        prefix   = logLevelPrefixes[msgLevel].stylizeHtml(ensureNl = false)

      return (prefix & msg, true)
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
  `cfg?`          = configSink(getSinkImplementation("stderr").get(),
                               "default-log-config",
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
    `debugHook?`      = configSink(getSinkImplementation("stderr").get(),
                                   "default-debug-config")
    defaultDebugHook* = `debugHook?`.get()

  proc debug*(msg: string) =
    discard publish(debugTopic, msg)
