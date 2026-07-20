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
 * PCMCIAKernBus Private Methods
 */

#import "PCMCIAKernBus.h"

/* Forward declarations that a secondary PCMCIA driver would have to hook into the bus driver */
@interface Object(PCMCIASocketWindowMethods)
- (id)windows;
- (void)setStatusChangeMask:(unsigned int)mask;
- (unsigned int)socketNumber;
- (unsigned int)status;
@end

@interface Object(ListFreeMethods)
- (id)freeObjects:(SEL)selector;
@end

@interface PCMCIAKernBus (Private)

/* Resource allocation */
- allocateResourcesForDeviceDescription:descr;
- allocateSharedMemory:(unsigned int)size
        ForDescription:deviceDesc
             AndSocket:socket;

/* Configuration */
- (BOOL)configTable:table matchesSocket:socket;
- (BOOL)configureDriverWithTable:table;
- (BOOL)configureSocket:socket;
- (BOOL)configureSocket:socket withDescription:deviceDesc;
- (BOOL)configureSocket:socket withDriverTable:table;

/* Tuple management */
- copyTupleList:tupleList;
- tupleListFromSocket:socket mappedAddress:(unsigned int)address;
- (BOOL)parseTuple:tuple intoDeviceDescription:deviceDesc;

/* Socket control */
- (BOOL)enableSocket:socket;
- (BOOL)disableSocket:socket;

/* Memory window management */
- freeMemoryWindowElement:element;
- mapAttributeMemory:(Range)range
           ForSocket:socket
            CardBase:(unsigned int)cardBase;
- mapMemory:(Range)range
  ForSocket:socket
ToCardAddress:(unsigned int)cardAddr;

/* Device probing */
- (BOOL)probeDevice:device withDescription:deviceDesc;
- (BOOL)testIDs:idList ForAdapter:adapter andSocket:socket;

/* I/O port management */
- (BOOL)entry:entry matchesUserIOPorts:(const char *)portString;
- (BOOL)reserveIOPorts:(const char *)portString UsingEntry:entry;

/* Range finding */
- findAndReserveRangeBase:(unsigned int)base
                   Length:(unsigned int)length
                AlignedTo:(unsigned int)alignment;

@end
