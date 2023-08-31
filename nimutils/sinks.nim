## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import streams, tables, options, os, strutils, std/[net, uri, httpclient],
       s3client, pubsub, misc, random, encodings, std/tempfiles,
       parseutils, unicodeid, openssl, file

const defaultLogSearchPath = @["/var/log/", "~/.log/", "."]

proc openLogFile*(name: string,
                  loc:  var string,
                  path: seq[string],
                  mode              = fmAppend): Option[FileStream] =
  ## Looks to open the given log file in the first possible place it
  ## can in the given path, even if it needs to create directories,
  ## etc.  If nothing in the path works, we try using a temp file as a
  ## last resort, using system APIs.
  ##
  ## The variable passed in as 'loc' will get the location we ended up
  ## selecting.
  ##
  ## Note that, if the 'name' parameter has a slash in it, we try that
  ## first, but if we can't open it, we try all our other options.
  ##
  ## Note that, if the mode is fmRead we position the steam at the
  ## beginning of the file.  For anything else, we jump to the end,
  ## even if you open for read/write.

  var
    fstream:  FileStream  = nil
    fullPath: seq[string] = path
    baseName: string      = name

  if '/' in name:
    let (head, tail) = splitPath(resolvePath(name))

    basename = tail
    fullPath = @[head] & fullPath

  for item in fullPath:
    try:
      let directory = resolvePath(item)
      createDir(directory)
      loc           = joinPath(directory, basename)
      fstream       = newFileStream(loc, mode)
      if fstream == nil:
        continue
      break
    except:
      continue

  if fstream == nil:
    try:
      let directory = createTempDir(basename, "tmpdir")
      loc           = joinPath(directory, basename)
      fstream       = newFileStream(loc, mode)
    except:
      return none(FileStream)

  # fmAppend will already position us at SEEK_END.  Nim doesn't have a
  # direct equivolent to seek() on file streams, we'd have to go down
  # to the posix API to so a seek(SEEK_END), so instead of picking
  # through the file stream internal state, we cheese it by discarding
  # a readAll().
  if mode notin [fmRead, fmAppend]:
    discard fstream.readAll()

  return some(fstream)

template cantLog() =
  var err = "Couldn't open a log file for sink configuration '" & cfg.name &
    "'; requested file was: '" & cfg.params["filename"] & "'"

  if '/' in cfg.params["filename"]:
    err &= "Fallback search path: "
  else:
    err &= "Directories tried: "

  err &= logpath.join(", ")
  raise newException(IOError, err)

proc stdoutSinkOut(msg:    string,
                   cfg:    SinkConfig,
                   t:      Topic,
                   ignore: StringTable) =
  stdout.write(msg)

proc addStdoutSink*() =
  registerSink("stdout", SinkImplementation(outputFunction: stdoutSinkOut))

proc stdErrSinkOut(msg:    string,
                   cfg:    SinkConfig,
                   t:      Topic,
                   ignore: StringTable) =
  stderr.write(msg)

proc addStdErrSink*() =
  registerSink("stderr", SinkImplementation(outputFunction: stderrSinkOut))

# Since we assume sink writes are only ever called from one thread at
# a time, the caller can look at the 'truncated' field after a publish()
# to decide if they want to do something about it.

proc fileSinkOut*(msg: string, cfg: SinkConfig, t: Topic, ignore: StringTable) =
  var stream = FileStream(cfg.private)
  if stream == nil:
    var
      outloc:    string
      streamOpt: Option[FileStream]
      mode    = fmAppend
      logpath: seq[string]

    if "use_search_path" notin cfg.params or
      cfg.params["use_search_path"] == "true":
      if "log_search_path" in cfg.params:
        logpath = cfg.params["log_search_path"].split(':')
      else:
        logpath = defaultLogSearchPath

      if "mode" in cfg.params and cfg.params["mode"] == "w":
         mode = fmWrite

      streamOpt = openLogFile(cfg.params["filename"], outloc, logpath, mode)
      if streamOpt.isNone():
        cantLog()
      stream = streamOpt.get()
    else:
      stream = newFileStream(resolvePath(cfg.params["filename"]), mode)
      if stream == nil:
        cantLog()

    cfg.params["actual_file"] = outloc
    cfg.private               = RootRef(stream)
    cfg.iolog(t, "Open") # The callback has access to format printing however.

  stream.write(msg)
  cfg.iolog(t, "Write")

