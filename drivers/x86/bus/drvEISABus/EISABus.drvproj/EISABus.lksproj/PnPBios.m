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
#import <machdep/i386/pmap.h>

/*
 * PnP BIOS Call Chain
 * =================================================
 *
 * Call flow from Objective-C to 16-bit PnP BIOS and back:
 *
 * 1. Objective-C methods (getPnPConfig, getDeviceNode, getNumNodes)
 *    - Call setupSegments() to configure GDT entries 16-19
 *    - Build arguments using PnPArgStack:
 *      [argStack reset]
 *      [argStack push: value]           // Push 16-bit values
 *      [argStack pushFarPtr: ptr]       // Push seg:offset pairs
 *    - PnPArgStack updates globals: PnPEntry_argStackBase, PnPEntry_numArgs
 *    ↓
 *    Call call_bios(&bb) with pointer to BIOSCallStruct
 *
 * 2. call_bios() [bios.c]
 *    - Takes BIOSCallStruct *bb containing all parameters
 *    - Calls __bios32PnP(bb) assembly trampoline
 *    - Returns bb->eax (BIOS status code)
 *    ↓
 *
 * 3. __bios32PnP() [biospnp.s - assembly trampoline]
 *    - Saves all registers (pusha) and segment registers (ES, FS, GS)
 *    - Loads input registers from BIOSCallStruct:
 *      EBX = bb->ebx, ECX = bb->ecx, EDX = bb->edx
 *      EDI = bb->edi, ESI = bb->esi, EAX = bb->eax
 *    - Loads DS from bb->ds (segment selector for BIOS data)
 *    - Disables interrupts (cli)
 *    - Executes far call: .byte 0x9A + bb->addr + bb->cs
 *      (Far call to bb->cs:bb->addr, typically PNP_CODE16_SEL:biosEntryOffset)
 *    ↓
 *
 * 4. 16-bit PnP BIOS [runs in GDT 16 @ biosCodeSegAddr]
 *    - Receives arguments via __PnPEntry stack mechanism (see below)
 *    - Executes BIOS function
 *    - Returns EAX = status code, other registers = output values
 *    - Performs far return back to __bios32PnP
 *    ↓
 *
 * 5. __bios32PnP() [resumes after far call]
 *    - Saves EFLAGS and output registers
 *    - Restores kernel DS (from kernDataSel)
 *    - Writes results back to BIOSCallStruct:
 *      bb->eax = EAX, bb->ebx = EBX, bb->ecx = ECX, etc.
 *    - Restores segment registers (ES, FS, GS) and general registers (popa)
 *    - Returns to call_bios()
 *    ↓
 *
 * 6. call_bios() [resumes in bios.c]
 *    - Reads bb->eax and returns it as status code
 *    ↓
 *
 * 7. Objective-C method receives status code
 *    - Calls releaseSegments() to restore original GDT entries
 *
 * GDT Configuration (set up in setupSegments, restored in releaseSegments):
 * - GDT 16 (0x80 = PNP_CODE16_SEL): 16-bit code → biosCodeSegAddr (BIOS code)
 * - GDT 17 (0x88 = PNP_KDATA_SEL):  32-bit data → (kData - 0x40000000) (our 64KB buffer)
 * - GDT 18 (0x90 = PNP_DATA32_SEL): 32-bit data → dataSegAddr (BIOS data)
 * - GDT 19 (0x98 = PNP_CS32_SEL):   32-bit code → &__PnPEntry (for far returns)
 *
 * WHY GDT 19 (PNP_CS32_SEL) POINTS TO __PnPEntry:
 * When __PnPEntry pushes a far return address for the BIOS, it pushes:
 *   CS = current CS (will be translated to PNP_CS32_SEL)
 *   Offset = (bios_rtn - __PnPEntry)
 *
 * When the BIOS does a far RET, it calculates:
 *   Return Address = GDT_19_base + offset
 *                  = &__PnPEntry + (bios_rtn - __PnPEntry)
 *                  = bios_rtn
 *
 * By pointing GDT 19 to __PnPEntry, the relative offset in the pushed return
 * address correctly resolves to bios_rtn's actual location.
 */

