/* RhapsodiOS: interfaces missing from the Rhapsody libc. */
#include "compat.h"
#ifdef SAMU_RHAPSODY
#include <errno.h>
#include <string.h>
#include <unistd.h>

#undef snprintf
#undef vsnprintf

int
samu_vsnprintf(char *buf, size_t len, const char *fmt, va_list ap)
{
	char dummy[1];

	/* The old libc rejects size zero, but counts truncated output. */
	return vsnprintf(len ? buf : dummy, len ? len : 1, fmt, ap);
}

int
samu_snprintf(char *buf, size_t len, const char *fmt, ...)
{
	va_list ap;
	int ret;

	va_start(ap, fmt);
	ret = samu_vsnprintf(buf, len, fmt, ap);
	va_end(ap);
	return ret;
}

int
samu_poll(struct pollfd *fds, size_t n, int timeout)
{
	fd_set readfds;
	struct timeval tv;
	size_t i;
	int maxfd, ret;

	FD_ZERO(&readfds);
	maxfd = -1;
	for (i = 0; i < n; ++i) {
		fds[i].revents = 0;
		if (fds[i].fd < 0)
			continue;
		if (fds[i].fd >= FD_SETSIZE) {
			errno = EINVAL;
			return -1;
		}
		FD_SET(fds[i].fd, &readfds);
		if (fds[i].fd > maxfd)
			maxfd = fds[i].fd;
	}
	tv.tv_sec = timeout / 1000;
	tv.tv_usec = (timeout % 1000) * 1000;
	ret = select(maxfd + 1, &readfds, NULL, NULL, &tv);
	if (ret > 0) {
		for (i = 0; i < n; ++i) {
			if (fds[i].fd >= 0 && FD_ISSET(fds[i].fd, &readfds))
				fds[i].revents = POLLIN;
		}
	}
	return ret;
}
#endif
