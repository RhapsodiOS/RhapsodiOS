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

/* kernel GDT access */
#import <architecture/i386/table.h>
#import <machdep/i386/gdt.h>
#import <machdep/i386/seg.h>
#import <machdep/i386/sel_inline.h>
#import <machdep/i386/table_inline.h>
#import <machdep/i386/desc_inline.h>
#import <machdep/i386/pmap.h>

/*
 * PnP BIOS Call Chain
 * =================================================
 *
 * Each of the three PnP BIOS calls below follows the same shape:
 *
 * 1. [self setupSegments]
 *    Saves the current GDT[16..19], installs the four descriptors this call
 *    needs, programs the globals the assembler thunk reads, zeroes the
 *    register block, and lazily creates the PnPArgStack.
 *
 * 2. [_argStack reset], then one push per argument word.
 *    The PnP BIOS Specification v1.0a passes arguments as 16-bit words in
 *    the ordinary C order - last parameter pushed first - so BiosSelector
 *    goes on first and the function number goes on last, ending up directly
 *    beneath the far return address.  The word count is per-function
 *    (4 for function 0x40, 6 for 0x00, 7 for 0x01); PnPArgStack tracks it
 *    and bios_rtn pops exactly that many words afterwards.
 *
 * 3. call_bios(&_bb)  [bios.c]
 *    Runs the 32-bit -> PM16 -> BIOS -> back transition with interrupts
 *    disabled.  See the block comment in bios.c for the instruction-level
 *    story; the whole apparatus lives there.
 *
 * 4. [self releaseSegments]
 *    Puts GDT[16..19] back exactly as they were.
 *
 * GDT configuration installed per call by -setupSegments:
 * - GDT 16 (0x80): 16-bit code   -> pm16cseg  (the BIOS's own code segment)
 * - GDT 17 (0x88): 16-bit data   -> _kData    (our 64KB transfer buffer)
 * - GDT 18 (0x90): 16-bit data   -> pm16dseg  (the BIOS's own data segment;
 *                                  its selector is the BiosSelector argument)
 * - GDT 19 (0x98): 32-bit code   -> _PnPEntry (aliases the thunk to offset 0)
 *
 * WHY GDT 19 IS CRITICAL:
 * The 16-bit BIOS returns with a far return that only pops a 16-bit IP.  By
 * giving GDT 19 a base of _PnPEntry, the thunk appears at offset 0 of that
 * segment, so the return offset _PnPEntry pushes (bios_rtn - _PnPEntry, a
 * little over 100 bytes) fits in 16 bits regardless of where the driver was
 * actually loaded.
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
#define PNP_DATA32_SEL          (18 << 3)  /* 0x90 - 16-bit PnP Data (Index 18) */
#define PNP_CS32_SEL            (19 << 3)  /* 0x98 - _PnPEntry alias (Index 19) */

/* Returned by the three call methods when -setupSegments fails. */
#define PNP_STATUS_SETUP_FAILED 0x8F

/*
PnP BIOS Function Codes

0x00 - Get Number of System Device Nodes
0x01 - Get Device Node
0x40 - Get Static Allocation Resource Information
0x41 - Get Dynamic Allocation Resource Information
0x42 - Get Resource Allocation Conflict Information
*/
#define PNP_FC_GET_NUM_NODES                                    0x00
#define PNP_FC_GET_DEVICE_NODE                                  0x01
#define PNP_FC_GET_STATIC_ALLOCATION_RESOURCE_INFORMATION       0x40
#define PNP_FC_GET_DYNAMIC_ALLOCATION_RESOURCE_INFORMATION      0x41
#define PNP_FC_GET_RESOURCE_ALLOCATION_CONFLICT_INFORMATION     0x42

typedef struct {
    unsigned short limitLow;
    unsigned short baseLow;
    unsigned char baseMid;
    unsigned char access;
    unsigned char flagsLimitHigh;
    unsigned char baseHigh;
} GDTEntry;

@implementation PnPBios

/*
 * Present - Check if PnP BIOS is present in the system
 *
 * Searches BIOS ROM area (0xF0000 to 0xFFFF0) for PnP installation check structure.
 *
 * @param pnpStructPtr  Pointer to store the found PnP BIOS structure
 * @return YES if valid PnP BIOS found, NO otherwise
 *
 * Validation performed:
 * 1. Signature check ("$PnP")
 * 2. Length field validation
 * 3. Checksum verification (sum of all bytes must equal 0)
 * 4. Version check (must be >= 1.0)
 */
