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

#import "AdaptecU2SCSI.h"
#import <driverkit/IODirectDevice.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <kernserv/prototypes.h>
#import <mach/mach_interface.h>
#import <string.h>

extern void SCSIGetFunctionPointers(void *table, unsigned int size);
extern unsigned int pmac_int_to_number(void);
extern void pmac_register_int(unsigned int num, unsigned int level, void *handler, void *param);
extern void *AdptMallocContiguous(unsigned int size);
extern void *_allocOSMIOB(void *p1, void *p2, void *p3, void *p4, void *p5, void *p6, void *p7, void *p8);
extern void _freeOSMIOB(void *iob, void *p1, void *p2, void *p3, void *p4, void *p5, void *p6, void *p7);
extern void _CleanupWaitingQ(void *targetStruct);
extern void AU2Handler(void);
extern id objc_getClass(const char *name);
extern kern_return_t port_set_backlog(task_t task, port_t port, int backlog);
extern task_t task_self(void);
extern unsigned int page_size;
extern unsigned int page_mask;

// Global adapter queue - one queue per IRQ number (0-255)
// Supports multiple adapters sharing the same IRQ
// Each queue is a circular doubly-linked list of AdapterQueueEntry structures
static queue_head_t adapterQ[256];

// Global OSM routines function table (defined in OSMFunctions.m)
// Size: 0x7c (124 bytes) = 31 entries * 4 bytes each
extern void *OSMRoutines[31];

// Module initialization - called when driver is loaded
// Initializes the global adapter queue array
static void __attribute__((constructor)) AdaptecU2SCSI_module_init(void)
{
    int i;
    for (i = 0; i < 256; i++) {
        queue_init(&adapterQ[i]);
    }
}

@implementation AdaptecU2SCSI

// Class method: Probe for compatible hardware
// Called during driver loading to check if this driver should attach to a device
+ (BOOL)probe:(id)deviceDescription
{
    unsigned int numInterrupts;
    unsigned int pciCommand;
    id instance;

    // Check if device has exactly one interrupt
    numInterrupts = [deviceDescription numInterrupts];
    if (numInterrupts != 1) {
        // Device doesn't have exactly 1 interrupt - not compatible
        return NO;
    }

    // Read PCI Command register (offset 4)
    [deviceDescription configReadLong:4 value:&pciCommand];

    // Enable I/O space (bit 0) and Memory space (bit 1)
    // Write back with bits 0-1 set (OR with 3)
    [deviceDescription configWriteLong:4 value:(pciCommand | 3)];

    // Allocate instance of this class
    instance = [self alloc];

    // Try to initialize from device description
    instance = [instance initFromDeviceDescription:deviceDescription];

    // Return YES if initialization succeeded, NO if it failed
    return (instance != nil);
}

- initFromDeviceDescription : deviceDescription
{
    unsigned char localStackBuffer[1000];
    id condLock;
    unsigned int irq;
    kern_return_t kr;

    // Set up stack buffer pointer at offset 0x244
    // This points to the local stack buffer used for temporary operations
    *((unsigned char **)((unsigned int)self + 0x244)) = localStackBuffer;

    // Initialize thread flags
    ioThreadRunning = NO;          // offset 0x5b0
    initComplete = YES;            // offset 0x5b1

    // Call superclass initializer
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        IOLog("AdaptecU2SCSI: super initFromDeviceDescription failed.\n");
        return [self free];
    }

    // Initialize reserved fields and chimWorkingMemory/numSamples
    chimWorkingMemory = NULL;      // offset 0x578 (also used as numSamples)
    reserved1 = 0;                 // offset 0x4c0
    reserved3 = 0;                 // offset 0x4c8
    reserved2 = 0;                 // offset 0x4c4

    // Set I/O thread running flag
    ioThreadRunning = YES;

    // Reset statistics counters
    [self resetStats];

    // Clear active command pointer (offset 0x5a0)
    activeCommand = NULL;

    // Initialize queues manually (circular doubly-linked lists)
    // Each queue head/tail points to itself when empty

    // incomingQueue (offset 0x580 = head, 0x584 = tail)
    incomingQueue.next = (queue_entry_t)&incomingQueue;
    incomingQueue.prev = (queue_entry_t)&incomingQueue;

    // pendingQueue (offset 0x588 = head, 0x58c = tail)
    pendingQueue.next = (queue_entry_t)&pendingQueue;
    pendingQueue.prev = (queue_entry_t)&pendingQueue;

    // disconnectedQueue (offset 0x590 = head, 0x594 = tail)
    disconnectedQueue.next = (queue_entry_t)&disconnectedQueue;
    disconnectedQueue.prev = (queue_entry_t)&disconnectedQueue;

    // Clear target structures array (offset 0x480, 64 bytes = 16 pointers)
    bzero(targetStructures, 0x40);

    // Create NXLock for queue protection
    incomingQueueLock = [[objc_getClass("NXLock") alloc] init];

    // Get method pointers for NXLock (offsets 0x5c8, 0x5cc)
    lockMethod = [incomingQueueLock methodFor:@selector(lock)];
    unlockMethod = [incomingQueueLock methodFor:@selector(unlock)];

    // Create temporary NXConditionLock to get method pointers
    condLock = [[objc_getClass("NXConditionLock") alloc] init];

    // Get method pointers for NXConditionLock (offsets 0x5b4-0x5c4)
    condLockInitWith = [condLock methodFor:@selector(initWith:)];
    condLockFree = [condLock methodFor:@selector(free)];
    condLockLock = [condLock methodFor:@selector(lock)];
    condLockLockWhen = [condLock methodFor:@selector(lockWhen:)];
    condLockUnlockWith = [condLock methodFor:@selector(unlockWith:)];

    // Free the temporary condition lock
    [condLock free];

    // Convert interrupt port to kernel port (offset 0x5ac)
    kernelInterruptPort = IOConvertPort([self interruptPort], IO_Kernel, IO_KernelIOTask);

    // Set port backlog to 16 messages
    kr = port_set_backlog(task_self(), [self interruptPort], 16);
    if (kr != KERN_SUCCESS) {
        IOLog("%s: error %d on port_set_backlog()\n", [self name], kr);
    }

    // Get CHIM function table (offset 0x4cc, size 0xa8 = 168 bytes = 42 pointers)
    SCSIGetFunctionPointers(chimFunctionTable, 0xa8);

    // Get CHIM working memory requirements
    if (![self getWorkingMemoryForCHIM]) {
        return [self free];
    }

    // Find and verify adapter hardware
    if (![self findAdapter]) {
        return [self free];
    }

    IOLog("AdaptecU2SCSI: Adaptec SCSI Adapter found.\n");

    // Register interrupt handler
    irq = [deviceDescription interrupt];
    [self registerHandlerForIRQ:irq];

    // Initialize adapter via CHIM
    if (![self initAdapter]) {
        return [self free];
    }

    // Scan for SCSI devices
    if (![self scanAdapter]) {
        return [self free];
    }

    // Register with DriverKit
    [self registerDevice];

    // Clear initialization complete flag (driver is now ready)
    initComplete = NO;

    return self;
}

