#import "AHCIPort.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/kernelDriver.h>
#import <mach/mach_interface.h>
#import <string.h>

extern unsigned int vm_page_size;

#define AHCI_LOCK_IDLE       0
#define AHCI_LOCK_PENDING    1
#define AHCI_LOCK_DONE       2
#define AHCI_TFD_BSY         0x80U
#define AHCI_TFD_DRQ         0x08U

@interface AHCIPort(Task10Private)
- (void)timeoutFired;
- (void)recoverCommand;
- (void)finishDeferredFree;
@end

@interface Object(AHCIControllerRecovery)
- (void)recoverController;
@end

static void AHCIPortTimeout(void *argument)
{
    [(AHCIPort *)argument timeoutFired];
}

static int AHCIPortMMIOValid(AHCIMMIOContext *context, AHCIU32 offset)
{
    return context != 0 && context->base != 0 &&
           context->length >= sizeof(AHCIU32) && (offset & 3U) == 0 &&
           offset <= context->length - sizeof(AHCIU32);
}

static AHCIU32 AHCIPortMMIORead(void *context, AHCIU32 offset)
{
    AHCIMMIOContext *mapped;

    mapped = (AHCIMMIOContext *)context;
    if (!AHCIPortMMIOValid(mapped, offset))
        return 0xffffffffU;
    return *(volatile AHCIU32 *)(mapped->base + offset);
}

static void AHCIPortMMIOWrite(void *context, AHCIU32 offset,
                              AHCIU32 value)
{
    AHCIMMIOContext *mapped;

    mapped = (AHCIMMIOContext *)context;
    if (!AHCIPortMMIOValid(mapped, offset))
        return;
    *(volatile AHCIU32 *)(mapped->base + offset) = value;
}

static void AHCIPortMMIOBarrier(void *context)
{
    volatile AHCIU32 readback;

    readback = AHCIPortMMIORead(context, AHCI_REG_GHC);
    (void)readback;
}

static void AHCIPortDelayMilliseconds(void *context,
                                      unsigned int milliseconds)
{
    (void)context;
    IOSleep(milliseconds);
}

static int AHCIPortTranslateAddress(void *context,
                                    unsigned long virtualAddress,
                                    AHCIU32 *physicalAddress)
{
    vm_offset_t physical;

    (void)context;
    if (physicalAddress == 0 ||
        IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)virtualAddress,
                              &physical) != IO_R_SUCCESS)
        return 0;
    *physicalAddress = (AHCIU32)physical;
    return (vm_offset_t)*physicalAddress == physical;
}

static void AHCIPortFillOps(AHCIPortOps *ops, AHCIMMIOContext *context)
{
    ops->context = context;
    ops->read = AHCIPortMMIORead;
    ops->write = AHCIPortMMIOWrite;
    ops->delay = AHCIPortDelayMilliseconds;
    ops->barrier = AHCIPortMMIOBarrier;
}

@implementation AHCIPort

- initWithMMIO:(AHCIMMIOContext *)context
           port:(unsigned int)number
   capabilities:(AHCIU32)capabilities
{
    AHCIPortOps ops;
    AHCIPortResult result;
    AHCICommandHeader *commandList;

    self = [super init];
    if (self == nil)
        return nil;
    if (context == 0 || number >= 32U || vm_page_size < 1024U ||
        (vm_page_size & (vm_page_size - 1U)) != 0) {
        [self free];
        return nil;
    }
    mmio = context;
    portNumber = number;
    portCapabilities = capabilities;
    commandLock = [[NXConditionLock alloc] initWith:AHCI_LOCK_IDLE];
    if (commandLock == nil) {
        [self free];
        return nil;
    }
    AHCICommandArbiterInit(&commandArbiter);
    rawArenaBytes = AHCI_PORT_ARENA_USABLE_BYTES + vm_page_size - 1U;
    rawArena = IOMallocLow(rawArenaBytes);
    if (rawArena == 0) {
        [self free];
        return nil;
    }
    result = AHCIPortPrepareArena((unsigned long)rawArena, rawArenaBytes,
                                  vm_page_size, AHCIPortTranslateAddress, 0,
                                  &arena);
    if (result != AHCI_PORT_SUCCESS) {
        [self free];
        return nil;
    }
    bzero((void *)arena.virtualBase, arena.usableBytes);
    commandList = (AHCICommandHeader *)
                  (arena.virtualBase + arena.commandListOffset);
    commandList[0].ctba = arena.physicalBase + arena.commandTableOffset;
    commandList[0].ctbau = 0;

    AHCIPortFillOps(&ops, mmio);
    hardwareTouched = YES;
    result = AHCIPortInitializeHardware(&ops, portNumber, capabilities,
                                        &arena, &deviceKind);
    if (result != AHCI_PORT_SUCCESS) {
        [self free];
        return nil;
    }
    online = deviceKind == AHCI_DEVICE_SATA ||
             deviceKind == AHCI_DEVICE_ATAPI;
    return self;
}

