## The basic idea here is to create const tables that are populated
## from a directory on the file system.  This only looks at flat
## files, and does no recursion.
##
## The keys are taken from the file name, with the extension, if any,
## ripped off of it.
import tables, strutils, os

type
  FileTable*        = Table[string, string]
  OrderedFileTable* = OrderedTable[string, string]


proc staticListFiles*(arg: string): seq[string] =
  # Unfortunately, for whatever reason, system/nimutils doesn't seem
  # to work from here, so we can't use listFiles().  As a result, we
  # use a staticexec("ls") and parse.  This obviously is not portable
  # to all versions of Windows.
  #
  # This invocation of ls might not be super portable.  Deserves a bit
  # of testing.
  result = @[]

  echo arg
  let
    lines = staticExec("ls -mp " & arg)
    line  = lines.replace("\n", " ")
    items = split(line, ",")

  for item in items:
    result.add(item.strip())

template ftBase(dir: static[string]) =

  for filename in staticListFiles(`dir`):
    if filename.endswith("/"): continue
    let
      pathToFile   = dir.joinPath(filename)
      fileContents = staticRead(pathToFile)
      key          = splitFile(filename).name

    ret[key] = fileContents


proc newFileTable*(dir: static[string]): FileTable =
  var ret: FileTable = initTable[string, string]()

  ftBase(dir)
  return ret


proc newOrderedFileTable*(dir: static[string]): OrderedFileTable =
  var ret: OrderedFileTable = initOrderedTable[string, string]()

  ftBase(dir)
  return ret
  

when isMainModule:
  const x = newFileTable("/Users/viega/dev/sami/src/help/")

  for k, v in x:
    echo "Filename: ", k
    echo "Contents: ", v[0 .. 40], "..."
