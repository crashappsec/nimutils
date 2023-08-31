when not defined(macosx):
  import macros
  static:
    error "macproc.nim only loads on macos"

{.emit: """

#include <sys/sysctl.h>
#include <sys/proc_info.h>
#include <libproc.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <grp.h>
#include <uuid/uuid.h>

typedef struct {
    int   id;
    char *name;
} gidinfo_t;

typedef struct {
    int           pid;
    int           uid;
    int           gid;
    int           euid;
    int           ppid;
    char         *username;
    char         *path;
    int           argc;
    int           envc;
    char         *memblock;
    char        **argv;
    char        **envp;
    int           numgroups;
    gidinfo_t    *gids;
} procinfo_t;

procinfo_t *proc_list(size_t *count);
procinfo_t *proc_list_one(size_t *count, int pid);
void        del_procinfo(procinfo_t *cur);

extern int errno;
int maxalloc;

void
del_procinfo(procinfo_t *cur) {
    int i = 0;

    if (cur == NULL) {
	return;
    }

    while (cur[i].pid) {
	if (cur[i].username != NULL) {
	    free(cur[i].username);
	}
	if (cur[i].path != NULL) {
	    free(cur[i].path);
	}
	free(cur[i].memblock);

	if (cur[i].numgroups != 0) {
	    for (int j = 0; j < cur[i].numgroups; j++) {
		free(cur[i].gids[j].name);
	    }
	    free(cur[i].gids);
	}
	i++;
    }

    free(cur);
}

void __attribute__((constructor)) set_maxalloc() {
    int    kargmax[]  = {CTL_KERN, KERN_ARGMAX};
    size_t size;

    if (sysctl(kargmax, 2, &maxalloc, &size, NULL, 0) == -1) {
	abort();
    }
}

void
get_more_procinfo(procinfo_t *cur, int pid) {
    char *path = calloc(PROC_PIDPATHINFO_MAXSIZE, 1);

    proc_pidpath(pid, path, PROC_PIDPATHINFO_MAXSIZE);
    cur->path = realloc(path, strlen(path) + 1);


    int procargs[] = {CTL_KERN, KERN_PROCARGS2, pid};

    size_t size;

    char *memblock = (char *)calloc(maxalloc, 1);

    if (!memblock) {
	return;
    }

    size = maxalloc;

    if (sysctl(procargs, 3, memblock, &size, NULL, 0) == -1) {
	free(memblock);
	cur->argc = 0;
	cur->envc = 0;
	return;
    }

    memblock      = realloc(memblock, size);
    cur->argc     = *(int *)memblock;
    cur->memblock = memblock;

    char *p = memblock + sizeof(int);

    // Skip path info; it's only partial, which is why we use proc_pidpath()
    while(*p != 0) { p++; }

    // Skip any nulls after the path;
    while(*p == 0) { p++; }

    cur->argv = calloc(sizeof(char *), cur->argc);

    for (int i = 0; i < cur->argc; i++) {
	cur->argv[i] = p;

	while (*p) p++;
	p++;
    }

    char *env_start = p;

    cur->envc = 0;

    while (*p) {
	cur->envc++;
	while(*p++);
    }

    p         = env_start;
    cur->envp = calloc(sizeof(char *), cur->envc);

    for (int i = 0; i < cur->envc; i++) {
	cur->envp[i] = p;

	while (*p) p++;
    }
}

/* Even though this seems like it allocates an insane amount of memory,
 * It's still plenty fast.
 *
 * For instance, I get a len of 284472 (which I expect is the next pid?)
 * but there are only 438 procs.
 *
 * The OS seems to put valid results all together, so the break
 * statement appears to work fine.
 *
 * But I've tested performance w/ a continue in the second loop
 * instead, and it's definitely a lot slower, but still runs in less
 * than .1 sec on my laptop (as opposed to around .01 seconds).
 */
procinfo_t *
proc_list(size_t *count) {
    int                err;
    struct kinfo_proc *result, *to_free;
    procinfo_t        *pi;
    procinfo_t        *to_return;
    int                name[] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL};
    size_t             i, len;
    size_t             valid = 0;

    // This loop should only ever run once from what I can tell, because
    // the OS has us massively over-allocate.
    while (true) {
	err = sysctl(name, 3, NULL, &len, NULL, 0);
	if (err != 0) {
	    return NULL;
	}

	result  = (struct kinfo_proc *)calloc(sizeof(struct kinfo_proc), len);
	to_free = result;

	if (result == NULL) {
	    return NULL;
	}
	if (sysctl(name, 3, result, &len, NULL, 0) == -1) {
	    free(result);
	}
	else {
	    break;
	}
    }

    // Add an extra one where we drop in pid = 0 as a sentinel.
    // Not that we're likely to need it.
    pi        = (procinfo_t *)calloc(sizeof(procinfo_t), len + 1);
    to_return = pi;

    for (i = 0; i < len; i++) {
	int pid = result->kp_proc.p_pid;

	if (!pid) {
	    printf("Stopping after: %d\n", i);
	    pi->pid = 0;
	    break;
	}

	valid = valid + 1;

	pi->pid       = pid;
	pi->ppid      = result->kp_eproc.e_ppid;
	pi->uid       = result->kp_eproc.e_pcred.p_ruid;
	pi->gid       = result->kp_eproc.e_pcred.p_rgid;
	pi->euid      = result->kp_eproc.e_ucred.cr_uid;
	pi->numgroups = result->kp_eproc.e_ucred.cr_ngroups;

	struct passwd *pwent = getpwuid(pi->uid);
	pi->username         = strdup(pwent->pw_name);

	struct group *ginfo;

	if (pi->numgroups == 0) {
	    pi->gids = NULL;
	} else {
	    // Seems to be a ton of dupes, so skipping them.
	    int sofar = 0;
	    pi->gids  = calloc(sizeof(gidinfo_t), pi->numgroups);

	    for (int i = 0; i < pi->numgroups; i++) {
		for (int j = 0; j < sofar; j++) {
		    if(pi->gids[j].id ==
		       result->kp_eproc.e_ucred.cr_groups[i]) {
			goto skip_copy;
		    }
		}
		pi->gids[sofar].id   = result->kp_eproc.e_ucred.cr_groups[i];
		ginfo                = getgrgid(pi->gids[i].id);
		pi->gids[sofar].name = strdup(ginfo->gr_name);
		sofar++;

	    skip_copy:
		continue;
	    }
	    pi->numgroups = sofar;
	}

	get_more_procinfo(pi, pid);

	pi++;
	result++;
    }

    free(to_free);

    *count = valid;

    to_return[valid].pid = 0;

    return realloc(to_return, sizeof(procinfo_t) * (valid + 1));
}

procinfo_t *
proc_list_one(size_t *count, int pid) {
    int                err;
    struct kinfo_proc *result;
    procinfo_t        *to_return;
    int                name[] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    size_t             i, len;
    size_t             valid = 0;

    while (true) {
	err = sysctl(name, 4, NULL, &len, NULL, 0);
	if (err != 0) {
	    return NULL;
	}

	result = (struct kinfo_proc *)calloc(sizeof(struct kinfo_proc), len);
	if (result == NULL) {
	    return NULL;
	}
	if (sysctl(name, 4, result, &len, NULL, 0) == -1) {
	    free(result);
	}
	else {
	    if (len != 1) {
		return NULL;
	    }
	    break;
	}
    }

    to_return = (procinfo_t *)calloc(sizeof(procinfo_t), len);

    for (i = 0; i < len; i++) {
	struct kinfo_proc *oneProc = &result[i];
	int pid = oneProc->kp_proc.p_pid;

	if (!pid) continue;

	valid = valid + 1;

	to_return[i].pid  = pid;
	to_return[i].ppid = oneProc->kp_eproc.e_ppid;
	to_return[i].uid  = oneProc->kp_eproc.e_ucred.cr_uid;

	get_more_procinfo(&to_return[i], pid);
    }

    free(result);

    *count = valid;

    return to_return;
}

#if 1
int
demo_ps() {
    procinfo_t *info;
    size_t      num;
    int         err;

    info = proc_list(&num);

    for (int i = 0; i < num; i++) {
	printf("%6d: %s ", info[i].pid, info[i].path);
	for(int j = 0; j < info[i].argc; j++) {
	    printf("%s ", info[i].argv[j]);
	}
      printf("uid = %d gid = %d ppid = %d uname = %s nargs = %d nenv = %d",
	     info[i].uid, info[i].gid, info[i].ppid,
	     info[i].username, info[i].argc, info[i].envc);

      if (info[i].numgroups != 0) {
	  printf(" #groups = %d groups = ", info[i].numgroups);
	  for (int j = 0; j < info[i].numgroups; j++) {
	      printf("%s(%d) ", info[i].gids[j].name,
		     info[i].gids[j].id);
	  }
      }

      printf("\n");
    }

    printf("\nFound %zu procs\n", num);

    del_procinfo(info);
    return 0;
}
#endif

""".}

