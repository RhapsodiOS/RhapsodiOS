/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 * Copyright (c) 2025 RhapsodiOS Project. All rights reserved.
 *
 * PPCSound.m - PPCAwacs Audio Device Driver
 *
 * HISTORY
 * 26-Oct-25    Created stub implementation for PPCAwacs driver
 */

#import "PPCSound.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>

/* Global instance for interrupt handlers */
static PPCAwacs *globalInstance = nil;

/* Global buffer count from device tree or configuration */
extern unsigned int _entry;  // Number of DMA buffers to allocate

/*
 * AWACS supported sampling rates array
 * Rates are in Hz
 */
unsigned int _awacs_rates[] = {
    7350,   // 0x1CB6
    8820,   // 0x2274
    11025,  // 0x2B11
    14700,  // 0x396C
    17640,  // 0x44E8
    22050,  // 0x5622
    29400,  // 0x72D8
    44100   // 0xAC44
};

/* Number of supported sampling rates */
unsigned int _num_awacs_rates = 8;

/*
 * Sound Generation System shadow registers
 * Used to maintain state of AWACS hardware registers
 */
unsigned char _SGSShadow[] = {
    0x09,   // SGS register 0
    0x20,   // SGS register 1
    0xFF,   // SGS register 2
    0x00,   // SGS register 3
    0x0A,   // SGS register 4
    0x00,   // SGS register 5
    0x0A    // SGS register 6
};

/*
 * Hardware Access Helper Functions
 */

/*
 * Read AWACS clipping count register
 * Combines 4 bytes at offsets 0x30-0x33 into a 32-bit big-endian value
 */
unsigned int _readClippingCountReg(unsigned int baseAddr)
{
    volatile unsigned char *reg = (volatile unsigned char *)baseAddr;
    return ((unsigned int)reg[0x33] << 24) |
           ((unsigned int)reg[0x32] << 16) |
           ((unsigned int)reg[0x31] << 8) |
           ((unsigned int)reg[0x30]);
}

/*
 * Read AWACS codec status register
 * Combines 4 bytes at offsets 0x20-0x23 into a 32-bit big-endian value
 */
unsigned int _readCodecStatusReg(unsigned int baseAddr)
{
    volatile unsigned char *reg = (volatile unsigned char *)baseAddr;
    return ((unsigned int)reg[0x23] << 24) |
           ((unsigned int)reg[0x22] << 16) |
           ((unsigned int)reg[0x21] << 8) |
           ((unsigned int)reg[0x20]);
}

/*
 * Write AWACS codec control register
 * Writes byte-swapped value to offset 0x10 and waits for busy bit to clear
 */
void _writeCodecControlReg(unsigned int baseAddr, unsigned int value)
{
    volatile unsigned int *reg = (volatile unsigned int *)(baseAddr + 0x10);
    volatile unsigned char *statusByte = (volatile unsigned char *)(baseAddr + 0x13);
    unsigned int swappedValue;

    /* Byte swap value to big-endian format */
    swappedValue = (value << 24) | ((value & 0xFF00) << 8) |
                   ((value >> 8) & 0xFF00) | (value >> 24);

    /* Write to codec control register at offset 0x10 */
    *reg = swappedValue;

    /* Ensure write completes before checking status */
    enforceInOrderExecutionIO();

    /* Wait for busy bit (bit 0 of byte at offset 0x13) to clear */
    do {
        enforceInOrderExecutionIO();
    } while ((*statusByte & 1) != 0);
}

/*
 * Write AWACS sound control register
 * Writes byte-swapped value to offset 0x0
 */
void _writeSoundControlReg(unsigned int baseAddr, unsigned int value)
{
    volatile unsigned int *reg = (volatile unsigned int *)baseAddr;
    unsigned int swappedValue;

    /* Byte swap value to big-endian format */
    swappedValue = (value << 24) | ((value & 0xFF00) << 8) |
                   ((value >> 8) & 0xFF00) | (value >> 24);

    /* Write to sound control register at offset 0x0 */
    *reg = swappedValue;

    /* Ensure write completes */
    enforceInOrderExecutionIO();
}

