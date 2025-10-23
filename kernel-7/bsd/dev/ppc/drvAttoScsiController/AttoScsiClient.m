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

/* AttoScsiClient.m - Atto SCSI Controller Client Interface */

#import "AttoScsiController.h"

@implementation AttoScsiController(Client)

/*
 * SCSI CDB Length Table
 * Indexed by command group (opcode >> 5)
 * Returns the CDB length for each command group
 */
static const u_int8_t kSCSICDBLengthTable[8] = {
    6,      // Group 0 (0x00-0x1F): 6-byte commands
    10,     // Group 1 (0x20-0x3F): 10-byte commands
    10,     // Group 2 (0x40-0x5F): 10-byte commands
    0,      // Group 3 (0x60-0x7F): Variable/reserved (use request length)
    16,     // Group 4 (0x80-0x9F): 16-byte commands
    12,     // Group 5 (0xA0-0xBF): 12-byte commands
    0,      // Group 6 (0xC0-0xDF): Vendor specific (use request length)
    0       // Group 7 (0xE0-0xFF): Vendor specific (use request length)
};

/*
 * getDMAAlignment:
 *
 * Returns DMA alignment requirements for this SCSI controller.
 * Clients use this information to properly align data buffers for DMA transfers.
 *
 * Parameters:
 *   alignment - Pointer to IODMAAlignment structure to fill in
 */
- (void) getDMAAlignment:(IODMAAlignment *)alignment
{
    // Set DMA alignment requirements
    alignment->readStart = 1;     // No special alignment needed for read start
    alignment->writeStart = 1;    // No special alignment needed for write start
    alignment->readLength = 1;    // Any length allowed for reads
    alignment->writeLength = 1;   // Any length allowed for writes
}

/*
 * numberOfTargets
 *
 * Returns the maximum number of SCSI targets supported by this controller.
 * This is always 16 for wide SCSI (8 for narrow, but we support both).
 *
 * Returns:
 *   Number of supported SCSI targets (16)
 */
- (int) numberOfTargets
{
    return MAX_SCSI_TARGETS;
}

