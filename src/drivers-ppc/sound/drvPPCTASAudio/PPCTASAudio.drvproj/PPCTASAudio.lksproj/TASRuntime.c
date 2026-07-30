#include "TASRuntime.h"

#include <string.h>

#define TAS_STAGE_BIT(stage) (1UL << (unsigned long)(stage))
#define TAS_ALL_STAGES ((1UL << (unsigned long)kTASRuntimeStageCount) - 1UL)

static TASStatus service_detect(TASRuntime *, int, unsigned long);
static TASStatus fail_mute_and_invalidate(TASRuntime *, int);

static unsigned long runtime_deadline_after(unsigned long now,
    unsigned long interval)
{
    if (now > ~0UL - interval)
        return ~0UL;
    return now + interval;
}

static void record_dma_fault(TASRuntime *runtime,
    TASStreamDirection direction, unsigned long deadline)
{
    unsigned long mask;
    mask = 1UL << (unsigned long)direction;
    runtime->ops.lockInterrupt(runtime->ops.context);
    runtime->dmaFaultMask |= mask;
    runtime->ops.unlockInterrupt(runtime->ops.context);
    (void)runtime->ops.stopResetDMA(runtime->ops.context, direction,
        &runtime->rings[(unsigned long)direction], deadline);
    if ((runtime->clock.activeMask & mask) != 0UL)
        (void)TASReleaseI2SStream(&runtime->clock, direction);
    runtime->ops.lockState(runtime->ops.context);
    runtime->audio.streamsRunning = runtime->clock.activeMask != 0UL;
    runtime->ops.unlockState(runtime->ops.context);
    (void)fail_mute_and_invalidate(runtime, 0);
}

static unsigned long route_mask(const TASMachineConfig *config)
{
    unsigned long routes;
    routes = kTASAudioRouteSpeaker;
    if (config->routes[kTASRouteHeadphone].present)
        routes |= kTASAudioRouteHeadphone;
    if (config->routes[kTASRouteLineOut].present)
        routes |= kTASAudioRouteLineOut;
    return routes;
}

static int valid_ops(const TASRuntimeOps *ops)
{
    return ops != 0 && ops->acquire != 0 && ops->release != 0 &&
        ops->prepareDMA != 0 && ops->startDMA != 0 &&
        ops->stopResetDMA != 0 && ops->serviceDMA != 0 &&
        ops->ackDMAInterrupt != 0 &&
        ops->ackDetectInterrupt != 0 &&
        ops->lockInterrupt != 0 && ops->unlockInterrupt != 0 &&
        ops->lockOperation != 0 && ops->unlockOperation != 0 &&
        ops->lockState != 0 && ops->unlockState != 0 &&
        ops->executeAction != 0 && ops->applyControls != 0 &&
        ops->applyOutputRoute != 0 &&
        ops->sampleDetects != 0 && ops->now != 0 &&
        ops->signalDeferred != 0 &&
        ops->failMuteOutputs != 0;
}

static TASStatus fail_mute_and_invalidate(TASRuntime *runtime,
    int detectBlocked)
{
    TASStatus muteStatus;
    muteStatus = runtime->ops.failMuteOutputs(runtime->ops.context);
    runtime->ops.lockState(runtime->ops.context);
    runtime->audio.hardwareValid = 0;
    runtime->audio.routeValid = 0;
    runtime->audio.outputsMuted = muteStatus == kTASStatusOK;
    runtime->audio.outputsMuteKnown = muteStatus == kTASStatusOK;
    if (detectBlocked)
        runtime->audio.detectBlocked = 1;
    runtime->ops.unlockState(runtime->ops.context);
    return muteStatus;
}

TASStatus TASRuntimeProbe(const TASPropertyReader *reader,
    TASMachineConfig *config)
{
    TASStatus status;
    if (reader == 0 || config == 0)
        return kTASStatusMalformed;
    status = TASParseMachineConfig(reader, config);
    if (status != kTASStatusOK)
        return status;
    if ((config->codecKind != kTASCodecTAS3001C &&
        config->codecKind != kTASCodecTAS3004) || config->rateCount == 0UL ||
        config->i2s.length == 0UL || config->outputDBDMA.length == 0UL ||
        config->inputDBDMA.length == 0UL)
        return kTASStatusNotMatched;
    return kTASStatusOK;
}

