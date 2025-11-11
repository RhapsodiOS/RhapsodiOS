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
static unsigned int sbBaseRegisterAddress = 0;

/*
 * DSP Register addresses - determined at runtime
 */
static unsigned int sbResetReg = 0;
static unsigned int sbReadDataReg = 0;
static unsigned int sbWriteDataOrCommandReg = 0;
static unsigned int sbWriteBufferStatusReg = 0;
static unsigned int sbDataAvailableStatusReg = 0;
static unsigned int sbAck8bitInterrupt = 0;
static unsigned int sbAck16bitInterrupt = 0;

static __inline__
void
assignDSPRegAddresses(void)
{
    sbResetReg =
        (sbBaseRegisterAddress + SB16_DSP_RESET_OFFSET);
    sbReadDataReg =
        (sbBaseRegisterAddress + SB16_DSP_READ_DATA_OFFSET);
    sbWriteDataOrCommandReg =
        (sbBaseRegisterAddress + SB16_DSP_WRITE_DATA_OR_COMMAND_OFFSET);
    sbWriteBufferStatusReg =
        (sbBaseRegisterAddress + SB16_DSP_WRITE_BUFFER_STATUS_OFFSET);
    sbDataAvailableStatusReg =
        (sbBaseRegisterAddress + SB16_DSP_DATA_AVAILABLE_STATUS_OFFSET);
    sbAck8bitInterrupt =
        (sbBaseRegisterAddress + SB16_DSP_DATA_AVAILABLE_STATUS_OFFSET);
    sbAck16bitInterrupt =
        (sbBaseRegisterAddress + SB16_DSP_16BIT_ACK_OFFSET);
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
static unsigned int sbMixerAddressReg = 0;
static unsigned int sbMixerDataReg = 0;

static __inline__
void
assignMixerRegAddresses(void)
{
    sbMixerAddressReg =
        (sbBaseRegisterAddress + SB16_MIXER_ADDRESS_OFFSET);
    sbMixerDataReg =
        (sbBaseRegisterAddress + SB16_MIXER_DATA_OFFSET);
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

/*
 * Interrupt status tracking
 */
static unsigned char interruptStatus =          0;
static unsigned int interruptCount =            0;

/*
 * Last stage (output) gain controls (0-3 for SB16)
 */
static unsigned char lastStageGainInputLeft =   0;
static unsigned char lastStageGainInputRight =  0;
static unsigned char lastStageGainOutputLeft =  0;
static unsigned char lastStageGainOutputRight = 0;

/*
 * Buffer counter and DMA command variables
 */
static unsigned int sbBufferCounter =           0;
static unsigned char sbStartDMACommand =        0;
static unsigned char sbStartDMAMode =           0;

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
        val = inb(sbDataAvailableStatusReg);
        if (val & SB16_DSP_BUSY_BIT)   /* MSB == 1 before reading */
            return YES;
    }

    /* Reset DSP to recover */
    outbV(sbResetReg, 0x01);
    IODelay(SB16_ADDRESS_WRITE_DELAY);
    outbV(sbResetReg, 0x00);
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
        val = inb(sbWriteBufferStatusReg);
        if (!(val & SB16_DSP_BUSY_BIT))     /* MSB == 0 before writing */
            return YES;
    }

    /* Reset DSP */
    outbV(sbResetReg, 0x01);
    IODelay(SB16_ADDRESS_WRITE_DELAY);
    outbV(sbResetReg, 0x00);
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

    outbV(sbWriteDataOrCommandReg, dataOrCommand);
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

    val = inb(sbReadDataReg);
    IODelay(SB16_DATA_READ_DELAY);

#ifdef DEBUG
    //IOLog("SoundBlaster16: read from DSP %x\n", val);
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
    outbV(sbMixerAddressReg, address);
    IODelay(SB16_ADDRESS_WRITE_DELAY);
    outbV(sbMixerDataReg, val);
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
 * Quick DSP reset
 */