from macros import hint

type
  gidinfot_469762363 {.pure, inheritable, bycopy.} = object
    id*: cint                ## Generated based on /Users/viega/dev/chalk-internal/futhark/macproc.h:16:9
    name*: cstring

  procinfot_469762366 {.pure, inheritable, bycopy.} = object
    pid*: cint               ## Generated based on /Users/viega/dev/chalk-internal/futhark/macproc.h:21:9
    uid*: cint
    gid*: cint
    euid*: cint
    ppid*: cint
    username*: cstring
    path*: cstring
    argc*: cint
    envc*: cint
    memblock*: cstring
    argv*: ptr ptr cschar
    envp*: ptr ptr cschar
    numgroups*: cint
    gids*: ptr gidinfot_469762365

  procinfot_469762367 = (when declared(procinfot):
    procinfot
   else:
    procinfot_469762366)
  gidinfot_469762365 = (when declared(gidinfot):
    gidinfot
   else:
    gidinfot_469762363)

when not declared(procinfot):
  type
    procinfot* = procinfot_469762366
else:
  static :
    hint("Declaration of " & "procinfot" & " already exists, not redeclaring")
when not declared(gidinfot):
  type
    gidinfot* = gidinfot_469762363
else:
  static :
    hint("Declaration of " & "gidinfot" & " already exists, not redeclaring")
when not declared(proclist):
  proc proclist*(count: ptr csize_t): ptr procinfot_469762367 {.cdecl,
      importc: "proc_list".}
else:
  static :
    hint("Declaration of " & "proclist" & " already exists, not redeclaring")
when not declared(proclistone):
  proc proclistone*(count: ptr csize_t; pid: cint): ptr procinfot_469762367 {.
      cdecl, importc: "proc_list_one".}
else:
  static :
    hint("Declaration of " & "proclistone" & " already exists, not redeclaring")
when not declared(delprocinfo):
  proc delprocinfo*(cur: ptr procinfot_469762367): void {.cdecl,
      importc: "del_procinfo".}
else:
  static :
    hint("Declaration of " & "delprocinfo" & " already exists, not redeclaring")


proc demops*(): cint {.discardable,cdecl,importc: "demo_ps".}

type ProcInfoT = object of procInfoT
proc `=destroy`*(ctx: var ProcInfoT) =
    delProcInfo(addr ctx)

when isMainModule:
  demops()
