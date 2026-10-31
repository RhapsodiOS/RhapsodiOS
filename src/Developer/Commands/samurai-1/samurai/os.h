/* RhapsodiOS: C89 and legacy POSIX port. */
#include "compat.h"
#include <stddef.h>
#ifndef _WIN32
#include <sys/types.h>
#endif

struct string;

struct samu_time {
	long tv_sec, tv_nsec;
};
/* Time used for progress displays, independent of system timespec spelling. */
int osclock(struct samu_time *);

void osgetcwd(char *, size_t);
/* changes the working directory to the given path */
void oschdir(const char *);
/* creates all the parent directories of the given path */
int osmkdirs(struct string *, bool);
/* queries the mtime of a file in nanoseconds since the UNIX epoch */
int64_t osmtime(const char *);
/* queries the number of online processors */
long osnproc(void);
/* spawn a child process */
#ifdef _WIN32
void *osspawn(const char *cmd, void *out);
#else
pid_t osspawn(char *const argv[], int fd);
#endif