proc fileSinkClose(cfg: SinkConfig): bool =
  try:
    var stream = FileStream(cfg.private)

    if stream != nil:
      stream.close()
    return true
  except:
    return false

type LogSinkState* = ref object of RootRef
  stream*:   FileStream
  maxSize*:  uint
  truncAmt*: uint

proc rotoLogSinkInit(cfg: SinkConfig): bool =
  try:
    var
      maxSize:  uint
      truncAmt: uint

    if parseUint(cfg.params["max"], maxSize) != len(cfg.params["max"]):
      # Not a valid integer, has trailing crap.
      return false
    if maxSize < 1024:
      return false # Too small to be useful.
    if "truncation_amount" in cfg.params:
      if parseUint(cfg.params["truncation_amount"], truncAmt) !=
         len(cfg.params["truncation_amount"]):
        return false
      if truncAmt >= maxSize:
        return false
    else:
        truncAmt = maxSize shr 2

    cfg.private = LogSinkState(maxSize: maxSize, truncAmt: truncAmt)
    return true
  except: # Can happen if parseUInt fails.
    return false

proc rotoLogSinkOut(msg: string, cfg: SinkConfig, t: Topic, tbl: StringTable) =
  var logState = LogSinkState(cfg.private)

  if logState.stream == nil:
    var
      outloc:    string
      streamOpt: Option[FileStream]
      logpath:   seq[string]

    if "log_search_path" in cfg.params:
      logpath = cfg.params["log_search_path"].split(':')
    else:
      logpath = defaultLogSearchPath

    streamOpt = openLogFile(cfg.params["filename"], outloc, logpath)

    if streamOpt.isNone():
      cantLog()

    logstate.stream           = streamOpt.get()
    cfg.params["actual_file"] = outloc
    cfg.iolog(t, "Open")

  # Even if no filter was added for \n we need to ensure the newline for
  # truncation boundaries.
  if msg[^1] != '\n':
    logState.stream.write(msg & '\n')
  else:
    logState.stream.write(msg)

  cfg.iolog(t, "Write")
  let loc = uint(logState.stream.getPosition())

  # If the message fills up the entire aloted space, we make an
  # exception (it's not a good log file if it doesn't actually write
  # the message in toto), but the next message will def push it out.
  # The +1 is because we might have written a newline above.
  if loc > logState.maxSize and logState.maxSize > uint(len(msg) + 1):
    let
      fullPath = cfg.params["actual_file"]
      truncLen = logState.truncAmt

    logState.stream.close() # "append" mode can't seek backward.

    let
      oldf            = newFileStream(fullPath, fmRead)
      (newfptr, path) = createTempFile("sink." & cfg.name, "log")
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
    cfg.iolog(t, "Truncate")

type S3SinkState* = ref object of RootRef
  region*:   string
  uri*:      Uri
  uid*:      string
  secret*:   string
  bucket*:   string
  objPath*:  string
  nameBase*: string
  extra*:    string

proc s3SinkInit(cfg: SinkConfig): bool =
  try:
    var region, extra: string
    let
      uri                 = parseURI(cfg.params["uri"])
      bucket              = uri.hostname
      uid                 = cfg.params["uid"]
      secret              = cfg.params["secret"]
      baseObj             = uri.path[1 .. ^1] # Strip the leading /
      (objPath, nameBase) = splitPath(baseObj)

    if "region" in cfg.params:
      region = cfg.params["region"]
    else:
      region = "us-east-1"

    if "extra" in cfg.params:
      extra = cfg.params["extra"]
    else:
      extra = ""

    cfg.private = S3SinkState(region: region, uri: uri, uid: uid,
                              secret: secret, bucket: bucket,
                              objPath: objPath,
                              nameBase: nameBase,  extra: extra)
    return true
  except:
    return false

