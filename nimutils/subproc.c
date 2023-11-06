/*
 * Currently, we're using select() here, not epoll(), etc.
 */
#if defined(__linux__)
#include <pty.h>
#elif defined(__APPLE__)
#include <util.h>
#else
#error "Platform not supported"
#endif
#include <stdio.h>
#ifndef SWITCHBOARD_H__
#include "switchboard.h"
#if defined(SB_DEBUG) || defined(SB_TEST)
#include "test.c"
#include "hex.h"
#endif
#endif

extern int party_fd(party_t *party);
/*
 * Initializes a `subprocess` context, setting the process to spawn.
 * By default, it will *not* be run on a pty; call `subproc_use_pty()`
 * before calling `subproc_run()` in order to turn that on.
 *
 * By default, the process will run QUIETLY, without any capture or
 * passthrough of IO.  See `subproc_set_passthrough()` for routing IO
 * between the subprocess and the parent, and `subproc_set_capture()`
 * for capturing output from the subprocess (or from your terminal).
 *
 * This does not take ownership of the strings passed in, and doesn't
 * use them until you call subproc_run(). In general, don't free
 * anything passed into this API until the process is done.
 */
void
subproc_init(subprocess_t *ctx, char *cmd, char *argv[])
{
    memset(ctx, 0, sizeof(subprocess_t));
    sb_init(&ctx->sb, DEFAULT_HEAP_SIZE);
    ctx->cmd         = cmd;
    ctx->argv        = argv;
    ctx->capture     = 0;
    ctx->passthrough = 0;

    sb_init_party_fd(&ctx->sb, &ctx->parent_stdin,  0, O_RDONLY, false, false);
    sb_init_party_fd(&ctx->sb, &ctx->parent_stdout, 1, O_WRONLY, false, false);
    sb_init_party_fd(&ctx->sb, &ctx->parent_stderr, 2, O_WRONLY, false, false);
}

/*
 * By default, we pass through the environment. Use this to set your own
 * environment.
 */
bool
subproc_set_envp(subprocess_t *ctx, char *envp[])
{
    if (ctx->run) {
	return false;
    }

    ctx->envp = envp;

    return true;
}

/*
 * This function passes the given string to the subprocess via
 * stdin. You can set this once before calling `subproc_run()`; but
 * after you've called `subproc_run()`, you can call this as many
 * times as you like, as long as the subprocess is open and its stdin
 * file descriptor hasn't been closed.
 */
bool
subproc_pass_to_stdin(subprocess_t *ctx, char *str, size_t len, bool close_fd)
{
    if (ctx->str_waiting || ctx->sb.done) {
	return false;
    }

    if (ctx->run && close_fd) {
	return false;
    }

    sb_init_party_input_buf(&ctx->sb, &ctx->str_stdin, str, len, false,
			    close_fd);

    if (ctx->run) {
	return sb_route(&ctx->sb, &ctx->str_stdin, &ctx->subproc_stdin);
    } else {
	ctx->str_waiting = true;

	if (close_fd) {
	    ctx->pty_stdin_pipe = true;
	}

	return true;
    }
}

/*
 * This controls whether I/O gets proxied between the parent process
 * and the subprocess.
 *
 * The `which` parameter should be some combination of the following
 * flags:
 *
 * SP_IO_STDIN   (what you type goes to subproc stdin)
 * SP_IO_STDOUT  (subproc's stdout gets written to your stdout)
 * SP_IO_STDERR
 *
 * SP_IO_ALL proxies everything. It's fine to use this even if no pty is used.
 *
 * If `combine` is true, then all subproc output for any proxied streams
 * will go to STDOUT.
 */
bool
subproc_set_passthrough(subprocess_t *ctx, unsigned char which, bool combine)
{
    if (ctx->run || which > SP_IO_ALL) {
	return false;
    }

    ctx->passthrough      = which;
    ctx->pt_all_to_stdout = combine;

    return true;
}

