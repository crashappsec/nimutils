import os, streams, misc
{.emit: """
bool
lock_file(char *lfpath, int max_attempts) {
    int   attempt, fd, result;
    pid_t pid;


    for (attempt = 0;  attempt < max_attempts;  attempt++) {
        if ((fd = open(lfpath, O_RDWR | O_CREAT | O_EXCL, S_IRWXU)) == -1) {
            if (errno != EEXIST) {
                return false;
            }
            if ((fd = open(lfpath, O_RDONLY)) == -1) {
                return false;
            }

            result = read_data(fd, &pid, sizeof(pid));
            close(fd);
            if (result) {
                if (pid == getpid()) {
                    return 1;
                }
                if (kill(pid, 0) == -1) {
                    if (errno != ESRCH) {
                        return false;
                    }
                    attempt--;
                    unlink(lfpath);
                    continue;
                }
            }
            sleep(1);
            continue;
        }

        pid = getpid();
        if (!write_data(fd, &pid, sizeof(pid))) {
            close(fd);
            return false;
        }
        close(fd);
        attempt--;
        }

    /* If we've made it to here, three attempts have been made and the
     * lock could not be obtained. Return an error code indicating
     * failure to obtain the requested lock.
     */
    return false;
}
""".}

proc fLockFile*(fname: cstring, maxAttempts: cint):
              bool {.importc: "lock_file".}
proc obtainLockFile*(fname: string, maxAttempts = 5): bool {.inline.} =
  return fLockFile(cstring(fname), cint(maxAttempts))

proc writeViaLockFile*(loc: string, output: string): bool =
  let
    resolvedLoc = resolvePath(loc)
    dstParts    = splitPath(resolvedLoc)
    lockFile    = joinPath(dstParts.head, "." & dstParts.tail)

  if lockFile.obtainLockFile():
    try:
      let f = newFileStream(resolvedLoc, fmWrite)
      if f == nil:
        return false
      f.write(output)
      f.close()
      return true
    finally:
      try:
        removeFile(lockFile)
      except:
        discard
  else:
    return true

proc readViaLockFile*(loc: string): string =
  let
    resolvedLoc = resolvePath(loc)
    dstParts    = splitPath(resolvedLoc)
    lockFile    = joinPath(dstParts.head, "." & dstParts.tail)

  if lockFile.obtainLockFile():
    try:
      let f = newFileStream(resolvedLoc)
      if f == nil:
        raise newException(IOError, "Couldn't open file")
      result = f.readAll()
      f.close()
      return
    finally:
      try:
        removeFile(lockFile)
      except:
        discard
  else:
    raise newException(IOError, "Couldn't obtain lock file")
