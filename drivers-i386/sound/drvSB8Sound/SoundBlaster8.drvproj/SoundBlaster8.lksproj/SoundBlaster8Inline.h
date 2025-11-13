/*
 * Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved. 
 *
 * HISTORY
 * 18-Sep-95    Rakesh Dubey at NeXT
 *      Some mixer related minor changes. 
 * 4-Mar-94    Rakesh Dubey at NeXT
 *      Created. 
 */

/*
 * Base address. 
 */
static unsigned int sbBaseRegisterAddress = 0;

/*
 * Register addresses. The base register addressess are determined at
 * run-time. 
 */

static unsigned int sbResetReg = 0;
static unsigned int sbReadDataReg = 0;
static unsigned int sbWriteDataOrCommandReg = 0;

static unsigned int sbWriteBufferStatusReg = 0;
static unsigned int sbDataAvailableStatusReg = 0;

static __inline__
void
assignDSPRegAddresses(void)
{
    sbResetReg = 
        (sbBaseRegisterAddress + SB_DSP_RESET_OFFSET);
    sbReadDataReg = 
        (sbBaseRegisterAddress + SB_DSP_READ_DATA_OFFSET);
    sbWriteDataOrCommandReg = 
        (sbBaseRegisterAddress + SB_DSP_WRITE_DATA_OR_COMMAND_OFFSET);
        
    sbWriteBufferStatusReg = 
        (sbBaseRegisterAddress + SB_DSP_WRITE_BUFFER_STATUS_OFFSET);
    sbDataAvailableStatusReg = 
        (sbBaseRegisterAddress + SB_DSP_DATA_AVAILABLE_STATUS_OFFSET);
}


/*
 * Print what is being written. 
 */
static __inline__
void
outbV(unsigned int address, unsigned int data)
{
#ifdef DEBUG
    IOLog("SoundBlaster8: Writing %x at address %x\n", data, address);
#endif DEBUG
    outb(address, data);
}

static unsigned int sbMixerAddressReg = 0;
static unsigned int sbMixerDataReg = 0;

static __inline__
void
assignMixerRegAddresses(void)
{
    sbMixerAddressReg = 
        (sbBaseRegisterAddress + SB_MIXER_ADDRESS_OFFSET);
    sbMixerDataReg = 
        (sbBaseRegisterAddress + SB_MIXER_DATA_OFFSET);
}

/*
 * Shadow registers for volume. Add more to this list when necessary. 
 */

static sbStereoMixerRegister_t volMaster = 	{0};
static sbStereoMixerRegister_t volFM = 		{0};
static sbStereoMixerRegister_t volLine = 	{0};
static sbStereoMixerRegister_t volVoc = 	{0};
static sbStereoMixerRegister_t volCD = 		{0};

static sbMonoMixerRegister_t volMic = 		{0};

static sbRecordingMode_t sbRecord = 		{0};
static sbPlaybackMode_t sbPlayback = 		{0};


#define MAX_WAIT_FOR_DATA_AVAILABLE     	2000
#define SB_WAIT_DELAY                   	10
#define SB_RESET_DELAY                  	100

static  __inline__
BOOL
dspReadWait()
{
    int     i;
    unsigned int val;

    for (i = 0; i < MAX_WAIT_FOR_DATA_AVAILABLE; i++) {
	IODelay(SB_WAIT_DELAY);
	val = inb(sbDataAvailableStatusReg);
	if (val & 0x080)   /* MSB == 1 before reading */
	    return YES;
    }

    /* Reset DSP, hopefully we will recover. */
    outbV(sbResetReg, 0x01);
    IODelay(SB_ADDRESS_WRITE_DELAY);
    outbV(sbResetReg, 0x00);
    IODelay(SB_ADDRESS_WRITE_DELAY);
    IODelay(SB_RESET_DELAY);

#ifdef DEBUG
    IOLog("SoundBlaster8: DSP not ready for reading!\n");
#endif DEBUG

    return NO;
}