/*
 * Local GDT selector values for PnP BIOS setup.
 * These map to the GDT indices (16-19) used by this driver.
 *
 * A selector value is (Index << 3) | RPL.
 * We are in kernel mode, so RPL = 0.
 */
#define PNP_CODE16_SEL          (16 << 3)  /* 0x80 - 16-bit PnP Code (Index 16) */
#define PNP_KDATA_SEL           (17 << 3)  /* 0x88 - Kernel Buffer (Index 17) */
#define PNP_DATA32_SEL          (18 << 3)  /* 0x90 - 32-bit PnP Data (Index 18) */
#define PNP_CS32_SEL            (19 << 3)  /* 0x98 - 32-bit Code @ __PnPEntry (Index 19) */

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

/* External globals for PnP BIOS */
extern unsigned short kernDataSel;
extern void *bios32PnP_ptr;

/* External verbose logging flag (defined in bios.c) */
extern char verbose;

/*
 * Assembly functions from biospnp.s
 */
extern void _bios32PnP(BIOSCallStruct *bb);
extern void _PnPEntry(void);
extern unsigned short _PnPEntry_biosCodeSelector;
extern unsigned int _PnPEntry_biosCodeOffset;

@implementation PnPBios

/*
 * Present - Check if PnP BIOS is present in the system
 *
 * Searches BIOS ROM area (0xF0000 to 0xFFFFE) for PnP installation check structure.
 *
 * @param pnpStructPtr  Pointer to store the found PnP BIOS structure
 * @return YES if valid PnP BIOS found, NO otherwise
 *
 * Validation performed:
 * 1. Signature check ("$PnP")
 * 2. Checksum verification (sum of all bytes must equal 0)
 */
