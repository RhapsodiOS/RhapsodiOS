/* Copyright (c) 2026 RhapsodiOS Project. */
#ifndef PPC_SCREAMER_RUNTIME_H
#define PPC_SCREAMER_RUNTIME_H
#include "ScreamerCodec.h"
#include "PPCDBDMAAudio.h"
typedef struct {
    void *context;
    ScreamerCodecOps codec;
    ScreamerStatus (*setPlatform)(void *,int);
    PPCDBDMAOps dma[2];
    PPCDBDMAStorage storage[2];
} ScreamerRuntimeOps;
typedef struct {
    void *buffer;
    unsigned long bytes,period,remainder;
    unsigned int rate,running,needsQuiesce;
} ScreamerStreamState;
typedef struct {
    ScreamerMachineConfig config;
    ScreamerRuntimeOps ops;
    ScreamerCodec codec;
    PPCDBDMARing rings[2];
    ScreamerStreamState streams[2];
    ScreamerControls desired,applied;
    ScreamerPowerState power;
    unsigned int initialized,faulted,closing,clockRate;
    unsigned long generation;
    unsigned long jackDeadline;
    unsigned int headphone,routeKnown,routePending,pendingHeadphone;
    unsigned int jackCandidate,jackCandidateValid;
} ScreamerRuntime;
ScreamerStatus ScreamerRuntimeInitialize(ScreamerRuntime *,const ScreamerMachineConfig *,const ScreamerRuntimeOps *,unsigned long);
ScreamerStatus ScreamerStart(ScreamerRuntime *,ScreamerStream,void *,unsigned long,unsigned long,unsigned int,unsigned long);
ScreamerStatus ScreamerStop(ScreamerRuntime *,ScreamerStream,unsigned long);
ScreamerStatus ScreamerCaptureCompletions(ScreamerRuntime *,ScreamerStream,unsigned int *);
ScreamerStatus ScreamerApplyControls(ScreamerRuntime *,const ScreamerControls *,unsigned long);
ScreamerStatus ScreamerObserveJack(ScreamerRuntime *,unsigned int,unsigned long,unsigned long);
ScreamerStatus ScreamerServiceDeferred(ScreamerRuntime *,unsigned long,unsigned int [2]);
/* Caller holds the short interrupt lock. This path never waits or touches codec commands. */
ScreamerStatus ScreamerAcknowledgeInterrupt(const ScreamerRuntimeOps *,unsigned int,unsigned int *);
#endif
