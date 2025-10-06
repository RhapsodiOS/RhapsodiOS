/*
 * Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved. 
 *
 * HISTORY
 * 4-Mar-94    Rakesh Dubey at NeXT
 *      Created. 
 */

#import "SoundBlaster8.h"
#import "SoundBlaster8Registers.h"

#import <driverkit/generalFuncs.h>

static const char codecDeviceName[] = "SoundBlaster8";
static const char codecDeviceKind[] = "Audio";

static  sbCardParameters_t sbCardType;	 	// hardware type
static  BOOL lowSpeedDMA;		 	// different programming

/*
 * Include inline functions. 
 */
#import "SoundBlaster8Inline.h"

@implementation SoundBlaster8

/*
 * Probe and initialize new instance 
 */
+ (BOOL) probe:deviceDescription
{
    SoundBlaster8       *dev;
    IORange             *portRangeList;
    int                 numPortRanges;
    unsigned int        baseAddress;

#ifdef DEBUG
    int                 i;
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
        IOLog("SoundBlaster8: port %x %d\n",
                portRangeList[i].start, portRangeList[i].size);
    }
#endif DEBUG

    baseAddress = portRangeList[0].start;
#ifdef DEBUG
    IOLog("SoundBlaster8: Base address = 0x%x.\n", baseAddress);
#endif DEBUG


    /*
     * Check base address to verify if this is a legal address.
     */

    if ((baseAddress == SB_BASE_ADDRESS_1) ||
        (baseAddress == SB_BASE_ADDRESS_2) ||
        (baseAddress == SB_BASE_ADDRESS_3) ||
        (baseAddress == SB_BASE_ADDRESS_4) ||
        (baseAddress == SB_BASE_ADDRESS_5) ||
        (baseAddress == SB_BASE_ADDRESS_6))     {
        sbBaseRegisterAddress = baseAddress;
    } else {
        IOLog("SoundBlaster8: Invalid port address 0x%0x.\n", baseAddress);
        [dev free];
        return NO;
    }

    /*
     * Now assign all SB DSP and Mixer registers their addresses.
     */
    assignDSPRegAddresses();
    assignMixerRegAddresses();
    
    return [dev initFromDeviceDescription:deviceDescription] != nil;
}


- (BOOL)reset
{
    unsigned int channel        = [[self deviceDescription] channel];
    unsigned int interrupt      = [[self deviceDescription] interrupt];

    IOReturn ioReturn;

    [self setName:codecDeviceName];
    [self setDeviceKind:codecDeviceKind];

    /*
     * Are user selections valid?
     */
    if (checkSelectedDMAAndIRQ(channel, interrupt) == NO) {
	return NO;
    }
    
    /*
     * Now that all hardware parameters have been assigned and/or verified
     * initialize the hardware.
     */
    [self initializeHardware];

    /*
     * This driver is only for 8-bit Sound Blaster cards. If this is not one
     * of these systems we quit since the test is fully reliable.
     */
    
    switch (sbCardType.version) {
      case SB_CLASSIC:
        sbCardType.name = "Classic";
        break;
      case SB_20:
        sbCardType.name = "2.0";
        break;
      case SB_PRO:
        sbCardType.name = "Pro";
        break;
      case SB_16:
        sbCardType.name = "Pro";
        sbCardType.version = SB_PRO;    /* SB16 will emulate it */
        break;
      default:  {
        IOLog("SoundBlaster8: Hardware not detected at port 0x%0x.\n",
		sbBaseRegisterAddress);
        return NO;
      }
    }
    
    IOLog("SoundBlaster8: Sound Blaster %s (ver %d.%d) at port 0x%0x.\n", 
		 sbCardType.name, 
		 sbCardType.majorVersion, sbCardType.minorVersion, 
		 sbBaseRegisterAddress);
    
    /*
     * Initialize DMA controller.
     */
     
    [self disableChannel: 0];

    /*
     * This call is only applicable in EISA systems. All dma channels
     * that are available to this driver in ISA machines are 8-bit. So we do
     * this setup only for EISA machines. 
     */
    if ([self isEISAPresent]) {
        ioReturn = [self setDMATransferWidth:IO_8Bit forChannel:0];
        if (ioReturn != IO_R_SUCCESS) {
            IOLog("SoundBlaster8: could not set transfer width to 8 bits, error %d.\n", ioReturn);
            return NO;
        }
    }
    
    ioReturn = [self setTransferMode: IO_Single forChannel: 0];
    if (ioReturn != IO_R_SUCCESS)  {
        IOLog("%s: dma transfer mode error %d\n", [self name], ioReturn);
        return NO;
    }

    /*
     * We will program the DMA controller in auto-init mode but the card is
     * in single cycle mode. So at every interrupt we only need to reprogram
     * the card.
     */
    ioReturn = [self setAutoinitialize: YES forChannel: 0];
    if (ioReturn != IO_R_SUCCESS) {
        IOLog("%s: dma auto initialize error %d", [self name], ioReturn);
        return NO;
    }
    
    return YES;
}


