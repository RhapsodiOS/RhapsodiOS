#include "tas_fixtures.h"
#include "TASRuntime.h"

#include <stdio.h>
#include <string.h>

static int failures;
static TASMachineConfig tumbler_config(void);
#define CHECK(expression) do { if (!(expression)) { \
    fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, \
        #expression); ++failures; } } while (0)

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
    unsigned long nowValue;
    unsigned long detectValues[8];
    unsigned long detectCount;
    unsigned long detectIndex;
    TASRuntime *runtime;
    TASAudioActionOperation injectOperation;
    TASAudioActionOperation failOperation;
    int injected;
    unsigned long outputRouteCalls;
    unsigned long lastOutputRoute;
    unsigned long prepareCount;
    const void *lastBuffer;
    unsigned long lastRate;
} RuntimeMock;

static TASStatus runtime_acquire(void *context, TASRuntimeStage stage,
    const TASMachineConfig *config)
{
    RuntimeMock *mock;
    (void)config;
    mock = (RuntimeMock *)context;
    mock->events[mock->eventCount++] = (long)stage + 1L;
    return mock->failAcquire == (unsigned long)stage + 1UL ?
        kTASStatusTimeout : kTASStatusOK;
}

static void runtime_release(void *context, TASRuntimeStage stage)
{
    RuntimeMock *mock;
    mock = (RuntimeMock *)context;
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
    ++mock->prepareCount;
    mock->lastBuffer = buffer;
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
    (void)deadline;
    mock = (RuntimeMock *)context;
    ++mock->hardwareCalls;
    ring->state = kPPCDBDMAReady;
    return kTASStatusOK;
}

static TASStatus runtime_service(void *context, TASStreamDirection direction,
    PPCDBDMARing *ring, unsigned long *completed)
{
    RuntimeMock *mock;
    (void)ring;
    mock = (RuntimeMock *)context;
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
    mock->trace[mock->traceCount++] = 100UL + (unsigned long)direction;
    return (mock->ackFailMask & (1UL << (unsigned long)direction)) != 0UL ?
        kTASStatusUnresolved : kTASStatusOK;
}

static TASStatus runtime_action(void *context, const TASAudioAction *action)
{
    RuntimeMock *mock;
    mock = (RuntimeMock *)context;
    if (mock->actionCount < 64UL)
        mock->actionOps[mock->actionCount++] = action->operation;
    ++mock->hardwareCalls;
    if (action->operation == kTASAudioScheduleDebounce &&
        mock->nowValue < action->deadline)
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
    ++mock->hardwareCalls;
    return mock->failHardware == mock->hardwareCalls ?
        kTASStatusTimeout : kTASStatusOK;
}

static TASStatus runtime_output_route(void *context, unsigned long routes,
    unsigned long deadline)
{
    RuntimeMock *mock;
    (void)deadline;
    mock = (RuntimeMock *)context;
    ++mock->outputRouteCalls;
    mock->lastOutputRoute = routes;
    if (!mock->injected && mock->runtime != 0 &&
        mock->injectOperation == kTASAudioSetCodecRoute) {
        mock->injected = 1;
        TASRuntimeRecordISR(mock->runtime, kTASRuntimeIRQDetect);
    }
    if (mock->failOperation == kTASAudioSetCodecRoute) {
        mock->failOperation = kTASAudioBlockStarts;
        return kTASStatusTimeout;
    }
    return kTASStatusOK;
}

