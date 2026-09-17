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
 * Register/control block handed to _bios32PnP for one PnP BIOS call.
 *
 * Exactly 48 bytes.  Every offset below is read directly out of the
 * reference disassembly of __bios32PnP (see the PnP BIOS thunk block in
 * bios.c and reconstruction/divergences.md).
 */
struct pnp_bios_regs {
    unsigned int   unused00;    /* 0x00: never referenced by the thunk       */
    unsigned int   eax;         /* 0x04: in: EAX; out: BIOS status in AX     */
    unsigned int   ebx;         /* 0x08: in/out EBX                          */
    unsigned int   ecx;         /* 0x0c: in/out ECX                          */
    unsigned int   edx;         /* 0x10: in: EDX; out: EDX                   */
    unsigned int   edi;         /* 0x14: in/out EDI                          */
    unsigned int   esi;         /* 0x18: in/out ESI                          */
    unsigned int   ebp;         /* 0x1c: out EBP                             */
    unsigned short entrySel;    /* 0x20: selector patched into the far call  */
    unsigned short dataSel;     /* 0x22: DS loaded before the far call       */
    unsigned short es;          /* 0x24: out ES                              */
    unsigned short unused26;    /* 0x26: padding, never referenced           */
    unsigned short flags;       /* 0x28: out low 16 bits of EFLAGS           */
    unsigned short unused2a;    /* 0x2a: padding, never referenced           */
    unsigned int   entryOffset; /* 0x2c: offset patched into the far call    */
};

/*
 * Globals shared between the assembler thunk, PnPArgStack and PnPBios.
 * These carry the reference's exact symbol names.
 */
extern unsigned short *PnPEntry_argStackBase;     /* _PnPEntry_argStackBase */
extern unsigned int    PnPEntry_numArgs;          /* _PnPEntry_numArgs */
extern unsigned int    PnPEntry_biosCodeOffset;   /* _PnPEntry_biosCodeOffset */
extern unsigned short  PnPEntry_biosCodeSelector; /* _PnPEntry_biosCodeSelector */
extern unsigned short  kernDataSel;               /* _kernDataSel */

/*
 * The two assembler entry points.  The leading underscore in the C name is
 * deliberate: it is what produces the reference's `__bios32PnP` /
 * `__PnPEntry` Mach-O symbols.
 */
extern void _bios32PnP(struct pnp_bios_regs *bb);
extern void _PnPEntry(void);

/*
 * Perform one PnP BIOS call.
 *
 * The argument words must already have been marshalled with PnPArgStack
 * (which publishes them via PnPEntry_argStackBase/PnPEntry_numArgs), and
 * -[PnPBios setupSegments] must have installed the GDT descriptors.
 * Returns the BIOS status word.
 */
extern int call_bios(struct pnp_bios_regs *bb);

/*
 * ISA PnP card isolation protocol
 * Attempts to isolate a card and assign it the specified CSN
 * Returns 1 if successful (checksum matched), 0 otherwise
 */
int isolateCard(unsigned char csn);

#endif /* _BIOS_H_ */
