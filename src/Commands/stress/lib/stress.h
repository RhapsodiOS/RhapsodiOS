/* Shared helpers for the system stress suite. C89; 32-bit values are held
 * in unsigned long and masked, so i386 and ppc agree bit for bit. */
#ifndef STRESS_H
#define STRESS_H

#define ST_MASK 0xffffffffUL

struct st_rng {
	unsigned long s;
};

unsigned long st_mix(unsigned long x);
unsigned long st_strhash(const char *s);
void st_rng_init(struct st_rng *r, unsigned long seed, const char *test, int idx);
unsigned long st_rand(struct st_rng *r);
unsigned long st_range(struct st_rng *r, unsigned long lo, unsigned long hi);

/* The byte at absolute offset o is byte (o & 3), least significant first,
 * of st_mix(((key ^ (o >> 2)) + 0x9e3779b9) & ST_MASK). */
void st_fill(void *buf, unsigned long len, unsigned long key, unsigned long off);
long st_check(const void *buf, unsigned long len, unsigned long key, unsigned long off);

const char *st_errname(int err);

/* Options, parsed once in stress_main. */
struct st_opts {
	int procs;			/* -n, default 4 */
	long iters;			/* -i, 0: the test's default */
	int secs;			/* -t watchdog, default 600 */
	unsigned long seed;		/* -s, default time ^ pid */
	const char *dir;		/* -d, default /tmp */
	unsigned long mem;		/* -m, 0: the test decides */
	int verbose;			/* -v */
	int selfcheck;			/* -x */
	const char *dev;		/* -D raw device, default NULL */
	int leakfail;			/* -L or STRESS_LEAK=fail */
	int noleak;			/* -N: no leak snapshot or fields; overrides -L */
	int budget;			/* -T: st_more returns 0 after this many seconds; 0: no budget.
					 * A test whose two processes run a shared count (ipc msg/ool,
					 * net select) sets it to 0: -T would stop one end only. */
};
extern struct st_opts st_opt;

/* One per worker process. */
struct st_ctx {
	const char *cat, *test;
	int idx, nprocs;		/* worker index and count */
	long iters;			/* -i, else the test's default */
	struct st_rng rng;
	int selfcheck;			/* -x */
	long t_start;			/* seconds, taken by the leader before it forks the workers */
	long iter;			/* the last i given to st_more, for FAIL lines */
	/* private */
	unsigned long units, maxlat_us, clockback;
	long t0_sec, t0_usec;
	int fd;				/* result pipe to the leader */
	void (*cleanup)(struct st_ctx *); /* st_set_cleanup */
};

struct st_test {
	const char *name;
	long def_iters;
	int solo;			/* 1: one worker; the test forks its own */
	int (*probe)(char *why, int len); /* NULL; >0 + why: UNSUP; <0 + why: FAIL with why as the fields */
	void (*body)(struct st_ctx *);	/* returns = success; failures go via st_fail */
	int named_only;			/* 1: runs only when named on the command line */
};

/* tests ends with a zero entry; returns the exit status. */
int stress_main(int argc, char **argv, const char *cat, const struct st_test *tests);

/* 1 when the leader still counts live workers but waitpid failed with err
 * ECHILD: the children are gone without having been reaped (lost-child). */
int st_lost(int live, int err);

/* These never return: they send FAIL to the leader and _exit(1). */
void st_fail(struct st_ctx *c, const char *fmt, ...);
void st_fail_errno(struct st_ctx *c, const char *call);	/* reason="call: ERRNAME" */
void st_fail_data(struct st_ctx *c, const char *what, const unsigned char *got,
		  unsigned long len, unsigned long key, unsigned long off, long bad);

/* st_fail (and so st_fail_errno/st_fail_data) calls fn(c) once, before the FAIL
 * line is written. fn must not call st_fail; it is cleared before it runs. */
void st_set_cleanup(struct st_ctx *c, void (*fn)(struct st_ctx *));

/* Loop on EINTR and short transfers. st_readfull returns len, fewer bytes
 * only at EOF, or -1; st_writefull returns len or -1. */
long st_readfull(int fd, void *buf, unsigned long len);
long st_writefull(int fd, const void *buf, unsigned long len);

void st_op_begin(struct st_ctx *c);
void st_op_end(struct st_ctx *c, unsigned long units);
int st_more(struct st_ctx *c, long i);
unsigned long st_physmem(void);
void st_path(struct st_ctx *c, char *buf, int len, const char *tag);

/* Prints "STRESS <cat> <test> <what>[ seed=X]" on stdout. */
void st_line(const char *cat, const char *test, const char *what, int seed);

/* Kernel resource counts, taken before and after a test. */
#define ST_LEAK_ZONES 256
struct st_leak {
	int nzones;			/* -1: zone info unavailable */
	char name[ST_LEAK_ZONES][80];
	long count[ST_LEAK_ZONES];
	long wired;			/* -1: unavailable */
	long mbufs;			/* -1: unavailable */
};
void st_leak_snap(struct st_leak *s);
/* Appends " leak=... wired=+N mbufs=+N" (only parts past the thresholds) to out; returns 1 if anything was appended. */
int st_leak_diff(const struct st_leak *before, const struct st_leak *after, char *out, int len);

#endif
