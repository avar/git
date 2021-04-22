/*
 * GIT - The information manager from hell
 *
 * Copyright (C) Linus Torvalds, 2005
 * Copyright (C) Junio C Hamano, 2005
 */
#include "builtin.h"
#include "config.h"
#include "object-store.h"
#include "blob.h"
#include "quote.h"
#include "parse-options.h"
#include "exec-cmd.h"

/*
 * This is to create corrupt objects for debugging and as such it
 * needs to bypass the data conversion performed by, and the type
 * limitation imposed by, index_fd() and its callees.
 */
static int hash_literally(struct object_id *oid, int fd, const char *type, unsigned flags)
{
	struct strbuf buf = STRBUF_INIT;
	int ret;

	if (strbuf_read(&buf, fd, 4096) < 0)
		ret = -1;
	else
		ret = hash_object_file_literally(buf.buf, buf.len, type,
						 strlen(type), oid, flags);
	strbuf_release(&buf);
	return ret;
}

static void hash_fd(int fd, enum object_type otype, const char *type,
		    size_t type_len, const char *path, unsigned flags,
		    int literally)
{
	struct stat st;
	struct object_id oid;

	if (fstat(fd, &st) < 0 ||
	    (literally
	     ? hash_literally(&oid, fd, type, flags)
	     : index_fd(the_repository->index, &oid, fd, &st, otype, path,
			flags)))
		die((flags & HASH_WRITE_OBJECT)
		    ? "Unable to add %s to database"
		    : "Unable to hash %s", path);
	printf("%s\n", oid_to_hex(&oid));
	maybe_flush_or_die(stdout, "hash to stdout");
}

static void hash_object(const char *path, enum object_type otype,
			const char *type, size_t type_len,
			const char *vpath, unsigned flags, int literally)
{
	int fd;
	fd = open(path, O_RDONLY);
	if (fd < 0)
		die_errno("Cannot open '%s'", path);
	hash_fd(fd, otype, type, type_len, vpath, flags, literally);
}

static void hash_stdin_paths(enum object_type otype, const char *type,
			     size_t type_len, int no_filters,
			     unsigned flags, int literally)
{
	struct strbuf buf = STRBUF_INIT;
	struct strbuf unquoted = STRBUF_INIT;

	while (strbuf_getline(&buf, stdin) != EOF) {
		const char *vpath;
		if (buf.buf[0] == '"') {
			strbuf_reset(&unquoted);
			if (unquote_c_style(&unquoted, buf.buf, NULL))
				die("line is badly quoted");
			strbuf_swap(&buf, &unquoted);
		}
		vpath = no_filters ? NULL : buf.buf;
		hash_object(buf.buf, otype, type, type_len, vpath , flags, literally);
	}
	strbuf_release(&buf);
	strbuf_release(&unquoted);
}

int cmd_hash_object(int argc, const char **argv, const char *prefix)
{
	static const char * const hash_object_usage[] = {
		N_("git hash-object [-t <type>] [-w] [--path=<file> | --no-filters] [--stdin] [--] <file>..."),
		N_("git hash-object  --stdin-paths"),
		NULL
	};
	const char *type = blob_type;
	size_t type_len;
	enum object_type otype = OBJ_BAD;
	int hashstdin = 0;
	int stdin_paths = 0;
	int no_filters = 0;
	int literally = 0;
	int nongit = 0;
	unsigned flags = HASH_FORMAT_CHECK;
	const char *vpath = NULL;
	const struct option hash_object_options[] = {
		OPT_STRING('t', NULL, &type, N_("type"), N_("object type")),
		OPT_BIT('w', NULL, &flags, N_("write the object into the object database"),
			HASH_WRITE_OBJECT),
		OPT_COUNTUP( 0 , "stdin", &hashstdin, N_("read the object from stdin")),
		OPT_BOOL( 0 , "stdin-paths", &stdin_paths, N_("read file names from stdin")),
		OPT_BOOL( 0 , "no-filters", &no_filters, N_("store file as is without filters")),
		OPT_BOOL( 0, "literally", &literally, N_("just hash any random garbage to create corrupt objects for debugging Git")),
		OPT_STRING( 0 , "path", &vpath, N_("file"), N_("process file as it were from this path")),
		OPT_END()
	};
	int i;
	const char *errstr = NULL;
	int errstr_arg_type = 0;

	argc = parse_options(argc, argv, prefix, hash_object_options,
			     hash_object_usage, 0);

	if (flags & HASH_WRITE_OBJECT)
		prefix = setup_git_directory();
	else
		prefix = setup_git_directory_gently(&nongit);

	if (vpath && prefix)
		vpath = xstrdup(prefix_filename(prefix, vpath));

	git_config(git_default_config, NULL);

	type_len = strlen(type);
	otype = type_from_string_gently(type, type_len);
	if (otype < 0 && !literally) {
		errstr = "the object type \"%.*s\" is invalid, did you mean to use --literally?";
		errstr_arg_type = 1;
	} else if (stdin_paths) {
		if (hashstdin)
			errstr = "Can't use --stdin-paths with --stdin";
		else if (argc)
			errstr = "Can't specify files with --stdin-paths";
		else if (vpath)
			errstr = "Can't use --stdin-paths with --path";
	} else if (hashstdin > 1) {
		errstr = "Multiple --stdin arguments are not supported";
	} else if (vpath && no_filters) {
		errstr = "Can't use --path with --no-filters";
	}

	if (errstr) {
		if (errstr_arg_type)
			error(errstr, (int)type_len, type);
		else
			error("%s", errstr);
		usage_with_options(hash_object_usage, hash_object_options);
	}

	if (hashstdin)
		hash_fd(0, otype, type, type_len, vpath, flags, literally);

	for (i = 0 ; i < argc; i++) {
		const char *arg = argv[i];
		char *to_free = NULL;
		const char *tmp;

		if (prefix)
			arg = to_free = prefix_filename(prefix, arg);
		tmp = no_filters ? NULL : vpath ? vpath : arg;
		hash_object(arg, otype, type, type_len, tmp, flags, literally);
		free(to_free);
	}

	if (stdin_paths)
		hash_stdin_paths(otype, type, type_len, no_filters, flags,
				 literally);

	return 0;
}
