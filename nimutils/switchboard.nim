import os

static:
  {.compile: joinPath(splitPath(currentSourcePath()).head, "switchboard.c").}
