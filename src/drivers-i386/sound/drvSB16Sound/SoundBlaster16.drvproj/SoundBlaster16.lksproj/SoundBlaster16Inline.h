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
 * Shadow registers for mixer settings, one variable per channel.
 */
static unsigned int volMasterLeft =             24;
static unsigned int volMasterRight =            24;
static unsigned int volVoiceLeft =              21;
static unsigned int volVoiceRight =             21;
static unsigned int volLineLeft =               16;
static unsigned int volLineRight =              16;
static unsigned int volPCSpeaker =              2;
static unsigned int volMic =                    21;
static unsigned int trebleLeft =                8;
static unsigned int trebleRight =               8;
static unsigned int bassLeft =                  9;
static unsigned int bassRight =                 9;
static unsigned int volMIDILeft =               0;
static unsigned int volMIDIRight =              0;
static unsigned int volCDLeft =                 21;
static unsigned int volCDRight =                21;

/*
 * Last stage (output) gain controls (0-3 for SB16)
 */
static unsigned int lastStageGainInputLeft =    2;
static unsigned int lastStageGainInputRight =   2;
static unsigned int lastStageGainOutputLeft =   2;
static unsigned int lastStageGainOutputRight =  2;

/*
 * Mixer routing switches
 */
static unsigned int outputMixerSwitch =         6;
static unsigned int inputMixerSwitchLeft =      21;
static unsigned int inputMixerSwitchRight =     11;

/*
 * DMA command variables
 */
static unsigned char sbStartDMACommand =        0;
static unsigned char sbStartDMAMode =           0;

/*
 * Interrupt status tracking
 */
static unsigned char interruptStatus;

/*
 * Buffer counter
 */
static unsigned int sbBufferCounter;

#define MAX_WAIT_FOR_DATA_AVAILABLE             10000
#define SB16_WAIT_DELAY                         10

/*
 * Wait for DSP to be ready for reading.  On timeout the DSP is pulsed and the
 * failure logged; there is no status to return, callers carry on regardless.
 */
static  __inline__
void
dspReadWait(void)
{
    int     i;

    for (i = 0; i < MAX_WAIT_FOR_DATA_AVAILABLE; i++) {
        if (inb(sbDataAvailableStatusReg) & SB16_DSP_BUSY_BIT)
            break;                      /* MSB == 1 before reading */
        IODelay(SB16_WAIT_DELAY);
    }

    if (i == MAX_WAIT_FOR_DATA_AVAILABLE) {
        outbV(sbResetReg, 0x01);
        IODelay(SB16_ADDRESS_WRITE_DELAY);
        outbV(sbResetReg, 0x00);
        IODelay(SB16_ADDRESS_WRITE_DELAY);
        IOLog("SoundBlaster16: DSP read error.\n");
    }
}

/*
 * Wait for DSP to be ready for writing
 */
static __inline__
void
dspWriteWait(void)
{
    int     i;

    for (i = 0; i < MAX_WAIT_FOR_DATA_AVAILABLE; i++) {
        if (!(inb(sbWriteBufferStatusReg) & SB16_DSP_BUSY_BIT))
            break;                      /* MSB == 0 before writing */
        IODelay(SB16_WAIT_DELAY);
    }

    if (i == MAX_WAIT_FOR_DATA_AVAILABLE) {
        outbV(sbResetReg, 0x01);
        IODelay(SB16_ADDRESS_WRITE_DELAY);
        outbV(sbResetReg, 0x00);
        IODelay(SB16_ADDRESS_WRITE_DELAY);
        IOLog("SoundBlaster16: DSP write error.\n");
    }
}

/*
 * Send command or data to DSP
 */
static __inline__
void
writeToDSP(unsigned int dataOrCommand)
{
    dspWriteWait();

    outbV(sbWriteDataOrCommandReg, dataOrCommand);
    IODelay(SB16_DATA_WRITE_DELAY);
}

/*
 * Read from DSP
 */