- free
{
    unsigned int i;
    void *entry;
    unsigned int *entryPtr;
    unsigned int *queuePtr;
    unsigned int *prevPtr;
    unsigned int *nextPtr;
    void *targetStruct;
    unsigned char savedProfileArea[436];  // 0x1b4 bytes
    typedef struct {
        id adapter;
        void *prev;
        void *next;
    } AdapterQueueEntry;
    AdapterQueueEntry *adapterEntry;

    // Dequeue and free all entries from pendingQueue (offset 0x588)
    queuePtr = (unsigned int *)&pendingQueue;
    while (queuePtr != (unsigned int *)queuePtr[0]) {
        entry = (void *)queuePtr[0];  // Get first entry
        entryPtr = (unsigned int *)entry;

        // Get prev/next pointers (offsets 0x18 and 0x1c)
        prevPtr = (unsigned int *)entryPtr[0x18 / 4];
        nextPtr = (unsigned int *)entryPtr[0x1c / 4];

        // Update prev's next pointer
        if (queuePtr == prevPtr) {
            queuePtr[1] = (unsigned int)nextPtr;  // Update tail
        } else {
            prevPtr[0x1c / 4] = (unsigned int)nextPtr;
        }

        // Update next's prev pointer
        if (queuePtr == nextPtr) {
            queuePtr[0] = (unsigned int)prevPtr;  // Update head
        } else {
            nextPtr[0x18 / 4] = (unsigned int)prevPtr;
        }

        IOFree(entry, 0x20);
    }

    // Clean up all target structures (offset 0x480, count at offset 0x320)
    for (i = 0; i < numTargets; i++) {
        targetStruct = targetStructures[i];
        if (targetStruct != NULL) {
            _CleanupWaitingQ(targetStruct);
            IOFree(targetStruct, 0x9c);
        }
    }

    // Dequeue and free all IOBs from incomingQueue (offset 0x580)
    queuePtr = (unsigned int *)&incomingQueue;
    while (queuePtr != (unsigned int *)queuePtr[0]) {
        entry = (void *)queuePtr[0];  // Get first entry
        entryPtr = (unsigned int *)entry;

        // Get prev/next pointers (offsets 0xc0 and 0xc4)
        prevPtr = (unsigned int *)entryPtr[0xc0 / 4];
        nextPtr = (unsigned int *)entryPtr[0xc4 / 4];

        // Update prev's next pointer
        if (queuePtr == prevPtr) {
            queuePtr[1] = (unsigned int)nextPtr;  // Update tail
        } else {
            prevPtr[0xc4 / 4] = (unsigned int)nextPtr;
        }

        // Update next's prev pointer
        if (queuePtr == nextPtr) {
            queuePtr[0] = (unsigned int)prevPtr;  // Update head
        } else {
            nextPtr[0xc0 / 4] = (unsigned int)prevPtr;
        }

        // Save profile area before freeing (offset 0x2c8, size 0x1b4)
        memcpy(savedProfileArea, (void *)((unsigned int)self + 0x2c8), 0x1b4);

        // Free the IOB with profileBuffer parameters
        _freeOSMIOB(entry, profileBuffer[0], profileBuffer[1], profileBuffer[2],
                    profileBuffer[3], profileBuffer[4], profileBuffer[5], profileBuffer[6]);
    }

    // Remove this adapter from the global adapterQ[adapterIRQ]
    adapterEntry = (AdapterQueueEntry *)adapterQ[adapterIRQ].next;
    while (adapterEntry != (AdapterQueueEntry *)&adapterQ[adapterIRQ]) {
        if (adapterEntry->adapter == self) {
            // Found our entry - dequeue it manually
            prevPtr = (unsigned int *)adapterEntry->prev;
            nextPtr = (unsigned int *)adapterEntry->next;

            // Update prev's next pointer
            if ((void *)&adapterQ[adapterIRQ] == adapterEntry->prev) {
                prevPtr[1] = (unsigned int)nextPtr;
            } else {
                prevPtr[2] = (unsigned int)nextPtr;
            }

            // Update next's prev pointer
            if ((void *)&adapterQ[adapterIRQ] == adapterEntry->next) {
                ((unsigned int *)&adapterQ[adapterIRQ])[0] = (unsigned int)prevPtr;
            } else {
                nextPtr[1] = (unsigned int)prevPtr;
            }

            IOFree(adapterEntry, 0xc);
            break;
        }
        adapterEntry = (AdapterQueueEntry *)adapterEntry->next;
    }

    // Free working memory (offset 0x2a0, size at 0x2a4)
    if (workingMemory != NULL) {
        IOFree(workingMemory, workingMemorySize);
    }

    // Free incoming queue lock (offset 0x5a8)
    if (incomingQueueLock != nil) {
        [incomingQueueLock free];
    }

    // Call superclass free
    return [super free];
}

- (BOOL)findAdapter
{
    id devDesc;
    int (*getAdapterInfo)(int, int *, unsigned int *);
    unsigned int deviceID, mask;
    int flags;
    int index;
    int result;

    // Get device description
    devDesc = [self deviceDescription];

    // Read PCI device/vendor ID from config space offset 0, store at offset 0x248
    result = [devDesc configReadLong:0 value:&pciDeviceID];

    if (result == 0) {
        // Success - check adapter compatibility table
        // CHIM function at offset 0x4d0 = chimFunctionTable[1]
        getAdapterInfo = chimFunctionTable[1];

        // Loop through compatibility table (max 2985 entries = 0xbb9)
        for (index = 0;
             (deviceID = getAdapterInfo(index, &flags, &mask), deviceID != 0) && (index < 0xbb9);
             index++) {
            // Check if PCI device ID matches after masking and flags are clear
            if (((pciDeviceID & mask) == deviceID) && (flags == 0)) {
                return YES;  // Compatible adapter found
            }
        }
    } else {
        // Failed to read PCI config space
        IOLog("AdaptecU2SCSI: Cannot get PCI config space. Aborting.\n");
    }

    return NO;  // No compatible adapter found
}

- (BOOL)getWorkingMemoryForCHIM
{
    int (*getMemSize)(void *);
    int size;

    getMemSize = chimFunctionTable[2];

    bzero(stackBuffer, 1000);
    size = getMemSize(stackBuffer);
    chimWorkingMemory = (void *)size;

    return (size != 0);
}

