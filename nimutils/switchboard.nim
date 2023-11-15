## Our switchboard API is focused on being able to arbitrarily
## multiplex IO across file descriptors, and do so using a single
## thread. for simplicitly. Currently, the intent is to be able to
## handle 'normal' applications that often benefit from avoiding the
## complexity of threads.
##
## This also means we use `select()` under the hood, with no option
## yet for `epoll()` or `kqueue()`. So if you've got a very large
## number of connections to multiplex, this isn't the right
## interface. However, this is very well suited for lower volume
## servers and subprocess handling.
##
## When we deal with underlying file decscriptors, we make no
## assumptions about whether they are set to blocking or not. We
## always make sure there's data ready to read, or that we can write
## at least `PIPE_BUF` bytes before we do any operation.
##
## And when multiplexing a listening socket, we only ever accept one
## listener at a time as well.
##
## The end result is that we should never block, and don't care
## whether the file descriptors are set to blocking or not.
##
## We use a pub/sub model, and in each poll, we will always select on
## any open fds that have subscribers available. For writers, we will
## only select on their fds if there are messages waiting to be
## written to that fd, so that we never wake up with nothing to do.
##
## In part, this is handled by having a message queue attached to
## readers. So in the first possible select cycle, (assuming there's
## no string being routed into a file descriptor), we will only
## select() for read fds.
##
## There's no write delay though, as when we re-enter the select loop,
## we'd expect the fds for write to all be ready for data, so th
## select() call will return immediately.
##
##
## Note that this module is a wrapping of the lower-level (C) API.
## Currently, this is primarily meant to be exposed through the
## `subprocess` interface, though we will, in the not-too-distant
## future add a more polished interface to this module that would be
## appropriate for server setups, etc.
import os, posix

{.pragma: sb, cdecl, importc, nodecl.}

static:
  {.compile: joinPath(splitPath(currentSourcePath()).head, "c/switchboard.c").}

type
  SwitchBoard* {.importc: "switchboard_t", header: "switchboard.h" .} = object
  Party* {.importc: "party_t", header: "switchboard.h" .} = object
  SBCallback* =
    proc (i0: var RootRef, i1: var RootRef, i2: cstring, i3: int) {. cdecl,
                                                                    gcsafe .}
  AcceptCallback* =
    proc (i0: var SwitchBoard, fd: cint, addressp: pointer,
          addrlenp: pointer) {. cdecl, gcsafe .}
  SBCaptures* {. importc: "sb_result_t", header: "switchboard.h" .} = object
  SbFdPerms* = enum sbRead = 0, sbWrite = 1, sbAll = 2

proc sb_init*(ctx: var SwitchBoard, heap_elems: csize_t) {.sb.}
 ## Low-level interface. Use initSwitchboard().

proc sb_init_party_fd(ctx: var Switchboard, party: var Party, fd: cint,
                      perms: SbFdPerms, stopWhenClosed: bool,
                      closeOnDestroy: bool) {.sb.}

proc initPartyCallback*(ctx: var Switchboard, party: var Party,
                        callback: SBCallback) {.cdecl,
                       importc: "sb_init_party_callback", nodecl .}
  ## This sets up a callback to receive incremental data that
  ## has been read from any file descriptor, except listening sockets.
  ##
  ## Any state information can be passed to this callback via the
  ## as-yet-unwrapped `sb_set_extra()` and retrieved by the similarly
  ## unwrapped `sb_get_party_extra()`.

proc sb_init_party_listener(ctx: var Switchboard, party: var Party,
                            sockfd: int, callback: AcceptCallback,
                            stopWhenClosed: bool, closeOnDestroy: bool) {.sb.}

proc initPartyListener*(ctx: var Switchboard, party: var Party,
                        sockfd: int, callback: AcceptCallback,
                        stopWhenClosed = false, closeOnDestroy = true) =
  ## This sets up monitoring of a socket that is listening for connections.
  ## The provided callback will be called whenever there is a listening
  ## socket waiting to be read.
  ctx.sb_init_party_listener(party, sockfd, callback, stopWhenClosed,
                             closeOnDestroy)

