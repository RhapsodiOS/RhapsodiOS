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
 * PCMCIAKernBus Private Methods Implementation
 */

#import "PCMCIAKernBus.h"
#import "PCMCIAKernBusPrivate.h"
#import <libkern/libkern.h>

/*
 * Wait for socket to become ready
 * Polls socket status up to 100 times with 500us delays
 * Returns 1 if socket becomes ready (bit 7 set), 0 on timeout
 */
static BOOL waitForSocketReady(id socket)
{
    unsigned char status;
    int retries;

    retries = 100;
    do {
        /* Get socket status */
        status = [socket status];

        /* Check if ready bit is set (bit 7 = 0x80) */
        if (status < 0) {  /* Signed char < 0 means bit 7 is set */
            return YES;
        }

        /* Wait 500 microseconds */
        IODelay(500);

        retries = retries - 1;
    } while (retries != 0);

    /* Timeout - socket never became ready */
    return NO;
}

/*
 * Print device description contents for debugging
 * Prints all string key-value pairs and resource lists
 */
static void printDescription(id deviceDesc)
{
    BOOL hasMore;
    unsigned long long state;
    const char *key;
    const char *stringValue;
    id resourceValue;
    unsigned int count;

    IOLog("PKB: Device description:\n------------\n");

    /* Iterate through string key-value pairs */
    state = [deviceDesc initStringState];
    while (1) {
        hasMore = [deviceDesc nextStringState:&state key:&key value:&stringValue];
        if (hasMore == NO) break;
        IOLog("\t(%s) = (%s)\n", key, stringValue);
    }

    /* Iterate through resource lists */
    state = [deviceDesc initResourcesState];
    while (1) {
        hasMore = [deviceDesc nextResourcesState:&state key:&key value:&resourceValue];
        if (hasMore == NO) break;
        count = [resourceValue count];
        IOLog("\t(%s) = %d resources\n", key, count);
    }

    IOLog("------------\n");
}

@implementation PCMCIAKernBus (Private)

/*
 * Allocate resources for device description
 */
- (BOOL)allocateResourcesForDeviceDescription:deviceDesc
{
    id eisaBus;
    BOOL result;

    /* Look up EISA bus instance */
    eisaBus = [KernBus lookupBusInstanceWithName:"EISA" busId:0];

    /* Set the bus on the device description */
    [deviceDesc setBus:eisaBus];

    /* Delegate resource allocation to EISA bus */
    result = [eisaBus allocateResourcesForDeviceDescription:deviceDesc];

    return result;
}

/*
 * Allocate shared memory for socket
 */
