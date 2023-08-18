import os, streams, misc, posix
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

extern bool read_data(int fd, void *buf, size_t nbytes);
extern bool write_data(int fd, NCSTRING buf, NI nbytes);

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

proc writeViaLockFile*(loc:    string,
                       output: string,
                       release     = true,
                       maxAttempts = 5,
                      ): bool =
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
    resolvedLoc = resolvePath(loc)
    dstParts    = splitPath(resolvedLoc)
    lockFile    = joinPath(dstParts.head, "." & dstParts.tail)

  if lockFile.obtainLockFile(maxAttempts):
    try:
      let f = newFileStream(resolvedLoc, fmWrite)
      if f == nil:
        return false
      f.write(output)
      f.close()
      return true
    finally:
      if release:
        try:
          removeFile(lockFile)
        except:
          discard
  else:
    return true

proc readViaLockFile*(loc: string, release = true, maxAttempts = 5): string =
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
    resolvedLoc = resolvePath(loc)
    dstParts    = splitPath(resolvedLoc)
    lockFile    = joinPath(dstParts.head, "." & dstParts.tail)

  if lockFile.obtainLockFile(maxAttempts):
    try:
      let f = newFileStream(resolvedLoc)
      if f == nil:
        raise newException(ValueError, "Couldn't open file")
      result = f.readAll()
      f.close()
      return
    finally:
      if release:
        try:
          removeFile(lockFile)
        except:
          discard
  else:
    raise newException(IOError, "Couldn't obtain lock file")

proc releaseLockFile*(loc: string) =
  let
    resolvedLoc = resolvePath(loc)
    dstParts    = splitPath(resolvedLoc)
    lockFile    = joinPath(dstParts.head, "." & dstParts.tail)

  removeFile(lockFile)
