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
 * BurgundySoundPrivate.m
 *
 * PowerPC Burgundy Sound Driver - Private Methods
 *
 */

#import "BurgundySound.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <machkit/NXLock.h>
#import <string.h>

@implementation PPCBurgundy(Private)

- (void)_addAudioBuffer:(void *)buffer
                 Length:(unsigned int)length
              Interrupt:(unsigned int)interruptCount
                 Output:(BOOL)isOutput
{
    unsigned int *descriptorBase;
    volatile unsigned int *descriptor;
    unsigned int commandType;
    unsigned int physicalAddr;
    unsigned int cmdDepField;
    int result;

    /* Select input or output DMA chain */
    if (isOutput) {
        descriptorBase = (unsigned int *)outputDMABufferList;
        descriptor = (volatile unsigned int *)(outputDMABufferList + outputWriteIndex * 0x20);
        commandType = 0;  /* OUTPUT_MORE or OUTPUT_LAST */
    } else {
        descriptorBase = (unsigned int *)inputDMABufferList;
        descriptor = (volatile unsigned int *)(inputDMABufferList + inputWriteIndex * 0x20);
        commandType = 2;  /* INPUT_MORE or INPUT_LAST */
    }

    /* Convert virtual buffer address to physical */
    /* FUN_00001444 - IOPhysicalFromVirtual */
    result = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)buffer, (vm_offset_t *)&physicalAddr);
    if (result != 0) {
        IOLog("PPCSound(burgundy):  Bad audio buffer address - %08x\n", (unsigned int)buffer);
    }

    /* Build DBDMA descriptor (32 bytes, 8 words) */
    /* Word 1: Physical buffer address (byte-swapped) */
    descriptor[1] = bswap32(physicalAddr);

    /* Words 2-3: Reserved/zero */
    descriptor[2] = 0;
    descriptor[3] = 0;

    enforceInOrderExecutionIO();

    /* Word 0: Command word with length and command type */
    descriptor[0] = bswap32(length | (commandType << 28));

    enforceInOrderExecutionIO();

    /* Word 5: Branch address (physical address of hardware index) */
    if (isOutput) {
        descriptor[5] = bswap32(outputHardwareIndexPhys);
    } else {
        descriptor[5] = bswap32(inputHardwareIndexPhys);
    }

    /* Word 6: Status and control fields - copy from current write index position */
    descriptor[6] = bswap32((outputWriteIndex << 24) | (outputWriteIndex << 16) |
                           ((outputWriteIndex << 16) >> 8) | outputWriteIndex);

    /* Word 7: Reserved */
    descriptor[7] = 0;

    enforceInOrderExecutionIO();

    /* Word 4: Command-dependent field (interrupt enable flag) */
    cmdDepField = 0x40000004;
    if (interruptCount != 0) {
        cmdDepField = 0x40300004;  /* Set interrupt enable bits */
    }
    descriptor[4] = bswap32(cmdDepField);

    enforceInOrderExecutionIO();

    /* Increment write index */
    if (isOutput) {
        outputWriteIndex++;
    } else {
        inputWriteIndex++;
    }

    /* Flush descriptor from data cache */
    dcbf((void *)descriptor, 0x20);
}

- (BOOL)_allocateDMAMemory
{
    /* Stub: Allocate memory for DMA descriptor lists and buffers */
    /* TODO: Allocate DBDMA descriptor lists */
    /* TODO: Allocate audio sample buffers */
    return YES;
}

- (BOOL)_checkHeadphonesInstalled
{
    unsigned int senseLines;
    unsigned int muteReg;
    BOOL isOutputMuted;

    /* Read codec sense lines */
    senseLines = _readCodecSenseLines(memoryRange0);

    muteReg = _currentOutputMuteReg;

    /* Check bit 2 (value & 4) for headphone detection */
    if ((senseLines & 4) == 0) {
        /* Headphones not connected */
        isOutputMuted = [self isOutputMuted];
        if (!isOutputMuted) {
            muteReg |= 0x80;  /* Set mute bit */
        }
    } else {
        /* Headphones connected */
        muteReg &= 0xFFFFFF7F;  /* Clear mute bit */
    }

    /* Update mute register if changed */
    if (muteReg != _currentOutputMuteReg) {
        _currentOutputMuteReg = muteReg;
        _writeCodecReg(memoryRange0, 0x16000, muteReg);
    }

    return ((senseLines & 4) != 0);
}

