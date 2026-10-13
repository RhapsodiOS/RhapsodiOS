/* Host test type bridge only: all disk structs come from exported headers. */
#ifndef EXT2_HOST_COMPAT_H
#define EXT2_HOST_COMPAT_H
#include <stdint.h>
#include <stddef.h>
#include <sys/types.h>
typedef uint8_t u_int8_t;
typedef uint16_t u_int16_t;
typedef uint32_t u_int32_t;
typedef uint64_t u_int64_t;
typedef unsigned char u_char;
#ifndef __P
#define __P(x) x
#endif
#define LITTLE_ENDIAN 1234
#define BIG_ENDIAN 4321
#define BYTE_ORDER LITTLE_ENDIAN
#define EXT2_PORTABLE_TEST 1
#endif
