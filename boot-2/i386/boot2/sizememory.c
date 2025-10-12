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

/*
 * Memory detection using BIOS INT 0x15 call with multiple fallback methods:
 * 1. E820h - Get full memory map (supports >4GB)
 * 2. E801h - Get extended memory size (supports up to 4GB)
 * 3. INT 88h - Legacy extended memory size (supports up to 64MB)
 *
 * Returns extended memory size in KB (memory above 1MB)
 */
unsigned int
sizememory(
    unsigned int	cnvmem
)
{
    unsigned long	extmem_kb = 0;

    printf("\nSizing memory... ");

    /* If left SHIFT key is held, skip detection and use BIOS value */
    if (readKeyboardShiftFlags() & 0x2) {
    	extmem_kb = memsize(1);
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
    	    printf("%dK", (int)total_kb);
    	    return extmem_kb;
    	}
    }

    /* Method 2: Try E801h (supports up to 4GB) */
    extmem_kb = getExtendedMemoryE801();
    if (extmem_kb > 0) {
    	printf("%dK", (int)(extmem_kb + 1024));
    	return extmem_kb;
    }

    /* Method 3: Fall back to INT 88h (legacy, up to 64MB) */
    extmem_kb = memsize(1);
    printf("%dK", (int)(extmem_kb + 1024));

    return extmem_kb;
}
