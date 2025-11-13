/*
 * Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved.
 * Copyright (c) 2025 RhapsodiOS Project. All rights reserved.
 *
 * HISTORY
 * 10-Nov-25   Created for ESS ES1x88 AudioDrive support
 *             Based on SoundBlaster16 driver
 */

#import "ES1x88AudioDriver.h"
#import "ES1x88AudioDriverRegisters.h"

#import <driverkit/generalFuncs.h>
#import <string.h>

static const char codecDeviceName[] = "ES1x88AudioDriver";
static const char codecDeviceKind[] = "Audio";

static  sb16CardParameters_t sb16CardType;       // hardware type

/*
 * Include inline functions.
 */
#import "ES1x88AudioDriverInline.h"

@implementation ES1x88AudioDriver

/*
 * Probe and initialize new instance
 */
+ (BOOL) probe:deviceDescription
{
    ES1x88AudioDriver  *dev;
    IORange         *portRangeList;
    int             numPortRanges;
    int             numChannels;
    unsigned int    baseAddress;

    dev = [self alloc];
    if (dev == nil)
        return NO;

    portRangeList = [deviceDescription portRangeList];
    numPortRanges = [deviceDescription numPortRanges];
    numChannels = [deviceDescription numChannels];

    /* Check that we have at least 1 port range and 1 or 2 DMA channels */
    if ((numPortRanges < 1) || ((numChannels - 1) > 1))
        return NO;

    baseAddress = portRangeList[0].start;

    /*
     * ES1x88 supports base addresses: 0x220, 0x230, 0x240, 0x250
     */
    if ((baseAddress == ES1x88_BASE_ADDRESS_1) ||
        (baseAddress == ES1x88_BASE_ADDRESS_2) ||
        (baseAddress == ES1x88_BASE_ADDRESS_3) ||
        (baseAddress == ES1x88_BASE_ADDRESS_4))   {

        /* Set base address and assign all DSP and Mixer register addresses */
        sbBaseRegisterAddress = baseAddress;
        assignDSPRegAddresses();
        assignMixerRegAddresses();

        return [dev initFromDeviceDescription:deviceDescription] != nil;
    }

    IOLog("ES1x88AudioDriver: Invalid port address 0x%0x.\n", baseAddress);
    [dev free];
    return NO;
}

- (BOOL)reset
{
    IODeviceDescription *deviceDescription;
    unsigned int *channelList;
    unsigned int dmaChannel1, dmaChannel2;
    unsigned int numChannels;
    unsigned int interrupt;
    IOReturn ioReturn;
    BOOL valid = YES;
    id configTable;
    const char *inputSourceStr;
    unsigned char recordSourceValue;

    deviceDescription = [self deviceDescription];
    channelList = (unsigned int *)[deviceDescription channelList];
    dmaChannel1 = channelList[0];
    numChannels = [deviceDescription numChannels];
    interrupt = [deviceDescription interrupt];

    [self setName:"ES1x88AudioDriver"];
    [self setDeviceKind:"Audio"];

    /* Get second DMA channel if dual-channel mode */
    dmaChannel2 = dmaChannel1;
    if (numChannels > 1) {
        dmaChannel2 = channelList[1];
    }

    /* Validate first DMA channel (must be 0, 1, or 3) */
    if ((dmaChannel1 > 1) && (dmaChannel1 != 3)) {
        IOLog("ES1x88AudioDriver: Audio DMA channel is %d.\n", dmaChannel1);
        IOLog("ES1x88AudioDriver: Audio DMA channel must be one of 0, 1, 3.\n");
        valid = NO;
    }

    /* Validate second DMA channel if different from first */
    if ((dmaChannel2 != dmaChannel1) && (dmaChannel2 > 1) && (dmaChannel2 != 3)) {
        IOLog("ES1x88AudioDriver: 2nd Audio DMA channel is %d.\n", dmaChannel2);
        IOLog("ES1x88AudioDriver: 2nd Audio DMA channel must be one of 0, 1, 3.\n");
        valid = NO;
    }

    /* Validate IRQ (must be 5, 7, 9, or 10) */
    if ((interrupt != 9) && (interrupt != 5) && (interrupt != 7) && (interrupt != 10)) {
        IOLog("ES1x88AudioDriver: Audio irq is %d.\n", interrupt);
        IOLog("ES1x88AudioDriver: Audio IRQ must be one of 5, 9, 7, 10.\n");
        valid = NO;
    }

    if (!valid) {
        return NO;
    }

    /* Initialize hardware and detect ES chip */
    [self initializeHardware];

    /* Parse "Input Source" from config table */
    configTable = [deviceDescription configTable];
    inputSourceStr = [[configTable valueForStringKey:"Input Source"] stringValue];

    if (inputSourceStr == NULL) {
        inputSource = 0;  /* Default to Mic */
    } else if (strcmp(inputSourceStr, "Mic") == 0) {
        inputSource = 0;
    } else if (strcmp(inputSourceStr, "CD") == 0) {
        inputSource = 2;
    } else if (strcmp(inputSourceStr, "Line") == 0) {
        inputSource = 1;
    } else {
        inputSource = 3;  /* Mixed */
    }

    /* Set mixer record source based on input source */
    if (inputSource == 0) {
        sbRecordSource = 0;  /* Microphone */
        recordSourceValue = 0;
    } else if (inputSource == 1) {
        sbRecordSource = 6;  /* Line In */
        recordSourceValue = 6;
    } else if (inputSource == 2) {
        sbRecordSource = 2;  /* CD */
        recordSourceValue = 2;
    } else {
        sbRecordSource = 7;  /* Mixed */
        recordSourceValue = 7;
    }

    outb(sbMixerAddressReg, ES_MIXER_RECORD_SOURCE);
    IODelay(10);
    outb(sbMixerDataReg, recordSourceValue);
    IODelay(25);

    /* Check ES hardware type and set hardware name */
    if (essHardware == 2) {
        hardwareName = "ES1688";
    } else if (essHardware == 1) {
        hardwareName = "ES688";
    } else if (essHardware == 3) {
        hardwareName = "ES1788";
    } else if (essHardware == 4) {
        hardwareName = "ES1888";
    } else {
        IOLog("ES1x88AudioDriver: Hardware not detected at port 0x%0x.\n", sbBaseRegisterAddress);
        return NO;
    }

    IOLog("ES1x88AudioDriver: %s AudioDrive (version: %x) at port 0x%0x.\n",
          hardwareName, essChipRevision, sbBaseRegisterAddress);

    /* Initialize DMA channel 0 */
    [self disableChannel:0];

    if ([self isEISAPresent]) {
        ioReturn = [self setDMATransferWidth:IO_8Bit forChannel:0];
        if (ioReturn != IO_R_SUCCESS) {
            IOLog("ES1x88AudioDriver: could not set transfer width to 8 bits, error %d.\n", ioReturn);
            return NO;
        }
    }

    ioReturn = [self setTransferMode:IO_Single forChannel:0];
    if (ioReturn != IO_R_SUCCESS) {
        IOLog("%s: dma transfer mode error %d\n", [self name], ioReturn);
        return NO;
    }

    ioReturn = [self setAutoinitialize:YES forChannel:0];
    if (ioReturn != IO_R_SUCCESS) {
        IOLog("%s: dma auto initialize error %d", [self name], ioReturn);
        return NO;
    }

    /* Disable remaining channels */
    while (numChannels > 1) {
        numChannels--;
        [self disableChannel:numChannels];
    }

    return YES;
}

