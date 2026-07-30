#include "TASRuntime.h"

#include <string.h>

#define TAS_STAGE_BIT(stage) (1UL << (unsigned long)(stage))

static TASStatus service_detect(TASRuntime *, int, unsigned long);

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
        ops->executeAction != 0 && ops->applyControls != 0 &&
        ops->applyOutputRoute != 0 &&
        ops->sampleDetects != 0 && ops->now != 0 &&
        ops->signalDeferred != 0 &&
        ops->failMute != 0;
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

void TASRuntimeUnwind(TASRuntime *runtime)
{
    long stage;
    if (runtime == 0 || !runtime->initialized)
        return;
    for (stage = (long)kTASRuntimeStageCount - 1L; stage >= 0L; --stage) {
        if ((runtime->acquiredMask & TAS_STAGE_BIT(stage)) != 0UL) {
            runtime->ops.release(runtime->ops.context,
                (TASRuntimeStage)stage);
            runtime->acquiredMask &= ~TAS_STAGE_BIT(stage);
        }
    }
    TASSharedClockInit(&runtime->clock);
    memset(runtime->rings, 0, sizeof(runtime->rings));
}

TASStatus TASRuntimeReset(TASRuntime *runtime, unsigned long deadline)
{
    TASRuntimeStage stage;
    TASStatus status;
    (void)deadline;
    if (runtime == 0 || !runtime->initialized ||
        runtime->acquiredMask != 0UL)
        return kTASStatusConflict;
    runtime->operationDeadline = deadline;
    for (stage = kTASRuntimePlatformReady;
        stage < kTASRuntimeStageCount; stage = (TASRuntimeStage)(stage + 1)) {
        status = runtime->ops.acquire(runtime->ops.context, stage,
            &runtime->config);
        if (status != kTASStatusOK) {
            if ((runtime->acquiredMask &
                TAS_STAGE_BIT(kTASRuntimeSafeOutputs)) != 0UL)
                runtime->ops.failMute(runtime->ops.context);
            TASRuntimeUnwind(runtime);
            return status;
        }
        runtime->acquiredMask |= TAS_STAGE_BIT(stage);
    }
    status = service_detect(runtime, 1, deadline);
    if (status == kTASStatusOK)
        status = service_detect(runtime, 0, deadline);
    if (status == kTASStatusOK)
        status = service_detect(runtime, 0, deadline);
    if (status != kTASStatusOK || runtime->audio.debouncePending ||
        !runtime->audio.routeValid) {
        runtime->ops.failMute(runtime->ops.context);
        TASRuntimeUnwind(runtime);
        return status == kTASStatusOK ? kTASStatusUnresolved : status;
    }
    return kTASStatusOK;
}

TASStatus TASRuntimeStartStream(TASRuntime *runtime,
    TASStreamDirection direction, const void *buffer, unsigned long bytes,
    unsigned long period, unsigned long rate, unsigned long deadline)
{
    TASStatus status;
    TASI2SClock clock;
    PPCDBDMARing *ring;
    if (runtime == 0 || buffer == 0 || bytes == 0UL || period == 0UL ||
        direction > kTASStreamInput || runtime->audio.startsBlocked)
        return kTASStatusConflict;
    status = TASAcquireI2SStream(&runtime->config, &runtime->clock,
        direction, rate, &clock);
    if (status != kTASStatusOK)
        return status;
    ring = &runtime->rings[(unsigned long)direction];
    status = runtime->ops.prepareDMA(runtime->ops.context, direction,
        buffer, bytes, period, ring);
    if (status == kTASStatusOK)
        status = runtime->ops.startDMA(runtime->ops.context, direction,
            ring, deadline);
    if (status != kTASStatusOK) {
        (void)TASReleaseI2SStream(&runtime->clock, direction);
        runtime->ops.failMute(runtime->ops.context);
        return status;
    }
    runtime->audio.streamsRunning = 1;
    return kTASStatusOK;
}

