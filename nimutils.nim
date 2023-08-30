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
## same license.
##
## formatstr is currently a copy of formatstr by G. Bareigts. It's not
## abandoned. Also MIT licensed, and not modified.
##
## I've also moved nimSHA2 into here. I intend to get rid of the weird
## crypto in nimAWS and replace nimSHA2 entirely via OpenSSL at some
## point when I'm bored enough to do it; until then, this lives it
## pinned. This also is MIT licensed, and was written by Andri Lim.

import nimutils/[box, random, unicodeid, pubsub, sinks, misc, ansi, texttable],
       nimutils/[file, process, filetable, encodings, advisory_lock, formatstr]
import nimutils/nimSHA2
export box, random, unicodeid, pubsub, sinks, misc, random, ansi, texttable,
       file, process, filetable, encodings, advisory_lock, formatstr, nimSHA2

## Things we don't want to force people to consume need to be imported
## manually. Currently, that's:
##
## `logging`    because importing it sets up data structures that you might
##              not use; you should explicitly choose to import it.
## `managedtmp` because it adds a destructor you might not want.
## `randwords`  because it does have a huge data structure embedded, which
##              isn't worth it if you're not using it.