- allocateSharedMemory:(unsigned int)size
        ForDescription:deviceDesc
             AndSocket:socket
{
    id memoryMapList;
    int memoryRangeCount;
    void *checkList;
    int i, j;
    BOOL userSupplied;
    id windowList;
    unsigned int *rangePtr;
    id rangeResource;
    IORange range;
    unsigned int base, length, cardBase;
    BOOL isShared;
    int matchIndex;
    id window;
    BOOL match;
    int listCount;

    userSupplied = NO;
    windowList = nil;

    /* Get memory maps from device description */
    memoryMapList = [deviceDesc resourcesForKey:"Memory Maps"];

    /* Get memory range count from device description (offset 0x104) */
    memoryRangeCount = *(int *)((char *)size + 0x104);

    /* Allocate check list (2 bytes per range) */
    checkList = IOMalloc(memoryRangeCount * 2);
    if (checkList == NULL) {
        IOLog("%s: IOMalloc failed on checkList_p\n", [self name]);
        return nil;
    }
    bzero(checkList, memoryRangeCount * 2);

    if (memoryMapList == nil) {
        /* Create new memory map list */
        memoryMapList = [[List alloc] init];
        if (memoryMapList == nil) {
            IOLog("%s: allocateSharedMemory: alloc memoryMapList failed\n", [self name]);
            goto cleanup_and_fail;
        }

        [memoryMapList setAvailableCapacity:memoryRangeCount];

        /* Process fixed-base memory ranges (offset 0x108 is start of array) */
        rangePtr = (unsigned int *)((char *)size + 0x108);
        for (i = 0; i < memoryRangeCount; i++) {
            base = rangePtr[0];
            length = rangePtr[1];
            cardBase = rangePtr[2];
            isShared = *(unsigned char *)(&rangePtr[3]);

            if (isShared == 0) {
                /* Reserve specific base address */
                rangeResource = [self findAndReserveRangeBase:base
                                                       Length:length
                                                    AlignedTo:0x1000];
                if (rangeResource != nil) {
                    range = [rangeResource range];
                    if (base == range.base) {
                        if (_verbose) {
                            IOLog("PKB: reserved range 0x%x..0x%x (card base 0x%x)\n",
                                  base, length, cardBase);
                        }
                        [memoryMapList insertObject:rangeResource at:i];
                        *((unsigned char *)checkList + i * 2 + 1) = i;
                    } else {
                        [rangeResource free];
                        IOLog("%s: failed to reserve 0x%x(0x%x)\n", [self name], base, length);
                        goto cleanup_and_fail;
                    }
                } else {
                    IOLog("%s: failed to reserve 0x%x(0x%x)\n", [self name], base, length);
                    goto cleanup_and_fail;
                }
            }

            rangePtr += 4;  /* Each entry is 16 bytes (4 ints) */
        }

        /* Process shared/any-base memory ranges */
        rangePtr = (unsigned int *)((char *)size + 0x108);
        for (i = 0; i < memoryRangeCount; i++) {
            length = rangePtr[1];
            cardBase = rangePtr[2];
            isShared = *(unsigned char *)(&rangePtr[3]);

            if (isShared == 1) {
                /* Allocate from bus memory range */
                rangeResource = [self findAndReserveRangeBase:_memoryBase
                                                       Length:length
                                                    AlignedTo:0x1000];
                if (rangeResource == nil) {
                    IOLog("%s: failed to reserve memory of length 0x%x\n", [self name], length);
                    goto cleanup_and_fail;
                }

                if (_verbose) {
                    range = [rangeResource range];
                    IOLog("PKB: reserved range 0x%x..0x%x (card base 0x%x)\n",
                          range.base, range.base + range.length, cardBase);
                }

                [memoryMapList insertObject:rangeResource at:i];
                *((unsigned char *)checkList + i * 2 + 1) = i;
            }

            rangePtr += 4;
        }

        [deviceDesc setResources:memoryMapList forKey:"Memory Maps"];
    } else {
        /* User supplied memory map list */
        userSupplied = YES;

        if (_verbose) {
            IOLog("PKB: user supplied memory range list (%d range(s))\n",
                  [memoryMapList count]);
        }

        /* Verify count matches */
        if (memoryRangeCount != [memoryMapList count]) {
            IOLog("%s: device has %d memory ranges, not %d\n",
                  [self name], memoryRangeCount, [memoryMapList count]);
            goto cleanup_and_fail;
        }

        /* Match fixed-base ranges */
        rangePtr = (unsigned int *)((char *)size + 0x108);
        for (i = 0; i < memoryRangeCount; i++) {
            base = rangePtr[0];
            length = rangePtr[1];
            isShared = *(unsigned char *)(&rangePtr[3]);

            if (isShared == 0) {
                /* Find matching range in list */
                listCount = [memoryMapList count];
                matchIndex = -1;
                for (j = 0; j < listCount; j++) {
                    if (*((unsigned char *)checkList + j * 2) == 0) {
                        rangeResource = [memoryMapList objectAt:j];
                        range = [rangeResource range];
                        match = YES;
                        if (base != 0 && base != range.base) {
                            match = NO;
                        }
                        if (length != 0 && length != range.length) {
                            match = NO;
                        }
                        if (match) {
                            matchIndex = j;
                            break;
                        }
                    }
                }

                if (matchIndex == -1) {
                    IOLog("%s: could not match device memory 0x%x(0x%x)\n",
                          [self name], base, length);
                    goto cleanup_and_fail;
                }

                *((unsigned char *)checkList + matchIndex * 2) = 1;
                *((unsigned char *)checkList + matchIndex * 2 + 1) = i;
            }

            rangePtr += 4;
        }

        /* Match shared/any-base ranges */
        rangePtr = (unsigned int *)((char *)size + 0x108);
        for (i = 0; i < memoryRangeCount; i++) {
            length = rangePtr[1];
            isShared = *(unsigned char *)(&rangePtr[3]);

            if (isShared == 1) {
                /* Find matching range by length */
                listCount = [memoryMapList count];
                matchIndex = -1;
                for (j = 0; j < listCount; j++) {
                    if (*((unsigned char *)checkList + j * 2) == 0) {
                        rangeResource = [memoryMapList objectAt:j];
                        range = [rangeResource range];
                        if (length == 0 || length == range.length) {
                            matchIndex = j;
                            break;
                        }
                    }
                }

                if (matchIndex == -1) {
                    IOLog("%s: could not match device memory length 0x%x)\n",
                          [self name], length);
                    goto cleanup_and_fail;
                }

                *((unsigned char *)checkList + matchIndex * 2) = 1;
                *((unsigned char *)checkList + matchIndex * 2 + 1) = i;
            }

            rangePtr += 4;
        }
    }

    /* Create window list */
    windowList = [[List alloc] init];
    if (windowList == nil) {
        IOLog("PCMCIA: failed to allocate windowList\n");
        goto cleanup_and_fail;
    }

    /* Map all memory ranges */
    rangePtr = (unsigned int *)((char *)size + 0x108);
    for (i = 0; i < memoryRangeCount; i++) {
        cardBase = rangePtr[2];

        /* Get the range resource for this entry */
        matchIndex = *((unsigned char *)checkList + i * 2 + 1);
        rangeResource = [memoryMapList objectAt:matchIndex];
        range = [rangeResource range];

        /* Map the memory window */
        window = [self mapMemory:range ForSocket:socket ToCardAddress:cardBase];
        if (window == nil) {
            IOLog("PCMCIA: could not allocate memory window\n");
            goto cleanup_and_fail;
        }

        /* Set 16-bit mode (offset 0x71 in size parameter) */
        [[window object] set16Bit:*(unsigned char *)((char *)size + 0x71)];

        [windowList addObject:window];

        rangePtr += 4;
    }

    IOFree(checkList, memoryRangeCount * 2);
    return windowList;

cleanup_and_fail:
    if (!userSupplied && memoryMapList != nil) {
        [[memoryMapList freeObjects:@selector(free)] free];
    }
    if (windowList != nil) {
        [[windowList freeObjects:@selector(free)] free];
    }
    IOFree(checkList, memoryRangeCount * 2);
    return nil;
}

/*
 * Check if configuration table matches socket
 */
- (BOOL)configTable:table matchesSocket:socket
{
    char *autoDetectIDs;
    SocketInfo *socketInfo;
    BOOL matched;
    id tempID;

    /* Get "Auto Detect IDs" string from table */
    autoDetectIDs = (char *)[table valueForStringKey:"Auto Detect IDs"];

    /* If no auto detect IDs specified, match any socket */
    if (autoDetectIDs == NULL) {
        return YES;
    }

    /* Look up socket info */
    socketInfo = (SocketInfo *)[_socketMap valueForKey:socket];

    matched = NO;

    /* Parse and match all IDs in the string */
    while (autoDetectIDs != NULL && *autoDetectIDs != '\0') {
        /* Create PCMCIAid from ID string */
        tempID = [[PCMCIAid alloc] initFromIDString:&autoDetectIDs];
        if (tempID == nil) {
            return matched;
        }

        /* Check if this ID matches the card's ID */
        if ([tempID matchesID:socketInfo->cardID]) {
            matched = YES;
        }

        /* Free temporary ID */
        [tempID free];

        /* Check if we've reached the end */
        if (autoDetectIDs == NULL || *autoDetectIDs == '\0') {
            return matched;
        }
    }

    return matched;
}

/*
 * Configure driver with table
 */
