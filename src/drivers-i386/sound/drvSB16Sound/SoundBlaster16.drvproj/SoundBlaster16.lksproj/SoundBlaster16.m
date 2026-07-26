/*
 * Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved.
 * Copyright (c) 2025 RhapsodiOS Project. All rights reserved.
 *
 * HISTORY
 * 6-Oct-25    Created for Sound Blaster 16, AWE32, AWE64 support
 *             Based on SoundBlaster8 driver by Rakesh Dubey
 */

#import "SoundBlaster16.h"
#import "SoundBlaster16Registers.h"

#import <driverkit/generalFuncs.h>

static const char codecDeviceName[] = "SoundBlaster16";
static const char codecDeviceKind[] = "Audio";

static  sb16CardParameters_t sb16CardType = {0}; // hardware type

/*
 * Include inline functions.
 */
#import "SoundBlaster16Inline.h"

@implementation SoundBlaster16

/*
 * Probe and initialize new instance
 */
+ (BOOL) probe:deviceDescription
{
    SoundBlaster16  *dev;
    IORange         *portRangeList;
    int             numPortRanges;
    unsigned int    baseAddress;

#ifdef DEBUG
    int             i;
#endif DEBUG

    dev = [self alloc];
    if (dev == nil)
        return NO;

    portRangeList = [deviceDescription portRangeList];
    numPortRanges = [deviceDescription numPortRanges];

    if (numPortRanges < 1)
        return NO;

#ifdef DEBUG
    for (i=0; i < numPortRanges; i++) {
        IOLog("SoundBlaster16: port %x %d\n",
                portRangeList[i].start, portRangeList[i].size);
    }
#endif DEBUG

    baseAddress = portRangeList[0].start;
#ifdef DEBUG
    IOLog("SoundBlaster16: Base address = 0x%x.\n", baseAddress);
#endif DEBUG

    /*
     * Check base address to verify if this is a legal address.
     * Matches original probe: implementation.
     */
    if ((baseAddress == SB16_BASE_ADDRESS_1) ||
        (baseAddress == SB16_BASE_ADDRESS_2) ||
        (baseAddress == SB16_BASE_ADDRESS_3) ||
        (baseAddress == SB16_BASE_ADDRESS_4))   {
        sbBaseRegisterAddress = baseAddress;
    } else {
        IOLog("SoundBlaster16: Invalid port address 0x%0x.\n", baseAddress);
        [dev free];
        return NO;
    }

    /*
     * Assign all DSP and Mixer registers their addresses.
     */
    assignDSPRegAddresses();
    assignMixerRegAddresses();

    return [dev initFromDeviceDescription:deviceDescription] != nil;
}

