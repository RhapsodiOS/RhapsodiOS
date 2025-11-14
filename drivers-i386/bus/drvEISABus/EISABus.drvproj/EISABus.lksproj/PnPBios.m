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

/* kernel GDT access */
#import <architecture/i386/table.h>
#import <machdep/i386/gdt.h>
#import <machdep/i386/seg.h>
#import <machdep/i386/sel_inline.h>
#import <machdep/i386/table_inline.h>
#import <machdep/i386/desc_inline.h>

/*

[getPnPConfig] ➡ __bios32PnP ➡ callf 0x98:0x00 ➡ __PnPEntry ➡ [16-bit PnP BIOS] ➡ return

call chain, which explains everything:

Objective-C: code calls call_bios(_bb).

call_bios: calls into the __bios32PnP assembly function.

__bios32PnP: This function reads the target from the _bb struct. setupSegments sets this target

The Trampoline: setupSegments also maps GDT segment 0x98 to __PnPEntry, where the BIOS code is loaded.

__PnPEntry: This function is the trampoline that jumps to the BIOS code.

*/

/*
 * Local GDT selector values for PnP BIOS setup.
 * These map to the GDT indices (16-19) and kernel data (2)
 * used by this driver.
 *
 * A selector value is (Index << 3) | RPL.
 * We are in kernel mode, so RPL = 0.
 */
#define PNP_KDS_SEL             (2 << 3)   /* 0x10 - Kernel Data (Index 2) */
#define PNP_CODE16_SEL          (16 << 3)  /* 0x80 - 16-bit PnP Code (Index 16) */
#define PNP_KDATA_SEL           (17 << 3)  /* 0x88 - Kernel Buffer (Index 17) */
#define PNP_DATA32_SEL          (18 << 3)  /* 0x90 - 32-bit PnP Data (Index 18) */
#define PNP_TRAMPOLINE_SEL      (19 << 3)  /* 0x98 - PnP Trampoline (Index 19) */

typedef struct {
    unsigned short limitLow;
    unsigned short baseLow;
    unsigned char baseMid;
    unsigned char access;
    unsigned char flagsLimitHigh;
    unsigned char baseHigh;
} GDTEntry;

/* External globals for PnP BIOS entry */
extern unsigned short PnPEntry_biosCodeSelector;
extern unsigned int PnPEntry_biosCodeOffset;
extern unsigned short kernDataSel;

extern unsigned short PnPEntry_pmStackSel;
extern unsigned int PnPEntry_pmStackOff; // Use 32-bit int for 16-bit offset

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

        /* Copy 32-bit Protected Mode Data Base Address (4 bytes at offset 0x19) */
        _dataSegAddr = *(unsigned int *)(structBytes + 0x19);

        /*
        * Copy 16-bit Protected Mode Stack Offsets (offsets 0x25 and 0x27)
        * as required by the PnP spec.
        */
        _pmStackOff = *(unsigned short *)(structBytes + 0x25);
        _pmStackSel = *(unsigned short *)(structBytes + 0x27);

        /* Allocate 64KB buffer for PnP BIOS operations */
        buffer = IOMalloc(0x10000);
        _kData = buffer;

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

    IOLog("PnPBios: GetDeviceNode result: 0x%x\n", result);

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

    IOLog("PnPBios: GetNumNodes result: 0x%x\n", result);

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
    setupOk = [self setupSegments];
    if (!setupOk) {
        return 0x8F;
    }

    /* Set output buffer pointer to PnP buffer */
    *(void **)buffer = _kData;

    /* Reset argument stack */
    [_argStack reset];

    /* Push arguments for PnP BIOS function 0x40 (Get Static Allocation Resource Information) */
    [_argStack push:_biosSelector];
    [_argStack pushFarPtr:_kData];
    [_argStack push:0x40];  /* Function 0x40 */

    /* Call PnP BIOS */
    result = call_bios(_bb);

    IOLog("PnPBios: GetPnPConfig result: 0x%x\n", result);

    /* Release segments */
    [self releaseSegments];

    return result;
}

/*
 * Setup segments for PnP BIOS calls
 *
 * This function temporarily reprograms GDT entries 16-19 to create
 * selectors for the PnP BIOS 16-bit code, 32-bit data, the kernel
 * data buffer, and the 32-bit PM trampoline.
 */
