import switchboard, posix, random, os

{.compile: joinPath(splitPath(currentSourcePath()).head, "c/subproc.c").}
{.pragma: sproc, cdecl, importc, nodecl.}

type
  SPResultObj* {. importc: "sb_result_t", header: "c/switchboard.h" .} = object
  SPResult* = ptr SPResultObj
  SubProcess*  {. importc: "subprocess_t" .} = object
    result*: SpResult

  SPIoKind* = enum SPIoNone = 0, SpIoStdin = 1, SpIoStdout = 2,
              SpIoInOut = 3, SpIoStderr = 4, SpIoInErr = 5,
              SpIoOutErr = 6, SpIoAll = 7

proc subproc_init(ctx: var SubProcess, cmd: cstring, args: cStringArray)
    {.sproc.}
proc subproc_set_envp(ctx: var SubProcess, args: cStringArray)
    {.sproc.}
proc subproc_pass_to_stdin(ctx: var SubProcess, s: cstring, l: csize_t,
                           close_fd: bool): bool {.sproc.}
proc sp_result_capture(res: SpResult, tag: cstring, ln: ptr cint): cstring
    {.sproc.}
proc sp_result_exit(res: SpResult): cint {.sproc.}
proc sp_result_errno(res: SPResult): cint {.sproc.}
proc sp_result_signal(res: SpResult): cint {.sproc.}

# Not wrapped.
# extern bool subproc_set_io_callback(subprocess_t *, unsigned char,
#                                    switchboard_cb_t);
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

  s = sp_result_capture(ctx.result, tag, addr outlen)
  if outlen == 0:
    ""
  else:
    bytesToString(cast[ptr UncheckedArray[char]](s), int(outlen))

proc getStdin*(ctx: var SubProcess): string =
  if ctx.result == SPResult(nil):
    raise newException(IoError, "Process hasn't exited")

  return getTaggedValue(ctx, cstring("stdin"))

proc getStdout*(ctx: var SubProcess): string =
  if ctx.result == nil:
    raise newException(IoError, "Process hasn't exited")

  return getTaggedValue(ctx, cstring("stdout"))
proc getStderr*(ctx: var SubProcess): string =
  if ctx.result == nil:
    raise newException(IoError, "Process hasn't exited")

  return getTaggedValue(ctx, cstring("stderr"))

proc getExitCode*(ctx: var SubProcess): int =
  if ctx.result == nil:
    raise newException(IoError, "Process hasn't exited")

  return int(sp_result_exit(ctx.result))

proc getErrno*(ctx: var SubProcess): int =
  if ctx.result == nil:
    raise newException(IoError, "Process hasn't exited")

  return int(sp_result_errno(ctx.result))

proc getSignal*(ctx: var SubProcess): int =
  if ctx.result == nil:
    raise newException(IoError, "Process hasn't exited")

  return int(sp_result_signal(ctx.result))


when isMainModule:
  var subproc: SubProcess
  var timeout: Timeval

  timeout.tv_sec  = Time(0)
  timeout.tv_usec = 1000

  subproc.initSubProcess("/bin/cat", ["/bin/cat", "aes.nim"])
  subproc.setTimeout(timeout)
  subproc.usePty()
  subproc.setPassthrough()
  subproc.setCapture()
  subproc.run()

  echo subproc.getPid()
  echo subproc.getStdout()
