#include "TASCodec.h"

#include <string.h>

static unsigned long tas3001_width(unsigned char reg)
{
    if (reg == 0x01) return 1UL;
    if (reg == 0x02) return 2UL;
    if (reg == 0x04) return 6UL;
    if (reg == 0x05 || reg == 0x06) return 1UL;
    if (reg == 0x07 || reg == 0x08) return 3UL;
    if ((reg >= 0x0a && reg <= 0x0f) ||
        (reg >= 0x13 && reg <= 0x18)) return 15UL;
    return 0UL;
}

unsigned long TASCodecRegisterWidth(const TASCodecOps *ops,
    unsigned char reg)
{
    if (ops == 0 || ops->registerWidth == 0)
        return 0UL;
    return ops->registerWidth(reg);
}

TASStatus TASCodecFailOperation(TASCodec *codec, TASStatus status)
{
    codec->hardwareValid = 0;
    codec->callbacks.failMute(codec->callbacks.context);
    return status;
}

TASStatus TASCodecBind(TASCodec *codec, const TASCodecOps *ops,
    const TASCodecCallbacks *callbacks)
{
    if (codec == 0 || ops == 0 || callbacks == 0 ||
        callbacks->writeRegister == 0 || callbacks->setReset == 0 ||
        callbacks->delayMicroseconds == 0 || callbacks->failMute == 0)
        return kTASStatusMalformed;
    memset(codec, 0, sizeof(*codec));
    codec->ops = ops;
    codec->callbacks = *callbacks;
    codec->inputGain = 0x010000UL;
    codec->inputSource = kTASCodecInputDigital1;
    return kTASStatusOK;
}

TASStatus TASCodecWrite(TASCodec *codec, unsigned char reg,
    const unsigned char *bytes, unsigned long length,
    unsigned long deadlineMilliseconds)
{
    unsigned long width;
    unsigned long written;
    TASStatus status;
    if (codec == 0 || codec->ops == 0 || bytes == 0 || length == 0UL)
        return kTASStatusMalformed;
    width = TASCodecRegisterWidth(codec->ops, reg);
    if (width == 0UL)
        return kTASStatusUnsupported;
    if (length != width || length > TAS_CODEC_REGISTER_BYTES)
        return kTASStatusMalformed;
    written = 0UL;
    status = codec->callbacks.writeRegister(codec->callbacks.context, reg,
        bytes, length, deadlineMilliseconds, &written);
    if (status != kTASStatusOK)
        return TASCodecFailOperation(codec, status);
    if (written != length)
        return TASCodecFailOperation(codec, kTASStatusUnresolved);
    memcpy(codec->shadow[reg], bytes, (size_t)length);
    codec->shadowLength[reg] = length;
    return kTASStatusOK;
}

TASStatus TASCodecReset(TASCodec *codec, int asserted)
{
    TASStatus status;
    status = codec->callbacks.setReset(codec->callbacks.context, asserted);
    if (status != kTASStatusOK)
        return TASCodecFailOperation(codec, status);
    return kTASStatusOK;
}

TASStatus TASCodecDelay(TASCodec *codec, unsigned long microseconds)
{
    TASStatus status;
    status = codec->callbacks.delayMicroseconds(codec->callbacks.context,
        microseconds);
    if (status != kTASStatusOK)
        return TASCodecFailOperation(codec, status);
    return kTASStatusOK;
}

void TASCodecEncode24(unsigned long value, unsigned char *bytes)
{
    bytes[0] = (unsigned char)(value >> 16);
    bytes[1] = (unsigned char)(value >> 8);
    bytes[2] = (unsigned char)value;
}

TASStatus TASCodecInitialize(TASCodec *codec, int clocksRunning,
    unsigned long deadlineMilliseconds)
{
    TASStatus status;
    if (codec == 0 || codec->ops == 0 ||
        (clocksRunning != 0 && clocksRunning != 1) ||
        deadlineMilliseconds == 0UL)
        return kTASStatusMalformed;
    if (!clocksRunning)
        return kTASStatusMalformed;
    codec->hardwareValid = 0;
    codec->shadowComplete = 0;
    status = codec->ops->initialize(codec, deadlineMilliseconds);
    if (status == kTASStatusOK) {
        codec->shadowComplete = 1;
        codec->hardwareValid = 1;
    }
    return status;
}