- (BOOL) initializeDMAChannels
{
    id deviceDesc = [self deviceDescription];
    int numChannels;
    unsigned int *channelList;
    IOReturn ioReturn;
    BOOL status;

    numChannels = [deviceDesc numChannels];

    if (numChannels == 1) {
        /* Single DMA channel - 8-bit only */
        dma8Channel = [deviceDesc channel];
        numDMAChannels = 1;

        /* Validate 8-bit DMA channel */
        if ((dma8Channel < 2) || (dma8Channel == 3)) {
            status = YES;
        } else {
            IOLog("ES1x88AudioDriver: 8-bit DMA channel is %d.\n", dma8Channel);
            IOLog("ES1x88AudioDriver: 8-Bit DMA channel must be one of 0, 1 and 3.\n");
            status = NO;
        }

        if (!status)
            return NO;

        /* Set default 16-bit channel to invalid value */
        dma16Channel = 99;

    } else if (numChannels == 2) {
        /* Dual DMA channels - 8-bit and 16-bit */
        channelList = (unsigned int *)[deviceDesc channelList];
        dma8Channel = channelList[0];
        dma16Channel = channelList[1];
        numDMAChannels = 2;

        /* Validate 8-bit DMA channel */
        if ((dma8Channel < 2) || (dma8Channel == 3)) {
            status = YES;
        } else {
            IOLog("ES1x88AudioDriver: 8-bit DMA channel is %d.\n", dma8Channel);
            IOLog("ES1x88AudioDriver: 8-Bit DMA channel must be one of 0, 1 and 3.\n");
            status = NO;
        }

        if (!status)
            return NO;

        /* Validate 16-bit DMA channel */
        if ((dma16Channel >= 5 && dma16Channel <= 6) || (dma16Channel == 7)) {
            status = YES;
        } else {
            IOLog("ES1x88AudioDriver: 16-bit DMA channel is %d.\n", dma16Channel);
            IOLog("ES1x88AudioDriver: 16-Bit DMA channel must be one of 5, 6 and 7.\n");
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

    ioReturn = [self setTransferMode: IO_Single forChannel: 0];
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
    if (numDMAChannels == 1) {
        return YES;
    }

    [self disableChannel: 1];

    if ([self isEISAPresent]) {
        ioReturn = [self setDMATransferWidth:IO_16Bit forChannel:1];
        if (ioReturn != IO_R_SUCCESS) {
            IOLog("%s: could not set transfer width to 16 bits, error %d.\n",
                  [self name], ioReturn);
            return NO;
        }
    }

    ioReturn = [self setTransferMode: IO_Single forChannel: 1];
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


- (void) initializeHardware
{
    char dspVersion;
    unsigned char chipId1, chipId2;

    /* Initialize ES hardware detection flag */
    essHardware = 0;

    /* Reset DSP */
    outb(sbResetReg, 1);
    IODelay(10);
    outb(sbResetReg, 0);
    IODelay(10);

    /* Wait for DSP ready (0xAA response) */
    if (!waitForDSPDataAvailable()) {
        return;
    }

    /* Read DSP version */
    dspVersion = inb(sbReadDataReg);
    IODelay(10);

    /* Check if DSP returned 0xAA ready response */
    if (dspVersion == (char)ES_DSP_READY_RESPONSE) {
        /* Sleep to let hardware stabilize */
        IOSleep(1);

        /* Send extended ID command */
        if (!waitForDSPWriteReady()) {
            return;
        }
        outb(sbWriteDataOrCommandReg, ES_CMD_EXTENDED_ID);

        /* Send version query command */
        if (!waitForDSPWriteReady()) {
            return;
        }
        outb(sbWriteDataOrCommandReg, ES_CMD_VERSION_QUERY);
        IODelay(25);

        /* Read chip ID bytes */
        if (!waitForDSPDataAvailable()) {
            return;
        }
        chipId1 = inb(sbReadDataReg);
        IODelay(10);

        chipId2 = inb(sbReadDataReg);
        IODelay(10);

        /* Check if this is an ES1x88 chip (ID starts with 'h' = 0x68) */
        if (chipId1 == ES_CHIP_ID_PREFIX) {
            essChipRevision = chipId2 & 0x0F;
            essHardware = 1;
        }
    }

    /* Reset mixer */
    outb(sbMixerAddressReg, ES_MIXER_RESET);
    IODelay(10);
    outb(sbMixerDataReg, 0x00);
    IODelay(25);

    /* Set Master Volume to 0xAA */
    volMaster.rawValue = 0xAA;
    outb(sbMixerAddressReg, ES_MIXER_MASTER_VOLUME);
    IODelay(10);
    outb(sbMixerDataReg, 0xAA);
    IODelay(25);

    /* Set FM Volume to 0x00 (off) */
    volFM.rawValue = 0x00;
    outb(sbMixerAddressReg, ES_MIXER_FM_VOLUME);
    IODelay(10);
    outb(sbMixerDataReg, 0x00);
    IODelay(25);

    /* Set CD Volume to 0xAA */
    volCD.rawValue = 0xAA;
    outb(sbMixerAddressReg, ES_MIXER_CD_VOLUME);
    IODelay(10);
    outb(sbMixerDataReg, 0xAA);
    IODelay(25);

    /* Set Line Volume to 0xAA */
    volLine.rawValue = 0xAA;
    outb(sbMixerAddressReg, ES_MIXER_LINE_VOLUME);
    IODelay(10);
    outb(sbMixerDataReg, 0xAA);
    IODelay(25);

    /* Set Voice Volume to 0xAA */
    volVoc = 0xAA;
    outb(sbMixerAddressReg, ES_MIXER_VOICE_VOLUME);
    IODelay(10);
    outb(sbMixerDataReg, 0xAA);
    IODelay(25);

    /* Set Mic Volume (combines with existing bits) */
    volMic = (volMic & 0x0F) | 0xA0;

    /* Set Record Source to 0x07 */
    sbRecordSource = 0x07;
    outb(sbMixerAddressReg, ES_MIXER_RECORD_SOURCE);
    IODelay(10);
    outb(sbMixerDataReg, 0x07);
    IODelay(25);
}

- (void) initializeLastStageGainRegisters
{
    id deviceDesc = [self deviceDescription];
    id configTable;
    const char *gainStr;
    unsigned char gainValue;

    /*
     * Read last-stage gain values from config table if present
     */
    configTable = [deviceDesc configTable];

    /* Read LS Input Gain */
    gainStr = [[configTable valueForStringKey:"LS Input Gain"] stringValue];
    if (gainStr != NULL && (gainStr[0] - '0') < 4) {
        gainValue = gainStr[0] - '0';
        lastStageGainInputLeft = gainValue;
        lastStageGainInputRight = gainValue;
    }

    /* Read LS Output Gain */
    gainStr = [[configTable valueForStringKey:"LS Output Gain"] stringValue];
    if (gainStr != NULL && (gainStr[0] - '0') < 4) {
        gainValue = gainStr[0] - '0';
        lastStageGainOutputLeft = gainValue;
        lastStageGainOutputRight = gainValue;
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
    unsigned char gainValue;

    gain = [self inputGainLeft];

    /* Scale 15-bit gain (0-32768) to 4-bit value (0-15) */
    if (gain == 0) {
        gainValue = 0;
    } else {
        gainValue = (unsigned char)((gain * ES_VOLUME_BITS) >> 0x0F);  /* (gain * 15) / 32768 */
    }

    /* Update shadow variables - ES1x88 format: upper 4 bits = left, lower 4 bits = right */
    volLine.rawValue = (volLine.rawValue & ES_VOLUME_BITS) | (gainValue << 4);
    volMic = (volMic & ES_VOLUME_BITS) | (gainValue << 4);
    volCD.rawValue = (volCD.rawValue & ES_VOLUME_BITS) | (gainValue << 4);

    /* Write to mixer registers */
    outb(sbMixerAddressReg, ES_MIXER_LINE_VOLUME);
    IODelay(10);
    outb(sbMixerDataReg, volLine.rawValue);
    IODelay(25);

    outb(sbMixerAddressReg, ES_MIXER_CD_VOLUME);
    IODelay(10);
    outb(sbMixerDataReg, volCD.rawValue);
    IODelay(25);
}

- (void)updateInputGainRight
{
    unsigned int gain;
    unsigned char gainValue;

    gain = [self inputGainRight];

    /* Scale 15-bit gain (0-32768) to 4-bit value (0-15) */
    if (gain == 0) {
        gainValue = 0;
    } else {
        gainValue = (unsigned char)((gain * ES_VOLUME_BITS) >> 0x0F);  /* (gain * 15) / 32768 */
    }

    /* Update shadow variables - ES1x88 format: upper 4 bits = left, lower 4 bits = right */
    volLine.rawValue = (volLine.rawValue & 0xF0) | (gainValue & ES_VOLUME_BITS);
    volMic = (volMic & 0xF0) | (gainValue & ES_VOLUME_BITS);
    volCD.rawValue = (volCD.rawValue & 0xF0) | (gainValue & ES_VOLUME_BITS);

    /* Write to mixer registers */
    outb(sbMixerAddressReg, ES_MIXER_LINE_VOLUME);
    IODelay(10);
    outb(sbMixerDataReg, volLine.rawValue);
    IODelay(25);

    outb(sbMixerAddressReg, ES_MIXER_CD_VOLUME);
    IODelay(10);
    outb(sbMixerDataReg, volCD.rawValue);
    IODelay(25);
}

- (void)updateOutputMute
{
    BOOL isMuted;
    unsigned char speakerCommand;

    isMuted = [self isOutputMuted];

    if (isMuted) {
        /* Mute all mixer channels */
        outb(sbMixerAddressReg, ES_MIXER_MASTER_VOLUME);
        IODelay(10);
        outb(sbMixerDataReg, 0);
        IODelay(25);

        outb(sbMixerAddressReg, ES_MIXER_CD_VOLUME);
        IODelay(10);
        outb(sbMixerDataReg, 0);
        IODelay(25);

        outb(sbMixerAddressReg, ES_MIXER_VOICE_VOLUME);
        IODelay(10);
        outb(sbMixerDataReg, 0);
        IODelay(25);

        outb(sbMixerAddressReg, ES_MIXER_LINE_VOLUME);
        IODelay(10);
        outb(sbMixerDataReg, 0);
        IODelay(25);

        speakerCommand = DC16_TURN_OFF_SPEAKER;
    } else {
        /* Restore volumes from shadow variables */
        outb(sbMixerAddressReg, ES_MIXER_MASTER_VOLUME);
        IODelay(10);
        outb(sbMixerDataReg, volMaster.rawValue);
        IODelay(25);

        outb(sbMixerAddressReg, ES_MIXER_CD_VOLUME);
        IODelay(10);
        outb(sbMixerDataReg, volCD.rawValue);
        IODelay(25);

        outb(sbMixerAddressReg, ES_MIXER_VOICE_VOLUME);
        IODelay(10);
        outb(sbMixerDataReg, volVoc);
        IODelay(25);

        outb(sbMixerAddressReg, ES_MIXER_LINE_VOLUME);
        IODelay(10);
        outb(sbMixerDataReg, volLine.rawValue);
        IODelay(25);

        speakerCommand = DC16_TURN_ON_SPEAKER;
    }

    /* Send speaker on/off command */
    outb(sbWriteDataOrCommandReg, speakerCommand);
    IODelay(25);
}

/*
 * Convert attenuation (0 to -84) to hardware volume (15 to 0)
 * Formula: volume = ((attenuation * 3 + 252) * 5) / 84
 */
- (void) updateOutputAttenuationLeft
{
    int attenuation;
    unsigned char volumeValue;
    unsigned char volInUpperNibble;

    attenuation = [self outputAttenuationLeft];

    /* Convert attenuation to 4-bit volume (0-15) */
    volumeValue = (unsigned char)(((attenuation * ES_ATTENUATION_MULTIPLIER + ES_ATTENUATION_OFFSET) * ES_ATTENUATION_SCALE) / ES_ATTENUATION_RANGE);
    volInUpperNibble = volumeValue << 4;

    /* Update shadow variables - left channel is upper 4 bits */
    volCD.rawValue = (volCD.rawValue & ES_VOLUME_BITS) | volInUpperNibble;
    volMaster.rawValue = (volMaster.rawValue & ES_VOLUME_BITS) | volInUpperNibble;
    volLine.rawValue = (volLine.rawValue & ES_VOLUME_BITS) | volInUpperNibble;
    volVoc = (volVoc & ES_VOLUME_BITS) | volInUpperNibble;

    /* Write to mixer registers */
    outb(sbMixerAddressReg, ES_MIXER_MASTER_VOLUME);
    IODelay(10);
    outb(sbMixerDataReg, volMaster.rawValue);
    IODelay(25);

    outb(sbMixerAddressReg, ES_MIXER_CD_VOLUME);
    IODelay(10);
    outb(sbMixerDataReg, volCD.rawValue);
    IODelay(25);

    outb(sbMixerAddressReg, ES_MIXER_VOICE_VOLUME);
    IODelay(10);
    outb(sbMixerDataReg, volVoc);
    IODelay(25);

    outb(sbMixerAddressReg, ES_MIXER_LINE_VOLUME);
    IODelay(10);
    outb(sbMixerDataReg, volLine.rawValue);
    IODelay(25);
}

- (void) updateOutputAttenuationRight
{
    int attenuation;
    unsigned char volumeValue;

    attenuation = [self outputAttenuationRight];

    /* Convert attenuation to 4-bit volume (0-15) */
    volumeValue = (unsigned char)(((attenuation * ES_ATTENUATION_MULTIPLIER + ES_ATTENUATION_OFFSET) * ES_ATTENUATION_SCALE) / ES_ATTENUATION_RANGE);
    volumeValue = volumeValue & ES_VOLUME_BITS;  /* Keep in lower 4 bits */

    /* Update shadow variables - right channel is lower 4 bits */
    volCD.rawValue = (volCD.rawValue & 0xF0) | volumeValue;
    volMaster.rawValue = (volMaster.rawValue & 0xF0) | volumeValue;
    volLine.rawValue = (volLine.rawValue & 0xF0) | volumeValue;
    volVoc = (volVoc & 0xF0) | volumeValue;

    /* Write to mixer registers */
    outb(sbMixerAddressReg, ES_MIXER_MASTER_VOLUME);
    IODelay(10);
    outb(sbMixerDataReg, volMaster.rawValue);
    IODelay(25);

    outb(sbMixerAddressReg, ES_MIXER_CD_VOLUME);
    IODelay(10);
    outb(sbMixerDataReg, volCD.rawValue);
    IODelay(25);

    outb(sbMixerAddressReg, ES_MIXER_VOICE_VOLUME);
    IODelay(10);
    outb(sbMixerDataReg, volVoc);
    IODelay(25);

    outb(sbMixerAddressReg, ES_MIXER_LINE_VOLUME);
    IODelay(10);
    outb(sbMixerDataReg, volLine.rawValue);
    IODelay(25);
}

/*
 * Program DSP for sample rate
 */
- (void)updateSampleRate
{
    unsigned int rate;
    unsigned int channelCount;
    unsigned char command;
    int timeout;
    char status;

    rate = [self sampleRate];
    channelCount = [self channelCount];

    // Determine command based on DMA direction
    if (currentDMADirection == DMA_DIRECTION_IN) {
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
        IOLog("ES1x88AudioDriver: DSP write error.\n");
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
        IOLog("ES1x88AudioDriver: DSP write error.\n");
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
        IOLog("ES1x88AudioDriver: DSP write error.\n");
    }

    outb(sbWriteDataOrCommandReg, rate & 0xff);
    IODelay(SB16_DATA_WRITE_DELAY);

    // Update DMA mode flags based on encoding and channel count
    if (is16BitTransfer == NX_SoundStreamDataEncoding_Linear8) {
        sbStartDMAMode &= ~DMA_MODE_SIGNED;  // Clear signed bit for 8-bit
    } else {
        sbStartDMAMode |= DMA_MODE_SIGNED;   // Set signed bit for 16-bit
    }

    if (channelCount == 2) {
        sbStartDMAMode |= DMA_MODE_STEREO;   // Set stereo bit
    } else {
        sbStartDMAMode &= ~DMA_MODE_STEREO;  // Clear stereo bit (mono)
    }
}

/*
 * Configure ES1x88 hardware registers for data transfer
 * This sets up sample rate, transfer mode, IRQ and DMA channels
 */
- (void)configureHardwareForDataTransfer:(unsigned int)transferCount
{
    IODeviceDescription *deviceDescription;
    unsigned int *channelList;
    unsigned int dmaChannel;
    unsigned int irq;
    unsigned int sampleRate;
    unsigned int channelCount;
    NXSoundParameterTag dataEncoding;
    unsigned char regValue;
    unsigned char sampleRateByte;
    unsigned char irqBits, dmaBits;
    unsigned char modeCommand1, modeCommand2;
    unsigned char modeData;
    unsigned short transferCountNeg;

    deviceDescription = [self deviceDescription];
    channelList = (unsigned int *)[deviceDescription channelList];
    dmaChannel = channelList[0];
    irq = [deviceDescription interrupt];
    sampleRate = [self sampleRate];
    channelCount = [self channelCount];
    dataEncoding = [self dataEncoding];

    /* Send Audio Control 2 command followed by direction-specific value */
    outb(sbWriteDataOrCommandReg, ES_REG_AUDIO_CONTROL_2);
    IODelay(25);
    if (currentDMADirection == DMA_DIRECTION_IN) {
        outb(sbWriteDataOrCommandReg, ES_MODE_INPUT);  /* Input/Record */
    } else {
        outb(sbWriteDataOrCommandReg, ES_MODE_OUTPUT);  /* Output/Playback */
    }
    IODelay(25);

    /* Send Read Register command */
    outb(sbWriteDataOrCommandReg, ES_CMD_READ_REGISTER);
    IODelay(25);

    /* Read Audio Mode register, modify channel bits, write back */
    outb(sbWriteDataOrCommandReg, ES_REG_AUDIO_MODE);
    IODelay(25);
    regValue = inb(sbReadDataReg);
    IODelay(10);

    /* Clear channel bits based on direction */
    if (currentDMADirection == DMA_DIRECTION_IN) {
        regValue &= 0xFC;  /* Clear lower 2 bits */
    } else {
        regValue &= 0xF8;  /* Clear lower 3 bits */
    }

    /* Set stereo/mono bit */
    if (channelCount == 2) {
        regValue |= ES_AUDIO_MODE_STEREO;  /* Stereo */
    } else {
        regValue |= ES_AUDIO_MODE_MONO;  /* Mono */
    }

    /* Write back to Audio Mode register */
    outb(sbWriteDataOrCommandReg, ES_REG_AUDIO_MODE);
    IODelay(25);
    outb(sbWriteDataOrCommandReg, regValue);
    IODelay(25);

    /* Send DMA Setup command with value 0x02 */
    outb(sbWriteDataOrCommandReg, ES_REG_DMA_SETUP);
    IODelay(25);
    outb(sbWriteDataOrCommandReg, 0x02);
    IODelay(25);

    /* Calculate and set sample rate register */
    if (sampleRate < ES_SAMPLE_RATE_THRESHOLD) {  /* < 22001 Hz */
        sampleRateByte = (0x80 - (ES_SAMPLE_RATE_CONST_LOW / sampleRate)) & 0x7F;
    } else {
        sampleRateByte = (-(ES_SAMPLE_RATE_CONST_HIGH / sampleRate)) | 0x80;
    }
    outb(sbWriteDataOrCommandReg, ES_REG_SAMPLE_RATE);
    IODelay(25);
    outb(sbWriteDataOrCommandReg, sampleRateByte);
    IODelay(25);

    /* Set filter register */
    outb(sbWriteDataOrCommandReg, ES_REG_FILTER);
    IODelay(25);
    outb(sbWriteDataOrCommandReg, -(ES_FILTER_CONST / (sampleRate * ES_FILTER_DIVISOR)));
    IODelay(25);

    /* Set transfer count (negative, 2's complement) */
    transferCountNeg = (~transferCount + 1);

    /* Low byte to Transfer Count register */
    outb(sbWriteDataOrCommandReg, ES_REG_TRANSFER_COUNT_LOW);
    IODelay(25);
    outb(sbWriteDataOrCommandReg, transferCountNeg & 0xFF);
    IODelay(25);

    /* High byte to Transfer Count register */
    outb(sbWriteDataOrCommandReg, ES_REG_TRANSFER_COUNT_HIGH);
    IODelay(25);
    outb(sbWriteDataOrCommandReg, (transferCountNeg >> 8) & 0xFF);
    IODelay(25);

    /* Determine mode commands based on channel count and encoding */
    if (channelCount == 2) {  /* Stereo */
        if (dataEncoding == NX_SoundStreamDataEncoding_Linear16) {
            modeData = ES_OUTPUT_MODE_16BIT;
            modeCommand1 = ES_AUDIO_MODE_STEREO_16BIT_CMD1;
            modeCommand2 = ES_AUDIO_MODE_STEREO_16BIT_CMD2;
        } else {  /* 8-bit */
            modeData = ES_OUTPUT_MODE_8BIT;
            modeCommand1 = ES_AUDIO_MODE_STEREO_8BIT_CMD1;
            modeCommand2 = ES_AUDIO_MODE_STEREO_8BIT_CMD2;
        }
    } else {  /* Mono */
        if (dataEncoding == NX_SoundStreamDataEncoding_Linear16) {
            modeData = ES_OUTPUT_MODE_16BIT;
            modeCommand1 = ES_AUDIO_MODE_MONO_16BIT_CMD1;
            modeCommand2 = ES_AUDIO_MODE_MONO_16BIT_CMD2;
        } else {  /* 8-bit */
            modeData = ES_OUTPUT_MODE_8BIT;
            modeCommand1 = ES_AUDIO_MODE_MONO_8BIT_CMD1;
            modeCommand2 = ES_AUDIO_MODE_MONO_8BIT_CMD2;
        }
    }

    /* Send Output Mode command for output (record/playback mode) */
    if (currentDMADirection != DMA_DIRECTION_IN) {
        outb(sbWriteDataOrCommandReg, ES_REG_OUTPUT_MODE);
        IODelay(25);
        outb(sbWriteDataOrCommandReg, modeData);
        IODelay(25);
    }

    /* Send Audio Control 1 command twice with mode values */
    outb(sbWriteDataOrCommandReg, ES_REG_AUDIO_CONTROL_1);
    IODelay(25);
    outb(sbWriteDataOrCommandReg, modeCommand1);
    IODelay(25);

    outb(sbWriteDataOrCommandReg, ES_REG_AUDIO_CONTROL_1);
    IODelay(25);
    outb(sbWriteDataOrCommandReg, modeCommand2);
    IODelay(25);

    /* Configure IRQ Control register */
    irqBits = 0;
    if (irq == 9) {
        irqBits = 0x00;
    } else if (irq == 5) {
        irqBits = 0x04;
    } else if (irq == 7) {
        irqBits = 0x08;
    } else if (irq == 10) {
        irqBits = 0x0C;
    }

    outb(sbWriteDataOrCommandReg, ES_REG_IRQ_CONTROL);
    IODelay(25);
    outb(sbWriteDataOrCommandReg, irqBits | 0x50);
    IODelay(25);

    /* Configure DMA Control register */
    dmaBits = 0;
    if (dmaChannel == 0) {
        dmaBits = 0x04;
    } else if (dmaChannel == 1) {
        dmaBits = 0x08;
    } else if (dmaChannel == 3) {
        dmaBits = 0x0C;
    }

    outb(sbWriteDataOrCommandReg, ES_REG_DMA_CONTROL);
    IODelay(25);
    outb(sbWriteDataOrCommandReg, dmaBits | 0x50);
    IODelay(25);
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
    /* ES1x88 interrupts are enabled by starting DMA, just call super */
    return [super enableAllInterrupts];
}

- (void) disableAllInterrupts
{
    /* ES1x88 interrupts are disabled by stopping DMA, just call super */
    [super disableAllInterrupts];
}

- (BOOL) startDMAForChannel: (unsigned int) localChannel
        read: (BOOL) isRead
        buffer: (IOEISADMABuffer) buffer
        bufferSizeForInterrupts: (unsigned int) bufferSize
{
    IOReturn ioReturn;
    unsigned char dspVersion;
    unsigned char recordSourceValue;
    unsigned char micValue;
    unsigned char regValue;

    /* Clear timeout flag */
    interruptTimedOut = NO;

    /* Set DMA direction: 0 for input (read), 1 for output (not read) */
    if (isRead) {
        currentDMADirection = DMA_DIRECTION_IN;
    } else {
        currentDMADirection = DMA_DIRECTION_OUT;
    }

    /* Reset DSP with value 3 */
    outb(sbResetReg, 3);
    IODelay(10);
    outb(sbResetReg, 0);
    IODelay(10);

    /* Wait for DSP ready and read version */
    if (!waitForDSPDataAvailable()) {
        IOLog("ES1x88AudioDriver: Can not reset DSP.\n");
        return NO;
    }

    dspVersion = inb(sbReadDataReg);
    IODelay(10);

    /* If DSP returned 0xAA ready response, send extended ID command */
    if (dspVersion == (char)ES_DSP_READY_RESPONSE) {
        if (waitForDSPWriteReady()) {
            outb(sbWriteDataOrCommandReg, ES_CMD_EXTENDED_ID);
        }
    } else {
        IOLog("ES1x88AudioDriver: Can not reset DSP.\n");
    }

    /* Configure hardware for this transfer */
    [self configureHardwareForDataTransfer:bufferSize];

    /* Start DMA on channel 0 */
    ioReturn = [self startDMAForBuffer:buffer channel:0];
    if (ioReturn != IO_R_SUCCESS) {
        IOLog("%s: could not start DMA channel error %d\n", [self name], ioReturn);
        return NO;
    }

    /* Enable DMA channel */
    ioReturn = [self enableChannel:0];
    if (ioReturn != IO_R_SUCCESS) {
        IOLog("%s: could not enable DMA channel error %d\n", [self name], ioReturn);
        return NO;
    }

    /* Enable interrupts */
    [self enableAllInterrupts];

    /* Restore mixer volumes if not muted */
    if (![self isOutputMuted]) {
        outb(sbMixerAddressReg, ES_MIXER_MASTER_VOLUME);
        IODelay(10);
        outb(sbMixerDataReg, volMaster.rawValue);
        IODelay(25);

        outb(sbMixerAddressReg, ES_MIXER_CD_VOLUME);
        IODelay(10);
        outb(sbMixerDataReg, volCD.rawValue);
        IODelay(25);

        outb(sbMixerAddressReg, ES_MIXER_VOICE_VOLUME);
        IODelay(10);
        outb(sbMixerDataReg, volVoc);
        IODelay(25);

        outb(sbMixerAddressReg, ES_MIXER_LINE_VOLUME);
        IODelay(10);
        outb(sbMixerDataReg, volLine.rawValue);
        IODelay(25);

        /* Turn on speaker */
        outb(sbWriteDataOrCommandReg, DC16_TURN_ON_SPEAKER);
        IODelay(25);
    }

    /* For recording (input), configure input source */
    if (isRead) {
        /* Set record source based on inputSource */
        if (inputSource == 0) {
            sbRecordSource = 0;  /* Microphone */
            recordSourceValue = 0;
        } else if (inputSource == 1) {
            sbRecordSource = 6;  /* Line In */
            recordSourceValue = 6;
        } else if (inputSource == 2) {
            sbRecordSource = 2;  /* CD */
            recordSourceValue = 2;
        } else {
            sbRecordSource = 7;  /* Mixed */
            recordSourceValue = 7;
        }

        outb(sbMixerAddressReg, ES_MIXER_RECORD_SOURCE);
        IODelay(10);
        outb(sbMixerDataReg, recordSourceValue);
        IODelay(25);

        /* Handle Microphone input source */
        micValue = volMic;
        if (inputSource == 0) {
            /* Microphone mode - set mic volume and mute other sources */
            outb(sbMixerAddressReg, ES_MIXER_MIC_VOLUME);
            IODelay(10);
            outb(sbMixerDataReg, micValue);
            IODelay(25);

            /* Mute all other volumes */
            outb(sbMixerAddressReg, ES_MIXER_MASTER_VOLUME);
            IODelay(10);
            outb(sbMixerDataReg, 0);
            IODelay(25);

            outb(sbMixerAddressReg, ES_MIXER_CD_VOLUME);
            IODelay(10);
            outb(sbMixerDataReg, 0);
            IODelay(25);

            outb(sbMixerAddressReg, ES_MIXER_VOICE_VOLUME);
            IODelay(10);
            outb(sbMixerDataReg, 0);
            IODelay(25);

            outb(sbMixerAddressReg, ES_MIXER_LINE_VOLUME);
            IODelay(10);
            outb(sbMixerDataReg, 0);
            IODelay(25);

            /* Turn off speaker for recording */
            outb(sbWriteDataOrCommandReg, DC16_TURN_OFF_SPEAKER);
            IODelay(25);
        } else if (inputSource == 3) {
            /* Mixed mode - set mic volume */
            outb(sbMixerAddressReg, ES_MIXER_MIC_VOLUME);
            IODelay(10);
            outb(sbMixerDataReg, micValue);
            IODelay(25);
        }
    }

    /* Send Read Register command */
    outb(sbWriteDataOrCommandReg, ES_CMD_READ_REGISTER);
    IODelay(25);

    /* Read Audio Control 2 register, OR with 1, write back */
    outb(sbWriteDataOrCommandReg, ES_REG_AUDIO_CONTROL_2);
    IODelay(25);
    regValue = inb(sbReadDataReg);
    IODelay(10);

    outb(sbWriteDataOrCommandReg, ES_REG_AUDIO_CONTROL_2);
    IODelay(25);
    outb(sbWriteDataOrCommandReg, regValue | 0x01);
    IODelay(25);

    return YES;
}

- (void) stopDMAForChannel: (unsigned int) localChannel read: (BOOL) isRead
{
    unsigned char regValue;

    /* Send Read Register command */
    outb(sbWriteDataOrCommandReg, ES_CMD_READ_REGISTER);
    IODelay(25);

    /* Read Audio Control 2 register, clear bit 0, write back */
    outb(sbWriteDataOrCommandReg, ES_REG_AUDIO_CONTROL_2);
    IODelay(25);
    regValue = inb(sbReadDataReg);
    IODelay(10);

    outb(sbWriteDataOrCommandReg, ES_REG_AUDIO_CONTROL_2);
    IODelay(25);
    outb(sbWriteDataOrCommandReg, regValue & 0xFE);  /* Clear bit 0 to stop audio engine */
    IODelay(25);

    /* Disable interrupts and DMA channel */
    [self disableAllInterrupts];
    [self disableChannel:0];

    /* Mute microphone */
    outb(sbMixerAddressReg, ES_MIXER_MIC_VOLUME);
    IODelay(10);
    outb(sbMixerDataReg, 0);
    IODelay(25);

    /* Restore mixer volumes if not muted */
    if (![self isOutputMuted]) {
        outb(sbMixerAddressReg, ES_MIXER_MASTER_VOLUME);
        IODelay(10);
        outb(sbMixerDataReg, volMaster.rawValue);
        IODelay(25);

        outb(sbMixerAddressReg, ES_MIXER_CD_VOLUME);
        IODelay(10);
        outb(sbMixerDataReg, volCD.rawValue);
        IODelay(25);

        outb(sbMixerAddressReg, ES_MIXER_VOICE_VOLUME);
        IODelay(10);
        outb(sbMixerDataReg, volVoc);
        IODelay(25);

        outb(sbMixerAddressReg, ES_MIXER_LINE_VOLUME);
        IODelay(10);
        outb(sbMixerDataReg, volLine.rawValue);
        IODelay(25);

        /* Turn on speaker */
        outb(sbWriteDataOrCommandReg, DC16_TURN_ON_SPEAKER);
        IODelay(25);
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
    /* Clear the interrupt by reading data available status register */
    inb(sbDataAvailableStatusReg);

    /*
     * Signal which direction needs service based on current DMA direction
     * For ES1x88: Direction 1 = Output/Playback, Direction 0 = Input/Record
     */
    if (currentDMADirection == DMA_DIRECTION_OUT) {
        *serviceOutput = YES;
    } else {
        *serviceInput = YES;
    }
}

/*
 * Handle timeout if interrupts stop
 */
- (void) timeoutOccurred
{
    unsigned char dspVersion;

    if (interruptTimedOut == NO) {
        /* Reset DSP with value 3 */
        outb(sbResetReg, 3);
        IODelay(10);
        outb(sbResetReg, 0);
        IODelay(10);

        /* Wait for DSP ready and read version */
        if (!waitForDSPDataAvailable()) {
            IOLog("ES1x88AudioDriver: Can not reset DSP.\n");
            interruptTimedOut = YES;
            return;
        }

        dspVersion = inb(sbReadDataReg);
        IODelay(10);

        /* If DSP returned 0xAA ready response, send extended ID command */
        if (dspVersion == (char)ES_DSP_READY_RESPONSE) {
            if (waitForDSPWriteReady()) {
                outb(sbWriteDataOrCommandReg, ES_CMD_EXTENDED_ID);
            }
        } else {
            IOLog("ES1x88AudioDriver: Can not reset DSP.\n");
        }

        interruptTimedOut = YES;
    }
}

/*
 * Select input source
 * Sets the mixer record source register
 * LineIn (201) -> 6, all others -> 0
 */
- (void)setAnalogInputSource:(NXSoundParameterTag) val
{
    unsigned char sourceValue;

    /*
     * ES1x88 mixer record source values:
     * 0 = Microphone
     * 6 = Line In
     */
    if (val == NX_SoundStreamDataAnalogSourceLineIn) {
        sbRecordSource = 6;
        sourceValue = 6;
    } else {
        /* Default to microphone for all other sources */
        sbRecordSource = 0;
        sourceValue = 0;
    }

    /* Program mixer record source register */
    outb(sbMixerAddressReg, ES_MIXER_RECORD_SOURCE);
    IODelay(10);
    outb(sbMixerDataReg, sourceValue);
    IODelay(25);
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
    *lowRate = 4000;
    *highRate = 44100;
}

- (void)getSamplingRates:(int *)rates
                                count:(unsigned int *)numRates
{
    rates[0] = 4000;
    rates[1] = 8000;
    rates[2] = 11025;
    rates[3] = 22050;
    rates[4] = 44100;
    *numRates = 5;
}

- (void)getDataEncodings: (NXSoundParameterTag *)encodings
                                count:(unsigned int *)numEncodings
{
    encodings[0] = NX_SoundStreamDataEncoding_Linear16;
    encodings[1] = NX_SoundStreamDataEncoding_Linear8;
    *numEncodings = 2;
}

- (unsigned int)channelCountLimit
{
    return 2;  /* Stereo support */
}

@end