/*
 * Enforce in-order execution of I/O operations (memory barrier)
 * On PowerPC, this is the eieio instruction
 */
void enforceInOrderExecutionIO(void)
{
    /* PowerPC eieio (Enforce In-order Execution of I/O) instruction */
    __asm__ volatile("eieio" ::: "memory");
}

/*
 * Byte swap 32-bit value (big-endian <-> little-endian)
 */
static inline unsigned int swapBytes32(unsigned int value)
{
    return (value << 24) | ((value & 0xFF00) << 8) |
           ((value >> 8) & 0xFF00) | (value >> 24);
}

/*
 * Scale volume from [0, 0x8000] to hardware [0, 0xF] range
 * leftRight: array of [left, right] volume values in [0, 0x8000] range
 * leftScaled: pointer to receive scaled left channel value [0, 0xF]
 * rightScaled: pointer to receive scaled right channel value [0, 0xF]
 * isOutput: 1 for output (inverts value for attenuation), 0 for input (direct)
 */
void _scale_volume(int *leftRight, int *leftScaled, unsigned int *rightScaled, int isOutput)
{
    unsigned int leftTemp, rightTemp;

    /* Scale from [0, 0x8000] to [0, 0xF] by multiplying by 0xF and dividing by 0x8000 */
    leftTemp = leftRight[0] * 0xF;
    /* Divide by 0x8000 (shift right 15) with rounding */
    *leftScaled = ((int)leftTemp >> 15) + (unsigned int)(((int)leftTemp < 0) && ((leftTemp & 0x7FFF) != 0));

    rightTemp = leftRight[1] * 0xF;
    *rightScaled = ((int)rightTemp >> 15) + (unsigned int)(((int)rightTemp < 0) && ((rightTemp & 0x7FFF) != 0));

    /* For output, invert values (0xF - value) to convert volume to attenuation */
    if (isOutput != 0) {
        *leftScaled = 0xF - *leftScaled;
        *rightScaled = 0xF - *rightScaled;
    }

    /* Clamp to valid range [0, 0xF] */
    if (*leftScaled > 0xF) {
        *leftScaled = 0xF;
    }
    if (*leftScaled < 0) {
        *leftScaled = 0;
    }
    if (*rightScaled > 0xF) {
        *rightScaled = 0xF;
    }
    if (*rightScaled < 0) {
        *rightScaled = 0;
    }
}

/*
 * Unscale volume from hardware [0, 0xF] range to [0, 0x8000]
 * leftScaled: scaled left channel value from register [0, 0xF]
 * rightScaled: scaled right channel value from register [0, 0xF]
 * leftRight: array to receive [left, right] volume values in [0, 0x8000] range
 * isOutput: 1 for output (un-inverts value from attenuation), 0 for input (direct)
 */
void _unscale_volume(unsigned int leftScaled, unsigned int rightScaled, int *leftRight, int isOutput)
{
    int leftValue, rightValue;

    /* For output, un-invert values (0xF - value) to convert attenuation to volume */
    if (isOutput != 0) {
        leftScaled = 0xF - leftScaled;
        rightScaled = 0xF - rightScaled;
    }

    /* Scale from [0, 0xF] to [0, 0x8000] by multiplying by 0x8000 and dividing by 0xF */
    leftValue = (leftScaled << 15) / 0xF;
    rightValue = (rightScaled << 15) / 0xF;

    /* Clamp to maximum 0x8000 */
    if (leftValue > 0x8000) {
        leftValue = 0x8000;
    }
    if (rightValue > 0x8000) {
        rightValue = 0x8000;
    }

    leftRight[0] = leftValue;
    leftRight[1] = rightValue;
}

@implementation PPCAwacs

