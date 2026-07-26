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

#ifndef _TTYIOPS_H_
#define _TTYIOPS_H_

#include <sys/types.h>
#include <sys/time.h>
#include <sys/tty.h>

@class IOPortSession;

/*
 * ttyiops_state - per-port driver state.
 *
 * This is the single instance variable PortServer declares (at offset 264,
 * bringing the class to 616 bytes).  The layout is taken from the reference's
 * __OBJC ivar type string; the embedded struct tty is 232 bytes, which puts
 * iops at +0xE8, it_out at +0xF4, it_in at +0x120, dtr_down_time at +0x14C,
 * in_opens_pending at +0x154, dcd_delay_ticks at +0x158 and the eleven
 * one-bit flags at +0x15C, for a total of 352 bytes.
 */
typedef struct ttyiops_state {
    struct tty      tty;
    IOPortSession  *iops;
    void           *rxThread;
    void           *txThread;
    struct termios  it_out;
    struct termios  it_in;
    struct timeval  dtr_down_time;
    int             in_opens_pending;
    int             dcd_delay_ticks;
    unsigned int    is_post_loaded:1;
    unsigned int    preempt:1;
    unsigned int    is_releasing:1;
    unsigned int    rx_blocked:1;
    unsigned int    has_audit_sleeper:1;
    unsigned int    kill_threads:1;
    unsigned int    is_timers_set:1;
    unsigned int    is_tx_enabled:1;
    unsigned int    is_rx_enabled:1;
    unsigned int    is_dcd_timer:1;
    unsigned int    is_dtr_delay:1;
} ttyiops_state;

/* Speed table for baud rate conversion */
extern struct speedtab ttyiops_speeds[];

/* Function declarations */
void ttyiops_getData(struct tty *tp);
void ttyiops_attachDevice(ttyiops_state *state);
unsigned int rs232totio(unsigned int rs232_flags);
unsigned int tiotors232(unsigned int tio_flags);
int ttyiops_acquireSession(struct tty *tp, unsigned int session_flags);
int ttyiops_open(unsigned int dev, int flag, int mode, struct proc *p);
int ttyiops_read(unsigned int dev, struct uio *uio, int flag);
int ttyiops_write(unsigned int dev, struct uio *uio, int flag);
int ttyiops_select(unsigned int dev, int which, struct proc *p);
int ttyiops_close(unsigned int dev, int flag);
int ttyiops_mctl(struct tty *tp, int bits, int how);
int ttyiops_control_ioctl(struct tty *tp, unsigned int dev, unsigned int cmd,
                          void *data, int flag, struct proc *p);
void ttyiops_convertFlowCtrl(id portSession, unsigned int *flags);
void ttyiops_dcddelay(struct tty *tp);
void ttyiops_init(struct tty *tp);
void ttyiops_start(struct tty *tp);
int ttyiops_stop(struct tty *tp, int flags);
int ttyiops_param(struct tty *tp, struct termios *t);
int ttyiops_ioctl(unsigned int dev, unsigned int cmd, void *data, int flag, struct proc *p);
void ttyiops_optimiseInput(struct tty *tp, struct termios *t);
int ttyiops_waitForDCD(struct tty *tp, int flag);
void ttyiops_rxFunc(struct tty *tp);
void ttyiops_txFunc(struct tty *tp);
void ttyiops_txload(struct tty *tp, unsigned int *mask);
void ttyiops_procEvent(struct tty *tp);

/* External references */
extern long hz;
extern struct timeval time;
extern int _portServerMajor;
extern id _ttyiopsMap[];  /* Array of PortServer instances */

#endif /* _TTYIOPS_H_ */
