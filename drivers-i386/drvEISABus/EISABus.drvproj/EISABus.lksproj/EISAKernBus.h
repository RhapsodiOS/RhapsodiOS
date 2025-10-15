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

@class EISAKernBusInterrupt;

/*
 * EISAKernBus - EISA Bus driver conforming to KernBus protocol
 */
@interface EISAKernBus : KernBus
{
    @private
    void *_eisaData;
    int _slotCount;
    BOOL _initialized;
    BOOL _inDependentSection;
    int _dependentPriority;
    id _pnpResourceTable;  /* Array/table of discovered PnP resources */
    id _niosTable;         /* NIOS (Non-Invasive Override String) table */
}

/*
 * Bus lifecycle methods
 */
+ initialize;
- init;
- free;

/*
 * Slot management
 */
- (int)getEISASlotNumber:(int)slot;
- (BOOL)testSlot:(int)slot;

/*
 * EISA slot information (required by IOEISADeviceDescription)
 */
- (IOReturn)getEISASlotNumber:(unsigned int *)slotNum
                       slotID:(unsigned long *)slotID
      usingDeviceDescription:deviceDescription;

/*
 * Resource management (KernBus protocol)
 */
- (const char **)resourceNames;

@end

/*
 * EISAKernBus Private Category for Plug and Play Support
 */
@interface EISAKernBus(PlugAndPlayPrivate)

- (void)initializeNIOSTable;
- (void *)pnpReadConfig:(int)length forCard:(int)csn;
- (void)pnpSetResourcesForDescription:(id)description errorStrings:(void *)errorStrings;
- (BOOL)pnpBios_setDeviceTable:(void *)table cardIndex:(int)index;
- (unsigned int)pnpBios_computeChecksum:(void *)data readIsolationBit:(BOOL)bit;
- (void)initializePnPBIOS:(void *)configTable;
- (void)deactivateLogicalDevices:(id)configTable;
- (BOOL)testConfig:(void *)config forCard:(int)csn;
- (BOOL)registerPnPResource:(int)instance
                        csn:(int)csn
              logicalDevice:(int)logicalDev
                   vendorID:(unsigned int)vendorID
                   deviceID:(unsigned int)deviceID
               resourceData:(void *)resourceData
             resourceLength:(int)resourceLength;
- (BOOL)unregisterPnPResource:(int)instance;
- (void *)lookForPnPResource:(int)instance;
- (void)findCardWithID:(int)serial LogicalDevice:(id)logicalDevice;
- (void)initializePnP:(id)configTable;
- (void)getConfigForCard:(id)logicalDevice;
- (void)allocateResources:(id)resources Using:(id)object;
- (void)setDepStart;
- (void)setDepEnd;
- (void)setDependentPriority:(int)priority;
- (BOOL)inDependentSection;

@end

#endif /* _EISAKERNBUS_H_ */
