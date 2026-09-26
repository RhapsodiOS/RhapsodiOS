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
 * PCMCIA Tuple Type Subclasses
 *
 * These classes represent specific PCMCIA tuple types.
 * They inherit all functionality from PCMCIATuple and exist
 * primarily for type identification and future extensibility.
 */

#ifndef _DRIVERKIT_I386_PCMCIATUPLETYPES_H_
#define _DRIVERKIT_I386_PCMCIATUPLETYPES_H_

#import "PCMCIATuple.h"

#ifdef DRIVER_PRIVATE

/* NULL tuple (0x00) - Null/filler */
@interface PCMCIATuple_NULL : PCMCIATuple
@end

/* DEVICE tuple (0x01) - Device information */
@interface PCMCIATuple_DEVICE : PCMCIATuple
@end

/* CHECKSUM tuple (0x10) - Checksum control */
@interface PCMCIATuple_CHECKSUM : PCMCIATuple
@end

/* LONGLINK_A tuple (0x11) - Long link to attribute memory */
@interface PCMCIATuple_LONGLINK_A : PCMCIATuple
@end

/* LONGLINK_C tuple (0x12) - Long link to common memory */
@interface PCMCIATuple_LONGLINK_C : PCMCIATuple
@end

/* LINKTARGET tuple (0x13) - Link target control */
@interface PCMCIATuple_LINKTARGET : PCMCIATuple
@end

/* NO_LINK tuple (0x14) - No link */
@interface PCMCIATuple_NO_LINK : PCMCIATuple
@end

/* VERS_1 tuple (0x15) - Level 1 version/product information */
@interface PCMCIATuple_VERS_1 : PCMCIATuple
@end

/* ALTSTR tuple (0x16) - Alternate language string */
@interface PCMCIATuple_ALTSTR : PCMCIATuple
@end

/* DEVICE_A tuple (0x17) - Device information for attribute memory */
@interface PCMCIATuple_DEVICE_A : PCMCIATuple
@end

/* JEDEC_C tuple (0x18) - JEDEC identifier for common memory */
@interface PCMCIATuple_JEDEC_C : PCMCIATuple
@end

/* JEDEC_A tuple (0x19) - JEDEC identifier for attribute memory */
@interface PCMCIATuple_JEDEC_A : PCMCIATuple
@end

/* CONFIG tuple (0x1A) - Configuration */
@interface PCMCIATuple_CONFIG : PCMCIATuple
@end

/* CFTABLE_ENTRY tuple (0x1B) - Configuration table entry */
@interface PCMCIATuple_CFTABLE_ENTRY : PCMCIATuple
@end

/* DEVICE_OC tuple (0x1C) - Other operating conditions device info */
@interface PCMCIATuple_DEVICE_OC : PCMCIATuple
@end

/* DEVICE_OA tuple (0x1D) - Other operating conditions device info (attribute) */
@interface PCMCIATuple_DEVICE_OA : PCMCIATuple
@end

/* DEVICE_GEO tuple (0x1E) - Device geometry for common memory */
@interface PCMCIATuple_DEVICE_GEO : PCMCIATuple
@end

/* DEVICE_GEO_A tuple (0x1F) - Device geometry for attribute memory */
@interface PCMCIATuple_DEVICE_GEO_A : PCMCIATuple
@end

/* MANFID tuple (0x20) - Manufacturer identification */
@interface PCMCIATuple_MANFID : PCMCIATuple
@end

/* FUNCID tuple (0x21) - Function identification */
@interface PCMCIATuple_FUNCID : PCMCIATuple
@end

/* FUNCE tuple (0x22) - Function extension */
@interface PCMCIATuple_FUNCE : PCMCIATuple
@end

/* SWIL tuple (0x23) - Software interleave */
@interface PCMCIATuple_SWIL : PCMCIATuple
@end

/* VERS_2 tuple (0x40) - Level 2 version information */
@interface PCMCIATuple_VERS_2 : PCMCIATuple
@end

/* FORMAT tuple (0x41) - Data recording format */
@interface PCMCIATuple_FORMAT : PCMCIATuple
@end

/* GEOMETRY tuple (0x42) - Geometry */
@interface PCMCIATuple_GEOMETRY : PCMCIATuple
@end

/* BYTEORDER tuple (0x43) - Byte order */
@interface PCMCIATuple_BYTEORDER : PCMCIATuple
@end

/* DATE tuple (0x44) - Card initialization date */
@interface PCMCIATuple_DATE : PCMCIATuple
@end

/* BATTERY tuple (0x45) - Battery replacement date */
@interface PCMCIATuple_BATTERY : PCMCIATuple
@end

/* ORG tuple (0x46) - Organization of data */
@interface PCMCIATuple_ORG : PCMCIATuple
@end

/* END tuple (0xFF) - End of tuple chain */
@interface PCMCIATuple_END : PCMCIATuple
@end

#endif /* DRIVER_PRIVATE */

#endif /* _DRIVERKIT_I386_PCMCIATUPLETYPES_H_ */