static __inline__
void
resetDSPQuick(void)
{
    outbV(sbResetReg, 0x01);
    IODelay(SB16_ADDRESS_WRITE_DELAY);
    outbV(sbResetReg, 0x00);
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
    outbV(sbResetReg, 0x01);
    IODelay(SB16_ADDRESS_WRITE_DELAY);
    outbV(sbResetReg, 0x00);
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
        cardType->name = "Sound Blaster 16";

        if (cardType->majorVersion == 4) {
            cardType->version = SB16_BASIC;
        } else if (cardType->majorVersion >= 5) {
            cardType->version = SB16_VIBRA;
        }
    } else if (cardType->majorVersion == 3) {
        /* DSP 3.x is 8-bit only (SBPro, etc.) */
        cardType->version = SB_8BIT;
        cardType->name = "Sound Blaster Pro";
        cardType->supports16Bit = NO;
        cardType->mixerPresent = YES;
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
 * Stop DMA transfer - sends pause command and performs DSP reset
 */
static __inline__
void
stopDMATransfer(BOOL is16Bit)
{
    unsigned char pauseCommand;

    /* Send appropriate pause command based on bit depth */
    if (is16Bit) {
        pauseCommand = DC16_PAUSE_16BIT_DMA;
    } else {
        pauseCommand = DC16_PAUSE_8BIT_DMA;
    }
    writeToDSP(pauseCommand);

    /* Perform full DSP reset to ensure clean stop */
    outbV(sbResetReg, 0x01);
    IODelay(SB16_ADDRESS_WRITE_DELAY);
    outbV(sbResetReg, 0x00);
    IODelay(SB16_ADDRESS_WRITE_DELAY);

    /* Wait for and verify 0xAA response */
    if (dspReadWait()) {
        unsigned int response = readFromDSP();
        if (response != 0xaa) {
            IOLog("SoundBlaster16: Can not reset DSP.\n");
        }
    }
}

/*
 * Clear and acknowledge interrupts
 * Reads the IRQ status register to determine which interrupt fired
 * and acknowledges only the appropriate one.
 */
static __inline__
void
clearInterrupts(void)
{
    unsigned char status;
    unsigned int ackReg;

    /* Read interrupt status register from mixer */
    outbV(sbMixerAddressReg, MC16_IRQ_STATUS);

    /* Track interrupt count for statistics */
    interruptCount++;

    IODelay(15);

    /* Read the status byte */
    status = inb(sbMixerDataReg);
    IODelay(75);

    /* Store for debugging */
    interruptStatus = status;

    /* Determine which interrupt fired and acknowledge it
     * Check bit 2 for 16-bit interrupt, bit 1 for 8-bit interrupt
     */
    ackReg = sbAck16bitInterrupt;
    if ((status & IRQ_STATUS_16BIT) ||
        (ackReg = sbAck8bitInterrupt, (status & IRQ_STATUS_8BIT))) {
        /* Acknowledge the interrupt by reading the appropriate register */
        inb(ackReg);
    }
}

/*
 * Program the DMA Select register (0x81) with the active DMA channels
 */
static __inline__
void
programDMASelect(unsigned int dma8Channel, unsigned int dma16Channel)
{
    unsigned char dmaSelectBits = 0;

    /* Set 8-bit DMA channel bit */
    if (dma8Channel == 0) {
        dmaSelectBits = 0x01;
    } else if (dma8Channel == 1) {
        dmaSelectBits = 0x02;
    } else if (dma8Channel == 3) {
        dmaSelectBits = 0x08;
    }

    /* Set 16-bit DMA channel bit */
    if (dma16Channel == 5) {
        dmaSelectBits |= 0x20;
    } else if (dma16Channel == 6) {
        dmaSelectBits |= 0x40;
    } else if (dma16Channel == 7) {
        dmaSelectBits |= 0x80;
    }

    /* Write to mixer DMA select register */
    outbIXMixer(MC16_DMA_SELECT, dmaSelectBits);
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
