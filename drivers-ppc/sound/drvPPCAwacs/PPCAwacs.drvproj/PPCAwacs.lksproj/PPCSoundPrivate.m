/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 * Copyright (c) 2025 RhapsodiOS Project. All rights reserved.
 *
 * PPCSoundPrivate.m - PPCAwacs Private Methods
 *
 * HISTORY
 * 26-Oct-25    Created stub implementation for PPCAwacs driver
 */

#import "PPCSound.h"
#import <driverkit/generalFuncs.h>

@implementation PPCAwacs (Private)

/*
 * Add an audio buffer to the DMA queue
 * Sets up a DBDMA descriptor for the buffer
 */
- (void)_addAudioBuffer:(void *)buffer
                 Length:(unsigned int)length
              Interrupt:(int)intNum
                 Output:(BOOL)isOutput
{
    unsigned int *descriptorPtr;
    int descriptorIndex;
    int *channelPtrAddr;
    unsigned int *descriptorBase;
    int commandCode;
    unsigned int physicalAddress[2];
    unsigned int physicalLength;
    unsigned int controlWord;
    int result;
    id task;

    IOLog("PPCAwacs: _addAudioBuffer: buffer=%p length=%d interrupt=%d output=%d\n",
          buffer, length, intNum, isOutput);

    /* Determine if this is input or output */
    if (isOutput) {
        channelPtrAddr = (int *)(((char *)self) + 0x1c8);  // outputChannelPtr offset
        descriptorBase = (unsigned int *)outputDMADescriptors;
        commandCode = DBDMA_CMD_OUTPUT_MORE;
    } else {
        channelPtrAddr = (int *)(((char *)self) + 0x1ac);  // inputChannelPtr offset
        descriptorBase = (unsigned int *)inputDMADescriptors;
        commandCode = DBDMA_CMD_INPUT_MORE;
    }

    /* Get descriptor for current buffer index */
    descriptorIndex = *(int *)(((char *)channelPtrAddr) + 0x10);  // currentInputBuffer or currentOutputBuffer
    descriptorPtr = &descriptorBase[descriptorIndex * 8];  // 8 words per descriptor

    /* Get physical address of buffer */
    task = [self ioTask];  // TODO: get task handle
    result = [task logicalToPhysical:(vm_address_t)buffer
                          actualStart:physicalAddress
                         actualLength:&physicalLength];
    if (result != 0) {
        IOLog("PPCAwacs: Bad audio buffer address - %p\n", buffer);
    }

    /* Build DBDMA descriptor (all values are big-endian) */

    /* Word 1: Physical buffer address */
    descriptorPtr[1] = swapBytes32(physicalAddress[0]);

    /* Words 2-3: reserved, set to 0 */
    descriptorPtr[2] = 0;
    descriptorPtr[3] = 0;

    /* Memory barrier before setting command word */
    enforceInOrderExecutionIO();

    /* Word 0: Command word with length and command code */
    descriptorPtr[0] = swapBytes32((length & 0xFFFF) | (commandCode << 28));

    /* Memory barrier */
    enforceInOrderExecutionIO();

    /* Word 5: Next descriptor branch address */
    descriptorPtr[5] = swapBytes32(*(unsigned int *)(((char *)channelPtrAddr) + 0x4));

    /* Word 6: Control/status word */
    controlWord = (*(unsigned char *)(((char *)channelPtrAddr) + 0x10) << 24) |
                  (*(unsigned char *)(((char *)channelPtrAddr) + 0x11) << 16) |
                  (*(unsigned char *)(((char *)channelPtrAddr) + 0x12) << 8) |
                  (*(unsigned char *)(((char *)channelPtrAddr) + 0x13));
    descriptorPtr[6] = swapBytes32(controlWord);

    /* Word 7: reserved */
    descriptorPtr[7] = 0;

    /* Memory barrier */
    enforceInOrderExecutionIO();

    /* Word 4: Control flags */
    controlWord = DBDMA_WAIT_NEVER | DBDMA_BRANCH_NEVER;
    if (intNum != 0) {
        controlWord |= DBDMA_INTERRUPT_ALWAYS;
    }
    descriptorPtr[4] = swapBytes32(controlWord);

    /* Memory barrier */
    enforceInOrderExecutionIO();

    /* Advance to next buffer index */
    (*(int *)(((char *)channelPtrAddr) + 0x10))++;

    /* Flush cache for the descriptor */
    // TODO: Call cache flush function
    // flush_dcache(descriptorPtr, DMA_DESCRIPTOR_SIZE);
}

