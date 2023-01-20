import macros
import times
import os
import std/wordwrap
import strutils

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

macro getOrElseActual(x: untyped, y: untyped): untyped =
  return quote do:
    if `x`.isSome():
      `x`.get()
    else:
      `y`

proc getOrElse*[T](x: Option[T], y: T): T {.inline.} =
  ## Allows us to derefenrece an Option[] type if it isSome(), and if
  ## not, set a default value instead.  This is intended to help make
  ## lets using options more concise when we need a default.  Note
  ## that you can make the second argument a code block, which is the
  ## ultimate reason why one might use this.
  getOrElseActual(x, y)

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

proc indentAndWrap*(str: string, indent: int, maxWidth = 80): string =
  ## Wrap to a fixed width, while still indenting.
  ## Probably can be done by fmt, but less clearly.
  let
    s = wrapWords(str, maxWidth - indent, false)
    pad = repeat(' ', indent)

  var lines = s.split("\n")

  for i in 0 ..< len(lines):
    lines[i] = pad & lines[i]

  return lines.join("\n")

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