- (BOOL)configureDriverWithTable:table
{
    NXHashState state;
    void *key;
    void *value;
    id socket;
    unsigned char *socketBytes;
    unsigned int socketNum;
    BOOL matched;
    BOOL configured;

    /* Iterate through all sockets in the socket map */
    state = [_socketMap initState];

    while ([_socketMap nextState:&state key:&key value:&value]) {
        socket = (id)key;
        socketBytes = (unsigned char *)value;

        /* Log socket status if verbose */
        if (_verbose) {
            socketNum = [socket socketNumber];
            IOLog("PKB: socket %d present %d probed %d\n",
                  socketNum, socketBytes[0] & 1, socketBytes[4]);
        }

        /* Skip if card not present (bit 0 of status) */
        if ((socketBytes[0] & 1) == 0) {
            continue;
        }

        /* Skip if already probed (byte at offset 4) */
        if (socketBytes[4] != 0) {
            continue;
        }

        /* Check if this table matches the socket */
        matched = [self configTable:table matchesSocket:socket];
        if (!matched) {
            continue;
        }

        /* Try to configure the socket with this driver table */
        configured = [self configureSocket:socket withDriverTable:table];
        if (!configured) {
            continue;
        }

        /* Success - mark socket as probed */
        if (_verbose) {
            socketNum = [socket socketNumber];
            IOLog("PKB: socket number %d now marked as probed\n", socketNum);
        }

        socketBytes[4] = 1;
        return YES;
    }

    /* No matching socket found */
    return NO;
}

/*
 * Configure socket
 */
- (BOOL)configureSocket:socket
{
    SocketInfo *socketInfo;
    unsigned int socketNum;
    unsigned int i, count;
    id table;
    BOOL matched;
    BOOL configured;
    extern id _driverConfigTables;

    /* Get socket info */
    socketInfo = (SocketInfo *)[_socketMap valueForKey:socket];

    if (_verbose) {
        socketNum = [socket socketNumber];
        IOLog("PKB: configuring socket %d\n", socketNum);
    }

    /* Iterate through global driver config tables */
    i = 0;
    while (YES) {
        count = [_driverConfigTables count];
        if (count <= i) {
            return NO;
        }

        table = [_driverConfigTables objectAt:i];

        /* Check if this table matches the socket */
        matched = [self configTable:table matchesSocket:socket];
        if (matched) {
            /* Try to configure with this table */
            configured = [self configureSocket:socket withDriverTable:table];
            if (configured) {
                /* Success - remove table from list and mark socket as probed */
                break;
            }
        }

        i++;
    }

    /* Remove the used table from the global list */
    [_driverConfigTables removeObjectAt:i];

    if (_verbose) {
        socketNum = [socket socketNumber];
        IOLog("PKB: socket %d marked as probed\n", socketNum);
    }

    /* Mark socket as probed (offset 4 in SocketInfo) */
    socketInfo->probed = 1;

    return YES;
}

/*
 * Configure socket with device description
 */
