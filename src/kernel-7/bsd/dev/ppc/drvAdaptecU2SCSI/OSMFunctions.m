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
 * OSMFunctions.m - OSM (Operating System Module) Functions for Adaptec CHIM
 *
 * These functions provide the interface between the Adaptec CHIM
 * (Common Hardware Interface Module) and the RhapsodiOS kernel.
 */

#import "OSMFunctions.h"

#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <kern/thread_call.h>
#import <kernserv/kalloc.h>
#import <kernserv/ns_timer.h>
#import <kernserv/prototypes.h>
#import <mach/vm_param.h>
#import <machdep/ppc/pmap.h>
#import <machdep/ppc/proc_reg.h>
#import <objc/objc.h>

/*
 * OSMIO Buffer Structure
 *
 * These buffers are used by the CHIM layer for I/O operations.
 * Each buffer contains metadata and a data area for DMA transfers.
 * Total size: 200 bytes (0xc8)
 */
typedef struct OSMIOBuffer {
    unsigned int physicalAddress;       // 0x00 - Physical address for DMA
    unsigned int dataSize;              // 0x04 - Size of data buffer
    unsigned int alignedVirtualAddr;    // 0x08 - Aligned virtual address
    unsigned int reserved1[24];         // 0x0c - Reserved (96 bytes to reach 0x6c)
    void *memoryBlock;                  // 0x6c - Original memory allocation
    unsigned int reserved2;             // 0x70 - Reserved
    void *workArea;                     // 0x74 - Work area pointer
    unsigned int reserved3[18];         // 0x78 - Reserved (72 bytes to reach 0xc0)
    void *prevLink;                     // 0xc0 - Previous IOB in free queue
    void *nextLink;                     // 0xc4 - Next IOB in free queue
} OSMIOBuffer;

/*
 * Allocate an OSMIO Buffer for CHIM operations.
 *
 * This creates a buffer structure that includes:
 * - DMA-capable contiguous memory
 * - Physical address mapping for hardware
 * - Work area for driver operations
 * - Queue linkage for buffer management
 *
 * The function is called with parameters from the CHIM profile buffer:
 * @param p1-p8 Various CHIM configuration parameters
 *              param_11 (alignment) and param_12 (size) are extracted
 * @return Pointer to allocated OSMIOBuffer, or NULL on failure
 */
void *_allocOSMIOB(void *p1, void *p2, void *p3, void *p4,
                   void *p5, void *p6, void *p7, void *p8)
{
    OSMIOBuffer *iob;
    void *dmaMemory;
    unsigned int alignment;
    unsigned int size;
    unsigned int alignedAddr;
    void *vmTask;
    unsigned int physAddr;
    int result;

    // Extract alignment and size from parameters
    // These come from the CHIM profile buffer
    alignment = (unsigned int)p5;  // Typically from offset in profile
    size = (unsigned int)p6;       // Size required

    // Allocate the IOB structure (200 bytes = 0xc8)
    iob = (OSMIOBuffer *)IOMalloc(200);
    if (iob == NULL) {
        return NULL;
    }

    // Clear the structure
    bzero(iob, 200);

    // Allocate contiguous DMA memory with alignment
    dmaMemory = AdptMallocContiguous(size + alignment);
    if (dmaMemory == NULL) {
        IOFree(iob, 200);
        return NULL;
    }

    // Store original allocation pointer (offset 0x6c)
    iob->memoryBlock = dmaMemory;

    // Store size (offset 0x04)
    iob->dataSize = size;

    // Calculate aligned address (offset 0x08)
    alignedAddr = ((unsigned int)dmaMemory + alignment) & ~alignment;
    iob->alignedVirtualAddr = alignedAddr;

    // Get physical address for DMA
    vmTask = IOVmTaskSelf();
    result = IOPhysicalFromVirtual(vmTask, alignedAddr, &physAddr);

    if (result != 0) {
        IOLog("AdaptecU2SCSI: Cannot get physical address.\n");
        AdptFreeContiguous(dmaMemory, size + alignment);
        IOFree(iob, 200);
        return NULL;
    }

    // Store physical address (offset 0x00)
    iob->physicalAddress = physAddr;

    // Allocate work area (one page, offset 0x74)
    iob->workArea = IOMalloc(page_size);

    return iob;
}

/*
 * Free an OSMIO Buffer (low-level deallocation).
 *
 * From decompiled code:
 *   void _freeOSMIOB(int param_1, int param_2, ...)
 *   {
 *       int param_11;  // alignment
 *       int param_12;  // size
 *
 *       AdptFreeContiguous(*(undefined4 *)(param_1 + 0x6c), param_12 + param_11);
 *       _IOFree(*(undefined4 *)(param_1 + 0x74), _page_size);
 *       _IOFree(param_1, 200);
 *   }
 *
 * This is the actual deallocator called by _FreeOSMIOB when the free pool is full.
 *
 * @param iobPtr The buffer to free
 * @param p1-p7 CHIM profile parameters for size calculation
 */

/*
 * Allocate an OSMIO Buffer (high-level with free pool).
 *
 * From decompiled code:
 *   void _AllocOSMIOB(int param_1)
 *   {
 *       int iVar1;
 *       int iVar2;
 *       undefined4 uVar3;
 *       int iVar4;
 *       undefined auStack_1b8[436];
 *
 *       iVar1 = *(int *)(param_1 + 0x580);
 *       if (param_1 + 0x580 == iVar1) {
 *           // Free pool is empty, allocate new IOB
 *           _memcpy(auStack_1b8, (void *)(param_1 + 0x2cc), 0x1b0);
 *           iVar1 = __allocOSMIOB(...);
 *       } else {
 *           // Free pool has IOBs, remove one from queue
 *           iVar4 = *(int *)(iVar1 + 0xc0);
 *           iVar2 = *(int *)(iVar1 + 0xc4);
 *           // ... queue removal logic ...
 *       }
 *
 *       // Initialize IOB fields
 *       *(int *)(param_1 + 0x574) = *(int *)(param_1 + 0x574) + 1;
 *       *(undefined4 *)(iVar1 + 0x78) = 0x20;
 *       uVar3 = *(undefined4 *)(param_1 + 0x5ac);
 *       *(int *)(iVar1 + 0x58) = iVar1 + 0xa4;
 *       *(undefined4 *)(iVar1 + 0x4c) = 0;
 *       // ... more field initializations ...
 *       *(undefined4 *)(iVar1 + 0x84) = uVar3;
 *       *(uint *)(iVar1 + 0x14) = *(uint *)(iVar1 + 0x14) & 0xe7ffffff;
 *   }
 *
 * This implements the allocation side of the free pool optimization:
 * - If free pool has IOBs: remove one from queue and return it
 * - If free pool is empty: call __allocOSMIOB to create new one
 * - Initialize IOB fields before returning
 *
 * Instance variables used:
 * - 0x574: freeIOBCount - number of IOBs in free pool
 * - 0x580: freeIOBQueueHead - head of free IOB queue
 * - 0x584: freeIOBQueueTail - tail of free IOB queue
 * - 0x2ac-0x2c8: profileBuffer - CHIM profile parameters
 * - 0x5ac: kernelInterruptPort - copied to IOB at 0x84
 *
 * IOB structure offsets initialized:
 * - 0x14: flags field (masked with 0xe7ffffff)
 * - 0x44-0x84: various fields cleared or set
 * - 0xc0, 0xc4: queue links (removed from free queue)
 *
 * @param adapter Pointer to adapter instance (AdaptecU2SCSI *)
 * @return Pointer to allocated/recycled IOB
 */
void *_AllocOSMIOB(void *adapter)
{
    unsigned int *adapterPtr = (unsigned int *)adapter;
    unsigned int *iob;
    unsigned int prevLink;
    unsigned int nextLink;
    unsigned char stackBuffer[436];
    unsigned int kernelPort;

    if (adapter == NULL) {
        return NULL;
    }

    // Get head of free queue (offset 0x580)
    iob = (unsigned int *)adapterPtr[0x580 / 4];

    // Check if free pool is empty (head points to itself)
    if ((unsigned int)adapter + 0x580 == (unsigned int)iob) {
        // Free pool is empty, allocate new IOB

        // Copy profile buffer to stack (0x1b0 = 432 bytes from offset 0x2cc)
        memcpy(stackBuffer, (void *)((unsigned int)adapter + 0x2cc), 0x1b0);

        // Call low-level allocator with profile parameters
        iob = (unsigned int *)_allocOSMIOB(
            (void *)adapterPtr[0x2ac / 4],  // Profile param 0
            (void *)adapterPtr[0x2b0 / 4],  // Profile param 1
            (void *)adapterPtr[0x2b4 / 4],  // Profile param 2
            (void *)adapterPtr[0x2b8 / 4],  // Profile param 3
            (void *)adapterPtr[700 / 4],    // Profile param 4 (alignment)
            (void *)adapterPtr[0x2c0 / 4],  // Profile param 5 (size)
            (void *)adapterPtr[0x2c4 / 4],  // Profile param 6
            (void *)adapterPtr[0x2c8 / 4]); // Profile param 7

        if (iob == NULL) {
            return NULL;
        }
    } else {
        // Free pool has IOBs, remove head from queue

        prevLink = iob[0xc0 / 4];  // Previous link
        nextLink = iob[0xc4 / 4];  // Next link

        // Update tail pointer if needed
        if ((unsigned int)adapter + 0x580 == prevLink) {
            // This was the only IOB in queue, update tail
            adapterPtr[0x584 / 4] = nextLink;
        } else {
            // Link previous IOB's next to our next
            *((unsigned int *)(prevLink + 0xc4)) = nextLink;
        }

        // Update head pointer if needed
        if ((unsigned int)adapter + 0x580 == nextLink) {
            // This was the only IOB, queue now empty
            adapterPtr[0x580 / 4] = prevLink;
        } else {
            // Link next IOB's prev to our prev
            *((unsigned int *)(nextLink + 0xc0)) = prevLink;
        }
    }

    // Increment free IOB count (seems backwards, but matches decompiled code)
    // This might be counting total allocated IOBs, not free ones
    adapterPtr[0x574 / 4] = adapterPtr[0x574 / 4] + 1;

    // Initialize IOB fields
    iob[0x78 / 4] = 0x20;  // Some flag or size

    // Get kernel interrupt port from adapter (offset 0x5ac)
    kernelPort = adapterPtr[0x5ac / 4];

    // Set up IOB fields
    iob[0x58 / 4] = (unsigned int)iob + 0xa4;  // Point to embedded area
    iob[0x4c / 4] = 0;   // Clear field
    iob[0x44 / 4] = 0;   // Clear field
    iob[0x48 / 4] = 0;   // Clear field
    iob[0x5c / 4] = 0x1c; // Size or count
    iob[0x10 / 4] = 0;   // Clear field
    iob[0x18 / 4] = 0;   // Clear field
    iob[0x30 / 4] = 0;   // Clear field
    iob[0x24 / 4] = 0;   // Clear field
    iob[0x2c / 4] = 0;   // Clear field
    iob[0x60 / 4] = 0;   // Clear field
    iob[100 / 4] = 0;    // Clear field (0x64)
    iob[0x84 / 4] = kernelPort;  // Set kernel port

    // Clear some bits in flags field at 0x14
    // Mask 0xe7ffffff clears bits 0x18000000
    iob[0x14 / 4] = iob[0x14 / 4] & 0xe7ffffff;

    return iob;
}
void _freeOSMIOB(void *iobPtr, void *p1, void *p2, void *p3,
                 void *p4, void *p5, void *p6, void *p7)
{
    OSMIOBuffer *iob = (OSMIOBuffer *)iobPtr;
    unsigned int alignment;
    unsigned int size;

    if (iob == NULL) {
        return;
    }

    // Extract alignment and size from profile parameters
    // These match the parameters passed to _allocOSMIOB
    alignment = (unsigned int)p4;  // param_11
    size = (unsigned int)p5;       // param_12

    // Free DMA memory if allocated (offset 0x6c)
    // Matches: AdptFreeContiguous(*(undefined4 *)(param_1 + 0x6c), param_12 + param_11)
    if (iob->memoryBlock != NULL) {
        AdptFreeContiguous(iob->memoryBlock, size + alignment);
    }

    // Free work area if allocated (offset 0x74)
    // Matches: _IOFree(*(undefined4 *)(param_1 + 0x74), _page_size)
    if (iob->workArea != NULL) {
        IOFree(iob->workArea, page_size);
    }

    // Free the buffer structure (200 bytes = 0xc8)
    // Matches: _IOFree(param_1, 200)
    IOFree(iob, 200);
}

