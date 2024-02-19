import switchboard, posix, random, os, file

{.warning[UnusedImport]: off.}
{.compile: joinPath(splitPath(currentSourcePath()).head, "c/subproc.c").}
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
  SPResultObj* {. importc: "sb_result_t", header: "switchboard.h" .} = object
  SPResult* = ptr SPResultObj
  SubProcess*  {.importc: "subprocess_t", header: "switchboard.h" .} = object

proc tcgetattr*(fd: cint, info: var Termcap): cint {. cdecl, importc,
                                 header: "<termios.h>", discardable.}
proc tcsetattr*(fd: cint, opt: TcsaConst, info: var Termcap):
              cint {. cdecl, importc, header: "<termios.h>", discardable.}
proc termcap_get*(termcap: var Termcap) {.sproc.}
proc termcap_set*(termcap: var Termcap) {.sproc.}
proc subproc_init(ctx: var SubProcess, cmd: cstring, args: cStringArray,
                  proxyStdinClose: bool)
    {.sproc.}
proc subproc_set_envp(ctx: var SubProcess, args: cStringArray)
    {.sproc.}
proc subproc_pass_to_stdin(ctx: var SubProcess, s: cstring, l: csize_t,
                           close_fd: bool): bool {.sproc.}
proc subproc_get_capture(ctx: var SubProcess, tag: cstring, ln: ptr csize_t):
                        cstring {.sproc.}
proc subproc_get_exit(ctx: var SubProcess, wait: bool): cint {.sproc.}
proc subproc_get_errno(ctx: var SubProcess, wait: bool): cint {.sproc.}
proc subproc_get_signal(ctx: var SubProcess, wait: bool): cint {.sproc.}

# Functions we can call directly w/o a nim proxy.
proc setParentTermcap*(ctx: var SubProcess, tc: var Termcap) {.cdecl,
                          importc: "subproc_set_parent_termcap", nodecl.}
  ## Set the parent's termcap at the time of a fork, for when subprocesses
  ## are using a pseudo-terminal (pty). Generally the default should be
  ## good.
  ##
  ## If not provided, the parent will assume that it's going to proxy
  ## most things from the child, and turn off any appropriate
  ## functionality (such as character echo).
  ##
  ## This must be called before spawning a process.

proc setChildTermcap*(ctx: var SubProcess, tc: var Termcap) {.cdecl,
                          importc: "subproc_set_parent_termcap", nodecl.}
  ## Set the child's termcap at the time of a fork, for when subprocesses
  ## are using a pseudo-terminal (pty).
  ##
  ## This does not need to be called unless customization is
  ## necessary, but if you do call it, you must do so before spawning
  ## a process.

proc setPassthroughRaw*(ctx: var SubProcess, which: SPIoKind, combine: bool)
    {.cdecl, importc: "subproc_set_passthrough", nodecl.}
  ## Low-level wrapper used by `setPassthrough()`

template setPassthrough*(ctx: var SubProcess, which = SPIoAll, merge = false) =
  ## This controls how input from the user gets forwarded to the child
  ## process. Currently, it can only be called before spawning a process.
  ##
  ## The streams denoted in the `which` parameter will have forwarding
  ## enabled.
  ctx.setPassthroughRaw(which, merge)

proc setCaptureRaw*(ctx: var SubProcess, which: SPIoKind, combine: bool)
    {.cdecl, importc: "subproc_set_capture", nodecl.}
  ## The low-level interface used by `setCapture`

template setCapture*(ctx: var SubProcess, which = SPIoOutErr, merge = false) =
  ## This controls what input streams will be *captured*. Captured
  ## input is available to the user after the process ends, by calling
  ## `getStdout()`, `getStderr()` and `getStdin()` on the `SPResult`
  ## object available after closing.
  ##
  ## If you want incremental input, use `setIoCallback()` instead.
  ##
  ## The `which` parameter controls which streams will be collected;
  ## this may include stdin if you want to capture raw input for
  ## whatever reason.
  ##
  ## When `merge` is true, then `stderr` and `stdout` will be treated
  ## as one output stream

  ## Currently, this must be called before spawning a process.
  ctx.setCaptureRaw(which, merge)

proc rawMode*(termcap: var Termcap) {.cdecl, importc: "termcap_set_raw_mode",
                                      nodecl.}
  ## This configures a `Termcap` data structure for `raw` mode, which
  ## loosely is non-echoing and unbuffered. There's not quite a firm
  ## standard for what raw mode is; but it's a collection of settings,
  ## most of which no longer matter in modern terminals.

