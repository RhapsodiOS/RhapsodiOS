/*
 * Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved.
 * Copyright (c) 2025 RhapsodiOS Project. All rights reserved.
 *
 * HISTORY
 * 6-Oct-25    Created for Sound Blaster 16, AWE32, AWE64 support
 *             Based on SoundBlaster8 driver by Rakesh Dubey
 */

#import <driverkit/IOAudio.h>
#import <driverkit/i386/ioPorts.h>

@interface SoundBlaster16 : IOAudio
{
@private
    unsigned int currentDMADirection;
    BOOL interruptTimedOut;
    BOOL is16BitTransfer;                // Are we doing 16-bit audio?
    unsigned int dma8Channel;            // 8-bit DMA channel
    unsigned int dma16Channel;           // 16-bit DMA channel
    unsigned int numDMAChannels;         // Number of DMA channels (1 or 2)
}

+ (BOOL)probe: deviceDescription;
- (BOOL)reset;
- (void) initializeHardware;
- (BOOL) initializeDMAChannels;
- (void) initializeLastStageGainRegisters;

- (BOOL) startDMAForChannel: (unsigned int) localChannel
        read: (BOOL) isRead
        buffer: (IOEISADMABuffer) buffer
        bufferSizeForInterrupts: (unsigned int) division;

- (void) stopDMAForChannel: (unsigned int) localChannel read: (BOOL) isRead;

- (void) interruptOccurredForInput: (BOOL *) serviceInput
                         forOutput: (BOOL *) serviceOutput;

- (void)updateSampleRate;

- (void) setBufferCount:(int)count;

- (IOReturn)enableAllInterrupts;
- (void)disableAllInterrupts;

- (BOOL)acceptsContinuousSamplingRates;

- (void)getSamplingRatesLow:(int *)lowRate
                                         high:(int *)highRate;

- (void)getSamplingRates:(int *)rates
                                count:(unsigned int *)numRates;

- (void)getDataEncodings: (NXSoundParameterTag *)encodings
                                count:(unsigned int *)numEncodings;

- (unsigned int)channelCountLimit;

- (void) updateInputGainLeft;
- (void) updateInputGainRight;
- (void) updateOutputMute;
- (void) updateOutputAttenuationLeft;
- (void) updateOutputAttenuationRight;

@end
