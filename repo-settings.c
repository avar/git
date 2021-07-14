#include "cache.h"
#include "config.h"
#include "repository.h"
#include "midx.h"

static void repo_config_get_bool_or(struct repository *r, const char *key,
				    int *dest, int def)
{
	if (repo_config_get_bool(r, key, dest))
		*dest = def;
}

void prepare_repo_settings(struct repository *r)
{
	int experimental;
	int value;
	char *strval;
	int manyfiles;

	if (r->settings.initialized++)
		return;

	/* Defaults */
	r->settings.index_version = -1;
	r->settings.core_untracked_cache = UNTRACKED_CACHE_UNSET;
	r->settings.fetch_negotiation_algorithm = FETCH_NEGOTIATION_DEFAULT;

	/* Booleans config or default, cascades to other settings */
	repo_config_get_bool_or(r, "feature.manyfiles", &manyfiles, 0);
	repo_config_get_bool_or(r, "feature.experimental", &experimental, 0);

	/* Defaults modified by feature.* */
	if (experimental) {
		r->settings.fetch_negotiation_algorithm = FETCH_NEGOTIATION_SKIPPING;
	}
	if (manyfiles) {
		r->settings.index_version = 4;
		r->settings.core_untracked_cache = UNTRACKED_CACHE_WRITE;
	}

	/* Boolean config or default, does not cascade (simple)  */
	repo_config_get_bool_or(r, "core.commitgraph",
				&r->settings.core_commit_graph, 1);
	repo_config_get_bool_or(r, "commitgraph.readchangedpaths",
				&r->settings.commit_graph_read_changed_paths, 1);
	repo_config_get_bool_or(r, "gc.writecommitgraph",
				&r->settings.gc_write_commit_graph, 1);
	repo_config_get_bool_or(r, "fetch.writecommitgraph",
				&r->settings.fetch_write_commit_graph, 0);
	repo_config_get_bool_or(r, "pack.usesparse",
				&r->settings.pack_use_sparse, 1);
	repo_config_get_bool_or(r, "core.multipackindex",
				&r->settings.core_multi_pack_index, 1);
	repo_config_get_bool_or(r, "index.sparse",
				&r->settings.sparse_index, 0);

	/*
	 * The GIT_TEST_MULTI_PACK_INDEX variable is special in that
	 * either it *or* the config sets
	 * r->settings.core_multi_pack_index if true. We don't take
	 * the environment variable if it exists (even if false) over
	 * any config, as in other cases.
	 */
	if (git_env_bool(GIT_TEST_MULTI_PACK_INDEX, 0))
		r->settings.core_multi_pack_index = 1;

	/*
	 * Non-boolean config
	 */
	if (!repo_config_get_int(r, "index.version", &value))
		r->settings.index_version = value;

	if (!repo_config_get_string(r, "core.untrackedcache", &strval)) {
		int maybe_bool = git_parse_maybe_bool(strval);
		if (maybe_bool == -1) {
			/*
			 * Set to "keep", or some other non-boolean
			 * value. In either case we do nothing but
			 * keep UNTRACKED_CACHE_UNSET.
			 */
		} else {
			r->settings.core_untracked_cache = maybe_bool
				? UNTRACKED_CACHE_WRITE
				: UNTRACKED_CACHE_REMOVE;
		}
		free(strval);
	}

	if (!repo_config_get_string(r, "fetch.negotiationalgorithm", &strval)) {
		if (!strcasecmp(strval, "skipping"))
			r->settings.fetch_negotiation_algorithm = FETCH_NEGOTIATION_SKIPPING;
		else if (!strcasecmp(strval, "noop"))
			r->settings.fetch_negotiation_algorithm = FETCH_NEGOTIATION_NOOP;
	}

	/*
	 * This setting guards all index reads to require a full index
	 * over a sparse index. After suitable guards are placed in the
	 * codebase around uses of the index, this setting will be
	 * removed.
	 */
	r->settings.command_requires_full_index = 1;
}
