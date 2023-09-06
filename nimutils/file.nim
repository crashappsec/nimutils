## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import os, posix, misc, strutils, posix_utils

proc getMyAppPath(): string {.importc.}

{.emit: """
// I already had this stuff sitting around, and haven't taken the time to
// push it down to nim (I started to w/ `readAll()` but decided it wasn't
// a good use of time.

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
write_data(int fd, NCSTRING buf, NI nbytes) {
    size_t  towrite, written = 0;
    ssize_t result;

    do {
        if (nbytes - written > SSIZE_MAX) {
            towrite = SSIZE_MAX;
        }
        else {
            towrite = nbytes - written;
        }
        if ((result = write(fd, buf + written, towrite)) >= 0) {
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

proc oneReadFromFd*(fd: cint): string =
  var
    buf: array[0 .. 4096, byte]

  while true:
    let n = read(fd, addr buf, 4096)
    if n > 0:
      return bytesToString(buf[0 ..< n])
    elif n == 0:
      return ""
    elif errno != EINTR:
      raise newException(IoError, $(strerror(errno)))

proc readAllFromFd*(fd: cint): string =

  while true:
    let val = fd.oneReadFromFd()

    if val == "":
      return result

    result &= val

proc fReadData*(fd: cint, buf: openarray[char]): bool {.importc: "read_data."}
proc fWriteData*(fd: cint, buf: openarray[char]): bool {.importc: "write_data".}
proc fWriteData*(fd: cint, s: string): bool =
  # toOpenArray does not convert the null terminator.
  return fWriteData(fd, s.toOpenArray(0, s.len() - 1))

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

proc tildeExpand(s: string): string {.inline.} =
  var homedir = getHomeDir()

  while homedir[^1] == '/':
    homedir.setLen(len(homedir) - 1)
  if s == "":
    return homedir

  if s.startsWith("/"):
    return homedir & s

  let parentFolder = homedir.splitPath().head

  return joinPath(parentFolder, s)

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

proc tryToLoadFile*(fname: string): string =
  try:
    return readFile(fname)
  except:
    return ""

proc tryToWriteFile*(fname: string, contents: string): bool =
  try:
    writeFile(fname, contents)
    return true
  except:
    return false

proc tryToCopyFile*(fname: string, dst: string): bool =
  try:
    copyFile(fname, dst)
    return true
  except:
    return false

template withWorkingDir*(dir: string, code: untyped) =
  let
    toRestore = getCurrentDir()

  try:
    setCurrentDir(dir)
    code
  finally:
    setCurrentDir(toRestore)

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
  dup2(filedes[0], 0);
  return filedes[1];
}

""".}

proc cReplaceStdinWithPipe*(): cint {.importc: "c_replace_stdin_with_pipe".}