/*
 * Free an OSMIO Buffer (high-level with free pool).
 *
 * From decompiled code:
 *   void _FreeOSMIOB(int param_1, int param_2)
 *   {
 *       int iVar1;
 *       undefined auStack_1c8[448];
 *
 *       if (*(int *)(param_1 + 0x574) < 0x10) {
 *           iVar1 = *(int *)(param_1 + 0x584);
 *           if (param_1 + 0x580 == iVar1) {
 *               *(int *)(param_1 + 0x580) = param_2;
 *           } else {
 *               *(int *)(iVar1 + 0xc0) = param_2;
 *           }
 *           *(int *)(param_2 + 0xc4) = iVar1;
 *           *(int *)(param_2 + 0xc0) = param_1 + 0x580;
 *           *(int *)(param_1 + 0x584) = param_2;
 *       } else {
 *           _memcpy(auStack_1c8, (void *)(param_1 + 0x2c8), 0x1b4);
 *           _freeOSMIOB(param_2, *(undefined4 *)(param_1 + 0x2ac),
 *                        *(undefined4 *)(param_1 + 0x2b0),
 *                        *(undefined4 *)(param_1 + 0x2b4),
 *                        *(undefined4 *)(param_1 + 0x2b8),
 *                        *(undefined4 *)(param_1 + 700),
 *                        *(undefined4 *)(param_1 + 0x2c0),
 *                        *(undefined4 *)(param_1 + 0x2c4));
 *       }
 *       *(int *)(param_1 + 0x574) = *(int *)(param_1 + 0x574) + -1;
 *   }
 *
 * This implements a free pool optimization. When freeing an IOB:
 * - If free pool has < 16 entries, add IOB to free pool queue
 * - Otherwise, actually deallocate the IOB
 *
 * Instance variables used:
 * - 0x574: freeIOBCount - number of IOBs in free pool
 * - 0x580: freeIOBQueueHead - head of free IOB queue
 * - 0x584: freeIOBQueueTail - tail of free IOB queue
 * - 0x2ac-0x2c4: profileBuffer - CHIM profile parameters
 *
 * IOB structure offsets:
 * - 0xc0: prevLink - previous IOB in queue
 * - 0xc4: nextLink - next IOB in queue
 *
 * @param adapter Pointer to adapter instance (AdaptecU2SCSI *)
 * @param iob The IOB to free
 */
void _FreeOSMIOB(void *adapter, void *iob)
{
    unsigned int *adapterPtr = (unsigned int *)adapter;
    unsigned int *iobPtr = (unsigned int *)iob;
    unsigned int queueTail;
    unsigned char stackBuffer[448];

    if (adapter == NULL || iob == NULL) {
        return;
    }

    // Check if free pool has room (< 16 entries at offset 0x574)
    if (adapterPtr[0x574 / 4] < 0x10) {
        // Add to free pool queue
        queueTail = adapterPtr[0x584 / 4];

        // Check if queue is empty (tail points to head)
        if ((unsigned int)adapter + 0x580 == queueTail) {
            // Empty queue, set head to this IOB
            adapterPtr[0x580 / 4] = (unsigned int)iob;
        } else {
            // Non-empty queue, link from current tail
            *((unsigned int *)(queueTail + 0xc0)) = (unsigned int)iob;
        }

        // Set up IOB's queue links
        iobPtr[0xc4 / 4] = queueTail;  // Previous = old tail
        iobPtr[0xc0 / 4] = (unsigned int)adapter + 0x580;  // Next = queue head

        // Update queue tail
        adapterPtr[0x584 / 4] = (unsigned int)iob;
    } else {
        // Free pool is full, actually deallocate

        // Copy profile buffer to stack (0x1b4 = 436 bytes)
        // This seems to be for safety during the free operation
        memcpy(stackBuffer, (void *)((unsigned int)adapter + 0x2c8), 0x1b4);

        // Call low-level deallocator with profile parameters
        _freeOSMIOB(iob,
                     (void *)adapterPtr[0x2ac / 4],  // Profile param 0
                     (void *)adapterPtr[0x2b0 / 4],  // Profile param 1
                     (void *)adapterPtr[0x2b4 / 4],  // Profile param 2
                     (void *)adapterPtr[0x2b8 / 4],  // Profile param 3
                     (void *)adapterPtr[700 / 4],    // Profile param 4 (alignment)
                     (void *)adapterPtr[0x2c0 / 4],  // Profile param 5 (size)
                     (void *)adapterPtr[0x2c4 / 4]); // Profile param 6
    }

    // Decrement free IOB count
    adapterPtr[0x574 / 4] = adapterPtr[0x574 / 4] - 1;
}

/*
 * CleanupWaitingQ - Clean up waiting queue for a target
 *
 * Based on decompiled code from binary.
 * Called during shutdown or error conditions to abort all pending
 * I/O requests in a target's waiting queue.
 *
 * Function signature from decompiled code:
 * void _CleanupWaitingQ(int *param_1)
 *
 * Decompiled structure:
 * - param_1 is the target structure pointer
 * - Gets adapter from target+0x00
 * - Walks waiting queue at target+0x8c (0x23 * 4)
 * - For each IOB in the queue:
 *   - Gets request object from IOB+0x20
 *   - Removes IOB from queue
 *   - Decrements I/O counter (adapter+0x578)
 *   - Frees the IOB
 *   - Sets request status to 5 (aborted)
 *   - Locks and unlocks the request
 * - Continues until queue is empty
 *
 * @param targetStruct Pointer to target structure (0x9c bytes)
 */
void _CleanupWaitingQ(void *targetStruct)
{
    unsigned int *targetPtr = (unsigned int *)targetStruct;
    unsigned int *queueHead;
    void *adapter;
    unsigned int *adapterPtr;
    unsigned int *currentIOB;
    unsigned int *queuePrev;
    unsigned int *queueNext;
    void *request;
    unsigned int *requestPtr;
    void (**chimFuncs)(void);

    // Get queue head pointer (waiting queue at offset 0x8c = 0x23 * 4)
    queueHead = targetPtr + 0x23;

    // Get adapter from target structure offset 0x00
    adapter = (void *)targetPtr[0];
    adapterPtr = (unsigned int *)adapter;

    // Get first IOB in the waiting queue
    currentIOB = (unsigned int *)targetPtr[0x23];

    // Walk through all IOBs in the waiting queue
    while (queueHead != currentIOB) {
        // Save the current IOB pointer (it's at target+0x23)
        currentIOB = (unsigned int *)targetPtr[0x23];

        // Get request object from IOB offset 0x20
        request = (void *)currentIOB[0x20 / 4];

        // Get queue links from IOB offsets 0xc0, 0xc4
        queuePrev = (unsigned int *)currentIOB[0xc0 / 4];
        queueNext = (unsigned int *)currentIOB[0xc4 / 4];

        // Remove IOB from queue
        // Update prev element's next pointer
        if (queueHead == queuePrev) {
            // Prev is queue head
            targetPtr[0x24] = (unsigned int)queueNext;
        }
        else {
            // Prev is another IOB at offset 0xc4
            queuePrev[0x31] = (unsigned int)queueNext;
        }

        // Update next element's prev pointer
        if (queueHead == queueNext) {
            // Next is queue head
            targetPtr[0x23] = (unsigned int)queuePrev;
        }
        else {
            // Next is another IOB at offset 0xc0
            queueNext[0x30] = (unsigned int)queuePrev;
        }

        // Decrement I/O counter at adapter offset 0x578
        adapterPtr[0x578 / 4] = adapterPtr[0x578 / 4] - 1;

        // Free the IOB
        _FreeOSMIOB(adapter, currentIOB);

        // Set request status to 5 (aborted) at offset 0x18
        requestPtr = (unsigned int *)request;
        requestPtr[0x18 / 4] = 5;

        // Lock the request using CHIM function at adapter+0x5bc
        chimFuncs = (void (**)(void))((unsigned int)adapter + 0x5bc);
        (*chimFuncs)((void *)requestPtr[0x14 / 4], (void *)"lock");

        // Unlock the request using CHIM function at adapter+0x5c4
        chimFuncs = (void (**)(void))((unsigned int)adapter + 0x5c4);
        (*chimFuncs)((void *)requestPtr[0x14 / 4], (void *)"unlockWith:", (void *)1);

        // Get next IOB (now at the head of the queue)
        currentIOB = (unsigned int *)targetPtr[0x23];
    }
}

/*
 * AU2Handler - Interrupt handler for Adaptec Ultra2 SCSI.
 *
 * This is called by the PowerMac interrupt system when the
 * SCSI controller raises an interrupt.
 */