/*
 * This controls whether input from a file descriptor is captured into
 * a string that is available when the process ends.
 *
 * You can capture any stream, including what the user's typing on stdin.
 *
 * The `which` parameter should be some combination of the following
 * flags:
 *
 * SP_IO_STDIN   (what you type); reference for string is "stdin"
 * SP_IO_STDOUT  reference for string is "stdout"
 * SP_IO_STDERR  reference for string is "stderr"
 *
 * SP_IO_ALL captures everything. It's fine to use this even if no pty is used.
 *
 * If `combine` is true, then all subproc output for any streams will
 * be combined into "stdout".  Retrieve from the `sb_result_t` object
 * returned from `subproc_run()`, using the sp_result_...() api.
 */
bool
subproc_set_capture(subprocess_t *ctx, unsigned char which, bool combine)
{
    if (ctx->run || which > SP_IO_ALL) {
	return false;
    }

    ctx->capture          = which;
    ctx->pt_all_to_stdout = combine;

    return true;
}

bool
subproc_set_io_callback(subprocess_t *ctx, unsigned char which,
			switchboard_cb_t cb)
{
    if (ctx->run || which > SP_IO_ALL) {
	return false;
    }

    deferred_cb_t *cbinfo = (deferred_cb_t *)malloc(sizeof(deferred_cb_t));

    cbinfo->next  = ctx->deferred_cbs;
    cbinfo->which = which;
    cbinfo->cb    = cb;

    ctx->deferred_cbs =  cbinfo;

    return true;
}

/*
 * This sets how long to wait in `select()` for file-descriptors to be
 * ready with data to read. If you don't set this, there will be no
 * timeout, and it's possible for the process to die and for the file
 * descriptors associated with them to never return ready.
 *
 * If you have a timeout, a progress callback can be called.
 *
 * Also, when the process is not blocked on the select(), right before
 * the next select we check the status of the subprocess. If it's
 * returned and all its descriptors are marked as closed, and no
 * descriptors that are open are waiting to write, then the subprocess
 * switchboard will exit.
 */
void
subproc_set_timeout(subprocess_t *ctx, struct timeval *timeout)
{
    sb_set_io_timeout(&ctx->sb, timeout);
}

/*
 * Removes any set timeout.
 */
void
subproc_clear_timeout(subprocess_t *ctx)
{
    sb_clear_io_timeout(&ctx->sb);
}

/*
 * When called before subproc_run(), will spawn the child process on
 * a pseudo-terminal.
 */
bool
subproc_use_pty(subprocess_t *ctx)
{
    if (ctx->run) {
	return false;
    }
    ctx->use_pty = true;
    return true;
}

bool
subproc_set_startup_callback(subprocess_t *ctx, void (*cb)(void *))
{
    ctx->startup_callback = cb;
}

int
subproc_get_pty_fd(subprocess_t *ctx)
{
    return ctx->pty_fd;
}

static void
setup_subscriptions(subprocess_t *ctx, bool pty)
{
    party_t *stderr_dst = &ctx->parent_stderr;

    if (ctx->pt_all_to_stdout) {
	stderr_dst = &ctx->parent_stdout;
    }

    if (ctx->passthrough) {
	if (ctx->passthrough & SP_IO_STDIN) {
	    if (pty) {
		sb_route(&ctx->sb, &ctx->parent_stdin, &ctx->subproc_stdout);
	    }
	    else {
		sb_route(&ctx->sb, &ctx->parent_stdin, &ctx->subproc_stdin);
	    }
	}
	if (ctx->passthrough & SP_IO_STDOUT) {
	    sb_route(&ctx->sb, &ctx->subproc_stdout, &ctx->parent_stdout);
	}
	if (!pty && ctx->passthrough & SP_IO_STDERR) {
	    sb_route(&ctx->sb, &ctx->subproc_stderr, stderr_dst);
	}
    }

    if (ctx->capture) {
	if (ctx->capture & SP_IO_STDIN) {
	    sb_init_party_output_buf(&ctx->sb, &ctx->capture_stdin,
				  "stdin",  CAP_ALLOC);
	}
	if (ctx->capture & SP_IO_STDOUT) {
	    sb_init_party_output_buf(&ctx->sb, &ctx->capture_stdout,
				  "stdout", CAP_ALLOC);
	}

	if (ctx->combine_captures) {
	    if (!(ctx->capture & SP_IO_STDOUT) &&
		ctx->capture & SP_IO_STDERR) {
		if (ctx->capture & SP_IO_STDOUT) {
		    sb_init_party_output_buf(&ctx->sb, &ctx->capture_stdout,
					  "stdout", CAP_ALLOC);
		}
      	    }

	    stderr_dst = &ctx->capture_stdout;
	}
	else {
	    if (!pty && ctx->capture & SP_IO_STDERR) {
		sb_init_party_output_buf(&ctx->sb, &ctx->capture_stderr,
				      "stderr", CAP_ALLOC);
	    }

	    stderr_dst = &ctx->capture_stderr;
	}

	if (ctx->capture & SP_IO_STDIN) {
	    sb_route(&ctx->sb, &ctx->parent_stdin, &ctx->capture_stdin);
	}
	if (ctx->capture & SP_IO_STDOUT) {
	    sb_route(&ctx->sb, &ctx->subproc_stdout, &ctx->capture_stdout);
	}
	if (!pty && ctx->capture & SP_IO_STDERR) {
	    sb_route(&ctx->sb, &ctx->subproc_stderr, stderr_dst);
	}
    }

    if (ctx->str_waiting) {
	sb_route(&ctx->sb, &ctx->str_stdin, &ctx->subproc_stdin);
	ctx->str_waiting = false;
    }

    // Make sure calls to the API know we've started!
    ctx->run = true;
}

