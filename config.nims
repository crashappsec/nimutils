import strutils, os, nimutils/nimscript

when (NimMajor, NimMinor) < (2, 0):
  echo "NimUtils requires Nim 2.0 or later."
  quit()

when not defined(debug):
    switch("d", "release")
    switch("opt", "speed")

var
  subdir = ""

for item in listDirs(thisDir()):
  if item.endswith("/files"):
    subdir = "/files"
    break

proc getEnvDir(s: string, default = ""): string =
  result = getEnv(s, default)

exec thisDir() & subdir & "/bin/buildlibs.sh " & thisDir() & "/files/deps"

var
  default  = getEnvDir("HOME").joinPath(".local/c0")
  localDir = getEnvDir("LOCAL_INSTALL_DIR", default)
  libDir   = localdir.joinPath("libs")
  libs     = ["pcre", "ssl", "crypto", "gumbo", "hatrack"]

applyCommonLinkOptions()
staticLinkLibraries(libs, libDir, muslBase = localDir)
