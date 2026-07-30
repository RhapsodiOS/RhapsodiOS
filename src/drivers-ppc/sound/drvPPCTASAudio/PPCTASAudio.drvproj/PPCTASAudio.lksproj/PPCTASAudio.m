#import "PPCTASAudio.h"
#import "TASTime.h"

#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/KernLock.h>
#import <machkit/NXLock.h>
#import <driverkit/ppc/IODBDMA.h>
#import <driverkit/ppc/IOTreeDevice.h>
#import <driverkit/ppc/IOPropertyTable.h>
#import <machdep/ppc/PEKeyLargo.h>
#import <kernserv/ns_timer.h>
#import <kernserv/prototypes.h>

#include <string.h>

#define TAS_TREE_NODES 128
#define TAS_I2S_SERIAL_FORMAT 0x10
#define TAS_I2S_DATA_WORD     0x18
#define TAS_POLL_INTERVAL_MS 250UL
#define TAS_NSEC_PER_MS      1000000ULL

extern void flush_cache_v(vm_offset_t, unsigned int);

@interface IOTreeDevice (PPCTASIteration)
+ findForIndex:(UInt32)index;
@end

typedef struct {
    IOTreeDevice *nodes[TAS_TREE_NODES];
    unsigned long count;
} PPCTASPropertyContext;

static TASStatus tas_detects(void *opaque, unsigned long *result);
static unsigned long tas_now(void *opaque);
static void tas_wait_microseconds(void *opaque, unsigned long usec);
static void tas_debounce_callout(void *opaque);
static void tas_poll_callout(void *opaque);
static void tas_worker_retry_callout(void *opaque);

/* The permanent lock serializes the singleton owner and token namespace. */
static NXLock *tasCalloutLock;
static PPCTASAudio *tasCalloutOwner;
static unsigned long tasNextCalloutToken;

static unsigned long tas_deadline_after(PPCTASAudio *self,
    unsigned long interval)
{
    unsigned long now;
    unsigned long deadline;
    now = tas_now(self);
    if (!TASTimeAdd(now, interval, &deadline))
        return now;
    return deadline;
}

static int tas_is_closing(PPCTASAudio *self)
{
    int closing;
    [tasCalloutLock lock];
    closing = self->closing;
    [tasCalloutLock unlock];
    return closing;
}

static void tas_lock_interrupt(void *opaque)
{
    [((PPCTASAudio *)opaque)->interruptLock acquire];
}

static void tas_unlock_interrupt(void *opaque)
{
    [((PPCTASAudio *)opaque)->interruptLock release];
}

/* Task lock order is operation -> state; raw ISRs use interrupt only. */
static void tas_lock_operation(void *opaque)
{
    [((PPCTASAudio *)opaque)->operationLock lock];
}

static void tas_unlock_operation(void *opaque)
{
    [((PPCTASAudio *)opaque)->operationLock unlock];
}

static void tas_lock_state(void *opaque)
{
    [((PPCTASAudio *)opaque)->stateLock acquire];
}

static void tas_unlock_state(void *opaque)
{
    [((PPCTASAudio *)opaque)->stateLock release];
}

static int tas_post_worker_message(PPCTASAudio *self)
{
    msg_header_t msg;
    memset(&msg, 0, sizeof(msg));
    msg.msg_size = sizeof(msg);
    msg.msg_remote_port = IOGetKernPort([self interruptPort]);
    msg.msg_id = IO_DEVICE_INTERRUPT_MSG;
    return msg_send_from_kernel(&msg, SEND_TIMEOUT, 0) == SEND_SUCCESS;
}

static unsigned long tas_next_callout_token_locked(void)
{
    if (tasNextCalloutToken == ~0UL)
        return 0UL;
    ++tasNextCalloutToken;
    return tasNextCalloutToken;
}

static void tas_schedule_worker_retry_locked(PPCTASAudio *self)
{
    unsigned long token;
    if (self->closing || self->workerRetryCalloutPending)
        return;
    token = tas_next_callout_token_locked();
    if (token == 0UL)
        return;
    self->workerRetryCalloutToken = token;
    self->workerRetryCalloutPending = 1;
    ns_timeout((func)tas_worker_retry_callout, (void *)token,
        (ns_time_t)TAS_AUDIO_DEBOUNCE_CONFIRM_MS * TAS_NSEC_PER_MS,
        CALLOUT_PRI_THREAD);
}

static void tas_signal_worker_locked(PPCTASAudio *self)
{
    if (tas_post_worker_message(self)) {
        if (self->workerRetryCalloutPending)
            (void)ns_untimeout((func)tas_worker_retry_callout,
                (void *)self->workerRetryCalloutToken);
        self->workerRetryCalloutPending = 0;
        self->workerRetryCalloutToken = 0UL;
    } else
        tas_schedule_worker_retry_locked(self);
}

