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
#import "kernBootStruct.h"
#import "memory.h"

/*
 * Memory detection using BIOS INT 0x15 with multiple fallback methods:
 * 1. E820h - full memory map; also handed to the kernel in kernBootStruct
 * 2. E801h - extended memory size (up to 4GB)
 * 3. INT 88h - legacy extended memory size (up to 64MB)
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
    } else {
    	unsigned long top;

    	/* Method 1: E820h memory map, which also hands the kernel the map */
    	top = getMemoryMap(kernBootStruct->memMap, BOOT_MEMMAP_MAX,
    			   &kernBootStruct->memMapCount);

    	if (top > EXTENDED_ADDR)
    	    extmem_kb = (top - EXTENDED_ADDR) / 1024;
    	/* Method 2: Try E801h (supports up to 4GB) */
    	else if ((extmem_kb = getExtendedMemoryE801()) == 0)
    	    /* Method 3: Fall back to INT 88h (legacy, up to 64MB) */
    	    extmem_kb = memsize(1);
    }

    printf("%dK", (int)(extmem_kb + 1024));

    return extmem_kb;
}
