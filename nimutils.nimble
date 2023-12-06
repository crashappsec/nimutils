# Package

version     = "0.2.1"
author      = "John Viega"
description = "Crash Øverride Nim utilities"
license     = "Apache-2.0"
bin         = @["nimutils"]

# Dependencies

requires "nim >= 2.0.0"
requires "unicodedb == 0.12.0"

before build:
  exec thisDir() & "/bin/header_install.sh"
