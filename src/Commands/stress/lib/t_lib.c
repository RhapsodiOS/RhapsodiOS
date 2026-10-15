#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "stress.h"

#define CHECK(c) do { if (!(c)) { printf("t_lib: FAIL line %d: %s\n", __LINE__, #c); return 1; } } while (0)

static struct st_leak lb, la;

static void
zone(struct st_leak *s, const char *name, long count)
{
	strcpy(s->name[s->nzones], name);
	s->count[s->nzones++] = count;
}

static void
clear(void)
{
	memset(&lb, 0, sizeof lb);
	memset(&la, 0, sizeof la);
	lb.wired = la.wired = lb.mbufs = la.mbufs = 0;
}

static unsigned char big[4096], win[100], pbuf[100000], rbuf[100000];

int
main(void)
{
	struct st_rng a, b, c;
	unsigned long v;
	int i, fds[2];
	pid_t pid;

	CHECK(st_mix(0) == 0);			/* the mix fixes 0; seeds avoid it */
	CHECK(st_mix(1) != 1);
	CHECK(st_strhash("") == 0x811c9dc5UL);
	/* determinism: same seed/test/idx -> same stream; different idx -> different */
	st_rng_init(&a, 1234, "cow", 0);
	st_rng_init(&b, 1234, "cow", 0);
	st_rng_init(&c, 1234, "cow", 1);
	CHECK(st_rand(&a) == st_rand(&b));
	CHECK(st_rand(&a) != st_rand(&c));
	for (i = 0; i < 1000; i++) {
		v = st_range(&a, 5, 9);
		CHECK(v >= 5 && v <= 9);
	}
	/* patterns: offset-addressable, unaligned windows agree with the whole */
	st_fill(big, 4096, 77, 0);
	st_fill(win, 100, 77, 13);
	CHECK(memcmp(big + 13, win, 100) == 0);
	CHECK(st_check(big, 4096, 77, 0) == -1);
	big[1234] ^= 0x40;
	CHECK(st_check(big, 4096, 77, 0) == 1234);
	CHECK(st_check(big, 4096, 78, 0) == 0);	/* wrong key fails at once */
	/* known vector pins the byte order for ppc too */
	CHECK(st_mix(1) == 0x688990c0UL);
	CHECK(st_mix(0x9e3779baUL) == 0x9f505634UL);	/* key 1, offset 0: (1 ^ 0) + 0x9e3779b9 */
	st_fill(win, 4, 1, 0);
	CHECK(win[0] == 0x34 && win[1] == 0x56 && win[2] == 0x50 && win[3] == 0x9f);
	/* where (o >> 2) == key the word must not be zero, or NUL holes hide */
	st_fill(win, 4, 5, 5 * 4);
	CHECK(win[0] | win[1] | win[2] | win[3]);
	CHECK(strcmp(st_errname(ENOSYS), "ENOSYS") == 0);
	CHECK(strcmp(st_errname(9999), "E9999") == 0);
	/* 1-byte writes from a child must come back whole through one read call */
	for (i = 0; i < 100000; i++)
		pbuf[i] = i * 7;
	CHECK(pipe(fds) == 0);
	pid = fork();
	CHECK(pid >= 0);
	if (pid == 0) {
		for (i = 0; i < 100000; i++)
			if (st_writefull(fds[1], pbuf + i, 1) != 1)
				_exit(1);
		_exit(0);
	}
	close(fds[1]);
	CHECK(st_readfull(fds[0], rbuf, 100000) == 100000);
	CHECK(memcmp(pbuf, rbuf, 100000) == 0);
	CHECK(st_readfull(fds[0], rbuf, 10) == 0);
	close(fds[0]);
	CHECK(waitpid(pid, &i, 0) == pid && i == 0);
	/* leak diff: thresholds, ordering, name matching */
	{
		char o[400];

		clear();
		zone(&lb, "vm.objects", 1000);
		zone(&la, "vm.objects", 1065);
		strcpy(o, "keep");
		CHECK(st_leak_diff(&lb, &la, o, sizeof o) == 0 && strcmp(o, "keep") == 0);
		clear();
		zone(&lb, "ipc ports", 100);
		zone(&la, "ipc ports", 165);
		o[0] = '\0';
		CHECK(st_leak_diff(&lb, &la, o, sizeof o) == 1 && strcmp(o, " leak=ipc_ports:+65") == 0);
		clear();
		zone(&lb, "a", 100);
		zone(&lb, "b", 100);
		zone(&lb, "c", 100);
		zone(&lb, "d", 100);
		zone(&la, "b", 300);
		zone(&la, "a", 200);
		zone(&la, "d", 500);
		zone(&la, "c", 400);
		o[0] = '\0';
		CHECK(st_leak_diff(&lb, &la, o, sizeof o) == 1 && strcmp(o, " leak=d:+400,c:+300,b:+200") == 0);
		clear();
		la.wired = 533;
		lb.wired = 500;
		o[0] = '\0';
		CHECK(st_leak_diff(&lb, &la, o, sizeof o) == 1 && strcmp(o, " wired=+33") == 0);
		la.wired = 532;
		strcpy(o, "keep");
		CHECK(st_leak_diff(&lb, &la, o, sizeof o) == 0 && strcmp(o, "keep") == 0);
		la.wired = -1;
		CHECK(st_leak_diff(&lb, &la, o, sizeof o) == 0 && strcmp(o, "keep") == 0);
		clear();
		lb.mbufs = 10;
		la.mbufs = 75;
		o[0] = '\0';
		CHECK(st_leak_diff(&lb, &la, o, sizeof o) == 1 && strcmp(o, " mbufs=+65") == 0);
		lb.mbufs = -1;
		strcpy(o, "keep");
		CHECK(st_leak_diff(&lb, &la, o, sizeof o) == 0 && strcmp(o, "keep") == 0);
		lb.mbufs = 10;
		la.mbufs = -1;
		CHECK(st_leak_diff(&lb, &la, o, sizeof o) == 0 && strcmp(o, "keep") == 0);
		clear();
		zone(&la, "new", 65);
		o[0] = '\0';
		CHECK(st_leak_diff(&lb, &la, o, sizeof o) == 1 && strcmp(o, " leak=new:+65") == 0);
		lb.nzones = -1;
		strcpy(o, "keep");
		CHECK(st_leak_diff(&lb, &la, o, sizeof o) == 0 && strcmp(o, "keep") == 0);
	}
	printf("t_lib: ok\n");
	return 0;
}
