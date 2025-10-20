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
 * Copyright (c) 1995 NeXT Computer, Inc.
 *
 * Kernel PCMCIA Bus Resource Object(s).
 */

#import <mach/mach_types.h>

#import <driverkit/KernLock.h>
#import "PCMCIAKernBus.h"
#import "PCMCIAKernBusPrivate.h"
#import "PCMCIAPool.h"
#import "PCMCIATuple.h"
#import "PCMCIATupleList.h"
#import "PCMCIAWindow.h"
#import "PCMCIASocket.h"
#import "PCMCIAid.h"
#import <driverkit/KernDevice.h>
#import <driverkit/KernDeviceDescription.h>
#import <driverkit/IODevice.h>
#import <kernserv/i386/spl.h>
#import <machdep/i386/intr_exported.h>
#import <machdep/i386/io_inline.h>
#import <objc/HashTable.h>
#import <objc/List.h>
#import <libkern/libkern.h>
#import <string.h>

/* Global list of bus instances */
static id _busInstances = nil;

/* Global list of driver config tables waiting to be matched */
id _driverConfigTables = nil;

/* Global BIOS memory bitmap - 3 uints (12 bytes) for tracking BIOS ROM regions */
/* Covers 0xC0000-0xF0000 range: 192KB / 2KB blocks = 96 blocks = 3 uints */
static unsigned int _biosBitmap[3];

/* External function to look up server configuration attributes */
extern char *configTableLookupServerAttribute(const char *busName, int busId, const char *attribute);

/*
 * Helper function to mark a range in the BIOS memory bitmap
 * bitmap: pointer to bitmap array (treated as array of unsigned ints)
 * offset: byte offset from base (0xC0000)
 * length: length of range to mark in bytes
 */
static void markRange(int bitmap, unsigned int offset, unsigned int length)
{
    unsigned int *intPtr;

    /* Convert offset to 2KB block index (>> 0xb = divide by 2048) */
    offset = offset >> 0xb;

    /* Convert length to number of 2KB blocks */
    for (length = length >> 0xb; length != 0; length = length - 1) {
        /* Calculate pointer to the uint containing this bit */
        /* offset >> 5 = divide by 32 (bits per uint) */
        /* * 4 = multiply by sizeof(uint) */
        intPtr = (unsigned int *)(bitmap + (offset >> 5) * 4);

        /* Set the bit: offset & 0x1f = modulo 32 (which bit in the uint) */
        *intPtr = *intPtr | (1 << ((unsigned char)offset & 0x1f));

        /* Move to next block */
        offset = offset + 1;
    }
}

/*
 * Find and mark BIOS ROM regions in upper memory area
 * Scans 0xC0000-0xF0000 for ROM signatures (0x55 0xAA)
 */
static void findBIOSMemoryRange(void *bitmap)
{
    unsigned char *scanPtr;
    int romSize;
    unsigned int roundedSize;

    /* Clear bitmap - 3 uints = 12 bytes */
    bzero(bitmap, 3 * sizeof(unsigned int));

    /* Scan from 0xC0000 to 0xF0000 */
    scanPtr = (unsigned char *)0xC0000;

    do {
        /* Check for ROM signature: 0x55 0xAA */
        if ((*scanPtr == 'U') && (scanPtr[1] == 0xAA)) {
            /* Third byte contains size in 512-byte blocks */
            romSize = (unsigned int)scanPtr[2] * 0x200;

            /* Round size to power-of-2 boundary for alignment */
            if (romSize - 0x8001 < 0x8000) {
                /* Size > 32KB, round to 64KB */
                roundedSize = 0x10000;
            } else if (romSize - 0x4001 < 0x4000) {
                /* Size > 16KB, round to 32KB */
                roundedSize = 0x8000;
            } else if (romSize - 0x2001 < 0x2000) {
                /* Size > 8KB, round to 16KB */
                roundedSize = 0x4000;
            } else {
                /* Minimum 8KB */
                roundedSize = 0x2000;
            }

            /* Mark the range as occupied */
            markRange((int)bitmap, scanPtr - (unsigned char *)0xC0000, roundedSize);

            /* Skip past this ROM */
            scanPtr += romSize;
        } else {
            /* No ROM found, advance by 2KB */
            scanPtr += 0x800;
        }
    } while (scanPtr < (unsigned char *)0xF0000);
}