static void tas_signal(void *opaque)
{
    PPCTASAudio *self;
    self = (PPCTASAudio *)opaque;
    [tasCalloutLock lock];
    if (tasCalloutOwner == self && !self->closing)
        tas_signal_worker_locked(self);
    [tasCalloutLock unlock];
}

static void tas_arm_poll_locked(PPCTASAudio *self)
{
    unsigned long token;
    if (self->closing || self->pollCalloutPending)
        return;
    token = tas_next_callout_token_locked();
    if (token == 0UL)
        return;
    self->pollCalloutToken = token;
    self->pollCalloutPending = 1;
    ns_timeout((func)tas_poll_callout, (void *)token,
        (ns_time_t)TAS_POLL_INTERVAL_MS * TAS_NSEC_PER_MS,
        CALLOUT_PRI_THREAD);
}

static void tas_arm_poll(PPCTASAudio *self)
{
    [tasCalloutLock lock];
    if (tasCalloutOwner == self)
        tas_arm_poll_locked(self);
    [tasCalloutLock unlock];
}

static int tas_register_callouts(PPCTASAudio *self)
{
    if (tasCalloutLock == nil)
        return 0;
    [tasCalloutLock lock];
    if (tasCalloutOwner != nil) {
        [tasCalloutLock unlock];
        return 0;
    }
    self->closing = 0;
    tasCalloutOwner = self;
    [tasCalloutLock unlock];
    return 1;
}

static void tas_cancel_callouts(PPCTASAudio *self, int retainOwner)
{
    if (tasCalloutLock == nil)
        return;
    [tasCalloutLock lock];
    if (tasCalloutOwner == self) {
        self->closing = 1;
        if (self->debounceCalloutPending)
            (void)ns_untimeout((func)tas_debounce_callout,
                (void *)self->debounceCalloutToken);
        if (self->pollCalloutPending)
            (void)ns_untimeout((func)tas_poll_callout,
                (void *)self->pollCalloutToken);
        if (self->workerRetryCalloutPending)
            (void)ns_untimeout((func)tas_worker_retry_callout,
                (void *)self->workerRetryCalloutToken);
        self->debounceCalloutPending = 0;
        self->pollCalloutPending = 0;
        self->workerRetryCalloutPending = 0;
        self->debounceCalloutToken = 0UL;
        self->pollCalloutToken = 0UL;
        self->workerRetryCalloutToken = 0UL;
        if (!retainOwner)
            tasCalloutOwner = nil;
    }
    [tasCalloutLock unlock];
}

static TASStatus tas_schedule_debounce_locked(PPCTASAudio *self,
    ns_time_t delay)
{
    unsigned long token;
    token = tas_next_callout_token_locked();
    if (token == 0UL)
        return kTASStatusOverflow;
    self->debounceCalloutToken = token;
    self->debounceCalloutPending = 1;
    ns_timeout((func)tas_debounce_callout, (void *)token, delay,
        CALLOUT_PRI_THREAD);
    return kTASStatusOK;
}

static void tas_debounce_callout(void *opaque)
{
    PPCTASAudio *self;
    unsigned long token;
    unsigned long generation;
    unsigned long deadline;
    unsigned long now;
    unsigned long remaining;
    int valid;
    token = (unsigned long)opaque;
    [tasCalloutLock lock];
    self = tasCalloutOwner;
    if (self == nil || self->closing || !self->debounceCalloutPending ||
        token != self->debounceCalloutToken) {
        [tasCalloutLock unlock];
        return;
    }
    generation = self->debounceCalloutGeneration;
    deadline = self->debounceCalloutDeadline;
    now = tas_now(self);
    if (!TASTimeDue(now, deadline)) {
        self->debounceCalloutPending = 0;
        self->debounceCalloutToken = 0UL;
        if (TASTimeRemaining(now, deadline, &remaining))
            (void)tas_schedule_debounce_locked(self,
                (ns_time_t)remaining * TAS_NSEC_PER_MS);
        [tasCalloutLock unlock];
        return;
    }
    [self->stateLock acquire];
    valid = self->runtime.audio.debouncePending &&
        self->runtime.audio.detectGeneration == generation &&
        self->runtime.audio.debounceDeadline == deadline;
    [self->stateLock release];
    self->debounceCalloutPending = 0;
    self->debounceCalloutToken = 0UL;
    if (valid)
        tas_signal_worker_locked(self);
    [tasCalloutLock unlock];
}

