#import "PPCTASAudio.h"

#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/ppc/IODBDMA.h>
#import <driverkit/ppc/IOTreeDevice.h>
#import <driverkit/ppc/IOPropertyTable.h>
#import <machdep/ppc/PEKeyLargo.h>

#include <string.h>

#define TAS_TREE_NODES 128
#define TAS_I2S_SERIAL_FORMAT 0x10
#define TAS_I2S_DATA_WORD     0x18

extern void flush_cache_v(vm_offset_t, unsigned int);

@interface IOTreeDevice (PPCTASIteration)
+ findForIndex:(UInt32)index;
@end

typedef struct {
    IOTreeDevice *nodes[TAS_TREE_NODES];
    unsigned long count;
} PPCTASPropertyContext;

static unsigned long tas_detects(void *opaque);

static int tas_get_property(void *opaque, TASNode node, const char *name,
    const unsigned char **bytes, unsigned long *length)
{
    PPCTASPropertyContext *context;
    void *value;
    ByteCount size;
    context = (PPCTASPropertyContext *)opaque;
    if (node == 0UL || node > context->count)
        return 0;
    value = 0;
    size = 0;
    if ([[context->nodes[node - 1UL] propertyTable] getProperty:name
        flags:kReferenceProperty value:&value length:&size] != IO_R_SUCCESS)
        return 0;
    *bytes = (const unsigned char *)value;
    *length = (unsigned long)size;
    return 1;
}

static int tas_find_node(void *opaque, const char *query, TASNode *node)
{
    PPCTASPropertyContext *context;
    unsigned long index;
    char path[256];
    const char *name;
    context = (PPCTASPropertyContext *)opaque;
    index = *node;
    while (index < context->count) {
        name = [context->nodes[index] nodeName];
        path[0] = '\0';
        [context->nodes[index] getDevicePath:path maxLength:sizeof(path)
            useAlias:NO];
        ++index;
        if ((query[0] == '/' && strcmp(query, path) == 0) ||
            (query[0] != '/' && name != 0 && strcmp(query, name) == 0)) {
            *node = index;
            return 1;
        }
    }
    return 0;
}

static int tas_get_parent(void *opaque, TASNode node, TASNode *parent)
{
    PPCTASPropertyContext *context;
    id object;
    unsigned long index;
    context = (PPCTASPropertyContext *)opaque;
    if (node == 0UL || node > context->count)
        return 0;
    object = [context->nodes[node - 1UL] parent];
    for (index = 0UL; index < context->count; ++index) {
        if (context->nodes[index] == object) {
            *parent = index + 1UL;
            return 1;
        }
    }
    return 0;
}

static int tas_make_reader(TASPropertyReader *reader,
    PPCTASPropertyContext *context)
{
    unsigned long index;
    id node;
    memset(context, 0, sizeof(*context));
    for (index = 0UL; index < TAS_TREE_NODES; ++index) {
        node = [IOTreeDevice findForIndex:(UInt32)index];
        if (node == nil)
            break;
        context->nodes[context->count++] = node;
    }
    if (context->count == 0UL || index == TAS_TREE_NODES)
        return 0;
    memset(reader, 0, sizeof(*reader));
    reader->context = context;
    reader->getProperty = tas_get_property;
    reader->findNode = tas_find_node;
    reader->getParent = tas_get_parent;
    return 1;
}

static TASStatus tas_status(IOReturn result)
{
    return result == IO_R_SUCCESS ? kTASStatusOK : kTASStatusTimeout;
}

static TASStatus tas_codec_write(void *opaque, unsigned char reg,
    const unsigned char *bytes, unsigned long length, unsigned long deadline,
    unsigned long *written)
{
    PPCTASAudio *self;
    PEKeyWestI2CRequest request;
    self = (PPCTASAudio *)opaque;
    memset(&request, 0, sizeof(request));
    request.port = self->machineConfig.i2cPort;
    request.address = (unsigned char)self->machineConfig.i2cAddress;
    request.subaddress = reg;
    request.direction = kPEKeyWestWrite;
    request.buffer = (unsigned char *)bytes;
    request.length = (unsigned int)length;
    request.deadline.tv_sec = deadline / 1000UL;
    request.deadline.tv_nsec = (deadline % 1000UL) * 1000000UL;
    if (PEKeyWestI2CTransfer(&request) != KERN_SUCCESS) {
        *written = 0UL;
        return kTASStatusTimeout;
    }
    *written = length;
    return kTASStatusOK;
}

