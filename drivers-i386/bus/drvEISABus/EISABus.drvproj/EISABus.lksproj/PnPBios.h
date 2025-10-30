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

/* PnP Installation Check Structure */
typedef struct {
    char signature[4];          /* "$PnP" */
    unsigned char version;
    unsigned char length;
    unsigned short controlField;
    unsigned char checksum;
    unsigned int eventNotify;
    unsigned short realModeOffset;
    unsigned short realModeCS;
    unsigned short protModeOffset;
    unsigned int protModeCS;
    unsigned int oemDeviceId;
    unsigned short realModeDataCS;
    unsigned int protModeDataBaseAddr;
} PnPInstallationStructure;

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
    unsigned short _kDataSelector;          /* Buffer selector at offset 0x4C */
    unsigned int _saveGDTBiosCode[2];       /* Saved GDT entry 16 (0x80) at 0x50-0x57 */
    unsigned int _saveGDTBiosEntry[2];      /* Saved GDT entry 18 (0x90) at 0x58-0x5F */
    unsigned int _saveGDTKData[2];          /* Saved GDT entry 19 (0x98) at 0x60-0x67 */
    unsigned int _saveGDTBiosData[2];       /* Saved GDT entry 17 (0x88) at 0x68-0x6F */
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