TASStatus TASRuntimeInit(TASRuntime *runtime,
    const TASMachineConfig *config, const TASAudioDesiredControls *desired,
    const TASRuntimeOps *ops)
{
    TASStatus status;
    if (runtime == 0 || config == 0 || desired == 0 || !valid_ops(ops))
        return kTASStatusMalformed;
    memset(runtime, 0, sizeof(*runtime));
    runtime->config = *config;
    runtime->ops = *ops;
    status = TASCodecBind(&runtime->codec,
        config->codecKind == kTASCodecTAS3001C ? TAS3001CCodecOps() :
        TAS3004CodecOps(), &ops->codecCallbacks);
    if (status != kTASStatusOK)
        return status;
    TASSharedClockInit(&runtime->clock);
    status = TASAudioStateInit(&runtime->audio, route_mask(config),
        config->codecKind, config->quirks, desired);
    if (status != kTASStatusOK)
        return status;
    runtime->initialized = 1;
    return kTASStatusOK;
}

static void release_stage_locked(TASRuntime *runtime,
    TASRuntimeStage stage)
{
    if ((runtime->acquiredMask & TAS_STAGE_BIT(stage)) == 0UL)
        return;
    runtime->ops.release(runtime->ops.context, stage);
    runtime->acquiredMask &= ~TAS_STAGE_BIT(stage);
}

static TASStatus cleanup_dma_locked(TASRuntime *runtime,
    unsigned long deadline)
{
    TASStatus first;
    TASStatus status;
    TASStreamDirection direction;
    unsigned long faults;
    unsigned long mask;
    first = kTASStatusOK;
    runtime->ops.lockInterrupt(runtime->ops.context);
    faults = runtime->dmaFaultMask;
    runtime->ops.unlockInterrupt(runtime->ops.context);
    for (direction = kTASStreamOutput; direction <= kTASStreamInput;
        direction = (TASStreamDirection)(direction + 1)) {
        mask = 1UL << (unsigned long)direction;
        if ((runtime->clock.activeMask & mask) == 0UL &&
            (faults & mask) == 0UL &&
            runtime->rings[(unsigned long)direction].state !=
                kPPCDBDMARunning &&
            runtime->rings[(unsigned long)direction].state !=
                kPPCDBDMAFaulted)
            continue;
        status = runtime->ops.stopResetDMA(runtime->ops.context, direction,
            &runtime->rings[(unsigned long)direction], deadline);
        if (first == kTASStatusOK && status != kTASStatusOK)
            first = status;
        if ((runtime->clock.activeMask & mask) != 0UL)
            (void)TASReleaseI2SStream(&runtime->clock, direction);
    }
    return first;
}

static void clear_work_latches_locked(TASRuntime *runtime)
{
    runtime->ops.lockInterrupt(runtime->ops.context);
    runtime->pendingIRQs = 0UL;
    runtime->detectISREdges = 0UL;
    runtime->dmaFaultMask = 0UL;
    runtime->detectFaultPending = 0;
    runtime->ops.unlockInterrupt(runtime->ops.context);
}

static TASStatus unwind_locked(TASRuntime *runtime, unsigned long deadline)
{
    long stage;
    TASStatus status;
    if (runtime == 0 || !runtime->initialized)
        return kTASStatusMalformed;
    release_stage_locked(runtime, kTASRuntimeInstallInputIRQ);
    release_stage_locked(runtime, kTASRuntimeInstallOutputIRQ);
    status = cleanup_dma_locked(runtime, deadline);
    clear_work_latches_locked(runtime);
    runtime->ops.lockState(runtime->ops.context);
    runtime->audio.streamsRunning = 0;
    runtime->ops.unlockState(runtime->ops.context);
    if (status != kTASStatusOK) {
        (void)fail_mute_and_invalidate(runtime, 0);
        return status;
    }
    for (stage = (long)kTASRuntimeStageCount - 1L; stage >= 0L; --stage) {
        release_stage_locked(runtime, (TASRuntimeStage)stage);
    }
    TASSharedClockInit(&runtime->clock);
    memset(runtime->rings, 0, sizeof(runtime->rings));
    return kTASStatusOK;
}

TASStatus TASRuntimeUnwind(TASRuntime *runtime)
{
    TASStatus status;
    unsigned long deadline;
    if (runtime == 0 || !runtime->initialized)
        return kTASStatusMalformed;
    runtime->ops.lockOperation(runtime->ops.context);
    deadline = runtime_deadline_after(
        runtime->ops.now(runtime->ops.context), 100UL);
    status = unwind_locked(runtime, deadline);
    runtime->ops.unlockOperation(runtime->ops.context);
    return status;
}

TASStatus TASRuntimeBeginClose(TASRuntime *runtime)
{
    if (runtime == 0 || !runtime->initialized)
        return kTASStatusConflict;
    runtime->ops.lockOperation(runtime->ops.context);
    runtime->closing = 1;
    runtime->ops.unlockOperation(runtime->ops.context);
    return kTASStatusOK;
}

