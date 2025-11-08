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
 * AdaptecU2SCSIThread.m - I/O Thread Implementation
 * Category methods for thread-based request processing
 */

#import "AdaptecU2SCSI.h"
#import "OSMFunctions.h"

#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <kernserv/prototypes.h>
#import <mach/vm_param.h>

// Forward declarations for thread methods
extern void ResetSCSIBus(id adapter, void *request);

void AdaptecU2SCSIIOThread(thread_call_spec_t spec, thread_call_t call)
{
    id adapter = (id)spec;
    (void)call;

    if (adapter == nil) {
        return;
    }

    [adapter commandRequestOccurred];
}

@implementation AdaptecU2SCSI(AdaptecU2SCSIThread)

// I/O thread entry point - processes requests from the disconnectedQueue
// This method is called when a message arrives on the interrupt port
- (void)commandRequestOccurred
{
    void *request;
    unsigned int *requestPtr;
    unsigned int *queuePtr;
    unsigned int *prevPtr;
    unsigned int *nextPtr;
    int requestType;
    id conditionLock;

    // Lock the incoming queue (offset 0x5a8)
    (*lockMethod)(incomingQueueLock, @selector(lock));

    // Process all requests in the disconnectedQueue (offset 0x590)
    queuePtr = (unsigned int *)&disconnectedQueue;

    while (1) {
        // Check if queue is empty
        if (queuePtr == (unsigned int *)queuePtr[0]) {
            // Queue empty - unlock and return
            (*unlockMethod)(incomingQueueLock, @selector(unlock));
            return;
        }

        // Dequeue first request from disconnectedQueue
        request = (void *)queuePtr[0];  // Get head
        requestPtr = (unsigned int *)request;

        // Get prev/next pointers (offsets 0x24 and 0x28)
        prevPtr = (unsigned int *)requestPtr[0x24 / 4];
        nextPtr = (unsigned int *)requestPtr[0x28 / 4];

        // Update prev's next pointer
        if (queuePtr == prevPtr) {
            queuePtr[1] = (unsigned int)nextPtr;  // Update tail
        } else {
            prevPtr[0x28 / 4] = (unsigned int)nextPtr;
        }

        // Update next's prev pointer
        if (queuePtr == nextPtr) {
            queuePtr[0] = (unsigned int)prevPtr;  // Update head
        } else {
            nextPtr[0x24 / 4] = (unsigned int)prevPtr;
        }

        // Unlock queue while processing request
        (*unlockMethod)(incomingQueueLock, @selector(unlock));

        // Get request type from offset 0x0
        requestType = requestPtr[0];

        // Dispatch based on request type
        if (requestType == 1) {
            // Type 1: Probe/initialize target
            ProbeTarget(self, request);
        } else if (requestType == 0) {
            // Type 0: Execute SCSI command
            [self threadExecuteRequest:request];
        } else if (requestType == 2) {
            // Type 2: Reset SCSI bus
            [self threadResetSCSIBus:request];
        } else if (requestType == 3) {
            // Type 3: Exit I/O thread
            // Get condition lock from request (offset 0x14)
            conditionLock = (id)requestPtr[0x14 / 4];

            // Lock and unlock with value 1 to signal completion
            [conditionLock lock];
            [conditionLock unlockWith:1];

            // Terminate this thread
            IOExitThread();

            // This won't be reached, but compiler needs it
            ProbeTarget(self, request);
        }

        // Re-lock queue for next iteration
        (*lockMethod)(incomingQueueLock, @selector(lock));
    }
}