- (BOOL) initializeDMAChannels
{
    unsigned int dma8Channel;
    unsigned int dma16Channel = 99;     /* invalid until a 16-bit channel is set */
    unsigned int *channelList;
    IOReturn ioReturn;
    BOOL status;

    if ([[self deviceDescription] numChannels] == 1) {
        /* Single DMA channel - 8-bit only */
        dma8Channel = [[self deviceDescription] channel];
        dmaChannelsAvailable = 1;

        /* Validate 8-bit DMA channel */
        if ((dma8Channel < 2) || (dma8Channel == 3)) {
            status = YES;
        } else {
            IOLog("SoundBlaster16: 8-bit DMA channel is %d.\n", dma8Channel);
            IOLog("SoundBlaster16: 8-Bit DMA channel must be one of 0, 1 and 3.\n");
            status = NO;
        }

        if (!status)
            return NO;

    } else if ([[self deviceDescription] numChannels] == 2) {
        /* Dual DMA channels - 8-bit and 16-bit */
        channelList = (unsigned int *)[[self deviceDescription] channelList];
        dma8Channel = channelList[0];
        dma16Channel = channelList[1];
        dmaChannelsAvailable = 2;

        /* Validate 8-bit DMA channel */
        if ((dma8Channel < 2) || (dma8Channel == 3)) {
            status = YES;
        } else {
            IOLog("SoundBlaster16: 8-bit DMA channel is %d.\n", dma8Channel);
            IOLog("SoundBlaster16: 8-Bit DMA channel must be one of 0, 1 and 3.\n");
            status = NO;
        }

        if (!status)
            return NO;

        /* Validate 16-bit DMA channel */
        if ((dma16Channel >= 5 && dma16Channel <= 6) || (dma16Channel == 7)) {
            status = YES;
        } else {
            IOLog("SoundBlaster16: 16-bit DMA channel is %d.\n", dma16Channel);
            IOLog("SoundBlaster16: 16-Bit DMA channel must be one of 5, 6 and 7.\n");
            status = NO;
        }

        if (!status)
            return NO;

    } else {
        IOLog("%s: Must specify either one or two channels.\n", [self name]);
        return NO;
    }

    /*
     * Program the DMA select register in the mixer
     */
    programDMASelect(dma8Channel, dma16Channel);

    /*
     * Initialize 8-bit DMA controller
     */
    [self disableChannel: 0];

    if ([self isEISAPresent]) {
        ioReturn = [self setDMATransferWidth:IO_8Bit forChannel:0];
        if (ioReturn != IO_R_SUCCESS) {
            IOLog("%s: could not set transfer width to 8 bits, error %d.\n",
                  [self name], ioReturn);
            return NO;
        }
    }

    ioReturn = [self setTransferMode: IO_Demand forChannel: 0];
    if (ioReturn != IO_R_SUCCESS)  {
        IOLog("%s: dma transfer mode error %d\n", [self name], ioReturn);
        return NO;
    }

    ioReturn = [self setAutoinitialize: YES forChannel: 0];
    if (ioReturn != IO_R_SUCCESS) {
        IOLog("%s: dma auto initialize error %d", [self name], ioReturn);
        return NO;
    }

    /*
     * Initialize 16-bit DMA controller (only if dual-channel mode)
     */
    if (dmaChannelsAvailable == 1) {
        return YES;
    }

    [self disableChannel: 1];

    if ([self isEISAPresent]) {
        ioReturn = [self setDMATransferWidth:IO_16BitByteCount forChannel:1];
        if (ioReturn != IO_R_SUCCESS) {
            IOLog("%s: could not set transfer width to 16 bits, error %d.\n",
                  [self name], ioReturn);
            return NO;
        }
    }

    ioReturn = [self setTransferMode: IO_Demand forChannel: 1];
    if (ioReturn != IO_R_SUCCESS)  {
        IOLog("%s: dma transfer mode error %d\n", [self name], ioReturn);
        return NO;
    }

    ioReturn = [self setAutoinitialize: YES forChannel: 1];
    if (ioReturn != IO_R_SUCCESS) {
        IOLog("%s: dma auto initialize error %d", [self name], ioReturn);
        return NO;
    }

    return YES;
}

- (BOOL)reset
{
    unsigned int interrupt;
    unsigned char irqSelectBits;
    BOOL status;

    interrupt = [[self deviceDescription] interrupt];

    [self setName:codecDeviceName];
    [self setDeviceKind:codecDeviceKind];

    /*
     * Validate IRQ selection
     */
    if ((interrupt == 5) || (interrupt == 7) ||
        (interrupt >= 9 && interrupt <= 10)) {
        status = YES;
    } else {
        IOLog("SoundBlaster16: Audio irq is %d.\n", interrupt);
        IOLog("SoundBlaster16: Audio IRQ must be one of 5, 7, 9, 10.\n");
        status = NO;
    }

    if (!status)
        return NO;

    /*
     * Initialize hardware - detects card type
     */
    [self initializeHardware];

    /*
     * Check card type and reject unsupported cards
     */
    if (sb16CardType.version == SB16_BASIC ||
        sb16CardType.version == SB16_VIBRA) {
        /* Card types 1 and 2 are supported (16-bit capable) */
        IOLog("%s hardware version is %d.%d\n",
              [self name],
              sb16CardType.majorVersion,
              sb16CardType.minorVersion);
    } else if (sb16CardType.version == 3) {
        /* Card type 3 is 8-bit only */
        IOLog("%s: This driver does not support 8-bit Sound Blaster cards.\n", [self name]);
        return NO;
    } else {
        /* Card type 4 or unknown means no card detected */
        IOLog("%s: None or unsupported card.\n", [self name]);
        return NO;
    }

    /*
     * Initialize DMA channels
     */
    if (![self initializeDMAChannels])
        return NO;

    /*
     * Program IRQ select register (0x80) in mixer
     */
    irqSelectBits = 0;
    if (interrupt == 9) {
        irqSelectBits = 0x01;
    } else if (interrupt == 5) {
        irqSelectBits = 0x02;
    } else if (interrupt == 7) {
        irqSelectBits = 0x04;
    } else if (interrupt == 10) {
        irqSelectBits = 0x08;
    }

    outbIXMixer(MC16_IRQ_SELECT, irqSelectBits);

    return YES;
}