static TASStatus tas_codec_reset(void *opaque, int asserted)
{
    PPCTASAudio *self;
    PEAudioGPIO gpio;
    self = (PPCTASAudio *)opaque;
    gpio.offset = self->machineConfig.hardwareReset.offset;
    gpio.activeHigh = self->machineConfig.hardwareReset.activeHigh;
    return PEAudioGPIOWrite(&gpio, asserted ? TRUE : FALSE) == KERN_SUCCESS ?
        kTASStatusOK : kTASStatusTimeout;
}

static TASStatus tas_codec_delay(void *opaque, unsigned long usec,
    unsigned long deadline)
{
    (void)opaque;
    (void)deadline;
    IODelay(usec);
    return kTASStatusOK;
}

static void tas_fail_mute(void *opaque)
{
    PPCTASAudio *self;
    PEAudioGPIO gpio;
    self = (PPCTASAudio *)opaque;
    gpio.offset = self->machineConfig.amplifierMute.offset;
    gpio.activeHigh = self->machineConfig.amplifierMute.activeHigh;
    (void)PEAudioGPIOWrite(&gpio, TRUE);
}

static TASStatus tas_translate(void *opaque, const void *address,
    unsigned long *physical, unsigned long *contiguous)
{
    vm_offset_t result;
    unsigned long pageRemaining;
    (void)opaque;
    if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_offset_t)address,
        &result) != IO_R_SUCCESS)
        return kPPCDBDMAUnmappable;
    *physical = (unsigned long)result;
    pageRemaining = PAGE_SIZE - ((unsigned long)address & (PAGE_SIZE - 1UL));
    *contiguous = pageRemaining;
    return kPPCDBDMAOK;
}

static unsigned long tas_dma_read(void *opaque, unsigned long reg)
{
    volatile IODBDMAChannelRegisters *registers;
    registers = (volatile IODBDMAChannelRegisters *)opaque;
    if (reg == kPPCDBDMARegStatus)
        return IOGetDBDMAChannelStatus(registers);
    return 0UL;
}

static void tas_dma_write(void *opaque, unsigned long reg,
    unsigned long value)
{
    volatile IODBDMAChannelRegisters *registers;
    registers = (volatile IODBDMAChannelRegisters *)opaque;
    if (reg == kPPCDBDMARegControl)
        IOSetDBDMAChannelControl(registers, value);
    else if (reg == kPPCDBDMARegCommandPtr)
        IOSetDBDMACommandPtr(registers, value);
}

static unsigned long tas_now(void *opaque)
{
    ns_time_t now;
    (void)opaque;
    IOGetTimestamp(&now);
    return (unsigned long)(now / 1000000ULL);
}

static PPCDBDMAStatus tas_publish(void *opaque, void *address,
    unsigned long bytes)
{
    (void)opaque;
    flush_cache_v((vm_offset_t)address, (unsigned int)bytes);
    return kPPCDBDMAOK;
}

static TASStatus tas_apply_i2s(PPCTASAudio *self, unsigned long rate,
    unsigned long deadline)
{
    TASI2SClock clock;
    TASI2SPlanStep format;
    unsigned long serial;
    unsigned long dataWord;
    if (TASSelectI2SClock(&self->machineConfig, rate, &clock) != kTASStatusOK)
        return kTASStatusUnsupported;
    memset(&format, 0, sizeof(format));
    format.sourceHz = clock.sourceHz;
    format.mclkDivisor = clock.mclkDivisor;
    format.sclkDivisor = clock.sclkDivisor;
    format.value = clock.dataWord;
    if (TASRuntimeEncodeI2S(&format, &serial, &dataWord) != kTASStatusOK)
        return kTASStatusUnsupported;
    if (tas_now(self) >= deadline)
        return kTASStatusTimeout;
    if (PEI2SSetCellState((unsigned int)self->machineConfig.i2sCell,
        kPEI2SCellEnabledClockHeld) != KERN_SUCCESS)
        return kTASStatusUnresolved;
    if (tas_now(self) >= deadline)
        return kTASStatusTimeout; /* Held clock; no partial tuple write. */
    /* Apple I2S semantic tuple: source, MCLK divisor, SCLK divisor, word. */
    *(volatile unsigned long *)((unsigned char *)self->i2sRegisters +
        TAS_I2S_SERIAL_FORMAT) = serial;
    *(volatile unsigned long *)((unsigned char *)self->i2sRegisters +
        TAS_I2S_DATA_WORD) = dataWord;
    eieio();
    return tas_status(PEI2SSetCellState(
        (unsigned int)self->machineConfig.i2sCell, kPEI2SCellRunning));
}

static PPCDBDMAStatus tas_barrier(void *opaque)
{
    (void)opaque;
    eieio();
    return kPPCDBDMAOK;
}

