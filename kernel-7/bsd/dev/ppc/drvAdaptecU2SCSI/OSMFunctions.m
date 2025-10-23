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

#import <kernserv/prototypes.h>
#import <kernserv/ns_timer.h>
#import <mach/vm_param.h>
#import <machdep/ppc/proc_reg.h>
#import <objc/objc.h>

// External kernel memory allocation functions
extern void *kalloc(unsigned int size);
extern void kfree(void *addr, unsigned int size);

// Page size variables from kernel
extern unsigned int page_size;
extern unsigned int page_shift;
extern unsigned int page_mask;

// External kernel cache management
extern void flush_cache_v(vm_offset_t pa, unsigned length);

/*
 * Allocate contiguous physical memory.
 *
 * This function allocates memory that is guaranteed to be physically
 * contiguous and aligned to page boundaries. This is required for
 * DMA operations on the Adaptec SCSI controller.
 *
 * The function works by:
 * 1. Allocating 2x the requested size + 4 bytes overhead
 * 2. Checking if the allocation crosses a page boundary
 * 3. If it does, aligning to the next page boundary
 * 4. Storing the original allocation pointer 4 bytes before the returned address
 *
 * @param size The number of bytes to allocate (must be <= page_size)
 * @return Pointer to aligned contiguous memory, or NULL on failure
 */
void *AdptMallocContiguous(unsigned int size)
{
    void *allocation;
    unsigned int aligned;
    unsigned int pageShift;

    // Validate parameters
    if (size == 0) {
        return NULL;
    }

    if (size > page_size) {
        return NULL;
    }

    // Allocate 2x size plus 4 bytes for storing original pointer
    allocation = kalloc(size * 2 + 4);
    if (allocation == NULL) {
        return NULL;
    }

    // Start 4 bytes into allocation (room for original pointer)
    aligned = (unsigned int)allocation + 4;

    // Check if allocation crosses a page boundary
    pageShift = page_shift & 0x3f;

    if ((aligned >> pageShift) != ((aligned + size) - 1) >> pageShift) {
        // Crosses page boundary, align to next page
        aligned = (aligned + page_mask) & ~page_mask;
    }

    // Store original allocation pointer 4 bytes before aligned address
    // This is needed for freeing the memory later
    *((void **)(aligned - 4)) = allocation;

    return (void *)aligned;
}

/*
 * Free memory allocated by AdptMallocContiguous.
 *
 * From decompiled code:
 *   void AdptFreeContiguous(int param_1, int param_2)
 *   {
 *       _kfree(*(undefined4 *)(param_1 + -4), param_2 * 2 + 4);
 *   }
 *
 * @param addr The address returned by AdptMallocContiguous
 * @param size The size that was originally allocated
 */
void AdptFreeContiguous(void *addr, unsigned int size)
{
    void *original;

    if (addr == NULL) {
        return;
    }

    // Retrieve original allocation pointer from 4 bytes before
    // This matches: *(undefined4 *)(param_1 + -4)
    original = *((void **)((unsigned int)addr - 4));

    // Free original allocation
    // This matches: kfree(original, param_2 * 2 + 4)
    kfree(original, size * 2 + 4);
}

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