static __inline__
BOOL 
dspWriteWait()
{
    int     i;
    unsigned int val;

    for (i = 0; i < MAX_WAIT_FOR_DATA_AVAILABLE; i++) {
	IODelay(SB_WAIT_DELAY);
	val = inb(sbWriteBufferStatusReg);
	if (!(val & 0x080))	/* MSB == 0 before writing */
	    return YES;
    }

    /* Reset DSP */
    outbV(sbResetReg, 0x01);
    IODelay(SB_ADDRESS_WRITE_DELAY);
    outbV(sbResetReg, 0x00);
    IODelay(SB_ADDRESS_WRITE_DELAY);
    IODelay(SB_RESET_DELAY);

#ifdef DEBUG
    IOLog("SoundBlaster8: DSP not ready for writing!\n");
#endif DEBUG

    return NO;
}

/*
 * Send some data or command to SoundBlaster8 DSP. 
 */
static
BOOL
writeToDSP(unsigned int dataOrCommand)
{
    outbV(sbWriteDataOrCommandReg, dataOrCommand);
    IODelay(SB_DATA_WRITE_DELAY);

#ifdef DEBUG
    //IOLog("SoundBlaster8: Wrote DSP command %x\n", dataOrCommand);
#endif DEBUG

    return YES;
}

/*
 * Read from the SoundBlaster DSP. 
 */
static
unsigned int
readFromDSP(void)
{
    unsigned int val;
    
    val = inb(sbReadDataReg);
    IODelay(SB_DATA_READ_DELAY);

#ifdef DEBUG
    IOLog("SoundBlaster8: read from DSP %x\n", val);
#endif DEBUG

    return val;
}
    
/*
 * Function to read from the Mixer registers. 
 */
static __inline__
unsigned int
inbIXMixer(unsigned int address)
{
    unsigned int val = 0xff;
        
    outbV(sbMixerAddressReg, address);
    IODelay(SB_ADDRESS_WRITE_DELAY);
    val = inb(sbMixerDataReg);
    
#ifdef DEBUG
    IOLog("SoundBlaster8: Mixer address %x. Read %x\n", address, val);
#endif DEBUG
    return val;
}

/*
 * Function to write to the Mixer registers. 
 */
static  __inline__
void
outbIXMixer(unsigned int address, unsigned int val)
{
    outbV(sbMixerAddressReg, address);
    IODelay(SB_ADDRESS_WRITE_DELAY);
    outbV(sbMixerDataReg, val);
    IODelay(SB_DATA_WRITE_DELAY);

#ifdef DEBUG
    IOLog("SoundBlaster8: Mixer address %x. Wrote %x\n", address, val);
#endif DEBUG
}

/*
 * Initialize DSP registers. There aren't any.
 */

static __inline__
void
initDSPRegisters(void)
{
}

/*
 * Initialize the registers on the Mixer. 
 */

static __inline__
void
initMixerRegisters(void)
{
    if (sbCardType.mixerPresent == NO)
        return;

#ifdef DEBUG
    IOLog("SoundBlaster8: Initializing mixer registers.\n");
#endif DEBUG

    /*
     * First set the volume controlling registers to their default values. 
     */
    volMaster.reg.left = 10;
    volMaster.reg.right = 10;
    outbIXMixer(MC_MASTER_VOLUME, volMaster.data);
    
    volFM.reg.left = 0;
    volFM.reg.right = 0;
    outbIXMixer(MC_FM_VOLUME, volFM.data);
    
    volCD.reg.left = 0;
    volCD.reg.right = 0;
    outbIXMixer(MC_CD_VOLUME, volCD.data);
    
    volLine.reg.left = 0;
    volLine.reg.right = 0;
    outbIXMixer(MC_LINE_VOLUME, volLine.data);
    
    volVoc.reg.left = 10;
    volVoc.reg.right = 10;
    outbIXMixer(MC_VOC_VOLUME, volVoc.data);
    
    /* Microphone can go only upto 7. */
    volMic = 6;
    outbIXMixer(MC_MICROPHONE_VOLUME, volMic);
    
    /* 
     * Now set the record and playback mode registers.
     */
    sbRecord.data = 0;
    sbRecord.reg.source = SB_RECORD_SOURCE_MIC;
    sbRecord.reg.inputFilter = SB_RECORD_ANFI_OFF;
    sbRecord.reg.highFreq = SB_RECORD_FREQ_HIGH;
    outbIXMixer(MC_RECORD_CONTROL, sbRecord.data);
    
    sbPlayback.data = 0;
    sbPlayback.reg.outputFilter = SB_PLAYBACK_DNFI_OFF;
    sbPlayback.reg.stereo = SB_PLAYBACK_STEREO;
    outbIXMixer(MC_PLAYBACK_CONTROL, sbPlayback.data);
}