@implementation PCMCIAKernBus

static const char *resourceNameStrings[] = {
    IRQ_LEVELS_KEY,
    DMA_CHANNELS_KEY,
    MEM_MAPS_KEY,
    IO_PORTS_KEY,
    PCMCIA_SOCKETS_KEY,
    NULL
};

+ initialize
{
    /* Initialize BIOS memory range bitmap */
    findBIOSMemoryRange(&_biosBitmap);

    /* Initialize global list of driver config tables */
    _driverConfigTables = [[List alloc] init];

    /* Initialize global list of bus instances */
    _busInstances = [[List alloc] init];

    /* Register the bus class */
    [self registerBusClass:self name:"PCMCIA"];

    /* Register with IODevice */
    [IODevice registerClass:self];

    return self;
}

/*
 * Class method to configure a driver with a table
 * Called when a driver loads to match it with an existing card
 */
+ (BOOL)configureDriverWithTable:table
{
    unsigned int i, count;
    id busInstance;
    BOOL configured;

    /* Try to configure with each bus instance */
    for (i = 0; i < [_busInstances count]; i++) {
        busInstance = [_busInstances objectAt:i];
        configured = [busInstance configureDriverWithTable:table];
        if (configured) {
            /* Successfully configured - done */
            return YES;
        }
    }

    /* No existing card matched - add to queue for future matching */
    [_driverConfigTables addObject:table];
    return YES;
}

/*
 * Class method to return device style
 * Returns 1 to indicate this is a physical device
 */
+ (int)deviceStyle
{
    return 1;
}

/*
 * Class method to return required protocols
 * Returns a NULL-terminated array of protocol objects
 */
+ (id *)requiredProtocols
{
    static id protocols[] = { "PCMCIAStatusChange", "PCMCIAAdapter", NULL };
    return protocols;
}

/*
 * Class method to probe and configure bus instances
 * Configures each bus instance with settings from config table
 */
+ (BOOL)probe:deviceDesc
{
    id directDevice;
    unsigned int i;
    unsigned int busCount;
    id busInstance;
    char *configValue;
    char *strPtr;
    char c;
    unsigned int strLen;
    unsigned int memoryBase;
    unsigned int memoryLength;
    IORange range;

    /* Get the direct device from device description */
    directDevice = [deviceDesc directDevice];

    /* Iterate through all bus instances */
    i = 0;
    do {
        busCount = [_busInstances count];
        if (i >= busCount) {
            return NO;
        }

        /* Set default memory range values */
        memoryBase = 0xD0000;
        memoryLength = 0x2000;

        /* Get bus instance */
        busInstance = [_busInstances objectAt:i];

        /* Look up "Verbose" configuration */
        configValue = configTableLookupServerAttribute("PCMCIABus", i, "Verbose");
        [busInstance setVerbose:NO];

        if (configValue != NULL) {
            if (*configValue == 'Y' || *configValue == 'y') {
                [busInstance setVerbose:YES];
            }

            /* Calculate string length manually and free */
            strLen = 0xFFFFFFFF;
            strPtr = configValue;
            do {
                if (strLen == 0) break;
                strLen--;
                c = *strPtr;
                strPtr++;
            } while (c != '\0');
            IOFree(configValue, ~strLen);
        }

        /* Look up "PCMCIA Memory Base" configuration */
        configValue = configTableLookupServerAttribute("PCMCIABus", i, "PCMCIA Memory Base");

        if (configValue != NULL) {
            memoryBase = strtol(configValue, NULL, 0);

            /* Clamp to valid range 0xC0000 - 0xEF000 */
            if (memoryBase < 0xC0000) {
                memoryBase = 0xC0000;
            } else if (memoryBase > 0xEEFFF) {
                memoryBase = 0xEF000;
            }

            /* Calculate string length and free */
            strLen = 0xFFFFFFFF;
            strPtr = configValue;
            do {
                if (strLen == 0) break;
                strLen--;
                c = *strPtr;
                strPtr++;
            } while (c != '\0');
            IOFree(configValue, ~strLen);
        }

        /* Look up "PCMCIA Memory Length" configuration */
        configValue = configTableLookupServerAttribute("PCMCIABus", i, "PCMCIA Memory Length");

        if (configValue != NULL) {
            memoryLength = strtol(configValue, NULL, 0);

            /* Clamp to minimum 0x1000 */
            if (memoryLength < 0x1000) {
                memoryLength = 0x1000;
            }

            /* Ensure it fits within upper memory area (up to 0xF0000) */
            if (memoryLength > (0xF0000 - memoryBase)) {
                memoryLength = 0xF0000 - memoryBase;
            }

            /* Calculate string length and free */
            strLen = 0xFFFFFFFF;
            strPtr = configValue;
            do {
                if (strLen == 0) break;
                strLen--;
                c = *strPtr;
                strPtr++;
            } while (c != '\0');
            IOFree(configValue, ~strLen);
        }

        /* Set bus range */
        range.base = memoryBase;
        range.length = memoryLength;
        [busInstance setBusRange:range];

        /* Add adapter to bus instance */
        [busInstance addAdapter:directDevice];

        i++;
    } while (1);
}