static TASStatus tas_acquire(void *opaque, TASRuntimeStage stage,
    const TASMachineConfig *config)
{
    PPCTASAudio *self;
    unsigned long index;
    PEAudioGPIO gpio;
    vm_offset_t physical;
    self = (PPCTASAudio *)opaque;
    switch (stage) {
    case kTASRuntimePlatformReady:
        return [self deviceDescription] != nil ? kTASStatusOK :
            kTASStatusMissing;
    case kTASRuntimeMapI2S:
    case kTASRuntimeMapOutputDBDMA:
    case kTASRuntimeMapInputDBDMA:
        index = (unsigned long)stage - (unsigned long)kTASRuntimeMapI2S;
        if ([self mapMemoryRange:(unsigned int)index
            to:(vm_address_t *)(index == 0UL ? &self->i2sRegisters :
            (index == 1UL ? &self->outputDBDMARegisters :
            &self->inputDBDMARegisters)) findSpace:YES cache:IO_CacheOff] !=
            IO_R_SUCCESS)
            return kTASStatusMissing;
        return kTASStatusOK;
    case kTASRuntimeInstallOutputIRQ:
    case kTASRuntimeInstallInputIRQ:
        [self enableInterrupt:(unsigned int)stage -
            (unsigned int)kTASRuntimeInstallOutputIRQ];
        return kTASStatusOK;
    case kTASRuntimeInstallDetectIRQs:
        for (index = 2UL;
            index < (unsigned long)[[self deviceDescription] numInterrupts];
            ++index)
            [self enableInterrupt:(unsigned int)index];
        return kTASStatusOK;
    case kTASRuntimeEnableI2S:
        return tas_apply_i2s(self, self->desiredControls.rate,
            self->runtime.operationDeadline);
    case kTASRuntimeSafeOutputs:
        gpio.offset = config->amplifierMute.offset;
        gpio.activeHigh = config->amplifierMute.activeHigh;
        return tas_status(PEAudioGPIOWrite(&gpio, TRUE));
    case kTASRuntimeInitializeCodec:
        return TASCodecInitialize(&self->runtime.codec, 1,
            self->runtime.operationDeadline);
    case kTASRuntimeAllocateOutputRing:
    case kTASRuntimeAllocateInputRing:
        index = (unsigned long)stage -
            (unsigned long)kTASRuntimeAllocateOutputRing;
        self->ringAllocations[index * 2UL] =
            IOMalloc(PPC_DBDMA_MAX_RING_BYTES + 15UL);
        self->ringAllocations[index * 2UL + 1UL] =
            IOMalloc(PPC_DBDMA_MAX_RING_BYTES + 15UL);
        if (self->ringAllocations[index * 2UL] == 0 ||
            self->ringAllocations[index * 2UL + 1UL] == 0)
            return kTASStatusMissing;
        self->ringStorage[index].logical = (void *)
            (((unsigned long)self->ringAllocations[index * 2UL] + 15UL) &
            ~15UL);
        self->ringStorage[index].scratch = (void *)
            (((unsigned long)self->ringAllocations[index * 2UL + 1UL] +
            15UL) & ~15UL);
        if (IOPhysicalFromVirtual(IOVmTaskSelf(),
            (vm_offset_t)self->ringStorage[index].logical, &physical) !=
            IO_R_SUCCESS)
            return kTASStatusUnresolved;
        self->ringStorage[index].physical = (unsigned long)physical;
        self->ringStorage[index].bytes = PPC_DBDMA_MAX_RING_BYTES;
        self->ringStorage[index].scratchBytes = PPC_DBDMA_MAX_RING_BYTES;
        return kTASStatusOK;
    case kTASRuntimeCreateAudioChannels:
        return kTASStatusOK; /* IOAudio init owns channel/thread creation. */
    case kTASRuntimeInitialRoute:
        return kTASStatusOK;
    default:
        return kTASStatusMalformed;
    }
}