static void tas_poll_callout(void *opaque)
{
    PPCTASAudio *self;
    TASPowerState powerState;
    unsigned long token;
    token = (unsigned long)opaque;
    [tasCalloutLock lock];
    self = tasCalloutOwner;
    if (self == nil || self->closing || !self->pollCalloutPending ||
        token != self->pollCalloutToken) {
        [tasCalloutLock unlock];
        return;
    }
    self->pollCalloutPending = 0;
    self->pollCalloutToken = 0UL;
    [self->stateLock acquire];
    powerState = self->runtime.audio.powerState;
    [self->stateLock release];
    if (self->runtime.initialized && powerState == kTASPowerReady) {
        TASRuntimeRecordISR(&self->runtime, kTASRuntimeIRQDetect);
        tas_signal_worker_locked(self);
    }
    tas_arm_poll_locked(self);
    [tasCalloutLock unlock];
}

static void tas_worker_retry_callout(void *opaque)
{
    PPCTASAudio *self;
    unsigned long token;
    token = (unsigned long)opaque;
    [tasCalloutLock lock];
    self = tasCalloutOwner;
    if (self == nil || self->closing ||
        !self->workerRetryCalloutPending ||
        token != self->workerRetryCalloutToken) {
        [tasCalloutLock unlock];
        return;
    }
    self->workerRetryCalloutPending = 0;
    self->workerRetryCalloutToken = 0UL;
    tas_signal_worker_locked(self);
    [tasCalloutLock unlock];
}

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

static unsigned long tas_resolve_phandle(void *opaque,
    unsigned long phandle, TASNode *node)
{
    PPCTASPropertyContext *context;
    static const char *names[] = { "AAPL,phandle", "phandle",
        "linux,phandle" };
    const unsigned char *bytes;
    unsigned long length;
    unsigned long index;
    unsigned long name;
    unsigned long value;
    unsigned long matches;
    context = (PPCTASPropertyContext *)opaque;
    matches = 0UL;
    for (index = 0UL; index < context->count; ++index) {
        for (name = 0UL; name < sizeof(names) / sizeof(names[0]); ++name) {
            if (!tas_get_property(context, index + 1UL, names[name],
                &bytes, &length) || length != 4UL)
                continue;
            value = ((unsigned long)bytes[0] << 24) |
                ((unsigned long)bytes[1] << 16) |
                ((unsigned long)bytes[2] << 8) | bytes[3];
            if (value == phandle) {
                *node = index + 1UL;
                ++matches;
            }
            break;
        }
    }
    return matches;
}

static int tas_make_reader(TASPropertyReader *reader,
    PPCTASPropertyContext *context, IODeviceDescription *description)
{
    unsigned long index;
    unsigned long matches;
    id node;
    char candidatePath[256];
    char nodePath[256];
    if (description == nil)
        return 0;
    candidatePath[0] = '\0';
    [description getDevicePath:candidatePath maxLength:sizeof(candidatePath)
        useAlias:NO];
    if (candidatePath[0] == '\0')
        return 0;
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
    reader->resolvePhandle = tas_resolve_phandle;
    reader->getParent = tas_get_parent;
    matches = 0UL;
    for (index = 0UL; index < context->count; ++index) {
        nodePath[0] = '\0';
        [context->nodes[index] getDevicePath:nodePath
            maxLength:sizeof(nodePath) useAlias:NO];
        if (strcmp(candidatePath, nodePath) == 0) {
            reader->candidateNode = index + 1UL;
            ++matches;
        }
    }
    return matches == 1UL;
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
    ns_time_t absolute;
    unsigned long remaining;
    unsigned long serialNow;
    self = (PPCTASAudio *)opaque;
    IOGetTimestamp(&absolute);
    serialNow = TASTimeNormalize(
        (unsigned long)(absolute / TAS_NSEC_PER_MS));
    if (!TASTimeRemaining(serialNow, deadline, &remaining) ||
        remaining == 0UL) {
        *written = 0UL;
        return kTASStatusTimeout;
    }
    absolute -= absolute % TAS_NSEC_PER_MS;
    absolute += (ns_time_t)remaining * TAS_NSEC_PER_MS;
    memset(&request, 0, sizeof(request));
    request.port = self->machineConfig.i2cPort;
    request.address = (unsigned char)self->machineConfig.i2cAddress;
    request.subaddress = reg;
    request.direction = kPEKeyWestWrite;
    request.buffer = (unsigned char *)bytes;
    request.length = (unsigned int)length;
    request.deadline.tv_sec = absolute / 1000000000ULL;
    request.deadline.tv_nsec = absolute % 1000000000ULL;
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
    return TASRuntimeBoundedDelay(opaque, usec, deadline, tas_now,
        tas_wait_microseconds);
}

