/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 * Copyright (c) 2025 RhapsodiOS Project. All rights reserved.
 *
 * PPCSound.h - PPCAwacs Audio Device Driver
 *
 * HISTORY
 * 26-Oct-25    Created stub implementation for PPCAwacs driver
 */

#import <driverkit/IOAudio.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/IODevice.h>

@interface PPCAwacs : IOAudio
{
@private
    void *awacsRegs;
    void *dmaRegs;
    int inputInterruptIndex;
    int outputInterruptIndex;
    BOOL headphonesInstalled;
    unsigned int currentRate;
    unsigned int currentInputSource;

    /* Hardware control flags - accessed as individual bytes:
     *   Byte 0 (0x184): Output active flag
     *   Byte 1 (0x185): Input active flag
     *   Bytes 2-3 (0x186-0x187): Reserved/unused
     */
    unsigned int hardwareFlags;      // Offset 0x184 - hardware status flags

    /* DMA buffer management - offsets based on disassembly */
    int interruptCount;              // Offset 0x188
    int totalInterruptCount;         // Offset 0x18c
    int processedInterruptCount;     // Offset 0x190 (400 decimal)

    /* Input DMA structures */
    void *inputDMADescriptors;       // Offset 0x1a8 - base address of input descriptors
    void *inputChannelPtr;           // Offset 0x1ac - pointer to input channel data
    unsigned int inputPhysicalAddr;  // Offset 0x1b0 - physical address of input buffer
    int currentInputBuffer;          // Offset 0x1b4 - current input buffer index
    int numInputBuffers;             // Offset 0x1bc - number of input buffers
    int inputBufferSize;             // Offset 0x1c0 - size of input buffers

    /* Output DMA structures */
    void *outputDMADescriptors;      // Offset 0x1c4 - base address of output descriptors
    void *outputChannelPtr;          // Offset 0x1c8 - pointer to output channel data
    unsigned int outputPhysicalAddr; // Offset 0x1cc - physical address of output buffer
    int currentOutputBuffer;         // Offset 0x1d0 - current output buffer index
    int numOutputBuffers;            // Offset 0x1d8 - number of output buffers
    int outputBufferSize;            // Offset 0x1dc - size of output buffers

    /* Hardware memory ranges from device tree */
    unsigned int awacsRegisterBase;  // Offset 0x198 - AWACS register base
    unsigned int dmaInputBase;       // Offset 0x19c - DMA input base
    unsigned int dmaOutputBase;      // Offset 0x1a0 - DMA output base

    /* Hardware revision flags */
    BOOL isPerchHardware;            // Offset 0x1a4 - TRUE if Perch-based hardware
    BOOL isScreenas5;                // Offset 0x1a5 - TRUE if Screamer 5 revision
    BOOL isScreenas8;                // Offset 0x1a6 - TRUE if Screamer 8 revision

    /* Audio parameter shadow registers */
    unsigned int currentSampleRate;      // Offset 0x1e0 - current sample rate
    unsigned int inputSourceSetting;     // Offset 0x1e4 - input source setting
    unsigned int soundControlShadow;     // Offset 0x1e8 - sound control register shadow
    unsigned int inputGainShadow;        // Offset 0x1ec - input gain/volume register shadow
    unsigned int codecControlShadow;     // Offset 0x1f0 - codec control register shadow
    unsigned int codecRegister2Shadow;   // Offset 0x1f4 (500 decimal) - codec register 2 shadow
    unsigned int outputAttenuationShadow;// Offset 0x1fc - output attenuation register shadow
    unsigned int powerControlShadow;     // Offset 0x204 - power control register shadow
}

/* Class methods */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;

/* Instance methods */
- (BOOL)reset;
- (void)interruptOccurredForInput:(BOOL *)serviceInput forOutput:(BOOL *)serviceOutput;
- (BOOL)startDMAForChannel:(unsigned int)localChannel
                      read:(BOOL)isRead
                    buffer:(IODMABuffer)buffer
   bufferSizeForInterrupts:(unsigned int)bufferSize;
- (void)stopDMAForChannel:(unsigned int)localChannel read:(BOOL)isRead;

/* Audio parameter update methods */
- (void)updateSampleRate:(unsigned int)newRate;
- (void)updateInputGain;
- (void)updateInputGainLeft;
- (void)updateInputGainRight;
- (void)updateOutputAttenuation;
- (void)updateOutputAttenuationLeft;
- (void)updateOutputAttenuationRight;
- (void)updateOutputMute;