static void
subproc_do_exec(subprocess_t *ctx)
{
    if (ctx->envp) {
	execve(ctx->cmd, ctx->argv, ctx->envp);
    }
    else {
	execv(ctx->cmd, ctx->argv);
    }
    // If we get past the exec, kill the subproc, which will
    // tear down the switchboard.
    abort();
}

party_t *
subproc_new_party_callback(switchboard_t *ctx, switchboard_cb_t cb)
{
    party_t *result = (party_t *)calloc(sizeof(party_t), 1);
    sb_init_party_callback(ctx, result, cb);

    return result;
}


static void
subproc_install_callbacks(subprocess_t *ctx)
{
    deferred_cb_t *entry = ctx->deferred_cbs;

    while(entry) {
	entry->to_free = subproc_new_party_callback(&ctx->sb, entry->cb);
	if (entry->which & SP_IO_STDIN) {
	    sb_route(&ctx->sb, &ctx->parent_stdin, entry->to_free);
	}
	if (entry->which & SP_IO_STDOUT) {
	    sb_route(&ctx->sb, &ctx->subproc_stdout, entry->to_free);
	}
	if (entry->which & SP_IO_STDERR) {
	    sb_route(&ctx->sb, &ctx->subproc_stderr, entry->to_free);
	}
	entry = entry->next;
    }
}

static void
run_startup_callback(subprocess_t *ctx)
{
    if (ctx->startup_callback) {
	(*ctx->startup_callback)(ctx);
    }
}

static void
subproc_spawn_fork(subprocess_t *ctx)
{
    pid_t           pid;
    int             stdin_pipe[2];
    int             stdout_pipe[2];
    int             stderr_pipe[2];

    pipe(stdin_pipe);
    pipe(stdout_pipe);
    pipe(stderr_pipe);

    pid = fork();

    if (pid != 0) {
	close(stdin_pipe[0]);
	close(stdout_pipe[1]);
	close(stderr_pipe[1]);

	sb_init_party_fd(&ctx->sb, &ctx->subproc_stdin, stdin_pipe[1],
			 O_WRONLY, false, true);
	sb_init_party_fd(&ctx->sb, &ctx->subproc_stdout, stdout_pipe[0],
			 O_RDONLY, false, true);
	sb_init_party_fd(&ctx->sb, &ctx->subproc_stderr, stderr_pipe[0],
			 O_RDONLY, false, true);

	sb_monitor_pid(&ctx->sb, pid, &ctx->subproc_stdin, &ctx->subproc_stdout,
		    &ctx->subproc_stderr, true);
	subproc_install_callbacks(ctx);
	setup_subscriptions(ctx, false);
	run_startup_callback(ctx);
    } else {
	close(stdin_pipe[1]);
	close(stdout_pipe[0]);
	close(stderr_pipe[0]);
	dup2(stdin_pipe[0],  0);
	dup2(stdout_pipe[1], 1);
	dup2(stderr_pipe[1], 2);

	subproc_do_exec(ctx);
    }
}