- (void) initializeHardware
{
    resetHardware(&sb16CardType);
    [self initializeLastStageGainRegisters];
}

- (void) initializeLastStageGainRegisters
{
    const char *gainStr;
    unsigned char gainValue;

    /*
     * Read last-stage gain values from config table if present
     */

    /* Read LS Input Gain */
    gainStr = [[[self deviceDescription] configTable]
                        valueForStringKey:"LS Input Gain"];
    if (gainStr != NULL) {
        gainValue = gainStr[0] - '0';
        if (gainValue < 4)
            lastStageGainInputLeft = lastStageGainInputRight = gainValue;
    }

    /* Read LS Output Gain */
    gainStr = [[[self deviceDescription] configTable]
                        valueForStringKey:"LS Output Gain"];
    if (gainStr != NULL) {
        gainValue = gainStr[0] - '0';
        if (gainValue < 4)
            lastStageGainOutputLeft = lastStageGainOutputRight = gainValue;
    }

    /*
     * Program last-stage (output) gain registers
     * These are 2-bit values (0-3) shifted left by 6 bits
     */
    outbIXMixer(MC16_INPUT_GAIN_LEFT, lastStageGainInputLeft << 6);
    outbIXMixer(MC16_INPUT_GAIN_RIGHT, lastStageGainInputRight << 6);
    outbIXMixer(MC16_OUTPUT_GAIN_LEFT, lastStageGainOutputLeft << 6);
    outbIXMixer(MC16_OUTPUT_GAIN_RIGHT, lastStageGainOutputRight << 6);
}

/*
 * Convert gain (0 - 32768) to hardware gain (0 - 3)
 */
- (void)updateInputGainLeft
{
    unsigned int gain;

    gain = [self inputGainLeft];
    if (gain != 0) {
        gain = (gain * MAX_MASTER_VOLUME_16) >> 0xf;  // Scale 15-bit gain to 5-bit volume
    }

    // Update shadow variables
    volCDLeft = volCDRight = volLineLeft = volLineRight = volMic = gain;

    // Program CT1745 mixer registers (shift left 3 for 8-bit register)
    outbIXMixer(CT1745_LINE_VOLUME_LEFT, volLineLeft << 3);
    outbIXMixer(CT1745_CD_VOLUME_LEFT, volCDLeft << 3);
    outbIXMixer(CT1745_MIC_VOLUME, volMic << 3);
}

- (void)updateInputGainRight
{
    unsigned int gain;

    gain = [self inputGainRight];
    if (gain != 0) {
        gain = (gain * MAX_MASTER_VOLUME_16) >> 0xf;  // Scale 15-bit gain to 5-bit volume
    }

    // Update shadow variables
    volCDLeft = volCDRight = volLineLeft = volLineRight = volMic = gain;

    // Program CT1745 mixer registers (shift left 3 for 8-bit register)
    outbIXMixer(CT1745_LINE_VOLUME_RIGHT, volLineRight << 3);
    outbIXMixer(CT1745_CD_VOLUME_RIGHT, volCDRight << 3);
    outbIXMixer(CT1745_MIC_VOLUME, volMic << 3);
}

