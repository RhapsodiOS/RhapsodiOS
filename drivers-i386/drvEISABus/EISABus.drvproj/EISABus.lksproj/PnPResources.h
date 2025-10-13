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
 * PnPResources.h
 * EISA Plug and Play Resource Management
 */

#ifndef _PNPRESOURCES_H_
#define _PNPRESOURCES_H_

#import <objc/Object.h>

/* PnPArgStack - Stack for PnP configuration arguments */
@interface PnPArgStack : Object
{
    @private
    void *_stackData;
    int _depth;
}
- init;
- free;
- (BOOL)push:(void *)data;
- (void *)pop;
- (int)depth;
@end

/* PnPBios - BIOS interface */
@interface PnPBios : Object
{
    @private
    void *_biosData;
    unsigned int _biosAddress;
}
- init;
- free;
- (BOOL)detectBios;
- (void *)getBiosData;
@end

/* PnPDependentResources - Dependent resource configurations */
@interface PnPDependentResources : Object
{
    @private
    void *_resources;
    int _count;
}
- init;
- free;
- (BOOL)addResource:(void *)resource;
- (void *)getResource:(int)index;
- (int)count;
@end

/* PnPInterruptResource - Interrupt resource descriptor */
@interface PnPInterruptResource : Object
{
    @private
    unsigned int _irqMask;
    unsigned char _flags;
}
- init;
- free;
- (void)setIRQMask:(unsigned int)mask;
- (unsigned int)irqMask;
- (void)setFlags:(unsigned char)flags;
- (unsigned char)flags;
@end

/* PnPIOPortResource - I/O Port resource descriptor */
@interface PnPIOPortResource : Object
{
    @private
    unsigned int _minBase;
    unsigned int _maxBase;
    unsigned char _alignment;
    unsigned char _length;
    unsigned char _flags;
}
- init;
- free;
- (void)setMinBase:(unsigned int)base;
- (void)setMaxBase:(unsigned int)base;
- (void)setAlignment:(unsigned char)align;
- (void)setLength:(unsigned char)len;
- (void)setFlags:(unsigned char)flags;
- (unsigned int)minBase;
- (unsigned int)maxBase;
- (unsigned char)alignment;
- (unsigned char)length;
- (unsigned char)flags;
@end

/* PnPMemoryResource - Memory resource descriptor */
@interface PnPMemoryResource : Object
{
    @private
    unsigned int _minBase;
    unsigned int _maxBase;
    unsigned int _alignment;
    unsigned int _length;
    unsigned char _flags;
}
- init;
- free;
- (void)setMinBase:(unsigned int)base;
- (void)setMaxBase:(unsigned int)base;
- (void)setAlignment:(unsigned int)align;
- (void)setLength:(unsigned int)len;
- (void)setFlags:(unsigned char)flags;
- (unsigned int)minBase;
- (unsigned int)maxBase;
- (unsigned int)alignment;
- (unsigned int)length;
- (unsigned char)flags;
@end

/* PnPDMAResource - DMA resource descriptor */
@interface PnPDMAResource : Object
{
    @private
    unsigned char _channelMask;
    unsigned char _flags;
}
- init;
- free;
- (void)setChannelMask:(unsigned char)mask;
- (unsigned char)channelMask;
- (void)setFlags:(unsigned char)flags;
- (unsigned char)flags;
@end

#endif /* _PNPRESOURCES_H_ */
