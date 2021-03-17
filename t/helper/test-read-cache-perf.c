#include "test-tool.h"
#include "cache.h"

int cmd__read_cache_perf(int argc, const char **argv)
{
	struct repository *r = the_repository;
	int cnt;

	if (argc == 2)
		cnt = strtol(argv[1], NULL, 0);
	else
		die("usage: test-tool read-cache-perf [<count>]");

	setup_git_directory();
	while (cnt--) {
		repo_read_index(r);
		discard_index(r->index);
	}

	return 0;
}
