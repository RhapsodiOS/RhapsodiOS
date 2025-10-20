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
 * Global variables used by PnP BIOS interface
 * These are set up by PnPBios setupSegments method
 */
extern unsigned short PnPEntry_biosCodeSelector;
extern unsigned int PnPEntry_biosCodeOffset;
extern unsigned short *PnPEntry_argStackBase;
extern int PnPEntry_numArgs;
extern unsigned short kernDataSel;

/*
 * Global variables used internally by _bios32PnP
 */
extern int save_edx;
extern unsigned short uRam00006f7f;
extern unsigned int uRam00006f7b;

/*
 * Global variables used internally by __PnPEntry
 */
extern int save_eax;
extern int save_ecx;

/*
 * Verbose logging flag
 * Set to non-zero to enable verbose logging of PnP BIOS operations
 */
extern char verbose;

/*
 * Call PnP BIOS with the given parameters structure
 * Returns the result code from the BIOS
 */
int call_bios(void *biosCallData);

/*
 * Low-level BIOS32 PnP call
 * Performs the actual protected mode to real mode transition
 */
void _bios32PnP(void *biosCallData);

/*
 * Clear all PnP configuration registers
 * Writes zero to all PnP config registers via ports 0x279/0xa79
 */
void clearPnPConfigRegisters(void);

/*
 * Low-level PnP BIOS entry trampoline
 * Sets up and makes a far call to the PnP BIOS entry point
 * Uses regparm(3) calling convention: param_1=EAX, param_2=EDX, param_3=ECX
 */
void __attribute__((regparm(3))) __PnPEntry(unsigned int param_1, unsigned int param_2, unsigned int param_3);

/*
 * ISA PnP card isolation protocol
 * Attempts to isolate a card and assign it the specified CSN
 * Returns 1 if successful (checksum matched), 0 otherwise
 */
int isolateCard(unsigned char csn);

#endif /* _BIOS_H_ */