- (BOOL)configureSocket:socket withDescription:deviceDesc
{
    id eisaBus;
    id tpceList;
    id portRangeList;
    id irqList;
    id windowList;
    id selectedConfig;
    BOOL userSuppliedPorts;
    BOOL userSuppliedIRQ;
    unsigned int i, j, count;
    id config;
    BOOL matched;
    id ioPortsResource;
    unsigned int alignment, numRanges;
    IORange range;
    id rangeResource;
    BOOL failed;
    id irqLevelsResource;
    unsigned int irqNumber;
    unsigned int irqMask;
    id irqResource;
    id memMapList;
    id window;
    id windowObject;
    char *configRegAddrStr;
    unsigned int configRegOffset;
    unsigned int baseOffset;
    id configRangeResource;
    unsigned int configBase;
    id configWindow;
    unsigned int configValue;
    id audioEnableStr;
    BOOL audioEnable;
    unsigned char *configPtr;
    int waitResult;
    id socketList;
    id socketElement;

    windowList = nil;
    selectedConfig = nil;
    userSuppliedPorts = NO;
    userSuppliedIRQ = NO;

    /* Look up EISA bus */
    eisaBus = [KernBus lookupBusInstanceWithName:"EISA" busId:0];

    if (_verbose) {
        IOLog("PKB: configureSocket:withDescription:\n");
        if (_verbose) {
            _printDescription(deviceDesc);
        }
    }

    /* Get TPCE list */
    tpceList = [deviceDesc resourcesForKey:"PCMCIA_TPCE_LIST"];

    if (_verbose) {
        IOLog("PKB: configureCardWithDescription: %d TPCE tuples\n", [tpceList count]);
    }

    /* Get or create port range list */
    portRangeList = [deviceDesc resourcesForKey:"I/O Ports"];
    if (portRangeList == nil) {
        portRangeList = [[List alloc] init];
        if (portRangeList == nil) {
            IOLog("PCMCIA: alloc portRangeList failed\n");
            goto cleanup_and_fail;
        }
    } else {
        userSuppliedPorts = YES;
        if (_verbose) {
            IOLog("PKB: user supplied port list (%d ranges)\n", [portRangeList count]);
        }
    }

    /* Get or create IRQ list */
    irqList = [deviceDesc resourcesForKey:"IRQ Levels"];
    if (irqList == nil) {
        irqList = [[List alloc] init];
        if (irqList == nil) {
            IOLog("PCMCIA: alloc irqList failed\n");
            goto cleanup_and_fail;
        }
    } else {
        userSuppliedIRQ = YES;
        if (_verbose) {
            IOLog("PKB: user supplied IRQ list (%d items)\n", [irqList count]);
        }
    }

    /* Create window list */
    windowList = [[List alloc] init];
    if (windowList == nil) {
        IOLog("PCMCIA: alloc windowList failed\n");
        goto cleanup_and_fail;
    }

    /* Get I/O Ports resource from EISA bus */
    ioPortsResource = [eisaBus _lookupResourceWithKey:"I/O Ports"];

    /* Try to find a matching configuration entry */
    selectedConfig = nil;
    for (i = 0; i < [tpceList count]; i++) {
        if (_verbose) {
            IOLog("PKB: configuring card, looking at config entry %d\n", i);
        }

        config = [tpceList objectAt:i];

        if (userSuppliedPorts) {
            matched = [self entry:config matchesUserIOPorts:portRangeList];
        } else {
            matched = [self reserveIOPorts:portRangeList UsingEntry:config];
        }

        if (matched) {
            selectedConfig = config;
            break;
        }
    }

    /* If no config found, try to make one up */
    if (selectedConfig == nil) {
        if (_verbose) {
            IOLog("PKB: couldn't find a configuration; making one up.\n");
        }

        for (i = 0; i < [tpceList count]; i++) {
            config = [tpceList objectAt:i];

            /* Check if this config decodes all address lines (offset 0x6c) */
            if (*(int *)((char *)config + 0x6c) == 0) {
                if (_verbose) {
                    IOLog("PKB: this configuration decodes all address lines; trying another.\n");
                }
                continue;
            }

            /* Calculate alignment from address line count */
            alignment = 1 << (*(unsigned int *)((char *)config + 0x6c) & 0x1f);
            numRanges = *(unsigned int *)((char *)config + 0x74);

            if (numRanges == 0 && alignment > 1) {
                numRanges = 1;
            }

            failed = NO;
            for (j = 0; j < numRanges; j++) {
                if (userSuppliedPorts) {
                    rangeResource = [portRangeList objectAt:j];
                    range = [rangeResource range];
                } else {
                    range = [ioPortsResource findFreeRangeWithSize:alignment alignment:alignment];
                }

                if (range.length != alignment) {
                    if (_verbose) {
                        IOLog("PKB: range %x+%x doesn't exist or doesn't match alignment %d\n",
                              range.base, range.length, alignment);
                    }
                    failed = YES;
                    break;
                }

                if (!userSuppliedPorts) {
                    rangeResource = [ioPortsResource reserveRange:range];
                    if (rangeResource == nil) {
                        failed = YES;
                        [[portRangeList freeObjects:@selector(free)] free];
                        break;
                    }
                    [portRangeList addObject:rangeResource];
                }
            }

            if (!failed) {
                selectedConfig = config;
                break;
            }
        }

        if (selectedConfig == nil) {
            if (_verbose) {
                IOLog("PKB: no configuration found\n");
            }
            goto cleanup_and_fail;
        }
    }

    /* Allocate IRQ if needed */
    if ([irqList count] == 0 && *(unsigned char *)((char *)selectedConfig + 0xf8) != 0) {
        if (_verbose) {
            IOLog("PKB: looking for IRQ in tuples\n");
        }

        irqLevelsResource = [eisaBus _lookupResourceWithKey:"IRQ Levels"];
        irqMask = *(unsigned int *)((char *)selectedConfig + 0x100);

        irqResource = nil;
        for (i = 0; i < 16; i++) {
            if ((irqMask & 1) != 0) {
                irqResource = [irqLevelsResource reserveItem:i];
                if (irqResource != nil) {
                    break;
                }
            }
            irqMask >>= 1;
        }

        if (irqResource == nil) {
            if (_verbose) {
                IOLog("PKB: trying to find a free IRQ\n");
            }
            irqNumber = [irqLevelsResource findFreeItem];
            irqResource = [irqLevelsResource reserveItem:irqNumber];
        }

        if (irqResource != nil) {
            [irqList addObject:irqResource];
        }
    } else {
        irqResource = [irqList objectAt:0];
        irqNumber = [irqResource item];
        if (_verbose) {
            IOLog("PKB: user supplied irq %d\n", irqNumber);
        }
    }

    /* Handle memory maps if needed */
    if (*(int *)((char *)selectedConfig + 0x104) != 0) {
        /* Card needs shared memory */
        memMapList = [self allocateSharedMemory:selectedConfig
                                 ForDescription:deviceDesc
                                      AndSocket:socket];
        if (memMapList == nil) {
            goto cleanup_and_fail;
        }
        [windowList appendList:memMapList];
    } else {
        /* Check if driver's config table incorrectly indicates shared memory */
        memMapList = [deviceDesc resourcesForKey:"Memory Maps"];
        if (memMapList != nil && _verbose) {
            IOLog("PKB: driver's config table indicates shared memory but device does not\n");
        }
    }

    /* Log port ranges and IRQs if verbose */
    if (_verbose) {
        IOLog("PKB: port range list: ");
        for (i = 0; i < [portRangeList count]; i++) {
            rangeResource = [portRangeList objectAt:i];
            if (_verbose) {
                range = [rangeResource range];
                IOLog("%x-%x ", range.base, range.base + range.length - 1);
            }
        }
        if (_verbose) {
            IOLog("\n");
            IOLog("PKB: IRQ list: ");
        }
        for (i = 0; i < [irqList count]; i++) {
            irqResource = [irqList objectAt:i];
            if (_verbose) {
                IOLog("%d ", [irqResource item]);
            }
        }
        if (_verbose) {
            IOLog("\n");
        }
    }

    /* Set resources in device description */
    [deviceDesc setResources:portRangeList forKey:"I/O Ports"];
    [deviceDesc setResources:irqList forKey:"IRQ Levels"];

    /* Allocate and configure I/O windows */
    for (i = 0; i < [portRangeList count]; i++) {
        window = [self allocIOWindowForSocket:socket];
        if (window == nil) {
            if (_verbose) {
                IOLog("PKB: couldn't get all requested I/O windows\n");
            }
            goto cleanup_and_fail;
        }
        [windowList addObject:window];

        windowObject = [window object];
        rangeResource = [portRangeList objectAt:i];
        range = [rangeResource range];
        [windowObject setMapWithSize:range.length systemAddress:range.base cardAddress:0];
        [windowObject setEnabled:YES];
        [windowObject set16Bit:*(unsigned char *)((char *)selectedConfig + 0x71) != 0];
    }

    [deviceDesc setResources:windowList forKey:"PCMCIA_WINDOW_LIST"];
    windowList = nil;

    /* Set card IRQ */
    if (_verbose) {
        IOLog("PKB: setting hardware IRQ to %d\n", irqNumber);
    }
    if (irqNumber != 0) {
        [socket setCardIRQ:irqNumber];
    }

    /* Set socket to I/O mode */
    if (_verbose) {
        IOLog("PKB: setting socket to I/O mode\n");
    }
    [socket setMemoryInterface:NO];

    /* Map and configure configuration option register */
    configRegAddrStr = (char *)[deviceDesc stringForKey:"PCMCIA_TPCC_RADR"];
    configRegOffset = strtol(configRegAddrStr, NULL, 0);

    /* Calculate offset within memory window */
    baseOffset = 0;
    if (_memoryLength <= configRegOffset) {
        baseOffset = _memoryLength * (configRegOffset / _memoryLength);
        configRegOffset = configRegOffset - baseOffset;
    }

    if (_verbose) {
        IOLog("PKB: trying for address base 0x%x\n", _memoryBase);
    }

    configRangeResource = [self findAndReserveRangeBase:_memoryBase
                                                 Length:_memoryLength
                                              AlignedTo:0x1000];
    if (configRangeResource == nil) {
        IOLog("PCMCIA: could not find a range to map config registers\n");
        goto cleanup_and_fail;
    }

    range = [configRangeResource range];
    configBase = range.base;

    if (_verbose) {
        IOLog("PKB: mapping config option reg: host 0x%x (card 0x%x)\n",
              configBase, baseOffset);
    }

    configWindow = [self mapAttributeMemory:range ForSocket:socket CardBase:baseOffset];
    if (configWindow == nil) {
        IOLog("PCMCIA: could not map attribute memory\n");
        [configRangeResource free];
        goto cleanup_and_fail;
    }

    /* Write configuration option register */
    configValue = *(unsigned int *)((char *)selectedConfig + 4);
    if (*(unsigned char *)((char *)selectedConfig + 0xf8) != 0 &&
        *(unsigned char *)((char *)selectedConfig + 0xfb) != 0) {
        configValue |= 0x40;
    }

    if (_verbose) {
        IOLog("PKB: writing %x to %x\n", configValue, configRegOffset + configBase);
    }

    configPtr = (unsigned char *)(configRegOffset + configBase);
    *configPtr = (unsigned char)configValue;

    /* Enable audio if requested */
    audioEnableStr = [[deviceDesc configTable] valueForStringKey:"Enable Audio"];
    audioEnable = (audioEnableStr != nil);
    if (audioEnable) {
        configPtr[2] |= 0x08;
    }

    /* Clean up config mapping */
    [self freeMemoryWindowElement:configWindow];
    [configRangeResource free];

    /* Wait for socket to be ready */
    waitResult = _waitForSocketReady(socket);
    if (waitResult == 0) {
        IOLog("PCMCIA: configureDriver: waitForSocketReady failed\n");
    }

    /* Create socket list with one element */
    socketList = [[List alloc] initCount:1];
    socketElement = [[_PCMCIAPoolElement alloc] initWithPCMCIAPool:nil object:socket];
    [socketList addObject:socketElement];
    [deviceDesc setResources:socketList forKey:"PCMCIA_SOCKET_LIST"];

    return YES;

cleanup_and_fail:
    if (_verbose) {
        IOLog("PKB: card could not be configured\n");
    }

    if (!userSuppliedPorts && portRangeList != nil) {
        [[portRangeList freeObjects:@selector(free)] free];
    }
    if (!userSuppliedIRQ && irqList != nil) {
        [[irqList freeObjects:@selector(free)] free];
    }
    if (windowList != nil) {
        [[windowList freeObjects:@selector(free)] free];
    }

    return NO;
}