void
termcap_set_raw_mode(struct termios *termcap) {
    termcap->c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
    //termcap->c_oflag &= ~OPOST;
    termcap->c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
    termcap->c_cflag &= ~(CSIZE | PARENB);
    termcap->c_cc[VMIN]  = 0;
    termcap->c_cc[VTIME] = 0;
    tcsetattr(1, TCSAFLUSH, termcap);
}

static void
subproc_spawn_forkpty(subprocess_t *ctx)
{
    struct winsize wininfo;
    struct termios *term_ptr = ctx->child_termcap;
    struct winsize *win_ptr  = &wininfo;
    pid_t           pid;
    int             pty_fd;
    int             stdin_pipe[2];


    tcgetattr(0, &ctx->saved_termcap);

    if (ctx->pty_stdin_pipe) {
	pipe(stdin_pipe);
    }

    // We're going to use a pipe for stderr to get a separate
    // stream. The tty FD will be stdin and stdout for the child
    // process.
    //
    // Also, if we want to close the subproc's stdin after an initial
    // write, we will dup2.
    //
    // Note that this means the child process will see isatty() return
    // true for stdin and stdout, but not stderr.
    if(!isatty(0)) {
	win_ptr  = NULL;
    } else {
	ioctl(0, TIOCGWINSZ, win_ptr);
    }

    pid = forkpty(&pty_fd, NULL, term_ptr, win_ptr);

    if (pid != 0) {
	if (ctx->pty_stdin_pipe) {
	    close(stdin_pipe[0]);
	    sb_init_party_fd(&ctx->sb, &ctx->subproc_stdin, stdin_pipe[1],
			     O_WRONLY, false, false);
	}

	ctx->pty_fd = pty_fd;

	sb_init_party_fd(&ctx->sb, &ctx->subproc_stdout, pty_fd, O_RDWR, true,
			 true);

	sb_monitor_pid(&ctx->sb, pid, &ctx->subproc_stdout,
		       &ctx->subproc_stdout, NULL, true);
	subproc_install_callbacks(ctx);
	setup_subscriptions(ctx, true);

	if (!ctx->parent_termcap) {
	    termcap_set_raw_mode(&ctx->saved_termcap);
	}
	else {
	    tcsetattr(1, TCSAFLUSH, ctx->parent_termcap);
	}
	int flags = fcntl(pty_fd, F_GETFL, 0) | O_NONBLOCK;
	fcntl(pty_fd, F_SETFL, flags);
	run_startup_callback(ctx);

    } else {

	setvbuf(stdout, NULL, _IONBF, (size_t) 0);
	setvbuf(stdin, NULL, _IONBF, (size_t) 0);
	
	if (ctx->pty_stdin_pipe) {
	    close(stdin_pipe[1]);
	    dup2(stdin_pipe[0], 0);
	}

	signal(SIGHUP,   SIG_DFL);
	signal(SIGINT,   SIG_DFL);
	signal(SIGILL,   SIG_DFL);
	signal(SIGABRT,  SIG_DFL);
	signal(SIGFPE,   SIG_DFL);
	signal(SIGKILL,  SIG_DFL);
	signal(SIGSEGV,  SIG_DFL);
	signal(SIGPIPE,  SIG_DFL);
	signal(SIGALRM,  SIG_DFL);
	signal(SIGTERM,  SIG_DFL);
	signal(SIGCHLD,  SIG_DFL);
	signal(SIGCONT,  SIG_DFL);
	signal(SIGSTOP,  SIG_DFL);
	signal(SIGTSTP,  SIG_DFL);
	signal(SIGTTIN,  SIG_DFL);
	signal(SIGTTOU,  SIG_DFL);
	signal(SIGWINCH, SIG_DFL);
	subproc_do_exec(ctx);
    }
}

void
termcap_get(struct termios *termcap) {
    tcgetattr(0, termcap);
}

void
termcap_set(struct termios *termcap) {
    tcsetattr(0, TCSANOW, termcap);
}

/*
 * Start a subprocess if you want to be responsible for making
 * sufficient calls to poll for IP, instead of having it run to
 * completion.
 *
 * If you use this, call subproc_poll() until it returns false,
 * at which point, call subproc_prepare_results().
 */
void
subproc_start(subprocess_t *ctx)
{
    if (ctx->use_pty) {
	subproc_spawn_forkpty(ctx);
    }
    else {
	subproc_spawn_fork(ctx);
    }
}

