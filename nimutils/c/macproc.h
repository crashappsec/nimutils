#ifndef __MACPROC_H__
#define __MACPROC_H__

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

extern procinfo_t *proc_list(size_t *count);
extern procinfo_t *proc_list_one(size_t *count, int pid);
extern void        del_procinfo(procinfo_t *cur);

extern int errno;
extern void del_procinfo(procinfo_t *);
extern void get_more_procinfo(procinfo_t *, int);
extern procinfo_t *proc_list(size_t *);
extern procinfo_t *proc_list_one(size_t *, int);
#endif