static void tas_release(void *opaque, TASRuntimeStage stage)
{
    PPCTASAudio *self;
    unsigned long index;
    self = (PPCTASAudio *)opaque;
    if (stage == kTASRuntimeInstallOutputIRQ ||
        stage == kTASRuntimeInstallInputIRQ) {
        [self disableInterrupt:(unsigned int)stage -
            (unsigned int)kTASRuntimeInstallOutputIRQ];
    } else if (stage == kTASRuntimeInstallDetectIRQs) {
        for (index = 2UL;
            index < (unsigned long)[[self deviceDescription] numInterrupts];
            ++index)
            [self disableInterrupt:(unsigned int)index];
    } else if (stage == kTASRuntimeEnableI2S) {
        (void)PEI2SSetCellState((unsigned int)self->machineConfig.i2sCell,
            kPEI2SCellDisabledReset);
    } else if (stage >= kTASRuntimeMapI2S &&
        stage <= kTASRuntimeMapInputDBDMA) {
        index = (unsigned long)stage - (unsigned long)kTASRuntimeMapI2S;
        [self unmapMemoryRange:(unsigned int)index];
        if (index == 0UL)
            self->i2sRegisters = 0;
        else if (index == 1UL)
            self->outputDBDMARegisters = 0;
        else
            self->inputDBDMARegisters = 0;
    }
    if (stage == kTASRuntimeAllocateOutputRing ||
        stage == kTASRuntimeAllocateInputRing) {
        index = (unsigned long)stage -
            (unsigned long)kTASRuntimeAllocateOutputRing;
        if (self->ringAllocations[index * 2UL] != 0)
            IOFree(self->ringAllocations[index * 2UL],
                PPC_DBDMA_MAX_RING_BYTES + 15UL);
        if (self->ringAllocations[index * 2UL + 1UL] != 0)
            IOFree(self->ringAllocations[index * 2UL + 1UL],
                PPC_DBDMA_MAX_RING_BYTES + 15UL);
        self->ringAllocations[index * 2UL] = 0;
        self->ringAllocations[index * 2UL + 1UL] = 0;
    }
}

static TASStatus tas_prepare_dma(void *opaque, TASStreamDirection direction,
    const void *buffer, unsigned long bytes, unsigned long period,
    PPCDBDMARing *ring)
{
    PPCTASAudio *self;
    self = (PPCTASAudio *)opaque;
    return PPCDBDMABuildRing(ring, &self->ringStorage[(unsigned long)direction],
        direction == kTASStreamInput ? kPPCDBDMAInput : kPPCDBDMAOutput,
        buffer, bytes, period, &self->dmaOps[(unsigned long)direction]) ==
        kPPCDBDMAOK ? kTASStatusOK : kTASStatusUnresolved;
}

static TASStatus tas_start_dma(void *opaque, TASStreamDirection direction,
    PPCDBDMARing *ring, unsigned long deadline)
{
    PPCTASAudio *self;
    PPCDBDMATransition transition;
    self = (PPCTASAudio *)opaque;
    transition = PPCDBDMAStartRing(ring,
        &self->dmaOps[(unsigned long)direction], deadline);
    return transition.status == kPPCDBDMAOK ? kTASStatusOK :
        kTASStatusTimeout;
}

static TASStatus tas_stop_dma(void *opaque, TASStreamDirection direction,
    PPCDBDMARing *ring, unsigned long deadline)
{
    PPCTASAudio *self;
    PPCDBDMATransition transition;
    self = (PPCTASAudio *)opaque;
    transition = PPCDBDMAStopRing(ring,
        &self->dmaOps[(unsigned long)direction], deadline);
    if (transition.status != kPPCDBDMAOK)
        return kTASStatusTimeout;
    transition = PPCDBDMAResetRing(ring,
        &self->dmaOps[(unsigned long)direction], deadline);
    return transition.status == kPPCDBDMAOK ? kTASStatusOK :
        kTASStatusTimeout;
}

static TASStatus tas_service_dma(void *opaque, TASStreamDirection direction,
    PPCDBDMARing *ring, unsigned long *completed)
{
    PPCTASAudio *self;
    PPCDBDMACompletion completion;
    PPCDBDMAStatus status;
    self = (PPCTASAudio *)opaque;
    status = PPCDBDMAServiceCompletions(ring,
        &self->dmaOps[(unsigned long)direction], &completion);
    *completed = completion.descriptors;
    return status == kPPCDBDMAOK ? kTASStatusOK : kTASStatusUnresolved;
}

static TASStatus tas_ack_dma_interrupt(void *opaque,
    TASStreamDirection direction)
{
    PPCTASAudio *self;
    volatile IODBDMAChannelRegisters *registers;
    self = (PPCTASAudio *)opaque;
    registers = (volatile IODBDMAChannelRegisters *)(direction ==
        kTASStreamOutput ? self->outputDBDMARegisters :
        self->inputDBDMARegisters);
    if (registers == 0)
        return kTASStatusMissing;
    (void)IOGetDBDMAChannelStatus(registers);
    eieio();
    return kTASStatusOK;
}

