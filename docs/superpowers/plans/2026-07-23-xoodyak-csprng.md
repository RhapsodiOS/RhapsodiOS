# Xoodyak CSPRNG Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the dead, incompatible Yarrow `/dev/random` code with a single live Xoodyak-based CSPRNG that backs `/dev/random`, `/dev/urandom`, the kernel `read_random()`/`RandomULong()` exports, and libkern `random()`.

**Architecture:** A pure, endian-neutral Xoodoo[12] + Xoodyak Cyclist primitive (`xoodyak.c`) is driven by a rewritten `randomdev.c` that owns one global CSPRNG instance behind a `simple_lock`, seeded from `microtime()`. The character device is wired via the static `cdevsw[]` tables (major 17) on both i386 and ppc, nodes are created by MAKEDEV, and libkern `random()` delegates to `RandomULong()`. The old `YarrowCoreLib/` tree is deleted.

**Tech Stack:** C89, NeXT/Rhapsody BSD kernel (Darwin 0.3), static device switch tables, `simple_lock`, `microtime`, `uiomove`.

## Global Constraints

- **C89 only** (the `rbuild-c89` branch). No `//` comments, declarations at block top, no C99 features. Verify each new file compiles with `cc -std=c89 -Wall -Wextra` on the host.
- **Two architectures:** i386 (little-endian) and ppc (**big-endian**). The crypto primitive MUST be endian-neutral — pack/unpack the 32-bit lanes with explicit byte shifts, never by casting a byte pointer to `u_int32_t *`.
- **No third-party code.** The Xoodyak primitive is clean-room from the public Xoodoo/Xoodyak specification. Do not copy any licensed reference implementation into the tree.
- **Commit messages MUST reference GitHub issue #11** (append `(#11)` to the subject line). Subsystem prefix per repo convention (e.g. `random: ...`). Short, human-readable, no metadata.
- **Preserve existing Apple `@APPLE_LICENSE_HEADER@` blocks** on files you modify (randomdev.c/.h, libkern/random.c, conf.c, init_main.c).
- **Device major number: 17** (free in both `cdevsw[]` tables and unused by MAKEDEV). Minor 0 = `random`, minor 1 = `urandom` (identical behavior).

### Pinned known-answer vectors (verified against the Xoodyak reference)

These were generated from the Apache-2.0 `xoocycle` reference used strictly as a host-side oracle (not shipped). The clean-room primitive reproduces all of them byte-for-byte. **These values are the source of truth — if a test fails, fix the implementation, never the vector.**

| Test | Operation | Expected hex |
|------|-----------|--------------|
| hash(empty) | `init(NULL,0)` → `squeeze(32)` | `8dd8d589bffc63a9192d231b14a0a5ffccf629d657274c72278283347cbd8035` |
| hash("abc") | `init(NULL,0)` → `absorb("abc")` → `squeeze(32)` | `661f71b331a0c1214441c4b4a811697e9109bc0b3c4e1e647c4d1127b18e2a1e` |
| keyed K1 | `init(key16)` → `squeeze(32)` | `b0bbb12f061ea97fed79938fabf9cd9a55dbcd5dba12bdbab24499b622aa0d7e` |
| keyed K2 | `init(key16)` → `absorb(8×0xaa)` → `squeeze(32)` | `57e1468a6ec583ad7ad0bb998219e81ddb0e63ca26d8e242579d48695f7fc8a8` |
| keyed K3 | `init(key16)` → `squeeze(16)` → `ratchet` → `squeeze(16)` | `83ed4ed7aa202949090ef7293421afba` |
| seedvec | `init(seed8)` → `squeeze(16)`, seed = LE(0x11223344)‖LE(0x55667788) | `85fa03e325ccbfbab48a5785ee3292c6` |

`key16` = bytes `00 01 02 ... 0f`.

---

### Task 1: Xoodyak crypto primitive + host KAT harness

**Files:**
- Create: `src/kernel-7/bsd/dev/random/xoodyak.h`
- Create: `src/kernel-7/bsd/dev/random/xoodyak.c`
- Create: `src/kernel-7/bsd/dev/random/xoodyak_kat.c` (standalone host test; never added to `conf/files`)

