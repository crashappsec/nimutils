## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022-2023, Crash Override, Inc.
##
import macros, times, os, strutils, osproc, posix, posix_utils

# The name flatten conflicts with a method in the options module.
from options import get, Option, isSome, isNone
export get, Option, isSome, isNone

{.warning[UnusedImport]: off.}


{.emit: """
#include <sys/types.h>
#include <unistd.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <stdbool.h>

bool
read_data(int fd, void *buf, size_t nbytes) {
    size_t  toread, nread = 0;
    ssize_t result;

    do {
         if (nbytes - nread > SSIZE_MAX) {
             toread = SSIZE_MAX;
         }
         else {
             toread = nbytes - nread;
         }
         if ((result = read(fd, (char *)buf + nread, toread)) >= 0) {
           nread += result;
         }
         else if (errno != EINTR) {
           return false;
         }
       }
    while (nread < nbytes);

    return true;
}

bool
write_data(int fd, const void *buf, size_t nbytes) {
    size_t  towrite, written = 0;
    ssize_t result;

    do {
        if (nbytes - written > SSIZE_MAX) {
            towrite = SSIZE_MAX;
        }
        else {
            towrite = nbytes - written;
        }
        if ((result = write(fd, (const char *)buf + written, towrite)) >= 0) {
            written += result;
        }
        else if (errno != EINTR) {
            return false;
        }
    }
    while (written < nbytes);

    return true;
 }
""".}

proc fReadData*(fd: cint, buf: openarray[char]): bool {.importc: "read_data."}
proc fWriteData*(fd: cint, buf: openarray[char]): bool {.importc: "write_data".}
proc fWriteData*(fd: cint, s: string): bool =
  return fWriteData(fd, s.toOpenArray(0, s.len()))

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
  proc getMyAppPath*(): string =
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
  template getMyAppPath*(): string = betterGetAppFileName()

template unreachable*() =
  let info = instantiationInfo()

  ## We use this to be explicit about case statements that are
  ## necessary to cover all cases, but should be impossible to
  ## execute.  That way, if they do execute, we know we made a
  ## mistake.
  try:
    echo "Reached code that was supposed to be unreachable.  Stack trace:"
    echo "REACHED UNREACHABLE CODE AT: " & info.filename & ":" & $(info.line)
    echo getStackTrace()
    doAssert(false, "Reached code the programmer thought was unreachable :(")
  finally:
    discard

template dirWalk*(recursive: bool, body: untyped) =
  ## This is a helper function that helps one unify code when a
  ## program might need to do either a single dir walk or a recursive
  ## walk.  Specifically, depending on whether you pass in the
  ## recursive flag or not, this will call either os.walkDirRec or
  ## os.walkDir.  In either case, it injects a variable named `item`
  ## into the calling scope.
  var item {.inject.}: string

  when recursive:
    for i in walkDirRec(path):
      item = i
      body
  else:
    for i in walkDir(path):
      item = i.path
      body

template unixTimeInMS*(): uint64 =
  ## Return the current Unix epoch in miliseconds.  That is, this
  ## function will return the number of miliseconds since Jan 1, 1970
  ## (GMT).

  # One oddity of NIM is that, if I put a decimal point here to make
  # it a float, I *have* to put a trailing zero. That in and of itself
  # is fine, but the error message when I don't sucks: 'Error: Invalid
  # indentation'
  const toMS = 1000.0
  uint64(epochTime() * toMS)

proc tildeExpand(s: string): string {.inline.} =
  var homedir = os.getHomeDir()

  while homedir[^1] == '/':
    homedir.setLen(len(homedir) - 1)
  if s == "":
    return homedir

  if s.startsWith("/"):
    return homedir & s

  let parentFolder = homedir.splitPath().head

  return os.joinPath(parentFolder, s)

proc resolvePath*(inpath: string): string =
  ## This first does tilde expansion (e.g., ~/file or ~viega/file),
  ## and then normalizes the path, and expresses it as an absolute
  ## path.  The Nim os utilities don't do the tilde expansion.

  # First, resolve tildes, as Nim doesn't seem to have an API call to
  # do that for us.
  var cur = inpath

  if inpath == "": return getCurrentDir()
  while cur[^1] == '/':
    if len(cur) == 1:
      return "/"
    cur.setLen(len(cur) - 1)
  if cur[0] == '~':
    let ix = cur.find('/')
    if ix == -1:
      return tildeExpand(cur[1 .. ^1])
    cur = joinPath(tildeExpand(cur[1 .. ix]), cur[ix+1 .. ^1])
  return cur.normalizedPath().absolutePath()


proc clzll*(argc: uint): cint {.cdecl, importc: "__builtin_clzll".}
## Call the 64-bit count-leading-zeros builtin.

proc log2*(s: uint): int = 63 - clzll(s)
## Calculate log base 2, truncating.

type
  Flattenable[T] = concept x
    (x is seq) or (x is array)

proc flatten*[T](arr: Flattenable, res: var seq[T]) =
  ## Given arbitrarily nested arrays, flatten into a single array.
  ## Passing a pre-allocated value into the var parameter will
  ## generally remove the need to specify T.
  for entry in arr.items:
    when typeof(arr[0]) is T:
      res.add(entry)
    elif (typeof(arr[0]) is seq) or (typeof(arr[0]) is array):
      flatten(entry, res)
    else:
      static:
        error "Cannot flatten " & $(typeof(arr[0])) & " (expected " & $(T) & ")"

proc flatten*[T](arr: Flattenable): seq[T] =
  ## Given arbitrarily nested arrays, flatten into a single array.
  ## Generally, you will need to specify the type parameter;
  ## result types don't get inferred in Nim.
  result = newSeq[T]()
  flatten[T](arr, result)