static TASStatus tas_action(void *opaque, const TASAudioAction *action)
{
    PPCTASAudio *self;
    PEAudioGPIO gpio;
    TASStreamDirection direction;
    unsigned long index;
    self = (PPCTASAudio *)opaque;
    switch (action->operation) {
    case kTASAudioBlockStarts:
        return kTASStatusOK;
    case kTASAudioScheduleDebounce:
        IODelay(TAS_AUDIO_DEBOUNCE_CONFIRM_MS * 1000UL);
        return kTASStatusOK;
    case kTASAudioSampleDetects:
        (void)tas_detects(self);
        return kTASStatusOK;
    case kTASAudioMuteSpeaker:
    case kTASAudioUnmuteSpeaker:
        gpio.offset = self->machineConfig.amplifierMute.offset;
        gpio.activeHigh = self->machineConfig.amplifierMute.activeHigh;
        return tas_status(PEAudioGPIOWrite(&gpio,
            action->operation == kTASAudioMuteSpeaker));
    case kTASAudioMuteHeadphone:
    case kTASAudioUnmuteHeadphone:
        gpio.offset = self->machineConfig.routes[kTASRouteHeadphone].mute.offset;
        gpio.activeHigh =
            self->machineConfig.routes[kTASRouteHeadphone].mute.activeHigh;
        return tas_status(PEAudioGPIOWrite(&gpio,
            action->operation == kTASAudioMuteHeadphone));
    case kTASAudioMuteLineOut:
    case kTASAudioUnmuteLineOut:
        gpio.offset = self->machineConfig.routes[kTASRouteLineOut].mute.offset;
        gpio.activeHigh =
            self->machineConfig.routes[kTASRouteLineOut].mute.activeHigh;
        return tas_status(PEAudioGPIOWrite(&gpio,
            action->operation == kTASAudioMuteLineOut));
    case kTASAudioCodecDigitalMute:
        return TASCodecSetMute(&self->runtime.codec, action->value != 0UL,
            action->deadline);
    case kTASAudioAssertReset:
    case kTASAudioReleaseReset:
    case kTASAudioAssertAndedReset:
    case kTASAudioReleaseAndedReset:
        return tas_codec_reset(self,
            action->operation == kTASAudioAssertReset ||
            action->operation == kTASAudioAssertAndedReset);
    case kTASAudioSetResetAmpConstituent:
        gpio.offset = self->machineConfig.amplifierMute.offset;
        gpio.activeHigh = self->machineConfig.amplifierMute.activeHigh;
        return tas_status(PEAudioGPIOWrite(&gpio, action->value != 0UL));
    case kTASAudioSetResetHeadphoneConstituent:
        gpio.offset = self->machineConfig.routes[kTASRouteHeadphone].mute.offset;
        gpio.activeHigh =
            self->machineConfig.routes[kTASRouteHeadphone].mute.activeHigh;
        return tas_status(PEAudioGPIOWrite(&gpio, action->value != 0UL));
    case kTASAudioSetOutputMux:
        gpio.offset = self->machineConfig.inputMux.offset;
        gpio.activeHigh = self->machineConfig.inputMux.activeHigh;
        return tas_status(PEAudioGPIOWrite(&gpio, action->value != 0UL));
    case kTASAudioSetCodecRoute:
    case kTASAudioRestoreInputSource:
        return TASCodecSetInputSource(&self->runtime.codec,
            (TASCodecInputSource)self->runtime.audio.desired.inputSource,
            action->deadline);
    case kTASAudioCodecRestore:
        return TASCodecRestore(&self->runtime.codec, action->deadline);
    case kTASAudioCodecReset:
        return TASCodecInitialize(&self->runtime.codec, 1, action->deadline);
    case kTASAudioRestoreVolume:
        return TASCodecSetVolume(&self->runtime.codec,
            self->runtime.audio.desired.leftVolume,
            self->runtime.audio.desired.rightVolume, action->deadline);
    case kTASAudioRestoreInputGain:
        return TASCodecSetInputGain(&self->runtime.codec,
            self->runtime.audio.desired.inputGain, action->deadline);
    case kTASAudioStopOutputDMA:
    case kTASAudioResetOutputDMA:
    case kTASAudioRebuildOutputDMA:
    case kTASAudioStopInputDMA:
    case kTASAudioResetInputDMA:
    case kTASAudioRebuildInputDMA:
        direction = (action->operation == kTASAudioStopInputDMA ||
            action->operation == kTASAudioResetInputDMA ||
            action->operation == kTASAudioRebuildInputDMA) ?
            kTASStreamInput : kTASStreamOutput;
        if (self->runtime.rings[(unsigned long)direction].state ==
            kPPCDBDMARunning)
            return tas_stop_dma(self, direction,
                &self->runtime.rings[(unsigned long)direction],
                action->deadline);
        return kTASStatusOK;
    case kTASAudioGateI2SCell:
        return tas_status(PEI2SSetCellState(
            (unsigned int)self->machineConfig.i2sCell,
            kPEI2SCellDisabledReset));
    case kTASAudioEnableI2SCellClock:
        return tas_status(PEI2SSetCellState(
            (unsigned int)self->machineConfig.i2sCell,
            kPEI2SCellEnabledClockHeld));
    case kTASAudioApplyI2SRate:
        return tas_apply_i2s(self, self->runtime.audio.desired.rate,
            action->deadline);
    case kTASAudioDisableDetectIRQs:
        for (index = 2UL;
            index < (unsigned long)[[self deviceDescription] numInterrupts];
            ++index)
            [self disableInterrupt:(unsigned int)index];
        return kTASStatusOK;
    case kTASAudioEnableDetectIRQs:
        for (index = 2UL;
            index < (unsigned long)[[self deviceDescription] numInterrupts];
            ++index)
            [self enableInterrupt:(unsigned int)index];
        return kTASStatusOK;
    case kTASAudioCodecAnalogLowPower:
    case kTASAudioCodecMuteLowPower:
        return TASCodecSetMute(&self->runtime.codec, 1, action->deadline);
    default:
        return kTASStatusUnsupported;
    }
}

