#include "macproc.h"

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
    size_t             valid    = 0;
    int                failsafe = 0;

    // This loop should only ever run once from what I can tell, because
    // the OS has us massively over-allocate.
    // If this goes more than 10 loops, we bail.
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
	    if (failsafe++ == 10) {
		return NULL;
	    }
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
    size_t             valid    = 0;
    int                failsafe = 0;

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

	    if (failsafe++ == 10) {
		return NULL;
	    }
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