**Interfaces:**
- Produces:
  - `typedef struct { u_int8_t s[48]; int mode; int phase; unsigned rabsorb; unsigned rsqueeze; } xoodyak_t;`
  - `void xoodyak_init(xoodyak_t *c, const u_int8_t *key, unsigned keylen);` — `keylen==0` → hash mode; `keylen>0` (≤43) → keyed mode with empty id/counter.
  - `void xoodyak_absorb(xoodyak_t *c, const u_int8_t *in, unsigned len);`
  - `void xoodyak_squeeze(xoodyak_t *c, u_int8_t *out, unsigned len);`
  - `void xoodyak_ratchet(xoodyak_t *c);`

- [ ] **Step 1: Write the header**

Create `src/kernel-7/bsd/dev/random/xoodyak.h`:

```c
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
```

- [ ] **Step 2: Write the failing KAT harness**

Create `src/kernel-7/bsd/dev/random/xoodyak_kat.c`. This is a host-only program (not part of the kernel build) that pins the vectors from the Global Constraints table:

```c
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

    return fail;
}
```

- [ ] **Step 3: Run the harness to verify it fails (no implementation yet)**

```bash
cd src/kernel-7/bsd/dev/random
mkdir -p /tmp/xdkinc/dev/random && cp xoodyak.h /tmp/xdkinc/dev/random/
cc -std=c89 -Wall -Wextra -I/tmp/xdkinc -o /tmp/xoodyak_kat xoodyak_kat.c xoodyak.c
```
Expected: **link/compile error** — `xoodyak.c` does not exist yet (or undefined symbols).

- [ ] **Step 4: Write the implementation**

Create `src/kernel-7/bsd/dev/random/xoodyak.c`:

```c
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
```

- [ ] **Step 5: Run the harness to verify it passes**

```bash
cd src/kernel-7/bsd/dev/random
cp xoodyak.h /tmp/xdkinc/dev/random/
cc -std=c89 -Wall -Wextra -I/tmp/xdkinc -o /tmp/xoodyak_kat xoodyak_kat.c xoodyak.c
/tmp/xoodyak_kat; echo "exit=$?"
```
Expected: six `PASS` lines and `exit=0`. No compiler warnings.

If any vector FAILS: the bug is in `xoodyak.c` (permutation offsets, domain constants, or block loop). Debug against the spec; do not edit the expected hex.

- [ ] **Step 6: Commit**

```bash
git add src/kernel-7/bsd/dev/random/xoodyak.h src/kernel-7/bsd/dev/random/xoodyak.c src/kernel-7/bsd/dev/random/xoodyak_kat.c
git commit -m "random: add clean-room Xoodyak CSPRNG primitive with KAT (#11)"
```

---

### Task 2: CSPRNG driver rewrite (randomdev.c / randomdev.h)

**Files:**
- Modify: `src/kernel-7/bsd/dev/random/randomdev.h` (add `random_init` prototype)
- Modify: `src/kernel-7/bsd/dev/random/randomdev.c` (full rewrite of the body)

**Interfaces:**
- Consumes (from Task 1): `xoodyak_t`, `xoodyak_init`, `xoodyak_absorb`, `xoodyak_squeeze`, `xoodyak_ratchet`.
- Produces:
  - `void random_init(void);` — one-time seed + lock init.
  - `int random_open/close/read/write(...)` — cdevsw entry points (signatures unchanged from existing header).
  - `u_long RandomULong(void);`
  - `void read_random(void *buffer, u_int numBytes);`

This task cannot be unit-tested in isolation (kernel-only APIs: `uio`, `simple_lock`, `microtime`, `uiomove`). Its build gate is Task 6; its logic gate is the `seedvec` KAT already proven in Task 1 (the driver seeds and squeezes exactly as `seedvec` does) plus the review checklist in Step 3.

- [ ] **Step 1: Update the header**

In `src/kernel-7/bsd/dev/random/randomdev.h`, add the `random_init` prototype after the existing device prototypes (keep the Apple license header intact):

```c
int random_open(dev_t dev, int flags, int devtype, struct proc *pp);
int random_close(dev_t dev, int flags, int mode, struct proc *pp);
int random_read(dev_t dev, struct uio *uio, int ioflag);
int random_write(dev_t dev, struct uio *uio, int ioflag);

void random_init(void);
u_long RandomULong();
void read_random(void* buffer, u_int numBytes);
```