- (BOOL)initAdapter
{
    id devDesc;
    int (*getConfig)(void *, void *, unsigned int);
    int (*setConfig)(void *, void *, unsigned int);
    unsigned int (*getMemSize)(void *, unsigned int);
    void *(*createHandle)(void *, void *, id, int);
    void (*setOSMRoutines)(void *, void *, int);
    int (*verifyAdapter)(void *);
    int (*initializeAdapter)(void *);
    void (*sizeSCB)(void *);
    void (*enableInterrupts)(void *);
    void (*getProfile)(void *, void *);
    int (*modifyProfile)(void *, void *);
    int result;

    // Get device description
    devDesc = [self deviceDescription];

    // Get CHIM function pointers from function table (offset 0x4cc)
    getConfig = chimFunctionTable[3];           // offset 0x4d8
    setConfig = chimFunctionTable[4];           // offset 0x4dc
    getMemSize = chimFunctionTable[5];          // offset 0x4e0
    createHandle = chimFunctionTable[6];        // offset 0x4e4
    setOSMRoutines = chimFunctionTable[7];      // offset 0x4e8
    verifyAdapter = chimFunctionTable[10];      // offset 0x4f4 (FIXED: was 11)
    initializeAdapter = chimFunctionTable[11];  // offset 0x4f8 (FIXED: was 12)
    sizeSCB = chimFunctionTable[15];            // offset 0x508 (FIXED: was 17)
    enableInterrupts = chimFunctionTable[16];   // offset 0x50c (FIXED: was 18)
    getProfile = chimFunctionTable[26];         // offset 0x534
    modifyProfile = chimFunctionTable[28];      // offset 0x53c (FIXED: was 27)

    // Get default configuration (uses stackBuffer at offset 0x244, NOT chimWorkingMemory)
    getConfig(stackBuffer, configBuffer, pciDeviceID);

    // Validate and clamp configuration values
    // configBuffer is at offset 0x25c, these access specific config fields:
    if (configBuffer[1] > 0x20) {               // offset 0x260: max targets = 32
        configBuffer[1] = 0x20;
    }
    if (configBuffer[5] != 2) {                 // offset 0x270: if not 2, set to 1
        configBuffer[5] = 1;
    }
    if (configBuffer[3] > 0x200) {              // offset 0x268: max value = 512
        configBuffer[3] = 0x200;
    }

    // Set configuration
    setConfig(stackBuffer, configBuffer, pciDeviceID);

    // Get required working memory size and allocate it
    workingMemorySize = getMemSize(stackBuffer, pciDeviceID);
    workingMemory = IOMalloc(workingMemorySize);
    bzero(workingMemory, workingMemorySize);

    // Create HIM adapter handle
    himHandle = createHandle(stackBuffer, workingMemory, self, 0);

    // Set OSM function pointers (0x7c = 124 bytes)
    setOSMRoutines(himHandle, &OSMRoutines, 0x7c);

    // Verify adapter compatibility
    result = verifyAdapter(himHandle);
    if (result == 1) {
        IOLog("AdaptecU2SCSI: HIM Failure when verifying adapter.\n");
        return NO;
    }
    if (result != 0) {
        IOLog("AdaptecU2SCSI: Adapter not supported.\n");
        return NO;
    }

    IOLog("AdaptecU2SCSI: Adapter verified by HIM.\n");

    // Allocate adapter memory for DMA operations
    if (![self allocateAdapterMemory]) {
        IOLog("AdaptecU2SCSI: Cannot allocate adapter memory.\n");
        return NO;
    }

    // Get profile into profileBuffer (offset 0x2ac)
    getProfile(himHandle, profileBuffer);

    // Set all profile flags to 1 (offset 0x3bc, size 0x80 = 128 bytes)
    memset(profileFlags, 1, 0x80);

    // Modify profile with new settings
    result = modifyProfile(himHandle, profileBuffer);
    if (result == 1) {
        IOLog("AdaptecU2SCSI: Failed to modifiy adapter profile.\n");
        return NO;
    }
    if (result == 2) {
        IOLog("AdaptecU2SCSI: Adapter not idle when modifying profile.\n");
        return NO;
    }
    if (result == 7) {
        IOLog("AdaptecU2SCSI: Illegal change made to adapter profile.\n");
        return NO;
    }

    // Copy pointer from offset 0x334 to 0x47c (copySource to copyDest)
    copyDest = copySource;

    // Size the SCB (SCSI Control Block)
    sizeSCB(himHandle);

    // Initialize the adapter
    result = initializeAdapter(himHandle);
    if (result != 0) {
        IOLog("AdaptecU2SCSI: HIMInitialize failed.\n");
        return NO;
    }

    // Log IRQ being used
    IOLog("AdaptecU2SCSI: Using IRQ: %d\n", [devDesc interrupt]);

    // Create pool of OSM IOBs
    [self createOSMIOBPool];

    // Enable interrupts
    enableInterrupts(himHandle);

    return YES;
}

- (BOOL)allocateAdapterMemory
{
    int (*getMemReq)(void *, void *, unsigned int, int, int *, int *, void *, unsigned int *);
    int (*setMemPtr)(void *, int, int, void *, int);
    int index = 0;
    int needsContiguous, size;
    unsigned int alignment, offset;
    void *memory, *aligned;
    int result;

    getMemReq = chimFunctionTable[8];
    setMemPtr = chimFunctionTable[9];

    while (1) {
        // Query CHIM for next memory segment requirements
        // Uses stackBuffer (offset 0x244), himHandle (0x2a8), pciDeviceID (0x248)
        result = getMemReq(stackBuffer, himHandle, pciDeviceID, index,
                          &needsContiguous, &size, &alignment, &offset);

        if (result == 0) {
            return YES;
        }

        // Check if allocation will exceed page size
        if ((size + offset) > page_size) {
            // Cannot allocate contiguous memory larger than a page
            if (needsContiguous) {
                IOLog("AdaptecU2SCSI: Cannot allocate locked memory.\n");
                return NO;
            }
            // Use non-contiguous memory for large allocations
            memory = IOMalloc(size + offset);
        } else {
            // Allocation fits in a page
            if (needsContiguous) {
                // Allocate DMA-capable contiguous memory
                memory = AdptMallocContiguous(size + offset);
            } else {
                // Allocate normal kernel memory
                memory = IOMalloc(size + offset);
            }
        }

        if (memory == NULL) {
            IOLog("AdaptecU2SCSI: Memory allocation failed.\n");
            return NO;
        }

        bzero(memory, size + offset);
        aligned = (void *)(((unsigned int)memory + offset) & ~offset);

        result = setMemPtr(himHandle, index, needsContiguous, aligned, size);
        if (result != 0) {
            IOLog("AdaptecU2SCSI: Could not set memory pointer.\n");
            return NO;
        }

        index++;
    }
}

- (void)createOSMIOBPool
{
    int i;
    void *iob;
    unsigned int *iobPtr;
    unsigned int *queuePtr;
    unsigned int *tailPtr;

    // Clear the free IOB counter (offset 0x574)
    freeIOBCount = 0;

    // Allocate and enqueue 16 IOBs
    for (i = 0; i < 16; i++) {
        // Allocate IOB using profile buffer parameters (offsets 0x2ac-0x2cb)
        iob = _allocOSMIOB(profileBuffer[0], profileBuffer[1], profileBuffer[2],
                          profileBuffer[3], profileBuffer[4], profileBuffer[5],
                          profileBuffer[6], profileBuffer[7]);

        if (iob == NULL) {
            IOLog("AdaptecU2SCSI::createOSMIOBPool: Failed to allocate IOB %d\n", i);
            continue;
        }

        // Manual circular doubly-linked list enqueue
        // Queue structure is at offset 0x580 (incomingQueue)
        iobPtr = (unsigned int *)iob;
        queuePtr = (unsigned int *)&incomingQueue;

        // Get current tail (offset 0x4 from queue head = 0x584)
        tailPtr = (unsigned int *)queuePtr[1];

        // Check if queue is empty (tail points to queue head)
        if (tailPtr == queuePtr) {
            // Empty queue - set head to point to new IOB
            queuePtr[0] = (unsigned int)iob;
        } else {
            // Non-empty queue - link tail's next to new IOB
            // IOB next pointer is at offset 0xc4 (index 0x31)
            tailPtr[0x31] = (unsigned int)iob;
        }

        // Set new IOB's prev pointer (offset 0xc0, index 0x30) to current tail
        iobPtr[0x30] = (unsigned int)tailPtr;

        // Set new IOB's next pointer (offset 0xc4, index 0x31) to queue head
        iobPtr[0x31] = (unsigned int)queuePtr;

        // Update queue tail to point to new IOB (offset 0x584)
        queuePtr[1] = (unsigned int)iob;

        // Increment free IOB count
        freeIOBCount++;
    }

    IOLog("AdaptecU2SCSI::createOSMIOBPool: Created pool with %u IOBs\n", freeIOBCount);
}

