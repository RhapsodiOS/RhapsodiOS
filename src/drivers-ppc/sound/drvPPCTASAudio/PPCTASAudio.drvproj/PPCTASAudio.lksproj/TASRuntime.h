#ifndef TAS_RUNTIME_H
#define TAS_RUNTIME_H

#include "PPCDBDMAAudio.h"
#include "TASCodec.h"

typedef enum {
    kTASRuntimePlatformReady = 0,
    kTASRuntimeMapI2S,
    kTASRuntimeMapOutputDBDMA,
    kTASRuntimeMapInputDBDMA,
    kTASRuntimeInstallOutputIRQ,
    kTASRuntimeInstallInputIRQ,
    kTASRuntimeInstallDetectIRQs,
    kTASRuntimeEnableI2S,
    kTASRuntimeSafeOutputs,
    kTASRuntimeInitializeCodec,
    kTASRuntimeAllocateOutputRing,
    kTASRuntimeAllocateInputRing,
    kTASRuntimeCreateAudioChannels,
    kTASRuntimeInitialRoute,
    kTASRuntimeStageCount
} TASRuntimeStage;

typedef enum {
    kTASRuntimeIRQOutput = 1,
    kTASRuntimeIRQInput = 2,
    kTASRuntimeIRQDetect = 4
} TASRuntimeIRQ;

typedef struct {
    void *context;
    TASCodecCallbacks codecCallbacks;
    TASStatus (*acquire)(void *, TASRuntimeStage,
        const TASMachineConfig *);
    void (*release)(void *, TASRuntimeStage);
    TASStatus (*prepareDMA)(void *, TASStreamDirection, const void *,
        unsigned long, unsigned long, PPCDBDMARing *);
    TASStatus (*startDMA)(void *, TASStreamDirection, PPCDBDMARing *,
        unsigned long);
    TASStatus (*stopResetDMA)(void *, TASStreamDirection, PPCDBDMARing *,
        unsigned long);
    TASStatus (*serviceDMA)(void *, TASStreamDirection, PPCDBDMARing *,
        unsigned long *);
    TASStatus (*ackDMAInterrupt)(void *, TASStreamDirection);
    TASStatus (*ackDetectInterrupt)(void *);
    void (*lockInterrupt)(void *);
    void (*unlockInterrupt)(void *);
    void (*lockOperation)(void *);
    void (*unlockOperation)(void *);
    void (*lockState)(void *);
    void (*unlockState)(void *);
    TASStatus (*executeAction)(void *, const TASAudioAction *);
    TASStatus (*applyControls)(void *, const TASAudioDesiredControls *,
        unsigned long);
    TASStatus (*applyOutputRoute)(void *, unsigned long, unsigned long);
    TASStatus (*sampleDetects)(void *, unsigned long *);
    unsigned long (*now)(void *);
    void (*signalDeferred)(void *);
    TASStatus (*failMuteOutputs)(void *);
} TASRuntimeOps;

typedef struct {
    TASMachineConfig config;
    TASCodec codec;
    TASSharedClock clock;
    TASAudioState audio;
    PPCDBDMARing rings[2];
    TASRuntimeOps ops;
    unsigned long acquiredMask;
    unsigned long pendingIRQs;
    unsigned long detectISREdges;
    unsigned long dmaFaultMask;
    unsigned long operationDeadline;
    int detectFaultPending;
    int initialized;
} TASRuntime;

TASStatus TASRuntimeProbe(const TASPropertyReader *, TASMachineConfig *);
TASStatus TASRuntimeInit(TASRuntime *, const TASMachineConfig *,
    const TASAudioDesiredControls *, const TASRuntimeOps *);
TASStatus TASRuntimeReset(TASRuntime *, unsigned long);
TASStatus TASRuntimeUnwind(TASRuntime *);
TASStatus TASRuntimeStartStream(TASRuntime *, TASStreamDirection,
    const void *, unsigned long, unsigned long, unsigned long,
    unsigned long);
TASStatus TASRuntimeStopStream(TASRuntime *, TASStreamDirection,
    unsigned long);
void TASRuntimeRecordISR(TASRuntime *, TASRuntimeIRQ);
TASStatus TASRuntimeRecordDMAISR(TASRuntime *, TASStreamDirection);
TASStatus TASRuntimeRecordDetectISR(TASRuntime *);
TASStatus TASRuntimeServiceDeferred(TASRuntime *, unsigned long, int *, int *);
TASStatus TASRuntimeSetControls(TASRuntime *,
    const TASAudioDesiredControls *, unsigned long);
TASStatus TASRuntimeSetPower(TASRuntime *, TASPowerState, unsigned long);
TASStatus TASRuntimeEncodeI2S(const TASI2SPlanStep *, unsigned long *,
    unsigned long *);
TASStatus TASRuntimeBoundedDelay(void *, unsigned long, unsigned long,
    unsigned long (*)(void *), void (*)(void *, unsigned long));
TASStatus TASRuntimeFailMuteOutputs(const TASMachineConfig *, void *,
    TASStatus (*)(void *, const TASGPIODescriptor *, int));
TASStatus TASRuntimeApplyANDedReset(const TASMachineConfig *, int, void *,
    TASStatus (*)(void *, const TASGPIODescriptor *, int));
TASStatus TASRuntimeAttenuationToCodec(int, unsigned long *);
TASStatus TASRuntimeGainToCodec(int, unsigned long *);

#endif