- free
{
    AHCIPortOps ops;
    AHCIPortResult stopResult;
    BOOL defer;

    defer = NO;
    if (commandLock != nil) {
        [commandLock lock];
        destroying = YES;
        online = NO;
        skipCommandRecovery = YES;
        if (AHCICommandAbort(&commandArbiter)) {
            commandResult = IO_R_OFFLINE;
            [commandLock unlockWith:AHCI_LOCK_DONE];
        } else {
            [commandLock unlockWith:
                commandArbiter.state == AHCI_COMMAND_PENDING ?
                AHCI_LOCK_PENDING :
                (commandArbiter.state == AHCI_COMMAND_IDLE ?
                 AHCI_LOCK_IDLE : AHCI_LOCK_DONE)];
        }
    }
    stopResult = AHCI_PORT_SUCCESS;
    if (hardwareTouched && mmio != 0 && mmio->base != 0) {
        AHCIPortFillOps(&ops, mmio);
        stopResult = AHCIPortStopHardware(&ops, portNumber);
        hardwareTouched = NO;
    }
    if (commandLock != nil) {
        [commandLock lock];
        deferredArenaRelease = AHCIPortArenaMayRelease(stopResult) ?
                               YES : NO;
        quiesceComplete = YES;
        defer = timeoutArmed || activeExecutors != 0;
        mmio = 0;
        [commandLock unlock];
        if (defer)
            return self;
    }
    if (AHCIPortArenaMayRelease(stopResult) && rawArena != 0) {
        IOFreeLow(rawArena, rawArenaBytes);
        rawArena = 0;
        rawArenaBytes = 0;
    } else if (rawArena != 0) {
        IOLog("AHCI: port %u engine did not stop; preserving DMA arena\n",
              portNumber);
    }
    if (commandLock != nil) {
        [commandLock free];
        commandLock = nil;
    }
    mmio = 0;
    return [super free];
}

- (void)finishDeferredFree
{
    if (deferredArenaRelease && rawArena != 0) {
        IOFreeLow(rawArena, rawArenaBytes);
        rawArena = 0;
        rawArenaBytes = 0;
    } else if (rawArena != 0) {
        IOLog("AHCI: port %u engine did not stop; preserving DMA arena\n",
              portNumber);
    }
    if (commandLock != nil) {
        [commandLock free];
        commandLock = nil;
    }
    [super free];
}

- (void)setController:(id)owner
{
    controller = owner;
}

- (BOOL)controllerDidReset
{
    AHCIPortOps ops;
    AHCIPortResult result;
    AHCIDeviceKind previousKind;
    AHCIDeviceKind recoveredKind;

    [commandLock lock];
    if (destroying) {
        [commandLock unlockWith:AHCI_LOCK_DONE];
        return NO;
    }
    previousKind = deviceKind;
    AHCIPortFillOps(&ops, mmio);
    result = AHCIPortInitializeHardware(&ops, portNumber, portCapabilities,
                                        &arena, &recoveredKind);
    online = result == AHCI_PORT_SUCCESS &&
             AHCIRecoveredKindValid(previousKind, recoveredKind);
    if (online)
        deviceKind = recoveredKind;
    if (commandArbiter.state == AHCI_COMMAND_PENDING &&
        AHCICommandFinishIRQ(&commandArbiter, commandArbiter.generation)) {
        controllerResetting = NO;
        [commandLock unlockWith:AHCI_LOCK_DONE];
    } else {
        int condition;

        controllerResetting = NO;
        condition = commandArbiter.state == AHCI_COMMAND_IDLE ?
                    AHCI_LOCK_IDLE : AHCI_LOCK_DONE;
        [commandLock unlockWith:condition];
    }
    return online;
}

- (void)controllerResetFailed
{
    [commandLock lock];
    online = NO;
    if (commandArbiter.state == AHCI_COMMAND_PENDING &&
        AHCICommandFinishIRQ(&commandArbiter, commandArbiter.generation)) {
        controllerResetting = NO;
        [commandLock unlockWith:AHCI_LOCK_DONE];
    } else {
        int condition;

        controllerResetting = NO;
        condition = commandArbiter.state == AHCI_COMMAND_IDLE ?
                    AHCI_LOCK_IDLE : AHCI_LOCK_DONE;
        [commandLock unlockWith:condition];
    }
}