- init
{
    int busId;

    [super init];

    /* Create adapters list */
    _adapters = [[List alloc] init];

    /* Create socket mapping hash table */
    _socketMap = [[HashTable alloc] initKeyDesc:"@" valueDesc:"!"];

    /* Initialize global bus instances list if needed */
    if (_busInstances == nil) {
        _busInstances = [[List alloc] init];
    }

    /* Add to global bus instances */
    [_busInstances addObject:self];

    /* Set bus ID to 0 */
    [self setBusId:0];

    /* Register the bus instance */
    busId = [self busId];
    [[self class] registerBusInstance:self name:"PCMCIA" busId:busId];

    /* Initialize memory range resource to NULL */
    _memoryRangeResource = nil;

    /* Initialize verbose flag to 0 */
    _verbose = 0;

    return self;
}

- free
{
    NXHashState state;
    void *key;
    void *value;

    /* Free the adapters list */
    [_adapters free];

    /* Iterate through socket map and free all values */
    state = [_socketMap initState];
    while ([_socketMap nextState:&state key:&key value:&value]) {
        /* Free the socket info structure (24 bytes) */
        IOFree(value, 0x18);
    }

    /* Free the socket map hash table */
    [_socketMap free];

    /* Remove from global bus instances list */
    [_busInstances removeObject:self];

    return [super free];
}

/*
 * Allocate memory window for socket
 */
- allocMemoryWindowForSocket:socket
{
    SocketInfo *socketInfo;
    id window;

    /* Look up socket info in hash table */
    socketInfo = (SocketInfo *)[_socketMap valueForKey:socket];
    if (socketInfo == NULL) {
        return nil;
    }

    /* Allocate window from pool using supportsMemory predicate */
    window = [socketInfo->pool allocElementByMethod:@selector(supportsMemory)];

    return window;
}

/*
 * Return memory range resource for mapping
 */
- memoryRangeResource
{
    unsigned int alignedLength;
    IORange range;

    /* If we have a cached resource, free it first */
    if (_memoryRangeResource != nil) {
        if (_verbose) {
            range = [_memoryRangeResource range];
            IOLog("PKB: freeing range 0x%x(0x%x)\n", range.base, range.length);
        }
        [_memoryRangeResource free];
        _memoryRangeResource = nil;
    }

    /* Calculate page-aligned length */
    extern vm_size_t page_size;
    alignedLength = ((page_size + _memoryLength - 1) / page_size) * page_size;

    /* Find and reserve a memory range */
    _memoryRangeResource = [self findAndReserveRangeBase:_memoryBase
                                                  Length:alignedLength
                                               Alignment:page_size];

    /* Log the result if verbose */
    if (_verbose) {
        if (_memoryRangeResource == nil) {
            IOLog("%s: memoryRangeResource: resource is nil\n", [self name]);
        } else {
            range = [_memoryRangeResource range];
            IOLog("%s: memoryRangeResource: reserved 0x%x..0x%x\n",
                  [self name], range.base, range.base + range.length);
        }
    }

    return _memoryRangeResource;
}

/*
 * Socket info structure (24 bytes)
 */
