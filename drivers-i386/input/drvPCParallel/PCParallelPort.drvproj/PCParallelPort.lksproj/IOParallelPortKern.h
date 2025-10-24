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

#import <sys/types.h>
#import <sys/errno.h>

// Kernel-level parallel port constants
#define PP_KERN_DATA_SIZE     1024
#define PP_KERN_MAX_PORTS     4
#define PP_KERN_TIMEOUT_MS    5000

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

// Parallel port modes
typedef enum {
    PP_MODE_SPP = 0,    // Standard Parallel Port
    PP_MODE_EPP,        // Enhanced Parallel Port
    PP_MODE_ECP,        // Extended Capabilities Port
    PP_MODE_COMPATIBLE  // Compatibility mode
} pp_mode_t;

// Parallel port status
typedef struct {
    unsigned char status;
    unsigned char control;
    unsigned char data;
    unsigned char reserved;
} pp_port_state_t;

// Function prototypes for kernel-level operations
void pp_kern_init(void);
int pp_kern_probe(unsigned int baseAddr);
int pp_kern_reset(unsigned int portNum);
int pp_kern_set_mode(unsigned int portNum, pp_mode_t mode);
int pp_kern_get_mode(unsigned int portNum, pp_mode_t *mode);
int pp_kern_read_data(unsigned int portNum, unsigned char *data);
int pp_kern_write_data(unsigned int portNum, unsigned char data);
int pp_kern_read_status(unsigned int portNum, unsigned char *status);
int pp_kern_read_control(unsigned int portNum, unsigned char *control);
int pp_kern_write_control(unsigned int portNum, unsigned char control);
int pp_kern_get_state(unsigned int portNum, pp_port_state_t *state);
int pp_kern_set_state(unsigned int portNum, const pp_port_state_t *state);
void pp_kern_delay(unsigned int microseconds);
int pp_kern_wait_busy(unsigned int portNum, unsigned int timeout_ms);
int pp_kern_strobe(unsigned int portNum);
int pp_kern_enable_interrupts(unsigned int portNum);
int pp_kern_disable_interrupts(unsigned int portNum);

// Character device interface functions
int enodev(void);
int seltrue(void);
int ppopen(dev_t dev, int flags, int devtype, void *p);
int ppclose(dev_t dev, int flags, int devtype, void *p);
int ppread(dev_t dev, void *uio, int ioflag);
int ppwrite(dev_t dev, void *uio, int ioflag);
int ppioctl(dev_t dev, unsigned long cmd, void *data, int flag, void *p);
void ppstrategy(void *bp);
void ppminphys(void *bp);

// Internal helper functions
void IOParallelPortInterruptHandler(unsigned int param1, unsigned int param2, int portNum);
void IOParallelPortThread(id portObject);
int _strobeChar(int portNum, unsigned int delay, char useSpl);

// Message and interrupt handling
void IOSendInterrupt(unsigned int param1, unsigned int param2, int msgType);
void IOExitThread(void);

// Mach message receive
int msg_receive(void *msg, int option, int timeout);

// Software control structure
extern void *pp_softc;

#endif /* KERNEL */

#endif /* _BSD_DEV_I386_IOPARALLELPORTKERN_H_ */
