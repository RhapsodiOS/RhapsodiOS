/* compat.h - C89 shims for old toolchains.
 *
 * Windows (MSVC / NT4): force-included via Makefile.nmake -FIcompat.h
 * Rhapsody / pre-C99 POSIX: force-included via Makefile -include compat.h
 *   with -DSAMU_COMPAT -DNO_POSIX_SPAWN -Icompat
 *
 * On POSIX, sources still #include <stdint.h> etc.; the compat/ stubs are
 * empty because this header already provided the types.
 */
#ifndef SAMU_COMPAT_H
#define SAMU_COMPAT_H

#if defined(_WIN32) || defined(SAMU_COMPAT)

#include <stddef.h>   /* size_t */
#ifdef _WIN32
#include <stdarg.h>   /* va_list for snprintf shims */
#endif

/* <stdbool.h> / C99 _Bool */
#ifndef true
typedef int _Bool;
typedef _Bool bool;
#define true  1
#define false 0
#endif

/* <stdint.h> */
#ifndef SAMU_COMPAT_STDINT_DONE
#define SAMU_COMPAT_STDINT_DONE
typedef signed char        int8_t;
typedef unsigned char      uint8_t;
typedef short              int16_t;
typedef unsigned short     uint16_t;
typedef int                int32_t;
typedef unsigned int       uint32_t;
#ifdef _WIN32
typedef __int64            int64_t;
typedef unsigned __int64   uint64_t;
typedef int                ssize_t;
#else
typedef long long          int64_t;
typedef unsigned long long uint64_t;
#endif
typedef uint32_t           uint_least32_t;
typedef uint64_t           uint_least64_t;
#ifndef SIZE_MAX
#define SIZE_MAX ((size_t)-1)
#endif
#endif /* SAMU_COMPAT_STDINT_DONE */

/* <inttypes.h> printf macros */
#ifndef PRIu32
#define PRId32 "d"
#define PRIi32 "i"
#define PRIu32 "u"
#define PRIx32 "x"
#endif

/* <ctype.h> isblank (C99) */
#ifndef isblank
#ifdef SAMU_COMPAT
int isblank(int c);
#else
#define isblank(c) ((c) == ' ' || (c) == '\t')
#endif
#endif

/* <stdlib.h> 64-bit strtol (C99) — os-windows.c or compat-posix.c */
int64_t  samu_strtoll(const char *s, char **end, int base);
uint64_t samu_strtoull(const char *s, char **end, int base);
#define strtoll  samu_strtoll
#define strtoull samu_strtoull

/* C99 integer-constant macros */
#ifdef _WIN32
#ifndef INT64_C
#define INT64_C(x)  x##i64
#define UINT64_C(x) x##ui64
#endif
#else
#ifndef INT64_C
#define INT64_C(x)  x##LL
#define UINT64_C(x) x##ULL
#endif
#endif

/* C99 inline */
#ifndef inline
#ifdef _WIN32
#define inline __inline
#else
#define inline
#endif
#endif

#ifdef _WIN32
/* <time.h> monotonic clock — implemented in os-windows.c */
#ifndef CLOCK_MONOTONIC
#define CLOCK_MONOTONIC 1
struct timespec {
	long tv_sec;
	long tv_nsec;
};
int clock_gettime(int clk, struct timespec *ts);
#endif

/* snprintf/vsnprintf — implemented in os-windows.c */
int samu_snprintf(char *buf, size_t size, const char *fmt, ...);
int samu_vsnprintf(char *buf, size_t size, const char *fmt, va_list ap);
#define snprintf  samu_snprintf
#define vsnprintf samu_vsnprintf

#else /* SAMU_COMPAT POSIX / Rhapsody */

#include <time.h>
#ifndef CLOCK_MONOTONIC
#define CLOCK_MONOTONIC 1
struct timespec {
	long tv_sec;
	long tv_nsec;
};
int clock_gettime(int clk, struct timespec *ts);
#endif

/* poll(2) — implemented in compat-posix.c */
#ifndef POLLIN
#define POLLIN   0x0001
#define POLLOUT  0x0004
#define POLLERR  0x0008
#define POLLHUP  0x0010
#define POLLNVAL 0x0020
struct pollfd {
	int fd;
	short events;
	short revents;
};
int poll(struct pollfd *fds, unsigned long nfds, int timeout);
#endif

const char *strsignal(int sig);

#endif /* _WIN32 */

#endif /* _WIN32 || SAMU_COMPAT */
#endif /* SAMU_COMPAT_H */
