import os

static:
  {.compile: joinPath(splitPath(currentSourcePath()).head, "c/switchboard.c").}