+ (BOOL)Present:(void **)pnpStructPtr
{
    pnp_bios_install_struct *check;
    unsigned char sum;
    int i;
    unsigned char length;
    unsigned char version;

    /* Scan BIOS ROM from 0xF0000 to 0xFFFF0 in 16-byte increments */
    for (check = (pnp_bios_install_struct *)0xF0000;
         check < (pnp_bios_install_struct *)0xFFFF0;
         check = (pnp_bios_install_struct *)((unsigned char *)check + 0x10))
    {
        /* Check for "$PnP" signature (0x506E5024) */
        if (check->fields.signature != PNP_SIGNATURE)
            continue;

        /* Validate structure length */
        length = check->fields.length;
        if (length == 0) {
            IOLog("PnPBios: Found signature at 0x%08x but invalid length (0)\n",
                  (unsigned int)check);
            continue;
        }

        /* Calculate checksum - sum of all bytes should be 0 */
        sum = 0;
        for (i = 0; i < length; i++) {
            sum += check->bytes[i];
        }

        if (sum != 0) {
            IOLog("PnPBios: Found signature at 0x%08x but checksum failed (0x%02x)\n",
                  (unsigned int)check, sum);
            continue;
        }

        /* Validate version (must be >= 1.0) */
        version = check->fields.version;
        if (version < 0x10) {
            IOLog("PnPBios: Found PnP BIOS v%x.%x at 0x%08x, but need >= v1.0\n",
                  version >> 4, version & 0x0F, (unsigned int)check);
            continue;
        }

        /* All validation passed */
#ifdef PNPBIOSDEBUG
        IOLog("PnPBios: Found valid PnP BIOS v%x.%x at 0x%08x\n",
              version >> 4, version & 0x0F, (unsigned int)check);
        IOLog("PnPBios: Length: 0x%02x, Control: 0x%04x\n",
              length, check->fields.control);
#endif

        *pnpStructPtr = check;
        return YES;
    }

    return NO;
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
 *
 * Improved initialization based on Linux's approach:
 * - Better validation of PnP BIOS structure
 * - More detailed logging of BIOS configuration
 * - Simplified buffer allocation
 */
- init
{
    BOOL present;

    /* Call superclass init */
    [super init];

    /* Initialize instance variables */
    _argStack = nil;
    _kData = NULL;
    _pnpBios = NULL;

    /* Probe for PnP BIOS */
    present = [PnPBios Present:(void **)&_pnpBios];
    if (!present) {
        IOLog("PnPBios: PnP BIOS not detected\n");
        return [self free];
    }

#ifdef PNPBIOSDEBUG
    /*
     * Extract entry points from PnP BIOS installation structure
     *
     * Following Linux's approach, we use the protected-mode 16-bit entry point:
     * - PM16 code segment base address (NOT real-mode segment)
     * - PM16 entry offset
     * - PM16 data segment base address
     */
    /* Debug: dump the raw structure bytes */
    {
        unsigned char *raw = (unsigned char *)_pnpBios;
        int i;
        IOLog("PnPBios DEBUG: Structure bytes at 0x%08x:\n", (unsigned int)_pnpBios);
        for (i = 0; i < 0x21; i++) {
            if ((i % 16) == 0)
                IOLog("  %02x: ", i);
            IOLog("%02x ", raw[i]);
            if ((i % 16) == 15 || i == 0x20)
                IOLog("\n");
        }
    }
#endif

    /* Read from structure fields - we have #pragma pack(1) so no padding */
    _biosEntryOffset = _pnpBios->fields.pm16offset;
    _biosCodeSegAddr = _pnpBios->fields.pm16cseg;
    _dataSegAddr = _pnpBios->fields.pm16dseg;

#ifdef PNPBIOSDEBUG
    IOLog("PnPBios DEBUG: Struct field reads:\n");
    IOLog("  pm16offset: 0x%04x\n", _biosEntryOffset);
    IOLog("  pm16cseg: 0x%08x\n", _biosCodeSegAddr);
    IOLog("  pm16dseg: 0x%08x\n", _dataSegAddr);

    /* Log PnP BIOS configuration - read from structure fields */
    {
        unsigned char version = _pnpBios->fields.version;
        unsigned short control = _pnpBios->fields.control;
        unsigned int deviceID = _pnpBios->fields.deviceID;

        IOLog("PnPBios: Version %x.%x, Control=0x%04x\n",
              version >> 4, version & 0x0F, control);

        IOLog("PnPBios: PM16 entry point: CS=0x%08x:0x%04x, DS=0x%08x\n",
              _biosCodeSegAddr, _biosEntryOffset, _dataSegAddr);

        if (deviceID != 0) {
            IOLog("PnPBios: Device ID: 0x%08x\n", deviceID);
        }
    }
#endif

    /* Allocate 64KB buffer for PnP BIOS data transfers */
    _kData = IOMalloc(0x10000);
    if (_kData == NULL) {
        IOLog("PnPBios: Failed to allocate kernel buffer\n");
        return [self free];
    }

#if 1
    /* Test BIOS call with Function 0x00 (Get Number of Nodes) */
    {
        int numNodes, maxNodeSize;
        int testResult;

        IOLog("PnPBios: Testing BIOS calls with GetNumNodes (func=0x00)...\n");
        testResult = [self getNumNodes:&numNodes AndSize:&maxNodeSize];

        if (testResult == 0) {
            IOLog("PnPBios: SUCCESS! GetNumNodes returned: numNodes=%d, maxNodeSize=%d\n",
                  numNodes, maxNodeSize);
        } else {
            IOLog("PnPBios: GetNumNodes returned error 0x%02x\n", testResult);
        }
    }
#endif

    /* Successfully initialized */
    IOLog("PnPBios: Initialization successful\n");
    return self;
}

/*
 * Free PnP BIOS resources
 */
- free
{
    /* Free allocated buffer */
    if (_kData != NULL) {
        IOFree(_kData, 0x10000);
        _kData = NULL;
    }

    /* Free the lazily-created argument stack */
    if (_argStack != nil) {
        [_argStack free];
        _argStack = nil;
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
    int result;

    if (![self setupSegments]) {
        return PNP_STATUS_SETUP_FAILED;
    }

    /*
     * GetSystemDeviceNode(Function, NodeNumber far *, NodeBuffer far *,
     *                     Control, BiosSelector) - 7 words.
     * The node number is handed to the BIOS in the first byte of the
     * transfer buffer and the node itself comes back just after it.
     */
    pnpBuf = (unsigned char *)_kData;
    pnpBuf[0] = (unsigned char)handle;

    [_argStack reset];
    [_argStack push:_biosSelector];
    [_argStack push:1];                     /* Control: 1 = current config */
    [_argStack pushFarPtr:pnpBuf + 2];      /* NodeBuffer */
    [_argStack pushFarPtr:pnpBuf];          /* NodeNumber */
    [_argStack push:PNP_FC_GET_DEVICE_NODE];

    *buffer = pnpBuf + 2;

    IOLog("PnPBios: Calling GetDeviceNode (handle=0x%02x)\n", handle);

    result = call_bios(&_bb);

    [self releaseSegments];

    IOLog("PnPBios: GetDeviceNode result: 0x%x\n", result);

    return result;
}


/*
 * Get number of nodes and maximum node size
 */
- (int)getNumNodes:(int *)numNodes AndSize:(int *)maxNodeSize
{
    unsigned char *pnpBuf;
    int result;

    if (![self setupSegments]) {
        return PNP_STATUS_SETUP_FAILED;
    }

    /*
     * GetNumberOfSystemDeviceNodes(Function, NumberOfNodes far *,
     *                              NodeSize far *, BiosSelector) - 6 words.
     * Pushed last-parameter-first, so the deeper far pointer is NodeSize
     * (a word, written at buffer+0) and the shallower one is
     * NumberOfNodes (a byte, written at buffer+2).
     */
    pnpBuf = (unsigned char *)_kData;

    [_argStack reset];
    [_argStack push:_biosSelector];
    [_argStack pushFarPtr:pnpBuf];          /* NodeSize */
    [_argStack pushFarPtr:pnpBuf + 2];      /* NumberOfNodes */
    [_argStack push:PNP_FC_GET_NUM_NODES];

    IOLog("PnPBios: Calling GetNumNodes\n");

    result = call_bios(&_bb);

    /* Copy results from buffer */
    *maxNodeSize = (int)*(unsigned short *)pnpBuf;
    *numNodes = (int)pnpBuf[2];

    [self releaseSegments];

    IOLog("PnPBios: GetNumNodes result: 0x%x\n", result);

    return result;
}


/*
 * Get PnP configuration
 */
- (int)getPnPConfig:(void **)buffer
{
    int result;

    if (![self setupSegments]) {
        return PNP_STATUS_SETUP_FAILED;
    }

    /* Set output buffer pointer to PnP buffer */
    *buffer = _kData;

    /*
     * PnPConfigStructure(Function, Structure far *, BiosSelector) - 4 words.
     */
    [_argStack reset];
    [_argStack push:_biosSelector];
    [_argStack pushFarPtr:*buffer];
    [_argStack push:PNP_FC_GET_STATIC_ALLOCATION_RESOURCE_INFORMATION];

    IOLog("PnPBios: Calling GetPnPConfig (func=0x40, BiosSelector=0x%02x)\n",
          _biosSelector);

    result = call_bios(&_bb);

    [self releaseSegments];

    IOLog("PnPBios: GetPnPConfig returned, result=0x%x\n", result);

    return result;
}



/*
 * Setup segments for one PnP BIOS call.
 *
 * Called immediately before every call and undone by -releaseSegments
 * immediately after (reconstruction/divergences.md Finding 2).
 *
 * GDT Entries:
 * - GDT 16 (PNP_CODE16_SEL=0x80): 16-bit code segment for BIOS
 * - GDT 17 (PNP_KDATA_SEL=0x88): 16-bit data segment for kernel buffer
 * - GDT 18 (PNP_DATA32_SEL=0x90): 16-bit data segment for BIOS data
 * - GDT 19 (PNP_CS32_SEL=0x98): 32-bit code segment alias for _PnPEntry
 */
- (BOOL)setupSegments
{
    unsigned char *gdtBase;
    unsigned int base;
    GDTEntry *entryPnPCode16;
    GDTEntry *entryKData;
    GDTEntry *entryPnPData32;
    GDTEntry *entryPnPCS32;

    /* Get pointer to GDT */
    gdtBase = (unsigned char *)gdt;

    /* Get GDT entry pointers */
    entryPnPCode16 = (GDTEntry *)(gdtBase + PNP_CODE16_SEL);   /* 0x80 */
    entryKData = (GDTEntry *)(gdtBase + PNP_KDATA_SEL);         /* 0x88 */
    entryPnPData32 = (GDTEntry *)(gdtBase + PNP_DATA32_SEL);   /* 0x90 */
    entryPnPCS32 = (GDTEntry *)(gdtBase + PNP_CS32_SEL);       /* 0x98 */

    /*
     * Save the pre-existing contents of GDT[16..19] before overwriting them,
     * so -releaseSegments can restore them after the BIOS call completes
     * (see reconstruction/divergences.md Finding 2).
     */
    memcpy(_saveGDTBiosCode, entryPnPCode16, sizeof(GDTEntry));
    memcpy(_saveGDTBiosEntry, entryPnPData32, sizeof(GDTEntry));
    memcpy(_saveGDTBiosData, entryKData, sizeof(GDTEntry));
    memcpy(_saveGDTKData, entryPnPCS32, sizeof(GDTEntry));

    /*
     * Setup GDT 16 (PNP_CODE16_SEL) - 16-bit code segment for BIOS
     * Base: _biosCodeSegAddr (pm16cseg from PnP BIOS structure)
     * Limit: 0xFFFF (64KB), Granularity: byte, Size: 16-bit
     */
    base = _biosCodeSegAddr;
    entryPnPCode16->limitLow = 0xFFFF;
    entryPnPCode16->baseLow = (unsigned short)base;
    entryPnPCode16->baseMid = (unsigned char)(base >> 16);
    entryPnPCode16->baseHigh = (unsigned char)(base >> 24);
    entryPnPCode16->access = 0x9A;          /* P=1, DPL=0, S=1, Type=1010 (Code, Execute/Read) */
    entryPnPCode16->flagsLimitHigh = 0x00;  /* G=0 (byte), D/B=0 (16-bit), L=0, AVL=0 */

    /*
     * Setup GDT 18 (PNP_DATA32_SEL) - 16-bit data segment for BIOS data
     * Base: _dataSegAddr (pm16dseg from PnP BIOS structure)
     * Limit: 0xFFFF (64KB), Granularity: byte, Size: 16-bit
     *
     * This descriptor's selector is the BiosSelector argument every PnP
     * BIOS function takes as its last parameter.
     */
    base = _dataSegAddr;
    entryPnPData32->limitLow = 0xFFFF;
    entryPnPData32->baseLow = (unsigned short)base;
    entryPnPData32->baseMid = (unsigned char)(base >> 16);
    entryPnPData32->baseHigh = (unsigned char)(base >> 24);
    entryPnPData32->access = 0x92;          /* P=1, DPL=0, S=1, Type=0010 (Data, Read/Write) */
    entryPnPData32->flagsLimitHigh = 0x00;  /* G=0 (byte), D/B=0 (16-bit), L=0, AVL=0 */

    _biosSelector = PNP_DATA32_SEL;

    /*
     * Setup GDT 17 (PNP_KDATA_SEL) - 16-bit data segment for our buffer
     * Base: _kData (our allocated 64KB buffer)
     * Limit: 0xFFFF (64KB), Granularity: byte, Size: 16-bit
     *
     * This is the segment half of every far pointer PnPArgStack pushes, so
     * the 16-bit BIOS dereferences it; it must be a 16-bit descriptor.
     */
    base = (unsigned int)_kData;
    entryKData->limitLow = 0xFFFF;
    entryKData->baseLow = (unsigned short)base;
    entryKData->baseMid = (unsigned char)(base >> 16);
    entryKData->baseHigh = (unsigned char)(base >> 24);
    entryKData->access = 0x92;              /* P=1, DPL=0, S=1, Type=0010 (Data, Read/Write) */
    entryKData->flagsLimitHigh = 0x00;      /* G=0 (byte), D/B=0 (16-bit), L=0, AVL=0 */

    /*
     * Setup GDT 19 (PNP_CS32_SEL) - 32-bit code segment alias for _PnPEntry
     * Base: address of _PnPEntry
     * Limit: 0xFFFF (64KB), Granularity: byte, Size: 32-bit
     *
     * This segment makes _PnPEntry appear at offset 0, so the 16-bit far
     * return address it pushes for the BIOS fits in 16 bits.
     */
    base = (unsigned int)_PnPEntry;
    entryPnPCS32->limitLow = 0xFFFF;
    entryPnPCS32->baseLow = (unsigned short)base;
    entryPnPCS32->baseMid = (unsigned char)(base >> 16);
    entryPnPCS32->baseHigh = (unsigned char)(base >> 24);
    entryPnPCS32->access = 0x9A;            /* P=1, DPL=0, S=1, Type=1010 (Code, Execute/Read) */
    entryPnPCS32->flagsLimitHigh = 0x40;    /* G=0 (byte), D/B=1 (32-bit), L=0, AVL=0 */

    /* Save selector values for later use */
    _kDataSelector = PNP_KDATA_SEL;

    /*
     * Program the globals the assembler thunk reads.  _PnPEntry patches the
     * BIOS entry point into its own far jump from these two; _bios32PnP
     * restores DS from kernDataSel after the BIOS returns.
     */
    PnPEntry_biosCodeSelector = PNP_CODE16_SEL;
    PnPEntry_biosCodeOffset = _biosEntryOffset;
    kernDataSel = PNP_KDS_SEL;

    /*
     * Set up the register block.  _bios32PnP far-calls entrySel:entryOffset,
     * which is _PnPEntry at offset 0 of its GDT 19 alias, and loads dataSel
     * into DS beforehand so the thunk can reach its own globals.
     */
    memset(&_bb, 0, sizeof(_bb));
    _bb.entrySel = PNP_CS32_SEL;
    _bb.entryOffset = 0;
    _bb.dataSel = PNP_KDS_SEL;

    /* Create the argument stack once, on first use. */
    if (_argStack == nil) {
        _argStack = [[PnPArgStack alloc] initWithData:_kData
                                             Selector:_kDataSelector];
        if (_argStack == nil) {
            IOLog("PnPBios: PnPArgStack init failed\n");
            return NO;
        }
    }

    return YES;
}

/*
 * Restore the GDT[16..19] entries saved by -setupSegments.
 *
 * Called immediately after each PnP BIOS call, undoing exactly the four
 * installs -setupSegments performs (GDT 20, our own dedicated 16-bit stack
 * segment, has no reference counterpart and is left alone -- see
 * reconstruction/divergences.md Finding 2).
 */
- releaseSegments
{
    unsigned char *gdtBase;
    GDTEntry *entryPnPCode16;
    GDTEntry *entryKData;
    GDTEntry *entryPnPData32;
    GDTEntry *entryPnPCS32;

    gdtBase = (unsigned char *)gdt;

    entryPnPCode16 = (GDTEntry *)(gdtBase + PNP_CODE16_SEL);   /* 0x80 */
    entryKData = (GDTEntry *)(gdtBase + PNP_KDATA_SEL);         /* 0x88 */
    entryPnPData32 = (GDTEntry *)(gdtBase + PNP_DATA32_SEL);   /* 0x90 */
    entryPnPCS32 = (GDTEntry *)(gdtBase + PNP_CS32_SEL);       /* 0x98 */

    memcpy(entryPnPCode16, _saveGDTBiosCode, sizeof(GDTEntry));
    memcpy(entryPnPData32, _saveGDTBiosEntry, sizeof(GDTEntry));
    memcpy(entryKData, _saveGDTBiosData, sizeof(GDTEntry));
    memcpy(entryPnPCS32, _saveGDTKData, sizeof(GDTEntry));

    return self;
}

@end