TASStatus TASRuntimeReset(TASRuntime *runtime, unsigned long deadline)
{
    TASRuntimeStage stage;
    TASStatus status;
    unsigned long debounceDeadline;
    unsigned long now;
    int detectPending;
    int routeValid;
    (void)deadline;
    if (runtime == 0 || !runtime->initialized)
        return kTASStatusConflict;
    runtime->ops.lockOperation(runtime->ops.context);
    if (runtime->closing || runtime->acquiredMask != 0UL) {
        runtime->ops.unlockOperation(runtime->ops.context);
        return kTASStatusConflict;
    }
    runtime->operationDeadline = deadline;
    for (stage = kTASRuntimePlatformReady;
        stage < kTASRuntimeStageCount; stage = (TASRuntimeStage)(stage + 1)) {
        status = runtime->ops.acquire(runtime->ops.context, stage,
            &runtime->config);
        if (status != kTASStatusOK) {
            if ((runtime->acquiredMask &
                TAS_STAGE_BIT(kTASRuntimeSafeOutputs)) != 0UL)
                (void)runtime->ops.failMuteOutputs(runtime->ops.context);
            (void)unwind_locked(runtime, deadline);
            runtime->ops.unlockOperation(runtime->ops.context);
            return status;
        }
        runtime->acquiredMask |= TAS_STAGE_BIT(stage);
    }
    status = service_detect(runtime, 1, deadline);
    if (status == kTASStatusOK) {
        runtime->ops.lockState(runtime->ops.context);
        detectPending = runtime->audio.debouncePending;
        debounceDeadline = runtime->audio.debounceDeadline;
        runtime->ops.unlockState(runtime->ops.context);
        now = runtime->ops.now(runtime->ops.context);
        if (detectPending && now >= debounceDeadline)
            status = service_detect(runtime, 0, deadline);
    }
    if (status == kTASStatusOK) {
        runtime->ops.lockState(runtime->ops.context);
        detectPending = runtime->audio.debouncePending;
        debounceDeadline = runtime->audio.debounceDeadline;
        runtime->ops.unlockState(runtime->ops.context);
        now = runtime->ops.now(runtime->ops.context);
        if (detectPending && now >= debounceDeadline)
            status = service_detect(runtime, 0, deadline);
    }
    runtime->ops.lockState(runtime->ops.context);
    detectPending = runtime->audio.debouncePending;
    routeValid = runtime->audio.routeValid;
    runtime->ops.unlockState(runtime->ops.context);
    if (status != kTASStatusOK || (!detectPending && !routeValid)) {
        (void)runtime->ops.failMuteOutputs(runtime->ops.context);
        (void)unwind_locked(runtime, deadline);
        runtime->ops.unlockOperation(runtime->ops.context);
        return status == kTASStatusOK ? kTASStatusUnresolved : status;
    }
    runtime->ops.lockInterrupt(runtime->ops.context);
    runtime->dmaFaultMask = 0UL;
    runtime->ops.unlockInterrupt(runtime->ops.context);
    runtime->ops.unlockOperation(runtime->ops.context);
    return kTASStatusOK;
}

TASStatus TASRuntimeStartStream(TASRuntime *runtime,
    TASStreamDirection direction, const void *buffer, unsigned long bytes,
    unsigned long period, unsigned long rate, unsigned long deadline)
{
    TASStatus status;
    TASI2SClock clock;
    PPCDBDMARing *ring;
    unsigned long faults;
    int gateOpen;
    if (runtime == 0 || buffer == 0 || bytes == 0UL || period == 0UL ||
        direction > kTASStreamInput)
        return kTASStatusConflict;
    runtime->ops.lockOperation(runtime->ops.context);
    if (runtime->closing) {
        runtime->ops.unlockOperation(runtime->ops.context);
        return kTASStatusConflict;
    }
    runtime->ops.lockInterrupt(runtime->ops.context);
    faults = runtime->dmaFaultMask;
    runtime->ops.unlockInterrupt(runtime->ops.context);
    runtime->ops.lockState(runtime->ops.context);
    gateOpen = runtime->acquiredMask == TAS_ALL_STAGES &&
        runtime->audio.powerState == kTASPowerReady &&
        runtime->audio.hardwareValid && runtime->audio.routeValid &&
        !runtime->audio.startsBlocked &&
        (faults & (1UL << (unsigned long)direction)) == 0UL;
    runtime->ops.unlockState(runtime->ops.context);
    if (!gateOpen) {
        runtime->ops.unlockOperation(runtime->ops.context);
        return kTASStatusConflict;
    }
    status = TASAcquireI2SStream(&runtime->config, &runtime->clock,
        direction, rate, &clock);
    if (status != kTASStatusOK) {
        runtime->ops.unlockOperation(runtime->ops.context);
        return status;
    }
    ring = &runtime->rings[(unsigned long)direction];
    status = runtime->ops.prepareDMA(runtime->ops.context, direction,
        buffer, bytes, period, ring);
    if (status == kTASStatusOK)
        status = runtime->ops.startDMA(runtime->ops.context, direction,
            ring, deadline);
    if (status != kTASStatusOK) {
        (void)TASReleaseI2SStream(&runtime->clock, direction);
        runtime->ops.lockInterrupt(runtime->ops.context);
        runtime->dmaFaultMask |= 1UL << (unsigned long)direction;
        runtime->ops.unlockInterrupt(runtime->ops.context);
        (void)fail_mute_and_invalidate(runtime, 0);
        runtime->ops.unlockOperation(runtime->ops.context);
        return status;
    }
    runtime->ops.lockState(runtime->ops.context);
    runtime->audio.streamsRunning = 1;
    runtime->ops.unlockState(runtime->ops.context);
    runtime->ops.unlockOperation(runtime->ops.context);
    return kTASStatusOK;
}