- setupSegments
{
    unsigned char *gdtBase;
    unsigned int base;
    unsigned int bufferBase = 0;
    unsigned int trampolineBase = 0;
    BiosCallData *callData = (BiosCallData *)_bb;
    GDTEntry *entryPnPCode16;
    GDTEntry *entryKData;
    GDTEntry *entryPnPData32;
    GDTEntry *entryPnPTrampoline;
    unsigned int *entryWords;

    /* Get pointer to GDT as byte array for offset calculations */
    gdtBase = (unsigned char *)gdt;

    /* Get GDT entry pointers using their selector values as offsets */
    entryPnPCode16 = (GDTEntry *)(gdtBase + PNP_CODE16_SEL);      /* 0x80 */
    entryKData = (GDTEntry *)(gdtBase + PNP_KDATA_SEL);       /* 0x88 */
    entryPnPData32 = (GDTEntry *)(gdtBase + PNP_DATA32_SEL);      /* 0x90 */
    entryPnPTrampoline = (GDTEntry *)(gdtBase + PNP_TRAMPOLINE_SEL);  /* 0x98 */

    /*
     * Save existing GDT entries (8 bytes each)
     */
    entryWords = (unsigned int *)entryPnPCode16;
    _saveGDTBiosCode[0] = entryWords[0];
    _saveGDTBiosCode[1] = entryWords[1];

    entryWords = (unsigned int *)entryPnPData32;
    _saveGDTBiosEntry[0] = entryWords[0];
    _saveGDTBiosEntry[1] = entryWords[1];

    entryWords = (unsigned int *)entryPnPTrampoline;
    _saveGDTKData[0] = entryWords[0];
    _saveGDTKData[1] = entryWords[1];

    entryWords = (unsigned int *)entryKData;
    _saveGDTBiosData[0] = entryWords[0];
    _saveGDTBiosData[1] = entryWords[1];

    /*
     * Setup GDT 16 (PNP_CODE16_SEL) - 16-bit code segment
     * Base: _biosCodeSegAddr, Limit: 0xFFFF
     */
    base = _biosCodeSegAddr;
    entryPnPCode16->limitLow = 0xFFFF;
    entryPnPCode16->baseLow = (unsigned short)base;
    entryPnPCode16->baseMid = (unsigned char)(base >> 16);
    entryPnPCode16->baseHigh = (unsigned char)(base >> 24);
    entryPnPCode16->access = (entryPnPCode16->access & 0xE0) | 0x1A; /* type = 16-bit code */
    entryPnPCode16->access = (entryPnPCode16->access & 0x9F);  /* DPL = ring 0 */
    entryPnPCode16->access |= 0x80; /* P = 1 (present) */
    entryPnPCode16->flagsLimitHigh &= 0xBF; /* D/B = 0 (16-bit) */
    entryPnPCode16->flagsLimitHigh &= 0xF0; /* G = 0 (byte granular) */
    entryPnPCode16->flagsLimitHigh &= 0x7F; /* AVL = 0 */

    /*
     * Setup GDT 18 (PNP_DATA32_SEL) - 32-bit data segment
     * Base: _dataSegAddr, Limit: 0xFFFF
     */
    base = _dataSegAddr;
    entryPnPData32->limitLow = 0xFFFF;
    entryPnPData32->baseLow = (unsigned short)base;
    entryPnPData32->baseMid = (unsigned char)(base >> 16);
    entryPnPData32->baseHigh = (unsigned char)(base >> 24);
    entryPnPData32->access = (entryPnPData32->access & 0xE0) | 0x12; /* type = data, W */
    entryPnPData32->access = (entryPnPData32->access & 0x9F); /* DPL = ring 0 */
    entryPnPData32->access |= 0x80; /* P = 1 */
    entryPnPData32->flagsLimitHigh |= 0x40; /* D/B = 1 (32-bit) */
    entryPnPData32->flagsLimitHigh &= 0xF0; /* G = 0 (byte granular) */
    entryPnPData32->flagsLimitHigh &= 0x7F; /* AVL = 0 */
    entryPnPData32->flagsLimitHigh &= 0xBF; /* L = 0 */

    /* Set _biosSelector to the 32-bit PnP data segment */
    _biosSelector = PNP_DATA32_SEL; /* 0x90 */

    /*
     * Setup GDT 19 (PNP_TRAMPOLINE_SEL) - Trampoline segment
     * Base: (address of _PnPEntry), Limit: 0xFFFF
     */
    trampolineBase = (unsigned int)&_PnPEntry;
    entryPnPTrampoline->limitLow = 0xFFFF;
    entryPnPTrampoline->baseLow = (unsigned short)trampolineBase;
    entryPnPTrampoline->baseMid = (unsigned char)(trampolineBase >> 16);
    entryPnPTrampoline->baseHigh = (unsigned char)(trampolineBase >> 24);
    entryPnPTrampoline->access = (entryPnPTrampoline->access & 0xE0) | 0x1A;
    entryPnPTrampoline->access = (entryPnPTrampoline->access & 0x9F);
    entryPnPTrampoline->access |= 0x80;
    entryPnPTrampoline->flagsLimitHigh |= 0x40;
    entryPnPTrampoline->flagsLimitHigh &= 0xF0;
    entryPnPTrampoline->flagsLimitHigh &= 0x7F;

    /*
     * Setup GDT 17 (PNP_KDATA_SEL) - Kernel buffer segment
     * Base: _kData - 0x40000000, Limit: 0xFFFF
     */
    bufferBase = (unsigned int)_kData - 0x40000000;
    entryKData->limitLow = 0xFFFF;
    entryKData->baseLow = (unsigned short)bufferBase;
    entryKData->baseMid = (unsigned char)(bufferBase >> 16);
    entryKData->baseHigh = (unsigned char)(bufferBase >> 24);
    entryKData->access = (entryKData->access & 0xE0) | 0x12;
    entryKData->access = (entryKData->access & 0x9F);
    entryKData->access |= 0x80;
    entryKData->flagsLimitHigh |= 0x40;
    entryKData->flagsLimitHigh &= 0xF0;
    entryKData->flagsLimitHigh &= 0x7F;
    entryKData->flagsLimitHigh &= 0xBF;

    /* Set _kDataSelector to the kernel buffer segment */
    _kDataSelector = PNP_KDATA_SEL; /* 0x88 */

    /* Clear the bios call data struct */
    bzero(callData, sizeof(BiosCallData));

    /* Set the far call target to the PnP PM Trampoline */
    callData->far_seg    = PNP_TRAMPOLINE_SEL; /* 0x98 - PnP Trampoline */
    callData->far_offset = 0;

    /* Set the Data Segment for the 16-bit call (Kernel Data Segment) */
    callData->ds_seg = PNP_KDS_SEL; /* 0x10 */

    /* Set global PnP entry point variables (used by the trampoline) */
    PnPEntry_biosCodeSelector = PNP_CODE16_SEL; /* 0x80 */
    PnPEntry_biosCodeOffset = (unsigned int)_biosEntryOffset;
    kernDataSel = PNP_KDS_SEL; /* 0x10 */

    /* Set global PnP 16-bit stack variables */
    PnPEntry_pmStackSel = _pmStackSel;
    PnPEntry_pmStackOff = (unsigned int)_pmStackOff; /* Zero-extend 16-bit offset */

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
    unsigned char *gdtBase;
    GDTEntry *entryPnPCode16;
    GDTEntry *entryKData;
    GDTEntry *entryPnPData32;
    GDTEntry *entryPnPTrampoline;
    unsigned int *entryWords;

    /* Get pointer to GDT as byte array for offset calculations */
    gdtBase = (unsigned char *)gdt;

    /* Get GDT entry pointers using their selector values as offsets */
    entryPnPCode16 = (GDTEntry *)(gdtBase + PNP_CODE16_SEL);      /* 0x80 - PnP 16-bit Code */
    entryKData = (GDTEntry *)(gdtBase + PNP_KDATA_SEL);           /* 0x88 - Kernel Buffer */
    entryPnPData32 = (GDTEntry *)(gdtBase + PNP_DATA32_SEL);      /* 0x90 - 32-bit PnP Data */
    entryPnPTrampoline = (GDTEntry *)(gdtBase + PNP_TRAMPOLINE_SEL);  /* 0x98 - PnP Trampoline */

    /* Restore selector PNP_CODE16_SEL (PnP 16-bit Code) */
    entryWords = (unsigned int *)entryPnPCode16;
    entryWords[0] = _saveGDTBiosCode[0];
    entryWords[1] = _saveGDTBiosCode[1];

    /* Restore selector PNP_DATA32_SEL (PnP 32-bit Data) */
    entryWords = (unsigned int *)entryPnPData32;
    entryWords[0] = _saveGDTBiosEntry[0];
    entryWords[1] = _saveGDTBiosEntry[1];

    /* Restore selector PNP_TRAMPOLINE_SEL (PnP Trampoline) */
    entryWords = (unsigned int *)entryPnPTrampoline;
    entryWords[0] = _saveGDTKData[0];
    entryWords[1] = _saveGDTKData[1];

    /* Restore selector PNP_KDATA_SEL (Kernel Buffer) */
    entryWords = (unsigned int *)entryKData;
    entryWords[0] = _saveGDTBiosData[0];
    entryWords[1] = _saveGDTBiosData[1];

    IOLog("PnPBios: releaseSegments end\n");

    return self;
}

@end
