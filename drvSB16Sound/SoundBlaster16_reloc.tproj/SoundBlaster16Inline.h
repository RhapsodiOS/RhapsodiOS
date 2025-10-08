/*
 * Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved.
 * Copyright (c) 2025 RhapsodiOS Project. All rights reserved.
 *
 * HISTORY
 * 6-Oct-25    Created for Sound Blaster 16, AWE32, AWE64 support
 *             Based on SoundBlaster8 driver by Rakesh Dubey
 */

/*
 * Base address - determined at runtime
 */
static unsigned int sb16BaseRegisterAddress = 0;

/*
 * Register addresses - determined at runtime
 */
static unsigned int sb16ResetReg = 0;
static unsigned int sb16ReadDataReg = 0;
static unsigned int sb16WriteDataOrCommandReg = 0;
static unsigned int sb16WriteBufferStatusReg = 0;
static unsigned int sb16DataAvailableStatusReg = 0;
static unsigned int sb16Interrupt16BitAckReg = 0;

static __inline__
void
assignDSPRegAddresses(void)
{
    sb16ResetReg =
        (sb16BaseRegisterAddress + SB16_DSP_RESET_OFFSET);
    sb16ReadDataReg =
        (sb16BaseRegisterAddress + SB16_DSP_READ_DATA_OFFSET);
    sb16WriteDataOrCommandReg =
        (sb16BaseRegisterAddress + SB16_DSP_WRITE_DATA_OR_COMMAND_OFFSET);
    sb16WriteBufferStatusReg =
        (sb16BaseRegisterAddress + SB16_DSP_WRITE_BUFFER_STATUS_OFFSET);
    sb16DataAvailableStatusReg =
        (sb16BaseRegisterAddress + SB16_DSP_DATA_AVAILABLE_STATUS_OFFSET);
    sb16Interrupt16BitAckReg =
        (sb16BaseRegisterAddress + SB16_DSP_16BIT_ACK_OFFSET);
}

/*
 * Debug output wrapper
 */
static __inline__
void
outbV(unsigned int address, unsigned int data)
{
#ifdef DEBUG
    IOLog("SoundBlaster16: Writing %x at address %x\n", data, address);
#endif DEBUG
    outb(address, data);
}

/*
 * Mixer register addresses
 */
static unsigned int sb16MixerAddressReg = 0;
static unsigned int sb16MixerDataReg = 0;

static __inline__
void
assignMixerRegAddresses(void)
{
    sb16MixerAddressReg =
        (sb16BaseRegisterAddress + SB16_MIXER_ADDRESS_OFFSET);
    sb16MixerDataReg =
        (sb16BaseRegisterAddress + SB16_MIXER_DATA_OFFSET);
}

/*
 * Shadow registers for mixer settings
 */
static sb16MonoMixerRegister_t volMaster =      {0};
static sb16MonoMixerRegister_t volVoice =       {0};
static sb16MonoMixerRegister_t volFM =          {0};
static sb16MonoMixerRegister_t volCD =          {0};
static sb16MonoMixerRegister_t volLine =        {0};
static unsigned char volMic =                   0;
static unsigned char inputControlLeft =         0;
static unsigned char inputControlRight =        0;
static unsigned char inputGainLeft =            0;
static unsigned char inputGainRight =           0;
static unsigned char outputGainLeft =           0;
static unsigned char outputGainRight =          0;

#define MAX_WAIT_FOR_DATA_AVAILABLE             2000
#define SB16_WAIT_DELAY                         10
#define SB16_RESET_DELAY                        100

/*
 * Wait for DSP to be ready for reading
 */
static  __inline__
BOOL
dspReadWait(void)
{
    int     i;
    unsigned int val;

    for (i = 0; i < MAX_WAIT_FOR_DATA_AVAILABLE; i++) {
        IODelay(SB16_WAIT_DELAY);
        val = inb(sb16DataAvailableStatusReg);
        if (val & 0x080)   /* MSB == 1 before reading */
            return YES;
    }

    /* Reset DSP to recover */
    outbV(sb16ResetReg, 0x01);
    IODelay(SB16_ADDRESS_WRITE_DELAY);
    outbV(sb16ResetReg, 0x00);
    IODelay(SB16_ADDRESS_WRITE_DELAY);
    IODelay(SB16_RESET_DELAY);

#ifdef DEBUG
    IOLog("SoundBlaster16: DSP not ready for reading!\n");
#endif DEBUG

    return NO;
}