TASStatus TASRuntimeStopStream(TASRuntime *runtime,
    TASStreamDirection direction, unsigned long deadline)
{
    TASStatus status;
    if (runtime == 0 || direction > kTASStreamInput)
        return kTASStatusMalformed;
    runtime->ops.lockOperation(runtime->ops.context);
    if (runtime->closing) {
        runtime->ops.unlockOperation(runtime->ops.context);
        return kTASStatusConflict;
    }
    if ((runtime->clock.activeMask &
        (1UL << (unsigned long)direction)) == 0UL) {
        runtime->ops.unlockOperation(runtime->ops.context);
        return kTASStatusOK;
    }
    status = runtime->ops.stopResetDMA(runtime->ops.context, direction,
        &runtime->rings[(unsigned long)direction], deadline);
    if (status != kTASStatusOK) {
        runtime->ops.lockInterrupt(runtime->ops.context);
        runtime->dmaFaultMask |= 1UL << (unsigned long)direction;
        runtime->ops.unlockInterrupt(runtime->ops.context);
        (void)fail_mute_and_invalidate(runtime, 0);
        runtime->ops.unlockOperation(runtime->ops.context);
        return status;
    }
    status = TASReleaseI2SStream(&runtime->clock, direction);
    runtime->ops.lockState(runtime->ops.context);
    runtime->audio.streamsRunning = runtime->clock.activeMask != 0UL;
    runtime->ops.unlockState(runtime->ops.context);
    runtime->ops.unlockOperation(runtime->ops.context);
    return status;
}

void TASRuntimeRecordISR(TASRuntime *runtime, TASRuntimeIRQ irq)
{
    if (runtime == 0 || !runtime->initialized)
        return;
    runtime->ops.lockInterrupt(runtime->ops.context);
    if (irq == kTASRuntimeIRQDetect)
        ++runtime->detectISREdges;
    runtime->pendingIRQs |= (unsigned long)irq;
    runtime->ops.unlockInterrupt(runtime->ops.context);
}

TASStatus TASRuntimeRecordDMAISRLocked(TASRuntime *runtime,
    TASStreamDirection direction)
{
    TASStatus status;
    TASRuntimeIRQ irq;
    if (runtime == 0 || !runtime->initialized ||
        (direction != kTASStreamOutput && direction != kTASStreamInput))
        return kTASStatusMalformed;
    status = runtime->ops.ackDMAInterrupt(runtime->ops.context, direction);
    irq = direction == kTASStreamOutput ? kTASRuntimeIRQOutput :
        kTASRuntimeIRQInput;
    runtime->pendingIRQs |= (unsigned long)irq;
    if (status != kTASStatusOK)
        runtime->dmaFaultMask |= 1UL << (unsigned long)direction;
    return status;
}

TASStatus TASRuntimeRecordDMAISR(TASRuntime *runtime,
    TASStreamDirection direction)
{
    TASStatus status;
    if (runtime == 0 || !runtime->initialized ||
        (direction != kTASStreamOutput && direction != kTASStreamInput))
        return kTASStatusMalformed;
    runtime->ops.lockInterrupt(runtime->ops.context);
    status = TASRuntimeRecordDMAISRLocked(runtime, direction);
    runtime->ops.unlockInterrupt(runtime->ops.context);
    return status;
}

TASStatus TASRuntimeRecordDetectISRLocked(TASRuntime *runtime)
{
    TASStatus status;
    if (runtime == 0 || !runtime->initialized)
        return kTASStatusMalformed;
    status = runtime->ops.ackDetectInterrupt(runtime->ops.context);
    ++runtime->detectISREdges;
    runtime->pendingIRQs |= kTASRuntimeIRQDetect;
    if (status != kTASStatusOK)
        runtime->detectFaultPending = 1;
    return status;
}

TASStatus TASRuntimeRecordDetectISR(TASRuntime *runtime)
{
    TASStatus status;
    if (runtime == 0 || !runtime->initialized)
        return kTASStatusMalformed;
    runtime->ops.lockInterrupt(runtime->ops.context);
    status = TASRuntimeRecordDetectISRLocked(runtime);
    runtime->ops.unlockInterrupt(runtime->ops.context);
    return status;
}

