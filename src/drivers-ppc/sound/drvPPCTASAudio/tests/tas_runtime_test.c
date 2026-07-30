#define _CRT_SECURE_NO_WARNINGS 1

#include "tas_fixtures.h"
#include "TASRuntime.h"
#include "TASTime.h"

#include <stdio.h>
#include <string.h>
#include <limits.h>

static int failures;
static TASMachineConfig tumbler_config(void);
#define CHECK(expression) do { if (!(expression)) { \
    fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, \
        #expression); ++failures; } } while (0)

static int source_file_contains(const char *path, const char *text)
{
    FILE *file;
    static char source[65536];
    size_t count;
    file = fopen(path, "rb");
    if (file == 0)
        return 0;
    count = fread(source, 1, sizeof(source) - 1U, file);
    fclose(file);
    source[count] = 0;
    return strstr(source, text) != 0;
}

static int driver_source_contains(const char *text)
{
    return source_file_contains(
        "../PPCTASAudio.drvproj/PPCTASAudio.lksproj/PPCTASAudio.m", text);
}

static unsigned long driver_source_count(const char *text)
{
    FILE *file;
    static char source[65536];
    char *cursor;
    size_t count;
    unsigned long matches;
    file = fopen(
        "../PPCTASAudio.drvproj/PPCTASAudio.lksproj/PPCTASAudio.m", "rb");
    if (file == 0)
        return 0UL;
    count = fread(source, 1, sizeof(source) - 1U, file);
    fclose(file);
    source[count] = 0;
    matches = 0UL;
    cursor = source;
    while ((cursor = strstr(cursor, text)) != 0) {
        ++matches;
        cursor += strlen(text);
    }
    return matches;
}

typedef struct {
    long events[128];
    unsigned long eventCount;
    unsigned long failAcquire;
    unsigned long failHardware;
    unsigned long hardwareCalls;
    unsigned long failMuteCount;
    unsigned long signalCount;
    unsigned long serviceCount[2];
    unsigned long failServiceMask;
    TASAudioActionOperation actionOps[64];
    unsigned long actionCount;
    unsigned long trace[128];
    unsigned long traceCount;
    unsigned long ackFailMask;
    unsigned long ackOutsideInterrupt;
    unsigned long nowValue;
    unsigned long detectValues[8];
    unsigned long detectCount;
    unsigned long detectIndex;
    TASRuntime *runtime;
    TASAudioActionOperation injectOperation;
    TASAudioActionOperation failOperation;
    int injected;
    unsigned long safeMuteFailCall;
    unsigned long safeMuteCalls;
    unsigned long prepareCount;
    unsigned long failPrepare;
    unsigned long stopCount[2];
    unsigned long failStopMask;
    TASStatus detectStatus;
    TASStatus failMuteStatus;
    unsigned long operationDepth;
    unsigned long stateDepth;
    unsigned long interruptDepth;
    unsigned long lockViolations;
    int mutateRouteBeforeOperation;
    const void *lastBuffer;
    unsigned long lastRate;
    unsigned long lastStopDeadline;
    int deferSchedule;
} RuntimeMock;

static void runtime_hardware_boundary(RuntimeMock *mock)
{
    if (mock->stateDepth != 0UL || mock->operationDepth != 1UL)
        ++mock->lockViolations;
}

static TASStatus runtime_safe_mute_gpio(void *context,
    const TASGPIODescriptor *gpio, int active)
{
    RuntimeMock *mock;
    (void)gpio;
    (void)active;
    mock = (RuntimeMock *)context;
    runtime_hardware_boundary(mock);
    ++mock->safeMuteCalls;
    return mock->safeMuteCalls == mock->safeMuteFailCall ?
        kTASStatusTimeout : kTASStatusOK;
}

static TASStatus runtime_acquire(void *context, TASRuntimeStage stage,
    const TASMachineConfig *config)
{
    RuntimeMock *mock;
    (void)config;
    mock = (RuntimeMock *)context;
    runtime_hardware_boundary(mock);
    mock->events[mock->eventCount++] = (long)stage + 1L;
    if (stage == kTASRuntimeSafeOutputs && mock->safeMuteFailCall != 0UL)
        return TASRuntimeFailMuteOutputs(config, mock,
            runtime_safe_mute_gpio);
    return mock->failAcquire == (unsigned long)stage + 1UL ?
        kTASStatusTimeout : kTASStatusOK;
}

static void runtime_release(void *context, TASRuntimeStage stage)
{
    RuntimeMock *mock;
    mock = (RuntimeMock *)context;
    runtime_hardware_boundary(mock);
    mock->events[mock->eventCount++] = -((long)stage + 1L);
}

static TASStatus runtime_prepare(void *context, TASStreamDirection direction,
    const void *buffer, unsigned long bytes, unsigned long period,
    PPCDBDMARing *ring)
{
    RuntimeMock *mock;
    (void)direction;
    (void)bytes;
    (void)period;
    mock = (RuntimeMock *)context;
    runtime_hardware_boundary(mock);
    ++mock->prepareCount;
    mock->lastBuffer = buffer;
    if (mock->failPrepare != 0UL)
        return kTASStatusTimeout;
    ring->state = kPPCDBDMAReady;
    return kTASStatusOK;
}

static TASStatus runtime_start(void *context, TASStreamDirection direction,
    PPCDBDMARing *ring, unsigned long deadline)
{
    RuntimeMock *mock;
    (void)direction;
    (void)deadline;
    mock = (RuntimeMock *)context;
    runtime_hardware_boundary(mock);
    ++mock->hardwareCalls;
    if (mock->failHardware == mock->hardwareCalls)
        return kTASStatusTimeout;
    ring->state = kPPCDBDMARunning;
    return kTASStatusOK;
}

static TASStatus runtime_stop(void *context, TASStreamDirection direction,
    PPCDBDMARing *ring, unsigned long deadline)
{
    RuntimeMock *mock;
    (void)direction;
    mock = (RuntimeMock *)context;
    runtime_hardware_boundary(mock);
    ++mock->hardwareCalls;
    ++mock->stopCount[(unsigned long)direction];
    mock->lastStopDeadline = deadline;
    mock->events[mock->eventCount++] = -100L - (long)direction;
    if ((mock->failStopMask &
        (1UL << (unsigned long)direction)) != 0UL) {
        ring->state = kPPCDBDMAFaulted;
        return kTASStatusTimeout;
    }
    ring->state = kPPCDBDMAReady;
    return kTASStatusOK;
}

static TASStatus runtime_service(void *context, TASStreamDirection direction,
    PPCDBDMARing *ring, unsigned long *completed)
{
    RuntimeMock *mock;
    (void)ring;
    mock = (RuntimeMock *)context;
    runtime_hardware_boundary(mock);
    mock->trace[mock->traceCount++] = 400UL + (unsigned long)direction;
    ++mock->serviceCount[(unsigned long)direction];
    *completed = 1UL;
    if ((mock->failServiceMask & (1UL << (unsigned long)direction)) != 0UL)
        return kTASStatusUnresolved;
    return kTASStatusOK;
}

static TASStatus runtime_ack(void *context, TASStreamDirection direction)
{
    RuntimeMock *mock;
    mock = (RuntimeMock *)context;
    if (mock->interruptDepth == 0UL)
        ++mock->ackOutsideInterrupt;
    mock->trace[mock->traceCount++] = 100UL + (unsigned long)direction;
    return (mock->ackFailMask & (1UL << (unsigned long)direction)) != 0UL ?
        kTASStatusUnresolved : kTASStatusOK;
}

static TASStatus runtime_ack_detect(void *context)
{
    RuntimeMock *mock;
    mock = (RuntimeMock *)context;
    if (mock->interruptDepth == 0UL)
        ++mock->ackOutsideInterrupt;
    mock->trace[mock->traceCount++] = 150UL;
    return kTASStatusOK;
}

