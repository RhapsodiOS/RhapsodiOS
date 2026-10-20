#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "stress.h"

static const struct {
	int num;
	const char *name;
} errtab[] = {
	{ EPERM, "EPERM" }, { ENOENT, "ENOENT" }, { EINTR, "EINTR" },
	{ EIO, "EIO" }, { EBADF, "EBADF" }, { ECHILD, "ECHILD" },
	{ EAGAIN, "EAGAIN" }, { ENOMEM, "ENOMEM" }, { EACCES, "EACCES" },
	{ EFAULT, "EFAULT" }, { EEXIST, "EEXIST" }, { ENOTDIR, "ENOTDIR" },
	{ EISDIR, "EISDIR" }, { EINVAL, "EINVAL" }, { ENFILE, "ENFILE" },
	{ EMFILE, "EMFILE" }, { ENOSPC, "ENOSPC" }, { EPIPE, "EPIPE" },
	{ ENOSYS, "ENOSYS" }, { EOPNOTSUPP, "EOPNOTSUPP" }, { EBUSY, "EBUSY" },
	{ EPROTONOSUPPORT, "EPROTONOSUPPORT" }, { EADDRINUSE, "EADDRINUSE" },
	{ ECONNREFUSED, "ECONNREFUSED" }, { ECONNRESET, "ECONNRESET" },
	{ ENOBUFS, "ENOBUFS" }, { ETIMEDOUT, "ETIMEDOUT" }, { ENOTSOCK, "ENOTSOCK" }
};

const char *
st_errname(int err)
{
	static char buf[16];
	unsigned int i;

	for (i = 0; i < sizeof errtab / sizeof errtab[0]; i++)
		if (errtab[i].num == err)
			return errtab[i].name;
	sprintf(buf, "E%d", err);
	return buf;
}

void
st_line(const char *cat, const char *test, const char *what, int seed)
{
	printf("STRESS %s %s %s", cat, test, what);
	if (seed)
		printf(" seed=%lu", st_opt.seed);
	printf("\n");
	fflush(stdout);
}

void
st_set_cleanup(struct st_ctx *c, void (*fn)(struct st_ctx *))
{
	c->cleanup = fn;
}

/* One write of at most PIPE_BUF (512) bytes, so lines from several
 * workers never interleave. */
void
st_fail(struct st_ctx *c, const char *fmt, ...)
{
	char buf[2048], at[64];
	va_list ap;
	int n, m;
	void (*fn)(struct st_ctx *) = c->cleanup;

	if (fn) {
		c->cleanup = NULL;
		fn(c);
	}

	strcpy(buf, "FAIL ");
	va_start(ap, fmt);
	vsprintf(buf + 5, fmt, ap);
	va_end(ap);
	m = sprintf(at, " worker=%d iter=%ld\n", c->idx, c->iter);
	n = strlen(buf);
	if (n > 511 - m)
		n = 511 - m;
	strcpy(buf + n, at);
	write(c->fd, buf, n + m);
	_exit(1);
}

void
st_unsup(struct st_ctx *c, const char *fmt, ...)
{
	char buf[2048];
	va_list ap;
	int n;
	void (*fn)(struct st_ctx *) = c->cleanup;

	if (fn) {
		c->cleanup = NULL;
		fn(c);
	}
	strcpy(buf, "UNSUP ");
	va_start(ap, fmt);
	vsprintf(buf + 6, fmt, ap);
	va_end(ap);
	n = strlen(buf);
	if (n > 510)
		n = 510;
	buf[n++] = '\n';
	write(c->fd, buf, n);
	_exit(0);
}

void
st_fail_errno(struct st_ctx *c, const char *call)
{
	st_fail(c, "reason=\"%s: %s\"", call, st_errname(errno));
}

/* got[bad] is the first wrong byte of a buffer filled from (key, off). */
void
st_fail_data(struct st_ctx *c, const char *what, const unsigned char *got,
	     unsigned long len, unsigned long key, unsigned long off, long bad)
{
	unsigned char want[16];
	char w[33], g[33];
	unsigned long n = len - bad, i;

	if (n > 16)
		n = 16;
	st_fill(want, n, key, off + bad);
	w[0] = g[0] = '\0';
	for (i = 0; i < n; i++) {
		sprintf(w + 2 * i, "%02x", want[i]);
		sprintf(g + 2 * i, "%02x", got[bad + i]);
	}
	st_fail(c, "what=%s off=0x%lx want=%s got=%s", what, off + bad, w, g);
}