typedef struct {
    unsigned int    status;         // Offset 0 - Current socket status
    unsigned char   flag1;          // Offset 4
    unsigned char   probed;         // Offset 5 - Card has been probed
    unsigned short  padding;        // Offset 6
    id              pool;           // Offset 8 - PCMCIAPool
    id              tupleList;      // Offset 12 - PCMCIATupleList
    id              deviceDesc;     // Offset 16 - KernDeviceDescription
    id              cardID;         // Offset 20 - PCMCIAid
} SocketInfo;

/*
 * Add adapter to the bus
 */
- addAdapter:adapter
{
    id sockets;
    unsigned int i, count;
    id socket;
    SocketInfo *socketInfo;
    id pool;
    id windows;
    unsigned int windowCount;

    if (_verbose) {
        IOLog("PKB: adding adapter %x\n", (unsigned int)adapter);
    }

    /* Add adapter to list */
    [_adapters addObject:adapter];

    /* Set self as status change handler */
    [adapter setStatusChangeHandler:self];

    /* Get sockets from adapter */
    sockets = [adapter sockets];

    /* Process each socket */
    count = [sockets count];
    for (i = 0; i < count; i++) {
        socket = [sockets objectAt:i];

        /* Allocate socket info structure (24 bytes) */
        socketInfo = (SocketInfo *)IOMalloc(0x18);
        bzero(socketInfo, 0x18);

        /* Create pool for this socket */
        pool = [[PCMCIAPool alloc] init];
        socketInfo->pool = pool;

        /* Add windows from socket to pool */
        if (_verbose) {
            windows = [socket windows];
            windowCount = [windows count];
            IOLog("PKB: adding %d windows for adapter\n", windowCount);
        }

        windows = [socket windows];
        [socketInfo->pool addList:windows];

        /* Insert socket and info into hash table */
        [_socketMap insertKey:socket value:socketInfo];

        /* Set status change mask */
        [socket setStatusChangeMask:1];

        /* Initialize remaining fields */
        socketInfo->tupleList = nil;
        socketInfo->deviceDesc = nil;
        socketInfo->flag1 = 0;
        socketInfo->probed = 0;
        socketInfo->cardID = nil;

        /* Trigger initial status change */
        [self statusChangedForSocket:socket changedStatus:1];
    }

    return self;
}

/*
 * Remove adapter from the bus
 */
- removeAdapter:adapter
{
    id sockets;
    unsigned int i, count;
    id socket;
    SocketInfo *socketInfo;

    /* Get sockets from adapter */
    sockets = [adapter sockets];

    /* Remove each socket */
    count = [sockets count];
    for (i = 0; i < count; i++) {
        socket = [sockets objectAt:i];

        /* Look up socket info in hash table */
        socketInfo = (SocketInfo *)[_socketMap valueForKey:socket];

        /* Free the pool */
        [socketInfo->pool free];

        /* Free the socket info structure (24 bytes) */
        IOFree(socketInfo, 0x18);

        /* Remove socket from hash table */
        [_socketMap removeKey:socket];
    }

    /* Remove adapter from list */
    [_adapters removeObject:adapter];

    return self;
}

/*
 * Allocate I/O window for socket
 */
- allocIOWindowForSocket:socket
{
    SocketInfo *socketInfo;
    id window;

    /* Look up socket info in hash table */
    socketInfo = (SocketInfo *)[_socketMap valueForKey:socket];
    if (socketInfo == NULL) {
        return nil;
    }

    /* Allocate window from pool using supportsIO predicate */
    window = [socketInfo->pool allocElementByMethod:@selector(supportsIO)];

    return window;
}

/*
 * Set bus range
 */
- (void)setBusRange:(IORange)range
{
    _memoryBase = range.base;
    _memoryLength = range.length;
}

/*
 * Set verbose logging flag
 */
- (void)setVerbose:(BOOL)verbose
{
    _verbose = verbose;
}

/*
 * Handle socket status change
 */
