This is a collection of random utilities that were developed for
[Chalk](https://github.com/crashappsec/chalk) and
[Con4m](https://github.com/crashappsec/con4m), that were more general.

This is nowhere near a proper 1.0 release. Functionality will grow
slowly. For instance, we're going to be wrapping the GitHub markdown
library (no Nim ones let us operate on a tree), and we will probably
wrap the AWS SDK, because *all* of the nim options suck (see below).

And currently there is *no* documentation, but we've tried to keep
APIs simple and obvious.

# Current highlights

- Fast cryptography painfully missing from Nim. See below.

- Fancy hex dumps that can respect your terminal width via
  `strdump(string): string` and `hexDump(pointer, sz): string`.

- A "managed" temp file interface, that gives your tmp files and
  directories that will be automatically cleaned up if your program
  exits normally (or if your signal handler calls
  tmpfileOnExit()). This includes, `getNewTmpDir(prefix = "tmp",
  suffix = ""): string`, `getNewTmpFile(prefix = "tmp", suffix = "")`
  , `registerTempFile(path: string)`, and `registerTmpDir(path:
  string)`
  
- An API for cross-process locking through lock-files:
  `writeViaLockFile(path, contents: string, release = true, maxAttempts = 5):
  bool` and `readViaLockFile*(path: string, release = true, maxAttempts
  = 5): string`

- Our `Box` type that allows you to have containers that take objects
  of varying types.  You just `pack()` and `unpack()` values into and
  out of a box. It doesn't try to handle every possible Nim type (just
  the one needed), but covers the important stuff, and won't end up
  losing access to the value if seq's or objects go out of scope
  (unlike the Nim `Any` type found in std/typeinfo). In plenty of
  cases, Nim will need to know the type of object when *unpacking*, so
  specify: `unpack[int](box)`.  If you know the box contains a list of
  variably typed items, you can do: `unpack[seq[Box]](box)`

- There are other posix-nicities, like a call for forking and execing
  a process that gives you more flexibility than you can get in
  Nim. For instance, you can get stdout, stderr AND the exit code,
  plus you could automatically replace stdin with a string.  We'll add
  more options here as we need them. See `file.nim`, `process.nim`

- While not quite posix, there's an API for getting Mac process info
  (for a single process, or the whole system).

- A pub-sub API so that you can make it easy for users to configure
  where various kinds of output should go, and to filter stuff.

- A logging API build on the pub-sub API, so that you can just call
  things like `info(msg)` or `trace(msg)`, and the code will run or
  not based on the configured log-level. Pretty ansi includd.

- We've incorporated a 3rd-party S3 client because it needed work to
  work w/ either 1.6 or 2.0, and the maintainers were not responsive
  to PRs. This was currently the best thing out there, and it wasn't
  good, which is why we may end up having to wrap the official C++
  SDK.

- A `fileTable` nodule, that can create tables or ordered tables at
  compile time, where the keys are taken from file names, and the
  values are taken from the files themselves.  For instance:

```nim
  const t = newFileTable(".")  # t gets set at compile time.
  
  for k, v in t:
    echo "Filename: ", k
    echo "Contents: ", v
```    

Our super flexible getopt style API has moved to Con4m, where you can
now spec rich command lines without writing any code at all.

# Cryptography

Nimutils contains some high-level crypto APIs we've needed, where it's
been impossible to find something good in the Nim world till now:

- There's a high-level wrapper that provides both encryption and
  message integrity via AES-GCM (which is the default TLS
  algorithm). The API is designed to handle many messages (example
  below).
  
- The AES-GCM message authentication code has an API.

- There's an EASY interface to SHA2-256, SHA2-512 and SHA3. Get the
  binary digest with `sha256(x)` and get it in hex with
  `sha256hex()`. There is also an incremental interface if needed.

- There's a matching set of 'one-shot' interfaces to hmac, for
  instance: `hmacSha256(key, toauth)` for binary output, and
  `hmacSha256hex(key, toauth)` for hex encoded output (we haven't
  needed an incremental interface yet).

- There's an implementation of a (provably secure) non-malleable
  encryption algorithm. We've configured it to work only on data 24
  bytes or larger, but it's a decent option when you're more focused
  on storing structured data; Data doesn't expand and there's no worry
  about bit-flipping attacks. The big downside is you're passing over
  the data with crypto ops four times instead of once, and cannot
  stream the data. A smaller downside is that if you encrypt the same
  thing twice, you'll get the same output (unless you use a nonce,
  which the API encourages). Still, this is a pretty good option with
  no IP restrictions for long-term storage of files, which we use
  before sending data to the builtin Chalk secret manager, for
  instance.  For other crypto nerds, this is the four round
  Luby-Rackoff algorithm w/ AES-CTR and HMAC-SHA3 as the PRFs.

- There's a simple interface to secure random numbers. Want a random
  byte string of 14 bytes? `randString(14)`. For ints and arrays, you
  can use the generic `secureRand` call.  For instance:
  `secureRand[uint64]()` or `secureRand[array[6, byte]]()`

There are some other little bits in there that are more building
blocks for cryptographers, not stuff the average person should use
directly.

We wrap OpenSSL for the core crypto algorithms we use,
which ensures you will get hardware accelerated algorithms on most
platforms. We are not huge fans of OpenSSL, but:

1. Nim's standard libraries (particularly their http implementation)
   use OpenSSL already, and we use those things too.

2. The pure-nim crypto libs are either not-hardware accelarated, or
   are fundamentally bad.

For instance, on #2, the somewhat popular NimCrypto library proves
that Cryptocurrency people don't necessarily understand cryptography
well.  Their AES-GCM implementation is fundamentally flawed... it does
not follow the NIST spec and renders it basically no better than
AES-CTR. I have told them this, and told them I was *co-author* of
AES-GCM. They don't seem to want to fix it.  Definitely don't use that
library.

We do use the OpenSSL3 API. It's not as universally installed as
OpenSSL 1, so we currently recommend statically linking it to your
apps. To do this in nim you need to put the following in your
config.nims:

```nim
switch("d", "useOpenSSL3")
switch("passL", "/full/path/to/platforms/libssl.a")
switch("passL", "/full/path/to/platforms/libcrypto.a")
switch("dynlibOverride", "ssl")
switch("dynlibOverride", "crypto")
```

# Other notes

Most of the bits you'll find in the library that are not already
mentioned were basically early Nim experiements that we may still
using, but will eventually rip out or replace.

A lot of these bits contain some wrapped C code. Don't be alarmed if
you're digging through the source, you can just focus on the Nim APIs.

Again, we'll eventually do some real documentation, but with no
expectation of time frame. This library is developed more as it suits
our internal needs, where there are bits and bobs that seem like
they'd be useful across projects. If other people find it useful
as-is, great, but we are not focused on outside usage.