/*
 * Allocate DMA memory for audio transfers
 * Allocates DBDMA command buffers for both input and output
 */
- (BOOL)_allocateDMAMemory
{
    int bufferCount;
    int descriptorListEnd;
    int result;
    id task;
    unsigned int physicalAddr[3];

    IOLog("PPCAwacs: _allocateDMAMemory called\n");

    /* Calculate number of buffers based on _entry global */
    bufferCount = (_entry >> 5) - 2;
    IOLog("PPCAwacs: Allocating DMA for %d buffers\n", bufferCount);

    /* ===== ALLOCATE INPUT DMA BUFFERS ===== */

    if (inputDMADescriptors == NULL) {
        /* Allocate memory for input DBDMA descriptors */
        result = IOGetObjectResource("IOMemory", (id *)&inputDMADescriptors, _entry);
        if (result != 0) {
            IOLog("PPCAwacs: Can't allocate input DBDMA commands\n");
            return NO;
        }
    }

    /* Calculate end of descriptor list */
    descriptorListEnd = (unsigned int)inputDMADescriptors + (bufferCount * DMA_DESCRIPTOR_SIZE) + DMA_DESCRIPTOR_SIZE;
    inputChannelPtr = (void *)descriptorListEnd;

    /* Get physical address of input channel pointer */
    task = [self ioTask];
    result = [task logicalToPhysical:(vm_address_t)descriptorListEnd
                          actualStart:physicalAddr
                         actualLength:NULL];
    if (result != 0) {
        IOLog("PPCAwacs: Bad input DBDMA command buf - %p\n", (void *)descriptorListEnd);
    }
    inputPhysicalAddr = physicalAddr[0];

    /* Store buffer count */
    inputBufferSize = bufferCount;

    /* Reset input audio */
    [self _resetAudio:NO];  // NO = input

    /* Zero out the descriptor memory */
    bzero(inputDMADescriptors, _entry);

    /* ===== ALLOCATE OUTPUT DMA BUFFERS ===== */

    if (outputDMADescriptors == NULL) {
        /* Allocate memory for output DBDMA descriptors */
        result = IOGetObjectResource("IOMemory", (id *)&outputDMADescriptors, _entry);
        if (result != 0) {
            IOLog("PPCAwacs: Can't allocate output DBDMA commands\n");
            return NO;
        }
    }

    /* Calculate end of descriptor list */
    descriptorListEnd = (unsigned int)outputDMADescriptors + (bufferCount * DMA_DESCRIPTOR_SIZE) + DMA_DESCRIPTOR_SIZE;
    outputChannelPtr = (void *)descriptorListEnd;

    /* Get physical address of output channel pointer */
    result = [task logicalToPhysical:(vm_address_t)descriptorListEnd
                          actualStart:physicalAddr
                         actualLength:NULL];
    if (result != 0) {
        IOLog("PPCAwacs: Bad output DBDMA command buf - %p\n", (void *)descriptorListEnd);
    }
    outputPhysicalAddr = physicalAddr[0];

    /* Store buffer count */
    outputBufferSize = bufferCount;

    /* Reset output audio */
    [self _resetAudio:YES];  // YES = output

    /* Zero out the descriptor memory */
    bzero(outputDMADescriptors, _entry);

    IOLog("PPCAwacs: DMA memory allocation complete\n");
    return YES;
}

/*
 * Check if headphones are currently installed
 * Reads hardware status register and updates codec control accordingly
 */