static TASStatus runtime_action(void *context, const TASAudioAction *action)
{
    RuntimeMock *mock;
    mock = (RuntimeMock *)context;
    runtime_hardware_boundary(mock);
    if (mock->actionCount < 64UL)
        mock->actionOps[mock->actionCount++] = action->operation;
    ++mock->hardwareCalls;
    if (action->operation == kTASAudioScheduleDebounce &&
        !mock->deferSchedule && TASTimeBefore(mock->nowValue, action->deadline))
        mock->nowValue = action->deadline;
    if (!mock->injected && mock->runtime != 0 &&
        action->operation == mock->injectOperation) {
        mock->injected = 1;
        TASRuntimeRecordISR(mock->runtime, kTASRuntimeIRQDetect);
    }
    if (mock->failOperation != kTASAudioBlockStarts &&
        action->operation == mock->failOperation) {
        mock->failOperation = kTASAudioBlockStarts;
        return kTASStatusTimeout;
    }
    return mock->failHardware == mock->hardwareCalls ?
        kTASStatusTimeout : kTASStatusOK;
}

static TASStatus runtime_controls(void *context,
    const TASAudioDesiredControls *controls, unsigned long deadline)
{
    RuntimeMock *mock;
    (void)controls;
    (void)deadline;
    mock = (RuntimeMock *)context;
    runtime_hardware_boundary(mock);
    ++mock->hardwareCalls;
    return mock->failHardware == mock->hardwareCalls ?
        kTASStatusTimeout : kTASStatusOK;
}

static TASStatus runtime_detects(void *context, unsigned long *detects)
{
    RuntimeMock *mock;
    mock = (RuntimeMock *)context;
    runtime_hardware_boundary(mock);
    mock->trace[mock->traceCount++] = 200UL;
    if (mock->detectStatus != kTASStatusOK)
        return mock->detectStatus;
    if (mock->detectIndex < mock->detectCount)
        *detects = mock->detectValues[mock->detectIndex++];
    else
        *detects = 1UL;
    return kTASStatusOK;
}

static unsigned long runtime_now(void *context)
{
    RuntimeMock *mock;
    mock = (RuntimeMock *)context;
    return mock->nowValue == 0UL ? 1000UL : mock->nowValue;
}

static void runtime_signal(void *context)
{
    RuntimeMock *mock;
    mock = (RuntimeMock *)context;
    ++mock->signalCount;
    mock->trace[mock->traceCount++] = 300UL;
}

static void runtime_lock_interrupt(void *context)
{
    RuntimeMock *mock;
    mock = (RuntimeMock *)context;
    if (mock->interruptDepth != 0UL)
        ++mock->lockViolations;
    ++mock->interruptDepth;
}

static void runtime_unlock_interrupt(void *context)
{
    RuntimeMock *mock;
    mock = (RuntimeMock *)context;
    if (mock->interruptDepth != 1UL)
        ++mock->lockViolations;
    --mock->interruptDepth;
}

static void runtime_lock_operation(void *context)
{
    RuntimeMock *mock;
    mock = (RuntimeMock *)context;
    if (mock->operationDepth != 0UL)
        ++mock->lockViolations;
    if (mock->mutateRouteBeforeOperation && mock->runtime != 0) {
        mock->runtime->audio.currentRoutes = kTASAudioRouteHeadphone;
        mock->runtime->audio.desiredDetects = kTASAudioRouteHeadphone;
        mock->mutateRouteBeforeOperation = 0;
    }
    ++mock->operationDepth;
}

static void runtime_unlock_operation(void *context)
{
    RuntimeMock *mock;
    mock = (RuntimeMock *)context;
    if (mock->operationDepth != 1UL || mock->stateDepth != 0UL)
        ++mock->lockViolations;
    --mock->operationDepth;
}

static void runtime_lock_state(void *context)
{
    RuntimeMock *mock;
    mock = (RuntimeMock *)context;
    if (mock->operationDepth != 1UL || mock->stateDepth != 0UL)
        ++mock->lockViolations;
    ++mock->stateDepth;
}

static void runtime_unlock_state(void *context)
{
    RuntimeMock *mock;
    mock = (RuntimeMock *)context;
    if (mock->stateDepth != 1UL)
        ++mock->lockViolations;
    --mock->stateDepth;
}

static void runtime_fail_mute(void *context)
{
    ++((RuntimeMock *)context)->failMuteCount;
}

static TASStatus runtime_fail_mute_outputs(void *context)
{
    RuntimeMock *mock;
    mock = (RuntimeMock *)context;
    runtime_hardware_boundary(mock);
    ++mock->failMuteCount;
    return mock->failMuteStatus;
}

static TASStatus runtime_codec_write(void *context, unsigned char reg,
    const unsigned char *bytes, unsigned long length, unsigned long deadline,
    unsigned long *written)
{
    (void)context;
    (void)reg;
    (void)bytes;
    (void)deadline;
    *written = length;
    return kTASStatusOK;
}

static TASStatus runtime_codec_reset(void *context, int asserted)
{
    (void)context;
    (void)asserted;
    return kTASStatusOK;
}

static TASStatus runtime_codec_delay(void *context, unsigned long usec,
    unsigned long deadline)
{
    (void)context;
    (void)usec;
    (void)deadline;
    return kTASStatusOK;
}

static TASRuntimeOps runtime_ops(RuntimeMock *mock)
{
    TASRuntimeOps ops;
    memset(&ops, 0, sizeof(ops));
    ops.context = mock;
    ops.codecCallbacks.context = mock;
    ops.codecCallbacks.writeRegister = runtime_codec_write;
    ops.codecCallbacks.setReset = runtime_codec_reset;
    ops.codecCallbacks.delayMicroseconds = runtime_codec_delay;
    ops.codecCallbacks.failMute = runtime_fail_mute;
    ops.acquire = runtime_acquire;
    ops.release = runtime_release;
    ops.prepareDMA = runtime_prepare;
    ops.startDMA = runtime_start;
    ops.stopResetDMA = runtime_stop;
    ops.serviceDMA = runtime_service;
    ops.ackDMAInterrupt = runtime_ack;
    ops.ackDetectInterrupt = runtime_ack_detect;
    ops.lockInterrupt = runtime_lock_interrupt;
    ops.unlockInterrupt = runtime_unlock_interrupt;
    ops.lockOperation = runtime_lock_operation;
    ops.unlockOperation = runtime_unlock_operation;
    ops.lockState = runtime_lock_state;
    ops.unlockState = runtime_unlock_state;
    ops.executeAction = runtime_action;
    ops.applyControls = runtime_controls;
    ops.sampleDetects = runtime_detects;
    ops.now = runtime_now;
    ops.signalDeferred = runtime_signal;
    ops.failMuteOutputs = runtime_fail_mute_outputs;
    return ops;
}

static void test_raw_isr_only_acks_and_latches(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    memset(&mock, 0, sizeof(mock));
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    config = tumbler_config();
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeRecordDMAISR(&runtime, kTASStreamOutput) == kTASStatusOK);
    CHECK(mock.traceCount == 1UL && mock.trace[0] == 100UL);
    CHECK(runtime.pendingIRQs == kTASRuntimeIRQOutput);
    CHECK(mock.serviceCount[0] == 0UL && mock.detectIndex == 0UL &&
        mock.hardwareCalls == 0UL);
    mock.ackFailMask = kTASStreamMaskInput;
    CHECK(TASRuntimeRecordDMAISR(&runtime, kTASStreamInput) ==
        kTASStatusUnresolved);
    CHECK((runtime.pendingIRQs & kTASRuntimeIRQInput) != 0UL &&
        runtime.dmaFaultMask == kTASStreamMaskInput);
    mock.traceCount = 0UL;
    CHECK(TASRuntimeRecordDetectISR(&runtime) == kTASStatusOK);
    CHECK(mock.traceCount == 1UL && mock.trace[0] == 150UL &&
        (runtime.pendingIRQs & kTASRuntimeIRQDetect) != 0UL);
}

static void test_initial_detect_advances_without_another_edge(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    int notifyInput;
    int notifyOutput;
    memset(&mock, 0, sizeof(mock));
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    mock.nowValue = 1000UL;
    mock.detectValues[0] = 1UL;
    mock.detectValues[1] = 1UL;
    mock.detectCount = 2UL;
    config = tumbler_config();
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 1200UL) == kTASStatusOK);
    (void)notifyInput;
    (void)notifyOutput;
    CHECK(!runtime.audio.debouncePending && mock.detectIndex == 2UL &&
        runtime.audio.desiredDetects == 1UL && runtime.audio.routeValid);
}