proc setTimeout*(ctx: var SubProcess, value: var Timeval)
    {.cdecl, importc: "subproc_set_timeout", nodecl.}
  ## This sets how long the process should wait when doing a single
  ## poll of file-descriptors to be ready with data to read. If you
  ## don't set this, there will be no timeout, and it's possible for
  ## the process to die and for the file descriptors associated with
  ## them to never return ready.
  ##
  ## This is *not* an overall timeout for your process, it's a timeout
  ## for a single i/o polling cycle.
  ##
  ## If you have a timeout, a progress callback can be called.
  ##
  ## Also, when the process is not blocked on the select(), right
  ## before the next select we check the status of the subprocess. If
  ## it's returned and all its descriptors are marked as closed, and
  ## no descriptors that are open are waiting to write, then the
  ## subprocess switchboard will exit.

proc clearTimeout*(ctx: var SubProcess)
    {.cdecl, importc: "subproc_clear_timeout", nodecl.}
  ## Remove any set timeout.

proc usePty*(ctx: var SubProcess) {.cdecl, importc: "subproc_use_pty", nodecl.}
  ## When this is set on a SubProcess object before the process is
  ## spawned, it will cause the process to start using a
  ## pseudo-terminal (pty), which, from the point of view of the
  ## process being called, simulates a terminal.
  ##
  ## This can be necessary since some programs only work properly when
  ## connected to a terminal, such as `more()` or `less()`.

proc getPtyFd*(ctx: var SubProcess): cint
    {.cdecl, importc: "subproc_get_pty_fd", nodecl.}
  ## When using a PTY, this call returns the file descriptor associated
  ## with the child process's terminal.

proc start*(ctx: var SubProcess) {.cdecl, importc: "subproc_start", nodecl.}
  ## This starts the sub-process, forking it off. It does NOT poll for
  ## input-output. For many apps, you don't need this function;
  ## instead, use `run()`.
  ##
  ## Use this only when you're going to do your own IO polling loop.

proc poll*(ctx: var SubProcess): bool {.cdecl, importc: "subproc_poll", nodecl.}
  ## If you're running your own IO polling loop, this runs the loop
  ## one time. You must have previously called `start()`.
  ##
  ## This returns `true` when called after the process has exited.

proc run*(ctx: var SubProcess)  {.cdecl, importc: "subproc_run", nodecl.}
  ## This launches a subprocess, and polls it for IO until the process
  ## ends, and has no waiting data left to read.
  ##
  ## Once that happens, you can immediately query results.
  ##
  ## Note that if you want the subprocess to run in parallel while you
  ## do other things, you can either set an IO callback (with
  ## `setIoCallback()`) or manually poll by instead using `start()` and
  ## then calling `poll()` in your own loop.

proc close*(ctx: var SubProcess) {.cdecl, importc: "subproc_close", nodecl.}
  ## Closes down a subprocess; do not call any querying function after
  ## this, as the memory will be freed.

proc `=destroy`*(ctx: var SubProcess) =
    ctx.close()

proc getPid*(ctx: var SubProcess): Pid
    {.cdecl, importc: "subproc_get_pid", nodecl.}
  ## Returns the process ID associated with the subprocess. This may
  ## be called at any point after the process spawns.

proc setExtra*(ctx: var SubProcess, p: pointer)
    {.cdecl, importc: "subproc_set_extra", nodecl.}
  ## This can be used to make arbitrary information available to your
  ## I/O callbacks that is specific to the SubProcess instance.

proc getExtra*(ctx: var SubProcess): pointer
    {.cdecl, importc: "subproc_get_extra", nodecl.}
  ## This can be used to retrieve any information set via `setExtra()`.

proc pausePassthrough*(ctx: var SubProcess, which: SpIoKind)
    {.cdecl, importc: "subproc_pause_passthrough", nodecl.}
  ## Stops passthrough data from being passed (though pending writes
  ## may still succeed).

proc resumePassthrough*(ctx: var SubProcess, which: SpIoKind)
    {.cdecl, importc: "subproc_resume_passthrough", nodecl.}
  ## Resumes passthrough after being paused.  For data that didn't get
  ## passed during the pause, it will not be seen after the pause
  ## either.
  ##
  ## This allows you to toggle whether input makes it to the
  ## subprocess, for instance.

proc pauseCapture*(ctx: var SubProcess, which: SpIoKind)
    {.cdecl, importc: "subproc_pause_capture", nodecl.}
  ## Stops capture of a stream.  If it's resumed, data published
  ## during the pause will NOT be added to the capture.

proc resumeCapture*(ctx: var SubProcess, which: SpIoKind)
    {.cdecl, importc: "subproc_resume_capture", nodecl.}
  ## Resumes capturing a stream that's been paused.

