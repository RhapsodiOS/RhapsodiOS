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
 * PnPBios.h
 * PnP BIOS Interface
 */

#ifndef _PNPBIOS_H_
#define _PNPBIOS_H_

#import <objc/Object.h>
#import "bios.h"

/*
 * PnP BIOS Installation Check Structure
 * Based on PnP BIOS Specification v1.0a, §4.3
 *
 * This union allows both field-level access and byte-level checksum calculation.
 * The structure is exactly 0x21 (33) bytes as defined by the specification.
 *
 */
#pragma pack(1)
union pnp_bios_install_struct {
    struct {
        unsigned int signature;               /* 0x00: "$PnP" signature (0x506E5024) */
        unsigned char version;                /* 0x04: BCD version (e.g., 0x10 = v1.0) */
        unsigned char length;                 /* 0x05: Structure length (0x21) */
        unsigned short control;               /* 0x06: System capabilities bitmap */
        unsigned char checksum;               /* 0x08: Checksum - packed to prevent padding after */
        unsigned int eventflag;               /* 0x09: Physical address of event flag */
        unsigned short rmoffset;              /* 0x0D: Real-mode entry point offset */
        unsigned short rmcseg;                /* 0x0F: Real-mode code segment */
        unsigned short pm16offset;            /* 0x11: 16-bit PM entry point offset */
        unsigned int pm16cseg;                /* 0x13: 16-bit PM code segment base */
        unsigned int deviceID;                /* 0x17: EISA system ID (or 0) */
        unsigned short rmdseg;                /* 0x1B: Real-mode data segment */
        unsigned int pm16dseg;                /* 0x1D: 16-bit PM data segment base */
    } fields;
    unsigned char bytes[0x21];            /* Raw bytes for checksum calculation */
};
#pragma pack()
typedef union pnp_bios_install_struct pnp_bios_install_struct;

/*
 * Forward declaration for PnPArgStack
 */
@class PnPArgStack;

/* PnPBios - BIOS interface */
@interface PnPBios : Object
{
    @private
    PnPArgStack *argStack;                  /* Argument stack builder */
    BIOSCallStruct bb;                      /* BIOS call structure (48 bytes) */
    unsigned int biosCodeSegAddr;           /* BIOS code segment base address */
    unsigned short biosEntryOffset;         /* BIOS entry point offset */
    unsigned short biosSelector;            /* BIOS code selector */
    unsigned int dataSegAddr;               /* BIOS data segment base address */
    pnp_bios_install_struct *installCheck_p; /* PnP BIOS installation structure */
    void *kData;                            /* 64KB buffer for PnP operations */
    unsigned short kDataSelector;           /* Buffer selector */
    unsigned int saveGDTBiosCode[2];        /* Saved GDT entry 16 */
    unsigned int saveGDTBiosData[2];        /* Saved GDT entry 17 */
    unsigned int saveGDTBiosEntry[2];       /* Saved GDT entry 18 */
    unsigned int saveGDTKData[2];           /* Saved GDT entry 19 */
}

/*
 * Class methods
 */
+ (BOOL)Present:(void **)pnpStructPtr;
+ (void)setVerbose:(char)verboseFlag;

/*
 * Initialization
 */
- init;
- free;

/*
 * Device node operations
 */
- (int)getDeviceNode:(void **)buffer ForHandle:(int)handle;
- (int)getNumNodes:(int *)numNodes AndSize:(int *)maxNodeSize;

/*
 * Configuration
 */
- (int)getPnPConfig:(void **)buffer;

/*
 * Internal methods for GDT segment management
 */
- (BOOL)setupSegments;
- (void)releaseSegments;

@end

#endif /* _PNPBIOS_H_ */
