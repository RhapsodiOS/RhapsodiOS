#ifndef RHAPSODIOS_AHCI_CONTROLLER_H
#define RHAPSODIOS_AHCI_CONTROLLER_H

#import <driverkit/IODirectDevice.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import "AHCIHBA.h"

@interface AHCIController : IODirectDevice
{
    vm_address_t abarAddress;
    volatile unsigned char *abar;
    BOOL abarMapped;
    AHCIHBAInfo hbaInfo;
}

+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;
- free;
- (void)interruptOccurred;

@end

#endif
