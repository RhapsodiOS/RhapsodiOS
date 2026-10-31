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
 * PCMCIA Tuple Type Subclasses Implementation
 *
 * These classes inherit all functionality from PCMCIATuple.
 * No additional methods are implemented.
 */

#import "PCMCIATupleTypes.h"

/* NULL tuple (0x00) */
@implementation PCMCIATuple_NULL
@end

/* DEVICE tuple (0x01) */
@implementation PCMCIATuple_DEVICE
@end

/* CHECKSUM tuple (0x10) */
@implementation PCMCIATuple_CHECKSUM
@end

/* LONGLINK_A tuple (0x11) */
@implementation PCMCIATuple_LONGLINK_A
@end

/* LONGLINK_C tuple (0x12) */
@implementation PCMCIATuple_LONGLINK_C
@end

/* LINKTARGET tuple (0x13) */
@implementation PCMCIATuple_LINKTARGET
@end

/* NO_LINK tuple (0x14) */
@implementation PCMCIATuple_NO_LINK
@end

/* VERS_1 tuple (0x15) */
@implementation PCMCIATuple_VERS_1
@end

/* ALTSTR tuple (0x16) */
@implementation PCMCIATuple_ALTSTR
@end

/* DEVICE_A tuple (0x17) */
@implementation PCMCIATuple_DEVICE_A
@end

/* JEDEC_C tuple (0x18) */
@implementation PCMCIATuple_JEDEC_C
@end

/* JEDEC_A tuple (0x19) */
@implementation PCMCIATuple_JEDEC_A
@end

/* CONFIG tuple (0x1A) */
@implementation PCMCIATuple_CONFIG
@end

/* CFTABLE_ENTRY tuple (0x1B) */
@implementation PCMCIATuple_CFTABLE_ENTRY
@end

/* DEVICE_OC tuple (0x1C) */
@implementation PCMCIATuple_DEVICE_OC
@end

/* DEVICE_OA tuple (0x1D) */
@implementation PCMCIATuple_DEVICE_OA
@end

/* DEVICE_GEO tuple (0x1E) */
@implementation PCMCIATuple_DEVICE_GEO
@end

/* DEVICE_GEO_A tuple (0x1F) */
@implementation PCMCIATuple_DEVICE_GEO_A
@end

/* MANFID tuple (0x20) */
@implementation PCMCIATuple_MANFID
@end

/* FUNCID tuple (0x21) */
@implementation PCMCIATuple_FUNCID
@end

/* FUNCE tuple (0x22) */
@implementation PCMCIATuple_FUNCE
@end

/* SWIL tuple (0x23) */
@implementation PCMCIATuple_SWIL
@end

/* VERS_2 tuple (0x40) */
@implementation PCMCIATuple_VERS_2
@end

/* FORMAT tuple (0x41) */
@implementation PCMCIATuple_FORMAT
@end

/* GEOMETRY tuple (0x42) */
@implementation PCMCIATuple_GEOMETRY
@end

/* BYTEORDER tuple (0x43) */
@implementation PCMCIATuple_BYTEORDER
@end

/* DATE tuple (0x44) */
@implementation PCMCIATuple_DATE
@end

/* BATTERY tuple (0x45) */
@implementation PCMCIATuple_BATTERY
@end

/* ORG tuple (0x46) */
@implementation PCMCIATuple_ORG
@end

/* END tuple (0xFF) */
@implementation PCMCIATuple_END
@end
