## The basic idea here is to create const tables that are populated
## from a directory on the file system.  This only looks at flat
## files, and does no recursion.
##
## The keys are taken from the file name, with the extension, if any,
## ripped off of it.
##
## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022, 2023, Crash Override, Inc.


import tables, strutils, os, system/nimscript

type
  FileTable*        = Table[string, string]
  OrderedFileTable* = OrderedTable[string, string]


proc staticListFiles*(arg: string): seq[string] =
  # Unfortunately, for whatever reason, system/nimutils's listFiles()
  # doesn't seem to work from here, so we can't use listFiles().  As a
  # result, we use a staticexec("ls") and parse.  This obviously is
  # not portable to all versions of Windows.
  #
  # This invocation of ls might not be super portable.  Deserves a bit
  # of testing.
  result = @[]

  let
    lines = staticExec("ls --color=never -pF " & arg &
      " | grep -v \"[^a-zA-Z0-9]$\"")
    items = split(lines, "\n")

  for item in items:
    result.add(item.strip())


template newFileTable*(dir: static[string]): FileTable =
  var
    ret: FileTable = initTable[string, string]()
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

template newOrderedFileTable*(dir: static[string]): OrderedFileTable =
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

when isMainModule:
  const x = newFileTable("/Users/viega/dev/sami/src/help/")

  for k, v in x:
    echo "Filename: ", k
    echo "Contents: ", v[0 .. 40], "..."