- [ ] **Step 2: Rewrite the driver body**

Replace the entire body of `src/kernel-7/bsd/dev/random/randomdev.c` below the Apple license header with the following (keep the existing `@APPLE_LICENSE_HEADER@` block at the top):

```c
#include <sys/param.h>
#include <sys/systm.h>
#include <sys/proc.h>
#include <sys/errno.h>
#include <sys/fcntl.h>
#include <sys/uio.h>
#include <sys/time.h>
#include <kern/parallel.h>

#include <dev/random/randomdev.h>
#include <dev/random/xoodyak.h>

/*
 * A single global Xoodyak CSPRNG instance, shared by /dev/random,
 * /dev/urandom, read_random(), RandomULong(), and libkern random().
 * All access is serialized by a simple lock (cf. bsd/kern/subr_log.c).
 * Entropy model: a microtime() seed at init, reseeded by device writes.
 * See docs/kernel/CSPRNG.md for the construction and future hooks.
 */

static int       gRandomReady = 0;
static xoodyak_t gCsprng;
decl_simple_lock_data(, gRandomLock);

#define CSPRNG_LOCK()   simple_lock(&gRandomLock)
#define CSPRNG_UNLOCK() simple_unlock(&gRandomLock)

/*
 * Seed the generator from the system clock.  This is weak boot entropy
 * (see CSPRNG.md); the security server reseeds via writes to /dev/random.
 */
static void
csprng_seed(void)
{
    struct timeval tt;
    u_int8_t seed[8];
    int i;

    microtime(&tt);
    for (i = 0; i < 4; i++)
        seed[i] = (u_int8_t)(tt.tv_sec >> (8 * i));
    for (i = 0; i < 4; i++)
        seed[4 + i] = (u_int8_t)(tt.tv_usec >> (8 * i));
    xoodyak_init(&gCsprng, seed, sizeof (seed));
}

void
random_init(void)
{
    if (gRandomReady)
        return;
    simple_lock_init(&gRandomLock);
    csprng_seed();
    gRandomReady = 1;
}

int
random_open(dev_t dev, int flags, int devtype, struct proc *p)
{
    /*
     * If opened for write, require privilege to reseed the generator.
     */
    if (flags & FWRITE) {
        if (securelevel >= 2)
            return (EPERM);
        if ((securelevel >= 1) && suser(p->p_ucred, &p->p_acflag))
            return (EPERM);
    }
    return (0);
}

int
random_close(dev_t dev, int flags, int mode, struct proc *p)
{
    return (0);
}

/*
 * Reseed the generator with entropy supplied by the caller.
 */
int
random_write(dev_t dev, struct uio *uio, int ioflag)
{
    int retCode = 0;
    u_int8_t buf[256];

    if (!gRandomReady)
        random_init();

    CSPRNG_LOCK();
    while (uio->uio_resid > 0) {
        int n = min(uio->uio_resid, sizeof (buf));
        retCode = uiomove((caddr_t)buf, n, uio);
        if (retCode != 0)
            break;
        xoodyak_absorb(&gCsprng, buf, n);
    }
    CSPRNG_UNLOCK();
    return (retCode);
}

/*
 * Return pseudorandom bytes to the caller.
 */
int
random_read(dev_t dev, struct uio *uio, int ioflag)
{
    int retCode = 0;
    u_int8_t buf[512];

    if (!gRandomReady)
        random_init();

    CSPRNG_LOCK();
    while (uio->uio_resid > 0) {
        int n = min(uio->uio_resid, sizeof (buf));
        xoodyak_squeeze(&gCsprng, buf, n);
        retCode = uiomove((caddr_t)buf, n, uio);
        if (retCode != 0)
            break;
    }
    xoodyak_ratchet(&gCsprng);
    CSPRNG_UNLOCK();
    return (retCode);
}

/*
 * Export good random numbers to the rest of the kernel.
 */
void
read_random(void *buffer, u_int numbytes)
{
    if (!gRandomReady)
        random_init();

    CSPRNG_LOCK();
    xoodyak_squeeze(&gCsprng, (u_int8_t *)buffer, numbytes);
    xoodyak_ratchet(&gCsprng);
    CSPRNG_UNLOCK();
}

/*
 * Return an unsigned long pseudo-random number.
 */
u_long
RandomULong()
{
    u_long buf;
    read_random(&buf, sizeof (buf));
    return (buf);
}
```

