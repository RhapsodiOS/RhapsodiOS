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
 * Mach Operating System
 * Copyright (c) 1989 Carnegie-Mellon University
 * Copyright (c) 1988 Carnegie-Mellon University
 * All rights reserved.  The CMU software License Agreement specifies
 * the terms and conditions for use and redistribution.
 */
/* 
 * HISTORY
 * Revision 1.1.1.1  1997/09/30 02:45:12  wsanchez
 * Import of kernel from umeshv/kernel
 *
 *
 * 4-Jan-95 Curtis Galloway (galloway) at NeXT
 *	Created cross-buildable version from old genassym.c.
 *
 * 16-Mar-93  Curtis Galloway (galloway) at NeXT
 *      Remove obsolete 68k timer references.
 *
 * Revision 1.4.1.3  91/03/28  08:43:49  rvb
 * 	Flush THREAD_EXIT & THREAD_EXIT_CODE for X134.
 * 	[91/03/23            rvb]
 * 
 * Revision 1.4.1.2  90/02/09  17:23:20  rvb
 * 	Constants for Mach emulation support.
 * 	[90/02/09            rvb]
 * 
 * Revision 1.4.1.1  90/01/02  13:50:28  rvb
 * 	Flush MACH_TIME.
 * 
 * Revision 1.4  89/04/05  12:57:30  rvb
 * 	X78: no more vmmeter
 * 	[89/03/24            rvb]
 * 
 * Revision 1.3  89/02/26  12:31:18  gm0w
 * 	Changes for cleanup.
 * 
 * 31-Dec-88  Robert Baron (rvb) at Carnegie-Mellon University
 *	Derived from MACH2.0 vax release.
 *	Still a lot of dead wood to cleanup.
 *
 * 11-Dec-87  Stephen Schwab (schwab) at Carnegie-Mellon University
 *	For 650, define ssc timer symbolic offsets.
 *
 */

#import <confdep.h>

#import <stddef.h>
#import <mach/mach_types.h>

#import <sys/param.h>
#import <sys/buf.h>
#import <sys/vmparam.h>
#import <sys/dir.h>
#import <sys/proc.h>
#import <sys/user.h>
#import <sys/mbuf.h>
#import <sys/msgbuf.h>

#import <kern/lock.h>

#import <kern/thread.h>
#import <kern/task.h>

int _ERR = offsetof(thread_saved_state_t, frame.err);
int _EFL = offsetof(thread_saved_state_t, frame.eflags);
int _EBP = offsetof(thread_saved_state_t, regs.ebp);
int _P_PRI = offsetof(struct proc, p_priority);
int _P_STAT = offsetof(struct proc, p_stat);
int _P_SIG = offsetof(struct proc, p_siglist);
int _P_FLAG = offsetof(struct proc, p_flag);
int _SSLEEP = SSLEEP;
int _SRUN = SRUN;
int _RU_MINFLT = offsetof(struct rusage, ru_minflt);
int _PR_BASE = offsetof(struct uprof, pr_base);
int _PR_SIZE = offsetof(struct uprof, pr_size);
int _PR_OFF = offsetof(struct uprof, pr_off);
int _PR_SCALE = offsetof(struct uprof, pr_scale);
int _U_AR0 = offsetof(struct uthread, uu_ar0);
int _THREAD_PCB = offsetof(struct thread, pcb);
int _THREAD_RECOVER = offsetof(struct thread, recover);
int _THREAD_TASK = offsetof(struct thread, task);
int _THREAD_AST = offsetof(struct thread, ast);
int _AST_ZILCH = AST_ZILCH;
//	sel_conv.sel = NULL_SEL;
//int _NULLSEL = sel_conv.sel_data);
sel_t _NULLSEL = NULL_SEL;
//	sel_conv.sel = KCS_SEL;
//int _KCSSEL = sel_conv.sel_data);
sel_t _KCSSEL = KCS_SEL;
//	sel_conv.sel = KDS_SEL;
//int _KDSSEL = sel_conv.sel_data);
sel_t _KDSSEL = KDS_SEL;
//	sel_conv.sel = LCODE_SEL;
//int _LCODESEL = sel_conv.sel_data);
sel_t _LCODESEL = LCODE_SEL;
//	sel_conv.sel = LDATA_SEL;
//int _LDATASEL = sel_conv.sel_data);
sel_t _LDATASEL = LDATA_SEL;
int _VM_MIN_KERNEL_ADDRESS  = VM_MIN_KERNEL_ADDRESS;
int _KERNEL_LINEAR_BASE  = KERNEL_LINEAR_BASE;
int _KERN_FAILURE = KERN_FAILURE;
