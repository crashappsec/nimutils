#ifndef SWITCHBOARD_H__
#define SWITCHBOARD_H__

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <termios.h>
#include <util.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/types.h>
#include <sys/ioctl.h>

#define DEFAULT_HEAP_SIZE (256) 
#define SB_ALLOC_LEN (PIPE_BUF + sizeof(struct sb_msg_t))
#define SB_MSG_LEN PIPE_BUF

typedef enum
{ PT_STRING = 1, PT_FD = 2, PT_LISTENER = 4, PT_CALLBACK = 8} party_e;


typedef void (*switchboard_cb_t)(void *, void *, char *, size_t);
typedef void (*accept_cb_decl)(void *, int fd, struct sockaddr *, socklen_t *);
typedef bool (*progress_cb_decl)(void *);

/* We queue these messages up for parties registered for writing, but
 * only if the sink is a file descriptor; callbacks and strings will
 * have the write processed immediately when the reader generates it.
 *
 * Note that we alloc these messages in some bulk; the switchboard_t
 * context below handles the memory management.
 *
 * In most systems when no reader is particularly slow relative to
 * others, there may never need to be more than one malloc call.
 */
typedef struct sb_msg_t {
    struct sb_msg_t *next;
    size_t           len;
    char             data[SB_MSG_LEN + 1];
} sb_msg_t;

/*
 * This is the heap data type; the switchboard mallocs one heap at a
 * time, and hands out sb_msg_t's from it. The switchboard also keeps
 * a list of returned cells, and prefers returned cells over giving
 * out unused cells from the heap.
 *
 * If there's nothing left to give out in the heap or in the free
 * list, then we create a new heap (keeping the old one linked).
 *
 * When we get rid of our switchboard, we free any heaps, and can
 * ignore individual sb_msg_t objects.
 */
typedef struct sb_heap_t {
    struct sb_heap_t *next;
    size_t            cur_cell;
    sb_msg_t          cells[];
} sb_heap_t;

/*
 * For file descriptors that we might read from, where we might proxy
 * the data to some other file descriptor, we keep a linked list of
 * subscriber information.
 *
 * Only parties implemented as FDs are allowed to have
 * subscribers. Strings are the other source for input, but those are
 * 'published' immediately when the string is connected to the output.
 */
typedef struct subscription_t {
    struct subscription_t *next;
    struct party_t        *subscriber;
} subscription_t;

/*
 * This abstraction is used for any party that's a file descriptor.
 * If the file descriptor is read-only, the first_msg and last_msg
 * fields will be unused.
 *
 * If the FD is write-only, then subscribers will not be used.
 */
typedef struct {
    int             fd;
    sb_msg_t       *first_msg;
    sb_msg_t       *last_msg;
    subscription_t *subscribers;
} fd_party_t;

/*
 * This is used for listening sockets.
 */
typedef struct {
    int            fd;
    accept_cb_decl accept_cb;
    int            saved_flags;
} listener_party_t;

/*
 * For strings being piped into a process, pipe or whatever.
 */
typedef struct {
    char   *strbuf;
    bool    free_on_close;      // Did we take ownership of the str?
    size_t  len;                // Total length of strbuf.
    bool    close_fd_when_done; // Close the fd after writing?
} str_src_party_t;

/*
 * For buffer output into a string that's fully returned at the end.
 * If you want incremental output, use a callback.
 */
typedef struct {
    char  *strbuf;
    size_t len;            // Length allocated for strbuf
    size_t ix;             // Current length; next write at strbuf + ix
    char  *tag;            // Used when returning.
    size_t step;           // Step for alloc length
} str_dst_party_t;

/*
 * For incremental output! If you need to save state, you can do it by
 * assigning to either the swichboard_t 'extra' field or the party_t
 * 'extra' field; these are there for you to be able to keep state.
 */
typedef struct {
    switchboard_cb_t callback;
} callback_party_t;

/*
 * The union for the five party types above.
 */
typedef union {
    str_src_party_t  rstrinfo;     // Strings used as an input source only 
    str_dst_party_t  wstrinfo;     // Strings used as an output sink only
    fd_party_t       fdinfo;       // Can be source, sink or both.
    listener_party_t listenerinfo; // We only read from it to kick off accept cb
    callback_party_t cbinfo;       // Sink only.
} party_info_t;

