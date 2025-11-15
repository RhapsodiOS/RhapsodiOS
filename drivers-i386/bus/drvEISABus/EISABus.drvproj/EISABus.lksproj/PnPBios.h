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

/*
 * Compilers used in the historical build chain were based on GCC 2.7, which
 * understands __attribute__((packed)) but not the more modern #pragma pack
 * push/pop syntax.  Provide a macro so newer compilers can continue to pack
 * the structure while older ones quietly ignore it (in which case the build
 * should define a compatible mechanism).
 */
#if defined(__GNUC__)
#define PNP_PACKED __attribute__((packed))
#else
#define PNP_PACKED
#endif

/*
 * PnP Installation Check Structure (PnP BIOS Specification v1.0a, §4.3)
 * Offsets are documented to make it obvious when fields need to line up with
 * the firmware-defined layout.
 */
struct PnPInstallationStructure {
    char signature[4];              /* 0x00: ASCII "$PnP" */
    unsigned char version;          /* 0x04: BCD version (major<<4 | minor) */
    unsigned char length;           /* 0x05: Total length of this structure */
    unsigned short controlField;    /* 0x06: Feature flags */
    unsigned char checksum;         /* 0x08: Sum over length bytes == 0 */
    unsigned int eventNotification; /* 0x09: Physical address of event flag */
    unsigned short realModeEntryOffset;   /* 0x0D: Real-mode entry offset */
    unsigned short realModeEntrySegment;  /* 0x0F: Real-mode entry segment */
    unsigned short protModeEntryOffset;   /* 0x11: 16-bit protected entry offset */
    unsigned int protModeEntryBase;       /* 0x13: 32-bit base for protected entry */
    unsigned int oemDeviceID;             /* 0x17: OEM-specific ID */
    unsigned short realModeDataSegment;   /* 0x1B: Real-mode data segment */
    unsigned int protModeDataBaseAddr;    /* 0x1D: 32-bit base for protected data */
    unsigned char reserved0[0x25 - 0x21]; /* 0x21-0x24: Reserved by spec */
    unsigned short pmStackOffset;         /* 0x25: 16-bit protected stack offset */
    unsigned short pmStackSelector;       /* 0x27: Selector for protected stack */
} PNP_PACKED;

typedef struct PnPInstallationStructure PnPInstallationStructure;

/* PnPBios - BIOS interface */
@interface PnPBios : Object
{
    @private
    id _argStack;                           /* PnPArgStack object at offset 0x04 */
    unsigned char _bb[48];                  /* BIOS call structure at offset 0x08 */
    unsigned int _biosCodeSegAddr;          /* Real mode entry offset at 0x38 */
    unsigned short _biosEntryOffset;        /* Real mode code segment at 0x3C */
    unsigned short _biosSelector;           /* Data segment selector at 0x3E */
    unsigned int _dataSegAddr;              /* Protected mode entry at 0x40 */
    PnPInstallationStructure *_installCheck_p;  /* PnP structure pointer at 0x44 */
    void *_kData;                           /* 64KB buffer at 0x48 */
    void *_paddingBuffer;                   /* Padding buffer */
    void *_biosDataSegBuffer;               /* BIOS data segment buffer */
    unsigned short _kDataSelector;          /* Buffer selector */
    unsigned short _pmStackSel;
    unsigned short _pmStackOff;
    unsigned int _saveGDTBiosCode[2];       /* Saved GDT entry 16 */
    unsigned int _saveGDTBiosEntry[2];      /* Saved GDT entry 18 */
    unsigned int _saveGDTKData[2];          /* Saved GDT entry 19 */
    unsigned int _saveGDTBiosData[2];       /* Saved GDT entry 17 */
}

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
 * Segment setup and release
 */
- setupSegments;
- releaseSegments;

@end

#endif /* _PNPBIOS_H_ */
