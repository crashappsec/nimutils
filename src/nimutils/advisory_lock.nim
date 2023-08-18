import os, streams, misc

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
proc fReadAll*(fd: cint, bufptr: ptr cstring, nbytes: ptr cint):
             bool {.importc: "read_all".}
proc fReadData*(fd: cint, buf: openarray[byte]): bool {.importc: "read_data."}
proc fWriteData*(fd: cint, buf: openarray[byte]): bool {.importc: "write_data".}
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
