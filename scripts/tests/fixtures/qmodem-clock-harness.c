/* Exercise the real scanner queue without changing the host clock or UCI. */
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static time_t wall_now = 1800000000;
static time_t mono_now = 1000;
static int wait_count;
static clockid_t condition_clock = CLOCK_REALTIME;

static time_t test_time(time_t *result)
{
    if (result) *result = wall_now;
    return wall_now;
}

static int test_clock_gettime(clockid_t clock, struct timespec *result)
{
    result->tv_sec = clock == CLOCK_MONOTONIC ? mono_now : wall_now;
    result->tv_nsec = 0;
    return 0;
}

static int test_cond_init(pthread_cond_t *condition, const pthread_condattr_t *attr)
{
    if (attr) assert(pthread_condattr_getclock(attr, &condition_clock) == 0);
    return pthread_cond_init(condition, attr);
}

static int test_cond_timedwait(pthread_cond_t *condition, pthread_mutex_t *lock,
                               const struct timespec *deadline)
{
    (void)condition;
    (void)lock;
    time_t now = condition_clock == CLOCK_MONOTONIC ? mono_now : wall_now;
    assert(deadline->tv_sec == now + 1);
    if (++wait_count > 16) {
        fprintf(stderr, "FAIL: delayed scan remains blocked after clock rollback\n");
        exit(20);
    }
    ++wall_now;
    ++mono_now;
    return 0;
}

#define time test_time
#define clock_gettime test_clock_gettime
#define pthread_cond_init test_cond_init
#define pthread_cond_timedwait test_cond_timedwait
#define main scanner_daemon_main
#include QMODEM_SCANNER_SOURCE
#undef main
#undef pthread_cond_timedwait
#undef pthread_cond_init
#undef clock_gettime
#undef time

int main(int argc, char **argv)
{
    assert(argc == 2);
    assert(pthread_mutex_init(&g.queue_lock, NULL) == 0);
#ifdef TEST_PATCHED
    assert(init_queue_condition() == 0);
#else
    assert(test_cond_init(&g.queue_cond, NULL) == 0);
#endif
    g.log_level = LOG_L_ERR;
    if (!strcmp(argv[1], "condition")) {
        assert(condition_clock == CLOCK_MONOTONIC);
        puts("PASS: queue condition uses CLOCK_MONOTONIC");
        return 0;
    }
    int delay = !strcmp(argv[1], "immediate") ? 0 : 8;
    assert(enqueue_event(EV_ADD, "6-1", "usb", delay) == 0);
    if (!strcmp(argv[1], "backward")) {
        wall_now -= 7200;
        /* Match the reported device: an old pending add deduplicates new adds. */
        assert(enqueue_event(EV_ADD, "6-1", "usb", 0) == 1);
    } else if (!strcmp(argv[1], "forward")) {
        wall_now += 7200;
    }
    struct event *event = dequeue_event();
    assert(event && !strcmp(event->slot, "6-1"));
    assert(wait_count == delay);
    current_event = event;
    assert(event_current());
    finish_event_key(event);
    free(event);
    current_event = NULL;
    assert(g.queue_len == 0 && g.active_jobs == 0 && active_resources.len == 0);
    printf("PASS: %s scan executes after %d elapsed seconds\n", argv[1], wait_count);
    return 0;
}
