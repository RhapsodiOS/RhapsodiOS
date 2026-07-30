#import "AHCIController.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import "AHCIHBA.h"
#import "AHCIShared.h"

static AHCIU32 AHCIMMIORead(void *context, AHCIU32 offset)
{
    volatile unsigned char *base;
    volatile AHCIU32 *reg;

    base = (volatile unsigned char *)context;
    reg = (volatile AHCIU32 *)(base + offset);
    return *reg;
}

static void AHCIMMIOWrite(void *context, AHCIU32 offset, AHCIU32 value)
{
    volatile unsigned char *base;
    volatile AHCIU32 *reg;

    base = (volatile unsigned char *)context;
    reg = (volatile AHCIU32 *)(base + offset);
    *reg = value;
}

static void AHCIMMIOBarrier(void *context)
{
    volatile unsigned char *base;
    volatile AHCIU32 readback;

    base = (volatile unsigned char *)context;
    readback = *(volatile AHCIU32 *)(base + AHCI_REG_GHC);
    (void)readback;
}

static void AHCIDelayMilliseconds(void *context, unsigned int milliseconds)
{
    (void)context;
    IOSleep(milliseconds);
}

static int AHCIVersionIsCommon(AHCIU32 version)
{
    AHCIU32 major;
    AHCIU32 minor;
    AHCIU32 revision;

    major = version >> 16;
    minor = (version >> 8) & 0xffU;
    revision = version & 0xffU;
    return major == 1U &&
           (minor < 3U || (minor == 3U && revision <= 1U));
}

@implementation AHCIController

+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription
{
    AHCIController *controller;

    controller = [[self alloc]
        initFromDeviceDescription:deviceDescription];
    if (controller == nil)
        return NO;
    if ([controller registerDevice] == nil) {
        [controller free];
        return NO;
    }
    return YES;
}

- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription
{
    unsigned long pciID;
    unsigned long classRevision;
    unsigned long bar5;
    unsigned long abarPhysical;
    unsigned long command;
    unsigned long enabledCommand;
    unsigned long commandReadback;
    IORange memoryRange;
    IOReturn mapResult;
    AHCIHBAOps ops;

    if ([IODirectDevice getPCIConfigData:&pciID
              atRegister:AHCI_PCI_ID_REGISTER
              withDeviceDescription:deviceDescription] != IO_R_SUCCESS ||
        pciID != AHCI_ICH9_PCI_ID ||
        [IODirectDevice getPCIConfigData:&classRevision
              atRegister:AHCI_PCI_CLASS_REGISTER
              withDeviceDescription:deviceDescription] != IO_R_SUCCESS ||
        ((classRevision >> 8) & 0x00ffffff) != AHCI_PCI_CLASS_CODE) {
        [self free];
        return nil;
    }

    if ([IODirectDevice getPCIConfigData:&bar5
              atRegister:AHCI_PCI_BAR5_REGISTER
              withDeviceDescription:deviceDescription] != IO_R_SUCCESS ||
        bar5 == 0 || bar5 == 0xffffffffU ||
        (bar5 & AHCI_PCI_BAR_IO) != 0 ||
        (bar5 & AHCI_PCI_BAR_TYPE_MASK) != AHCI_PCI_BAR_TYPE_32 ||
        (bar5 & AHCI_PCI_BAR_PREFETCH) != 0) {
        [self free];
        return nil;
    }
    abarPhysical = bar5 & AHCI_PCI_BAR_MEMORY_MASK;
    if (abarPhysical == 0 ||
        abarPhysical == AHCI_PCI_BAR_MEMORY_MASK ||
        abarPhysical > 0xffffffffU - (AHCI_ABAR_LENGTH - 1U)) {
        [self free];
        return nil;
    }

    if ([IODirectDevice getPCIConfigData:&command
              atRegister:AHCI_PCI_COMMAND_REGISTER
              withDeviceDescription:deviceDescription] != IO_R_SUCCESS) {
        [self free];
        return nil;
    }
    enabledCommand = command | AHCI_PCI_COMMAND_MEMORY |
                     AHCI_PCI_COMMAND_MASTER;
    if ([IODirectDevice setPCIConfigData:enabledCommand
              atRegister:AHCI_PCI_COMMAND_REGISTER
              withDeviceDescription:deviceDescription] != IO_R_SUCCESS ||
        [IODirectDevice getPCIConfigData:&commandReadback
              atRegister:AHCI_PCI_COMMAND_REGISTER
              withDeviceDescription:deviceDescription] != IO_R_SUCCESS ||
        (commandReadback & (AHCI_PCI_COMMAND_MEMORY |
                            AHCI_PCI_COMMAND_MASTER)) !=
            (AHCI_PCI_COMMAND_MEMORY | AHCI_PCI_COMMAND_MASTER)) {
        [self free];
        return nil;
    }

    memoryRange.start = abarPhysical;
    memoryRange.size = AHCI_ABAR_LENGTH;
    if ([deviceDescription setMemoryRangeList:&memoryRange num:1] !=
        IO_R_SUCCESS) {
        [self free];
        return nil;
    }

    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        [self free];
        return nil;
    }
    [self setName:"AHCI"];
    [self setDeviceKind:"Other"];
    abarAddress = 0;
    mapResult = [self mapMemoryRange:0 to:&abarAddress findSpace:YES
                      cache:IO_CacheOff];
    if (mapResult != IO_R_SUCCESS) {
        [self free];
        return nil;
    }
    abarMapped = YES;
    if (abarAddress == 0 || (abarAddress & 3U) != 0) {
        [self free];
        return nil;
    }
    abar = (volatile unsigned char *)abarAddress;

    ops.context = (void *)abar;
    ops.read = AHCIMMIORead;
    ops.write = AHCIMMIOWrite;
    ops.delay = AHCIDelayMilliseconds;
    ops.barrier = AHCIMMIOBarrier;
    if (AHCIHBAInitialize(&ops, &hbaInfo) != AHCI_HBA_SUCCESS) {
        [self free];
        return nil;
    }

    if (!AHCIVersionIsCommon(hbaInfo.version))
        IOLog("%s: AHCI version %x is newer or unknown; using common register subset\n",
              [self name], hbaInfo.version);

    IOLog("%s: Intel AHCI 8086:2922 class 01:06:01 version %x CAP %08x CAP2 %08x PI %08x attached\n",
          [self name], hbaInfo.version, hbaInfo.capabilities,
          hbaInfo.capabilities2, hbaInfo.portsImplemented);
    return self;
}

- free
{
    if (abarMapped) {
        [self unmapMemoryRange:0 from:abarAddress];
        abarMapped = NO;
        abarAddress = 0;
        abar = 0;
    }
    return [super free];
}

- (void)interruptOccurred
{
    /* Task 9 installs per-port interrupt masks before global IE is enabled. */
}

@end
