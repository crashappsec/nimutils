import streams, tables, options, os, strutils
import std/[net, uri, httpclient]
import topics
import nimaws/s3client
import misc
import random


proc stdoutSink(msg: string, cfg: SinkConfig, ignore: StringTable): bool =
  stdout.write(msg)
  return true

proc addStdoutSink*() =
  registerSink("stdout", SinkRecord(outputFunction: stdoutSink))
               
proc stdErrSink(msg: string, cfg: SinkConfig, ignore: StringTable): bool =
  stderr.write(msg)
  return true

proc addStdErrSink*() =
  registerSink("stderr", SinkRecord(outputFunction: stderrSink))

proc fileSinkInit(record: SinkConfig): bool =
  var
    filename = resolvePath(record.config["filename"])
    mode     = fmAppend

  if record.config.contains("mode"):
    let modeCfg = record.config["mode"]
    case modeCfg
    of "w": mode = fmWrite
    of "a": mode = fmAppend
    else: return false
      
  var stream     = newFileStream(filename, mode)
  record.private = cast[RootRef](stream)

  if stream == nil: return false
  return true

proc fileSinkOut(msg: string, cfg: SinkConfig, ignore: StringTable): bool =
  try:
    var stream = cast[FileStream](cfg.private)
    
    stream.write(msg)
    return true
  except:
    return false

proc fileSinkClose(cfg: SinkConfig): bool =
  try:
    var stream = cast[FileStream](cfg.private)
    
    stream.close()
    return true
  except:
    return false

proc addFileSink*() =
  var
    record   = SinkRecord()
    keys     = { "filename" : true, "mode" : false }.toTable()

  # I learned the hard way here that, except when procs are
  # declared, the default calling convention is {.closure.},
  # not {.nimcall.}.  so types like InitCallback expect
  # {.closure.}, but if we assign directly to a field, it
  # silently figures it out.  When we pass to some() though,
  # it does not.
  record.initFunction   = some(InitCallback(fileSinkInit))
  record.outputFunction = fileSinkOut
  record.closeFunction  = some(CloseCallback(fileSinkClose))
  record.keys           = keys
  
  registerSink("file", record)

var awsClientCache: Table[string, S3Client]

proc s3SinkInit(record: SinkConfig): bool =
  if "cacheid" in record.config:
    let
      uid    = record.config["uid"]
      secret = record.config["secret"]
    
    awsClientCache[record.config["cacheid"]] = newS3Client((uid, secret))
      
  return true
  
proc s3SinkOut(msg: string, record: SinkConfig, ignored: StringTable): bool =
  var extra  = if "cacheid" in record.config: record.config["cacheid"] else: ""
  var client = if extra != "":
                 awsClientCache[extra]
               else:
                 let
                   uid    = record.config["uid"]                   
                   secret = record.config["secret"]
                 newS3Client((uid, secret))
  try:
    let
      uri          = record.config["uri"]
      dstUri       = parseURI(uri)
      bucket       = dstUri.hostname
      ts           = $(unixTimeInMS())
      randVal      = getRandomWords(2)
      baseObj      = dstUri.path[1 .. ^1] # Strip the leading /
      (head, tail) = splitPath(baseObj)
    var
      objParts: seq[string] = @[ts, randVal]

    if extra != "": objParts.add(extra)
    
    objParts.add(tail)

    let
      newTail = objParts.join("-")
      newPath = joinPath(head, newTail)
      res     = client.putObject(bucket, newPath, msg)
      
    if res.code == Http200:
      return true
    else:
      return false
  except:
    if extra != "":
      discard s3SinkInit(record)
    return false

proc s3SinkClose(record: SinkConfig): bool =
  if "cacheid" in record.config: record.config.del("cacheid")
      
proc addS3Sink*() =
  var
    record = SinkRecord()
    keys   = { "uid"     : true,
               "secret"  : true,
               "uri"     : true,
               "cacheid" : false # We cache w/ this if present.
             }.toTable()

  record.initFunction   = some(InitCallback(s3SinkInit))
  record.outputFunction = s3SinkOut
  record.closeFunction  = some(InitCallback(s3SinkClose))
  record.keys           = keys

  registerSink("s3", record)

proc postSinkOut(msg: string, record: SinkConfig, ignored: StringTable): bool =
  let
    uriStr = record.config["uri"]
    uriObj = parseURI(uriStr)

  var client = if uriObj.scheme == "https":
                 newHttpClient(sslContext=newContext(verifyMode=CVerifyPeer))
               else:
                 newHttpClient()
                 
  if client == nil: return false

  if "headers" in record.config:
    var
      headers = record.config["headers"].split("\n")
      tups: seq[(string, string)] = @[]

    for line in headers:
      let ix  = line.find(":")
      if ix == -1:
        continue
      let
        key = line[0 ..< ix].strip()
        val = line[ix + 1 .. ^1].strip()
      tups.add((key, val))
      
    if len(headers) != 0:
      client.headers = newHTTPHeaders(tups)

  let response = client.request(uriStr, httpMethod = HttpPost, body = msg)

  if `$`(response.code)[0] == '2':
    return true
  else:
    return false
  
proc addPostSink*() =
  var
    record = SinkRecord()
    keys = {
      "uri"     : true,
      "headers" : false
    }.toTable()

  record.outputFunction = postSinkOut
  record.keys           = keys

  registerSink("post", record)
  
proc addDefaultSinks*() =
  addStdoutSink()
  addStderrSink()
  addFileSink()
  addS3Sink()
  addPostSink()

when isMainModule:
  addDefaultSinks()
  let
    s3Conf    = { "uid"     : "INSERT UID",
                  "secret"  : "INSERT SECRET",
                  "uri"     : "s3://insert-bucket-info-blah/test",
                  "cacheid" : "yo" }.toTable()
    testTopic = registerTopic("test")
    cffile    = configSink(getSink("file").get(),
                           some( { "filename" : "/tmp/sinktest",
                                   "mode" : "a" }.toTable() )).get()
    cferr     = configSink(getSink("stderr").get()).get()
    s3sink    = getSink("s3").get()
    cfs3      = configSink(s3sink, some(s3Conf)).get()
                           
  discard subscribe(testTopic, cffile)
  discard subscribe(testTopic, cferr)
  discard subscribe(testTopic, cfs3)

  discard publish(testTopic, "Hello, file!\n")
