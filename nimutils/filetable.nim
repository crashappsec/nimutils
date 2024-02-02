## The basic idea here is to create const tables that are populated
## from a directory on the file system.  This only looks at flat
## files, and does no recursion.
##
## The keys are taken from the file name, with the extension, if any,
## ripped off of it.
##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022, 2023, Crash Override, Inc.


import tables, strutils, os

type
  FileTable*        = Table[string, string]
  OrderedFileTable* = OrderedTable[string, string]


proc staticListFiles*(arg: string): seq[string] =
  ## Unfortunately, for whatever reason, system/nimutils's listFiles()
  ## doesn't seem to work from here, so we can't use listFiles().  As a
  ## result, we use a staticexec("ls") and parse.  This obviously is
  ## not portable to all versions of Windows.
  ##
  ## This is super hacky, but works well enough, without digging deep
  ## into the Javascript runtime.
  result = @[]

  let
    lines = staticExec("find " & arg  & " -type f " &
                       " | grep -v \"[^a-zA-Z0-9]$\"")
    items = split(lines, "\n")

  for item in items:
    var path = item
    path.removePrefix(arg)
    path.removePrefix(DirSep)
    result.add(path.strip())


template newFileTable*(dir: static[string]): FileTable =
  ## This will, at compile time, read files from the named directory,
  ## and produce a `Table[string, string]` where the keys are the file
  ## names (without path info), and the values are the file contents.
  ##
  ## This doesn't use the newer dictionary interface, and I think at
  ## this point, our tooling is good enough that we don't need this
  ## for our own uses, but no reason why it can't stay if others might
  ## find it useful.
  var
    ret: FileTable = initTable[string, string]()
    path = instantiationInfo(fullPaths = true).filename.splitPath().head
    dst  = path.joinPath(dir)

  let pwd = staticExec("cd " & dst & "; pwd")

  for filename in staticListFiles(dst[0 ..< ^1]):
    let
      pathToFile   = pwd.joinPath(filename)
      fileContents = staticRead(pathToFile)
      key          = splitFile(filename).name.toLower()

    ret[key] = fileContents
  ret

template newOrderedFileTable*(dir: static[string]): OrderedFileTable =
  ## Same as `newFileTable()` except uses an `OrderedTable`.
  var
    ret: OrderedFileTable = initOrderedTable[string, string]()
    path = instantiationInfo(fullPaths = true).filename.splitPath().head
    dst  = path.joinPath(dir)

  let pwd = staticExec("cd " & dst & "; pwd")

  for filename in staticListFiles(dst[0 ..< ^1]):
    let
      pathToFile   = pwd.joinPath(filename)
      fileContents = staticRead(pathToFile)
      key          = splitFile(filename).name

    ret[key] = fileContents
  ret
