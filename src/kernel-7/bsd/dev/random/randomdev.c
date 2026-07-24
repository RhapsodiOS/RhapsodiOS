/*
 * Copyright (c) 1999, 2000-2001 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * The contents of this file constitute Original Code as defined in and
 * are subject to the Apple Public Source License Version 1.1 (the
 * "License").  You may not use this file except in compliance with the
 * License.  Please obtain a copy of the License at
 * http://www.apple.com/publicsource and read it before using this file.
 * 
 * This Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */

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

