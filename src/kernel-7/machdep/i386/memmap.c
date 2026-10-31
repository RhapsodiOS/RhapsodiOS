/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

#include <machdep/i386/memmap.h>

#define EXT_BASE	0x100000	/* extended memory starts at 1MB */

/*
 * Top of the contiguous run of usable RAM starting at 1MB.  Entries are not
 * guaranteed sorted, so repeat until stable.  A non-RAM range starting inside
 * the run cuts it there, even where the BIOS also reported that space as RAM;
 * one straddling 1MB leaves no run.  Returns EXT_BASE when no RAM adjoins 1MB.
 */
unsigned int
memmap_contiguous_top(const boot_mem_range_t *map, int n)
{
    unsigned int	top = EXT_BASE;
    int			changed = 1;
    int			i;

    while (changed) {
	changed = 0;
	for (i = 0; i < n; i++) {
	    if (map[i].type != BOOT_MEM_RAM)
		continue;
	    if (map[i].base <= top && map[i].end > top) {
		top = map[i].end;
		changed = 1;
	    }
	}
    }

    for (i = 0; i < n; i++) {
	if (map[i].type == BOOT_MEM_RAM)
	    continue;
	if (map[i].base < EXT_BASE && map[i].end > EXT_BASE)
	    return (EXT_BASE);
	if (map[i].base >= EXT_BASE && map[i].base < top)
	    top = map[i].base;
    }

    return (top);
}

/*
 * The count is written by code the kernel does not control, so bound it.
 */
int
memmap_count(int raw)
{
    if (raw < 0)
	return (0);
    if (raw > BOOT_MEMMAP_MAX)
	return (BOOT_MEMMAP_MAX);
    return (raw);
}

/*
 * A usable map bounds memory; maxmem may only lower it.  Without one,
 * maxmem or the BIOS extended memory size decides.
 */
unsigned int
memmap_end_of_memory(
    unsigned int	map_top,
    unsigned int	maxmem_bytes,
    unsigned int	extmem_bytes
)
{
    if (map_top > EXT_BASE) {
	if (maxmem_bytes && maxmem_bytes < map_top)
	    return (maxmem_bytes);
	return (map_top);
    }
    if (maxmem_bytes)
	return (maxmem_bytes);
    return (extmem_bytes);
}

/*
 * Kernel virtual address that pmap_bootstrap() reserves above the V == P
 * map of physical memory.  This must track:
 *
 *	machdep/i386/pmap.c		pmap_bootstrap()'s 64MB base size
 *	kern/zalloc.c			zone_map_sizer()
 *	machdep/i386/unix_startup.c	buffer_map_sizer()
 *
 * The real sizers cannot be called this early: buffer_map_sizer() memoizes
 * bufpages, nbuf and niobuf, which startup_early() consumes later.
 */
#define EST_KMEM_BASE	(64 * 1024 * 1024)
#define EST_ZONE_MIN	(12 * 1024 * 1024)	/* zone_map_size_min */
#define EST_ZONE_MAX	(128 * 1024 * 1024)	/* zone_map_size_max */
#define EST_MAXBSIZE	8192			/* bsd/sys/param.h MAXBSIZE */
#define EST_MAXPHYS	(64 * 1024)		/* bsd/i386/param.h MAXPHYS */
#define CLAMP_STEP	(16 * 1024 * 1024)

static unsigned int
kmem_va_estimate(unsigned int mem, unsigned int page_size)
{
    unsigned int	zone, bufpages, nbuf, niobuf;

    zone = mem / 8;
    if (zone < EST_ZONE_MIN)
	zone = EST_ZONE_MIN;
    else if (zone > EST_ZONE_MAX)
	zone = EST_ZONE_MAX;

    bufpages = (mem / 50) / page_size;
    nbuf = (bufpages < 16 ? 16 : bufpages) + 64;

    niobuf = bufpages / (EST_MAXPHYS / page_size);
    if (niobuf > 1024)
	niobuf = 1024;
    if (niobuf < 32)
	niobuf = 32;

    return (EST_KMEM_BASE + zone + nbuf * EST_MAXBSIZE + niobuf * EST_MAXPHYS);
}

/*
 * Subtract on the budget side so the sum can never wrap.
 */
static int
kmem_va_fits(unsigned int mem, unsigned int budget, unsigned int page_size)
{
    return (mem <= budget &&
	    kmem_va_estimate(mem, page_size) <= budget - mem);
}

/*
 * The most physical memory that, with the kernel reserve above it, fits a
 * kernel window of "budget" bytes.  Memory that fits is returned unchanged;
 * otherwise the result is rounded down to a 16MB step first, so it depends
 * only on the budget and not on how much memory was detected.  Returns 0 if
 * nothing fits.
 */
unsigned int
memmap_clamp(unsigned int end, unsigned int budget, unsigned int page_size)
{
    if (kmem_va_fits(end, budget, page_size))
	return (end);

    end &= ~(CLAMP_STEP - 1);
    while (!kmem_va_fits(end, budget, page_size)) {
	if (end < CLAMP_STEP)
	    return (0);
	end -= CLAMP_STEP;
    }
    return (end);
}