template `?`*(x: typedesc): typedesc = Option[x]
template `?`*[T](x: Option[T]): bool = x.isSome()

when defined(autoOption):
  converter toTOpt*[T](x: T): Option[T] =
    some(x)

template getOrElse*[T](x: Option[T], y: T): T =
  ## When writing x.get(12), I think it's confusing.  This uses a
  ## better name.
  get(x, y)

when defined(posix):
  template unprivileged*(code: untyped) =
    ## Run a block of code under the user's UID. Ie, make sure that if the
    ## euid is 0, the code runs with the user's UID, not 0.
    let
      uid = getuid()
      euid = geteuid()
      gid = getgid()
      egid = getegid()
    if (uid != euid) or (gid != egid):
      discard seteuid(uid)
      discard setegid(gid)
    code
    if (uid != euid): discard seteuid(euid)
    if (gid != egid): discard setegid(egid)
else:
  template unprivileged*(code: untyped) =
    code

proc copy*[T](data: sink T): ref T =
  new result
  result[] = data

proc getpass*(prompt: cstring) : cstring {.header: "<unistd.h>",
                                           header: "<pwd.h>",
                                          importc: "getpass".}

const
  S_IFMT  = 0xf000
  S_IFREG = 0x8000
  S_IXUSR = 0x0040
  S_IXGRP = 0x0008
  S_IXOTH = 0x0001
  S_IXALL = S_IXUSR or S_IXGRP or S_IXOTH

template isFile*(info: Stat): bool =
  (info.st_mode and S_IFMT) == S_IFREG

template hasUserExeBit*(info: Stat): bool =
  (info.st_mode and S_IXUSR) != 0

template hasGroupExeBit*(info: Stat): bool =
  (info.st_mode and S_IXGRP) != 0

template hasOtherExeBit*(info: Stat): bool =
  (info.st_mode and S_IXOTH) != 0

template hasAnyExeBit*(info: Stat): bool =
  (info.st_mode and S_IXALL) != 0

proc isExecutable*(path: string): bool =
  try:
    let info = stat(path)

    if not info.isFile():
      return false

    if not info.hasAnyExeBit():
      return false

    let myeuid = geteuid()

    if myeuid == 0:
      return true

    if info.st_uid == myeuid:
      return info.hasUserExeBit()

    var groupinfo: array[0 .. 255, Gid]
    let numGroups = getgroups(255, addr groupinfo)

    if info.st_gid in groupinfo[0 ..< numGroups]:
      return info.hasGroupExeBit()

    return info.hasOtherExeBit()

  except:
    return false # Couldn't stat.

proc findAllExePaths*(cmdName:    string,
                      extraPaths: seq[string] = @[],
                      usePath                 = true): seq[string] =
  ##
  ## The priority here is to the passed command name, but if and only
  ## if it is a path; we're assuming that they want to try to run
  ## something in a particular location.  Generally, we're disallowing
  ## this in config files, but it's here just in case.
  ##
  ## Our second priority is to the the extraPaths array, which is
  ## basically a programmer supplied PATH, in case the right place
  ## doesn't get picked up in our environment.
  ##
  ## If all else fails, we search the PATH environment variable.
  ##
  ## Note that we don't check for permissions problems (including
  ## not-executable), and we do not open the file, so there's the
  ## chance of the executable going away before we try to run it.
  ##
  ## The point is, the caller should eanticipate failure.
  let
    (mydir, me) = getMyAppPath().splitPath()
  var
    targetName  = cmdName
    allPaths    = extraPaths

  if usePath:
    allPaths &= getEnv("PATH").split(":")

  if '/' in cmdName:
    let tup    = resolvePath(cmdName).splitPath()
    targetName = tup.tail
    allPaths   = @[tup.head] & allPaths

  for item in allPaths:
    let path = resolvePath(item)
    if me == targetName and path == mydir: continue # Don't ever find ourself.
    let potential = joinPath(path, targetName)
    if potential.isExecutable():
      result.add(potential)

{.emit: """
#include <unistd.h>

int c_replace_stdin_with_pipe() {
  int filedes[2];

  pipe(filedes);
  dup2(filedes, 0);
  return filedes[1];
}

""".}

proc cReplaceStdinWithPipe*(): cint {.importc: "c_replace_stdin_with_pipe".}

template runCmdGetOutput*(exe: string, args: seq[string]): string =
  execProcess(exe, args = args, options = {})

type ExecOutput* = object
    stdout*:   string
    stderr*:   string
    exitCode*: int

proc bytesToString*(bytes: openarray[byte]): string =
  result = newString(bytes.len)
  copyMem(result[0].addr, bytes[0].unsafeAddr, bytes.len)

proc readAllFromFd*(fd: cint): string =
  var
    buf: array[0 .. 4096, byte]

  while true:
    let n = read(fd, addr buf, 4096)
    if n >= 0:
      let s  = bytesToString(buf)
      result = result & s
      if n == 0:
        return
    else:
      if errno != EINTR:
        raise newException(IoError, $(strerror(errno)))

template ccall*(code: untyped, success = 0) =
  let ret = code

  if ret != success:
    error($(strerror(ret)))
    quit(1)

proc runCmdGetEverything*(exe:      string,
                          args:     seq[string],
                          newStdIn: string       = ""): ExecOutput =
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

    var stat_ptr: cint
    discard waitpid(pid, stat_ptr, 0)
    result.exitCode = int(WEXITSTATUS(stat_ptr))
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
    error("Cannot read password securely when not run from a tty.")
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