static void test_reset_leaves_async_debounce_to_worker(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    int notifyInput;
    int notifyOutput;
    memset(&mock, 0, sizeof(mock));
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    mock.nowValue = 1000UL;
    mock.detectValues[0] = 1UL;
    mock.detectValues[1] = 1UL;
    mock.detectCount = 2UL;
    mock.deferSchedule = 1;
    config = tumbler_config();
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 1200UL) == kTASStatusOK);
    CHECK(runtime.audio.debouncePending && !runtime.audio.routeValid &&
        mock.detectIndex == 0UL && mock.signalCount == 0UL);
    mock.nowValue = runtime.audio.debounceDeadline;
    CHECK(TASRuntimeServiceDeferred(&runtime, 1200UL, &notifyInput,
        &notifyOutput) == kTASStatusOK);
    CHECK(runtime.audio.debouncePending && mock.detectIndex == 1UL);
    mock.nowValue = runtime.audio.debounceDeadline;
    CHECK(TASRuntimeServiceDeferred(&runtime, 1200UL, &notifyInput,
        &notifyOutput) == kTASStatusOK);
    CHECK(!runtime.audio.debouncePending && runtime.audio.routeValid &&
        mock.detectIndex == 2UL && mock.signalCount == 0UL);
}

static void test_bounce_and_wake_continue_without_external_edges(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    int notifyInput;
    int notifyOutput;
    unsigned long index;
    memset(&mock, 0, sizeof(mock));
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    mock.nowValue = 1000UL;
    mock.detectValues[0] = 1UL;
    mock.detectValues[1] = 1UL;
    mock.detectValues[2] = 0UL;
    mock.detectValues[3] = 1UL;
    mock.detectValues[4] = 1UL;
    mock.detectValues[5] = 1UL;
    mock.detectValues[6] = 1UL;
    mock.detectCount = 7UL;
    config = tumbler_config();
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 2000UL) == kTASStatusOK);
    TASRuntimeRecordISR(&runtime, kTASRuntimeIRQDetect);
    for (index = 0UL; index < 4UL; ++index) {
        if (index != 0UL)
            mock.nowValue = runtime.audio.debounceDeadline;
        CHECK(TASRuntimeServiceDeferred(&runtime, 2000UL, &notifyInput,
            &notifyOutput) == kTASStatusOK);
    }
    CHECK(runtime.audio.routeValid && !runtime.audio.debouncePending &&
        mock.detectIndex == 5UL);
    runtime.dmaFaultMask = kTASStreamMaskOutput;
    CHECK(TASRuntimeSetPower(&runtime, kTASPowerOff, 3000UL) ==
        kTASStatusOK);
    CHECK(TASRuntimeSetPower(&runtime, kTASPowerReady, 4000UL) ==
        kTASStatusOK);
    CHECK(runtime.audio.powerState == kTASPowerWaking &&
        runtime.audio.debouncePending);
    for (index = 0UL; index < 3UL; ++index) {
        if (index != 0UL)
            mock.nowValue = runtime.audio.debounceDeadline;
        CHECK(TASRuntimeServiceDeferred(&runtime, 4000UL, &notifyInput,
            &notifyOutput) == kTASStatusOK);
    }
    CHECK(runtime.audio.powerState == kTASPowerReady &&
        !runtime.audio.startsBlocked && runtime.audio.routeValid &&
        mock.detectIndex == 7UL && runtime.dmaFaultMask == 0UL);
}

static void test_edge_during_route_rolls_back_safely(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    int notifyInput;
    int notifyOutput;
    memset(&mock, 0, sizeof(mock));
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    mock.nowValue = 1000UL;
    mock.detectValues[0] = 0UL;
    mock.detectValues[1] = 0UL;
    mock.detectValues[2] = 1UL;
    mock.detectValues[3] = 1UL;
    mock.detectCount = 4UL;
    config = tumbler_config();
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    mock.runtime = &runtime;
    CHECK(TASRuntimeReset(&runtime, 2000UL) == kTASStatusOK);
    mock.injectOperation = kTASAudioUnmuteHeadphone;
    TASRuntimeRecordISR(&runtime, kTASRuntimeIRQDetect);
    CHECK(TASRuntimeServiceDeferred(&runtime, 2000UL, &notifyInput,
        &notifyOutput) == kTASStatusOK);
    mock.nowValue = runtime.audio.debounceDeadline;
    CHECK(TASRuntimeServiceDeferred(&runtime, 2000UL, &notifyInput,
        &notifyOutput) == kTASStatusOK);
    mock.nowValue = runtime.audio.debounceDeadline;
    CHECK(TASRuntimeServiceDeferred(&runtime, 2000UL, &notifyInput,
        &notifyOutput) == kTASStatusConflict);
    CHECK(mock.injected && runtime.audio.debouncePending);
    CHECK(runtime.audio.powerState == kTASPowerFault &&
        runtime.audio.outputsMuted && !runtime.audio.transitionPending);
}

static void test_route_action_failure_rolls_back_muted(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    int notifyInput;
    int notifyOutput;
    memset(&mock, 0, sizeof(mock));
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    mock.nowValue = 1000UL;
    mock.detectValues[0] = 0UL;
    mock.detectValues[1] = 0UL;
    mock.detectValues[2] = 1UL;
    mock.detectValues[3] = 1UL;
    mock.detectCount = 4UL;
    config = tumbler_config();
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 2000UL) == kTASStatusOK);
    TASRuntimeRecordISR(&runtime, kTASRuntimeIRQDetect);
    CHECK(TASRuntimeServiceDeferred(&runtime, 2000UL, &notifyInput,
        &notifyOutput) == kTASStatusOK);
    mock.nowValue = runtime.audio.debounceDeadline;
    CHECK(TASRuntimeServiceDeferred(&runtime, 2000UL, &notifyInput,
        &notifyOutput) == kTASStatusOK);
    mock.failOperation = kTASAudioUnmuteHeadphone;
    mock.nowValue = runtime.audio.debounceDeadline;
    CHECK(TASRuntimeServiceDeferred(&runtime, 2000UL, &notifyInput,
        &notifyOutput) == kTASStatusTimeout);
    CHECK(mock.failMuteCount != 0UL && runtime.audio.outputsMuted &&
        !runtime.audio.transitionPending);
}

static TASMachineConfig tumbler_config(void)
{
    TASFixture fixture;
    TASPropertyReader reader;
    TASMachineConfig config;
    TASFixtureTumbler(&fixture);
    reader = TASFixtureReader(&fixture);
    memset(&config, 0, sizeof(config));
    CHECK(TASRuntimeProbe(&reader, &config) == kTASStatusOK);
    return config;
}

static void test_delivered_resource_validation(void)
{
    TASMachineConfig config;
    TASDeliveredRange ranges[3];
    unsigned int interrupts[3];
    config = tumbler_config();
    ranges[0].start = config.i2s.address;
    ranges[0].size = config.i2s.length;
    ranges[1].start = config.outputDBDMA.address;
    ranges[1].size = config.outputDBDMA.length;
    ranges[2].start = config.inputDBDMA.address;
    ranges[2].size = config.inputDBDMA.length;
    interrupts[0] = 41U;
    interrupts[1] = 42U;
    interrupts[2] = 43U;
    CHECK(TASRuntimeValidateResources(&config, 3UL, ranges, 3UL,
        interrupts) == kTASStatusOK);
    CHECK(TASRuntimeValidateResources(&config, 2UL, ranges, 3UL,
        interrupts) == kTASStatusMalformed);
    CHECK(TASRuntimeValidateResources(&config, 3UL, ranges, 2UL,
        interrupts) == kTASStatusMalformed);
    ranges[1].size += 1UL;
    CHECK(TASRuntimeValidateResources(&config, 3UL, ranges, 3UL,
        interrupts) == kTASStatusConflict);
    ranges[1].size = config.outputDBDMA.length;
    interrupts[2] = interrupts[0];
    CHECK(TASRuntimeValidateResources(&config, 3UL, ranges, 3UL,
        interrupts) == kTASStatusConflict);
    interrupts[2] = 43U;
    interrupts[0] = 0U;
    CHECK(TASRuntimeValidateResources(&config, 3UL, ranges, 3UL,
        interrupts) == kTASStatusConflict);
#if ULONG_MAX > UINT_MAX
    interrupts[0] = 41U;
    ranges[0].start = (unsigned long)UINT_MAX + 1UL;
    CHECK(TASRuntimeValidateResources(&config, 3UL, ranges, 3UL,
        interrupts) == kTASStatusOverflow);
#endif
}