/*
 * AU2Handler - Interrupt handler for Adaptec Ultra2 SCSI.
 *
 * From decompiled code:
 *   void _AU2Handler(undefined4 param_1, undefined4 param_2, undefined4 param_3)
 *   {
 *       _thread_call_func(&LAB_0018b2a8, param_3, 1);
 *   }
 *
 * This is called by the PowerMac interrupt system when the SCSI controller
 * raises an interrupt. It schedules the actual interrupt processing on a
 * thread using thread_call_func.
 *
 * The decompiled code references LAB_0018b2a8 which is likely a function
 * that performs the actual interrupt handling. This would be the I/O thread
 * function that processes SCSI commands.
 *
 * @param param_1 Interrupt context (unused)
 * @param param_2 Interrupt context (unused)
 * @param param_3 Adapter instance or context
 */
void AU2Handler(int interruptType, void *state, void *context)
{
    (void)interruptType;
    (void)state;

    // Schedule the I/O thread to process the interrupt
    // Flags: 1 = async (don't wait for completion)
    thread_call_func(AdaptecU2SCSIIOThread, context, TRUE);
}

/*
 * SCSI Timeout Handler
 *
 * From decompiled code:
 *   void _AdaptecU2SCSITimeout(int param_1)
 *   {
 *       _IOLog("AdaptecU2SCSI: SCSI Timeout.\n");
 *       _objc_msgSend(**(undefined4 **)(param_1 + 0x70), s_resetSCSIBus_0034da0c);
 *   }
 *
 * This function is called when a SCSI operation times out. It:
 * 1. Logs a timeout message
 * 2. Calls resetSCSIBus on the adapter instance
 *
 * The function receives a pointer to some structure (likely a command or request)
 * at param_1. Offset 0x70 in that structure contains a pointer to a pointer to
 * the adapter instance (AdaptecU2SCSI **).
 *
 * @param commandOrRequest Pointer to command/request structure that timed out
 */
void _AdaptecU2SCSITimeout(void *commandOrRequest)
{
    void **cmdPtr = (void **)commandOrRequest;
    id adapter;

    if (commandOrRequest == NULL) {
        return;
    }

    // Log timeout error
    IOLog("AdaptecU2SCSI: SCSI Timeout.\n");

    // Get adapter instance from offset 0x70 in command structure
    // This is a pointer to a pointer: **(void **)(param_1 + 0x70)
    adapter = (id)*((void **)cmdPtr[0x70 / 4]);

    // Call resetSCSIBus method on the adapter
    if (adapter != nil) {
        [adapter resetSCSIBus];
    }
}

/*
 * OSMMapIOHandle - Map PCI I/O region into driver address space
 *
 * From decompiled code:
 *   undefined4 OSMMapIOHandle(int param_1, int param_2, int param_3, int param_4,
 *                               undefined4 param_5, int param_6, int *param_7)
 *
 * This function maps a PCI Base Address Register (BAR) into the driver's
 * virtual address space so the driver can access hardware registers.
 *
 * Algorithm:
 * 1. Read PCI config register (BAR at offset 0x10 + param_2 * 4)
 * 2. Check if memory-mapped (bit 0 clear) or I/O-mapped (bit 0 set)
 * 3. For memory-mapped:
 *    - Add physical memory to pmap
 *    - Map physical to virtual using IOMapPhysicalIntoIOTask
 * 4. For I/O-mapped:
 *    - Get I/O aperture from device description
 * 5. Create handle structure and add to adapter's handle queue
 * 6. Return handle info to caller
 *
 * @param adapter Adapter instance (param_1)
 * @param barIndex PCI BAR index (param_2: 0-5 for BARs 0x10-0x24)
 * @param offset Offset within BAR (param_3)
 * @param size Size to map (param_4)
 * @param param_5 Unused
 * @param handleType Handle type/flags (param_6)
 * @param handleOut Output structure for handle (param_7: 8 ints = 32 bytes)
 * @return 0 on success, 1 on failure
 */



















/*
 * PostRoutineEventPAC - Post-routine for PAC event
 * Forward declaration - actual implementation would handle PAC completion
 */
void _PostRoutineEventPAC(void);

/*
 * PostRoutineEventResetHW - Post-routine for hardware reset event
 * Forward declaration - actual implementation would handle reset completion
 */
void _PostRoutineEventResetHW(void);

/*
 * SendIOBsMaybe - Send queued I/O requests to hardware
 *
 * From decompiled code - walks target's waiting queue and submits IOBs
 * to the CHIM layer for hardware execution.
 *
 * @param targetStruct Pointer to target structure
 */
void SendIOBsMaybe(void *targetStruct);

/*
 * OSMEvent - Handle CHIM events
 *
 * From decompiled code:
 *   void _OSMEvent(int param_1, undefined4 param_2)
 *   {
 *       switch(param_2) {
 *       case 1:  // PAC event
 *       case 2:  // Another PAC variant
 *           iVar1 = _AllocOSMIOB(param_1);
 *           // Set up IOB fields
 *           *(code **)(iVar1 + 0x34) = _PostRoutineEventPAC;
 *           *(undefined4 *)(param_1 + 0x4c0) = 1;
 *           break;
 *       case 3:  // Reset hardware event
 *           // Similar to PAC but uses _PostRoutineEventResetHW
 *           *(undefined4 *)(param_1 + 0x4c8) = 1;
 *           break;
 *       case 4:  // Freeze event
 *           *(undefined4 *)(param_1 + 0x4c4) = 1;
 *           break;
 *       case 5:  // Unfreeze event
 *           *(undefined4 *)(param_1 + 0x4c4) = 0;
 *           // Send pending IOBs for all targets
 *           break;
 *       }
 *   }
 *
 * Events from CHIM:
 * - 1, 2: PAC (probably "Poll And Complete" or similar)
 * - 3: Reset hardware
 * - 4: Freeze I/O
 * - 5: Unfreeze I/O and send pending requests
 *
 * Adapter offsets used:
 * - 0x2a8: himHandle
 * - 0x4c0: Flag for PAC pending (offset matches)
 * - 0x4c4: Freeze flag
 * - 0x4c8: Reset pending flag
 * - 0x51c: CHIM function pointer
 * - 0x578: chimWorkingMemory or counter
 * - 800 (0x320): numTargets
 * - 0x480: targetStructures array base
 *
 * @param adapter Adapter instance
 * @param eventType Event type (1-5)
 */
void _OSMEvent(void *adapter, unsigned int eventType)
{
    unsigned int *adapterPtr = (unsigned int *)adapter;
    void *iob;
    void *himHandle;
    void (*chimFunc)(void);
    unsigned int counter;
    unsigned int targetIndex;
    void **targetStructures;
    unsigned int numTargets;
    const char *eventName;

    if (adapter == NULL) {
        return;
    }

    switch (eventType) {
    case 1:
    case 2:
        // PAC event - allocate IOB and call CHIM
        iob = _AllocOSMIOB(adapter);
        if (iob == NULL) {
            return;
        }

        // Set up IOB fields
        *((void **)((unsigned int)iob + 0x70)) = adapter;
        *((unsigned int *)((unsigned int)iob + 0x0c)) = 6;

        himHandle = (void *)adapterPtr[0x2a8 / 4];
        *((unsigned int *)((unsigned int)iob + 0x20)) = 0;
        *((void **)((unsigned int)iob + 0x34)) = (void *)_PostRoutineEventPAC;
        *((void **)((unsigned int)iob + 0x28)) = himHandle;

        // Set PAC pending flag
        adapterPtr[0x4c0 / 4] = 1;

        // Increment counter and call CHIM function
        counter = adapterPtr[0x578 / 4];
        adapterPtr[0x578 / 4] = counter + 1;

        chimFunc = (void (*)(void))adapterPtr[0x51c / 4];
        (*chimFunc)();
        break;

    case 3:
        // Reset hardware event
        iob = _AllocOSMIOB(adapter);
        if (iob == NULL) {
            return;
        }

        // Set up IOB fields
        *((void **)((unsigned int)iob + 0x70)) = adapter;
        *((unsigned int *)((unsigned int)iob + 0x0c)) = 5;

        himHandle = (void *)adapterPtr[0x2a8 / 4];
        *((unsigned int *)((unsigned int)iob + 0x20)) = 0;
        *((void **)((unsigned int)iob + 0x34)) = (void *)_PostRoutineEventResetHW;
        *((void **)((unsigned int)iob + 0x28)) = himHandle;

        // Set reset pending flag
        adapterPtr[0x4c8 / 4] = 1;

        // Increment counter and call CHIM function
        counter = adapterPtr[0x578 / 4];
        adapterPtr[0x578 / 4] = counter + 1;

        chimFunc = (void (*)(void))adapterPtr[0x51c / 4];
        (*chimFunc)();
        break;

    case 4:
        // Freeze I/O
        adapterPtr[0x4c4 / 4] = 1;
        break;

    case 5:
        // Unfreeze I/O and send pending requests
        adapterPtr[0x4c4 / 4] = 0;

        // Get number of targets
        numTargets = adapterPtr[800 / 4];  // 0x320

        if (numTargets != 0) {
            targetStructures = (void **)&adapterPtr[0x480 / 4];

            for (targetIndex = 0; targetIndex < numTargets; targetIndex++) {
                if (targetStructures[targetIndex] != NULL) {
                    SendIOBsMaybe(targetStructures[targetIndex]);
                }
            }
        }
        break;

    default:
        // Unknown event
        eventName = IOFindNameForValue(eventType, (void *)0x00230ca0);
        IOLog("AdaptecU2SCSI: OSMEvent: %s\n", eventName);
        break;
    }
}

/*
 * SendIOBsMaybe - Send queued I/O requests to hardware
 *
 * From decompiled code:
 *   void SendIOBsMaybe(int *param_1)
 *   {
 *       piVar1 = (int *)param_1[0x23];  // Queue at offset 0x8c in target
 *       iVar4 = *param_1;                // Adapter pointer
 *
 *       // Check if queue not empty and not frozen/busy
 *       if (((param_1 + 0x23 != piVar1) && (*(int *)(iVar4 + 0x4c4) != 1)) &&
 *          (*(int *)(iVar4 + 0x4c0) != 1)) {
 *           while (*(int *)(iVar4 + 0x4c8) != 1) {
 *               // Remove IOB from waiting queue
 *               // Schedule timeout if needed
 *               // Call CHIM to execute IOB
 *               // Add to active queue
 *           }
 *       }
 *   }
 *
 * This walks the target's waiting queue and submits IOBs to the CHIM
 * for hardware execution, as long as the adapter is not frozen or busy.
 *
 * Target structure offsets (from decompiled code):
 * - 0x00: adapter pointer
 * - 0x8c (0x23*4): waiting queue head
 * - 0x90 (0x24*4): waiting queue tail
 * - 0x94 (0x25*4): active queue head
 * - 0x98 (0x26*4): active queue tail
 *
 * Adapter flags:
 * - 0x4c0: PAC pending
 * - 0x4c4: Freeze flag
 * - 0x4c8: Reset pending
 * - 0x51c: CHIM execute function pointer
 * - 0x578: Counter
 *
 * IOB offsets:
 * - 0x20: scsiReq pointer
 * - 0xc0 (0x30*4): prev link
 * - 0xc4 (0x31*4): next link
 *
 * @param targetStruct Pointer to target structure
 */
