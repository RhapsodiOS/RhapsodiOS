/* stress-vm: virtual memory tests. Paging under pressure, copy-on-write
 * across fork, the Mach VM calls, the heap and page wiring. */
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <errno.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "stress.h"

#define MB (1024UL * 1024)

static unsigned long
pagesz(void)
{
	return (unsigned long)getpagesize();
}

/* A key for this worker's data; the offset then tells the pages apart. */
static unsigned long
wkey(struct st_ctx *c, unsigned long salt)
{
	return st_mix((st_opt.seed ^ salt) + (unsigned long)c->idx) & ST_MASK;
}

/* pressure: every worker holds its share of 1.5x RAM (or -m) and keeps
 * re-checking all of it in a random page order, so pages are evicted and
 * faulted back in under each other. */
static void
t_pressure(struct st_ctx *c)
{
	unsigned long ps = pagesz(), bytes, np, i, j, t, key;
	unsigned long *order;
	unsigned char *buf;
	long pass, bad;

	if (st_opt.mem)
		bytes = st_opt.mem / c->nprocs;
	else
		bytes = (st_physmem() + st_physmem() / 2) / c->nprocs;
	np = bytes / ps;
	if (np < 1)
		np = 1;
	buf = malloc(np * ps);
	order = malloc(np * sizeof *order);
	if (buf == NULL || order == NULL)
		st_fail_errno(c, "malloc");
	key = wkey(c, 1);
	for (i = 0; i < np; i++) {
		st_fill(buf + i * ps, ps, key, i * ps);
		order[i] = i;
	}
	if (c->selfcheck)
		buf[st_range(&c->rng, 0, np * ps - 1)] ^= 0x01;
	for (pass = 0; st_more(c, pass); pass++) {
		st_op_begin(c);
		for (i = np - 1; i > 0; i--) {	/* shuffle */
			j = st_range(&c->rng, 0, i);
			t = order[i];
			order[i] = order[j];
			order[j] = t;
		}
		for (i = 0; i < np; i++) {
			bad = st_check(buf + order[i] * ps, ps, key, order[i] * ps);
			if (bad >= 0)
				st_fail_data(c, "page", buf + order[i] * ps, ps, key,
					     order[i] * ps, bad);
		}
		st_op_end(c, np);
	}
	free(buf);
	free(order);
}

#define COWSIZE (4 * MB)
#define COWREWRITE 16

static void
t_cow(struct st_ctx *c)
{
	unsigned long ps = pagesz(), np = COWSIZE / ps, i, p, key, nkey;
	unsigned char *buf, *mine;
	long gen, bad;
	pid_t pid;
	int status;

	buf = malloc(COWSIZE);
	mine = malloc(np);
	if (buf == NULL || mine == NULL)
		st_fail_errno(c, "malloc");
	key = wkey(c, 2);
	st_fill(buf, COWSIZE, key, 0);
	for (gen = 0; st_more(c, gen); gen++) {
		st_op_begin(c);
		nkey = st_mix(key + gen + 1);
		memset(mine, 0, np);
		for (i = 0; i < COWREWRITE; i++)
			mine[st_range(&c->rng, 0, np - 1)] = 1;
		pid = fork();
		if (pid < 0)
			st_fail_errno(c, "fork");
		if (pid == 0) {
			for (p = 0; p < np; p++)
				if (mine[p])
					st_fill(buf + p * ps, ps, nkey, p * ps);
			for (p = 0; p < np; p++) {
				bad = mine[p] ? st_check(buf + p * ps, ps, nkey, p * ps)
				    : st_check(buf + p * ps, ps, key, p * ps);
				if (bad >= 0)
					st_fail_data(c, mine[p] ? "child-new" : "child-old",
						     buf + p * ps, ps, mine[p] ? nkey : key,
						     p * ps, bad);
			}
			_exit(0);
		}
		while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
			;
		if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
			st_fail(c, "reason=\"child: status=0x%x\"", status);
		if (c->selfcheck && gen == 0)
			buf[st_range(&c->rng, 0, COWSIZE - 1)] ^= 0x01;
		bad = st_check(buf, COWSIZE, key, 0);
		if (bad >= 0)
			st_fail_data(c, "parent", buf + bad, COWSIZE - bad, key, bad, 0);
		st_op_end(c, np);
	}
	free(buf);
	free(mine);
}