static void test_probe_is_narrow(void)
{
    TASFixture fixture;
    TASPropertyReader reader;
    TASMachineConfig config;
    TASFixtureSnapper(&fixture);
    reader = TASFixtureReader(&fixture);
    CHECK(TASRuntimeProbe(&reader, &config) == kTASStatusOK);
    CHECK(config.codecKind == kTASCodecTAS3004);
    TASFixtureSetString(&fixture, kFixtureCodec, "compatible", "awacs");
    reader = TASFixtureReader(&fixture);
    CHECK(TASRuntimeProbe(&reader, &config) != kTASStatusOK);
    TASFixtureTumbler(&fixture);
    TASFixtureAddSecondI2S(&fixture);
    reader = TASFixtureReader(&fixture);
    CHECK(TASRuntimeProbe(&reader, &config) == kTASStatusAmbiguous);
    reader.candidateNode = kFixtureI2S;
    CHECK(TASRuntimeProbe(&reader, &config) == kTASStatusOK);
    reader.candidateNode = 20UL;
    TASFixtureSetString(&fixture, 22UL, "compatible", "burgundy");
    CHECK(TASRuntimeProbe(&reader, &config) == kTASStatusNotMatched);
}

typedef struct {
    unsigned long now;
    unsigned long waited;
} DelayMock;

static unsigned long delay_now(void *context)
{
    return ((DelayMock *)context)->now;
}

static void delay_wait(void *context, unsigned long usec)
{
    DelayMock *mock;
    mock = (DelayMock *)context;
    mock->waited += usec;
    mock->now += (usec + 999UL) / 1000UL;
}

static void delay_wait_overshoot(void *context, unsigned long usec)
{
    delay_wait(context, usec);
    ++((DelayMock *)context)->now;
}

static void test_codec_delay_is_deadline_bounded(void)
{
    DelayMock mock;
    memset(&mock, 0, sizeof(mock));
    mock.now = 100UL;
    CHECK(TASRuntimeBoundedDelay(&mock, 5000UL, 105UL, delay_now,
        delay_wait) == kTASStatusOK && mock.waited == 5000UL);
    mock.waited = 0UL;
    CHECK(TASRuntimeBoundedDelay(&mock, 1UL, 105UL, delay_now,
        delay_wait) == kTASStatusTimeout && mock.waited == 0UL);
    mock.now = 100UL;
    CHECK(TASRuntimeBoundedDelay(&mock, 5001UL, 105UL, delay_now,
        delay_wait) == kTASStatusTimeout && mock.waited == 0UL);
    mock.now = 100UL;
    CHECK(TASRuntimeBoundedDelay(&mock, 5000UL, 105UL, delay_now,
        delay_wait_overshoot) == kTASStatusTimeout);
}

static void test_control_conversion_endpoints_and_monotonicity(void)
{
    unsigned long previous;
    unsigned long value;
    int attenuation;
    CHECK(TASRuntimeAttenuationToCodec(0, &value) == kTASStatusOK &&
        value == 0x010000UL);
    CHECK(TASRuntimeAttenuationToCodec(-84, &value) == kTASStatusOK &&
        value == 0UL);
    CHECK(TASRuntimeAttenuationToCodec(1, &value) == kTASStatusOK &&
        value == 0x010000UL);
    CHECK(TASRuntimeAttenuationToCodec(-85, &value) == kTASStatusOK &&
        value == 0UL);
    previous = 0UL;
    for (attenuation = -84; attenuation <= 0; ++attenuation) {
        CHECK(TASRuntimeAttenuationToCodec(attenuation, &value) ==
            kTASStatusOK);
        CHECK(value >= previous);
        previous = value;
    }
    CHECK(TASRuntimeGainToCodec(0, &value) == kTASStatusOK &&
        value == 0x010000UL);
    CHECK(TASRuntimeGainToCodec(32768, &value) == kTASStatusOK &&
        value == 0x020000UL);
    CHECK(TASRuntimeGainToCodec(32769, &value) == kTASStatusOK &&
        value == 0x020000UL);
    CHECK(TASRuntimeGainToCodec(-1, &value) == kTASStatusOK &&
        value == 0x010000UL);
}

static void test_deadline_delay_is_wrap_safe(void)
{
    DelayMock mock;
    memset(&mock, 0, sizeof(mock));
    mock.now = 0xfffffffeUL;
    CHECK(TASRuntimeBoundedDelay(&mock, 2000UL, 0UL, delay_now,
        delay_wait) == kTASStatusOK);
    CHECK((mock.now & 0xffffffffUL) == 0UL);
}

typedef struct {
    unsigned long calls;
    unsigned long failCall;
} MuteMock;

typedef struct {
    unsigned long offsets[4];
    int active[4];
    unsigned long calls;
    unsigned long failCall;
} GPIOTrace;

static TASStatus trace_gpio(void *context, const TASGPIODescriptor *gpio,
    int active)
{
    GPIOTrace *trace;
    trace = (GPIOTrace *)context;
    trace->offsets[trace->calls] = gpio->offset;
    trace->active[trace->calls] = active;
    ++trace->calls;
    return trace->calls == trace->failCall ? kTASStatusTimeout :
        kTASStatusOK;
}

static TASStatus mute_gpio(void *context, const TASGPIODescriptor *gpio,
    int active)
{
    MuteMock *mock;
    (void)gpio;
    CHECK(active);
    mock = (MuteMock *)context;
    ++mock->calls;
    return mock->calls == mock->failCall ? kTASStatusTimeout : kTASStatusOK;
}

static void test_fail_mute_attempts_every_present_output(void)
{
    TASFixture fixture;
    TASPropertyReader reader;
    TASMachineConfig config;
    MuteMock mock;
    TASFixtureSnapper(&fixture);
    reader = TASFixtureReader(&fixture);
    CHECK(TASRuntimeProbe(&reader, &config) == kTASStatusOK);
    config.routes[kTASRouteLineOut].present = 1;
    config.routes[kTASRouteLineOut].mute =
        config.routes[kTASRouteHeadphone].mute;
    config.quirks |= kTASQuirkANDedReset;
    for (mock.failCall = 1UL; mock.failCall <= 3UL; ++mock.failCall) {
        mock.calls = 0UL;
        CHECK(TASRuntimeFailMuteOutputs(&config, &mock, mute_gpio) ==
            kTASStatusTimeout);
        CHECK(mock.calls == 3UL);
    }
}

static void test_safe_output_stage_failure_attempts_every_output(void)
{
    TASFixture fixture;
    TASPropertyReader reader;
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    unsigned long fail;
    TASFixtureSnapper(&fixture);
    reader = TASFixtureReader(&fixture);
    CHECK(TASRuntimeProbe(&reader, &config) == kTASStatusOK);
    config.routes[kTASRouteLineOut].present = 1;
    config.routes[kTASRouteLineOut].mute =
        config.routes[kTASRouteHeadphone].mute;
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    for (fail = 1UL; fail <= 3UL; ++fail) {
        memset(&mock, 0, sizeof(mock));
        mock.safeMuteFailCall = fail;
        ops = runtime_ops(&mock);
        CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) ==
            kTASStatusOK);
        CHECK(TASRuntimeReset(&runtime, 2000UL) == kTASStatusTimeout);
        CHECK(mock.safeMuteCalls == 3UL && runtime.acquiredMask == 0UL);
    }
}