static void tas_wait_microseconds(void *opaque, unsigned long usec)
{
    (void)opaque;
    IODelay(usec);
}

static TASStatus tas_write_mute_gpio(void *opaque,
    const TASGPIODescriptor *descriptor, int active)
{
    PEAudioGPIO gpio;
    (void)opaque;
    gpio.offset = descriptor->offset;
    gpio.activeHigh = descriptor->activeHigh;
    return tas_status(PEAudioGPIOWrite(&gpio, active ? TRUE : FALSE));
}

static TASStatus tas_fail_mute_outputs(PPCTASAudio *self)
{
    return TASRuntimeFailMuteOutputs(&self->machineConfig, self,
        tas_write_mute_gpio);
}

static void tas_fail_mute(void *opaque)
{
    PPCTASAudio *self;
    self = (PPCTASAudio *)opaque;
    (void)tas_fail_mute_outputs(self);
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
    return TASTimeNormalize((unsigned long)(now / 1000000ULL));
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
    if (TASTimeDue(tas_now(self), deadline))
        return kTASStatusTimeout;
    if (PEI2SSetCellState((unsigned int)self->machineConfig.i2sCell,
        kPEI2SCellEnabledClockHeld) != KERN_SUCCESS)
        return kTASStatusUnresolved;
    if (TASTimeDue(tas_now(self), deadline))
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
    IOPhysicalAddress physical;
    self = (PPCTASAudio *)opaque;
    switch (stage) {
    case kTASRuntimePlatformReady:
        (void)config;
        return kTASStatusOK;
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
        if (index == 1UL)
            self->dmaOps[0].registerContext = self->outputDBDMARegisters;
        else if (index == 2UL)
            self->dmaOps[1].registerContext = self->inputDBDMARegisters;
        return kTASStatusOK;
    case kTASRuntimeInstallOutputIRQ:
    case kTASRuntimeInstallInputIRQ:
        if (stage == kTASRuntimeInstallOutputIRQ)
            [self enableInterrupt:1U];
        else
            [self enableInterrupt:2U];
        return kTASStatusOK;
    case kTASRuntimeInstallDetectIRQs:
        /* GPIO detects are child resources, not main interrupt ordinals. */
        return kTASStatusOK;
    case kTASRuntimeEnableI2S:
        return tas_apply_i2s(self, self->desiredControls.rate,
            self->runtime.operationDeadline);
    case kTASRuntimeSafeOutputs:
        return tas_fail_mute_outputs(self);
    case kTASRuntimeInitializeCodec:
        return TASCodecInitialize(&self->runtime.codec, 1,
            self->runtime.operationDeadline);
    case kTASRuntimeAllocateOutputRing:
    case kTASRuntimeAllocateInputRing:
        index = (unsigned long)stage -
            (unsigned long)kTASRuntimeAllocateOutputRing;
        if (PPC_DBDMA_MAX_RING_BYTES > 4096UL)
            return kTASStatusUnsupported;
        if (IOAllocatePhysicallyContiguousMemory(
            (unsigned int)PPC_DBDMA_MAX_RING_BYTES, 0,
            (IOVirtualAddress *)&self->ringAllocations[index * 2UL],
            &physical) != IO_R_SUCCESS)
            return kTASStatusMissing;
        if ((((unsigned long)self->ringAllocations[index * 2UL] |
            (unsigned long)physical) & 15UL) != 0UL ||
            (unsigned long)physical > ~0UL - PPC_DBDMA_MAX_RING_BYTES) {
            (void)IOFreePhysicallyContiguousMemory(
                (IOVirtualAddress *)self->ringAllocations[index * 2UL],
                (unsigned int)PPC_DBDMA_MAX_RING_BYTES);
            self->ringAllocations[index * 2UL] = 0;
            return kTASStatusUnresolved;
        }
        self->ringAllocations[index * 2UL + 1UL] =
            IOMalloc(PPC_DBDMA_MAX_RING_BYTES + 15UL);
        if (self->ringAllocations[index * 2UL + 1UL] == 0) {
            (void)IOFreePhysicallyContiguousMemory(
                (IOVirtualAddress *)self->ringAllocations[index * 2UL],
                (unsigned int)PPC_DBDMA_MAX_RING_BYTES);
            self->ringAllocations[index * 2UL] = 0;
            return kTASStatusMissing;
        }
        self->ringStorage[index].logical =
            self->ringAllocations[index * 2UL];
        self->ringStorage[index].scratch = (void *)
            (((unsigned long)self->ringAllocations[index * 2UL + 1UL] +
            15UL) & ~15UL);
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
        [self disableInterrupt:stage == kTASRuntimeInstallOutputIRQ ?
            1U : 2U];
    } else if (stage == kTASRuntimeInstallDetectIRQs) {
        /* No main-description detect interrupt was installed. */
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
            (void)IOFreePhysicallyContiguousMemory(
                (IOVirtualAddress *)self->ringAllocations[index * 2UL],
                (unsigned int)PPC_DBDMA_MAX_RING_BYTES);
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

static TASStatus tas_ack_detect_interrupt(void *opaque)
{
    (void)opaque;
    /* mpic_interrupt writes MPIC_P0_EOI before invoking this handler. */
    eieio();
    return kTASStatusOK;
}

static TASStatus tas_action(void *opaque, const TASAudioAction *action)
{
    PPCTASAudio *self;
    PEAudioGPIO gpio;
    TASStreamDirection direction;
    TASAudioDesiredControls desired;
    TASStatus status;
    self = (PPCTASAudio *)opaque;
    [self->stateLock acquire];
    desired = self->runtime.audio.desired;
    [self->stateLock release];
    switch (action->operation) {
    case kTASAudioBlockStarts:
        return kTASStatusOK;
    case kTASAudioScheduleDebounce:
        if (tasCalloutLock == nil)
            return kTASStatusConflict;
        [tasCalloutLock lock];
        if (tasCalloutOwner != self || self->closing) {
            [tasCalloutLock unlock];
            return kTASStatusConflict;
        }
        if (self->debounceCalloutPending) {
            (void)ns_untimeout((func)tas_debounce_callout,
                (void *)self->debounceCalloutToken);
            self->debounceCalloutPending = 0;
            self->debounceCalloutToken = 0UL;
        }
        self->debounceCalloutGeneration = action->value;
        self->debounceCalloutDeadline = action->deadline;
        status = tas_schedule_debounce_locked(self,
            (ns_time_t)TAS_AUDIO_DEBOUNCE_CONFIRM_MS * TAS_NSEC_PER_MS);
        [tasCalloutLock unlock];
        return status;
    case kTASAudioSampleDetects:
        /* TASRuntime performs the single injected physical sample. */
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
        return tas_codec_reset(self,
            action->operation == kTASAudioAssertReset);
    case kTASAudioAssertAndedReset:
    case kTASAudioReleaseAndedReset:
        return TASRuntimeApplyANDedReset(&self->machineConfig,
            action->operation == kTASAudioAssertAndedReset, self,
            tas_write_mute_gpio);
    case kTASAudioSetResetAmpConstituent:
        gpio.offset = self->machineConfig.amplifierMute.offset;
        gpio.activeHigh = self->machineConfig.amplifierMute.activeHigh;
        return tas_status(PEAudioGPIOWrite(&gpio, action->value != 0UL));
    case kTASAudioSetResetHeadphoneConstituent:
        gpio.offset = self->machineConfig.routes[kTASRouteHeadphone].mute.offset;
        gpio.activeHigh =
            self->machineConfig.routes[kTASRouteHeadphone].mute.activeHigh;
        return tas_status(PEAudioGPIOWrite(&gpio, action->value != 0UL));
    case kTASAudioRestoreInputSource:
        return TASCodecSetInputSource(&self->runtime.codec,
            (TASCodecInputSource)desired.inputSource,
            action->deadline);
    case kTASAudioCodecRestore:
        return TASCodecRestore(&self->runtime.codec, action->deadline);
    case kTASAudioCodecReset:
        return TASCodecInitialize(&self->runtime.codec, 1, action->deadline);
    case kTASAudioRestoreVolume:
        return TASCodecSetVolume(&self->runtime.codec,
            desired.leftVolume, desired.rightVolume, action->deadline);
    case kTASAudioRestoreInputGain:
        return TASCodecSetInputGain(&self->runtime.codec,
            desired.inputGain, action->deadline);
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
            kPPCDBDMARunning ||
            self->runtime.rings[(unsigned long)direction].state ==
            kPPCDBDMAFaulted)
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
        return tas_apply_i2s(self, desired.rate,
            action->deadline);
    case kTASAudioDisableDetectIRQs:
        return kTASStatusOK;
    case kTASAudioEnableDetectIRQs:
        /* Detect GPIO IRQs are not main-description interrupt ordinals. */
        tas_arm_poll(self);
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
    PEAudioGPIO gpio;
    TASStatus status;
    int oldMuxActive;
    self = (PPCTASAudio *)opaque;
    oldMuxActive = self->desiredControls.inputMuxActive;
    gpio.offset = self->machineConfig.inputMux.offset;
    gpio.activeHigh = self->machineConfig.inputMux.activeHigh;
    status = tas_status(PEAudioGPIOWrite(&gpio,
        controls->inputMuxActive ? TRUE : FALSE));
    if (status != kTASStatusOK)
        return status;
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
    if (status != kTASStatusOK &&
        oldMuxActive != controls->inputMuxActive)
        (void)PEAudioGPIOWrite(&gpio, oldMuxActive ? TRUE : FALSE);
    return status;
}

static TASStatus tas_detects(void *opaque, unsigned long *result)
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
        if (PEAudioGPIORead(&gpio, &active) != KERN_SUCCESS)
            return kTASStatusTimeout;
        if (active)
            detects |= 1UL << route;
    }
    *result = detects;
    return kTASStatusOK;
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
    ops.ackDetectInterrupt = tas_ack_detect_interrupt;
    ops.lockInterrupt = tas_lock_interrupt;
    ops.unlockInterrupt = tas_unlock_interrupt;
    ops.lockOperation = tas_lock_operation;
    ops.unlockOperation = tas_unlock_operation;
    ops.lockState = tas_lock_state;
    ops.unlockState = tas_unlock_state;
    ops.executeAction = tas_action;
    ops.applyControls = tas_controls;
    ops.sampleDetects = tas_detects;
    ops.now = tas_now;
    ops.signalDeferred = tas_signal;
    ops.failMuteOutputs = tas_fail_mute_outputs;
    return ops;
}