static __inline__
unsigned char
readFromDSP(void)
{
    unsigned char val;

    dspReadWait();

    val = inb(sbReadDataReg);
    IODelay(SB16_DATA_READ_DELAY);

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
 * Program every mixer register from its shadow variable.
 */
static __inline__
void
initMixerRegisters(void)
{
#ifdef DEBUG
    IOLog("SoundBlaster16: Initializing mixer registers.\n");
#endif DEBUG

    outbIXMixer(CT1745_MASTER_VOLUME_LEFT,  volMasterLeft << 3);
    outbIXMixer(CT1745_MASTER_VOLUME_RIGHT, volMasterRight << 3);
    outbIXMixer(CT1745_VOICE_VOLUME_LEFT,   volVoiceLeft << 3);
    outbIXMixer(CT1745_VOICE_VOLUME_RIGHT,  volVoiceRight << 3);
    outbIXMixer(CT1745_FM_VOLUME_LEFT,      volMIDILeft << 3);
    outbIXMixer(CT1745_FM_VOLUME_RIGHT,     volMIDIRight << 3);
    outbIXMixer(CT1745_CD_VOLUME_LEFT,      volCDLeft << 3);
    outbIXMixer(CT1745_CD_VOLUME_RIGHT,     volCDRight << 3);
    outbIXMixer(CT1745_LINE_VOLUME_LEFT,    volLineLeft << 3);
    outbIXMixer(CT1745_LINE_VOLUME_RIGHT,   volLineRight << 3);
    outbIXMixer(CT1745_MIC_VOLUME,          volMic << 3);
    outbIXMixer(MC16_PC_SPEAKER_VOLUME,     volPCSpeaker << 6);
    outbIXMixer(MC16_OUTPUT_CONTROL,        outputMixerSwitch);
    outbIXMixer(MC16_INPUT_CONTROL_LEFT,    inputMixerSwitchLeft);
    outbIXMixer(MC16_INPUT_CONTROL_RIGHT,   inputMixerSwitchRight);
    outbIXMixer(MC16_AGC,                   0);
    outbIXMixer(MC16_TREBLE_LEFT,           trebleLeft << 4);
    outbIXMixer(MC16_TREBLE_RIGHT,          trebleRight << 4);
    outbIXMixer(MC16_BASS_LEFT,             bassLeft << 4);
    outbIXMixer(MC16_BASS_RIGHT,            bassRight << 4);
    outbIXMixer(MC16_INPUT_GAIN_LEFT,       lastStageGainInputLeft << 6);
    outbIXMixer(MC16_INPUT_GAIN_RIGHT,      lastStageGainInputRight << 6);
    outbIXMixer(MC16_OUTPUT_GAIN_LEFT,      lastStageGainOutputLeft << 6);
    outbIXMixer(MC16_OUTPUT_GAIN_RIGHT,     lastStageGainOutputRight << 6);
}

/*
 * Send an invert-byte probe: the DSP answers with the one's complement of the
 * argument.  Both bytes go out behind a single write wait.
 */
static __inline__
void
writeInvertByte(unsigned int data)
{
    dspWriteWait();

    outbV(sbWriteDataOrCommandReg, DC16_INVERT_BYTE);
    IODelay(SB16_DATA_WRITE_DELAY);
    outbV(sbWriteDataOrCommandReg, data);
    IODelay(SB16_DATA_WRITE_DELAY);
}

/*
 * Full DSP reset and detection
 */
static __inline__
void
resetDSP(sb16CardParameters_t *cardType)
{
    unsigned char val;
    BOOL detected = NO;

    /* Assume no card present */
    cardType->version = SB16_NONE;
    cardType->majorVersion = 0;
    cardType->minorVersion = 0;

    /* Reset DSP */
    outbV(sbResetReg, 0x01);
    IODelay(SB16_ADDRESS_WRITE_DELAY);
    outbV(sbResetReg, 0x00);
    IODelay(SB16_ADDRESS_WRITE_DELAY);

    /* The reset response, then two invert-byte probes */
    if (readFromDSP() == 0xaa) {
        writeInvertByte(0x43);
        if (readFromDSP() == 0xbc) {
            writeInvertByte(0x94);
            if (readFromDSP() == 0x6b)
                detected = YES;
        }
    }

    if (!detected) {
        IOLog("SoundBlaster16: SoundBlaster not detected at address 0x%0x.\n",
              sbBaseRegisterAddress);
        return;
    }

    cardType->version = SB_8BIT;

    /* Get DSP version.  Both digits come back from one wait. */
    writeToDSP(DC16_GET_VERSION);

    cardType->majorVersion = readFromDSP() & 0x0f;

    val = inb(sbReadDataReg);
    IODelay(SB16_DATA_READ_DELAY);
    cardType->minorVersion = val & 0x0f;
}

/*
 * Reset mixer chip
 */
static __inline__
void
resetMixer(void)
{
    outbIXMixer(MC16_RESET, 0x00);
    IODelay(50);
}

/*
 * Write and read back the eleven CT1745 volume registers.  Only a card with a
 * CT1745 mixer answers, which is what distinguishes an SB16 from an 8-bit card.
 */
static __inline__
BOOL
probeMixerRegisters(void)
{
    int             reg;
    unsigned char   testValue;
    unsigned char   val;

    for (reg = CT1745_MASTER_VOLUME_LEFT; reg <= CT1745_MIC_VOLUME; reg++) {
        testValue = (reg + 0xd5) << 3;

        outbIXMixer(reg, testValue);
        IODelay(SB16_WAIT_DELAY);

        outbV(sbMixerAddressReg, reg);
        IODelay(SB16_ADDRESS_WRITE_DELAY);
        val = inb(sbMixerDataReg);
        IODelay(SB16_DATA_WRITE_DELAY);

        if ((val & 0xf8) != testValue)
            return NO;
    }

    return YES;
}

/*
 * Initialize all hardware
 */
static __inline__
void
resetHardware(sb16CardParameters_t *cardType)
{
    resetDSP(cardType);

    if (cardType->version != SB16_NONE) {
        resetMixer();

        if (probeMixerRegisters()) {
            resetMixer();
            cardType->version = SB16_BASIC;
        }

        initMixerRegisters();
    }
}

/*
 * Stop DMA transfer - sends pause command and performs DSP reset
 */
static __inline__
void
stopDMATransfer(unsigned int encoding)
{
    dspWriteWait();

    /* The 16-bit pause stops an 8-bit encoding and vice versa */
    if (encoding == NX_SoundStreamDataEncoding_Linear8) {
        outbV(sbWriteDataOrCommandReg, DC16_PAUSE_16BIT_DMA);
        IODelay(SB16_DATA_WRITE_DELAY);
    } else {
        outbV(sbWriteDataOrCommandReg, DC16_PAUSE_8BIT_DMA);
        IODelay(SB16_DATA_WRITE_DELAY);
    }

    /* Perform full DSP reset to ensure clean stop */
    outbV(sbResetReg, 0x01);
    IODelay(SB16_ADDRESS_WRITE_DELAY);
    outbV(sbResetReg, 0x00);
    IODelay(SB16_ADDRESS_WRITE_DELAY);

    /* Verify the 0xAA response */
    if (readFromDSP() != 0xaa) {
        IOLog("SoundBlaster16: Can not reset DSP.\n");
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
        (ackReg = sbAck8bitInterrupt, (interruptStatus & IRQ_STATUS_8BIT))) {
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
