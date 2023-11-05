import switchboard, posix, random, os, file

{.warning[UnusedImport]: off.}
{.compile: joinPath(splitPath(currentSourcePath()).head, "subproc.c").}
{.pragma: sproc, cdecl, importc, nodecl.}

type
  Termcap* {. importc: "struct termios", header: "<termios.h>" .} = object
    c_iflag*:  uint
    c_oflag*:  uint
    c_cflag*:  uint
    c_lflag*:  uint
    c_cc*:     array[20, byte]
    c_ispeed*: int
    c_ospeed*: int
  TcsaConst* = enum
    TCSANOW, TCSADRAIN, TCSAFLUSH

  CCConst* = enum
    VEOF = 0, VEOL = 1, VEOL2 = 2, VERASE = 3, VWERASE = 4, VKILL = 5,
    VREPRINT = 6, VINTR = 8, VQUIT = 9, VSUSP = 10, VDSUSP = 11, VSTART = 12,
    VSTOP = 13, VLNEXT = 14, VDISCARD = 15, VMIN = 16, VTIME = 17,
    VSTATUS = 18, NCCS = 20

  IFConst* = enum
    IGNBRK = 0x01'i32, BRKINT = 0x02, IGNPAR = 0x04, PARMRK = 0x08,
    INPCK = 0x10, ISTRIP = 0x20, INLCR = 0x40, IGNCR = 0x80, ICRNL = 0x100,
    IXON = 0x200, IXOFF = 0x400, IXANY = 0x800, IUCLC = 0x1000,
    IMAXBEL = 0x2000

  OFConst* = enum
    TAB0 = 0x00'i32, OPOST = 0x01, ONLCR = 0x02, TABDLY = 0x04,
    ONOEOT = 0x08, OCRNL = 0x10, OLCUC = 0x20, ONOCR = 0x40, ONLRET = 0x80

  CFConst* = enum
    CS5 = 0, CIGNORE = 0x01, CS6 = 0x100, CS7 = 0x200, CSIZE = 0x300,
    CSTOPB = 0x400, CREAD = 0x800, PARENB = 0x1000, PARODD = 0x2000,
    HUPCL = 0x4000, CLOCAL = 0x8000, CRTSCTS = 0x10000, MDMBUF = 0x100000

  LFConst* = enum
    ECHOKE = 0x01, ECHOE = 0x02, ECHOK = 0x04, ECHO = 0x08, ECHONL = 0x10,
    ECHOPRT = 0x20, ECHOCTL = 0x40, ISIG = 0x80, ICANON = 0x100,
    ALTWERASE = 0x200, IEXTEN = 0x400, EXTPROC = 0x800, TOSTOP = 0x400000,
    FLUSHO = 0x800000, XCASE = 0x1000000, NOKERNINFO = 0x2000000,
    PENDIN = 0x20000000, NOFLSH = 0x80000000

  SubProcCallback* =
    proc (i0: pointer, i1: pointer, i2: cstring, i3: int) {. cdecl, gcsafe .}
  SpStartupCallback* =
    proc (i0: var SubProcess) {. cdecl, gcsafe .}

  SPIoKind* = enum
    SPIoNone = 0, SpIoStdin = 1, SpIoStdout = 2,
    SpIoInOut = 3, SpIoStderr = 4, SpIoInErr = 5,
    SpIoOutErr = 6, SpIoAll = 7
  SPResultObj* {. importc: "sb_result_t", header: joinPath(splitPath(currentSourcePath()).head, "switchboard.h") .} = object
  SPResult* = ptr SPResultObj
  SubProcess*  {.importc: "subprocess_t", header: joinPath(splitPath(currentSourcePath()).head, "switchboard.h") .} = object

proc tcgetattr*(fd: cint, info: var Termcap): cint {. cdecl, importc,
                                 header: "<termios.h>", discardable.}
proc tcsetattr*(fd: cint, opt: TcsaConst, info: var Termcap):
              cint {. cdecl, importc, header: "<termios.h>", discardable.}
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
proc subproc_get_exit(ctx: var SubProcess, wait: bool): cint {.sproc.}
proc subproc_get_errno(ctx: var SubProcess, wait: bool): cint {.sproc.}
proc subproc_get_signal(ctx: var SubProcess, wait: bool): cint {.sproc.}

# Functions we can call directly w/o a nim proxy.
proc setParentTermcap*(ctx: var SubProcess, tc: var Termcap) {.cdecl,
                          importc: "subproc_set_parent_termcap", nodecl.}
