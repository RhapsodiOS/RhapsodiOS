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
 *    ↓
 *    Call call_pnp_bios(func, arg1, arg2, ..., arg7) with individual u16 arguments
 *
 * 2. call_pnp_bios() [bios.c]
 *    - Packs arguments into registers:
 *      EAX = func | (arg1 << 16)
 *      EBX = arg2 | (arg3 << 16)
 *      ECX = arg4 | (arg5 << 16)
 *      EDX = arg6 | (arg7 << 16)
 *    - Saves all segment registers (DS, ES, FS, GS) and EFLAGS
 *    - Executes: lcall $0x98, $0
 *      (Far call to PNP_CS32_SEL:0, which is pnp_bios_callfunc)
 *      This pushes CS:EIP and switches to segment 0x98
 *    ↓
 *
 * 3. pnp_bios_callfunc() [PnPBios.m - inline assembly, executing in segment 0x98:0]
 *    - Saves current SS:ESP in registers (DI:ESI) - CRITICAL for stack switch!
 *    - Switches to 16-bit stack segment (SS=0xA0, ESP=0x1000)
 *      GDT 20 points to our allocated 4KB buffer (_kStack)
 *      This is required because x86 CPU may fault if CS is 16-bit but SS is 32-bit
 *    - Pushes EDX, ECX, EBX, EAX onto 16-bit stack (creates 8 words for BIOS)
 *    - Executes: lcallw *pnp_bios_callpoint
 *      (Far call to segment 0x80:offset, where 0x80 = PNP_CODE16_SEL)
 *      This is a 16-bit far call, so it only pushes 16-bit CS:IP!
 *    ↓
 *
 * 4. 16-bit PnP BIOS [runs in GDT segment 16 @ pm16cseg base address]
 *    - Pops 8 words from stack as BIOS arguments
 *    - Executes BIOS function
 *    - Returns AX = status code
 *    - Does far return back to pnp_bios_callfunc
 *      CRITICAL: Far return only pops 16-bit IP! Works because we're in
 *      segment 0x98 where pnp_bios_callfunc appears at offset 0, so the
 *      return address (instruction after lcallw) is < 64KB
 *    ↓
 *
 * 5. pnp_bios_callfunc() [resumes after lcallw, still in segment 0x98]
 *    - Restores original SS from DI register
 *    - Restores original ESP from ESI register (back to kernel stack)
 *    - Cleans up arguments (addl $16, %esp)
 *    - Executes lretl (far return using CS:EIP pushed by lcall in step 2)
 *    ↓
 *
 * 6. call_pnp_bios() [resumes after lcall, back in kernel code segment 0x08]
 *    - Restores EFLAGS and segment registers
 *    - Returns AX (status) to caller
 *    ↓
 *
 * 7. Objective-C method receives status code
 *
 * GDT Configuration (set up once in setupSegments):
 * - GDT 16 (0x80): 16-bit code segment → pm16cseg (BIOS code)
 * - GDT 17 (0x88): 32-bit data segment → _kData (our 64KB buffer)
 * - GDT 18 (0x90): 32-bit data segment → pm16dseg (BIOS data)
 * - GDT 19 (0x98): 32-bit code segment → pnp_bios_callfunc (makes it appear at offset 0)
 * - GDT 20 (0xA0): 16-bit stack segment → _kStack (4KB dedicated BIOS stack buffer)
 *
 * The pnp_bios_callpoint structure contains: { offset, 0x80 }
 * where offset = pm16offset from PnP BIOS installation structure.
 *
 * WHY GDT 19 (PNP_CS32) IS CRITICAL:
 * The 16-bit BIOS uses far return which only pops 16-bit IP. If pnp_bios_callfunc
 * were at its real address (e.g., 0xc00a376), the return would truncate to 0xa376
 * and crash. By setting GDT 19's base to pnp_bios_callfunc, that function appears
 * at offset 0, and the instruction after lcallw is at a small offset (< 64KB),
 * allowing the 16-bit return to work correctly.
 */

/*
 * Local GDT selector values for PnP BIOS setup.
 * These map to the GDT indices (16-20) and kernel data (2)
 * used by this driver.
 *
 * A selector value is (Index << 3) | RPL.
 * We are in kernel mode, so RPL = 0.
 */