- (void)updateOutputMute
{
    if ([self isOutputMuted]) {
        // Mute by setting all volumes to 0
        outbIXMixer(CT1745_VOICE_VOLUME_LEFT, 0);
        outbIXMixer(CT1745_VOICE_VOLUME_RIGHT, 0);
        outbIXMixer(CT1745_MASTER_VOLUME_LEFT, 0);
        outbIXMixer(CT1745_MASTER_VOLUME_RIGHT, 0);
    } else {
        // Restore volumes from shadow variables
        outbIXMixer(CT1745_VOICE_VOLUME_LEFT, volVoiceLeft << 3);
        outbIXMixer(CT1745_VOICE_VOLUME_RIGHT, volVoiceRight << 3);
        outbIXMixer(CT1745_MASTER_VOLUME_LEFT, volMasterLeft << 3);
        outbIXMixer(CT1745_MASTER_VOLUME_RIGHT, volMasterRight << 3);
    }
}

/*
 * Convert (0) - (-84) to hardware range (0) - (31)
 */
- (void) updateOutputAttenuationLeft
{
    unsigned int attenuation;
    unsigned int volume;

    attenuation = [self outputAttenuationLeft];
    volume = ((attenuation + SB16_ATTENUATION_RANGE) * MAX_MASTER_VOLUME_16) / SB16_ATTENUATION_RANGE;

    // Update shadow variables
    volVoiceLeft = volVoiceRight = volCDLeft = volCDRight =
        volMasterLeft = volMasterRight = volume;

    // Program CT1745 mixer registers (shift left 3 for 8-bit register)
    outbIXMixer(CT1745_MASTER_VOLUME_LEFT, volMasterLeft << 3);
    outbIXMixer(CT1745_CD_VOLUME_LEFT, volCDLeft << 3);
    outbIXMixer(CT1745_VOICE_VOLUME_LEFT, volVoiceLeft << 3);

    [self updateOutputMute];
}

- (void) updateOutputAttenuationRight
{
    unsigned int attenuation;
    unsigned int volume;

    attenuation = [self outputAttenuationRight];
    volume = ((attenuation + SB16_ATTENUATION_RANGE) * MAX_MASTER_VOLUME_16) / SB16_ATTENUATION_RANGE;

    // Update shadow variables
    volVoiceLeft = volVoiceRight = volCDLeft = volCDRight =
        volMasterLeft = volMasterRight = volume;

    // Program CT1745 mixer registers (shift left 3 for 8-bit register)
    outbIXMixer(CT1745_MASTER_VOLUME_RIGHT, volMasterRight << 3);
    outbIXMixer(CT1745_CD_VOLUME_RIGHT, volCDRight << 3);
    outbIXMixer(CT1745_VOICE_VOLUME_RIGHT, volVoiceRight << 3);

    [self updateOutputMute];
}

/*
 * Program DSP for sample rate
 */
