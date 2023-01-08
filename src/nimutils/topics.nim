## For now, anything that changes the state is assumed to be not
## thread-safe.
##
## While I'd like to improve this some day, it's just enough for
## Sami, while making it reusable for other single-threaded apps.

import tables, sugar, options

type
  InitCallback*   = ((SinkConfig) -> bool)
  OutputCallback* = ((string, SinkConfig, StringTable) -> bool)
  CloseCallback*  = ((SinkConfig) -> bool)
  StringTable*    = Table[string, string]
  MsgFilter*      = ((string, StringTable) -> (string, bool))
  
  SinkRecord* = ref object
    initFunction*:   Option[InitCallback]
    outputFunction*: OutputCallback
    closeFunction*:  Option[CloseCallback]
    keys*:           Table[string, bool]
    
  SinkConfig* = ref object
    mySink:   SinkRecord
    filters:  seq[MsgFilter]
    config*:  StringTable
    private*: RootRef        # It's funny to make 'private' public,
                             # but externally written sinks can store
                             # state here, like file pointers.
  Topic* = ref object
    subscribers: seq[SinkConfig]

var allSinks: Table[string, SinkRecord]
var allTopics: Table[string, Topic]

proc subscribe*(topic: Topic, record: SinkConfig): Topic =
  if record notin topic.subscribers:
    topic.subscribers.add(record)

  return topic

proc subscribe*(t: string, record: SinkConfig): Option[Topic] =
  if t notin allTopics:
    return none(Topic)
  
  return some(subscribe(allTopics[t], record))

proc registerSink*(name: string, record: SinkRecord) =
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
    config = initTable[string, string]()
    
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

  result = Topic()
  allTopics[name] = result
  
  
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

const emptyAux = initTable[string, string]()

proc publish*(t: Topic,
              message: string,
              aux: StringTable = emptyAux): bool =
  var success = true
  
  for hook in t.subscribers:
    var
      currentMsg = message # Each hook gets to filter seprately
      more: bool
    
    for filter in hook.filters:
      (currentMsg, more) = filter(currentMsg, aux)
      if not more: break

    let fptr = hook.mySink.outputFunction
    
    if not fptr(currentMsg, hook, aux):
      success = false # TODO, allow registering a handler for this.
    
proc publish*(t:       string,
              message: string,
              aux:     StringTable = emptyAux): bool =
  if t notin allTopics:
    return false

  return publish(allTopics[t], message, aux)