TASStatus TASCodecRestore(TASCodec *codec, unsigned long deadlineMilliseconds)
{
    TASStatus status;
    if (codec == 0 || codec->ops == 0 || !codec->shadowComplete ||
        deadlineMilliseconds == 0UL)
        return kTASStatusMalformed;
    codec->hardwareValid = 0;
    status = codec->ops->restore(codec, deadlineMilliseconds);
    if (status == kTASStatusOK)
        codec->hardwareValid = 1;
    return status;
}

TASStatus TASCodecSetVolume(TASCodec *codec, unsigned long left,
    unsigned long right, unsigned long deadlineMilliseconds)
{
    unsigned char bytes[6];
    if (left > 0xffffffUL || right > 0xffffffUL)
        return kTASStatusMalformed;
    TASCodecEncode24(left, bytes);
    TASCodecEncode24(right, bytes + 3);
    return TASCodecWrite(codec, 0x04, bytes, 6UL, deadlineMilliseconds);
}

TASStatus TASCodecSetMute(TASCodec *codec, int muted,
    unsigned long deadlineMilliseconds)
{
    if (muted != 0 && muted != 1)
        return kTASStatusMalformed;
    return TASCodecSetVolume(codec, muted ? 0UL : 0x010000UL,
        muted ? 0UL : 0x010000UL, deadlineMilliseconds);
}

TASStatus TASCodecSetInputGain(TASCodec *codec, unsigned long gain,
    unsigned long deadlineMilliseconds)
{
    TASStatus status;
    if (codec == 0 || codec->ops == 0 || gain > 0xffffffUL)
        return kTASStatusMalformed;
    status = codec->ops->setInputGain(codec, gain, deadlineMilliseconds);
    if (status == kTASStatusOK)
        codec->inputGain = gain;
    return status;
}

TASStatus TASCodecSetInputSource(TASCodec *codec, TASCodecInputSource source,
    unsigned long deadlineMilliseconds)
{
    TASStatus status;
    if (codec == 0 || codec->ops == 0 || source < kTASCodecInputDigital1 ||
        source > kTASCodecInputAnalog)
        return kTASStatusMalformed;
    status = codec->ops->setInputSource(codec, source,
        deadlineMilliseconds);
    if (status == kTASStatusOK)
        codec->inputSource = source;
    return status;
}

static TASStatus write_neutral(TASCodec *codec, unsigned char reg,
    unsigned long deadline)
{
    unsigned char bytes[15];
    memset(bytes, 0, sizeof(bytes));
    bytes[0] = 0x10;
    return TASCodecWrite(codec, reg, bytes, 15UL, deadline);
}

static TASStatus tas3001_state(TASCodec *codec, unsigned long deadline)
{
    unsigned char zero6[6];
    unsigned char zero2[2];
    unsigned char zero3[3];
    unsigned char zero1[1];
    unsigned char unity[3];
    TASStatus status;
    memset(zero6, 0, sizeof(zero6));
    memset(zero2, 0, sizeof(zero2));
    memset(zero3, 0, sizeof(zero3));
    zero1[0] = 0;
    unity[0] = 1; unity[1] = 0; unity[2] = 0;
    status = TASCodecWrite(codec, 0x02, zero2, 2UL, deadline);
    if (status != kTASStatusOK) return status;
    status = TASCodecWrite(codec, 0x04, zero6, 6UL, deadline);
    if (status != kTASStatusOK) return status;
    status = TASCodecWrite(codec, 0x05, zero1, 1UL, deadline);
    if (status != kTASStatusOK) return status;
    status = TASCodecWrite(codec, 0x06, zero1, 1UL, deadline);
    if (status != kTASStatusOK) return status;
    status = TASCodecWrite(codec, 0x07, unity, 3UL, deadline);
    if (status != kTASStatusOK) return status;
    return TASCodecWrite(codec, 0x08, zero3, 3UL, deadline);
}