- (BOOL)_checkHeadphonesInstalled
{
    unsigned int statusReg;
    unsigned int newCodecControl;
    unsigned int headphoneBit;
    BOOL isMuted;
    unsigned int i;

    IOLog("PPCAwacs: _checkHeadphonesInstalled called\n");

    /* Read codec status register */
    statusReg = _readCodecStatusReg(awacsRegisterBase);

    /* Get current codec control shadow value */
    newCodecControl = codecControlShadow;

    /* Determine which bit to check based on hardware revision */
    if (isPerchHardware || isScreenas5) {
        headphoneBit = SCREAMER_HEADPHONE_BIT_PERCH;  // Bit 2 (0x4)
    } else if (isScreenas8) {
        headphoneBit = SCREAMER_HEADPHONE_BIT_REV8;   // Bit 0 (0x1)
    } else {
        headphoneBit = SCREAMER_HEADPHONE_BIT_DEFAULT; // Bit 3 (0x8)
    }

    /* Check if headphones are plugged in */
    if ((statusReg & headphoneBit) == 0) {
        /* Headphones NOT plugged in */
        headphonesInstalled = NO;

        /* Check if output is currently muted */
        isMuted = [self isOutputMuted];
        if (!isMuted) {
            /* Unmute the codec (clear bit 7) */
            newCodecControl &= ~CODEC_HEADPHONE_MUTE;
        }
    } else {
        /* Headphones ARE plugged in */
        headphonesInstalled = YES;

        /* Mute the codec (set bit 7) */
        newCodecControl |= CODEC_HEADPHONE_MUTE;
    }

    /* Only update if the value changed */
    if (newCodecControl != codecControlShadow) {
        IOLog("PPCAwacs: Headphone state changed, updating codec (0x%x -> 0x%x)\n",
              codecControlShadow, newCodecControl);

        codecControlShadow = newCodecControl;
        _writeCodecControlReg(awacsRegisterBase, newCodecControl);

        /* For Perch hardware, also update SGS shadow registers */
        if (isPerchHardware) {
            /* Clear headphone enable bits in SGS registers */
            _SGSShadow[3] &= ~SGS_HEADPHONE_ENABLE;
            _SGSShadow[5] &= ~SGS_HEADPHONE_ENABLE;

            /* Set headphone enable bits if headphones are plugged in */
            if (headphonesInstalled) {
                _SGSShadow[3] |= SGS_HEADPHONE_ENABLE;
                _SGSShadow[5] |= SGS_HEADPHONE_ENABLE;
            }

            /* Write all SGS shadow registers to hardware */
            for (i = 0; i < 7; i++) {
                // TODO: Write SGS register
                // _writeSGSRegister(0x8A, i, _SGSShadow[i]);
                IOLog("PPCAwacs: Writing SGS register %d = 0x%02x\n", i, _SGSShadow[i]);
            }
        }
    }

    IOLog("PPCAwacs: Headphones %s\n", headphonesInstalled ? "installed" : "not installed");
    return headphonesInstalled;
}

/*
 * Get the current input source
 */
- (unsigned int)_getInputSrc
{
    IOLog("PPCAwacs: _getInputSrc called, returning 0x%x\n", inputSourceSetting);
    return inputSourceSetting;
}

/*
 * Get the input volume for left or right channel
 */
- (unsigned int)_getInputVol:(BOOL)isLeft
{
    int volumeLR[2];
    unsigned int leftScaled;
    unsigned int rightScaled;

    IOLog("PPCAwacs: _getInputVol: %s channel\n", isLeft ? "left" : "right");

    /* Extract scaled values from inputGainShadow register */
    leftScaled = (inputGainShadow >> 4) & 0xF;
    rightScaled = inputGainShadow & 0xF;

    /* Unscale to dB values */
    _unscale_volume(leftScaled, rightScaled, volumeLR, 0);

    return volumeLR[isLeft ? 0 : 1];
}

/*
 * Get the output volume for left or right channel
 */
- (int)_getOutputVol:(BOOL)isLeft
{
    int volumeLR[2];
    unsigned int leftScaled;
    unsigned int rightScaled;

    IOLog("PPCAwacs: _getOutputVol: %s channel\n", isLeft ? "left" : "right");

    /* Extract scaled values from outputAttenuationShadow register */
    leftScaled = (outputAttenuationShadow >> 6) & 0xF;
    rightScaled = outputAttenuationShadow & 0xF;

    /* Unscale to dB values */
    _unscale_volume(leftScaled, rightScaled, volumeLR, 1);

    return volumeLR[isLeft ? 0 : 1];
}

/*
 * Get the current sample rate
 */
- (unsigned int)_getRate
{
    IOLog("PPCAwacs: _getRate called, returning %d Hz\n", currentSampleRate);
    return currentSampleRate;
}

/*
 * Enable or disable audio looping
 * Sets up a DBDMA BRANCH command to loop back to the start
 */
