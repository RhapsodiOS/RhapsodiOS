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
 * BIOS Call Data Structure
 * This structure is passed to _bios32PnP to make far calls to the PnP BIOS.
 * Total size: 48 bytes (0x30)
 */
typedef struct {
    unsigned int reserved;          /* +0x00: Reserved */
    unsigned int eax;                /* +0x04: EAX register (input/output) */
    unsigned int ebx;                /* +0x08: EBX register (input/output) */
    unsigned int ecx;                /* +0x0C: ECX register (input/output) */
    unsigned int edx;                /* +0x10: EDX register (input/output) */
    unsigned int edi;                /* +0x14: EDI register (input/output) */
    unsigned int esi;                /* +0x18: ESI register (input/output) */
    unsigned int ebp;                /* +0x1C: EBP register (output only) */
    unsigned short far_seg;          /* +0x20: Far call segment (input) */
    unsigned short ds_seg;           /* +0x22: DS segment (input) */
    unsigned short es_seg;           /* +0x24: ES segment (output) */
    unsigned short reserved2;        /* +0x26: Reserved */
    unsigned short flags;            /* +0x28: EFLAGS (output, word only) */
    unsigned short reserved3;        /* +0x2A: Reserved */
    unsigned int far_offset;         /* +0x2C: Far call offset (input) */
} BiosCallData;

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
 * Global variables - ordered to match decompiled binary memory layout
 * Starting at 0x80CC
 */
extern unsigned short readPort;                  /* 0x80CE - PnP read port */
extern unsigned short save_es;                   /* 0x80D0 - Temp ES storage */
extern unsigned int save_eax;                    /* 0x80D4 - Temp EAX storage */
extern unsigned int save_ecx;                    /* 0x80D8 - Temp ECX storage */
extern unsigned int save_edx;                    /* 0x80DC - Saves biosCallData pointer */
extern unsigned short save_flag;                 /* 0x80E0 - Temp EFLAGS storage */
extern unsigned int new_eax;                     /* 0x80E4 - Input EAX value */
extern unsigned int new_edx;                     /* 0x80E8 - Input/output EDX value */

/*
 * Far pointer components for BIOS calls
 * These are defined in bios_asm.s in the .data section (writable memory)
 *
 * save_addr and save_seg form a 6-byte far pointer used by _bios32PnP
 * pnp_addr and pnp_seg form a 6-byte far pointer used by __PnPEntry
 *
 * The assembly code uses indirect far call/jump through these addresses:
 *   lcall *_save_addr  (reads 6 bytes: 4-byte offset + 2-byte segment)
 *   ljmp *_pnp_addr    (reads 6 bytes: 4-byte offset + 2-byte segment)
 */
extern unsigned int save_addr;       /* Far call offset (4 bytes) */
extern unsigned short save_seg;      /* Far call segment (2 bytes, immediately follows save_addr) */
extern unsigned int pnp_addr;        /* Far jump offset (4 bytes) */
extern unsigned short pnp_seg;       /* Far jump segment (2 bytes, immediately follows pnp_addr) */

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
