import std/tempfiles, streams, sugar, os

type OnExitTmpFileCallback = (seq[string], seq[string], seq[string]) -> void

var
  managedTmpDirs*:   seq[string]           = @[]
  managedTmpFiles*:  seq[string]           = @[]
  exitCallback*:     OnExitTmpFileCallback = nil
  onExitCopyDir*:    string                = ""
  defaultTmpPrefix*: string                = "tmp"
  defaultTmpSuffix*: string                = ""

proc getNewTempDir*(tmpFilePrefix = defaultTmpPrefix,
                    tmpFileSuffix = defaultTmpSuffix): string =
  result = createTempDir(tmpFilePrefix, tmpFileSuffix)
  managedTmpDirs.add(result)

proc getNewTempFile*(prefix = defaultTmpPrefix, suffix = defaultTmpSuffix,
                     autoClean = true): (FileStream, string) =
  var (f, path) = createTempFile(prefix, suffix)
  if autoClean:
    managedTmpFiles.add(path)

  result = (newFileStream(f), path)

template registerTempFile*(path: string) =
  managedTmpFiles.add(path)

template registerTmpDir*(path: string) =
  managedTmpDirs.add(path)

template setManagedTmpExitCallback*(cb: OnExitTmpFileCallback) =
  exitCallback = cb

template setManagedTmpCopyLocation*(loc: string) =
  onExitCopyDir = loc

template setDefaultTmpFilePrefix*(s: string) =
  defaultTmpPrefix = s

template setDefaultTmpFileSuffix*(s: string) =
  defaultTmpSuffix = s

{.pragma: destructor,
  codegenDecl: "__attribute__((destructor)) $# $#$#", exportc.}
#{.pragma: constructor,
#  codegenDecl: "__attribute__((constructor)) $# $#$#", exportc.}

proc tmpfile_on_exit*() {.destructor.} =
  var
    fileList: seq[string]
    dirList:  seq[string]
    errList:  seq[string]

  if onExitCopyDir != "":
    try:
      createDir(onExitCopyDir)
      for item in managedTmpDirs & managedTmpFiles:
        let baseName = splitPath(item).tail
        if fileExists(item):
          try:
            moveFile(item, onExitCopyDir.joinPath(baseName))
            fileList.add(item)
          except:
            errList.add(item & ": " & getCurrentExceptionMsg())
        else:
          try:
            moveDir(item, onExitCopyDir.joinPath(baseName))
            dirList.add(item)
          except:
            errList.add(item & ": " & getCurrentExceptionMsg())
    except:
      errList.add(getCurrentExceptionMsg())

  else:
    for item in managedTmpFiles:
      try:
        removeFile(item)
        fileList.add(item)
      except:
        errList.add(item & ": " & getCurrentExceptionMsg())
    for item in managedTmpDirs:
      try:
        removeDir(item)
        dirList.add(item)
      except:
        errList.add(item & ": " & getCurrentExceptionMsg())

  if exitCallback != nil:
    exitCallback(fileList, dirList, errList)