static void test_anded_reset_uses_mute_constituents(void)
{
    TASMachineConfig config;
    GPIOTrace trace;
    config = tumbler_config();
    config.quirks |= kTASQuirkANDedReset;
    memset(&config.hardwareReset, 0, sizeof(config.hardwareReset));
    memset(&trace, 0, sizeof(trace));
    trace.failCall = 1UL;
    CHECK(TASRuntimeApplyANDedReset(&config, 1, &trace, trace_gpio) ==
        kTASStatusTimeout);
    CHECK(trace.calls == 2UL && trace.active[0] && trace.active[1] &&
        trace.offsets[0] == config.amplifierMute.offset &&
        trace.offsets[1] == config.routes[kTASRouteHeadphone].mute.offset);
    memset(&trace, 0, sizeof(trace));
    CHECK(TASRuntimeApplyANDedReset(&config, 0, &trace, trace_gpio) ==
        kTASStatusOK);
    CHECK(trace.calls == 2UL && !trace.active[0] && !trace.active[1] &&
        trace.offsets[0] == config.routes[kTASRouteHeadphone].mute.offset &&
        trace.offsets[1] == config.amplifierMute.offset);
}

static void test_runtime_binds_both_reviewed_codecs(void)
{
    TASFixture fixture;
    TASPropertyReader reader;
    TASMachineConfig config;
    TASAudioDesiredControls desired;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    memset(&mock, 0, sizeof(mock));
    ops = runtime_ops(&mock);
    TASFixtureTumbler(&fixture);
    reader = TASFixtureReader(&fixture);
    CHECK(TASRuntimeProbe(&reader, &config) == kTASStatusOK);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(runtime.codec.ops == TAS3001CCodecOps());
    TASFixtureSnapper(&fixture);
    reader = TASFixtureReader(&fixture);
    CHECK(TASRuntimeProbe(&reader, &config) == kTASStatusOK);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(runtime.codec.ops == TAS3004CodecOps());
}

static void test_acquisition_unwinds_every_stage(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    unsigned long fail;
    unsigned long index;
    unsigned long scan;
    int found;
    config = tumbler_config();
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    for (fail = 1UL; fail <= (unsigned long)kTASRuntimeStageCount; ++fail) {
        memset(&mock, 0, sizeof(mock));
        mock.failAcquire = fail;
        ops = runtime_ops(&mock);
        CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) ==
            kTASStatusOK);
        CHECK(TASRuntimeReset(&runtime, 100UL) == kTASStatusTimeout);
        CHECK(runtime.acquiredMask == 0UL);
        for (index = 0UL; index + 1UL < fail; ++index) {
            found = 0;
            for (scan = fail; scan < mock.eventCount; ++scan)
                if (mock.events[scan] == -((long)index + 1L))
                    found = 1;
            CHECK(found);
        }
        CHECK(mock.failMuteCount ==
            (fail > (unsigned long)kTASRuntimeSafeOutputs + 1UL ? 1UL : 0UL));
    }
}

static void test_initial_route_failure_unwinds_muted(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    memset(&mock, 0, sizeof(mock));
    mock.nowValue = 1000UL;
    mock.failOperation = kTASAudioUnmuteHeadphone;
    config = tumbler_config();
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 2000UL) == kTASStatusTimeout);
    CHECK(runtime.acquiredMask == 0UL && mock.failMuteCount != 0UL);
    CHECK(mock.eventCount == (unsigned long)kTASRuntimeStageCount * 2UL);
    CHECK(mock.events[mock.eventCount - 1UL] == -1L);
}

static void test_controls_conflict_has_no_codec_io(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    TASAudioActionPlan plan;
    TASAudioToken token;
    unsigned long before;
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    memset(&mock, 0, sizeof(mock));
    config = tumbler_config();
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASAudioPrepareRoute(&runtime.audio, kTASAudioRouteSpeaker,
        &plan, &token) == kTASStatusOK);
    before = mock.hardwareCalls;
    desired.leftVolume = 99UL;
    CHECK(TASRuntimeSetControls(&runtime, &desired, 2000UL) ==
        kTASStatusConflict);
    CHECK(mock.hardwareCalls == before &&
        runtime.audio.desired.leftVolume == 0UL);
    CHECK(TASAudioCancelTransition(&runtime.audio, &token) == kTASStatusOK);
}

static void test_route_uses_output_op_and_preserves_input_state(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    desired.inputSource = kTASCodecInputAnalog;
    desired.inputGain = 77UL;
    memset(&mock, 0, sizeof(mock));
    mock.nowValue = 1000UL;
    config = tumbler_config();
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 2000UL) == kTASStatusOK);
    CHECK(runtime.audio.desired.inputSource == kTASCodecInputAnalog &&
        runtime.audio.desired.inputGain == 77UL);
}

static void test_full_duplex_controls_isr_and_power(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    unsigned char output[512];
    unsigned char input[512];
    unsigned long before;
    unsigned long signalBefore;
    unsigned long wakeActions;
    unsigned long actionIndex;
    unsigned long enableIndex;
    unsigned long releaseIndex;
    unsigned long applyIndex;
    int notifyInput;
    int notifyOutput;
    config = tumbler_config();
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    desired.leftVolume = 10UL;
    desired.rightVolume = 11UL;
    memset(&mock, 0, sizeof(mock));
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 100UL) == kTASStatusOK);
    CHECK(TASRuntimeStartStream(&runtime, kTASStreamOutput, output,
        sizeof(output), 256UL, 44100UL, 200UL) == kTASStatusOK);
    CHECK(mock.lastBuffer == output);
    CHECK(TASRuntimeStartStream(&runtime, kTASStreamInput, input,
        sizeof(input), 256UL, 44100UL, 200UL) == kTASStatusOK);
    before = mock.prepareCount;
    CHECK(TASRuntimeStartStream(&runtime, kTASStreamInput, input,
        sizeof(input), 256UL, 48000UL, 200UL) == kTASStatusConflict);
    CHECK(mock.prepareCount == before);

    before = mock.hardwareCalls;
    signalBefore = mock.signalCount;
    TASRuntimeRecordISR(&runtime, kTASRuntimeIRQOutput);
    TASRuntimeRecordISR(&runtime, kTASRuntimeIRQInput);
    TASRuntimeRecordISR(&runtime, kTASRuntimeIRQDetect);
    CHECK(mock.hardwareCalls == before && mock.signalCount == signalBefore);
    CHECK(TASRuntimeServiceDeferred(&runtime, 300UL, &notifyInput,
        &notifyOutput) == kTASStatusOK);
    CHECK(notifyInput && notifyOutput && mock.serviceCount[0] == 1UL &&
        mock.serviceCount[1] == 1UL);

    desired.leftVolume = 20UL;
    mock.failHardware = mock.hardwareCalls + 1UL;
    CHECK(TASRuntimeSetControls(&runtime, &desired, 400UL) ==
        kTASStatusTimeout);
    CHECK(runtime.audio.desired.leftVolume == 10UL &&
        mock.failMuteCount == 1UL);
    mock.failHardware = 0UL;
    CHECK(TASRuntimeSetControls(&runtime, &desired, 400UL) == kTASStatusOK);
    CHECK(runtime.audio.desired.leftVolume == 20UL);

    CHECK(TASRuntimeStopStream(&runtime, kTASStreamInput, 500UL) ==
        kTASStatusOK);
    CHECK(runtime.clock.activeMask == kTASStreamMaskOutput);
    CHECK(TASRuntimeStopStream(&runtime, kTASStreamOutput, 500UL) ==
        kTASStatusOK);
    CHECK(runtime.clock.activeMask == 0UL);
    CHECK(TASRuntimeSetPower(&runtime, kTASPowerOff, 600UL) ==
        kTASStatusOK);
    wakeActions = mock.actionCount;
    CHECK(TASRuntimeSetPower(&runtime, kTASPowerReady, 700UL) ==
        kTASStatusOK);
    enableIndex = releaseIndex = applyIndex = mock.actionCount;
    for (actionIndex = wakeActions; actionIndex < mock.actionCount;
        ++actionIndex) {
        if (mock.actionOps[actionIndex] == kTASAudioEnableI2SCellClock)
            enableIndex = actionIndex;
        else if (mock.actionOps[actionIndex] == kTASAudioReleaseReset)
            releaseIndex = actionIndex;
        else if (mock.actionOps[actionIndex] == kTASAudioApplyI2SRate)
            applyIndex = actionIndex;
    }
    CHECK(enableIndex < releaseIndex && releaseIndex < applyIndex);
    CHECK(runtime.audio.startsBlocked && runtime.audio.debouncePending);
    CHECK(mock.lockViolations == 0UL);
}