static unsigned long runtime_detects(void *context)
{
    RuntimeMock *mock;
    mock = (RuntimeMock *)context;
    mock->trace[mock->traceCount++] = 200UL;
    if (mock->detectIndex < mock->detectCount)
        return mock->detectValues[mock->detectIndex++];
    return 1UL;
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

static void runtime_fail_mute(void *context)
{
    ++((RuntimeMock *)context)->failMuteCount;
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
    ops.executeAction = runtime_action;
    ops.applyControls = runtime_controls;
    ops.applyOutputRoute = runtime_output_route;
    ops.sampleDetects = runtime_detects;
    ops.now = runtime_now;
    ops.signalDeferred = runtime_signal;
    ops.failMute = runtime_fail_mute;
    return ops;
}

static void test_raw_dma_isr_only_acks_records_and_signals(void)
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
    CHECK(mock.traceCount == 2UL && mock.trace[0] == 100UL &&
        mock.trace[1] == 300UL);
    CHECK(runtime.pendingIRQs == kTASRuntimeIRQOutput);
    CHECK(mock.serviceCount[0] == 0UL && mock.detectIndex == 0UL &&
        mock.hardwareCalls == 0UL);
    mock.ackFailMask = kTASStreamMaskInput;
    CHECK(TASRuntimeRecordDMAISR(&runtime, kTASStreamInput) ==
        kTASStatusUnresolved);
    CHECK((runtime.pendingIRQs & kTASRuntimeIRQInput) != 0UL &&
        runtime.dmaFaultMask == kTASStreamMaskInput);
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
        mock.detectIndex == 7UL);
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
    mock.injectOperation = kTASAudioSetCodecRoute;
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
    mock.failOperation = kTASAudioSetCodecRoute;
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

typedef struct {
    unsigned long calls;
    unsigned long failCall;
} MuteMock;

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
    memset(&mock, 0, sizeof(mock));
    mock.failCall = 1UL;
    CHECK(TASRuntimeFailMuteOutputs(&config, &mock, mute_gpio) ==
        kTASStatusTimeout);
    CHECK(mock.calls == 3UL);
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
        for (index = 0UL; index + 1UL < fail; ++index)
            CHECK(mock.events[fail + index] == -((long)fail - 1L -
                (long)index));
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
    mock.failOperation = kTASAudioSetCodecRoute;
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
    CHECK(mock.outputRouteCalls == 1UL);
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
    CHECK(mock.hardwareCalls == before &&
        mock.signalCount == signalBefore + 3UL);
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
    int notifyInput;
    int notifyOutput;
    config = tumbler_config();
    memset(&desired, 0, sizeof(desired));
    desired.rate = 44100UL;
    memset(&mock, 0, sizeof(mock));
    mock.failServiceMask = kTASStreamMaskOutput;
    ops = runtime_ops(&mock);
    CHECK(TASRuntimeInit(&runtime, &config, &desired, &ops) == kTASStatusOK);
    TASRuntimeRecordISR(&runtime, kTASRuntimeIRQOutput);
    TASRuntimeRecordISR(&runtime, kTASRuntimeIRQInput);
    CHECK(TASRuntimeServiceDeferred(&runtime, 300UL, &notifyInput,
        &notifyOutput) == kTASStatusUnresolved);
    CHECK(mock.serviceCount[0] == 1UL && mock.serviceCount[1] == 1UL);
    CHECK(runtime.dmaFaultMask == kTASStreamMaskOutput);
    CHECK(notifyInput && !notifyOutput);
}

int main(void)
{
    test_raw_dma_isr_only_acks_records_and_signals();
    test_initial_detect_advances_without_another_edge();
    test_bounce_and_wake_continue_without_external_edges();
    test_edge_during_route_rolls_back_safely();
    test_route_action_failure_rolls_back_muted();
    test_probe_is_narrow();
    test_codec_delay_is_deadline_bounded();
    test_fail_mute_attempts_every_present_output();
    test_runtime_binds_both_reviewed_codecs();
    test_acquisition_unwinds_every_stage();
    test_initial_route_failure_unwinds_muted();
    test_controls_conflict_has_no_codec_io();
    test_route_uses_output_op_and_preserves_input_state();
    test_full_duplex_controls_isr_and_power();
    test_dma_fault_is_isolated_to_one_direction();
    test_i2s_adapter_uses_apple_raw_fields();
    if (failures != 0) {
        fprintf(stderr, "%d TAS runtime checks failed\n", failures);
        return 1;
    }
    puts("TAS runtime checks passed");
    return 0;
}