proc sb_init_party_input_buf(ctx: var Switchboard, party: var Party,
                             input: cstring, l: csize_t, dup: bool,
                             free: bool, close_fd_when_done: bool) {.sb.}

proc sb_init_party_output_buf(ctx: var Switchboard, party: var Party,
                              tag: cstring, l: csize_t) {.sb.}

proc initPartyCapture*(ctx: var Switchboard, party: var Party,
                       prealloc = 4096, tag: static[string]) =
  ## Sets up a capture buffer that you can send output to, as long as
  ## the source you're routing from is a non-string writer.
  ##
  ## The underlying api assumes that it never has to free the passed
  ## tag and that it will always exit, so in this variant, the tag
  ## must point to static memory.
  ctx.sb_init_party_output_buf(party, tag, csize_t(prealloc))

proc unsafeInitPartyCapture*(ctx: var Switchboard, party: var Party,
                             prealloc = 4096, tag: string) =
  ## This is the same as initPartyCapture, except you use a string
  ## that you assert will not be freed before the switchboard has been
  ## torn down.
  ##
  ## If you don't follow this contract, you will probably either
  ## crash, or get garbage.
  ##
  ## We may refactor the underlying implementation to address this,
  ## but don't count on it!
  ctx.sb_init_party_output_buf(party, tag, csize_t(prealloc))

proc sb_monitor_pid(ctx: var Switchboard, pid: Pid, stdin: ptr Party,
                    stdout: ptr Party, stderr: ptr Party, shutdown: bool) {.sb.}

proc monitorProcess*(ctx: var Switchboard, pid: Pid, stdin: ref Party = nil,
                     stdout: ref Party = nil, stderr: ref Party = nil,
                     shutdown: bool = false) =
  ## Sets up a process monitor for a switchboard.  Currently there is
  ## no direct API for retrieving data from the monitors. We need to
  ## fix this. If you're using the subprocess interface, you're
  ## indirectly getting access to a single monitor.
  ##
  ## If you attach parties to the process that present the stdin,
  ## stdout or stderr of the process, the system can detect when they
  ## close. This is most useful if you want to exit when the process
  ## disappears, which we might notice if trying to write to its file
  ## descriptor, but it fails.
  ##
  ## If that happens and `shutdown` is true, then the remaining data
  ## is drained from the read side of this file descriptor, all queued
  ## writes are completed, then the switchboard will exit (possibly
  ## with active file descriptors).  A few reads from other file
  ## descriptors could get services while waiting for the shutdown.
  ctx.sb_monitor_pid(pid, cast[ptr Party](stdin), cast[ptr Party](stdout),
                     cast[ptr Party](stderr), shutdown)

proc initPartyStrInput*(ctx: var Switchboard, party: var Party,
                        input: string = "", closeFdWhenDone: bool = false) =
  ## Initializes an input string that can be the source when routing
  ## to a file descriptor. This is generally useful for sending data
  ## to sockets, or to subprocesses.
  ##
  ## This object can be re-used as much as you like by calling
  ## `party.setString()`.
  ##
  ## However, neither this function nor `setString()` pass data
  ## explicitly; with strings, you must call `route` every time to any
  ## party you want to send the string to. We may add a wrapper object
  ## that automates this process.
  ##
  ## If `closeFdWhenDone` is set, then this is intended to be a one-off,
  ## and any file descriptors this is scheduled to write to will be
  ## closed automatically once the write is completed. This allows you
  ## to close the stdin of a subprocess after the string gets written.
  ctx.sb_init_party_input_buf(party, cstring(input), csize_t(input.len()),
                              true, true, close_fd_when_done)

proc sb_party_input_buf_new_string(party: var Party, input: cstring,
                                   l: csize_t, dup: bool,
                                   free: bool, closeFd: bool) {.sb.}

proc setString*(party: var Party, input: string, closeAfter: bool = false) =
  ## If a party is a string input buffer, this will update the string
  ## it sends out when you call `route` on it.
  ##
  ## If this doesn't represent an string input party, nothing will happen.
  ##
  ## If `closeAfter` is true, then once this string is written, any
  ## subscriber will be closed.
  party.sb_party_input_buf_new_string(cstring(input), csize_t(input.len()),
                                      true, true, closeAfter)
