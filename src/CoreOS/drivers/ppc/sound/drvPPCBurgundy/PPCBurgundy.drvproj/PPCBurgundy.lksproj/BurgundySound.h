/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * BurgundySound.h
 *
 * PowerPC Burgundy Sound Driver
 *
 */

#import <driverkit/IOAudio.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <architecture/ppc/asm_help.h>
#import <mach/mach_interface.h>
#import <kernserv/prototypes.h>

@interface PPCBurgundy : IOAudio
{
    /* Hardware control flags - accessed as individual bytes:
     *   Byte 0 (0x184): Output active flag
     *   Byte 1 (0x185): Input active flag
     */
    unsigned int hardwareFlags;  /* offset 0x184 */

    /* Interrupt counters */
    unsigned int totalInterruptCount;    /* offset 0x188 - pending interrupt count */
    unsigned int frameCount;             /* offset 0x18c - frame counter */
    unsigned int cumulativeInterruptCount; /* offset 0x190 - cumulative total */
    unsigned int reserved_0x194;         /* offset 0x194 */

    /* Hardware state shadow registers - offsets TBD */
    unsigned int outputVolumeShadow;
    unsigned int inputVolumeShadow;

    /* Memory-mapped I/O base addresses from device tree */
    unsigned int memoryRange0;           /* offset 0x198 */
    unsigned int memoryRange1;           /* offset 0x19c */
    unsigned int memoryRange2;           /* offset 0x1a0 */
    unsigned char isDVD;                 /* offset 0x1a4 - DVD-Video variant flag */

    /* Input DMA management */
    unsigned int inputDMABufferList;        /* offset 0x1a8 - DBDMA descriptor list base */
    unsigned int *inputHardwareIndex;       /* offset 0x1ac - pointer to hardware index */
    unsigned int inputHardwareIndexPhys;    /* offset 0x1b0 - physical address of hw index */
    unsigned int inputReadIndex;            /* offset 0x1b4 - service routine read index */
    unsigned int reserved1;                 /* offset 0x1b8 */
    unsigned int inputWriteIndex;           /* offset 0x1bc - addBuffer write index */
    unsigned int inputBufferCount;          /* offset 0x1c0 - total descriptor capacity */

    /* Output DMA management */
    unsigned int outputDMABufferList;       /* offset 0x1c4 - DBDMA descriptor list base */
    unsigned int *outputHardwareIndex;      /* offset 0x1c8 - pointer to hardware index */
    unsigned int outputHardwareIndexPhys;   /* offset 0x1cc - physical address of hw index */
    unsigned int outputReadIndex;           /* offset 0x1d0 - service routine read index */
    unsigned int reserved2;                 /* offset 0x1d4 */
    unsigned int outputWriteIndex;          /* offset 0x1d8 - addBuffer write index */
    unsigned int outputBufferCount;         /* offset 0x1dc - total descriptor capacity */

    /* Audio settings */
    unsigned int currentSampleRate;         /* offset 0x1e0 - current sample rate */
    unsigned int currentInputSource;        /* offset 0x1e4 - current input source */
    unsigned int soundControlReg;           /* offset 0x1e8 - sound control register shadow */
}

/* Public IOAudio interface methods */
- (unsigned int)channelCount;
- (unsigned int)channelCountLimit;
- (void)getDataEncodings:(NXSoundParameterTag *)encodings count:(unsigned int *)numEncodings;
- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(void **)arg
      forInterrupt:(unsigned int)localInterrupt;
- (void)getSamplingRates:(int *)rates count:(unsigned int *)numRates;
- (void)getSamplingRatesLow:(int *)lowRate high:(int *)highRate;
- (IOInterruptHandler)interruptClearFunc;
- (void)interruptOccurredForInput:(BOOL *)serviceInput forOutput:(BOOL *)serviceOutput;
- (BOOL)isInputActive;
- (BOOL)isOutputActive;
- (BOOL)reset;
- (BOOL)startDMAForChannel:(unsigned int)localChannel
                      read:(BOOL)isRead
                    buffer:(IODMABuffer)buffer
   bufferSizeForInterrupts:(unsigned int)bufferSize;
- (void)stopDMAForChannel:(unsigned int)localChannel read:(BOOL)isRead;
- (void)updateInputGain;
- (void)updateInputGainLeft;
- (void)updateInputGainRight;
- (void)updateOutputAttenuation;
- (void)updateOutputAttenuationLeft;
- (void)updateOutputAttenuationRight;
- (void)updateOutputMute;
- (void)updateSampleRate:(int)sampleRate;

/* Interrupt handler */
- (void)_interruptOccurred;

@end

/* Category for private methods */
@interface PPCBurgundy(Private)

- (void)_addAudioBuffer:(void *)buffer
                 Length:(unsigned int)length
              Interrupt:(unsigned int)interruptCount
                 Output:(BOOL)isOutput;
- (BOOL)_allocateDMAMemory;
- (BOOL)_checkHeadphonesInstalled;
- (unsigned int)_getInputSrc;
- (void)_getInputVol:(int *)volumeLR;
- (void)_getOutputVol:(int *)volumeLR;
- (unsigned int)_getRate;
- (void)_loopAudio:(BOOL)shouldLoop;
- (void)_resetAudio:(BOOL)isInput;
- (BOOL)_resetBurgundy;
- (void)_setInputSource:(unsigned int)source;
- (void)_setInputVol:(int *)volumeLR;
- (void)_setOutputMute:(BOOL)isMuted;
- (void)_setOutputVol:(int *)volumeLR;
- (void)_setRate:(unsigned int)sampleRate;
- (void)_startIO:(void *)requestPtr;

@end

/* Utility function prototypes */
void _PPCSoundInputInt(void *identity, void *state, unsigned int arg);
void _PPCSoundOutputInt(void *identity, void *state, unsigned int arg);
int _serviceInputInterrupt(PPCBurgundy *self);
int _serviceOutputInterrupt(PPCBurgundy *self);
IOReturn _clearInterrupts(void *identity, void *state, unsigned int arg);

/* Hardware access function prototypes */
unsigned int _readBurgundyReg(unsigned int baseAddr, unsigned int offset);
void _writeBurgundyReg(unsigned int baseAddr, unsigned int offset, unsigned int value);
unsigned int _readCodecReg(unsigned int baseAddr, unsigned int regAddr);
unsigned int _readCodecSenseLines(unsigned int baseAddr);
void _writeCodecReg(unsigned int baseAddr, unsigned int regAddr, unsigned int value);
void _writeSoundControlReg(unsigned int baseAddr, unsigned int value);
void _stopDMAEngine(unsigned int dmaEngineAddr);
void enforceInOrderExecutionIO(void);
void _scale_volume(int *volumeLR, int *leftScaled, int *rightScaled);
void IODelay(unsigned int microseconds);

/* Helper function prototypes for DBDMA management */
unsigned int bswap32(unsigned int value);
void dcbf(void *addr, unsigned int length);

/* Global variables */
extern unsigned int _currentOutputMuteReg;
extern unsigned int _entry;

/* I/O request structure */
typedef struct {
    char *buffer;           /* 0x0 - Buffer pointer */
    unsigned int totalSize; /* 0x4 - Total size */
    unsigned int frameSize; /* 0x8 - Frame size */
    unsigned int isOutput;  /* 0xc - Output flag */
} io_request_t;