/*
 * Probe for device and create instance
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    PPCAwacs *instance;
    const char *compatible;
    unsigned int numMemoryRanges;
    IORange *memoryRangeList;
    id busClass;
    id perchDevice;
    const char *deviceName;
    unsigned int *soundPropertyData;
    unsigned int soundPropertyLength;
    int propertyResult;

    IOLog("PPCAwacs: probe called\n");

    /* Check if this is a burgundy or DVD device - we don't support those */
    compatible = [deviceDescription propertyStringFor:"compatible"];
    if (compatible != NULL) {
        if ((strcmp(compatible, "burgundy") == 0) ||
            (strcmp(compatible, "DVD-Video and Audio/Video") == 0)) {
            IOLog("PPCAwacs: Device is %s, not AWACS - skipping\n", compatible);
            return NO;
        }
    }

    /* Verify we have at least 3 memory ranges */
    numMemoryRanges = [deviceDescription numMemoryRanges];
    if (numMemoryRanges < 3) {
        IOLog("PPCAwacs: Incorrect device description - need at least 3 memory ranges, got %d\n",
              numMemoryRanges);
        return NO;
    }

    /* Allocate instance */
    instance = [self alloc];
    if (instance == nil) {
        IOLog("PPCAwacs: Failed to allocate instance\n");
        return NO;
    }

    /* Get memory range list and store base addresses */
    memoryRangeList = [deviceDescription memoryRangeList];
    instance->awacsRegisterBase = memoryRangeList[0].start;
    instance->dmaInputBase = memoryRangeList[1].start;
    instance->dmaOutputBase = memoryRangeList[2].start;

    IOLog("PPCAwacs: AWACS registers at 0x%x, Input DMA at 0x%x, Output DMA at 0x%x\n",
          instance->awacsRegisterBase, instance->dmaInputBase, instance->dmaOutputBase);

    /* Initialize hardware revision flags */
    instance->isPerchHardware = NO;
    instance->isScreenas5 = NO;
    instance->isScreenas8 = NO;

    /* Check if we're on Perch hardware */
    busClass = [deviceDescription deviceClass];
    if (busClass != nil) {
        perchDevice = [busClass performSelector:@selector(findMatchingDevice:location:)
                                      withObject:@"perch"
                                      withObject:nil];
        if (perchDevice != nil) {
            IOLog("PPCAwacs: Detected Perch hardware\n");
            instance->isPerchHardware = YES;
        }
    }

    /* Check for Screamer hardware revision */
    if (!instance->isPerchHardware) {
        deviceName = [deviceDescription propertyStringFor:"name"];
        if (deviceName != NULL && strcmp(deviceName, "sound") == 0) {
            /* Get property 0x1f00 (layout-id or sound-objects property) */
            propertyResult = [deviceDescription propertyFor:0x1f00
                                                      value:(void **)&soundPropertyData
                                                     length:&soundPropertyLength];
            if (propertyResult && soundPropertyLength == 4) {
                unsigned int revisionValue = *soundPropertyData;
                IOLog("PPCAwacs: Sound property value: %d\n", revisionValue);

                if (revisionValue == 5) {
                    IOLog("PPCAwacs: Detected Screamer 5 hardware\n");
                    instance->isScreenas5 = YES;
                } else if (revisionValue == 8) {
                    IOLog("PPCAwacs: Detected Screamer 8 hardware\n");
                    instance->isScreenas8 = YES;
                }
            }
        }
    }

    /* Initialize the device */
    if ([instance initFromDeviceDescription:deviceDescription] == nil) {
        IOLog("PPCAwacs: Failed to initialize from device description\n");
        [instance free];
        return NO;
    }

    globalInstance = instance;

    IOLog("PPCAwacs: Probe successful\n");
    return YES;
}

/*
 * Reset and initialize the device
 * Sets device properties and calls _resetAwacs to initialize hardware
 */
- (BOOL)reset
{
    [self setDeviceKind:"PPCAwacs"];
    [self setUnit:0];
    [self setName:"PPCAwacs0"];
    [self _resetAwacs];
    return YES;
}

/*
 * Handle interrupt occurred callback - called from interrupt handlers
 * This processes accumulated interrupts and notifies the IOAudio framework
 */
