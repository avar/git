#ifndef HOOK_H
#define HOOK_H
#include "strbuf.h"
#include "strvec.h"
#include "run-command.h"
#include "list.h"

/*
 * Returns the path to the hook file, or NULL if the hook is missing
 * or disabled. Note that this points to static storage that will be
 * overwritten by further calls to find_hook and run_hook_*.
 *
 * If the hook is not a native hook (e.g. present in Documentation/githooks.txt)
 * find_hook() will die(). find_hook_gently() does not consult the native hook
 * list and will check for any hook name in the hooks directory regardless of
 * whether it is known. find_hook() should be used by internal calls to hooks,
 * and find_hook_gently() should only be used when the hookname was provided by
 * the user, such as by 'git hook run my-wrapper-hook'.
 */
const char *find_hook(const char *name);
const char *find_hook_gently(const char *name);

/*
 * A boolean version of find_hook()
 */
int hook_exists(const char *hookname);

struct hook {
	struct list_head list;
	/* The path to the hook */
	const char *command;

	unsigned from_hookdir : 1;

	/*
	 * Use this to keep state for your feed_pipe_fn if you are using
	 * run_hooks_opt.feed_pipe. Otherwise, do not touch it.
	 */
	void *feed_pipe_cb_data;
};

/*
 * Provides a linked list of 'struct hook' detailing commands which should run
 * in response to the 'hookname' event, in execution order.
 *
 * If allow_unknown is unset, hooks will be checked against the hook list
 * generated from Documentation/githooks.txt. Otherwise, any hook name will be
 * allowed. allow_unknown should only be set when the hook name is provided by
 * the user; internal calls to hook_list should make sure the hook they are
 * invoking is present in Documentation/githooks.txt.
 */
struct list_head* hook_list(const char *hookname, int allow_unknown);

/* Provides the number of threads to use for parallel hook execution. */
int configured_hook_jobs(void);

struct run_hooks_opt
{
	/* Environment vars to be set for each hook */
	struct strvec env;

	/* Args to be passed to each hook */
	struct strvec args;

	/*
	 * Number of threads to parallelize across, currently a stub,
	 * we use the parallel API for future-proofing, but we always
	 * have one hook of a given name, so this is always an
	 * implicit 1 for now.
	 */
	int jobs;

	/* Resolve and run the "absolute_path(hook)" instead of
	 * "hook". Used for "git worktree" hooks
	 */
	int absolute_path;

	/* Path to initial working directory for subprocess */
	const char *dir;

	/* Path to file which should be piped to stdin for each hook */
	const char *path_to_stdin;

	/*
	 * Callback and state pointer to ask for more content to pipe to stdin.
	 * Will be called repeatedly, for each hook. See
	 * hook.c:pipe_from_stdin() for an example. Keep per-hook state in
	 * hook.feed_pipe_cb_data (per process). Keep initialization context in
	 * feed_pipe_ctx (shared by all processes).
	 *
	 * See 'pipe_from_string_list()' for info about how to specify a
	 * string_list as the stdin input instead of writing your own handler.
	 */
	feed_pipe_fn feed_pipe;
	void *feed_pipe_ctx;

	/*
	 * Populate this to capture output and prevent it from being printed to
	 * stderr. This will be passed directly through to
	 * run_command:run_parallel_processes(). See t/helper/test-run-command.c
	 * for an example.
	 */
	consume_sideband_fn consume_sideband;

	/*
	 * A pointer which if provided will be set to 1 or 0 depending
	 * on if a hook was invoked (i.e. existed), regardless of
	 * whether or not that was successful. Used for avoiding
	 * TOCTOU races in code that would otherwise call hook_exist()
	 * after a "maybe hook run" to see if a hook was invoked.
	 */
	int *invoked_hook;
};

/*
 * To specify a 'struct string_list', set 'run_hooks_opt.feed_pipe_ctx' to the
 * string_list and set 'run_hooks_opt.feed_pipe' to 'pipe_from_string_list()'.
 * This will pipe each string in the list to stdin, separated by newlines.  (Do
 * not inject your own newlines.)
 */
int pipe_from_string_list(struct strbuf *pipe, void *pp_cb, void *pp_task_cb);

struct hook_cb_data {
	/* rc reflects the cumulative failure state */
	int rc;
	const char *hook_name;
	struct list_head *head;
	struct hook *run_me;
	struct run_hooks_opt *options;
	int *invoked_hook;
};

void run_hooks_opt_init_sync(struct run_hooks_opt *o);
void run_hooks_opt_init_async(struct run_hooks_opt *o);
void run_hooks_opt_clear(struct run_hooks_opt *o);

/*
 * Calls find_hook(hookname) and runs the hooks (if any) with
 * run_found_hooks().
 */
int run_hooks(const char *hook_name, struct run_hooks_opt *options);

/*
 * Takes an already resolved hook and runs it. Internally the simpler
 * run_hooks() will call this.
 */
int run_found_hooks(const char *hookname, struct list_head *hooks,
		    struct run_hooks_opt *options);

/* Empties the list at 'head', calling 'free_hook()' on each entry */
void clear_hook_list(struct list_head *head);

#endif