- (void)_loopAudio:(BOOL)isOutput
{
    unsigned int *descriptorPtr;
    int descriptorIndex;
    unsigned int *descriptorBase;
    id task;
    int result;
    unsigned int physicalAddr[2];
    unsigned int controlWord;
    unsigned int dmaBase;

    IOLog("PPCAwacs: _loopAudio: %s\n", isOutput ? "output" : "input");

    /* Determine which DMA channel to set up */
    if (isOutput) {
        descriptorBase = (unsigned int *)outputDMADescriptors;
        descriptorIndex = currentOutputBuffer;
        dmaBase = dmaOutputBase;
    } else {
        descriptorBase = (unsigned int *)inputDMADescriptors;
        descriptorIndex = currentInputBuffer;
        dmaBase = dmaInputBase;
    }

    /* Get pointer to current descriptor */
    descriptorPtr = &descriptorBase[descriptorIndex * 8];  // 8 words per descriptor

    /* Get physical address of the descriptor list start */
    task = [self ioTask];
    result = [task logicalToPhysical:(vm_address_t)descriptorBase
                          actualStart:physicalAddr
                         actualLength:NULL];
    if (result != 0) {
        IOLog("PPCAwacs: loopAudio - Bad DBDMA command buf - %p\n", descriptorBase);
    }

    /* Build DBDMA BRANCH descriptor */
    descriptorPtr[1] = 0;  // Reserved
    descriptorPtr[2] = swapBytes32(physicalAddr[0]);  // Branch address
    descriptorPtr[3] = 0;  // Reserved

    /* Memory barrier */
    enforceInOrderExecutionIO();

    /* Command word: DBDMA_BRANCH_ALWAYS (0x0c60) */
    descriptorPtr[0] = swapBytes32(0x0C60);

    /* Memory barrier */
    enforceInOrderExecutionIO();

    /* Flush cache for the descriptor */
    // TODO: flush_dcache(descriptorPtr, DMA_DESCRIPTOR_SIZE);

    /* Start the DMA engine */
    // TODO: Start DMA controller
    // _startDMAEngine(dmaBase);

    /* Enable all interrupts */
    [self enableAllInterrupts];
}

/*
 * Reset the audio subsystem for input or output
 * Stops DMA and reinitializes channel state
 */
- (void)_resetAudio:(BOOL)isInput
{
    int *channelPtr;
    void *descriptorBase;
    unsigned int dmaBase;
    id task;
    int result;
    unsigned int physicalAddr[11];

    IOLog("PPCAwacs: _resetAudio: %s\n", isInput ? "input" : "output");

    /* Determine which channel to reset */
    if (!isInput) {
        /* Input channel */
        channelPtr = (int *)(((char *)self) + 0x1ac);  // inputChannelPtr
        descriptorBase = inputDMADescriptors;
        dmaBase = dmaInputBase;
    } else {
        /* Output channel */
        channelPtr = (int *)(((char *)self) + 0x1c8);  // outputChannelPtr
        descriptorBase = outputDMADescriptors;
        dmaBase = dmaOutputBase;
    }

    /* Stop the DMA controller */
    // TODO: Implement DMA stop function
    // _stopDMAController(dmaBase);
    IOLog("PPCAwacs: Stopping DMA controller at 0x%x\n", dmaBase);

    /* Get physical address of descriptor base */
    task = [self ioTask];
    result = [task logicalToPhysical:(vm_address_t)descriptorBase
                          actualStart:physicalAddr
                         actualLength:NULL];
    if (result != 0) {
        IOLog("PPCAwacs: Bad DBDMA command buf - %p\n", descriptorBase);
    }

    /* Write to DMA controller registers */
    /* Clear command pointer register (offset 8) */
    *(volatile unsigned int *)(dmaBase + 8) = 0;

    /* Memory barrier */
    enforceInOrderExecutionIO();

    /* Set descriptor list base address (offset 0xc) */
    *(volatile unsigned int *)(dmaBase + 0xc) = swapBytes32(physicalAddr[0]);

    /* Memory barrier */
    enforceInOrderExecutionIO();

    /* Reset channel state */
    *(channelPtr + 2) = 0;   // Offset +8: clear some state
    *(channelPtr + 4) = 0;   // Offset +0x10: clear buffer index

    IOLog("PPCAwacs: Reset %s audio complete, descriptor base physical = 0x%x\n",
          isInput ? "output" : "input", physicalAddr[0]);
}

