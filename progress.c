/*
 * Simple text-based progress display module for GIT
 *
 * Copyright (c) 2007 by Nicolas Pitre <nico@fluxnic.net>
 *
 * This code is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#include "cache.h"
#include "gettext.h"
#include "progress.h"
#include "strbuf.h"
#include "trace.h"
#include "utf8.h"
#include "config.h"

static volatile sig_atomic_t progress_update;
static struct progress *global_progress;

static int is_foreground_fd(int fd)
{
	int tpgrp = tcgetpgrp(fd);
	return tpgrp < 0 || tpgrp == getpgid(0);
}

static void display(struct progress *progress, uint64_t n,
		    const char *update_msg, int last_update)
{
	const char *tp;
	struct strbuf *counters_sb = &progress->counters_sb;
	int show_update = 0;
	int last_count_len = counters_sb->len;

	if (progress->delay && (!progress_update || --progress->delay))
		return;

	progress->last_value = n;
	tp = (progress->throughput) ? progress->throughput->display.buf : "";
	if (progress->total) {
		unsigned percent = n * 100 / progress->total;
		if (percent != progress->last_percent || progress_update) {
			progress->last_percent = percent;

			strbuf_reset(counters_sb);
			strbuf_addf(counters_sb,
				    "%3u%% (%"PRIuMAX"/%"PRIuMAX")%s", percent,
				    (uintmax_t)n, (uintmax_t)progress->total,
				    tp);
			show_update = 1;
		}
	} else if (progress_update) {
		strbuf_reset(counters_sb);
		strbuf_addf(counters_sb, "%"PRIuMAX"%s", (uintmax_t)n, tp);
		show_update = 1;
	}

	if (show_update && update_msg)
		strbuf_addf(counters_sb, ", %s.", update_msg);

	if (show_update) {
		int stderr_is_foreground_fd = is_foreground_fd(fileno(stderr));
		if (stderr_is_foreground_fd || update_msg) {
			const char *eol = last_update ? "\n" : "\r";
			size_t clear_len = counters_sb->len < last_count_len ?
					last_count_len - counters_sb->len + 1 :
					0;
			/* The "+ 2" accounts for the ": ". */
			size_t progress_line_len = progress->title_len +
						counters_sb->len + 2;
			int cols = term_columns();

			if (progress->split) {
				fprintf(stderr, "  %s%*s", counters_sb->buf,
					(int) clear_len, eol);
			} else if (!update_msg && cols < progress_line_len) {
				clear_len = progress->title_len + 1 < cols ?
					    cols - progress->title_len - 1 : 0;
				fprintf(stderr, "%s:%*s\n  %s%s",
					progress->title, (int) clear_len, "",
					counters_sb->buf, eol);
				progress->split = 1;
			} else {
				fprintf(stderr, "%s: %s%*s", progress->title,
					counters_sb->buf, (int) clear_len, eol);
			}
			if (stderr_is_foreground_fd)
				fflush(stderr);
		}
		progress_update = 0;
	}
}

static void throughput_string(struct strbuf *buf, uint64_t total,
			      unsigned int rate)
{
	strbuf_reset(buf);
	strbuf_addstr(buf, ", ");
	strbuf_humanise_bytes(buf, total);
	strbuf_addstr(buf, " | ");
	strbuf_humanise_rate(buf, rate * 1024);
}

static uint64_t progress_getnanotime(struct progress *progress)
{
	if (progress->test_getnanotime)
		return progress->start_ns + progress->test_getnanotime;
	else
		return getnanotime();
}

void display_throughput(struct progress *progress, uint64_t total)
{
	struct throughput *tp;
	uint64_t now_ns;
	unsigned int misecs, count, rate;

	if (!progress)
		return;
	tp = progress->throughput;

	now_ns = progress_getnanotime(progress);

	if (!tp) {
		progress->throughput = CALLOC_ARRAY(tp, 1);
		tp->prev_total = tp->curr_total = total;
		tp->prev_ns = now_ns;
		strbuf_init(&tp->display, 0);
		return;
	}
	tp->curr_total = total;

	/* only update throughput every 0.5 s */
	if (now_ns - tp->prev_ns <= 500000000)
		return;

	/*
	 * We have x = bytes and y = nanosecs.  We want z = KiB/s:
	 *
	 *	z = (x / 1024) / (y / 1000000000)
	 *	z = x / y * 1000000000 / 1024
	 *	z = x / (y * 1024 / 1000000000)
	 *	z = x / y'
	 *
	 * To simplify things we'll keep track of misecs, or 1024th of a sec
	 * obtained with:
	 *
	 *	y' = y * 1024 / 1000000000
	 *	y' = y * (2^10 / 2^42) * (2^42 / 1000000000)
	 *	y' = y / 2^32 * 4398
	 *	y' = (y * 4398) >> 32
	 */
	misecs = ((now_ns - tp->prev_ns) * 4398) >> 32;

	count = total - tp->prev_total;
	tp->prev_total = total;
	tp->prev_ns = now_ns;
	tp->avg_bytes += count;
	tp->avg_misecs += misecs;
	rate = tp->avg_bytes / tp->avg_misecs;
	tp->avg_bytes -= tp->last_bytes[tp->idx];
	tp->avg_misecs -= tp->last_misecs[tp->idx];
	tp->last_bytes[tp->idx] = count;
	tp->last_misecs[tp->idx] = misecs;
	tp->idx = (tp->idx + 1) % PROGRESS_THROUGHPUT_IDX_MAX;

	throughput_string(&tp->display, total, rate);
	if (progress->last_value != -1 && progress_update)
		display(progress, progress->last_value, NULL, 0);
}

