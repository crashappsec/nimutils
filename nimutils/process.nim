## Process-related utilities.
##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

import misc, strutils, posix, os, options

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
