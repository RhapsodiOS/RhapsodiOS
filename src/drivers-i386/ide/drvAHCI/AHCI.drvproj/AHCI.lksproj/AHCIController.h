#ifndef RHAPSODIOS_AHCI_CONTROLLER_H
#define RHAPSODIOS_AHCI_CONTROLLER_H

#import <driverkit/IODirectDevice.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import "AHCIHBA.h"
#import "AHCIPCI.h"
#import "AHCIShared.h"
#import "AHCIPort.h"

@interface AHCIController : IODirectDevice
{
    vm_address_t abarAddress;
    BOOL abarMapped;
    IOPCIDeviceDescription *pciDeviceDescription;
    AHCIU32 originalPCIConfig;
    AHCIU32 pciCommandRestore;
    BOOL pciCommandWriteAttempted;
    BOOL pciCommandChanged;
    AHCIMMIOContext mmio;
    AHCIHBAInfo hbaInfo;
    AHCIPort *ports[AHCI_MAX_PORTS];
    unsigned int portCount;
    BOOL driverKitInterruptsEnabled;
    BOOL globalInterruptsEnabled;
}

+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;
- free;
- (void)interruptOccurred;

@end

#endif
