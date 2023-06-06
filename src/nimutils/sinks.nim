import streams, tables, options, os, strutils, std/[net, uri, httpclient],
       nimaws/s3client, topics, misc, random, encodings, std/termios,
       std/posix, std/tempfiles, parseutils, unicodeid

proc stdoutSink(msg: string, cfg: SinkConfig, ignore: StringTable) =
  stdout.write(msg.perLineWrap())

proc addStdoutSink*() =
  registerSink("stdout", SinkRecord(outputFunction: stdoutSink))

proc stdErrSink(msg: string, cfg: SinkConfig, ignore: StringTable) =
  stderr.write(msg.perLineWrap())

proc addStdErrSink*() =
  registerSink("stderr", SinkRecord(outputFunction: stderrSink))

# Since we assume sink writes are only ever called from one thread at
# a time, the caller can look at the 'truncated' field after a publish()
# to decide if they want to do something about it.

proc fileSinkOut*(msg: string, cfg: SinkConfig, ignore: StringTable) =
  var stream = FileStream(cfg.private)

  if stream == nil:
    var mode = fmAppend

    if cfg.config.contains("mode") and cfg.config["mode"] == "w":
      mode = fmWrite
    stream      = newFileStream(resolvePath(cfg.config["filename"]), mode)
    cfg.private = RootRef(stream)

  stream.write(msg)

proc fileSinkClose(cfg: SinkConfig): bool =
  try:
    var stream = FileStream(cfg.private)

    if stream != nil:
      stream.close()
    return true
  except:
    return false

type LogSinkState* = ref object of RootRef
  stream*:    FileStream
  maxSize*:   uint
  truncated*: bool


proc rotoLogSinkInit(cfg: SinkConfig): bool =
  try:
    var maxSize: uint

    if parseUint(cfg.config["max"], maxSize) != len(cfg.config["max"]):
      # Not a valid integer, has trailing crap.
      return false
    if maxSize >= 1024:
      cfg.private = LogSinkState(maxSize: maxSize)
      return true
    else:
      return false
  except:
    return false

proc rotoLogSinkOut*(msg: string, cfg: SinkConfig, ignore: StringTable) =
  var logState = LogSinkState(cfg.private)

  logState.truncated = false

  if logState.stream == nil:
    let fullPath = resolvePath(cfg.config["filename"])
    try:
      # Append expects the file to exist.
      logState.stream = newFileStream(fullPath, fmAppend)
    except:
      # If this write doesn't work, then it's a permissions issue, and
      # we should let the exception propogate.
      logState.stream = newFileStream(fullPath, fmWrite)

  if msg[^1] != '\n':
    logState.stream.write(msg & '\n')
  else:
    logState.stream.write(msg)

  let loc = uint(logState.stream.getPosition())

  # If the message fills up the entire aloted space, we make an exception,
  # but the next message will def push it out.  The +1 is because we might
  # have written a newline above.
  if loc > logState.maxSize and logState.maxSize > uint(len(msg) + 1):
    let
      fullPath = resolvePath(cfg.config["filename"])
      truncLen = logState.maxSize shr 2  # Remove 25% of the file

    logState.stream.close() # "append" mode can't seek backward.
    let
      oldf            = newFileStream(fullPath, fmRead)
      (newfptr, path) = createTempFile("nimutils", "log")
      newf            = newFileStream(newfptr)

    while oldf.getPosition() < int64(truncLen):
      discard oldf.readLine()

    while oldf.getPosition() < int64(loc):
      newf.writeLine(oldf.readLine())

    # Since we shrunk into a temp file that we're going to move over,
    # it's a lot easier to close the file and move it over.  If
    # another write happens to this sink config, then the file will
    # get re-opened next time.
    oldf.close()
    newf.close()
    moveFile(path, fullPath)
    logState.stream    = nil
    logState.truncated = true

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

proc pipeOut(msg: string, cfg: SinkConfig, ignore: StringTable) =
  var f = cast[File](cfg.private)
  f.write(msg)

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
  record.outputFunction = fileSinkOut
  record.closeFunction  = some(CloseCallback(fileSinkClose))
  record.keys           = keys

  registerSink("file", record)

proc addRotoLogSink*() =
  var
    record = SinkRecord()
    keys   = {"filename" : true, "max" : true}.toTable()

  record.initFunction   = some(InitCallback(rotologSinkInit))
  record.outputFunction = rotologSinkOut
  record.closeFunction  = some(CloseCallback(fileSinkClose))
  record.keys           = keys

  registerSink("rotating_log", record)

var awsClientCache: Table[string, S3Client]

proc s3SinkInit(record: SinkConfig): bool =
  if "cacheid" in record.config:
    let
      uid    = record.config["uid"]
      secret = record.config["secret"]

    awsClientCache[record.config["cacheid"]] = newS3Client((uid, secret))

  return true

proc s3SinkOut(msg: string, record: SinkConfig, ignored: StringTable) =
  var extra  = if "cacheid" in record.config:
                 record.config["cacheid"]
               else:
                 ""
  var client = if extra != "": awsClientCache[extra]
               else:
                 let
                   uid    = record.config["uid"]
                   secret = record.config["secret"]
                 newS3Client((uid, secret))
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

  if res.code != Http200:
    raise newException(ValueError, "S3 failed with https err code: " &
      $(res.code))

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

proc postSinkOut(msg: string, record: SinkConfig, ignored: StringTable) =
  let
    uriStr = record.config["uri"]
    uriObj = parseURI(uriStr)

  var client = if uriObj.scheme == "https":
                 newHttpClient(sslContext=newContext(verifyMode=CVerifyPeer))
               else:
                 newHttpClient()

  if client == nil:
    raise newException(ValueError, "Invalid HTTP configuration")

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

  if `$`(response.code)[0] != '2':
    raise newException(ValueError, "HTTP post failed with code: " &
      $(response.code))

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
  addRotoLogSink()
  addS3Sink()
  addPostSink()
  # addPipeSink() Don't think this got finished?  Either way, not looking now.

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
