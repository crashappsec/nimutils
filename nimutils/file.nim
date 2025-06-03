## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import std/[os, posix, strutils, posix_utils, sets, options]

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
    ## Returns the proper location of the running executable on disk,
    ## resolving any file system links.
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
else:
  proc getMyAppPath*(): string {.exportc.} =
    ## Returns the proper location of the running executable on disk,
    ## resolving any file system links.
    betterGetAppFileName()

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
  ## path. The Nim os utilities don't do the tilde expansion, for
  ## some unfathomable reasons.

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
  ## A wrapper around readFile that returns an empty string if a file
  ## cannot be read.
  try:
    return readFile(fname)
  except:
    return ""

proc tryToWriteFile*(fname: string, contents: string): bool =
  ## A wrapper around writeFile that returns `true` if the file was
  ## successfully written, and `false` otherwise.
  try:
    writeFile(fname, contents)
    return true
  except:
    return false

proc tryToCopyFile*(fname: string, dst: string): bool =
  ## A wrapper around copyFile that returns `true` if the file was
  ## successfully copied, and `false` otherwise.

  try:
    copyFile(fname, dst)
    return true
  except:
    return false

template withWorkingDir*(dir: string, code: untyped) =
  ## Changes the working directory of a process to the given
  ## directory, thens runs a block of code.
  ##
  ## When the code block is exited in any way, the original working
  ## directory is restored.
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
  ## Test a posix stat object to see if it represents a regulat file.
  (info.st_mode and S_IFMT) == S_IFREG

template hasUserExeBit*(info: Stat): bool =
  ## Test a stat object to see if it's user-executable.
  ## See `isExecutable()` for more complete testing.
  (info.st_mode and S_IXUSR) != 0

template hasGroupExeBit*(info: Stat): bool =
  ## Test a stat object to see if it's group-executable.
  ## See `isExecutable()` for more complete testing.
  (info.st_mode and S_IXGRP) != 0

template hasOtherExeBit*(info: Stat): bool =
  ## Test a stat object to see if it's executable by others.
  ## See `isExecutable()` for more complete testing.
  (info.st_mode and S_IXOTH) != 0

template hasAnyExeBit*(info: Stat): bool =
  ## Test for any of the executable bits being set.
  ## See `isExecutable()` for more complete testing.
  (info.st_mode and S_IXALL) != 0

proc isExecutable*(path: string): bool =
  ## Tests to see if the current process has permissions to run the
  ## file at the given location, and that the file is a valid
  ## executable.
  ##
  ## Note that, since this operates on a path instead of a file
  ## descriptor, there could be a TOCTOU bug. However, you'll learn
  ## about that when you then try to execute, so not the end of the
  ## world!
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
  ## This looks for valid executables of the given name that the
  ## current process has permission to execute. Generally, when
  ## multiple items are returned, you should want to run the first
  ## returned item (which you can do via `findExePath()`). However,
  ## this gives you the option to fall back on other executables if
  ## something goes wrong (if they're present, of course).
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
  ## Note that we don't check for all possible issues that could cause
  ## something not to run, and there's the chance of the executable
  ## going away before we try to run it.
  ##
  ## The point is, the caller should anticipate failure.
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
    let path =
      try:
        resolvePath(item)
      except:
        # most likely running in limited env and cant resolve "~"
        continue
    if me == targetName and path == mydir: continue # Don't ever find ourself.
    let potential = joinPath(path, targetName)
    if potential.isExecutable():
      result.add(potential)

proc findExePath*(cmdName:    string,
                  extraPaths: seq[string] = @[],
                  usePath                 = true): string =
  ## This looks for valid executables of the given name that the
  ## current process has permission to execute. It returns the first
  ## matching executable, using the priority rulles described in
  ## `findAllExePaths()`.
  ##
  ## If no executables are found, this returns the empty string.

  let options = cmdName.findAllExePaths(extraPaths, usePath)
  if len(options) != 0:
    return options[0]

let PATH_MAX {.importc, header: "<stdio.h>".}: int

proc expandLink(s: string): tuple[
  name:    string,
  srcKind: PathComponent,
  dstKind: PathComponent,
] =
  ## A wrapper for the posix `readlink` call that also resolves any
  ## relative paths in the result.
  var path = s
  let kind = getFileInfo(path, followSymlink = false).kind
  while true:
    let buf = cast[cstring](alloc0(PATH_MAX))
    try:
      let n = readlink(cstring(path), buf, PATH_MAX)
      if n < 0:
        raiseOSError(osLastError())
      let read = $buf
      path = resolvePath(
        if read.isAbsolute():
          read
        else:
          joinPath(path.parentDir(), read)
      )
      let finfo = getFileInfo(path, followSymLink = false)
      case finfo.kind
      of pcLinkToFile, pcLinkToDir:
        continue # keep resolving nested symlinks
      else:
        return (path, kind, finfo.kind)
    finally:
      dealloc(buf)
  raise newException(OSError, s & ": could not expand symlink to valid file or dir")

proc startsWithAnyOf(s: string, ignoreStartsWith: openArray[string]): bool =
  for i in ignoreStartsWith:
    if s.startsWith(i):
      return true
  return false

proc popLeft[T](s: var OrderedSet[T]): T =
  for i in s:
    s.excl(i)
    return i