proc setChildTermcap*(ctx: var SubProcess, tc: var Termcap) {.cdecl,
                          importc: "subproc_set_parent_termcap", nodecl.}

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
proc getPtyFd*(ctx: var SubProcess): cint
    {.cdecl, importc: "subproc_get_pty_fd", nodecl.}
proc start*(ctx: var SubProcess) {.cdecl, importc: "subproc_start", nodecl.}
proc poll*(ctx: var SubProcess): bool {.cdecl, importc: "subproc_poll", nodecl.}
proc prepareResults*(ctx: var SubProcess) {.cdecl,
                     importc: "subproc_prepare_results", nodecl.}
proc run*(ctx: var SubProcess)  {.cdecl, importc: "subproc_run", nodecl.}
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
proc setStartupCallback*(ctx: var SubProcess, callback: SpStartupCallback) {.
      cdecl, importc: "subproc_set_startup_callback", nodecl .}
proc rawFdWrite*(fd: cint, buf: pointer, l: csize_t)
    {.cdecl, importc: "write_data", nodecl.}
proc binaryCstringToString*(s: cstring, l: int): string =
  for i in 0 ..< l:
    result.add(s[i])

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
    binaryCstringToString(s, outlen);

proc getStdin*(ctx: var SubProcess): string =
  ctx.getTaggedValue("stdin")

proc getStdout*(ctx: var SubProcess): string =
  ctx.getTaggedValue("stdout")

proc getStderr*(ctx: var SubProcess): string =
  ctx.getTaggedValue("stderr")

proc getExitCode*(ctx: var SubProcess, waitForExit = true): int =
  return int(subproc_get_exit(ctx, waitForExit))

proc getErrno*(ctx: var SubProcess, waitForExit = true): int =
  return int(subproc_get_errno(ctx, waitForExit))

proc getSignal*(ctx: var SubProcess, waitForExit = true): int =
  return int(subproc_get_signal(ctx, waitForExit))

type ExecOutput* = ref object
    stdin*:    string
    stdout*:   string
    stderr*:   string
    exitCode*: int
    pid*:      Pid

proc runCommand*(exe:  string,
                 args: seq[string],
                 newStdin                = "",
                 closeStdIn              = false,
                 pty                     = false,
                 passthrough             = SpIoNone,
                 passStderrToStdin       = false,
                 capture                 = SpIoOutErr,
                 combineCapture          = false,
                 timeoutUsec             = 1000,
                 env:  openarray[string] = [],
                 waitForExit             = true): ExecOutput =
  ## One-shot interface
  var
    subproc: SubProcess
    timeout: Timeval
    binloc:  string
    binlocs = exe.findAllExePaths()

  if binlocs.len() == 0:
    binloc = exe
  else:
    binloc = binlocs[0]

  timeout.tv_sec  = Time(timeoutUsec / 1000000)
  timeout.tv_usec = Suseconds(timeoutUsec mod 1000000)

  subproc.initSubprocess(binloc, @[exe] & args)
  subproc.setTimeout(timeout)

  if len(env) != 0:
    subproc.setEnv(env)
  if pty:
    subproc.usePty()
  if passthrough != SpIoNone:
    subproc.setPassthrough(passthrough, passStderrToStdin)
  if capture != SpIoNone:
    subproc.setCapture(capture, combineCapture)

  if newStdIn != "":
    discard subproc.pipeToStdin(newStdin, closeStdin)
  subproc.run()

  result          = ExecOutput()
  result.pid      = subproc.getPid()
  result.exitCode = subproc.getExitCode(waitForExit)
  result.stdout   = subproc.getStdout()
  result.stdin    = subproc.getStdin()
  result.stderr   = subproc.getStderr()

template getStdout*(o: ExecOutput): string = o.stdout
template getStderr*(o: ExecOutput): string = o.stderr
template getExit*(o: ExecOutput): int      = o.exitCode

template runInteractiveCmd*(path: string,
                            args: seq[string],
                            passToChild = "",
                            closeFdAfterPass = true,
                            ensureExit = true) =
  discard runCommand(path, args, passthrough = SpIoAll, capture = SpIoNone,
                     newStdin = passToChild, closeStdin = closeFdAfterPass,
                                pty = true, waitForExit = ensureExit)

proc runCmdGetEverything*(exe:  string,
                              args: seq[string],
                              newStdIn    = "",
                              closeStdIn  = true,
                              passthrough = false,
                              timeoutUsec = 1000000,
                              ensureExit  = true): ExecOutput =
  return runCommand(exe, args, newStdin, closeStdin, pty = false,
                    passthrough = if passthrough: SpIoAll else: SpIoNone,
                    timeoutUSec = timeoutUsec, capture = SpIoOutErr, waitForExit = ensureExit)

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