- (BOOL)scanAdapter
{
    unsigned int busResetRequest[6];  // Bus reset request (24 bytes)
    int busResetStatus;                // Status at offset 0x18 from busResetRequest
    unsigned int targetRequest[4];     // Target init request
    unsigned char *targetLunPtr;       // Pointer to target/LUN array
    unsigned char targetLun[2];        // Target and LUN bytes
    int result;
    unsigned int targetIndex;

    // Issue bus reset command (type 2)
    busResetRequest[0] = 2;
    result = [self executeRequest:busResetRequest];

    if (result != 0) {
        // Bus reset failed
        return NO;
    }

    // Bus reset succeeded - scan all targets
    if (numTargets != 0) {
        for (targetIndex = 0; targetIndex < numTargets; targetIndex++) {
            // Build target/LUN array
            targetLun[0] = targetIndex;  // Target ID
            targetLun[1] = 0;            // LUN 0

            // Build target initialization request (type 1)
            // Request structure:
            //   offset 0x00: request type (1)
            //   offset 0x04-0x0c: reserved
            //   offset 0x10: pointer to target/LUN array
            //   offset 0x14: condition lock (set by executeRequest)
            //   offset 0x18: status (set by I/O thread)
            targetRequest[0] = 1;
            targetRequest[1] = 0;  // Reserved
            targetRequest[2] = 0;  // Reserved
            targetRequest[3] = 0;  // Reserved
            targetLunPtr = targetLun;
            *(unsigned char **)(targetRequest + 4) = targetLunPtr;  // offset 0x10

            // Execute target initialization
            result = [self executeRequest:targetRequest];
            if (result != 0) {
                // Target init failed
                return NO;
            }
        }
    }

    // All targets scanned - check final status of bus reset
    // The I/O thread stores completion status at offset 0x18
    busResetStatus = *(int *)((char *)busResetRequest + 0x18);

    // Return success only if bus reset status is 0
    return (busResetStatus == 0);
}

- (BOOL)registerHandlerForIRQ:(unsigned int)irq
{
    typedef struct {
        id adapter;
        void *next;
        void *prev;
    } AdapterQueueEntry;

    AdapterQueueEntry *entry;
    AdapterQueueEntry **queueTail;
    unsigned int intNum;

    // Store IRQ number at offset 0x5a4
    adapterIRQ = irq;

    // Check if queue for this IRQ is empty
    // Queue is empty if head pointer equals the queue head address
    if ((void *)&adapterQ[irq] == adapterQ[irq].next) {
        // First adapter on this IRQ - register interrupt handler
        intNum = pmac_int_to_number();
        pmac_register_int(intNum, 0x18, AU2Handler, self);
    }

    // Walk the queue to check if this adapter is already registered
    entry = (AdapterQueueEntry *)adapterQ[irq].next;
    while (entry != (AdapterQueueEntry *)&adapterQ[irq]) {
        if (entry->adapter == self) {
            // Already registered
            return YES;
        }
        entry = (AdapterQueueEntry *)entry->next;
    }

    // Not found - allocate new queue entry
    entry = (AdapterQueueEntry *)IOMalloc(0xc);
    entry->adapter = self;

    // Manually enqueue at tail
    // adapterQ[irq].prev is the tail pointer (offset +4 from queue head)
    queueTail = (AdapterQueueEntry **)&adapterQ[irq].prev;

    // Check if queue is empty
    if ((void *)&adapterQ[irq] == *queueTail) {
        // Empty queue - set head to new entry
        adapterQ[irq].next = (queue_entry_t)entry;
    } else {
        // Non-empty - link tail's next to new entry
        (*queueTail)->next = entry;
    }

    // Set new entry's prev to current tail
    entry->prev = *queueTail;

    // Set new entry's next to queue head
    entry->next = (void *)&adapterQ[irq];

    // Update tail to point to new entry
    *queueTail = entry;

    return YES;
}

- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiReq
{
    void *request;
    int result;

    request = stackBuffer;
    *(int *)request = 0;
    *(IOSCSIRequest **)(request + 8) = scsiReq;

    result = [self executeRequest:request];
    return result;
}

- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiReq
                       buffer:(void *)buffer
                       client:(vm_task_t)client
{
    unsigned char opcode;
    unsigned char *cdb;
    unsigned char additionalLengthByte;
    unsigned int cdbLength;
    unsigned int lengthField;
    sc_status_t status = SR_IOST_GOOD;
    void *request;
    int result;

    // Check if LUN is non-zero (offset 0x1 in IOSCSIRequest)
    if (scsiReq->lun != 0) {
        status = SR_IOST_CMDREJ;
        goto done;
    }

    // Check if target structure exists at offset 0x480
    if (targetStructures[scsiReq->target] == NULL) {
        unsigned char targetLun[2];
        void *initReq;
        int initResult;
        int initStatus;

        // Initialize target with request type 1
        targetLun[0] = scsiReq->target;
        targetLun[1] = 0;

        initReq = stackBuffer;
        *(int *)initReq = 1;                     // Type 1: probe target
        *(int *)(initReq + 4) = 0;               // Reserved
        *(int *)(initReq + 8) = 0;               // Reserved
        *(int *)(initReq + 0xc) = 0;             // Reserved
        *(void **)(initReq + 0x10) = targetLun;  // Target/LUN array pointer

        initResult = [self executeRequest:initReq];
        initStatus = *(int *)(initReq + 0x14);

        if (initResult != 0 || initStatus != 0) {
            status = SR_IOST_CMDREJ;
            goto done;
        }
    }

    // Extract opcode from CDB byte 0 (offset 0x4 in IOSCSIRequest)
    cdb = scsiReq->cdb;
    opcode = cdb[0] & 0xe0;

    // Determine CDB length based on command group
    if (opcode == 0x00) {
        // Group 0 commands (6-byte CDBs)
        additionalLengthByte = cdb[5];  // offset 0x9 in IOSCSIRequest
        cdbLength = 6;
    } else if (opcode == 0x20 || opcode == 0x40) {
        // Group 1/2 commands (10-byte CDBs)
        additionalLengthByte = cdb[9];  // offset 0xd in IOSCSIRequest
        cdbLength = 10;
    } else if (opcode == 0xa0) {
        // Group 5 commands (12-byte CDBs)
        additionalLengthByte = cdb[11];  // offset 0xf in IOSCSIRequest
        cdbLength = 12;
    } else if (opcode == 0xc0) {
        // Group 6 vendor-specific commands
        // Use cdbLength field at offset 0x1c in IOSCSIRequest
        lengthField = scsiReq->cdbLength;
        cdbLength = 6;  // Default to 6 bytes
        if ((lengthField & 0xf) != 0) {
            cdbLength = lengthField & 0xf;
        }
        additionalLengthByte = 0;
    } else if (opcode == 0xe0) {
        // Group 7 vendor-specific commands
        // Use cdbLength field at offset 0x1c in IOSCSIRequest
        lengthField = scsiReq->cdbLength;
        cdbLength = 10;  // Default to 10 bytes
        if ((lengthField & 0xf) != 0) {
            cdbLength = lengthField & 0xf;
        }
        additionalLengthByte = 0;
    } else {
        // Invalid opcode
        status = SR_IOST_INVALID;
        goto done;
    }

    // Build internal request structure in stackBuffer
    // Structure layout:
    //   offset 0x00: request type (0 = SCSI command)
    //   offset 0x04: CDB length
    //   offset 0x08: reserved (0)
    //   offset 0x0c: reserved (0)
    //   offset 0x10: IOSCSIRequest pointer
    //   offset 0x14: buffer pointer
    //   offset 0x18: client task
    request = stackBuffer;
    *(int *)request = 0;                        // Request type 0
    *(unsigned int *)(request + 4) = cdbLength; // CDB length
    *(int *)(request + 8) = 0;                  // Reserved
    *(int *)(request + 0xc) = 0;                // Reserved
    *(IOSCSIRequest **)(request + 0x10) = scsiReq;  // SCSI request
    *(void **)(request + 0x14) = buffer;        // Buffer pointer
    *(vm_task_t *)(request + 0x18) = client;    // Client task

    // Validate additional length byte and execute request
    // For standard groups (0, 1, 2, 5), check that lower 2 bits are clear
    if ((additionalLengthByte & 3) == 0) {
        result = [self executeRequest:request];
        if (result == 0) {
            goto done;
        }
    }

    // Request failed or validation failed
    status = SR_IOST_INVALID;

done:
    // Store status in IOSCSIRequest at offset 0x20
    scsiReq->driverStatus = status;
    return status;
}

- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiReq
           ioMemoryDescriptor:(IOMemoryDescriptor *)ioMemoryDescriptor
{
    return [self executeRequest:scsiReq buffer:ioMemoryDescriptor client:0xffffffff];
}

// Private internal executeRequest that takes void* to internal request structure
// This is the core method that enqueues requests and wakes the I/O thread
- (int)executeRequest:(void *)request
{
    msg_header_t msg;
    id conditionLock;
    unsigned int *requestPtr = (unsigned int *)request;
    unsigned int *queuePtr;
    unsigned int *tailPtr;
    msg_return_t msgResult;
    int result = 0;

    // Set up Mach message to wake I/O thread
    msg.msg_simple = 1;
    msg.msg_size = 0x18;  // 24 bytes
    msg.msg_type = 0;
    msg.msg_local_port = 0;
    msg.msg_remote_port = 0;  // Will be set to kernelInterruptPort below
    msg.msg_id = 0x00232324;  // Message ID

    // Set condition value at offset 0x18 (request timeout/completion flag)
    requestPtr[0x18 / 4] = 100;

    // Create NXConditionLock for request completion signaling
    conditionLock = [objc_getClass("NXConditionLock") alloc];
    conditionLock = (*condLockInitWith)(conditionLock, @selector(initWith:), 0);

    // Store condition lock in request structure at offset 0x14
    requestPtr[0x14 / 4] = (unsigned int)conditionLock;

    // Lock the incoming queue (offset 0x5a8)
    (*lockMethod)(incomingQueueLock, @selector(lock));

    // Manually enqueue request onto disconnectedQueue (offset 0x590)
    // Queue head is at 0x590, tail at 0x594
    queuePtr = (unsigned int *)&disconnectedQueue;
    tailPtr = (unsigned int *)queuePtr[1];  // Get tail (offset 0x594)

    // Check if queue is empty (tail points to queue head)
    if (tailPtr == queuePtr) {
        // Empty queue - set head to point to new request
        queuePtr[0] = (unsigned int)request;
    } else {
        // Non-empty queue - link tail's next to new request
        // Request next pointer is at offset 0x24
        tailPtr[0x24 / 4] = (unsigned int)request;
    }

    // Set request's prev pointer (offset 0x28) to current tail
    requestPtr[0x28 / 4] = (unsigned int)tailPtr;

    // Set request's next pointer (offset 0x24) to queue head
    requestPtr[0x24 / 4] = (unsigned int)queuePtr;

    // Update queue tail to point to new request
    queuePtr[1] = (unsigned int)request;

    // Unlock the queue
    (*unlockMethod)(incomingQueueLock, @selector(unlock));

    // Set message remote port to kernel interrupt port (offset 0x5ac)
    msg.msg_remote_port = kernelInterruptPort;

    // Send message to wake up I/O thread
    msgResult = msg_send_from_kernel(&msg, MSG_OPTION_NONE, 0);

    if (msgResult == SEND_SUCCESS) {
        // Wait for I/O thread to complete the request
        // Thread will unlock condition lock with value 1 when done
        (*condLockLockWhen)(conditionLock, @selector(lockWhen:), 1);
    } else {
        // Message send failed
        result = SR_IOST_IOTO;  // 0xfffffd41 = -703
        IOLog("%s: msg_send_from_kernel() returned %d\n", [self name], msgResult);
    }

    // Free the condition lock
    (*condLockFree)(conditionLock, @selector(free));

    return result;
}

- (sc_status_t)resetSCSIBus
{
    unsigned int requestBuffer[6];  // 24 bytes for request structure
    int status;                      // Status returned at offset 0x18
    int result;

    // Build bus reset request (type 2)
    requestBuffer[0] = 2;

    // Execute bus reset command
    result = [self executeRequest:requestBuffer];

    if (result == 0) {
        // Success - return status from offset 0x18 (requestBuffer + 0x18)
        status = *(int *)((char *)requestBuffer + 0x18);
        return status;
    }

    // Request failed - return invalid status (7)
    return SR_IOST_INVALID;
}

- (int)numberOfTargets
{
    // Return number of targets from offset 0x320 (800 decimal)
    return numTargets;
}

- (unsigned int)maxTransfer
{
    // Return maximum transfer size: 510 pages (0x1fe)
    // At 4KB page size, this is approximately 2MB
    return page_size * 0x1fe;
}

- (unsigned int)numQueueSamples
{
    // Return number of queue samples from offset 0x578
    // This field is dual-purpose: chimWorkingMemory during init, numSamples after
    return (unsigned int)chimWorkingMemory;
}

- (unsigned int)sumQueueLengths
{
    // Return sum of queue lengths statistic from offset 0x59c
    return sumQueueLengths;
}

- (unsigned int)maxQueueLength
{
    // Return maximum queue length statistic from offset 0x598
    return maxQueueLen;
}

- (void)resetStats
{
    // Clear sum of queue lengths statistic (offset 0x59c)
    sumQueueLengths = 0;

    // Clear maximum queue length statistic (offset 0x598)
    maxQueueLen = 0;
}


- (BOOL)getWorkingMemoryForCHIM
{
    int (*getMemSize)(void *);
    int size;

    getMemSize = chimFunctionTable[2];

    bzero(stackBuffer, 1000);
    size = getMemSize(stackBuffer);
    chimWorkingMemory = (void *)size;

    return (size != 0);
}

