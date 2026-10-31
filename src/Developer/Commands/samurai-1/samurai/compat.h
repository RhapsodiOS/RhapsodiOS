/* RhapsodiOS: C89 types and legacy POSIX interfaces.
 * Windows shims are retained from the source fork. */
#ifndef SAMU_COMPAT_H
#define SAMU_COMPAT_H
#if !defined(_WIN32) && !defined(SAMU_RHAPSODY)
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#define _DEFAULT_SOURCE 1
#endif
#ifdef _WIN32

#include <stddef.h>   /* size_t */
#include <stdarg.h>   /* va_list for the snprintf shims */

/* <stdbool.h> / C99 _Bool. _Bool is an ordinary identifier under C89, so the
 * headers' `_Bool` parameter types resolve to this typedef. */
typedef int _Bool;
typedef _Bool bool;
#define true  1
#define false 0

/* <stdint.h> */
typedef signed char        int8_t;
typedef unsigned char      uint8_t;
typedef short              int16_t;
typedef unsigned short     uint16_t;
typedef int                int32_t;
typedef unsigned int       uint32_t;
typedef __int64            int64_t;
typedef unsigned __int64   uint64_t;
typedef uint32_t           uint_least32_t;
typedef uint64_t           uint_least64_t;
typedef int                ssize_t;
#ifndef SIZE_MAX
#define SIZE_MAX ((size_t)-1)
#endif

/* <inttypes.h> printf macros */
#define PRId32 "d"
#define PRIi32 "i"
#define PRIu32 "u"
#define PRIx32 "x"
/* No PRI*64 macros: this CRT's printf has no %I64 length modifier and would
 * crash. Format 64-bit values with util.h's i64dec/u64hex instead. */

/* <ctype.h> isblank (C99; absent from the NT4 CRT) */
#ifndef isblank
#define isblank(c) ((c) == ' ' || (c) == '\t')
#endif

/* <stdlib.h> 64-bit strtol (C99; the NT4 CRT has neither strtoll nor
 * _strtoi64). Implemented in os-windows.c. */
int64_t  samu_strtoll(const char *s, char **end, int base);
uint64_t samu_strtoull(const char *s, char **end, int base);
#define strtoll  samu_strtoll
#define strtoull samu_strtoull

/* C99 integer-constant macros (this CL rejects the ull/ll suffixes) */
#define INT64_C(x)  x##i64
#define UINT64_C(x) x##ui64

/* C99 inline */
#ifndef inline
#define inline __inline
#endif

/* <time.h> monotonic clock via QueryPerformanceCounter (NT4 time.h has no
 * timespec/clock_gettime). Implemented in os-windows.c. */
#ifndef CLOCK_MONOTONIC
#define CLOCK_MONOTONIC 1
struct timespec {
	long tv_sec;
	long tv_nsec;
};
int clock_gettime(int clk, struct timespec *ts);
#endif

/* snprintf/vsnprintf that always return the required length, even with a
 * NULL/zero buffer. The old CRT's _vsnprintf returns -1 on truncation, which
 * breaks util.c's xasprintf sizing. Implemented in os-windows.c. */
int samu_snprintf(char *buf, size_t size, const char *fmt, ...);
int samu_vsnprintf(char *buf, size_t size, const char *fmt, va_list ap);
#define snprintf  samu_snprintf
#define vsnprintf samu_vsnprintf

#else

#include <stddef.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#ifdef SAMU_RHAPSODY
#include <sys/types.h>
#include <sys/time.h>
typedef u_int32_t uint32_t;
typedef u_int64_t uint64_t;
typedef uint32_t uint_least32_t;
typedef uint64_t uint_least64_t;
#define PRIu32 "u"
#define UINT64_C(x) ((uint64_t)(x))
#define SIZE_MAX ((size_t)-1)
#define strtoll strtoq
#define strtoull strtouq
#ifndef isblank
#define isblank(c) ((c) == ' ' || (c) == '\t')
#endif

/* Only read readiness is needed for job output and the signal pipe. */
struct pollfd {
	int fd;
	short events, revents;
};
#define POLLIN 1
int samu_poll(struct pollfd *, size_t, int);
#define poll samu_poll

int samu_snprintf(char *, size_t, const char *, ...);
int samu_vsnprintf(char *, size_t, const char *, va_list);
#define snprintf samu_snprintf
#define vsnprintf samu_vsnprintf
#else
#include <stdint.h>
#include <inttypes.h>
#endif

typedef int bool;
#define true 1
#define false 0

#endif /* _WIN32 */
#endif /* SAMU_COMPAT_H */
