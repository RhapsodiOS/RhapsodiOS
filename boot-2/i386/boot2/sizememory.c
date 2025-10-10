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
#import <mach/i386/vm_types.h>
#import "libsaio.h"

#define KB(x)		(1024*(x))
#define MB(x)		(1024*KB(x))
#define GB(x)		(1024*MB(x))

/*
 * Modern memory detection using BIOS INT 0x15 with multiple fallback methods:
 * 1. E820h - Get full memory map (supports >4GB)
 * 2. E801h - Get extended memory size (supports up to 4GB)
 * 3. AH=88h - An old generic method (supports up to 64MB)
 * 4. Manual scanning - Last resort fallback
 *
 * Returns extended memory size in KB (memory above 1MB)
 */
unsigned int
sizememory(
    unsigned int	cnvmem
)
{
    vm_offset_t		end_of_memory;
    unsigned long	extmem_kb = 0;
    int verbose = 0;  /* Set to 1 for debugging output */

#define	SCAN_INCR	KB(64)
#define	SCAN_LEN	8
#define SCAN_LIM	GB(4)

    printf("\nSizing memory... ");

    /* If left SHIFT key is held, skip detection and use BIOS value */
    if (readKeyboardShiftFlags() & 0x2) {
    	if (verbose) printf("[shift key - using BIOS] ");
	end_of_memory = KB(memsize(1)) + MB(1);
	extmem_kb = (end_of_memory - KB(1024)) / 1024;
	printf("%dK", (int)(extmem_kb + 1024));
	return extmem_kb;
    }

    /* Method 1: Try E820h memory map (modern systems, supports >4GB) */
    {
	e820_entry_t memmap[32];
	int numEntries = 0;
	unsigned long total_kb;

	total_kb = getMemoryMap(memmap, 32, &numEntries);

	if (total_kb > 1024) {  /* Got valid result (more than 1MB) */
	    /* Subtract first 1MB to get extended memory only */
	    extmem_kb = total_kb - 1024;
	    if (verbose) printf("[E820: %d entries] ", numEntries);
	    printf("%dK", (int)total_kb);
	    return extmem_kb;
	}
    }

    /* Method 2: Try E801h (supports up to 4GB) */
    extmem_kb = getExtendedMemoryE801();
    if (extmem_kb > 0) {
	if (verbose) printf("[E801] ");
	printf("%dK", (int)(extmem_kb + 1024));
	return extmem_kb;
    }

    /* Method 3: Try old AH=88h method (supports up to 64MB) */
    extmem_kb = memsize(1);  /* Returns extended memory in KB */
    if (extmem_kb > 0) {
	if (verbose) printf("[88h] ");
	printf("%dK", (int)(extmem_kb + 1024));
	return extmem_kb;
    }

    /* Method 4: Manual memory scanning (last resort) */
    if (verbose) printf("[scanning] ");

    /*
     * First scan beginning at start of extended memory using
     * a reasonably large segment size (64KB).
     */
    end_of_memory = scan_memory(
				KB(1024),
				KB(cnvmem),
				SCAN_INCR,
				SCAN_LEN,
				SCAN_LIM);

    /*
     * Now scan the top segment a page at a time (4KB)
     * to find the actual end of extended memory.
     */
    if (end_of_memory > KB(1024))
	end_of_memory = scan_memory(
				    end_of_memory - SCAN_INCR,
				    KB(cnvmem),
				    KB(4),
				    SCAN_LEN,
				    end_of_memory);

    /* Convert to KB and subtract first 1MB to get extended memory only */
    extmem_kb = (end_of_memory - KB(1024)) / 1024;
    printf("%dK", (int)(extmem_kb + 1024));

    return extmem_kb;
}