void SendIOBsMaybe(void *targetStruct)
{
    unsigned int **targetPtr = (unsigned int **)targetStruct;
    unsigned int *adapterPtr;
    unsigned int *iob;
    unsigned int *queueHead;
    unsigned int *prev;
    unsigned int *next;
    void *scsiReq;
    unsigned int timeoutField;
    void (*chimExecute)(void *);

    if (targetStruct == NULL) {
        return;
    }

    // Get adapter pointer from target (offset 0x00)
    adapterPtr = (unsigned int *)targetPtr[0];

    // Get head of waiting queue (offset 0x8c = 0x23 * 4)
    iob = (unsigned int *)targetPtr[0x23];
    queueHead = (unsigned int *)&targetPtr[0x23];

    // Check if queue is not empty
    if ((unsigned int *)queueHead == iob) {
        return;
    }

    // Check adapter flags: not frozen and not PAC pending
    if (adapterPtr[0x4c4 / 4] == 1) {
        return;
    }
    if (adapterPtr[0x4c0 / 4] == 1) {
        return;
    }

    // Process IOBs while reset is not pending
    while (adapterPtr[0x4c8 / 4] != 1) {
        // Get prev/next links from IOB (offsets 0xc0, 0xc4)
        prev = (unsigned int *)iob[0x30];  // 0xc0 / 4
        next = (unsigned int *)iob[0x31];  // 0xc4 / 4

        // Remove IOB from waiting queue
        if (queueHead == prev) {
            // Update tail
            targetPtr[0x24] = (unsigned int *)next;
        } else {
            // Link prev's next to our next
            prev[0x31] = (unsigned int)next;
        }

        if (queueHead == next) {
            // Update head
            targetPtr[0x23] = (unsigned int *)prev;
        } else {
            // Link next's prev to our prev
            next[0x30] = (unsigned int)prev;
        }

        // Check if timeout should be scheduled
        scsiReq = (void *)iob[0x20 / 4];  // scsiReq at offset 0x20 in IOB
        if (scsiReq != NULL) {
            timeoutField = *((unsigned int *)((unsigned int)scsiReq + 0x10));
            if (timeoutField != 0) {
                timeoutField = *((unsigned int *)((unsigned int)timeoutField + 0x18));
                if (timeoutField != 0) {
                    // Schedule timeout callback
                    IOScheduleFunc(_AdaptecU2SCSITimeout, iob);
                }
            }
        }

        // Increment counter
        adapterPtr[0x578 / 4] = adapterPtr[0x578 / 4] + 1;

        // Call CHIM to execute the IOB
        chimExecute = (void (*)(void *))adapterPtr[0x51c / 4];
        (*chimExecute)(iob);

        // Add IOB to active queue (offsets 0x94, 0x98)
        next = (unsigned int *)targetPtr[0x26];  // Active queue tail
        queueHead = (unsigned int *)&targetPtr[0x25];  // Active queue head

        if (queueHead == next) {
            // Empty active queue
            targetPtr[0x25] = (unsigned int *)iob;
        } else {
            // Add to tail
            next[0x30] = (unsigned int)iob;
        }

        iob[0x31] = (unsigned int)next;
        iob[0x30] = (unsigned int)queueHead;
        targetPtr[0x26] = (unsigned int *)iob;

        // Get next IOB from waiting queue
        iob = (unsigned int *)targetPtr[0x23];

        // Check exit conditions
        if ((unsigned int *)&targetPtr[0x23] == iob) {
            return;  // Queue empty
        }
        if (adapterPtr[0x4c4 / 4] == 1) {
            return;  // Frozen
        }
        if (adapterPtr[0x4c0 / 4] == 1) {
            return;  // PAC pending
        }
    }
}

/*
 * ValidateTargets - Validate all target structures
 * Forward declaration - actual implementation would validate target state
 */
void _ValidateTargets(void *adapter);

/*
 * PostRoutineEventPAC - Post-routine callback for PAC events
 *
 * From decompiled code:
 *   undefined4 _PostRoutineEventPAC(int param_1)
 *   {
 *       int iVar1;
 *
 *       iVar1 = *(int *)(param_1 + 0x70);
 *       _ValidateTargets();
 *       *(undefined4 *)(iVar1 + 0x4c0) = 0;
 *       *(int *)(iVar1 + 0x578) = *(int *)(iVar1 + 0x578) + -1;
 *       _FreeOSMIOB(iVar1, param_1);
 *       return 0;
 *   }
 *
 * This is called when a PAC (Poll And Complete) operation finishes.
 * It:
 * 1. Gets adapter pointer from IOB (offset 0x70)
 * 2. Validates all targets
 * 3. Clears PAC pending flag (0x4c0)
 * 4. Decrements counter (0x578)
 * 5. Frees the IOB
 *
 * @param iob The IOB used for the PAC operation
 * @return 0
 */
int _PostRoutineEventPAC(void *iob)
{
    void *adapter;
    unsigned int *adapterPtr;

    if (iob == NULL) {
        return 0;
    }

    // Get adapter pointer from IOB (offset 0x70)
    adapter = *((void **)((unsigned int)iob + 0x70));
    adapterPtr = (unsigned int *)adapter;

    // Validate all targets
    _ValidateTargets(adapter);

    // Clear PAC pending flag
    adapterPtr[0x4c0 / 4] = 0;

    // Decrement counter
    adapterPtr[0x578 / 4] = adapterPtr[0x578 / 4] - 1;

    // Free the IOB
    _FreeOSMIOB(adapter, iob);

    return 0;
}

/*
 * PostRoutineEventResetHW - Post-routine callback for hardware reset events
 *
 * From decompiled code:
 *   undefined4 _PostRoutineEventResetHW(int param_1)
 *   {
 *       iVar3 = *(int *)(param_1 + 0x70);
 *       *(undefined4 *)(iVar3 + 0x4c8) = 0;
 *       if (*(int *)(param_1 + 0x2c) == 1) {
 *           *(int *)(iVar3 + 0x578) = *(int *)(iVar3 + 0x578) + -1;
 *           _FreeOSMIOB(iVar3, param_1);
 *           iVar2 = _AllocOSMIOB(iVar3);
 *           // Set up PAC IOB
 *           (**(code **)(iVar3 + 0x51c))();
 *       } else {
 *           _IOPanic("AdaptecU2SCSI: Hardware reset failed.\n");
 *       }
 *       return 0;
 *   }
 *
 * This is called when a hardware reset operation finishes.
 * It:
 * 1. Clears reset pending flag (0x4c8)
 * 2. Checks reset status (offset 0x2c in IOB)
 * 3. If success:
 *    - Decrements counter, frees reset IOB
 *    - Allocates new IOB for PAC operation
 *    - Triggers PAC to complete the reset sequence
 * 4. If failed:
 *    - Panics the system (unrecoverable)
 *
 * @param iob The IOB used for the reset operation
 * @return 0
 */
int _PostRoutineEventResetHW(void *iob)
{
    void *adapter;
    unsigned int *adapterPtr;
    unsigned int *iobPtr;
    void *pacIOB;
    void *himHandle;
    int resetStatus;
    void (*chimFunc)(void);

    if (iob == NULL) {
        return 0;
    }

    iobPtr = (unsigned int *)iob;

    // Get adapter pointer from IOB (offset 0x70)
    adapter = *((void **)((unsigned int)iob + 0x70));
    adapterPtr = (unsigned int *)adapter;

    // Clear reset pending flag
    adapterPtr[0x4c8 / 4] = 0;

    // Check reset status (offset 0x2c in IOB)
    resetStatus = iobPtr[0x2c / 4];

    if (resetStatus == 1) {
        // Reset succeeded

        // Decrement counter
        adapterPtr[0x578 / 4] = adapterPtr[0x578 / 4] - 1;

        // Free the reset IOB
        _FreeOSMIOB(adapter, iob);

        // Allocate new IOB for PAC operation
        pacIOB = _AllocOSMIOB(adapter);
        if (pacIOB == NULL) {
            IOLog("AdaptecU2SCSI: Cannot allocate PAC IOB after reset.\n");
            return 0;
        }

        // Set up PAC IOB (same as OSMEvent case 1/2)
        *((void **)((unsigned int)pacIOB + 0x70)) = adapter;
        *((unsigned int *)((unsigned int)pacIOB + 0x0c)) = 6;

        himHandle = *((void **)((unsigned int)iob + 0x28));  // Copy from reset IOB
        *((void **)((unsigned int)pacIOB + 0x34)) = (void *)_PostRoutineEventPAC;
        *((unsigned int *)((unsigned int)pacIOB + 0x20)) = 0;
        *((void **)((unsigned int)pacIOB + 0x28)) = himHandle;

        // Set PAC pending flag
        adapterPtr[0x4c0 / 4] = 1;

        // Increment counter
        adapterPtr[0x578 / 4] = adapterPtr[0x578 / 4] + 1;

        // Call CHIM function
        chimFunc = (void (*)(void))adapterPtr[0x51c / 4];
        (*chimFunc)();

    } else {
        // Reset failed - this is fatal
        IOPanic("AdaptecU2SCSI: Hardware reset failed.\n");
    }

    return 0;
}

/*
 * ValidateTargets - Validate all target structures
 *
 * Based on decompiled code from binary.
 * This is called after PAC to ensure all targets are in a consistent state.
 * It walks through all target structures and checks their state via CHIM.
 * If a target's unit handle returns a status of 2 (likely disconnected/invalid),
 * the target structure is cleaned up and freed.
 *
 * Function signature from decompiled code:
 * void _ValidateTargets(int param_1)
 *
 * Decompiled structure:
 * - param_1+0x70 gets adapter pointer (but we pass adapter directly)
 * - Check numTargets at adapter+0x320 (800 decimal)
 * - Iterate through targetStructures array at adapter+0x480
 * - For each target:
 *   - Call CHIM function at adapter+0x524 with unit handle from target+0x04
 *   - If function returns 2:
 *     - CleanupWaitingQ(target)
 *     - IOFree buffer at target+0x08 with size from target+0x0c
 *     - IOFree target structure (0x9c bytes)
 *     - Clear target pointer in array
 *
 * @param adapter Pointer to AdaptecU2SCSI adapter instance
 */