void display_progress(struct progress *progress, uint64_t n)
{
	if (progress)
		display(progress, n, NULL, 0);
}

static void progress_interval(int signum)
{
	progress_update = 1;
}

void test_progress_force_update(void)
{
	progress_interval(SIGALRM);
}

static void set_progress_signal(struct progress *progress)
{
	struct sigaction sa;
	struct itimerval v;

	if (global_progress)
		BUG("should have no global_progress in set_progress_signal()");
	global_progress = progress;

	if (progress->test_mode)
		return;

	progress_update = 0;

	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = progress_interval;
	sigemptyset(&sa.sa_mask);
	sa.sa_flags = SA_RESTART;
	sigaction(SIGALRM, &sa, NULL);

	v.it_interval.tv_sec = 0;
	v.it_interval.tv_usec = 50000;
	v.it_value = v.it_interval;
	setitimer(ITIMER_REAL, &v, NULL);
}

static void clear_progress_signal(struct progress *progress)
{
	struct itimerval v = {{0,},};

	if (!global_progress)
		BUG("should have a global_progress in clear_progress_signal()");
	global_progress = NULL;

	if (progress->test_mode)
		return;

	setitimer(ITIMER_REAL, &v, NULL);
	signal(SIGALRM, SIG_IGN);
	progress_update = 0;
}

static struct progress *start_progress_delay(const char *title, uint64_t total,
					     unsigned delay, int testing)
{
	struct progress *progress = xmalloc(sizeof(*progress));
	progress->title = title;
	progress->total = total;
	progress->last_value = -1;
	progress->last_percent = -1;
	progress->delay = delay;
	progress->throughput = NULL;
	progress->start_ns = getnanotime();
	strbuf_init(&progress->counters_sb, 0);
	progress->title_len = utf8_strwidth(title);
	progress->split = 0;
	progress->test_mode = testing;
	set_progress_signal(progress);
	trace2_region_enter("progress", title, the_repository);
	return progress;
}

struct progress *start_progress_testing(const char *title, uint64_t total)
{
	return start_progress_delay(title, total, 0, 1);
}

static int get_default_delay(void)
{
	static int delay_in_secs = -1;

	if (delay_in_secs < 0)
		delay_in_secs = git_env_ulong("GIT_PROGRESS_DELAY", 2);

	return delay_in_secs;
}

struct progress *start_delayed_progress(const char *title, uint64_t total)
{
	return start_progress_delay(title, total, get_default_delay(), 0);
}

struct progress *start_progress(const char *title, uint64_t total)
{
	return start_progress_delay(title, total, 0, 0);
}

void stop_progress(struct progress **p_progress)
{
	if (!p_progress)
		BUG("don't provide NULL to stop_progress");

	if (*p_progress) {
		struct progress *progress = *p_progress;
		trace2_data_intmax("progress", the_repository, "total_objects",
				   (*p_progress)->total);

		if ((*p_progress)->throughput)
			trace2_data_intmax("progress", the_repository,
					   "total_bytes",
					   progress->throughput->curr_total);

		trace2_region_leave("progress", progress->title, the_repository);
	}

	stop_progress_msg(p_progress, _("done"));
}

void stop_progress_msg(struct progress **p_progress, const char *msg)
{
	struct progress *progress;

	if (!p_progress)
		BUG("don't provide NULL to stop_progress_msg");

	progress = *p_progress;
	if (!progress)
		return;
	*p_progress = NULL;
	if (progress->last_value != -1) {
		/* Force the last update */
		struct throughput *tp = progress->throughput;

		if (tp) {
			uint64_t now_ns = progress_getnanotime(progress);
			unsigned int misecs, rate;
			misecs = ((now_ns - progress->start_ns) * 4398) >> 32;
			rate = tp->curr_total / (misecs ? misecs : 1);
			throughput_string(&tp->display, tp->curr_total, rate);
		}
		progress_update = 1;
		display(progress, progress->last_value, msg, 1);
	}
	clear_progress_signal(progress);
	strbuf_release(&progress->counters_sb);
	if (progress->throughput)
		strbuf_release(&progress->throughput->display);
	free(progress->throughput);
	free(progress);
}