- (unsigned int)_getInputSrc
{
    /* Return current input source from instance variable */
    return currentInputSource;
}

- (void)_getInputVol:(int *)volumeLR
{
    /* Empty - no-op in decompilation */
    return;
}

- (void)_getOutputVol:(int *)volumeLR
{
    /* Empty - no-op in decompilation */
    return;
}

- (unsigned int)_getRate
{
    /* Return current sample rate from instance variable */
    return currentSampleRate;
}

- (void)_loopAudio:(BOOL)shouldLoop
{
    unsigned int dmaBufferList;
    unsigned int *hardwareIndexPtr;
    unsigned int writeIndex;
    volatile unsigned int *descriptor;
    unsigned int physicalAddr;
    int result;

    /* Select input or output DMA chain */
    if (shouldLoop) {
        hardwareIndexPtr = outputHardwareIndex;
        dmaBufferList = outputDMABufferList;
        writeIndex = outputWriteIndex;
    } else {
        hardwareIndexPtr = inputHardwareIndex;
        dmaBufferList = inputDMABufferList;
        writeIndex = inputWriteIndex;
    }

    /* Get descriptor for current write index */
    descriptor = (volatile unsigned int *)(dmaBufferList + writeIndex * 0x20);

    /* Convert virtual address of DMA buffer list to physical */
    result = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)dmaBufferList, (vm_offset_t *)&physicalAddr);
    if (result != 0) {
        IOLog("PPCSound(burgundy) loopAudio - Bad DBDMA command buf - %08x\n", dmaBufferList);
    }

    /* Build DBDMA STOP descriptor to loop */
    descriptor[1] = 0;  /* No buffer address */
    descriptor[2] = bswap32(physicalAddr);  /* Branch back to start of list */
    descriptor[3] = 0;

    enforceInOrderExecutionIO();

    /* Command word: 0x0c60 = STOP command */
    descriptor[0] = 0x0c60;

    enforceInOrderExecutionIO();

    /* Flush descriptor from cache */
    dcbf((void *)descriptor, 0x20);

    /* Start DMA engine */
    if (shouldLoop) {
        _writeBurgundyReg(memoryRange1, 0, 0);  /* Start output DMA */
    } else {
        _writeBurgundyReg(memoryRange2, 0, 0);  /* Start input DMA */
    }

    /* Enable interrupts */
    [self enableAllInterrupts];
}

- (void)_resetAudio:(BOOL)isInput
{
    unsigned int *hardwareIndexPtr;
    unsigned int dmaBufferList;
    unsigned int dmaEngineAddr;
    unsigned int physicalAddr;
    int result;

    /* Select input or output DMA */
    if (!isInput) {
        /* Input DMA */
        hardwareIndexPtr = inputHardwareIndex;
        dmaBufferList = inputDMABufferList;
        dmaEngineAddr = memoryRange2;
    } else {
        /* Output DMA */
        hardwareIndexPtr = outputHardwareIndex;
        dmaBufferList = outputDMABufferList;
        dmaEngineAddr = memoryRange1;
    }

    /* Stop DMA engine */
    _stopDMAEngine(dmaEngineAddr);

    /* Get physical address of DMA buffer list */
    result = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)dmaBufferList, (vm_offset_t *)&physicalAddr);
    if (result != 0) {
        IOLog("PPCSound(burgundy): Bad DBDMA command buf - %08x\n", dmaBufferList);
    }

    /* Write to DMA engine control registers */
    _writeBurgundyReg(dmaEngineAddr, 8, 0);  /* Clear command pointer low */
    enforceInOrderExecutionIO();
    _writeBurgundyReg(dmaEngineAddr, 0xc, bswap32(physicalAddr));  /* Set command pointer high */
    enforceInOrderExecutionIO();

    /* Reset indices - clear offsets at hardwareIndexPtr + 8 and + 0x10 */
    /* These map to inputReadIndex/outputReadIndex and inputWriteIndex/outputWriteIndex */
    if (!isInput) {
        inputReadIndex = 0;
        inputWriteIndex = 0;
    } else {
        outputReadIndex = 0;
        outputWriteIndex = 0;
    }
}

