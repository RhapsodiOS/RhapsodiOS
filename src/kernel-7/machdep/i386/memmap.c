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
 * guaranteed sorted, so repeat until stable.  Returns EXT_BASE when no RAM
 * adjoins 1MB.
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