/*
 * Wait for DSP to be ready for writing
 */
static __inline__
BOOL
dspWriteWait(void)
{
    int     i;
    unsigned int val;

    for (i = 0; i < MAX_WAIT_FOR_DATA_AVAILABLE; i++) {
        IODelay(SB16_WAIT_DELAY);
        val = inb(sb16WriteBufferStatusReg);
        if (!(val & 0x080))     /* MSB == 0 before writing */
            return YES;
    }

    /* Reset DSP */
    outbV(sb16ResetReg, 0x01);
    IODelay(SB16_ADDRESS_WRITE_DELAY);
    outbV(sb16ResetReg, 0x00);
    IODelay(SB16_ADDRESS_WRITE_DELAY);
    IODelay(SB16_RESET_DELAY);

#ifdef DEBUG
    IOLog("SoundBlaster16: DSP not ready for writing!\n");
#endif DEBUG

    return NO;
}

/*
 * Send command or data to DSP
 */
static
BOOL
writeToDSP(unsigned int dataOrCommand)
{
    if (!dspWriteWait())
        return NO;

    outbV(sb16WriteDataOrCommandReg, dataOrCommand);
    IODelay(SB16_DATA_WRITE_DELAY);

#ifdef DEBUG
    //IOLog("SoundBlaster16: Wrote DSP command %x\n", dataOrCommand);
#endif DEBUG

    return YES;
}

/*
 * Read from DSP
 */
static
unsigned int
readFromDSP(void)
{
    unsigned int val;

    if (!dspReadWait())
        return 0xff;

    val = inb(sb16ReadDataReg);
    IODelay(SB16_DATA_READ_DELAY);

#ifdef DEBUG
    //IOLog("SoundBlaster16: read from DSP %x\n", val);
#endif DEBUG

    return val;
}

/*
 * Read from mixer register
 */
static __inline__
unsigned int
inbIXMixer(unsigned int address)
{
    unsigned int val = 0xff;

    outbV(sb16MixerAddressReg, address);
    IODelay(SB16_ADDRESS_WRITE_DELAY);
    val = inb(sb16MixerDataReg);

#ifdef DEBUG
    //IOLog("SoundBlaster16: Mixer address %x. Read %x\n", address, val);
#endif DEBUG
    return val;
}

/*
 * Write to mixer register
 */
static  __inline__
void
outbIXMixer(unsigned int address, unsigned int val)
{
    outbV(sb16MixerAddressReg, address);
    IODelay(SB16_ADDRESS_WRITE_DELAY);
    outbV(sb16MixerDataReg, val);
    IODelay(SB16_DATA_WRITE_DELAY);

#ifdef DEBUG
    //IOLog("SoundBlaster16: Mixer address %x. Wrote %x\n", address, val);
#endif DEBUG
}

/*
 * Initialize mixer registers to default values
 */
static __inline__
void
initMixerRegisters(void)
{
#ifdef DEBUG
    IOLog("SoundBlaster16: Initializing mixer registers.\n");
#endif DEBUG

    /* Reset mixer */
    outbIXMixer(MC16_RESET, 0x00);
    IODelay(100);

    /* Set master volume (0-31 per channel) */
    volMaster.reg.left = 24;
    volMaster.reg.right = 24;
    outbIXMixer(MC16_MASTER_VOLUME, volMaster.data);

    /* Set voice volume */
    volVoice.reg.left = 24;
    volVoice.reg.right = 24;
    outbIXMixer(MC16_VOICE_VOLUME, volVoice.data);

    /* Set FM volume to low default */
    volFM.reg.left = 0;
    volFM.reg.right = 0;
    outbIXMixer(MC16_FM_VOLUME, volFM.data);

    /* Set CD volume to low default */
    volCD.reg.left = 0;
    volCD.reg.right = 0;
    outbIXMixer(MC16_CD_VOLUME, volCD.data);

    /* Set Line volume */
    volLine.reg.left = 0;
    volLine.reg.right = 0;
    outbIXMixer(MC16_LINE_VOLUME, volLine.data);

    /* Set microphone volume (0-7) */
    volMic = 5;
    outbIXMixer(MC16_MIC_VOLUME, volMic);

    /* Set input controls - microphone by default */
    inputControlLeft = INPUT_SOURCE_MIC;
    inputControlRight = INPUT_SOURCE_MIC;
    outbIXMixer(MC16_INPUT_CONTROL_LEFT, inputControlLeft);
    outbIXMixer(MC16_INPUT_CONTROL_RIGHT, inputControlRight);

    /* Set input gain */
    inputGainLeft = 0;
    inputGainRight = 0;
    outbIXMixer(MC16_INPUT_GAIN_LEFT, inputGainLeft);
    outbIXMixer(MC16_INPUT_GAIN_RIGHT, inputGainRight);

    /* Set output gain */
    outputGainLeft = 0;
    outputGainRight = 0;
    outbIXMixer(MC16_OUTPUT_GAIN_LEFT, outputGainLeft);
    outbIXMixer(MC16_OUTPUT_GAIN_RIGHT, outputGainRight);
}