void _ValidateTargets(void *adapter)
{
    unsigned int *adapterPtr;
    unsigned int numTargets;
    unsigned int targetIndex;
    void **targetStructuresArray;
    void *targetStruct;
    unsigned int *targetPtr;
    int (**chimFuncs)(void);
    int (*getUnitState)(void *);
    int unitState;
    void *unitHandle;
    void *unitBuffer;
    unsigned int unitBufferSize;

    if (adapter == NULL) {
        return;
    }

    adapterPtr = (unsigned int *)adapter;

    // Get number of targets from adapter offset 0x320 (800 decimal)
    numTargets = adapterPtr[0x320 / 4];

    if (numTargets == 0) {
        return;
    }

    // Get pointer to chimFunctionTable at offset 0x4cc
    chimFuncs = (int (**)(void))&adapterPtr[0x4cc / 4];

    // Get the CHIM function at offset 0x524
    // 0x524 - 0x4cc = 0x58 bytes = 22 words = index 22
    getUnitState = (int (*)(void *))chimFuncs[22];

    // Get pointer to targetStructures array at offset 0x480
    targetStructuresArray = (void **)&adapterPtr[0x480 / 4];

    // Iterate through all targets
    for (targetIndex = 0; targetIndex < numTargets; targetIndex++) {
        targetStruct = targetStructuresArray[targetIndex];

        if (targetStruct != NULL) {
            targetPtr = (unsigned int *)targetStruct;

            // Get unit handle from target structure offset 0x04
            unitHandle = (void *)targetPtr[0x04 / 4];

            // Call CHIM function to get unit state
            unitState = getUnitState(unitHandle);

            // If state is 2, the target is invalid/disconnected and should be freed
            if (unitState == 2) {
                // Clean up the target's waiting queue
                _CleanupWaitingQ(targetStruct);

                // Free the unit info buffer
                // Buffer pointer at offset 0x08, size at offset 0x0c
                unitBuffer = (void *)targetPtr[0x08 / 4];
                unitBufferSize = targetPtr[0x0c / 4];

                if (unitBuffer != NULL && unitBufferSize > 0) {
                    IOFree(unitBuffer, unitBufferSize);
                }

                // Free the target structure itself (0x9c = 156 bytes)
                IOFree(targetStruct, 0x9c);

                // Clear the pointer in the target structures array
                targetStructuresArray[targetIndex] = NULL;
            }
        }
    }
}

/*
 * PostProbe - Post-routine callback for target probe completion
 *
 * Based on decompiled code from binary.
 * Called when a SCSI target probe operation completes.
 *
 * Function signature from decompiled code:
 * undefined4 _PostProbe(int param_1)
 *
 * Decompiled structure:
 * - param_1 is the IOB pointer
 * - Gets request object from IOB+0x20
 * - Gets adapter from IOB+0x70
 * - Gets target ID from request+0x10
 * - If probe succeeded (IOB+0x2c == 1):
 *   - Gets unit size via CHIM function at adapter+0x4fc
 *   - Allocates target structure (0x9c bytes)
 *   - Initializes waiting queue (offset 0x8c/0x23*4)
 *   - Initializes active queue (offset 0x94/0x25*4)
 *   - Allocates unit info buffer
 *   - Gets unit handle via CHIM function at adapter+0x504
 *   - Calls CHIM function at adapter+0x540 to get unit info
 *   - Stores target in adapter array at offset 0x480
 *   - For Ultra2 adapters (0x248 & 0xffff0000 == 0x500000):
 *     - Ensures min transfer period >= 400
 *     - Updates unit info via CHIM function at adapter+0x548
 * - Decrements I/O counter (adapter+0x578)
 * - Frees the probe IOB
 * - If request exists:
 *   - Sets request status based on probe result
 *   - Locks and unlocks request using CHIM functions
 */
int _PostProbe(void *iob)
{
    unsigned int *iobPtr = (unsigned int *)iob;
    void *request;
    void *adapter;
    unsigned char targetID;
    unsigned int *adapterPtr;
    int probeStatus;
    size_t unitSize;
    unsigned int *targetStruct;
    void *unitInfoBuffer;
    int unitHandle;
    void (**chimFuncs)(void);

    // Get request object from IOB offset 0x20
    request = (void *)iobPtr[0x20 / 4];

    // Get adapter from IOB offset 0x70
    adapter = (void *)iobPtr[0x70 / 4];
    adapterPtr = (unsigned int *)adapter;

    // Get target ID from request+0x10 (points to a byte)
    targetID = **(unsigned char **)((unsigned int)request + 0x10);

    // Get probe status from IOB offset 0x2c
    probeStatus = iobPtr[0x2c / 4];

    if (probeStatus == 1) {
        // Probe succeeded - create target structure

        // Get CHIM function pointer at adapter+0x4fc to get unit size
        chimFuncs = (void (**)(void))((unsigned int)adapter + 0x4fc);
        unitSize = (size_t)(*chimFuncs)((void *)adapterPtr[0x2a8 / 4]);

        // Allocate target structure (0x9c bytes = 156 bytes)
        targetStruct = (unsigned int *)IOMalloc(0x9c);
        bzero(targetStruct, 0x9c);

        // Initialize waiting queue at offset 0x8c (0x23 * 4)
        // Queue head points to itself initially (empty circular list)
        targetStruct[0x24] = (unsigned int)(targetStruct + 0x23);  // next
        targetStruct[0x23] = (unsigned int)(targetStruct + 0x23);  // prev

        // Initialize active queue at offset 0x94 (0x25 * 4)
        targetStruct[0x26] = (unsigned int)(targetStruct + 0x25);  // next
        targetStruct[0x25] = (unsigned int)(targetStruct + 0x25);  // prev

        // Store adapter pointer at offset 0x00
        targetStruct[0] = (unsigned int)adapter;

        // Allocate unit info buffer
        unitInfoBuffer = (void *)IOMalloc(unitSize);
        targetStruct[2] = (unsigned int)unitInfoBuffer;
        targetStruct[3] = unitSize;
        bzero(unitInfoBuffer, unitSize);

        // Get unit handle via CHIM function at adapter+0x504
        chimFuncs = (void (**)(void))((unsigned int)adapter + 0x504);
        unitHandle = (int)(*chimFuncs)((void *)adapterPtr[0x2a8 / 4], (void *)0xffff, unitInfoBuffer);
        targetStruct[1] = unitHandle;

        // Call CHIM function at adapter+0x540 to get unit info
        chimFuncs = (void (**)(void))((unsigned int)adapter + 0x540);
        (*chimFuncs)((void *)unitHandle, (void *)(targetStruct + 4));

        // Store target structure in adapter array at offset 0x480 + (targetID * 4)
        adapterPtr[(0x480 / 4) + targetID] = (unsigned int)targetStruct;

        // Check if this is an Ultra2 adapter (version field at 0x248)
        if ((adapterPtr[0x248 / 4] & 0xffff0000) == 0x500000) {
            // Ensure minimum transfer period >= 400
            // Transfer period is at offset 0x68 (0x1a * 4) in target struct
            if (targetStruct[0x1a] < 400) {
                targetStruct[0x1a] = 400;
            }

            // Update unit info via CHIM function at adapter+0x548
            chimFuncs = (void (**)(void))((unsigned int)adapter + 0x548);
            (*chimFuncs)((void *)targetStruct[1], (void *)(targetStruct + 4));
        }
    }

    // Decrement I/O counter at adapter offset 0x578
    adapterPtr[0x578 / 4] = adapterPtr[0x578 / 4] - 1;

    // Free the probe IOB
    _FreeOSMIOB(adapter, iob);

    // If request object exists, update its status
    if (request != NULL) {
        unsigned int *requestPtr = (unsigned int *)request;

        // Set request status at offset 0x18
        // Status is 0 if probe succeeded, non-zero if failed
        requestPtr[0x18 / 4] = (probeStatus != 1) ? 1 : 0;

        // Lock the request using CHIM function at adapter+0x5bc
        chimFuncs = (void (**)(void))((unsigned int)adapter + 0x5bc);
        (*chimFuncs)((void *)requestPtr[0x14 / 4], (void *)"lock");

        // Unlock the request using CHIM function at adapter+0x5c4
        chimFuncs = (void (**)(void))((unsigned int)adapter + 0x5c4);
        (*chimFuncs)((void *)requestPtr[0x14 / 4], (void *)"unlockWith:", (void *)1);
    }

    return 0;
}

/*
 * ProbeTarget - Initiate a SCSI target probe
 *
 * Based on decompiled code from binary.
 * Sends a probe command to a SCSI target to check if it exists.
 *
 * Function signature from decompiled code:
 * undefined4 _ProbeTarget(int param_1, int param_2)
 *
 * Decompiled structure:
 * - param_1 is the adapter pointer
 * - param_2 is the request object pointer
 * - Gets target ID from request+0x10
 * - If target ID matches adapter's own ID (at adapter+0x3b0):
 *   - Mark request as failed (status=1)
 *   - Lock and unlock request
 * - Otherwise:
 *   - Allocate IOB
 *   - Set function code 0x13 (probe)
 *   - Set post-routine to _PostProbe
 *   - Store request pointer at IOB+0x20
 *   - Set target ID in IOB's embedded structure
 *   - Increment I/O counter
 *   - Call CHIM execute function
 */