- (void)statusChangedForSocket:socket changedStatus:(unsigned int)changedStatus
{
    SocketInfo *socketInfo;
    unsigned int socketNum;
    unsigned int currentStatus;
    id memRange;
    IORange range;
    id memWindow;
    unsigned int i, count;
    id tuple;

    /* Get socket number for logging */
    socketNum = [socket socketNumber];

    /* Check if we care about this status change (bit 0) */
    if ((changedStatus & 1) == 0) {
        IOLog("PCMCIA: don't care socket %d\n", socketNum);
        return;
    }

    /* Look up socket info */
    socketInfo = (SocketInfo *)[_socketMap valueForKey:socket];
    if (socketInfo == NULL) {
        IOLog("PCMCIA: Status changed on unknown socket %x\n", (unsigned int)socket);
        return;
    }

    /* Check if already probed */
    if (socketInfo->flag1 != 0) {
        IOLog("PCMCIA: Socket %d: already probed\n", socketNum);
        return;
    }

    /* Get current status */
    currentStatus = [socket status];

    if (_verbose) {
        IOLog("PKB: socket %d status: changed = %x, current = %x\n",
              socketNum, changedStatus, currentStatus);
    }

    /* Store current status */
    socketInfo->status = currentStatus;

    /* Check if card is present (bit 0 of status) */
    if ((currentStatus & 1) == 0) {
        /* Card removed */
        if (socketInfo->probed != 0) {
            /* Clean up card resources */
            if (socketInfo->tupleList != nil) {
                [[socketInfo->tupleList freeObjects:@selector(free)] free];
            }

            if (socketInfo->deviceDesc != nil) {
                [socketInfo->deviceDesc free];
            }

            if (socketInfo->cardID != nil) {
                [socketInfo->cardID free];
            }

            socketInfo->cardID = nil;
            socketInfo->tupleList = nil;
            socketInfo->deviceDesc = nil;
            socketInfo->probed = 0;
            socketInfo->flag1 = 0;

            [self disableSocket:socket];
            IOLog("PCMCIABus: Socket %d: card removed\n", socketNum);
        }
    } else {
        /* Card inserted */
        if (socketInfo->probed == 0) {
            socketInfo->probed = 1;

            /* Enable socket */
            if (![self enableSocket:socket]) {
                IOLog("%s: enableSocket failed\n", [self name]);
                return;
            }

            /* Allocate memory range for attribute memory */
            if (_verbose) {
                IOLog("%s: trying to allocate memory range 0x%x..0x%x\n",
                      [self name], _memoryBase, _memoryBase + _memoryLength - 1);
            }

            memRange = [self findAndReserveRangeBase:_memoryBase
                                              Length:_memoryLength
                                           Alignment:0x1000];

            if (memRange == nil) {
                IOLog("PCMCIA: could not find a memory range 0x%x..0x%x\n",
                      _memoryBase, _memoryBase + _memoryLength - 1);
                return;
            }

            range = [memRange range];

            if (_verbose) {
                IOLog("%s: reserved memory range 0x%x..0x%x\n",
                      [self name], range.base, range.base + range.length - 1);
            }

            /* Map attribute memory */
            memWindow = [self mapAttributeMemory:range ForSocket:socket CardOffset:0];

            if (memWindow == nil) {
                [memRange free];
                IOLog("PCMCIA: couldn't get a memory window!\n");
                return;
            }

            /* Read and parse tuples */
            socketInfo->tupleList = [self tupleListFromSocket:socket
                                                mappedAddress:range.base];

            /* Create device description */
            socketInfo->deviceDesc = [[KernDeviceDescription alloc] init];

            if (socketInfo->deviceDesc != nil) {
                /* Parse all tuples into device description */
                count = [socketInfo->tupleList count];
                for (i = 0; i < count; i++) {
                    tuple = [socketInfo->tupleList objectAt:i];
                    [self parseTuple:tuple intoDeviceDescription:socketInfo->deviceDesc];
                }

                IOLog("PCMCIABus: Socket %d: card inserted\n", socketNum);

                /* Create PCMCIAid from device description */
                socketInfo->cardID = [[PCMCIAid alloc] initFromDescription:socketInfo->deviceDesc];

                /* Log card information */
                [PCMCIAid IOLogCardInformation:socketInfo->deviceDesc];
            }

            /* Clean up */
            [self freeMemoryWindowElement:memWindow];
            [memRange free];

            /* Configure the socket */
            [self configureSocket:socket];
        }
    }
}

@end
