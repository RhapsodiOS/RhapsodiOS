#ifndef RHAPSODIOS_AHCI_CONTROLLER_H
#define RHAPSODIOS_AHCI_CONTROLLER_H

#import <driverkit/IODirectDevice.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <machkit/NXLock.h>
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
    NXLock *recoveryLock;
    BOOL hbaResetAlreadyTried;
    BOOL controllerOffline;
    BOOL controllerRecovering;
    AHCIRecoveryGate recoveryGate;
}

+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;
- free;
- (void)interruptOccurred;
- (void)recoverController;
- (BOOL)beginSubmission;
- (void)endSubmission;
- (BOOL)commitSubmission;
- (void)finishSubmissionCommit;

@end

#endif