/*-----------------------------------------------------------------------------*
 * Grow the SRB pool by allocating a new page of memory.
 *
 * This routine allocates a page of wired kernel memory, divides it into
 * SRB structures, and adds them to the free SRB pool. It runs in a continuous
 * loop to ensure the pool always has SRBs available.
 *
 * The routine:
 *   1. Waits on the pool semaphore (condition = 1)
 *   2. Allocates a page of wired memory
 *   3. Gets the physical address of the page
 *   4. Divides the page into SRB structures (0x2a4 bytes each)
 *   5. Links the SRBs into the free list
 *   6. Adds the page to the pool page list
 *   7. Signals completion (condition = 2) and loops
 *
 * Memory layout of allocated page:
 *   Offset 0x00-0x1f: SRBPoolPage header
 *   Offset 0x20+:     Array of SRB structures
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiGrowSRBPool
{
    vm_address_t        pageAddr;
    vm_address_t        pagePhysAddr;
    kern_return_t       kr;
    vm_task_t           vmTask;
    SRBPoolPage         *poolPage;
    SRB                 *srb;
    SRB                 *freeListHead;
    u_int32_t           srbCount;
    u_int32_t           i;
    u_int32_t           maxSRBs;

    while ( TRUE )
    {
        // Wait for pool allocation request (condition = 1)
        [srbPoolSemaphore lockWhen: 1];

        // Get VM task for kernel
        vmTask = IOVmTaskSelf();

        // Allocate a page of wired memory
        kr = kmem_alloc_wired( vmTask, &pageAddr, page_size );
        if ( kr != KERN_SUCCESS )
        {
            IOPanic("AttoScsiGrowSRBPool: kmem_alloc_wired failed\n\r");
        }

        // Get physical address of the page
        kr = IOPhysicalFromVirtual( vmTask, pageAddr, &pagePhysAddr );

        // Initialize the pool page header
        poolPage = (SRBPoolPage *)pageAddr;
        poolPage->physicalAddr = pagePhysAddr;
        poolPage->inUseCount = 0;

        // Calculate how many SRBs fit in this page
        // Page size minus header (0x20) divided by SRB size (0x2a4)
        maxSRBs = (page_size - 0x20) / SRB_SIZE;

        // Initialize the free SRB list for this page
        freeListHead = (SRB *)&poolPage->freeSRBs;
        poolPage->freeSRBs.next = freeListHead;
        poolPage->freeSRBs.prev = freeListHead;

        // Create SRBs starting at offset 0x20
        srb = (SRB *)((u_int8_t *)pageAddr + 0x20);
        srbCount = 0;

        // Add each SRB to the free list
        for ( i = 0; i < maxSRBs; i++ )
        {
            // Get current tail of free list
            SRB *freeTail = (SRB *)poolPage->freeSRBs.prev;

            // Link this SRB into the free list
            if ( freeTail == freeListHead )
            {
                // First SRB in list
                poolPage->freeSRBs.next = srb;
            }
            else
            {
                // Add after current tail
                freeTail->nextSRB = srb;
            }

            srb->prevSRB = freeTail;
            srb->nextSRB = freeListHead;
            poolPage->freeSRBs.prev = srb;

            // Advance to next SRB (0x2a4 bytes = 0xa9 words)
            srb = (SRB *)((u_int8_t *)srb + SRB_SIZE);
            srbCount++;
        }

        // Add this page to the pool page list
        [srbPoolLock lock];

        // Get current tail of page list
        SRBPoolPage *pageTail = (SRBPoolPage *)srbPoolPages.prev;
        SRBPoolPage *pageHead = (SRBPoolPage *)&srbPoolPages;

        // Link this page into the page list
        if ( pageTail == pageHead )
        {
            // First page in list
            srbPoolPages.next = poolPage;
        }
        else
        {
            // Add after current tail
            pageTail->nextPage = poolPage;
        }

        poolPage->prevPage = pageTail;
        poolPage->nextPage = pageHead;
        srbPoolPages.prev = poolPage;

        [srbPoolLock unlock];

        // Clear the pool flag
        srbPoolFlag = 0;

        // Initialize in-use count
        poolPage->inUseCount = 0;

        // Signal pool allocation complete (condition = 2)
        [srbPoolSemaphore unlockWith: 2];
    }
}

/*-----------------------------------------------------------------------------*
 * Allocate an SRB from the pool.
 *
 * This routine searches the pool pages for a free SRB. If none are available,
 * it signals the pool growth thread and waits for new SRBs to become available.
 *
 * Returns:
 *   Pointer to an initialized SRB
 *
 * The routine:
 *   1. Locks the pool and searches for a free SRB
 *   2. If found, dequeues it from the free list
 *   3. Increments the page's in-use count
 *   4. Zeros the SRB
 *   5. Sets the SRB's physical address
 *   6. Assigns a sequence number
 *   7. Returns the SRB
 *
 * If no free SRB is found, triggers pool growth and waits.
 *-----------------------------------------------------------------------------*/
- (SRB *) AttoScsiAllocSRB
{
    SRBPoolPage     *poolPage;
    SRBPoolPage     *pageHead;
    SRB             *srb;
    SRB             *nextSRB;
    SRB             *freeListHead;
    u_int32_t       pageOffset;

    srb = NULL;

    while ( TRUE )
    {
        // Lock the pool
        [srbPoolLock lock];

        // Iterate through all pool pages
        pageHead = (SRBPoolPage *)&srbPoolPages;
        for ( poolPage = (SRBPoolPage *)srbPoolPages.next;
              poolPage != pageHead;
              poolPage = poolPage->nextPage )
        {
            // Check if this page has free SRBs
            freeListHead = (SRB *)&poolPage->freeSRBs;

            if ( poolPage->freeSRBs.next != freeListHead )
            {
                // Increment in-use count
                poolPage->inUseCount++;

                // Dequeue first SRB from free list
                srb = (SRB *)poolPage->freeSRBs.next;
                nextSRB = srb->nextSRB;

                // Update free list head
                if ( nextSRB == freeListHead )
                {
                    // This was the last free SRB
                    poolPage->freeSRBs.prev = freeListHead;
                }
                else
                {
                    // Update next SRB's prev pointer
                    nextSRB->prevSRB = freeListHead;
                }

                // Advance list head
                poolPage->freeSRBs.next = nextSRB;

                break;
            }
        }

        // Unlock the pool
        [srbPoolLock unlock];

        // If we got an SRB, initialize and return it
        if ( srb != NULL )
        {
            // Zero the entire SRB
            bzero( srb, SRB_SIZE );

            // Calculate and set physical address
            // SRB phys addr = page phys addr + offset of SRB in page
            pageOffset = (u_int32_t)srb - (u_int32_t)poolPage;
            srb->srbPhysAddr = poolPage->physicalAddr + pageOffset;

            // Assign sequence number
            resetSeqNum++;
            srb->srbTimeout = resetSeqNum;

            return srb;
        }

        // No free SRB available - trigger pool growth
        if ( srbPoolFlag == 0 )
        {
            srbPoolFlag = 1;
            [srbPoolSemaphore unlockWith: 1];
        }

        // Wait for pool allocation to complete
        [srbPoolSemaphore lockWhen: 2];
        [srbPoolSemaphore unlockWith: 2];

        // Loop back and try again
    }
}