- (void) initializeHardware
{
    resetHardware();
}

/*
 * Converts gain (0 - 32768) into hardware supported gain (0 - 7). If the
 * input source is line (not supported now), simply double the gain. 
 */

- (void)updateInputGainLeft
{
    unsigned int gain = [self inputGainLeft];
    unsigned int left  = 0;
    
    if (gain)
        left = ((gain * MAX_INPUT_GAIN_MICROPHONE)/32768);
    else
        left = gain;    // minimum input gain = 0
        
    setInputGain(LEFT_CHANNEL, left);
#ifdef DEBUG
    IOLog("%s: updateInputGainLeft %d based on gain %d\n", [self name],left, gain);
#endif DEBUG
}

/*
 * Converts gain (0 - 32768) into hardware supported gain (0 - 7)
 */

- (void)updateInputGainRight
{
    unsigned int gain = [self inputGainRight];
    unsigned int right = 0;
    
    if (gain)
        right = ((gain * MAX_INPUT_GAIN_MICROPHONE)/32768);
    else
        right = gain;   // minimum input gain = 0
        
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
 * (0) - (-84) needs to be converted to hardware supported (0) - (15)
 */
- (void) updateOutputAttenuationLeft
{
    unsigned int attenuation = [self outputAttenuationLeft] + 84;
    unsigned int left = 0;
    
    left = ((attenuation * MAX_MASTER_OUTPUT_VOLUME)/84);
   
    setOutputAttenuation(LEFT_CHANNEL, left);
    
#ifdef DEBUG
    IOLog("%s: converted la: %d into %d\n", [self name], attenuation, left);
#endif DEBUG
}

/*
 * (0) - (-84) needs to be converted to hardware supported (0) - (15)
 */
- (void) updateOutputAttenuationRight
{
    unsigned int attenuation = [self outputAttenuationRight] + 84;
    unsigned int right = 0;
    
    right = ((attenuation * MAX_MASTER_OUTPUT_VOLUME)/84);
    
    setOutputAttenuation(RIGHT_CHANNEL, right);
   
#ifdef DEBUG
    IOLog("SoundBlaster8: converted ra: %d into %d\n", attenuation, right);
#endif DEBUG
}

/*
 * Program DSP.
 */
- (void)updateSampleRate
{
    unsigned int rate;
    unsigned int mode;
    
    rate = [self sampleRate];
    mode = ([self channelCount] == 2) ? DSP_STEREO_MODE : DSP_MONO_MODE;

    /*
     * Programming sequence depends upon whether we are doing a low speed or
     * high speed transfer. Rather messy, see SB SDK page 12-5.
     */
    if (sbCardType.version == SB_CLASSIC) {
	lowSpeedDMA = YES;
    } else if (sbCardType.version == SB_20) {
	if (currentDMADirection == DMA_DIRECTION_IN)
	    lowSpeedDMA = (rate < SB_20_LOW_SPEED_RECORD) ? YES : NO;
	else
	    lowSpeedDMA = (rate < SB_20_LOW_SPEED_PLAYBACK) ? YES : NO;
    } else if (sbCardType.version == SB_PRO) {
        if (mode == DSP_STEREO_MODE)
	    rate *= 2;
	lowSpeedDMA = (rate < SB_PRO_LOW_SPEED) ? YES : NO;
    }
    
    setCodecDataMode(mode, currentDMADirection);
    setCodecSamplingRate(rate);
}


/*
 * Sets the DMA Counter Load register which decides when the next interrupt
 * will arrive.
 */
- (void) setBufferCount:(int)count
{
    setSampleBufferCounter(count);      
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
 * Return NO if the hardware does not support this particular playback/record
 * request. The parameter scheme in soundkit does not fit the anarchy
 * of PC world very well.
 */
- (BOOL)isValidRequest: (BOOL)isRead
{
    unsigned int rate;
    unsigned int mode;
    unsigned int encoding;
    
    rate = [self sampleRate];
    encoding = [self dataEncoding];
    mode = ([self channelCount] == 2) ? DSP_STEREO_MODE : DSP_MONO_MODE;

#ifdef DEBUG
    IOLog("SoundBlaster8: rate: %d ", rate);
    
    if (mode == DSP_MONO_MODE)
        IOLog("dataMode: mono ");
    else if (mode == DSP_STEREO_MODE)
        IOLog("dataMode: stereo ");
    else
        IOLog("dataMode: unknown ");
        
    if (encoding == NX_SoundStreamDataEncoding_Linear16)
        IOLog("dataEncoding: linear 16\n");
    else if (encoding == NX_SoundStreamDataEncoding_Linear8)
        IOLog("dataEncoding: linear 8\n");
    else if (encoding == NX_SoundStreamDataEncoding_Mulaw8)
        IOLog("dataEncoding: mulaw 8\n");
    else if (encoding == NX_SoundStreamDataEncoding_Alaw8)
        IOLog("dataEncoding: Alaw 8\n");
    else
        IOLog("dataEncoding: unknown\n");
#endif DEBUG
	
    if (sbCardType.version == SB_PRO) {
        if ((mode == DSP_STEREO_MODE) &&
            (rate > SB_PRO_LOW_SPEED))
            return NO;          
    }
    
    if (sbCardType.version == SB_20) {
	if (isRead && rate > SB_20_LOW_SPEED_RECORD)
	    return NO;
    }
                
    if (sbCardType.version == SB_CLASSIC) {
	if (isRead && rate > SB_CLASSIC_MAX_SPEED_RECORD)
	    return NO;
	if (!isRead && rate > SB_CLASSIC_MAX_SPEED_PLAYBACK)
	    return NO;
    }
    
    return YES;
}


- (BOOL) startDMAForChannel: (unsigned int) localChannel
        read: (BOOL) isRead
        buffer: (IOEISADMABuffer) buffer
        bufferSizeForInterrupts: (unsigned int) bufferSize
{
    IOReturn ioReturn;
    
#ifdef DEBUG
    IOLog("SoundBlaster8: startDMAForChannel\n");
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

    /*
     * Output must be off while recording. 
     */
    if (![self isOutputMuted])
	enableAudioOutput(isRead ? NO : YES);

    [self updateSampleRate];
    
    dmaDescriptorSize = bufferSize;	// used by interrupt handler
            
#ifdef DEBUG
    if (lowSpeedDMA)
        IOLog("SoundBlaster8: starting low speed DMA ");
    else
        IOLog("SoundBlaster8: starting high speed DMA ");
        
    if (isRead)
        IOLog("input.\n");
    else
        IOLog("output.\n");
#endif DEBUG

    ioReturn = [self startDMAForBuffer: buffer channel: localChannel];

    if (ioReturn != IO_R_SUCCESS) {
        IOLog("%s: could not start DMA channel error %d\n",
                [self name], ioReturn);
        return NO;
    }
        
    ioReturn = [self enableChannel: localChannel];
    
    if (ioReturn != IO_R_SUCCESS) {
        IOLog("%s: could not enable DMA channel error %d\n",
                [self name], ioReturn);
        return NO;
    }

    (void) [self enableAllInterrupts];

    /*
     * The order is important here. See SB SDK page 12-8 and 12-13. 
     */
    if (lowSpeedDMA)    {
        if (isRead) {
            startDMA(DMA_DIRECTION_IN);
        } else {
            startDMA(DMA_DIRECTION_OUT);
        }
        [self setBufferCount: dmaDescriptorSize];
    } else {
        [self setBufferCount: dmaDescriptorSize];
        if (isRead) {
            startDMA(DMA_DIRECTION_IN);
        } else {
            startDMA(DMA_DIRECTION_OUT);
        }
    }
    
    return YES;
}

- (void) stopDMAForChannel: (unsigned int) localChannel read: (BOOL) isRead
{
#ifdef DEBUG
    IOLog("SoundBlaster8: stopDMAForChannel\n");
#endif DEBUG

    /*
     * DMA request was denied bacause of lack of hardware support. 
     */
    if (isValidRequest == NO)
        return;
    
    if (isRead) {
        stopDMAInput();
    } else {
        stopDMAOutput();
    }
    
    (void)[self disableAllInterrupts];
    
    /*
     * Disable channel only after disabling capture and playback. 
     */
    [self disableChannel: localChannel];
    
    /*
     * Reset DSP to stop high speed DMA transfer. This is necessary since the
     * current "DMA block" might be continuing in case the transfer was
     * interrupted. 
     */
    if (lowSpeedDMA == NO) {
	resetDSPQuick();
    }
}

static void clearInterrupts(void)
{
    /*
     * Acknowledge and clear the interrupt.
     */

    inb(sbDataAvailableStatusReg);
}

- (IOAudioInterruptClearFunc) interruptClearFunc
{
    return clearInterrupts;
}

- (void) interruptOccurredForInput: (BOOL *) serviceInput  
                         forOutput: (BOOL *) serviceOutput
{
#ifdef DEBUG
    IOLog("SoundBlaster8: handleHardwareInterrupt\n");
#endif DEBUG
    
    /*
     * Acknowledge and clear the interrupt.
     */

    inb(sbDataAvailableStatusReg);
    
    /*
     * We do not have simultaneous playback and record in SB.
     */
    if (currentDMADirection == DMA_DIRECTION_OUT)
        *serviceOutput = YES;
    else
        *serviceInput = YES;
        
    if (lowSpeedDMA)    {
        if (currentDMADirection == DMA_DIRECTION_IN) {
            startDMA(DMA_DIRECTION_IN);
        } else {
            startDMA(DMA_DIRECTION_OUT);
        }
        [self setBufferCount: dmaDescriptorSize];	/* needed here */
    } else {
        //[self setBufferCount: dmaDescriptorSize]; 	/* but not here */
        if (currentDMADirection == DMA_DIRECTION_IN) {
            startDMA(DMA_DIRECTION_IN);
        } else {
            startDMA(DMA_DIRECTION_OUT);
        }
    }
}

/*
 * This routine will be called if interrupts are not being received. Some
 * cards seem to lock up once in a while. 
 */
- (void) timeoutOccurred
{
#ifdef DEBUG
    IOLog("%s: timeout occurred.\n", [self name]);
#endif DEBUG

    if (interruptTimedOut == NO) {
	resetDSPQuick();
	interruptTimedOut = YES;		// reset only once
    }
}

/*
 * Choose between different input sources.
 */
 
- (void)setAnalogInputSource:(NXSoundParameterTag) val
{
    if (val == NX_SoundDeviceAnalogInputSource_Microphone) {
        setInputLevel(MICROPHONE_LEVEL_INPUT);
    } else if (val == NX_SoundDeviceAnalogInputSource_LineIn) {
        setInputLevel(LINE_LEVEL_INPUT);
    } else {
        setInputLevel(MICROPHONE_LEVEL_INPUT);  // default
    }
}

/*
 * Parameter access.
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
    /* Return some supported rates */
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
    encodings[0] = NX_SoundStreamDataEncoding_Linear8;
    *numEncodings = 1;
}

- (unsigned int)channelCountLimit
{
    return (sbCardType.version == SB_PRO) ? 2 : 1;      /* stereo and mono */
}

@end