- (BOOL)initAdapter
{
    id devDesc;
    int (*getConfig)(void *, void *, unsigned int);
    int (*setConfig)(void *, void *, unsigned int);
    unsigned int (*getMemSize)(void *, unsigned int);
    void *(*createHandle)(void *, void *, id, int);
    void (*setOSMRoutines)(void *, void *, int);
    int (*verifyAdapter)(void *);
    int (*initializeAdapter)(void *);
    void (*sizeSCB)(void *);
    void (*enableInterrupts)(void *);
    void (*getProfile)(void *, void *);
    int (*modifyProfile)(void *, void *);
    int result;

    // Get device description
    devDesc = [self deviceDescription];

    // Get CHIM function pointers from function table (offset 0x4cc)
    getConfig = chimFunctionTable[3];           // offset 0x4d8
    setConfig = chimFunctionTable[4];           // offset 0x4dc
    getMemSize = chimFunctionTable[5];          // offset 0x4e0
    createHandle = chimFunctionTable[6];        // offset 0x4e4
    setOSMRoutines = chimFunctionTable[7];      // offset 0x4e8
    verifyAdapter = chimFunctionTable[10];      // offset 0x4f4 (FIXED: was 11)
    initializeAdapter = chimFunctionTable[11];  // offset 0x4f8 (FIXED: was 12)
    sizeSCB = chimFunctionTable[15];            // offset 0x508 (FIXED: was 17)
    enableInterrupts = chimFunctionTable[16];   // offset 0x50c (FIXED: was 18)
    getProfile = chimFunctionTable[26];         // offset 0x534
    modifyProfile = chimFunctionTable[28];      // offset 0x53c (FIXED: was 27)

    // Get default configuration (uses stackBuffer at offset 0x244, NOT chimWorkingMemory)
    getConfig(stackBuffer, configBuffer, pciDeviceID);

    // Validate and clamp configuration values
    // configBuffer is at offset 0x25c, these access specific config fields:
    if (configBuffer[1] > 0x20) {               // offset 0x260: max targets = 32
        configBuffer[1] = 0x20;
    }
    if (configBuffer[5] != 2) {                 // offset 0x270: if not 2, set to 1
        configBuffer[5] = 1;
    }
    if (configBuffer[3] > 0x200) {              // offset 0x268: max value = 512
        configBuffer[3] = 0x200;
    }

    // Set configuration
    setConfig(stackBuffer, configBuffer, pciDeviceID);

    // Get required working memory size and allocate it
    workingMemorySize = getMemSize(stackBuffer, pciDeviceID);
    workingMemory = IOMalloc(workingMemorySize);
    bzero(workingMemory, workingMemorySize);

    // Create HIM adapter handle
    himHandle = createHandle(stackBuffer, workingMemory, self, 0);

    // Set OSM function pointers (0x7c = 124 bytes)
    setOSMRoutines(himHandle, &OSMRoutines, 0x7c);

    // Verify adapter compatibility
    result = verifyAdapter(himHandle);
    if (result == 1) {
        IOLog("AdaptecU2SCSI: HIM Failure when verifying adapter.\n");
        return NO;
    }
    if (result != 0) {
        IOLog("AdaptecU2SCSI: Adapter not supported.\n");
        return NO;
    }

    IOLog("AdaptecU2SCSI: Adapter verified by HIM.\n");

    // Allocate adapter memory for DMA operations
    if (![self allocateAdapterMemory]) {
        IOLog("AdaptecU2SCSI: Cannot allocate adapter memory.\n");
        return NO;
    }

    // Get profile into profileBuffer (offset 0x2ac)
    getProfile(himHandle, profileBuffer);

    // Set all profile flags to 1 (offset 0x3bc, size 0x80 = 128 bytes)
    memset(profileFlags, 1, 0x80);

    // Modify profile with new settings
    result = modifyProfile(himHandle, profileBuffer);
    if (result == 1) {
        IOLog("AdaptecU2SCSI: Failed to modifiy adapter profile.\n");
        return NO;
    }
    if (result == 2) {
        IOLog("AdaptecU2SCSI: Adapter not idle when modifying profile.\n");
        return NO;
    }
    if (result == 7) {
        IOLog("AdaptecU2SCSI: Illegal change made to adapter profile.\n");
        return NO;
    }

    // Copy pointer from offset 0x334 to 0x47c (copySource to copyDest)
    copyDest = copySource;

    // Size the SCB (SCSI Control Block)
    sizeSCB(himHandle);

    // Initialize the adapter
    result = initializeAdapter(himHandle);
    if (result != 0) {
        IOLog("AdaptecU2SCSI: HIMInitialize failed.\n");
        return NO;
    }

    // Log IRQ being used
    IOLog("AdaptecU2SCSI: Using IRQ: %d\n", [devDesc interrupt]);

    // Create pool of OSM IOBs
    [self createOSMIOBPool];

    // Enable interrupts
    enableInterrupts(himHandle);

    return YES;
}

- (BOOL)allocateAdapterMemory
{
    int (*getMemReq)(void *, void *, unsigned int, int, int *, int *, void *, unsigned int *);
    int (*setMemPtr)(void *, int, int, void *, int);
    int index = 0;
    int needsContiguous, size;
    unsigned int alignment, offset;
    void *memory, *aligned;
    int result;

    getMemReq = chimFunctionTable[8];
    setMemPtr = chimFunctionTable[9];

    while (1) {
        // Query CHIM for next memory segment requirements
        // Uses stackBuffer (offset 0x244), himHandle (0x2a8), pciDeviceID (0x248)
        result = getMemReq(stackBuffer, himHandle, pciDeviceID, index,
                          &needsContiguous, &size, &alignment, &offset);

        if (result == 0) {
            return YES;
        }

        // Check if allocation will exceed page size
        if ((size + offset) > page_size) {
            // Cannot allocate contiguous memory larger than a page
            if (needsContiguous) {
                IOLog("AdaptecU2SCSI: Cannot allocate locked memory.\n");
                return NO;
            }
            // Use non-contiguous memory for large allocations
            memory = IOMalloc(size + offset);
        } else {
            // Allocation fits in a page
            if (needsContiguous) {
                // Allocate DMA-capable contiguous memory
                memory = AdptMallocContiguous(size + offset);
            } else {
                // Allocate normal kernel memory
                memory = IOMalloc(size + offset);
            }
        }

        if (memory == NULL) {
            IOLog("AdaptecU2SCSI: Memory allocation failed.\n");
            return NO;
        }

        bzero(memory, size + offset);
        aligned = (void *)(((unsigned int)memory + offset) & ~offset);

        result = setMemPtr(himHandle, index, needsContiguous, aligned, size);
        if (result != 0) {
            IOLog("AdaptecU2SCSI: Could not set memory pointer.\n");
            return NO;
        }

        index++;
    }
}