/*-----------------------------------------------------------------------------*
 * Free an SRB back to the pool.
 *
 * This routine returns an SRB to the free list of its pool page. It also
 * performs garbage collection, freeing pages that have been empty for a while.
 *
 * Parameters:
 *   srb - Pointer to the SRB to free
 *
 * The routine:
 *   1. Finds which pool page owns this SRB
 *   2. Decrements the page's in-use count
 *   3. Adds the SRB to the page's free list
 *   4. Scans for pages with zero in-use count
 *   5. After finding 3+ empty pages, frees older empty pages
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiFreeSRB:(SRB *)srb
{
    SRBPoolPage     *poolPage;
    SRBPoolPage     *pageHead;
    SRBPoolPage     *nextPage;
    SRBPoolPage     *prevPage;
    SRB             *freeListTail;
    SRB             *freeListHead;
    u_int8_t        *srbAddr;
    u_int8_t        *pageStart;
    u_int8_t        *pageEnd;
    u_int32_t       maxSRBs;
    u_int32_t       emptyPageCount;
    kern_return_t   kr;
    vm_task_t       vmTask;

    // Lock the pool
    [srbPoolLock lock];

    // Find which page owns this SRB
    pageHead = (SRBPoolPage *)&srbPoolPages;
    srbAddr = (u_int8_t *)srb;

    for ( poolPage = (SRBPoolPage *)srbPoolPages.next;
          poolPage != pageHead;
          poolPage = poolPage->nextPage )
    {
        // Calculate valid SRB range for this page
        pageStart = (u_int8_t *)poolPage + 0x20;  // SRBs start at offset 0x20
        maxSRBs = (page_size - 0x20) / SRB_SIZE;
        pageEnd = pageStart + (maxSRBs * SRB_SIZE) - 1;

        // Check if SRB falls within this page's range
        if ( srbAddr >= pageStart && srbAddr <= pageEnd )
        {
            // Decrement in-use count
            poolPage->inUseCount--;

            // Add SRB to this page's free list
            freeListHead = (SRB *)&poolPage->freeSRBs;
            freeListTail = (SRB *)poolPage->freeSRBs.prev;

            if ( freeListTail == freeListHead )
            {
                // Free list was empty
                poolPage->freeSRBs.next = srb;
            }
            else
            {
                // Add after current tail
                freeListTail->nextSRB = srb;
            }

            srb->prevSRB = freeListTail;
            srb->nextSRB = freeListHead;
            poolPage->freeSRBs.prev = srb;

            break;
        }
    }

    // Garbage collection: free pages with no SRBs in use
    // Keep at least 3 pages, even if empty
    emptyPageCount = 0;

    for ( poolPage = (SRBPoolPage *)srbPoolPages.next;
          poolPage != pageHead;
          poolPage = nextPage )
    {
        nextPage = poolPage->nextPage;

        if ( poolPage->inUseCount == 0 )
        {
            emptyPageCount++;

            // Free this page if we have more than 3 empty pages
            if ( emptyPageCount > 3 )
            {
                // Remove page from list
                prevPage = poolPage->prevPage;

                if ( nextPage == pageHead )
                {
                    // This was the last page
                    srbPoolPages.prev = prevPage;
                }
                else
                {
                    // Update next page's prev pointer
                    nextPage->prevPage = prevPage;
                }

                if ( prevPage == pageHead )
                {
                    // This was the first page
                    srbPoolPages.next = nextPage;
                }
                else
                {
                    // Update prev page's next pointer
                    prevPage->nextPage = nextPage;
                }

                // Free the page memory
                vmTask = IOVmTaskSelf();
                kr = kmem_free( vmTask, (vm_address_t)poolPage, page_size );
                if ( kr != KERN_SUCCESS )
                {
                    IOPanic("SCSI(Atto): AttoScsiFreeSRB: kmem_free failed\n\r");
                }
            }
        }
    }

    // Unlock the pool
    [srbPoolLock unlock];
}

/*-----------------------------------------------------------------------------*
 * Free a SCSI tag.
 *
 * This routine releases a SCSI tag and unlocks the associated target lock.
 * Tags are tracked using a bitmap where each bit represents one tag.
 *
 * Parameters:
 *   srb - Pointer to the SRB whose tag should be freed
 *
 * The routine:
 *   1. Gets the tag from the SRB
 *   2. Clears the corresponding bit in the tag bitmap
 *   3. Unlocks the appropriate lock:
 *      - For untagged commands (tag < 0x80): per-target lock
 *      - For tagged commands (tag >= 0x80): shared untagged lock
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiFreeTag:(SRB *)srb
{
    u_int8_t    tag;
    u_int8_t    targetID;
    u_int32_t   bitmapIndex;
    u_int32_t   bitMask;
    NXLock      *targetLock;

    // Get the tag from the SRB
    tag = srb->tag;

    // Calculate bitmap index and bit mask
    // bitmapIndex = (tag >> 5) * 4 = (tag >> 3) & 0x1c
    bitmapIndex = (tag >> 3) & 0x1c;

    // Create mask to clear the bit
    // Bit position within the u_int32_t is (tag & 0x1f)
    bitMask = ~(1 << (tag & 0x1f));

    // Clear the bit in the tag bitmap
    tagBitmap[bitmapIndex >> 2] &= bitMask;

    // Unlock the appropriate lock
    if ( tag < MIN_SCSI_TAG )
    {
        // Untagged command - use per-target lock
        targetID = srb->target;
        targetLock = targets[targetID].targetLock;
    }
    else
    {
        // Tagged command - use shared untagged lock
        targetLock = untaggedLock;
    }

    [targetLock unlock];
}

/*-----------------------------------------------------------------------------*
 * Allocate a SCSI tag for a command.
 *
 * This routine allocates a SCSI tag from the tag bitmap. Tags are used to
 * identify commands on the SCSI bus.
 *
 * Parameters:
 *   srb      - Pointer to the SRB needing a tag
 *   cmdQueue - Tag allocation mode:
 *              NO (0): Untagged command - allocate target/LUN-specific tag (0-127)
 *              YES (!0): Tagged command - allocate from tagged pool (128-255)
 *
 * Tag allocation:
 *   - Untagged tags (0-127): One tag per target/LUN combination
 *     Tag = (target * 8) + LUN
 *     Uses per-target lock for synchronization
 *
 *   - Tagged tags (128-255): Shared pool for all targets
 *     Searches for first available tag in range
 *     Uses shared untaggedLock for synchronization
 *
 * The routine loops until a tag becomes available. Locks are used as
 * semaphores - AttoScsiFreeTag unlocks to signal tag availability.
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiAllocTag:(SRB *)srb CmdQueue:(BOOL)cmdQueue
{
    u_int8_t    tag;
    u_int8_t    targetID;
    u_int8_t    lun;
    u_int32_t   bitmapIndex;
    u_int32_t   bitMask;
    u_int32_t   bitmapValue;
    NXLock      *lock;
    BOOL        tagFound;

    while ( TRUE )
    {
        tagFound = NO;

        if ( !cmdQueue )
        {
            // Untagged command - use target/LUN-specific tag
            targetID = srb->target;
            lun = srb->lun;

            // Calculate tag: (target * 8) + LUN
            // This gives tags 0-127 for 16 targets * 8 LUNs
            tag = (targetID * 8) | lun;

            // Calculate bitmap index and bit mask
            // Bitmap word index: (tag >> 3) & 0xfc gives byte offset, divide by 4 for word index
            bitmapIndex = ((tag >> 3) & 0xfc) >> 2;
            bitMask = 1 << (tag & 0x1f);

            // Check if tag is available
            bitmapValue = tagBitmap[bitmapIndex];

            if ( (bitmapValue & bitMask) == 0 )
            {
                // Tag is free - allocate it
                tagBitmap[bitmapIndex] = bitmapValue | bitMask;
                srb->tag = tag;
                return;
            }

            // Tag is busy - get target lock to wait
            lock = targets[targetID].targetLock;
        }
        else
        {
            // Tagged command - search for available tag in range 0x80-0xff
            for ( tag = MIN_SCSI_TAG; tag != 0; tag++ )  // Loops 0x80-0xff, then wraps to 0
            {
                // Calculate bitmap index and bit mask
                bitmapIndex = ((tag >> 3) & 0x1ffffffc) >> 2;
                bitMask = 1 << (tag & 0x1f);

                // Check if tag is available
                bitmapValue = tagBitmap[bitmapIndex];

                if ( (bitmapValue & bitMask) == 0 )
                {
                    // Tag is free - allocate it
                    tagBitmap[bitmapIndex] = bitmapValue | bitMask;
                    srb->tag = tag;
                    tagFound = YES;
                    break;
                }

                // Check if we've wrapped around to 0
                if ( tag == 0xff )
                {
                    break;
                }
            }

            if ( tagFound )
            {
                return;
            }

            // No tagged tags available - get untagged lock to wait
            lock = untaggedLock;
        }

        // Lock and loop - waiting for a tag to become available
        // When AttoScsiFreeTag unlocks this lock, we'll loop and try again
        [lock lock];
    }
}

/*-----------------------------------------------------------------------------*
 * Update scatter-gather list using IOMemoryDescriptor.
 *
 * This routine builds a scatter-gather list for DMA transfers using an
 * IOMemoryDescriptor object. It queries the descriptor for physical memory
 * ranges and constructs SG entries.
 *
 * Parameters:
 *   srb - Pointer to the SRB containing the IOMemoryDescriptor
 *
 * Returns:
 *   YES if SG list built successfully
 *   NO if an error occurred (too many ranges needed)
 *
 * The SG list:
 *   - Starts at srb->sgList[2] (entries 0-1 are reserved)
 *   - Maximum of 65 entries (MAX_SG_ENTRIES)
 *   - Each entry: physAddr (endian swapped) + length|flags (endian swapped)
 *   - Terminators: SG_TERMINATOR_OK for success, SG_TERMINATOR_ERR for overflow
 *-----------------------------------------------------------------------------*/
