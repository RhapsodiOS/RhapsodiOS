/*
 * Standalone host-side known-answer test for the Xoodyak primitive.
 * NOT part of the kernel build (absent from conf/files).
 * Build: cc -std=c89 -Wall -Wextra -I<hdrdir> -o xoodyak_kat xoodyak_kat.c xoodyak.c
 * where <hdrdir> contains dev/random/xoodyak.h.
 */
#include <stdio.h>
#include <string.h>
#include <dev/random/xoodyak.h>

static int fail = 0;

static void
check(const char *name, const u_int8_t *got, unsigned n, const char *hex)
{
    char h[129];
    unsigned i;
    for (i = 0; i < n; i++)
        sprintf(h + 2 * i, "%02x", got[i]);
    if (strcmp(h, hex) == 0) {
        printf("PASS %s\n", name);
    } else {
        printf("FAIL %s\n  got %s\n  exp %s\n", name, h, hex);
        fail = 1;
    }
}

int
main(void)
{
    xoodyak_t c;
    u_int8_t out[32], key[16], seed8[8];
    int i;

    for (i = 0; i < 16; i++) key[i] = (u_int8_t)i;
    for (i = 0; i < 8; i++)  seed8[i] = 0xaa;

    xoodyak_init(&c, (u_int8_t *)0, 0);
    xoodyak_squeeze(&c, out, 32);
    check("hash(empty)", out, 32,
        "8dd8d589bffc63a9192d231b14a0a5ffccf629d657274c72278283347cbd8035");

    xoodyak_init(&c, (u_int8_t *)0, 0);
    xoodyak_absorb(&c, (const u_int8_t *)"abc", 3);
    xoodyak_squeeze(&c, out, 32);
    check("hash(abc)", out, 32,
        "661f71b331a0c1214441c4b4a811697e9109bc0b3c4e1e647c4d1127b18e2a1e");

    xoodyak_init(&c, key, 16);
    xoodyak_squeeze(&c, out, 32);
    check("keyed K1", out, 32,
        "b0bbb12f061ea97fed79938fabf9cd9a55dbcd5dba12bdbab24499b622aa0d7e");

    xoodyak_init(&c, key, 16);
    xoodyak_absorb(&c, seed8, 8);
    xoodyak_squeeze(&c, out, 32);
    check("keyed K2 (reseed)", out, 32,
        "57e1468a6ec583ad7ad0bb998219e81ddb0e63ca26d8e242579d48695f7fc8a8");

    xoodyak_init(&c, key, 16);
    xoodyak_squeeze(&c, out, 16);
    xoodyak_ratchet(&c);
    xoodyak_squeeze(&c, out, 16);
    check("keyed K3 (ratchet)", out, 16,
        "83ed4ed7aa202949090ef7293421afba");

    {
        u_int8_t seed[8];
        unsigned long sec = 0x11223344UL, usec = 0x55667788UL;
        for (i = 0; i < 4; i++) seed[i] = (u_int8_t)(sec >> (8 * i));
        for (i = 0; i < 4; i++) seed[4 + i] = (u_int8_t)(usec >> (8 * i));
        xoodyak_init(&c, seed, 8);
        xoodyak_squeeze(&c, out, 16);
        check("seedvec", out, 16, "85fa03e325ccbfbab48a5785ee3292c6");
    }

    {
        u_int8_t key2[16], msg[50];

        for (i = 0; i < 16; i++) key2[i] = (u_int8_t)i;
        for (i = 0; i < 50; i++) msg[i] = (u_int8_t)i;
        xoodyak_init(&c, key2, 16);
        xoodyak_absorb(&c, msg, 50);
        xoodyak_squeeze(&c, out, 32);
        check("absorb 2-block", out, 32,
            "cc14a5fd760c59271d54060afa7c4075d19d6684a533e1d222df4e4901d479ad");
    }

    return fail;
}
