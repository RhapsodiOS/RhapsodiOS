#import "AHCIPort.h"
#import "AHCIDisk.h"
#import "AHCIATAPI.h"
#import "AHCICommand.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/kernelDriver.h>
#import <mach/mach_interface.h>
#import <string.h>

/* The kernel's page size variable (vm/vm_resident.c:115).  Use this, not the
 * user-space Mach spelling with the vm_ prefix: mach/vm_param.h declares
 * that one only outside KERNEL builds, so referencing it leaves sarld with
 * an undefined symbol when it links this driver against mach_kernel at
 * boot.  The Floppy boot driver uses page_size for the same reason. */
extern unsigned int page_size;

typedef struct {
    vm_task_t task;
} AHCIPortTranslationContext;

#define AHCI_LOCK_IDLE       0
#define AHCI_LOCK_PENDING    1
#define AHCI_LOCK_DONE       2
@interface AHCIPort(Task10Private)
- (void)timeoutFired;
- (void)recoverCommand;
- (void)finishDeferredFree;
- (AHCIU32)snapshotCommandState:(AHCIU32)status;
- (AHCIPortResult)validateRecoveredKind:(AHCIDeviceKind)kind
                            matchesKind:(BOOL)sameKind;
@end

@interface Object(AHCIControllerRecovery)
- (BOOL)recoverController;
- (BOOL)beginSubmission;
- (void)endSubmission;
- (BOOL)commitSubmission;
- (void)finishSubmissionCommit;
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
    AHCIPortTranslationContext *translation;

    translation = (AHCIPortTranslationContext *)context;
    if (physicalAddress == 0 ||
        IOPhysicalFromVirtual(translation == 0 ? IOVmTaskSelf() :
                              translation->task,
                              (vm_address_t)virtualAddress,
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

static int AHCIPortPacketCheckCondition(
    BOOL isPacket, const AHCICompletionSnapshot *snapshot)
{
    AHCIU32 errorInterrupts;

    if (!isPacket || snapshot == 0 || snapshot->serr != 0 ||
        (snapshot->taskFile & 1U) == 0)
        return 0;
    errorInterrupts = snapshot->portIS &
                      (AHCI_PXIS_RECOVERABLE_MASK |
                       AHCI_PXIS_FATAL_MASK);
    return errorInterrupts == AHCI_PXIS_TFES;
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
    if (context == 0 || number >= 32U || page_size < 1024U ||
        (page_size & (page_size - 1U)) != 0) {
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
    AHCITimeoutChainInit(&timeoutChain);
    rawArenaBytes = AHCI_PORT_ARENA_USABLE_BYTES + page_size - 1U;
    rawArena = IOMallocLow(rawArenaBytes);
    if (rawArena == 0) {
        [self free];
        return nil;
    }
    result = AHCIPortPrepareArena((unsigned long)rawArena, rawArenaBytes,
                                  page_size, AHCIPortTranslateAddress, 0,
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

    if (![self unpublishDisk])
        return self;
    if (![self unpublishATAPI])
        return self;
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

- (AHCIPortResult)validateRecoveredKind:(AHCIDeviceKind)kind
                            matchesKind:(BOOL)sameKind
{
    AHCIPortOps ops;
    AHCICommandHeader *commandList;
    unsigned char *commandTable;
    unsigned short *identifyData;

    if (!sameKind || destroying || diskUnpublishing || atapiUnpublishing)
        return AHCI_PORT_COMMAND_ERROR;
    AHCIPortFillOps(&ops, mmio);
    commandList = (AHCICommandHeader *)
                  (arena.virtualBase + arena.commandListOffset);
    commandTable = (unsigned char *)
                   (arena.virtualBase + arena.commandTableOffset);
    identifyData = (unsigned short *)
                   (arena.virtualBase + arena.identifyOffset);
    {
        AHCIPortResult result;

        result = AHCIPortRecoveryIdentify(&ops, portNumber, &arena,
                                           commandList, commandTable,
                                           identifyData, kind);
        if (result == AHCI_PORT_SUCCESS && disk != nil &&
            ![disk reidentifyFromWords:identifyData])
            return AHCI_PORT_COMMAND_ERROR;
        if (result == AHCI_PORT_SUCCESS && atapi != nil &&
            ![atapi reidentifyFromWords:identifyData])
            return AHCI_PORT_COMMAND_ERROR;
        return result;
    }
}

- (BOOL)controllerDidReset
{
    AHCIPortOps ops;
    AHCIPortResult result;
    AHCIPortResult validationResult;
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
    controllerResetting = NO;
    validationResult = (diskUnpublishing || atapiUnpublishing) ?
        AHCI_PORT_COMMAND_ERROR :
        (result == AHCI_PORT_SUCCESS ?
         [self validateRecoveredKind:recoveredKind
                          matchesKind:AHCIRecoveredKindValid(
                              previousKind, recoveredKind)] :
         AHCI_PORT_COMMAND_ERROR);
    online = result == AHCI_PORT_SUCCESS &&
             validationResult == AHCI_PORT_SUCCESS;
    AHCIPortMMIOWrite(mmio, AHCI_PORT_BASE(portNumber) + AHCI_PX_IE,
                      online ? AHCI_PORT_INITIAL_IE_MASK : 0);
    AHCIPortMMIOBarrier(mmio);
    if (online)
        deviceKind = recoveredKind;
    if (online && atapi != nil)
        [atapi portBecameReady];
    else if (atapi != nil)
        [atapi portBecameNotReady];
    if (commandArbiter.state == AHCI_COMMAND_PENDING &&
        AHCICommandFinishIRQ(&commandArbiter, commandArbiter.generation)) {
        [commandLock unlockWith:AHCI_LOCK_DONE];
    } else {
        int condition;

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
    if (disk != nil)
        [disk portBecameNotReady];
    if (atapi != nil)
        [atapi portBecameNotReady];
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
    if (disk != nil)
        [disk portBecameNotReady];
    if (atapi != nil)
        [atapi portBecameNotReady];
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

- (AHCIU32)snapshotCommandState:(AHCIU32)status
{
    AHCIU32 base;
    AHCIU32 linkStatus;
    AHCICommandHeader *commandList;
    volatile AHCICommandHeader *volatileCommandList;
    volatile unsigned char *receivedFIS;

    base = AHCI_PORT_BASE(portNumber);
    commandList = (AHCICommandHeader *)
                  (arena.virtualBase + arena.commandListOffset);
    completionSnapshot.portIS = status;
    completionSnapshot.taskFile =
        AHCIPortMMIORead(mmio, base + AHCI_PX_TFD);
    completionSnapshot.serr =
        AHCIPortMMIORead(mmio, base + AHCI_PX_SERR);
    completionSnapshot.commandIssue =
        AHCIPortMMIORead(mmio, base + AHCI_PX_CI);
    completionSnapshot.portIS |=
        AHCIPortMMIORead(mmio, base + AHCI_PX_IS);
    completionSnapshot.serr |=
        AHCIPortMMIORead(mmio, base + AHCI_PX_SERR);
    linkStatus = AHCIPortMMIORead(mmio, base + AHCI_PX_SSTS);
    AHCIPortMMIOBarrier(mmio);
    volatileCommandList = (volatile AHCICommandHeader *)commandList;
    completionSnapshot.transferred = volatileCommandList[0].prdbc;
    receivedFIS = (volatile unsigned char *)
                  (arena.virtualBase + arena.receivedFISOffset);
    AHCICopyVolatileBytes(receivedFISSnapshot, receivedFIS,
                          sizeof(receivedFISSnapshot));
    return linkStatus;
}

- (void)timeoutFired
{
    int condition;
    ns_time_t now;
    unsigned long nowSeconds;
    AHCITimeoutAction timeoutAction;
    AHCIU32 base;
    AHCIU32 status;

    [commandLock lock];
    if (destroying) {
        if (!quiesceComplete || activeExecutors != 0) {
            timeoutArmed = YES;
            IOScheduleFunc(AHCIPortTimeout, self, 1);
            [commandLock unlockWith:AHCI_LOCK_DONE];
            return;
        }
        timeoutArmed = NO;
        AHCITimeoutChainInit(&timeoutChain);
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
    nowSeconds = AHCITimestampSeconds((unsigned long)(now >> 32),
                                      (unsigned long)now);
    if (!AHCITimeoutChainCallbackMayEvaluate(&timeoutChain)) {
        IOScheduleFunc(AHCIPortTimeout, self, 1);
        [commandLock unlockWith:AHCI_LOCK_PENDING];
        return;
    }
    timeoutAction = AHCICommandTimeoutAction(
        &commandArbiter, timeoutChain.armedGeneration,
        timeoutDeadlineSeconds,
        nowSeconds);
    if (timeoutAction == AHCI_TIMEOUT_REARM) {
        IOScheduleFunc(AHCIPortTimeout, self, 1);
        [commandLock unlockWith:AHCI_LOCK_PENDING];
        return;
    }
    if (timeoutAction == AHCI_TIMEOUT_EXPIRE) {
        if (mmio != 0 && mmio->base != 0) {
            base = AHCI_PORT_BASE(portNumber);
            AHCIPortMMIOWrite(mmio, base + AHCI_PX_IE, 0);
            AHCIPortMMIOBarrier(mmio);
            status = AHCIPortMMIORead(mmio, base + AHCI_PX_IS);
            (void)[self snapshotCommandState:status];
        }
    }
    if (timeoutAction == AHCI_TIMEOUT_EXPIRE &&
        AHCICommandFinishTimeout(&commandArbiter,
                                 timeoutChain.armedGeneration)) {
        timeoutArmed = NO;
        AHCITimeoutChainInit(&timeoutChain);
        commandResult = IO_R_TIMEOUT;
        [commandLock unlockWith:AHCI_LOCK_DONE];
        return;
    }
    if (commandArbiter.state == AHCI_COMMAND_PENDING) {
        IOScheduleFunc(AHCIPortTimeout, self, 1);
        [commandLock unlockWith:AHCI_LOCK_PENDING];
        return;
    }
    timeoutArmed = NO;
    AHCITimeoutChainInit(&timeoutChain);
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
    AHCIPortResult validationResult;
    AHCIDeviceKind previousKind;
    AHCIDeviceKind recoveredKind;

    [commandLock lock];
    if (!AHCILocalRecoveryAllowed(destroying, controllerResetting,
                                  diskUnpublishing || atapiUnpublishing)) {
        [commandLock unlockWith:AHCI_LOCK_DONE];
        return;
    }
    if (disk != nil)
        [disk portBecameNotReady];
    if (atapi != nil)
        [atapi portBecameNotReady];
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
    validationResult = result == AHCI_PORT_SUCCESS ?
        [self validateRecoveredKind:recoveredKind
                         matchesKind:AHCIRecoveredKindValid(
                             previousKind, recoveredKind)] :
        AHCI_PORT_COMMAND_ERROR;
    if (result == AHCI_PORT_SUCCESS &&
        validationResult == AHCI_PORT_SUCCESS) {
        deviceKind = recoveredKind;
        online = YES;
        AHCIPortMMIOWrite(mmio, AHCI_PORT_BASE(portNumber) + AHCI_PX_IE,
                          AHCI_PORT_INITIAL_IE_MASK);
        AHCIPortMMIOBarrier(mmio);
        if (atapi != nil)
            [atapi portBecameReady];
        [commandLock unlockWith:AHCI_LOCK_DONE];
        return;
    }
    online = NO;
    AHCIPortMMIOWrite(mmio, AHCI_PORT_BASE(portNumber) + AHCI_PX_IE, 0);
    AHCIPortMMIOBarrier(mmio);
    [commandLock unlockWith:AHCI_LOCK_DONE];
    if ((result == AHCI_PORT_ENGINE_TIMEOUT ||
         validationResult == AHCI_PORT_ENGINE_TIMEOUT) && controller != nil)
        [controller recoverController];
}

- (IOReturn)executeATA:(unsigned char)command
                   fis:(const unsigned char *)fis
                packet:(const unsigned char *)packet
                buffer:(void *)buffer
                length:(unsigned int)length
                 write:(BOOL)write
                client:(vm_task_t)client
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
    BOOL submissionEntered;
    ns_time_t now;
    AHCIPortTranslationContext translation;

    if (fis == 0 || actual == 0 || seconds == 0 ||
        length > AHCI_MAX_TRANSFER_BYTES ||
        (length != 0 && buffer == 0))
        return IO_R_INVALID_ARG;
    *actual = 0;
    [commandLock lockWhen:AHCI_LOCK_IDLE];
    if (destroying) {
        [commandLock unlockWith:AHCI_LOCK_IDLE];
        return IO_R_OFFLINE;
    }
    if (!online || mmio == 0 || mmio->base == 0) {
        [commandLock unlockWith:AHCI_LOCK_IDLE];
        return IO_R_OFFLINE;
    }
    segmentCount = 0;
    translation.task = client;
    if (length != 0 &&
        AHCIPortBuildSegments((unsigned long)buffer, length, page_size,
                              AHCIPortTranslateAddress, &translation,
                              segments, 32U,
                              &segmentCount) != AHCI_PORT_SUCCESS) {
        [commandLock unlockWith:AHCI_LOCK_IDLE];
        return IO_R_INVALID_ARG;
    }
    submissionEntered = controller != nil && [controller beginSubmission];
    if (!submissionEntered) {
        [commandLock unlockWith:AHCI_LOCK_IDLE];
        return IO_R_BUSY;
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
        AHCIPortMMIOWrite(mmio, base + AHCI_PX_IE, 0);
        AHCIPortMMIOBarrier(mmio);
        stale = AHCIPortMMIORead(mmio, base + AHCI_PX_IS);
        (void)[self snapshotCommandState:stale];
        if (submissionEntered)
            [controller endSubmission];
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
        if (submissionEntered)
            [controller endSubmission];
        [commandLock unlockWith:AHCI_LOCK_IDLE];
        return IO_R_INVALID_ARG;
    }
    if (submissionEntered && ![controller commitSubmission]) {
        submissionEntered = NO;
        [commandLock unlockWith:AHCI_LOCK_IDLE];
        return IO_R_BUSY;
    }
    submissionEntered = NO;
    generation = AHCICommandBegin(&commandArbiter);
    if (generation == 0) {
        [controller finishSubmissionCommit];
        [commandLock unlockWith:AHCI_LOCK_IDLE];
        return IO_R_BUSY;
    }
    ++activeExecutors;
    requestedBytes = length;
    packetCommand = packet != 0;
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
        AHCITimestampSeconds((unsigned long)(now >> 32),
                             (unsigned long)now) + seconds;
    if (!timeoutArmed) {
        timeoutArmed = YES;
        if (AHCITimeoutChainArm(&timeoutChain, generation))
            IOScheduleFunc(AHCIPortTimeout, self, 1);
    } else {
        (void)AHCITimeoutChainArm(&timeoutChain, generation);
    }
    AHCIPortMMIOBarrier(mmio);
    AHCIPortMMIOWrite(mmio, base + AHCI_PX_CI, 1U);
    [controller finishSubmissionCommit];
    [commandLock unlockWith:AHCI_LOCK_PENDING];

    [commandLock lockWhen:AHCI_LOCK_DONE];
    result = commandResult;
    *actual = completionSnapshot.transferred;
    recover = result != IO_R_SUCCESS && !skipCommandRecovery &&
              !(result == IO_R_IO &&
                AHCIPortPacketCheckCondition(packetCommand,
                                             &completionSnapshot));
    skipCommandRecovery = NO;
    if (recover) {
        [commandLock unlockWith:AHCI_LOCK_DONE];
        [self recoverCommand];
        [commandLock lock];
    }
    commandArbiter.state = AHCI_COMMAND_IDLE;
    packetCommand = NO;
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

- (void *)identifyBuffer
{
    if (rawArena == 0)
        return 0;
    return (void *)(arena.virtualBase + arena.identifyOffset);
}

- (BOOL)publishDiskFromDeviceDescription:
    (IODeviceDescription *)deviceDescription
{
    if (deviceKind != AHCI_DEVICE_SATA || disk != nil)
        return disk != nil;
    disk = [AHCIDisk publishForPort:self
                 deviceDescription:deviceDescription];
    return disk != nil;
}

- (BOOL)publishATAPIFromDeviceDescription:
    (IODeviceDescription *)deviceDescription
{
    unsigned char fis[20];
    unsigned int actual;
    unsigned short *identifyData;

    if (deviceKind != AHCI_DEVICE_ATAPI || atapi != nil)
        return atapi != nil;
    identifyData = (unsigned short *)[self identifyBuffer];
    if (identifyData == 0)
        return NO;
    bzero(identifyData, 512);
    AHCIBuildIdentifyFIS(fis, 1);
    if ([self executeATA:AHCI_ATAPI_IDENTIFY_PACKET_DEVICE
                     fis:fis packet:0 buffer:identifyData
                   length:512 write:NO client:IOVmTaskSelf()
                  timeout:AHCI_ATAPI_IDENTIFY_TIMEOUT_SECONDS
              transferred:&actual] != IO_R_SUCCESS ||
        actual != 512U)
        return NO;
    atapi = [AHCIATAPIController publishForPort:self
                                  identifyWords:identifyData
                             deviceDescription:deviceDescription];
    return atapi != nil;
}

- (BOOL)unpublishATAPI
{
    AHCIATAPIController *device;
    int condition;

    if (commandLock == nil)
        return atapi == nil;
    [commandLock lock];
    if (atapi == nil) {
        condition = commandArbiter.state == AHCI_COMMAND_PENDING ?
                    AHCI_LOCK_PENDING :
                    (commandArbiter.state == AHCI_COMMAND_IDLE ?
                     AHCI_LOCK_IDLE : AHCI_LOCK_DONE);
        [commandLock unlockWith:condition];
        return YES;
    }
    atapiUnpublishing = YES;
    device = atapi;
    [device portBecameNotReady];
    atapi = nil;
    condition = commandArbiter.state == AHCI_COMMAND_PENDING ?
                AHCI_LOCK_PENDING :
                (commandArbiter.state == AHCI_COMMAND_IDLE ?
                 AHCI_LOCK_IDLE : AHCI_LOCK_DONE);
    [commandLock unlockWith:condition];
    if ([device free] != nil) {
        [commandLock lock];
        atapi = device;
        online = NO;
        [device portBecameNotReady];
        atapiUnpublishing = NO;
        condition = commandArbiter.state == AHCI_COMMAND_PENDING ?
                    AHCI_LOCK_PENDING :
                    (commandArbiter.state == AHCI_COMMAND_IDLE ?
                     AHCI_LOCK_IDLE : AHCI_LOCK_DONE);
        [commandLock unlockWith:condition];
        return NO;
    }
    [commandLock lock];
    atapiUnpublishing = NO;
    condition = commandArbiter.state == AHCI_COMMAND_PENDING ?
                AHCI_LOCK_PENDING :
                (commandArbiter.state == AHCI_COMMAND_IDLE ?
                 AHCI_LOCK_IDLE : AHCI_LOCK_DONE);
    [commandLock unlockWith:condition];
    return YES;
}

- (BOOL)resetATAPIDevice:(AHCIATAPIController *)device
{
    BOOL ready;
    int condition;

    if (device == nil || controller == nil ||
        ![controller recoverController])
        return NO;
    [commandLock lock];
    ready = !destroying && online && !atapiUnpublishing && atapi == device;
    condition = commandArbiter.state == AHCI_COMMAND_PENDING ?
                AHCI_LOCK_PENDING :
                (commandArbiter.state == AHCI_COMMAND_IDLE ?
                 AHCI_LOCK_IDLE : AHCI_LOCK_DONE);
    [commandLock unlockWith:condition];
    return ready;
}

- (BOOL)unpublishDisk
{
    AHCIDisk *diskToFree;
    int condition;
    BOOL unpublished;
    BOOL notifyDiskOffline;

    if (commandLock == nil)
        return disk == nil;
    [commandLock lock];
    while (diskUnpublishing) {
        condition = commandArbiter.state == AHCI_COMMAND_PENDING ?
                    AHCI_LOCK_PENDING :
                    (commandArbiter.state == AHCI_COMMAND_IDLE ?
                     AHCI_LOCK_IDLE : AHCI_LOCK_DONE);
        [commandLock unlockWith:condition];
        IOSleep(1);
        [commandLock lock];
    }
    if (disk == nil) {
        condition = commandArbiter.state == AHCI_COMMAND_PENDING ?
                    AHCI_LOCK_PENDING :
                    (commandArbiter.state == AHCI_COMMAND_IDLE ?
                     AHCI_LOCK_IDLE : AHCI_LOCK_DONE);
        [commandLock unlockWith:condition];
        return YES;
    }
    diskUnpublishing = YES;
    diskNotificationsBlocked = YES;
    diskToFree = disk;
    disk = nil;
    while (activeDiskNotifications != 0) {
        condition = commandArbiter.state == AHCI_COMMAND_PENDING ?
                    AHCI_LOCK_PENDING :
                    (commandArbiter.state == AHCI_COMMAND_IDLE ?
                     AHCI_LOCK_IDLE : AHCI_LOCK_DONE);
        [commandLock unlockWith:condition];
        IOSleep(1);
        [commandLock lock];
    }
    condition = commandArbiter.state == AHCI_COMMAND_PENDING ?
                AHCI_LOCK_PENDING :
                (commandArbiter.state == AHCI_COMMAND_IDLE ?
                 AHCI_LOCK_IDLE : AHCI_LOCK_DONE);
    [commandLock unlockWith:condition];

    unpublished = [diskToFree free] == nil ? YES : NO;
    notifyDiskOffline = NO;
    [commandLock lock];
    if (unpublished) {
        diskUnpublishing = NO;
    } else {
        disk = diskToFree;
        online = NO;
        if (mmio != 0 && mmio->base != 0) {
            AHCIPortMMIOWrite(mmio,
                              AHCI_PORT_BASE(portNumber) + AHCI_PX_IE, 0);
            AHCIPortMMIOBarrier(mmio);
        }
        ++activeDiskNotifications;
        notifyDiskOffline = YES;
    }
    condition = commandArbiter.state == AHCI_COMMAND_PENDING ?
                AHCI_LOCK_PENDING :
                (commandArbiter.state == AHCI_COMMAND_IDLE ?
                 AHCI_LOCK_IDLE : AHCI_LOCK_DONE);
    [commandLock unlockWith:condition];
    if (notifyDiskOffline) {
        [diskToFree portBecameNotReady];
        [commandLock lock];
        --activeDiskNotifications;
        diskNotificationsBlocked = NO;
        diskUnpublishing = NO;
        condition = commandArbiter.state == AHCI_COMMAND_PENDING ?
                    AHCI_LOCK_PENDING :
                    (commandArbiter.state == AHCI_COMMAND_IDLE ?
                     AHCI_LOCK_IDLE : AHCI_LOCK_DONE);
        [commandLock unlockWith:condition];
    }
    return unpublished;
}

- (void)handleInterrupt
{
    AHCIU32 base;
    AHCIU32 status;
    AHCIU32 error;
    AHCIU32 linkStatus;
    AHCICompletionResult completion;
    AHCIAsyncAction asyncAction;
    int condition;
    BOOL deferHBARecovery;
    BOOL notifyDiskOffline;
    AHCIDisk *diskToNotify;

    notifyDiskOffline = NO;
    diskToNotify = nil;
    [commandLock lock];
    condition = commandArbiter.state == AHCI_COMMAND_PENDING ?
                AHCI_LOCK_PENDING :
                (commandArbiter.state == AHCI_COMMAND_IDLE ?
                 AHCI_LOCK_IDLE : AHCI_LOCK_DONE);
    if (mmio == 0 || mmio->base == 0) {
        [commandLock unlockWith:condition];
        return;
    }
    base = AHCI_PORT_BASE(portNumber);
    status = AHCIPortMMIORead(mmio, base + AHCI_PX_IS);
    if ((status & AHCI_PORT_INITIAL_IE_MASK) == 0) {
        [commandLock unlockWith:condition];
        return;
    }
    linkStatus = [self snapshotCommandState:status];
    error = completionSnapshot.serr;
    AHCIPortMMIOWrite(mmio, base + AHCI_PX_IS,
                      status & AHCI_PORT_INITIAL_IE_MASK);
    if (error != 0)
        AHCIPortMMIOWrite(mmio, base + AHCI_PX_SERR, error);
    AHCIPortMMIOBarrier(mmio);
    completion = AHCIClassifyCompletion(&completionSnapshot,
                                         requestedBytes);
    if (completion == AHCI_COMPLETION_ERROR &&
        !AHCIPortPacketCheckCondition(packetCommand,
                                      &completionSnapshot)) {
        AHCIPortMMIOWrite(mmio, base + AHCI_PX_IE, 0);
        AHCIPortMMIOBarrier(mmio);
    }
    asyncAction = AHCIAsyncInterruptAction(completionSnapshot.portIS,
                                            completionSnapshot.serr,
                                            linkStatus);
    if (asyncAction == AHCI_ASYNC_PORT_OFFLINE) {
        online = NO;
        if (atapi != nil)
            [atapi portBecameNotReady];
        if (disk != nil && !diskNotificationsBlocked) {
            notifyDiskOffline = YES;
            diskToNotify = disk;
            ++activeDiskNotifications;
        }
    }
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
    deferHBARecovery = AHCIAsyncHBARecoveryDeferred(
        commandArbiter.state, activeExecutors != 0,
        commandResult != IO_R_SUCCESS) ? YES : NO;
    [commandLock unlockWith:condition];
    if (notifyDiskOffline) {
        [diskToNotify portBecameNotReady];
        [commandLock lock];
        --activeDiskNotifications;
        condition = commandArbiter.state == AHCI_COMMAND_PENDING ?
                    AHCI_LOCK_PENDING :
                    (commandArbiter.state == AHCI_COMMAND_IDLE ?
                     AHCI_LOCK_IDLE : AHCI_LOCK_DONE);
        [commandLock unlockWith:condition];
    }
    if (asyncAction == AHCI_ASYNC_HBA_RECOVERY && !deferHBARecovery &&
        controller != nil)
        [controller recoverController];
}

@end