int ProbeTarget(void *adapter, void *request)
{
    unsigned int *adapterPtr = (unsigned int *)adapter;
    unsigned int *requestPtr = (unsigned int *)request;
    unsigned char targetID;
    void *iob;
    unsigned int *iobPtr;
    void *iobEmbedded;
    void (**chimFuncs)(void);

    // Get target ID from request+0x10 (points to a byte)
    targetID = **(unsigned char **)((unsigned int)request + 0x10);

    // Check if target ID is the adapter's own SCSI ID (at adapter+0x3b0)
    if (adapterPtr[0x3b0 / 4] == targetID) {
        // Can't probe our own ID - mark request as failed
        requestPtr[0x18 / 4] = 1;

        // Lock the request using CHIM function at adapter+0x5bc
        chimFuncs = (void (**)(void))((unsigned int)adapter + 0x5bc);
        (*chimFuncs)((void *)requestPtr[0x14 / 4], (void *)"lock");

        // Unlock the request using CHIM function at adapter+0x5c4
        chimFuncs = (void (**)(void))((unsigned int)adapter + 0x5c4);
        (*chimFuncs)((void *)requestPtr[0x14 / 4], (void *)"unlockWith:", (void *)1);
    }
    else {
        // Allocate IOB for probe operation
        iob = _AllocOSMIOB(adapter);
        iobPtr = (unsigned int *)iob;

        // Set adapter pointer at IOB offset 0x70
        iobPtr[0x70 / 4] = (unsigned int)adapter;

        // Set function code 0x13 (probe) at IOB offset 0xc
        iobPtr[0xc / 4] = 0x13;

        // Set post-routine callback to _PostProbe at IOB offset 0x34
        iobPtr[0x34 / 4] = (unsigned int)_PostProbe;

        // Get embedded structure pointer from IOB offset 0x1c
        iobEmbedded = (void *)iobPtr[0x1c / 4];

        // Clear some fields at IOB offsets 0x38 and 0x3c
        iobPtr[0x38 / 4] = 0;
        iobPtr[0x3c / 4] = 0;

        // Store request pointer at IOB offset 0x20
        iobPtr[0x20 / 4] = (unsigned int)request;

        // Store CHIM adapter handle at IOB offset 0x28
        iobPtr[0x28 / 4] = adapterPtr[0x2a8 / 4];

        // Set target ID in embedded structure at offset 0x10
        *((unsigned char *)iobEmbedded + 0x10) = targetID;

        // Clear LUN at embedded structure offset 0x12
        *((unsigned char *)iobEmbedded + 0x12) = 0;

        // Increment I/O counter at adapter offset 0x578
        adapterPtr[0x578 / 4] = adapterPtr[0x578 / 4] + 1;

        // Call CHIM execute function at adapter offset 0x51c
        chimFuncs = (void (**)(void))((unsigned int)adapter + 0x51c);
        (*chimFuncs)();
    }

    return 0;
}

/*
 * HandleHIMFrozen - Handle HIM frozen condition
 *
 * Based on decompiled code from binary.
 * Called when the HIM (Hardware Interface Module) reports a frozen condition.
 * Allocates an IOB to unfreeze the HIM queue.
 *
 * Function signature from decompiled code:
 * void _HandleHIMFrozen(int param_1)
 *
 * Decompiled structure:
 * - param_1 is the IOB pointer
 * - Gets target from IOB+0x70
 * - Allocates new IOB for unfreeze operation
 * - Sets function code 0xb (unfreeze)
 * - Sets post-routine to _PostUnfreezeHIMQueue
 * - Copies CHIM adapter handle from original IOB
 * - Adds new IOB to target's waiting queue
 * - Calls SendIOBsMaybe to dispatch
 */
void _HandleHIMFrozen(void *iob)
{
    unsigned int *iobPtr = (unsigned int *)iob;
    unsigned int *targetStruct;
    void *adapter;
    void *unfreezeIOB;
    unsigned int *unfreezePtr;
    unsigned int chimHandle;
    unsigned int *queueNext;

    // Get target structure from IOB offset 0x70
    targetStruct = *(unsigned int **)((unsigned int)iob + 0x70);

    // Get adapter from target structure offset 0x00
    adapter = (void *)targetStruct[0];

    // Allocate IOB for unfreeze operation
    unfreezeIOB = _AllocOSMIOB(adapter);
    unfreezePtr = (unsigned int *)unfreezeIOB;

    // Set target pointer at IOB offset 0x70
    unfreezePtr[0x70 / 4] = (unsigned int)targetStruct;

    // Set function code 0xb (unfreeze) at IOB offset 0xc
    unfreezePtr[0xc / 4] = 0xb;

    // Get CHIM adapter handle from original IOB offset 0x28
    chimHandle = iobPtr[0x28 / 4];

    // Set post-routine callback to _PostUnfreezeHIMQueue at IOB offset 0x34
    unfreezePtr[0x34 / 4] = (unsigned int)_PostUnfreezeHIMQueue;

    // Store CHIM adapter handle at IOB offset 0x28
    unfreezePtr[0x28 / 4] = chimHandle;

    // Add to target's waiting queue at offset 0x8c (0x23 * 4)
    // Get current queue next pointer
    queueNext = (unsigned int *)targetStruct[0x24];

    if (targetStruct + 0x23 == queueNext) {
        // Queue is empty, set prev to new IOB
        targetStruct[0x23] = (unsigned int)unfreezeIOB;
    }
    else {
        // Insert at end, set prev IOB's next pointer
        queueNext[0x30] = (unsigned int)unfreezeIOB;
    }

    // Set new IOB's queue links
    unfreezePtr[0xc4 / 4] = (unsigned int)queueNext;  // next
    unfreezePtr[0xc0 / 4] = (unsigned int)(targetStruct + 0x23);  // prev

    // Update queue head's next pointer
    targetStruct[0x24] = (unsigned int)unfreezeIOB;

    // Try to send waiting IOBs
    SendIOBsMaybe(targetStruct);
}

/*
 * NormalPostRoutine - Normal I/O completion callback
 *
 * Based on decompiled code from binary.
 * Called when a normal SCSI I/O operation completes.
 * Handles various completion statuses and updates the request object.
 *
 * Function signature from decompiled code:
 * undefined4 NormalPostRoutine(int param_1)
 *
 * Decompiled structure:
 * - param_1 is the IOB pointer
 * - Gets target from IOB+0x70
 * - Gets adapter from target+0x00
 * - Decrements I/O counters (adapter+0x578, adapter+0x5a0)
 * - Removes IOB from active queue
 * - Maps IOB status (IOB+0x2c) to SCSI status codes
 * - Handles special cases:
 *   - 0x23: Retry - decrements retry count, re-queues to waiting queue
 *   - 0x30/0x31: HIM frozen - calls _HandleHIMFrozen
 *   - 0x50: Fatal error - triggers bus reset
 * - Calculates elapsed time from timestamps
 * - Updates request object with status and timing
 * - Unschedules timeout
 * - Frees IOB
 * - Unlocks request
 */
int NormalPostRoutine(void *iob)
{
    unsigned int *iobPtr = (unsigned int *)iob;
    unsigned int *targetStruct;
    void *adapter;
    unsigned int *adapterPtr;
    unsigned int iobStatus;
    unsigned int scsiStatus;
    unsigned char senseKey;
    unsigned int *queuePrev;
    unsigned int *queueNext;
    int shouldResetBus;
    void *request;
    unsigned int *requestPtr;
    unsigned int *cmdPtr;
    unsigned int startTimeSec, startTimeNsec;
    unsigned int endTimeSec, endTimeNsec;
    unsigned int elapsedSec, elapsedNsec;
    unsigned int bytesTransferred;
    void (**chimFuncs)(void);

    // Get target structure from IOB offset 0x70
    targetStruct = *(unsigned int **)((unsigned int)iob + 0x70);

    // Get adapter from target structure offset 0x00
    adapter = (void *)targetStruct[0];
    adapterPtr = (unsigned int *)adapter;

    shouldResetBus = 0;
    scsiStatus = 0xe;  // Default error
    senseKey = 0;

    // Decrement I/O counter at adapter offset 0x578
    adapterPtr[0x578 / 4] = adapterPtr[0x578 / 4] - 1;

    // Decrement another counter at adapter offset 0x5a0
    adapterPtr[0x5a0 / 4] = adapterPtr[0x5a0 / 4] - 1;

    // Remove IOB from active queue (links at IOB offsets 0xc0, 0xc4)
    queuePrev = (unsigned int *)iobPtr[0xc0 / 4];
    queueNext = (unsigned int *)iobPtr[0xc4 / 4];

    // Update prev element's next pointer
    if (targetStruct + 0x25 == queuePrev) {
        // Prev is queue head
        targetStruct[0x26] = (unsigned int)queueNext;
    }
    else {
        // Prev is another IOB at offset 0xc4
        queuePrev[0x31] = (unsigned int)queueNext;
    }

    // Update next element's prev pointer
    if (targetStruct + 0x25 == queueNext) {
        // Next is queue head
        targetStruct[0x25] = (unsigned int)queuePrev;
    }
    else {
        // Next is another IOB at offset 0xc0
        queueNext[0x30] = (unsigned int)queuePrev;
    }

    // Get IOB status from offset 0x2c
    iobStatus = iobPtr[0x2c / 4];

    // Map IOB status to SCSI status
    switch (iobStatus) {
    case 1:  // Success
        scsiStatus = 0;
        senseKey = 0;
        break;

    case 2:  // Check condition
        scsiStatus = 2;
        senseKey = 2;
        break;

    case 3:  // Condition met
        scsiStatus = 3;
        senseKey = 2;
        break;

    case 0x10:  // Underrun
    case 0x11:  // Overrun
        scsiStatus = 0xe;
        break;

    case 0x20:  // Selection timeout
        scsiStatus = 1;
        break;

    case 0x22:  // Data error
    case 0x40:  // Protocol error
    case 0x41:  // Phase error
    case 0x42:  // Parity error
    case 0x43:  // Hardware error
    case 0x44:  // SCSI bus error
    case 0x45:  // Command error
        scsiStatus = 0xc;
        break;

    case 0x23:  // Retry
        scsiStatus = 0x15;
        // Check retry count at IOB offset 0x78
        if (iobPtr[0x78 / 4] != 0) {
            // Decrement retry count
            iobPtr[0x78 / 4] = iobPtr[0x78 / 4] - 1;

            // Re-add to waiting queue at offset 0x8c (0x23 * 4)
            queueNext = (unsigned int *)targetStruct[0x24];

            if (targetStruct + 0x23 == queueNext) {
                // Queue is empty
                targetStruct[0x23] = (unsigned int)iob;
            }
            else {
                // Insert at end
                queueNext[0x30] = (unsigned int)iob;
            }

            // Set IOB's queue links
            iobPtr[0xc4 / 4] = (unsigned int)queueNext;
            iobPtr[0xc0 / 4] = (unsigned int)(targetStruct + 0x23);

            // Update queue head
            targetStruct[0x24] = (unsigned int)iob;

            // Try to send waiting IOBs
            SendIOBsMaybe(targetStruct);
        }
        break;

    case 0x24:  // Queue full
        senseKey = 0;
        // Set status based on field at IOB offset 0x60
        scsiStatus = (iobPtr[0x60 / 4] == 0) ? 4 : 0;
        break;

    case 0x30:  // HIM frozen (abort)
        senseKey = 8;
        _HandleHIMFrozen(iob);
        break;

    case 0x31:  // HIM frozen (reset)
        senseKey = 0x28;
        _HandleHIMFrozen(iob);
        break;

    case 0x46:  // Aborted
        scsiStatus = 6;
        break;

    case 0x50:  // Fatal error
        scsiStatus = 0x16;
        shouldResetBus = 1;
        break;

    default:
        scsiStatus = 0xe;
        shouldResetBus = 1;
        break;
    }

    // Get current timestamp
    IOGetTimestamp(&endTimeSec, &endTimeNsec);

    // Get request object from IOB offset 0x20
    request = (void *)iobPtr[0x20 / 4];
    requestPtr = (unsigned int *)request;

    // Get start timestamp from IOB offsets 0x7c, 0x80
    startTimeSec = iobPtr[0x7c / 4];
    startTimeNsec = iobPtr[0x80 / 4];

    // Set request status at offset 0x18
    requestPtr[0x18 / 4] = scsiStatus;

    // Get command structure from request offset 0x10
    cmdPtr = (unsigned int *)requestPtr[0x10 / 4];

    // Set command status at offset 0x20
    cmdPtr[0x20 / 4] = scsiStatus;

    // Set sense key at offset 0x24
    *((unsigned char *)cmdPtr + 0x24) = senseKey;

    // Calculate elapsed time
    if (endTimeNsec < startTimeNsec) {
        elapsedSec = endTimeSec - startTimeSec - 1;
        elapsedNsec = (1000000000 + endTimeNsec) - startTimeNsec;
    }
    else {
        elapsedSec = endTimeSec - startTimeSec;
        elapsedNsec = endTimeNsec - startTimeNsec;
    }

    // Store elapsed time in command at offsets 0x2c, 0x30
    cmdPtr[0x2c / 4] = elapsedSec;
    cmdPtr[0x30 / 4] = elapsedNsec;

    // Calculate bytes transferred (requested - residual)
    // Requested at IOB offset 0x50, residual at offset 0x60
    bytesTransferred = iobPtr[0x50 / 4] - iobPtr[0x60 / 4];
    cmdPtr[0x28 / 4] = bytesTransferred;

    // Unschedule timeout
    IOUnscheduleFunc(_AdaptecU2SCSITimeout, iob);

    // Free the IOB
    _FreeOSMIOB(adapter, iob);

    // Lock the request using CHIM function at adapter+0x5bc
    chimFuncs = (void (**)(void))((unsigned int)adapter + 0x5bc);
    (*chimFuncs)((void *)requestPtr[0x14 / 4], (void *)"lock");

    // Unlock the request using CHIM function at adapter+0x5c4
    chimFuncs = (void (**)(void))((unsigned int)adapter + 0x5c4);
    (*chimFuncs)((void *)requestPtr[0x14 / 4], (void *)"unlockWith:", (void *)1);

    // If fatal error, reset the bus
    if (shouldResetBus) {
        ResetSCSIBus(adapter, 0);
    }

    return 0;
}

