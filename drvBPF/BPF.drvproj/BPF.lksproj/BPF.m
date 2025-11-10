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
 * BPF.m
 * Berkeley Packet Filter (BPF) DriverKit Driver
 *
 * This driver provides a DriverKit wrapper for the BSD BPF subsystem.
 * The actual BPF implementation is in bpf.c and bpf_filter.c.
 */

#import "BPF.h"
#import <driverkit/generalFuncs.h>
#import <sys/types.h>
#import <sys/uio.h>
#import <sys/proc.h>

/* External BPF functions from bpf.c */
extern int bpfopen(dev_t dev, int flag);
extern int bpfclose(dev_t dev, int flag);
extern int bpfread(dev_t dev, struct uio *uio);
extern int bpfwrite(dev_t dev, struct uio *uio);
extern int bpfioctl(dev_t dev, u_long cmd, caddr_t addr, int flag);
extern int bpf_select(dev_t dev, int rw, struct proc *p);
extern void bpfilterattach(int n);

/* External BPF globals */
extern int nbpfilter;

/* External device entry points */
extern int nulldev(void);
extern int enodev(void);

@implementation BPF

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    BOOL result;
    id instance;

    result = [self addToCdevswFromDescription:deviceDescription
                                         open:(IOSwitchFunc)bpfopen
                                        close:(IOSwitchFunc)bpfclose
                                         read:(IOSwitchFunc)bpfread
                                        write:(IOSwitchFunc)bpfwrite
                                        ioctl:(IOSwitchFunc)bpfioctl
                                         stop:(IOSwitchFunc)nulldev
                                        reset:(IOSwitchFunc)nulldev
                                       select:(IOSwitchFunc)bpf_select
                                         mmap:(IOSwitchFunc)enodev
                                     strategy:(IOSwitchFunc)enodev
                                      getstat:(IOSwitchFunc)enodev];

    if (result == YES) {
        instance = [[self alloc] initFromDeviceDescription:deviceDescription];
        if (instance != nil) {
            return YES;
        }
        [self removeFromCdevsw];
    }

    return NO;
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    [self setName:"bpf"];
    [super initFromDeviceDescription:deviceDescription];
    [self registerDevice];

    return self;
}

- (IOReturn)getIntValues:(int *)parameterArray
            forParameter:(IOParameterName)parameterName
                   count:(unsigned int *)count
{
    const char *expected = "BpfMajorMinor";
    const char *p1, *p2;

    /* Compare parameter name with "BpfMajorMinor" */
    p1 = parameterName;
    p2 = expected;

    while (*p1 && *p2) {
        if (*p1 != *p2)
            break;
        p1++;
        p2++;
    }

    /* Check if strings match and count is correct */
    if (*p1 == '\0' && *p2 == '\0' && *count == 2) {
        /* Get character major number from class method */
        unsigned int majorNum = [[self class] characterMajor];

        /* Return major device number and number of BPF devices */
        parameterArray[0] = majorNum;
        parameterArray[1] = nbpfilter;
        *count = 2;

        return IO_R_SUCCESS;
    }

    /* Call superclass implementation */
    return [super getIntValues:parameterArray
                  forParameter:parameterName
                         count:count];
}

@end
