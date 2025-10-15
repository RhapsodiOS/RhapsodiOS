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
 * PnPIOPortResource.h
 * PnP I/O Port Resource Descriptor
 */

#ifndef _PNPIOPORTRESOURCE_H_
#define _PNPIOPORTRESOURCE_H_

#import <objc/Object.h>

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

#endif /* _PNPIOPORTRESOURCE_H_ */
