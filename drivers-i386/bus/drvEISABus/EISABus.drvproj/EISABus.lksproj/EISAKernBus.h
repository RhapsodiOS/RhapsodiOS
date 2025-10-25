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
 * EISAKernBus.h
 * EISA Kernel Bus Header
 */

#ifndef _EISAKERNBUS_H_
#define _EISAKERNBUS_H_

#import <driverkit/KernBus.h>

/*
 * EISAKernBus - EISA Bus driver conforming to KernBus protocol
 */
@interface EISAKernBus : KernBus
{
    @private
    void *_eisaData;
    int _slotCount;
    BOOL _initialized;
}

/*
 * Bus lifecycle methods
 */
- init;
- free;

/*
 * EISA slot information (required by IOEISADeviceDescription)
 */
- (IOReturn)getEISASlotNumber:(unsigned int *)slotNum
                       slotID:(unsigned long *)slotID
      usingDeviceDescription:deviceDescription;

/*
 * Slot testing
 */
- (BOOL)testIDs:(const char *)ids slot:(unsigned int)slot;

/*
 * Resource management (KernBus protocol)
 */
- (const char **)resourceNames;
- allocateResourcesForDeviceDescription:descr;

@end

#endif /* _EISAKERNBUS_H_ */
