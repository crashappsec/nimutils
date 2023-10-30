import switchboard, posix, random, os, file

{.warning[UnusedImport]: off.}
{.compile: joinPath(splitPath(currentSourcePath()).head, "subproc.c").}
{.pragma: sproc, cdecl, importc, nodecl.}

type
  Termcap* {. importc: "struct termios", header: "<termios.h>" .} = object
  SubProcCallback* =
    proc (i0: pointer, i1: pointer, i2: cstring, i3: int) {. cdecl, gcsafe .}
  SPIoKind* = enum
    SPIoNone = 0, SpIoStdin = 1, SpIoStdout = 2,
    SpIoInOut = 3, SpIoStderr = 4, SpIoInErr = 5,
    SpIoOutErr = 6, SpIoAll = 7
  SPResultObj* {. importc: "sb_result_t", header: joinPath(splitPath(currentSourcePath()).head, "switchboard.h") .} = object
  SPResult* = ptr SPResultObj
  SubProcess*  {.importc: "subprocess_t", header: joinPath(splitPath(currentSourcePath()).head, "switchboard.h") .} = object

proc termcap_get*(termcap: var Termcap) {.sproc.}
proc termcap_set*(termcap: var Termcap) {.sproc.}
proc termcap_set_typical_parent*() {.sproc.}

proc subproc_init(ctx: var SubProcess, cmd: cstring, args: cStringArray)
    {.sproc.}
proc subproc_set_envp(ctx: var SubProcess, args: cStringArray)
    {.sproc.}
proc subproc_pass_to_stdin(ctx: var SubProcess, s: cstring, l: csize_t,
                           close_fd: bool): bool {.sproc.}
proc subproc_get_capture(ctx: var SubProcess, tag: cstring, ln: ptr cint):
                        cstring {.sproc.}
proc subproc_get_exit(ctx: var SubProcess): cint {.sproc.}
proc subproc_get_errno(ctx: var SubProcess): cint {.sproc.}
proc subproc_get_signal(ctx: var SubProcess): cint {.sproc.}

# Functions we can call directly w/o a nim proxy.
proc setPassthroughRaw*(ctx: var SubProcess, which: SPIoKind, combine: bool)
    {.cdecl, importc: "subproc_set_passthrough", nodecl.}
template setPassthrough*(ctx: var SubProcess, which = SPIoAll, merge = false) =
  ctx.setPassthroughRaw(which, merge)

proc setCaptureRaw*(ctx: var SubProcess, which: SPIoKind, combine: bool)
    {.cdecl, importc: "subproc_set_capture", nodecl.}
template setCapture*(ctx: var SubProcess, which = SPIoOutErr, merge = false) =
  ctx.setCaptureRaw(which, merge)

proc setTimeout*(ctx: var SubProcess, value: var Timeval)
    {.cdecl, importc: "subproc_set_timeout", nodecl.}
proc clearTimeout*(ctx: var SubProcess)
    {.cdecl, importc: "subproc_clear_timeout", nodecl.}
proc usePty*(ctx: var SubProcess) {.cdecl, importc: "subproc_use_pty", nodecl.}
proc start*(ctx: var SubProcess) {.cdecl, importc: "subproc_start", nodecl.}
proc poll*(ctx: var SubProcess) {.cdecl, importc: "subproc_poll", nodecl.}
proc getResult*(ctx: var SubProcess): SPResult
    {.cdecl, importc: "subproc_get_result", nodecl.}
proc run*(ctx: var SubProcess): SpResult
    {.cdecl, importc: "subproc_run", nodecl, discardable.}
proc close*(ctx: var SubProcess) {.cdecl, importc: "subproc_close", nodecl.}
proc getPid*(ctx: var SubProcess): Pid
    {.cdecl, importc: "subproc_get_pid", nodecl.}
proc setExtra*(ctx: var SubProcess, p: pointer)
    {.cdecl, importc: "subproc_set_extra", nodecl.}
proc getExtra*(ctx: var SubProcess): pointer
    {.cdecl, importc: "subproc_get_extra", nodecl.}
proc setIoCallback*(ctx: var SubProcess, which: SpIoKind,
                           callback: SubProcCallback): bool
    {.cdecl, importc: "subproc_set_io_callback", nodecl, discardable.}
proc rawFdWrite*(fd: cint, buf: pointer, l: csize_t)
    {.cdecl, importc: "write_data", nodecl.}


# Nim proxies. Note that the allocCStringArray() calls are going to leak
# for the time being. We should clean them up in a destructor.

proc initSubProcess*(ctx: var SubProcess, cmd: string,
                      args: openarray[string]) =
  var cargs = allocCstringArray(args)
  subproc_init(ctx, cstring(cmd), cargs)

