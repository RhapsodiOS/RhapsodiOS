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

/*
 * Sizing physical memory from the memory map the booter left in
 * kernBootStruct.
 */

#ifndef _MACHDEP_I386_MEMMAP_H_
#define _MACHDEP_I386_MEMMAP_H_

#include <machdep/i386/kernBootStruct.h>

unsigned int memmap_contiguous_top(const boot_mem_range_t *map, int n);
int memmap_count(int raw);
unsigned int memmap_end_of_memory(unsigned int map_top,
				  unsigned int maxmem_bytes,
				  unsigned int extmem_bytes);

#endif	/* _MACHDEP_I386_MEMMAP_H_ */