/*
 * Handle IO on the subprocess a single time. This is meant to be
 * called only when manually runnng the subprocess; if you call
 * subproc_run, don't use this interface!
 */
bool
subproc_poll(subprocess_t *ctx)
{
    return sb_operate_switchboard(&ctx->sb, false);
}

/*
 * Call this before querying any results.
 */
void
subproc_prepare_results(subprocess_t *ctx)
{
    sb_prepare_results(&ctx->sb);

    // Post-run cleanup.
    if (ctx->use_pty) {
	tcsetattr(0, TCSANOW, &ctx->saved_termcap);
    }
}

/*
 * Spawns a process, and runs it until the process has ended. The
 * process must first be set up with `subproc_init()` and you may
 * configure it with other `subproc_*()` calls before running.
 *
 * The results can be queried via the `subproc_get_*()` API.
 */
void
subproc_run(subprocess_t *ctx)
{
    subproc_start(ctx);
    sb_operate_switchboard(&ctx->sb, true);

    subproc_prepare_results(ctx);
}

/*
 * This destroys any allocated memory inside a `subproc` object.  You
 * should *not* call this until you're done with the `sb_result_t`
 * object, as any dynamic memory (like string captures) that you
 * haven't taken ownership of will get freed when you call this.
 *
 * This call *will* destroy to sb_result_t object.
 *
 * However, this does *not* free the `subprocess_t` object itself.
 */
void
subproc_close(subprocess_t *ctx)
{
    sb_destroy(&ctx->sb, false);

    deferred_cb_t *cbs = ctx->deferred_cbs;
    deferred_cb_t *next;

    while (cbs) {
	next = cbs->next;
	free(cbs->to_free);
	free(cbs);
	cbs = next;
    }
}

/*
 * Return the PID of the current subprocess.  Returns -1 if the
 * subprocess hasn't been launched.
 */
pid_t
subproc_get_pid(subprocess_t *ctx)
{
    monitor_t *subproc = ctx->sb.pid_watch_list;

    if (!subproc) {
	return -1;
    }
    return subproc->pid;
}

/*
 * If you've got captures under the given tag name, then this will
 * return whatever was captured. If nothing was captured, it will
 * return a NULL pointer.
 *
 * But if a capture is returned, it will have been allocated via
 * `malloc()` and you will be responsible for calling `free()`.
 */
char *
sp_result_capture(sp_result_t *ctx, char *tag, size_t *outlen)
{
    for (int i = 0; i < ctx->num_captures; i++) {
	if (!strcmp(tag, ctx->captures[i].tag)) {
	    *outlen = ctx->captures[i].len;
	    return ctx->captures[i].contents;
	}
    }

    *outlen = 0;
    return NULL;
}

char *
subproc_get_capture(subprocess_t *ctx, char *tag, size_t *outlen)
{
    return sp_result_capture(&ctx->sb.result, tag, outlen);
}

int
subproc_get_exit(subprocess_t *ctx, bool wait_for_exit)
{
    monitor_t *subproc = ctx->sb.pid_watch_list;

    if (!subproc) {
	return -1;
    }

    process_status_check(subproc, wait_for_exit);
    return subproc->exit_status;
}

int
subproc_get_errno(subprocess_t *ctx, bool wait_for_exit)
{
    monitor_t *subproc = ctx->sb.pid_watch_list;

    if (!subproc) {
	return -1;
    }

    process_status_check(subproc, wait_for_exit);
    return subproc->found_errno;
}

int
subproc_get_signal(subprocess_t *ctx, bool wait_for_exit)
{
    monitor_t *subproc = ctx->sb.pid_watch_list;

    if (!subproc) {
	return -1;
    }

    process_status_check(subproc, wait_for_exit);
    return subproc->term_signal;
}

void
subproc_set_parent_termcap(subprocess_t *ctx, struct termios *tc)
{
    ctx->parent_termcap = tc;
}

void
subproc_set_child_termcap(subprocess_t *ctx, struct termios *tc)
{
    ctx->child_termcap = tc;
}

void
subproc_set_extra(subprocess_t *ctx, void *extra)
{
    sb_set_extra(&ctx->sb, extra);
}

void *
subproc_get_extra(subprocess_t *ctx)
{
    return sb_get_extra(&ctx->sb);
}

