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
 * BPFDriver.m
 * Berkeley Packet Filter (BPF) IOKit Driver Implementation
 *
 * This driver provides an IOKit wrapper for the BSD BPF subsystem.
 */

#import "BPFDriver.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <bsd/sys/conf.h>
#import <bsd/sys/systm.h>
#import <bsd/sys/uio.h>
#import <bsd/sys/mbuf.h>
#import <bsd/net/bpf.h>

/* External kernel functions for BPF */
extern int bpfopen(dev_t dev, int flags);
extern int bpfclose(dev_t dev, int flags);
extern int bpfread(dev_t dev, struct uio *uio);
extern int bpfwrite(dev_t dev, struct uio *uio);
extern int bpfioctl(dev_t dev, u_long cmd, caddr_t addr, int flags);
extern int bpf_select(dev_t dev, int which, struct proc *p);
extern void bpfilterattach(int n);
extern void bpf_tap(caddr_t arg, u_char *pkt, u_int pktlen);
extern void bpf_mtap(caddr_t arg, struct mbuf *m);
extern int nbpfilter;
extern bpfops_t bpfops;

/* Global kernel server instance */
static BPFKernelServerInstance *gBPFKernelServer = nil;

/*
 * ============================================================================
 * BPFKernelServerInstance Implementation
 * ============================================================================
 */

@implementation BPFKernelServerInstance

/*
 * Probe method for kernel server
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    return YES;
}

/*
 * Initialize kernel server instance
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    const char *numDevStr;

    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Get number of BPF devices from device description, default to 16 */
    numDevStr = [deviceDescription valueForStringKey:"BPF Devices"];
    if (numDevStr != NULL) {
        _numDevices = atoi(numDevStr);
    } else {
        _numDevices = 16;  /* Default number of BPF devices */
    }

    /* Sanity check */
    if (_numDevices < 1) {
        _numDevices = 1;
    } else if (_numDevices > BPF_MAXDEVICES) {
        _numDevices = BPF_MAXDEVICES;
    }

    _initialized = NO;
    _majorDeviceNumber = -1;

    [self setName:"BPFKernelServer"];
    [self setDeviceKind:"BPFKernelServer"];

    gBPFKernelServer = self;

    return self;
}

/*
 * Free kernel server resources
 */
- free
{
    if (gBPFKernelServer == self) {
        gBPFKernelServer = nil;
    }

    return [super free];
}

/*
 * BPF device operations - wrappers around kernel functions
 */

- (int)bpfopen:(int)dev flags:(int)flags
{
    return bpfopen((dev_t)dev, flags);
}

- (int)bpfclose:(int)dev flags:(int)flags
{
    return bpfclose((dev_t)dev, flags);
}

- (int)bpfread:(int)dev uio:(void *)uio
{
    return bpfread((dev_t)dev, (struct uio *)uio);
}

- (int)bpfwrite:(int)dev uio:(void *)uio
{
    return bpfwrite((dev_t)dev, (struct uio *)uio);
}

- (int)bpfioctl:(int)dev cmd:(unsigned long)cmd data:(void *)data flags:(int)flags
{
    return bpfioctl((dev_t)dev, cmd, (caddr_t)data, flags);
}

- (int)bpf_select:(int)dev which:(int)which proc:(void *)proc
{
    return bpf_select((dev_t)dev, which, (struct proc *)proc);
}

/*
 * BPF initialization and packet tap functions
 */

- (void)bpfilterattach:(int)count
{
    bpfilterattach(count);
    nbpfilter = count;
    _numDevices = count;
    _initialized = YES;

    /* Register tap functions in bpfops */
    bpfops.bpf_tap = bpf_tap;
    bpfops.bpf_mtap = bpf_mtap;

    IOLog("BPFKernelServer: Attached %d BPF filter%s\n",
          count, (count == 1) ? "" : "s");
}

- (void)bpf_tap:(void *)arg packet:(unsigned char *)pkt length:(unsigned int)pktlen
{
    bpf_tap((caddr_t)arg, pkt, pktlen);
}

- (void)bpf_mtap:(void *)arg mbuf:(void *)m
{
    bpf_mtap((caddr_t)arg, (struct mbuf *)m);
}

/*
 * Configuration accessors
 */

- (int)getNumDevices
{
    return _numDevices;
}

- (void)setNumDevices:(int)numDevices
{
    if (!_initialized && numDevices > 0 && numDevices <= BPF_MAXDEVICES) {
        _numDevices = numDevices;
    }
}

@end

/*
 * ============================================================================
 * BPF Implementation
 * ============================================================================
 */

@implementation BPF

/*
 * Probe method - determines if this driver should load
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    if ([deviceDescription isKindOf:[IODeviceDescription class]]) {
        return YES;
    }
    return NO;
}

/*
 * Initialize from device description
 */
- (BOOL)initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return NO;
    }

    /* Create kernel server instance */
    _serverInstance = [[BPFKernelServerInstance alloc]
                       initFromDeviceDescription:deviceDescription];
    if (_serverInstance == nil) {
        IOLog("BPF: Failed to create kernel server instance\n");
        return NO;
    }

    _initialized = NO;

    [self setName:"BPF"];
    [self setDeviceKind:"BPF"];
    [self setLocation:NULL];

    [self registerDevice];

    return YES;
}

/*
 * Post-load initialization - called after driver is loaded
 */
- (BOOL)PostLoad
{
    int numDevices;

    if (_initialized) {
        return YES;
    }

    if (_serverInstance == nil) {
        IOLog("BPF: PostLoad called without server instance\n");
        return NO;
    }

    numDevices = [_serverInstance getNumDevices];

    /* Initialize BPF subsystem through kernel server */
    [_serverInstance bpfilterattach:numDevices];

    _initialized = YES;

    IOLog("BPF: PostLoad completed - %d BPF device%s initialized\n",
          numDevices, (numDevices == 1) ? "" : "s");

    return YES;
}

/*
 * Free driver resources
 */
- (void)free
{
    if (_serverInstance != nil) {
        [_serverInstance free];
        _serverInstance = nil;
    }

    [super free];
}

/*
 * Check if BPF driver is initialized
 */
- (BOOL)isBPFInitialized
{
    return _initialized;
}

@end