static void tas_output_interrupt(void *identity, void *state, void *argument)
{
    PPCTASAudio *self;
    int handled;
    self = (PPCTASAudio *)argument;
    [self->interruptLock acquire];
    handled = !self->interruptClosing;
    if (!self->interruptClosing)
        (void)TASRuntimeRecordDMAISRLocked(&self->runtime,
            kTASStreamOutput);
    [self->interruptLock release];
    if (handled)
        IOSendInterrupt(identity, state, IO_DEVICE_INTERRUPT_MSG);
}

static void tas_input_interrupt(void *identity, void *state, void *argument)
{
    PPCTASAudio *self;
    int handled;
    self = (PPCTASAudio *)argument;
    [self->interruptLock acquire];
    handled = !self->interruptClosing;
    if (!self->interruptClosing)
        (void)TASRuntimeRecordDMAISRLocked(&self->runtime,
            kTASStreamInput);
    [self->interruptLock release];
    if (handled)
        IOSendInterrupt(identity, state, IO_DEVICE_INTERRUPT_MSG);
}

static TASStatus tas_update_controls(PPCTASAudio *self,
    const TASAudioDesiredControls *candidate)
{
    TASStatus status;
    if (tas_is_closing(self))
        return kTASStatusConflict;
    status = TASRuntimeSetControls(&self->runtime, candidate,
        tas_deadline_after(self, 100UL));
    if (status == kTASStatusOK)
        self->desiredControls = *candidate;
    return status;
}

