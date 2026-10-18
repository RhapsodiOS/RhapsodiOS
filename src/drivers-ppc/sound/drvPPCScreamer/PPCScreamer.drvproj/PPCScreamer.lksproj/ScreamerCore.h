/* Copyright (c) 2026 RhapsodiOS Project. */
#ifndef PPC_SCREAMER_CORE_H
#define PPC_SCREAMER_CORE_H
#include "ScreamerIdentity.h"
typedef char ScreamerWordMustBe32Bits[(sizeof(unsigned int)==4)?1:-1];
typedef enum { kScreamerOK, kScreamerInvalid, kScreamerUnsupported,
    kScreamerUnresolved, kScreamerBusy, kScreamerTimeout, kScreamerIOError,
    kScreamerFault, kScreamerClosed } ScreamerStatus;
typedef enum { kScreamerPowerReady, kScreamerPowerStandby,
    kScreamerPowerSuspended, kScreamerPowerOff } ScreamerPowerState;
typedef enum { kScreamerStreamInput, kScreamerStreamOutput } ScreamerStream;
typedef enum { kScreamerInputMic, kScreamerInputLine, kScreamerInputCD,
    kScreamerInputCount } ScreamerInput;
typedef struct { unsigned int address, length; } ScreamerRange;
typedef struct {
    ScreamerRange ranges[3];
    unsigned int rangeCount, interrupts[3], interruptCount,interruptXor;
} ScreamerDeliveredResources;
typedef struct {
    void *context;
    unsigned int nodeCount;
    int (*getProperty)(void *, unsigned int, const char *, ScreamerBytes *);
    unsigned int (*getParent)(void *, unsigned int);
    const ScreamerDeliveredResources *delivered;
} ScreamerPropertyReader;
typedef struct {
    unsigned int headphoneMask, headphoneMatch, anySense;
    unsigned int speakerPort, headphonePort, speakerKind, speakerParam;
    unsigned int powerKind,initOutput;
    unsigned int inputBits[kScreamerInputCount];
    unsigned int frontMask,phaseInversion,monoMic;
    unsigned int micMuxMask,micMuxValue;
    unsigned int muxKind,muxInputs,source;
} ScreamerProfile;
typedef struct {
    ScreamerRange ranges[3];
    unsigned int interrupts[3], localInterrupts[3], controllerBase;
    unsigned int rates[8], rateCount,platformFamily;
    char machine[32];
    ScreamerProfile profile;
} ScreamerMachineConfig;
typedef struct {
    unsigned int attenuation[2], gain[2];
    ScreamerInput input;
    int userMuted;
} ScreamerControls;
ScreamerStatus ScreamerDiscover(const ScreamerPropertyReader *, unsigned int,
    ScreamerMachineConfig *);
ScreamerStatus ScreamerRateCode(const ScreamerMachineConfig *, unsigned int,
    unsigned int *);
unsigned int ScreamerQuantize(unsigned int, unsigned int);
unsigned int ScreamerBE32(const unsigned char *);
#endif
