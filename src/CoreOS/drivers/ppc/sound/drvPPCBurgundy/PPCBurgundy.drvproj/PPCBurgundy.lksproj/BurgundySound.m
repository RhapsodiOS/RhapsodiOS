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
 * BurgundySound.m
 *
 * PowerPC Burgundy Sound Driver
 *
 */

#import "BurgundySound.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>
#import <machkit/NXLock.h>
#import <string.h>

/* Global variables */
unsigned int _currentOutputMuteReg = 0;
unsigned int _entry = 0x2000;  /* Default DMA buffer size - 8KB */

/* Static interrupt counters for stub methods - TODO: replace with actual hardware status */
static unsigned int inputInterruptCount = 0;
static unsigned int outputInterruptCount = 0;

/* Burgundy sample rate data */
static int _burgundy_rates[] = { 0xAC44 };  /* 44100 Hz only */
static unsigned int _num_burgundy_rates = 1;

/* Hardware access functions */

void enforceInOrderExecutionIO(void)
{
    __asm__ volatile("eieio" ::: "memory");
}

unsigned int _readBurgundyReg(unsigned int baseAddr, unsigned int offset)
{
    volatile unsigned int *reg = (volatile unsigned int *)(baseAddr + offset);
    unsigned int value;

    value = *reg;
    enforceInOrderExecutionIO();

    return value;
}

void _writeBurgundyReg(unsigned int baseAddr, unsigned int offset, unsigned int value)
{
    volatile unsigned int *reg = (volatile unsigned int *)(baseAddr + offset);

    *reg = value;
    enforceInOrderExecutionIO();
}

unsigned int _readCodecReg(unsigned int baseAddr, unsigned int regAddr)
{
    unsigned int result = 0;
    unsigned int byteCount;
    unsigned int regCmd;
    unsigned int currentByte;
    unsigned int polarity;
    unsigned int timeout;
    unsigned int oldPolarity;
    volatile unsigned char *statusReg;
    volatile unsigned short *dataReg;
    BOOL timedOut;

    byteCount = (regAddr >> 16) & 0xFF;
    regCmd = ((regAddr >> 8) & 0xFF) << 12 |
             (byteCount + (regAddr & 0xFF) - 1) * 0x400 |
             0x100000;  /* Read command bit */

    enforceInOrderExecutionIO();

    /* Get expected polarity toggle pattern */
    statusReg = (volatile unsigned char *)(baseAddr + 0x21);
    polarity = (((unsigned int)(*statusReg << 8) >> 14) + 1) & 3;

    currentByte = 0;
    if (byteCount != 0) {
        do {
            /* Build register address for this byte */
            unsigned int addr = regCmd | ((regAddr & 0xFF) + currentByte) * 0x100;

            /* Write register address - byte swapped for big endian */
            *(volatile unsigned int *)(baseAddr + 0x10) =
                (addr & 0xFF00) << 8 | (addr >> 8) & 0xFF00 | (addr >> 24);
            enforceInOrderExecutionIO();

            /* Clear read bit for subsequent bytes */
            regCmd = regCmd & 0xFFEFFFFF;

            /* Wait for busy flag to clear */
            do {
                enforceInOrderExecutionIO();
            } while ((*(volatile unsigned char *)(baseAddr + 0x13) & 1) != 0);

            /* Wait for polarity toggle */
            timeout = 0;
            do {
                enforceInOrderExecutionIO();
                if (polarity == (((*(volatile unsigned char *)(baseAddr + 0x21) & 0xC0) << 8) >> 14))
                    break;
                timedOut = (timeout < 1000);
                timeout++;
            } while (timedOut);

            polarity++;
            IODelay(10);  /* 10 microsecond delay */

            /* Read data from register at offset 0x20-0x21 */
            dataReg = (volatile unsigned short *)(baseAddr + 0x20);
            result |= (((unsigned int)(*dataReg >> 4) & 0xFF) << ((currentByte & 7) << 3));

            currentByte++;
        } while (currentByte < byteCount);
    }

    return result;
}

unsigned int _readCodecSenseLines(unsigned int baseAddr)
{
    /* Read codec sense lines from lower 4 bits of byte at offset 0x20 */
    return *(volatile unsigned char *)(baseAddr + 0x20) & 0xF;
}