static TASStatus execute_plan(TASRuntime *, TASAudioActionPlan *,
    TASAudioToken *, unsigned long);

static TASStatus schedule_detect(TASRuntime *runtime,
    TASAudioActionPlan *plan)
{
    unsigned long index;
    TASStatus status;
    for (index = 0UL; index < plan->count; ++index) {
        if (plan->actions[index].operation != kTASAudioScheduleDebounce)
            return kTASStatusUnsupported;
        status = runtime->ops.executeAction(runtime->ops.context,
            &plan->actions[index]);
        if (status != kTASStatusOK) {
            (void)runtime->ops.failMuteOutputs(runtime->ops.context);
            return status;
        }
    }
    return kTASStatusOK;
}

static TASStatus service_detect(TASRuntime *runtime, int newEdge,
    unsigned long deadline)
{
    TASAudioActionPlan plan;
    TASAudioToken sample;
    TASAudioToken route;
    TASStatus status;
    unsigned long generation;
    unsigned long now;
    unsigned long detects;
    int debouncePending;
    now = runtime->ops.now(runtime->ops.context);
    if (newEdge) {
        runtime->ops.lockState(runtime->ops.context);
        status = TASAudioRecordDetectISR(&runtime->audio,
            runtime->audio.desiredDetects,
            &generation);
        runtime->ops.unlockState(runtime->ops.context);
        if (status != kTASStatusOK)
            return status;
        if (now > ~0UL - TAS_AUDIO_DEBOUNCE_CONFIRM_MS)
            return kTASStatusOverflow;
        runtime->ops.lockState(runtime->ops.context);
        status = TASAudioBuildDebounceSchedule(&runtime->audio, generation,
            now + TAS_AUDIO_DEBOUNCE_CONFIRM_MS, &plan);
        runtime->ops.unlockState(runtime->ops.context);
        if (status != kTASStatusOK)
            return status;
        return schedule_detect(runtime, &plan);
    }
    runtime->ops.lockState(runtime->ops.context);
    debouncePending = runtime->audio.debouncePending;
    runtime->ops.unlockState(runtime->ops.context);
    if (!debouncePending)
        return kTASStatusOK;
    runtime->ops.lockState(runtime->ops.context);
    generation = runtime->audio.detectGeneration;
    status = TASAudioPrepareDebounceSample(&runtime->audio, generation, now,
        &plan, &sample);
    runtime->ops.unlockState(runtime->ops.context);
    if (status == kTASStatusTimeout)
        return status;
    if (status != kTASStatusOK)
        return status;
    status = runtime->ops.executeAction(runtime->ops.context,
        &plan.actions[0]);
    if (status != kTASStatusOK) {
        (void)runtime->ops.failMuteOutputs(runtime->ops.context);
        return status;
    }
    status = runtime->ops.sampleDetects(runtime->ops.context, &detects);
    if (status != kTASStatusOK) {
        (void)fail_mute_and_invalidate(runtime, 1);
        return status;
    }
    runtime->ops.lockState(runtime->ops.context);
    status = TASAudioApplyDetectSample(&runtime->audio, &sample, detects,
        now, &plan, &route);
    runtime->ops.unlockState(runtime->ops.context);
    if (status == kTASStatusUnresolved)
        return schedule_detect(runtime, &plan);
    if (status != kTASStatusOK)
        return status;
    return execute_plan(runtime, &plan, &route, deadline);
}