proc initPartyFd*(ctx: var SwitchBoard, party: var Party, fd: int,
                  perms: SbFdPerms, stopWhenClosed = false,
                  closeOnDestroy = false) =
  ## Initializes a file descriptor that can be both a subscriber and
  ## subscribed to, depending on the fd's permissions (which are
  ## passed, not discovered).
  ##
  ## The `perms` field should be sbRead for O_RDONLY, sbWrite for O_WRONLY
  ## or sbAll for O_RDWR
  ##
  ## The `stopWhenClosed` field closes down the switchboard when I/O
  ## to this fd fails.
  ##
  ## If `closeOnDestroy` is true, we will call close() on the fd for
  ## you whenever the switchboard is torn down.
  sb_init_party_fd(ctx, party, cint(fd), perms, stopWhenClosed,
                   closeOnDestroy)

proc sb_destroy(ctx: var Switchboard, free: bool) {.sb.}

template initSwitchboard*(ctx: var SwitchBoard, heap_elems: int = 16) =
  sb_init(ctx, csize_t(heap_elems))
  ## Initialize a switchboard object.

proc route*(ctx: var Switchboard, src: var Party, dst: var Party): bool
    {.cdecl, importc: "sb_route", nodecl, discardable.}
  ## Route messages from the `src` object to the `dst` object.
  ## Basically, the `dst` party subscribes to messages from the `src`.
  ## These subscriptions shouldn't be removed, but can be paused and
  ## resumed (pausing and never resuming is tantamount to removing).

proc pauseRoute*(ctx: var Switchboard, src: var Party, dst: var Party): bool
    {.cdecl, importc: "sb_pause_route", nodecl, discardable.}
  ## Akin to removing a route subscription, except that you can easily
  ## re-subscribe if you wish by calling `resumeRoute`

proc resumeRoute*(ctx: var Switchboard, src: var Party, dst: var Party): bool
    {.cdecl, importc: "sb_resume_route", nodecl, discardable.}
  ## Restarts a previous route / subscription that has been paused.

proc routeIsActive*(ctx: var Switchboard, src: var Party, dst: var Party): bool
    {.cdecl, importc: "sb_route_is_active", nodecl, discardable.}
  ## Returns true if the subscription is active, meaning it exists,
  ## neither side is closed, and the subscription is not paused.

proc routeIsPaused*(ctx: var Switchboard, src: var Party, dst: var Party): bool
    {.cdecl, importc: "sb_route_is_paused", nodecl, discardable.}
  ## Returns true if the subscription is active but paused, meaning a
  ## subscribed happened, but it was paused. If either side is closed,
  ## this will return `false`, even if it had previously been paused.

proc routeIsSubscribed*(ctx: var Switchboard, src: var Party,
                        dst: var Party): bool
    {.cdecl, importc: "sb_route_is_subscribed", nodecl, discardable.}
  ## Returns true if the subscription is active, meaning a subscribed
  ## happened, and neither side is closed. However, it may be either
  ## paused or unpaused.

proc setTimeout*(ctx: var Switchboard, value: var Timeval)
    {.cdecl, importc: "sb_set_io_timeout", nodecl.}
  ## Sets the amount of time that one polling loop blocks waiting for
  ## I/O. If you're definitely going to wait forever until the
  ## switchboard ends, then this can be unlimited (see
  ## `clearTimeout()`).
  ##
  ## Generally, you want this low enough to make sure you're
  ## responsive to a hang of some sort, but not TOO low, as it will
  ## unnecessarily drive up CPU.

proc clearTimeout*(ctx: var Switchboard)
    {.cdecl, importc: "sb_clear_io_timeout", nodecl.}
  ## Removes any polling timeout; if there's no IO on the switchboard,
  ## polling will hang until there is.

proc operateSwitchboard*(ctx: var Switchboard, toCompletion: bool): bool
    {.cdecl, importc: "sb_operate_switchboard", nodecl, discardable.}
  ## Low-level interface; use run() instead.