// External kernel functions
extern void *IOVmTaskSelf(void);
extern int IOPhysicalFromVirtual(void *task, unsigned int vaddr, unsigned int *paddr);
extern void IOLog(const char *format, ...);

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
 *   void __freeOSMIOB(int param_1, int param_2, ...)
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
void __freeOSMIOB(void *iobPtr, void *p1, void *p2, void *p3,
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
 *           __freeOSMIOB(param_2, *(undefined4 *)(param_1 + 0x2ac),
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
        __freeOSMIOB(iob,
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
void _AU2Handler(void *param_1, void *param_2, void *param_3)
{
    // External kernel function for scheduling thread calls
    extern void thread_call_func(void *func, void *param, int flags);

    // External reference to the I/O thread function
    // This is likely AdaptecU2SCSIThread or similar
    extern void AdaptecU2SCSIIOThread(void *adapter);

    // Schedule the I/O thread to process the interrupt
    // Flags: 1 = async (don't wait for completion)
    thread_call_func(AdaptecU2SCSIIOThread, param_3, 1);
}
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
 *   undefined4 _OSMMapIOHandle(int param_1, int param_2, int param_3, int param_4,
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

// IO Handle structure (32 bytes = 0x20)
typedef struct OSMIOHandle {
    void *mappedAddress;        // 0x00 - Virtual address of mapped region
    unsigned int handleType;    // 0x04 - Handle type/flags
    unsigned int size;          // 0x08 - Size of mapped region
    unsigned int offset;        // 0x0c - Offset within BAR
    unsigned int isMemMapped;   // 0x10 - 1 if valid mapping
    void *baseAddress;          // 0x14 - Base virtual address
    void *queuePrev;            // 0x18 - Previous in queue
    void *queueNext;            // 0x1c - Next in queue
} OSMIOHandle;

int _OSMMapIOHandle(void *adapter, int barIndex, int offset, int size,
                    void *unused, int handleType, OSMIOHandle *handleOut)
{
    OSMIOHandle *handle;
    unsigned int *adapterPtr = (unsigned int *)adapter;
    id deviceDesc;
    int result;
    unsigned int barValue;
    unsigned int barOffset;
    unsigned int physAddr;
    void *virtAddr;
    unsigned int aperture;
    int pageAlignedSize;
    void *queueTail;

    if (adapter == NULL || handleOut == NULL) {
        return 1;
    }

    // Allocate handle structure (0x20 = 32 bytes)
    handle = (OSMIOHandle *)IOMalloc(0x20);
    if (handle == NULL) {
        return 1;
    }

    // Calculate PCI config offset: 0x10 + barIndex * 4
    // BARs are at: 0x10, 0x14, 0x18, 0x1c, 0x20, 0x24
    barOffset = barIndex * 4 + 0x10;

    // Get device description
    deviceDesc = [((id)adapter) deviceDescription];

    // Read PCI config register
    result = [deviceDesc configReadLong:barOffset value:&barValue];
    if (result != 0) {
        IOLog("AdaptecU2SCSI: Cannot aquire PCI config data in reg: 0x%x.\n", barOffset);
        IOFree(handle, 0x20);
        return 1;
    }

    // Check if I/O space (bit 0 set) or memory space (bit 0 clear)
    if ((barValue & 1) == 0) {
        // Memory-mapped I/O
        physAddr = barValue & 0xfffffff0;  // Clear lower 4 bits

        // Add physical memory to pmap (make it accessible)
        result = pmap_add_physical_memory(physAddr, physAddr + offset + size, 0, 7);
        if (result != 0) {
            IOLog("AdaptecU2SCSI: pmap_add_physical_memory() failed\n");
            IOFree(handle, 0x20);
            return 1;
        }

        // Map physical to virtual address
        // Align to page boundaries
        pageAlignedSize = (offset + size + page_mask) & ~page_mask;
        result = IOMapPhysicalIntoIOTask(physAddr & ~page_mask, pageAlignedSize, &virtAddr);
        if (result != 0) {
            IOLog("AdaptecU2SCSI: IOMapPhysicalIntoIOTask failed for 0x%x\n", barOffset);
            IOFree(handle, 0x20);
            return 1;
        }

        // Calculate page-aligned offset
        unsigned int pageOffset = (physAddr / page_size) * page_size;

        // Set up handle
        handle->baseAddress = virtAddr;
        handle->isMemMapped = 1;
        handle->mappedAddress = (void *)((unsigned int)virtAddr + (physAddr - pageOffset) + offset);

    } else {
        // I/O-mapped (use I/O aperture)
        aperture = [deviceDesc getIOAperture];

        handle->isMemMapped = 1;
        virtAddr = (void *)(aperture + (barValue & 0xfffffffc));
        handle->mappedAddress = (void *)((unsigned int)virtAddr + offset);
        handle->baseAddress = virtAddr;
    }

    // Fill in rest of handle
    handle->handleType = handleType;
    handle->size = size;
    handle->offset = offset;

    // Add to adapter's handle queue (at offset 0x588/0x58c)
    queueTail = (void *)adapterPtr[0x58c / 4];

    // Check if queue is empty
    if ((unsigned int)adapter + 0x588 == (unsigned int)queueTail) {
        // Empty queue
        adapterPtr[0x588 / 4] = (unsigned int)handle;
    } else {
        // Add to tail
        *((unsigned int *)((unsigned int)queueTail + 0x18)) = (unsigned int)handle;
    }

    // Set up handle's queue links
    handle->queueNext = queueTail;
    handle->queuePrev = (void *)((unsigned int)adapter + 0x588);

    // Update queue tail
    adapterPtr[0x58c / 4] = (unsigned int)handle;

    // Copy handle to output structure
    handleOut->mappedAddress = handle->mappedAddress;
    handleOut->handleType = handle->handleType;
    handleOut->size = handle->size;
    handleOut->offset = handle->offset;
    handleOut->isMemMapped = handle->isMemMapped;
    handleOut->baseAddress = handle->baseAddress;
    handleOut->queuePrev = handle->queuePrev;
    handleOut->queueNext = handle->queueNext;

    return 0;
}

/*
 * OSMWritePCIConfigurationByte - Write byte to PCI configuration space
 *
 * From decompiled code:
 *   void _OSMWritePCIConfigurationByte(undefined4 param_1, uint param_2, uint param_3)
 *   {
 *       // Calculate byte offset and aligned register
 *       iVar4 = (param_2 & 3) << 3;
 *       uVar1 = param_2 - (param_2 & 3) & 0xff;
 *
 *       // Read current 32-bit value
 *       configReadLong(uVar1, &local_28);
 *
 *       // Modify the specific byte
 *       local_28[0] = local_28[0] & ~(0xff << iVar4) | (param_3 & 0xff) << iVar4;
 *
 *       // Write back
 *       configWriteLong(uVar1, local_28[0]);
 *   }
 *
 * PCI configuration space can only be accessed in 32-bit chunks. To write
 * a single byte, this function:
 * 1. Aligns the offset to a 32-bit boundary
 * 2. Reads the current 32-bit value
 * 3. Replaces the specific byte
 * 4. Writes back the modified 32-bit value
 *
 * @param adapter Adapter instance
 * @param offset PCI config register offset (0-255)
 * @param value Byte value to write
 */
void _OSMWritePCIConfigurationByte(void *adapter, unsigned int offset, unsigned int value)
{
    id deviceDesc;
    int result;
    unsigned int alignedOffset;
    unsigned int byteShift;
    unsigned int currentValue;
    unsigned int newValue;
    const char *errorStr;

    if (adapter == NULL) {
        return;
    }

    // Calculate bit shift for the specific byte (0, 8, 16, or 24)
    byteShift = (offset & 3) << 3;

    // Align offset to 32-bit boundary
    alignedOffset = (offset - (offset & 3)) & 0xff;

    // Get device description
    deviceDesc = [((id)adapter) deviceDescription];

    // Read current 32-bit value
    result = [deviceDesc configReadLong:alignedOffset value:&currentValue];
    if (result != 0) {
        IOLog("OSMWritePCIConfigurationByte.\n");
        errorStr = [[IODevice class] stringFromReturn:result];
        IOLog("getPCIConfigData Error: %s\n", errorStr);
        IOLog("Register: 0x%x\n", alignedOffset);
        IOLog("Context: 0x%x\n", (unsigned int)adapter);
        return;
    }

    // Replace the specific byte in the 32-bit value
    // Clear the byte we want to replace: ~(0xff << byteShift)
    // Insert new byte value: (value & 0xff) << byteShift
    newValue = (currentValue & ~(0xff << byteShift)) | ((value & 0xff) << byteShift);

    // Write back modified value
    result = [deviceDesc configWriteLong:alignedOffset value:newValue];
    if (result != 0) {
        IOLog("OSMWritePCIConfigurationByte failed.\n");
        errorStr = [[IODevice class] stringFromReturn:result];
        IOLog("setPCIConfigData Error: %s\n", errorStr);
        IOLog("Register: 0x%x\n", alignedOffset);
        IOLog("Value: 0x%x\n", value & 0xff);
        IOLog("Context: 0x%x\n", (unsigned int)adapter);
    }
}

/*
 * OSMWritePCIConfigurationWord - Write 16-bit word to PCI configuration space
 *
 * From decompiled code:
 *   void _OSMWritePCIConfigurationWord(undefined4 param_1, uint param_2, uint param_3)
 *   {
 *       iVar4 = (param_2 & 3) << 3;
 *       uVar1 = param_2 - (param_2 & 3) & 0xff;
 *       configReadLong(uVar1, &local_28);
 *       local_28[0] = local_28[0] & ~(0xffff << iVar4) | (param_3 & 0xffff) << iVar4;
 *       configWriteLong(uVar1, local_28[0]);
 *   }
 *
 * Same algorithm as OSMWritePCIConfigurationByte, but operates on 16-bit words.
 * PCI configuration space can only be accessed in 32-bit chunks, so:
 * 1. Align offset to 32-bit boundary
 * 2. Read current 32-bit value
 * 3. Replace the specific 16-bit word
 * 4. Write back modified 32-bit value
 *
 * @param adapter Adapter instance
 * @param offset PCI config register offset (0-255, should be word-aligned)
 * @param value 16-bit word value to write
 */
void _OSMWritePCIConfigurationWord(void *adapter, unsigned int offset, unsigned int value)
{
    id deviceDesc;
    int result;
    unsigned int alignedOffset;
    unsigned int wordShift;
    unsigned int currentValue;
    unsigned int newValue;
    const char *errorStr;

    if (adapter == NULL) {
        return;
    }

    // Calculate bit shift for the specific word (0 or 16)
    wordShift = (offset & 3) << 3;

    // Align offset to 32-bit boundary
    alignedOffset = (offset - (offset & 3)) & 0xff;

    // Get device description
    deviceDesc = [((id)adapter) deviceDescription];

    // Read current 32-bit value
    result = [deviceDesc configReadLong:alignedOffset value:&currentValue];
    if (result != 0) {
        IOLog("OSMWritePCIConfigurationWord.\n");
        errorStr = [[IODevice class] stringFromReturn:result];
        IOLog("getPCIConfigData Error: %s\n", errorStr);
        IOLog("Register: 0x%x\n", alignedOffset);
        IOLog("Context: 0x%x\n", (unsigned int)adapter);
        return;
    }

    // Replace the specific 16-bit word in the 32-bit value
    // Clear the word we want to replace: ~(0xffff << wordShift)
    // Insert new word value: (value & 0xffff) << wordShift
    newValue = (currentValue & ~(0xffff << wordShift)) | ((value & 0xffff) << wordShift);

    // Write back modified value
    result = [deviceDesc configWriteLong:alignedOffset value:newValue];
    if (result != 0) {
        IOLog("OSMWritePCIConfigurationWord.\n");
        errorStr = [[IODevice class] stringFromReturn:result];
        IOLog("setPCIConfigData Error: %s\n", errorStr);
        IOLog("Register: 0x%x\n", alignedOffset);
        IOLog("Value: 0x%x\n", value & 0xffff);
        IOLog("Context: 0x%x\n", (unsigned int)adapter);
    }
}

/*
 * OSMWritePCIConfigurationDword - Write 32-bit dword to PCI configuration space
 *
 * From decompiled code:
 *   void _OSMWritePCIConfigurationDword(undefined4 param_1, uint param_2, undefined4 param_3)
 *   {
 *       uVar1 = _objc_msgSend(param_1, s_deviceDescription_0034d174);
 *       iVar2 = _objc_msgSend(uVar1, s_configWriteLong:value:_0034eb0c, param_2 & 0xfc, param_3);
 *       if (iVar2 != 0) {
 *           _IOLog("OSMWritePCIConfigurationDword.\n");
 *           // ... error logging ...
 *       }
 *   }
 *
 * Unlike Byte and Word writes, this is a direct write since PCI configuration
 * space is natively 32-bit. No read-modify-write cycle needed.
 *
 * Simply:
 * 1. Align offset to 32-bit boundary (& 0xfc)
 * 2. Write the 32-bit value directly
 *
 * @param adapter Adapter instance
 * @param offset PCI config register offset (0-255, will be aligned to dword)
 * @param value 32-bit dword value to write
 */
void _OSMWritePCIConfigurationDword(void *adapter, unsigned int offset, unsigned int value)
{
    id deviceDesc;
    int result;
    unsigned int alignedOffset;
    const char *errorStr;

    if (adapter == NULL) {
        return;
    }

    // Align offset to 32-bit boundary (clear lower 2 bits)
    // 0xfc = 11111100 binary
    alignedOffset = offset & 0xfc;

    // Get device description
    deviceDesc = [((id)adapter) deviceDescription];

    // Write 32-bit value directly (no read-modify-write needed)
    result = [deviceDesc configWriteLong:alignedOffset value:value];
    if (result != 0) {
        IOLog("OSMWritePCIConfigurationDword.\n");
        errorStr = [[IODevice class] stringFromReturn:result];
        IOLog("setPCIConfigData Error: %s\n", errorStr);
        IOLog("Register: 0x%x\n", alignedOffset);
        IOLog("Value: 0x%x\n", value);
        IOLog("Context: 0x%x\n", (unsigned int)adapter);
    }
}

/*
 * OSMReadPCIConfigurationByte - Read byte from PCI configuration space
 *
 * From decompiled code:
 *   uint _OSMReadPCIConfigurationByte(undefined4 param_1, uint param_2)
 *   {
 *       uVar3 = param_2 - (param_2 & 3) & 0xff;
 *       configReadLong(uVar3, &local_18);
 *       if (iVar2 == 0) {
 *           uVar3 = local_18[0] >> ((param_2 & 3) << 3) & 0xff;
 *       } else {
 *           uVar3 = 0;
 *       }
 *       return uVar3;
 *   }
 *
 * PCI configuration space can only be read in 32-bit chunks. To read
 * a single byte:
 * 1. Align offset to 32-bit boundary
 * 2. Read the 32-bit value
 * 3. Shift right to get the specific byte
 * 4. Mask to 8 bits
 *
 * @param adapter Adapter instance
 * @param offset PCI config register offset (0-255)
 * @return Byte value, or 0 on error
 */
unsigned int _OSMReadPCIConfigurationByte(void *adapter, unsigned int offset)
{
    id deviceDesc;
    int result;
    unsigned int alignedOffset;
    unsigned int byteShift;
    unsigned int value;
    const char *errorStr;

    if (adapter == NULL) {
        return 0;
    }

    // Align offset to 32-bit boundary
    alignedOffset = (offset - (offset & 3)) & 0xff;

    // Get device description
    deviceDesc = [((id)adapter) deviceDescription];

    // Read 32-bit value
    result = [deviceDesc configReadLong:alignedOffset value:&value];
    if (result == 0) {
        // Extract the specific byte
        // Shift right by (0, 8, 16, or 24) bits, then mask to 8 bits
        byteShift = (offset & 3) << 3;
        return (value >> byteShift) & 0xff;
    } else {
        // Error
        IOLog("OSMReadPCIConfigurationByte failed.\n");
        errorStr = [[IODevice class] stringFromReturn:result];
        IOLog("Error: %s\n", errorStr);
        IOLog("Register: 0x%x\n", alignedOffset);
        IOLog("Context: 0x%x\n", (unsigned int)adapter);
        return 0;
    }
}

/*
 * OSMReadPCIConfigurationWord - Read 16-bit word from PCI configuration space
 *
 * Similar to Byte read, but extracts a 16-bit word instead of 8-bit byte.
 *
 * @param adapter Adapter instance
 * @param offset PCI config register offset (0-255, should be word-aligned)
 * @return 16-bit word value, or 0 on error
 */
unsigned int _OSMReadPCIConfigurationWord(void *adapter, unsigned int offset)
{
    id deviceDesc;
    int result;
    unsigned int alignedOffset;
    unsigned int wordShift;
    unsigned int value;
    const char *errorStr;

    if (adapter == NULL) {
        return 0;
    }

    // Align offset to 32-bit boundary
    alignedOffset = (offset - (offset & 3)) & 0xff;

    // Get device description
    deviceDesc = [((id)adapter) deviceDescription];

    // Read 32-bit value
    result = [deviceDesc configReadLong:alignedOffset value:&value];
    if (result == 0) {
        // Extract the specific 16-bit word
        // Shift right by (0 or 16) bits, then mask to 16 bits
        wordShift = (offset & 3) << 3;
        return (value >> wordShift) & 0xffff;
    } else {
        // Error
        IOLog("OSMReadPCIConfigurationWord failed.\n");
        errorStr = [[IODevice class] stringFromReturn:result];
        IOLog("Error: %s\n", errorStr);
        IOLog("Register: 0x%x\n", alignedOffset);
        IOLog("Context: 0x%x\n", (unsigned int)adapter);
        return 0;
    }
}

/*
 * OSMReadPCIConfigurationDword - Read 32-bit dword from PCI configuration space
 *
 * This is the simplest read - PCI config is natively 32-bit, so just
 * align the offset and read directly.
 *
 * @param adapter Adapter instance
 * @param offset PCI config register offset (0-255, will be aligned to dword)
 * @return 32-bit dword value, or 0 on error
 */
unsigned int _OSMReadPCIConfigurationDword(void *adapter, unsigned int offset)
{
    id deviceDesc;
    int result;
    unsigned int alignedOffset;
    unsigned int value;
    const char *errorStr;

    if (adapter == NULL) {
        return 0;
    }

    // Align offset to 32-bit boundary (clear lower 2 bits)
    alignedOffset = offset & 0xfc;

    // Get device description
    deviceDesc = [((id)adapter) deviceDescription];

    // Read 32-bit value directly
    result = [deviceDesc configReadLong:alignedOffset value:&value];
    if (result == 0) {
        return value;
    } else {
        // Error
        IOLog("OSMReadPCIConfigurationDword failed.\n");
        errorStr = [[IODevice class] stringFromReturn:result];
        IOLog("Error: %s\n", errorStr);
        IOLog("Register: 0x%x\n", alignedOffset);
        IOLog("Context: 0x%x\n", (unsigned int)adapter);
        return 0;
    }
}

/*
 * OSMReleaseIOHandle - Release a previously mapped I/O handle
 *
 * From decompiled code:
 *   undefined4 _OSMReleaseIOHandle(int param_1, ..., int param_4, int param_5,
 *                                   int param_6, uint param_7, int param_8, int param_9)
 *   {
 *       if (param_6 == 1) {
 *           _IOUnmapPhysicalFromIOTask(param_7 & ~_page_mask,
 *                                      param_4 + param_5 + _page_mask & ~_page_mask);
 *       }
 *
 *       // Search for handle in queue (iVar3 == param_8)
 *       // Remove from queue
 *       // Free handle structure
 *       return 0;
 *   }
 *
 * This function:
 * 1. Unmaps the physical memory if it was memory-mapped (isMemMapped == 1)
 * 2. Searches the adapter's handle queue for the specific handle
 * 3. Removes the handle from the queue (update prev/next links)
 * 4. Frees the handle structure
 *
 * Parameters match OSMIOHandle structure:
 * - param_4: size (offset 0x08)
 * - param_5: offset (offset 0x0c)
 * - param_6: isMemMapped (offset 0x10)
 * - param_7: baseAddress (offset 0x14)
 * - param_8: queuePrev (offset 0x18)
 * - param_9: queueNext (offset 0x1c)
 *
 * @param adapter Adapter instance
 * @param handle Handle structure to release (OSMIOHandle *)
 * @return 0 on success
 */
int _OSMReleaseIOHandle(void *adapter, OSMIOHandle *handle)
{
    unsigned int *adapterPtr = (unsigned int *)adapter;
    unsigned int queueHead;
    unsigned int current;
    unsigned int prev;
    unsigned int next;
    unsigned int pageAlignedSize;

    if (adapter == NULL || handle == NULL) {
        return 0;
    }

    // If this was a memory-mapped region, unmap it
    if (handle->isMemMapped == 1) {
        // Calculate page-aligned size
        pageAlignedSize = (handle->size + handle->offset + page_mask) & ~page_mask;

        // Unmap the physical memory
        IOUnmapPhysicalFromIOTask((unsigned int)handle->baseAddress & ~page_mask,
                                  pageAlignedSize);
    }

    // Search for this handle in the adapter's handle queue (at 0x588/0x58c)
    queueHead = (unsigned int)adapter + 0x588;
    current = adapterPtr[0x588 / 4];

    // Walk the queue looking for this handle
    while (current != queueHead) {
        if (current == (unsigned int)handle) {
            // Found it! Remove from queue
            prev = handle->queuePrev;
            next = handle->queueNext;

            // Update tail if needed
            if (queueHead == (unsigned int)next) {
                // This was the last handle, update tail
                adapterPtr[0x58c / 4] = (unsigned int)prev;
            } else {
                // Link next handle's prev to our prev
                *((unsigned int *)((unsigned int)next + 0x18)) = (unsigned int)prev;
            }

            // Update head if needed
            if (queueHead == (unsigned int)prev) {
                // This was the first handle, update head
                adapterPtr[0x588 / 4] = (unsigned int)next;
            } else {
                // Link prev handle's next to our next
                *((unsigned int *)((unsigned int)prev + 0x1c)) = (unsigned int)next;
            }

            // Free the handle structure (32 bytes = 0x20)
            IOFree(handle, 0x20);

            return 0;
        }

        // Move to next handle in queue
        current = *((unsigned int *)(current + 0x18));
    }

    // Handle not found in queue
    return 0;
}

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
                    extern void IOScheduleFunc(void (*func)(void *), void *arg);
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
 * Forward declarations for SCSI hardware interface functions
 */
void _OSDBuildSCB(void *scb);
void _OSMWriteSCB8Words(unsigned int p0, unsigned int p1, unsigned int p2, unsigned int p3,
                        unsigned int p4, unsigned int p5, unsigned int p6, unsigned int p7,
                        unsigned char reg, unsigned char val);

/*
 * SCSIhSwapping32PatchXferOpt - Patch transfer options for byte swapping
 *
 * Based on decompiled code from binary.
 * This function patches SCSI transfer options to handle byte swapping on
 * PowerPC architecture. It reads transfer options from the unit info and
 * applies necessary patches to the SCB (SCSI Control Block).
 *
 * Function signature from decompiled code:
 * void _SCSIhSwapping32PatchXferOpt(undefined4 param_1, int *param_2)
 *
 * Decompiled structure:
 * - param_1 is unused (likely reserved for future use)
 * - param_2 is pointer to IOB or similar structure
 * - Gets unit info pointer from *param_2 + 8 (cast to ushort*)
 * - Gets SCB pointer from param_2[6] + 0xc
 * - Copies byte from unit info offset 3 to SCB offset 0x1d
 * - If bit 13 (0x2000) is set in unit info word 0:
 *   - Sets bit 2 (value 4) in SCB byte at offset 1
 *   - Flushes cache for the SCB (0x20 = 32 bytes)
 *
 * The bit 13 check likely indicates whether the device supports or requires
 * a specific SCSI protocol feature that needs byte swapping adjustments.
 *
 * @param param_1 Unused parameter (reserved)
 * @param param_2 Pointer to IOB structure containing unit info and SCB pointers
 */
void _SCSIhSwapping32PatchXferOpt(void *param_1, unsigned int *param_2)
{
    unsigned short *unitInfo;
    unsigned int *scbPtr;
    unsigned char *scbBytes;

    // Get unit info pointer from *param_2 + 8
    unitInfo = (unsigned short *)*(unsigned int **)(*param_2 + 8);

    // Get SCB pointer from param_2[6] + 0xc
    scbPtr = (unsigned int *)*(unsigned int *)(param_2[6] + 0xc);
    scbBytes = (unsigned char *)scbPtr;

    // Copy byte from unit info offset 3 to SCB offset 0x1d
    scbBytes[0x1d] = *((unsigned char *)unitInfo + 3);

    // Check if bit 13 (0x2000) is set in first word of unit info
    if ((*unitInfo & 0x2000) != 0) {
        // Set bit 2 (value 4) in SCB byte at offset 1
        scbBytes[1] |= 0x04;

        // Flush cache for the SCB structure (32 bytes)
        flush_cache_v((vm_offset_t)scbPtr, 0x20);
    }
}

/*
 * SCSIhDeliverScb - Deliver SCSI Control Block to hardware
 *
 * Based on decompiled code from binary.
 * This function prepares and delivers a SCSI Control Block (SCB) to the
 * Adaptec hardware. It builds the SCB, optionally calls a pre-delivery hook,
 * increments a counter, and writes the SCB to hardware using the
 * OSMWriteUExact8 function.
 *
 * Function signature from decompiled code:
 * void _SCSIhDeliverScb(int param_1, undefined4 param_2)
 *
 * Decompiled structure:
 * - param_1 is adapter or HIM structure pointer
 * - param_2 is SCB data to build
 * - Gets pointer from param_1+8 (array of 8 words to write)
 * - Calls OSDBuildSCB to prepare the SCB
 * - Gets optional function pointer from *(param_1+0xf0)+0x60
 * - If function pointer exists, calls it with (param_1, param_2)
 * - Increments counter at param_1+0xd8
 * - Calls OSMWriteUExact8 to write 8 words to hardware:
 *   - Words 0-7 from pointer at param_1+8
 *   - Register index from *(param_1+0xf0)+0x40
 *   - Value from param_1+0xd8 (the counter we just incremented)
 *
 * The 0xf0 offset likely points to a profile or configuration structure.
 * The 0xd8 offset is a delivery counter or sequence number.
 *
 * @param param_1 Adapter or HIM structure pointer
 * @param param_2 SCB data to be built and delivered
 */
void _SCSIhDeliverScb(unsigned int *param_1, void *param_2)
{
    void (*deliveryHook)(unsigned int *, void *);
    unsigned int *scbWords;
    unsigned int *profilePtr;
    unsigned char *counterBytes;
    unsigned char regIndex;
    unsigned char counter;

    // Get pointer to 8-word array at param_1+8
    scbWords = (unsigned int *)param_1[8 / 4];

    // Build the SCB structure
    _OSDBuildSCB(param_2);

    // Get profile/config pointer from param_1+0xf0
    profilePtr = (unsigned int *)param_1[0xf0 / 4];

    // Get optional pre-delivery hook function at profile+0x60
    deliveryHook = (void (*)(unsigned int *, void *))profilePtr[0x60 / 4];

    // If hook exists, call it
    if (deliveryHook != NULL) {
        deliveryHook(param_1, param_2);
    }

    // Increment delivery counter at param_1+0xd8
    counterBytes = (unsigned char *)param_1;
    counterBytes[0xd8]++;
    counter = counterBytes[0xd8];

    // Get register index from profile+0x40
    regIndex = *((unsigned char *)profilePtr + 0x40);

    // Write the 8-word SCB to hardware
    _OSMWriteSCB8Words(
        scbWords[0], scbWords[1], scbWords[2], scbWords[3],
        scbWords[4], scbWords[5], scbWords[6], scbWords[7],
        regIndex, counter
    );
}

/*
 * OSMGetBusAddress - Convert virtual address to physical bus address
 *
 * Based on decompiled code from binary.
 * This function translates a virtual memory address to its corresponding
 * physical bus address suitable for DMA operations. This is essential for
 * hardware that needs to access memory directly.
 *
 * Function signature from decompiled code:
 * undefined4 _OSMGetBusAddress(undefined4 param_1, undefined4 param_2, undefined4 param_3)
 *
 * Decompiled structure:
 * - param_1 is unused (likely reserved for adapter context)
 * - param_2 is unused (likely reserved for flags or options)
 * - param_3 is the virtual address to convert
 * - Gets VM task via IOVmTaskSelf()
 * - Calls IOPhysicalFromVirtual(task, param_3, &physAddr)
 * - Returns physical address on success, 0 on failure
 * - Logs error if conversion fails
 *
 * @param param_1 Unused (reserved for adapter or context)
 * @param param_2 Unused (reserved for flags)
 * @param virtualAddr Virtual address to convert
 * @return Physical bus address, or 0 on failure
 */
unsigned int _OSMGetBusAddress(void *param_1, void *param_2, unsigned int virtualAddr)
{
    void *vmTask;
    int result;
    unsigned int physAddr;

    // Get current VM task
    vmTask = IOVmTaskSelf();

    // Convert virtual to physical address
    result = IOPhysicalFromVirtual(vmTask, virtualAddr, &physAddr);

    if (result != 0) {
        // Conversion failed
        IOLog("Cannot get physical address for virtual 0x%x\n", virtualAddr);
        return 0;
    }

    return physAddr;
}

/*
 * OSMAdjustBusAddress - Adjust a bus address by adding an offset
 *
 * Based on decompiled code from binary.
 * This simple function adds an offset to a bus address pointer. It's used
 * to adjust physical addresses when dealing with segmented DMA operations
 * or when moving through scatter-gather lists.
 *
 * Function signature from decompiled code:
 * void _OSMAdjustBusAddress(int *param_1, int param_2)
 *
 * Decompiled structure:
 * - param_1 is pointer to bus address to adjust
 * - param_2 is offset to add
 * - Simply adds param_2 to *param_1
 *
 * @param busAddrPtr Pointer to bus address to adjust
 * @param offset Offset to add to the bus address
 */
void _OSMAdjustBusAddress(unsigned int *busAddrPtr, int offset)
{
    *busAddrPtr = *busAddrPtr + offset;
}

/*
 * OSMGetNVSize - Get NVRAM size for adapter configuration
 *
 * Based on decompiled code from binary.
 * Returns the size of non-volatile memory available for storing adapter
 * configuration. Returns 0 indicating no NVRAM is available on this platform.
 *
 * Function signature from decompiled code:
 * undefined4 _OSMGetNVSize(void)
 *
 * @return 0 (no NVRAM available)
 */
unsigned int _OSMGetNVSize(void)
{
    return 0;
}

/*
 * OSMPutNVData - Write data to NVRAM
 *
 * Based on decompiled code from binary.
 * Attempts to write configuration data to non-volatile memory.
 * Returns error code 3 indicating the operation is not supported
 * on this platform.
 *
 * Function signature from decompiled code:
 * undefined4 _OSMPutNVData(void)
 *
 * @return 3 (operation not supported)
 */
unsigned int _OSMPutNVData(void)
{
    return 3;
}

/*
 * OSMGetNVData - Read data from NVRAM
 *
 * Based on decompiled code from binary.
 * Attempts to read configuration data from non-volatile memory.
 * Returns error code 1 indicating the operation is not supported
 * on this platform.
 *
 * Function signature from decompiled code:
 * undefined4 _OSMGetNVData(void)
 *
 * @return 1 (operation not supported)
 */
unsigned int _OSMGetNVData(void)
{
    return 1;
}

/*
 * OSMReadUExact8 - Read an 8-bit value from hardware register
 *
 * Based on decompiled code from binary.
 * Reads a single byte from a hardware register at the specified base
 * address plus offset. This is used for accessing Adaptec SCSI controller
 * registers.
 *
 * Function signature from decompiled code:
 * undefined _OSMReadUExact8(int param_1)
 *
 * Note: The decompiled code shows param_9 being used, which indicates
 * a second parameter (offset) that Ghidra detected from the calling
 * convention but listed in the body rather than the signature.
 *
 * Decompiled structure:
 * - param_1 is base address
 * - param_9 (second param) is offset from base
 * - Returns byte at (param_1 + param_9)
 *
 * @param baseAddr Base address of hardware registers
 * @param offset Offset from base address
 * @return Byte value read from hardware register
 */
unsigned char _OSMReadUExact8(unsigned int baseAddr, unsigned int offset)
{
    return *(unsigned char *)(baseAddr + offset);
}

/*
 * OSMReadUExact16 - Read a 16-bit value from hardware register
 *
 * Based on decompiled code from binary.
 * Reads a 16-bit word from a hardware register with optional byte swapping.
 * The Adaptec controller may require byte swapping when accessing certain
 * registers on big-endian PowerPC systems interfacing with little-endian
 * hardware logic.
 *
 * Function signature from decompiled code:
 * undefined2 _OSMReadUExact16(int param_1, uint param_2)
 *
 * Decompiled structure:
 * - param_1 is base address
 * - param_2 contains flags (bit 1 = 0x2 indicates byte swap needed)
 * - param_9 (third param from calling convention) is offset
 * - If (param_2 & 2) == 0: read as normal 16-bit value
 * - If (param_2 & 2) != 0: read bytes and swap them
 * - CONCAT11 in decompiled code concatenates bytes in reversed order
 *
 * The byte swap converts between big-endian and little-endian:
 * - Normal read: [byte0, byte1] -> (byte0 << 8) | byte1
 * - Swapped read: [byte0, byte1] -> (byte1 << 8) | byte0
 *
 * @param baseAddr Base address of hardware registers
 * @param flags Flags controlling read behavior (bit 1 = byte swap)
 * @param offset Offset from base address
 * @return 16-bit value read from hardware register
 */
unsigned short _OSMReadUExact16(unsigned int baseAddr, unsigned int flags, unsigned int offset)
{
    unsigned char *bytePtr;
    unsigned short value;

    // Check if byte swapping is requested (bit 1 of flags)
    if ((flags & 0x2) == 0) {
        // Normal read - no byte swapping
        value = *(unsigned short *)(baseAddr + offset);
    }
    else {
        // Byte-swapped read
        bytePtr = (unsigned char *)(baseAddr + offset);
        // Swap bytes: [0][1] becomes [1][0]
        value = ((unsigned short)bytePtr[1] << 8) | (unsigned short)bytePtr[0];
    }

    return value;
}

/*
 * OSMReadUExact32 - Read a 32-bit value from hardware register
 *
 * Based on decompiled code from binary.
 * Reads a 32-bit doubleword from a hardware register with optional byte swapping.
 * Similar to OSMReadUExact16, this handles endianness conversion when needed.
 *
 * Function signature from decompiled code:
 * uint _OSMReadUExact32(int param_1, uint param_2)
 *
 * Decompiled structure:
 * - param_1 is base address
 * - param_2 contains flags (bit 1 = 0x2 indicates byte swap needed)
 * - param_9 (third param from calling convention) is offset
 * - If (param_2 & 2) == 0: read as normal 32-bit value
 * - If (param_2 & 2) != 0: read 4 bytes and reassemble in little-endian order
 *
 * The byte swap for 32-bit values:
 * - Normal read: [b0, b1, b2, b3] -> (b0<<24)|(b1<<16)|(b2<<8)|b3
 * - Swapped read: [b0, b1, b2, b3] -> (b3<<24)|(b2<<16)|(b1<<8)|b0
 *
 * @param baseAddr Base address of hardware registers
 * @param flags Flags controlling read behavior (bit 1 = byte swap)
 * @param offset Offset from base address
 * @return 32-bit value read from hardware register
 */
unsigned int _OSMReadUExact32(unsigned int baseAddr, unsigned int flags, unsigned int offset)
{
    unsigned char *bytePtr;
    unsigned int value;

    // Check if byte swapping is requested (bit 1 of flags)
    if ((flags & 0x2) == 0) {
        // Normal read - no byte swapping
        value = *(unsigned int *)(baseAddr + offset);
    }
    else {
        // Byte-swapped read (little-endian order)
        bytePtr = (unsigned char *)(baseAddr + offset);
        // Assemble bytes in little-endian order: [b0, b1, b2, b3] -> b3:b2:b1:b0
        value = ((unsigned int)bytePtr[3] << 24) |
                ((unsigned int)bytePtr[2] << 16) |
                ((unsigned int)bytePtr[1] << 8) |
                (unsigned int)bytePtr[0];
    }

    return value;
}

/*
 * Helper functions for byte swapping in string read operations
 * These inline functions handle different endianness modes for bulk reads
 */

// 16-bit swap helpers
static inline unsigned short _swap16_normal(unsigned short val)
{
    return val;
}

static inline unsigned short _swap16_byte(unsigned short val)
{
    return ((val & 0xFF) << 8) | ((val >> 8) & 0xFF);
}

static inline unsigned short _swap16_word(unsigned short val)
{
    // Alternative swap mode (same as byte swap for 16-bit)
    return ((val & 0xFF) << 8) | ((val >> 8) & 0xFF);
}

// 32-bit swap helpers
static inline unsigned int _swap32_normal(unsigned int val)
{
    return val;
}

static inline unsigned int _swap32_byte(unsigned int val)
{
    return ((val & 0xFF) << 24) |
           (((val >> 8) & 0xFF) << 16) |
           (((val >> 16) & 0xFF) << 8) |
           ((val >> 24) & 0xFF);
}

static inline unsigned int _swap32_word(unsigned int val)
{
    // Word swap (swap 16-bit halves)
    return ((val & 0xFFFF) << 16) | ((val >> 16) & 0xFFFF);
}

/*
 * OSMReadStringUExact8 - Read a string of 8-bit values from hardware
 *
 * Based on decompiled code from binary.
 * Reads multiple bytes from hardware registers with a configurable stride
 * pattern. This is used for bulk data transfers from SCSI FIFOs or buffers.
 *
 * Function signature from decompiled code:
 * void _OSMReadStringUExact8(int param_1)
 *
 * Decompiled structure:
 * - param_1 = base address
 * - param_9 = offset from base
 * - param_10 = destination buffer
 * - param_11 = count of bytes to read
 * - param_12 = stride multiplier
 * - Reads from (param_1 + param_9 + i*4) where i increments by param_12
 * - The *4 suggests hardware registers are 32-bit aligned
 *
 * @param baseAddr Base address of hardware registers
 * @param offset Offset from base address
 * @param destBuffer Destination buffer for read data
 * @param count Number of bytes to read
 * @param stride Stride multiplier for register spacing
 */
void _OSMReadStringUExact8(unsigned int baseAddr, unsigned int offset,
                           unsigned char *destBuffer, unsigned int count,
                           int stride)
{
    unsigned int i;
    int regIndex;

    regIndex = 0;
    for (i = 0; i < count; i++) {
        // Read from hardware with 4-byte aligned addressing
        destBuffer[i] = *(unsigned char *)(baseAddr + offset + regIndex * 4);
        regIndex += stride;
    }
}

/*
 * OSMReadStringUExact16 - Read a string of 16-bit values from hardware
 *
 * Based on decompiled code from binary.
 * Reads multiple 16-bit words from hardware registers with optional byte
 * swapping and configurable stride. Uses function pointers to select the
 * appropriate byte swapping mode based on flags.
 *
 * Function signature from decompiled code:
 * void _OSMReadStringUExact16(int param_1, uint param_2)
 *
 * Decompiled structure:
 * - param_1 = base address
 * - param_2 = flags (bit 0 and bit 1 control swapping mode)
 * - param_9 = offset from base
 * - param_10 = destination buffer
 * - param_11 = count of words to read
 * - param_12 = stride multiplier
 * - Function pointer selection:
 *   - If (flags & 2) != 0: use byte swap function
 *   - Else if (flags & 1) != 0: use alternate swap function
 *   - Else: use normal read function
 *
 * @param baseAddr Base address of hardware registers
 * @param flags Bit 0 and bit 1 control endianness mode
 * @param offset Offset from base address
 * @param destBuffer Destination buffer for read data
 * @param count Number of 16-bit words to read
 * @param stride Stride multiplier for register spacing
 */
void _OSMReadStringUExact16(unsigned int baseAddr, unsigned int flags,
                            unsigned int offset, unsigned short *destBuffer,
                            unsigned int count, int stride)
{
    unsigned int i;
    int regIndex;
    int destIndex;
    unsigned short value;
    unsigned short (*swapFunc)(unsigned short);

    // Select swap function based on flags
    if ((flags & 0x2) != 0) {
        // Bit 1 set: byte swap mode
        swapFunc = _swap16_byte;
    }
    else if ((flags & 0x1) != 0) {
        // Bit 0 set: alternate swap mode
        swapFunc = _swap16_word;
    }
    else {
        // Normal mode, no swapping
        swapFunc = _swap16_normal;
    }

    regIndex = 0;
    destIndex = 0;
    for (i = 0; i < count; i++) {
        // Read from hardware with 4-byte aligned addressing
        value = *(unsigned short *)(baseAddr + offset + regIndex * 4);
        // Apply byte swapping
        destBuffer[destIndex] = swapFunc(value);
        destIndex++;
        regIndex += stride;
    }
}

/*
 * OSMReadStringUExact32 - Read a string of 32-bit values from hardware
 *
 * Based on decompiled code from binary.
 * Reads multiple 32-bit doublewords from hardware registers with optional
 * byte/word swapping and configurable stride. Similar to the 16-bit version
 * but operates on 32-bit values.
 *
 * Function signature from decompiled code:
 * void _OSMReadStringUExact32(int param_1, uint param_2)
 *
 * Decompiled structure:
 * - param_1 = base address
 * - param_2 = flags (bit 0 and bit 1 control swapping mode)
 * - param_9 = offset from base
 * - param_10 = destination buffer
 * - param_11 = count of doublewords to read
 * - param_12 = stride multiplier
 * - Function pointer selection:
 *   - If (flags & 2) != 0: use byte swap function
 *   - Else if (flags & 1) != 0: use word swap function
 *   - Else: use normal read function
 *
 * @param baseAddr Base address of hardware registers
 * @param flags Bit 0 and bit 1 control endianness mode
 * @param offset Offset from base address
 * @param destBuffer Destination buffer for read data
 * @param count Number of 32-bit doublewords to read
 * @param stride Stride multiplier for register spacing
 */
void _OSMReadStringUExact32(unsigned int baseAddr, unsigned int flags,
                            unsigned int offset, unsigned int *destBuffer,
                            unsigned int count, int stride)
{
    unsigned int i;
    int regIndex;
    int destIndex;
    unsigned int value;
    unsigned int (*swapFunc)(unsigned int);

    // Select swap function based on flags
    if ((flags & 0x2) != 0) {
        // Bit 1 set: byte swap mode (full endian conversion)
        swapFunc = _swap32_byte;
    }
    else if ((flags & 0x1) != 0) {
        // Bit 0 set: word swap mode (swap 16-bit halves)
        swapFunc = _swap32_word;
    }
    else {
        // Normal mode, no swapping
        swapFunc = _swap32_normal;
    }

    regIndex = 0;
    destIndex = 0;
    for (i = 0; i < count; i++) {
        // Read from hardware with 4-byte aligned addressing
        value = *(unsigned int *)(baseAddr + offset + regIndex * 4);
        // Apply byte/word swapping
        destBuffer[destIndex] = swapFunc(value);
        destIndex++;
        regIndex += stride;
    }
}

/*
 * OSMWriteUExact8 - Write an 8-bit value to hardware register
 *
 * Based on decompiled code from binary.
 * Writes a single byte to a hardware register and ensures the write is
 * ordered correctly using the PowerPC eieio (Enforce In-order Execution
 * of I/O) instruction.
 *
 * Function signature from decompiled code:
 * void _OSMWriteUExact8(int param_1)
 *
 * Decompiled structure:
 * - param_1 = base address
 * - param_9 (second param) = offset from base
 * - param_10 (third param) = value to write
 * - Writes byte to (param_1 + param_9)
 * - Calls enforceInOrderExecutionIO() to ensure write completes
 *
 * The eieio() barrier is critical for:
 * - Ensuring writes complete before subsequent operations
 * - Preventing out-of-order execution that could cause hardware errors
 * - Maintaining proper sequencing for device register updates
 *
 * @param baseAddr Base address of hardware registers
 * @param offset Offset from base address
 * @param value Byte value to write
 */
void _OSMWriteUExact8(unsigned int baseAddr, unsigned int offset, unsigned char value)
{
    *(unsigned char *)(baseAddr + offset) = value;
    eieio();  // Enforce in-order execution of I/O
}

/*
 * OSMWriteUExact16 - Write a 16-bit value to hardware register
 *
 * Based on decompiled code from binary.
 * Writes a 16-bit word to a hardware register with optional byte swapping
 * and ensures write ordering with eieio.
 *
 * Function signature from decompiled code:
 * void _OSMWriteUExact16(int param_1, uint param_2)
 *
 * Decompiled structure:
 * - param_1 = base address
 * - param_2 = flags (bit 1 controls byte swapping)
 * - param_9 (third param) = offset from base
 * - param_10 (fourth param) = value to write
 * - If (flags & 2) != 0: byte swap the value before writing
 * - Else: write value as-is (bit 0 flag doesn't affect writes)
 * - Calls enforceInOrderExecutionIO() after write
 *
 * Byte swap operation for writes:
 * - Normal: value written as-is
 * - Swapped: (value >> 8) | (value << 8)
 *
 * @param baseAddr Base address of hardware registers
 * @param flags Bit 1 (0x2) controls byte swapping
 * @param offset Offset from base address
 * @param value 16-bit value to write
 */
void _OSMWriteUExact16(unsigned int baseAddr, unsigned int flags,
                       unsigned int offset, unsigned short value)
{
    unsigned short writeValue;

    if ((flags & 0x2) != 0) {
        // Byte swap mode
        writeValue = (value >> 8) | (value << 8);
    }
    else {
        // Normal mode (bit 0 doesn't affect the write)
        writeValue = value;
    }

    *(unsigned short *)(baseAddr + offset) = writeValue;
    eieio();  // Enforce in-order execution of I/O
}

/*
 * OSMWriteUExact32 - Write a 32-bit value to hardware register
 *
 * Based on decompiled code from binary.
 * Writes a 32-bit doubleword to a hardware register with optional byte
 * swapping and ensures write ordering with eieio.
 *
 * Function signature from decompiled code:
 * void _OSMWriteUExact32(int param_1, uint param_2)
 *
 * Decompiled structure:
 * - param_1 = base address
 * - param_2 = flags (bit 1 controls byte swapping)
 * - param_9 (third param) = offset from base
 * - param_10 (fourth param) = value to write
 * - If (flags & 2) != 0: perform full byte swap before writing
 * - Else: write value as-is
 * - Calls enforceInOrderExecutionIO() after write
 *
 * Byte swap operation:
 * - (value << 24): byte 0 → position 3
 * - ((value & 0xff00) << 8): byte 1 → position 2
 * - ((value >> 8) & 0xff00): byte 2 → position 1
 * - (value >> 24): byte 3 → position 0
 * Result: [b0,b1,b2,b3] → [b3,b2,b1,b0]
 *
 * @param baseAddr Base address of hardware registers
 * @param flags Bit 1 (0x2) controls byte swapping
 * @param offset Offset from base address
 * @param value 32-bit value to write
 */
void _OSMWriteUExact32(unsigned int baseAddr, unsigned int flags,
                       unsigned int offset, unsigned int value)
{
    unsigned int writeValue;

    if ((flags & 0x2) != 0) {
        // Full byte swap mode
        writeValue = (value << 24) |
                     ((value & 0xff00) << 8) |
                     ((value >> 8) & 0xff00) |
                     (value >> 24);
    }
    else {
        // Normal mode
        writeValue = value;
    }

    *(unsigned int *)(baseAddr + offset) = writeValue;
    eieio();  // Enforce in-order execution of I/O
}

/*
 * OSMWriteStringUExact8 - Write a string of 8-bit values to hardware
 *
 * Based on decompiled code from binary.
 * Writes multiple bytes to hardware registers with configurable stride,
 * ensuring each write completes with eieio before continuing. This is
 * used for bulk data transfers to SCSI FIFOs.
 *
 * Function signature from decompiled code:
 * void _OSMWriteStringUExact8(int param_1)
 *
 * Decompiled structure:
 * - param_1 = base address
 * - param_9 = offset from base
 * - param_10 = source buffer
 * - param_11 = count of bytes to write
 * - param_12 = stride multiplier
 * - Writes to (param_1 + param_9 + i*4) where i increments by param_12
 * - Reads from (param_10 + sequential offset)
 * - Calls enforceInOrderExecutionIO() after each write
 *
 * The eieio() after each write ensures that writes complete in order,
 * which is critical for FIFO operations where data must be written
 * sequentially.
 *
 * @param baseAddr Base address of hardware registers
 * @param offset Offset from base address
 * @param srcBuffer Source buffer containing data to write
 * @param count Number of bytes to write
 * @param stride Stride multiplier for register spacing
 */
void _OSMWriteStringUExact8(unsigned int baseAddr, unsigned int offset,
                            unsigned char *srcBuffer, unsigned int count,
                            int stride)
{
    unsigned int i;
    int regIndex;

    regIndex = 0;
    for (i = 0; i < count; i++) {
        // Write to hardware with 4-byte aligned addressing
        *(unsigned char *)(baseAddr + offset + regIndex * 4) = srcBuffer[i];
        eieio();  // Enforce ordering after each write
        regIndex += stride;
    }
}

/*
 * OSMWriteStringUExact16 - Write a string of 16-bit values to hardware
 *
 * Based on decompiled code from binary.
 * Writes multiple 16-bit words to hardware registers with optional byte
 * swapping and configurable stride. Each write is followed by eieio to
 * ensure proper ordering.
 *
 * Function signature from decompiled code:
 * void _OSMWriteStringUExact16(int param_1, uint param_2)
 *
 * Decompiled structure:
 * - param_1 = base address
 * - param_2 = flags (bit 0 and bit 1 control swapping mode)
 * - param_9 = offset from base
 * - param_10 = source buffer
 * - param_11 = count of words to write
 * - param_12 = stride multiplier
 * - Function pointer selection for byte swapping (same as read functions)
 * - Calls enforceInOrderExecutionIO() after each write
 *
 * @param baseAddr Base address of hardware registers
 * @param flags Bit 0 and bit 1 control endianness mode
 * @param offset Offset from base address
 * @param srcBuffer Source buffer containing data to write
 * @param count Number of 16-bit words to write
 * @param stride Stride multiplier for register spacing
 */
void _OSMWriteStringUExact16(unsigned int baseAddr, unsigned int flags,
                             unsigned int offset, unsigned short *srcBuffer,
                             unsigned int count, int stride)
{
    unsigned int i;
    int regIndex;
    int srcIndex;
    unsigned short value;
    unsigned short (*swapFunc)(unsigned short);

    // Select swap function based on flags
    if ((flags & 0x2) != 0) {
        // Bit 1 set: byte swap mode
        swapFunc = _swap16_byte;
    }
    else if ((flags & 0x1) != 0) {
        // Bit 0 set: alternate swap mode
        swapFunc = _swap16_word;
    }
    else {
        // Normal mode, no swapping
        swapFunc = _swap16_normal;
    }

    regIndex = 0;
    srcIndex = 0;
    for (i = 0; i < count; i++) {
        // Apply byte swapping to source value
        value = swapFunc(srcBuffer[srcIndex]);
        // Write to hardware with 4-byte aligned addressing
        *(unsigned short *)(baseAddr + offset + regIndex * 4) = value;
        eieio();  // Enforce ordering after each write
        regIndex += stride;
        srcIndex++;
    }
}

/*
 * OSMWriteStringUExact32 - Write a string of 32-bit values to hardware
 *
 * Based on decompiled code from binary.
 * Writes multiple 32-bit doublewords to hardware registers with optional
 * byte/word swapping and configurable stride. Similar to the 16-bit version
 * but operates on 32-bit values.
 *
 * Function signature from decompiled code:
 * void _OSMWriteStringUExact32(int param_1, uint param_2)
 *
 * Decompiled structure:
 * - param_1 = base address
 * - param_2 = flags (bit 0 and bit 1 control swapping mode)
 * - param_9 = offset from base
 * - param_10 = source buffer
 * - param_11 = count of doublewords to write
 * - param_12 = stride multiplier
 * - Function pointer selection for byte/word swapping
 * - Calls enforceInOrderExecutionIO() after each write
 *
 * @param baseAddr Base address of hardware registers
 * @param flags Bit 0 and bit 1 control endianness mode
 * @param offset Offset from base address
 * @param srcBuffer Source buffer containing data to write
 * @param count Number of 32-bit doublewords to write
 * @param stride Stride multiplier for register spacing
 */
void _OSMWriteStringUExact32(unsigned int baseAddr, unsigned int flags,
                             unsigned int offset, unsigned int *srcBuffer,
                             unsigned int count, int stride)
{
    unsigned int i;
    int regIndex;
    int srcIndex;
    unsigned int value;
    unsigned int (*swapFunc)(unsigned int);

    // Select swap function based on flags
    if ((flags & 0x2) != 0) {
        // Bit 1 set: byte swap mode (full endian conversion)
        swapFunc = _swap32_byte;
    }
    else if ((flags & 0x1) != 0) {
        // Bit 0 set: word swap mode (swap 16-bit halves)
        swapFunc = _swap32_word;
    }
    else {
        // Normal mode, no swapping
        swapFunc = _swap32_normal;
    }

    regIndex = 0;
    srcIndex = 0;
    for (i = 0; i < count; i++) {
        // Apply byte/word swapping to source value
        value = swapFunc(srcBuffer[srcIndex]);
        // Write to hardware with 4-byte aligned addressing
        *(unsigned int *)(baseAddr + offset + regIndex * 4) = value;
        eieio();  // Enforce ordering after each write
        regIndex += stride;
        srcIndex++;
    }
}

/*
 * OSMSynchronizeRange - Synchronize cache for a memory range
 *
 * Based on decompiled code from binary.
 * This function is a no-op on this platform. On other architectures,
 * it might be used to flush/invalidate CPU caches for DMA coherency.
 *
 * Function signature from decompiled code:
 * void _OSMSynchronizeRange(void)
 *
 * The function returns immediately without any operations, indicating
 * that cache synchronization is either:
 * - Not needed on PowerPC with this hardware
 * - Handled automatically by the hardware/chipset
 * - Performed by other mechanisms (like flush_cache_v calls)
 *
 * @param (parameters not used - function is a no-op)
 */
void _OSMSynchronizeRange(void)
{
    // No-op on this platform
    // Cache synchronization is handled by other mechanisms or not needed
    return;
}

/*
 * OSMWatchdog - Set up a watchdog timer
 *
 * Based on decompiled code from binary.
 * Sets up a nanosecond-resolution timeout using the kernel's ns_timeout
 * facility. This is used by the CHIM to detect and recover from hardware
 * timeouts or hung operations.
 *
 * Function signature from decompiled code:
 * void _OSMWatchdog(int param_1, undefined4 param_2, uint param_3)
 *
 * Decompiled structure:
 * - param_1 = adapter pointer
 * - param_2 = callback function pointer
 * - param_3 = timeout value in microseconds
 * - Gets HIM handle from adapter+0x2a8
 * - Multiplies timeout by 1000 to convert microseconds to nanoseconds
 * - Calls ns_timeout with:
 *   - proc = callback function (param_2)
 *   - arg = HIM handle from adapter+0x2a8
 *   - time = timeout in nanoseconds (param_3 * 1000)
 *   - pri = 4 (priority level)
 *
 * The 64-bit time value is created by multiplying the microsecond timeout
 * by 1000 to get nanoseconds, as required by ns_timeout.
 *
 * @param adapter Pointer to AdaptecU2SCSI adapter instance
 * @param callback Callback function to invoke on timeout
 * @param timeoutMicroseconds Timeout value in microseconds
 */
void _OSMWatchdog(void *adapter, void *callback, unsigned int timeoutMicroseconds)
{
    unsigned int *adapterPtr;
    void *himHandle;
    ns_time_t timeoutNanoseconds;

    adapterPtr = (unsigned int *)adapter;

    // Get HIM handle from adapter offset 0x2a8
    himHandle = (void *)adapterPtr[0x2a8 / 4];

    // Convert microseconds to nanoseconds
    timeoutNanoseconds = (ns_time_t)timeoutMicroseconds * 1000ULL;

    // Schedule timeout with priority 4
    ns_timeout((func)callback, himHandle, timeoutNanoseconds, 4);
}

/*
 * OSMSaveInterruptState - Save current interrupt state
 *
 * Based on decompiled code from binary.
 * Returns the current interrupt enable state. On this platform, this
 * function always returns 0, indicating that interrupt state management
 * is handled differently or not required.
 *
 * Function signature from decompiled code:
 * undefined4 _OSMSaveInterruptState(void)
 *
 * Decompiled structure:
 * - Simply returns 0
 * - No actual interrupt state manipulation
 *
 * This is likely because:
 * - Interrupt handling is managed by the kernel/DriverKit framework
 * - The CHIM doesn't need to disable interrupts on this platform
 * - Critical sections are protected by other mechanisms (locks)
 *
 * @return 0 (interrupt state - always returns 0 on this platform)
 */
unsigned int _OSMSaveInterruptState(void)
{
    // Always return 0 - interrupt state management not needed
    return 0;
}

/*
 * OSMSetInterruptState - Restore interrupt state
 *
 * Based on decompiled code from binary.
 * Restores the interrupt state previously saved by OSMSaveInterruptState.
 * On this platform, this is a no-op as interrupt state management is
 * not required.
 *
 * Function signature from decompiled code:
 * void _OSMSetInterruptState(void)
 *
 * Decompiled structure:
 * - Simply returns without doing anything
 * - Matches OSMSaveInterruptState behavior (no-op)
 *
 * This function would typically be called with the value returned from
 * _OSMSaveInterruptState, but since that always returns 0 and this
 * function doesn't use parameters, both are effectively no-ops.
 *
 * @param (state parameter not used - function is a no-op)
 */
void _OSMSetInterruptState(void)
{
    // No-op - interrupt state management not needed on this platform
    return;
}

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
void *OSMRoutines[31] = {
    NULL,                                   // 0x00: Reserved/padding
    _OSMMapIOHandle,                        // 0x04: Map I/O handle
    _OSMReleaseIOHandle,                    // 0x08: Release I/O handle
    _OSMEvent,                              // 0x0c: Event notification
    _OSMGetBusAddress,                      // 0x10: Get bus address
    _OSMAdjustBusAddress,                   // 0x14: Adjust bus address
    _OSMGetNVSize,                          // 0x18: Get NVRAM size
    _OSMPutNVData,                          // 0x1c: Put NVRAM data
    _OSMGetNVData,                          // 0x20: Get NVRAM data
    _OSMReadUExact8,                        // 0x24: Read 8-bit unaligned
    _OSMReadUExact16,                       // 0x28: Read 16-bit unaligned
    _OSMReadUExact32,                       // 0x2c: Read 32-bit unaligned
    _OSMReadStringUExact8,                  // 0x30: Read 8-bit string
    _OSMReadStringUExact16,                 // 0x34: Read 16-bit string
    _OSMReadStringUExact32,                 // 0x38: Read 32-bit string
    _OSMWriteUExact8,                       // 0x3c: Write 8-bit unaligned
    _OSMWriteUExact16,                      // 0x40: Write 16-bit unaligned
    _OSMWriteUExact32,                      // 0x44: Write 32-bit unaligned
    _OSMWriteStringUExact8,                 // 0x48: Write 8-bit string
    _OSMWriteStringUExact16,                // 0x4c: Write 16-bit string
    _OSMWriteStringUExact32,                // 0x50: Write 32-bit string
    _OSMSynchronizeRange,                   // 0x54: Synchronize cache range
    _OSMWatchdog,                           // 0x58: Watchdog timer
    _OSMSaveInterruptState,                 // 0x5c: Save interrupt state
    _OSMSetInterruptState,                  // 0x60: Set interrupt state
    _OSMReadPCIConfigurationDword,          // 0x64: Read PCI config dword
    _OSMReadPCIConfigurationWord,           // 0x68: Read PCI config word
    _OSMReadPCIConfigurationByte,           // 0x6c: Read PCI config byte
    _OSMWritePCIConfigurationDword,         // 0x70: Write PCI config dword
    _OSMWritePCIConfigurationWord,          // 0x74: Write PCI config word
    _OSMWritePCIConfigurationByte           // 0x78: Write PCI config byte
};