/*
 * The common abstraction for parties.
 * - `erno` will hold the value of any captured (fatal) os error we
 *    ran accross. This is only used for PT_FD and PT_LISTENER.
 * - `open` tracks whether we should deal with this party at all anymore;
 *   it can mean the fd is closed, or that nothing is routed to it anymore.
 * - `can_read_from_it` and `can_write_to_it` indicates whether a party is 
 *   a source (the former) or a sink (the later). Can be both, too.
 * - `close_on_destroy` indicates that we should call close() on any file
 *   descriptors when tearing down the switchboard. 
 *   When this is set, we do not report errors in close(), and we
 *   assume the same fd won't have been reused if it was otherwise
 *   closed during the switchboard operation.
 *   This only gets used for objs of type `PT_FD` and `PT_LISTENER`
 * - `stop_on_close` indicates that, when we notice a failure to
 *   read/write from a file descriptor, we should stop the switchboard;
 *   we do go ahead and finish available reads/writes, but we do nothing
 *   else.
 *   This should generally be the behavior you want when stdin, stdout
 *   or stderr go away (the controlling terminal is probably gone).
 *   However, it's not the right behavior for when a sub-process dies;
 *   There, you want to drain the read-size of the file descriptor.
 *   For that, you register the sub-process with `sb_monitor_pid()`.
 * - `next_reader`, `next_writer` and `next_loner` are three linked lists;
 *   a party might appear on up to two at once. `next_reader` and
 *   `next_writer` are only used for fd types. The first list can have
 *   both `PT_FD`s and `PT_LISTENER`s; the second only `PT_FD`s.
 *   The switchboard runs down these to figure out what to select() on.
 *   And, then when exiting, these lists are walked to free `party_t`
 *   objects.
 *   `next_loner` is for all other types, and is only used at the end to
 *   free stuff.
 * - `extra` is user-defined, ideal for state keeping in callbacks.
 */
typedef struct party_t {
    party_e         party_type;
    party_info_t    info;
    int             found_errno;
    bool            open_for_write;
    bool            open_for_read;
    bool            can_read_from_it;
    bool            can_write_to_it;
    bool            close_on_destroy;
    bool            stop_on_close;
    struct party_t *next_reader;
    struct party_t *next_writer;    
    struct party_t *next_loner;
    void           *extra;    
} party_t;

/*
 * When some of the i/o consists of other processes, we check on the
 * status of each process after every select call. This both keeps
 * state we need to monitor those processes, and anything we might
 * return about the process when returning switchboard results.
 */
typedef struct monitor_t {
    struct monitor_t *next;
    pid_t             pid;
    party_t          *stdin_fd_party; 
    party_t          *stdout_fd_party;
    party_t          *stderr_fd_party;
    bool              shutdown_when_closed;
    bool              closed;
    int               found_errno;
    int               term_signal;
    int               exit_status;
} monitor_t;    

/*
 * The main switchboard object. Generally, the fields here can be
 * transparent to the user; everything should be dealt with via API.
 */
typedef struct switchboard_t {
    struct timeval   *io_timeout_ptr;
    struct timeval    io_timeout;
    progress_cb_decl  progress_callback;
    bool              progress_on_timeout_only;
    bool              done;
    fd_set            readset;
    fd_set            writeset;
    int               max_fd;
    int               fds_ready; // Used to determine if we timed out.
    party_t          *parties_for_reading;
    party_t          *parties_for_writing;
    party_t          *party_loners;
    monitor_t        *pid_watch_list;
    sb_msg_t         *freelist;
    sb_heap_t        *heap;
    size_t            heap_elems;
    void             *extra;
    bool              ignore_running_procs_on_shutdown;
} switchboard_t;

typedef struct sb_result_t {
    struct sb_result_t *next;
    char               *tag; // only for string outputs.
    char               *contents;
    size_t              content_len;
    bool                exited;
    int                 found_errno;
    int                 term_signal;
    int                 exit_status;
    pid_t               pid;
} sb_result_t;

typedef sb_result_t sp_result_t;

typedef struct {
    sb_result_t    *result;
    switchboard_t  sb;
    bool           run;
    bool           use_pty;
    bool           pty_stdin_pipe;
    bool           str_waiting;
    char          *cmd;
    char         **argv;
    char         **envp;
    char          *path;
    char           passthrough;
    bool           pt_all_to_stdout;
    char           capture;
    bool           combine_captures;  // Combine stdout / err and termout
    party_t        str_stdin;
    party_t        parent_stdin;
    party_t        parent_stdout;
    party_t        parent_stderr;
    party_t        subproc_stdin;
    party_t        subproc_stdout;
    party_t        subproc_stderr;
    party_t        capture_stdin;
    party_t        capture_stdout;
    party_t        capture_stderr;
    struct termios saved_termcap;
    struct dcb_t  *deferred_cbs;
} subprocess_t;