void _writeCodecReg(unsigned int baseAddr, unsigned int regAddr, unsigned int value)
{
    unsigned int byteCount;
    unsigned int regCmd;
    unsigned int currentByte;
    unsigned int addr;

    byteCount = (regAddr >> 16) & 0xFF;
    regCmd = ((regAddr >> 8) & 0xFF) << 12 |
             (byteCount + (regAddr & 0xFF) - 1) * 0x400 |
             0x300000;  /* Write command bits */

    currentByte = 0;
    if (byteCount != 0) {
        do {
            /* Build register address for this byte */
            addr = regCmd | ((regAddr & 0xFF) + currentByte) * 0x100;

            /* Write data and address - byte swapped for big endian */
            *(volatile unsigned int *)(baseAddr + 0x10) =
                (value << 24) |
                ((addr & 0xFF00) << 8) |
                ((addr & 0xFF0000) >> 8) |
                (addr >> 24);
            enforceInOrderExecutionIO();

            /* Shift value for next byte */
            value = value >> 8;

            /* Clear write bit for subsequent bytes */
            regCmd = regCmd & 0xFFEFFFFF;

            /* Wait for busy flag to clear */
            do {
                enforceInOrderExecutionIO();
            } while ((*(volatile unsigned char *)(baseAddr + 0x13) & 1) != 0);

            currentByte++;
        } while (currentByte < byteCount);
    }
}

void _writeSoundControlReg(unsigned int baseAddr, unsigned int value)
{
    /* Write sound control register at offset 0 with byte swapping */
    *(volatile unsigned int *)baseAddr =
        (value << 24) |
        ((value & 0xFF00) << 8) |
        ((value >> 8) & 0xFF00) |
        (value >> 24);
    enforceInOrderExecutionIO();
}

void _stopDMAEngine(unsigned int dmaEngineAddr)
{
    /* Stop DMA engine */
    /* FUN_0000170c - Stop DBDMA channel */
    _writeBurgundyReg(dmaEngineAddr, 0, 0x80000000);  /* RUN bit clear, STOP bit set */
    enforceInOrderExecutionIO();
}

/* Helper functions for DBDMA management */

unsigned int bswap32(unsigned int value)
{
    return (value << 24) | ((value & 0xFF00) << 8) |
           ((value >> 8) & 0xFF00) | (value >> 24);
}

void dcbf(void *addr, unsigned int length)
{
    /* Data cache block flush for PowerPC */
    /* FUN_00001424 in decompilation - flush cache for DBDMA descriptor */
    __asm__ volatile("dcbf 0,%0" : : "r"(addr) : "memory");
    enforceInOrderExecutionIO();
}

void _scale_volume(int *volumeLR, int *leftScaled, int *rightScaled)
{
    unsigned int leftTemp;
    unsigned int rightTemp;

    /* Scale left channel: multiply by 0xFF and divide by 0x8000 with rounding */
    leftTemp = volumeLR[0] * 0xFF;
    *leftScaled = ((int)leftTemp >> 15) +
                  ((int)leftTemp < 0 && (leftTemp & 0x7FFF) != 0 ? 1 : 0);

    /* Scale right channel: multiply by 0xFF and divide by 0x8000 with rounding */
    rightTemp = volumeLR[1] * 0xFF;
    *rightScaled = ((int)rightTemp >> 15) +
                   ((int)rightTemp < 0 && (rightTemp & 0x7FFF) != 0 ? 1 : 0);

    /* Clamp left to [0, 0xFF] */
    if (*leftScaled > 0xFF) {
        *leftScaled = 0xFF;
    }
    if (*leftScaled < 0) {
        *leftScaled = 0;
    }

    /* Clamp right to [0, 0xFF] */
    if (*rightScaled > 0xFF) {
        *rightScaled = 0xFF;
    }
    if (*rightScaled < 0) {
        *rightScaled = 0;
    }
}

IOReturn _clearInterrupts(void *identity, void *state, unsigned int arg)
{
    /* Clear pending interrupts */
    /* TODO: Implement actual interrupt clearing */
    return IO_R_SUCCESS;
}

