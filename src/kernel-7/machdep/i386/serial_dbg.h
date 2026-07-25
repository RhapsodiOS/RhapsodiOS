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
 * serial_dbg.h -- polled 8250/16550 debug console for i386.
 *
 * Output only.  Safe with paging disabled, in interrupt context, and during
 * panic: no locks, no allocation, no interrupts, and a bounded spin so a
 * missing UART cannot wedge the kernel.
 */

#ifndef _MACHDEP_I386_SERIAL_DBG_
#define _MACHDEP_I386_SERIAL_DBG_

extern int	serial_dbg_port;	/* 0 disables; default 0x2f8 (COM2) */

void	serial_dbg_init(void);
void	serial_dbg_putc(char c);
void	serial_dbg_puts(const char *s);

#endif /* _MACHDEP_I386_SERIAL_DBG_ */
