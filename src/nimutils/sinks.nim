import streams, tables, options, os, strutils, std/[net, uri, httpclient],
       nimaws/s3client, topics, misc, random, encodings, std/termios, std/posix,
       box, unicodeid

proc stdoutSink(msg: string, cfg: SinkConfig, ignore: StringTable): bool =
  stdout.write(msg.perLineWrap())
  return true

proc addStdoutSink*() =
  registerSink("stdout", SinkRecord(outputFunction: stdoutSink))

proc stdErrSink(msg: string, cfg: SinkConfig, ignore: StringTable): bool =
  stdout.write(msg.perLineWrap())
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

const ptyheader = when defined(macosx): "<util.h>" else: "<pty.h>"

proc forkpty(aprimary: ptr FileHandle,
             name:     ptr char,
             termios:  ptr Termios,
             winsize:  ptr IOctl_WinSize):
               int {.cdecl, importc, header: ptyheader.}

proc freopen(path: ptr cchar,  mode: ptr cchar, stream: File):
            File {.cdecl, importc, header: "<stdio.h>".}


var pipePid: Pid = 0

proc pipeInit(record: SinkConfig): bool =
    var childStdout: array[2, cint]
    var fd:          FileHandle
    var filename =   "/usr/bin/less"
    var args     = allocCStringArray(["less", "-R", "-d", "-F"])
    var s: array[1000, char]
    var maintty  = ttyname(1)
    var pcchr = addr(maintty[0])
    var mode = cstring("rw")
    var pcmode = addr(mode[0])


    var fds: array[2, cint]

    setStdioUnbuffered()

    if record.config.contains("filename"):
      filename = record.config["filename"]
      if record.config.contains("args"):
        let cmdline = filename & " " & record.config["args"]
        args = allocCstringArray(cmdline.split(" "))
      else:
        args = allocCstringArray([filename])

    #let pid = forkpty(addr fd, addr(s[0]), nil, nil)

    discard pipe(fds)

    pipePid = fork()
    case pipePid
    of 0: # Child.
      echo "In child"
      discard dup2(fds[0], 0)
      discard close(fds[1])
      #discard freopen(pcchr, pcmode, stdin)
      echo pcchr
      discard freopen(pcchr, pcmode, stdout)
      setStdioUnbuffered()
      discard execvp(filename, cStringArray(args))
    of -1:
      echo "Fail :("
      discard
    else:
      echo "In parent"
      #let tty = $(cstring(addr(s[0])))
      var
        f:      File
      #echo "open = ",  open(f, fd, fmReadWrite)
      echo "open = ",  open(f, fds[1], fmWrite)
      discard close(fds[0])
      record.private = cast[RootRef](f)

    return true

proc pipeOut(msg: string, cfg: SinkConfig, ignore: StringTable): bool =
  try:
    var f = cast[File](cfg.private)
    f.write(msg)
    return true
  except:
    return false

  var x: cint
  discard waitpid(pipePid, x, 0)


proc pipeClose(cfg: SinkConfig): bool =
  try:
    var f = cast[FileStream](cfg.private)
    f.close()
  finally:
    return true

proc addPipeSink*() =
  var
    record = SinkRecord()
    keys   = { "filename": false, "args": false}.toTable()

  record.initFunction   = some(InitCallback(pipeInit))
  record.outputFunction = pipeOut
  record.closeFunction  = some(CloseCallback(pipeClose))
  record.keys           = keys

  registerSink("pipe", record)

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
      randVal      = base32vEncode(secureRand[array[16, char]]())
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

  if client == nil:
    return false

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
  addPipeSink()

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
