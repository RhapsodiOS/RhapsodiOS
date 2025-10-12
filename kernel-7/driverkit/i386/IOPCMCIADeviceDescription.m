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
 * Copyright (c) 1994 NeXT Computer, Inc.
 *
 * Kernel-side PCMCIA device description class.
 */

#define KERNEL_PRIVATE 1

#import <driverkit/i386/IOPCMCIADeviceDescription.h>
#import <driverkit/i386/IOEISADeviceDescription.h>
#import <driverkit/i386/PCMCIAKernBus.h>
#import <driverkit/i386/PCMCIAPool.h>
#import <driverkit/i386/PCMCIASocket.h>
#import <driverkit/i386/PCMCIAWindow.h>
#import <driverkit/IOConfigTable.h>
#import <objc/List.h>
#import <libkern/libkern.h>

@implementation IOPCMCIADeviceDescription

- initFromConfigTable:table socket:(int)socket tupleList:tuples
{
    id pool;
    id socketObject;

    [super initFromConfigTable:table];

    _socket = socket;
    _tupleList = tuples;

    /* Create socket list with the socket for this device */
    _socketList = [[List alloc] init];

    /* Get the PCMCIAPool for this socket and retrieve its socket object */
    id busInstance = [KernBus lookupBusInstanceWithName:"PCMCIA" busId:0];
    if (busInstance) {
        pool = [busInstance socketAtIndex:socket];
        if (pool) {
            socketObject = [pool socketObject];
            if (socketObject) {
                [_socketList addObject:socketObject];
            }
        }
    }

    /* Create empty window list - windows are allocated on demand */
    _windowList = [[List alloc] init];

    return self;
}

- free
{
    /* Don't free tuple list - it's owned by PCMCIAPool */
    _tupleList = nil;

    /* Free window objects in the list */
    if (_windowList) {
        [_windowList freeObjects];
        [_windowList free];
        _windowList = nil;
    }

    /* Don't free socket objects - they're owned by PCMCIAPool */
    if (_socketList) {
        [_socketList free];
        _socketList = nil;
    }

    return [super free];
}

- (int)socket
{
    return _socket;
}

- tupleList
{
    return _tupleList;
}

- socketList
{
    return _socketList;
}

- windowList
{
    return _windowList;
}

/*
 * Override resourcesForKey to provide PCMCIA resource lists
 */
- resourcesForKey:(const char *)key
{
    if (strcmp(key, PCMCIA_TUPLE_LIST) == 0) {
        return _tupleList;
    }

    if (strcmp(key, PCMCIA_SOCKET_LIST) == 0) {
        return _socketList;
    }

    if (strcmp(key, PCMCIA_WINDOW_LIST) == 0) {
        return _windowList;
    }

    return [super resourcesForKey:key];
}

@end