static void tas_initialize_dma_ops(PPCTASAudio *self)
{
    unsigned long direction;
    for (direction = 0UL; direction < 2UL; ++direction) {
        memset(&self->dmaOps[direction], 0, sizeof(self->dmaOps[direction]));
        self->dmaOps[direction].context = self;
        self->dmaOps[direction].translate = tas_translate;
        self->dmaOps[direction].readRegister = tas_dma_read;
        self->dmaOps[direction].writeRegister = tas_dma_write;
        self->dmaOps[direction].now = tas_now;
        self->dmaOps[direction].coherencyContext = self;
        self->dmaOps[direction].publish = tas_publish;
        self->dmaOps[direction].invalidate = tas_publish;
        self->dmaOps[direction].barrier = tas_barrier;
    }
}

@implementation PPCTASAudio

+ initialize
{
    /* The Objective-C runtime serializes this permanent broker setup. */
    if (self == [PPCTASAudio class] && tasCalloutLock == nil)
        tasCalloutLock = [NXLock new];
    return [super initialize];
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    PPCTASPropertyContext propertyContext;
    TASPropertyReader reader;
    TASMachineConfig config;
    TASRuntimeOps ops;
    TASDeliveredRange deliveredRanges[3];
    IORange *memoryRanges;
    unsigned int *interrupts;
    unsigned long index;
    PPCTASAudio *instance;
    if (!tas_make_reader(&reader, &propertyContext, deviceDescription) ||
        TASRuntimeProbe(&reader, &config) != kTASStatusOK)
        return NO;
    if (deviceDescription == nil ||
        [deviceDescription numMemoryRanges] != 3U ||
        [deviceDescription numInterrupts] != 3U)
        return NO;
    memoryRanges = [deviceDescription memoryRangeList];
    interrupts = [deviceDescription interruptList];
    if (memoryRanges == 0 || interrupts == 0)
        return NO;
    for (index = 0UL; index < 3UL; ++index) {
        deliveredRanges[index].start =
            (unsigned long)memoryRanges[index].start;
        deliveredRanges[index].size =
            (unsigned long)memoryRanges[index].size;
    }
    if (TASRuntimeValidateResources(&config, 3UL, deliveredRanges, 3UL,
        interrupts) != kTASStatusOK)
        return NO;
    instance = [self alloc];
    if (instance == nil)
        return NO;
    instance->machineConfig = config;
    instance->tasDeviceDescription = deviceDescription;
    instance->interruptLock = [[KernLock alloc] initWithLevel:7];
    instance->operationLock = [NXLock new];
    instance->stateLock = [[KernLock alloc] initWithLevel:7];
    if (instance->interruptLock == nil || instance->operationLock == nil ||
        instance->stateLock == nil) {
        [instance free];
        return NO;
    }
    memset(&instance->desiredControls, 0,
        sizeof(instance->desiredControls));
    instance->desiredControls.rate = config.rates[0];
    instance->desiredControls.leftVolume = 0x8000UL;
    instance->desiredControls.rightVolume = 0x8000UL;
    ops = tas_runtime_ops(instance);
    if (TASRuntimeInit(&instance->runtime, &config,
        &instance->desiredControls, &ops) != kTASStatusOK) {
        [instance free];
        return NO;
    }
    if (!tas_register_callouts(instance)) {
        [instance free];
        return NO;
    }
    if ([instance initFromDeviceDescription:deviceDescription] == nil) {
        [instance free];
        return NO;
    }
    instance->ioAudioInitialized = 1;
    return YES;
}

