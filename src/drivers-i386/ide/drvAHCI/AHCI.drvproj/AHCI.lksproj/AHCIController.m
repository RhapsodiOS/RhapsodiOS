#import "AHCIController.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/IOPCIDirectDevice.h>

#define AHCI_ICH9_PCI_ID 0x29228086
#define AHCI_PCI_CLASS_CODE 0x010601

@implementation AHCIController

+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription
{
    AHCIController *controller;

    controller = [[self alloc]
        initFromDeviceDescription:deviceDescription];
    if (controller == nil)
        return NO;
    [controller free];
    return NO;
}

- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription
{
    unsigned long pciID;
    unsigned long classRevision;

    [self setName:"AHCI"];
    [self setDeviceKind:"Other"];
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        [self free];
        return nil;
    }
    if ([self getPCIConfigData:&pciID atRegister:0x00] != IO_R_SUCCESS ||
        pciID != AHCI_ICH9_PCI_ID ||
        [self getPCIConfigData:&classRevision atRegister:0x08] != IO_R_SUCCESS ||
        ((classRevision >> 8) & 0x00ffffff) != AHCI_PCI_CLASS_CODE) {
        [self free];
        return nil;
    }

    IOLog("%s: Intel AHCI 8086:2922 class 01:06:01 matched; attachment deferred\n",
          [self name]);
    return self;
}

@end