/*
 * Input can be either microphone level or line level. We don't support other
 * inputs. 
 */

static __inline__
void
setInputLevel(unsigned int level)
{
    if (sbCardType.mixerPresent == NO)
        return;
        
    if (level == LINE_LEVEL_INPUT)      {
        sbRecord.reg.source = SB_RECORD_SOURCE_LINE;
    } else {
        sbRecord.reg.source = SB_RECORD_SOURCE_MIC;
    }
    
    outbIXMixer(MC_RECORD_CONTROL, sbRecord.data);
}

/*
 * Output level cannot be changed. 
 */

static __inline__
void
setOutputLevel(unsigned int channel, unsigned int level)
{
#ifdef DEBUG
    IOLog("SoundBlaster8: Audio output level is fixed.\n");
#endif DEBUG
}

/*
 * Initialize the hardware registers. 
 */
static __inline__
void 
initRegisters(void)
{
    initDSPRegisters();
    initMixerRegisters();
}


/*
 * These two routines are used to avoid clicks. 
 */

static __inline__
void 
muteOutput(void)
{
    if (sbCardType.mixerPresent == NO)
        return;
                
    outbIXMixer(MC_MASTER_VOLUME, 0);
    outbIXMixer(MC_CD_VOLUME, 0);
    outbIXMixer(MC_VOC_VOLUME, 0);
    outbIXMixer(MC_LINE_VOLUME, 0);
}

/*
 * This takes it back to the old values. So it is not exactly unmute.
 */
static __inline__
void 
unMuteOutput(void)
{
    if (sbCardType.mixerPresent == NO)
        return;
        
    outbIXMixer(MC_MASTER_VOLUME, volMaster.data);
    outbIXMixer(MC_CD_VOLUME, volCD.data);
    outbIXMixer(MC_VOC_VOLUME, volVoc.data);
    outbIXMixer(MC_LINE_VOLUME, volLine.data);
}

/*
 * This routine does a quick reset of the card. This is needed because
 * apparently the SoundBlaster8 cards need to be reset if you go from the
 * high speed to the low speed mode (wonderful world of hardware). 
 */

static __inline__
void
resetDSPQuick(void)
{
    outbV(sbResetReg, 0x01);
    IODelay(SB_ADDRESS_WRITE_DELAY);
    outbV(sbResetReg, 0x00);
    IODelay(SB_ADDRESS_WRITE_DELAY);
    
    /* It takes about 100us to reset */
    dspReadWait();
    if (readFromDSP() != 0xaa)    {
        IOLog("SoundBlaster8: Can not reset DSP.\n");
    }
}


#define SB_DELAY                       		100
#define MAX_RESET_WAIT                  	1000

/*
 * Reset the SoundBlaster card. This routine also detects if the card is
 * present and the type of card. 
 */