static void test_i2s_adapter_uses_apple_raw_fields(void)
{
    TASI2SPlanStep step;
    unsigned long serial;
    unsigned long dataWord;
    memset(&step, 0, sizeof(step));
    step.sourceHz = 49152000UL;
    step.mclkDivisor = 4UL;
    step.sclkDivisor = 4UL;
    step.value = 0x02000200UL;
    CHECK(TASRuntimeEncodeI2S(&step, &serial, &dataWord) == kTASStatusOK);
    CHECK(serial == 0x81100000UL && dataWord == 0x02000200UL);
    step.sourceHz = 123UL;
    CHECK(TASRuntimeEncodeI2S(&step, &serial, &dataWord) ==
        kTASStatusUnsupported);
}

static void test_dma_fault_is_isolated_to_one_direction(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    unsigned char output[512];
    unsigned char input[512];
    int notifyInput;
    int notifyOutput;
    config = tumbler_config();
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    memset(&mock, 0, sizeof(mock));
    mock.failServiceMask = kTASStreamMaskOutput;
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 2000UL) == kTASStatusOK);
    CHECK(TASRuntimeStartStream(&runtime, kTASStreamOutput, output,
        sizeof(output), 256UL, 44100UL, 2500UL) == kTASStatusOK);
    CHECK(TASRuntimeStartStream(&runtime, kTASStreamInput, input,
        sizeof(input), 256UL, 44100UL, 2500UL) == kTASStatusOK);
    TASRuntimeRecordISR(&runtime, kTASRuntimeIRQOutput);
    TASRuntimeRecordISR(&runtime, kTASRuntimeIRQInput);
    CHECK(TASRuntimeServiceDeferred(&runtime, 300UL, &notifyInput,
        &notifyOutput) == kTASStatusUnresolved);
    CHECK(mock.serviceCount[0] == 1UL && mock.serviceCount[1] == 1UL);
    CHECK(runtime.dmaFaultMask == kTASStreamMaskOutput);
    CHECK(notifyInput && !notifyOutput);
    CHECK(!runtime.audio.hardwareValid && !runtime.audio.routeValid &&
        runtime.audio.outputsMuted && runtime.audio.outputsMuteKnown);
    CHECK(mock.stopCount[0] == 1UL && mock.stopCount[1] == 0UL);
    CHECK(runtime.clock.activeMask == kTASStreamMaskInput);
    CHECK(TASRuntimeStartStream(&runtime, kTASStreamOutput, output,
        sizeof(output), 256UL, 44100UL, 400UL) == kTASStatusConflict);
    CHECK(TASRuntimeUnwind(&runtime) == kTASStatusOK);
    mock.failServiceMask = 0UL;
    CHECK(TASRuntimeReset(&runtime, 4000UL) == kTASStatusOK);
    CHECK(runtime.dmaFaultMask == 0UL);
    CHECK(TASRuntimeStartStream(&runtime, kTASStreamOutput, output,
        sizeof(output), 256UL, 44100UL, 4500UL) == kTASStatusOK);
}

static void test_start_requires_ready_valid_fully_acquired_state(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    unsigned char output[512];
    unsigned long fullMask;
    unsigned long before;
    config = tumbler_config();
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    memset(&mock, 0, sizeof(mock));
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 2000UL) == kTASStatusOK);
    fullMask = runtime.acquiredMask;
    before = mock.prepareCount;
    runtime.acquiredMask &= ~1UL;
    CHECK(TASRuntimeStartStream(&runtime, kTASStreamOutput, output,
        sizeof(output), 256UL, 44100UL, 3000UL) == kTASStatusConflict);
    runtime.acquiredMask = fullMask;
    runtime.audio.powerState = kTASPowerOff;
    CHECK(TASRuntimeStartStream(&runtime, kTASStreamOutput, output,
        sizeof(output), 256UL, 44100UL, 3000UL) == kTASStatusConflict);
    runtime.audio.powerState = kTASPowerReady;
    runtime.audio.hardwareValid = 0;
    CHECK(TASRuntimeStartStream(&runtime, kTASStreamOutput, output,
        sizeof(output), 256UL, 44100UL, 3000UL) == kTASStatusConflict);
    runtime.audio.hardwareValid = 1;
    runtime.audio.routeValid = 0;
    CHECK(TASRuntimeStartStream(&runtime, kTASStreamOutput, output,
        sizeof(output), 256UL, 44100UL, 3000UL) == kTASStatusConflict);
    runtime.audio.routeValid = 1;
    runtime.audio.startsBlocked = 1;
    CHECK(TASRuntimeStartStream(&runtime, kTASStreamOutput, output,
        sizeof(output), 256UL, 44100UL, 3000UL) == kTASStatusConflict);
    runtime.audio.startsBlocked = 0;
    runtime.dmaFaultMask = kTASStreamMaskOutput;
    CHECK(TASRuntimeStartStream(&runtime, kTASStreamOutput, output,
        sizeof(output), 256UL, 44100UL, 3000UL) == kTASStatusConflict);
    CHECK(mock.prepareCount == before);
}

static void test_stop_after_failed_prepare_is_harmless(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    unsigned char output[512];
    config = tumbler_config();
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    memset(&mock, 0, sizeof(mock));
    mock.failPrepare = 1UL;
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 2000UL) == kTASStatusOK);
    CHECK(TASRuntimeStartStream(&runtime, kTASStreamOutput, output,
        sizeof(output), 256UL, 44100UL, 3000UL) == kTASStatusTimeout);
    CHECK(!runtime.audio.hardwareValid && !runtime.audio.routeValid &&
        runtime.audio.outputsMuted && runtime.audio.outputsMuteKnown);
    CHECK(TASRuntimeStopStream(&runtime, kTASStreamOutput, 3000UL) ==
        kTASStatusOK);
    CHECK(mock.stopCount[0] == 0UL && runtime.clock.activeMask == 0UL);
}

static void test_detect_read_failure_propagates_and_fail_mutes(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    int notifyInput;
    int notifyOutput;
    config = tumbler_config();
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    memset(&mock, 0, sizeof(mock));
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 2000UL) == kTASStatusOK);
    mock.detectStatus = kTASStatusTimeout;
    TASRuntimeRecordISR(&runtime, kTASRuntimeIRQDetect);
    CHECK(TASRuntimeServiceDeferred(&runtime, 3000UL, &notifyInput,
        &notifyOutput) == kTASStatusOK);
    mock.nowValue = runtime.audio.debounceDeadline;
    CHECK(TASRuntimeServiceDeferred(&runtime, 3000UL, &notifyInput,
        &notifyOutput) == kTASStatusTimeout);
    CHECK(mock.failMuteCount != 0UL && runtime.audio.detectBlocked);
}

static void test_failed_controls_invalidate_truth_from_mute_result(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    config = tumbler_config();
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    desired.leftVolume = 10UL;
    memset(&mock, 0, sizeof(mock));
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 2000UL) == kTASStatusOK);
    desired.leftVolume = 20UL;
    mock.failHardware = mock.hardwareCalls + 1UL;
    CHECK(TASRuntimeSetControls(&runtime, &desired, 3000UL) ==
        kTASStatusTimeout);
    CHECK(runtime.audio.desired.leftVolume == 10UL &&
        !runtime.audio.hardwareValid && !runtime.audio.routeValid &&
        runtime.audio.outputsMuted && runtime.audio.outputsMuteKnown);

    memset(&mock, 0, sizeof(mock));
    mock.failMuteStatus = kTASStatusTimeout;
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 2000UL) == kTASStatusOK);
    desired.leftVolume = 30UL;
    mock.failHardware = mock.hardwareCalls + 1UL;
    CHECK(TASRuntimeSetControls(&runtime, &desired, 3000UL) ==
        kTASStatusTimeout);
    CHECK(!runtime.audio.outputsMuted && !runtime.audio.outputsMuteKnown);
}