- (void)controllerWillReset
{
    [commandLock lock];
    controllerResetting = YES;
    online = NO;
    if (commandArbiter.state == AHCI_COMMAND_PENDING) {
        skipCommandRecovery = YES;
        commandResult = IO_R_IO;
    }
    [commandLock unlockWith:
        commandArbiter.state == AHCI_COMMAND_PENDING ?
        AHCI_LOCK_PENDING :
        (commandArbiter.state == AHCI_COMMAND_IDLE ?
         AHCI_LOCK_IDLE : AHCI_LOCK_DONE)];
}

- (void)timeoutFired
{
    int condition;
    ns_time_t now;
    unsigned long nowSeconds;

    [commandLock lock];
    if (destroying) {
        if (!quiesceComplete || activeExecutors != 0) {
            timeoutArmed = YES;
            IOScheduleFunc(AHCIPortTimeout, self, 1);
            [commandLock unlockWith:AHCI_LOCK_DONE];
            return;
        }
        timeoutArmed = NO;
        [commandLock unlockWith:AHCI_LOCK_DONE];
        [self finishDeferredFree];
        return;
    }
    if (controllerResetting) {
        timeoutArmed = YES;
        IOScheduleFunc(AHCIPortTimeout, self, 1);
        [commandLock unlockWith:AHCI_LOCK_PENDING];
        return;
    }
    IOGetTimestamp(&now);
    nowSeconds = (unsigned long)(now / 1000000000ULL);
    if (commandArbiter.state == AHCI_COMMAND_PENDING &&
        armedGeneration != commandArbiter.generation)
        armedGeneration = commandArbiter.generation;
    if (AHCICommandTimeoutDue(&commandArbiter, timeoutDeadlineSeconds,
                              nowSeconds) &&
        AHCICommandFinishTimeout(&commandArbiter, armedGeneration)) {
        timeoutArmed = NO;
        commandResult = IO_R_TIMEOUT;
        [commandLock unlockWith:AHCI_LOCK_DONE];
        return;
    }
    if (commandArbiter.state == AHCI_COMMAND_PENDING) {
        armedGeneration = commandArbiter.generation;
        IOScheduleFunc(AHCIPortTimeout, self, 1);
        [commandLock unlockWith:AHCI_LOCK_PENDING];
        return;
    }
    timeoutArmed = NO;
    condition = commandArbiter.state == AHCI_COMMAND_PENDING ?
                AHCI_LOCK_PENDING :
                (commandArbiter.state == AHCI_COMMAND_IDLE ?
                 AHCI_LOCK_IDLE : AHCI_LOCK_DONE);
    [commandLock unlockWith:condition];
}

- (void)recoverCommand
{
    AHCIPortOps ops;
    AHCIPortResult result;
    AHCIDeviceKind previousKind;
    AHCIDeviceKind recoveredKind;

    [commandLock lock];
    if (destroying) {
        [commandLock unlockWith:AHCI_LOCK_DONE];
        return;
    }
    if (AHCIRecoveryFor(completionSnapshot.portIS,
                        completionSnapshot.serr, 1, 0) ==
        AHCI_RECOVERY_HBA) {
        online = NO;
        [commandLock unlockWith:AHCI_LOCK_DONE];
        if (controller != nil)
            [controller recoverController];
        return;
    }

    previousKind = deviceKind;
    AHCIPortFillOps(&ops, mmio);
    result = AHCIPortRecoverHardware(&ops, portNumber, &arena);
    recoveredKind = result == AHCI_PORT_SUCCESS ?
        AHCIClassifyPort(AHCIPortMMIORead(mmio,
                         AHCI_PORT_BASE(portNumber) + AHCI_PX_SSTS),
                         AHCIPortMMIORead(mmio,
                         AHCI_PORT_BASE(portNumber) + AHCI_PX_SIG)) :
        AHCI_DEVICE_NONE;
    if (result == AHCI_PORT_SUCCESS &&
        AHCIRecoveredKindValid(previousKind, recoveredKind)) {
        deviceKind = recoveredKind;
        online = YES;
        [commandLock unlockWith:AHCI_LOCK_DONE];
        return;
    }
    online = NO;
    [commandLock unlockWith:AHCI_LOCK_DONE];
    if (result == AHCI_PORT_ENGINE_TIMEOUT && controller != nil)
        [controller recoverController];
}

