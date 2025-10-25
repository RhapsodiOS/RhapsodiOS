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
 * PCICWindow - Represents a memory or I/O window in a PCMCIA socket
 */

#ifndef _PCIC_WINDOW_H_
#define _PCIC_WINDOW_H_

#import <objc/Object.h>

@interface PCICWindow : Object
{
    id socket;                  /* Parent socket object (offset 4) */
    id validSocketsList;        /* List of sockets this window is valid for (offset 8) */
    unsigned int socketNumber;  /* Cached socket number (offset 12/0xc) */
    unsigned int windowNumber;  /* Window number (offset 16/0x10) */
    unsigned char memoryWindow; /* Memory window/interface flag (0=memory, 1=I/O) (offset 20/0x14) */
    unsigned int systemAddress; /* System address mapping */
    unsigned int cardAddress;   /* Card address mapping (offset 28/0x1c) */
    unsigned int mapSize;       /* Size of mapping (offset 32/0x20) */
    unsigned int enabled;       /* Window enabled state */
    unsigned int attrMemFlag;   /* Attribute memory flag (cached) */
    unsigned int is16Bit;       /* 16-bit data path flag */
}

/* Initialization */
- initWithSocket:theSocket memoryWindow:(int)memoryWindow number:(int)number;

/* Window getters */
- socket;
- (unsigned int)enabled;
- (unsigned int)systemAddress;
- (unsigned int)cardAddress;
- (unsigned int)mapSize;
- (unsigned int)attributeMemory;
- (unsigned int)is16Bit;
- (unsigned int)memoryInterface;
- validSockets;

/* Window setters */
- (void)setSocket:theSocket;
- (void)setEnabled:(unsigned int)enabled;
- (void)setMapWithSize:(unsigned int)size systemAddress:(unsigned int)sysAddr cardAddress:(unsigned int)cardAddr;
- (void)setAttributeMemory:(unsigned int)attrMem;
- (void)set16Bit:(unsigned int)is16;
- (void)setMemoryInterface:(unsigned int)interface;

@end

#endif /* _PCIC_WINDOW_H_ */