/*
 * Configure socket with driver table
 */
- (BOOL)configureSocket:socket withDriverTable:table
{
    SocketInfo *socketInfo;
    id deviceDesc;
    id tupleListCopy;
    BOOL allocated;
    BOOL configured;
    char *driverName;
    BOOL probed;
    IORange range;

    /* Get socket info */
    socketInfo = (SocketInfo *)[_socketMap valueForKey:socket];

    /* Create device description from config table */
    deviceDesc = [[KernDeviceDescription alloc] initFromConfigTable:table];
    if (deviceDesc == nil) {
        IOLog("PCMCIA: could not allocate resources for driver\n");
        return NO;
    }

    /* Copy tuple list from socket info */
    tupleListCopy = [self copyTupleList:socketInfo->tupleList];
    if (tupleListCopy == nil) {
        IOLog("PCMCIA: could not allocate copy of tupleList\n");
        [deviceDesc free];
        return NO;
    }

    /* Allocate resources for description */
    if (_verbose) {
        IOLog("PKB: Allocating resources for description..\n");
    }

    allocated = [self allocateResourcesForDeviceDescription:deviceDesc];
    if (!allocated) {
        driverName = (char *)[table valueForStringKey:"Driver Name"];
        if (driverName == NULL) {
            driverName = "<unknown>";
        }
        IOLog("PCMCIA: could not allocate static resources for driver %s\n", driverName);
        if (driverName != NULL && strcmp(driverName, "<unknown>") != 0) {
            [table freeString:driverName];
        }
        [[tupleListCopy freeObjects:@selector(free)] free];
        [deviceDesc free];
        return NO;
    }

    /* Configure socket with description */
    if (_verbose) {
        IOLog("PKB: Configuring socket..\n");
    }

    configured = [self configureSocket:socket withDescription:deviceDesc];
    if (!configured) {
        if (_verbose) {
            IOLog("PKB: failed to configure\n");
        }
        [[tupleListCopy freeObjects:@selector(free)] free];
        [deviceDesc free];
        return NO;
    }

    /* Set tuple list as a resource */
    [deviceDesc setResources:tupleListCopy forKey:"PCMCIA_TUPLE_LIST"];

    /* Probe device with driver table */
    probed = [self probeDevice:table withDescription:deviceDesc];

    /* Free cached memory range resource if it exists */
    if (_memoryRangeResource != nil) {
        if (_verbose) {
            range = [_memoryRangeResource range];
            IOLog("PKB: freeing range 0x%x(0x%x)\n", range.base, range.length);
        }
        [_memoryRangeResource free];
        _memoryRangeResource = nil;
    }

    if (!probed) {
        if (_verbose) {
            IOLog("PKB: configure/probe failed\n");
        }
        [deviceDesc free];
        return NO;
    }

    return YES;
}

/*
 * Copy tuple list
 */
- copyTupleList:tupleList
{
    id newList;
    int count;
    int i;
    id tuple;
    unsigned int length;
    void *data;
    id newTuple;
    extern id PCMCIATuple;

    /* Create new list */
    newList = [[List alloc] init];
    if (newList == nil) {
        return nil;
    }

    /* Copy each tuple */
    count = [tupleList count];
    for (i = 0; i < count; i++) {
        tuple = [tupleList objectAt:i];
        length = [tuple length];
        data = [tuple data];

        /* Create new tuple from data */
        newTuple = [[PCMCIATuple alloc] initFromData:data length:length];
        if (newTuple != nil) {
            [newList addObject:newTuple];
        }
    }

    return newList;
}

/*
 * Get tuple list from socket at mapped address
 */