type
  FsRef* = tuple
    device: Dev
    inode: Ino

  PathRef* = ref object
    name*:  string
    kind*:  PathComponent
    fsRef*: FsRef

  PathInfo* = ref object
    linkInfo*: PathRef ## src symlink info
    dstInfo*:  PathRef ## dst symlink info
    info*:     PathRef ## info about path - either src or dst depending on PathBehavior

  PathBehavior* = enum
    Ignore, Yield, Follow

proc name*(p: PathInfo): string =
  return p.info.name

proc kind*(p: PathInfo): PathComponent =
  return p.info.kind

proc fsRef*(p: PathInfo): FsRef =
  return p.info.fsRef

proc isSymlink*(p: PathInfo): bool =
  return p.linkInfo != nil

proc linkOrInfo*(p: PathInfo): PathRef =
  if p.linkInfo != nil:
    return p.linkInfo
  return p.info

proc asLink(p: PathInfo): PathInfo =
  if p.isSymlink():
    return PathInfo(
      linkInfo: p.linkInfo,
      dstInfo:  p.dstInfo,
      info:     p.linkInfo,
    )
  return p

proc maybeGetPathInfo(fullPath:         string,
                      ignoreStartsWith: openArray[string] = [],
                      ): Option[PathInfo] =
  var stats: Stat
  if lstat(cstring(fullPath), stats) >= 0:
    if S_ISLNK(stats.st_mode):
      try:
        var linkstats: Stat
        let (expanded, srcKind, dstKind) = fullPath.expandLink()
        if not expanded.startsWithAnyOf(ignoreStartsWith):
          if lstat(cstring(expanded), linkStats) >= 0:
            let
              dst = PathRef(
                name: expanded,
                kind: dstKind,
                fsRef: (
                  linkstats.st_dev,
                  linkstats.st_ino,
                ),
              )
              src = PathRef(
                name: fullPath,
                kind: srcKind,
                fsRef: (
                  stats.st_dev,
                  stats.st_ino,
                ),
              )
            return some(PathInfo(
              linkInfo: src,
              dstInfo:  dst,
              info:     dst,
            ))
      except:
        discard
    elif S_ISREG(stats.st_mode):
      if not fullPath.startsWithAnyOf(ignoreStartsWith):
        let dst = PathRef(
          name: fullPath,
          kind: pcFile,
          fsRef: (
            stats.st_dev,
            stats.st_ino,
          ),
        )
        return some(PathInfo(
          dstInfo: dst,
          info:    dst,
        ))
    elif S_ISDIR(stats.st_mode):
      if not fullPath.startsWithAnyOf(ignoreStartsWith):
        let dst = PathRef(
          name: fullPath,
          kind: pcDir,
          fsRef: (
            stats.st_dev,
            stats.st_ino,
          ),
        )
        return some(PathInfo(
          dstInfo: dst,
          info:    dst,
        ))
    else:
      discard # Skip sockets, fifos, ...
  return none(PathInfo)

let systemIgnoreStartsWithPaths* = @[
  "/proc/",
  "/dev/",
  "/boot/",
  "/sys/",
  # probably biggest folders in /sys are:
  # "/sys/devices",
  # "/sys/kernel",
  # "/sys/module",
]

iterator getAllFileNames*(path:              string,
                          recurse          = true,
                          files            = Yield,
                          fileLinks        = Follow,
                          dirs             = Ignore,
                          dirLinks         = Ignore,
                          ignoreStartsWith = systemIgnoreStartsWithPaths,
                          ): PathInfo =
  ## This is a slightly more sane API for scanning for file names than the
  ## one provided in the nim standard API, primarily in that it is a single
  ## consistent API whether you scan recursively or not.
  var
    seenDirs = initHashSet[(Dev, Ino)]()
    toLook   = initOrderedSet[string]()
  toLook.incl(path)

  while len(toLook) > 0:
    let nameOpt = maybeGetPathInfo(
      toLook.popLeft(),
      ignoreStartsWith = ignoreStartsWith,
    )
    if nameOpt.isNone():
      continue
    let name = nameOpt.get()
    if name.fsRef in seenDirs:
      continue

    let kind = name.linkOrInfo.kind
    case kind
    of pcFile, pcLinkToFile:
      case (
        if kind == pcFile:
          files
        else:
          fileLinks
      )
      of Yield:
        yield name.asLink()
      of Follow:
        yield name
      else:
        discard

    of pcDir, pcLinkToDir:
      seenDirs.incl(name.fsRef)

      case (
        if kind == pcDir:
          dirs
        else:
          dirLinks
      )
      of Yield:
        yield name.asLink()
      of Follow:
        yield name
      else:
        discard

      let recurseDir =
        if kind == pcDir:
          recurse
        else:
          # only recurse symlink folders when symlinks are followed
          recurse and dirLinks == Follow

      if recurseDir:
        var dirent = opendir(cstring(name.name))
        try:
          if dirent == nil:
            continue
          while true:
            var oneentry = readdir(dirent)
            if oneentry == nil:
              break
            var filename = $cast[cstring](addr oneentry.d_name)
            if filename in [".", ".."]:
              continue
            let fullpath = joinPath(name.name, filename)
            toLook.incl(fullpath)
        finally:
          discard closedir(dirent)