static TASStatus tas_controls(void *opaque,
    const TASAudioDesiredControls *controls, unsigned long deadline)
{
    PPCTASAudio *self;
    TASStatus status;
    self = (PPCTASAudio *)opaque;
    status = TASCodecSetMute(&self->runtime.codec, 1, deadline);
    if (status == kTASStatusOK)
        status = TASCodecSetVolume(&self->runtime.codec,
            controls->leftVolume, controls->rightVolume, deadline);
    if (status == kTASStatusOK)
        status = TASCodecSetInputGain(&self->runtime.codec,
            controls->inputGain, deadline);
    if (status == kTASStatusOK)
        status = TASCodecSetInputSource(&self->runtime.codec,
            (TASCodecInputSource)controls->inputSource, deadline);
    if (status == kTASStatusOK)
        status = TASCodecSetMute(&self->runtime.codec,
            controls->userMuted, deadline);
    return status;
}

static unsigned long tas_detects(void *opaque)
{
    PPCTASAudio *self;
    PEAudioGPIO gpio;
    boolean_t active;
    unsigned long detects;
    unsigned long route;
    self = (PPCTASAudio *)opaque;
    detects = 0UL;
    for (route = 0UL; route < kTASRouteCount; ++route) {
        if (!self->machineConfig.routes[route].present)
            continue;
        gpio.offset = self->machineConfig.routes[route].detect.offset;
        gpio.activeHigh = self->machineConfig.routes[route].detect.activeHigh;
        if (PEAudioGPIORead(&gpio, &active) == KERN_SUCCESS && active)
            detects |= 1UL << route;
    }
    return detects;
}

static void tas_signal(void *opaque)
{
    PPCTASAudio *self;
    self = (PPCTASAudio *)opaque;
    ++self->pendingGeneration;
    [self _interruptOccurred];
}

static TASRuntimeOps tas_runtime_ops(PPCTASAudio *self)
{
    TASRuntimeOps ops;
    memset(&ops, 0, sizeof(ops));
    ops.context = self;
    ops.codecCallbacks.context = self;
    ops.codecCallbacks.writeRegister = tas_codec_write;
    ops.codecCallbacks.setReset = tas_codec_reset;
    ops.codecCallbacks.delayMicroseconds = tas_codec_delay;
    ops.codecCallbacks.failMute = tas_fail_mute;
    ops.acquire = tas_acquire;
    ops.release = tas_release;
    ops.prepareDMA = tas_prepare_dma;
    ops.startDMA = tas_start_dma;
    ops.stopResetDMA = tas_stop_dma;
    ops.serviceDMA = tas_service_dma;
    ops.ackDMAInterrupt = tas_ack_dma_interrupt;
    ops.executeAction = tas_action;
    ops.applyControls = tas_controls;
    ops.sampleDetects = tas_detects;
    ops.now = tas_now;
    ops.signalDeferred = tas_signal;
    ops.failMute = tas_fail_mute;
    return ops;
}

static void tas_output_interrupt(void *identity, void *state, void *argument)
{
    (void)identity;
    (void)state;
    (void)TASRuntimeRecordDMAISR(&((PPCTASAudio *)argument)->runtime,
        kTASStreamOutput);
}

