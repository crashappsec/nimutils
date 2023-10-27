## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import os, posix, strutils, posix_utils

proc getMyAppPath(): string {.importc.}

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
#include <stdio.h>

static int
get_path_max()
{
  return PATH_MAX;
}

static void
do_read_link(const char *filename, char *buf) {
  readlink(filename, buf, PATH_MAX);
}
""".}

proc do_read_link(s: cstring, p: pointer): void {.cdecl,importc,nodecl.}
proc get_path_max*(): cint {.cdecl,importc,nodecl.}

proc readLink*(s: string): string =
  var v = newStringOfCap(int(get_path_max()));
  do_read_link(cstring(s), addr s[0])
  result = resolvePath(v)

proc getAllFileNames*(dir: string,
                      recurse         = true,
                      yieldFileLinks  = false,
                      followFileLinks = false,
                      yieldDirs       = false,
                      followDirLinks  = false): seq[string] =
  var kind: PathComponent

  if yieldFileLinks and followFileLinks:
    raise newException(ValueError, "Do not specify yieldFileLinks and " &
      "followFileLinks in one call.")

  let resolved = resolvePath(dir)

  if resolved.startswith("/proc") or resolved.startswith("/dev"):
    return @[]

  try:
    let info = getFileInfo(dir, followSymLink = false)

    kind = info.kind
  except:
    return @[]

  case kind
    of pcFile:
      return @[dir]
    of pcLinkToFile:
      if yieldFileLinks:
        return @[dir]
      elif followFileLinks:
        return @[readlink(dir)]
      else:
        return @[]
    else:
      discard

  var dirent = opendir(dir)
  var subdirList: seq[string]

  if dirent == nil:
    return

  while true:
    var oneentry = readdir(dirent)
    if oneentry == nil:
      break
    var filename = $cast[cstring](addr oneentry.d_name)
    if filename in [".", ".."]:
      continue
    let fullpath = joinPath(dir, filename)
    var statbuf: Stat
    if lstat(fullPath, statbuf) < 0:
      continue
    elif S_ISLNK(statbuf.st_mode):
      if dirExists(fullpath):
        if recurse and followDirLinks:
          subdirList.add(fullPath)
        if yieldDirs:
          result.add(fullPath)
      else:
        if yieldFileLinks:
          result.add(fullPath)
        elif followFileLinks:
          var
            newPath = fullPath
            i       = 40
          while i != 0:
            newPath = readlink(newPath)
            let finfo = getFileInfo(newPath, followSymLink = false).kind
            if finfo != pcLinkToFile:
              break
            i -= 0
          if i != 0:
            result.add(newPath)
    elif S_ISREG(statbuf.st_mode):
      result.add(fullPath)
    elif S_ISDIR(statbuf.st_mode):
      if recurse:
        subdirList.add(fullpath)
        if yieldDirs:
          result.add(fullpath)
    else:
      continue # Skip sockets, fifos, ...

  discard closedir(dirent)
  for item in subdirList:
    result &= item.getAllFileNames()