/*
 * Set input source
 */
static __inline__
void
setInputLevel(unsigned int level)
{
    if (level == LINE_LEVEL_INPUT)      {
        inputControlLeft = INPUT_SOURCE_LINE_LEFT;
        inputControlRight = INPUT_SOURCE_LINE_RIGHT;
    } else if (level == CD_LEVEL_INPUT) {
        inputControlLeft = INPUT_SOURCE_CD_LEFT;
        inputControlRight = INPUT_SOURCE_CD_RIGHT;
    } else {
        inputControlLeft = INPUT_SOURCE_MIC;
        inputControlRight = INPUT_SOURCE_MIC;
    }

    outbIXMixer(MC16_INPUT_CONTROL_LEFT, inputControlLeft);
    outbIXMixer(MC16_INPUT_CONTROL_RIGHT, inputControlRight);
}

/*
 * Mute audio output
 */
static __inline__
void
muteOutput(void)
{
    outbIXMixer(MC16_MASTER_VOLUME, 0);
    outbIXMixer(MC16_VOICE_VOLUME, 0);
}

/*
 * Unmute audio output (restore previous values)
 */
static __inline__
void
unMuteOutput(void)
{
    outbIXMixer(MC16_MASTER_VOLUME, volMaster.data);
    outbIXMixer(MC16_VOICE_VOLUME, volVoice.data);
}

/*
 * Quick DSP reset
 */
static __inline__
void
resetDSPQuick(void)
{
    outbV(sb16ResetReg, 0x01);
    IODelay(SB16_ADDRESS_WRITE_DELAY);
    outbV(sb16ResetReg, 0x00);
    IODelay(SB16_ADDRESS_WRITE_DELAY);
    IODelay(SB16_RESET_DELAY);

    /* Wait for 0xAA response */
    if (dspReadWait()) {
        unsigned int val = readFromDSP();
        if (val != 0xaa) {
            IOLog("SoundBlaster16: DSP reset failed, got %x instead of 0xaa\n", val);
        }
    }
}

/*
 * Full DSP reset and detection
 */
static __inline__
void
resetDSP(sb16CardParameters_t *cardType)
{
    unsigned int val;

    /* Assume no card present */
    cardType->version = SB16_NONE;
    cardType->name = "";
    cardType->majorVersion = 0;
    cardType->minorVersion = 0;
    cardType->mixerPresent = NO;
    cardType->supports16Bit = NO;
    cardType->supportsAWE = NO;

    /* Reset DSP */
    outbV(sb16ResetReg, 0x01);
    IODelay(SB16_ADDRESS_WRITE_DELAY);
    outbV(sb16ResetReg, 0x00);
    IODelay(SB16_ADDRESS_WRITE_DELAY);
    IODelay(SB16_RESET_DELAY);

    /* Read response */
    if (!dspReadWait()) {
#ifdef DEBUG
        IOLog("SoundBlaster16: No response from DSP during reset\n");
#endif DEBUG
        return;
    }

    val = readFromDSP();
    if (val != 0xaa) {
#ifdef DEBUG
        IOLog("SoundBlaster16: Wrong reset response %x, expected 0xaa\n", val);
#endif DEBUG
        return;
    }

#ifdef DEBUG
    IOLog("SoundBlaster16: DSP detected.\n");
#endif DEBUG

    IOSleep(1);

    /* Get DSP version */
    writeToDSP(DC16_GET_VERSION);

    if (!dspReadWait())
        return;

    cardType->majorVersion = readFromDSP();

    if (!dspReadWait())
        return;

    cardType->minorVersion = readFromDSP();

#ifdef DEBUG
    IOLog("SoundBlaster16: DSP version %d.%d\n",
          cardType->majorVersion, cardType->minorVersion);
#endif DEBUG

    /* Determine card type based on version */
    if (cardType->majorVersion >= 4) {
        cardType->supports16Bit = YES;
        cardType->mixerPresent = YES;

        if (cardType->majorVersion == 4) {
            cardType->version = SB16_BASIC;
            cardType->name = "Sound Blaster 16";
        } else if (cardType->majorVersion == 5) {
            cardType->version = SB16_VIBRA;
            cardType->name = "Sound Blaster 16 Vibra";
        }

        /* Check for AWE capabilities by reading mixer */
        /* AWE cards have additional registers */
        val = inbIXMixer(0x20);  /* AWE identification register */
        if ((val & 0xf0) == 0xf0) {
            cardType->supportsAWE = YES;
            if (cardType->majorVersion >= 8) {
                cardType->version = SB16_AWE64;
                cardType->name = "Sound Blaster AWE64";
            } else {
                cardType->version = SB16_AWE32;
                cardType->name = "Sound Blaster AWE32";
            }
        }
    }
}