- (BOOL) AttoScsiUpdateSGListDesc:(SRB *)srb
{
    IOMemoryDescriptor  *memDesc;
    IOReturn            ioReturn;
    IOPhysicalRange     range;
    u_int32_t           newPosition;
    u_int32_t           actualByteCount;
    u_int32_t           actualRangeCount;
    u_int32_t           remainingBytes;
    u_int32_t           sgIndex;
    u_int32_t           lengthWithFlags;
    SGEntry             *sgEntry;
    BOOL                success;

    // Get the IOMemoryDescriptor
    memDesc = (IOMemoryDescriptor *)srb->ioMemoryDescriptor;

    // Calculate remaining bytes to transfer
    remainingBytes = srb->xferEndOffset - srb->xferDoneVirt;

    // Set position in descriptor to current transfer offset
    [memDesc setPosition: srb->xferDoneVirt];

    success = YES;
    sgIndex = 2;  // Start at entry 2 (entries 0-1 are reserved)

    // Build scatter-gather list
    while ( remainingBytes != 0 && sgIndex <= MAX_SG_ENTRIES )
    {
        // Get next physical range from descriptor
        ioReturn = [memDesc getPhysicalRanges: &range
                                 maxByteCount: 0xffffff
                                  newPosition: &newPosition
                              actualByteCount: &actualByteCount
                             actualRangeCount: &actualRangeCount];

        // Check for success and that we got exactly one range
        if ( ioReturn != IO_R_SUCCESS || actualRangeCount != 1 )
        {
            success = NO;
            break;
        }

        // Build SG entry
        sgEntry = &srb->sgList[sgIndex];

        // Set length with flags OR'd in (endian swapped)
        lengthWithFlags = actualByteCount | srb->srbFlags;
        sgEntry->length = EndianSwap32( lengthWithFlags );

        // Set physical address with flags OR'd in (endian swapped)
        lengthWithFlags = range.address | srb->srbFlags;
        sgEntry->physAddr = EndianSwap32( lengthWithFlags );

        // Update remaining bytes
        remainingBytes -= actualByteCount;

        // Advance to next entry
        sgIndex++;
    }

    // Add terminator entry
    sgEntry = &srb->sgList[sgIndex];

    if ( remainingBytes != 0 )
    {
        // Transfer didn't fit in SG list - error terminator
        sgEntry->physAddr = EndianSwap32( SG_TERMINATOR_ERR );
        sgEntry->length = SG_ERROR_LENGTH;  // 15 in big-endian
        success = NO;
    }
    else
    {
        // Normal completion - success terminator
        sgEntry->physAddr = EndianSwap32( SG_TERMINATOR_OK );
        sgEntry->length = 0;
    }

    // Update transfer positions
    srb->xferDonePhys = srb->xferDoneVirt;
    srb->xferDoneVirt = newPosition;

    return success;
}

