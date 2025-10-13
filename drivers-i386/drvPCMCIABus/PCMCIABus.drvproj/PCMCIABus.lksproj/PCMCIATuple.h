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
 * PCMCIA Tuple Definitions and Structures
 */

#ifndef _DRIVERKIT_I386_PCMCIATUPLE_H_
#define _DRIVERKIT_I386_PCMCIATUPLE_H_

#import <objc/Object.h>

/* PCMCIA Tuple Codes (from PC Card Standard) */
#define CISTPL_NULL             0x00    /* Null tuple */
#define CISTPL_DEVICE           0x01    /* Device information */
#define CISTPL_LONGLINK_CB      0x02    /* Long link to next chain (CardBus) */
#define CISTPL_INDIRECT         0x03    /* Indirect access */
#define CISTPL_CONFIG_CB        0x04    /* Configuration (CardBus) */
#define CISTPL_CFTABLE_ENTRY_CB 0x05    /* Configuration table entry (CardBus) */
#define CISTPL_LONGLINK_MFC     0x06    /* Long link to multi-function card */
#define CISTPL_BAR              0x07    /* Base address register (CardBus) */
#define CISTPL_PWR_MGMNT        0x08    /* Power management */
#define CISTPL_EXTDEVICE        0x09    /* Extended device information */
#define CISTPL_CHECKSUM         0x10    /* Checksum control */
#define CISTPL_LONGLINK_A       0x11    /* Long link to attribute memory */
#define CISTPL_LONGLINK_C       0x12    /* Long link to common memory */
#define CISTPL_LINKTARGET       0x13    /* Link target control */
#define CISTPL_NO_LINK          0x14    /* No link */
#define CISTPL_VERS_1           0x15    /* Level 1 version/product info */
#define CISTPL_ALTSTR           0x16    /* Alternate language string */
#define CISTPL_DEVICE_A         0x17    /* Device information (attribute memory) */
#define CISTPL_JEDEC_C          0x18    /* JEDEC programming info (common) */
#define CISTPL_JEDEC_A          0x19    /* JEDEC programming info (attribute) */
#define CISTPL_CONFIG           0x1A    /* Configuration */
#define CISTPL_CFTABLE_ENTRY    0x1B    /* Configuration table entry */
#define CISTPL_DEVICE_OC        0x1C    /* Device info (other conditions) */
#define CISTPL_DEVICE_OA        0x1D    /* Device info (other, attribute) */
#define CISTPL_DEVICE_GEO       0x1E    /* Device geometry */
#define CISTPL_DEVICE_GEO_A     0x1F    /* Device geometry (attribute) */
#define CISTPL_MANFID           0x20    /* Manufacturer identification */
#define CISTPL_FUNCID           0x21    /* Function identification */
#define CISTPL_FUNCE            0x22    /* Function extension */
#define CISTPL_SWIL             0x23    /* Software interleave */
#define CISTPL_VERS_2           0x40    /* Level 2 version info */
#define CISTPL_FORMAT           0x41    /* Format */
#define CISTPL_GEOMETRY         0x42    /* Geometry */
#define CISTPL_BYTEORDER        0x43    /* Byte order */
#define CISTPL_DATE             0x44    /* Card initialization date */
#define CISTPL_BATTERY          0x45    /* Battery replacement date */
#define CISTPL_ORG              0x46    /* Organization */
#define CISTPL_END              0xFF    /* End of chain */

/* PCMCIA Function ID Codes */
#define CISTPL_FUNCID_MULTI     0x00    /* Multi-function card */
#define CISTPL_FUNCID_MEMORY    0x01    /* Memory card */
#define CISTPL_FUNCID_SERIAL    0x02    /* Serial I/O card */
#define CISTPL_FUNCID_PARALLEL  0x03    /* Parallel I/O card */
#define CISTPL_FUNCID_FIXED     0x04    /* Fixed disk card */
#define CISTPL_FUNCID_VIDEO     0x05    /* Video adapter */
#define CISTPL_FUNCID_NETWORK   0x06    /* Network adapter */
#define CISTPL_FUNCID_AIMS      0x07    /* Auto incrementing mass storage */

/* Maximum tuple size */
#define MAX_TUPLE_SIZE          256

/* PCMCIA Tuple Structure */
typedef struct pcmcia_tuple {
    unsigned char   code;               /* Tuple code */
    unsigned char   link;               /* Link to next tuple */
    unsigned char   data[MAX_TUPLE_SIZE]; /* Tuple data */
} pcmcia_tuple_t;

#ifdef DRIVER_PRIVATE

@interface PCMCIATuple : Object
{
@private
    unsigned char   _code;              /* Tuple code */
    unsigned char   _link;              /* Link value */
    unsigned char   *_data;             /* Tuple data */
    unsigned int    _length;            /* Data length */
}

- initWithCode:(unsigned char)code
          link:(unsigned char)link
          data:(unsigned char *)data
        length:(unsigned int)length;

- (unsigned char)code;
- (unsigned char)link;
- (unsigned char *)data;
- (unsigned int)length;

/* Parse specific tuple types */
- (BOOL)parseManufacturerID:(unsigned short *)manfid
                  cardID:(unsigned short *)cardid;
- (BOOL)parseFunctionID:(unsigned char *)funcid;
- (BOOL)parseVersionString:(char *)product
                    vendor:(char *)vendor
                   version:(char *)version;

@end

#endif /* DRIVER_PRIVATE */

#endif /* _DRIVERKIT_I386_PCMCIATUPLE_H_ */
