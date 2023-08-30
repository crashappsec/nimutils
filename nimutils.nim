## :Author: John Viega (john@crashoverride.com)
## :Copyright: 2022 - 2023, Crash Override, Inc.
##
## We're also directly pulling in Nim code that does not have a wide
## user base; some of it is abandoned, and for the rest, it's easier
## for us to have control over upstream dependencies that might go
## away.
##
## NimAWS code is abandoned, so currently taking over it. Originally
## written by "Gooseus" and made available under an MIT license.  My
## few fixes have all been for compatability and are made under the
## same license. I also migrated the crypto to openssl.
##
## formatstr is currently a copy of formatstr by G. Bareigts. It's not
## abandoned. Also MIT licensed, and not modified.
##
## I am currently pulling in Glob, since the code seems 2.0 compat,
## but the nimble file denies it.  I think I should remove this from
## chalk, there are easy options if I wrap something in C.

import nimutils/[box, random, unicodeid, pubsub, sinks, misc, ansi, texttable],
       nimutils/[file, process, filetable, encodings, advisory_lock, formatstr]
import nimutils/[sha, aes, prp, hexdump]
export box, random, unicodeid, pubsub, sinks, misc, random, ansi, texttable,
       file, process, filetable, encodings, advisory_lock, formatstr,
       sha, aes, prp, hexdump

## Things we don't want to force people to consume need to be imported
## manually. Currently, that's:
##
## `logging`    because importing it sets up data structures that you might
##              not use; you should explicitly choose to import it.
## `managedtmp` because it adds a destructor you might not want.
## `randwords`  because it does have a huge data structure embedded, which
##              isn't worth it if you're not using it.