/*
 * Reset mixer chip
 */
static __inline__
void
resetMixer(void)
{
    outbIXMixer(MC16_RESET, 0x00);
    IODelay(100);
}

/*
 * Initialize all hardware
 */
static __inline__
void
resetHardware(sb16CardParameters_t *cardType)
{
    resetDSP(cardType);
    resetMixer();
    if (cardType->mixerPresent)
        initMixerRegisters();
}

/*
 * Set input gain (0-3 for SB16)
 */
static  __inline__
void
setInputGain(unsigned int channel, unsigned int gain)
{
    if (channel == LEFT_CHANNEL) {
        inputGainLeft = gain & 0x03;
        outbIXMixer(MC16_INPUT_GAIN_LEFT, inputGainLeft);
    } else {
        inputGainRight = gain & 0x03;
        outbIXMixer(MC16_INPUT_GAIN_RIGHT, inputGainRight);
    }

#ifdef DEBUG
    IOLog("SoundBlaster16: set input gain channel %d to %d\n", channel, gain);
#endif DEBUG
}

/*
 * Set output attenuation (master volume)
 */
static  __inline__
void
setOutputAttenuation(unsigned int channel, unsigned int attenuation)
{
    if (channel == LEFT_CHANNEL) {
        volMaster.reg.left = attenuation & 0x1f;
        volVoice.reg.left = attenuation & 0x1f;
    } else {
        volMaster.reg.right = attenuation & 0x1f;
        volVoice.reg.right = attenuation & 0x1f;
    }

    outbIXMixer(MC16_MASTER_VOLUME, volMaster.data);
    outbIXMixer(MC16_VOICE_VOLUME, volVoice.data);

#ifdef DEBUG
    IOLog("SoundBlaster16: set output attenuation channel %d to %d\n",
          channel, attenuation);
#endif DEBUG
}

/*
 * Enable/disable audio output
 */
static __inline__
void
enableAudioOutput(BOOL enable)
{
    (enable) ? unMuteOutput() : muteOutput();
    (enable) ? writeToDSP(DC16_TURN_ON_SPEAKER) :
               writeToDSP(DC16_TURN_OFF_SPEAKER);
}

/*
 * Set DMA buffer size
 */
static  __inline__
void
setSampleBufferCounter(unsigned int count, BOOL is16Bit)
{
    /* For 16-bit, count is in samples, need to multiply by 2 for bytes */
    if (is16Bit)
        count = (count * 2) - 1;
    else
        count -= 1;

    writeToDSP(count & 0xff);
    writeToDSP((count >> 8) & 0xff);

#ifdef DEBUG
    //IOLog("SoundBlaster16: buffer counter set to %d\n", count);
#endif DEBUG
}

/*
 * Set sample rate for output
 */
static __inline__
void
setCodecSamplingRateOutput(unsigned int rate)
{
    /* Clamp to valid range */
    if (rate < SB16_MIN_SAMPLE_RATE_16BIT)
        rate = SB16_MIN_SAMPLE_RATE_16BIT;
    else if (rate > SB16_MAX_SAMPLE_RATE_16BIT)
        rate = SB16_MAX_SAMPLE_RATE_16BIT;

    writeToDSP(DC16_SET_SAMPLE_RATE_OUTPUT);
    writeToDSP((rate >> 8) & 0xff);
    writeToDSP(rate & 0xff);

#ifdef DEBUG
    IOLog("SoundBlaster16: output sample rate set to %d Hz\n", rate);
#endif DEBUG
}

/*
 * Set sample rate for input
 */
