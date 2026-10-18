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
} ScreamerRuntime;
ScreamerStatus ScreamerRuntimeInitialize(ScreamerRuntime *,const ScreamerMachineConfig *,const ScreamerRuntimeOps *,unsigned long);
ScreamerStatus ScreamerStart(ScreamerRuntime *,ScreamerStream,void *,unsigned long,unsigned long,unsigned int,unsigned long);
ScreamerStatus ScreamerStop(ScreamerRuntime *,ScreamerStream,unsigned long);
ScreamerStatus ScreamerCaptureCompletions(ScreamerRuntime *,ScreamerStream,unsigned int *);
#endif