/*-----------------------------------------------------------------------------*
 * Update scatter-gather list using virtual memory buffer.
 *
 * This routine builds a scatter-gather list for DMA transfers from a virtual
 * memory buffer. It translates virtual addresses to physical addresses and
 * respects page boundaries.
 *
 * Parameters:
 *   srb - Pointer to the SRB containing the buffer information
 *
 * Returns:
 *   YES if SG list built successfully
 *   NO if an error occurred (translation failure or too many pages)
 *
 * The SG list:
 *   - Starts at srb->sgList[2] (entries 0-1 are reserved)
 *   - Maximum of 65 entries (MAX_SG_ENTRIES)
 *   - Each entry: physAddr (endian swapped) + length|flags (endian swapped)
 *   - Respects page boundaries (splits transfers at page edges)
 *   - Terminators: SG_TERMINATOR_OK for success, SG_TERMINATOR_ERR for overflow
 *-----------------------------------------------------------------------------*/
- (BOOL) AttoScsiUpdateSGListVirt:(SRB *)srb
{
    vm_task_t       vmTask;
    vm_address_t    virtAddr;
    vm_address_t    physAddr;
    kern_return_t   kr;
    u_int32_t       currentOffset;
    u_int32_t       remainingBytes;
    u_int32_t       chunkSize;
    u_int32_t       maxChunkSize;
    u_int32_t       pageOffset;
    u_int32_t       sgIndex;
    u_int32_t       lengthWithFlags;
    SGEntry         *sgEntry;
    BOOL            success;

    // Get VM task and buffer pointer
    vmTask = (vm_task_t)srb->srbVMTask;
    virtAddr = (vm_address_t)srb->ioMemoryDescriptor;  // Reused as buffer pointer

    // Calculate current offset and remaining bytes
    currentOffset = srb->xferDoneVirt;
    remainingBytes = srb->xferEndOffset - currentOffset;

    success = YES;
    sgIndex = 2;  // Start at entry 2 (entries 0-1 are reserved)

    // Build scatter-gather list
    while ( remainingBytes != 0 && sgIndex <= MAX_SG_ENTRIES )
    {
        // Translate virtual address to physical
        kr = IOPhysicalFromVirtual( vmTask,
                                     virtAddr + currentOffset,
                                     &physAddr );

        if ( kr != KERN_SUCCESS )
        {
            success = NO;
            break;
        }

        // Calculate maximum chunk size respecting page boundary
        pageOffset = (virtAddr + currentOffset) & (page_size - 1);
        maxChunkSize = page_size - pageOffset;

        // Determine actual chunk size
        chunkSize = (maxChunkSize < remainingBytes) ? maxChunkSize : remainingBytes;

        // Build SG entry
        sgEntry = &srb->sgList[sgIndex];

        // Set physical address (endian swapped)
        sgEntry->physAddr = EndianSwap32( physAddr );

        // Set length with flags OR'd in (endian swapped)
        lengthWithFlags = chunkSize | srb->srbFlags;
        sgEntry->length = EndianSwap32( lengthWithFlags );

        // Update current offset and remaining bytes
        currentOffset += chunkSize;
        remainingBytes -= chunkSize;

        // Advance to next entry
        sgIndex++;
    }

    // Add terminator entry
    sgEntry = &srb->sgList[sgIndex];

    if ( remainingBytes != 0 )
    {
        // Transfer didn't fit in SG list - error terminator
        sgEntry->physAddr = EndianSwap32( SG_TERMINATOR_ERR );
        sgEntry->length = SG_ERROR_LENGTH;  // 15 in big-endian
        success = NO;
    }
    else
    {
        // Normal completion - success terminator
        sgEntry->physAddr = EndianSwap32( SG_TERMINATOR_OK );
        sgEntry->length = 0;
    }

    // Update transfer positions
    srb->xferDonePhys = srb->xferDoneVirt;
    srb->xferDoneVirt = currentOffset;

    return success;
}