- (BOOL)reset
{
    if (tas_is_closing(self))
        return NO;
    [self setDeviceKind:"PPCTASAudio"];
    [self setUnit:0];
    [self setName:"PPCTASAudio0"];
    tas_initialize_dma_ops(self);
    if (TASRuntimeReset(&runtime, tas_deadline_after(self, 1000UL)) !=
        kTASStatusOK)
        return NO;
    tas_arm_poll(self);
    return YES;
}

- free
{
    TASStatus status;
    [interruptLock acquire];
    self->interruptClosing = 1;
    [interruptLock release];
    tas_cancel_callouts(self, 1);
    if (runtime.initialized) {
        (void)TASRuntimeBeginClose(&runtime);
        status = TASRuntimeUnwind(&runtime);
    } else
        status = kTASStatusOK;
    if (status != kTASStatusOK) {
        IOLog("PPCTASAudio: DMA cleanup failed; preserving resources\n");
        return self;
    }
    if (!ioAudioInitialized) {
        tas_cancel_callouts(self, 0);
        [interruptLock free];
        interruptLock = nil;
        [operationLock free];
        operationLock = nil;
        [stateLock free];
        stateLock = nil;
        return [super free];
    }
    IOLog("PPCTASAudio: quiesced; IOAudio worker threads retain driver\n");
    return self;
}

- (BOOL)startDMAForChannel:(unsigned int)localChannel read:(BOOL)isRead
    buffer:(IODMABuffer)buffer
    bufferSizeForInterrupts:(unsigned int)bufferSize
{
    void *channelAddress;
    unsigned int channelBytes;
    (void)localChannel;
    if (tas_is_closing(self))
        return NO;
    if (isRead)
        [self getInputChannelBuffer:&channelAddress size:&channelBytes];
    else
        [self getOutputChannelBuffer:&channelAddress size:&channelBytes];
    (void)channelAddress;
    return TASRuntimeStartStream(&runtime,
        isRead ? kTASStreamInput : kTASStreamOutput, buffer,
        (unsigned long)channelBytes,
        bufferSize, [self sampleRate], tas_deadline_after(self, 1000UL)) ==
        kTASStatusOK ? YES : NO;
}

- (void)stopDMAForChannel:(unsigned int)localChannel read:(BOOL)isRead
{
    (void)localChannel;
    if (tas_is_closing(self))
        return;
    (void)TASRuntimeStopStream(&runtime,
        isRead ? kTASStreamInput : kTASStreamOutput,
        tas_deadline_after(self, 1000UL));
}

- (void)interruptOccurredForInput:(BOOL *)serviceInput
    forOutput:(BOOL *)serviceOutput
{
    *serviceInput = NO;
    *serviceOutput = NO;
    if (tas_is_closing(self))
        return;
    (void)TASRuntimeServiceDeferred(&runtime,
        tas_deadline_after(self, 100UL),
        serviceInput, serviceOutput);
}

