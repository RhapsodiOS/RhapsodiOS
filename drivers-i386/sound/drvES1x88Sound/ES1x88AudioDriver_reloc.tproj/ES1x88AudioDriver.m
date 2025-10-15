/*
 * ES1x88AudioDriver.m
 * ESS 1x88 Audio Driver
 *
 * Driver for ESS 1688/1788/1888 ISA Audio chips
 */

#import "ES1x88AudioDriver.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/IOEISADeviceDescription.h>
#import <driverkit/i386/directDevice.h>
#import <driverkit/i386/dma.h>
#import <mach/mach_interface.h>

@implementation ES1x88AudioDriver

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    ES1x88AudioDriver *driver;
    BOOL result = NO;

    driver = [[self alloc] initFromDeviceDescription:deviceDescription];
    if (driver) {
        if ([driver detectESS]) {
            result = YES;
        }
        [driver free];
    }

    return result;
}

- initFromDeviceDescription:(IODeviceDescription *)devDesc
{
    IORange *portRange;
    unsigned int *irqList;
    unsigned int *dmaList;

    if ([super initFromDeviceDescription:devDesc] == nil)
        return nil;

    deviceDescription = devDesc;

    // Get I/O port base address
    portRange = [deviceDescription portRangeList];
    if (portRange)
        baseIOPort = portRange->start;
    else
        baseIOPort = ESS_DEFAULT_BASE;

    // Get IRQ
    irqList = [deviceDescription interrupt];
    if (irqList)
        irqLevel = irqList[0];
    else
        irqLevel = ESS_DEFAULT_IRQ;

    // Get DMA channel
    dmaList = [deviceDescription channelList];
    if (dmaList)
        dmaChannel = dmaList[0];
    else
        dmaChannel = ESS_DEFAULT_DMA;

    dmaChannel16 = 0; // ESS 1x88 typically uses 8-bit DMA only

    // Initialize state
    isPlaying = NO;
    isRecording = NO;
    isDSPReady = NO;
    dmaBuffer = NULL;
    bufferSize = ESS_BUFFER_SIZE;
    transferSize = 0;

    // Default audio parameters
    sampleRate = 22050;
    bitsPerSample = 8;
    channels = 1;

    return self;
}

- (BOOL)resetDSP
{
    int i;

    // Send reset command
    IOWriteUCharacter(baseIOPort + ESS_DSP_RESET, 1);
    IODelay(3);
    IOWriteUCharacter(baseIOPort + ESS_DSP_RESET, 0);
    IODelay(3);

    // Wait for DSP ready (should return 0xAA)
    for (i = 0; i < 1000; i++) {
        if ([self isDSPDataAvailable]) {
            if ([self readDSP] == 0xAA) {
                isDSPReady = YES;
                return YES;
            }
        }
        IODelay(1);
    }

    return NO;
}

- (BOOL)detectESS
{
    unsigned int version;

    if (![self resetDSP])
        return NO;

    // Get DSP version
    version = [self getDSPVersion];
    if (version == 0)
        return NO;

    dspVersion = version;

    // Check if it's an ESS chip
    // ESS chips return version >= 0x688
    if (version >= 0x688) {
        isESS = YES;

        // Try to read ESS chip ID
        [self essExtendedMode:YES];
        essChipId = [self essReadRegister:ESS_REG_CHIP_ID];
        [self essExtendedMode:NO];

        IOLog("ES1x88AudioDriver: Detected ESS chip, version 0x%x, ID 0x%x\n",
              version, essChipId);
        return YES;
    }

    return NO;
}

- (unsigned int)getDSPVersion
{
    int high, low;

    if (![self writeDSP:ESS_CMD_GET_VERSION])
        return 0;

    IODelay(10);

    high = [self readDSP];
    if (high < 0)
        return 0;

    low = [self readDSP];
    if (low < 0)
        return 0;

    return (high << 8) | low;
}

- (void)configureHardware
{
    // Reset DSP
    [self resetDSP];

    // Initialize mixer
    [self initMixer];

    // Enable speaker output
    [self writeDSP:ESS_CMD_ENABLE_SPEAKER];

    // Set default sample rate
    [self essSetSampleRate:sampleRate forOutput:YES];

    // Configure for mono
    [self writeDSP:ESS_CMD_SET_MONO];
}

- (BOOL)isDSPReadyToWrite
{
    unsigned char status = IOReadUCharacter(baseIOPort + ESS_DSP_WRITE_STATUS);
    return (status & ESS_DSP_BUSY) == 0;
}

- (BOOL)isDSPDataAvailable
{
    unsigned char status = IOReadUCharacter(baseIOPort + ESS_DSP_READ_STATUS);
    return (status & ESS_DSP_DATA_AVAIL) != 0;
}

- (BOOL)writeDSP:(unsigned char)value
{
    int i;

    for (i = 0; i < 10000; i++) {
        if ([self isDSPReadyToWrite]) {
            IOWriteUCharacter(baseIOPort + ESS_DSP_WRITE, value);
            return YES;
        }
        IODelay(1);
    }

    return NO;
}

