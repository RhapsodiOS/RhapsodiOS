/*
 * ES1x88AudioDriverKernelServerInstance.m
 * Kernel Server Instance for ES1x88 Audio Driver
 */

#import "ES1x88AudioDriverKernelServerInstance.h"
#import "ES1x88AudioDriver.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

@implementation ES1x88AudioDriverKernelServerInstance

- initWithDriver:driverInstance
{
    [super init];
    driver = driverInstance;
    return self;
}

- (IOReturn)probe:(IODeviceDescription *)deviceDescription
{
    if ([ES1x88AudioDriver probe:deviceDescription]) {
        return IO_R_SUCCESS;
    }
    return IO_R_NOT_FOUND;
}

- (IOReturn)startDriver
{
    if (driver == nil)
        return IO_R_NO_DEVICE;

    // Configure hardware
    [driver configureHardware];

    // Enable interrupts
    [driver enableAllInterrupts];

    IOLog("ES1x88AudioDriver: Started successfully\n");

    return IO_R_SUCCESS;
}

- (IOReturn)stopDriver
{
    if (driver == nil)
        return IO_R_NO_DEVICE;

    // Disable interrupts
    [driver disableAllInterrupts];

    // Stop any ongoing DMA
    [driver stopDMA];

    IOLog("ES1x88AudioDriver: Stopped\n");

    return IO_R_SUCCESS;
}

- (void)free
{
    if (driver) {
        [driver free];
        driver = nil;
    }
    [super free];
}

@end
