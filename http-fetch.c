#include "cache.h"
#include "config.h"
#include "exec-cmd.h"
#include "http.h"
#include "walker.h"
#include "strvec.h"
#include "parse-options.h"

static char const * const http_fetch_usage[] = {
	N_("[-v] --packfile=checksum --index-pack-args=<arg>... <url>"),
	N_("[-v] [--recover] [-w ref <commit> | -w ref --stdin] <url>"),
	NULL
};

static int fetch_using_walker(const char *raw_url, int get_verbosely,
			      int get_recover, int commits, char **commit_id,
			      const char **write_ref, int commits_on_stdin)
{
	char *url = NULL;
	struct walker *walker;
	int rc;

	str_end_url_with_slash(raw_url, &url);

	http_init(NULL, url, 0);

	walker = get_http_walker(url);
	walker->get_verbosely = get_verbosely;
	walker->get_recover = get_recover;
	walker->get_progress = 0;

	rc = walker_fetch(walker, commits, commit_id, write_ref, url);

	if (commits_on_stdin)
		walker_targets_free(commits, commit_id, write_ref);

	if (walker->corrupt_object_found) {
		fprintf(stderr,
"Some loose object were found to be corrupt, but they might be just\n"
"a false '404 Not Found' error message sent with incorrect HTTP\n"
"status code.  Suggest running 'git fsck'.\n");
	}

	walker_free(walker);
	http_cleanup();
	free(url);

	return rc;
}

static void fetch_single_packfile(struct object_id *packfile_hash,
				  const char *url,
				  const char **index_pack_args) {
	struct http_pack_request *preq;
	struct slot_results results;
	int ret;

	http_init(NULL, url, 0);

	preq = new_direct_http_pack_request(packfile_hash->hash, xstrdup(url));
	if (preq == NULL)
		die("couldn't create http pack request");
	preq->slot->results = &results;
	preq->index_pack_args = index_pack_args;
	preq->preserve_index_pack_stdout = 1;

	if (start_active_slot(preq->slot)) {
		run_active_slot(preq->slot);
		if (results.curl_result != CURLE_OK) {
			die("Unable to get pack file %s\n%s", preq->url,
			    curl_errorstr);
		}
	} else {
		die("Unable to start request");
	}

	if ((ret = finish_http_pack_request(preq)))
		die("finish_http_pack_request gave result %d", ret);

	release_http_pack_request(preq);
	http_cleanup();
}

int cmd_main(int argc, const char **argv)
{
	int commits_on_stdin = 0;
	char **commit_id = NULL;
	int get_verbosely = 0;
	int get_recover = 0;
	int packfile = 0;
	const char *write_ref = NULL;
	const char *url;
	struct object_id packfile_hash = { 0 };
	struct strvec index_pack_args = STRVEC_INIT;
	struct option options[] = {
		OPT__VERBOSE(&get_verbosely, N_("be verbose")),
		OPT_STRING('w', NULL, &write_ref, N_("refname"),
			   N_("reference name to write to")),
		OPT_BOOL(0, "recover", &get_recover,
			 N_("Verify that everything reachable from target is fetched")),
		OPT_BOOL(0, "stdin", &commits_on_stdin,
			 N_("read commits and filename from stdin")),
		{ OPTION_CALLBACK, 0, "packfile", &packfile_hash,
		  N_("checksum"), N_("the checksum of the packfile"),
		  PARSE_OPT_NONEG, parse_opt_object_id_hex, 0 },
		OPT_STRVEC(0, "index-pack-arg", &index_pack_args, N_("args"),
			   N_("arguments to pass to git-index-pack")),
		OPT_END(),
	};

	setup_git_directory();
	git_config(git_default_config, NULL);

	argc = parse_options(argc, argv, NULL, options, http_fetch_usage, 0);
	packfile = !is_null_oid(&packfile_hash);

	if (!packfile && !commits_on_stdin && argc != 2) {
		error(_("must supply --packfile, --stdin or <commit>"));
		goto usage;
	}

	if (!is_null_oid(&packfile_hash)) {
		if (!index_pack_args.nr) {
			error(_("--packfile requires --index-pack-args"));
			goto usage;
		}
		if (get_recover || write_ref || commits_on_stdin) {
			error(_("incompatible options with --packfile"));
			goto usage;
		}
		if (argc != 1) {
			error(_("must provide one URL with --packfile=*"));
			goto usage;
		}

		url = argv[0];
		fetch_single_packfile(&packfile_hash, url, index_pack_args.v);

		return 0;
	}

	if (index_pack_args.nr)
		die(_("--index-pack-args can only be used with --packfile"));

	if (commits_on_stdin) {
		char **commit_id = NULL;
		const char **write_ref_stdin = NULL;
		int targets;

		if (argc > 1) {
			error(_("only provide <url>, not <commit> with --stdin"));
			goto usage;
		}

		targets = walker_targets_stdin(&commit_id, &write_ref_stdin);
		return fetch_using_walker(argv[0], get_verbosely, get_recover,
					  targets, commit_id, write_ref_stdin,
					  1);
	}

	if (argc != 2) {
		error(_("need <commit> and <url> with -w without --stdin"));
		goto usage;
	}

	commit_id = (char **)&argv[0];
	url = argv[1];
	return fetch_using_walker(url, get_verbosely, get_recover, 1,
				  commit_id, &write_ref, 0);
usage:
	usage_with_options(http_fetch_usage, options);
}