static TASStatus tas3001_program(TASCodec *codec, unsigned long deadline,
    int reset)
{
    unsigned char mcr[1];
    unsigned char reg;
    TASStatus status;
    if (reset) {
        status = TASCodecReset(codec, 1); if (status != kTASStatusOK) return status;
        status = TASCodecDelay(codec, 2UL); if (status != kTASStatusOK) return status;
        status = TASCodecReset(codec, 0); if (status != kTASStatusOK) return status;
        status = TASCodecDelay(codec, 5000UL); if (status != kTASStatusOK) return status;
    }
    mcr[0] = 0xea;
    status = TASCodecWrite(codec, 0x01, mcr, 1UL, deadline);
    if (status != kTASStatusOK) return status;
    for (reg = 0x0a; reg <= 0x0f; ++reg) {
        status = reset ? write_neutral(codec, reg, deadline) :
            TASCodecWrite(codec, reg, codec->shadow[reg], 15UL, deadline);
        if (status != kTASStatusOK) return status;
    }
    for (reg = 0x13; reg <= 0x18; ++reg) {
        status = reset ? write_neutral(codec, reg, deadline) :
            TASCodecWrite(codec, reg, codec->shadow[reg], 15UL, deadline);
        if (status != kTASStatusOK) return status;
    }
    mcr[0] = 0x6a;
    status = TASCodecWrite(codec, 0x01, mcr, 1UL, deadline);
    if (status != kTASStatusOK) return status;
    if (reset)
        status = tas3001_state(codec, deadline);
    else {
        static const unsigned char regs[] = { 0x02,0x04,0x05,0x06,0x07,0x08 };
        unsigned long index;
        for (index = 0; index < sizeof(regs); ++index) {
            reg = regs[index];
            status = TASCodecWrite(codec, reg, codec->shadow[reg],
                codec->shadowLength[reg], deadline);
            if (status != kTASStatusOK) return status;
        }
    }
    if (status != kTASStatusOK) return status;
    return TASCodecWrite(codec, 0x01, mcr, 1UL, deadline);
}

static TASStatus tas3001_init(TASCodec *codec, unsigned long deadline)
{
    return tas3001_program(codec, deadline, 1);
}

static TASStatus tas3001_restore(TASCodec *codec, unsigned long deadline)
{
    return tas3001_program(codec, deadline, 0);
}

static TASStatus tas3001_gain(TASCodec *codec, unsigned long gain,
    unsigned long deadline)
{
    unsigned char bytes[3];
    unsigned char reg;
    if (codec->inputSource == kTASCodecInputAnalog)
        return kTASStatusUnsupported;
    TASCodecEncode24(gain, bytes);
    reg = codec->inputSource == kTASCodecInputDigital1 ? 0x07 : 0x08;
    return TASCodecWrite(codec, reg, bytes, 3UL, deadline);
}

static TASStatus tas3001_source(TASCodec *codec, TASCodecInputSource source,
    unsigned long deadline)
{
    unsigned char selected[3];
    unsigned char muted[3];
    TASStatus status;
    if (source == kTASCodecInputAnalog)
        return kTASStatusUnsupported;
    memset(muted, 0, sizeof(muted));
    TASCodecEncode24(codec->inputGain, selected);
    status = TASCodecWrite(codec, 0x07,
        source == kTASCodecInputDigital1 ? selected : muted, 3UL, deadline);
    if (status != kTASStatusOK) return status;
    return TASCodecWrite(codec, 0x08,
        source == kTASCodecInputDigital2 ? selected : muted, 3UL, deadline);
}

static const TASCodecOps tas3001Ops = {
    "TAS3001C", 1, 21UL, tas3001_width, tas3001_init, tas3001_restore,
    tas3001_gain, tas3001_source
};

const TASCodecOps *TAS3001CCodecOps(void)
{
    return &tas3001Ops;
}