/*
 * PostUnfreezeHIMQueue - Post-routine callback for HIM queue unfreeze
 *
 * Based on decompiled code from binary.
 * Called when a HIM queue unfreeze operation completes.
 *
 * Function signature from decompiled code:
 * undefined4 _PostUnfreezeHIMQueue(int param_1)
 *
 * Decompiled structure:
 * - param_1 is the IOB pointer
 * - Gets target from IOB+0x70
 * - Gets adapter from target+0x00
 * - Decrements I/O counter (adapter+0x578)
 * - Removes IOB from active queue
 * - Checks unfreeze status (IOB+0x2c)
 * - If successful (status == 1):
 *   - Frees the IOB
 * - If failed:
 *   - Panics the system (unfreeze failure is fatal)
 */
int _PostUnfreezeHIMQueue(void *iob)
{
    unsigned int *iobPtr = (unsigned int *)iob;
    unsigned int *targetStruct;
    void *adapter;
    unsigned int *adapterPtr;
    unsigned int *queuePrev;
    unsigned int *queueNext;
    int unfreezeStatus;

    // Get target structure from IOB offset 0x70
    targetStruct = *(unsigned int **)((unsigned int)iob + 0x70);

    // Get adapter from target structure offset 0x00
    adapter = (void *)targetStruct[0];
    adapterPtr = (unsigned int *)adapter;

    // Decrement I/O counter at adapter offset 0x578
    adapterPtr[0x578 / 4] = adapterPtr[0x578 / 4] - 1;

    // Remove IOB from active queue (links at IOB offsets 0xc0, 0xc4)
    queuePrev = (unsigned int *)iobPtr[0xc0 / 4];
    queueNext = (unsigned int *)iobPtr[0xc4 / 4];

    // Update prev element's next pointer
    if (targetStruct + 0x25 == queuePrev) {
        // Prev is queue head (active queue at 0x94 = 0x25 * 4)
        targetStruct[0x26] = (unsigned int)queueNext;
    }
    else {
        // Prev is another IOB at offset 0xc4
        queuePrev[0x31] = (unsigned int)queueNext;
    }

    // Update next element's prev pointer
    if (targetStruct + 0x25 == queueNext) {
        // Next is queue head
        targetStruct[0x25] = (unsigned int)queuePrev;
    }
    else {
        // Next is another IOB at offset 0xc0
        queueNext[0x30] = (unsigned int)queuePrev;
    }

    // Get unfreeze status from IOB offset 0x2c
    unfreezeStatus = iobPtr[0x2c / 4];

    if (unfreezeStatus == 1) {
        // Unfreeze succeeded - free the IOB
        _FreeOSMIOB(adapter, iob);
    }
    else {
        // Unfreeze failed - this is fatal, panic the system
        IOPanic("AdaptecU2SCSI: Cannot unfreeze target queue.\n");
    }

    return 0;
}


















/*
 * Helper functions for byte swapping in string read operations
 * These inline functions handle different endianness modes for bulk reads
 */

// 16-bit swap helpers






// 32-bit swap helpers
































/*
 * EnqueueOsmIOB - Add an IOB to a target's waiting queue
 *
 * Based on decompiled code from binary.
 * Enqueues an I/O block at the tail of a target's waiting queue and
 * attempts to send queued I/O to the hardware. This implements a
 * doubly-linked circular queue insertion.
 *
 * Function signature from decompiled code:
 * void _EnqueueOsmIOB(int param_1, int param_2)
 *
 * Decompiled structure:
 * - param_1 = IOB to enqueue
 * - param_2 = target structure pointer
 * - Gets current tail from target+0x90
 * - If queue is empty (tail == head at target+0x8c):
 *   - Set head to point to new IOB
 * - Else:
 *   - Link old tail's next to new IOB
 * - Set new IOB's next pointer to old tail
 * - Set new IOB's prev pointer to queue head
 * - Set queue tail to new IOB
 * - Call SendIOBsMaybe to process queue
 *
 * Target structure queue offsets:
 * - 0x8c (0x23*4): Queue head (prev link of first element)
 * - 0x90 (0x24*4): Queue tail (next link of last element)
 *
 * IOB queue link offsets:
 * - 0xc0 (0x30*4): Prev link
 * - 0xc4 (0x31*4): Next link
 *
 * This maintains a circular doubly-linked list where:
 * - Empty queue: head->next == head, head->prev == head
 * - Non-empty: head->next = first IOB, head->prev = last IOB
 *
 * @param iob IOB to enqueue
 * @param targetStruct Target structure containing the waiting queue
 */
void _EnqueueOsmIOB(void *iob, void *targetStruct)
{
    unsigned int *iobPtr;
    unsigned int *targetPtr;
    unsigned int *queueHead;
    unsigned int *currentTail;

    iobPtr = (unsigned int *)iob;
    targetPtr = (unsigned int *)targetStruct;

    // Get queue head pointer at target offset 0x8c (0x23 * 4)
    queueHead = targetPtr + 0x23;

    // Get current tail from target offset 0x90 (0x24 * 4)
    currentTail = (unsigned int *)targetPtr[0x24];

    // Check if queue is empty (tail points back to head)
    if (currentTail == queueHead) {
        // Queue is empty - set head to point to new IOB
        targetPtr[0x23] = (unsigned int)iob;
    }
    else {
        // Queue not empty - link old tail's next to new IOB
        // Old tail's next link is at offset 0xc4 (0x31 * 4)
        currentTail[0x31] = (unsigned int)iob;
    }

    // Set new IOB's next pointer to old tail (offset 0xc4 = 0x31 * 4)
    iobPtr[0x31] = (unsigned int)currentTail;

    // Set new IOB's prev pointer to queue head (offset 0xc0 = 0x30 * 4)
    iobPtr[0x30] = (unsigned int)queueHead;

    // Update queue tail to point to new IOB (offset 0x90 = 0x24 * 4)
    targetPtr[0x24] = (unsigned int)iob;

    // Try to send queued IOBs to hardware
    SendIOBsMaybe(targetStruct);
}

/*
 * _PostProbe - Completion callback for target probe operations
 *
 * Decompiled from: undefined4 _PostProbe(int param_1)
 *
 * Called by CHIM when a target probe/initialization IOB completes.
 * If probe succeeded, allocates and initializes a target structure,
 * creates CHIM target handle, and stores it in the adapter's target array.
 *
 * @param iob The completed IOB pointer
 * @return 0 on success
 */
