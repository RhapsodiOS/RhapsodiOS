/*
 * ES1x88AudioDriver.h
 * ESS 1x88 Audio Driver
 *
 * Driver for ESS 1688/1788/1888 ISA Audio chips
 */

#import <driverkit/IOAudioDriver.h>
#import <driverkit/IODevice.h>
#import <driverkit/IODirectDevice.h>

@interface ES1x88AudioDriver : IOAudioDriver
{
    IODeviceDescription *deviceDescription;
    unsigned int baseIOPort;
    unsigned int irqLevel;
    unsigned int dmaChannel;
    unsigned int dmaChannel16;

    // DSP state
    unsigned int dspVersion;
    BOOL isESS;
    BOOL isDSPReady;

    // Mixer state
    unsigned int masterVolume;
    unsigned int pcmVolume;
    unsigned int voiceVolume;
    unsigned int fmVolume;
    unsigned int cdVolume;
    unsigned int lineVolume;
    unsigned int micVolume;

    // Audio state
    unsigned int sampleRate;
    unsigned int bitsPerSample;
    unsigned int channels;
    BOOL isPlaying;
    BOOL isRecording;

    // Buffer management
    void *dmaBuffer;
    unsigned int bufferSize;
    unsigned int transferSize;

    // ESS specific registers
    unsigned int essRevision;
    unsigned int essChipId;
}

// Initialization and probe
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;

// Configuration
- (BOOL)resetDSP;
- (BOOL)detectESS;
- (unsigned int)getDSPVersion;
- (void)configureHardware;

// DSP operations
- (BOOL)writeDSP:(unsigned char)value;
- (int)readDSP;
- (BOOL)isDSPReadyToWrite;
- (BOOL)isDSPDataAvailable;

// Mixer operations
- (void)initMixer;
- (void)setMasterVolume:(unsigned int)left right:(unsigned int)right;
- (void)setPCMVolume:(unsigned int)left right:(unsigned int)right;
- (void)setVoiceVolume:(unsigned int)left right:(unsigned int)right;
- (void)setFMVolume:(unsigned int)left right:(unsigned int)right;
- (void)setCDVolume:(unsigned int)left right:(unsigned int)right;
- (void)setLineVolume:(unsigned int)left right:(unsigned int)right;
- (void)setMicVolume:(unsigned int)volume;
- (unsigned char)readMixer:(unsigned char)reg;
- (void)writeMixer:(unsigned char)reg value:(unsigned char)value;

// Audio playback/recording
- (IOReturn)startDMAForOutput:(BOOL)forOutput;
- (IOReturn)stopDMA;
- (void)setupDMABuffer;
- (void)programDMA:(BOOL)forOutput;

// Power management
- (IOReturn)getPowerState;
- (IOReturn)setPowerState:(unsigned int)state;

// Interrupt handling
- (void)interruptOccurred;
- (void)timeoutOccurred;

// ESS specific methods
- (BOOL)essWriteRegister:(unsigned char)reg value:(unsigned char)value;
- (unsigned char)essReadRegister:(unsigned char)reg;
- (void)essExtendedMode:(BOOL)enable;
- (void)essSetSampleRate:(unsigned int)rate forOutput:(BOOL)output;
- (void)essSetTransferCount:(unsigned int)count;

// Audio format methods
- (IOReturn)setSampleRate:(unsigned int)rate;
- (IOReturn)setBitsPerSample:(unsigned int)bits;
- (IOReturn)setChannels:(unsigned int)numChannels;

// Resource management
- (void)enableAllInterrupts;
- (void)disableAllInterrupts;
- (void)acknowledgeInterrupt;
- (void)free;

@end

// Port definitions
#define ESS_DSP_RESET           0x06
#define ESS_DSP_READ            0x0A
#define ESS_DSP_WRITE           0x0C
#define ESS_DSP_WRITE_STATUS    0x0C
#define ESS_DSP_READ_STATUS     0x0E
#define ESS_DSP_ACK_16BIT       0x0F

#define ESS_MIXER_ADDR          0x04
#define ESS_MIXER_DATA          0x05

// DSP commands
#define ESS_CMD_GET_VERSION     0xE1
#define ESS_CMD_ENABLE_SPEAKER  0xD1
#define ESS_CMD_DISABLE_SPEAKER 0xD3
#define ESS_CMD_SET_SAMPLE_RATE 0x41
#define ESS_CMD_SET_STEREO      0xA8
#define ESS_CMD_SET_MONO        0xA0

// ESS specific commands
#define ESS_CMD_EXTENDED_MODE   0xC6
#define ESS_CMD_EXIT_EXTENDED   0xC7
#define ESS_CMD_READ_REGISTER   0xC0
#define ESS_CMD_WRITE_REGISTER  0xA0

// ESS registers
#define ESS_REG_AUDIO1_CTRL1    0xA1
#define ESS_REG_AUDIO1_CTRL2    0xA2
#define ESS_REG_AUDIO1_COUNT_L  0xA4
#define ESS_REG_AUDIO1_COUNT_H  0xA5
#define ESS_REG_FILTER_DIV      0xA1
#define ESS_REG_FILTER_CLOCK    0xA2
#define ESS_REG_IRQ_CTRL        0xB1
#define ESS_REG_DMA_CTRL        0xB2
#define ESS_REG_CHIP_ID         0xE7

// Mixer registers
#define ESS_MIXER_RESET         0x00
#define ESS_MIXER_MASTER_VOL    0x32
#define ESS_MIXER_VOICE_VOL     0x14
#define ESS_MIXER_FM_VOL        0x36
#define ESS_MIXER_CD_VOL        0x38
#define ESS_MIXER_LINE_VOL      0x3E
#define ESS_MIXER_MIC_VOL       0x1A
#define ESS_MIXER_PC_SPEAKER    0x3B
#define ESS_MIXER_OUTPUT_CTRL   0x3C
#define ESS_MIXER_INPUT_SRC     0x1C

// Status bits
#define ESS_DSP_BUSY            0x80
#define ESS_DSP_DATA_AVAIL      0x80

// Default values
#define ESS_DEFAULT_IRQ         5
#define ESS_DEFAULT_DMA         1
#define ESS_DEFAULT_BASE        0x220
#define ESS_BUFFER_SIZE         65536
#define ESS_MAX_SAMPLE_RATE     48000
