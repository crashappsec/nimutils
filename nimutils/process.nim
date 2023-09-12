## Process-related utilities.
##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import misc, strutils, posix, file, os, options

template runCmdGetOutput*(exe: string, args: seq[string]): string =
  execProcess(exe, args = args, options = {})

type ExecOutput* = object
    stdout*:   string
    stderr*:   string
    exitCode*: int

# Returns the exit code on normal exit; throws an exception otherwise.
proc waitPidWithTimeout*(pid: Pid, timeoutms: int = 1000): int =
  var
    stat_ptr: cint
    incr = int(timeoutms / 10)
    i = 0

  if incr == 0:
    incr = 1

  while true:
    let pid = waitpid(pid, stat_ptr, WNOHANG)
    if pid != -1:
      return int(WEXITSTATUS(stat_ptr))
    if i >= timeoutms:
      raise newException(IoError, "Timeout")
    i += incr
    os.sleep(incr)

when hostOs == "macosx":
  {.emit: """
#include <unistd.h>
#include <libproc.h>

   char *c_get_app_fname(char *buf) {
     proc_pidpath(getpid(), buf, PROC_PIDPATHINFO_MAXSIZE); // 4096
     return buf;
   }
   """.}

  proc cGetAppFilename(x: cstring): cstring {.importc: "c_get_app_fname".}

  proc betterGetAppFileName(): string =
    var x: array[4096, byte]

    return $(cGetAppFilename(cast[cstring](addr x[0])))

elif hostOs == "linux":
  {.emit: """
#include <unistd.h>

   char *c_get_app_fname(char *buf) {
   char proc_path[128];
   snprintf(proc_path, 128, "/proc/%d/exe", getpid());
   readlink(proc_path, buf, 4096);
   return buf;
   }
   """.}

  proc cGetAppFilename(x: cstring): cstring {.importc: "c_get_app_fname".}

  proc betterGetAppFileName(): string =
    var x: array[4096, byte]

    return $(cGetAppFilename(cast[cstring](addr x[0])))
else:
  template betterGetAppFileName(): string = getAppFileName()

when hostOs == "macosx":
  proc getMyAppPath*(): string {.exportc.} =
    let name = betterGetAppFileName()

    if "_CHALK" notin name:
      return name
    let parts = name.split("_CHALK")[0 .. ^1]

    for item in parts:
      if len(item) < 3:
        return name
      case item[0 ..< 3]
      of "HM_":
        result &= "#"
      of "SP_":
        result &= " "
      of "SL_":
        result &= "/"
      else:
        return name
      if len(item) > 3:
        result &= item[3 .. ^1]
    echo "getMyAppPath() = ", result
else:
  proc getMyAppPath*(): string {.exportc.} = betterGetAppFileName()

template ccall*(code: untyped, success = 0) =
  let ret = code

  if ret != success:
    echo ($(strerror(ret)))
    quit(1)

proc readAllOutput*(pid: Pid, stdout, stderr: cint, timeoutUsec: int):
                  ExecOutput =
  var
    toRead:   TFdSet
    timeout:  Timeval
    stat_ptr: cint
    buf:      array[0 .. 4096, byte]



  FD_ZERO(toRead)

  timeout.tv_sec  = Time(timeoutUsec / 1000000)
  timeout.tv_usec = Suseconds(timeoutUsec mod 1000000)

  while true:
    FD_SET(stdout, toRead)
    FD_SET(stderr, toRead)

    case select(2, addr toRead, nil, nil, addr timeout)
    of 0:
      let res = waitpid(pid, stat_ptr, WNOHANG)
      if res != -1:
        break
      else:
        raise newException(IOError, "Timeout exceeded while waiting for output")
    of 2:
      result.stdout &= stdout.oneReadFromFd()
      result.stderr &= stderr.oneReadFromFd()
    of 1:
      if FD_ISSET(stdout, toRead) != 0:
        result.stdout &= stdout.oneReadFromFd()
      else:
        result.stdout &= stdout.oneReadFromFd()
    else:
      if errno == EINVAL or errno == EBADF:
        raise newException(ValueError, "Invalid parameter for select()")
      else:
        continue # EAGAIN or EINTR

    let res = waitpid(pid, stat_ptr, WNOHANG)
    if res != -1: # Process ended; break to drain.
      break

  result.stdout &= stdout.readAllFromFd()
  result.stderr &= stderr.readAllFromFd()
  result.exitCode = int(WEXITSTATUS(stat_ptr))


{.emit: """
#include <stdlib.h>
#include <termios.h>
#include <unistd.h>
#include <util.h>
#include <sys/ioctl.h>


/* This is not yet going to handle window size changes. */

pid_t
spawn_pty_c(char *path, char *argv[], char *envp[], int *fd)
{
    struct termios termcap;
    struct winsize wininfo;
    struct termios *term_ptr = &termcap;
    struct winsize *win_ptr  = &wininfo;

    pid_t pid;

    if (!isatty(0)) {
	printf("No terminal.\n");
	term_ptr = NULL;
	win_ptr  = NULL;
    }
    else {
	ioctl(0, TIOCGWINSZ, win_ptr);
	tcgetattr(0, term_ptr);
    }
    pid = forkpty(fd, NULL, term_ptr, win_ptr);

    if (pid != 0) {
	return pid;
    }

    execve(path, argv, envp);
    abort();
}
""".}

proc spawn_pty_c(path: cstring, argv: cstringArray, env: cstringArray,
                 fdptr: ptr cint): Pid {.importc, cdecl, nodecl.}