// Thread method to execute a SCSI command request
// Builds scatter-gather list, configures IOB, and enqueues to target
- (void)threadExecuteRequest:(void *)request
{
    unsigned int *requestPtr = (unsigned int *)request;
    IOSCSIRequest *scsiReq;
    void *iob;
    unsigned int *iobPtr;
    unsigned int *sgList;
    unsigned int *sgEntry;
    void *buffer;
    vm_task_t client;
    unsigned int cdbLength;
    unsigned int dataLength;
    unsigned int numPages;
    unsigned int numSGEntries;
    unsigned int bytesProcessed;
    unsigned int chunkSize;
    unsigned int physAddr;
    unsigned int physAddrSwapped;
    unsigned int lengthSwapped;
    unsigned int flags;
    unsigned int targetIndex;
    void *targetStruct;
    id conditionLock;
    BOOL success = NO;
    int result;

    // Allocate an OSM IOB structure
    iob = _AllocOSMIOB(self);
    iobPtr = (unsigned int *)iob;

    // Get IOSCSIRequest pointer from request offset 0x10
    scsiReq = *(IOSCSIRequest **)(requestPtr + 0x10 / 4);

    // Get data transfer length from IOSCSIRequest offset 0x14
    dataLength = scsiReq->maxTransfer;

    // Check if there's data to transfer
    if (dataLength <= 0) {
        success = YES;
        goto setupIOB;
    }

    // Get buffer pointer from request offset 0x14
    buffer = *(void **)(requestPtr + 0x14 / 4);

    // Get client task from request offset 0x18
    client = *(vm_task_t *)(requestPtr + 0x18 / 4);

    // Get scatter-gather buffer from IOB offset 0x74
    sgList = *(unsigned int **)(iobPtr + 0x74 / 4);

    if (client == 0xffffffff) {
        // IOMemoryDescriptor case - use getPhysicalRanges:
        id memDesc = (id)buffer;
        unsigned int rangeCount = 1;
        unsigned int rangeByteCount;
        unsigned int rangePhysAddr;
        unsigned int totalBytes = dataLength;
        unsigned int position = 0;

        // Set position to start
        [memDesc setPosition:0];

        numSGEntries = 0;
        bytesProcessed = 0;
        sgEntry = sgList;

        // Build scatter-gather list from IOMemoryDescriptor
        while (totalBytes != 0 && numSGEntries < 0x200) {
            // Get one physical range
            [memDesc getPhysicalRanges:&rangePhysAddr
                          maxByteCount:0xffffff
                                     n:&rangeCount
                             byteCount:&rangeByteCount
                             remaining:&position];

            if (rangeCount != 1) {
                goto error;
            }

            // Byte-swap physical address (big-endian to little-endian for hardware)
            physAddrSwapped = (rangePhysAddr << 24) |
                             ((rangePhysAddr & 0xff00) << 8) |
                             ((rangePhysAddr >> 8) & 0xff00) |
                             (rangePhysAddr >> 24);

            // Byte-swap length
            lengthSwapped = (rangeByteCount << 24) |
                           ((rangeByteCount & 0xff00) << 8) |
                           ((rangeByteCount >> 8) & 0xff00) |
                           (rangeByteCount >> 24);

            // Store address and length in S/G list
            sgEntry[0] = physAddrSwapped;
            sgEntry[1] = lengthSwapped;

            bytesProcessed += rangeByteCount;
            totalBytes -= rangeByteCount;
            sgEntry += 2;
            numSGEntries++;
        }

        // Mark last entry with end bit (0x80 in byte-swapped high byte)
        sgList[numSGEntries * 2 - 1] |= 0x80;

        // Store S/G list info in IOB
        iobPtr[0x4c / 4] = (unsigned int)sgList;
        iobPtr[0x50 / 4] = bytesProcessed;
        iobPtr[0x48 / 4] = numSGEntries * 8;

        // Get physical address of S/G list itself
        result = IOPhysicalFromVirtual(IOVmTaskSelf(), (void *)sgList, &physAddr);
        if (result != 0) {
            IOLog("AdaptecU2SCSI: Cannot get physical address.\n");
            requestPtr[0x18 / 4] = 9;  // Error status
            goto error;
        }

        success = YES;
        iobPtr[0x44 / 4] = physAddr;

    } else {
        // Direct buffer case - use IOPhysicalFromVirtual
        // Calculate number of pages needed
        numPages = (((unsigned int)buffer + page_mask + dataLength) & ~page_mask) -
                   (((unsigned int)buffer) & ~page_mask);
        numPages /= page_size;

        if (numPages >= 0x201) {
            // Too many pages (max 512)
            IOLog("AdaptecU2SCSI: Max DMA Count Exceeded (max: %d, request: %d)\n",
                  page_size * 0x1fe, dataLength);
            requestPtr[0x18 / 4] = 0x17;  // Error status
            goto error;
        }

        // Build scatter-gather list from buffer pages
        bytesProcessed = 0;
        numSGEntries = 0;
        sgEntry = sgList;

        for (numSGEntries = 0; numSGEntries < numPages; numSGEntries++) {
            // Calculate chunk size (up to next page boundary)
            chunkSize = (((unsigned int)buffer + page_mask + 1) & ~page_mask) - (unsigned int)buffer;
            if (dataLength <= chunkSize) {
                chunkSize = dataLength;
            }

            // Get physical address for this chunk
            result = IOPhysicalFromVirtual(client, buffer, &physAddr);
            if (result != 0) {
                IOLog("AdaptecU2SCSI: Cannot get physical address.\n");
                requestPtr[0x18 / 4] = 9;  // Error status
                goto error;
            }

            // Byte-swap physical address
            physAddrSwapped = (physAddr << 24) |
                             ((physAddr & 0xff00) << 8) |
                             ((physAddr >> 8) & 0xff00) |
                             (physAddr >> 24);

            // Byte-swap length
            lengthSwapped = (chunkSize << 24) |
                           ((chunkSize & 0xff00) << 8) |
                           ((chunkSize >> 8) & 0xff00) |
                           (chunkSize >> 24);

            // Store in S/G list
            sgEntry[0] = physAddrSwapped;
            sgEntry[1] = lengthSwapped;

            bytesProcessed += chunkSize;
            buffer += chunkSize;
            dataLength -= chunkSize;
            sgEntry += 2;
        }

        // Mark last entry with end bit
        sgList[numSGEntries * 2 - 1] |= 0x80;

        // Store S/G list info in IOB
        iobPtr[0x4c / 4] = (unsigned int)sgList;
        iobPtr[0x50 / 4] = bytesProcessed;
        iobPtr[0x48 / 4] = numSGEntries * 8;

        // Get physical address of S/G list
        result = IOPhysicalFromVirtual(IOVmTaskSelf(), (void *)sgList, &physAddr);
        if (result != 0) {
            IOLog("AdaptecU2SCSI: Cannot get physical address.\n");
            requestPtr[0x18 / 4] = 9;  // Error status
            goto error;
        }

        success = YES;
        iobPtr[0x44 / 4] = physAddr;
    }

setupIOB:
    if (!success) {
        // Signal completion with error
        conditionLock = (id)requestPtr[0x14 / 4];
        (*condLockLock)(conditionLock, @selector(lock));
        (*condLockUnlockWith)(conditionLock, @selector(unlockWith:), 1);
        return;
    }

    // Get target structure from targetStructures array
    targetIndex = scsiReq->target;
    targetStruct = targetStructures[targetIndex];

    // Get CDB length from request offset 0x4
    cdbLength = requestPtr[0x4 / 4];

    // Clear field at offset 0xc
    iobPtr[0xc / 4] = 0;

    // Build flags field at offset 0x14
    flags = iobPtr[0x14 / 4];

    // Bit 31: direction (read/write) from scsiReq->driverStatus bit 28
    flags = (flags & 0x7fffffff) |
            ((((scsiReq->driverStatus ^ 0x10000000) >> 28) & 1) << 31);

    // Bit 25: flag from scsiReq->driverStatus bit 30
    flags = (flags & 0x7dffffff) |
            ((((scsiReq->driverStatus ^ 0x40000000) >> 30) & 1) << 25);

    // Bit 30: read flag from scsiReq->read bit 0
    flags = (flags & 0x3dffffff) |
            (((scsiReq->read & 1) << 30));

    // Bit 29: disconnect allowed (inverse of scsiReq->read)
    flags = (flags & 0x19ffffff) |
            (((scsiReq->read == 0 ? 1 : 0) << 29));

    iobPtr[0x14 / 4] = flags;

    // Set various IOB fields
    iobPtr[0x58 / 4] = (unsigned int)(((unsigned char *)scsiReq) + 0x3c);  // Sense buffer
    iobPtr[0x1c / 4] = 0;
    iobPtr[0x5c / 4] = 0x1c;  // Sense buffer size (28 bytes)
    iobPtr[0x20 / 4] = (unsigned int)request;  // Store request pointer
    iobPtr[0x34 / 4] = (unsigned int)NormalPostRoutine;  // Completion routine
    iobPtr[0x38 / 4] = (unsigned int)(((unsigned char *)scsiReq) + 4);  // CDB pointer
    iobPtr[0x28 / 4] = *(unsigned int *)((unsigned int)targetStruct + 4);  // Target field
    iobPtr[0x3c / 4] = cdbLength;  // CDB length
    iobPtr[0x68 / 4] = 0;
    iobPtr[0x70 / 4] = (unsigned int)targetStruct;  // Target structure
    iobPtr[0x84 / 4] = (unsigned int)kernelInterruptPort;  // Interrupt port

    // Update statistics
    activeCommand++;
    if (maxQueueLen < activeCommand) {
        maxQueueLen = activeCommand;
    }
    sumQueueLengths += activeCommand;

    // Get timestamp
    IOGetTimestamp(((unsigned char *)iob) + 0x7c);

    // Enqueue IOB to target's waiting queue
    _EnqueueOsmIOB(iob, targetStruct);
    return;

error:
    // Signal completion with error
    conditionLock = (id)requestPtr[0x14 / 4];
    (*condLockLock)(conditionLock, @selector(lock));
    (*condLockUnlockWith)(conditionLock, @selector(unlockWith:), 1);
}

// Thread method to reset the SCSI bus
// Simply calls external ResetSCSIBus function
- (void)threadResetSCSIBus:(void *)request
{
    ResetSCSIBus(self, request);
}

@end
