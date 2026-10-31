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
 * EISAKernBusPortRange.h
 * EISA/ISA I/O Port Range Resource
 */

#ifndef _EISAKERNBUSPORTRANGE_H_
#define _EISAKERNBUSPORTRANGE_H_

#import <driverkit/KernBus.h>

/*
 * EISAKernBusPortRange - I/O port range resource
 * Extends KernBusRange for EISA/ISA I/O port management
 */
@interface EISAKernBusPortRange : KernBusRange
{
    @private
}

/*
 * I/O port access methods
 */
- (unsigned char)readByteAt:(unsigned int)offset;
- (unsigned short)readWordAt:(unsigned int)offset;
- (unsigned int)readLongAt:(unsigned int)offset;

- (void)writeByte:(unsigned char)value At:(unsigned int)offset;
- (void)writeWord:(unsigned short)value At:(unsigned int)offset;
- (void)writeLong:(unsigned int)value At:(unsigned int)offset;

@end

#endif /* _EISAKERNBUSPORTRANGE_H_ */