proc setIoCallback*(ctx: var SubProcess, which: SpIoKind,
                           callback: SubProcCallback): bool
    {.cdecl, importc: "subproc_set_io_callback", nodecl, discardable.}
  ## Sets up a callback for receiving IO as it is read or written from
  ## the terminal. The `which` parameter indicates which streams you
  ## wish to subscribe to. You may call this multiple times, for
  ## instance, if you'd like to subscribe each stream to a different
  ## function, or would like two different functions to receive data.

proc setStartupCallback*(ctx: var SubProcess, callback: SpStartupCallback) {.
      cdecl, importc: "subproc_set_startup_callback", nodecl .}
  ## This allows you to set a callback in the parent process that will
  ## run once, after the underlying fork occurs, but before any IO is
  ## processed.

proc rawFdWrite*(fd: cint, buf: pointer, l: csize_t)
    {.cdecl, importc: "write_data", nodecl.}
  ## An operation that writes from memory to a raw file descriptor.

template binaryCstringToString*(s: cstring, l: int): string =
  ## Don't use this; should probably be rm'd in favor of bytesToString,
  ## which it now calls.
  bytesToString(s, l)

# Nim proxies. Note that the allocCStringArray() calls are going to leak
# for the time being. We should clean them up in a destructor.

proc initSubProcess*(ctx: var SubProcess, cmd: string,
                     args: openarray[string], proxyStdinClose: bool) =
  ## Initialize a subprocess with the command to call. This does *NOT*
  ## run the sub-process. Instead, you can first configure it, and
  ## then call `run()` when ready.
  var cargs = allocCstringArray(args)
  subproc_init(ctx, cstring(cmd), cargs, proxyStdinClose)

proc setEnv*(ctx: var SubProcess, env: openarray[string]) =
  ## Explicitly set the environment the subprocess should inherit. If
  ## not called before the process is launched, the parent's
  ## environment will be inherited.
  var envp = allocCstringArray(env)
  ctx.subproc_set_envp(envp)

proc pipeToStdin*(ctx: var SubProcess, s: string, close_fd: bool): bool =
  ## This allows you to pass input to the subprocess through its
  ## stdin.  If called before the process spawns, the input will be
  ## passed before any other input to the subprocessed process is
  ## handled.
  ##
  ## You can still use this at any point as long as the process's stdin
  ## remains open. However, if you pass `true` to the parameter `close_fd`,
  ## then the child's stdin will get closed automatically once the
  ## write completes.
  return ctx.subproc_pass_to_stdin(cstring(s), csize_t(s.len()), close_fd)

proc getTaggedValue*(ctx: var SubProcess, tag: cstring): string =
  ## Lower-level interface to retrieving captured streams. Use
  ## `getStd*()` instead.
  var
    outlen: csize_t
    s:      cstring

  s = subproc_get_capture(ctx, tag, addr outlen)
  if outlen == 0:
    result = ""
  else:
    result = binaryCstringToString(s, int(outlen))

proc getStdin*(ctx: var SubProcess): string =
  ## Retrieve stdin, if it was captured. Must be called after the
  ## process has completed.
  ctx.getTaggedValue("stdin")

proc getStdout*(ctx: var SubProcess): string =
  ## Retrieve stdout, if it was captured. Must be called after the
  ## process has completed.
  ##
  ## If you specified combining stdout and stderr, it will be
  ## available here.
  ctx.getTaggedValue("stdout")

proc getStderr*(ctx: var SubProcess): string =
  ## Retrieve stdout, if it was captured. Must be called after the
  ## process has completed.
  ctx.getTaggedValue("stderr")

proc getExitCode*(ctx: var SubProcess, waitForExit = true): int =
  ## Returns the exit code of the process.
  return int(subproc_get_exit(ctx, waitForExit))

proc getErrno*(ctx: var SubProcess, waitForExit = true): int =
  ## If the child died and we received an error, this will contain
  ## the value of `errno`.
  return int(subproc_get_errno(ctx, waitForExit))

