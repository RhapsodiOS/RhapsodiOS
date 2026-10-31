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
 * pnpIOPort.h
 * PnP I/O Port Resource Descriptor
 */

#ifndef _PNPIOPORT_H_
#define _PNPIOPORT_H_

#import <objc/Object.h>

/* pnpIOPort - I/O port range resource descriptor */
@interface pnpIOPort : Object
{
    @private
    unsigned short _min_base;      /* Minimum base address at offset 0x04 */
    unsigned short _max_base;      /* Maximum base address at offset 0x06 */
    unsigned short _alignment;     /* Alignment at offset 0x08 */
    unsigned short _length;        /* Length at offset 0x0a */
    unsigned char _lines_decoded;  /* Address lines decoded at offset 0x0c */
}

/*
 * Initialization
 */
- initFrom:(void *)buffer Length:(int)length Type:(int)type;
- initWithBase:(unsigned short)base Length:(unsigned short)length;

/*
 * I/O port information
 */
- (unsigned short)min_base;
- (unsigned short)max_base;
- (unsigned short)alignment;
- (unsigned short)length;
- (unsigned char)lines_decoded;
- (BOOL)matches:(id)otherPort;

/*
 * Output
 */
- print;

/*
 * Configuration
 */
- writePnPConfig:(id)portObject Index:(int)index;

@end

#endif /* _PNPIOPORT_H_ */