- (BOOL)_resetBurgundy
{
    unsigned int codecControl;
    BOOL result;

    /* Initialize sound control register */
    soundControlReg = 0x11;
    currentSampleRate = 0xAC44;  /* 44100 Hz - Burgundy's only rate */

    /* Write sound control register */
    _writeSoundControlReg(memoryRange0, soundControlReg);

    /* Initialize Burgundy codec registers */
    _writeCodecReg(memoryRange0, 0x12500, 0xDF);  /* Volume controls */
    _writeCodecReg(memoryRange0, 0x12501, 0xDF);
    _writeCodecReg(memoryRange0, 0x42A00, 0x1000100);
    _writeCodecReg(memoryRange0, 0x17800, 0);
    _writeCodecReg(memoryRange0, 0x12D02, 0xDF);
    _writeCodecReg(memoryRange0, 0x12D03, 0xDF);
    _writeCodecReg(memoryRange0, 0x12E00, 0xDF);
    _writeCodecReg(memoryRange0, 0x12E01, 0xDF);
    _writeCodecReg(memoryRange0, 0x12E02, 0xDF);
    _writeCodecReg(memoryRange0, 0x12E03, 0xDF);
    _writeCodecReg(memoryRange0, 0x13000, 0xDF);
    _writeCodecReg(memoryRange0, 0x13001, 0xDF);
    _writeCodecReg(memoryRange0, 0x16500, 0);

    /* Check if DVD variant or standard Burgundy */
    if (!isDVD) {
        /* Standard Burgundy */
        _writeCodecReg(memoryRange0, 0x16200, 0);
        _currentOutputMuteReg = 0x86;
        codecControl = 1;
    } else {
        /* DVD-Video variant */
        _writeCodecReg(memoryRange0, 0x16300, 0);
        _writeCodecReg(memoryRange0, 0x16400, 0);
        _writeCodecReg(memoryRange0, 0x13002, 0xDF);
        _writeCodecReg(memoryRange0, 0x13003, 0xDF);
        _currentOutputMuteReg = 0xF8;
        codecControl = 5;
    }

    /* Write codec control and mute registers */
    _writeCodecReg(memoryRange0, 0x42F00, codecControl);
    _writeCodecReg(memoryRange0, 0x16000, _currentOutputMuteReg);
    _writeCodecReg(memoryRange0, 0x16700, 0x40);

    /* Set input source to default (0x80) */
    [self _setInputSource:0x80];

    /* Allocate DMA memory */
    result = [self _allocateDMAMemory];

    /* Clear interrupt counters */
    totalInterruptCount = 0;
    frameCount = 0;

    return result;
}

- (void)_setInputSource:(unsigned int)source
{
    unsigned int codecReg;

    /* Store input source */
    currentInputSource = source;

    /* Configure codec based on input source */
    if ((source & 0x80) == 0) {
        /* Clear bits for non-0x80 source */
        codecReg = _readCodecReg(memoryRange0, 0x11200);
        _writeCodecReg(memoryRange0, 0x11200, codecReg & 0xFFFFFFFA);

        codecReg = _readCodecReg(memoryRange0, 0x42C00);
        _writeCodecReg(memoryRange0, 0x42C00, codecReg & 0xFFFBFFFB);

        codecReg = _readCodecReg(memoryRange0, 0x42F00);
        _writeCodecReg(memoryRange0, 0x42F00, codecReg & 0xFCFFFFFF);

        codecReg = _readCodecReg(memoryRange0, 0x17A00);
        codecReg = codecReg & 0xFFFFFFFE;
    } else {
        /* Set bits for 0x80 source */
        codecReg = _readCodecReg(memoryRange0, 0x11200);
        _writeCodecReg(memoryRange0, 0x11200, codecReg | 5);

        codecReg = _readCodecReg(memoryRange0, 0x42C00);
        _writeCodecReg(memoryRange0, 0x42C00, codecReg | 0x40004);

        codecReg = _readCodecReg(memoryRange0, 0x42F00);
        _writeCodecReg(memoryRange0, 0x42F00, codecReg | 0x3000000);

        codecReg = _readCodecReg(memoryRange0, 0x17A00);
        codecReg = codecReg | 1;
    }

    /* Write final codec register */
    _writeCodecReg(memoryRange0, 0x17A00, codecReg);
}