#define MACHSIZE (256 * 1024)

static void
kchk(struct st_ctx *c, const char *call, kern_return_t kr)
{
	if (kr != KERN_SUCCESS)
		st_fail(c, "reason=\"%s: kr=%d\"", call, (int)kr);
}

static void
t_machvm(struct st_ctx *c)
{
	vm_address_t a, b;
	unsigned long key;
	long i, bad;

	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		key = wkey(c, 3 + i);
		a = b = 0;
		kchk(c, "vm_allocate", vm_allocate(task_self(), &a, MACHSIZE, TRUE));
		kchk(c, "vm_allocate", vm_allocate(task_self(), &b, MACHSIZE, TRUE));
		st_fill((void *)a, MACHSIZE, key, 0);
		kchk(c, "vm_copy", vm_copy(task_self(), a, MACHSIZE, b));
		if (c->selfcheck)
			((unsigned char *)b)[st_range(&c->rng, 0, MACHSIZE - 1)] ^= 0x01;
		bad = st_check((void *)b, MACHSIZE, key, 0);
		if (bad >= 0)
			st_fail_data(c, "copy", (unsigned char *)b + bad, MACHSIZE - bad,
				     key, bad, 0);
		kchk(c, "vm_protect", vm_protect(task_self(), b, MACHSIZE, FALSE, VM_PROT_READ));
		kchk(c, "vm_deallocate", vm_deallocate(task_self(), a, MACHSIZE));
		kchk(c, "vm_deallocate", vm_deallocate(task_self(), b, MACHSIZE));
		st_op_end(c, MACHSIZE / 1024);
	}
}

#define NBLK 64

struct blk {
	unsigned char *p;
	unsigned long size, key;
};

static unsigned long
blksize(struct st_ctx *c)
{
	unsigned long e = st_range(&c->rng, 0, 12), base = 16UL << e;

	return e < 12 ? base + st_range(&c->rng, 0, base - 1) : base;
}

static void
blkcheck(struct st_ctx *c, struct blk *b, unsigned long len)
{
	long bad = st_check(b->p, len, b->key, 0);

	if (bad >= 0)
		st_fail_data(c, "block", b->p, len, b->key, 0, bad);
}

/* Re-keys a block: the key is (block id, generation). */
static void
blkfill(struct st_ctx *c, struct blk *b, int id, unsigned long *gen)
{
	b->key = st_mix(((unsigned long)id << 20) ^ (*gen)++ ^ wkey(c, 4));
	st_fill(b->p, b->size, b->key, 0);
}

static void
t_brk(struct st_ctx *c)
{
	struct blk tab[NBLK];
	unsigned long gen = 0, ns;
	unsigned char *np;
	int id, hit = 0;
	long i;

	memset(tab, 0, sizeof tab);
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		id = st_range(&c->rng, 0, NBLK - 1);
		if (tab[id].p == NULL) {
			tab[id].size = blksize(c);
			tab[id].p = malloc(tab[id].size);
			if (tab[id].p == NULL)
				st_fail_errno(c, "malloc");
			blkfill(c, &tab[id], id, &gen);
			if (c->selfcheck && !hit) {
				hit = 1;
				tab[id].p[st_range(&c->rng, 0, tab[id].size - 1)] ^= 0x01;
			}
		} else if (st_rand(&c->rng) & 1) {
			blkcheck(c, &tab[id], tab[id].size);
			free(tab[id].p);
			tab[id].p = NULL;
		} else {
			blkcheck(c, &tab[id], tab[id].size);
			ns = blksize(c);
			np = realloc(tab[id].p, ns);
			if (np == NULL)
				st_fail_errno(c, "realloc");
			tab[id].p = np;
			blkcheck(c, &tab[id], ns < tab[id].size ? ns : tab[id].size);
			tab[id].size = ns;
			blkfill(c, &tab[id], id, &gen);
		}
		st_op_end(c, 1);
	}
	for (id = 0; id < NBLK; id++) {
		if (tab[id].p != NULL) {
			blkcheck(c, &tab[id], tab[id].size);
			free(tab[id].p);
		}
	}
}