/* Utility functions */

void _PPCSoundInputInt(void *identity, void *state, unsigned int arg)
{
    PPCBurgundy *self = (PPCBurgundy *)arg;
    int interruptCount;

    if (self == nil) {
        return;
    }

    interruptCount = _serviceInputInterrupt(self);

    if (interruptCount != 0) {
        if (self->totalInterruptCount == 0) {
            /* FUN_000003b8(identity, state, 0x232325) - stub/lock function */
        }
        self->totalInterruptCount += interruptCount;
        self->frameCount += interruptCount;
    }

    /* FUN_000003a8(identity) - stub/unlock function */
}

void _PPCSoundOutputInt(void *identity, void *state, unsigned int arg)
{
    PPCBurgundy *self = (PPCBurgundy *)arg;
    int interruptCount;

    if (self == nil) {
        return;
    }

    interruptCount = _serviceOutputInterrupt(self);

    if (interruptCount != 0) {
        if (self->totalInterruptCount == 0) {
            /* FUN_000002e8(identity, state, 0x232325) - stub/lock function */
        }
        self->totalInterruptCount += interruptCount;
        self->frameCount += interruptCount;
    }

    /* FUN_000002d8(identity) - stub/unlock function */
}

int _serviceInputInterrupt(PPCBurgundy *self)
{
    int interruptCount;
    unsigned int loopCount;
    int currentIndex;
    volatile unsigned char *descriptor;

    interruptCount = 0;
    loopCount = 0;

    if (self->inputWriteIndex != 0) {
        do {
            currentIndex = self->inputReadIndex;

            /* Check DBDMA descriptor status at offset 0x12 (status field) */
            descriptor = (volatile unsigned char *)(currentIndex * 0x20 + self->inputDMABufferList);

            /* Check for ACTIVE (0x10) or DEAD (0x20) status bits */
            if ((descriptor[0x12] & 0x30) != 0) {
                interruptCount++;
            }

            /* Advance read index */
            self->inputReadIndex++;
            if (self->inputWriteIndex <= self->inputReadIndex) {
                self->inputReadIndex = 0;
            }

            /* FUN_00000f08(self->inputHardwareIndex, 4) - advance hardware pointer by 4 bytes */
            /* This is likely eieio or cache sync */

        } while ((*(self->inputHardwareIndex) != currentIndex) &&
                 (loopCount++, loopCount < self->inputWriteIndex));
    }

    return interruptCount;
}

int _serviceOutputInterrupt(PPCBurgundy *self)
{
    int interruptCount;
    unsigned int loopCount;
    int currentIndex;
    volatile unsigned char *descriptor;

    interruptCount = 0;
    loopCount = 0;

    if (self->outputWriteIndex != 0) {
        do {
            currentIndex = self->outputReadIndex;

            /* Check DBDMA descriptor status at offset 0x12 (status field) */
            descriptor = (volatile unsigned char *)(currentIndex * 0x20 + self->outputDMABufferList);

            /* Check for ACTIVE (0x10) or DEAD (0x20) status bits */
            if ((descriptor[0x12] & 0x30) != 0) {
                interruptCount++;
            }

            /* Advance read index */
            self->outputReadIndex++;
            if (self->outputWriteIndex <= self->outputReadIndex) {
                self->outputReadIndex = 0;
            }

            /* FUN_00000e10(self->outputHardwareIndex, 4) - advance hardware pointer by 4 bytes */
            /* This is likely eieio or cache sync */

        } while ((*(self->outputHardwareIndex) != currentIndex) &&
                 (loopCount++, loopCount < self->outputWriteIndex));
    }

    return interruptCount;
}

@implementation PPCBurgundy

/* IOAudio public interface methods */

- (unsigned int)channelCount
{
    /* Return number of channels - stereo */
    return 2;
}

- (unsigned int)channelCountLimit
{
    /* Return maximum supported channels - stereo only */
    return 2;
}

- (void)getDataEncodings:(NXSoundParameterTag *)encodings count:(unsigned int *)numEncodings
{
    /* Return supported data encodings */
    if (numEncodings != NULL) {
        *numEncodings = 1;
    }
    if (encodings != NULL) {
        *encodings = 600;  /* NX_SoundStreamDataEncoding_Linear16 */
    }
}

- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(void **)arg
      forInterrupt:(unsigned int)localInterrupt
{
    /* Return interrupt handler for specified interrupt */
    if (localInterrupt == 1) {
        /* Output interrupt */
        *handler = (IOInterruptHandler)_PPCSoundOutputInt;
        *ipl = 0x18;  /* IPL_DEVICE */
        *arg = (void *)self;
        return YES;
    } else if (localInterrupt == 2) {
        /* Input interrupt */
        *handler = (IOInterruptHandler)_PPCSoundInputInt;
        *ipl = 0x18;  /* IPL_DEVICE */
        *arg = (void *)self;
        return YES;
    }

    return NO;
}

- (void)getSamplingRates:(int *)rates count:(unsigned int *)numRates
{
    /* Burgundy supports only 44.1kHz (0xAC44) */
    if (numRates != NULL) {
        *numRates = 1;
    }
    if (rates != NULL) {
        bcopy(_burgundy_rates, rates, 4);  /* Copy 4 bytes (one int) */
    }
}

- (void)getSamplingRatesLow:(int *)lowRate high:(int *)highRate
{
    /* Burgundy supports only 44.1kHz (0xAC44) */
    *lowRate = 0xAC44;   /* 44100 Hz */
    *highRate = 0xAC44;  /* 44100 Hz */
}

- (IOInterruptHandler)interruptClearFunc
{
    /* Return pointer to interrupt clear function */
    return (IOInterruptHandler)_clearInterrupts;
}

- (void)interruptOccurredForInput:(BOOL *)serviceInput forOutput:(BOOL *)serviceOutput
{
    unsigned char *flagsPtr = (unsigned char *)&hardwareFlags;

    /* Check headphones if output is active */
    if (flagsPtr[0] != 0) {
        [self _checkHeadphonesInstalled];
    }

    /* Increment counter at offset 0x194 */
    reserved_0x194++;

    /* Set serviceOutput based on output active flag (byte 0 of hardwareFlags) */
    /* Expression: (byte)(-(uint)*(byte)(addr) >> 0x1f) converts non-zero to 1 */
    *serviceOutput = (flagsPtr[0] != 0) ? YES : NO;

    /* Set serviceInput based on input active flag (byte 1 of hardwareFlags) */
    *serviceInput = (flagsPtr[1] != 0) ? YES : NO;
}

- (BOOL)isInputActive
{
    /* Check if input DMA is active - byte 1 of hardwareFlags (offset 0x185) */
    unsigned char *flagsPtr = (unsigned char *)&hardwareFlags;
    return (char)flagsPtr[1];
}

- (BOOL)isOutputActive
{
    /* Check if output DMA is active - byte 0 of hardwareFlags (offset 0x184) */
    unsigned char *flagsPtr = (unsigned char *)&hardwareFlags;
    return (char)flagsPtr[0];
}

- (void)reset
{
    /* Reset the audio hardware */
    [self setDeviceKind:"PPCBurgundy"];
    [self setUnit:0];
    [self setName:"PPCBurgundy0"];

    return [self _resetBurgundy];
}

- (BOOL)startDMAForChannel:(unsigned int)localChannel
                      read:(BOOL)isRead
                    buffer:(IODMABuffer)buffer
   bufferSizeForInterrupts:(unsigned int)bufferSize
{
    io_request_t request;
    unsigned char *flagsPtr = (unsigned char *)&hardwareFlags;

    /* Initialize request structure */
    request.frameSize = bufferSize;

    if (isRead == NO) {
        /* Output DMA */
        [self getOutputChannelBuffer:&request.buffer size:&request.totalSize];
        request.isOutput = 1;
        [self _startIO:&request];
        flagsPtr[0] = 1;  /* Set output active flag */
    } else {
        /* Input DMA */
        [self getInputChannelBuffer:&request.buffer size:&request.totalSize];
        request.isOutput = 0;
        [self _startIO:&request];
        flagsPtr[1] = 1;  /* Set input active flag */
    }

    return YES;
}

