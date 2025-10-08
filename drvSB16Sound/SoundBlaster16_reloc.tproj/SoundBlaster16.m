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

static  sb16CardParameters_t sb16CardType;       // hardware type

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
     */
    if ((baseAddress == SB16_BASE_ADDRESS_1) ||
        (baseAddress == SB16_BASE_ADDRESS_2) ||
        (baseAddress == SB16_BASE_ADDRESS_3) ||
        (baseAddress == SB16_BASE_ADDRESS_4))   {
        sb16BaseRegisterAddress = baseAddress;
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


- (BOOL)reset
{
    unsigned int channel8       = [[self deviceDescription] channel];
    unsigned int channel16      = [[self deviceDescription] channelSet];
    unsigned int interrupt      = [[self deviceDescription] interrupt];
    IOReturn ioReturn;

    [self setName:codecDeviceName];
    [self setDeviceKind:codecDeviceKind];

    /* Store DMA channels */
    dma8Channel = channel8;
    dma16Channel = channel16;

    /*
     * Validate user selections for DMA and IRQ
     */
    if (!checkSelectedDMAAndIRQ(dma8Channel, dma16Channel, interrupt)) {
        return NO;
    }

    /*
     * Initialize hardware
     */
    [self initializeHardware];

    /*
     * Check if this is a SB16 or compatible card
     */
    if (sb16CardType.version == SB16_NONE || sb16CardType.majorVersion < 4) {
        IOLog("SoundBlaster16: No Sound Blaster 16 hardware detected at port 0x%0x.\n",
                sb16BaseRegisterAddress);
        return NO;
    }

    IOLog("SoundBlaster16: %s (DSP ver %d.%d) at port 0x%0x.\n",
             sb16CardType.name,
             sb16CardType.majorVersion, sb16CardType.minorVersion,
             sb16BaseRegisterAddress);

    if (sb16CardType.supports16Bit)
        IOLog("SoundBlaster16: 16-bit audio supported.\n");

    if (sb16CardType.supportsAWE)
        IOLog("SoundBlaster16: AWE wavetable synthesis supported.\n");

    /*
     * Initialize 8-bit DMA controller
     */
    [self disableChannel: 0];

    if ([self isEISAPresent]) {
        ioReturn = [self setDMATransferWidth:IO_8Bit forChannel:0];
        if (ioReturn != IO_R_SUCCESS) {
            IOLog("SoundBlaster16: could not set 8-bit transfer width, error %d.\n",
                  ioReturn);
            return NO;
        }
    }

    ioReturn = [self setTransferMode: IO_Single forChannel: 0];
    if (ioReturn != IO_R_SUCCESS)  {
        IOLog("%s: 8-bit dma transfer mode error %d\n", [self name], ioReturn);
        return NO;
    }

    ioReturn = [self setAutoinitialize: YES forChannel: 0];
    if (ioReturn != IO_R_SUCCESS) {
        IOLog("%s: 8-bit dma auto initialize error %d\n", [self name], ioReturn);
        return NO;
    }

    /*
     * Initialize 16-bit DMA controller
     */
    [self disableChannel: 1];

    if ([self isEISAPresent]) {
        ioReturn = [self setDMATransferWidth:IO_16Bit forChannel:1];
        if (ioReturn != IO_R_SUCCESS) {
            IOLog("SoundBlaster16: could not set 16-bit transfer width, error %d.\n",
                  ioReturn);
            return NO;
        }
    }

    ioReturn = [self setTransferMode: IO_Single forChannel: 1];
    if (ioReturn != IO_R_SUCCESS)  {
        IOLog("%s: 16-bit dma transfer mode error %d\n", [self name], ioReturn);
        return NO;
    }

    ioReturn = [self setAutoinitialize: YES forChannel: 1];
    if (ioReturn != IO_R_SUCCESS) {
        IOLog("%s: 16-bit dma auto initialize error %d\n", [self name], ioReturn);
        return NO;
    }

    return YES;
}


- (void) initializeHardware
{
    resetHardware(&sb16CardType);
}

/*
 * Convert gain (0 - 32768) to hardware gain (0 - 3)
 */
- (void)updateInputGainLeft
{
    unsigned int gain = [self inputGainLeft];
    unsigned int left  = 0;

    if (gain)
        left = ((gain * MAX_INPUT_GAIN_16) / 32768);
    else
        left = 0;

    setInputGain(LEFT_CHANNEL, left);
#ifdef DEBUG
    IOLog("%s: updateInputGainLeft %d based on gain %d\n", [self name], left, gain);
#endif DEBUG
}

- (void)updateInputGainRight
{
    unsigned int gain = [self inputGainRight];
    unsigned int right = 0;

    if (gain)
        right = ((gain * MAX_INPUT_GAIN_16) / 32768);
    else
        right = 0;

    setInputGain(RIGHT_CHANNEL, right);
#ifdef DEBUG
    IOLog("%s: updateInputGainRight %d based on gain %d\n", [self name], right, gain);
#endif DEBUG
}

- (void)updateOutputMute
{
    enableAudioOutput(! [self isOutputMuted]);
}

/*
 * Convert (0) - (-84) to hardware range (0) - (31)
 */
- (void) updateOutputAttenuationLeft
{
    unsigned int attenuation = [self outputAttenuationLeft] + 84;
    unsigned int left = 0;

    left = ((attenuation * MAX_MASTER_VOLUME_16) / 84);

    setOutputAttenuation(LEFT_CHANNEL, left);

#ifdef DEBUG
    IOLog("%s: converted left attenuation: %d into %d\n", [self name], attenuation, left);
#endif DEBUG
}

- (void) updateOutputAttenuationRight
{
    unsigned int attenuation = [self outputAttenuationRight] + 84;
    unsigned int right = 0;

    right = ((attenuation * MAX_MASTER_VOLUME_16) / 84);

    setOutputAttenuation(RIGHT_CHANNEL, right);

#ifdef DEBUG
    IOLog("%s: converted right attenuation: %d into %d\n", [self name], attenuation, right);
#endif DEBUG
}

/*
 * Program DSP for sample rate
 */
- (void)updateSampleRate
{
    unsigned int rate = [self sampleRate];

    if (currentDMADirection == DMA_DIRECTION_IN) {
        setCodecSamplingRateInput(rate);
    } else {
        setCodecSamplingRateOutput(rate);
    }
}

/*
 * Set DMA buffer count
 */
- (void) setBufferCount:(int)count
{
    /* Count will be set when starting DMA */
    dmaDescriptorSize = count;
}

- (IOReturn) enableAllInterrupts
{
    enableCodecInterrupts();
    return [super enableAllInterrupts];
}

- (void) disableAllInterrupts
{
   disableCodecInterrupts();
   [super disableAllInterrupts];
}

/*
 * Validate if hardware supports requested mode
 */
- (BOOL)isValidRequest: (BOOL)isRead
{
    unsigned int rate;
    unsigned int encoding;
    unsigned int channelCount;

    rate = [self sampleRate];
    encoding = [self dataEncoding];
    channelCount = [self channelCount];

#ifdef DEBUG
    IOLog("SoundBlaster16: rate: %d channels: %d ", rate, channelCount);

    if (encoding == NX_SoundStreamDataEncoding_Linear16)
        IOLog("encoding: linear 16\n");
    else if (encoding == NX_SoundStreamDataEncoding_Linear8)
        IOLog("encoding: linear 8\n");
    else
        IOLog("encoding: other\n");
#endif DEBUG

    /* Check sample rate range */
    if (encoding == NX_SoundStreamDataEncoding_Linear16) {
        if (rate < SB16_MIN_SAMPLE_RATE_16BIT || rate > SB16_MAX_SAMPLE_RATE_16BIT)
            return NO;
    } else {
        if (rate < SB16_MIN_SAMPLE_RATE_8BIT || rate > SB16_MAX_SAMPLE_RATE_8BIT)
            return NO;
    }

    /* SB16 supports both mono and stereo */
    if (channelCount > 2)
        return NO;

    return YES;
}


- (BOOL) startDMAForChannel: (unsigned int) localChannel
        read: (BOOL) isRead
        buffer: (IOEISADMABuffer) buffer
        bufferSizeForInterrupts: (unsigned int) bufferSize
{
    IOReturn ioReturn;
    unsigned int encoding;
    BOOL isStereo;
    unsigned int actualChannel;

#ifdef DEBUG
    IOLog("SoundBlaster16: startDMAForChannel\n");
#endif DEBUG

    isValidRequest = [self isValidRequest:isRead];

    interruptTimedOut = NO;

    if (isValidRequest == NO)   {
        IOLog("%s: unsupported %s mode.\n", [self name],
                isRead ? "recording" : "playback");

        if (isRead)
            return YES;
        else
            return NO;
    }

    if (isRead)
        currentDMADirection = DMA_DIRECTION_IN;
    else
        currentDMADirection = DMA_DIRECTION_OUT;

    /* Determine if we're using 16-bit mode */
    encoding = [self dataEncoding];
    is16BitTransfer = (encoding == NX_SoundStreamDataEncoding_Linear16);

    /* Determine stereo mode */
    isStereo = ([self channelCount] == 2);

    /* Select appropriate DMA channel */
    if (is16BitTransfer) {
        actualChannel = 1;  /* Use 16-bit DMA */
        useHighDMA = YES;
    } else {
        actualChannel = 0;  /* Use 8-bit DMA */
        useHighDMA = NO;
    }

    /*
     * Mute output while recording
     */
    if (![self isOutputMuted])
        enableAudioOutput(isRead ? NO : YES);

    [self updateSampleRate];

    dmaDescriptorSize = bufferSize;

#ifdef DEBUG
    IOLog("SoundBlaster16: starting %d-bit %s %s.\n",
          is16BitTransfer ? 16 : 8,
          isStereo ? "stereo" : "mono",
          isRead ? "input" : "output");
#endif DEBUG

    ioReturn = [self startDMAForBuffer: buffer channel: actualChannel];

    if (ioReturn != IO_R_SUCCESS) {
        IOLog("%s: could not start DMA channel error %d\n",
                [self name], ioReturn);
        return NO;
    }

    ioReturn = [self enableChannel: actualChannel];

    if (ioReturn != IO_R_SUCCESS) {
        IOLog("%s: could not enable DMA channel error %d\n",
                [self name], ioReturn);
        return NO;
    }

    (void) [self enableAllInterrupts];

    /*
     * Start the DMA transfer
     */
    startDMA(currentDMADirection, is16BitTransfer, isStereo, dmaDescriptorSize);

    return YES;
}

- (void) stopDMAForChannel: (unsigned int) localChannel read: (BOOL) isRead
{
#ifdef DEBUG
    IOLog("SoundBlaster16: stopDMAForChannel\n");
#endif DEBUG

    /*
     * DMA request was denied because of lack of hardware support.
     */
    if (isValidRequest == NO)
        return;

    stopDMA(is16BitTransfer);

    (void)[self disableAllInterrupts];

    /*
     * Disable the appropriate DMA channel
     */
    if (useHighDMA)
        [self disableChannel: 1];
    else
        [self disableChannel: 0];
}

static void clearInterrupts8Bit(void)
{
    /* Acknowledge 8-bit interrupt */
    inb(sb16DataAvailableStatusReg);
}

static void clearInterrupts16Bit(void)
{
    /* Acknowledge 16-bit interrupt */
    inb(sb16Interrupt16BitAckReg);
}

- (IOAudioInterruptClearFunc) interruptClearFunc
{
    /* Return appropriate clear function based on transfer mode */
    return is16BitTransfer ? clearInterrupts16Bit : clearInterrupts8Bit;
}

- (void) interruptOccurredForInput: (BOOL *) serviceInput
                         forOutput: (BOOL *) serviceOutput
{
#ifdef DEBUG
    //IOLog("SoundBlaster16: handleHardwareInterrupt\n");
#endif DEBUG

    /*
     * Acknowledge and clear the interrupt
     */
    if (is16BitTransfer)
        inb(sb16Interrupt16BitAckReg);
    else
        inb(sb16DataAvailableStatusReg);

    /*
     * Signal which direction needs service
     */
    if (currentDMADirection == DMA_DIRECTION_OUT)
        *serviceOutput = YES;
    else
        *serviceInput = YES;
}

/*
 * Handle timeout if interrupts stop
 */
- (void) timeoutOccurred
{
#ifdef DEBUG
    IOLog("%s: timeout occurred.\n", [self name]);
#endif DEBUG

    if (interruptTimedOut == NO) {
        resetDSPQuick();
        interruptTimedOut = YES;
    }
}

/*
 * Select input source
 */
- (void)setAnalogInputSource:(NXSoundParameterTag) val
{
    if (val == NX_SoundDeviceAnalogInputSource_Microphone) {
        setInputLevel(MICROPHONE_LEVEL_INPUT);
    } else if (val == NX_SoundDeviceAnalogInputSource_LineIn) {
        setInputLevel(LINE_LEVEL_INPUT);
    } else if (val == NX_SoundDeviceAnalogInputSource_CD) {
        setInputLevel(CD_LEVEL_INPUT);
    } else {
        setInputLevel(MICROPHONE_LEVEL_INPUT);  // default
    }
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
    *lowRate = SB16_MIN_SAMPLE_RATE_16BIT;
    *highRate = SB16_MAX_SAMPLE_RATE_16BIT;
}

- (void)getSamplingRates:(int *)rates
                                count:(unsigned int *)numRates
{
    rates[0] = 5000;
    rates[1] = 8000;
    rates[2] = 11025;
    rates[3] = 16000;
    rates[4] = 22050;
    rates[5] = 32000;
    rates[6] = 44100;
    *numRates = 7;
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