- (void)_interruptOccurred
{
    int savedInterruptCount;
    int i;

    /*
     * Atomically get the interrupt count
     * Note: FUN_00000580() and FUN_00000570() in the original binary both call entry()
     * and are effectively no-ops. The driver appears to rely on interrupt context
     * or hardware interrupt masking for atomicity rather than explicit locks.
     */
    savedInterruptCount = interruptCount;
    interruptCount = 0;

    /* Update total processed interrupt count */
    processedInterruptCount += savedInterruptCount;

    /* Call superclass _interruptOccurred for each pending interrupt */
    for (i = 0; i < savedInterruptCount; i++) {
        [super _interruptOccurred];

        /* Check if we should stop processing - hardware flag check */
        if ((hardwareFlags & 0xFFFF0000) != 0) {
            break;
        }
    }
}

/*
 * Determine which interrupts need service
 * Checks hardware flags and calls headphone detection if output is active
 */
- (void)interruptOccurredForInput:(BOOL *)serviceInput forOutput:(BOOL *)serviceOutput
{
    unsigned char *flagsPtr = (unsigned char *)&hardwareFlags;
    unsigned char outputActive = flagsPtr[0];  // Byte at offset 0x184
    unsigned char inputActive = flagsPtr[1];   // Byte at offset 0x185

    /* If output is active, check headphone status */
    if (outputActive != 0) {
        [self _checkHeadphonesInstalled];
    }

    /* Increment processed interrupt count */
    processedInterruptCount++;

    /* Set service flags based on active status
     * Formula from decompiled code: (-(uint)byte >> 0x1f)
     * This converts non-zero byte to 1, zero byte to 0
     */
    *serviceOutput = (outputActive != 0) ? YES : NO;
    *serviceInput = (inputActive != 0) ? YES : NO;
}

/*
 * Get the number of audio channels
 * Always returns 2 for stereo
 */
- (unsigned int)channelCount
{
    return 2;
}

/*
 * Get the maximum number of channels supported
 * Always returns 2 for stereo only
 */
- (unsigned int)channelCountLimit
{
    return 2;
}

/*
 * Get the range of supported sampling rates
 * Returns 0x1cb6 (7350 Hz) and 0xac44 (44100 Hz)
 */
- (void)getSamplingRatesLow:(int *)lowRate high:(int *)highRate
{
    *lowRate = 0x1cb6;   // 7350 Hz - lowest supported rate
    *highRate = 0xac44;  // 44100 Hz - highest supported rate
}

/*
 * Get the list of supported sampling rates
 * Copies the entire _awacs_rates array to the provided buffer
 */
- (void)getSamplingRates:(int *)rates count:(unsigned int *)numRates
{
    /* Set the count to 8 */
    *numRates = 8;

    /* Copy the _awacs_rates array (32 bytes = 8 rates * 4 bytes each) */
    if (rates != NULL) {
        bcopy(_awacs_rates, rates, 0x20);  // Copy 32 bytes
    }
}

/*
 * Get the list of supported data encodings
 * Returns 16-bit linear PCM (value 600)
 */
- (void)getDataEncodings:(NXSoundParameterTag *)encodings count:(unsigned int *)numEncodings
{
    /* Set count to 1 - only one encoding supported */
    *numEncodings = 1;

    /* Set encoding to 600 (16-bit linear PCM) */
    *encodings = 600;
}

/*
 * Get interrupt handler information
 * Returns appropriate handler based on interrupt number:
 *   1 = Output interrupt
 *   2 = Input interrupt
 */
- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(void **)arg
      forInterrupt:(unsigned int)localInterrupt
{
    /* Determine handler based on interrupt number */
    if (localInterrupt == 1) {
        /* Output interrupt */
        *handler = (IOInterruptHandler)_PPCSoundOutputInt;
    } else if (localInterrupt == 2) {
        /* Input interrupt */
        *handler = (IOInterruptHandler)_PPCSoundInputInt;
    } else {
        /* Invalid interrupt number */
        return NO;
    }

    /* Set interrupt priority level to 0x18 (IPLDEVICE) */
    *ipl = 0x18;

    /* Set argument to self (the driver instance) */
    *arg = self;

    return YES;
}