/*-----------------------------------------------------------------------------*
 * Send a command to the controller.
 *
 * This routine queues an SRB to the command queue for processing by the
 * controller. It creates a condition lock for the command and waits for
 * completion.
 *
 * Parameters:
 *   srb - SRB to send
 *
 * The routine:
 *   1. Creates NXConditionLock for this SRB
 *   2. Locks it with condition ksrbCmdPending
 *   3. Adds SRB to command queue
 *   4. Calls commandRequestOccurred to process queue
 *   5. Waits for condition ksrbCmdComplete
 *   6. Frees the lock
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiSendCommand:(SRB *)srb
{
    NXConditionLock     *cmdLock;
    SRB                 *queueTail;

    // Create condition lock for this command
    cmdLock = [[NXConditionLock alloc] initWith: ksrbCmdPending];
    srb->srbCmdLock = cmdLock;

    // Lock the queue
    [queueLock lock];

    // Add SRB to tail of command queue
    queueTail = (SRB *)commandQueue.prev;

    if ( queueTail == (SRB *)&commandQueue )
    {
        // Queue was empty
        commandQueue.next = srb;
    }
    else
    {
        // Add after current tail
        queueTail->nextSRB = srb;
    }

    srb->prevSRB = queueTail;
    srb->nextSRB = (SRB *)&commandQueue;
    commandQueue.prev = srb;

    // Unlock the queue
    [queueLock unlock];

    // Process the command queue
    [self commandRequestOccurred];

    // Wait for command completion
    [cmdLock lockWhen: ksrbCmdComplete];
    [cmdLock unlock];

    // Free the lock
    [cmdLock free];
    srb->srbCmdLock = NULL;
}

/*-----------------------------------------------------------------------------*
 * Update scatter-gather list for a command.
 *
 * This is a wrapper that calls the appropriate SG list update routine based
 * on whether the request uses an IOMemoryDescriptor or a virtual buffer.
 *
 * Parameters:
 *   srb - SRB whose scatter-gather list needs updating
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiUpdateSGList:(SRB *)srb
{
    // Check if using IOMemoryDescriptor (bit 28 of srbFlags indicates this)
    if ( srb->srbFlags & 0x10000000 )
    {
        // Using virtual buffer
        [self AttoScsiUpdateSGListVirt: srb];
    }
    else
    {
        // Using IOMemoryDescriptor
        [self AttoScsiUpdateSGListDesc: srb];
    }
}

/*-----------------------------------------------------------------------------*
 * Reset the SCSI bus.
 *
 * This is the client-facing method for resetting the SCSI bus. It allocates
 * an SRB, sends a reset command, and returns the result.
 *
 * Returns:
 *   SC_STATUS_SUCCESS (0) if successful
 *   SC_STATUS_ERROR (-1) if SRB allocation failed
 *   Other status codes based on reset result
 *-----------------------------------------------------------------------------*/