#define PNP_KDS_SEL             (2 << 3)   /* 0x10 - Kernel Data (Index 2) */
#define PNP_CODE16_SEL          (16 << 3)  /* 0x80 - 16-bit PnP Code (Index 16) */
#define PNP_KDATA_SEL           (17 << 3)  /* 0x88 - Kernel Buffer (Index 17) */
#define PNP_DATA32_SEL          (18 << 3)  /* 0x90 - 32-bit PnP Data (Index 18) */
#define PNP_CS32_SEL            (19 << 3)  /* 0x98 - pnp_bios_callfunc alias (Index 19) */
#define PNP_STACK16_SEL         (20 << 3)  /* 0xA0 - 16-bit stack segment (Index 20) */

#define PNP_STACK_INITIAL_OFFSET 0xFFFC

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

/* External globals for PnP BIOS */
extern unsigned short kernDataSel;

/* External verbose logging flag (defined in bios.c) */
extern char verbose;

/*
 * PnP BIOS callpoint structure (Linux-style)
 * This 4-byte structure contains the far pointer for calling the 16-bit BIOS
 * For 16-bit code, offset must be 16-bit, not 32-bit!
 * Must be non-static so inline assembly can reference it.
 */
static struct {
    unsigned short offset;   /* 2-byte offset (16-bit) */
    unsigned short segment;  /* 2-byte segment selector */
} pnp_bios_callpoint;

/*
 * pnp_bios_callfunc - Low-level PnP BIOS call entry point (inline assembly)
 *
 * This is a static assembly function that acts as a trampoline for calling
 * the 16-bit PnP BIOS from 32-bit kernel code.
 *
 * CRITICAL STACK HANDLING (Linux-style approach):
 * The x86 CPU requires that when executing 16-bit code (CS with D/B=0), the
 * stack segment SS should also be 16-bit (D/B=0) to avoid compatibility issues.
 *
 * We use a dedicated 4KB stack buffer (allocated in init) to avoid corrupting
 * low memory (BIOS data area, IVT, etc.). GDT 20 points to this buffer.
 *
 * Stack switching sequence:
 * 1. Save current SS:ESP in registers (DI:ESI) before switching
 * 2. Switch to GDT 20 (16-bit stack segment: base=_kStack, limit=4KB)
 * 3. Set ESP to 0x1000 (top of 4KB buffer, grows down)
 * 4. Push arguments (EDX, ECX, EBX, EAX) onto 16-bit stack
 * 5. Call 16-bit BIOS (which pops arguments from this stack)
 * 6. Restore original SS:ESP from registers
 *
 * The function is called via far call from call_pnp_bios (with CS:EIP pushed).
 * Arguments are passed in registers EAX, EBX, ECX, EDX (packed as 4 dwords).
 */
void pnp_bios_callfunc(void);

