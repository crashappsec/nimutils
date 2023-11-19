## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022-2023, Crash Override, Inc.

import macros, times, os, posix
# The name flatten conflicts with a method in the options module.
from options import get, Option, isSome, isNone
export get, Option, isSome, isNone

template unreachable*() =
  let info = instantiationInfo()

  ## We use this to be explicit about case statements that are
  ## necessary to cover all cases, but should be impossible to
  ## execute.  That way, if they do execute, we know we made a
  ## mistake.
  try:
    echo "Reached code that was supposed to be unreachable.  Stack trace:"
    echo "REACHED UNREACHABLE CODE AT: " & info.filename & ":" & $(info.line)
    echo getStackTrace()
    doAssert(false, "Reached code the programmer thought was unreachable :(")
  finally:
    discard

proc unixTimeInMS*(): uint64 =
  ## Return the current Unix epoch in miliseconds.  That is, this
  ## function will return the number of miliseconds since Jan 1, 1970
  ## (GMT).

  # One oddity of NIM is that, if I put a decimal point here to make
  # it a float, I *have* to put a trailing zero. That in and of itself
  # is fine, but the error message when I don't sucks: 'Error: Invalid
  # indentation'
  const
    toMS = 1000.0
  uint64(epochTime() * toMS)

proc clzll*(argc: uint): cint {.cdecl, importc: "__builtin_clzll".}
## Call the 64-bit count-leading-zeros builtin.

proc log2*(s: uint): int = 63 - clzll(s)
## Calculate log base 2, truncating.

type
  Flattenable[T] = concept x
    (x is seq) or (x is array)

proc flatten*[T](arr: Flattenable, res: var seq[T]) =
  ## Given arbitrarily nested arrays, flatten into a single array.
  ## Passing a pre-allocated value into the var parameter will
  ## generally remove the need to specify T.
  for entry in arr.items:
    when typeof(arr[0]) is T:
      res.add(entry)
    elif (typeof(arr[0]) is seq) or (typeof(arr[0]) is array):
      flatten(entry, res)
    else:
      static:
        error "Cannot flatten " & $(typeof(arr[0])) & " (expected " & $(T) & ")"

proc flatten*[T](arr: Flattenable): seq[T] =
  ## Given arbitrarily nested arrays, flatten into a single array.
  ## Generally, you will need to specify the type parameter;
  ## result types don't get inferred in Nim.
  result = newSeq[T]()
  flatten[T](arr, result)

template `?`*(x: typedesc): typedesc = Option[x]
template `?`*[T](x: Option[T]): bool = x.isSome()

when defined(autoOption):
  converter toTOpt*[T](x: T): Option[T] =
    some(x)

template getOrElse*[T](x: Option[T], y: T): T =
  ## When writing x.get(12), I think it's confusing.  This uses a
  ## better name.
  get(x, y)

when defined(posix):
  template unprivileged*(code: untyped) =
    ## Run a block of code under the user's UID. Ie, make sure that if the
    ## euid is 0, the code runs with the user's UID, not 0.
    let
      uid = getuid()
      euid = geteuid()
      gid = getgid()
      egid = getegid()
    if (uid != euid) or (gid != egid):
      discard seteuid(uid)
      discard setegid(gid)
    code
    if (uid != euid): discard seteuid(euid)
    if (gid != egid): discard setegid(egid)
else:
  template unprivileged*(code: untyped) =
    code

proc copy*[T](data: sink T): ref T =
  new result
  result[] = data

proc getpass*(prompt: cstring) : cstring {.header: "<unistd.h>",
                                           header: "<pwd.h>",
                                          importc: "getpass".}
  ## The raw getpass function. Nim 2.0 now wraps this, so could be
  ## deprecated.

template getPassword*(prompt: string): string =
  ## Retrieve a password from the terminal (turning off echo for the
  ## duration of the input). This is now part of Nim 2, but whatever.
  $(getpass(cstring(prompt)))

proc bytesToString*(bytes: openarray[byte]): string =
  ## Take raw bytes and copy them into a string object.
  result = newString(bytes.len)
  copyMem(result[0].addr, bytes[0].unsafeAddr, bytes.len)

proc bytesToString*(bytes: pointer, l: int): string =
  ## Converts bytes at a memory address to a string.
  if bytes == nil:
    return ""
  result = newString(l)
  copyMem(result[0].addr, bytes, l)

proc delByValue*[T](s: var seq[T], x: T): bool {.discardable.} =
  let ix = s.find(x)
  if ix == -1:
    return false

  s.delete(ix)

  return true  