TASStatus TASRuntimeServiceDeferred(TASRuntime *runtime,
    unsigned long deadline, int *notifyInput, int *notifyOutput)
{
    TASStatus status;
    TASStatus result;
    unsigned long completed;
    unsigned long faults;
    unsigned long pending;
    TASPowerState powerBefore;
    TASPowerState powerAfter;
    int debouncePending;
    int detectFault;
    if (runtime == 0 || notifyInput == 0 || notifyOutput == 0)
        return kTASStatusMalformed;
    *notifyInput = 0;
    *notifyOutput = 0;
    if (!runtime->initialized)
        return kTASStatusConflict;
    runtime->ops.lockOperation(runtime->ops.context);
    if (runtime->closing || runtime->acquiredMask != TAS_ALL_STAGES) {
        runtime->ops.unlockOperation(runtime->ops.context);
        return kTASStatusConflict;
    }
    result = kTASStatusOK;
    runtime->ops.lockInterrupt(runtime->ops.context);
    pending = runtime->pendingIRQs;
    runtime->pendingIRQs = 0UL;
    faults = runtime->dmaFaultMask;
    detectFault = runtime->detectFaultPending;
    runtime->detectFaultPending = 0;
    runtime->ops.unlockInterrupt(runtime->ops.context);
    runtime->ops.lockState(runtime->ops.context);
    debouncePending = runtime->audio.debouncePending;
    powerBefore = runtime->audio.powerState;
    runtime->ops.unlockState(runtime->ops.context);
    if (detectFault) {
        (void)fail_mute_and_invalidate(runtime, 1);
        pending &= ~((unsigned long)kTASRuntimeIRQDetect);
        debouncePending = 0;
        result = kTASStatusUnresolved;
    }
    if ((pending & kTASRuntimeIRQOutput) != 0UL) {
        status = runtime->ops.serviceDMA(runtime->ops.context,
            kTASStreamOutput, &runtime->rings[0], &completed);
        if (status != kTASStatusOK ||
            (faults & kTASStreamMaskOutput) != 0UL) {
            record_dma_fault(runtime, kTASStreamOutput, deadline);
            result = status == kTASStatusOK ? kTASStatusUnresolved : status;
        } else
            *notifyOutput = completed != 0UL;
    }
    if ((pending & kTASRuntimeIRQInput) != 0UL) {
        status = runtime->ops.serviceDMA(runtime->ops.context,
            kTASStreamInput, &runtime->rings[1], &completed);
        if (status != kTASStatusOK ||
            (faults & kTASStreamMaskInput) != 0UL) {
            record_dma_fault(runtime, kTASStreamInput, deadline);
            if (result == kTASStatusOK)
                result = status == kTASStatusOK ? kTASStatusUnresolved :
                    status;
        } else
            *notifyInput = completed != 0UL;
    }
    if ((pending & kTASRuntimeIRQDetect) != 0UL || debouncePending) {
        status = service_detect(runtime,
            (pending & kTASRuntimeIRQDetect) != 0UL, deadline);
        if (status != kTASStatusOK && result == kTASStatusOK)
            result = status;
    }
    runtime->ops.lockState(runtime->ops.context);
    powerAfter = runtime->audio.powerState;
    runtime->ops.unlockState(runtime->ops.context);
    if (result == kTASStatusOK && powerBefore == kTASPowerWaking &&
        powerAfter == kTASPowerReady) {
        runtime->ops.lockInterrupt(runtime->ops.context);
        runtime->dmaFaultMask = 0UL;
        runtime->ops.unlockInterrupt(runtime->ops.context);
    }
    runtime->ops.unlockOperation(runtime->ops.context);
    return result;
}

TASStatus TASRuntimeSetControls(TASRuntime *runtime,
    const TASAudioDesiredControls *desired, unsigned long deadline)
{
    TASStatus status;
    TASAudioState candidate;
    if (runtime == 0 || desired == 0)
        return kTASStatusMalformed;
    if (!runtime->initialized)
        return kTASStatusConflict;
    runtime->ops.lockOperation(runtime->ops.context);
    if (runtime->closing || runtime->acquiredMask != TAS_ALL_STAGES) {
        runtime->ops.unlockOperation(runtime->ops.context);
        return kTASStatusConflict;
    }
    runtime->ops.lockState(runtime->ops.context);
    candidate = runtime->audio;
    status = TASAudioSetDesiredControls(&candidate, desired);
    runtime->ops.unlockState(runtime->ops.context);
    if (status != kTASStatusOK) {
        runtime->ops.unlockOperation(runtime->ops.context);
        return status;
    }
    status = runtime->ops.applyControls(runtime->ops.context, desired,
        deadline);
    if (status != kTASStatusOK) {
        (void)fail_mute_and_invalidate(runtime, 0);
        runtime->ops.unlockOperation(runtime->ops.context);
        return status;
    }
    runtime->ops.lockState(runtime->ops.context);
    runtime->audio = candidate;
    runtime->ops.unlockState(runtime->ops.context);
    runtime->ops.unlockOperation(runtime->ops.context);
    return kTASStatusOK;
}

