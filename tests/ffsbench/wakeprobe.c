/*
 * ffsbench wakeup probe.  Sleeps 100 ms at a time and, once a second,
 * prints the worst lateness seen since the last line together with the
 * free page and pageout counts:
 *
 *	wp <seconds> <late_ms_max> <free_pages> <pageouts>
 *
 * "wakeprobe -t" prints time(0) and exits; the run scripts use it for
 * timing because DR2's date has no %s.
 */
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#define PERIOD_US	100000

static long
ms_between(struct timeval *a, struct timeval *b)
{
	return (b->tv_sec - a->tv_sec) * 1000 + (b->tv_usec - a->tv_usec) / 1000;
}

int
main(int argc, char **argv)
{
	struct timeval start, before, after, last;
	vm_statistics_data_t vs;
	long late, worst = 0;

	if (argc > 1 && strcmp(argv[1], "-t") == 0) {
		printf("%ld\n", (long)time(0));
		return 0;
	}
	gettimeofday(&start, 0);
	last = start;
	for (;;) {
		gettimeofday(&before, 0);
		usleep(PERIOD_US);
		gettimeofday(&after, 0);
		late = ms_between(&before, &after) - PERIOD_US / 1000;
		if (late > worst)
			worst = late;
		if (ms_between(&last, &after) >= 1000) {
			vm_statistics(task_self(), &vs);
			printf("wp %d %d %d %d\n", (int)(after.tv_sec - start.tv_sec),
			    (int)worst, (int)vs.free_count, (int)vs.pageouts);
			fflush(stdout);
			worst = 0;
			last = after;
		}
	}
}