static void test_unwind_disables_irqs_before_dma_and_clears_latches(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    unsigned char output[512];
    unsigned long before;
    config = tumbler_config();
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    memset(&mock, 0, sizeof(mock));
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 2000UL) == kTASStatusOK);
    CHECK(TASRuntimeStartStream(&runtime, kTASStreamOutput, output,
        sizeof(output), 256UL, 44100UL, 2500UL) == kTASStatusOK);
    runtime.pendingIRQs = 7UL;
    runtime.detectISREdges = 9UL;
    runtime.detectFaultPending = 1;
    runtime.dmaFaultMask = kTASStreamMaskInput;
    runtime.rings[1].state = kPPCDBDMAFaulted;
    before = mock.eventCount;
    CHECK(TASRuntimeUnwind(&runtime) == kTASStatusOK);
    CHECK(mock.events[before] ==
        -((long)kTASRuntimeInstallInputIRQ + 1L));
    CHECK(mock.events[before + 1UL] ==
        -((long)kTASRuntimeInstallOutputIRQ + 1L));
    CHECK(mock.events[before + 2UL] == -100L &&
        mock.events[before + 3UL] == -101L);
    CHECK(mock.stopCount[0] == 1UL && mock.stopCount[1] == 1UL);
    CHECK(runtime.clock.activeMask == 0UL && runtime.acquiredMask == 0UL);
    CHECK(runtime.pendingIRQs == 0UL && runtime.detectISREdges == 0UL &&
        runtime.dmaFaultMask == 0UL && !runtime.detectFaultPending);
}

static void test_unwind_failure_preserves_dma_resources_and_mute_truth(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    unsigned char output[512];
    unsigned long ringBit;
    config = tumbler_config();
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    memset(&mock, 0, sizeof(mock));
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 2000UL) == kTASStatusOK);
    CHECK(TASRuntimeStartStream(&runtime, kTASStreamOutput, output,
        sizeof(output), 256UL, 44100UL, 2500UL) == kTASStatusOK);
    mock.failStopMask = kTASStreamMaskOutput;
    ringBit = 1UL << (unsigned long)kTASRuntimeAllocateOutputRing;
    CHECK(TASRuntimeUnwind(&runtime) == kTASStatusTimeout);
    CHECK((runtime.acquiredMask & ringBit) != 0UL &&
        runtime.clock.activeMask == 0UL);
    CHECK(!runtime.audio.hardwareValid && !runtime.audio.routeValid &&
        runtime.audio.outputsMuted && runtime.audio.outputsMuteKnown);
    CHECK(runtime.pendingIRQs == 0UL && runtime.dmaFaultMask == 0UL);
}

static void test_unwind_deadline_wraps_with_clock(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    unsigned char output[512];
    config = tumbler_config();
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    memset(&mock, 0, sizeof(mock));
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 2000UL) == kTASStatusOK);
    CHECK(TASRuntimeStartStream(&runtime, kTASStreamOutput, output,
        sizeof(output), 256UL, 44100UL, 2500UL) == kTASStatusOK);
    mock.nowValue = ~0UL - 50UL;
    CHECK(TASRuntimeUnwind(&runtime) == kTASStatusOK);
    CHECK(mock.lastStopDeadline == 49UL);
}

static void test_runtime_commands_reject_after_unwind(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    unsigned long hardwareCalls;
    unsigned long signalCount;
    int notifyInput;
    int notifyOutput;
    config = tumbler_config();
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    memset(&mock, 0, sizeof(mock));
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 2000UL) == kTASStatusOK);
    CHECK(TASRuntimeUnwind(&runtime) == kTASStatusOK);
    hardwareCalls = mock.hardwareCalls;
    signalCount = mock.signalCount;
    desired.leftVolume = 123UL;
    CHECK(TASRuntimeSetControls(&runtime, &desired, 3000UL) ==
        kTASStatusConflict);
    CHECK(TASRuntimeSetPower(&runtime, kTASPowerOff, 3000UL) ==
        kTASStatusConflict);
    runtime.pendingIRQs = kTASRuntimeIRQOutput | kTASRuntimeIRQDetect;
    notifyInput = 1;
    notifyOutput = 1;
    CHECK(TASRuntimeServiceDeferred(&runtime, 3000UL, &notifyInput,
        &notifyOutput) == kTASStatusConflict);
    CHECK(!notifyInput && !notifyOutput &&
        runtime.pendingIRQs ==
            (kTASRuntimeIRQOutput | kTASRuntimeIRQDetect));
    CHECK(mock.hardwareCalls == hardwareCalls &&
        mock.signalCount == signalCount);
}

static void test_interrupt_close_drains_and_skips_mmio(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    unsigned long traceCount;
    int interruptClosing;
    config = tumbler_config();
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    memset(&mock, 0, sizeof(mock));
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    interruptClosing = 0;
    runtime_lock_interrupt(&mock);
    if (!interruptClosing)
        CHECK(TASRuntimeRecordDMAISRLocked(&runtime,
            kTASStreamOutput) == kTASStatusOK);
    runtime_unlock_interrupt(&mock);
    CHECK(mock.ackOutsideInterrupt == 0UL &&
        runtime.pendingIRQs == kTASRuntimeIRQOutput);
    runtime_lock_interrupt(&mock);
    if (!interruptClosing)
        CHECK(TASRuntimeRecordDetectISRLocked(&runtime) == kTASStatusOK);
    runtime_unlock_interrupt(&mock);
    CHECK(mock.ackOutsideInterrupt == 0UL &&
        (runtime.pendingIRQs & kTASRuntimeIRQDetect) != 0UL);
    runtime_lock_interrupt(&mock);
    interruptClosing = 1;
    runtime_unlock_interrupt(&mock);
    traceCount = mock.traceCount;
    runtime_lock_interrupt(&mock);
    if (!interruptClosing)
        (void)TASRuntimeRecordDMAISRLocked(&runtime, kTASStreamInput);
    runtime_unlock_interrupt(&mock);
    CHECK(mock.traceCount == traceCount &&
        (runtime.pendingIRQs & kTASRuntimeIRQInput) == 0UL);
}

static void test_begin_close_serializes_against_reset_and_commands(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    unsigned char output[512];
    unsigned long hardwareCalls;
    int notifyInput;
    int notifyOutput;
    config = tumbler_config();
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    memset(&mock, 0, sizeof(mock));
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeBeginClose(&runtime) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 2000UL) == kTASStatusConflict);
    CHECK(mock.eventCount == 0UL);

    memset(&mock, 0, sizeof(mock));
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 2000UL) == kTASStatusOK);
    CHECK(TASRuntimeStartStream(&runtime, kTASStreamOutput, output,
        sizeof(output), 256UL, 44100UL, 2500UL) == kTASStatusOK);
    CHECK(TASRuntimeBeginClose(&runtime) == kTASStatusOK);
    hardwareCalls = mock.hardwareCalls;
    CHECK(TASRuntimeStartStream(&runtime, kTASStreamInput, output,
        sizeof(output), 256UL, 44100UL, 3000UL) == kTASStatusConflict);
    CHECK(TASRuntimeStopStream(&runtime, kTASStreamOutput, 3000UL) ==
        kTASStatusConflict);
    CHECK(TASRuntimeSetControls(&runtime, &desired, 3000UL) ==
        kTASStatusConflict);
    CHECK(TASRuntimeSetPower(&runtime, kTASPowerOff, 3000UL) ==
        kTASStatusConflict);
    notifyInput = 1;
    notifyOutput = 1;
    CHECK(TASRuntimeServiceDeferred(&runtime, 3000UL, &notifyInput,
        &notifyOutput) == kTASStatusConflict);
    CHECK(!notifyInput && !notifyOutput &&
        mock.hardwareCalls == hardwareCalls);
    CHECK(TASRuntimeUnwind(&runtime) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 4000UL) == kTASStatusConflict);
}