static __inline__
void
setCodecSamplingRateInput(unsigned int rate)
{
    /* Clamp to valid range */
    if (rate < SB16_MIN_SAMPLE_RATE_16BIT)
        rate = SB16_MIN_SAMPLE_RATE_16BIT;
    else if (rate > SB16_MAX_SAMPLE_RATE_16BIT)
        rate = SB16_MAX_SAMPLE_RATE_16BIT;

    writeToDSP(DC16_SET_SAMPLE_RATE_INPUT);
    writeToDSP((rate >> 8) & 0xff);
    writeToDSP(rate & 0xff);

#ifdef DEBUG
    IOLog("SoundBlaster16: input sample rate set to %d Hz\n", rate);
#endif DEBUG
}

/*
 * Start DMA transfer
 */
static __inline__
void
startDMA(unsigned int direction, BOOL is16Bit, BOOL isStereo, unsigned int count)
{
    unsigned int command;
    unsigned int mode = DMA_MODE_FIFO | DMA_MODE_AUTO_INIT;

    if (isStereo)
        mode |= DMA_MODE_STEREO;

    if (is16Bit) {
        mode |= DMA_MODE_SIGNED;  /* 16-bit is always signed */
        command = (direction == DMA_DIRECTION_IN) ?
                  DC16_START_16BIT_DMA_ADC : DC16_START_16BIT_DMA_DAC;
    } else {
        command = (direction == DMA_DIRECTION_IN) ?
                  DC16_START_8BIT_DMA_ADC : DC16_START_8BIT_DMA_DAC;
    }

    /* Send DMA command with mode */
    writeToDSP(command | mode);

    /* Send buffer size */
    setSampleBufferCounter(count, is16Bit);

#ifdef DEBUG
    IOLog("SoundBlaster16: started %s %d-bit %s DMA\n",
          direction == DMA_DIRECTION_IN ? "input" : "output",
          is16Bit ? 16 : 8,
          isStereo ? "stereo" : "mono");
#endif DEBUG
}

/*
 * Stop DMA transfer
 */
static __inline__
void
stopDMA(BOOL is16Bit)
{
    if (is16Bit) {
        writeToDSP(DC16_PAUSE_16BIT_DMA);
        writeToDSP(DC16_EXIT_16BIT_AUTO_DMA);
    } else {
        writeToDSP(DC16_PAUSE_8BIT_DMA);
        writeToDSP(DC16_EXIT_8BIT_AUTO_DMA);
    }

    /* Quick reset to ensure DMA is stopped */
    resetDSPQuick();
}

/*
 * Enable codec interrupts (handled by mixer/DSP)
 */
static __inline__
void
enableCodecInterrupts(void)
{
    /* SB16 interrupts are enabled by starting DMA */
}

/*
 * Disable codec interrupts
 */
static __inline__
void
disableCodecInterrupts(void)
{
    /* Interrupts disabled by stopping DMA */
}

/*
 * Validate DMA channel selection
 */
static  __inline__
BOOL
checkSelectedDMAAndIRQ(unsigned int dma8Channel, unsigned int dma16Channel,
                      unsigned int irq)
{
    BOOL status = YES;

    /* Check 8-bit DMA channel */
    if ((dma8Channel != 0) && (dma8Channel != 1) && (dma8Channel != 3)) {
        IOLog("SoundBlaster16: 8-bit DMA channel is %d.\n", dma8Channel);
        IOLog("SoundBlaster16: 8-bit DMA channel must be 0, 1, or 3.\n");
        status = NO;
    }

    /* Check 16-bit DMA channel */
    if ((dma16Channel != 5) && (dma16Channel != 6) && (dma16Channel != 7)) {
        IOLog("SoundBlaster16: 16-bit DMA channel is %d.\n", dma16Channel);
        IOLog("SoundBlaster16: 16-bit DMA channel must be 5, 6, or 7.\n");
        status = NO;
    }

    /* 8-bit and 16-bit channels must be different */
    if (dma8Channel == dma16Channel) {
        IOLog("SoundBlaster16: 8-bit and 16-bit DMA channels must be different.\n");
        status = NO;
    }

    /* Check IRQ */
    if ((irq != 2) && (irq != 5) && (irq != 7) && (irq != 10)) {
        IOLog("SoundBlaster16: IRQ is %d.\n", irq);
        IOLog("SoundBlaster16: IRQ must be 2, 5, 7, or 10.\n");
        status = NO;
    }

    return status;
}