- (int)readDSP
{
    int i;

    for (i = 0; i < 10000; i++) {
        if ([self isDSPDataAvailable]) {
            return IOReadUCharacter(baseIOPort + ESS_DSP_READ);
        }
        IODelay(1);
    }

    return -1;
}

- (void)initMixer
{
    // Reset mixer
    IOWriteUCharacter(baseIOPort + ESS_MIXER_ADDR, ESS_MIXER_RESET);
    IOWriteUCharacter(baseIOPort + ESS_MIXER_DATA, 0);
    IODelay(10);

    // Set default volumes (75%)
    [self setMasterVolume:12 right:12];
    [self setPCMVolume:12 right:12];
    [self setVoiceVolume:12 right:12];
    [self setFMVolume:12 right:12];
    [self setCDVolume:12 right:12];
    [self setLineVolume:12 right:12];
    [self setMicVolume:12];
}

- (unsigned char)readMixer:(unsigned char)reg
{
    IOWriteUCharacter(baseIOPort + ESS_MIXER_ADDR, reg);
    IODelay(1);
    return IOReadUCharacter(baseIOPort + ESS_MIXER_DATA);
}

- (void)writeMixer:(unsigned char)reg value:(unsigned char)value
{
    IOWriteUCharacter(baseIOPort + ESS_MIXER_ADDR, reg);
    IODelay(1);
    IOWriteUCharacter(baseIOPort + ESS_MIXER_DATA, value);
    IODelay(1);
}

- (void)setMasterVolume:(unsigned int)left right:(unsigned int)right
{
    unsigned char value = ((left & 0x0F) << 4) | (right & 0x0F);
    [self writeMixer:ESS_MIXER_MASTER_VOL value:value];
    masterVolume = value;
}

- (void)setPCMVolume:(unsigned int)left right:(unsigned int)right
{
    unsigned char value = ((left & 0x0F) << 4) | (right & 0x0F);
    [self writeMixer:ESS_MIXER_VOICE_VOL value:value];
    pcmVolume = value;
}

- (void)setVoiceVolume:(unsigned int)left right:(unsigned int)right
{
    unsigned char value = ((left & 0x0F) << 4) | (right & 0x0F);
    [self writeMixer:ESS_MIXER_VOICE_VOL value:value];
    voiceVolume = value;
}

- (void)setFMVolume:(unsigned int)left right:(unsigned int)right
{
    unsigned char value = ((left & 0x0F) << 4) | (right & 0x0F);
    [self writeMixer:ESS_MIXER_FM_VOL value:value];
    fmVolume = value;
}

- (void)setCDVolume:(unsigned int)left right:(unsigned int)right
{
    unsigned char value = ((left & 0x0F) << 4) | (right & 0x0F);
    [self writeMixer:ESS_MIXER_CD_VOL value:value];
    cdVolume = value;
}

- (void)setLineVolume:(unsigned int)left right:(unsigned int)right
{
    unsigned char value = ((left & 0x0F) << 4) | (right & 0x0F);
    [self writeMixer:ESS_MIXER_LINE_VOL value:value];
    lineVolume = value;
}

- (void)setMicVolume:(unsigned int)volume
{
    unsigned char value = (volume & 0x0F) << 4;
    [self writeMixer:ESS_MIXER_MIC_VOL value:value];
    micVolume = value;
}

- (BOOL)essWriteRegister:(unsigned char)reg value:(unsigned char)value
{
    if (![self writeDSP:ESS_CMD_WRITE_REGISTER])
        return NO;
    if (![self writeDSP:reg])
        return NO;
    if (![self writeDSP:value])
        return NO;
    return YES;
}

- (unsigned char)essReadRegister:(unsigned char)reg
{
    if (![self writeDSP:ESS_CMD_READ_REGISTER])
        return 0;
    if (![self writeDSP:reg])
        return 0;
    return [self readDSP];
}

- (void)essExtendedMode:(BOOL)enable
{
    if (enable) {
        [self writeDSP:ESS_CMD_EXTENDED_MODE];
        [self writeDSP:0x69]; // Magic value for ESS chips
    } else {
        [self writeDSP:ESS_CMD_EXIT_EXTENDED];
    }
}

- (void)essSetSampleRate:(unsigned int)rate forOutput:(BOOL)output
{
    unsigned int timeConstant;
    unsigned char filterDiv;

    // Calculate time constant for ESS chips
    // TC = 256 - (1000000 / (channels * rate))
    if (rate < 4000) rate = 4000;
    if (rate > ESS_MAX_SAMPLE_RATE) rate = ESS_MAX_SAMPLE_RATE;

    timeConstant = 256 - (1000000 / (channels * rate));

    [self essExtendedMode:YES];

    // Set filter divider
    filterDiv = 256 - (7160000 / (rate * 82));
    [self essWriteRegister:ESS_REG_FILTER_DIV value:filterDiv];

    // Set time constant
    [self writeDSP:0x40]; // Set time constant command
    [self writeDSP:timeConstant & 0xFF];

    [self essExtendedMode:NO];

    sampleRate = rate;
}