/*
 * Check if input is currently active
 * Returns byte at offset 0x185 (second byte of hardwareFlags)
 */
- (BOOL)isInputActive
{
    unsigned char *flagsPtr = (unsigned char *)&hardwareFlags;
    return (flagsPtr[1] != 0);  // Byte at offset 0x185
}

/*
 * Check if output is currently active
 * Returns byte at offset 0x184 (first byte of hardwareFlags)
 */
- (BOOL)isOutputActive
{
    unsigned char *flagsPtr = (unsigned char *)&hardwareFlags;
    return (flagsPtr[0] != 0);  // Byte at offset 0x184
}

/*
 * Start DMA for a channel
 */
- (BOOL)startDMAForChannel:(unsigned int)localChannel
                      read:(BOOL)isRead
                    buffer:(IODMABuffer)buffer
   bufferSizeForInterrupts:(unsigned int)bufferSize
{
    unsigned int sampleRate;
    io_request_t request;
    char *channelBuffer;
    unsigned int channelSize;
    unsigned char *flagsPtr = (unsigned char *)&hardwareFlags;

    /* Get current sample rate and update it */
    sampleRate = [self sampleRate];
    [self updateSampleRate:sampleRate];

    /* Build I/O request structure */
    request.blockSize = bufferSize;

    if (isRead == NO) {
        /* Output channel */
        [self getOutputChannelBuffer:&channelBuffer size:&channelSize];
        request.buffer = channelBuffer;
        request.totalSize = channelSize;
        request.isOutput = YES;

        /* Start I/O */
        [self _startIO:&request];

        /* Set output active flag at byte 0x184 */
        flagsPtr[0] = 1;
    } else {
        /* Input channel */
        [self getInputChannelBuffer:&channelBuffer size:&channelSize];
        request.buffer = channelBuffer;
        request.totalSize = channelSize;
        request.isOutput = NO;

        /* Start I/O */
        [self _startIO:&request];

        /* Set input active flag at byte 0x185 */
        flagsPtr[1] = 1;
    }

    return YES;
}

/*
 * Stop DMA for a channel
 * Clears hardware flags, resets the audio channel, and clears interrupt counters
 */
- (void)stopDMAForChannel:(unsigned int)localChannel read:(BOOL)isRead
{
    unsigned char *flagsPtr = (unsigned char *)&hardwareFlags;
    int *counterPtr;

    /* Clear hardware active flag */
    if (isRead == NO) {
        /* Clear output active flag at byte 0x184 */
        flagsPtr[0] = 0;
    } else {
        /* Clear input active flag at byte 0x185 */
        flagsPtr[1] = 0;
    }

    /* Reset the audio channel - parameter is YES for output (isRead == NO) */
    [self _resetAudio:(isRead == NO)];

    /* Clear all interrupt counters */
    interruptCount = 0;                  // Offset 0x188
    totalInterruptCount = 0;             // Offset 0x18c
    processedInterruptCount = 0;         // Offset 0x190 (400 decimal)

    /* Clear additional counter at offset 0x194 (404 decimal) */
    counterPtr = (int *)(((char *)self) + 0x194);
    *counterPtr = 0;
}

/*
 * Get the interrupt clear function
 */
- (IOAudioInterruptClearFunc)interruptClearFunc
{
    /* Return pointer to _clearInterrupts function */
    return (IOAudioInterruptClearFunc)&_clearInterrupts;
}

/*
 * Update the sample rate
 * Calls _setRate: to apply the new rate to hardware
 */
- (void)updateSampleRate:(unsigned int)newRate
{
    [self _setRate:newRate];
}

/*
 * Update input gain (both channels)
 * Gets left/right values from framework, clamps to [0, 0x8000], and updates hardware
 */
