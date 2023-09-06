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

proc runCmdGetEverything*(exe:      string,
                          args:     seq[string],
                          newStdIn: string       = "",
                          timeoutMs              = 1000): ExecOutput =
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

    try:
      result.exitCode = waitpidWithTimeout(pid, timeoutMs)
    except:
      raise newException(IoError,
       "Subprocess failed to exit exit after " & $(timeoutMs) & "ms .\n" &
         "proces = " & exe & " " & args.join(" "))

    result.stdout   = readAllFromFd(stdOutPipe[0])
    result.stderr   = readAllFromFd(stdErrPipe[0])
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
