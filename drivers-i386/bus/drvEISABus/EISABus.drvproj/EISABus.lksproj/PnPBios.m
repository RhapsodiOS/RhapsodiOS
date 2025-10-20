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
#import <string.h>

/* External GDT pointer */
extern unsigned int *__gdt;

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
        if (ptr >= (unsigned char *)0xFFFFE) {
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
    _pnpBuffer = NULL;

    /* Check if PnP BIOS is present and get structure pointer */
    present = [PnPBios Present:&_pnpStruct];

    if (present) {
        /* Copy entry points from PnP installation structure */
        /* Note: These offsets match the PnP BIOS specification */
        unsigned char *structBytes = (unsigned char *)_pnpStruct;

        /* Copy 16-bit Protected Mode Offset (2 bytes at offset 0x11) */
        _realModeCS = *(unsigned short *)(structBytes + 0x11);

        /* Copy 32-bit Protected Mode Code Base Address (4 bytes at offset 0x13) */
        _realModeEntryOffset = *(unsigned int *)(structBytes + 0x13);

        /* Copy 32-bit Protected Mode Data Base Address (4 bytes at offset 0x1D) */
        _protModeEntryOffset = *(unsigned int *)(structBytes + 0x1D);

        /* Allocate 64KB buffer for PnP BIOS operations */
        buffer = IOMalloc(0x10000);
        _pnpBuffer = buffer;

        if (buffer != NULL) {
            /* Successfully initialized */
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
    if (_pnpBuffer != NULL) {
        IOFree(_pnpBuffer, 0x10000);
    }

    /* Free the argument stack object if allocated */
    if (_argStack != nil) {
        [_argStack free];
    }

    /* Call superclass free */
    [super free];

    return self;
}

/*
 * Get device node information
 */
- (int)getDeviceNode:(void *)buffer ForHandle:(int *)handle
{
    unsigned char *pnpBuf;
    BOOL setupOk;
    int result;

    /* Setup segments for BIOS call */
    setupOk = [self setupSegments];
    if (!setupOk) {
        return 0x8F;
    }

    /* Get pointer to PnP buffer */
    pnpBuf = (unsigned char *)_pnpBuffer;

    /* Store handle in first byte of buffer */
    *pnpBuf = (unsigned char)*handle;

    /* Reset argument stack */
    [_argStack reset];

    /* Push arguments for PnP BIOS function 0x01 (Get Device Node) */
    /* Arguments are pushed in reverse order */
    [_argStack push:_dataSelector];
    [_argStack push:1];  /* Function 0x01 */
    [_argStack pushFarPtr:(pnpBuf + 2)];  /* Far pointer to node buffer */
    [_argStack pushFarPtr:pnpBuf];        /* Far pointer to handle/control */
    [_argStack push:1];  /* Get next node */

    /* Set output buffer pointer to node data area (offset +2) */
    *(void **)buffer = pnpBuf + 2;

    /* Call PnP BIOS */
    result = call_bios(_biosCallData);

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
    BOOL setupOk;
    int result;

    /* Setup segments for BIOS call */
    setupOk = [self setupSegments];
    if (!setupOk) {
        return 0x8F;
    }

    /* Get pointer to PnP buffer (as short array) */
    pnpBuf = (unsigned short *)_pnpBuffer;

    /* Reset argument stack */
    [_argStack reset];

    /* Push arguments for PnP BIOS function 0x00 (Get Number of System Device Nodes) */
    [_argStack push:_dataSelector];
    [_argStack pushFarPtr:pnpBuf];        /* Far pointer for numNodes */
    [_argStack pushFarPtr:(pnpBuf + 1)];  /* Far pointer for maxNodeSize */
    [_argStack push:0];  /* Function 0x00 */

    /* Call PnP BIOS */
    result = call_bios(_biosCallData);

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
- (int)getPnPConfig:(void *)buffer
{
    BOOL setupOk;
    int result;

    /* Setup segments for BIOS call */
    setupOk = [self setupSegments];
    if (!setupOk) {
        return 0x8F;
    }

    /* Set output buffer pointer to PnP buffer */
    *(void **)buffer = _pnpBuffer;

    /* Reset argument stack */
    [_argStack reset];

    /* Push arguments for PnP BIOS function 0x40 (Get Static Allocation Resource Information) */
    [_argStack push:_dataSelector];
    [_argStack pushFarPtr:_pnpBuffer];
    [_argStack push:0x40];  /* Function 0x40 */

    /* Call PnP BIOS */
    result = call_bios(_biosCallData);

    /* Release segments */
    [self releaseSegments];

    return result;
}

/*
 * Setup segments for PnP BIOS calls
 * Creates temporary GDT entries for PnP BIOS access
 */
- setupSegments
{
    unsigned int *gdt = __gdt;
    unsigned int base;
    unsigned short *bufferSelector;

    /* Save current GDT entries before modifying them */
    _savedGDT[0] = *(unsigned int *)(gdt + 0x80);
    _savedGDT[1] = *(unsigned int *)(gdt + 0x84);
    _savedGDT[2] = *(unsigned int *)(gdt + 0x90);
    _savedGDT[3] = *(unsigned int *)(gdt + 0x94);
    _savedGDT[4] = *(unsigned int *)(gdt + 0x98);
    _savedGDT[5] = *(unsigned int *)(gdt + 0x9C);
    _savedGDT[6] = *(unsigned int *)(gdt + 0x88);
    _savedGDT[7] = *(unsigned int *)(gdt + 0x8C);

    /* Setup segment 16 (0x80) - PnP BIOS real mode code segment */
    base = _realModeEntryOffset;
    *(unsigned short *)(gdt + 0x82) = (unsigned short)base;
    *(unsigned char *)(gdt + 0x84) = (unsigned char)(base >> 16);
    *(unsigned char *)(gdt + 0x87) = (unsigned char)(base >> 24);
    *(unsigned char *)(gdt + 0x85) = (*(unsigned char *)(gdt + 0x85) & 0xE0) | 0x1A;
    *(unsigned char *)(gdt + 0x85) = (*(unsigned char *)(gdt + 0x85) & 0x9F) | 0x80;
    *(unsigned char *)(gdt + 0x86) &= 0x3F;
    *(unsigned short *)(gdt + 0x80) = 0xFFFF;
    *(unsigned char *)(gdt + 0x86) &= 0xF0;

    /* Setup segment 18 (0x90) - PnP BIOS protected mode code segment */
    base = _protModeEntryOffset;
    *(unsigned short *)(gdt + 0x92) = (unsigned short)base;
    *(unsigned char *)(gdt + 0x94) = (unsigned char)(base >> 16);
    *(unsigned char *)(gdt + 0x97) = (unsigned char)(base >> 24);
    *(unsigned char *)(gdt + 0x95) = (*(unsigned char *)(gdt + 0x95) & 0xE0) | 0x12;
    *(unsigned char *)(gdt + 0x95) = (*(unsigned char *)(gdt + 0x95) & 0x9F) | 0x80;
    *(unsigned char *)(gdt + 0x96) = (*(unsigned char *)(gdt + 0x96) | 0x40) & 0x7F;
    *(unsigned short *)(gdt + 0x90) = 0xFFFF;
    *(unsigned char *)(gdt + 0x96) = (*(unsigned char *)(gdt + 0x96) & 0xF0) & 0xBF;

    /* Set data selector to 0x90 */
    _dataSelector = 0x90;

    /* Setup segment 19 (0x98) - Data segment at 0x6FEC */
    *(unsigned short *)(gdt + 0x9A) = 0x6FEC;
    *(unsigned char *)(gdt + 0x9C) = 0;
    *(unsigned char *)(gdt + 0x9F) = 0xC0;
    *(unsigned char *)(gdt + 0x9D) = (*(unsigned char *)(gdt + 0x9D) & 0xE0) | 0x1A;
    *(unsigned char *)(gdt + 0x9D) = (*(unsigned char *)(gdt + 0x9D) & 0x9F) | 0x80;
    *(unsigned char *)(gdt + 0x9E) = (*(unsigned char *)(gdt + 0x9E) | 0x40) & 0x7F;
    *(unsigned short *)(gdt + 0x98) = 0xFFFF;
    *(unsigned char *)(gdt + 0x9E) &= 0xF0;

    /* Setup segment 17 (0x88) - Buffer segment */
    base = (unsigned int)_pnpBuffer - 0x40000000;
    *(unsigned short *)(gdt + 0x8A) = (unsigned short)base;
    *(unsigned char *)(gdt + 0x8C) = (unsigned char)(base >> 16);
    *(unsigned char *)(gdt + 0x8F) = (unsigned char)(base >> 24);
    *(unsigned char *)(gdt + 0x8D) = (*(unsigned char *)(gdt + 0x8D) & 0xE0) | 0x12;
    *(unsigned char *)(gdt + 0x8D) = (*(unsigned char *)(gdt + 0x8D) & 0x9F) | 0x80;
    *(unsigned char *)(gdt + 0x8E) = (*(unsigned char *)(gdt + 0x8E) | 0x40) & 0x7F;
    *(unsigned short *)(gdt + 0x88) = 0xFFFF;
    *(unsigned char *)(gdt + 0x8E) = (*(unsigned char *)(gdt + 0x8E) & 0xF0) & 0xBF;

    /* Set buffer selector */
    bufferSelector = (unsigned short *)((unsigned char *)self + 0x4C);
    *bufferSelector = 0x88;

    /* Clear BIOS call data structure (48 bytes) */
    bzero(_biosCallData, 0x30);

    /* Setup BIOS call structure fields */
    *(unsigned short *)(_biosCallData + 0x20) = 0x98;  /* Data segment at offset 0x28 */
    *(unsigned int *)(_biosCallData + 0x2C) = 0;        /* Reserved at offset 0x34 */
    *(unsigned short *)(_biosCallData + 0x22) = 0x10;   /* Kernel data at offset 0x2A */

    /* Set global PnP entry variables */
    PnPEntry_biosCodeSelector = 0x80;
    PnPEntry_biosCodeOffset = (unsigned int)_realModeCS;
    kernDataSel = 0x10;

    /* Create PnPArgStack if not already created */
    if (_argStack == nil) {
        _argStack = [[PnPArgStack alloc] initWithData:_pnpBuffer Selector:*bufferSelector];
        if (_argStack == nil) {
            IOLog("PnPBios: PnPArgStack init failed\n");
            return NO;
        }
    }

    return YES;
}

/*
 * Release segments after PnP BIOS calls
 * Restores saved GDT entries for segments 16-19 (0x80-0x9F)
 */
- releaseSegments
{
    unsigned int *gdt = __gdt;

    /* Restore saved GDT entries (8 DWORDs) */
    /* Segment 16 (0x80): Code segment */
    *(unsigned int *)(gdt + 0x80) = _savedGDT[0];
    *(unsigned int *)(gdt + 0x84) = _savedGDT[1];

    /* Segment 18 (0x90): Data selector */
    *(unsigned int *)(gdt + 0x90) = _savedGDT[2];
    *(unsigned int *)(gdt + 0x94) = _savedGDT[3];

    /* Segment 19 (0x98): Data segment */
    *(unsigned int *)(gdt + 0x98) = _savedGDT[4];
    *(unsigned int *)(gdt + 0x9C) = _savedGDT[5];

    /* Segment 17 (0x88): Buffer segment */
    *(unsigned int *)(gdt + 0x88) = _savedGDT[6];
    *(unsigned int *)(gdt + 0x8C) = _savedGDT[7];

    return self;
}

@end