proc s3SinkOut(msg: string, cfg: SinkConfig, t: Topic, ignored: StringTable) =
  var
    state  = S3SinkState(cfg.private)
    client = newS3Client((state.uid, state.secret), state.region)

  cfg.iolog(t, "Open") # Not really a connect...

  let
      ts           = $(unixTimeInMS())
      randVal      = base32vEncode(secureRand[array[16, char]]())
  var
      objParts: seq[string] = @[ts, randVal]

  if state.extra != "": objParts.add(state.extra)

  objParts.add(state.nameBase)

  let
      newTail  = objParts.join("-")
      newPath  = joinPath(state.objPath, newTail)
      response = client.putObject(state.bucket, newPath, msg)

  if response.status[0] != '2':
    raise newException(ValueError, response.status)
  else:
    cfg.iolog(t, "Post to: " & newPath & "; response = " & response.status)

proc SSL_CTX_load_verify_file(ctx: SslCtx, CAfile: cstring):
                       cint {.cdecl, dynlib: DLLSSLName, importc.}

proc postSinkOut(msg: string, cfg: SinkConfig, t: Topic, ignored: StringTable) =
  var
    client:      HttpClient
    headers:     HttpHeaders
    timeout:     int
    uri:         Uri                   = parseURI(cfg.params["uri"])
    tups:        seq[(string, string)] = @[]
    contentType: string                = cfg.params["content_type"]
    pinnedCert:  string                = ""
    context:     SslContext

  if "pinned_cert_file" in cfg.params:
    pinnedCert = cfg.params["pinned_cert_file"]
  if "headers" in cfg.params:
    var
      rawHeaders = cfg.params["headers"].split("\n")

    for line in rawHeaders:
      let ix  = line.find(":")
      if ix == -1:
        continue
      let
        key = line[0 ..< ix].strip()
        val = line[ix + 1 .. ^1].strip()
      tups.add((key, val))

  # This might also get provided in the headers; not checking right now.
  tups.add(("Content-Type", contentType))

  headers = newHTTPHeaders(tups)

  if "timeout" in cfg.params:
    let paramstr = cfg.params["timeout"]
    if parseInt(paramstr, timeout) != len(paramstr):
      raise newException(ValueError, "Timeout must be miliseconds " &
                         "represented as an integer, or 0 for no timeout.")
    elif timeout <= 0:
      timeout = -1
  else:
    timeout = 5000 # 5 seconds.

  if uri.scheme == "https":
    context = newContext(verifyMode = CVerifyPeer)
    if pinnedCert != "":
      discard context.context.SSL_CTX_load_verify_file(pinnedCert)
    client  = newHttpClient(sslContext=context, timeout=timeout)
  else:
    if "disallow_http" in cfg.params:
      raise newException(ValueError, "http:// URLs not allowed (only https).")
    elif pinnedCert != "":
      raise newException(ValueError, "Pinned cert not allowed with http " &
                                      "URL (only https).")
    client = newHttpClient(timeout=timeout)

  if client == nil:
    raise newException(ValueError, "Invalid HTTP configuration")

  let response = client.request(url        = uri,
                                httpMethod = HttpPost,
                                body       = msg,
                                headers    = headers)
  if response.status[0] != '2':
    raise newException(ValueError, response.status)

  cfg.iolog(t, "Post " & response.status)

proc addFileSink*() =
  var
    record   = SinkImplementation()
    keys     = { "filename"       : true,
                 "mode"           : false,
                 "log_search_path": false,
                 "use_search_path": false,
               }.toTable()

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
    record = SinkImplementation()
    keys   = {
      "filename"          : true,
      "max"               : true,
      "log_search_path"   : false,
      "truncation_amount" : false
             }.toTable()

  record.initFunction   = some(InitCallback(rotologSinkInit))
  record.outputFunction = rotologSinkOut
  record.closeFunction  = some(CloseCallback(fileSinkClose))
  record.keys           = keys

  registerSink("rotating_log", record)

proc addS3Sink*() =
  var
    record = SinkImplementation()
    keys   = { "uid"     : true,
               "secret"  : true,
               "uri"     : true,
               "region"  : false,
               "extra"   : false
             }.toTable()

  record.initFunction   = some(InitCallback(s3SinkInit))
  record.outputFunction = s3SinkOut
  record.keys           = keys

  registerSink("s3", record)

proc addPostSink*() =
  var
    record = SinkImplementation()
    keys = {
      "uri"              : true,
      "content_type"     : true,
      "disallow_http"    : false,
      "headers"          : false,
      "timeout"          : false,
      "pinned_cert_file" : false
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
