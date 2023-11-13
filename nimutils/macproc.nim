when not defined(macosx):
  static:
    error "macproc.nim only loads on macos"

import os, posix

{.compile: joinPath(splitPath(currentSourcePath()).head, "c/macproc.c").}

type
  CGidInfo* {.importc: "gidinfo_t", header: "macproc.h", bycopy.} = object
    id*: cint
    name*: cstring

  CProcInfo* {.importc: "procinfo_t", header: "macproc.h", bycopy.} = object
    pid*: cint
    uid*: cint
    gid*: cint
    euid*: cint
    ppid*: cint
    username*: cstring
    path*: cstring
    argc*: cint
    envc*: cint
    memblock*: cstring
    argv*: ptr UncheckedArray[cstring]
    envp*: ptr UncheckedArray[cstring]
    numgroups*: cint
    gids*: ptr UncheckedArray[CGidInfo]

  GroupInfo* = object
    id*:   Gid
    name*: string

  ProcessInfo* = object
    pid*:      Pid
    uid*:      Uid
    gid*:      Gid
    euid*:     Uid
    ppid*:     Pid
    username*: string
    path*:     string
    argv*:     seq[string]
    envp*:     seq[string]
    groups*:   seq[GroupInfo]

proc proc_list*(count: ptr csize_t): ptr UncheckedArray[CProcInfo]
    {. cdecl, importc, header: "macproc.h" .}
proc proc_list_one*(count: ptr csize_t; pid: Pid): ptr CProcInfo
    {. cdecl, importc, header: "macproc.h" .}
proc del_procinfo*(cur: ptr CProcInfo) {. cdecl, importc, header: "macproc.h" .}

template copyProcessInfo(nimOne: var ProcessInfo, cOne: CProcInfo) =
    nimOne.pid      = Pid(cOne.pid)
    nimOne.uid      = Uid(cOne.uid)
    nimOne.gid      = Gid(cOne.gid)
    nimOne.euid     = Uid(cOne.euid)
    nimOne.ppid     = Pid(cOne.ppid)
    nimOne.username = $(cOne.username)
    nimOne.path     = $(cOne.path)

    if cOne.argc > 0:
      for j in 0 ..< cOne.argc:
        nimOne.argv.add($(cOne.argv[j]))

    if cOne.envc > 0:
      for j in 0 ..< cOne.envc:
        nimOne.envp.add($(cOne.envp[j]))

    if cOne.numgroups > 0:
      for j in 0 ..< cOne.numgroups:
        let grpObj = cOne.gids[j]
        nimOne.groups.add(GroupInfo(id: Gid(grpObj.id), name: $(grpObj.name)))

proc listProcesses*(): seq[ProcessInfo] =
  var num: csize_t

  let procInfo = proc_list(addr num)

  for i in 0 ..< num:
    var nimOne: ProcessInfo

    nimOne.copyProcessInfo(procInfo[i])
    result.add(nimOne)

  del_procinfo(addr procInfo[0])

proc getProcessInfo*(pid: Pid): ProcessInfo =
  var num: csize_t

  let procInfo = proc_list_one(addr num, pid)

  if num == 0:
    raise newException(ValueError, "PID not found")

  result.copyProcessInfo(procInfo[])
  del_procinfo(procInfo);

proc getPid*(o: ProcessInfo): Pid = o.pid
proc getUid*(o: ProcessInfo): Uid = o.uid
proc getGid*(o: ProcessInfo): Gid = o.gid
proc getEuid*(o: ProcessInfo): Uid = o.euid
proc getParentPid*(o: ProcessInfo): Pid = o.ppid
proc getUserName*(o: ProcessInfo): string = o.username
proc getExePath*(o: ProcessInfo): string = o.path
proc getArgv*(o: ProcessInfo): seq[string] = o.argv
proc getEnvp*(o: ProcessInfo): seq[string] = o.envp
proc getGroups*(o: ProcessInfo): seq[GroupInfo] = o.groups

proc getGid*(o: GroupInfo): Gid = o.id
proc getGroupName*(o: GroupInfo): string = o.name
