## For now, anything that changes the state is assumed to be not
## thread-safe.
##
## While I'd like to improve this some day, it's just enough for
## Sami, while making it reusable for other single-threaded apps.

import tables, sugar, options, json, strutils, ansi, strutils, std/terminal,
       unicodeid

type
  InitCallback*   = ((SinkConfig) -> bool)
  OutputCallback* = ((string, SinkConfig, StringTable) -> bool)
  CloseCallback*  = ((SinkConfig) -> bool)
  StringTable*    = OrderedTableRef[string, string]
  MsgFilter*      = ((string, StringTable) -> (string, bool))
  
  SinkRecord* = ref object
    name:           string
    initFunction*:   Option[InitCallback]
    outputFunction*: OutputCallback
    closeFunction*:  Option[CloseCallback]
    keys*:           Table[string, bool]
    
  SinkConfig* = ref object
    mySink*:  SinkRecord
    filters*: seq[MsgFilter]
    config*:  StringTable
    private*: RootRef        # It's funny to make 'private' public,
                             # but externally written sinks can store
                             # state here, like file pointers.
  Topic* = ref object
    subscribers*: seq[SinkConfig]
    
proc getSinkName*(rec: SinkRecord): string = rec.name
  
# Exported so you can 'patch' default sinks, etc.
var allSinks*: Table[string, SinkRecord]
var allTopics*: Table[string, Topic]
var revTopics: Table[Topic, string]

proc subscribe*(topic: Topic, record: SinkConfig): Topic =
  if record notin topic.subscribers:
    topic.subscribers.add(record)

  return topic

proc subscribe*(t: string, record: SinkConfig): Option[Topic] =
  if t notin allTopics:
    return none(Topic)
  
  return some(subscribe(allTopics[t], record))

proc registerSink*(name: string, record: SinkRecord) =
  record.name = name
  allSinks[name] = record
  
proc getSink*(name: string): Option[SinkRecord] =
  if name in allSinks:
    return some(allSinks[name])

  return none(SinkRecord)
  
proc configSink*(s:         SinkRecord,
                 `config?`: Option[StringTable] = none(StringTable),
                 filters:   seq[MsgFilter] = @[]): Option[SinkConfig] =
  var config: StringTable
  
  if `config?`.isSome():
    config = `config?`.get()
  else:
    config = newOrderedTable[string, string]()
    
  for k, v in config:
    if k notin s.keys: return none(SinkConfig) # Extraneous key.
    
  for k, v in s.keys:
    if v and k notin config: return none(SinkConfig) # Required key missing.

  let confObj = SinkConfig(mySink: s, config: config, filters: filters)
  
  if s.initFunction.isSome():
    let fptr = s.initFunction.get()
    if not fptr(confObj):
      return none(SinkConfig)

  return some(confObj)

proc registerTopic*(name: string): Topic =
  if name in allTopics: return allTopics[name]

  result            = Topic()
  allTopics[name]   = result
  revTopics[result] = name
  
  
proc unsubscribe*(topic: Topic, record: SinkConfig): bool =
  let ix = topic.subscribers.find(record)

  if ix == -1: return false

  topic.subscribers.delete(ix) # Super not threadsafe.
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
              aux:     StringTable = nil): bool {.discardable.} =
  var success = true
  var tbl: StringTable

  if aux == nil:
    tbl = newOrderedTable[string, string]({"topic" : revTopics[t]})
  else:
    tbl = aux
    tbl["topic"] = revTopics[t]
  
  for hook in t.subscribers:
    var
      currentMsg = message # Each hook gets to filter seprately
      more: bool
    
    for filter in hook.filters:
      (currentMsg, more) = filter(currentMsg, tbl)
      if not more: break

    let fptr = hook.mySink.outputFunction
    
    if not fptr(currentMsg, hook, aux):
      success = false # TODO, allow registering a handler for this.
    
proc publish*(t:       string,
              message: string,
              aux:     StringTable = nil): bool {.discardable.} =
  
  if t notin allTopics:
    return false

  return publish(allTopics[t], message, aux)

proc prettyJson*(msg: string, extra: StringTable): (string, bool) =
  try:
    return (pretty(parseJson(msg)), true)
  except:
    return ("Error: Invalid Json formatting", false)

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
    prefix  = ansi("font1", "BLUE").get() & "[[start " & topic & "]]\n" &
              ansi("reset").get()
    postfix = ansi("font1", "BLUE").get() & "[[end " & topic & "]]\n" &
              ansi("reset").get()
    newstr  =  prefix & body & postfix
    
  return (newstr, true)