- [ ] **Step 3: Review checklist (self-verify before commit)**

Confirm each:
- [ ] The `@APPLE_LICENSE_HEADER@` block is still at the top of both files.
- [ ] No reference to `yarrow.h`, `prng*`, `PrngRef`, `gYarrowMutex`, `devfs_make_node`, `cdevsw_add`, or `random_cdevsw` remains: `grep -nE 'yarrow|prng|Yarrow|devfs_make_node|cdevsw_add' src/kernel-7/bsd/dev/random/randomdev.c` prints nothing.
- [ ] Every `xoodyak_squeeze`/`xoodyak_absorb`/`xoodyak_ratchet` call is inside a `CSPRNG_LOCK()/CSPRNG_UNLOCK()` region.
- [ ] `min` and `uiomove` are the forms already used elsewhere in this kernel (they are: `sys/param.h` and the `uiomove(caddr_t, int, struct uio *)` prototype).

- [ ] **Step 4: Commit**

```bash
git add src/kernel-7/bsd/dev/random/randomdev.c src/kernel-7/bsd/dev/random/randomdev.h
git commit -m "random: rewrite /dev/random driver on Xoodyak CSPRNG (#11)"
```

---

### Task 3: Kernel build integration + delete Yarrow

Wires the new sources into the build, registers the device on both architectures, routes libkern `random()`, seeds at boot, and removes the dead Yarrow tree. These changes are interdependent (the kernel only links once all references resolve), so they land together and are gated by a full compile.

**Files:**
- Modify: `src/kernel-7/conf/files`
- Modify: `src/kernel-7/bsd/dev/i386/conf.c`
- Modify: `src/kernel-7/bsd/dev/ppc/conf.c`
- Modify: `src/kernel-7/bsd/libkern/random.c`
- Modify: `src/kernel-7/bsd/kern/init_main.c`
- Delete: `src/kernel-7/bsd/dev/random/YarrowCoreLib/` (entire directory)

**Interfaces:**
- Consumes (from Task 2): `random_open/close/read/write`, `random_init`, `RandomULong`.

- [ ] **Step 1: Add the new sources to `conf/files`**

In `src/kernel-7/conf/files`, immediately after the line `bsd/libkern/random.c			standard` add:

```
bsd/dev/random/randomdev.c		standard
bsd/dev/random/xoodyak.c		standard
```

(`xoodyak_kat.c` is deliberately NOT listed — it is a host-only test.)

- [ ] **Step 2: Register the device in the i386 cdevsw table**

In `src/kernel-7/bsd/dev/i386/conf.c`, add the include after `#import <sys/conf.h>` (line ~44):

```c
#import <dev/random/randomdev.h>
```

Then replace the line `    NO_CDEVICE,								/*17*/` with:

```c
    {
	random_open,	random_close,	random_read,	random_write,	/*17*/
	eno_ioctl,	nulldev,	nulldev,	0,		eno_select,
	eno_mmap,	eno_strat,	eno_getc,	eno_putc,	0
    },
```

- [ ] **Step 3: Register the device in the ppc cdevsw table**

In `src/kernel-7/bsd/dev/ppc/conf.c`, add the include after `#include <sys/conf.h>` (line ~38):

```c
#include <dev/random/randomdev.h>
```

Then replace that file's `    NO_CDEVICE,								/*17*/` line with the identical entry:

```c
    {
	random_open,	random_close,	random_read,	random_write,	/*17*/
	eno_ioctl,	nulldev,	nulldev,	0,		eno_select,
	eno_mmap,	eno_strat,	eno_getc,	eno_putc,	0
    },
```

- [ ] **Step 4: Route libkern `random()` through the CSPRNG**

Replace the body of `src/kernel-7/bsd/libkern/random.c` below the license/Berkeley headers with the following (keep both existing copyright headers; delete the `Modification History` comment block, the `#include <sys/time.h>`, and the old Park–Miller function):

```c
#include <libkern/libkern.h>
#include <dev/random/randomdev.h>

/*
 * Pseudo-random number generator, now backed by the kernel CSPRNG
 * (Xoodyak) via RandomULong().  Result is uniform on [0, 2^31 - 1].
 */
u_long
random()
{
	return (RandomULong() & 0x7fffffff);
}
```