- (void)updateInputGain
{
    int gainValues[2];
    int i;

    /* Get left and right gain values from IOAudio framework */
    gainValues[0] = [self inputGainLeft];
    gainValues[1] = [self inputGainRight];

    /* Clamp values to valid range [0, 0x8000] */
    for (i = 0; i < 2; i++) {
        if (gainValues[i] > 0x8000) {
            gainValues[i] = 0x8000;
        }
        if (gainValues[i] < 0) {
            gainValues[i] = 0;
        }
    }

    /* Apply to hardware */
    [self _setInputVol:gainValues];
}

/*
 * Update left input gain - calls updateInputGain
 */
- (void)updateInputGainLeft
{
    [self updateInputGain];
}

/*
 * Update right input gain - calls updateInputGain
 */
- (void)updateInputGainRight
{
    [self updateInputGain];
}

/*
 * Update output attenuation (both channels)
 * Gets left/right attenuation values from framework, applies dB conversion, and updates hardware
 * Formula: ((attenuation + 84) * 8192) / 21
 */
- (void)updateOutputAttenuation
{
    int attenuationValues[2];
    int leftAtt, rightAtt;
    int i;

    /* Get left and right attenuation values from IOAudio framework */
    leftAtt = [self outputAttenuationLeft];
    rightAtt = [self outputAttenuationRight];

    /* Apply dB conversion formula */
    attenuationValues[0] = ((leftAtt + 0x54) * 0x2000) / 0x15;
    attenuationValues[1] = ((rightAtt + 0x54) * 0x2000) / 0x15;

    /* Clamp values to valid range [0, 0x8000] */
    for (i = 0; i < 2; i++) {
        if (attenuationValues[i] > 0x8000) {
            attenuationValues[i] = 0x8000;
        }
        if (attenuationValues[i] < 0) {
            attenuationValues[i] = 0;
        }
    }

    /* Apply to hardware */
    [self _setOutputVol:attenuationValues];
}

/*
 * Update left output attenuation - calls updateOutputAttenuation
 */
- (void)updateOutputAttenuationLeft
{
    [self updateOutputAttenuation];
}

/*
 * Update right output attenuation - calls updateOutputAttenuation
 */
- (void)updateOutputAttenuationRight
{
    [self updateOutputAttenuation];
}

/*
 * Update output mute state
 * Gets current mute state from framework and applies to hardware
 */
- (void)updateOutputMute
{
    BOOL isMuted;

    /* Get current mute state from IOAudio framework */
    isMuted = [self isOutputMuted];

    /* Apply to hardware */
    [self _setOutputMute:isMuted];
}

@end

/*
 * Utility Functions
 */

/*
 * Service input interrupt - process completed input DMA buffers
 * Returns the number of buffers processed
 */
int _serviceInputInterrupt(PPCAwacs *instance)
{
    int buffersProcessed = 0;
    unsigned int loopCount = 0;
    int startBufferIndex;
    unsigned char *descriptorBase;
    unsigned char statusByte;

    if (instance->numInputBuffers == 0) {
        return 0;
    }

    descriptorBase = (unsigned char *)instance->inputDMADescriptors;

    do {
        startBufferIndex = instance->currentInputBuffer;

        /* Check status byte in the DMA descriptor */
        statusByte = descriptorBase[startBufferIndex * DMA_DESCRIPTOR_SIZE + DMA_STATUS_OFFSET];

        if ((statusByte & DMA_STATUS_MASK) != 0) {
            buffersProcessed++;
        }

        /* Advance to next buffer */
        instance->currentInputBuffer++;
        if (instance->currentInputBuffer >= instance->numInputBuffers) {
            instance->currentInputBuffer = 0;
        }

        /* Advance the input channel pointer
         * Note: FUN_00000f64(inputChannelPtr, 4) in the original binary calls entry()
         * and is effectively a no-op stub. The actual channel advancement appears to
         * happen through other mechanisms (likely hardware or framework-managed).
         */

        loopCount++;

    } while ((*(int *)instance->inputChannelPtr != startBufferIndex) &&
             (loopCount < instance->numInputBuffers));

    return buffersProcessed;
}

