#ifndef __DEV_XOODYAK_H__
#define __DEV_XOODYAK_H__

#include <sys/types.h>

/*
 * Xoodyak (Xoodoo[12] + Cyclist mode) - a lightweight cryptographic
 * primitive used as the core of the kernel CSPRNG.  This unit is pure:
 * no globals, no locks, no kernel dependencies, endian-neutral.  It is
 * validated in userland against reference known-answer test vectors.
 */

/* Cyclist rate parameters (bytes). */
#define XOODYAK_RHASH     16
#define XOODYAK_RKIN      44
#define XOODYAK_RKOUT     24
#define XOODYAK_RRATCHET  16

typedef struct {
    u_int8_t  s[48];    /* 384-bit Xoodoo state, little-endian byte order */
    int       mode;     /* 0 = hash, 1 = keyed */
    int       phase;    /* 0 = up, 1 = down */
    unsigned  rabsorb;
    unsigned  rsqueeze;
} xoodyak_t;

void xoodyak_init(xoodyak_t *c, const u_int8_t *key, unsigned keylen);
void xoodyak_absorb(xoodyak_t *c, const u_int8_t *in, unsigned len);
void xoodyak_squeeze(xoodyak_t *c, u_int8_t *out, unsigned len);
void xoodyak_ratchet(xoodyak_t *c);

#endif /* __DEV_XOODYAK_H__ */
