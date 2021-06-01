#include "cache.h"
#include "builtin.h"
#include "config.h"
#include "hook.h"
#include "parse-options.h"
#include "strbuf.h"
#include "strvec.h"

static const char * const builtin_hook_usage[] = {
	N_("git hook run [--to-stdin=<path>] <hook-name> [-- <hook-args>]"),
	NULL
};

static int run(int argc, const char **argv, const char *prefix)
{
	int i;
	struct run_hooks_opt opt = RUN_HOOKS_OPT_INIT;
	int rc = 0;
	int ignore_missing = 0;
	const char *hook_name;
	const char *hook_path;

	struct option run_options[] = {
		OPT_BOOL(0, "ignore-missing", &ignore_missing,
			 N_("exit quietly with a zero exit code if the requested hook cannot be found")),
		OPT_STRING(0, "to-stdin", &opt.path_to_stdin, N_("path"),
			   N_("file to read into hooks' stdin")),
		OPT_END(),
	};

	argc = parse_options(argc, argv, prefix, run_options,
			     builtin_hook_usage, PARSE_OPT_KEEP_UNKNOWN | PARSE_OPT_KEEP_DASHDASH);

	if (argc > 2) {
		if (strcmp(argv[2], "--") &&
		    strcmp(argv[2], "--end-of-options"))
			/* Having a -- for "run" is mandatory */
			usage_with_options(builtin_hook_usage, run_options);
		/* Add our arguments, start after -- */
		for (i = 3 ; i < argc; i++)
			strvec_push(&opt.args, argv[i]);
	}

	/* Need to take into account core.hooksPath */
	git_config(git_default_config, NULL);

	hook_name = argv[1];
	hook_path = find_hook(hook_name);
	if (!hook_path) {
		if (ignore_missing)
			return 0;
		error("cannot find a hook named %s", hook_name);
		return 1;
	}
	rc = run_found_hooks(hook_name, hook_path, &opt);

	run_hooks_opt_clear(&opt);

	return rc;
}

int cmd_hook(int argc, const char **argv, const char *prefix)
{
	struct option builtin_hook_options[] = {
		OPT_END(),
	};

	if (!strcmp(argv[1], "run"))
		return run(argc, argv, prefix);
	usage_with_options(builtin_hook_usage, builtin_hook_options);
	return 1;
}