- (BOOL)getHandler:(IOInterruptHandler *)handler level:(unsigned int *)ipl
    argument:(void **)argument forInterrupt:(unsigned int)localInterrupt
{
    if (localInterrupt == 1U)
        *handler = (IOInterruptHandler)tas_output_interrupt;
    else if (localInterrupt == 2U)
        *handler = (IOInterruptHandler)tas_input_interrupt;
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
    BOOL active;
    if (tas_is_closing(self))
        return NO;
    [operationLock lock];
    active = (runtime.clock.activeMask & kTASStreamMaskInput) != 0UL;
    [operationLock unlock];
    return active;
}
- (BOOL)isOutputActive
{
    BOOL active;
    if (tas_is_closing(self))
        return NO;
    [operationLock lock];
    active = (runtime.clock.activeMask & kTASStreamMaskOutput) != 0UL;
    [operationLock unlock];
    return active;
}

- (void)updateInputGainLeft
{
    TASAudioDesiredControls candidate;
    unsigned long coefficient;
    if (tas_is_closing(self))
        return;
    if (TASRuntimeGainToCodec((int)[self inputGainLeft], &coefficient) !=
        kTASStatusOK)
        return;
    candidate = desiredControls;
    candidate.inputGain = coefficient;
    (void)tas_update_controls(self, &candidate);
}
- (void)updateInputGainRight
{
    TASAudioDesiredControls candidate;
    unsigned long coefficient;
    if (tas_is_closing(self))
        return;
    if (TASRuntimeGainToCodec((int)[self inputGainRight], &coefficient) !=
        kTASStatusOK)
        return;
    candidate = desiredControls;
    candidate.inputGain = coefficient;
    (void)tas_update_controls(self, &candidate);
}
- (void)updateOutputMute
{
    TASAudioDesiredControls candidate;
    if (tas_is_closing(self))
        return;
    candidate = desiredControls;
    candidate.userMuted = [self isOutputMuted];
    (void)tas_update_controls(self, &candidate);
}
- (void)updateOutputAttenuationLeft
{
    TASAudioDesiredControls candidate;
    unsigned long coefficient;
    if (tas_is_closing(self))
        return;
    if (TASRuntimeAttenuationToCodec([self outputAttenuationLeft],
        &coefficient) != kTASStatusOK)
        return;
    candidate = desiredControls;
    candidate.leftVolume = coefficient;
    (void)tas_update_controls(self, &candidate);
}
- (void)updateOutputAttenuationRight
{
    TASAudioDesiredControls candidate;
    unsigned long coefficient;
    if (tas_is_closing(self))
        return;
    if (TASRuntimeAttenuationToCodec([self outputAttenuationRight],
        &coefficient) != kTASStatusOK)
        return;
    candidate = desiredControls;
    candidate.rightVolume = coefficient;
    (void)tas_update_controls(self, &candidate);
}
- (void)setInput:(NXSoundParameterTag)tag enable:(BOOL)enable
{
    TASAudioDesiredControls candidate;
    if (tas_is_closing(self))
        return;
    candidate = desiredControls;
    if (!enable)
        return;
    if (tag != NX_SoundDeviceMicIn && tag != NX_SoundDeviceLineIn)
        return;
    /* The required firmware input-data-mux proves the two external analog
     * positions.  Keep the TAS mixer on one stable I2S path: this GPIO,
     * never output-route state, selects microphone (inactive) or line
     * (active). */
    candidate.inputMuxActive = tag == NX_SoundDeviceLineIn;
    candidate.inputSource = kTASCodecInputDigital1;
    (void)tas_update_controls(self, &candidate);
}
- (void)setOutput:(NXSoundParameterTag)tag enable:(BOOL)enable
{
    TASAudioDesiredControls candidate;
    (void)tag;
    if (tas_is_closing(self))
        return;
    candidate = desiredControls;
    candidate.userMuted = !enable;
    (void)tas_update_controls(self, &candidate);
}
- (void)setAnalogInputSource:(NXSoundParameterTag)tag
{
    if (tas_is_closing(self))
        return;
    if (tag == NX_SoundDeviceAnalogInputSource_Microphone)
        [self setInput:NX_SoundDeviceMicIn enable:YES];
    else if (tag == NX_SoundDeviceAnalogInputSource_LineIn)
        [self setInput:NX_SoundDeviceLineIn enable:YES];
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
    if (tas_is_closing(self))
        return IO_R_NOT_ATTACHED;
    target = state == PM_OFF ? kTASPowerOff :
        (state == PM_SUSPENDED ? kTASPowerSuspended :
        (state == PM_STANDBY ? kTASPowerStandby : kTASPowerReady));
    if (TASRuntimeSetPower(&runtime, target,
        tas_deadline_after(self, 1000UL)) !=
        kTASStatusOK)
        return IO_R_IO;
    if (target == kTASPowerReady)
        tas_arm_poll(self);
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
