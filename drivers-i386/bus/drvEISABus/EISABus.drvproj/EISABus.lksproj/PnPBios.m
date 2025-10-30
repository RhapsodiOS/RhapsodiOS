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
 * PnPBios.m
 * PnP BIOS Interface Implementation
 */

#import "PnPBios.h"
#import "PnPArgStack.h"
#import "bios.h"
#import <driverkit/generalFuncs.h>
#import <architecture/i386/table.h>
#import <string.h>

/* For interrupt control (splhigh/splx) */
#import <bsd/sys/param.h>
#import <kernserv/i386/spl.h>

/* RhapsodiOS kernel GDT access */
#import <architecture/i386/table.h>
#import <machdep/i386/gdt.h>
#import <machdep/i386/seg.h>
#import <machdep/i386/sel_inline.h>
#import <machdep/i386/table_inline.h>
#import <machdep/i386/desc_inline.h>

/* External globals for PnP BIOS entry */
extern unsigned short PnPEntry_biosCodeSelector;
extern unsigned int PnPEntry_biosCodeOffset;
extern unsigned short kernDataSel;

/* External verbose logging flag (defined in bios.c) */
extern char verbose;

@implementation PnPBios

/*
 * Check if PnP BIOS is present in the system
 * Searches BIOS ROM area (0xF0000 to 0xFFFFE) for PnP installation check structure
 * Returns YES if found and valid, NO otherwise
 * If found, stores pointer to structure in pnpStructPtr
 */
+ (BOOL)Present:(void **)pnpStructPtr
{
    unsigned char *ptr;
    int compareResult;
    unsigned char checksum;
    int i;
    unsigned char length;

    /* Search BIOS ROM from 0xF0000 to 0xFFFFE in 16-byte increments */
    ptr = (unsigned char *)0xF0000;

    while (1) {
        /* Check for "$PnP" signature (4 bytes) */
        compareResult = strncmp((char *)ptr, "$PnP", 4);

        if (compareResult == 0) {
            /* Found signature - validate checksum */
            /* Offset 5 contains structure length */
            length = ptr[5];

            /* Calculate checksum - sum of all bytes should be 0 */
            checksum = 0;
            i = 0;

            if (length != 0) {
                do {
                    checksum = checksum + ptr[i];
                    i++;
                } while (i < (int)length);
            }

            /* If checksum is valid (0), we found it */
            if (checksum == 0) {
                *pnpStructPtr = ptr;
                return YES;
            }
        }

        /* Move to next 16-byte boundary */
        ptr = ptr + 0x10;

        /* Check if we've passed the end of the search area (0xFFFFE) */
        if (ptr > (unsigned char *)0xFFFFE) {
            return NO;
        }
    }
}

/*
 * Set verbose logging mode
 * Enables or disables verbose logging for PnP BIOS operations
 */
+ (void)setVerbose:(char)verboseFlag
{
    verbose = verboseFlag;
}

/*
 * Initialize PnP BIOS interface
 */
- init
{
    BOOL present;
    void *buffer;

    /* Call superclass init */
    [super init];

    /* Initialize instance variables */
    _argStack = nil;
    _kData = NULL;

    IOLog("PnPBios: Calling Present\n");

    /* Check if PnP BIOS is present and get structure pointer */
    present = [PnPBios Present:(void **)&_installCheck_p];
    if (present) {
        /* Copy entry points from PnP installation structure */
        /* Note: These offsets match the PnP BIOS specification */
        unsigned char *structBytes = (unsigned char *)_installCheck_p;

        /* Copy 16-bit Real Mode Code Offset (2 bytes at offset 0x0B) */
        _biosEntryOffset = *(unsigned short *)(structBytes + 0x0B);

        /* Copy 16-bit Real Mode Code Segment (2 bytes at offset 0x09) */
        /* Note: We are storing a 'short' in an 'int' field, which is fine. */
        _biosCodeSegAddr = *(unsigned short *)(structBytes + 0x09);

        /* Copy 32-bit Protected Mode Data Base Address (4 bytes at offset 0x1D) */
        _dataSegAddr = *(unsigned int *)(structBytes + 0x1D);

        /* Allocate 64KB buffer for PnP BIOS operations */
        buffer = IOMalloc(0x10000);
        _kData = buffer;

        if (buffer != NULL) {
            /* Successfully initialized */
            IOLog("PnPBios: Present succeeded! Entry: 0x%X:0x%X\n", _biosCodeSegAddr, _biosEntryOffset);
            return self;
        }

        /* Allocation failed */
        IOLog("PnPBios: IOMalloc failed\n");
    }

    /* PnP BIOS not present or initialization failed - free and return nil */
    return [self free];
}

