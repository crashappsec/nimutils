import os

static:
  echo currentSourcePath().head
  {.compile: joinPath(splitPath(currentSourcePath()).head, "switchboard.c").}