- (IOReturn)executeATA:(unsigned char)command
                   fis:(const unsigned char *)fis
                packet:(const unsigned char *)packet
                buffer:(void *)buffer
                length:(unsigned int)length
                 write:(BOOL)write
               timeout:(unsigned int)seconds
           transferred:(unsigned int *)actual
{
    AHCISegment segments[32];
    unsigned int segmentCount;
    unsigned int generation;
    unsigned int waited;
    unsigned char commandFIS[20];
    unsigned char *table;
    AHCICommandHeader *commandList;
    AHCIU32 base;
    AHCIU32 stale;
    IOReturn result;
    BOOL recover;
    BOOL finishFree;
    ns_time_t now;

    if (fis == 0 || actual == 0 || seconds == 0 ||
        length > AHCI_MAX_TRANSFER_BYTES ||
        (length != 0 && buffer == 0))
        return IO_R_INVALID_ARG;
    *actual = 0;
    [commandLock lockWhen:AHCI_LOCK_IDLE];
    if (!online || mmio == 0 || mmio->base == 0) {
        [commandLock unlockWith:AHCI_LOCK_IDLE];
        return IO_R_OFFLINE;
    }
    segmentCount = 0;
    if (length != 0 &&
        AHCIPortBuildSegments((unsigned long)buffer, length, vm_page_size,
                              AHCIPortTranslateAddress, 0, segments, 32U,
                              &segmentCount) != AHCI_PORT_SUCCESS) {
        [commandLock unlockWith:AHCI_LOCK_IDLE];
        return IO_R_INVALID_ARG;
    }
    base = AHCI_PORT_BASE(portNumber);
    waited = 0;
    while ((AHCIPortMMIORead(mmio, base + AHCI_PX_TFD) &
            (AHCI_TFD_BSY | AHCI_TFD_DRQ)) != 0 &&
           waited < AHCI_TFD_TIMEOUT_MS) {
        IOSleep(AHCI_POLL_INTERVAL_MS);
        waited += AHCI_POLL_INTERVAL_MS;
    }
    if ((AHCIPortMMIORead(mmio, base + AHCI_PX_TFD) &
         (AHCI_TFD_BSY | AHCI_TFD_DRQ)) != 0) {
        completionSnapshot.portIS = AHCI_PXIS_TFES;
        completionSnapshot.serr = 0;
        ++activeExecutors;
        [commandLock unlockWith:AHCI_LOCK_DONE];
        [self recoverCommand];
        [commandLock lock];
        if (activeExecutors != 0)
            --activeExecutors;
        finishFree = destroying && quiesceComplete && !timeoutArmed &&
                     activeExecutors == 0;
        [commandLock unlockWith:AHCI_LOCK_IDLE];
        if (finishFree)
            [self finishDeferredFree];
        return IO_R_TIMEOUT;
    }
    memcpy(commandFIS, fis, sizeof(commandFIS));
    commandFIS[2] = command;
    commandList = (AHCICommandHeader *)
                  (arena.virtualBase + arena.commandListOffset);
    table = (unsigned char *)(arena.virtualBase + arena.commandTableOffset);
    if (!AHCIPortBuildSlot(&commandList[0], table,
                           arena.physicalBase + arena.commandTableOffset,
                           commandFIS, packet, packet == 0 ? 0U : 16U,
                           segments, segmentCount, length, write,
                           packet != 0)) {
        [commandLock unlockWith:AHCI_LOCK_IDLE];
        return IO_R_INVALID_ARG;
    }
    generation = AHCICommandBegin(&commandArbiter);
    if (generation == 0) {
        [commandLock unlockWith:AHCI_LOCK_IDLE];
        return IO_R_BUSY;
    }
    ++activeExecutors;
    requestedBytes = length;
    commandResult = IO_R_IO;
    bzero(&completionSnapshot, sizeof(completionSnapshot));
    stale = AHCIPortMMIORead(mmio, base + AHCI_PX_IS);
    AHCIPortMMIOWrite(mmio, base + AHCI_PX_IS, stale);
    stale = AHCIPortMMIORead(mmio, base + AHCI_PX_SERR);
    AHCIPortMMIOWrite(mmio, base + AHCI_PX_SERR, stale);
    commandList[0].prdbc = 0;
    AHCIPortMMIOWrite(mmio, base + AHCI_PX_IE,
                      AHCI_PORT_INITIAL_IE_MASK);
    IOGetTimestamp(&now);
    timeoutDeadlineSeconds =
        (unsigned long)(now / 1000000000ULL) + seconds;
    if (!timeoutArmed) {
        timeoutArmed = YES;
        armedGeneration = generation;
        IOScheduleFunc(AHCIPortTimeout, self, 1);
    }
    AHCIPortMMIOBarrier(mmio);
    AHCIPortMMIOWrite(mmio, base + AHCI_PX_CI, 1U);
    [commandLock unlockWith:AHCI_LOCK_PENDING];

    [commandLock lockWhen:AHCI_LOCK_DONE];
    result = commandResult;
    if (result == IO_R_SUCCESS)
        *actual = completionSnapshot.transferred;
    recover = result != IO_R_SUCCESS && !skipCommandRecovery;
    skipCommandRecovery = NO;
    if (recover) {
        [commandLock unlockWith:AHCI_LOCK_DONE];
        [self recoverCommand];
        [commandLock lock];
    }
    commandArbiter.state = AHCI_COMMAND_IDLE;
    if (activeExecutors != 0)
        --activeExecutors;
    finishFree = destroying && quiesceComplete && !timeoutArmed &&
                 activeExecutors == 0;
    [commandLock unlockWith:AHCI_LOCK_IDLE];
    if (finishFree) {
        [self finishDeferredFree];
        return result;
    }
    return result;
}

