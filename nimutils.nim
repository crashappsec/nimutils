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

import nimutils/[box, random, unicodeid, pubsub, sinks, misc, texttable],
       nimutils/[file, process, filetable, encodings, advisory_lock]
import nimutils/[sha, aes, prp, hexdump, markdown, htmlparse, net]
import nimutils/[colortable, rope_base, rope_styles, rope_construct,
                 rope_prerender, rope_ansirender, switchboard, subproc]
export box, random, unicodeid, pubsub, sinks, misc, random, texttable,
       file, process, filetable, encodings, advisory_lock, sha, aes, prp,
       hexdump, markdown, htmlparse, net
export colortable, rope_base, rope_styles, rope_construct, rope_prerender,
       rope_ansirender, switchboard, subproc

## Things we don't want to force people to consume need to be imported
## manually. Currently, that's:
##
## `logging`    because importing it sets up data structures that you might
##              not use; you should explicitly choose to import it.
## `managedtmp` because it adds a destructor you might not want.
## `randwords`  because it does have a huge data structure embedded, which
##              isn't worth it if you're not using it.