static TASStatus execute_plan(TASRuntime *runtime,
    TASAudioActionPlan *plan, TASAudioToken *token, unsigned long deadline)
{
    TASStatus status;
    TASStatus failureStatus;
    TASAudioActionPlan rollbackPlan;
    TASAudioToken rollback;
    unsigned long index;
    unsigned long rollbackDeadline;
    unsigned long detectEdges;
    unsigned long detects;
    unsigned long generation;
    runtime->ops.lockInterrupt(runtime->ops.context);
    detectEdges = runtime->detectISREdges;
    runtime->ops.unlockInterrupt(runtime->ops.context);
    for (index = 0UL; index < plan->count; ++index) {
        runtime->ops.lockState(runtime->ops.context);
        status = TASAudioAuthorizeAction(&runtime->audio, token, index);
        runtime->ops.unlockState(runtime->ops.context);
        if (status != kTASStatusOK)
            break;
        plan->actions[index].deadline = deadline;
        if (plan->actions[index].operation == kTASAudioSetOutputMux)
            status = kTASStatusOK;
        else if (plan->actions[index].operation == kTASAudioSetCodecRoute)
            status = runtime->ops.applyOutputRoute(runtime->ops.context,
                plan->actions[index].value, deadline);
        else
            status = runtime->ops.executeAction(runtime->ops.context,
                &plan->actions[index]);
        if (status != kTASStatusOK)
            break;
        runtime->ops.lockInterrupt(runtime->ops.context);
        generation = runtime->detectISREdges;
        runtime->ops.unlockInterrupt(runtime->ops.context);
        if (generation != detectEdges) {
            status = runtime->ops.sampleDetects(runtime->ops.context,
                &detects);
            if (status != kTASStatusOK) {
                (void)fail_mute_and_invalidate(runtime, 1);
                break;
            }
            runtime->ops.lockState(runtime->ops.context);
            status = TASAudioRecordDetectISR(&runtime->audio,
                detects, &rollbackDeadline);
            runtime->ops.unlockState(runtime->ops.context);
            detectEdges = generation;
            if (status != kTASStatusOK)
                break;
        }
        runtime->ops.lockState(runtime->ops.context);
        status = TASAudioCompleteAction(&runtime->audio, token, index);
        runtime->ops.unlockState(runtime->ops.context);
        if (status != kTASStatusOK)
            break;
    }
    if (index == plan->count) {
        runtime->ops.lockState(runtime->ops.context);
        status = TASAudioCommitTransition(&runtime->audio, token);
        runtime->ops.unlockState(runtime->ops.context);
        return status;
    }
    failureStatus = status;
    (void)runtime->ops.failMuteOutputs(runtime->ops.context);
    rollbackDeadline = runtime->ops.now(runtime->ops.context) + 100UL;
    if (rollbackDeadline < 100UL)
        rollbackDeadline = ~0UL;
    runtime->ops.lockState(runtime->ops.context);
    status = TASAudioFailTransition(&runtime->audio, token, rollbackDeadline,
        &rollbackPlan, &rollback);
    runtime->ops.unlockState(runtime->ops.context);
    if (status == kTASStatusOK) {
        for (index = 0UL; index < rollbackPlan.count; ++index) {
            runtime->ops.lockState(runtime->ops.context);
            status = TASAudioAuthorizeAction(&runtime->audio, &rollback,
                index);
            runtime->ops.unlockState(runtime->ops.context);
            if (status != kTASStatusOK)
                break;
            rollbackPlan.actions[index].deadline = rollbackDeadline;
            if (runtime->ops.executeAction(runtime->ops.context,
                &rollbackPlan.actions[index]) != kTASStatusOK)
                break;
            runtime->ops.lockState(runtime->ops.context);
            status = TASAudioCompleteAction(&runtime->audio, &rollback,
                index);
            runtime->ops.unlockState(runtime->ops.context);
            if (status != kTASStatusOK)
                break;
        }
        runtime->ops.lockState(runtime->ops.context);
        if (index == rollbackPlan.count)
            (void)TASAudioCommitRollback(&runtime->audio, &rollback);
        else
            (void)TASAudioAbortRollback(&runtime->audio, &rollback);
        runtime->ops.unlockState(runtime->ops.context);
    }
    return failureStatus;
}

TASStatus TASRuntimeSetPower(TASRuntime *runtime, TASPowerState power,
    unsigned long deadline)
{
    TASAudioActionPlan plan;
    TASAudioToken token;
    TASStatus status;
    int debouncePending;
    TASPowerState currentPower;
    if (runtime == 0)
        return kTASStatusMalformed;
    if (!runtime->initialized)
        return kTASStatusConflict;
    runtime->ops.lockOperation(runtime->ops.context);
    if (runtime->closing || runtime->acquiredMask != TAS_ALL_STAGES) {
        runtime->ops.unlockOperation(runtime->ops.context);
        return kTASStatusConflict;
    }
    runtime->ops.lockState(runtime->ops.context);
    status = TASAudioPreparePower(&runtime->audio, power, deadline, &plan,
        &token);
    runtime->ops.unlockState(runtime->ops.context);
    if (status != kTASStatusOK) {
        runtime->ops.unlockOperation(runtime->ops.context);
        return status;
    }
    status = execute_plan(runtime, &plan, &token, deadline);
    runtime->ops.lockState(runtime->ops.context);
    debouncePending = runtime->audio.debouncePending;
    currentPower = runtime->audio.powerState;
    runtime->ops.unlockState(runtime->ops.context);
    if (status == kTASStatusOK && debouncePending &&
        currentPower == kTASPowerWaking) {
        TASRuntimeRecordISR(runtime, kTASRuntimeIRQDetect);
        runtime->ops.signalDeferred(runtime->ops.context);
    }
    runtime->ops.unlockOperation(runtime->ops.context);
    return status;
}