proc getSignal*(ctx: var SubProcess, waitForExit = true): int =
  ## If the process died as the result of being passed a signal,
  ## this will contain the signal number.
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
                 closeStdin              = false,
                 proxyStdinClose         = true,
                 pty                     = false,
                 passthrough             = SpIoNone,
                 passStderrToStdout      = false,
                 capture                 = SpIoOutErr,
                 combineCapture          = false,
                 timeoutUsec             = 1000,
                 env:  openarray[string] = [],
                 waitForExit             = true): ExecOutput =
  ## This is wrapper that provides a a single call alternative to the
  ## builder-style interface. It encompases most of the functionality,
  ## though it currently doesn't support setting callbacks.
  ##
  ## Parameters are:
  ## - `exe`: The path to the executable to run.
  ## - `args`: The arguments to pass. DO NOT include `exe` again as
  ##           the first argument, as it is automatically added.
  ## - `newStdin`: If not empty, the contents will be fed to the subprocess
  ##               after it starts.
  ## - `closeStdin`: If true, will close stdin after writing the contents
  ##                 of `newStdin` to the subprocess.
  ## - `proxyStdinClose`: If true, will close stdin subscribers after
  ##                      source stdin is closed.
  ## - `pty`: Whether to use a pseudo-terminal (pty) to run the sub-process.
  ## - `passthrough`: Whether to proxy between the parent's stdin/stdout/stderr
  ##                  and the child's. You can specify which ones to proxy.
  ## - `passStderrToStdout`: When this is true, the child's stderr is passed
  ##                         to stdout, not stderr.
  ## - `capture`: Specifies which file descritors to capture.  Captures are
  ##              available after the process ends.
  ## - `combineCapture`: If true, and if you requested capturing both stdout
  ##                     and stderr, will combine them into one stream.
  ## - `timeoutUsec`: The number of milliseconds to wait per polling cycle
  ##                  for input. If this is ever exceeded, the subprocess
  ##                  will abort. Set to 0 for unlimited (default is 1000,
  ##                  or 1 second).
  ## - `env`: The environment to pass to the subprocess. The default
  ##          is to inherit the parent's environment.
  ## - `waitForExit`: If false, runCommand returns as soon as the subprocess's
  ##                  file descriptors are closed, and doesn't wait for the
  ##                  subprocess to finish. In this case, process exit status
  ##                  will not be reliable.
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

  subproc.initSubprocess(binloc, @[exe] & args, proxyStdinClose)
  subproc.setTimeout(timeout)

  if len(env) != 0:
    subproc.setEnv(env)
  if pty:
    subproc.usePty()
  if passthrough != SpIoNone:
    subproc.setPassthrough(passthrough, passStderrToStdout)
  if capture != SpIoNone:
    subproc.setCapture(capture, combineCapture)

  if newStdin != "":
    discard subproc.pipeToStdin(newStdin, closeStdin)
  subproc.run()

  result          = ExecOutput()
  result.pid      = subproc.getPid()
  result.exitCode = subproc.getExitCode(waitForExit)
  result.stdin    = subproc.getStdin()
  result.stdout   = subproc.getStdout()
  result.stderr   = subproc.getStderr()

template getStdin*(o: ExecOutput): string =
  ## Returns any data captured from the child's stdin stream.
  o.stdin
template getStdout*(o: ExecOutput): string =
  ## Returns any data captured from the child's stdout stream.
  o.stdout
template getStderr*(o: ExecOutput): string =
  ## Returns any data captured from the child's stderr stream.
  o.stderr
template getExit*(o: ExecOutput): int =
  ## Returns any data captured, as passed to the child's std input
  o.exitCode
template getPid*(o: ExecOutput): int =
  ## Returns the PID from the exited process
  o.pid

template runInteractiveCmd*(path: string,
                            args: seq[string],
                            passToChild = "",
                            closeFdAfterPass = true,
                            ensureExit = true) =
  ## A wrapper for `runCommand` that uses a pseudo-terminal, and lets the
  ## user interact with the subcommand.
  discard runCommand(path, args, passthrough = SpIoAll, capture = SpIoNone,
                     newStdin = passToChild, closeStdin = closeFdAfterPass,
                                pty = true, waitForExit = ensureExit)

proc runCmdGetEverything*(exe:  string,
                          args: seq[string],
                          newStdin    = "",
                          closeStdin  = true,
                          passthrough = false,
                          timeoutUsec = 1000000,
                          ensureExit  = true): ExecOutput =
  ## A wrapper for `runCommand` that captures all output from the
  ## process.  This is similar to Nim's `execCmdEx` but allows for
  ## optional passthrough, timeouts, and sending an input string to
  ## stdin.
  let isStdinTTY = isatty(0) != 0
  return runCommand(exe, args, newStdin, closeStdin,
                    pty         = if passthrough: isStdinTTY else: false,
                    passthrough = if passthrough: SpIoAll else: SpIoNone,
                    timeoutUSec = timeoutUsec,
                    capture     = SpIoOutErr,
                    waitForExit = ensureExit)

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
  ## A legacy wrapper that remains for compatability.
  execProcess(exe, args = args, options = {})