- (void)updateSampleRate
{
    unsigned int rate;
    unsigned int stereo;
    unsigned int dmaDirection;
    unsigned char command;
    int timeout;
    char status;

    rate = [self sampleRate];
    stereo = ([self channelCount] == 2);
    dmaDirection = currentDMADirection;

    // Determine command based on DMA direction
    if (dmaDirection == DMA_DIRECTION_IN) {
        command = DC16_SET_SAMPLE_RATE_INPUT;   // 0x42
    } else {
        command = DC16_SET_SAMPLE_RATE_OUTPUT;  // 0x41
    }

    // Write command with timeout check
    timeout = 0;
    do {
        status = inb(sbWriteBufferStatusReg);
        if ((status & SB16_DSP_BUSY_BIT) == 0) break;
        IODelay(10);
        timeout++;
    } while (timeout < 10000);

    if (timeout == 10000) {
        outb(sbResetReg, 1);
        IODelay(SB16_ADDRESS_WRITE_DELAY);
        outb(sbResetReg, 0);
        IODelay(SB16_ADDRESS_WRITE_DELAY);
        IOLog("SoundBlaster16: DSP write error.\n");
    }

    outb(sbWriteDataOrCommandReg, command);
    IODelay(SB16_DATA_WRITE_DELAY);

    // Write high byte of sample rate with timeout check
    timeout = 0;
    do {
        status = inb(sbWriteBufferStatusReg);
        if ((status & SB16_DSP_BUSY_BIT) == 0) break;
        IODelay(10);
        timeout++;
    } while (timeout < 10000);

    if (timeout == 10000) {
        outb(sbResetReg, 1);
        IODelay(SB16_ADDRESS_WRITE_DELAY);
        outb(sbResetReg, 0);
        IODelay(SB16_ADDRESS_WRITE_DELAY);
        IOLog("SoundBlaster16: DSP write error.\n");
    }

    outb(sbWriteDataOrCommandReg, (rate >> 8) & 0xff);
    IODelay(SB16_DATA_WRITE_DELAY);

    // Write low byte of sample rate with timeout check
    timeout = 0;
    do {
        status = inb(sbWriteBufferStatusReg);
        if ((status & SB16_DSP_BUSY_BIT) == 0) break;
        IODelay(10);
        timeout++;
    } while (timeout < 10000);

    if (timeout == 10000) {
        outb(sbResetReg, 1);
        IODelay(SB16_ADDRESS_WRITE_DELAY);
        outb(sbResetReg, 0);
        IODelay(SB16_ADDRESS_WRITE_DELAY);
        IOLog("SoundBlaster16: DSP write error.\n");
    }

    outb(sbWriteDataOrCommandReg, rate & 0xff);
    IODelay(SB16_DATA_WRITE_DELAY);

    // Update DMA mode flags based on encoding and channel count
    if (currentEncoding == NX_SoundStreamDataEncoding_Linear8) {
        sbStartDMAMode &= ~DMA_MODE_SIGNED;  // Clear signed bit for 8-bit
    } else {
        sbStartDMAMode |= DMA_MODE_SIGNED;   // Set signed bit for 16-bit
    }

    if (stereo == YES) {
        sbStartDMAMode |= DMA_MODE_STEREO;   // Set stereo bit
    } else {
        sbStartDMAMode &= ~DMA_MODE_STEREO;  // Clear stereo bit (mono)
    }
}

/*
 * Set DMA buffer count
 */
- (void) setBufferCount:(int)count
{
    sbBufferCounter = count;
}

- (IOReturn) enableAllInterrupts
{
    /* SB16 interrupts are enabled by starting DMA, just call super */
    return [super enableAllInterrupts];
}

- (void) disableAllInterrupts
{
    /* SB16 interrupts are disabled by stopping DMA, just call super */
    [super disableAllInterrupts];
}

