/*
 * Copyright (c) 1998 Apple Computer, Inc. All rights reserved.
 *
 * ATIMach64DisplayDriverKernelServerInstance.m
 * Kernel Server Instance Implementation for ATI Mach64 Display Driver
 *
 * HISTORY
 * 28 Mar 98    Created.
 */

#import "ATIMach64DisplayDriverKernelServerInstance.h"
#import <driverkit/generalFuncs.h>
#import <string.h>

@implementation ATIMach64DisplayDriverKernelServerInstance

+ (id)allocKernelInstance
{
    return [[self alloc] init];
}

- (id)initFromMachine:(void *)machine fromSource:(void *)source
{
    self = [super init];
    if (self) {
        _kernelInstance = machine;
        _deviceInstance = source;
    }
    return self;
}

- (void)free
{
    _kernelInstance = NULL;
    _deviceInstance = NULL;
    [super free];
}

@end
