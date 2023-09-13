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

/* This is not yet going to handle window size changes. */

void
handle_comms(int fd, int pid)
{
    fd_set 	   set;
    char   	   buf[4096];
    int    	   stat;
    int            res;
    int            n;
    struct timeval timeout;

    // 1/20th of a second.
    timeout.tv_sec  = 0;
    timeout.tv_usec = 500000;

    FD_ZERO(&set);

    while (true) {
	FD_SET(0,  &set);
	FD_SET(fd, &set);
	switch (select(fd + 1, &set, NULL, NULL, &timeout)) {
	case 0:
	    res = waitpid(pid, &stat, WNOHANG);
	    if (res != -1) {
		break;
	    }
	    exit(1);
	default:
	    if (FD_ISSET(fd, &set) != 0) {
		n = read_one(fd, buf, 4096);
		if (n > 0) {
		    printf("%s", buf);
		} else {
		    return;
		}
	    }

	    if (FD_ISSET(0, &set) != 0) {
		int n = read_one(0, buf, 4096);
		if (n > 0) {
		    write_data(fd, buf, n);
		}
	    }
	}
    }

    while ((n = read_one(fd, buf, 4096)) > 0) {
	printf("%s", buf);
    }
}

pid_t
spawn_pty(char *path, char *argv[], char *envp[], char *topipe, int len)
{
    struct termios termcap;
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

    if (pid != 0) {
	close(stdin[0]);
	termcap.c_lflag &= ~ICANON;
	termcap.c_cc[VMIN] = 1;
	termcap.c_cc[VTIME] = 0;
	tcsetattr(0, TCSANOW, term_ptr);

	write_data(stdin[1], topipe, len);
	close(stdin[1]);
	handle_comms(fd, pid);
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
  setStdIoUnbuffered()

  var
    cargs = allocCstringArray(@[path] & args)
    envitems: seq[string]
    envp:     cStringArray

  for k, v in envPairs():
    envitems.add(k & "=" & v)

  envp = allocCStringArray(envitems)
  spawn_pty(cstring(path), cargs, envp, cstring(passtoChild),
            cint(len(passToChild)))


proc runPager*(s: string) =
  var exe: string

  let less = findAllExePaths("less")
  if len(less) > 0:
    exe = less[0]
  else:
    let more = findAllExePaths("more")
    if len(more) > 0:
      exe = more[0]
    else:
      raise newException(ValueError, "Could not find 'more' or 'less' in your path.")

  runInteractiveCmd(exe, @["-R"], s)



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