- (BOOL) startDMAForChannel: (unsigned int) localChannel
        read: (BOOL) isRead
        buffer: (IOEISADMABuffer) buffer
        bufferSizeForInterrupts: (unsigned int) bufferSize
{
    IOReturn ioReturn;
    unsigned int encoding;
    unsigned int actualChannel;

#ifdef DEBUG
    IOLog("SoundBlaster16: startDMAForChannel\n");
#endif DEBUG

    /*
     * Restore volume if not muted (using CT1745 registers)
     */
    if (![self isOutputMuted]) {
        outbIXMixer(CT1745_VOICE_VOLUME_LEFT, volVoiceLeft << 3);
        outbIXMixer(CT1745_VOICE_VOLUME_RIGHT, volVoiceRight << 3);
        outbIXMixer(CT1745_MASTER_VOLUME_LEFT, volMasterLeft << 3);
        outbIXMixer(CT1745_MASTER_VOLUME_RIGHT, volMasterRight << 3);
    }

    /*
     * Set DMA direction: 1 for output, 0 for input
     */
    currentDMADirection = isRead ? DMA_DIRECTION_IN : DMA_DIRECTION_OUT;

    /*
     * Get encoding and determine if we need 16-bit transfer
     */
    encoding = [self dataEncoding];
    currentEncoding = encoding;  /* Store raw encoding value */

    /*
     * Select DMA channel based on configuration
     * If dual-channel mode AND 16-bit encoding, use 16-bit DMA
     */
    actualChannel = localChannel;
    if (dmaChannelsAvailable == 2) {
        actualChannel =
            (encoding == NX_SoundStreamDataEncoding_Linear16) ? 1 : 0;
    }

    /*
     * Start DMA on the controller
     */
    ioReturn = [self startDMAForBuffer: buffer channel: actualChannel];
    if (ioReturn != IO_R_SUCCESS) {
        IOLog("%s: could not start DMA channel error %d\n",
                [self name], ioReturn);
        return NO;
    }

    /*
     * Enable interrupts first, then enable the DMA channel
     */
    ioReturn = [self enableAllInterrupts];
    if (ioReturn != IO_R_SUCCESS) {
        IOLog("%s: could not enable interrupts%d\n",
                [self name], ioReturn);
        return NO;
    }

    ioReturn = [self enableChannel: actualChannel];
    if (ioReturn != IO_R_SUCCESS) {
        IOLog("%s: could not enable DMA channel error %d\n",
                [self name], ioReturn);
        return NO;
    }

    /*
     * Update sample rate and buffer count
     */
    [self updateSampleRate];
    [self setBufferCount: bufferSize];

    /*
     * For mono recording, enable all input sources
     */
    if (isRead) {
        if ([self channelCount] == 1) {
            outbIXMixer(MC16_INPUT_CONTROL_LEFT, INPUT_SOURCE_ALL);
        }
    }

    /*
     * Program DSP for DMA transfer
     */
    if (isRead) {
        /* Recording mode */
        sbStartDMACommand = 0;
        if (currentEncoding == NX_SoundStreamDataEncoding_Linear16) {
            sbStartDMACommand = DC16_START_16BIT_DMA_DAC;
        } else {
            sbStartDMACommand &= 0x0f;
            sbStartDMACommand |= DC16_START_8BIT_DMA_DAC;
        }
        sbStartDMACommand |= DMA_MODE_ADC;
        sbStartDMACommand |= DMA_MODE_AUTO_INIT;
        sbStartDMACommand |= DMA_MODE_FIFO;

        /* Adjust buffer counter for 16-bit transfers */
        if (currentEncoding == NX_SoundStreamDataEncoding_Linear16) {
            sbBufferCounter >>= 1;
        }
        sbBufferCounter--;

        /* Send DSP commands */
        writeToDSP(sbStartDMACommand);
        writeToDSP(sbStartDMAMode);
        writeToDSP(sbBufferCounter & 0xff);
        writeToDSP((sbBufferCounter >> 8) & 0xff);
    } else {
        /* Playback mode */
        sbStartDMACommand = 0;
        if (currentEncoding == NX_SoundStreamDataEncoding_Linear16) {
            sbStartDMACommand = DC16_START_16BIT_DMA_DAC;
        } else {
            sbStartDMACommand &= 0x0f;
            sbStartDMACommand |= DC16_START_8BIT_DMA_DAC;
        }
        sbStartDMACommand &= ~DMA_MODE_ADC;
        sbStartDMACommand |= DMA_MODE_AUTO_INIT;
        sbStartDMACommand |= DMA_MODE_FIFO;

        /* Adjust buffer counter for 16-bit transfers */
        if (currentEncoding == NX_SoundStreamDataEncoding_Linear16) {
            sbBufferCounter >>= 1;
        }
        sbBufferCounter--;

        /* Send DSP commands */
        writeToDSP(sbStartDMACommand);
        writeToDSP(sbStartDMAMode);
        writeToDSP(sbBufferCounter & 0xff);
        writeToDSP((sbBufferCounter >> 8) & 0xff);
    }

    return YES;
}