/*
 * Service output interrupt - process completed output DMA buffers
 * Returns the number of buffers processed
 */
int _serviceOutputInterrupt(PPCAwacs *instance)
{
    int buffersProcessed = 0;
    unsigned int loopCount = 0;
    int startBufferIndex;
    unsigned char *descriptorBase;
    unsigned char statusByte;

    if (instance->numOutputBuffers == 0) {
        return 0;
    }

    descriptorBase = (unsigned char *)instance->outputDMADescriptors;

    do {
        startBufferIndex = instance->currentOutputBuffer;

        /* Check status byte in the DMA descriptor */
        statusByte = descriptorBase[startBufferIndex * DMA_DESCRIPTOR_SIZE + DMA_STATUS_OFFSET];

        if ((statusByte & DMA_STATUS_MASK) != 0) {
            buffersProcessed++;
        }

        /* Advance to next buffer */
        instance->currentOutputBuffer++;
        if (instance->currentOutputBuffer >= instance->numOutputBuffers) {
            instance->currentOutputBuffer = 0;
        }

        /* Advance the output channel pointer
         * Note: FUN_00000e6c(outputChannelPtr, 4) in the original binary calls entry()
         * and is effectively a no-op stub. The actual channel advancement appears to
         * happen through other mechanisms (likely hardware or framework-managed).
         */

        loopCount++;

    } while ((*(int *)instance->outputChannelPtr != startBufferIndex) &&
             (loopCount < instance->numOutputBuffers));

    return buffersProcessed;
}

/*
 * Input interrupt handler
 */
void _PPCSoundInputInt(void *param1, void *param2, void *instance)
{
    PPCAwacs *self = (PPCAwacs *)instance;
    int buffersProcessed;

    if (self == nil) {
        return;
    }

    buffersProcessed = _serviceInputInterrupt(self);

    if (buffersProcessed != 0) {
        /* On first interrupt, start audio processing */
        if (self->interruptCount == 0) {
            /* FUN_00000484 is a NULL stub (branches to 0x00000000) - not implemented */
            /* This appears to be an optional callback that isn't needed for AWACS */
        }

        /* Update interrupt counters */
        self->interruptCount += buffersProcessed;
        self->totalInterruptCount += buffersProcessed;

        /* Notify IOAudio framework of completed buffers */
        [self _interruptOccurred];
    }

    /* FUN_00000474 is a NULL stub (branches to 0x00000000) - not implemented */
    /* Interrupt clearing is handled by DBDMA status register reads */
}

/*
 * Output interrupt handler
 */
void _PPCSoundOutputInt(void *param1, void *param2, void *instance)
{
    PPCAwacs *self = (PPCAwacs *)instance;
    int buffersProcessed;

    if (self == nil) {
        return;
    }

    buffersProcessed = _serviceOutputInterrupt(self);

    if (buffersProcessed != 0) {
        /* On first interrupt, start audio processing */
        if (self->interruptCount == 0) {
            /* FUN_000003b4 is a NULL stub (branches to 0x00000000) - not implemented */
            /* This appears to be an optional callback that isn't needed for AWACS */
        }

        /* Update interrupt counters */
        self->interruptCount += buffersProcessed;
        self->totalInterruptCount += buffersProcessed;

        /* Notify IOAudio framework of completed buffers */
        [self _interruptOccurred];
    }

    /* FUN_000003a4 is a NULL stub (branches to 0x00000000) - not implemented */
    /* Interrupt clearing is handled by DBDMA status register reads */
}

/*
 * Clear interrupts - called by IOAudio framework
 * This is a stub that may need hardware-specific clearing
 */
void _clearInterrupts(void)
{
    /* On AWACS/DBDMA, interrupts are typically cleared by:
     * 1. Reading the DBDMA channel status register
     * 2. Writing to the interrupt status register to acknowledge
     * For now, this is a no-op as DBDMA typically auto-clears on read
     */
}