- tupleListFromSocket:socket mappedAddress:(unsigned int)address
{
    id tupleList;
    unsigned char *attrMem;
    unsigned char *endAddr;
    char tupleCode;
    unsigned char tupleLength;
    unsigned int actualLength;
    unsigned int i;
    char tupleData[260];
    id tuple;
    int waitResult;
    int count;


    if (_verbose) {
        IOLog("PKB: Scanning for tuples\n");
    }

    /* Create tuple list */
    tupleList = [[List alloc] init];

    /* Scan attribute memory (0x2000 bytes = 8KB) */
    attrMem = (unsigned char *)address;
    endAddr = (unsigned char *)(address + 0x2000);

    while (attrMem < endAddr) {
        /* Wait for socket to be ready */
        waitResult = _waitForSocketReady(socket);
        if (waitResult == 0) {
            IOLog("PCMCIA: tupleListFromSocket: not ready 1\n");
            break;
        }

        /* Read tuple code (at offset 0) and length (at offset 2) */
        tupleCode = attrMem[0];
        tupleLength = attrMem[2];

        if (_verbose) {
            IOLog("PKB: Scanning at %x, tuple '%x', length %d\n",
                  (unsigned int)attrMem, tupleCode, tupleLength);
        }

        /* Check for end of chain marker */
        if (tupleCode == 0xFF) {
            break;
        }

        /* Wait for socket ready before reading data */
        waitResult = _waitForSocketReady(socket);
        if (waitResult == 0) {
            IOLog("PCMCIA: tupleListFromSocket: not ready 2\n");
            break;
        }

        /* Calculate actual length (0 means 256) */
        actualLength = tupleLength;
        if (actualLength == 0) {
            actualLength = 0x100;
        }

        /* Add 2 for tuple code and length bytes */
        actualLength += 2;

        /* Copy tuple data from attribute memory */
        /* Attribute memory has data at even addresses only (every 2 bytes) */
        for (i = 0; i < actualLength; i++) {
            waitResult = _waitForSocketReady(socket);
            if (waitResult == 0) {
                IOLog("PCMCIA: tupleListFromSocket: not ready 3\n");
                goto done;
            }
            tupleData[i] = attrMem[i * 2];
        }

        /* Create tuple from data */
        tuple = [[PCMCIATuple alloc] initFromData:tupleData length:actualLength];
        if (tuple != nil) {
            [tupleList addObject:tuple];
        }

        /* Move to next tuple (attribute memory is at even addresses) */
        attrMem += actualLength * 2;
    }

done:
    /* Check if we found any tuples */
    count = [tupleList count];
    if (count == 0) {
        [tupleList free];
        return nil;
    }

    return tupleList;
}

/*
 * Parse tuple into device description
 */
- (BOOL)parseTuple:tuple intoDeviceDescription:deviceDesc
{
    // TODO: Implement based on decompiled code
    return NO;
}

/*
 * Enable socket
 */
- (BOOL)enableSocket:socket
{
    int retries;
    char status;
    unsigned int socketNum;

    /* Assert reset */
    [socket setCardReset:YES];

    /* Read current Vcc power setting */
    [socket cardVccPower];

    /* Turn on power supplies */
    [socket setCardVccPower:1];
    [socket setCardVppPower:1];

    /* Wait for power to stabilize (1500ms) */
    IOSleep(1500);

    /* Enable auto power management and card interface */
    [socket setCardAutoPower:1];
    [socket setCardEnabled:1];

    /* Wait for interface to settle */
    IOSleep(300);

    /* De-assert reset */
    [socket setCardReset:NO];

    /* Wait for card to start responding */
    IOSleep(100);

    /* Wait for card to become ready (check bit 7 of status) */
    retries = 100;
    do {
        status = (char)[socket status];
        if (status < 0) {
            /* Card is ready (bit 7 set) */
            IOSleep(20);
            break;
        }
        IOSleep(20);
        retries--;
    } while (retries != 0);

    if (retries == 0) {
        socketNum = [socket socketNumber];
        IOLog("PCMCIA: Card in socket %d did not become ready\n", socketNum);
    }

    return (retries != 0);
}

/*
 * Disable socket
 */
- (BOOL)disableSocket:socket
{
    /* Disable card */
    [socket setCardEnabled:NO];

    /* Turn off power supplies */
    [socket setCardVccPower:0];
    [socket setCardVppPower:0];
    [socket setCardAutoPower:0];

    /* Wait for power to settle */
    IOSleep(10);

    /* Assert reset */
    [socket setCardReset:YES];

    /* Wait for reset to take effect */
    IOSleep(100);

    return YES;
}

/*
 * Free memory window element
 */
- freeMemoryWindowElement:element
{
    id window;

    /* Get the window object from the pool element */
    window = [element object];

    /* Disable the window */
    [window setEnabled:NO];

    /* Free the pool element (auto-releases window back to pool) */
    [element free];

    return self;
}

/*
 * Map attribute memory
 */
- mapAttributeMemory:(IORange)range
           ForSocket:socket
            CardBase:(unsigned int)cardBase
{
    id windowElement;
    id window;

    /* Map memory using standard memory mapping */
    windowElement = [self mapMemory:range ForSocket:socket ToCardAddress:cardBase];

    if (windowElement == nil) {
        return nil;
    }

    /* Get the window object and set attribute memory mode */
    window = [windowElement object];
    [window setAttributeMemory:YES];

    return windowElement;
}

/*
 * Map memory to card address
 */
- mapMemory:(IORange)range
  ForSocket:socket
ToCardAddress:(unsigned int)cardAddr
{
    id windowElement;
    id window;

    /* Allocate a memory window for this socket */
    windowElement = [self allocMemoryWindowForSocket:socket];

    if (windowElement == nil) {
        if (_verbose) {
            IOLog("PKB: couldn't get a memory window!\n");
        }
        return nil;
    }

    /* Get the window object */
    window = [windowElement object];

    /* Configure the window */
    [window setEnabled:NO];
    [window setMemoryInterface:YES];
    [window setAttributeMemory:NO];
    [window setMapWithSize:range.length systemAddress:range.base cardAddress:cardAddr];
    [window setEnabled:YES];

    return windowElement;
}

/*
 * Probe device with description
 */
