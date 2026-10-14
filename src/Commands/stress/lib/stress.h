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
};

struct st_test {
	const char *name;
	long def_iters;
	int solo;			/* 1: one worker; the test forks its own */
	int (*probe)(char *why, int len); /* NULL, or nonzero + why when unsupported */
	void (*body)(struct st_ctx *);	/* returns = success; failures go via st_fail */
};

/* tests ends with a zero entry; returns the exit status. */
int stress_main(int argc, char **argv, const char *cat, const struct st_test *tests);

/* These never return: they send FAIL to the leader and _exit(1). */
void st_fail(struct st_ctx *c, const char *fmt, ...);
void st_fail_errno(struct st_ctx *c, const char *call);	/* reason="call: ERRNAME" */
void st_fail_data(struct st_ctx *c, const char *what, const unsigned char *got,
		  unsigned long len, unsigned long key, unsigned long off, long bad);

void st_op_begin(struct st_ctx *c);
void st_op_end(struct st_ctx *c, unsigned long units);
int st_more(struct st_ctx *c, long i);
unsigned long st_physmem(void);
void st_path(struct st_ctx *c, char *buf, int len, const char *tag);

/* Prints "STRESS <cat> <test> <what>[ seed=X]" on stdout. */
void st_line(const char *cat, const char *test, const char *what, int seed);

#endif
