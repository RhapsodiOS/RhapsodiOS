#include "TASCodec.h"

#include <string.h>

static unsigned long tas3004_width(unsigned char reg)
{
    if (reg == 0x01 || reg == 0x05 || reg == 0x06 ||
        reg == 0x40 || reg == 0x43) return 1UL;
    if (reg == 0x02 || reg == 0x04) return 6UL;
    if (reg == 0x07 || reg == 0x08) return 9UL;
    if ((reg >= 0x0a && reg <= 0x10) ||
        (reg >= 0x13 && reg <= 0x19) || reg == 0x21 || reg == 0x22)
        return 15UL;
    if (reg == 0x23 || reg == 0x24) return 3UL;
    return 0UL;
}

static TASStatus write_neutral(TASCodec *codec, unsigned char reg,
    unsigned long deadline)
{
    unsigned char bytes[15];
    memset(bytes, 0, sizeof(bytes));
    bytes[0] = 0x10;
    return TASCodecWrite(codec, reg, bytes, 15UL, deadline);
}

static TASStatus tas3004_state(TASCodec *codec, unsigned long deadline)
{
    unsigned char drc[6];
    unsigned char zero6[6];
    unsigned char zero3[3];
    unsigned char zero1[1];
    unsigned char mixer[9];
    unsigned char allPass[1];
    TASStatus status;
    memset(drc, 0, sizeof(drc)); drc[0] = 1;
    memset(zero6, 0, sizeof(zero6));
    memset(zero3, 0, sizeof(zero3));
    zero1[0] = 0;
    memset(mixer, 0, sizeof(mixer)); mixer[0] = 1;
    allPass[0] = 2;
    status = TASCodecWrite(codec, 0x02, drc, 6UL, deadline);
    if (status != kTASStatusOK) return status;
    status = TASCodecWrite(codec, 0x04, zero6, 6UL, deadline);
    if (status != kTASStatusOK) return status;
    status = TASCodecWrite(codec, 0x05, zero1, 1UL, deadline);
    if (status != kTASStatusOK) return status;
    status = TASCodecWrite(codec, 0x06, zero1, 1UL, deadline);
    if (status != kTASStatusOK) return status;
    status = TASCodecWrite(codec, 0x07, mixer, 9UL, deadline);
    if (status != kTASStatusOK) return status;
    status = TASCodecWrite(codec, 0x08, mixer, 9UL, deadline);
    if (status != kTASStatusOK) return status;
    status = TASCodecWrite(codec, 0x23, zero3, 3UL, deadline);
    if (status != kTASStatusOK) return status;
    status = TASCodecWrite(codec, 0x24, zero3, 3UL, deadline);
    if (status != kTASStatusOK) return status;
    status = TASCodecWrite(codec, 0x40, zero1, 1UL, deadline);
    if (status != kTASStatusOK) return status;
    return TASCodecWrite(codec, 0x43, allPass, 1UL, deadline);
}

static TASStatus shadow_state(TASCodec *codec, unsigned long deadline)
{
    static const unsigned char regs[] = {
        0x02,0x04,0x05,0x06,0x07,0x08,0x23,0x24,0x40,0x43
    };
    unsigned long index;
    unsigned char reg;
    TASStatus status;
    for (index = 0; index < sizeof(regs); ++index) {
        reg = regs[index];
        status = TASCodecWrite(codec, reg, codec->shadow[reg],
            codec->shadowLength[reg], deadline);
        if (status != kTASStatusOK) return status;
    }
    return kTASStatusOK;
}

static TASStatus tas3004_program(TASCodec *codec, unsigned long deadline,
    int reset)
{
    unsigned char mcr[1];
    unsigned char reg;
    TASStatus status;
    if (reset) {
        status = TASCodecDelay(codec, 5000UL); if (status != kTASStatusOK) return status;
        status = TASCodecReset(codec, 1); if (status != kTASStatusOK) return status;
        status = TASCodecDelay(codec, 20000UL); if (status != kTASStatusOK) return status;
        status = TASCodecReset(codec, 0); if (status != kTASStatusOK) return status;
        status = TASCodecDelay(codec, 10000UL); if (status != kTASStatusOK) return status;
    }
    mcr[0] = 0xea;
    status = TASCodecWrite(codec, 0x01, mcr, 1UL, deadline);
    if (status != kTASStatusOK) return status;
    for (reg = 0x0a; reg <= 0x10; ++reg) {
        status = reset ? write_neutral(codec, reg, deadline) :
            TASCodecWrite(codec, reg, codec->shadow[reg], 15UL, deadline);
        if (status != kTASStatusOK) return status;
    }
    status = reset ? write_neutral(codec, 0x21, deadline) :
        TASCodecWrite(codec, 0x21, codec->shadow[0x21], 15UL, deadline);
    if (status != kTASStatusOK) return status;
    for (reg = 0x13; reg <= 0x19; ++reg) {
        status = reset ? write_neutral(codec, reg, deadline) :
            TASCodecWrite(codec, reg, codec->shadow[reg], 15UL, deadline);
        if (status != kTASStatusOK) return status;
    }
    status = reset ? write_neutral(codec, 0x22, deadline) :
        TASCodecWrite(codec, 0x22, codec->shadow[0x22], 15UL, deadline);
    if (status != kTASStatusOK) return status;
    mcr[0] = 0x6a;
    status = TASCodecWrite(codec, 0x01, mcr, 1UL, deadline);
    if (status != kTASStatusOK) return status;
    status = reset ? tas3004_state(codec, deadline) :
        shadow_state(codec, deadline);
    if (status != kTASStatusOK) return status;
    return TASCodecWrite(codec, 0x01, mcr, 1UL, deadline);
}

static TASStatus tas3004_init(TASCodec *codec, unsigned long deadline)
{
    return tas3004_program(codec, deadline, 1);
}

static TASStatus tas3004_restore(TASCodec *codec, unsigned long deadline)
{
    return tas3004_program(codec, deadline, 0);
}

static TASStatus tas3004_mix(TASCodec *codec, TASCodecInputSource source,
    unsigned long gain, unsigned long deadline)
{
    unsigned char mixer[9];
    unsigned long offset;
    TASStatus status;
    memset(mixer, 0, sizeof(mixer));
    offset = source == kTASCodecInputDigital1 ? 0UL :
        (source == kTASCodecInputDigital2 ? 3UL : 6UL);
    TASCodecEncode24(gain, mixer + offset);
    status = TASCodecWrite(codec, 0x07, mixer, 9UL, deadline);
    if (status != kTASStatusOK) return status;
    return TASCodecWrite(codec, 0x08, mixer, 9UL, deadline);
}

static TASStatus tas3004_gain(TASCodec *codec, unsigned long gain,
    unsigned long deadline)
{
    return tas3004_mix(codec, codec->inputSource, gain, deadline);
}

static TASStatus tas3004_source(TASCodec *codec, TASCodecInputSource source,
    unsigned long deadline)
{
    return tas3004_mix(codec, source, codec->inputGain, deadline);
}

static const TASCodecOps tas3004Ops = {
    "TAS3004", 1, 29UL, tas3004_width, tas3004_init, tas3004_restore,
    tas3004_gain, tas3004_source
};

const TASCodecOps *TAS3004CodecOps(void)
{
    return &tas3004Ops;
}