- (unsigned int)portNumber
{
    return portNumber;
}

- (AHCIDeviceKind)deviceKind
{
    return deviceKind;
}

- (void)handleInterrupt
{
    AHCIU32 base;
    AHCIU32 status;
    AHCIU32 error;
    AHCIU32 linkStatus;
    AHCICommandHeader *commandList;
    volatile AHCICommandHeader *volatileCommandList;
    volatile unsigned char *receivedFIS;
    unsigned int fisIndex;
    AHCICompletionResult completion;
    AHCIAsyncAction asyncAction;
    int condition;
    BOOL activeAtInterrupt;

    if (mmio == 0 || mmio->base == 0)
        return;
    base = AHCI_PORT_BASE(portNumber);
    status = AHCIPortMMIORead(mmio, base + AHCI_PX_IS);
    if ((status & AHCI_PORT_INITIAL_IE_MASK) == 0)
        return;
    [commandLock lock];
    activeAtInterrupt = commandArbiter.state == AHCI_COMMAND_PENDING;
    commandList = (AHCICommandHeader *)
                  (arena.virtualBase + arena.commandListOffset);
    completionSnapshot.portIS = status;
    completionSnapshot.taskFile =
        AHCIPortMMIORead(mmio, base + AHCI_PX_TFD);
    completionSnapshot.serr =
        AHCIPortMMIORead(mmio, base + AHCI_PX_SERR);
    completionSnapshot.commandIssue =
        AHCIPortMMIORead(mmio, base + AHCI_PX_CI);
    linkStatus = AHCIPortMMIORead(mmio, base + AHCI_PX_SSTS);
    AHCIPortMMIOBarrier(mmio);
    volatileCommandList = (volatile AHCICommandHeader *)commandList;
    completionSnapshot.transferred = volatileCommandList[0].prdbc;
    receivedFIS = (volatile unsigned char *)
                  (arena.virtualBase + arena.receivedFISOffset);
    for (fisIndex = 0; fisIndex < sizeof(receivedFISSnapshot); ++fisIndex)
        receivedFISSnapshot[fisIndex] = receivedFIS[fisIndex];
    error = completionSnapshot.serr;
    AHCIPortMMIOWrite(mmio, base + AHCI_PX_IS,
                      status & AHCI_PORT_INITIAL_IE_MASK);
    if (error != 0)
        AHCIPortMMIOWrite(mmio, base + AHCI_PX_SERR, error);
    AHCIPortMMIOBarrier(mmio);
    completion = AHCIClassifyCompletion(&completionSnapshot,
                                         requestedBytes);
    asyncAction = AHCIAsyncInterruptAction(completionSnapshot.portIS,
                                            completionSnapshot.serr,
                                            linkStatus);
    if (asyncAction == AHCI_ASYNC_PORT_OFFLINE)
        online = NO;
    if (commandArbiter.state == AHCI_COMMAND_PENDING &&
        completion != AHCI_COMPLETION_PENDING &&
        AHCICommandFinishIRQ(&commandArbiter,
                             commandArbiter.generation)) {
        commandResult = completion == AHCI_COMPLETION_OK ?
                        IO_R_SUCCESS : IO_R_IO;
        condition = AHCI_LOCK_DONE;
    } else {
        condition = commandArbiter.state == AHCI_COMMAND_PENDING ?
                    AHCI_LOCK_PENDING :
                    (commandArbiter.state == AHCI_COMMAND_IDLE ?
                     AHCI_LOCK_IDLE : AHCI_LOCK_DONE);
    }
    [commandLock unlockWith:condition];
    if (asyncAction == AHCI_ASYNC_HBA_RECOVERY && !activeAtInterrupt &&
        controller != nil)
        [controller recoverController];
}

@end
