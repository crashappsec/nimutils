## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022-2023, Crash Override, Inc.
##
import macros, options, times, os, strutils

# The name flatten conflicts with a method in the options module.
from options import get, Option, isSome, isNone
export get, Option, isSome, isNone

{.warning[UnusedImport]: off.}

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

template dirWalk*(recursive: bool, body: untyped) =
  ## This is a helper function that helps one unify code when a
  ## program might need to do either a single dir walk or a recursive
  ## walk.  Specifically, depending on whether you pass in the
  ## recursive flag or not, this will call either os.walkDirRec or
  ## os.walkDir.  In either case, it injects a variable named `item`
  ## into the calling scope.
  var item {.inject.}: string

  when recursive:
    for i in walkDirRec(path):
      item = i
      body
  else:
    for i in walkDir(path):
      item = i.path
      body

template unixTimeInMS*(): uint64 =
  ## Return the current Unix epoch in miliseconds.  That is, this
  ## function will return the number of miliseconds since Jan 1, 1970
  ## (GMT).

  # One oddity of NIM is that, if I put a decimal point here to make
  # it a float, I *have* to put a trailing zero. That in and of itself
  # is fine, but the error message when I don't sucks: 'Error: Invalid
  # indentation'
  const toMS = 1000000.0
  cast[uint64](epochTime() * toMS)

proc tildeExpand(s: string): string {.inline.} =
  var homedir = os.getHomeDir()

  while homedir[^1] == '/':
    homedir.setLen(len(homedir) - 1)
  if s == "":
    return homedir

  let parentFolder = homedir.splitPath().head

  return os.joinPath(parentFolder, s)

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
  import posix
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
