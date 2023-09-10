## Process-related utilities.
##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import misc, strutils, posix, file, os

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


proc interactiveProxy*(pid: Pid, substdin, substdout, substderr: cint,
                       showOut, captureOut, showErr, captureErr: bool):
                         ExecOutput =
  # TODO: non-blocking stdin

  var
    selectSet: TFdSet
    stat_ptr:  cint
    buf:       array[0 .. 4096, byte]

  FD_ZERO(selectSet)

  while true:
    FD_SET(0,         selectSet)
    FD_SET(substdout, selectSet)
    FD_SET(substderr, selectSet)

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

proc runInteractiveCmd*(exe: string, args: seq[string], captureOut = true,
                        showOut = true, captureErr = true, showErr = true):
                          ExecOutput =
  var
    stdInPipe:  array[0 .. 1, cint]
    stdOutPipe: array[0 .. 1, cint]
    stdErrPipe: array[0 .. 1, cint]

  ccall pipe(stdInPipe)
  ccall pipe(stdOutPipe)
  ccall pipe(stdErrPipe)

  let pid = fork()
  if pid != 0:
    ccall close(stdInPipe[0])
    ccall close(stdOutPipe[1])
    ccall close(stdErrPipe[1])
    result = interactiveProxy(pid, stdInPipe[1], stdOutPipe[0], stdErrPipe[0],
                              showOut, captureOut, showErr, captureErr)
    ccall close(stdInPipe[1])
    ccall close(stdOutPipe[0])
    ccall close(stdErrPipe[0])
  else:
    let cargs = allocCStringArray(@[exe] & args)
    discard dup2(stdInPipe[0], 0)
    discard dup2(stdOutPipe[1], 1)
    discard dup2(stdErrPipe[1], 2)
    ccall close(stdInPipe[1])
    ccall close(stdOutPipe[0])
    ccall close(stdErrPipe[0])
    ccall(execv(cstring(exe), cargs), -1)

    stdout.write("error: " & exe & ": command not found\n")
    quit(-1)

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
