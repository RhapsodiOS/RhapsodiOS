/*
 * ES1x88AudioDriverKernelServerInstance.h
 * Kernel Server Instance for ES1x88 Audio Driver
 */

#import <objc/Object.h>
#import <driverkit/IODevice.h>

@interface ES1x88AudioDriverKernelServerInstance : Object
{
    id driver;
    IOObjectNumber deviceNumber;
}

- initWithDriver:driverInstance;
- (IOReturn)probe:(IODeviceDescription *)deviceDescription;
- (IOReturn)startDriver;
- (IOReturn)stopDriver;
- (void)free;

@end