__asm__(
    ".text\n"
    ".align 4,0x90\n"
    "_pnp_bios_callfunc:\n"
    /* Save current SS:ESP in registers before switching stacks */
    "    movl  %esp, %esi\n"               /* Save current ESP in ESI */
    "    movw  %ss, %di\n"                 /* Save current SS in DI */
    /* Switch to 16-bit stack segment (points to our 4KB allocated buffer) */
    "    movw  $0xa0, %ax\n"               /* Load PNP_STACK16_SEL (0xA0) */
    "    movw  %ax, %ss\n"                 /* Set SS to 16-bit segment (base=_kStack, limit=4KB) */
    "    movl  $0x1000, %esp\n"            /* Set ESP to top of 4KB buffer (grows down from here) */
    /* NOW push arguments onto the 16-bit stack for BIOS to consume */
    "    pushl %edx\n"
    "    pushl %ecx\n"
    "    pushl %ebx\n"
    "    pushl %eax\n"
    /* lcallw FAR *[_pnp_bios_callpoint] - calls 16-bit BIOS */
    /* 0x66 = operand size override (makes call 16-bit in 32-bit mode) */
    /* 0xFF /3 = FAR call indirect through memory */
    "    .byte 0x66, 0xff, 0x1d\n"        /* CALL FAR m16:16 opcode */
    "    .long _pnp_bios_callpoint\n"     /* Address of callpoint structure */
    /* Restore original SS:ESP from registers */
    "    movw  %di, %ss\n"                 /* Restore original SS from DI */
    "    movl  %esi, %esp\n"               /* Restore original ESP from ESI */
    "    .byte 0xcb\n"                     /* lretl opcode (32-bit far return) */
);

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
    _kData = NULL;
    _kStack = NULL;
    _pnpBios = NULL;

    /* Probe for PnP BIOS */
    present = [PnPBios Present:(void **)&_pnpBios];
    if (!present) {
        IOLog("PnPBios: PnP BIOS not detected\n");
        return [self free];
    }

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

    /* Read from structure fields - we have #pragma pack(1) so no padding */
    _biosEntryOffset = _pnpBios->fields.pm16offset;
    _biosCodeSegAddr = _pnpBios->fields.pm16cseg;
    _dataSegAddr = _pnpBios->fields.pm16dseg;

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

    /* Allocate 64KB buffer for PnP BIOS data transfers */
    _kData = IOMalloc(0x10000);
    if (_kData == NULL) {
        IOLog("PnPBios: Failed to allocate kernel buffer\n");
        return [self free];
    }

    /* Allocate 4KB stack for 16-bit BIOS calls (Linux-style) */
    _kStack = IOMalloc(0x1000);
    if (_kStack == NULL) {
        IOLog("PnPBios: Failed to allocate BIOS stack\n");
        return [self free];
    }
    IOLog("PnPBios: Allocated 4KB BIOS stack at 0x%08x\n", (unsigned int)_kStack);

    /* Setup GDT segments for PnP BIOS calls (one-time setup) */
    if ([self setupSegments] == nil) {
        IOLog("PnPBios: Failed to setup segments\n");
        return [self free];
    }

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

    /* Free allocated stack */
    if (_kStack != NULL) {
        IOFree(_kStack, 0x1000);
        _kStack = NULL;
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

    /* Get pointer to PnP buffer */
    pnpBuf = (unsigned char *)_kData;

    /* Set output buffer pointer */
    *(void **)buffer = pnpBuf;

    IOLog("PnPBios: Calling GetDeviceNode (handle=0x%02x)\n", handle);

    /* Call PnP BIOS - Function 0x01: AX=0x01, CL=node, ES:BX=buffer, DL=control */
    result = call_pnp_bios(
        PNP_FC_GET_DEVICE_NODE,     /* AX = function */
        (unsigned short)handle,     /* CL = node number */
        _kDataSelector,             /* ES = buffer segment */
        0,                          /* BX = buffer offset */
        1,                          /* DL = control (1 = current config) */
        0, 0, 0                     /* Unused arguments */
    );

    IOLog("PnPBios: GetDeviceNode result: 0x%x\n", result);

    return result;
}


/*
 * Get number of nodes and maximum node size
 */
- (int)getNumNodes:(int *)numNodes AndSize:(int *)maxNodeSize
{
    unsigned short *pnpBuf;
    int result;

    /* Get pointer to PnP buffer (as short array) */
    pnpBuf = (unsigned short *)_kData;

    IOLog("PnPBios: Calling GetNumNodes\n");

    /* Call PnP BIOS - Function 0x00: AX=0x00, ES:BX=NumNodes, CX=2, ES:DI=MaxNodeSize */
    result = call_pnp_bios(
        PNP_FC_GET_NUM_NODES,   /* AX = function */
        _kDataSelector,         /* ES = buffer segment */
        0,                      /* BX = offset for NumNodes */
        2,                      /* CX = size (2 bytes) */
        2,                      /* DI = offset for MaxNodeSize */
        0, 0, 0                 /* Unused arguments */
    );

    IOLog("PnPBios: GetNumNodes result: 0x%x\n", result);

    /* Copy results from buffer */
    *maxNodeSize = (int)*pnpBuf;
    *numNodes = (int)*((unsigned char *)(pnpBuf + 1));

    return result;
}