proc setEnv*(ctx: var SubProcess, env: openarray[string]) =
  var envp = allocCstringArray(env)
  ctx.subproc_set_envp(envp)

proc pipeToStdin*(ctx: var SubProcess, s: string, close_fd: bool): bool =
  return ctx.subproc_pass_to_stdin(cstring(s), csize_t(s.len()), close_fd)

template getTaggedValue*(ctx: var SubProcess, tag: static[cstring]): string =
  var
    outlen: cint
    s:      cstring

  s = subproc_get_capture(ctx, tag, addr outlen)
  if outlen == 0:
    ""
  else:
    bytesToString(cast[ptr UncheckedArray[char]](s), int(outlen))

proc getStdin*(ctx: var SubProcess): string =
  ctx.getTaggedValue("stdin")

proc getStdout*(ctx: var SubProcess): string =
  ctx.getTaggedValue("stdout")

proc getStderr*(ctx: var SubProcess): string =
  ctx.getTaggedValue("stderr")

proc getExitCode*(ctx: var SubProcess): int =
  return int(subproc_get_exit(ctx))

proc getErrno*(ctx: var SubProcess): int =
  return int(subproc_get_errno(ctx))

proc getSignal*(ctx: var SubProcess): int =
  return int(subproc_get_signal(ctx))

type ExecOutput* = object
    stdin*:    string
    stdout*:   string
    stderr*:   string
    exitCode*: int
    pid*:      Pid

proc runCommand*(exe:  string,
                 args: seq[string],
                 env:  openarray[string] = [],
                 newStdin                = "",
                 closeStdIn              = false,
                 pty                     = false,
                 passthrough             = SpIoNone,
                 passStderrToStdin       = false,
                 capture                 = SpIoOutErr,
                 combineCapture          = false,
                 timeoutUsec             = 1000): ExecOutput =
  ## One-shot interface
  var
    subproc: SubProcess
    timeout: Timeval

  timeout.tv_sec  = Time(timeoutUsec / 1000000)
  timeout.tv_usec = Suseconds(timeoutUsec mod 1000000)

  subproc.initSubprocess(exe, @[exe] & args)
  subproc.setTimeout(timeout)

  if len(env) != 0:
    subproc.setEnv(env)
  if pty:
    subproc.usePty()
  if passthrough != SpIoNone:
    subproc.setPassthrough(passthrough, passStderrToStdin)
  if capture != SpIoNone:
    subproc.setCapture(capture, combineCapture)

  subproc.run()

  result.pid      = subproc.getPid()
  result.exitCode = subproc.getExitCode()
  result.stdout   = subproc.getStdout()
  result.stdin    = subproc.getStdin()
  result.stderr   = subproc.getStderr()


template getStdout*(o: ExecOutput): string = o.stdout
template getStderr*(o: ExecOutput): string = o.stderr
template getExit*(o: ExecOutput): int      = o.exitCode


template runInteractiveCmd*(path: string,
                            args: seq[string],
                            passToChild = "") =
  let closeIt = if passToChild == "": false else: true
  discard runCommand(path, args, passthrough = SpIoAll, capture = SpIoNone,
                     newStdin = passToChild, closeStdin = closeIt, pty = true)

template runCmdGetEverything*(exe:  string,
                              args: seq[string],
                              newStdIn    = "",
                              closeStdIn  = false,
                              passthrough = false,
                              timeoutUsec = 1000000): ExecOutput =
  discard runCommand(exe, args, newStdin, closeStdin, pty = false,
                     passthrough = if passthrough: SpIoAll else: SpIoNone,
                     timeoutUSec = timeoutUsec, capture = SpIoOutErr)


proc runPager*(s: string) =
  var
    exe:   string
    flags: seq[string]

  if s == "":
    return

  if isatty(1) == 0:
    echo s
    return

  let less = findAllExePaths("less")
  if len(less) > 0:
    exe   = less[0]
    flags = @["-r", "-F"]
  else:
    let more = findAllExePaths("more")
    if len(more) > 0:
      exe = more[0]
    else:
      raise newException(ValueError,
                         "Could not find 'more' or 'less' in your path.")

  runInteractiveCmd(exe, flags, s)


template runCmdGetOutput*(exe: string, args: seq[string]): string =
  execProcess(exe, args = args, options = {})

when isMainModule:
  var res = runCommand("/bin/cat", @["aes.nim"], pty = true, capture = SpIoAll,
                                                       passthrough = SpIoNone)

  echo "pid = ", res.pid

  sleep(2000)
  echo res.stdout