TASStatus TASRuntimeStopStream(TASRuntime *runtime,
    TASStreamDirection direction, unsigned long deadline)
{
    TASStatus status;
    if (runtime == 0 || direction > kTASStreamInput)
        return kTASStatusMalformed;
    status = runtime->ops.stopResetDMA(runtime->ops.context, direction,
        &runtime->rings[(unsigned long)direction], deadline);
    if (status != kTASStatusOK) {
        runtime->dmaFaultMask |= 1UL << (unsigned long)direction;
        runtime->ops.failMute(runtime->ops.context);
        return status;
    }
    status = TASReleaseI2SStream(&runtime->clock, direction);
    runtime->audio.streamsRunning = runtime->clock.activeMask != 0UL;
    return status;
}

void TASRuntimeRecordISR(TASRuntime *runtime, TASRuntimeIRQ irq)
{
    if (runtime == 0 || !runtime->initialized)
        return;
    if (irq == kTASRuntimeIRQDetect)
        ++runtime->detectISREdges;
    runtime->pendingIRQs |= (unsigned long)irq;
    runtime->ops.signalDeferred(runtime->ops.context);
}

TASStatus TASRuntimeRecordDMAISR(TASRuntime *runtime,
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
    runtime->ops.signalDeferred(runtime->ops.context);
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
            runtime->ops.failMute(runtime->ops.context);
            return status;
        }
    }
    runtime->ops.signalDeferred(runtime->ops.context);
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
    now = runtime->ops.now(runtime->ops.context);
    if (newEdge) {
        status = TASAudioRecordDetectISR(&runtime->audio,
            runtime->audio.desiredDetects,
            &generation);
        if (status != kTASStatusOK)
            return status;
        if (now > ~0UL - TAS_AUDIO_DEBOUNCE_CONFIRM_MS)
            return kTASStatusOverflow;
        status = TASAudioBuildDebounceSchedule(&runtime->audio, generation,
            now + TAS_AUDIO_DEBOUNCE_CONFIRM_MS, &plan);
        if (status != kTASStatusOK)
            return status;
        return schedule_detect(runtime, &plan);
    }
    if (!runtime->audio.debouncePending)
        return kTASStatusOK;
    generation = runtime->audio.detectGeneration;
    status = TASAudioPrepareDebounceSample(&runtime->audio, generation, now,
        &plan, &sample);
    if (status == kTASStatusTimeout)
        return status;
    if (status != kTASStatusOK)
        return status;
    status = runtime->ops.executeAction(runtime->ops.context,
        &plan.actions[0]);
    if (status != kTASStatusOK) {
        runtime->ops.failMute(runtime->ops.context);
        return status;
    }
    detects = runtime->ops.sampleDetects(runtime->ops.context);
    status = TASAudioApplyDetectSample(&runtime->audio, &sample, detects,
        now, &plan, &route);
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
    unsigned long pending;
    if (runtime == 0 || notifyInput == 0 || notifyOutput == 0)
        return kTASStatusMalformed;
    *notifyInput = 0;
    *notifyOutput = 0;
    result = kTASStatusOK;
    pending = runtime->pendingIRQs;
    runtime->pendingIRQs = 0UL;
    if ((pending & kTASRuntimeIRQOutput) != 0UL) {
        status = runtime->ops.serviceDMA(runtime->ops.context,
            kTASStreamOutput, &runtime->rings[0], &completed);
        if (status != kTASStatusOK) {
            runtime->dmaFaultMask |= kTASStreamMaskOutput;
            result = status;
        } else
            *notifyOutput = completed != 0UL;
    }
    if ((pending & kTASRuntimeIRQInput) != 0UL) {
        status = runtime->ops.serviceDMA(runtime->ops.context,
            kTASStreamInput, &runtime->rings[1], &completed);
        if (status != kTASStatusOK) {
            runtime->dmaFaultMask |= kTASStreamMaskInput;
            if (result == kTASStatusOK)
                result = status;
        } else
            *notifyInput = completed != 0UL;
    }
    if ((pending & kTASRuntimeIRQDetect) != 0UL ||
        runtime->audio.debouncePending) {
        status = service_detect(runtime,
            (pending & kTASRuntimeIRQDetect) != 0UL, deadline);
        if (status != kTASStatusOK && result == kTASStatusOK)
            result = status;
    }
    return result;
}

