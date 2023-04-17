# Package

version       = "0.3.3"
author        = "John Viega"
description   = "Crash Øverride Nim utilities"
license       = "Apache-2.0"
srcDir        = "src"


# Dependencies

requires "nim >= 1.6.10"
requires "unicodedb == 0.11.1"
requires "https://github.com/viega/nimaws == 0.3.4"
requires "https://github.com/guibar64/formatstr == 0.2.1"

let s = "nimble doc --project" &
  " --git.url:https://github.com/crashappsec/nimutils.git" &
  " --git.commit:v" & version &
  " --outdir:docs" &
  " --index:on src/nimutils"

task docs, "Build our docs":
  exec s

# This doesn't work with nimble 2.
# let nimblePath = "~/.nimble/pkgs/nimutils-" & version & "/nimutils"

# task link, "Symlink nimutils to ~/.nimble for local dev":
#   exec "set -x && rm -rf " & nimblePath
#   exec "set -x && ln -s $(pwd)/src/nimutils " & nimblePath