static __inline__
void
resetDSP(void)
{
    unsigned int val;

    /*
     * Assume no sound card in the system. 
     */
    sbCardType.version = SB_NONE;
    sbCardType.name = "";
    sbCardType.majorVersion = 0;
    sbCardType.minorVersion = 0;
    sbCardType.mixerPresent = NO;
    
    outbV(sbResetReg, 0x01);
    IODelay(SB_ADDRESS_WRITE_DELAY);
    outbV(sbResetReg, 0x00);
    IODelay(SB_ADDRESS_WRITE_DELAY);
    
    /* Now we can read the data. */
    dspReadWait();
    val = readFromDSP();
    if (val == 0xaa)    {
#ifdef DEBUG
        IOLog("SoundBlaster8: DSP detected.\n");
#endif DEBUG
        IOSleep(1);
    } else {
#ifdef DEBUG
        IOLog("SoundBlaster8: Read ID %x is wrong.\n", val);
        IOLog("SoundBlaster8: SoundBlaster not detected at address 0x%0x.\n", 
                sbBaseRegisterAddress);
#endif DEBUG
        return;
    }

    /*
     * We have a SoundBlaster card. We will upgrade it to a pro if we detect
     * a mixer as well. 
     */
    sbCardType.version = SB_CLASSIC;

    /*
     * Another confirmatory test here. This is not documented in the SB SDK
     * so it might fail on some compatible cards. Maybe we should just print
     * a warning message if this test fails. 
     */
    dspWriteWait();
    writeToDSP(DC_INVERT_BYTE);
    
    dspWriteWait();
    writeToDSP(0x43);   /* Send some test pattern. */
    
    dspReadWait();
    val = readFromDSP();
    
    if (val == 0xbc)    {
#ifdef DEBUG
        IOLog("SoundBlaster8: Invert test passed.\n");
#endif DEBUG
    } else      {
#ifdef DEBUG
        IOLog("SoundBlaster8: Invert test failed!!\n");
        IOLog("SoundBlaster8: SoundBlaster not detected at address 0x%0x.\n", 
                sbBaseRegisterAddress);
#endif DEBUG
    }

    /*
     * Reset the DSP here because sometimes you may get crazy values as
     * version. So just to be on the safe side.. 
     */
    resetDSPQuick();
    
    /*
     * Now we know that a SoundBlaster or compatible card exists. We need to
     * find the version number to decide the type of card.
     */
    dspWriteWait();
    writeToDSP(DC_GET_VERSION);

    dspReadWait();
    sbCardType.majorVersion = readFromDSP() & 0x0f;
    sbCardType.minorVersion = readFromDSP() & 0x0f;
    
#ifdef DEBUG
    //IOLog("SoundBlaster8: Major 0x%x Minor 0x%x\n", sbCardType.majorVersion, sbCardType.minorVersion);
#endif DEBUG

    /*
     * Upgrade the card to SB_20 or SB_16 depending upon what the version
     * number reads. 
     */
    if (sbCardType.majorVersion >= 2)
        sbCardType.version = SB_20;
 
    if (sbCardType.majorVersion >= 4)
        sbCardType.version = SB_16;
}

static __inline__
void
resetMixer(void)
{
    unsigned int val1, val2;
    
    /*
     * Reset the mixer by sending zero to both address and data ports.
     */
     outbIXMixer(0x0, 0x0);

    /*
     * Now try to write and then read from one of the mixer registers. 
     */
     outbIXMixer(MC_MASTER_VOLUME, 0x15);
     outbIXMixer(MC_MICROPHONE_VOLUME, 0x13);
     
     val1 = inbIXMixer(MC_MASTER_VOLUME);
     val2 = inbIXMixer(MC_MICROPHONE_VOLUME);

    if ((val1 == 0x15) && (val2 == 0x13)) {
	sbCardType.mixerPresent = YES;
    } else {
	sbCardType.mixerPresent = NO;
    }
                
    /*
     * Try once more, so that we are really sure. 
     */
     outbIXMixer(MC_LINE_VOLUME, 0x17);
     outbIXMixer(MC_FM_VOLUME, 0x19);

     val1 = inbIXMixer(MC_LINE_VOLUME);
     val2 = inbIXMixer(MC_FM_VOLUME);

    if ((val1 == 0x17) && (val2 == 0x19)) {
	sbCardType.mixerPresent = YES;
    } else {
	sbCardType.mixerPresent = NO;
    }

    /*
     * We have a pro card if we found the mixer. 
     */
    if (sbCardType.mixerPresent == YES) {
        sbCardType.version = SB_PRO;
        outbIXMixer(0x0, 0x0);          /* reset the mixer to a good state */
    }
     
#ifdef DEBUG
     if (sbCardType.mixerPresent == YES)
        IOLog("SoundBlaster8: Mixer detected.\n");
     else
        IOLog("SoundBlaster8: Mixer not detected.\n");
#endif DEBUG
}