/*
 * Free PnP BIOS resources
 */
- free
{
    /* Free the 64KB PnP buffer if allocated */
    if (_kData != NULL) {
        IOFree(_kData, 0x10000);
    }

    /* Free the argument stack object if allocated */
    if (_argStack != nil) {
        [_argStack free];
    }

    /* Call superclass free and return its result */
    return [super free];
}

/*
 * Get device node information
 */
- (int)getDeviceNode:(void **)buffer ForHandle:(int)handle
{
    unsigned char *pnpBuf;
    id setupOk;
    int result;

    /* Setup segments for BIOS call */
    setupOk = [self setupSegments];
    if (!setupOk) {
        return 0x8F;
    }

    /* Get pointer to PnP buffer */
    pnpBuf = (unsigned char *)_kData;

    /* Store handle in first byte of buffer */
    *pnpBuf = (unsigned char)handle;

    /* Reset argument stack */
    [_argStack reset];

    /* Push arguments for PnP BIOS function 0x01 (Get Device Node) */
    /* Arguments are pushed in reverse order */
    [_argStack push:_biosSelector];
    [_argStack push:1];  /* Function 0x01 */
    [_argStack pushFarPtr:(pnpBuf + 2)];  /* Far pointer to node buffer */
    [_argStack pushFarPtr:pnpBuf];        /* Far pointer to handle/control */
    [_argStack push:1];  /* Get next node */

    /* Set output buffer pointer to node data area (offset +2) */
    *(void **)buffer = pnpBuf + 2;

    /* Call PnP BIOS */
    result = call_bios(_bb);

    /* Release segments */
    [self releaseSegments];

    return result;
}

/*
 * Get number of nodes and maximum node size
 */
- (int)getNumNodes:(int *)numNodes AndSize:(int *)maxNodeSize
{
    unsigned short *pnpBuf;
    id setupOk;
    int result;

    /* Setup segments for BIOS call */
    setupOk = [self setupSegments];
    if (!setupOk) {
        return 0x8F;
    }

    /* Get pointer to PnP buffer (as short array) */
    pnpBuf = (unsigned short *)_kData;

    /* Reset argument stack */
    [_argStack reset];

    /* Push arguments for PnP BIOS function 0x00 (Get Number of System Device Nodes) */
    [_argStack push:_biosSelector];
    [_argStack pushFarPtr:pnpBuf];        /* Far pointer for numNodes */
    [_argStack pushFarPtr:(pnpBuf + 1)];  /* Far pointer for maxNodeSize */
    [_argStack push:0];  /* Function 0x00 */

    /* Call PnP BIOS */
    result = call_bios(_bb);

    /* Copy results from buffer */
    *maxNodeSize = (int)*pnpBuf;
    *numNodes = (int)*((unsigned char *)(pnpBuf + 1));

    /* Release segments */
    [self releaseSegments];

    return result;
}

/*
 * Get PnP configuration
 */