#ifdef SB_TEST
void
capture_tty_data(switchboard_t *sb, party_t *party, char *data, size_t len)
{
    printf("Callback got %d bytes from fd %d\n", len, party_fd(party));
}

int
test1() {
    char        *cmd    = "/bin/cat";
    char        *args[] = { "/bin/cat", "../aes.nim", 0 };
    subprocess_t ctx;
    sb_result_t *result;
    struct timeval timeout = {.tv_sec = 0, .tv_usec = 1000 };

    subproc_init(&ctx, cmd, args);
    subproc_use_pty(&ctx);
    subproc_set_passthrough(&ctx, SP_IO_ALL, false);
    subproc_set_capture(&ctx, SP_IO_ALL, false);
    subproc_set_timeout(&ctx, &timeout);
    subproc_set_io_callback(&ctx, SP_IO_STDOUT, capture_tty_data);

    result = subproc_run(&ctx);

    while(result) {
	if (result->tag) {
	    print_hex(result->contents, result->content_len, result->tag);
	}
	else {
	    printf("PID: %d\n", result->pid);
	    printf("Exit status: %d\n", result->exit_status);
	}
	result = result->next;
    }
    return 0;
}

int
test2() {
    char        *cmd    = "/bin/cat";
    char        *args[] = { "/bin/cat", "-", 0 };

    subprocess_t ctx;
    sb_result_t *result;
    struct timeval timeout = {.tv_sec = 0, .tv_usec = 1000 };

    subproc_init(&ctx, cmd, args);
    subproc_set_passthrough(&ctx, SP_IO_ALL, false);
    subproc_set_capture(&ctx, SP_IO_ALL, false);
    subproc_pass_to_stdin(&ctx, test_txt, strlen(test_txt), true);
    subproc_set_timeout(&ctx, &timeout);
    subproc_set_io_callback(&ctx, SP_IO_STDOUT, capture_tty_data);

    result = subproc_run(&ctx);

    while(result) {
	if (result->tag) {
	    print_hex(result->contents, result->content_len, result->tag);
	}
	else {
	    printf("PID: %d\n", result->pid);
	    printf("Exit status: %d\n", result->exit_status);
	}
	result = result->next;
    }
    return 0;
}

int
test3() {
    char        *cmd    = "/usr/bin/less";
    char        *args[] = { "/usr/bin/less", "../aes.nim", 0 };
    subprocess_t ctx;
    sb_result_t *result;
    struct timeval timeout = {.tv_sec = 0, .tv_usec = 1000 };

    subproc_init(&ctx, cmd, args);
    subproc_use_pty(&ctx);
    subproc_set_passthrough(&ctx, SP_IO_ALL, false);
    subproc_set_capture(&ctx, SP_IO_ALL, false);
    subproc_set_timeout(&ctx, &timeout);
    subproc_set_io_callback(&ctx, SP_IO_STDOUT, capture_tty_data);

    result = subproc_run(&ctx);

    while(result) {
	if (result->tag) {
	    print_hex(result->contents, result->content_len, result->tag);
	}
	else {
	    printf("PID: %d\n", result->pid);
	    printf("Exit status: %d\n", result->exit_status);
	}
	result = result->next;
    }
    return 0;
}

int
test4() {
    char        *cmd    = "/bin/cat";
    char        *args[] = { "/bin/cat", "-", 0 };

    subprocess_t ctx;
    sb_result_t *result;
    struct timeval timeout = {.tv_sec = 0, .tv_usec = 1000 };

    subproc_init(&ctx, cmd, args);
    subproc_use_pty(&ctx);
    subproc_set_passthrough(&ctx, SP_IO_ALL, false);
    subproc_set_capture(&ctx, SP_IO_ALL, false);
    subproc_set_timeout(&ctx, &timeout);
    subproc_set_io_callback(&ctx, SP_IO_STDOUT, capture_tty_data);

    result = subproc_run(&ctx);

    while(result) {
	if (result->tag) {
	    print_hex(result->contents, result->content_len, result->tag);
	}
	else {
	    printf("PID: %d\n", result->pid);
	    printf("Exit status: %d\n", result->exit_status);
	}
	result = result->next;
    }
    return 0;
}


int main() {
    test1();
    test2();
    test3();
    test4();
}
#endif