static void tas_input_interrupt(void *identity, void *state, void *argument)
{
    (void)identity;
    (void)state;
    (void)TASRuntimeRecordDMAISR(&((PPCTASAudio *)argument)->runtime,
        kTASStreamInput);
}

static void tas_detect_interrupt(void *identity, void *state, void *argument)
{
    (void)identity;
    (void)state;
    TASRuntimeRecordISR(&((PPCTASAudio *)argument)->runtime,
        kTASRuntimeIRQDetect);
}

@implementation PPCTASAudio

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    PPCTASPropertyContext propertyContext;
    TASPropertyReader reader;
    TASMachineConfig config;
    TASRuntimeOps ops;
    PPCTASAudio *instance;
    if (!tas_make_reader(&reader, &propertyContext) ||
        TASRuntimeProbe(&reader, &config) != kTASStatusOK)
        return NO;
    instance = [self alloc];
    if (instance == nil)
        return NO;
    instance->machineConfig = config;
    instance->tasDeviceDescription = deviceDescription;
    memset(&instance->desiredControls, 0,
        sizeof(instance->desiredControls));
    instance->desiredControls.rate = config.rates[0];
    instance->desiredControls.leftVolume = 0x8000UL;
    instance->desiredControls.rightVolume = 0x8000UL;
    ops = tas_runtime_ops(instance);
    if (TASRuntimeInit(&instance->runtime, &config,
        &instance->desiredControls, &ops) != kTASStatusOK ||
        [instance initFromDeviceDescription:deviceDescription] == nil) {
        [instance free];
        return NO;
    }
    return YES;
}

- (BOOL)reset
{
    unsigned long direction;
    void *registers;
    [self setDeviceKind:"PPCTASAudio"];
    [self setUnit:0];
    [self setName:"PPCTASAudio0"];
    if (TASRuntimeReset(&runtime, tas_now(self) + 1000UL) != kTASStatusOK)
        return NO;
    for (direction = 0UL; direction < 2UL; ++direction) {
        registers = direction == 0UL ? outputDBDMARegisters :
            inputDBDMARegisters;
        memset(&dmaOps[direction], 0, sizeof(dmaOps[direction]));
        dmaOps[direction].context = self;
        dmaOps[direction].translate = tas_translate;
        dmaOps[direction].registerContext = registers;
        dmaOps[direction].readRegister = tas_dma_read;
        dmaOps[direction].writeRegister = tas_dma_write;
        dmaOps[direction].now = tas_now;
        dmaOps[direction].coherencyContext = self;
        dmaOps[direction].publish = tas_publish;
        dmaOps[direction].invalidate = tas_publish;
        dmaOps[direction].barrier = tas_barrier;
    }
    return YES;
}

- free
{
    TASRuntimeUnwind(&runtime);
    return [super free];
}

- (BOOL)startDMAForChannel:(unsigned int)localChannel read:(BOOL)isRead
    buffer:(IODMABuffer)buffer
    bufferSizeForInterrupts:(unsigned int)bufferSize
{
    void *channelAddress;
    unsigned int channelBytes;
    (void)localChannel;
    if (isRead)
        [self getInputChannelBuffer:&channelAddress size:&channelBytes];
    else
        [self getOutputChannelBuffer:&channelAddress size:&channelBytes];
    (void)channelAddress;
    return TASRuntimeStartStream(&runtime,
        isRead ? kTASStreamInput : kTASStreamOutput, buffer,
        (unsigned long)channelBytes,
        bufferSize, [self sampleRate], tas_now(self) + 1000UL) ==
        kTASStatusOK ? YES : NO;
}

- (void)stopDMAForChannel:(unsigned int)localChannel read:(BOOL)isRead
{
    (void)localChannel;
    (void)TASRuntimeStopStream(&runtime,
        isRead ? kTASStreamInput : kTASStreamOutput,
        tas_now(self) + 1000UL);
}

- (void)interruptOccurredForInput:(BOOL *)serviceInput
    forOutput:(BOOL *)serviceOutput
{
    (void)TASRuntimeServiceDeferred(&runtime, tas_now(self) + 100UL,
        serviceInput, serviceOutput);
}

- (BOOL)getHandler:(IOInterruptHandler *)handler level:(unsigned int *)ipl
    argument:(void **)argument forInterrupt:(unsigned int)localInterrupt
{
    if (localInterrupt == 0U)
        *handler = (IOInterruptHandler)tas_output_interrupt;
    else if (localInterrupt == 1U)
        *handler = (IOInterruptHandler)tas_input_interrupt;
    else if (localInterrupt < [tasDeviceDescription numInterrupts])
        *handler = (IOInterruptHandler)tas_detect_interrupt;
    else
        return NO;
    *ipl = IPLDEVICE;
    *argument = self;
    return YES;
}