+ (BOOL)Present:(void **)pnpStructPtr
{
    unsigned int i;
    pnp_bios_install_struct *candidate;
    unsigned char checksum;
    int j;

    /* Scan BIOS ROM from 0xF0000 to 0xFFFFE in 16-byte increments */
    for (i = 0xF0000; i <= 0xFFFFE; i += 16)
    {
        candidate = (pnp_bios_install_struct *)i;

        /* Check for "$PnP" signature using strncmp */
        if (strncmp((const char *)i, "$PnP", 4) != 0)
            continue;

        /* Calculate checksum - sum of all bytes in structure */
        checksum = 0;
        if (candidate->fields.length != 0) {
            for (j = 0; j < candidate->fields.length; j++) {
                checksum += candidate->bytes[j];
            }
        }

        /* If checksum is 0, we found a valid structure */
        if (checksum == 0) {
            *pnpStructPtr = (void *)candidate;
            return YES;
        }
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
 */
- init
{
    IOLog("PnPBios: init - entering\n");

    [super init];

    /* Initialize instance variables to NULL */
    argStack = nil;
    kData = NULL;

    /* Probe for PnP BIOS, store pointer in installCheck_p */
    IOLog("PnPBios: init - probing for PnP BIOS\n");
    if (![PnPBios Present:(void **)&installCheck_p]) {
        IOLog("PnPBios: PnP BIOS not detected\n");
        return [self free];
    }

    IOLog("PnPBios: init - PnP BIOS found at 0x%x\n", installCheck_p);

    /* Read entry point information from installation check structure */
    biosEntryOffset = installCheck_p->fields.pm16offset;   /* 16-bit PM entry point offset */
    biosCodeSegAddr = installCheck_p->fields.pm16cseg;     /* 16-bit PM code segment base */
    dataSegAddr = installCheck_p->fields.pm16dseg;         /* 16-bit PM data segment base */

    IOLog("PnPBios: init - biosEntryOffset=0x%x biosCodeSegAddr=0x%x dataSegAddr=0x%x\n",
          biosEntryOffset, biosCodeSegAddr, dataSegAddr);

    /* Allocate 64KB buffer for PnP BIOS data transfers */
    IOLog("PnPBios: init - allocating 64KB buffer\n");
    kData = IOMalloc(0x10000);
    if (kData == NULL) {
        IOLog("PnPBios: IOMalloc failed\n");
        return [self free];
    }

    IOLog("PnPBios: init - buffer allocated at 0x%x\n", kData);
    IOLog("PnPBios: init - completed successfully\n");

    /* Successfully initialized */
    return self;
}

/*
 * Free PnP BIOS resources
 */
- free
{
    /* Free allocated buffer */
    if (kData != NULL) {
        IOFree(kData, 0x10000);
    }

    /* Free argument stack if allocated */
    if (argStack != nil) {
        [argStack free];
    }

    /* Call superclass free and return its result */
    return [super free];
}

/*
 * Get device node information
 *
 * Retrieves configuration information for a specific PnP device node.
 *
 * @param buffer   Pointer to receive the address of the device node data
 * @param handle   Device node handle to query
 * @return         BIOS return code (0 = success)
 */
- (int)getDeviceNode:(void **)buffer ForHandle:(int)handle
{
    int bufferAddr;
    int result;

    IOLog("PnPBios: getDeviceNode - entering, handle=0x%x\n", handle);

    /* Setup GDT segments for BIOS call */
    if (![self setupSegments]) {
        IOLog("PnPBios: getDeviceNode - setupSegments failed\n");
        return 143;  /* DMI_INVALID_HANDLE or error code */
    }

    IOLog("PnPBios: getDeviceNode - setupSegments succeeded\n");

    /* Get buffer address */
    bufferAddr = (int)kData;
    IOLog("PnPBios: getDeviceNode - bufferAddr=0x%x\n", bufferAddr);

    /* Store handle as first byte in buffer */
    *(unsigned char *)bufferAddr = (unsigned char)handle;

    /* Reset argument stack and build arguments */
    IOLog("PnPBios: getDeviceNode - building arguments\n");
    [argStack reset];
    [argStack push:kDataSelector];              /* DS segment selector */
    [argStack push:PNP_FC_GET_DEVICE_NODE];     /* Function 0x01 */
    [argStack pushFarPtr:(void *)(bufferAddr + 2)];  /* ES:BX = buffer+2 */
    [argStack pushFarPtr:(void *)bufferAddr];   /* CX:DI = buffer */
    [argStack push:1];                          /* Control flag */

    /* Set output buffer pointer (skip first 2 bytes) */
    *buffer = (void *)(bufferAddr + 2);

    IOLog("PnPBios: getDeviceNode - calling BIOS function 0x01\n");

    /* Call BIOS with bb structure */
    result = call_bios(&bb);

    IOLog("PnPBios: getDeviceNode - BIOS returned 0x%x\n", result);

    /* Release GDT segments */
    [self releaseSegments];

    IOLog("PnPBios: getDeviceNode - completed\n");

    return result;
}


/*
 * Get number of nodes and maximum node size
 *
 * Retrieves the total number of PnP device nodes and the maximum size
 * of any node's configuration data.
 *
 * @param numNodes      Pointer to receive the number of nodes
 * @param maxNodeSize   Pointer to receive the maximum node size
 * @return              BIOS return code (0 = success)
 */
- (int)getNumNodes:(int *)numNodes AndSize:(int *)maxNodeSize
{
    int bufferAddr;
    int result;

    IOLog("PnPBios: getNumNodes - entering\n");

    /* Setup GDT segments for BIOS call */
    if (![self setupSegments]) {
        IOLog("PnPBios: getNumNodes - setupSegments failed\n");
        return 143;  /* Error code */
    }

    IOLog("PnPBios: getNumNodes - setupSegments succeeded\n");

    /* Get buffer address */
    bufferAddr = (int)kData;
    IOLog("PnPBios: getNumNodes - bufferAddr=0x%x\n", bufferAddr);

    /* Reset argument stack and build arguments */
    IOLog("PnPBios: getNumNodes - building arguments\n");
    [argStack reset];
    [argStack push:kDataSelector];              /* DS segment selector */
    [argStack pushFarPtr:(void *)bufferAddr];   /* ES:BX = buffer (for maxNodeSize) */
    [argStack pushFarPtr:(void *)(bufferAddr + 2)]; /* CX:DI = buffer+2 (for numNodes) */
    [argStack push:PNP_FC_GET_NUM_NODES];       /* Function 0x00 */

    IOLog("PnPBios: getNumNodes - calling BIOS function 0x00\n");

    /* Call BIOS with bb structure */
    result = call_bios(&bb);

    IOLog("PnPBios: getNumNodes - BIOS returned 0x%x\n", result);

    /* Read results from buffer */
    *maxNodeSize = *(unsigned short *)bufferAddr;         /* Word at offset 0 */
    *numNodes = *(unsigned char *)(bufferAddr + 2);       /* Byte at offset 2 */

    IOLog("PnPBios: getNumNodes - numNodes=%d maxNodeSize=%d\n", *numNodes, *maxNodeSize);

    /* Release GDT segments */
    [self releaseSegments];

    IOLog("PnPBios: getNumNodes - completed\n");

    return result;
}


/*
 * Get PnP configuration
 *
 * Retrieves static allocation resource information from PnP BIOS.
 *
 * @param buffer   Pointer to receive the address of the configuration data
 * @return         BIOS return code (0 = success)
 */
- (int)getPnPConfig:(void **)buffer
{
    int result;

    IOLog("PnPBios: getPnPConfig - entering\n");

    /* Setup GDT segments for BIOS call */
    if (![self setupSegments]) {
        IOLog("PnPBios: getPnPConfig - setupSegments failed\n");
        return 143;  /* Error code */
    }

    IOLog("PnPBios: getPnPConfig - setupSegments succeeded\n");

    /* Set output buffer pointer */
    *buffer = kData;
    IOLog("PnPBios: getPnPConfig - buffer=0x%x\n", *buffer);

    /* Reset argument stack and build arguments */
    IOLog("PnPBios: getPnPConfig - building arguments\n");
    [argStack reset];
    [argStack push:kDataSelector];              /* DS segment selector */
    [argStack pushFarPtr:*buffer];              /* ES:BX = buffer */
    [argStack push:PNP_FC_GET_STATIC_ALLOCATION_RESOURCE_INFORMATION];  /* Function 0x40 */

    IOLog("PnPBios: getPnPConfig - calling BIOS function 0x40\n");

    /* Call BIOS with bb structure */
    result = call_bios(&bb);

    IOLog("PnPBios: getPnPConfig - BIOS returned 0x%x\n", result);

    /* Release GDT segments */
    [self releaseSegments];

    IOLog("PnPBios: getPnPConfig - completed\n");

    return result;
}

/*
 * Setup GDT segments for PnP BIOS calls
 *
 * Configures GDT entries for BIOS calling:
 * - GDT 16 (0x80): 16-bit BIOS code segment
 * - GDT 17 (0x88): 32-bit kernel data segment
 * - GDT 18 (0x90): 32-bit BIOS data segment
 * - GDT 19 (0x98): 32-bit code segment
 *
 * @return YES if successful, NO if argStack allocation fails
 */
- (BOOL)setupSegments
{
    struct real_descriptor *gdtEntry16;  /* GDT index 16 (0x80) */
    struct real_descriptor *gdtEntry17;  /* GDT index 17 (0x88) */
    struct real_descriptor *gdtEntry18;  /* GDT index 18 (0x90) */
    struct real_descriptor *gdtEntry19;  /* GDT index 19 (0x98) */
    unsigned int biosCodeBase;
    unsigned int biosDataBase;
    unsigned int kernelDataOffset;
    unsigned int pnpEntryAddr;
    PnPArgStack *stack;

    IOLog("PnPBios: setupSegments - entering\n");
    IOLog("PnPBios: biosCodeSegAddr=0x%x biosEntryOffset=0x%x\n", biosCodeSegAddr, biosEntryOffset);
    IOLog("PnPBios: dataSegAddr=0x%x kData=0x%x\n", dataSegAddr, kData);

    gdtEntry16 = &gdt[16];  /* PNP_CODE16_SEL >> 3 */
    gdtEntry17 = &gdt[17];  /* PNP_KDATA_SEL >> 3 */
    gdtEntry18 = &gdt[18];  /* PNP_DATA32_SEL >> 3 */
    gdtEntry19 = &gdt[19];  /* PNP_CS32_SEL >> 3 */

    IOLog("PnPBios: GDT entries: 16=0x%08x 17=0x%08x 18=0x%08x 19=0x%08x\n", 
        (unsigned int)gdtEntry16, 
        (unsigned int)gdtEntry17, 
        (unsigned int)gdtEntry18, 
        (unsigned int)gdtEntry19);

    /* Save current GDT entries (8 bytes each) */
    saveGDTBiosCode[0] = *(unsigned int *)gdtEntry16;
    saveGDTBiosCode[1] = *((unsigned int *)gdtEntry16 + 1);
    saveGDTBiosData[0] = *(unsigned int *)gdtEntry18;
    saveGDTBiosData[1] = *((unsigned int *)gdtEntry18 + 1);
    saveGDTBiosEntry[0] = *(unsigned int *)gdtEntry19;
    saveGDTBiosEntry[1] = *((unsigned int *)gdtEntry19 + 1);
    saveGDTKData[0] = *(unsigned int *)gdtEntry17;
    saveGDTKData[1] = *((unsigned int *)gdtEntry17 + 1);

    /* Setup GDT 16 (0x80) - 16-bit BIOS code segment */
    biosCodeBase = biosCodeSegAddr;
    gdtEntry16->base_low = (unsigned short)biosCodeBase;
    gdtEntry16->base_med = (unsigned char)(biosCodeBase >> 16);
    gdtEntry16->base_high = (unsigned char)(biosCodeBase >> 24);
    gdtEntry16->access = 0x9A;           /* P=1, DPL=0, S=1, Type=1010 (Code, Execute/Read) */
    gdtEntry16->limit_low = 0xFFFF;      /* Limit low 16 bits */
    gdtEntry16->granularity = 0x00;      /* G=0 (byte), D/B=0 (16-bit), limit high = 0 */

    /* Setup GDT 18 (0x90) - 32-bit BIOS data segment */
    biosDataBase = dataSegAddr;
    gdtEntry18->base_low = (unsigned short)biosDataBase;
    gdtEntry18->base_med = (unsigned char)(biosDataBase >> 16);
    gdtEntry18->base_high = (unsigned char)(biosDataBase >> 24);
    gdtEntry18->access = 0x92;           /* P=1, DPL=0, S=1, Type=0010 (Data, Read/Write) */
    gdtEntry18->limit_low = 0xFFFF;      /* Limit low 16 bits */
    gdtEntry18->granularity = 0x00;      /* G=0 (byte), D/B=0 (16-bit), limit high = 0 */

    kDataSelector = PNP_DATA32_SEL;  /* 0x90 */

    /* Setup GDT 19 (0x98) - 32-bit code segment pointing to __PnPEntry */
    /* This is needed for the far return address from BIOS calls */
    pnpEntryAddr = (unsigned int)&_PnPEntry;
    gdtEntry19->base_low = (unsigned short)pnpEntryAddr;               /* Base low 16 bits */
    gdtEntry19->base_med = (unsigned char)(pnpEntryAddr >> 16);        /* Base mid 8 bits */
    gdtEntry19->base_high = (unsigned char)(pnpEntryAddr >> 24);       /* Base high 8 bits */
    gdtEntry19->access = 0x9A;           /* P=1, DPL=0, S=1, Type=1010 (Code, Execute/Read) */
    gdtEntry19->limit_low = 0xFFFF;      /* Limit low 16 bits */
    gdtEntry19->granularity = 0x40;      /* G=0 (byte), D/B=1 (32-bit), limit high = 0 */

    /* Setup GDT 17 (0x88) - 32-bit kernel data segment */
    kernelDataOffset = (unsigned int)kData - 0x40000000;
    gdtEntry17->base_low = (unsigned short)kernelDataOffset;
    gdtEntry17->base_med = (unsigned char)(kernelDataOffset >> 16);
    gdtEntry17->base_high = (unsigned char)(kernelDataOffset >> 24);
    gdtEntry17->access = 0x92;           /* P=1, DPL=0, S=1, Type=0010 (Data, Read/Write) */
    gdtEntry17->limit_low = 0xFFFF;      /* Limit low 16 bits */
    gdtEntry17->granularity = 0x40;      /* G=0 (byte), D/B=1 (32-bit), limit high = 0 */

    kDataSelector = PNP_KDATA_SEL;  /* 0x88 - final value */

    IOLog("PnPBios: GDT setup complete\n");

    /* Zero out bb structure (48 bytes) */
    bzero((char *)&bb, sizeof(BIOSCallStruct));

    /* Set bb structure fields for BIOS calls */
    bb.cs = PNP_CS32_SEL;     /* CS segment selector = 0x98 */
    bb.ds = 16;               /* DS = kernel data selector */
    bb.es = 0;                /* ES = 0 */
    bb.pad = 0;               /* Padding = 0 */
    bb.addr = 0;              /* Far call address/offset = 0 */

    IOLog("PnPBios: Setting assembly variables\n");

    /* Set global PnPEntry variables */
    _PnPEntry_biosCodeSelector = PNP_CODE16_SEL;  /* 0x80 */
    _PnPEntry_biosCodeOffset = biosEntryOffset;
    kernDataSel = 16;

    IOLog("PnPBios: _PnPEntry_biosCodeSelector=0x%x _PnPEntry_biosCodeOffset=0x%x\n",
          PNP_CODE16_SEL, biosEntryOffset);

    /* Initialize bios32PnP_ptr to point to assembly trampoline */
    bios32PnP_ptr = (void *)&_bios32PnP;

    IOLog("PnPBios: bios32PnP_ptr=%p\n", bios32PnP_ptr);

    /* Create argStack if not already allocated */
    if (argStack != nil) {
        IOLog("PnPBios: argStack already exists, returning YES\n");
        return YES;
    }

    IOLog("PnPBios: Creating PnPArgStack\n");
    stack = [PnPArgStack alloc];
    argStack = [stack initWithData:kData Selector:kDataSelector];

    if (argStack == nil) {
        IOLog("PnPBios: PnPArgStack init failed\n");
        return NO;
    }

    IOLog("PnPBios: setupSegments - completed successfully\n");
    return YES;
}

/*
 * Release GDT segments
 *
 * Restores saved GDT entries back to their original values.
 */
- (void)releaseSegments
{
    struct real_descriptor *gdtEntry16;
    struct real_descriptor *gdtEntry17;
    struct real_descriptor *gdtEntry18;
    struct real_descriptor *gdtEntry19;

    IOLog("PnPBios: releaseSegments - entering\n");

    gdtEntry16 = &gdt[16];  /* PNP_CODE16_SEL >> 3 */
    gdtEntry17 = &gdt[17];  /* PNP_KDATA_SEL >> 3 */
    gdtEntry18 = &gdt[18];  /* PNP_DATA32_SEL >> 3 */
    gdtEntry19 = &gdt[19];  /* PNP_CS32_SEL >> 3 */

    /* Restore saved GDT entries (8 bytes each) */
    *(unsigned int *)gdtEntry16 = saveGDTBiosCode[0];
    *((unsigned int *)gdtEntry16 + 1) = saveGDTBiosCode[1];
    *(unsigned int *)gdtEntry18 = saveGDTBiosData[0];
    *((unsigned int *)gdtEntry18 + 1) = saveGDTBiosData[1];
    *(unsigned int *)gdtEntry19 = saveGDTBiosEntry[0];
    *((unsigned int *)gdtEntry19 + 1) = saveGDTBiosEntry[1];
    *(unsigned int *)gdtEntry17 = saveGDTKData[0];
    *((unsigned int *)gdtEntry17 + 1) = saveGDTKData[1];

    IOLog("PnPBios: releaseSegments - completed\n");
}

@end