- (int)getPnPConfig:(void **)buffer
{
    id setupOk;
    int result;

    /* Setup segments for BIOS call */
    IOLog("PnPBios: getPnPConfig calling setupSegments\n");
    setupOk = [self setupSegments];
    if (!setupOk) {
        return 0x8F;
    }

    IOLog("PnPBios: getPnPConfig setting buffer\n");

    /* Set output buffer pointer to PnP buffer */
    *(void **)buffer = _kData;

    /* Reset argument stack */
    [_argStack reset];

    /* Push arguments for PnP BIOS function 0x40 (Get Static Allocation Resource Information) */
    [_argStack push:_biosSelector];
    [_argStack pushFarPtr:_kData];
    [_argStack push:0x40];  /* Function 0x40 */

    /* Call PnP BIOS */
    IOLog("PnPBios: getPnPConfig call_bios\n");
    result = call_bios(_bb);

    /* Release segments */
    IOLog("PnPBios: getPnPConfig calling releaseSegments\n");
    [self releaseSegments];

    IOLog("PnPBios: getPnPConfig done\n");

    return result;
}

/*
 * Setup segments for PnP BIOS calls
 * Implementation based on decompiled original code
 * Saves and restores GDT entries 16, 17, 18, 19 (0x80, 0x88, 0x90, 0x98)
 */