/*
 * Reset the AWACS hardware
 * Initializes all codec registers to default values
 */
- (void)_resetAwacs
{
    unsigned int statusReg;
    unsigned int hardwareRevision;
    unsigned int i;

    IOLog("PPCAwacs: _resetAwacs called\n");

    /* Read codec status register to get hardware revision */
    statusReg = _readCodecStatusReg(awacsRegisterBase);
    hardwareRevision = (statusReg >> 12) & 0xF;  // Bits 12-15

    IOLog("PPCAwacs: Hardware revision: %d\n", hardwareRevision);

    /* For hardware revision > 2, set power control */
    if (hardwareRevision > 2) {
        powerControlShadow = 0x6000;
        _writeCodecControlReg(awacsRegisterBase, 0x6000);
    }

    /* For Perch hardware, write all SGS shadow registers */
    if (isPerchHardware) {
        for (i = 0; i < 7; i++) {
            // TODO: Replace with actual SGS write function
            // _writeSGSRegister(0x8A, i, _SGSShadow[i]);
            IOLog("PPCAwacs: Writing SGS register %d = 0x%02x\n", i, _SGSShadow[i]);
        }
    }

    /* Initialize sound control shadow register */
    soundControlShadow = 0x211;

    /* Set default sample rate to 22050 Hz (0x5622) */
    currentSampleRate = 0x5622;  // 22050 Hz

    /* Write sound control register */
    _writeSoundControlReg(awacsRegisterBase, soundControlShadow);

    /* Initialize codec shadow registers to default values */
    inputGainShadow = 0;
    codecControlShadow = 0x1000;
    codecRegister2Shadow = 0x2000;
    outputAttenuationShadow = 0x4000;

    /* Add default gain settings */
    inputGainShadow |= 0x4CC;

    /* For Perch or Screamer 5, add additional codec control bits */
    if (isPerchHardware || isScreenas5) {
        codecControlShadow |= 0xC00;
    }

    /* Write all codec control registers to hardware */
    _writeCodecControlReg(awacsRegisterBase, inputGainShadow);
    _writeCodecControlReg(awacsRegisterBase, codecControlShadow);
    _writeCodecControlReg(awacsRegisterBase, codecRegister2Shadow);
    _writeCodecControlReg(awacsRegisterBase, outputAttenuationShadow);

    /* Allocate DMA memory */
    [self _allocateDMAMemory];

    /* Reset interrupt counters */
    interruptCount = 0;
    processedInterruptCount = 0;
    totalInterruptCount = 0;

    IOLog("PPCAwacs: AWACS reset complete\n");
}

/*
 * Set the input source
 */
- (void)_setInputSource:(unsigned int)source
{
    unsigned int controlBits = 0;

    IOLog("PPCAwacs: _setInputSource: 0x%x\n", source);

    /* Build control bits based on input source flags */
    if ((source & 0x80) != 0) {
        controlBits = 0x400;  // Bit 10
    }
    if ((source & 0x100) != 0) {
        controlBits |= 0x200;  // Bit 9
    }

    /* Store the input source setting (mask to bits 7 and 8) */
    inputSourceSetting = source & 0x180;

    /* Update inputGainShadow register, preserving other bits */
    inputGainShadow = (inputGainShadow & 0xFFFFF1FF) | controlBits;

    /* Write to hardware */
    _writeCodecControlReg(awacsRegisterBase, inputGainShadow);
}

/*
 * Set the input volume
 */
- (void)_setInputVol:(int *)volumeLR
{
    int leftScaled;
    unsigned int rightScaled;

    /* Scale the volume values */
    _scale_volume(volumeLR, &leftScaled, &rightScaled, 0);

    /* Clear existing volume bits and set new values */
    inputGainShadow = (inputGainShadow & 0xFFFFFF00) | (leftScaled << 4) | rightScaled;

    /* Write to hardware */
    _writeCodecControlReg(awacsRegisterBase, inputGainShadow);
}

/*
 * Set the output mute state
 */