proc sb_set_extra(ctx: var Switchboard, extra: RootRef) {.sb.}
proc sb_set_party_extra(ctx: var Party, extra: RootRef) {.sb.}

proc getExtraData*(ctx: var Switchboard): RootRef
    {.cdecl, importc: "sb_get_extra", nodecl.}
  ## Retrieves any extra data stored, specific to a switchboard.

proc getExtraData*(ctx: var Party): RootRef
    {.cdecl, importc: "sb_get_party_extra", nodecl.}
  ## Retrieves any extra data stored for the party.

proc clearExtraData*(ctx: var Switchboard) =
  ## Removes any stored extra data (setting it to nil).
  let x = ctx.getExtraData()

  if x != nil:
    ctx.sb_set_extra(RootRef(nil))
    GC_unref(x)

proc clearExtraData*(ctx: var Party) =
  ## Removes any stored extra data (setting it to nil).
  let x = ctx.getExtraData()

  if x != nil:
    ctx.sb_set_party_extra(RootRef(nil))
    GC_unref(x)

proc setExtraData*(ctx: var Switchboard, extra: RootRef) =
  ## Sets any extra data that will get passed to IO callbacks that is
  ## specific to this switchboard. It must be a "ref" object
  ## (inheriting from RootRef). The reference will be held until the
  ## process exits, or it is replaced.
  ##
  ## This call should only ever be called from one thread at a time;
  ## there's a race condition otherwise, where you could end up trying
  ## to double-free the old object, and end up leaking the object that
  ## gets written first.
  let x = ctx.getExtraData()

  if x != nil:
    GC_unref(x)

  ctx.sb_set_extra(extra)

  if extra != RootRef(nil):
    GC_ref(extra)

proc setExtraData*(ctx: var Party, extra: RootRef) =
  ## Sets any extra data that will get passed to IO callbacks that is
  ## specific to this party (will be passed back to you in the second
  ## parameter of the callback). It must be a "ref" object (inheriting
  ## from RootRef). The reference will be held until the process
  ## exits, or it is replaced.
  ##
  ## This call should only ever be called from one thread at a time;
  ## there's a race condition otherwise, where you could end up trying
  ## to double-free the old object, and end up leaking the object that
  ## gets written first.
  let x = ctx.getExtraData()

  if x != nil:
    GC_unref(x)

  ctx.sb_set_party_extra(extra)

  if extra != RootRef(nil):
    GC_ref(extra)

proc `=destroy`*(ctx: Switchboard) =
  var copy = ctx
  copy.clearExtraData()
  copy.sb_destroy(false)

proc `=destroy`*(ctx: Party) =
  var copy = ctx
  copy.clearExtraData()

proc sb_result_destroy(res: var SBCaptures) {.sb.}

proc `=destroy*`(res: var SBCaptures) =
  res.sb_result_destroy()

proc sb_result_get_capture(res: var SBCaptures, tag: cstring,
                           borrow: bool): cstring {.sb.}

proc getCapture*(res: var SBCaptures, tag: string): string =
  ## Returns a specific process capture by tag.
  return $(res.sb_result_get_capture(cstring(tag), true))

proc run*(ctx: var Switchboard, toCompletion = true): bool {.discardable.} =
  ## Runs the switchboard IO polling cycle. By default, this will keep
  ## running until there are no subscriptions that could possibly be
  ## serviced without a new subscription.
  ##
  ## However, if you set `toCompletion` to `false`, it will run only
  ## one polling cycle.  In this mode, you're expected to manually
  ## poll when it's convenient for your application.
  ##
  ## Once the switchboard has ended, call `ctx.getResults()`
  ## to get any capture or process info.

  if not operateSwitchboard(ctx, toCompletion):
    ctx.clearExtraData() # Don't need it anymore, why wait till close?
    return true
  elif toCompletion:
    return true
  else:
    return false

# Not yet wrapped:
## extern void sb_monitor_pid(switchboard_t *, pid_t, party_t *, party_t *,
## 			   party_t *, bool);
