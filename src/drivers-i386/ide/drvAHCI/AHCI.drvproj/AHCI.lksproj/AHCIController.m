#import "AHCIController.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import "AHCIHBA.h"
#import "AHCIPCI.h"
#import "AHCIShared.h"

static int AHCIMMIOOffsetValid(AHCIMMIOContext *mmio, AHCIU32 offset)
{
    return !(mmio == 0 || mmio->base == 0 ||
             mmio->length < sizeof(AHCIU32) || (offset & 3U) != 0 ||
             offset > mmio->length - sizeof(AHCIU32));
}

static AHCIU32 AHCIMMIORead(void *context, AHCIU32 offset)
{
    AHCIMMIOContext *mmio;
    volatile AHCIU32 *reg;

    mmio = (AHCIMMIOContext *)context;
    if (!AHCIMMIOOffsetValid(mmio, offset))
        return 0xffffffffU;
    reg = (volatile AHCIU32 *)(mmio->base + offset);
    return *reg;
}

static void AHCIMMIOWrite(void *context, AHCIU32 offset, AHCIU32 value)
{
    AHCIMMIOContext *mmio;
    volatile AHCIU32 *reg;

    mmio = (AHCIMMIOContext *)context;
    if (!AHCIMMIOOffsetValid(mmio, offset))
        return;
    reg = (volatile AHCIU32 *)(mmio->base + offset);
    *reg = value;
}

static void AHCIMMIOBarrier(void *context)
{
    volatile AHCIU32 readback;

    readback = AHCIMMIORead(context, AHCI_REG_GHC);
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
    unsigned long command;
    unsigned long commandReadback;
    AHCIU32 abarPhysical;
    AHCIU32 enabledCommand;
    unsigned char commandChanged;
    IORange memoryRange;
    IOReturn mapResult;
    AHCIHBAOps ops;

    pciDeviceDescription = deviceDescription;
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
        AHCIPCIValidateBAR5((AHCIU32)bar5, AHCI_ABAR_LENGTH,
                            &abarPhysical) != AHCI_PCI_SUCCESS) {
        [self free];
        return nil;
    }

    if ([IODirectDevice getPCIConfigData:&command
              atRegister:AHCI_PCI_COMMAND_REGISTER
              withDeviceDescription:deviceDescription] != IO_R_SUCCESS) {
        [self free];
        return nil;
    }
    originalPCIConfig = (AHCIU32)command;
    if (AHCIPCIPlanCommand(originalPCIConfig, &enabledCommand,
                           &pciCommandRestore, &commandChanged) !=
        AHCI_PCI_SUCCESS) {
        [self free];
        return nil;
    }
    pciCommandChanged = commandChanged ? YES : NO;
    if (pciCommandChanged) {
        pciCommandWriteAttempted = YES;
        if ([IODirectDevice setPCIConfigData:enabledCommand
                  atRegister:AHCI_PCI_COMMAND_REGISTER
                  withDeviceDescription:deviceDescription] != IO_R_SUCCESS) {
            [self free];
            return nil;
        }
    }
    if ([IODirectDevice getPCIConfigData:&commandReadback
              atRegister:AHCI_PCI_COMMAND_REGISTER
              withDeviceDescription:deviceDescription] != IO_R_SUCCESS ||
        AHCIPCIValidateCommandReadback((AHCIU32)commandReadback) !=
            AHCI_PCI_SUCCESS) {
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
    mmio.base = (volatile unsigned char *)abarAddress;
    mmio.length = AHCI_ABAR_LENGTH;
    ops.context = &mmio;
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
    IOReturn restoreResult;

    if (abarMapped) {
        [self unmapMemoryRange:0 from:abarAddress];
        abarMapped = NO;
        abarAddress = 0;
        mmio.base = 0;
        mmio.length = 0;
    }
    if (pciCommandWriteAttempted && pciCommandChanged) {
        restoreResult = [IODirectDevice setPCIConfigData:pciCommandRestore
              atRegister:AHCI_PCI_COMMAND_REGISTER
              withDeviceDescription:pciDeviceDescription];
        if (restoreResult != IO_R_SUCCESS)
            IOLog("AHCI: failed to restore PCI command register\n");
        pciCommandWriteAttempted = NO;
        pciCommandChanged = NO;
    }
    return [super free];
}

- (void)interruptOccurred
{
    /* Task 9 installs per-port interrupt masks before global IE is enabled. */
}

@end
