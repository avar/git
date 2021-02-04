/*
 * Copyright (C) 2005 Junio C Hamano
 * Copyright (C) 2010 Google Inc.
 */
#include "cache.h"
#include "diff.h"
#include "diffcore.h"
#include "xdiff-interface.h"
#include "grep.h"

struct diffgrep_cb {
	struct grep_opt	*grep_filter;
	int hit;
	int patch;
};

static int diffgrep_consume(void *priv, char *line, unsigned long len)
{
	struct diffgrep_cb *data = priv;
	regmatch_t regmatch;
	struct grep_opt *grep_filter = data->grep_filter;
	struct grep_pat *grep_pat = grep_filter->pattern_list;
	size_t off = data->patch ? 0 : 1;

	if (off && line[0] != '+' && line[0] != '-')
		return 0;
	if (data->hit)
		BUG("Already matched in diffgrep_consume! Broken xdiff_emit_line_fn?");
	if (patmatch(grep_pat, line + off, line + len + 1, &regmatch, 0)) {
		data->hit = 1;
		return 1;
	}
	return 0;
}

static int diff_grep(mmfile_t *one, mmfile_t *two,
		     struct diff_options *o,
		     struct grep_opt *grep_filter)
{
	struct diffgrep_cb ecbdata;
	xpparam_t xpp;
	xdemitconf_t xecfg;
	int ret;

	/*
	 * We have both sides; need to run textual diff and see if
	 * the pattern appears on added/deleted lines.
	 */
	memset(&xpp, 0, sizeof(xpp));
	memset(&xecfg, 0, sizeof(xecfg));
	ecbdata.grep_filter = grep_filter;
	ecbdata.hit = 0;
	xecfg.flags = XDL_EMIT_NO_HUNK_HDR;
	xecfg.ctxlen = o->context;
	ecbdata.patch = o->pickaxe_opts & DIFF_PICKAXE_PATCH;
	xecfg.interhunkctxlen = o->interhunkcontext;

	/*
	 * An xdiff error might be our "data->hit" from above. See the
	 * comment for xdiff_emit_line_fn in xdiff-interface.h
	 */
	ret = xdi_diff_outf(one, two, NULL, diffgrep_consume,
			    &ecbdata, &xpp, &xecfg);
	if (ecbdata.hit)
		return 1;
	if (ret)
		return ret;
	return 0;
}

static unsigned int contains(mmfile_t *mf, struct grep_opt *grep_filter,
			     unsigned int limit)
{

	unsigned int cnt = 0;
	unsigned long sz = mf->size;
	char *data = mf->ptr;
	regmatch_t regmatch;
	int flags = 0;
	struct grep_pat *grep_pat = grep_filter->pattern_list;

	while (sz &&
	       patmatch(grep_pat, data, data + sz, &regmatch, flags)) {
		flags |= REG_NOTBOL;
		data += regmatch.rm_eo;
		sz -= regmatch.rm_eo;
		if (sz && regmatch.rm_so == regmatch.rm_eo) {
			data++;
			sz--;
		}
		cnt++;
		if (limit && cnt == limit)
			return cnt;
	}
	return cnt;
}

static int has_changes(mmfile_t *one, mmfile_t *two,
		       struct diff_options *o,
		       struct grep_opt *grep_filter)
{
	unsigned int c1 = one ? contains(one, grep_filter, 0) : 0;
	unsigned int c2 = two ? contains(two, grep_filter, c1 + 1) : 0;
	return c1 != c2;
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

	ret = fn(&mf1, &mf2, o, grep_filter);

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

static void compile_pickaxe(struct diff_options *o)
{
	const char *needle = o->pickaxe;
	int opts = o->pickaxe_opts;
	pickaxe_fn fn;

	assert(!o->pickaxed_compiled);
	o->pickaxed_compiled = 1;

	if (opts & ~DIFF_PICKAXE_KIND_OBJFIND &&
	    (!needle || !*needle))
		BUG("should have needle under -G or -S");
	if (opts & (DIFF_PICKAXE_REGEX | DIFF_PICKAXE_KIND_GS_MASK)) {
		grep_init(&o->pickaxe_grep_opt, the_repository, NULL);
#ifdef USE_LIBPCRE2
		grep_commit_pattern_type(GREP_PATTERN_TYPE_PCRE, &o->pickaxe_grep_opt);
#else
		grep_commit_pattern_type(GREP_PATTERN_TYPE_ERE, &o->pickaxe_grep_opt);
#endif

		if (o->pickaxe_opts & DIFF_PICKAXE_IGNORE_CASE)
			o->pickaxe_grep_opt.ignore_case = 1;
		if (opts & DIFF_PICKAXE_KIND_S &&
		    !(opts & DIFF_PICKAXE_REGEX))
			o->pickaxe_grep_opt.fixed = 1;

		append_grep_pattern(&o->pickaxe_grep_opt, needle, "diffcore-pickaxe", 0, GREP_PATTERN);
		fprintf(stderr, "compiling for %s\n", needle);
		compile_grep_patterns(&o->pickaxe_grep_opt);

		if (opts & DIFF_PICKAXE_KIND_G)
			fn = diff_grep;
		else if (opts & DIFF_PICKAXE_KIND_S)
			fn = has_changes;
		else if (opts & DIFF_PICKAXE_REGEX)
			fn = has_changes;
		else
			/*
			 * We don't need to check the combination of
			 * -G and --pickaxe-regex, by the time we get
			 * here diff.c has already died if they're
			 * combined. See the usage tests in
			 * t4209-log-pickaxe.sh.
			 */
			BUG("unreachable");

		o->pickaxe_fn = fn;
	} else if (opts & DIFF_PICKAXE_KIND_OBJFIND) {
		fn = NULL;
	} else {
		BUG("unknown pickaxe_opts flag");
	}
}

void diffcore_pickaxe(struct diff_options *o)
{
	if (!o->pickaxed_compiled)
		compile_pickaxe(o);
	pickaxe(&diff_queued_diff, o, &o->pickaxe_grep_opt, o->pickaxe_fn);

	/*if (opts & ~DIFF_PICKAXE_KIND_OBJFIND)
		free_grep_patterns(&o->pickaxe_grep_opt);*/

	return;
}