- (void)stopDMAForChannel:(unsigned int)localChannel read:(BOOL)isRead
{
    unsigned char *flagsPtr = (unsigned char *)&hardwareFlags;

    /* Clear active flags */
    if (isRead == NO) {
        /* Output DMA */
        flagsPtr[0] = 0;
    } else {
        /* Input DMA */
        flagsPtr[1] = 0;
    }

    /* Reset audio channel - note inverted logic: OUTPUT gets YES, INPUT gets NO */
    [self _resetAudio:(isRead == NO)];

    /* Clear all interrupt counters */
    totalInterruptCount = 0;      /* 0x188 */
    cumulativeInterruptCount = 0; /* 0x190 */
    frameCount = 0;                /* 0x18c */
    reserved_0x194 = 0;            /* 0x194 */
}

- (void)updateInputGain
{
    unsigned int gainLeft;
    unsigned int gainRight;
    int volumeLR[2];
    int i;

    /* Get gain values from framework */
    gainLeft = [self inputGainLeft];
    volumeLR[0] = (gainLeft >> 1) + 0x4000;

    gainRight = [self inputGainRight];
    volumeLR[1] = (gainRight >> 1) + 0x4000;

    /* Clamp values to valid range [0, 0x8000] */
    for (i = 0; i < 2; i++) {
        if (volumeLR[i] > 0x8000) {
            volumeLR[i] = 0x8000;
        }
        if (volumeLR[i] < 0) {
            volumeLR[i] = 0;
        }
    }

    /* Set hardware input volume */
    [self _setInputVol:volumeLR];
}

- (void)updateInputGainLeft
{
    /* Update left input gain by calling main update method */
    [self updateInputGain];
}

- (void)updateInputGainRight
{
    /* Update right input gain by calling main update method */
    [self updateInputGain];
}

- (void)updateOutputAttenuation
{
    int attenuationLeft;
    int attenuationRight;
    int volumeLR[2];
    int i;

    /* Get attenuation values from framework */
    attenuationLeft = [self outputAttenuationLeft];
    volumeLR[0] = (attenuationLeft + 0x2A) * 0x118 + 0x6000;

    attenuationRight = [self outputAttenuationRight];
    volumeLR[1] = (attenuationRight + 0x2A) * 0x118 + 0x6000;

    /* Clamp values to valid range [0, 0x8000] */
    for (i = 0; i < 2; i++) {
        if (volumeLR[i] > 0x8000) {
            volumeLR[i] = 0x8000;
        }
        if (volumeLR[i] < 0) {
            volumeLR[i] = 0;
        }
    }

    /* Set hardware output volume */
    [self _setOutputVol:volumeLR];
}

- (void)updateOutputAttenuationLeft
{
    /* Update left output attenuation by calling main update method */
    [self updateOutputAttenuation];
}

- (void)updateOutputAttenuationRight
{
    /* Update right output attenuation by calling main update method */
    [self updateOutputAttenuation];
}

- (void)updateOutputMute
{
    BOOL isMuted;

    /* Get current mute state from framework and apply to hardware */
    isMuted = [self isOutputMuted];
    [self _setOutputMute:isMuted];
}

- (void)updateSampleRate:(int)sampleRate
{
    /* Stub: Update sample rate */
    [self _setRate:sampleRate];
}

- (void)_interruptOccurred
{
    int interruptCount;
    int i;
    unsigned int flags;

    /* Lock */
    /* FUN_000004b4() - TODO: implement proper locking */

    /* Read and clear pending interrupt count */
    interruptCount = totalInterruptCount;
    totalInterruptCount = 0;

    /* Unlock */
    /* FUN_000004a4() - TODO: implement proper unlocking */

    /* Accumulate total interrupts at offset 0x190 */
    cumulativeInterruptCount += interruptCount;

    /* Call superclass interrupt handler for each interrupt */
    for (i = 0; i < interruptCount; i++) {
        [super _interruptOccurred];

        /* Check if upper 16 bits of hardwareFlags are clear (DMA inactive) */
        flags = hardwareFlags;
        if ((flags & 0xFFFF0000) == 0) {
            break;
        }
    }
}

@end
