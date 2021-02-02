/*
 * Copyright (C) 2005 Junio C Hamano
 * Copyright (C) 2010 Google Inc.
 */
#include "cache.h"
#include "diff.h"
#include "diffcore.h"
#include "xdiff-interface.h"
#include "grep.h"
#include "commit.h"
#include "quote.h"

typedef int (*pickaxe_fn)(mmfile_t *one, mmfile_t *two,
			  struct diff_options *o,
			  struct grep_opt *grep_filter);

struct diffgrep_cb {
	struct grep_opt	*grep_filter;
	int hit;
};

static void diffgrep_consume(void *priv, char *line, unsigned long len)
{
	struct diffgrep_cb *data = priv;
	regmatch_t regmatch;
	struct grep_opt *grep_filter = data->grep_filter;
	struct grep_pat *grep_pat = grep_filter->pattern_list;

	if (line[0] != '+' && line[0] != '-')
		return;
	if (data->hit)
		/*
		 * NEEDSWORK: we should have a way to terminate the
		 * caller early.
		 */
		return;
	data->hit = patmatch(grep_pat, line + 1, line + len + 1, &regmatch, 0);
}

static int diff_grep(mmfile_t *one, mmfile_t *two,
		     struct diff_options *o,
		     struct grep_opt *grep_filter)
{
	struct diffgrep_cb ecbdata;
	xpparam_t xpp;
	xdemitconf_t xecfg;
	regmatch_t regmatch;
	struct grep_pat *grep_pat = grep_filter->pattern_list;

	if (!one)
		return patmatch(grep_pat, two->ptr, two->ptr + two->size,
				&regmatch, 0);
	if (!two)
		return patmatch(grep_pat, one->ptr, one->ptr + one->size,
				&regmatch, 0);

	/*
	 * We have both sides; need to run textual diff and see if
	 * the pattern appears on added/deleted lines.
	 */
	memset(&xpp, 0, sizeof(xpp));
	memset(&xecfg, 0, sizeof(xecfg));
	ecbdata.grep_filter = grep_filter;
	ecbdata.hit = 0;
	xecfg.ctxlen = o->context;
	xecfg.interhunkctxlen = o->interhunkcontext;
	if (xdi_diff_outf(one, two, discard_hunk_line, diffgrep_consume,
			  &ecbdata, &xpp, &xecfg))
		return 0;
	return ecbdata.hit;
}

static unsigned int contains(mmfile_t *mf, struct grep_opt *grep_filter)
{

	unsigned int cnt = 0;
	unsigned long sz = mf->size;
	char *data = mf->ptr;
	regmatch_t regmatch;
	int flags = 0;
	struct grep_pat *grep_pat = grep_filter->pattern_list;

	while (patmatch(grep_pat, data, data + sz, &regmatch, flags)) {
		flags |= REG_NOTBOL;
		data += regmatch.rm_eo;
		sz -= regmatch.rm_eo;
		if (regmatch.rm_so == regmatch.rm_eo) {
			data++;
			sz--;
		}
		cnt++;
	}
	return cnt;
}

static int has_changes(mmfile_t *one, mmfile_t *two,
		       struct diff_options *o,
		       struct grep_opt *grep_filter)
{
	unsigned int one_contains = one ? contains(one, grep_filter) : 0;
	unsigned int two_contains = two ? contains(two, grep_filter) : 0;
	return one_contains != two_contains;
}

static int pickaxe_match(struct diff_filepair *p, struct diff_options *o,
			 struct grep_opt *grep_filter, pickaxe_fn fn)
{
	struct userdiff_driver *textconv_one = NULL;
	struct userdiff_driver *textconv_two = NULL;
	mmfile_t mf1, mf2;
	int ret;

	/* ignore unmerged */
	if (!DIFF_FILE_VALID(p->one) && !DIFF_FILE_VALID(p->two))
		return 0;

	if (o->objfind) {
		return  (DIFF_FILE_VALID(p->one) &&
			 oidset_contains(o->objfind, &p->one->oid)) ||
			(DIFF_FILE_VALID(p->two) &&
			 oidset_contains(o->objfind, &p->two->oid));
	}

