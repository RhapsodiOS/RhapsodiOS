#include <errno.h>
#include <stdio.h>
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
	{ ENOSYS, "ENOSYS" }, { EOPNOTSUPP, "EOPNOTSUPP" },
	{ EPROTONOSUPPORT, "EPROTONOSUPPORT" }, { EADDRINUSE, "EADDRINUSE" },
	{ ECONNREFUSED, "ECONNREFUSED" }, { ECONNRESET, "ECONNRESET" },
	{ ENOBUFS, "ENOBUFS" }, { ETIMEDOUT, "ETIMEDOUT" }
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