/*
 * Reset all hardware and bring us back to the default state. 
 */
static __inline__
void 
resetHardware(void)
{
    resetDSP();
    resetMixer();
    initRegisters();
}

/*
 * There seems to be no way to change input gain. Also note that recording is
 * only possible from Microphone. 
 */
static  __inline__
void 
setInputGain(unsigned int channel, unsigned int gain)
{
    if (sbCardType.mixerPresent == NO)
        return;
        
    volMic = gain;
    outbIXMixer(MC_MICROPHONE_VOLUME, volMic);
    
#ifdef DEBUG
    IOLog("SoundBlaster8: set input gain %d\n", gain);
#endif DEBUG
}

static  __inline__
void
setOutputAttenuation(unsigned int channel, unsigned int attenuation)
{
    if (sbCardType.mixerPresent == NO)
        return;
        
    if (channel == LEFT_CHANNEL) {
	volMaster.reg.left = volCD.reg.left = attenuation;
	volVoc.reg.left = volLine.reg.left = attenuation;
        outbIXMixer(MC_MASTER_VOLUME, volMaster.data);
        outbIXMixer(MC_CD_VOLUME, volCD.data);
        outbIXMixer(MC_VOC_VOLUME, volVoc.data);
	outbIXMixer(MC_LINE_VOLUME, volLine.data);
    } else {
	volMaster.reg.right = volCD.reg.right = attenuation;
	volVoc.reg.right = volLine.reg.right = attenuation;
        outbIXMixer(MC_MASTER_VOLUME, volMaster.data);
        outbIXMixer(MC_CD_VOLUME, volCD.data);
        outbIXMixer(MC_VOC_VOLUME, volVoc.data);
	outbIXMixer(MC_LINE_VOLUME, volLine.data);
    }
#ifdef DEBUG
    IOLog("SoundBlaster8: set output attenuation %d\n", attenuation);
#endif DEBUG
}

static __inline__
void
enableAudioOutput(BOOL enable)
{
    if (sbCardType.mixerPresent == YES)	{
	(enable) ? unMuteOutput() : muteOutput();
    }

    /*
     * Now enable sound output in the DSP. 
     */
    (enable) ? writeToDSP(DC_TURN_ON_SPEAKER) : 
	    writeToDSP( DC_TURN_OFF_SPEAKER);
}

static  __inline__
void    setSampleBufferCounter(unsigned int count)
{
    if (!lowSpeedDMA)	{
	dspWriteWait();
        writeToDSP(DC_SET_BLOCK_SIZE);
    } 
    
    count -= 1;
    dspWriteWait();
    writeToDSP(count & 0x0ff);
    dspWriteWait();
    writeToDSP((count >> 8) & 0x0ff);
#ifdef DEBUG
    //IOLog("SoundBlaster8: buffer counter set to %x\n", count);
#endif DEBUG
}

/*
 * Start DMA. Command patterns are different depending upon whether we are
 * doing low speed or high speed transfers. 
 */
     
static __inline__
void startDMA(unsigned int direction)
{       
    dspWriteWait();
    if (lowSpeedDMA)    {
        if (direction == DMA_DIRECTION_IN) 
            writeToDSP(DC_START_LS_DMA_ADC_8);
        else
            writeToDSP(DC_START_LS_DMA_DAC_8);
    } else {
        if (direction == DMA_DIRECTION_IN) 
            writeToDSP(DC_START_HS_DMA_ADC_8);
        else
            writeToDSP(DC_START_HS_DMA_DAC_8);
    }
}

