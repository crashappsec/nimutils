## Process-related utilities.
##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import misc, strutils, posix, file, os, options

{.emit: """
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <errno.h>
#include <termios.h>
#include <unistd.h>
#include <limits.h>
#include <sys/ioctl.h>
#include <sys/select.h>

#ifdef __APPLE__
#include <util.h>
#endif

// Already in nimutils
extern bool write_data(int fd, char *buf, size_t nbytes);

size_t
read_one(int fd, char *buf, size_t nbytes) {
    size_t  toread, nr = 0;
    ssize_t result;
    size_t  n;

    while(true) {
	n = read(fd, buf, nbytes - 1);

	switch(n) {
	case 0:
	    *buf = 0;
	    return n;
	case -1:
	    if(errno == EINTR) {
		continue;
	    }
	    return -1;
	default:
	    buf[n] = 0;
	    return n;
	}
    }

    return true;
}

/* This is not yet going to handle window size changes.
** Also, should we handle whether to kill() the child if the parent
** disappears? Right now I am not.
**
** Currently, this also doesn't capture the child's stdin or stderr,
** because we do not need them.
*/

#ifdef MIN
#undef MIN
#endif
#define MIN(a,b) ((a) <= (b)) ? (a) : (b)

int
subprocess_comms(int ptyfd, int child_stdin_fd, char *inp, int inlen,
                 int timeout_sec, int timeout_usec)
{
    /* We're guaranteed that, if a fd is cleared for write, we can push up to
     * PIPE_BUF bytes at once.
     *
     * Note that we assume it's never a problem to block on writing to stdout.
     */
    fd_set 	    readset;
    fd_set          writeset;
    fd_set          errset;
    char   	    to_parent[PIPE_BUF+1];
    char            to_child_buf[PIPE_BUF];
    char           *to_child  = &to_child_buf;
    int             to_child_len  = 0;
    int             n; // A temporary
    int             max = ptyfd;
    struct timeval  timeout;
    struct timeval *timeval_ptr = NULL;
    bool            read_available_on_stdin    = false;
    bool            read_available_on_child    = false;
    bool            can_write_to_child_stdin   = false;
    bool            can_write_to_child_tty     = false;
    bool            stopped_due_to_child_death = false;

    if (child_stdin_fd > max) {
      max = child_stdin_fd;
    }

    max++;

    if (timeout_sec >= 0 && timeout_usec >= 0) {
      timeout.tv_sec  =  timeout_sec;
      timeout.tv_usec =  timeout_usec;
      timeval_ptr     = &timeout;
    }

    if (inlen < 0 || child_stdin_fd <= 2 || inp == NULL) {
      // From now on we'll just check this to see if we have anything to pass
      // down to the child's stdin.
      inlen = 0;
    }


    FD_ZERO(&readset);
    FD_ZERO(&writeset);
    FD_ZERO(&errset);
    while (true) {
        FD_SET(0, &errset);        // If the user went away, shut down.
        FD_SET(ptyfd, &errset);    // If the child went away, shut down.

        FD_SET(ptyfd, &readset);

        if (inlen != 0) {
          FD_SET(child_stdin_fd, &writeset);
        }
        if (to_child_len == 0) {
          FD_SET(0, &readset);
        } else {
          FD_SET(ptyfd, &writeset);
        }

	switch (select(max, &readset, &writeset, &errset, timeval_ptr)) {
        case -1:
          if (errno == EINVAL || errno == EBADF) {
            return errno;
          }
          // Else, EINTR or EAGAIN
          exit(-1);
          continue;
	case 0:
            continue;
            // We got the timeout.
            return -2;
	default:
            // First, if we have any error conditions, we bail.
            // If the parent is still around, we'll want to jump to
            // where we do a final read.
            if (FD_ISSET(0, &errset)) {
              FD_CLR(0, &errset);
              // No more user; shut down the pipe to the child.
              close(ptyfd);
              return -1; // There's no point in a final read I think.
            }
            if (FD_ISSET(ptyfd, &errset)) {
              FD_CLR(ptyfd, &errset);
              stopped_due_to_child_death = true;
              goto final_read;
            }

            // Now, let's mark everything that we know is ready.
            if (FD_ISSET(0, &readset)) {
               FD_CLR(0, &readset);
               read_available_on_stdin   = true;
            }
            if (FD_ISSET(ptyfd, &readset)) {
               FD_CLR(ptyfd, &readset);
               read_available_on_child = true;
            }
            if (FD_ISSET(ptyfd, &writeset)) {
               FD_CLR(ptyfd, &writeset);
               can_write_to_child_tty = true;
            }
            if (FD_ISSET(child_stdin_fd, &writeset)) {
               FD_CLR(child_stdin_fd, &writeset);
               can_write_to_child_stdin = true;
            }

            // Cool, now let's test the flags to do whatever work we
            // can do, then clear any flag that let we do work on.

            // This was only ever set if we have data to pass over stdin,
            if (can_write_to_child_stdin) {
              can_write_to_child_stdin = false;

              n = write(child_stdin_fd, inp, MIN(PIPE_BUF, inlen));
              if (n != -1) {
                inp   += n;
                inlen -= n;
                if (inlen <= 0) {
                  close(child_stdin_fd);
                }
              }
              else {
                if (errno != EAGAIN && errno != EINTR) {
                  return -4;
                }
              }
            }

            if (read_available_on_child) {
              read_available_on_child = false;

              n = read(ptyfd, to_parent, PIPE_BUF);
              if (n == 0) {
                break; // EOF, proper child exit.
              }
              if (n == -1) {
                if (errno != EAGAIN && errno != EINTR) {
                  return -4;
                }
              } else {
                to_parent[n] = 0;
                write_data(1, to_parent, n);
              }
            }

            if (read_available_on_stdin && to_child_len == 0) {

               to_child_len = read(0, to_child, PIPE_BUF);
               if (to_child_len == 0) {
                 close(ptyfd);
                 return -3;
               }
               if (to_child_len == -1) {
                 if (errno != EAGAIN && errno != EINTR) {
                  return -4;
                 } else {
                   to_child_len = 0;
                 }
               }
            }
            read_available_on_stdin = false;


            if (can_write_to_child_tty) {
              can_write_to_child_tty = false;

              n = write(ptyfd, to_child, to_child_len);
              if (n != -1) {
                to_child_len -= n;
                to_child     += n;
                if (to_child_len == 0) {
                  to_child = &to_child_buf;
                }
              }
              else {
                if (errno != EAGAIN && errno != EINTR) {
                   return -4;
                }
              }
            }
       }
    }

final_read:
    while ((n = read_one(ptyfd, to_parent, PIPE_BUF - 1)) > 0) {
        to_parent[n] = 0;
        write_data(1, to_parent, n);
    }

    if (stopped_due_to_child_death) {
      return -1;
    }
    return 0;
}

pid_t
spawn_pty(char *path, char *argv[], char *envp[], char *topipe, int len)
{
    struct termios termcap;
    struct termios saved_termcap;
    struct winsize wininfo;
    struct termios *term_ptr = &termcap;
    struct winsize *win_ptr  = &wininfo;
    int             stdin[2];
    pid_t           pid;
    int             fd;

    pipe(stdin);

    if (!isatty(0)) {
	term_ptr = NULL;
	win_ptr  = NULL;
    }
    else {
	ioctl(0, TIOCGWINSZ, win_ptr);
	tcgetattr(0, term_ptr);
    }
    pid = forkpty(&fd, NULL, term_ptr, win_ptr);

    if (pid < 0) {
      printf("%s\n", strerror(errno));
      exit(-1);
    }

    if (pid != 0) {
	close(stdin[0]);
        tcgetattr(0, &saved_termcap);
	termcap.c_lflag &= ~(ICANON | ECHO);
	termcap.c_cc[VMIN] = 1;
	termcap.c_cc[VTIME] = 0;
	tcsetattr(0, TCSANOW, term_ptr);

	subprocess_comms(fd, stdin[1], topipe, len, -1, -1);

        tcsetattr(0, TCSANOW, &saved_termcap);
	return pid;
    }
    close(stdin[1]);
    dup2(stdin[0], 0);

    termcap.c_lflag &= ~(ICANON | ISIG | IEXTEN | ECHO);
    termcap.c_oflag &= ~OPOST;
    termcap.c_cc[VMIN] = 1;
    termcap.c_cc[VTIME] = 0;

    tcsetattr(fd, TCSANOW, term_ptr);
    execve(path, argv, envp);
    abort();
}
""".}

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

proc spawn_pty*(path: cstring, argv, env: cStringArray, p: cstring, l: cint): int
    {.cdecl,discardable,nodecl,importc.}

proc runInteractiveCmd*(path: string, args: seq[string], passToChild = ""):
                      int {.discardable.} =
  # Returns -1 if it didn't work.
  setStdIoUnbuffered()

  var
    cargs = allocCstringArray(@[path] & args)
    envitems: seq[string]
    envp:     cStringArray

  for k, v in envPairs():
    envitems.add(k & "=" & v)

  envp = allocCStringArray(envitems)

  if spawn_pty(cstring(path), cargs, envp, cstring(passtoChild),
            cint(len(passToChild))) == -1:
    raise newException(IoError, "Spawn failed.")

proc runPager*(s: string) =
  var
    exe:   string
    flags: seq[string]

  if s == "":
    return

  let less = findAllExePaths("less")
  if len(less) > 0:
    exe   = less[0]
    flags = @["-r"]
  else:
    let more = findAllExePaths("more")
    if len(more) > 0:
      exe = more[0]
    else:
      raise newException(ValueError, "Could not find 'more' or 'less' in your path.")

  runInteractiveCmd(exe, flags, s)

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
