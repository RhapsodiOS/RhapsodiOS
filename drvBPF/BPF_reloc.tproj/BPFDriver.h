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
 * BPFDriver.h
 * Berkeley Packet Filter (BPF) IOKit Driver
 *
 * This driver provides an IOKit wrapper for the BSD BPF subsystem,
 * allowing user-space applications to capture and filter network packets.
 */

#ifndef _BPFDRIVER_H_
#define _BPFDRIVER_H_

#import <driverkit/IODevice.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <bsd/dev/bpf.h>

/* Maximum number of BPF devices to support */
#define BPF_MAXDEVICES 256

/* BPF device state */
typedef enum {
    BPF_STATE_IDLE = 0,
    BPF_STATE_WAITING,
    BPF_STATE_TIMED_OUT
} BPFDeviceState;

/*
 * BPFKernelServerInstance - Kernel server for BPF operations
 */
@interface BPFKernelServerInstance : IODevice
{
    @private
    int _numDevices;            /* Number of BPF devices configured */
    int _majorDeviceNumber;      /* Major device number for BPF */
    BOOL _initialized;           /* Driver initialization state */
}

/*
 * Server lifecycle methods
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- free;

/*
 * BPF device operations
 */
- (int)bpfopen:(int)dev flags:(int)flags;
- (int)bpfclose:(int)dev flags:(int)flags;
- (int)bpfread:(int)dev uio:(void *)uio;
- (int)bpfwrite:(int)dev uio:(void *)uio;
- (int)bpfioctl:(int)dev cmd:(unsigned long)cmd data:(void *)data flags:(int)flags;
- (int)bpf_select:(int)dev which:(int)which proc:(void *)proc;

/*
 * BPF initialization
 */
- (void)bpfilterattach:(int)count;
- (void)bpf_tap:(void *)arg packet:(unsigned char *)pkt length:(unsigned int)pktlen;
- (void)bpf_mtap:(void *)arg mbuf:(void *)m;

/*
 * Configuration
 */
- (int)getNumDevices;
- (void)setNumDevices:(int)numDevices;

@end

/*
 * BPFDriver - Main driver class
 */
@interface BPFDriver : IODevice
{
    @private
    BPFKernelServerInstance *_serverInstance;
    BOOL _initialized;
}

/*
 * Driver lifecycle methods
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- (BOOL)initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (void)free;

/*
 * Post-load initialization
 */
- (BOOL)PostLoad;

/*
 * Utility methods
 */
- (BOOL)isBPFInitialized;

@end

#endif /* _BPFDRIVER_H_ */