/*
 * Get PnP configuration
 */
- (int)getPnPConfig:(void **)buffer
{
    int result;

    /* Set output buffer pointer to PnP buffer */
    *(void **)buffer = _kData;

    IOLog("PnPBios: Calling GetPnPConfig (func=0x40, ES=0x%02x, BX=0x%04x)\n",
          _kDataSelector, 0);

    /* Call PnP BIOS - Function 0x40: AX=0x40, ES:BX=buffer */
    result = call_pnp_bios(
        PNP_FC_GET_STATIC_ALLOCATION_RESOURCE_INFORMATION,  /* AX = function */
        _kDataSelector,                                      /* ES = buffer segment */
        0,                                                   /* BX = buffer offset */
        0, 0, 0, 0, 0                                        /* Unused arguments */
    );

    IOLog("PnPBios: GetPnPConfig returned, result=0x%x\n", result);

    return result;
}



/*
 * Setup segments for PnP BIOS calls (Linux-style)
 *
 * Following Linux's approach, we set up GDT entries ONCE during initialization.
 * These remain permanently configured - no save/restore needed.
 *
 * GDT Entries:
 * - GDT 16 (PNP_CODE16_SEL=0x80): 16-bit code segment for BIOS
 * - GDT 17 (PNP_KDATA_SEL=0x88): 32-bit data segment for kernel buffer
 * - GDT 18 (PNP_DATA32_SEL=0x90): 32-bit data segment for BIOS data
 * - GDT 19 (PNP_CS32_SEL=0x98): 32-bit code segment alias for pnp_bios_callfunc
 */