TASStatus TASRuntimeSetControls(TASRuntime *runtime,
    const TASAudioDesiredControls *desired, unsigned long deadline)
{
    TASStatus status;
    TASAudioState candidate;
    if (runtime == 0 || desired == 0)
        return kTASStatusMalformed;
    candidate = runtime->audio;
    status = TASAudioSetDesiredControls(&candidate, desired);
    if (status != kTASStatusOK)
        return status;
    status = runtime->ops.applyControls(runtime->ops.context, desired,
        deadline);
    if (status != kTASStatusOK) {
        runtime->ops.failMute(runtime->ops.context);
        runtime->audio.outputsMuted = 1;
        return status;
    }
    runtime->audio = candidate;
    return kTASStatusOK;
}

static TASStatus execute_plan(TASRuntime *runtime,
    TASAudioActionPlan *plan, TASAudioToken *token, unsigned long deadline)
{
    TASStatus status;
    TASAudioActionPlan rollbackPlan;
    TASAudioToken rollback;
    unsigned long index;
    unsigned long rollbackDeadline;
    unsigned long detectEdges;
    unsigned long generation;
    detectEdges = runtime->detectISREdges;
    for (index = 0UL; index < plan->count; ++index) {
        status = TASAudioAuthorizeAction(&runtime->audio, token, index);
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
        if (runtime->detectISREdges != detectEdges) {
            status = TASAudioRecordDetectISR(&runtime->audio,
                runtime->ops.sampleDetects(runtime->ops.context),
                &generation);
            detectEdges = runtime->detectISREdges;
            if (status != kTASStatusOK)
                break;
        }
        status = TASAudioCompleteAction(&runtime->audio, token, index);
        if (status != kTASStatusOK)
            break;
    }
    if (index == plan->count)
        return TASAudioCommitTransition(&runtime->audio, token);
    runtime->ops.failMute(runtime->ops.context);
    rollbackDeadline = runtime->ops.now(runtime->ops.context) + 100UL;
    if (rollbackDeadline < 100UL)
        rollbackDeadline = ~0UL;
    if (TASAudioFailTransition(&runtime->audio, token, rollbackDeadline,
        &rollbackPlan, &rollback) == kTASStatusOK) {
        for (index = 0UL; index < rollbackPlan.count; ++index) {
            if (TASAudioAuthorizeAction(&runtime->audio, &rollback, index) !=
                kTASStatusOK)
                break;
            rollbackPlan.actions[index].deadline = rollbackDeadline;
            if (runtime->ops.executeAction(runtime->ops.context,
                &rollbackPlan.actions[index]) != kTASStatusOK)
                break;
            if (TASAudioCompleteAction(&runtime->audio, &rollback, index) !=
                kTASStatusOK)
                break;
        }
        if (index == rollbackPlan.count)
            (void)TASAudioCommitRollback(&runtime->audio, &rollback);
        else
            (void)TASAudioAbortRollback(&runtime->audio, &rollback);
    }
    return status;
}

TASStatus TASRuntimeSetPower(TASRuntime *runtime, TASPowerState power,
    unsigned long deadline)
{
    TASAudioActionPlan plan;
    TASAudioToken token;
    TASStatus status;
    if (runtime == 0)
        return kTASStatusMalformed;
    status = TASAudioPreparePower(&runtime->audio, power, deadline, &plan,
        &token);
    if (status != kTASStatusOK)
        return status;
    status = execute_plan(runtime, &plan, &token, deadline);
    if (status == kTASStatusOK && runtime->audio.debouncePending &&
        runtime->audio.powerState == kTASPowerWaking)
        TASRuntimeRecordISR(runtime, kTASRuntimeIRQDetect);
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
    if (now == 0 || wait == 0 || deadline == 0UL)
        return kTASStatusMalformed;
    current = now(context);
    required = usec / 1000UL + ((usec % 1000UL) != 0UL ? 1UL : 0UL);
    if (current >= deadline || required > deadline - current)
        return kTASStatusTimeout;
    wait(context, usec);
    return now(context) > deadline ? kTASStatusTimeout : kTASStatusOK;
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
