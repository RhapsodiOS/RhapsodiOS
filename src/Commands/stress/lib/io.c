#include <errno.h>
#include <unistd.h>
#include "stress.h"

long
st_readfull(int fd, void *buf, unsigned long len)
{
	unsigned long got = 0;
	long n;

	while (got < len) {
		n = read(fd, (char *)buf + got, len - got);
		if (n < 0 && errno == EINTR)
			continue;
		if (n < 0)
			return -1;
		if (n == 0)
			break;
		got += n;
	}
	return got;
}

long
st_writefull(int fd, const void *buf, unsigned long len)
{
	unsigned long put = 0;
	long n;

	while (put < len) {
		n = write(fd, (const char *)buf + put, len - put);
		if (n < 0 && errno == EINTR)
			continue;
		if (n < 0)
			return -1;
		put += n;
	}
	return put;
}
