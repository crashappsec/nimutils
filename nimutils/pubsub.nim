## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

## For now, not intended to be threadsafe for mutation ops.

import tables, sugar, options, json, strutils, strutils, std/terminal,
       unicodeid, rope_ansirender, rope_construct

type
  InitCallback*   = ((SinkConfig) -> bool)
  OutputCallback* = ((string, SinkConfig, Topic, StringTable) -> void)
  CloseCallback*  = ((SinkConfig) -> bool)
  FailCallback*   = ((SinkConfig, Topic, string, string, string) -> void)
  LogCallback*    = ((SinkConfig, Topic, string) -> void)
  StringTable*    = OrderedTableRef[string, string]
  MsgFilter*      = ((string, StringTable) -> (string, bool))

  SinkImplementation* = ref object
    name*:           string
    initFunction*:   Option[InitCallback]
    outputFunction*: OutputCallback
    closeFunction*:  Option[CloseCallback]
    keys*:           Table[string, bool]

  SinkConfig* = ref object
    name*:    string
    mySink*:  SinkImplementation
    filters*: seq[MsgFilter]
    params*:  StringTable
    private*: RootRef        # It's funny to make 'private' public,
                             # but externally written sinks can store
                             # state here, like file pointers.
    onFail*:   Option[FailCallback]
    logFunc*:  Option[LogCallback]
    rmOnErr*: bool

  Topic* = ref object
    name*:       string
    subscribers: seq[SinkConfig]

proc getName*(sink: SinkImplementation): string = sink.name
proc getName*(config: SinkConfig): string = config.name

var allSinks:   Table[string, SinkImplementation]
var allTopics*: Table[string, Topic]
var revTopics: Table[Topic, string]

proc subscribe*(topic: Topic, config: SinkConfig): Topic {.discardable.} =
  if config notin topic.subscribers:
    topic.subscribers.add(config)

  return topic

proc subscribe*(t: string, config: SinkConfig): Option[Topic] {.discardable.} =
  if t notin allTopics:
    return none(Topic)

  return some(subscribe(allTopics[t], config))

proc registerSink*(name: string, sink: SinkImplementation) =
  sink.name    = name
  allSinks[name] = sink

proc getSinkImplementation*(name: string): Option[SinkImplementation] =
  if name in allSinks:
    return some(allSinks[name])

  return none(SinkImplementation)

proc iolog*(s: SinkConfig, t: Topic, m: string) =
  if s.logFunc.isSome():
    let f = s.logFunc.get()
    f(s, t, m)

proc configSink*(s:          SinkImplementation,
                 name:       string,
                 `params?`:  Option[StringTable]  = none(StringTable),
                 filters:    seq[MsgFilter] = @[],
                 handler:    Option[FailCallback] = none(FailCallback),
                 logger:     Option[LogCallback]  = none(LogCallback),
                 rmOnErr:    bool = true,
                 raiseOnErr: bool = false

                ): Option[SinkConfig] =
  var params: StringTable

  if `params?`.isSome():
    params = `params?`.get()
  else:
    params = newOrderedTable[string, string]()

  for k, v in params:
    if k notin s.keys:
      if raiseOnErr:
        raise newException(ValueError, "Extraneous key: " & k)
      else:
        return none(SinkConfig)

  for k, v in s.keys:
    if v and k notin params:
      if raiseOnErr:
        raise newException(ValueError, "Required key missing: " & k)
      else:
        return none(SinkConfig) # Required key missing.

  let confObj = SinkConfig(mySink: s, name: name, params: params,
                           logFunc: logger, filters: filters, onFail: handler,
                           rmOnErr: rmOnErr)

  if s.initFunction.isSome():
    let fptr = s.initFunction.get()
    if not fptr(confObj):
      if raiseOnErr:
        raise newException(ValueError, "Sink init function failed.")
      else:
        return none(SinkConfig)

  return some(confObj)

proc registerTopic*(name: string): Topic =
  if name in allTopics: return allTopics[name]

  result            = Topic(name: name)
  allTopics[name]   = result
  revTopics[result] = name

proc getSubscribers*(topic: Topic): seq[SinkConfig] =
  return topic.subscribers