- (sc_status_t) resetSCSIBus
{
    SRB             *srb;
    sc_status_t     status;

    // Allocate an SRB for the reset command
    srb = [self AttoScsiAllocSRB];

    if ( srb == NULL )
    {
        return SR_IOST_MEMALL;  // Memory allocation failure
    }

    // Set up the SRB for bus reset
    srb->srbCmd = ksrbCmdResetSCSIBus;

    // Send the command
    [self AttoScsiSendCommand: srb];

    // Get result from srbRetryCount
    status = (sc_status_t)srb->srbRetryCount;

    // Free the SRB
    [self AttoScsiFreeSRB: srb];

    return status;
}

/*-----------------------------------------------------------------------------*
 * Execute a SCSI request.
 *
 * This is the main entry point for executing SCSI I/O requests. It sets up
 * an SRB from the IOSCSIRequest, executes the command, and returns results.
 *
 * Parameters:
 *   scsiReq - IOSCSIRequest structure with command parameters
 *   buffer  - Data buffer pointer (virtual address)
 *   client  - Client VM task
 *
 * Returns:
 *   SC_STATUS_SUCCESS (0) if successful
 *   Error code otherwise
 *-----------------------------------------------------------------------------*/
- (sc_status_t) executeRequest:(IOSCSIRequest *)scsiReq
                         buffer:(void *)buffer
                         client:(vm_task_t)client
{
    SRB             *srb;
    sc_status_t     status;
    u_int32_t       startTime[2];
    u_int32_t       endTime[2];
    u_int32_t       cdbLength;
    u_int8_t        groupCode;
    u_int32_t       srbPhysAddr;
    BOOL            isRead;

    // Get current timestamp
    IOGetTimestamp( startTime );

    // Wait for any reset quiesce period to complete
    while ( resetQuiesceTimer != 0 )
    {
        [resetQuiesceSem lock];
    }
    [resetQuiesceSem unlock];

    // Allocate an SRB
    srb = [self AttoScsiAllocSRB];

    if ( srb == NULL )
    {
        return SR_IOST_MEMALL;
    }

    // Set up basic SRB fields
    srb->srbVMTask = client;
    srb->ioMemoryDescriptor = buffer;
    srb->xferEndOffset = scsiReq->maxTransfer;

    // Set up autosense if not disabled
    if ( !(scsiReq->driverFlags & 0x10000000) )
    {
        srb->senseDataBuffer = &scsiReq->senseData;
        srb->senseDataLength = 0x1c;  // Standard sense data length
    }

    // Set command and state
    srb->srbCmd = ksrbCmdExecuteReq;
    srb->srbState = 0x01;  // Normal I/O state

    // Set target and LUN
    srb->target = scsiReq->target;
    srb->lun = scsiReq->lun;

    // Set timeout (convert to milliseconds: timeout * 4 + 1)
    if ( scsiReq->timeout != 0 )
    {
        srb->srbTimeoutStart = scsiReq->timeout * 4 + 1;
    }

    // Set transfer direction flags
    isRead = (scsiReq->read != 0);
    if ( isRead )
    {
        // Read operation - data in
        srb->srbFlags = 0;
    }
    else
    {
        // Write operation - data out
        srb->srbFlags = 0x01000000;
    }

    // Set up target parameters in nexus
    srb->nexus.targetParms[0] = srb->target;

    // Calculate CDB physical address and set in nexus
    srbPhysAddr = srb->srbPhysAddr + 0x6c;
    srb->nexus.cdbData = EndianSwap32( srbPhysAddr );

    // Determine CDB length from command opcode
    groupCode = scsiReq->cdb[0] >> 5;
    cdbLength = kSCSICDBLengthTable[groupCode];

    if ( cdbLength == 0 )
    {
        // Variable length - use length from request
        cdbLength = scsiReq->cdbLength & 0xF;
    }

    srb->nexus.cdbLength = EndianSwap32( cdbLength );

    // Copy CDB from request
    bcopy( scsiReq->cdb, srb->scsiCDB, 12 );  // Copy up to 12 bytes

    // Set capability flags from request
    if ( scsiReq->disconnect )
    {
        srb->targetCapabilities |= kTargetCapTagQueueEnabled;
    }

    if ( scsiReq->cmdQueueDisable )
    {
        // Command queuing disabled
        srb->targetCapabilities &= ~kTargetCapTaggedQueuing;
    }
    else
    {
        // Command queuing enabled
        srb->targetCapabilities |= kTargetCapTaggedQueuing;
    }

    // Calculate SCSI messages
    [self AttoScsiCalcMsgs: srb];

    // Set up SG list physical address (starts at offset 0x9c in SRB)
    srbPhysAddr = srb->srbPhysAddr + 0x9c;
    srb->nexus.ppSGList = EndianSwap32( srbPhysAddr );

    // Build scatter-gather list
    [self AttoScsiUpdateSGList: srb];

    // Send the command
    [self AttoScsiSendCommand: srb];

    // Check if command timed out and needs retry
    if ( srb->srbCmd == ksrbCmdProcessTimeout )
    {
        // Lock timeout processing
        [timeoutLock lock];

        // Set command to abort
        srb->srbCmd = ksrbCmdAbortReq;

        // Retry the command
        [self AttoScsiSendCommand: srb];

        [timeoutLock unlock];
    }

    // Free the tag
    [self AttoScsiFreeTag: srb];

    // Get end timestamp and calculate duration
    IOGetTimestamp( endTime );

    scsiReq->totalTime = endTime[0] - startTime[0];
    if ( endTime[1] < startTime[1] )
    {
        scsiReq->totalTime--;  // Borrow for low word
    }
    scsiReq->latentTime = endTime[1] - startTime[1];

    // Copy results back to request
    scsiReq->driverStatus = (IOReturn)srb->srbRetryCount;
    scsiReq->scsiStatus = srb->scsiStatus;
    scsiReq->bytesTransferred = srb->xferOffset;

    // Free the SRB
    [self AttoScsiFreeSRB: srb];

    // Return status
    status = scsiReq->driverStatus;

    return status;
}

@end
