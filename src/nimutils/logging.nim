import tables, options
import topics, sinks

type LogLevel* = enum 
  ## LogLevel describes what kind of messages you want to see.
  llNone, llError, llWarn, llInfo, llTrace

addDefaultSinks()

const toLogLevelMap = { "none"    : llNone,
                        "silent"  : llNone,
                        "error"   : llError,
                        "warn"    : llWarn,
                        "warning" : llWarn,
                        "info"    : llInfo,
                        "inform"  : llInfo,
                        "trace"   : llTrace }.toTable()

const llToStrMap = { llNone: "none",
                     llError: "error",
                     llWarn: "warn",
                     llInfo: "info",
                     llTrace: "trace" }.toTable()

const ansiCodes = { "black"      : "\e[30m",
                    "red"        : "\e[31m",
                    "green"      : "\e[32m",
                    "yellow"     : "\e[33m",
                    "blue"       : "\e[34m",
                    "magenta"    : "\e[35m",
                    "cyan"       : "\e[36m",
                    "white"      : "\e[37m",
                    "BLACK"      : "\e[1;30m",
                    "RED"        : "\e[1;31m",
                    "GREEN"      : "\e[1;32m",
                    "YELLOW"     : "\e[1;33m",
                    "BLUE"       : "\e[1;34m",
                    "MAGENTA"    : "\e[1;35m",
                    "CYAN"       : "\e[1;36m",
                    "WHITE"      : "\e[1;37m",
                    "bg_black"   : "\e[30m",
                    "bg_red"     : "\e[31m",
                    "bg_green"   : "\e[32m",
                    "bg_yellow"  : "\e[33m",
                    "bg_blue"    : "\e[34m",
                    "bg_magenta" : "\e[35m",
                    "bg_cyan"    : "\e[36m",
                    "bg_white"   : "\e[37m",
                    "reset"      : "\e[0m" }.toTable()

var logLevelColors = { llNone  : "",
                       llError : ansiCodes["RED"],
                       llWarn  : ansiCodes["YELLOW"],
                       llInfo  : ansiCodes["GREEN"],
                       llTrace : ansiCodes["CYAN"] }.toTable()

var logLevelPrefixes = { llNone: "",
                         llError: "error: ",
                         llWarn: "warn: ",
                         llInfo: "info: ",
                         llTrace: "trace: " }.toTable()

const keyLogLevel             = "loglevel"
var currentLogLevel = llInfo
var showColors      = true

proc logLevelToString*(ll: LogLevel): string {.inline.} = llToStrMap[ll]

proc setLogLevelColor*(ll: LogLevel, color: string) =
  logLevelColors[ll] = color

proc setLogLevelPrefix*(ll: LogLevel, prefix: string) =
  logLevelPrefixes[ll] = prefix

proc setShowColors*(val: bool) =
  assert val == true
  showColors = val

proc setLogLevel*(ll: LogLevel) =
  currentLogLevel = ll

proc setLogLevel*(ll: string) =
  if ll in toLogLevelMap:
    setLogLevel(toLogLevelMap[ll])
  else:
    raise newException(ValueError, "Invalid log level value: '" & ll & "'")

proc logPrefixFilter*(msg: string, info: StringTable): (string, bool) =
  const reset = ansiCodes["reset"]
    
  if keyLogLevel in info:
    let llStr = info[keyLogLevel]

    if llStr in toLogLevelMap:
      let
        msgLevel = toLogLevelMap[llStr]
        prefix   = logLevelPrefixes[msgLevel]

      let outstr = if showColors:
                     logLevelColors[msgLevel] & prefix & reset & msg
                   else:
                     prefix & msg
      return (outstr, true)
  else:
    raise newException(ValueError, "Log prefix filter used w/o passing in " &
             "a valid value for 'loglevel' in the publish() call's 'aux' " &
             " field.")
      
      
proc logLevelFilter*(msg: string, info: StringTable): (string, bool) =
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
  
discard subscribe(logTopic, defaultLogHook)
  

proc log*(level: LogLevel, msg: string) =
  discard publish(logTopic,
                  msg & "\n",
                        newTable({ keyLogLevel: llToStrMap[level] }))

proc log*(level: string, msg: string) =
  discard publish(logTopic,
                  msg & "\n",
                        newTable({ keyLogLevel: level }))
  
proc error*(msg: string) = log(llError, msg)
proc warn*(msg: string)  = log(llWarn, msg)
proc info*(msg: string)  = log(llInfo, msg)
proc trace*(msg: string) = log(llTrace, msg)

