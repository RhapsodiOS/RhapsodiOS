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
 * PCMCIA Socket Implementation
 */

#import <driverkit/i386/PCMCIASocket.h>
#import <driverkit/KernLock.h>
#import <kernserv/i386/spl.h>

@implementation PCMCIASocket

- initWithSocketNumber:(int)socketNum pool:pool
{
    [super init];

    _socketNumber = socketNum;
    _pool = pool;
    _memoryInterface = NO;

    _lock = [[KernLock alloc] initWithLevel:IPLHIGH];

    return self;
}

- free
{
    if (_lock) {
        [_lock free];
        _lock = nil;
    }

    return [super free];
}

/* Socket configuration */
- (void)setMemoryInterface:(BOOL)memInterface
{
    [_lock acquire];
    _memoryInterface = memInterface;
    [_lock release];
}

- (BOOL)memoryInterface
{
    BOOL result;
    [_lock acquire];
    result = _memoryInterface;
    [_lock release];
    return result;
}

- (int)socketNumber
{
    return _socketNumber;
}

- pool
{
    return _pool;
}

/* Element interface */
- object
{
    return self;
}

@end