- (void) stopDMAForChannel: (unsigned int) localChannel read: (BOOL) isRead
{
    unsigned int actualChannel;
    unsigned int channelCount;

#ifdef DEBUG
    IOLog("SoundBlaster16: stopDMAForChannel\n");
#endif DEBUG

    /* Disable interrupts first */
    [self disableAllInterrupts];

    /*
     * Stop DMA transfer (sends pause command and resets DSP)
     * Note: The original uses 16-bit pause for 8-bit transfers and vice versa
     */
    if (isRead) {
        stopDMATransfer(currentEncoding == NX_SoundStreamDataEncoding_Linear8);
    } else {
        stopDMATransfer(currentEncoding == NX_SoundStreamDataEncoding_Linear8);
    }

    /* Sleep to let hardware settle */
    IOSleep(50);

    /*
     * Determine which DMA channel to disable
     */
    actualChannel = localChannel;
    if (dmaChannelsAvailable == 2) {
        actualChannel =
            (currentEncoding == NX_SoundStreamDataEncoding_Linear16) ? 1 : 0;
    }

    [self disableChannel: actualChannel];

    /* Mark DMA as stopped */
    currentDMADirection = DMA_DIRECTION_STOPPED;

    /*
     * Restore input control for mono recording
     */
    channelCount = [self channelCount];
    if (isRead && (channelCount == 1)) {
        outbIXMixer(MC16_INPUT_CONTROL_LEFT, inputMixerSwitchLeft);
    }
}

- (IOAudioInterruptClearFunc) interruptClearFunc
{
    /* Return unified interrupt clear function */
    return (IOAudioInterruptClearFunc)clearInterrupts;
}

- (void) interruptOccurredForInput: (BOOL *) serviceInput
                         forOutput: (BOOL *) serviceOutput
{
    unsigned char status;
    unsigned int ackReg;

#ifdef DEBUG
    //IOLog("SoundBlaster16: handleHardwareInterrupt\n");
#endif DEBUG

    /*
     * Read interrupt status register from mixer to determine which interrupt fired
     */
    outbV(sbMixerAddressReg, MC16_IRQ_STATUS);
    IODelay(15);
    status = inb(sbMixerDataReg);
    IODelay(75);

    /* Store status for debugging */
    interruptStatus = status;

    /*
     * Acknowledge the appropriate interrupt by reading its ack register
     */
    ackReg = sbAck16bitInterrupt;
    if ((status & IRQ_STATUS_16BIT) ||
        (ackReg = sbAck8bitInterrupt, (interruptStatus & IRQ_STATUS_8BIT))) {
        inb(ackReg);
    }

    /*
     * Signal which direction needs service based on current DMA direction
     */
    if (currentDMADirection == DMA_DIRECTION_OUT)
        *serviceOutput = YES;
    else if (currentDMADirection == DMA_DIRECTION_IN)
        *serviceInput = YES;
}

/*
 * Handle timeout if interrupts stop
 */
- (void) timeoutOccurred
{
    if (interruptTimedOut == NO) {
        resetHardware(&sb16CardType);
        IOLog("%s: reset hardware.\n", [self name]);
        interruptTimedOut = YES;
    }
}

/*
 * Select input source
 */
- (void)setAnalogInputSource:(NXSoundParameterTag) val
{
    /* Input source selection not implemented in original driver */
    return;
}

/*
 * Parameter access methods
 */

- (BOOL)acceptsContinuousSamplingRates
{
    return YES;
}

- (void)getSamplingRatesLow:(int *)lowRate
                                         high:(int *)highRate
{
    *lowRate = 5000;
    *highRate = 45000;
}

- (void)getSamplingRates:(int *)rates
                                count:(unsigned int *)numRates
{
    rates[0] = 5000;
    rates[1] = 8000;
    rates[2] = 11025;
    rates[3] = 22050;
    rates[4] = 44100;
    rates[5] = 45000;
    *numRates = 6;
}

- (void)getDataEncodings: (NXSoundParameterTag *)encodings
                                count:(unsigned int *)numEncodings
{
    encodings[0] = NX_SoundStreamDataEncoding_Linear8;
    encodings[1] = NX_SoundStreamDataEncoding_Linear16;
    *numEncodings = 2;
}

- (unsigned int)channelCountLimit
{
    return 2;  /* Stereo support */
}

@end