/* Audio information methods */
- (unsigned int)channelCount;
- (unsigned int)channelCountLimit;
- (void)getSamplingRatesLow:(int *)lowRate high:(int *)highRate;
- (void)getSamplingRates:(int *)rates count:(unsigned int *)numRates;
- (void)getDataEncodings:(NXSoundParameterTag *)encodings count:(unsigned int *)numEncodings;
- (BOOL)isInputActive;
- (BOOL)isOutputActive;
- (IOAudioInterruptClearFunc)interruptClearFunc;

/* Interrupt handling */
- (void)_interruptOccurred;
- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(void **)arg
      forInterrupt:(unsigned int)localInterrupt;

@end

/* I/O request structure for audio operations */
typedef struct {
    char *buffer;           // Offset 0x0 - buffer pointer
    unsigned int totalSize; // Offset 0x4 - total size in bytes
    unsigned int blockSize; // Offset 0x8 - block size
    BOOL isOutput;          // Offset 0xc - direction (YES=output, NO=input)
} io_request_t;

/* Private category - implemented in PPCSoundPrivate.m */
@interface PPCAwacs (Private)

- (void)_addAudioBuffer:(void *)buffer
                 Length:(unsigned int)length
              Interrupt:(int)intNum
                 Output:(BOOL)isOutput;
- (BOOL)_allocateDMAMemory;
- (BOOL)_checkHeadphonesInstalled;
- (unsigned int)_getInputSrc;
- (unsigned int)_getInputVol:(BOOL)isLeft;
- (int)_getOutputVol:(BOOL)isLeft;
- (unsigned int)_getRate;
- (void)_resetAudio:(BOOL)isInput;
- (void)_resetAwacs;
- (void)_setInputSource:(unsigned int)source;
- (void)_setInputVol:(int *)volumeLR;
- (void)_setOutputMute:(BOOL)isMuted;
- (void)_setOutputVol:(int *)volumeLR;
- (void)_setRate:(unsigned int)rate;
- (void)_startIO:(io_request_t *)request;
- (void)_loopAudio:(BOOL)isOutput;

@end

/* DMA descriptor structure (DBDMA) */
#define DMA_DESCRIPTOR_SIZE 0x20  // 32 bytes per descriptor
#define DMA_STATUS_OFFSET   0x12  // Status byte at offset 18
#define DMA_STATUS_MASK     0x30  // Bits 4 and 5 indicate completion

/* DBDMA command codes */
#define DBDMA_CMD_OUTPUT_MORE  0x0  // Output with more data coming
#define DBDMA_CMD_INPUT_MORE   0x2  // Input with more data coming

/* DBDMA control word flags */
#define DBDMA_WAIT_NEVER       0x00000004
#define DBDMA_BRANCH_NEVER     0x40000000
#define DBDMA_INTERRUPT_NEVER  0x00000000
#define DBDMA_INTERRUPT_ALWAYS 0x00300000

/* Codec control register bits */
#define CODEC_HEADPHONE_MUTE   0x80  // Bit 7: mute when headphones inserted

/* Screamer hardware detection bits */
#define SCREAMER_HEADPHONE_BIT_DEFAULT 0x8  // Default AWACS
#define SCREAMER_HEADPHONE_BIT_PERCH   0x4  // Perch hardware
#define SCREAMER_HEADPHONE_BIT_REV8    0x1  // Screamer revision 8

/* SGS register bits for Perch */
#define SGS_HEADPHONE_ENABLE   0x20  // Bit 5: enable headphones

/* Hardware access function prototypes */
unsigned int _readClippingCountReg(unsigned int baseAddr);
unsigned int _readCodecStatusReg(unsigned int baseAddr);
void _writeCodecControlReg(unsigned int baseAddr, unsigned int value);
void _writeSoundControlReg(unsigned int baseAddr, unsigned int value);
void enforceInOrderExecutionIO(void);

/* Volume scaling helper functions */
void _scale_volume(int *leftRight, int *leftScaled, unsigned int *rightScaled, int isOutput);
void _unscale_volume(unsigned int leftScaled, unsigned int rightScaled, int *leftRight, int isOutput);

/* Utility function prototypes */
void _PPCSoundInputInt(void *param1, void *param2, void *instance);
void _PPCSoundOutputInt(void *param1, void *param2, void *instance);
int _serviceInputInterrupt(PPCAwacs *instance);
int _serviceOutputInterrupt(PPCAwacs *instance);
void _clearInterrupts(void);

/* Global variables */
extern unsigned int _awacs_rates[];
extern unsigned int _num_awacs_rates;
extern unsigned char _SGSShadow[];