- setupSegments
{
    unsigned int *gdtPtr;
    unsigned char *gdtBase;
    unsigned int base;
    unsigned int bufferBase = 0;
    BiosCallData *callData = (BiosCallData *)_bb;

    /* Get pointer to GDT as byte array for offset calculations */
    gdtBase = (unsigned char *)gdt;

    /*
     * Save existing GDT entries (8 bytes each)
     * Entry 16 (0x80) -> _saveGDTBiosCode
     * Entry 18 (0x90) -> _saveGDTBiosEntry
     * Entry 19 (0x98) -> _saveGDTKData
     * Entry 17 (0x88) -> _saveGDTBiosData
     */
    gdtPtr = (unsigned int *)(gdtBase + 0x80);
    _saveGDTBiosCode[0] = gdtPtr[0];
    _saveGDTBiosCode[1] = gdtPtr[1];

    gdtPtr = (unsigned int *)(gdtBase + 0x90);
    _saveGDTBiosEntry[0] = gdtPtr[0];
    _saveGDTBiosEntry[1] = gdtPtr[1];

    gdtPtr = (unsigned int *)(gdtBase + 0x98);
    _saveGDTKData[0] = gdtPtr[0];
    _saveGDTKData[1] = gdtPtr[1];

    gdtPtr = (unsigned int *)(gdtBase + 0x88);
    _saveGDTBiosData[0] = gdtPtr[0];
    _saveGDTBiosData[1] = gdtPtr[1];

    /*
     * Setup entry 16 (0x80) - 16-bit code segment
     * Base: _biosCodeSegAddr, Limit: 0xFFFF
     * Type: 0x1A (16-bit code, readable), DPL: 0, Present: 1
     */
    base = _biosCodeSegAddr;
    *(unsigned short *)(gdtBase + 0x80) = 0xFFFF;  /* Limit 15:0 */
    *(unsigned short *)(gdtBase + 0x82) = (unsigned short)base;  /* Base 15:0 */
    *(unsigned char *)(gdtBase + 0x84) = (unsigned char)(base >> 16);  /* Base 23:16 */
    *(unsigned char *)(gdtBase + 0x87) = (unsigned char)(base >> 24);  /* Base 31:24 */
    *(unsigned char *)(gdtBase + 0x85) = (*(unsigned char *)(gdtBase + 0x85) & 0xE0) | 0x1A;
    *(unsigned char *)(gdtBase + 0x85) = (*(unsigned char *)(gdtBase + 0x85) & 0x9F);
    *(unsigned char *)(gdtBase + 0x85) = *(unsigned char *)(gdtBase + 0x85) | 0x80;
    *(unsigned char *)(gdtBase + 0x86) = *(unsigned char *)(gdtBase + 0x86) & 0xBF;
    *(unsigned char *)(gdtBase + 0x86) = (*(unsigned char *)(gdtBase + 0x86) & 0xF0);
    *(unsigned char *)(gdtBase + 0x86) = (*(unsigned char *)(gdtBase + 0x86) & 0x7F);

    /*
     * Setup entry 18 (0x90) - 32-bit code segment
     * Base: _dataSegAddr, Limit: 0xFFFF
     * Type: 0x12 (32-bit data, writable), DPL: 0, Present: 1, D/B: 1
     */
    base = _dataSegAddr;
    *(unsigned short *)(gdtBase + 0x90) = 0xFFFF;  /* Limit 15:0 */
    *(unsigned short *)(gdtBase + 0x92) = (unsigned short)base;  /* Base 15:0 */
    *(unsigned char *)(gdtBase + 0x94) = (unsigned char)(base >> 16);  /* Base 23:16 */
    *(unsigned char *)(gdtBase + 0x97) = (unsigned char)(base >> 24);  /* Base 31:24 */
    *(unsigned char *)(gdtBase + 0x95) = (*(unsigned char *)(gdtBase + 0x95) & 0xE0) | 0x12;
    *(unsigned char *)(gdtBase + 0x95) = (*(unsigned char *)(gdtBase + 0x95) & 0x9F);
    *(unsigned char *)(gdtBase + 0x95) = *(unsigned char *)(gdtBase + 0x95) | 0x80;
    *(unsigned char *)(gdtBase + 0x96) = *(unsigned char *)(gdtBase + 0x96) | 0x40;
    *(unsigned char *)(gdtBase + 0x96) = (*(unsigned char *)(gdtBase + 0x96) & 0xF0);
    *(unsigned char *)(gdtBase + 0x96) = (*(unsigned char *)(gdtBase + 0x96) & 0x7F);
    *(unsigned char *)(gdtBase + 0x96) = (*(unsigned char *)(gdtBase + 0x96) & 0xBF);

    /* Set _biosSelector to 0x90 */
    _biosSelector = 0x90;

    /*
     * Setup entry 19 (0x98) - Data segment at 0xC0006FEC
     * Base: 0xC0006FEC, Limit: 0xFFFF
     * Type: 0x1A (code/data), DPL: 0, Present: 1, D/B: 1
     */
    *(unsigned short *)(gdtBase + 0x98) = 0xFFFF;  /* Limit 15:0 */
    *(unsigned short *)(gdtBase + 0x9A) = 0x6FEC;  /* Base 15:0 */
    *(unsigned char *)(gdtBase + 0x9C) = 0x00;  /* Base 23:16 */
    *(unsigned char *)(gdtBase + 0x9F) = 0xC0;  /* Base 31:24 */
    *(unsigned char *)(gdtBase + 0x9D) = (*(unsigned char *)(gdtBase + 0x9D) & 0xE0) | 0x1A;
    *(unsigned char *)(gdtBase + 0x9D) = (*(unsigned char *)(gdtBase + 0x9D) & 0x9F);
    *(unsigned char *)(gdtBase + 0x9D) = (*(unsigned char *)(gdtBase + 0x9D) | 0x80);
    *(unsigned char *)(gdtBase + 0x9E) = *(unsigned char *)(gdtBase + 0x9E) | 0x40;
    *(unsigned char *)(gdtBase + 0x9E) = (*(unsigned char *)(gdtBase + 0x9E) & 0xF0);
    *(unsigned char *)(gdtBase + 0x9E) = (*(unsigned char *)(gdtBase + 0x9E) & 0x7F);

    /*
     * Setup entry 17 (0x88) - Buffer segment
     * Base: _kData - 0x40000000, Limit: 0xFFFF
     * Type: 0x12 (32-bit data, writable), DPL: 0, Present: 1, D/B: 1
     */
    bufferBase = (unsigned int)_kData - 0x40000000;
    *(unsigned short *)(gdtBase + 0x88) = 0xFFFF;  /* Limit 15:0 */
    *(unsigned short *)(gdtBase + 0x8A) = (unsigned short)bufferBase;  /* Base 15:0 */
    *(unsigned char *)(gdtBase + 0x8C) = (unsigned char)(bufferBase >> 16);  /* Base 23:16 */
    *(unsigned char *)(gdtBase + 0x8F) = (unsigned char)(bufferBase >> 24);  /* Base 31:24 */
    *(unsigned char *)(gdtBase + 0x8D) = (*(unsigned char *)(gdtBase + 0x8D) & 0xE0) | 0x12;
    *(unsigned char *)(gdtBase + 0x8D) = (*(unsigned char *)(gdtBase + 0x8D) & 0x9F);
    *(unsigned char *)(gdtBase + 0x8D) = (*(unsigned char *)(gdtBase + 0x8D) | 0x80);
    *(unsigned char *)(gdtBase + 0x8E) = *(unsigned char *)(gdtBase + 0x8E) | 0x40;
    *(unsigned char *)(gdtBase + 0x8E) = (*(unsigned char *)(gdtBase + 0x8E) & 0xF0);
    *(unsigned char *)(gdtBase + 0x8E) = (*(unsigned char *)(gdtBase + 0x8E) & 0x7F);
    *(unsigned char *)(gdtBase + 0x8E) = (*(unsigned char *)(gdtBase + 0x8E) & 0xBF);

    /* Set _kDataSelector to 0x88 */
    _kDataSelector = 0x88;

    /* Clear the bios call data struct */
    bzero(callData, sizeof(BiosCallData));

    /* Set our initial segment address and entry offset */
    callData->far_seg    = 0x98; // Assembly: MOV word ptr [ESI + 0x28], 0x98
    callData->far_offset = 0;    // Assembly: MOV dword ptr [ESI + 0x34], 0x0

    /*
     * This sets the Data Segment for the 16-bit call.
     * This value comes from the assembly (0x3730: MOV word ptr [ESI + 0x2a], 0x10)
     * and corresponds to the kernel data segment selector (0x10).
     */
    callData->ds_seg = 0x10;

    /* Set global PnP entry point variables */
    PnPEntry_biosCodeSelector = 0x80;
    PnPEntry_biosCodeOffset = (unsigned int)_biosEntryOffset;
    kernDataSel = 0x10;

    /* Create PnPArgStack if not already created */
    if (_argStack == nil) {
        _argStack = [[PnPArgStack alloc] initWithData:_kData Selector:_kDataSelector];
        if (_argStack == nil) {
            IOLog("PnPBios: PnPArgStack init failed\n");
            return nil;
        }
    }

    return self;
}