- [ ] **Step 5: Seed the CSPRNG at boot**

In `src/kernel-7/bsd/kern/init_main.c`, add the include near the other `#import <sys/...>` lines (after line ~179 `#import <sys/conf.h>`):

```c
#import <dev/random/randomdev.h>
```

Then, in `bsd_init`, immediately after the `log_init();` call (the `/* Initialize syslog */` block, ~line 481), add:

```c
	/* Initialize the kernel CSPRNG (/dev/random) */
	random_init();
```

- [ ] **Step 6: Delete the Yarrow tree**

```bash
git rm -r src/kernel-7/bsd/dev/random/YarrowCoreLib
```

- [ ] **Step 7: Verify no dangling Yarrow references remain**

```bash
grep -rniE 'yarrow|YarrowCoreLib' src/kernel-7/ ; echo "exit=$?"
```
Expected: no matches (`exit=1` from grep). If anything prints, it is a leftover include or conf reference — remove it.

- [ ] **Step 8: Build the kernel for both architectures**

Build using the repo's normal kernel build (per `rbuild`/README). Expected: i386 and ppc kernels compile and link with no errors; no unresolved `random_open`, `RandomULong`, `read_random`, or `xoodyak_*` symbols, and no remaining `prng*`/Yarrow symbols.

If the exact build invocation is unknown, confirm at minimum that the two new files compile in isolation for each arch's cc and that `conf.c`/`random.c`/`init_main.c` still parse.

- [ ] **Step 9: Commit**

```bash
git add src/kernel-7/conf/files src/kernel-7/bsd/dev/i386/conf.c src/kernel-7/bsd/dev/ppc/conf.c src/kernel-7/bsd/libkern/random.c src/kernel-7/bsd/kern/init_main.c
git commit -m "random: wire Xoodyak /dev/random into kernel, drop Yarrow (#11)"
```

---

### Task 4: Create device nodes in MAKEDEV

**Files:**
- Modify: `src/kernel-7/src/MAKEDEV/MAKEDEV.csh`

- [ ] **Step 1: Add the nodes to the `std)` stanza**

In `src/kernel-7/src/MAKEDEV/MAKEDEV.csh`, inside the `std)` case block (after the `mknod sound c 36 0` line, before the `;;`), add:

```sh
	mknod random	c 17 0	; chmod 644 random
	mknod urandom	c 17 1	; chmod 644 urandom
```

(The `rhapsody` bundle already invokes `$0 std ...`, so no change to that line is needed.)

- [ ] **Step 2: Verify the script still parses**

```bash
sh -n src/kernel-7/src/MAKEDEV/MAKEDEV.csh; echo "exit=$?"
```
Expected: `exit=0` (no syntax errors). Also confirm the new lines are present under `std)`:
```bash
grep -nE 'mknod (u)?random' src/kernel-7/src/MAKEDEV/MAKEDEV.csh
```
Expected: the two new lines print.

- [ ] **Step 3: Commit**

```bash
git add src/kernel-7/src/MAKEDEV/MAKEDEV.csh
git commit -m "MAKEDEV: create /dev/random and /dev/urandom nodes (#11)"
```

---

### Task 5: Documentation — docs/kernel/CSPRNG.md

**Files:**
- Create: `docs/kernel/CSPRNG.md`

- [ ] **Step 1: Write the document**

Create `docs/kernel/CSPRNG.md`:

```markdown
# Kernel CSPRNG (Xoodyak)

The kernel's random number generator is a single Xoodyak-based CSPRNG that
backs `/dev/random`, `/dev/urandom`, the in-kernel `read_random()` /
`RandomULong()` exports, and libkern `random()`.

## Construction

- **Primitive:** Xoodoo[12] permutation (384-bit state) with the Xoodyak
  Cyclist mode in keyed operation. Implemented clean-room from the public
  specification in `bsd/dev/random/xoodyak.c`; the state is stored as 48
  little-endian bytes and lanes are packed with explicit shifts, so the
  code is correct on both i386 (LE) and ppc (BE).
- **Instance:** one global `xoodyak_t` in `bsd/dev/random/randomdev.c`,
  serialized by a `simple_lock`.
- **Output:** `xoodyak_squeeze`. After serving a request the state is
  advanced with `xoodyak_ratchet` for forward secrecy.
- **Reseed:** `xoodyak_absorb` of caller-supplied bytes (device writes).

## Consumers

| Consumer | Path |
|----------|------|
| `/dev/random`, `/dev/urandom` (major 17, minors 0/1) | `random_read` = squeeze, `random_write` = reseed |
| `read_random()` / `RandomULong()` | squeeze |
| libkern `random()` | `RandomULong() & 0x7fffffff` |

## Entropy model (current: "A")

Seeded once at boot from `microtime()` (`csprng_seed`), reseeded by writes
to `/dev/random` (the historical "security server sends entropy" path).
This is weak boot entropy: on 1999-era ppc/i386 there is no hardware RNG,
so early output is only as unpredictable as the boot-time clock. Writes
after boot strengthen the state.

### Seed size refinement (16 → 8 bytes)

The approved design called for a 16-byte `microtime()` seed. This was
refined to **8 bytes**: `struct timeval` on the 32-bit ppc/i386 targets is
two 32-bit longs (`tv_sec` + `tv_usec`), i.e. 8 bytes, so a single
`microtime()` yields 8 bytes — matching what the original Yarrow code
sampled. `csprng_seed()` packs those two longs little-endian into an
8-byte buffer and keys the generator with it.

## Wiring

- Static `cdevsw[]` entry at major 17 in `bsd/dev/i386/conf.c` and
  `bsd/dev/ppc/conf.c` (kept identical).
- Device nodes created by `src/MAKEDEV/MAKEDEV.csh` (`std` stanza).
- `random_init()` is called from `bsd_init()` in `bsd/kern/init_main.c`
  after `log_init()`; device paths also lazy-init on first use.

## Testing

`bsd/dev/random/xoodyak_kat.c` is a standalone host known-answer test (not
part of the kernel build). Build and run:

    cd bsd/dev/random
    mkdir -p /tmp/xdkinc/dev/random && cp xoodyak.h /tmp/xdkinc/dev/random/
    cc -std=c89 -Wall -Wextra -I/tmp/xdkinc -o /tmp/xoodyak_kat xoodyak_kat.c xoodyak.c
    /tmp/xoodyak_kat

All vectors must print `PASS`.

## Future hooks (not yet implemented)

- **Entropy model B — opportunistic harvesting:** fold cheap timing jitter
  (interrupt timestamps, `microtime` low bits) into the state via
  `xoodyak_absorb` on paths already taken (device reads, `random()`,
  a hook in the timer/interrupt code).
- **Entropy model C — boot-time pool:** gather several early-boot timing
  samples before declaring the generator ready.
- **Per-open reseed**, an **ioctl** to report/estimate entropy, and
  optional **blocking `/dev/random`** semantics distinct from `/dev/urandom`.
```

- [ ] **Step 2: Commit**

```bash
git add docs/kernel/CSPRNG.md
git commit -m "docs: document kernel Xoodyak CSPRNG and future hooks (#11)"
```

---

### Task 6: Runtime verification (temporary disk image)

Per `CLAUDE.md` §6, verify on a bootable Rhapsody DR2 / Mac OS X Server guest using a **temporary disk image** so concurrent debugging sessions stay isolated. This task is manual/interactive and has no commit.

- [ ] **Step 1: Boot the new kernel and confirm the nodes exist**

```bash
ls -l /dev/random /dev/urandom
```
Expected: two character-special files, major 17, minors 0 and 1, mode 0644.

- [ ] **Step 2: Read produces non-blocking, varying output**

```bash
head -c 32 /dev/urandom | hexdump -C
head -c 32 /dev/random  | hexdump -C
dd if=/dev/urandom bs=16 count=1 2>/dev/null | hexdump -C
```
Expected: each command returns immediately (non-blocking); two successive reads differ; output is not all-zero / not constant.

- [ ] **Step 3: Write (reseed) succeeds for a privileged user**

```bash
echo "some entropy" > /dev/random ; echo "write exit=$?"
```
Expected: `write exit=0` (as root / securelevel 0).

- [ ] **Step 4: Record the result**

Note pass/fail for each check. If a read returns `ENOTSUP` or blocks, or the node is missing, re-check Tasks 3–4 (cdevsw major, conf/files, MAKEDEV major) before proceeding.
```