	if (!o->pickaxe[0])
		return 0;

	if (o->flags.allow_textconv) {
		textconv_one = get_textconv(o->repo, p->one);
		textconv_two = get_textconv(o->repo, p->two);
	}

	/*
	 * If we have an unmodified pair, we know that the count will be the
	 * same and don't even have to load the blobs. Unless textconv is in
	 * play, _and_ we are using two different textconv filters (e.g.,
	 * because a pair is an exact rename with different textconv attributes
	 * for each side, which might generate different content).
	 */
	if (textconv_one == textconv_two && diff_unmodified_pair(p))
		return 0;

	if ((o->pickaxe_opts & DIFF_PICKAXE_KIND_G) &&
	    !o->flags.text &&
	    ((!textconv_one && diff_filespec_is_binary(o->repo, p->one)) ||
	     (!textconv_two && diff_filespec_is_binary(o->repo, p->two))))
		return 0;

	mf1.size = fill_textconv(o->repo, textconv_one, p->one, &mf1.ptr);
	mf2.size = fill_textconv(o->repo, textconv_two, p->two, &mf2.ptr);

	ret = fn(DIFF_FILE_VALID(p->one) ? &mf1 : NULL,
		 DIFF_FILE_VALID(p->two) ? &mf2 : NULL,
		 o, grep_filter);

	if (textconv_one)
		free(mf1.ptr);
	if (textconv_two)
		free(mf2.ptr);
	diff_free_filespec_data(p->one);
	diff_free_filespec_data(p->two);

	return ret;
}

static void pickaxe(struct diff_queue_struct *q, struct diff_options *o,
		    struct grep_opt *grep_filter, pickaxe_fn fn)
{
	int i;
	struct diff_queue_struct outq;

	DIFF_QUEUE_CLEAR(&outq);

	if (o->pickaxe_opts & DIFF_PICKAXE_ALL) {
		/* Showing the whole changeset if needle exists */
		for (i = 0; i < q->nr; i++) {
			struct diff_filepair *p = q->queue[i];
			if (pickaxe_match(p, o, grep_filter, fn))
				return; /* do not munge the queue */
		}

		/*
		 * Otherwise we will clear the whole queue by copying
		 * the empty outq at the end of this function, but
		 * first clear the current entries in the queue.
		 */
		for (i = 0; i < q->nr; i++)
			diff_free_filepair(q->queue[i]);
	} else {
		/* Showing only the filepairs that has the needle */
		for (i = 0; i < q->nr; i++) {
			struct diff_filepair *p = q->queue[i];
			if (pickaxe_match(p, o, grep_filter, fn))
				diff_q(&outq, p);
			else
				diff_free_filepair(p);
		}
	}

	free(q->queue);
	*q = outq;
}

void diffcore_pickaxe(struct diff_options *o)
{
	const char *needle = o->pickaxe;
	int opts = o->pickaxe_opts;
	struct grep_opt opt;

	if (opts & (DIFF_PICKAXE_REGEX | DIFF_PICKAXE_KIND_GS_MASK)) {
		grep_init(&opt, the_repository, NULL);
#ifdef USE_LIBPCRE2
		grep_commit_pattern_type(GREP_PATTERN_TYPE_PCRE, &opt);
#else
		grep_commit_pattern_type(GREP_PATTERN_TYPE_ERE, &opt);
#endif

		if (o->pickaxe_opts & DIFF_PICKAXE_IGNORE_CASE)
			opt.ignore_case = 1;

		append_grep_pattern(&opt, needle, "diffcore-pickaxe", 0, GREP_PATTERN);
		compile_grep_patterns(&opt);
	}

	pickaxe(&diff_queued_diff, o, &opt,
		(opts & DIFF_PICKAXE_KIND_G) ? diff_grep : has_changes);

	if (opts & ~DIFF_PICKAXE_KIND_OBJFIND)
		free_grep_patterns(&opt);

	return;
}
