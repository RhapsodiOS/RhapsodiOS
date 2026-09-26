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
 * pnpDMA.h
 * PnP DMA Resource Descriptor
 */

#ifndef _PNPDMA_H_
#define _PNPDMA_H_

#import <objc/Object.h>

/* pnpDMA - DMA channel resource descriptor */
@interface pnpDMA : Object
{
    @private
    int _dmaChannels[8];        /* DMA channel numbers array at offset 0x04 */
    int _count;                 /* Number of channels in array at offset 0x24 */
    unsigned char _speedType1;  /* Speed/type flag 1 at offset 0x28 */
    unsigned char _speedType2;  /* Speed/type flag 2 at offset 0x29 */
    unsigned char _busmaster;   /* Bus master flag at offset 0x2a */
    unsigned char _byteMode;    /* Byte mode flag at offset 0x2b */
    unsigned char _wordMode;    /* Word mode flag at offset 0x2c */
    unsigned char _speedField;  /* Speed field at offset 0x2d */
}

/*
 * Initialization
 */
- initFrom:(void *)buffer Length:(int)length;

/*
 * DMA channel information
 */
- (int *)dmaChannels;
- (int)number;
- (BOOL)matches:(id)otherDMA;

/*
 * Output
 */
- print;

/*
 * Configuration
 */
- addDMAToList:(id)list;
- writePnPConfig:(id)dmaObject Index:(int)index;

@end

#endif /* _PNPDMA_H_ */