#define SP_IO_STDIN     1
#define SP_IO_STDOUT    2
#define SP_IO_STDERR    4
#define SP_IO_ALL       7
#define CAP_ALLOC       16 // In # of PIPE_BUF sized chunks

// These are the real signatures.
typedef void (*accept_cb_t)(struct switchboard_t *, int fd,
			    struct sockaddr *, socklen_t *);
typedef bool (*progress_cb_t)(struct switchboard_t *);

typedef struct dcb_t {
    struct dcb_t       *next;
    unsigned char       which;
    switchboard_cb_t    cb;
    party_t            *to_free;
} deferred_cb_t;

extern ssize_t read_one(int, char *, size_t);
extern bool write_data(int, char *, size_t);
extern void sb_init_party_listener(switchboard_t *, party_t *, int,
	 		        accept_cb_t, bool, bool);
extern party_t * sb_new_party_listener(switchboard_t *, int, accept_cb_t, bool,
				    bool);
extern void sb_init_party_fd(switchboard_t *, party_t *, int , int , bool,
			     bool);
extern party_t *sb_new_party_fd(switchboard_t *, int, int, bool, bool);
extern void sb_init_party_input_buf(switchboard_t *, party_t *, char *, size_t,
				 bool, bool);
extern party_t *sb_new_party_input_buf(switchboard_t *, char *, size_t, bool,
				    bool);
extern void sb_init_party_output_buf(switchboard_t *, party_t *, char *,
				     size_t);
extern party_t *sb_new_party_output_buf(switchboard_t *, char *, size_t);
extern void sb_init_party_callback(switchboard_t *, party_t *,
				   switchboard_cb_t);
extern party_t *sb_new_party_callback(switchboard_t *, switchboard_cb_t);
extern void sb_monitor_pid(switchboard_t *, pid_t, party_t *, party_t *,
			   party_t *, bool);
extern void *sb_get_extra(switchboard_t *);
extern void sb_set_extra(switchboard_t *, void *);
extern void *sb_get_party_extra(party_t *);
extern void sb_set_party_extra(party_t *, void *);
extern bool sb_route(switchboard_t *, party_t *, party_t *);
extern void sb_init(switchboard_t *, size_t);
extern void sb_set_io_timeout(switchboard_t *, struct timeval *);
extern void sb_clear_io_timeout(switchboard_t *);
extern void sb_destroy(switchboard_t *, bool);
extern bool sb_operate_switchboard(switchboard_t *, bool);
extern sb_result_t *sb_automatic_switchboard(switchboard_t *, bool);
extern void subproc_init(subprocess_t *, char *, char *[]);
extern bool subproc_set_envp(subprocess_t *, char *[]);
extern bool subproc_pass_to_stdin(subprocess_t *, char *, size_t, bool);
extern bool subproc_set_passthrough(subprocess_t *, unsigned char, bool);
extern bool subproc_set_capture(subprocess_t *, unsigned char, bool);
extern bool subproc_set_io_callback(subprocess_t *, unsigned char,
                                    switchboard_cb_t);
extern void subproc_set_timeout(subprocess_t *, struct timeval *);
extern void subproc_clear_timeout(subprocess_t *);
extern bool subproc_use_pty(subprocess_t *);
extern void subproc_start(subprocess_t *);
extern bool subproc_poll(subprocess_t *);
extern sb_result_t *subproc_get_result(subprocess_t *);
extern sp_result_t *subproc_run(subprocess_t *);
extern void subproc_close(subprocess_t *);
extern pid_t subproc_get_pid(subprocess_t *);
extern void sp_result_delete(sp_result_t *);
extern char *sp_result_capture(sp_result_t *, char *, size_t *);
extern int sp_result_exit(sp_result_t *);
extern int sp_result_errno(sp_result_t *);
extern int sp_result_signal(sp_result_t *);
extern char *subproc_get_capture(subprocess_t *, char *, size_t *);
extern int subproc_get_exit(subprocess_t *);
extern int subproc_get_errno(subprocess_t *);
extern int subproc_get_signal(subprocess_t *);
extern void subproc_set_extra(subprocess_t *, void *);
extern void *subproc_get_extra(subprocess_t *);

// pty params.
// ASCII Cinema.
#endif

