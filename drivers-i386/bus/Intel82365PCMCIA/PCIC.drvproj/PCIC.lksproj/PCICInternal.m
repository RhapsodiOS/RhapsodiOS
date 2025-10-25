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
 * PCIC Internal Category Implementation
 */

#import "PCIC.h"
#import <driverkit/generalFuncs.h>
#import <machdep/i386/io_inline.h>

/* External reference to global reg_base from PCIC.m */
extern unsigned int reg_base;

@implementation PCIC(Internal)

/*
 * Read register for socket
 * Directly accesses PCIC hardware registers
 */
- (unsigned char)_readRegister:(int)regOffset socket:(int)socket
{
    unsigned char value;

    /* Write register offset to index port: (socket * 64) + regOffset */
    outb(reg_base, (char)(socket << 6) + (char)regOffset);

    /* Read value from data port */
    value = inb(reg_base + 1);

    return value;
}

/*
 * Write register for socket
 * Directly accesses PCIC hardware registers
 */
- (void)_writeRegister:(int)regOffset socket:(int)socket value:(unsigned char)value
{
    char offsetCalc;

    /* Calculate socket offset: socket * 64 */
    offsetCalc = (char)(socket << 6);

    /* Write register offset to index port */
    outb(reg_base, offsetCalc + (char)regOffset);

    /* Write value to data port */
    outb(reg_base + 1, value);
}

@end