proc getNumSubscribers*(topic: Topic): int =
  return topic.subscribers.len()

proc unsubscribe*(topic: Topic, record: SinkConfig): bool =
  let ix = topic.subscribers.find(record)

  if ix == -1: return false

  # Super not threadsafe.
  topic.subscribers.delete(ix)
  if record.mySink.closeFunction.isSome():
    let fptr = record.mySink.closeFunction.get()
    return fptr(record)

  return true

proc unsubscribe*(topicName: string, record: SinkConfig): bool =
  if topicName notin allTopics:
    return false

  return unsubscribe(allTopics[topicName], record)

proc publish*(t:       Topic,
              message: string,
              aux:     StringTable = nil): int {.discardable.} =
  var
    tbl:        StringTable

  result = 0

  if aux == nil:
    tbl = newOrderedTable[string, string]({"topic" : revTopics[t]})
  else:
    tbl = aux
    tbl["topic"] = revTopics[t]

  for configObj in t.getSubscribers():
    var
      skipPublish = false
      currentMsg  = message # Each config gets to filter seprately
      more: bool

    for filter in configObj.filters:
      (currentMsg, more) = filter(currentMsg, tbl)
      if not more:
        skipPublish = true
        break

    if not skipPublish:
      let fptr = configObj.mySink.outputFunction

      try:
        fptr(currentMsg, configObj, t, aux)
        result += 1
      except:
        if configObj.onFail.isSome():
          let errHandler = configObj.onFail.get()
          errHandler(configObj, t, message, getCurrentExceptionMsg(),
                     getCurrentException().getStackTrace());
        if configObj.rmOnErr:
          #we're iterating over a copy of the subscribers, so this
          #should be ok.
          discard t.unsubscribe(configObj)

proc publish*(t:       string,
              message: string,
              aux:     StringTable = nil): int {.discardable.} =

  if t notin allTopics: return 0

  return publish(allTopics[t], message, aux)

proc prettyJson*(msg: string, extra: StringTable): (string, bool) =
  try:
    return (pretty(parseJson(msg)), true)
  except:
    when not defined(release):
      # This will help you figure out where and why you're
      # sending something that isn't valid JSON
      stderr.writeLine(getCurrentException().getStackTrace())
      stderr.writeLine(getCurrentExceptionMsg())
    return ("[Error: Invalid Json formatting] " & msg, false)

proc prettyJsonl*(msg: string, extra: StringTable): (string, bool) =
  var toReturn = ""

  try:
    let lines = msg.strip().split("\n")
    for line in lines:
      let strippedLine = line.strip()
      if len(strippedLine) == 0:
        continue
      toReturn &= pretty(parseJson(line)) & "\n"
    return (toReturn, true)
  except:
    when not defined(release):
      # This will help you figure out where and why you're
      # sending something that isn't valid JSON
      stderr.writeLine(getCurrentException().getStackTrace())
      stderr.writeLine(getCurrentExceptionMsg())
    return ("[Error: Invalid Json log formatting] " & msg, false)

proc fixNewline*(msg: string, extra: StringTable): (string, bool) =
  if msg[^1] != '\n':
    return (msg & "\n", true)
  return (msg, true)

proc wrapToWidth*(msg: string, extra: StringTable): (string, bool) =
  # Problem w/ this at the moment is it doesn't take ANSI codes into account.
  var
    w = if "width" in extra:
          parseInt(extra["width"])
        else:
          terminalWidth()
    i = if "indent" in extra:
          parseInt(extra["indent"])
        else:
          2

  return (indentWrap(msg, w, i), true)

proc addTopic*(msg: string, extra: StringTable): (string, bool) =
  var lines                 = msg.split("\n")
  var newLines: seq[string] = @[]

  for line in lines:
    newLines.add("  " & line)

  let
    topic   = extra["topic"]
    body    = newLines.join("\n") & "\n"
    prefix  = "<h4>" & "[[start " & topic & "]]\n" & "</h4>"
    postfix = "<h4>" & "[[end " & topic & "]]\n" & "</h4>"
    newstr  = prefix.stylize() & body & postfix.stylize()

  return (newstr, true)