static void test_controls_preserve_prior_serialized_route_commit(void)
{
    TASMachineConfig config;
    TASRuntime runtime;
    TASRuntimeOps ops;
    RuntimeMock mock;
    TASAudioDesiredControls desired;
    config = tumbler_config();
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    memset(&mock, 0, sizeof(mock));
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    CHECK(TASRuntimeReset(&runtime, 2000UL) == kTASStatusOK);
    mock.runtime = &runtime;
    mock.mutateRouteBeforeOperation = 1;
    desired.leftVolume = 0x8000UL;
    CHECK(TASRuntimeSetControls(&runtime, &desired, 3000UL) == kTASStatusOK);
    CHECK(runtime.audio.currentRoutes == kTASAudioRouteHeadphone &&
        runtime.audio.desiredDetects == kTASAudioRouteHeadphone &&
        mock.lockViolations == 0UL);
}

static void test_driver_binds_runtime_controls_and_safe_irq_ordinals(void)
{
    CHECK(driver_source_contains(
        "TASRuntimeAttenuationToCodec([self outputAttenuationLeft]"));
    CHECK(driver_source_contains(
        "TASRuntimeGainToCodec((int)[self inputGainLeft]"));
    CHECK(driver_source_contains("ops.lockOperation = tas_lock_operation"));
    CHECK(driver_source_contains("ops.failMuteOutputs = "
        "tas_fail_mute_outputs"));
    CHECK(driver_source_contains("[self enableInterrupt:1U]"));
    CHECK(driver_source_contains("[self enableInterrupt:2U]"));
    CHECK(!driver_source_contains("index = 2UL"));
    CHECK(driver_source_contains("localInterrupt == 1U"));
    CHECK(driver_source_contains("localInterrupt == 2U"));
    CHECK(driver_source_contains("tag != NX_SoundDeviceMicIn"));
    CHECK(!driver_source_contains("NX_SoundDeviceCDIn"));
    CHECK(!driver_source_contains("NX_SoundDeviceAux1In"));
    CHECK(driver_source_contains("controls->inputMuxActive ? TRUE : FALSE"));
    CHECK(!driver_source_contains("tas_output_route"));
    CHECK(!source_file_contains(
        "../PPCTASAudio.drvproj/PPCTASAudio.lksproj/TASRuntime.h",
        "applyOutputRoute"));
    CHECK(!source_file_contains(
        "../PPCTASAudio.drvproj/PPCTASAudio.lksproj/TASCore.h",
        "kTASAudioSetCodecRoute"));
}

static void test_driver_uses_async_debounce_and_bounded_polling(void)
{
    CHECK(driver_source_contains("ns_timeout"));
    CHECK(driver_source_contains("ns_untimeout"));
    CHECK(driver_source_contains("CALLOUT_PRI_THREAD"));
    CHECK(driver_source_contains("msg_header_t msg"));
    CHECK(driver_source_contains("memset(&msg, 0, sizeof(msg))"));
    CHECK(driver_source_contains(
        "IOGetKernPort([self interruptPort])"));
    CHECK(driver_source_contains("msg_send_from_kernel"));
    CHECK(driver_source_contains("SEND_TIMEOUT, 0"));
    CHECK(!driver_source_contains("MSG_OPTION_NONE"));
    CHECK(driver_source_contains("TAS_POLL_INTERVAL_MS 250UL"));
    CHECK(driver_source_contains("debounceCalloutPending"));
    CHECK(driver_source_contains("pollCalloutPending"));
    CHECK(driver_source_contains("closing"));
    CHECK(driver_source_contains("tasCalloutOwner != nil"));
    CHECK(driver_source_contains("tas_cancel_callouts(self, 1)"));
    CHECK(driver_source_contains("workerRetryCalloutPending"));
    CHECK(driver_source_contains("tas_worker_retry_callout"));
    CHECK(driver_source_contains("token != self->debounceCalloutToken"));
    CHECK(driver_source_contains("token != self->pollCalloutToken"));
    CHECK(driver_source_contains("tas_next_callout_token_locked"));
    CHECK(driver_source_contains("+ initialize"));
    CHECK(driver_source_contains("instance->ioAudioInitialized = 1"));
    CHECK(driver_source_contains("if (!ioAudioInitialized)"));
    CHECK(driver_source_contains("if (!retainOwner)"));
    CHECK(driver_source_contains("*serviceInput = NO"));
    CHECK(driver_source_contains("*serviceOutput = NO"));
    CHECK(driver_source_contains("if (tas_is_closing(self))"));
    CHECK(driver_source_contains("if (target == kTASPowerReady)"));
    CHECK(driver_source_contains("static int tas_is_closing"));
    CHECK(driver_source_contains("closing = self->closing"));
    CHECK(driver_source_count("tas_is_closing(self)") >= 16UL);
    CHECK(driver_source_contains("self->interruptClosing = 1"));
    CHECK(driver_source_contains("TASRuntimeBeginClose(&runtime)"));
    CHECK(driver_source_contains("if (!self->interruptClosing)"));
    CHECK(driver_source_contains("TASRuntimeRecordDMAISRLocked"));
    CHECK(source_file_contains(
        "../PPCTASAudio.drvproj/PPCTASAudio.lksproj/TASRuntime.c",
        "TASRuntimeRecordDetectISRLocked"));
    CHECK(driver_source_contains(
        "    }\n    tas_arm_poll_locked(self);\n"
        "    [tasCalloutLock unlock];"));
    CHECK(driver_source_contains(
        "IOAudio worker threads retain driver\\n\");\n    return self;"));
    CHECK(!driver_source_contains("[self _interruptOccurred]"));
    CHECK(!driver_source_contains(
        "IODelay(TAS_AUDIO_DEBOUNCE_CONFIRM_MS"));
    CHECK(source_file_contains(
        "../PPCTASAudio.drvproj/English.lproj/DriverHelp/README.txt",
        "250 ms"));
    CHECK(source_file_contains(
        "../PPCTASAudio.drvproj/English.lproj/DriverHelp/README.txt",
        "preserves DMA resources"));
    CHECK(source_file_contains(
        "../PPCTASAudio.drvproj/English.lproj/DriverHelp/README.txt",
        "worker threads"));
    CHECK(source_file_contains(
        "../PPCTASAudio.drvproj/English.lproj/DriverHelp/README.txt",
        "cannot be unloaded"));
}

int main(void)
{
    test_raw_isr_only_acks_and_latches();
    test_initial_detect_advances_without_another_edge();
    test_reset_leaves_async_debounce_to_worker();
    test_bounce_and_wake_continue_without_external_edges();
    test_edge_during_route_rolls_back_safely();
    test_route_action_failure_rolls_back_muted();
    test_probe_is_narrow();
    test_delivered_resource_validation();
    test_codec_delay_is_deadline_bounded();
    test_control_conversion_endpoints_and_monotonicity();
    test_deadline_delay_is_wrap_safe();
    test_fail_mute_attempts_every_present_output();
    test_safe_output_stage_failure_attempts_every_output();
    test_anded_reset_uses_mute_constituents();
    test_runtime_binds_both_reviewed_codecs();
    test_acquisition_unwinds_every_stage();
    test_initial_route_failure_unwinds_muted();
    test_controls_conflict_has_no_codec_io();
    test_route_uses_output_op_and_preserves_input_state();
    test_full_duplex_controls_isr_and_power();
    test_dma_fault_is_isolated_to_one_direction();
    test_start_requires_ready_valid_fully_acquired_state();
    test_stop_after_failed_prepare_is_harmless();
    test_detect_read_failure_propagates_and_fail_mutes();
    test_failed_controls_invalidate_truth_from_mute_result();
    test_unwind_disables_irqs_before_dma_and_clears_latches();
    test_unwind_failure_preserves_dma_resources_and_mute_truth();
    test_unwind_deadline_wraps_with_clock();
    test_runtime_commands_reject_after_unwind();
    test_interrupt_close_drains_and_skips_mmio();
    test_begin_close_serializes_against_reset_and_commands();
    test_controls_preserve_prior_serialized_route_commit();
    test_driver_binds_runtime_controls_and_safe_irq_ordinals();
    test_driver_uses_async_debounce_and_bounded_polling();
    test_i2s_adapter_uses_apple_raw_fields();
    if (failures != 0) {
        fprintf(stderr, "%d TAS runtime checks failed\n", failures);
        return 1;
    }
    puts("TAS runtime checks passed");
    return 0;
}
