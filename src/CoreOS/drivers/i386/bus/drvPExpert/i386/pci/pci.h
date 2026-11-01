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
 * pci.h
 * PCI Helper Functions
 */

#ifndef _PCI_H_
#define _PCI_H_

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Helper function to check if string starts with a prefix followed by '('
 * Returns pointer after the prefix if match, NULL otherwise
 * Example: PCIParsePrefix("PCI", "PCI(something)") returns pointer to "(something)"
 */
char *PCIParsePrefix(char *prefix, char *str);

/*
 * Helper function to parse PCI location strings
 * Format: Supports keywords like "DEV:1 FUNC:0 BUS:0 REG:10"
 * Returns 1 if parsing successful, 0 otherwise
 */
unsigned int PCIParseKeys(char *locationStr,
                         unsigned long *device,
                         unsigned int *function,
                         unsigned int *bus,
                         unsigned int *reg);

#ifdef __cplusplus
}
#endif

#endif /* _PCI_H_ */
