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
 * pnpIRQ.h
 * PnP IRQ Resource Descriptor
 */

#ifndef _PNPIRQ_H_
#define _PNPIRQ_H_

#import <objc/Object.h>

/* pnpIRQ - IRQ resource descriptor */
@interface pnpIRQ : Object
{
    @private
    int _irqs[16];              /* IRQ numbers array at offset 0x04 (64 bytes) */
    int _count;                 /* Number of IRQs at offset 0x44 */
    unsigned char _highLevel;   /* High/level flag at offset 0x48 */
    unsigned char _flag1;       /* Flag 1 at offset 0x49 */
    unsigned char _flag2;       /* Flag 2 at offset 0x4a */
    unsigned char _flag3;       /* Flag 3 at offset 0x4b */
}

/*
 * Initialization
 */
- initFrom:(void *)buffer Length:(int)length;

/*
 * IRQ information
 */
- (int *)irqs;
- (int)number;
- (BOOL)matches:(id)otherIRQ;

/*
 * Configuration
 */
- setHigh:(BOOL)high Level:(BOOL)level;
- addToIRQList:(id)list;

/*
 * Output
 */
- print;

/*
 * Configuration
 */
- writePnPConfig:(id)irqObject Index:(int)index;

@end

#endif /* _PNPIRQ_H_ */