/*
 * Release segments after PnP BIOS calls
 * Restores saved GDT entries
 */
- releaseSegments
{
    unsigned int *gdtPtr;
    unsigned char *gdtBase;

    /* Get pointer to GDT as byte array for offset calculations */
    gdtBase = (unsigned char *)gdt;

    /*
     * Restore saved GDT entries (8 bytes each)
     * Entry 16 (0x80) from _saveGDTBiosCode
     * Entry 18 (0x90) from _saveGDTBiosEntry
     * Entry 19 (0x98) from _saveGDTKData
     * Entry 17 (0x88) from _saveGDTBiosData
     */
    gdtPtr = (unsigned int *)(gdtBase + 0x80);
    gdtPtr[0] = _saveGDTBiosCode[0];
    gdtPtr[1] = _saveGDTBiosCode[1];

    gdtPtr = (unsigned int *)(gdtBase + 0x90);
    gdtPtr[0] = _saveGDTBiosEntry[0];
    gdtPtr[1] = _saveGDTBiosEntry[1];

    gdtPtr = (unsigned int *)(gdtBase + 0x98);
    gdtPtr[0] = _saveGDTKData[0];
    gdtPtr[1] = _saveGDTKData[1];

    gdtPtr = (unsigned int *)(gdtBase + 0x88);
    gdtPtr[0] = _saveGDTBiosData[0];
    gdtPtr[1] = _saveGDTBiosData[1];

    return self;
}

@end
