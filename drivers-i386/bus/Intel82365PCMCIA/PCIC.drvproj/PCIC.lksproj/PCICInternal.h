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
 * PCIC Internal Helper Function Declarations
 */

#ifndef _PCIC_INTERNAL_H_
#define _PCIC_INTERNAL_H_

#import <objc/objc.h>

/* Internal helper functions */
static char _socketIsValid(unsigned int socket);
static unsigned char _checkForCirrusChip(void);
static void _setStatusChangeInterrupt(unsigned int socket, unsigned int irq);

/* Window configuration functions (non-static, used by PCICWindow.m) */
void _setIoWindow(unsigned int socket, unsigned int window, unsigned int cardAddr, unsigned int size, unsigned int sysAddr);
void _setMemoryWindow(unsigned int socket, unsigned int window, unsigned int cardAddr, unsigned int size, unsigned int sysAddr);

#endif /* _PCIC_INTERNAL_H_ */
