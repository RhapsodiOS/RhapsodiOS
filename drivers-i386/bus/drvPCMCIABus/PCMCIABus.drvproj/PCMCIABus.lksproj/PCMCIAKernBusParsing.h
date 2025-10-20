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
 * PCMCIAKernBus Parsing Category
 *
 * Methods for parsing PCMCIA tuples and allocating resources
 * from device descriptions.
 */

#ifndef _DRIVERKIT_I386_PCMCIAKERNBUSPARSING_H_
#define _DRIVERKIT_I386_PCMCIAKERNBUSPARSING_H_

#import "PCMCIAKernBus.h"

#ifdef DRIVER_PRIVATE

@interface PCMCIAKernBus(Parsing)

/*
 * Allocate resources for a device description by parsing tuple list
 * Returns the description if successful, nil otherwise
 */
- _allocResourcesForDescription:description fromTupleList:tupleList;

/*
 * Parse a single tuple into device description
 * Extracts resource information from the tuple and adds it to the description
 */
- (void)_parseTuple:tuple intoDeviceDescription:description;

@end

#endif /* DRIVER_PRIVATE */

#endif /* _DRIVERKIT_I386_PCMCIAKERNBUSPARSING_H_ */