proc spawnPty*(path: string, argv: seq[string],
                env: Option[seq[string]] = none(seq[string])): (Pid, cint, string) =
  var
    buf:  array[4096, byte]
    fd:   cint
    pid:  Pid
    envp: cStringArray
    cargs = allocCstringArray(@[path] & argv)
    plen: int

  if env.isNone():
    var envitems: seq[string]
    for k, v in envPairs():
      envitems.add(k & "=" & v)
    envp = allocCStringArray(envitems)
  else:
    envp = allocCStringArray(env.get())

  pid = spawn_pty_c(cstring(path), cargs, envp, addr fd)

  discard ttyname_r(fd, cast[cstring](addr buf[0]), 4096)

  for item in buf:
    if item == 0:
      break
    plen += 1

  let ttyname = bytesToString(buf[0 ..< plen])

  return (pid, fd, ttyname)


proc runCmdGetEverything*(exe:      string,
                          args:     seq[string],
                          newStdIn: string       = "",
                          timeoutUsec            = 1000000): ExecOutput =
  var
    stdOutPipe: array[0 .. 1, cint]
    stdErrPipe: array[0 .. 1, cint]
    stdInPipe:  array[0 .. 1, cint]

  ccall pipe(stdOutPipe)
  ccall pipe(stdErrPipe)

  if newStdIn != "":
    ccall pipe(stdInPipe)

  let pid = fork()
  if pid != 0:
    ccall close(stdOutPipe[1])
    ccall close(stdErrPipe[1])
    if newStdIn != "":
      ccall close(stdInPipe[0])
      if not fWriteData(stdInPipe[1], newStdIn):
        stdout.write("error: Write to pipe failed: " & $(strerror(errno)) &
          "\n")
      ccall close(stdInPipe[1])

    result = readAllOutput(pid, stdoutPipe[0], stdErrPipe[0], timeoutUsec)
    ccall close(stdOutPipe[0])
    ccall close(stdErrPipe[0])
  else:
    let cargs = allocCStringArray(@[exe] & args)
    if newStdIn != "":
      ccall close(stdInPipe[1])
      discard dup2(stdInPipe[0], 0)
      ccall close(stdInPipe[0])
    else:
      let nullfd = open("/dev/null", O_RDONLY)
      discard dup2(nullfd, 0)

    ccall close(stdOutPipe[0])
    ccall close(stdErrPipe[0])
    discard dup2(stdOutPipe[1], 1)
    discard dup2(stdErrPipe[1], 2)
    ccall close(stdOutPipe[1])
    ccall close(stdErrPipe[1])
    ccall(execv(cstring(exe), cargs), -1)

    stdout.write("error: " & exe & ": command not found\n")
    quit(-1)

proc interactiveProxy*(pid: Pid, args: string): ExecOutput =
  # TODO: non-blocking stdin

  var
    selectSet: TFdSet
    stat_ptr:  cint
    buf:       array[0 .. 4096, byte]

  FD_ZERO(selectSet)

  when false: # while true
    FD_SET(0,         selectSet)
    FD_SET(substdout, selectSet)
    FD_SET(substderr, selectSet)

    if passToChildStdin != "":
      discard fWriteData(substdin, passToChildStdIn)

    case select(3, addr selectSet, nil, nil, nil)
    of 0:
      let res = waitpid(pid, stat_ptr, WNOHANG)
      if res != -1:
        break
      else:
        raise newException(IOError, "Error waiting for output")
    else:
      if FD_ISSET(0, selectSet) != 0:
        let readFromStdin = oneReadFromFd(0)
        discard fWriteData(substdin, readFromStdIn)
      if FD_ISSET(substdout, selectSet) != 0:
        let readFromSubOut = oneReadFromFd(substdout)
        if showOut:
          discard fWriteData(1, readFromSubOut)
        if captureOut:
          result.stdout &= readFromSubOut
      if FD_ISSET(substderr, selectSet) != 0:
        let readFromSubErr = oneReadFromFd(substderr)
        if showErr:
          discard fWriteData(2, readFromSubErr)
        if captureErr:
          result.stderr &= readFromSubErr

  when false:
    # Dedent 2
    let
      readFromSubOut = oneReadFromFd(substdout)
      readFromSubErr = oneReadFromFd(substderr)

    if showOut:
      discard fWriteData(1, readFromSubOut)
    if captureOut:
      result.stdout &= readFromSubOut
    if showErr:
      discard fWriteData(2, readFromSubErr)
      result.stderr &= readFromSubErr

    result.exitCode = int(WEXITSTATUS(stat_ptr))

proc runInteractiveCmd*(exe: string, args: seq[string], passToChildStdin = "") =
  let (pid, fd, ttyname) = spawnPty(exe, args)
  #interactiveProxy(pid, fd, passToChildStdin)

template getStdout*(o: ExecOutput): string = o.stdout
template getStderr*(o: ExecOutput): string = o.stderr
template getExit*(o: ExecOutput): int      = o.exitCode

proc getPasswordViaTty*(): string {.discardable.} =
  if isatty(0) == 0:
    return ""

  var pw = getpass(cstring("Enter password for decrypting the private key: "))

  result = $(pw)

  for i in 0 ..< len(pw):
    pw[i] = char(0)

proc delByValue*[T](s: var seq[T], x: T): bool {.discardable.} =
  let ix = s.find(x)
  if ix == -1:
    return false

  s.delete(ix)
  return true