- (void)_setInputVol:(int *)volumeLR
{
    int leftScaled;
    int rightScaled;

    if (volumeLR == NULL) {
        return;
    }

    /* Scale volume values for hardware */
    _scale_volume(volumeLR, &leftScaled, &rightScaled);

    /* Write to input volume codec registers */
    _writeCodecReg(memoryRange0, 0x11500, 0x44);
    _writeCodecReg(memoryRange0, 0x12200, leftScaled);
    _writeCodecReg(memoryRange0, 0x12202, rightScaled);

    /* Update shadow register */
    inputVolumeShadow = (volumeLR[0] << 16) | (volumeLR[1] & 0xFFFF);
}

- (void)_setOutputMute:(BOOL)isMuted
{
    unsigned int muteMask;

    /* Determine mute mask based on DVD variant */
    if (isDVD) {
        muteMask = 0xF8;
    } else {
        muteMask = 0x86;
    }

    /* Apply or clear mute bits */
    if (isMuted == NO) {
        /* Mute: OR with mask */
        _currentOutputMuteReg = _currentOutputMuteReg | muteMask;
    } else {
        /* Unmute: AND with inverted mask */
        _currentOutputMuteReg = _currentOutputMuteReg & ~muteMask;
    }

    /* Write to codec mute register */
    _writeCodecReg(memoryRange0, 0x16000, _currentOutputMuteReg);
}

- (void)_setOutputVol:(int *)volumeLR
{
    int leftScaled;
    int rightScaled;

    if (volumeLR == NULL) {
        return;
    }

    /* Scale volume values for hardware */
    _scale_volume(volumeLR, &leftScaled, &rightScaled);

    /* Write to output volume codec registers */
    _writeCodecReg(memoryRange0, 0x13000, leftScaled);
    _writeCodecReg(memoryRange0, 0x13001, rightScaled);

    /* DVD variant has additional output channels */
    if (isDVD) {
        _writeCodecReg(memoryRange0, 0x13002, leftScaled);
        _writeCodecReg(memoryRange0, 0x13003, rightScaled);
    }

    /* Update shadow register */
    outputVolumeShadow = (volumeLR[0] << 16) | (volumeLR[1] & 0xFFFF);
}

- (void)_setRate:(unsigned int)sampleRate
{
    /* Burgundy only supports 44.1kHz - force to that rate */
    currentSampleRate = 0xAC44;

    /* Clear bits 8-10 of sound control register */
    soundControlReg = soundControlReg & 0xFFFFF8FF;

    /* Write updated sound control register */
    _writeSoundControlReg(memoryRange0, soundControlReg);
}

- (void)_startIO:(void *)requestPtr
{
    io_request_t *request = (io_request_t *)requestPtr;
    char *bufferPtr;
    int remainingSize;
    unsigned int frameSize;
    unsigned int chunkSize;

    if (request == NULL) {
        return;
    }

    bufferPtr = request->buffer;
    remainingSize = (request->totalSize / request->frameSize) * request->frameSize;

    /* Process buffer in chunks */
    while (remainingSize != 0) {
        frameSize = request->frameSize;

        /* Split frame into multiple buffers if needed */
        while (frameSize != 0) {
            /* Calculate chunk size (max _entry bytes) */
            chunkSize = frameSize;
            if (frameSize > _entry) {
                chunkSize = _entry;
            }

            /* Add buffer to DMA chain */
            [self _addAudioBuffer:bufferPtr
                           Length:chunkSize
                        Interrupt:(frameSize <= _entry)
                           Output:request->isOutput];

            remainingSize -= chunkSize;
            bufferPtr += chunkSize;
            frameSize -= chunkSize;
        }
    }

    /* Start audio looping */
    [self _loopAudio:request->isOutput];
}

@end
