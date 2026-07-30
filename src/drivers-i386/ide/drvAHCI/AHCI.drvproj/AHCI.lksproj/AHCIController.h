#ifndef RHAPSODIOS_AHCI_CONTROLLER_H
#define RHAPSODIOS_AHCI_CONTROLLER_H

#import <driverkit/IODirectDevice.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>

@interface AHCIController : IODirectDevice
{
}

+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;
- (void)interruptOccurred;

@end

#endif