- (void)essSetTransferCount:(unsigned int)count
{
    [self essExtendedMode:YES];
    [self essWriteRegister:ESS_REG_AUDIO1_COUNT_L value:(count & 0xFF)];
    [self essWriteRegister:ESS_REG_AUDIO1_COUNT_H value:((count >> 8) & 0xFF)];
    [self essExtendedMode:NO];
}

- (void)setupDMABuffer
{
    if (dmaBuffer == NULL) {
        dmaBuffer = IOMalloc(bufferSize);
        if (dmaBuffer == NULL) {
            IOLog("ES1x88AudioDriver: Failed to allocate DMA buffer\n");
            return;
        }
        IOLog("ES1x88AudioDriver: Allocated DMA buffer at %p, size %d\n",
              dmaBuffer, bufferSize);
    }
}

- (void)programDMA:(BOOL)forOutput
{
    unsigned int physAddr;
    unsigned int count;

    // Get physical address of DMA buffer
    physAddr = (unsigned int)dmaBuffer; // Should use proper virtual-to-physical conversion
    count = transferSize - 1;

    // Program DMA controller
    IODMADisable(dmaChannel);
    IODMAClear(dmaChannel);
    IODMASetMode(dmaChannel, forOutput ? IO_DMA_MODE_READ : IO_DMA_MODE_WRITE);
    IODMASetAddress(dmaChannel, physAddr);
    IODMASetCount(dmaChannel, count);
    IODMAEnable(dmaChannel);
}

- (IOReturn)startDMAForOutput:(BOOL)forOutput
{
    if (forOutput && isPlaying)
        return IO_R_BUSY;
    if (!forOutput && isRecording)
        return IO_R_BUSY;

    [self setupDMABuffer];

    transferSize = 16384; // 16KB transfers

    // Program DMA
    [self programDMA:forOutput];

    // Set ESS transfer count
    [self essSetTransferCount:transferSize];

    // Start DMA on DSP
    if (forOutput) {
        [self writeDSP:0x14]; // 8-bit DMA DAC
        [self writeDSP:(transferSize - 1) & 0xFF];
        [self writeDSP:((transferSize - 1) >> 8) & 0xFF];
        isPlaying = YES;
    } else {
        [self writeDSP:0x24]; // 8-bit DMA ADC
        [self writeDSP:(transferSize - 1) & 0xFF];
        [self writeDSP:((transferSize - 1) >> 8) & 0xFF];
        isRecording = YES;
    }

    return IO_R_SUCCESS;
}

- (IOReturn)stopDMA
{
    // Halt DMA
    [self writeDSP:0xD0]; // Halt 8-bit DMA

    IODMADisable(dmaChannel);

    isPlaying = NO;
    isRecording = NO;

    return IO_R_SUCCESS;
}

- (IOReturn)setSampleRate:(unsigned int)rate
{
    [self essSetSampleRate:rate forOutput:YES];
    return IO_R_SUCCESS;
}

- (IOReturn)setBitsPerSample:(unsigned int)bits
{
    if (bits != 8 && bits != 16)
        return IO_R_INVALID_ARG;

    bitsPerSample = bits;
    return IO_R_SUCCESS;
}

- (IOReturn)setChannels:(unsigned int)numChannels
{
    if (numChannels < 1 || numChannels > 2)
        return IO_R_INVALID_ARG;

    channels = numChannels;

    // Configure DSP for mono/stereo
    if (numChannels == 2) {
        [self writeDSP:ESS_CMD_SET_STEREO];
    } else {
        [self writeDSP:ESS_CMD_SET_MONO];
    }

    return IO_R_SUCCESS;
}

- (void)enableAllInterrupts
{
    // Enable interrupts on ESS chip
    [self essExtendedMode:YES];
    [self essWriteRegister:ESS_REG_IRQ_CTRL value:0x01];
    [self essExtendedMode:NO];
}

- (void)disableAllInterrupts
{
    // Disable interrupts on ESS chip
    [self essExtendedMode:YES];
    [self essWriteRegister:ESS_REG_IRQ_CTRL value:0x00];
    [self essExtendedMode:NO];
}

- (void)acknowledgeInterrupt
{
    // Acknowledge interrupt by reading DSP read status
    IOReadUCharacter(baseIOPort + ESS_DSP_READ_STATUS);
}

- (void)interruptOccurred
{
    [self acknowledgeInterrupt];

    // Handle DMA buffer completion
    if (isPlaying || isRecording) {
        // Notify that buffer needs servicing
        // In a real driver, this would signal to refill/consume the buffer
    }
}

- (void)timeoutOccurred
{
    // Handle timeout
}

- (IOReturn)getPowerState
{
    return IO_R_SUCCESS;
}

- (IOReturn)setPowerState:(unsigned int)state
{
    if (state == 0) {
        // Power down
        [self disableAllInterrupts];
        [self stopDMA];
        [self writeDSP:ESS_CMD_DISABLE_SPEAKER];
    } else {
        // Power up
        [self configureHardware];
        [self enableAllInterrupts];
    }

    return IO_R_SUCCESS;
}

- (void)free
{
    if (dmaBuffer) {
        IOFree(dmaBuffer, bufferSize);
        dmaBuffer = NULL;
    }

    [super free];
}

@end
