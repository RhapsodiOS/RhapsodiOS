/*
 * Copyright (c) 1998 Apple Computer, Inc. All rights reserved.
 *
 * IBM ThinkPad 760ED Display Driver - Kernel Server Instance
 */

#import "IBMThinkPad760EDDisplayDriverKernelServerInstance.h"
#import "IBMThinkPad760EDDisplayDriver.h"
#import <driverkit/IODeviceMaster.h>
#import <driverkit/IODevice.h>
#import <kernserv/prototypes.h>

@implementation IBMThinkPad760EDDisplayDriverKernelServerInstance

static IBMThinkPad760EDDisplayDriverKernelServerInstance *serverInstance = nil;

+ (BOOL)loadDriver
{
    if (serverInstance == nil) {
        serverInstance = [[IBMThinkPad760EDDisplayDriverKernelServerInstance alloc] init];
        if (serverInstance == nil) {
            IOLog("IBMThinkPad760EDDisplayDriverKernelServerInstance: Failed to create instance\n");
            return NO;
        }

        if ([serverInstance startDriver] != KERN_SUCCESS) {
            IOLog("IBMThinkPad760EDDisplayDriverKernelServerInstance: Failed to start driver\n");
            [serverInstance free];
            serverInstance = nil;
            return NO;
        }

        IOLog("IBMThinkPad760EDDisplayDriverKernelServerInstance: Driver loaded successfully\n");
        return YES;
    }

    return YES;
}

+ (BOOL)unloadDriver
{
    if (serverInstance != nil) {
        [serverInstance stopDriver];
        [serverInstance free];
        serverInstance = nil;
        IOLog("IBMThinkPad760EDDisplayDriverKernelServerInstance: Driver unloaded\n");
        return YES;
    }

    return NO;
}

- init
{
    [super init];

    driver = nil;
    kernelServer = KERN_SERV_NULL;

    return self;
}

- (void)free
{
    if (driver) {
        [driver free];
        driver = nil;
    }

    [super free];
}

- (kern_return_t)startDriver
{
    IODeviceMaster *deviceMaster;
    kern_return_t ret;

    IOLog("IBMThinkPad760EDDisplayDriverKernelServerInstance: Starting driver\n");

    /* Get device master */
    deviceMaster = [IODeviceMaster new];
    if (deviceMaster == nil) {
        IOLog("IBMThinkPad760EDDisplayDriverKernelServerInstance: Failed to get device master\n");
        return KERN_FAILURE;
    }

    /* Probe for devices */
    ret = [deviceMaster probe];
    if (ret != IO_R_SUCCESS) {
        IOLog("IBMThinkPad760EDDisplayDriverKernelServerInstance: Probe failed\n");
        [deviceMaster free];
        return KERN_FAILURE;
    }

    IOLog("IBMThinkPad760EDDisplayDriverKernelServerInstance: Driver started\n");

    return KERN_SUCCESS;
}

- (kern_return_t)stopDriver
{
    IOLog("IBMThinkPad760EDDisplayDriverKernelServerInstance: Stopping driver\n");

    if (driver) {
        [driver free];
        driver = nil;
    }

    return KERN_SUCCESS;
}

@end

/* Kernel server entry points */

kern_return_t IBMThinkPad760EDDisplayDriver_loadDriver(void)
{
    if ([IBMThinkPad760EDDisplayDriverKernelServerInstance loadDriver]) {
        return KERN_SUCCESS;
    }
    return KERN_FAILURE;
}

kern_return_t IBMThinkPad760EDDisplayDriver_unloadDriver(void)
{
    if ([IBMThinkPad760EDDisplayDriverKernelServerInstance unloadDriver]) {
        return KERN_SUCCESS;
    }
    return KERN_FAILURE;
}
