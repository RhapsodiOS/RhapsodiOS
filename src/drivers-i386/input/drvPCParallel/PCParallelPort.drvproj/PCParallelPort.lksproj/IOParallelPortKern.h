/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.0 (the 'License').  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License."
 *
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 * IOParallelPortKern.h - Kernel-level interface for PC Parallel Port driver.
 *
 * HISTORY
 */

#ifndef _BSD_DEV_I386_IOPARALLELPORTKERN_H_
#define _BSD_DEV_I386_IOPARALLELPORTKERN_H_

#ifdef KERNEL

#import <objc/objc.h>
#import <sys/types.h>
#import <sys/errno.h>

struct buf;

// IOCTL command codes
#define PP_IOCTL_GET_STATUS_WORD          0x40047000
#define PP_IOCTL_SET_TIMEOUT              0x80047002
#define PP_IOCTL_GET_INT_HANDLER_DELAY    0x40047004
#define PP_IOCTL_SET_INT_HANDLER_DELAY    0x80047005
#define PP_IOCTL_GET_IO_THREAD_DELAY      0x40047006
#define PP_IOCTL_SET_IO_THREAD_DELAY      0x80047007
#define PP_IOCTL_GET_MIN_PHYS             0x40047008
#define PP_IOCTL_SET_MIN_PHYS             0x80047009
#define PP_IOCTL_GET_BLOCK_SIZE           0x4004700a
#define PP_IOCTL_SET_BLOCK_SIZE           0x8004700b
#define PP_IOCTL_GET_BUSY_RETRY_INTERVAL  0x4004700c
#define PP_IOCTL_SET_BUSY_RETRY_INTERVAL  0x8004700d
#define PP_IOCTL_GET_BUSY_MAX_RETRIES     0x4004700e
#define PP_IOCTL_SET_BUSY_MAX_RETRIES     0x8004700f
#define PP_IOCTL_GET_STATUS_REG_CONTENTS  0x40047010
#define PP_IOCTL_GET_CONTROL_REG_CONTENTS 0x40047011
#define PP_IOCTL_GET_CONTROL_REG_DEFAULTS 0x40047012

// Character device interface functions
int ppopen(dev_t dev, int flags, int devtype, void *p);
int ppclose(dev_t dev, int flags, int devtype, void *p);
int ppread(dev_t dev, void *uio, int ioflag);
int ppwrite(dev_t dev, void *uio, int ioflag);
int ppioctl(dev_t dev, unsigned long cmd, void *data, int flag, void *p);
int ppstrategy(struct buf *bp);
unsigned int ppminphys(struct buf *bp);

// Internal helper functions
void IOParallelPortInterruptHandler(void *identity, void *state, unsigned int portNum);
void IOParallelPortThread(void *portObject);
int _strobeChar(int portNum, unsigned int delay, char useSpl);

// Message and interrupt handling — use System.framework declarations.
// (Do not redeclare IOExitThread / msg_receive / enodev / seltrue; they conflict.)

/*
 * Software control structure.  The reference's _pp_softc is a 12-byte array
 * in __DATA,__data with a single element — one device per driver, which is
 * what the "only one dev this version" refusal in
 * -initFromDeviceDescription: enforces.  Every access site indexes it as
 * pp_softc[minor(dev)].
 */
typedef struct {
    id              device;   // +0x00
    int             count;    // +0x04  bytes left in the current transfer
    unsigned char  *data;     // +0x08  next byte to move
} pp_softc_t;

extern pp_softc_t pp_softc[1];

#endif /* KERNEL */

#endif /* _BSD_DEV_I386_IOPARALLELPORTKERN_H_ */
