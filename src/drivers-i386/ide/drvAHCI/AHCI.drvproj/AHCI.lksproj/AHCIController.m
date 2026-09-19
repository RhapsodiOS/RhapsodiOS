#import "AHCIController.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import "AHCIHBA.h"
#import "AHCIPCI.h"
#import "AHCIShared.h"
#import "AHCIPort.h"
#import "AHCIState.h"
#import "AHCIDisk.h"
#import <bsd/dev/ata_hd_registry.h>

#define AHCI_SUBMISSION_DRAIN_TIMEOUT_MS 11000U

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

    if (!ata_hd_devsw_init([AHCIDisk class], deviceDescription)) {
        IOLog("AHCI: failed to initialize shared hd devsw tables.\n");
        return NO;
    }
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
    unsigned long interruptConfig;
    AHCIU32 abarPhysical;
    AHCIU32 enabledCommand;
    unsigned char commandChanged;
    IORange memoryRange;
    IOReturn mapResult;
    AHCIHBAOps ops;
    unsigned int interruptLine;
    unsigned char implementedPorts[AHCI_MAX_PORTS];
    unsigned int implementedCount;
    unsigned int portIndex;
    int port;
    AHCIDeviceKind kind;
    AHCIU32 ghc;

    pciDeviceDescription = deviceDescription;
    if ([IODirectDevice getPCIConfigData:&pciID
              atRegister:AHCI_PCI_ID_REGISTER
              withDeviceDescription:deviceDescription] != IO_R_SUCCESS ||
        pciID != AHCI_ICH9_PCI_ID ||
        [IODirectDevice getPCIConfigData:&classRevision
              atRegister:AHCI_PCI_CLASS_REGISTER
              withDeviceDescription:deviceDescription] != IO_R_SUCCESS ||
        ((classRevision >> 8) & 0x00ffffff) != AHCI_PCI_CLASS_CODE) {
        IOLog("AHCI: PCI identity or class register is not ICH9-AHCI.\n");
        [self free];
        return nil;
    }

    if ([IODirectDevice getPCIConfigData:&bar5
              atRegister:AHCI_PCI_BAR5_REGISTER
              withDeviceDescription:deviceDescription] != IO_R_SUCCESS ||
        AHCIPCIValidateBAR5((AHCIU32)bar5, AHCI_ABAR_LENGTH,
                            &abarPhysical) != AHCI_PCI_SUCCESS) {
        IOLog("AHCI: BAR5 is missing or not a usable ABAR.\n");
        [self free];
        return nil;
    }

    if ([IODirectDevice getPCIConfigData:&command
              atRegister:AHCI_PCI_COMMAND_REGISTER
              withDeviceDescription:deviceDescription] != IO_R_SUCCESS) {
        IOLog("AHCI: cannot read the PCI command register.\n");
        [self free];
        return nil;
    }
    originalPCIConfig = (AHCIU32)command;
    if (AHCIPCIPlanCommand(originalPCIConfig, &enabledCommand,
                           &pciCommandRestore, &commandChanged) !=
        AHCI_PCI_SUCCESS) {
        IOLog("AHCI: cannot plan the PCI command register update.\n");
        [self free];
        return nil;
    }
    pciCommandChanged = commandChanged ? YES : NO;
    if (pciCommandChanged) {
        pciCommandWriteAttempted = YES;
        if ([IODirectDevice setPCIConfigData:enabledCommand
                  atRegister:AHCI_PCI_COMMAND_REGISTER
                  withDeviceDescription:deviceDescription] != IO_R_SUCCESS) {
            IOLog("AHCI: cannot enable PCI memory space and bus mastering.\n");
            [self free];
            return nil;
        }
    }
    if ([IODirectDevice getPCIConfigData:&commandReadback
              atRegister:AHCI_PCI_COMMAND_REGISTER
              withDeviceDescription:deviceDescription] != IO_R_SUCCESS ||
        AHCIPCIValidateCommandReadback((AHCIU32)commandReadback) !=
            AHCI_PCI_SUCCESS) {
        IOLog("AHCI: PCI command register did not hold the enabled bits.\n");
        [self free];
        return nil;
    }

    if ([IODirectDevice getPCIConfigData:&interruptConfig
              atRegister:AHCI_PCI_INTERRUPT_REGISTER
              withDeviceDescription:deviceDescription] != IO_R_SUCCESS) {
        IOLog("AHCI: cannot read the PCI interrupt register.\n");
        [self free];
        return nil;
    }
    if (AHCIPCIInterruptLine((AHCIU32)interruptConfig, &interruptLine) !=
            AHCI_PCI_SUCCESS ||
        [deviceDescription setInterruptList:&interruptLine num:1] !=
            IO_R_SUCCESS) {
        IOLog("AHCI: no usable PCI interrupt line.\n");
        [self free];
        return nil;
    }

    memoryRange.start = abarPhysical;
    memoryRange.size = AHCI_ABAR_LENGTH;
    if ([deviceDescription setMemoryRangeList:&memoryRange num:1] !=
        IO_R_SUCCESS) {
        IOLog("AHCI: cannot register the ABAR memory range.\n");
        [self free];
        return nil;
    }

    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        IOLog("AHCI: IODirectDevice initialisation failed.\n");
        [self free];
        return nil;
    }
    recoveryLock = [[NXLock alloc] init];
    if (recoveryLock == nil) {
        IOLog("AHCI: cannot allocate the recovery lock.\n");
        [self free];
        return nil;
    }
    AHCIRecoveryGateInit(&recoveryGate);
    [self setName:"AHCI"];
    [self setDeviceKind:"Other"];
    abarAddress = 0;
    mapResult = [self mapMemoryRange:0 to:&abarAddress findSpace:YES
                      cache:IO_CacheOff];
    if (mapResult != IO_R_SUCCESS) {
        IOLog("AHCI: cannot map the ABAR into kernel space.\n");
        [self free];
        return nil;
    }
    abarMapped = YES;
    if (abarAddress == 0 || (abarAddress & 3U) != 0) {
        IOLog("AHCI: mapped ABAR address is null or misaligned.\n");
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
        IOLog("AHCI: HBA reset and initialisation failed.\n");
        [self free];
        return nil;
    }

    implementedCount = AHCIPortCollectImplemented(
        hbaInfo.portsImplemented, implementedPorts, AHCI_MAX_PORTS);
    if (implementedCount == 0 || implementedCount > AHCI_MAX_PORTS) {
        IOLog("AHCI: HBA reports no usable implemented ports.\n");
        [self free];
        return nil;
    }
    for (portIndex = 0; portIndex < implementedCount; ++portIndex) {
        port = (int)implementedPorts[portIndex];
        ports[port] = [[AHCIPort alloc] initWithMMIO:&mmio
                                                port:(unsigned int)port
                                        capabilities:hbaInfo.capabilities];
        if (ports[port] == nil) {
            IOLog("AHCI: cannot allocate a port object.\n");
            [self free];
            return nil;
        }
        [ports[port] setController:self];
        ++portCount;
        kind = [ports[port] deviceKind];
        if (kind == AHCI_DEVICE_SATA)
            IOLog("%s: port %d SATA device detected\n", [self name], port);
        else if (kind == AHCI_DEVICE_ATAPI)
            IOLog("%s: port %d ATAPI device detected\n", [self name], port);
        else if (kind == AHCI_DEVICE_UNSUPPORTED)
            IOLog("%s: port %d unsupported signature\n", [self name], port);
        else
            IOLog("%s: port %d empty\n", [self name], port);
    }
    if (portCount != implementedCount) {
        IOLog("AHCI: port count disagrees with the implemented mask.\n");
        [self free];
        return nil;
    }
    if ([self startIOThread] != IO_R_SUCCESS) {
        IOLog("AHCI: cannot start the I/O thread.\n");
        [self free];
        return nil;
    }
    if ([self enableAllInterrupts] != IO_R_SUCCESS) {
        [self disableAllInterrupts];
        IOLog("AHCI: cannot enable controller interrupts.\n");
        [self free];
        return nil;
    }
    driverKitInterruptsEnabled = YES;
    globalInterruptsEnabled = YES;
    ghc = AHCIMMIORead(&mmio, AHCI_REG_GHC);
    AHCIMMIOWrite(&mmio, AHCI_REG_GHC,
                  ghc | AHCI_GHC_AE | AHCI_GHC_IE);
    AHCIMMIOBarrier(&mmio);

    for (portIndex = 0; portIndex < implementedCount; ++portIndex) {
        port = (int)implementedPorts[portIndex];
        if ([ports[port] deviceKind] == AHCI_DEVICE_SATA &&
            ![ports[port]
                publishDiskFromDeviceDescription:deviceDescription])
            IOLog("%s: port %d SATA disk was not published\n",
                  [self name], port);
        if ([ports[port] deviceKind] == AHCI_DEVICE_ATAPI &&
            ![ports[port]
                publishATAPIFromDeviceDescription:deviceDescription])
            IOLog("%s: port %d ATAPI device was not published\n",
                  [self name], port);
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
    AHCIU32 ghc;
    unsigned int port;

    for (port = 0; port < AHCI_MAX_PORTS; ++port) {
        if (ports[port] != nil && ![ports[port] unpublishDisk]) {
            IOLog("%s: retaining controller while hd registry is busy\n",
                  [self name]);
            return self;
        }
        if (ports[port] != nil && ![ports[port] unpublishATAPI]) {
            IOLog("%s: retaining controller while ATAPI child is busy\n",
                  [self name]);
            return self;
        }
    }

    if (globalInterruptsEnabled && mmio.base != 0) {
        ghc = AHCIMMIORead(&mmio, AHCI_REG_GHC);
        AHCIMMIOWrite(&mmio, AHCI_REG_GHC, ghc & ~AHCI_GHC_IE);
        AHCIMMIOBarrier(&mmio);
        globalInterruptsEnabled = NO;
    }
    if (driverKitInterruptsEnabled) {
        [self disableAllInterrupts];
        driverKitInterruptsEnabled = NO;
    }
    for (port = 0; port < AHCI_MAX_PORTS; ++port) {
        if (ports[port] != nil) {
            [ports[port] free];
            ports[port] = nil;
        }
    }
    portCount = 0;

    if (recoveryLock != nil) {
        [recoveryLock free];
        recoveryLock = nil;
    }

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

- (BOOL)recoverController
{
    AHCIHBAOps ops;
    AHCIHBAResult resetResult;
    AHCIU32 ghc;
    unsigned int port;
    unsigned int waited;
    int drained;

    if (recoveryLock == nil)
        return NO;
    [recoveryLock lock];
    if (!AHCIRecoveryGateStart(&recoveryGate)) {
        [recoveryLock unlock];
        return NO;
    }
    controllerRecovering = YES;
    hbaResetAlreadyTried = YES;
    [recoveryLock unlock];

    waited = 0;
    drained = 0;
    for (;;) {
        [recoveryLock lock];
        drained = AHCIRecoveryGateDrained(&recoveryGate);
        [recoveryLock unlock];
        if (drained || waited >= AHCI_SUBMISSION_DRAIN_TIMEOUT_MS)
            break;
        IOSleep(AHCI_POLL_INTERVAL_MS);
        waited += AHCI_POLL_INTERVAL_MS;
    }
    if (!drained) {
        [recoveryLock lock];
        AHCIRecoveryGateComplete(&recoveryGate, 0);
        controllerOffline = YES;
        controllerRecovering = NO;
        [recoveryLock unlock];
        return NO;
    }
    globalInterruptsEnabled = NO;
    ghc = AHCIMMIORead(&mmio, AHCI_REG_GHC);
    AHCIMMIOWrite(&mmio, AHCI_REG_GHC, ghc & ~AHCI_GHC_IE);
    AHCIMMIOBarrier(&mmio);
    for (port = 0; port < AHCI_MAX_PORTS; ++port) {
        if (ports[port] != nil)
            [ports[port] controllerWillReset];
    }
    ops.context = &mmio;
    ops.read = AHCIMMIORead;
    ops.write = AHCIMMIOWrite;
    ops.delay = AHCIDelayMilliseconds;
    ops.barrier = AHCIMMIOBarrier;
    resetResult = AHCIHBAInitialize(&ops, &hbaInfo);
    if (resetResult != AHCI_HBA_SUCCESS) {
        controllerOffline = YES;
        controllerRecovering = NO;
        for (port = 0; port < AHCI_MAX_PORTS; ++port) {
            if (ports[port] != nil)
                [ports[port] controllerResetFailed];
        }
        [recoveryLock lock];
        AHCIRecoveryGateComplete(&recoveryGate, 0);
        [recoveryLock unlock];
        return NO;
    }
    for (port = 0; port < AHCI_MAX_PORTS; ++port) {
        if (ports[port] != nil)
            [ports[port] controllerDidReset];
    }
    ghc = AHCIMMIORead(&mmio, AHCI_REG_GHC);
    AHCIMMIOWrite(&mmio, AHCI_REG_GHC,
                  ghc | AHCI_GHC_AE | AHCI_GHC_IE);
    AHCIMMIOBarrier(&mmio);
    globalInterruptsEnabled = YES;
    hbaResetAlreadyTried = NO;
    controllerRecovering = NO;
    [recoveryLock lock];
    AHCIRecoveryGateComplete(&recoveryGate, 1);
    [recoveryLock unlock];
    return YES;
}

- (BOOL)beginSubmission
{
    BOOL allowed;

    [recoveryLock lock];
    allowed = AHCIRecoveryGateBeginSubmission(&recoveryGate) ? YES : NO;
    [recoveryLock unlock];
    return allowed;
}

- (void)endSubmission
{
    [recoveryLock lock];
    AHCIRecoveryGateEndSubmission(&recoveryGate);
    [recoveryLock unlock];
}

- (BOOL)commitSubmission
{
    BOOL allowed;

    [recoveryLock lock];
    allowed = AHCIRecoveryGateCommitSubmission(&recoveryGate) ? YES : NO;
    if (!allowed)
        [recoveryLock unlock];
    return allowed;
}

- (void)finishSubmissionCommit
{
    [recoveryLock unlock];
}

- (void)interruptOccurred
{
    AHCIU32 asserted;
    AHCIU32 ghc;
    int port;

    driverKitInterruptsEnabled = NO;
    asserted = 0;
    if (globalInterruptsEnabled && mmio.base != 0) {
        asserted = AHCIMMIORead(&mmio, AHCI_REG_IS) &
                   hbaInfo.portsImplemented;
        for (port = AHCINextPort(asserted, -1);
             port >= 0;
             port = AHCINextPort(asserted, port)) {
            if (ports[port] != nil)
                [ports[port] handleInterrupt];
        }
        if (asserted != 0) {
            AHCIMMIOWrite(&mmio, AHCI_REG_IS, asserted);
            AHCIMMIOBarrier(&mmio);
        }
    }
    if ([self enableAllInterrupts] == IO_R_SUCCESS) {
        driverKitInterruptsEnabled = YES;
    } else {
        if (globalInterruptsEnabled && mmio.base != 0) {
            ghc = AHCIMMIORead(&mmio, AHCI_REG_GHC);
            AHCIMMIOWrite(&mmio, AHCI_REG_GHC, ghc & ~AHCI_GHC_IE);
            AHCIMMIOBarrier(&mmio);
            globalInterruptsEnabled = NO;
        }
        IOLog("AHCI: failed to re-enable DriverKit interrupts\n");
    }
}

@end
