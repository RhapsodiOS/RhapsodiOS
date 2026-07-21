/* compat.h - C89 shims for old toolchains.
 *
 * Windows (MSVC / NT4): force-included via Makefile.nmake -FIcompat.h
 * Rhapsody / pre-C99 POSIX: Makefile uses -Icompat -DSAMU_COMPAT so that
 *   #include <stdint.h> (etc.) hits compat/*.h stubs, which #include this file.
 *   (Rhapsody's cc ignores gcc's -include flag.)
 *
 * Rhapsody already provides signed int8_t..int64_t via bsd/.../types.h; we only
 * add what is missing (bool, uintN_t, poll, clock_gettime, etc.).
 */
#ifndef SAMU_COMPAT_H
#define SAMU_COMPAT_H

#if defined(_WIN32) || defined(SAMU_COMPAT)

#include <stddef.h>   /* size_t */
#ifdef _WIN32
#include <stdarg.h>   /* va_list for snprintf shims */
#else
#include <sys/types.h> /* Rhapsody: int8_t..int64_t */
#endif

/* <stdbool.h> / C99 _Bool */
#ifndef true
typedef int _Bool;
typedef _Bool bool;
#define true  1
#define false 0
#endif

/* <stdint.h> — platform-specific */
#ifdef _WIN32
#ifndef SAMU_COMPAT_STDINT_DONE
#define SAMU_COMPAT_STDINT_DONE
typedef signed char        int8_t;
typedef unsigned char      uint8_t;
typedef short              int16_t;
typedef unsigned short     uint16_t;
typedef int                int32_t;
typedef unsigned int       uint32_t;
typedef __int64            int64_t;
typedef unsigned __int64   uint64_t;
typedef int                ssize_t;
typedef uint32_t           uint_least32_t;
typedef uint64_t           uint_least64_t;
#ifndef SIZE_MAX
#define SIZE_MAX ((size_t)-1)
#endif
#endif /* SAMU_COMPAT_STDINT_DONE */
#else /* SAMU_COMPAT POSIX / Rhapsody */
#ifndef _UINT8_T
#define _UINT8_T
typedef unsigned char uint8_t;
#endif
#ifndef _UINT16_T
#define _UINT16_T
typedef unsigned short uint16_t;
#endif
#ifndef _UINT32_T
#define _UINT32_T
typedef unsigned int uint32_t;
#endif
#ifndef _UINT64_T
#define _UINT64_T
typedef unsigned long long uint64_t;
#endif
#ifndef _UINT_LEAST32_T
#define _UINT_LEAST32_T
typedef uint32_t uint_least32_t;
#endif
#ifndef _UINT_LEAST64_T
#define _UINT_LEAST64_T
typedef uint64_t uint_least64_t;
#endif
#ifndef SIZE_MAX
#define SIZE_MAX ((size_t)-1)
#endif
#endif /* _WIN32 */

/* <inttypes.h> printf macros */
#ifndef PRIu32
#define PRId32 "d"
#define PRIi32 "i"
#define PRIu32 "u"
#define PRIx32 "x"
#endif

/* <ctype.h> isblank (C99) — only declare if the libc header did not */
#ifndef isblank
#ifdef SAMU_COMPAT
int isblank(int c);
#else
#define isblank(c) ((c) == ' ' || (c) == '\t')
#endif
#endif

#ifdef SAMU_COMPAT
#ifndef strsignal
const char *strsignal(int sig);
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

#include <sys/time.h>
#include <time.h>
/* Rhapsody has struct timespec in sys/time.h but no CLOCK_MONOTONIC/clock_gettime. */
#ifndef CLOCK_MONOTONIC
#define CLOCK_MONOTONIC 1
int clock_gettime(int clk, struct timespec *ts);
#endif

#ifndef O_CLOEXEC
#define O_CLOEXEC 0
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

#endif /* _WIN32 */

#endif /* _WIN32 || SAMU_COMPAT */
#endif /* SAMU_COMPAT_H */