/* No can do */
static __inline__
void enableCodecInterrupts(void)
{
}

static __inline__
void disableCodecInterrupts(void)
{
}

static __inline__
void stopDMA(void)
{
    writeToDSP(DC_HALT_DMA);
}

/*
 * This routine will stop input dma. 
 */
static __inline__
void stopDMAInput(void)
{
    stopDMA();
}

/*
 * Likewise, but for output dma. 
 */
static __inline__
void stopDMAOutput(void)
{
    stopDMA();
}

/*
 * Select between DSP_MONO_MODE and DSP_STEREO_MODE mode. Note that stereo
 * recording is undocumented so it could potentially break on some clone
 * cards. 
 */
static __inline__
void setCodecDataMode(unsigned int mode, unsigned int dir)
{
    if (sbCardType.mixerPresent == NO)
        return;
        
    if (dir == DMA_DIRECTION_OUT) {
	if (mode == DSP_STEREO_MODE) {
	    sbPlayback.reg.stereo = SB_PLAYBACK_STEREO;
	} else {
	    sbPlayback.reg.stereo = SB_PLAYBACK_MONO;
	}
	outbIXMixer(MC_PLAYBACK_CONTROL, sbPlayback.data);
    } else if (dir == DMA_DIRECTION_IN)	{
	dspWriteWait();
	if (mode == DSP_STEREO_MODE) {
	    writeToDSP(DC_RECORD_IN_STEREO);
	} else {
	    writeToDSP(DC_RECORD_IN_MONO);
	}
    }
}


static __inline__
void setCodecSamplingRate(unsigned int rate)
{
    unsigned int timeConstant;
    
    /* Sanity check. */
    if (rate < SB_MIN_SAMPLE_RATE)
        rate = SB_MIN_SAMPLE_RATE;
    else if (rate > SB_MAX_SAMPLE_RATE)
        rate = SB_MAX_SAMPLE_RATE;
        
    dspWriteWait();
    if (lowSpeedDMA)    {
        timeConstant = 256 - (1000*1000)/rate;
        writeToDSP(DC_SET_TIME_CONSTANT);
	dspWriteWait();
        writeToDSP(timeConstant);
#ifdef DEBUG
    IOLog("SoundBlaster8: Sample rate = %u, timeConstant = %x\n", rate, timeConstant);
#endif DEBUG
    } else {
        timeConstant = 65536 - (256*1000*1000)/rate;
        writeToDSP(DC_SET_TIME_CONSTANT);
	dspWriteWait();
        writeToDSP(timeConstant >> 8);
#ifdef DEBUG
    IOLog("SoundBlaster8: Sample rate = %u, timeConstant = %x\n", rate, timeConstant >> 8);
#endif DEBUG
    }
}

/*
 * We test here if the user supplied dma/irq selections are correct. Actually
 * it is more complicated than this because not all kinds of cards can use
 * all dma/irq combinations. We simply allow the superset and avoid
 * complicated version dependent verification. (Available interrupts are 3,
 * 5, 7 for SBPro and 5, 7, 10 for other kinds, clone cards may have slight
 * differences.) 
 */

static  __inline__
BOOL
checkSelectedDMAAndIRQ(unsigned int channel, unsigned int irq)
{
    BOOL status = YES;

    if ((channel != 0) && (channel != 1) && (channel != 3)) {
        IOLog("SoundBlaster8: Audio DMA channel is %d.\n", channel);
        IOLog("SoundBlaster8: Audio DMA channel must be one of 0, 1, 3.\n");
        status = NO;
    }
    if ((irq != 3) && (irq != 5) &&
        (irq != 7) && (irq != 10)) {
        IOLog("SoundBlaster8: Audio irq is %d.\n", irq);
        IOLog("SoundBlaster8: Audio IRQ must be one of 3, 5, 7, 10.\n");
        status = NO;
    }
    
    return status;
}

