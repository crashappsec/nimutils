## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import os, file, posix, misc, subproc


proc flock*(fd: cint, flags: cint): cint {.discardable, importc,
                                           header: "<sys/file.h>".}
proc fdopen*(fd: cint, mode: cstring): File {.importc, header: "<stdio.h>".}

type OsErrRef = ref OsError

proc obtainLockFile*(fname: string, writeLock = false, timeout: int64 = 5000,
                                                oflags: cint = 0): cint =
  var
    lockflags: cint
    openflags = oflags
    fullpath  = fname.resolvePath()

  if timeout >= 0:
    lockflags = 4
  if writeLock:
    lockflags = lockflags or 2
    if (openflags and 3) == 0:
      openflags = openflags or 2 # Go ahead and open RDWR
  else:
    lockflags = lockflags or 1
    openflags = openflags and not 2

  result = open(cstring(fullpath), openflags)

  if result == -1:
    raise OsErrRef(errorCode: errno)
  var
    endtime: uint64 = if timeout < 0:
                        0xffffffffffffffff
                      else:
                        unixTimeInMs() + uint64(timeout)
    sleepdur = 16

  while flock(result, lockflags) != 0:
    if unixTimeInMs() > endTime:
      raise newException(IoError, "Timeout when trying to attain file lock " &
        "for " & fullpath)
    sleep(sleepdur)
    sleepdur = sleepdur shl 1

proc unlockFd*(fd: cint) =
  flock(fd, 8)

proc writeViaLockFile*(loc:    string,
                       output: string,
                       release   = true,
                       timeoutMs = 5000): cint =
  ## This uses an advisory lock to perform a read of the file, and
  ## then releases the lock at the end, unless release == false.
  ##
  ## In that case, call releaseLockFile() passing the original file
  ## name of what you're locking in order to cleanly give up the lock.
  ##
  ## The file is closed after write, but when `release` is false, you
  ## will still hold the lock, until you release explicitly, or the
  ## process ends.

  let
    fd = loc.obtainLockFile(writelock = true, timeout = timeoutMs)

  rawFdWrite(fd, cstring(output), csize_t(output.len()))
  if release:
    fd.unlockFd()
    discard fd.close()
    return 0
  else:
    return fd

proc readViaLockFile*(loc: string, timeoutMs = 5000): string =
  ## This uses an advisory lock to perform a read of the file, and
  ## then releases the lock at the end, unless release == false.
  ##
  ## In that case, call releaseLockFile() passing the original file name
  ## of what you're locking in order to cleanly give up the lock.
  ##
  ## Even if you choose to hold the lock, the file will be closed
  ## after this call. No worries, as long as other processes use this
  ## same API, they will not take the lock as long as your process is
  ## still running and hasn't released it.

  let
    fd = loc.obtainLockFile(timeout = timeoutMs)
    f  = fdopen(fd, "r")

  result = f.readAll()
  fd.unlockFd()

proc unlock*(f: var File) =
  f.getFileHandle().unlockFd()

proc lock*(f: var File, writelock = false, blocking = true) =
  var opts: cint = 0

  if writelock:
    opts = 2
  else:
    opts = 1

  if blocking:
    opts = opts and 4

  flock(f.getFileHandle(), opts)
