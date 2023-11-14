## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import tables, options, pubsub, sinks, rope_base,rope_ansirender, rope_styles

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

var logLevelPrefixes = {
  llNone:  "",
  llError: $(defaultBg(fgColor("error: ", "red"))),
  llWarn:  $(defaultBg(fgColor("warn:  ", "yellow"))),
  llInfo:  $(defaultBg(fgColor("info:  ", "atomiclime"))),
  llTrace: $(defaultBg(fgColor("trace: ", "jazzberry")))
}.toTable()

const keyLogLevel*  = "loglevel"
var currentLogLevel = llInfo

proc `$`*(ll: LogLevel): string = llToStrMap[ll]

proc setLogLevelPrefix*(ll: LogLevel, prefix: string) =
  ## Set the prefix used for messages of a given log level.
  logLevelPrefixes[ll] = prefix

proc setLogLevel*(ll: LogLevel) =
  ## Sets the current log level using values from the enum `LogLevel`
  currentLogLevel = ll

proc setLogLevel*(ll: string) =
  ## Sets the current log level using the english string.
  if ll in toLogLevelMap:
    setLogLevel(toLogLevelMap[ll])
  else:
    raise newException(ValueError, "Invalid log level value: '" & ll & "'")

proc getLogLevel*(): LogLevel =
  ## Returns the current log level.
  currentLogLevel

proc logPrefixFilter*(msg: string, info: StringTable): (string, bool) =
  ## A filter, installed by default, that adds a logging prefix to
  ## the beginning of the message.
  if keyLogLevel in info:
    let llStr = info[keyLogLevel]

    if llStr in toLogLevelMap:
      let
        msgLevel = toLogLevelMap[llStr]

      return (logLevelPrefixes[msgLevel] & msg, true)
  else:
    raise newException(ValueError, "Log prefix filter used w/o passing in " &
             "a valid value for 'loglevel' in the publish() call's 'aux' " &
             " field.")

var suspendLogging = false

proc toggleLoggingEnabled*() =
  ## When logging is suspended, any published messages will be dropped when
  ## filtering by log level.
  suspendLogging = not suspendLogging

template getSuspendLogging*(): bool = suspendLogging

proc logLevelFilter*(msg: string, info: StringTable): (string, bool) =
  ## Filters out messages that are not important enough, per the currently
  ## set log level.
  ##
  ## If toggleLoggingEnabled() has been called an odd number of times,
  ## this filter will drop everything.
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
  ## Generic interface for publishing messages at a given log level.
  discard publish(logTopic,
                  msg & "\n",
                        newOrderedTable({ keyLogLevel: llToStrMap[level] }))

proc log*(level: string, msg: string) =
  ## Generic interface for publishing messages at a given log level.
  discard publish(logTopic,
                  msg & "\n",
                        newOrderedTable({ keyLogLevel: level }))

template log*(level: LogLevel, msg: Rope) = log(level, $(msg))
template log*(level: string, msg: Rope) = log(level, $(msg))
template error*(msg: string) = log(llError, msg)
template warn*(msg: string)  = log(llWarn, msg)
template info*(msg: string)  = log(llInfo, msg)
template trace*(msg: string) = log(llTrace, msg)
template error*(msg: Rope)   = log(llError, $(msg))
template warn*(msg: Rope)    = log(llWarn, $(msg))
template info*(msg: Rope)    = log(llInfo, $(msg))
template trace*(msg: Rope)   = log(llTrace, $(msg))

when not defined(release):
  let
    debugTopic        = registerTopic("debug")
    `debugHook?`      = configSink(getSinkImplementation("stderr").get(),
                                   "default-debug-config")
    defaultDebugHook* = `debugHook?`.get()

  proc debug*(msg: string) =
    discard publish(debugTopic, msg)