/* Raw fields follow Apple's AudioI2SControl serial-format register layout. */
TASStatus TASRuntimeEncodeI2S(const TASI2SPlanStep *step,
    unsigned long *serialFormat, unsigned long *dataWord)
{
    unsigned long source;
    unsigned long mclk;
    unsigned long sclk;
    if (step == 0 || serialFormat == 0 || dataWord == 0)
        return kTASStatusMalformed;
    source = step->sourceHz == 18432000UL ? 0UL :
        (step->sourceHz == 45158400UL ? 1UL :
        (step->sourceHz == 49152000UL ? 2UL : 3UL));
    if (source == 3UL || step->mclkDivisor == 0UL ||
        step->sclkDivisor == 0UL)
        return kTASStatusUnsupported;
    mclk = step->mclkDivisor == 1UL ? 0x14UL :
        (step->mclkDivisor == 3UL ? 0x13UL :
        (step->mclkDivisor == 5UL ? 0x12UL :
        (step->mclkDivisor / 2UL - 1UL)));
    sclk = step->sclkDivisor / 2UL - 1UL;
    *serialFormat = (source << 30) | ((mclk & 0x1fUL) << 24) |
        ((sclk & 0xfUL) << 20);
    *dataWord = step->value;
    return kTASStatusOK;
}

TASStatus TASRuntimeBoundedDelay(void *context, unsigned long usec,
    unsigned long deadline, unsigned long (*now)(void *),
    void (*wait)(void *, unsigned long))
{
    unsigned long current;
    unsigned long required;
    unsigned long remaining;
    unsigned long after;
    if (now == 0 || wait == 0)
        return kTASStatusMalformed;
    current = now(context) & 0xffffffffUL;
    deadline &= 0xffffffffUL;
    required = usec / 1000UL + ((usec % 1000UL) != 0UL ? 1UL : 0UL);
    remaining = (deadline - current) & 0xffffffffUL;
    if (remaining >= 0x80000000UL || required > remaining)
        return kTASStatusTimeout;
    wait(context, usec);
    after = now(context) & 0xffffffffUL;
    remaining = (deadline - after) & 0xffffffffUL;
    return remaining >= 0x80000000UL ? kTASStatusTimeout : kTASStatusOK;
}

TASStatus TASRuntimeFailMuteOutputs(const TASMachineConfig *config,
    void *context,
    TASStatus (*writeGPIO)(void *, const TASGPIODescriptor *, int))
{
    TASStatus first;
    TASStatus status;
    unsigned long route;
    if (config == 0 || writeGPIO == 0)
        return kTASStatusMalformed;
    first = writeGPIO(context, &config->amplifierMute, 1);
    for (route = 0UL; route < kTASRouteCount; ++route) {
        if (!config->routes[route].present)
            continue;
        status = writeGPIO(context, &config->routes[route].mute, 1);
        if (first == kTASStatusOK && status != kTASStatusOK)
            first = status;
    }
    return first;
}

TASStatus TASRuntimeAttenuationToCodec(int attenuation,
    unsigned long *coefficient)
{
    if (coefficient == 0)
        return kTASStatusMalformed;
    if (attenuation < -84)
        attenuation = -84;
    else if (attenuation > 0)
        attenuation = 0;
    *coefficient = (unsigned long)(attenuation + 84) * 0x010000UL / 84UL;
    return kTASStatusOK;
}

TASStatus TASRuntimeApplyANDedReset(const TASMachineConfig *config,
    int asserted, void *context,
    TASStatus (*writeGPIO)(void *, const TASGPIODescriptor *, int))
{
    const TASGPIODescriptor *first;
    const TASGPIODescriptor *second;
    TASStatus firstStatus;
    TASStatus secondStatus;
    if (config == 0 || writeGPIO == 0 ||
        (config->quirks & kTASQuirkANDedReset) == 0UL ||
        !config->routes[kTASRouteHeadphone].present)
        return kTASStatusMalformed;
    first = asserted ? &config->amplifierMute :
        &config->routes[kTASRouteHeadphone].mute;
    second = asserted ? &config->routes[kTASRouteHeadphone].mute :
        &config->amplifierMute;
    firstStatus = writeGPIO(context, first, asserted);
    secondStatus = writeGPIO(context, second, asserted);
    return firstStatus != kTASStatusOK ? firstStatus : secondStatus;
}

TASStatus TASRuntimeGainToCodec(int gain, unsigned long *coefficient)
{
    if (coefficient == 0)
        return kTASStatusMalformed;
    if (gain < 0)
        gain = 0;
    else if (gain > 32768)
        gain = 32768;
    *coefficient = 0x010000UL +
        (unsigned long)gain * 0x010000UL / 32768UL;
    return kTASStatusOK;
}