/* libc has no mlock stubs on this system, so the calls are bound through
 * dyld when something defines them; otherwise the test is unsupported. */
static int (*lockfn)(void *, size_t);
static int (*unlockfn)(void *, size_t);

static int
bindwire(void)
{
	if (lockfn != NULL)
		return 1;
	if (!NSIsSymbolNameDefined("_mlock") || !NSIsSymbolNameDefined("_munlock"))
		return 0;
	lockfn = (int (*)(void *, size_t))NSAddressOfSymbol(NSLookupAndBindSymbol("_mlock"));
	unlockfn = (int (*)(void *, size_t))NSAddressOfSymbol(NSLookupAndBindSymbol("_munlock"));
	return lockfn != NULL && unlockfn != NULL;
}

static int
p_wire(char *why, int len)
{
	unsigned long ps = pagesz();
	char *p = malloc(2 * ps);
	int e;

	if (!bindwire()) {
		sprintf(why, "mlock: %s", st_errname(ENOSYS));
		return 1;
	}
	if (p == NULL)
		return 0;
	p = (char *)(((unsigned long)p + ps - 1) & ~(ps - 1));
	if (lockfn(p, ps) == 0) {
		unlockfn(p, ps);
		return 0;
	}
	e = errno;
	if (e != EPERM && e != ENOSYS && e != EOPNOTSUPP)
		return 0;
	sprintf(why, "mlock: %s", st_errname(e));
	return 1;
}

/* A child that touches `limit` bytes of fresh heap, to push the wired
 * buffer's neighbours out to the pager. */
static void
squeeze(unsigned long limit)
{
	unsigned long ps = pagesz(), got = 0, o;
	unsigned char *p;

	while (got < limit && (p = malloc(MB)) != NULL) {
		for (o = 0; o < MB; o += ps)
			p[o] = 1;
		got += MB;
	}
	_exit(0);
}

static void
t_wire(struct st_ctx *c)
{
	unsigned long ps = pagesz(), key, limit;
	unsigned char *raw, *buf;
	long i, bad;
	pid_t pid;
	int status;

	limit = st_opt.mem ? st_opt.mem : st_physmem() + st_physmem() / 2;
	limit /= c->nprocs;
	raw = malloc(MB + ps);
	if (raw == NULL)
		st_fail_errno(c, "malloc");
	buf = (unsigned char *)(((unsigned long)raw + ps - 1) & ~(ps - 1));
	for (i = 0; st_more(c, i); i++) {
		st_op_begin(c);
		key = wkey(c, 5 + i);
		st_fill(buf, MB, key, 0);
		if (!bindwire() || lockfn(buf, MB) < 0)
			st_fail_errno(c, "mlock");
		pid = fork();
		if (pid < 0)
			st_fail_errno(c, "fork");
		if (pid == 0)
			squeeze(limit);
		while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
			;
		if (c->selfcheck)
			buf[st_range(&c->rng, 0, MB - 1)] ^= 0x01;
		bad = st_check(buf, MB, key, 0);
		if (bad >= 0)
			st_fail_data(c, "wired", buf + bad, MB - bad, key, bad, 0);
		if (unlockfn(buf, MB) < 0)
			st_fail_errno(c, "munlock");
		st_op_end(c, 1);
	}
	free(raw);
}

static const struct st_test tests[] = {
	{ "pressure", 3, 0, NULL, t_pressure },
	{ "cow", 20, 1, NULL, t_cow },
	{ "machvm", 200, 0, NULL, t_machvm },
	{ "brk", 20000, 0, NULL, t_brk },
	{ "wire", 50, 0, p_wire, t_wire },
	{ NULL }
};

int
main(int argc, char **argv)
{
	return stress_main(argc, argv, "vm", tests);
}
