/*
 * POSIX implementations of compat.h shims (Rhapsody / SAMU_COMPAT).
 * Windows counterparts live in os-windows.c.
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/select.h>
#include <unistd.h>

#include "compat.h"

int
poll(struct pollfd *fds, unsigned long nfds, int timeout)
{
	fd_set rfds, wfds, efds;
	struct timeval tv, *tvp;
	unsigned long i;
	int maxfd, n, fd;
	short rev;

	FD_ZERO(&rfds);
	FD_ZERO(&wfds);
	FD_ZERO(&efds);
	maxfd = -1;

	for (i = 0; i < nfds; ++i) {
		fd = fds[i].fd;
		fds[i].revents = 0;
		if (fd < 0)
			continue;
		if (fds[i].events & POLLIN)
			FD_SET(fd, &rfds);
		if (fds[i].events & POLLOUT)
			FD_SET(fd, &wfds);
		FD_SET(fd, &efds);
		if (fd > maxfd)
			maxfd = fd;
	}

	if (timeout < 0) {
		tvp = NULL;
	} else {
		tv.tv_sec = timeout / 1000;
		tv.tv_usec = (timeout % 1000) * 1000;
		tvp = &tv;
	}

	n = select(maxfd + 1, &rfds, &wfds, &efds, tvp);
	if (n <= 0)
		return n;

	n = 0;
	for (i = 0; i < nfds; ++i) {
		fd = fds[i].fd;
		rev = 0;
		if (fd < 0)
			continue;
		if ((fds[i].events & POLLIN) && FD_ISSET(fd, &rfds))
			rev |= POLLIN;
		if ((fds[i].events & POLLOUT) && FD_ISSET(fd, &wfds))
			rev |= POLLOUT;
		if (FD_ISSET(fd, &efds))
			rev |= POLLERR;
		fds[i].revents = rev;
		if (rev)
			++n;
	}
	return n;
}

int
clock_gettime(int clk, struct timespec *ts)
{
	struct timeval tv;

	(void)clk;
	if (!ts) {
		errno = EFAULT;
		return -1;
	}
	if (gettimeofday(&tv, NULL) != 0)
		return -1;
	ts->tv_sec = tv.tv_sec;
	ts->tv_nsec = tv.tv_usec * 1000;
	return 0;
}

static uint64_t
samu_parse_u64(const char *s, char **end, int base, int *neg_out)
{
	const char *p = s;
	uint64_t acc = 0;
	int neg = 0, any = 0, digit;

	while (isspace((unsigned char)*p))
		++p;
	if (*p == '-' || *p == '+') {
		neg = (*p == '-');
		++p;
	}
	if (base == 0) {
		if (*p == '0') {
			if (p[1] == 'x' || p[1] == 'X') {
				base = 16;
				p += 2;
			} else {
				base = 8;
			}
		} else {
			base = 10;
		}
	} else if (base == 16 && *p == '0' && (p[1] == 'x' || p[1] == 'X')) {
		p += 2;
	}

	for (; *p; ++p) {
		if (*p >= '0' && *p <= '9')
			digit = *p - '0';
		else if (*p >= 'a' && *p <= 'z')
			digit = *p - 'a' + 10;
		else if (*p >= 'A' && *p <= 'Z')
			digit = *p - 'A' + 10;
		else
			break;
		if (digit >= base)
			break;
		any = 1;
		acc = acc * (uint64_t)base + (uint64_t)digit;
	}
	if (end)
		*end = (char *)(any ? p : s);
	if (neg_out)
		*neg_out = neg;
	return acc;
}

uint64_t
samu_strtoull(const char *s, char **end, int base)
{
	return samu_parse_u64(s, end, base, NULL);
}

int64_t
samu_strtoll(const char *s, char **end, int base)
{
	int neg = 0;
	uint64_t u = samu_parse_u64(s, end, base, &neg);
	return neg ? -(int64_t)u : (int64_t)u;
}

#ifndef isblank
int
isblank(int c)
{
	return c == ' ' || c == '\t';
}
#endif

#ifndef strsignal
const char *
strsignal(int sig)
{
	static char buf[32];
	sprintf(buf, "signal %d", sig);
	return buf;
}
#endif