- (unsigned int)channelCount { return 2U; }
- (unsigned int)channelCountLimit { return 2U; }
- (BOOL)acceptsContinuousSamplingRates { return NO; }
- (void)getSamplingRatesLow:(int *)lowRate high:(int *)highRate
{
    *lowRate = (int)machineConfig.rates[0];
    *highRate = (int)machineConfig.rates[machineConfig.rateCount - 1UL];
}
- (void)getSamplingRates:(int *)rates count:(unsigned int *)numRates
{
    unsigned long index;
    *numRates = (unsigned int)machineConfig.rateCount;
    if (rates != 0)
        for (index = 0UL; index < machineConfig.rateCount; ++index)
            rates[index] = (int)machineConfig.rates[index];
}
- (void)getDataEncodings:(NXSoundParameterTag *)encodings
    count:(unsigned int *)numEncodings
{
    *numEncodings = 1U;
    if (encodings != 0)
        encodings[0] = NX_SoundStreamDataEncoding_Linear16;
}
- (BOOL)isInputActive
{
    return (runtime.clock.activeMask & kTASStreamMaskInput) != 0UL;
}
- (BOOL)isOutputActive
{
    return (runtime.clock.activeMask & kTASStreamMaskOutput) != 0UL;
}

- (void)updateInputGainLeft
{
    desiredControls.inputGain = [self inputGainLeft];
    (void)TASRuntimeSetControls(&runtime, &desiredControls,
        tas_now(self) + 100UL);
}
- (void)updateInputGainRight
{
    desiredControls.inputGain = [self inputGainRight];
    (void)TASRuntimeSetControls(&runtime, &desiredControls,
        tas_now(self) + 100UL);
}
- (void)updateOutputMute
{
    desiredControls.userMuted = [self isOutputMuted];
    (void)TASRuntimeSetControls(&runtime, &desiredControls,
        tas_now(self) + 100UL);
}
- (void)updateOutputAttenuationLeft
{
    desiredControls.leftVolume = (unsigned long)[self outputAttenuationLeft];
    (void)TASRuntimeSetControls(&runtime, &desiredControls,
        tas_now(self) + 100UL);
}
- (void)updateOutputAttenuationRight
{
    desiredControls.rightVolume = (unsigned long)[self outputAttenuationRight];
    (void)TASRuntimeSetControls(&runtime, &desiredControls,
        tas_now(self) + 100UL);
}
- (void)setInput:(NXSoundParameterTag)tag enable:(BOOL)enable
{
    if (enable)
        desiredControls.inputSource = tag == NX_SoundDeviceMicIn ?
            kTASCodecInputAnalog : kTASCodecInputDigital1;
    (void)TASRuntimeSetControls(&runtime, &desiredControls,
        tas_now(self) + 100UL);
}
- (void)setOutput:(NXSoundParameterTag)tag enable:(BOOL)enable
{
    (void)tag;
    desiredControls.userMuted = !enable;
    (void)TASRuntimeSetControls(&runtime, &desiredControls,
        tas_now(self) + 100UL);
}
- (void)setAnalogInputSource:(NXSoundParameterTag)tag
{
    [self setInput:tag enable:YES];
}
- (IOAudioInterruptClearFunc)interruptClearFunc
{
    /* Special direction-aware handlers own the sole DBDMA ack path. */
    return 0;
}

- (IOReturn)getPowerState:(PMPowerState *)state
{
    if (state == 0)
        return IO_R_INVALID_ARG;
    *state = currentPowerState;
    return IO_R_SUCCESS;
}
- (IOReturn)setPowerState:(PMPowerState)state
{
    TASPowerState target;
    target = state == PM_OFF ? kTASPowerOff :
        (state == PM_SUSPENDED ? kTASPowerSuspended : kTASPowerReady);
    if (TASRuntimeSetPower(&runtime, target, tas_now(self) + 1000UL) !=
        kTASStatusOK)
        return IO_R_IO;
    currentPowerState = state;
    return IO_R_SUCCESS;
}
- (IOReturn)getPowerManagement:(PMPowerManagementState *)state
{
    if (state == 0)
        return IO_R_INVALID_ARG;
    *state = PM_ENABLED;
    return IO_R_SUCCESS;
}
- (IOReturn)setPowerManagement:(PMPowerManagementState)state
{
    return state == PM_ENABLED || state == PM_DISABLED ? IO_R_SUCCESS :
        IO_R_INVALID_ARG;
}

/* The current PPC kernel does not dispatch DriverKit power callbacks end to end. */

@end
