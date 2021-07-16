#include "test-tool.h"
#include "gettext.h"
#include "parse-options.h"
#include "strbuf.h"

/*
 * This is a "close enough" version of Perl's
 * TAP::Parser::Grammar. TAP could still get past it (e.g. "Bail out!"
 * surrounded by whitespace, but it's exceedingly unlikely to matter
 * for git's tests.
 */
static int line_has_tap(const char *str)
{
	if (starts_with(str, "ok") ||
	    starts_with(str, "not ok") ||
	    starts_with(str, "1..") ||
	    starts_with(str, "Bail out!") ||
	    starts_with(str, "TAP version") ||
	    starts_with(str, "pragma") ||
	    starts_with(str, "#"))
		return 1;
	return  0;
}

int cmd__tee_tap(int argc, const char **argv)
{
	int out_only_tap = 0;
	int comment_level = -1;
	int out_escape = 0, file_escape = 0;
	char *prefix = NULL;
	size_t prefix_len = 0;
	const char *usage[] = {
		"test-tool tee-tap [<options>] <FILE>",
		NULL
	};
	struct option options[] = {
		OPT_BOOL(0, "out-only-tap", &out_only_tap,
			 "only emit TAP on stdout"),
		OPT_BOOL(0, "out-escape", &out_escape,
			 "escape bad TAP output on stdout"),
		OPT_BOOL(0, "file-escape", &file_escape,
			 "escape bad TAP output to file"),
		OPT_INTEGER(0, "out-comment-level",
			    &comment_level,
			    "allow '#' N-level comments under --out-only-tap"),
		OPT_STRING(0, "prefix", &prefix, "str",
			   "prefix to strip from the output"),
		OPT_END()
	};
	struct strbuf line = STRBUF_INIT;
	FILE *logfp = NULL;

	argc = parse_options(argc, argv, NULL, options, usage,
			     PARSE_OPT_STOP_AT_NON_OPTION);

	if (prefix)
		prefix_len = strlen(prefix);
	if (argc)
		logfp = xfopen(argv[0], "w");
	if (comment_level < 0)
		comment_level = 1;

	if (argc > 1 ||
	    /* Plain pass-though? No point, use tee(1) */
	    !prefix ||
	    /* Escape output we guarantee not to emit? */
	    (out_only_tap && out_escape) ||
	    /* Or something not asked for? */
	    (!logfp && file_escape) ||
	    /* That's just crazy */
	    line_has_tap(prefix))
		usage_with_options(usage, options);


	/*
	 * Turn off buffering, for tailing the log files, and because
	 * it's what "tee" does.
	 */
	if (logfp)
		setvbuf(logfp, NULL, _IONBF, 0);

	while (strbuf_getline(&line, stdin) != EOF) {
		char *buf = line.buf;
		int is_tap = 0;

		/* We can assume that --prefix isn't valid TAP... */
		if (out_escape || file_escape) {
			int is_bad = line_has_tap(buf);
			if (is_bad && out_escape)
				fprintf(stdout, "\\");
			if (is_bad && file_escape)
				fprintf(logfp, "\\");
		}

		/* ...ditto on the TAP v.s. --prefix assumption */
		if (starts_with(buf, prefix)) {
			is_tap = 1;
			buf += prefix_len;
		}

		/* No further special-cases for logging */
		if (logfp)
			fprintf(logfp, "%s\n", buf);

		if (!is_tap) {
			if (!out_only_tap)
				puts(buf);
			continue;
		}

		if (*buf == '#') {
			size_t pos;
			if (!comment_level)
				continue;

			pos = strspn(buf, "#");
			if (pos > comment_level)
				continue;
		}

		puts(buf);
	}
	strbuf_release(&line);
	if (logfp)
		fclose(logfp);

	return 0;
}
