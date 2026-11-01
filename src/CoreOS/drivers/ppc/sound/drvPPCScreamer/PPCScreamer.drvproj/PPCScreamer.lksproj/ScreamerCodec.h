/* Copyright (c) 2026 RhapsodiOS Project. */
#ifndef PPC_SCREAMER_CODEC_H
#define PPC_SCREAMER_CODEC_H
#include "ScreamerCore.h"
typedef struct {
    void *context;
    ScreamerStatus (*readLE32)(void *,unsigned int,unsigned int *);
    ScreamerStatus (*writeLE32)(void *,unsigned int,unsigned int);
    void (*barrier)(void *);
    unsigned long (*nowMS)(void *);
    void (*sleepMS)(void *,unsigned long);
} ScreamerCodecOps;
typedef struct {
    ScreamerCodecOps ops;
    unsigned int shadow[8],validMask,soundControl;
} ScreamerCodec;
ScreamerStatus ScreamerCodecWrite(ScreamerCodec *,unsigned int,unsigned int,unsigned long);
ScreamerStatus ScreamerCodecRead(ScreamerCodec *,unsigned int,unsigned int *,unsigned long);
ScreamerStatus ScreamerCodecInitialize(ScreamerCodec *,const ScreamerMachineConfig *,unsigned long);
ScreamerStatus ScreamerCodecSetPower(ScreamerCodec *,ScreamerPowerState,unsigned long);
ScreamerStatus ScreamerCodecSetRate(ScreamerCodec *,const ScreamerMachineConfig *,unsigned int,unsigned long);
ScreamerStatus ScreamerCodecDelay(ScreamerCodec *,unsigned long,unsigned long);
#endif