void _PostProbe(void *iob)
{
    unsigned char targetID;
    unsigned char **targetLunPtr;
    size_t targetStructSize;
    unsigned int *targetStruct;
    unsigned int *iobPtr;
    unsigned int *adapterPtr;
    unsigned int *requestPtr;
    void *request;
    void *adapter;
    void *chimTargetMem;
    void *targetHandle;
    void *himHandle;
    int probeStatus;
    unsigned int pciDeviceID;
    unsigned int transferSpeed;
    id conditionLock;
    size_t (*getTargetSize)(void *);
    void *(*createTarget)(void *, unsigned int, void *);
    void (*getProfile)(void *, void *);
    void (*setProfile)(void *, void *);

    iobPtr = (unsigned int *)iob;

    // Get request pointer from IOB (offset 0x20)
    request = (void *)iobPtr[0x20 / 4];
    requestPtr = (unsigned int *)request;

    // Get adapter pointer from IOB (offset 0x70)
    adapter = (void *)iobPtr[0x70 / 4];
    adapterPtr = (unsigned int *)adapter;

    // Get target ID from request structure
    targetLunPtr = (unsigned char **)(requestPtr + 0x10 / 4);
    targetID = **targetLunPtr;

    // Check probe status from IOB (offset 0x2c)
    probeStatus = iobPtr[0x2c / 4];

    if (probeStatus == 1) {
        // Probe succeeded - allocate and initialize target structure

        // Get HIM handle from adapter (offset 0x2a8)
        himHandle = (void *)adapterPtr[0x2a8 / 4];

        // Get CHIM function pointers
        // Function at offset 0x4fc = index 12: get target structure size
        getTargetSize = (size_t (*)(void *))adapterPtr[0x4fc / 4];
        targetStructSize = getTargetSize(himHandle);

        // Allocate target structure (156 bytes = 0x9c)
        targetStruct = (unsigned int *)IOMalloc(0x9c);
        bzero(targetStruct, 0x9c);

        // Initialize queue heads in target structure
        // First queue (offsets 0x8c-0x93):
        targetStruct[0x90 / 4] = (unsigned int)(targetStruct + 0x8c / 4);  // head
        targetStruct[0x8c / 4] = (unsigned int)(targetStruct + 0x8c / 4);  // tail

        // Second queue (offsets 0x94-0x9b):
        targetStruct[0x98 / 4] = (unsigned int)(targetStruct + 0x94 / 4);  // head
        targetStruct[0x94 / 4] = (unsigned int)(targetStruct + 0x94 / 4);  // tail

        // Store adapter pointer at offset 0
        targetStruct[0] = (unsigned int)adapter;

        // Allocate CHIM target structure
        chimTargetMem = IOMalloc(targetStructSize);
        targetStruct[0x8 / 4] = (unsigned int)chimTargetMem;  // CHIM target struct pointer
        targetStruct[0xc / 4] = targetStructSize;             // CHIM target struct size
        bzero(chimTargetMem, targetStructSize);

        // Create target handle via CHIM
        // Function at offset 0x504 = index 14: create target
        createTarget = (void *(*)(void *, unsigned int, void *))adapterPtr[0x504 / 4];
        targetHandle = createTarget(himHandle, 0xffff, chimTargetMem);
        targetStruct[0x4 / 4] = (unsigned int)targetHandle;  // Store target handle

        // Get profile from CHIM
        // Function at offset 0x540 = index 29: get profile
        getProfile = (void (*)(void *, void *))adapterPtr[0x540 / 4];
        getProfile(targetHandle, targetStruct + 0x10 / 4);  // Profile area at offset 0x10

        // Store target structure in adapter's targetStructures array (offset 0x480)
        adapterPtr[0x480 / 4 + targetID] = (unsigned int)targetStruct;

        // Check PCI device ID (offset 0x248)
        pciDeviceID = adapterPtr[0x248 / 4];

        // For specific adapter types (0x005xxxxx), ensure minimum transfer speed
        if ((pciDeviceID & 0xffff0000) == 0x00500000) {
            // Get transfer speed from profile (offset 0x68)
            transferSpeed = targetStruct[0x68 / 4];

            // Ensure minimum speed of 400
            if (transferSpeed < 400) {
                targetStruct[0x68 / 4] = 400;
            }

            // Set modified profile back to CHIM
            // Function at offset 0x548 = index 31: set profile
            setProfile = (void (*)(void *, void *))adapterPtr[0x548 / 4];
            setProfile(targetHandle, targetStruct + 0x10 / 4);
        }
    }

    // Decrement sample counter (offset 0x578)
    adapterPtr[0x578 / 4] = adapterPtr[0x578 / 4] - 1;

    // Free the IOB
    _FreeOSMIOB(adapter, iob);

    // Signal completion to waiting thread
    if (request != NULL) {
        // Set status in request structure (offset 0x18)
        // Status = 0 if probe succeeded (probeStatus == 1), 1 if failed
        requestPtr[0x18 / 4] = (probeStatus != 1) ? 1 : 0;

        // Get condition lock from request (offset 0x14)
        conditionLock = (id)requestPtr[0x14 / 4];

        // Call condLockLock (offset 0x5bc)
        (*(void (*)(id, SEL))adapterPtr[0x5bc / 4])(conditionLock, @selector(lock));

        // Call condLockUnlockWith (offset 0x5c4)
        (*(void (*)(id, SEL, int))adapterPtr[0x5c4 / 4])(conditionLock, @selector(unlockWith:), 1);
    }
}

/*
 * _ProbeTarget - Probe and initialize a SCSI target
 *
 * Decompiled from: undefined4 _ProbeTarget(int param_1,int param_2)
 *
 * This function is called from the I/O thread when a type 1 (probe) request
 * is dequeued. It either rejects the probe if the target is the adapter itself,
 * or allocates an IOB and queues a probe command to the CHIM.
 *
 * @param adapter The adapter instance (AdaptecU2SCSI object)
 * @param request Pointer to probe request structure
 * @return 0 on success
 */
void _ProbeTarget(id adapter, void *request)
{
    unsigned char targetID;
    unsigned char **targetLunPtr;
    void *iob;
    unsigned int *iobPtr;
    unsigned int *cdbPtr;
    unsigned int *adapterPtr;
    unsigned int *requestPtr;
    void *himHandle;
    id conditionLock;
    void (*queueIOB)(void);

    requestPtr = (unsigned int *)request;
    adapterPtr = (unsigned int *)adapter;

    // Get target ID from request structure
    // Request offset 0x10 points to target/LUN array
    targetLunPtr = (unsigned char **)(requestPtr + 0x10 / 4);
    targetID = **targetLunPtr;  // Dereference twice: pointer -> array -> first byte

    // Check if target ID matches adapter's own SCSI ID (offset 0x3b0)
    if (adapterPtr[0x3b0 / 4] == (unsigned int)targetID) {
        // Cannot probe ourselves - return error
        requestPtr[0x18 / 4] = 1;  // Set status to 1 (error)

        // Signal completion via condition lock
        conditionLock = (id)requestPtr[0x14 / 4];
        // Call condLockLock (offset 0x5bc)
        (*(void (*)(id, SEL))adapterPtr[0x5bc / 4])(conditionLock, @selector(lock));
        // Call condLockUnlockWith (offset 0x5c4)
        (*(void (*)(id, SEL, int))adapterPtr[0x5c4 / 4])(conditionLock, @selector(unlockWith:), 1);
        return;
    }

    // Allocate an IOB for the probe operation
    iob = _AllocOSMIOB(adapter);
    iobPtr = (unsigned int *)iob;

    // Set up IOB fields
    iobPtr[0x70 / 4] = (unsigned int)adapter;  // Adapter pointer
    iobPtr[0xc / 4] = 0x13;                    // Command type: 0x13 = probe

    // Get HIM handle from adapter (offset 0x2a8)
    himHandle = (void *)adapterPtr[0x2a8 / 4];

    // Set completion callback
    iobPtr[0x34 / 4] = (unsigned int)_PostProbe;

    // Clear parameters
    iobPtr[0x38 / 4] = 0;
    iobPtr[0x3c / 4] = 0;

    // Store request pointer
    iobPtr[0x20 / 4] = (unsigned int)request;

    // Store HIM handle
    iobPtr[0x28 / 4] = (unsigned int)himHandle;

    // Get CDB structure pointer from IOB (offset 0x1c)
    cdbPtr = (unsigned int *)iobPtr[0x1c / 4];

    // Set target ID and LUN in CDB structure
    *((unsigned char *)cdbPtr + 0x10) = targetID;  // Target ID
    *((unsigned char *)cdbPtr + 0x12) = 0;         // LUN 0

    // Increment sample counter (offset 0x578)
    adapterPtr[0x578 / 4] = adapterPtr[0x578 / 4] + 1;

    // Queue IOB to CHIM
    // CHIM function table is at offset 0x4cc
    // Function at offset 0x51c = index 20 (0x51c - 0x4cc = 0x50 = 80 / 4 = 20)
    queueIOB = (void (*)(void))adapterPtr[0x51c / 4];
    queueIOB();
}

/*
 * OSMRoutines Function Table
 *
 * This is the global function pointer table that gets passed to the CHIM
 * via setOSMRoutines(). The CHIM uses these function pointers to call back
 * into the OS for various operations.
 *
 * Size: 0x7c (124 bytes) = 31 entries * 4 bytes each
 * Entry 0: Reserved/padding (NULL)
 * Entries 1-30: Function pointers for OSM operations
 */
AdaptecU2OSMFunctions OSMRoutines = {
    0,                                      // 0x00: Version
    OSMMapIOHandle,                        // 0x04: Map I/O handle
    OSMReleaseIOHandle,                    // 0x08: Release I/O handle
    OSMEvent,                              // 0x0c: Event notification
    OSMGetBusAddress,                      // 0x10: Get bus address
    OSMAdjustBusAddress,                   // 0x14: Adjust bus address
    OSMGetNVSize,                          // 0x18: Get NVRAM size
    OSMPutNVData,                          // 0x1c: Put NVRAM data
    OSMGetNVData,                          // 0x20: Get NVRAM data
    OSMReadUExact8,                        // 0x24: Read 8-bit unaligned
    OSMReadUExact16,                       // 0x28: Read 16-bit unaligned
    OSMReadUExact32,                       // 0x2c: Read 32-bit unaligned
    OSMReadStringUExact8,                  // 0x30: Read 8-bit string
    OSMReadStringUExact16,                 // 0x34: Read 16-bit string
    OSMReadStringUExact32,                 // 0x38: Read 32-bit string
    OSMWriteUExact8,                       // 0x3c: Write 8-bit unaligned
    OSMWriteUExact16,                      // 0x40: Write 16-bit unaligned
    OSMWriteUExact32,                      // 0x44: Write 32-bit unaligned
    OSMWriteStringUExact8,                 // 0x48: Write 8-bit string
    OSMWriteStringUExact16,                // 0x4c: Write 16-bit string
    OSMWriteStringUExact32,                // 0x50: Write 32-bit string
    OSMSynchronizeRange,                   // 0x54: Synchronize cache range
    OSMWatchdog,                           // 0x58: Watchdog timer
    OSMSaveInterruptState,                 // 0x5c: Save interrupt state
    OSMSetInterruptState,                  // 0x60: Set interrupt state
    OSMReadPCIConfigurationDword,          // 0x64: Read PCI config dword
    OSMReadPCIConfigurationWord,           // 0x68: Read PCI config word
    OSMReadPCIConfigurationByte,           // 0x6c: Read PCI config byte
    OSMWritePCIConfigurationDword,         // 0x70: Write PCI config dword
    OSMWritePCIConfigurationWord,          // 0x74: Write PCI config word
    OSMWritePCIConfigurationByte           // 0x78: Write PCI config byte
};