- (BOOL)probeDevice:device withDescription:deviceDesc
{
    char *classNames;
    char *serverName;
    char *className;
    char *p;
    int classListLength;
    int classesLoaded;
    id driverClass;
    id kernDevice;
    id pcmciaDesc;
    int devicePort;
    BOOL respondsToProbe;
    int result;

    classesLoaded = 0;
    kernDevice = nil;
    pcmciaDesc = nil;

    /* Get class names from config table */
    classNames = (char *)[device valueForStringKey:"Class Names"];
    if (classNames == NULL) {
        classNames = (char *)[device valueForStringKey:"Driver Name"];
    }

    /* Calculate string length and make a copy */
    classListLength = strlen(classNames);

    if (_verbose) {
        IOLog("PKB: class list '%s'\n", classNames);
    }

    /* Get server name */
    serverName = (char *)[device valueForStringKey:"Server Name"];

    /* Parse and load each class */
    p = classNames;
    while (p != NULL && *p != '\0') {
        /* Find end of current class name */
        className = p;
        while (*p != '\0' && *p != ' ' && *p != '\t') {
            p++;
        }

        /* Null-terminate class name */
        if (*p != '\0') {
            *p = '\0';
            p++;
        }

        /* Skip whitespace */
        while (*p == ' ' || *p == '\t') {
            p++;
            if (*p == '\0') break;
        }

        /* Get the driver class */
        driverClass = objc_getClass(className);
        if (driverClass == nil) {
            if (_verbose) {
                IOLog("PKB: driver class '%s' was not loaded\n", className);
                if (serverName != NULL) {
                    IOLog("PKB: Driver %s could not be configured\n", serverName);
                }
            }
            goto cleanup_and_fail;
        }

        /* Create KernDevice */
        kernDevice = [[KernDevice alloc] initWithDeviceDescription:deviceDesc];
        if (kernDevice == nil) {
            if (_verbose) {
                IOLog("PKB:probeDriver: initFromDeviceDescription failed for class %s\n",
                      className);
            }
            goto cleanup_and_fail;
        }

        /* Set device on description */
        [deviceDesc setDevice:kernDevice];

        /* Create IOPCMCIADeviceDescription */
        pcmciaDesc = [[IOPCMCIADeviceDescription alloc] _initWithDelegate:deviceDesc];
        if (pcmciaDesc == nil) {
            if (_verbose) {
                IOLog("PKB: aborting probe\n");
            }
            goto cleanup_and_fail;
        }

        /* Create device port */
        devicePort = _create_dev_port(kernDevice);
        [pcmciaDesc setDevicePort:devicePort];

        /* Check if class responds to probe: */
        respondsToProbe = [driverClass respondsTo:@selector(probe:)];
        if (!respondsToProbe) {
            if (_verbose) {
                IOLog("PKB: configureDriver: Class %s does not respond to probe:\n", className);
            }
        } else {
            /* Add loaded class */
            if (_verbose) {
                IOLog("PKB: adding loaded class '%s'\n", className);
            }

            result = [IODevice addLoadedClass:driverClass description:pcmciaDesc];
            if (result == 0) {
                classesLoaded++;
                if (_verbose) {
                    IOLog("PKB: addLoadedClass returns success\n");
                }
            }
        }
    }

    /* Done probing */
    if (_verbose) {
        IOLog("PKB: all done probing\n");
    }

    /* Cleanup */
    if (classListLength != 0) {
        IOFree(classNames, classListLength);
    }
    if (serverName != NULL) {
        [device freeString:serverName];
    }

    if (classesLoaded == 0) {
        if (kernDevice != nil) {
            [kernDevice free];
        }
        if (pcmciaDesc != nil) {
            [pcmciaDesc free];
        }
        if (_verbose) {
            IOLog("PKB: no classes loaded, returning no\n");
        }
        return NO;
    }

    return YES;

cleanup_and_fail:
    if (classListLength != 0) {
        IOFree(classNames, classListLength);
    }
    if (serverName != NULL) {
        [device freeString:serverName];
    }
    if (kernDevice != nil) {
        [kernDevice free];
    }
    if (pcmciaDesc != nil) {
        [pcmciaDesc free];
    }
    return NO;
}

/*
 * Test IDs for adapter and socket
 */
- (BOOL)testIDs:idList ForAdapter:adapter andSocket:socket
{
    int adapterIndex;
    int socketIndex;
    unsigned int adapterCount;
    id adapterObj;
    id socketList;
    unsigned int socketCount;
    unsigned int i;
    id socketObj;
    unsigned int socketNum;
    SocketInfo *socketInfo;
    char *idString;
    BOOL matched;
    id tempID;

    adapterIndex = (int)adapter;
    socketIndex = (int)socket;
    socketInfo = NULL;

    /* Validate adapter index */
    adapterCount = [_adapters count];
    if (adapterIndex > adapterCount) {
        return NO;
    }

    /* Get adapter and its sockets */
    adapterObj = [_adapters objectAt:adapterIndex];
    socketList = [adapterObj sockets];

    /* Validate socket index */
    socketCount = [socketList count];
    if (socketIndex > socketCount) {
        return NO;
    }

    /* Find socket by socket number */
    for (i = 0; i < socketCount; i++) {
        socketObj = [socketList objectAt:i];
        socketNum = [socketObj socketNumber];
        if (socketIndex == socketNum) {
            socketInfo = (SocketInfo *)[_socketMap valueForKey:socketObj];
            break;
        }
    }

    /* Check if socket has a card ID */
    if (socketInfo == NULL || socketInfo->cardID == nil) {
        return NO;
    }

    /* Test IDs */
    idString = (char *)idList;
    matched = NO;

    if (idString == NULL) {
        return NO;
    }

    /* Parse and match all IDs in the string */
    while (idString != NULL && *idString != '\0') {
        /* Create PCMCIAid from ID string */
        tempID = [[PCMCIAid alloc] initFromIDString:&idString];
        if (tempID == nil) {
            return matched;
        }

        /* Check if this ID matches the card's ID */
        if ([tempID matchesID:socketInfo->cardID]) {
            matched = YES;
        }

        /* Free temporary ID */
        [tempID free];

        /* Check if we've reached the end */
        if (idString == NULL || *idString == '\0') {
            return matched;
        }
    }

    return matched;
}

/*
 * Check if entry matches user I/O ports
 */