- (void)_setOutputMute:(BOOL)isMuted
{
    unsigned int newValue;

    IOLog("PPCAwacs: _setOutputMute: %s\n", isMuted ? "muted" : "unmuted");

    if (isMuted) {
        /* Set mute bits (bit 7 and bit 9) */
        newValue = codecControlShadow | 0x280;
    } else {
        /* Clear mute bits */
        newValue = codecControlShadow & 0xFFFFFD7F;
    }

    codecControlShadow = newValue;

    /* Write to hardware */
    _writeCodecControlReg(awacsRegisterBase, codecControlShadow);
}

/*
 * Set the output volume
 */
- (void)_setOutputVol:(int *)volumeLR
{
    int leftScaled;
    unsigned int rightScaled;

    /* For Screamer revision 8, halve the volume */
    if (isScreenas8) {
        volumeLR[0] >>= 1;
        volumeLR[1] >>= 1;
    }

    /* Scale the volume values */
    _scale_volume(volumeLR, &leftScaled, &rightScaled, 1);

    /* Update outputAttenuationShadow register */
    outputAttenuationShadow = (outputAttenuationShadow & 0xFFFFFC30) |
                              (leftScaled << 6) | rightScaled;
    _writeCodecControlReg(awacsRegisterBase, outputAttenuationShadow);

    /* Update codecRegister2Shadow register */
    codecRegister2Shadow = (codecRegister2Shadow & 0xFFFFFC30) |
                           (leftScaled << 6) | rightScaled;
    _writeCodecControlReg(awacsRegisterBase, codecRegister2Shadow);
}

/*
 * Set the sample rate
 */
- (void)_setRate:(unsigned int)rate
{
    unsigned int i;
    unsigned int rateIndex;

    IOLog("PPCAwacs: _setRate: %d Hz\n", rate);

    /* Find the appropriate rate index */
    rateIndex = 0;
    for (i = 0; i < 7; i++) {  // Note: loop goes up to 7, not _num_awacs_rates
        if (rate <= _awacs_rates[i]) {
            rateIndex = i;
            break;
        }
    }

    /* Set the actual rate from the table */
    currentSampleRate = _awacs_rates[rateIndex];

    /* Update soundControlShadow register with rate index in bits 8-10 */
    /* Rate field is inverted: (7 - rateIndex) << 8 */
    soundControlShadow = (soundControlShadow & 0xFFFFF8FF) | ((7 - rateIndex) << 8);

    /* Write to hardware */
    _writeSoundControlReg(awacsRegisterBase, soundControlShadow);

    IOLog("PPCAwacs: Sample rate set to %d Hz (index %d)\n", currentSampleRate, rateIndex);
}

/*
 * Start I/O for input or output
 * This is called with an io_request_t structure describing the I/O operation
 * Breaks the request into buffer-sized chunks and queues them
 */
- (void)_startIO:(io_request_t *)request
{
    char *currentBuffer;
    int remainingBytes;
    unsigned int blockSize;
    unsigned int chunkSize;
    BOOL generateInterrupt;

    IOLog("PPCAwacs: _startIO: buffer=%p totalSize=%d blockSize=%d %s\n",
          request->buffer, request->totalSize, request->blockSize,
          request->isOutput ? "output" : "input");

    currentBuffer = request->buffer;

    /* Calculate total bytes to transfer (rounded down to block boundaries) */
    remainingBytes = (request->totalSize / request->blockSize) * request->blockSize;

    /* Process all data in blocks */
    while (remainingBytes != 0) {
        /* Process one complete block */
        blockSize = request->blockSize;

        /* Break the block into chunks that fit in DMA buffers */
        while (blockSize != 0) {
            /* Determine chunk size */
            chunkSize = blockSize;
            if (chunkSize > _entry) {
                chunkSize = _entry;  // Limit to DMA buffer size
            }

            /* Determine if we should generate an interrupt for this chunk */
            /* Generate interrupt if this is the last chunk of the block */
            generateInterrupt = (blockSize <= _entry);

            /* Queue the audio buffer */
            [self _addAudioBuffer:currentBuffer
                           Length:chunkSize
                        Interrupt:generateInterrupt
                           Output:request->isOutput];

            /* Advance pointers */
            remainingBytes -= chunkSize;
            blockSize -= chunkSize;
            currentBuffer += chunkSize;
        }
    }

    /* Set up looping for continuous playback/recording */
    [self _loopAudio:request->isOutput];

    IOLog("PPCAwacs: _startIO complete, queued %d bytes\n",
          request->totalSize - remainingBytes);
}

@end
