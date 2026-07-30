#ifndef TAS_CODEC_H
#define TAS_CODEC_H

#include "TASCore.h"

#define TAS_CODEC_REGISTER_COUNT 0x44
#define TAS_CODEC_REGISTER_BYTES 15

typedef enum {
    kTASCodecInputDigital1 = 0,
    kTASCodecInputDigital2,
    kTASCodecInputAnalog
} TASCodecInputSource;

typedef struct {
    void *context;
    TASStatus (*writeRegister)(void *, unsigned char,
        const unsigned char *, unsigned long, unsigned long,
        unsigned long *);
    TASStatus (*setReset)(void *, int);
    TASStatus (*delayMicroseconds)(void *, unsigned long);
    void (*failMute)(void *);
} TASCodecCallbacks;

struct TASCodec;

typedef struct TASCodecOps {
    const char *name;
    int supportsDRC;
    unsigned long restoreCount;
    unsigned long (*registerWidth)(unsigned char);
    TASStatus (*initialize)(struct TASCodec *, unsigned long);
    TASStatus (*restore)(struct TASCodec *, unsigned long);
    TASStatus (*setInputGain)(struct TASCodec *, unsigned long,
        unsigned long);
    TASStatus (*setInputSource)(struct TASCodec *, TASCodecInputSource,
        unsigned long);
} TASCodecOps;

typedef struct TASCodec {
    const TASCodecOps *ops;
    TASCodecCallbacks callbacks;
    unsigned char shadow[TAS_CODEC_REGISTER_COUNT][TAS_CODEC_REGISTER_BYTES];
    unsigned long shadowLength[TAS_CODEC_REGISTER_COUNT];
    unsigned long inputGain;
    TASCodecInputSource inputSource;
    int hardwareValid;
    int shadowComplete;
} TASCodec;

const TASCodecOps *TAS3001CCodecOps(void);
const TASCodecOps *TAS3004CodecOps(void);
unsigned long TASCodecRegisterWidth(const TASCodecOps *, unsigned char);
TASStatus TASCodecBind(TASCodec *, const TASCodecOps *,
    const TASCodecCallbacks *);
TASStatus TASCodecWrite(TASCodec *, unsigned char, const unsigned char *,
    unsigned long, unsigned long);
TASStatus TASCodecTransportWrite(TASCodec *, unsigned char,
    const unsigned char *, unsigned long, unsigned long);
TASStatus TASCodecInitialize(TASCodec *, int, unsigned long);
TASStatus TASCodecRestore(TASCodec *, unsigned long);
TASStatus TASCodecSetVolume(TASCodec *, unsigned long, unsigned long,
    unsigned long);
TASStatus TASCodecSetMute(TASCodec *, int, unsigned long);
TASStatus TASCodecSetInputGain(TASCodec *, unsigned long, unsigned long);
TASStatus TASCodecSetInputSource(TASCodec *, TASCodecInputSource,
    unsigned long);

TASStatus TASCodecFailOperation(TASCodec *, TASStatus);
TASStatus TASCodecReset(TASCodec *, int);
TASStatus TASCodecDelay(TASCodec *, unsigned long);
void TASCodecEncode24(unsigned long, unsigned char *);

#endif