- (BOOL)entry:entry matchesUserIOPorts:(const char *)portList
{
    int numRanges;
    int userCount;
    int addressLines;
    unsigned int alignment;
    id rangeResource;
    IORange range;
    BOOL matched;
    unsigned int i;
    unsigned int *rangesPtr;
    unsigned int entryBase, entryLength;
    IORange entryRange;

    matched = NO;

    /* Get number of ranges from entry (offset 0x74) */
    numRanges = *(int *)((char *)entry + 0x74);

    if (numRanges == 0) {
        /* Single range with alignment based on address lines */
        userCount = [(id)portList count];
        if (userCount != 1) {
            if (_verbose) {
                IOLog("PKB: port range count must be 1\n");
            }
            goto done;
        }

        rangeResource = [(id)portList objectAt:0];
        range = [rangeResource range];

        /* Check address lines (offset 0x6c) */
        addressLines = *(int *)((char *)entry + 0x6c);
        if (addressLines == 0) {
            /* Decodes all address lines - any range works */
            matched = YES;
        } else {
            /* Check if length matches alignment requirement */
            alignment = 1 << (addressLines & 0x1f);
            if (range.length == alignment) {
                matched = YES;
            } else {
                if (_verbose) {
                    IOLog("PKB: port range number of lines don't agree\n");
                }
            }
        }
    } else {
        /* Multiple ranges - must match exactly */
        userCount = [(id)portList count];
        if (numRanges != userCount) {
            if (_verbose) {
                IOLog("PKB: port range counts differ\n");
            }
            goto done;
        }

        /* Check each range matches */
        matched = YES;
        rangesPtr = (unsigned int *)((char *)entry + 0x78);
        for (i = 0; i < numRanges; i++) {
            entryBase = rangesPtr[0];
            entryLength = rangesPtr[1];

            rangeResource = [(id)portList objectAt:i];
            range = [rangeResource range];

            if (range.base != entryBase || range.length != entryLength) {
                if (_verbose) {
                    IOLog("PKB: user range doesn't match card range\n");
                }
                matched = NO;
                break;
            }

            rangesPtr += 2;  /* Move to next range (8 bytes) */
        }
    }

done:
    if (matched && _verbose) {
        IOLog("PKB: card entry %d matches user port ranges.\n",
              *(unsigned int *)((char *)entry + 4));
    }

    return matched;
}

/*
 * Reserve I/O ports using entry
 */
- (BOOL)reserveIOPorts:(const char *)portList UsingEntry:entry
{
    id eisaBus;
    id ioPortsResource;
    int numRanges;
    unsigned int i;
    unsigned int *rangesPtr;
    unsigned int base, length;
    IORange range;
    id rangeResource;

    /* Get EISA bus and I/O Ports resource */
    eisaBus = [KernBus lookupBusInstanceWithName:"EISA" busId:0];
    ioPortsResource = [eisaBus _lookupResourceWithKey:"I/O Ports"];

    if (_verbose) {
        IOLog("PKB: looking for a suitable config entry in the tuples..\n");
    }

    /* Check for invalid config (decodes lines but no ranges) */
    if (*(int *)((char *)entry + 8) == 1 && *(int *)((char *)entry + 0x74) == 0) {
        if (_verbose) {
            IOLog("PKB: config entry decodes address lines but has no port ranges.\n");
        }
        return NO;
    }

    /* Get number of ranges */
    numRanges = *(int *)((char *)entry + 0x74);

    if (numRanges != 0) {
        /* Reserve each range */
        rangesPtr = (unsigned int *)((char *)entry + 0x78);
        for (i = 0; i < numRanges; i++) {
            base = rangesPtr[0];
            length = rangesPtr[1];

            range.base = base;
            range.length = length;

            rangeResource = [ioPortsResource reserveRange:range];
            if (rangeResource == nil) {
                /* Reservation failed - free all previously allocated ranges */
                [(id)portList freeObjects:@selector(free)];
                return NO;
            }

            /* Add to port range list */
            [(id)portList addObject:rangeResource];

            rangesPtr += 2;  /* Move to next range (8 bytes) */
        }
    }

    if (_verbose) {
        IOLog("PKB: entry %d seems to be good\n", *(unsigned int *)((char *)entry + 4));
    }

    return YES;
}

/*
 * Find and reserve memory range
 */
- findAndReserveRangeBase:(unsigned int)base
                   Length:(unsigned int)length
                AlignedTo:(unsigned int)alignment
{
    unsigned int alignmentBlocks;
    unsigned int startBlock;
    unsigned int currentBlock;
    unsigned int consecutiveBlocks;
    unsigned int requiredBlocks;
    unsigned int word, bit;
    id eisaBus;
    id memMapsResource;
    unsigned int rangeBase;
    id rangeResource;
    extern unsigned int _biosBitmap[];

    /* Convert alignment to 2KB blocks (shift by 11 bits) */
    alignmentBlocks = alignment >> 11;

    /* Calculate starting block, rounded up to alignment */
    startBlock = (((alignmentBlocks - 1) + ((base - 0xc0000) >> 11)) / alignmentBlocks) * alignmentBlocks;

    currentBlock = startBlock;
    consecutiveBlocks = 1;
    requiredBlocks = length >> 11;

    /* Search for consecutive free blocks in the bitmap */
    while (1) {
        /* Check if we've exceeded the range (95 blocks max = 0xC0000 to 0xEF800) */
        if (currentBlock > 0x5f) {
            return nil;
        }

        /* Check if this block is free in the bitmap */
        word = currentBlock >> 5;  /* Which 32-bit word */
        bit = currentBlock & 0x1f;  /* Which bit in that word */

        if ((_biosBitmap[word] & (1 << bit)) != 0) {
            /* Block is used - skip to next aligned position */
            currentBlock = ((currentBlock + alignmentBlocks) / alignmentBlocks) * alignmentBlocks;
            consecutiveBlocks = 1;
            startBlock = currentBlock;
            continue;
        }

        /* Block is free - check if we have enough consecutive blocks */
        if (consecutiveBlocks == requiredBlocks) {
            /* Found enough consecutive free blocks - reserve the range */
            IORange range;

            eisaBus = [KernBus lookupBusInstanceWithName:"EISA" busId:0];
            memMapsResource = [eisaBus _lookupResourceWithKey:"Memory Maps"];

            /* Convert block number back to byte address */
            rangeBase = startBlock * 0x800 + 0xc0000;
            range.base = rangeBase;
            range.length = length;

            rangeResource = [memMapsResource reserveRange:range];

            return rangeResource;
        }

        /* Continue to next block */
        consecutiveBlocks++;
        currentBlock++;
    }

    return nil;
}

@end