- setupSegments
{
    unsigned char *gdtBase;
    unsigned int base;
    GDTEntry *entryPnPCode16;
    GDTEntry *entryKData;
    GDTEntry *entryPnPData32;
    GDTEntry *entryPnPCS32;
    GDTEntry *entryStack16;

    /* Get pointer to GDT */
    gdtBase = (unsigned char *)gdt;

    /* Get GDT entry pointers */
    entryPnPCode16 = (GDTEntry *)(gdtBase + PNP_CODE16_SEL);   /* 0x80 */
    entryKData = (GDTEntry *)(gdtBase + PNP_KDATA_SEL);         /* 0x88 */
    entryPnPData32 = (GDTEntry *)(gdtBase + PNP_DATA32_SEL);   /* 0x90 */
    entryPnPCS32 = (GDTEntry *)(gdtBase + PNP_CS32_SEL);       /* 0x98 */
    entryStack16 = (GDTEntry *)(gdtBase + PNP_STACK16_SEL);     /* 0xA0 */

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
     * Setup GDT 18 (PNP_DATA32_SEL) - 32-bit data segment for BIOS data
     * Base: _dataSegAddr (pm16dseg from PnP BIOS structure)
     * Limit: 0xFFFF (64KB), Granularity: byte, Size: 32-bit
     */
    base = _dataSegAddr;
    entryPnPData32->limitLow = 0xFFFF;
    entryPnPData32->baseLow = (unsigned short)base;
    entryPnPData32->baseMid = (unsigned char)(base >> 16);
    entryPnPData32->baseHigh = (unsigned char)(base >> 24);
    entryPnPData32->access = 0x92;          /* P=1, DPL=0, S=1, Type=0010 (Data, Read/Write) */
    entryPnPData32->flagsLimitHigh = 0x40;  /* G=0 (byte), D/B=1 (32-bit), L=0, AVL=0 */

    /*
     * Setup GDT 17 (PNP_KDATA_SEL) - 32-bit data segment for our buffer
     * Base: _kData (our allocated 64KB buffer)
     * Limit: 0xFFFF (64KB), Granularity: byte, Size: 32-bit
     */
    base = (unsigned int)_kData;
    entryKData->limitLow = 0xFFFF;
    entryKData->baseLow = (unsigned short)base;
    entryKData->baseMid = (unsigned char)(base >> 16);
    entryKData->baseHigh = (unsigned char)(base >> 24);
    entryKData->access = 0x92;              /* P=1, DPL=0, S=1, Type=0010 (Data, Read/Write) */
    entryKData->flagsLimitHigh = 0x40;      /* G=0 (byte), D/B=1 (32-bit), L=0, AVL=0 */

    /*
     * Setup GDT 19 (PNP_CS32_SEL) - 32-bit code segment alias for pnp_bios_callfunc
     * Base: address of pnp_bios_callfunc
     * Limit: 0xFFFF (64KB), Granularity: byte, Size: 32-bit
     *
     * This segment makes pnp_bios_callfunc appear at offset 0.
     * When the 16-bit BIOS does far return after lcallw, it only pops 16-bit IP.
     * By executing lcallw in the context of this segment (via far call from
     * call_pnp_bios), the return address is a small offset that fits in 16 bits.
     */
    base = (unsigned int)pnp_bios_callfunc;
    IOLog("PnPBios DEBUG: pnp_bios_callfunc address = 0x%08x\n", base);
    entryPnPCS32->limitLow = 0xFFFF;
    entryPnPCS32->baseLow = (unsigned short)base;
    entryPnPCS32->baseMid = (unsigned char)(base >> 16);
    entryPnPCS32->baseHigh = (unsigned char)(base >> 24);
    entryPnPCS32->access = 0x9A;            /* P=1, DPL=0, S=1, Type=1010 (Code, Execute/Read) */
    entryPnPCS32->flagsLimitHigh = 0x40;    /* G=0 (byte), D/B=1 (32-bit), L=0, AVL=0 */
    IOLog("PnPBios DEBUG: GDT 19 configured: base=0x%02x%02x%02x%02x\n",
          entryPnPCS32->baseHigh, entryPnPCS32->baseMid,
          (entryPnPCS32->baseLow >> 8) & 0xFF, entryPnPCS32->baseLow & 0xFF);

    /*
     * Setup GDT 20 (PNP_STACK16_SEL) - 16-bit stack segment (Linux-style)
     * Base: _kStack (our allocated 4KB buffer)
     * Limit: 0x0FFF (4KB), Granularity: byte, Size: 16-bit
     *
     * CRITICAL: When calling 16-bit BIOS code, SS must point to a 16-bit segment.
     * The CPU will fault if CS is 16-bit but SS is 32-bit.
     *
     * We allocate a dedicated 4KB stack buffer to avoid corrupting low memory
     * (BIOS data area, IVT, etc.) which would happen if we used base=0.
     */
    base = (unsigned int)_kStack;
    entryStack16->limitLow = 0x0FFF;        /* 4KB limit */
    entryStack16->baseLow = (unsigned short)base;
    entryStack16->baseMid = (unsigned char)(base >> 16);
    entryStack16->baseHigh = (unsigned char)(base >> 24);
    entryStack16->access = 0x92;            /* P=1, DPL=0, S=1, Type=0010 (Data, Read/Write) */
    entryStack16->flagsLimitHigh = 0x00;    /* G=0 (byte), D/B=0 (16-bit), L=0, AVL=0 */

    /* Save selector values for later use */
    _kDataSelector = PNP_KDATA_SEL;

    /*
     * Initialize PnP BIOS callpoint structure (Linux-style)
     * This 4-byte structure contains the segment:offset for the far call
     * Offset is 16-bit because PnP BIOS is 16-bit code!
     */
    pnp_bios_callpoint.offset = _biosEntryOffset;
    pnp_bios_callpoint.segment = PNP_CODE16_SEL;

    IOLog("PnPBios: GDT segments configured\n");
    IOLog("PnPBios: Code seg=0x%02x @ 0x%08x, Data seg=0x%02x @ 0x%08x\n",
          PNP_CODE16_SEL, _biosCodeSegAddr, PNP_DATA32_SEL, _dataSegAddr);
    IOLog("PnPBios: PNP_CS32 seg=0x%02x @ 0x%08x (pnp_bios_callfunc)\n",
          PNP_CS32_SEL, base);
    IOLog("PnPBios: Callpoint = %04x:%04x (struct @ 0x%08x)\n",
          pnp_bios_callpoint.segment, pnp_bios_callpoint.offset,
          (unsigned int)&pnp_bios_callpoint);

    return self;
}

@end