- (void)createOSMIOBPool
{
    int i;
    void *iob;
    unsigned int *iobPtr;
    unsigned int *queuePtr;
    unsigned int *tailPtr;

    // Clear the free IOB counter (offset 0x574)
    freeIOBCount = 0;

    // Allocate and enqueue 16 IOBs
    for (i = 0; i < 16; i++) {
        // Allocate IOB using profile buffer parameters (offsets 0x2ac-0x2cb)
        iob = _allocOSMIOB(profileBuffer[0], profileBuffer[1], profileBuffer[2],
                          profileBuffer[3], profileBuffer[4], profileBuffer[5],
                          profileBuffer[6], profileBuffer[7]);

        if (iob == NULL) {
            IOLog("AdaptecU2SCSI::createOSMIOBPool: Failed to allocate IOB %d\n", i);
            continue;
        }

        // Manual circular doubly-linked list enqueue
        // Queue structure is at offset 0x580 (incomingQueue)
        iobPtr = (unsigned int *)iob;
        queuePtr = (unsigned int *)&incomingQueue;

        // Get current tail (offset 0x4 from queue head = 0x584)
        tailPtr = (unsigned int *)queuePtr[1];

        // Check if queue is empty (tail points to queue head)
        if (tailPtr == queuePtr) {
            // Empty queue - set head to point to new IOB
            queuePtr[0] = (unsigned int)iob;
        } else {
            // Non-empty queue - link tail's next to new IOB
            // IOB next pointer is at offset 0xc4 (index 0x31)
            tailPtr[0x31] = (unsigned int)iob;
        }

        // Set new IOB's prev pointer (offset 0xc0, index 0x30) to current tail
        iobPtr[0x30] = (unsigned int)tailPtr;

        // Set new IOB's next pointer (offset 0xc4, index 0x31) to queue head
        iobPtr[0x31] = (unsigned int)queuePtr;

        // Update queue tail to point to new IOB (offset 0x584)
        queuePtr[1] = (unsigned int)iob;

        // Increment free IOB count
        freeIOBCount++;
    }

    IOLog("AdaptecU2SCSI::createOSMIOBPool: Created pool with %u IOBs\n", freeIOBCount);
}

- (BOOL)scanAdapter
{
    unsigned int busResetRequest[6];  // Bus reset request (24 bytes)
    int busResetStatus;                // Status at offset 0x18 from busResetRequest
    unsigned int targetRequest[4];     // Target init request
    unsigned char *targetLunPtr;       // Pointer to target/LUN array
    unsigned char targetLun[2];        // Target and LUN bytes
    int result;
    unsigned int targetIndex;

    // Issue bus reset command (type 2)
    busResetRequest[0] = 2;
    result = [self executeRequest:busResetRequest];

    if (result != 0) {
        // Bus reset failed
        return NO;
    }

    // Bus reset succeeded - scan all targets
    if (numTargets != 0) {
        for (targetIndex = 0; targetIndex < numTargets; targetIndex++) {
            // Build target/LUN array
            targetLun[0] = targetIndex;  // Target ID
            targetLun[1] = 0;            // LUN 0

            // Build target initialization request (type 1)
            // Request structure:
            //   offset 0x00: request type (1)
            //   offset 0x04-0x0c: reserved
            //   offset 0x10: pointer to target/LUN array
            //   offset 0x14: condition lock (set by executeRequest)
            //   offset 0x18: status (set by I/O thread)
            targetRequest[0] = 1;
            targetRequest[1] = 0;  // Reserved
            targetRequest[2] = 0;  // Reserved
            targetRequest[3] = 0;  // Reserved
            targetLunPtr = targetLun;
            *(unsigned char **)(targetRequest + 4) = targetLunPtr;  // offset 0x10

            // Execute target initialization
            result = [self executeRequest:targetRequest];
            if (result != 0) {
                // Target init failed
                return NO;
            }
        }
    }

    // All targets scanned - check final status of bus reset
    // The I/O thread stores completion status at offset 0x18
    busResetStatus = *(int *)((char *)busResetRequest + 0x18);

    // Return success only if bus reset status is 0
    return (busResetStatus == 0);
}

- (BOOL)registerHandlerForIRQ:(unsigned int)irq
{
    typedef struct {
        id adapter;
        void *next;
        void *prev;
    } AdapterQueueEntry;

    AdapterQueueEntry *entry;
    AdapterQueueEntry **queueTail;
    unsigned int intNum;

    // Store IRQ number at offset 0x5a4
    adapterIRQ = irq;

    // Check if queue for this IRQ is empty
    // Queue is empty if head pointer equals the queue head address
    if ((void *)&adapterQ[irq] == adapterQ[irq].next) {
        // First adapter on this IRQ - register interrupt handler
        intNum = pmac_int_to_number();
        pmac_register_int(intNum, 0x18, AU2Handler, self);
    }

    // Walk the queue to check if this adapter is already registered
    entry = (AdapterQueueEntry *)adapterQ[irq].next;
    while (entry != (AdapterQueueEntry *)&adapterQ[irq]) {
        if (entry->adapter == self) {
            // Already registered
            return YES;
        }
        entry = (AdapterQueueEntry *)entry->next;
    }

    // Not found - allocate new queue entry
    entry = (AdapterQueueEntry *)IOMalloc(0xc);
    entry->adapter = self;

    // Manually enqueue at tail
    // adapterQ[irq].prev is the tail pointer (offset +4 from queue head)
    queueTail = (AdapterQueueEntry **)&adapterQ[irq].prev;

    // Check if queue is empty
    if ((void *)&adapterQ[irq] == *queueTail) {
        // Empty queue - set head to new entry
        adapterQ[irq].next = (queue_entry_t)entry;
    } else {
        // Non-empty - link tail's next to new entry
        (*queueTail)->next = entry;
    }

    // Set new entry's prev to current tail
    entry->prev = *queueTail;

    // Set new entry's next to queue head
    entry->next = (void *)&adapterQ[irq];

    // Update tail to point to new entry
    *queueTail = entry;

    return YES;
}

- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiReq
{
    void *request;
    int result;

    request = stackBuffer;
    *(int *)request = 0;
    *(IOSCSIRequest **)(request + 8) = scsiReq;

    result = [self executeRequest:request];
    return result;
}

- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiReq
                       buffer:(void *)buffer
                       client:(vm_task_t)client
{
    unsigned char opcode;
    unsigned char *cdb;
    unsigned char additionalLengthByte;
    unsigned int cdbLength;
    unsigned int lengthField;
    sc_status_t status = SR_IOST_GOOD;
    void *request;
    int result;

    // Check if LUN is non-zero (offset 0x1 in IOSCSIRequest)
    if (scsiReq->lun != 0) {
        status = SR_IOST_CMDREJ;
        goto done;
    }

    // Check if target structure exists at offset 0x480
    if (targetStructures[scsiReq->target] == NULL) {
        unsigned char targetLun[2];
        void *initReq;
        int initResult;
        int initStatus;

        // Initialize target with request type 1
        targetLun[0] = scsiReq->target;
        targetLun[1] = 0;

        initReq = stackBuffer;
        *(int *)initReq = 1;                     // Type 1: probe target
        *(int *)(initReq + 4) = 0;               // Reserved
        *(int *)(initReq + 8) = 0;               // Reserved
        *(int *)(initReq + 0xc) = 0;             // Reserved
        *(void **)(initReq + 0x10) = targetLun;  // Target/LUN array pointer

        initResult = [self executeRequest:initReq];
        initStatus = *(int *)(initReq + 0x14);

        if (initResult != 0 || initStatus != 0) {
            status = SR_IOST_CMDREJ;
            goto done;
        }
    }

    // Extract opcode from CDB byte 0 (offset 0x4 in IOSCSIRequest)
    cdb = scsiReq->cdb;
    opcode = cdb[0] & 0xe0;

    // Determine CDB length based on command group
    if (opcode == 0x00) {
        // Group 0 commands (6-byte CDBs)
        additionalLengthByte = cdb[5];  // offset 0x9 in IOSCSIRequest
        cdbLength = 6;
    } else if (opcode == 0x20 || opcode == 0x40) {
        // Group 1/2 commands (10-byte CDBs)
        additionalLengthByte = cdb[9];  // offset 0xd in IOSCSIRequest
        cdbLength = 10;
    } else if (opcode == 0xa0) {
        // Group 5 commands (12-byte CDBs)
        additionalLengthByte = cdb[11];  // offset 0xf in IOSCSIRequest
        cdbLength = 12;
    } else if (opcode == 0xc0) {
        // Group 6 vendor-specific commands
        // Use cdbLength field at offset 0x1c in IOSCSIRequest
        lengthField = scsiReq->cdbLength;
        cdbLength = 6;  // Default to 6 bytes
        if ((lengthField & 0xf) != 0) {
            cdbLength = lengthField & 0xf;
        }
        additionalLengthByte = 0;
    } else if (opcode == 0xe0) {
        // Group 7 vendor-specific commands
        // Use cdbLength field at offset 0x1c in IOSCSIRequest
        lengthField = scsiReq->cdbLength;
        cdbLength = 10;  // Default to 10 bytes
        if ((lengthField & 0xf) != 0) {
            cdbLength = lengthField & 0xf;
        }
        additionalLengthByte = 0;
    } else {
        // Invalid opcode
        status = SR_IOST_INVALID;
        goto done;
    }

    // Build internal request structure in stackBuffer
    // Structure layout:
    //   offset 0x00: request type (0 = SCSI command)
    //   offset 0x04: CDB length
    //   offset 0x08: reserved (0)
    //   offset 0x0c: reserved (0)
    //   offset 0x10: IOSCSIRequest pointer
    //   offset 0x14: buffer pointer
    //   offset 0x18: client task
    request = stackBuffer;
    *(int *)request = 0;                        // Request type 0
    *(unsigned int *)(request + 4) = cdbLength; // CDB length
    *(int *)(request + 8) = 0;                  // Reserved
    *(int *)(request + 0xc) = 0;                // Reserved
    *(IOSCSIRequest **)(request + 0x10) = scsiReq;  // SCSI request
    *(void **)(request + 0x14) = buffer;        // Buffer pointer
    *(vm_task_t *)(request + 0x18) = client;    // Client task

    // Validate additional length byte and execute request
    // For standard groups (0, 1, 2, 5), check that lower 2 bits are clear
    if ((additionalLengthByte & 3) == 0) {
        result = [self executeRequest:request];
        if (result == 0) {
            goto done;
        }
    }

    // Request failed or validation failed
    status = SR_IOST_INVALID;

done:
    // Store status in IOSCSIRequest at offset 0x20
    scsiReq->driverStatus = status;
    return status;
}

- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiReq
           ioMemoryDescriptor:(IOMemoryDescriptor *)ioMemoryDescriptor
{
    return [self executeRequest:scsiReq buffer:ioMemoryDescriptor client:0xffffffff];
}

// Private internal executeRequest that takes void* to internal request structure
// This is the core method that enqueues requests and wakes the I/O thread
- (int)executeRequest:(void *)request
{
    msg_header_t msg;
    id conditionLock;
    unsigned int *requestPtr = (unsigned int *)request;
    unsigned int *queuePtr;
    unsigned int *tailPtr;
    msg_return_t msgResult;
    int result = 0;

    // Set up Mach message to wake I/O thread
    msg.msg_simple = 1;
    msg.msg_size = 0x18;  // 24 bytes
    msg.msg_type = 0;
    msg.msg_local_port = 0;
    msg.msg_remote_port = 0;  // Will be set to kernelInterruptPort below
    msg.msg_id = 0x00232324;  // Message ID

    // Set condition value at offset 0x18 (request timeout/completion flag)
    requestPtr[0x18 / 4] = 100;

    // Create NXConditionLock for request completion signaling
    conditionLock = [objc_getClass("NXConditionLock") alloc];
    conditionLock = (*condLockInitWith)(conditionLock, @selector(initWith:), 0);

    // Store condition lock in request structure at offset 0x14
    requestPtr[0x14 / 4] = (unsigned int)conditionLock;

    // Lock the incoming queue (offset 0x5a8)
    (*lockMethod)(incomingQueueLock, @selector(lock));

    // Manually enqueue request onto disconnectedQueue (offset 0x590)
    // Queue head is at 0x590, tail at 0x594
    queuePtr = (unsigned int *)&disconnectedQueue;
    tailPtr = (unsigned int *)queuePtr[1];  // Get tail (offset 0x594)

    // Check if queue is empty (tail points to queue head)
    if (tailPtr == queuePtr) {
        // Empty queue - set head to point to new request
        queuePtr[0] = (unsigned int)request;
    } else {
        // Non-empty queue - link tail's next to new request
        // Request next pointer is at offset 0x24
        tailPtr[0x24 / 4] = (unsigned int)request;
    }

    // Set request's prev pointer (offset 0x28) to current tail
    requestPtr[0x28 / 4] = (unsigned int)tailPtr;

    // Set request's next pointer (offset 0x24) to queue head
    requestPtr[0x24 / 4] = (unsigned int)queuePtr;

    // Update queue tail to point to new request
    queuePtr[1] = (unsigned int)request;

    // Unlock the queue
    (*unlockMethod)(incomingQueueLock, @selector(unlock));

    // Set message remote port to kernel interrupt port (offset 0x5ac)
    msg.msg_remote_port = kernelInterruptPort;

    // Send message to wake up I/O thread
    msgResult = msg_send_from_kernel(&msg, MSG_OPTION_NONE, 0);

    if (msgResult == SEND_SUCCESS) {
        // Wait for I/O thread to complete the request
        // Thread will unlock condition lock with value 1 when done
        (*condLockLockWhen)(conditionLock, @selector(lockWhen:), 1);
    } else {
        // Message send failed
        result = SR_IOST_IOTO;  // 0xfffffd41 = -703
        IOLog("%s: msg_send_from_kernel() returned %d\n", [self name], msgResult);
    }

    // Free the condition lock
    (*condLockFree)(conditionLock, @selector(free));

    return result;
}

- (sc_status_t)resetSCSIBus
{
    unsigned int requestBuffer[6];  // 24 bytes for request structure
    int status;                      // Status returned at offset 0x18
    int result;

    // Build bus reset request (type 2)
    requestBuffer[0] = 2;

    // Execute bus reset command
    result = [self executeRequest:requestBuffer];

    if (result == 0) {
        // Success - return status from offset 0x18 (requestBuffer + 0x18)
        status = *(int *)((char *)requestBuffer + 0x18);
        return status;
    }

    // Request failed - return invalid status (7)
    return SR_IOST_INVALID;
}

- (int)numberOfTargets
{
    // Return number of targets from offset 0x320 (800 decimal)
    return numTargets;
}

- (unsigned int)maxTransfer
{
    // Return maximum transfer size: 510 pages (0x1fe)
    // At 4KB page size, this is approximately 2MB
    return page_size * 0x1fe;
}

- (unsigned int)numQueueSamples
{
    // Return number of queue samples from offset 0x578
    // This field is dual-purpose: chimWorkingMemory during init, numSamples after
    return (unsigned int)chimWorkingMemory;
}

- (unsigned int)sumQueueLengths
{
    // Return sum of queue lengths statistic from offset 0x59c
    return sumQueueLengths;
}

- (unsigned int)maxQueueLength
{
    // Return maximum queue length statistic from offset 0x598
    return maxQueueLen;
}

- (void)resetStats
{
    // Clear sum of queue lengths statistic (offset 0x59c)
    sumQueueLengths = 0;

    // Clear maximum queue length statistic (offset 0x598)
    maxQueueLen = 0;
}

@end
