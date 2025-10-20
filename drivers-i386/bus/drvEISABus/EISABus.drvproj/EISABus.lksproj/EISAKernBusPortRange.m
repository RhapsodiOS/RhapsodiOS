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
 * EISAKernBusPortRange.m
 * EISA/ISA I/O Port Range Resource Implementation
 */

#import "EISAKernBusPortRange.h"
#import <driverkit/generalFuncs.h>

@implementation EISAKernBusPortRange

/*
 * Read byte from I/O port
 * Uses x86 inb instruction
 */
- (unsigned char)readByteAt:(unsigned int)offset
{
    unsigned int port;
    unsigned char value;

    /* Get absolute port address (base + offset) */
    port = [self base] + offset;

    /* Read byte from port */
    __asm__ volatile("inb %1, %0" : "=a"(value) : "d"((unsigned short)port));

    return value;
}

/*
 * Read word (16-bit) from I/O port
 * Uses x86 inw instruction
 */
- (unsigned short)readWordAt:(unsigned int)offset
{
    unsigned int port;
    unsigned short value;

    /* Get absolute port address (base + offset) */
    port = [self base] + offset;

    /* Read word from port */
    __asm__ volatile("inw %1, %0" : "=a"(value) : "d"((unsigned short)port));

    return value;
}

/*
 * Read long (32-bit) from I/O port
 * Uses x86 inl instruction
 */
- (unsigned int)readLongAt:(unsigned int)offset
{
    unsigned int port;
    unsigned int value;

    /* Get absolute port address (base + offset) */
    port = [self base] + offset;

    /* Read long from port */
    __asm__ volatile("inl %1, %0" : "=a"(value) : "d"((unsigned short)port));

    return value;
}

/*
 * Write byte to I/O port
 * Uses x86 outb instruction
 */
- (void)writeByte:(unsigned char)value At:(unsigned int)offset
{
    unsigned int port;

    /* Get absolute port address (base + offset) */
    port = [self base] + offset;

    /* Write byte to port */
    __asm__ volatile("outb %0, %1" : : "a"(value), "d"((unsigned short)port));
}

/*
 * Write word (16-bit) to I/O port
 * Uses x86 outw instruction
 */
- (void)writeWord:(unsigned short)value At:(unsigned int)offset
{
    unsigned int port;

    /* Get absolute port address (base + offset) */
    port = [self base] + offset;

    /* Write word to port */
    __asm__ volatile("outw %0, %1" : : "a"(value), "d"((unsigned short)port));
}

/*
 * Write long (32-bit) to I/O port
 * Uses x86 outl instruction
 */
- (void)writeLong:(unsigned int)value At:(unsigned int)offset
{
    unsigned int port;

    /* Get absolute port address (base + offset) */
    port = [self base] + offset;

    /* Write long to port */
    __asm__ volatile("outl %0, %1" : : "a"(value), "d"((unsigned short)port));
}

@end
