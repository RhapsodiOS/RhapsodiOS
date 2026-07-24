#include <dev/random/xoodyak.h>

/*
 * Xoodoo[12] permutation and Xoodyak Cyclist mode, clean-room from the
 * public Xoodoo/Xoodyak specification (Daemen, Hoffert, Peeters, Van
 * Assche, Van Keer).  The 384-bit state is held as 48 little-endian
 * bytes; lanes are loaded/stored with explicit shifts so the code is
 * correct on both little-endian (i386) and big-endian (ppc) targets.
 */

#define ROTL32(x, n) (((x) << (n)) | ((x) >> (32 - (n))))

static u_int32_t
load32(const u_int8_t *p)
{
    return (u_int32_t)p[0] | ((u_int32_t)p[1] << 8) |
           ((u_int32_t)p[2] << 16) | ((u_int32_t)p[3] << 24);
}

static void
store32(u_int8_t *p, u_int32_t v)
{
    p[0] = (u_int8_t)v;
    p[1] = (u_int8_t)(v >> 8);
    p[2] = (u_int8_t)(v >> 16);
    p[3] = (u_int8_t)(v >> 24);
}

static const u_int32_t xoodoo_rc[12] = {
    0x00000058, 0x00000038, 0x000003C0, 0x000000D0,
    0x00000120, 0x00000014, 0x00000060, 0x0000002C,
    0x00000380, 0x000000F0, 0x000001A0, 0x00000012
};

static void
xoodoo(u_int8_t st[48])
{
    u_int32_t a[12];
    int i, x;

    for (i = 0; i < 12; i++)
        a[i] = load32(st + 4 * i);

    for (i = 0; i < 12; i++) {
        u_int32_t p[4], e[4], b[4];

        /* theta */
        for (x = 0; x < 4; x++)
            p[x] = a[x] ^ a[4 + x] ^ a[8 + x];
        for (x = 0; x < 4; x++)
            e[x] = ROTL32(p[(x + 3) & 3], 5) ^ ROTL32(p[(x + 3) & 3], 14);
        for (x = 0; x < 4; x++) {
            a[x]     ^= e[x];
            a[4 + x] ^= e[x];
            a[8 + x] ^= e[x];
        }

        /* rho west */
        b[0] = a[4 + 3]; b[1] = a[4 + 0]; b[2] = a[4 + 1]; b[3] = a[4 + 2];
        for (x = 0; x < 4; x++)
            a[4 + x] = b[x];
        for (x = 0; x < 4; x++)
            a[8 + x] = ROTL32(a[8 + x], 11);

        /* iota */
        a[0] ^= xoodoo_rc[i];

        /* chi */
        for (x = 0; x < 4; x++) {
            u_int32_t a0 = a[x], a1 = a[4 + x], a2 = a[8 + x];
            a[x]     = a0 ^ (~a1 & a2);
            a[4 + x] = a1 ^ (~a2 & a0);
            a[8 + x] = a2 ^ (~a0 & a1);
        }

        /* rho east */
        for (x = 0; x < 4; x++)
            a[4 + x] = ROTL32(a[4 + x], 1);
        b[0] = ROTL32(a[8 + 2], 8); b[1] = ROTL32(a[8 + 3], 8);
        b[2] = ROTL32(a[8 + 0], 8); b[3] = ROTL32(a[8 + 1], 8);
        for (x = 0; x < 4; x++)
            a[8 + x] = b[x];
    }

    for (i = 0; i < 12; i++)
        store32(st + 4 * i, a[i]);
}

static void
down(xoodyak_t *c, const u_int8_t *x, unsigned n, u_int8_t cd)
{
    unsigned i;

    c->phase = 1;
    for (i = 0; i < n; i++)
        c->s[i] ^= x[i];
    c->s[n] ^= 0x01;
    c->s[47] ^= (c->mode == 0) ? (u_int8_t)(cd & 0x01) : cd;
}

static void
up(xoodyak_t *c, u_int8_t *y, unsigned n, u_int8_t cu)
{
    unsigned i;

    if (c->mode != 0)
        c->s[47] ^= cu;
    c->phase = 0;
    xoodoo(c->s);
    for (i = 0; i < n; i++)
        y[i] = c->s[i];
}

static void
absorb_any(xoodyak_t *c, const u_int8_t *x, unsigned n, unsigned r, u_int8_t cd)
{
    int first = 1;
    unsigned b;

    do {
        b = (n < r) ? n : r;
        if (c->phase != 0)
            up(c, (u_int8_t *)0, 0, 0);
        down(c, x, b, first ? cd : (u_int8_t)0x00);
        first = 0;
        x += b;
        n -= b;
    } while (n > 0);
}

static void
squeeze_any(xoodyak_t *c, u_int8_t *y, unsigned n, u_int8_t cu)
{
    unsigned r = c->rsqueeze;
    unsigned b;

    b = (n < r) ? n : r;
    up(c, y, b, cu);
    y += b; n -= b;
    while (n > 0) {
        b = (n < r) ? n : r;
        down(c, (u_int8_t *)0, 0, 0x00);
        up(c, y, b, 0x00);
        y += b; n -= b;
    }
}

void
xoodyak_init(xoodyak_t *c, const u_int8_t *key, unsigned keylen)
{
    int i;

    for (i = 0; i < 48; i++)
        c->s[i] = 0;
    c->phase = 0;
    c->mode = 0;
    c->rabsorb = XOODYAK_RHASH;
    c->rsqueeze = XOODYAK_RHASH;

    if (keylen > 0) {
        u_int8_t buf[XOODYAK_RKIN];
        unsigned k;

        c->mode = 1;
        c->rabsorb = XOODYAK_RKIN;
        c->rsqueeze = XOODYAK_RKOUT;
        for (k = 0; k < keylen; k++)
            buf[k] = key[k];
        buf[keylen] = 0x00;             /* empty id -> enc8(0) */
        absorb_any(c, buf, keylen + 1, XOODYAK_RKIN, 0x02);
    }
}

void
xoodyak_absorb(xoodyak_t *c, const u_int8_t *in, unsigned len)
{
    absorb_any(c, in, len, c->rabsorb, 0x03);
}

void
xoodyak_squeeze(xoodyak_t *c, u_int8_t *out, unsigned len)
{
    squeeze_any(c, out, len, 0x40);
}

void
xoodyak_ratchet(xoodyak_t *c)
{
    u_int8_t t[XOODYAK_RRATCHET];

    squeeze_any(c, t, XOODYAK_RRATCHET, 0x10);
    absorb_any(c, t, XOODYAK_RRATCHET, c->rabsorb, 0x00);
}
