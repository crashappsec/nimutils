import os, posix

{.pragma: sb, cdecl, importc, nodecl.}

static:
  {.compile: joinPath(splitPath(currentSourcePath()).head, "c/switchboard.c").}

type
  SwitchBoard* {.importc: "switchboard_t", header: joinPath(splitPath(currentSourcePath()).head, "switchboard.h") .} = object
  Party* {.importc: "party_t", header: joinPath(splitPath(currentSourcePath()).head, "switchboard.h") .} = object
  SBCallback* =
    proc (i0: pointer, i1: pointer, i2: cstring, i3: int) {. cdecl, gcsafe .}
  SBResultObj* {. importc: "sb_result_t", header: joinPath(splitPath(currentSourcePath()).head, "switchboard.h") .} = object
  SbFdPerms* = enum sbRead = 0, sbWrite = 1, sbAll = 2

proc sb_init*(ctx: var SwitchBoard, heap_elems: csize_t) {.sb.}
proc sb_init_party_fd*(ctx: var Switchboard, party: var Party, fd: cint,
                       perms: SbFdPerms, stopWhenClosed: bool,
                       closeOnDestroy: bool) {.sb.}
proc sb_init_party_callback*(ctx: var Switchboard, party: var Party,
                             callback: SBCallback) {.sb.}
proc sb_destroy(ctx: var Switchboard, free: bool) {.sb.}

template initSwitchboard*(ctx: var SwitchBoard, heap_elems: int = 16) =
  sb_init(ctx, csize_t(heap_elems))

template initPartyFd*(ctx: var SwitchBoard, party: var Party, fd: int,
                      perms: SbFdPerms, stopWhenClosed = false,
                      closeOnDestroy = false) =
  sb_init_party_fd(ctx, party, cint(fd), perms, stopWhenClosed,
                   closeOnDestroy)

template initPartyCallback*(ctx: var SwitchBoard, party: var Party,
                            cb: SBCallback) =
  sb_init_party_callback(ctx, party, cb);

proc route*(ctx: var Switchboard, src: var Party, dst: var Party): bool
    {.cdecl, importc: "sb_route", nodecl, discardable.}

proc setTimeout*(ctx: var Switchboard, value: var Timeval)
    {.cdecl, importc: "sb_set_io_timeout", nodecl.}

proc clearTimeout*(ctx: var Switchboard)
    {.cdecl, importc: "sb_clear_io_timeout", nodecl.}

proc operateSwitchboard*(ctx: var Switchboard, toCompletion: bool): bool
    {.cdecl, importc: "sb_operate_switchboard", nodecl, discardable.}

template run*(ctx: var Switchboard, toCompletion = false) =
  operateSwitchboard(ctx, toCompletion)

proc close*(ctx: var Switchboard) = ctx.sb_destroy(false)

# Not yet wrapped:
## extern void sb_init_party_listener(switchboard_t *, party_t *, int,
## 	 		        accept_cb_t, bool, bool);
## extern void sb_init_party_input_buf(switchboard_t *, party_t *, char *,
## 				 size_t, bool, bool);
## extern void sb_init_party_output_buf(switchboard_t *, party_t *, char *,
## 				     size_t);
## extern void sb_monitor_pid(switchboard_t *, pid_t, party_t *, party_t *,
## 			   party_t *, bool);
## extern void *sb_get_extra(switchboard_t *);
## extern void sb_set_extra(switchboard_t *, void *);
## extern void *sb_get_party_extra(party_t *);
## extern void sb_set_party_extra(party_t *, void *);
## extern sb_result_t *sb_automatic_switchboard(switchboard_t *, bool);
