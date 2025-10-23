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
#include <sys/tty.h>

/* Speed table for baud rate conversion */
extern int ttyiops_speeds[];

/* Function declarations */
void ttyiops_getData(struct tty *tp);
void ttyiops_attachDevice(id portServerObj, unsigned int unit);
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
extern int portServerMajor;
extern id _ttyiopsMap[];  /* Array of PortServer instances */


/* Character device switch wrappers */
int portServeropen(unsigned int dev, int flag, int mode, struct proc *p);
int portServerclose(unsigned int dev, int flag);
int portServerioctl(unsigned int dev, unsigned int cmd, void *data, int flag, struct proc *p);

#endif /* _TTYIOPS_H_ */
