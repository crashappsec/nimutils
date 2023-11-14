## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2023, Crash Override, Inc.

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
  ## Returns a new temporary directory that is `managed`, meaning it
  ## will be automatically removed when the program exits.
  ##
  ## Note that this only applies for normal exits; you will generally
  ## need to register a signal handler to call `tmpfileOnExit()`
  ## if there is an abnormal exit.
  result = createTempDir(tmpFilePrefix, tmpFileSuffix)
  managedTmpDirs.add(result)

proc getNewTempFile*(prefix = defaultTmpPrefix,
                     suffix = defaultTmpSuffix,
                     autoClean = true): (FileStream, string) =
  ## Returns a new temporary file that is `managed`, meaning it
  ## will be automatically removed when the program exits.
  ##
  ## Note that this only applies for normal exits; you will generally
  ## need to register a signal handler to call `tmpfileOnExit()`
  ## if there is an abnormal exit.

  # in some cases such as docker, due to snap permissions
  # it does not have access directly to files created in /tmp
  # but it can access those files if they are nested in another
  # directory.
  let dir = genTempPath(prefix, suffix)
  createDir(dir)
  var (f, path) = createTempFile(prefix, suffix, dir = dir)
  if autoClean:
    managedTmpFiles.add(path)

  result = (newFileStream(f), path)

template registerTempFile*(path: string) =
  ## Register a managed temp file created via some other interface.
  managedTmpFiles.add(path)

template registerTmpDir*(path: string) =
  ## Register a managed temp directory created via some other interface.
  managedTmpDirs.add(path)

template setManagedTmpExitCallback*(cb: OnExitTmpFileCallback) =
  ## If you add a callback, you can report on any errors in deleting, or,
  ## if temp files are to be moved instead of deleted, you can report
  ## on what's been saved where.
  exitCallback = cb

template setManagedTmpCopyLocation*(loc: string) =
  ## If this path is set, temp files will not be copied, they will
  ## instead be moved to a directory under the given location.
  ## Report on it with an exit callback.
  onExitCopyDir = loc

template setDefaultTmpFilePrefix*(s: string) =
  ## Set the default prefix to use for created temp files.
  defaultTmpPrefix = s

template setDefaultTmpFileSuffix*(s: string) =
  ## Set the default suffix to use for created temp files.
  defaultTmpSuffix = s

{.pragma: destructor,
  codegenDecl: "__attribute__((destructor)) $# $#$#", exportc.}
#{.pragma: constructor,
#  codegenDecl: "__attribute__((constructor)) $# $#$#", exportc.}

proc tmpfile_on_exit*() {.destructor.} =
  ## This will get called automatically on normal program exit, but
  ## must be called manually if terminating due to a signal.
  ##
  ## It implements the logic for deleting, moving and calling any
  ## callback.
  var
    fileList: seq[string]
    dirList:  seq[string]
    errList:  seq[string]

  if onExitCopyDir != "":
    try:
      createDir(onExitCopyDir)
      for item in managedTmpFiles & managedTmpDirs:
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
