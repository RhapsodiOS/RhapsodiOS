#include <stddef.h>
#ifndef _WIN32
#include <stdint.h>
#include <sys/types.h>
#endif

struct string;

void osgetcwd(char *, size_t);
/* changes the working directory to the given path */
void oschdir(const char *);
/* creates all the parent directories of the given path */
int osmkdirs(struct string *, _Bool);
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
