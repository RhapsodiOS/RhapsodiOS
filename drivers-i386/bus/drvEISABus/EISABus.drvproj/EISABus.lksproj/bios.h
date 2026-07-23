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
 * bios.h
 * BIOS Call Utilities
 */

#ifndef _BIOS_H_
#define _BIOS_H_

/*
 * Global variables for BIOS operations
 */
extern unsigned short readPort;                  /* PnP read port */
extern char verbose;                             /* Verbose logging flag */

/*
 * Clear all PnP configuration registers
 * Writes zero to all PnP config registers via ports 0x279/0xa79
 */
void clearPnPConfigRegisters(void);

/*
 * PnP BIOS call wrapper (matches Linux kernel)
 *
 * Arguments are packed into registers:
 * EAX = func | (arg1 << 16)
 * EBX = arg2 | (arg3 << 16)
 * ECX = arg4 | (arg5 << 16)
 * EDX = arg6 | (arg7 << 16)
 *
 * We call pnp_bios_callfunc which:
 * - Pushes the packed registers onto stack (as 4 dwords = 8 words for BIOS)
 * - Calls BIOS via lcallw
 * - Returns via lret back to us
 */
extern int call_pnp_bios(unsigned short func, unsigned short arg1,
    unsigned short arg2, unsigned short arg3,
    unsigned short arg4, unsigned short arg5,
    unsigned short arg6, unsigned short arg7);

/*
 * ISA PnP card isolation protocol
 * Attempts to isolate a card and assign it the specified CSN
 * Returns 1 if successful (checksum matched), 0 otherwise
 */
int isolateCard(unsigned char csn);

#endif /* _BIOS_H_ */
