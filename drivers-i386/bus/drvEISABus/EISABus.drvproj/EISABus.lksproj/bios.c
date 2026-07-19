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
 * bios.c
 * BIOS Call Utilities Implementation
 */

#include "bios.h"
#include <driverkit/generalFuncs.h>
#include <driverkit/i386/ioPorts.h>

/* Global PnP read port - set during initialization */
extern unsigned short pnpReadPort;

/*
 * Global variables for BIOS operations
 */
char verbose = 0;                      /* Verbose logging flag */
unsigned short readPort = 0;           /* PnP read port */
void *bios32PnP_ptr = NULL;            /* BIOS32 PnP entry point function pointer */
unsigned short kernDataSel = 0x10;     /* Kernel data segment selector (GDT entry 2) */

/*
 * PnP BIOS call wrapper
 *
 * Calls the BIOS32 PnP entry point with a pointer to a BIOSCallStruct.
 * The BIOS writes its return code to the eax field of the structure.
 *
 * @param bb  Pointer to BIOSCallStruct containing BIOS call parameters
 * @return    BIOS return code from bb->eax
 */
int call_bios(BIOSCallStruct *bb)
{
    IOLog("PnPBios: call_bios - entering\n");
    IOLog("PnPBios: call_bios - bb=%p bios32PnP_ptr=%p\n", bb, bios32PnP_ptr);
    IOLog("PnPBios: call_bios - intno=0x%x eax=0x%x ebx=0x%x ecx=0x%x edx=0x%x\n",
          bb->intno, bb->eax, bb->ebx, bb->ecx, bb->edx);
    IOLog("PnPBios: call_bios - edi=0x%x esi=0x%x ebp=0x%x\n",
          bb->edi, bb->esi, bb->ebp);
    IOLog("PnPBios: call_bios - cs=0x%x ds=0x%x es=0x%x flags=0x%x addr=0x%x\n",
          bb->cs, bb->ds, bb->es, bb->flags, bb->addr);

    if (verbose == 1) {
        IOLog("PnPBios: calling BIOS (verbose mode)\n");
    }

    IOLog("PnPBios: call_bios - about to call assembly trampoline\n");

    /* Call BIOS32 PnP entry point with structure pointer */
    ((void (*)(BIOSCallStruct *))bios32PnP_ptr)(bb);

    IOLog("PnPBios: call_bios - returned from assembly trampoline\n");
    IOLog("PnPBios: call_bios - result: eax=0x%x ebx=0x%x ecx=0x%x edx=0x%x\n",
          bb->eax, bb->ebx, bb->ecx, bb->edx);
    IOLog("PnPBios: call_bios - result: edi=0x%x esi=0x%x ebp=0x%x flags=0x%x\n",
          bb->edi, bb->esi, bb->ebp, bb->flags);

    if (verbose == 1) {
        IOLog("PnPBios: BIOS returned 0x%x (verbose mode)\n", bb->eax);
    }

    IOLog("PnPBios: call_bios - returning 0x%x\n", bb->eax);

    /* Return the result code from eax field */
    return bb->eax;
}

/*
 * clearPnPConfigRegisters - Clear all PnP configuration registers
 *
 * Writes zero to all PnP configuration registers using PnP helper functions.
 *
 * This clears registers in ranges:
 * - 0x70-0x73: Memory descriptors
 * - 0x74-0x75: Special registers (write 4)
 * - 0x60-0x6f: I/O descriptors
 * - 0x40-0x5c: DMA/IRQ descriptors
 * - 0x76-0x7f, 0x80-0x89, 0x90-0x99, 0xa0-0xa9: Extended descriptors
 */
void clearPnPConfigRegisters(void)
{
    int i, j;
    unsigned char addr;

    /* Clear registers 0x70-0x73 (Memory descriptors) */
    for (i = 0; i < 2; i++) {
        for (j = 0; j < 2; j++) {
            addr = 0x70 + (i * 2) + j;
            pnp_write_byte(addr, 0);
        }
    }

    /* Clear registers 0x74-0x75 (Special - write 4) */
    for (i = 0; i < 2; i++) {
        for (j = 0; j < 1; j++) {
            addr = 0x74 + i + j;
            pnp_write_byte(addr, 4);
        }
    }

    /* Clear registers 0x60-0x6f (I/O descriptors) */
    for (i = 0; i < 8; i++) {
        for (j = 0; j < 2; j++) {
            addr = 0x60 + (i * 2) + j;
            pnp_write_byte(addr, 0);
        }
    }

    /* Clear registers 0x40-0x5c (DMA/IRQ descriptors) */
    for (i = 0; i < 4; i++) {
        for (j = 0; j < 5; j++) {
            addr = 0x40 + (i * 8) + j;
            pnp_write_byte(addr, 0);
        }
    }

    /* Clear extended registers (varies by i) */
    for (i = 0; i < 4; i++) {
        unsigned char baseAddr;

        /* Determine base address based on i */
        switch (i) {
        case 0:
            baseAddr = 0x76;
            break;
        case 1:
            baseAddr = 0x80;
            break;
        case 2:
            baseAddr = 0x90;
            break;
        case 3:
            baseAddr = 0xa0;
            break;
        default:
            baseAddr = 0x76;
            break;
        }

        for (j = 0; j < 9; j++) {
            addr = baseAddr + j;
            pnp_write_byte(addr, 0);
        }
    }
}

/*
 * Convert a PnP vendor and product ID to a string
 *
 * @param vendor		PnP vendor ID
 * @param product		PnP product ID
 * @ret string		String representation of the PnP ID
 */
char * pnp_id_string(unsigned short vendor, unsigned short product)
{
	static unsigned char buf[7];
	int i;

	/* Vendor ID is a compressed ASCII string */
	vendor = bswap_16 ( vendor );
	for ( i = 2 ; i >= 0 ; i-- ) {
		buf[i] = ( 'A' - 1 + ( vendor & 0x1f ) );
		vendor >>= 5;
	}
	
	/* Product ID is a 4-digit hex string */
	sprintf ( &buf[3], "%hx", bswap_16 ( product ) );

	return buf;
}
