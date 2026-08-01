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

#ifndef _INTERRUPT_KEYLARGO_H_
#define _INTERRUPT_KEYLARGO_H_

#include <ppc/spl.h>
#include <mach/boolean.h>

#include <machdep/ppc/dbdma.h>
#include <mach/kern_return.h>

#define KEYLARGO_FCR0_OFFSET 0x38
#define KEYLARGO_FCR1_OFFSET 0x3c
#define KEYLARGO_FCR2_OFFSET 0x40
#define KEYLARGO_FCR3_OFFSET 0x44
#define KEYLARGO_FCR4_OFFSET 0x48

/* DBDMA Channel Map */
extern powermac_dbdma_channels_t keylargo_dbdma_channels;
extern boolean_t PEKeyLargoGetMacIOInfo(unsigned int *base,
    unsigned int *size);
extern kern_return_t PEKeyLargoInitialize(void);

#endif /* _INTERRUPT_KEYLARGO_H_ */
