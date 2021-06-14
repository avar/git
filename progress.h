#ifndef PROGRESS_H
#define PROGRESS_H

struct progress;

/*
 * test_*() functions are only for use in t/helper/test-progress.c. Do
 * not use them elsewhere!
 */
void test_progress_force_update(void);
struct progress *test_progress_start(const char *title, uint64_t total);
void test_progress_setnanotime(struct progress *progress, uint64_t time);

void display_throughput(struct progress *progress, uint64_t total);
void display_progress(struct progress *progress, uint64_t n);
struct progress *start_progress(const char *title, uint64_t total);
struct progress *start_sparse_progress(const char *title, uint64_t total);
struct progress *start_delayed_progress(const char *title, uint64_t total);
struct progress *start_delayed_sparse_progress(const char *title,
					       uint64_t total);
void stop_progress(struct progress **progress);
void stop_progress_msg(struct progress **progress, const char *msg);

#endif
