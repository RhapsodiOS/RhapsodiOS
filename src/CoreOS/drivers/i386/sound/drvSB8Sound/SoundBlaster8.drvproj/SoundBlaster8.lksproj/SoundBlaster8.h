/*
 * Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved. 
 *
 * HISTORY
 * 4-Mar-94    Rakesh Dubey at NeXT
 *      Created. 
 */

#import <driverkit/IOAudio.h>
#import <driverkit/i386/ioPorts.h>

@interface SoundBlaster8 : IOAudio
{
@private
    unsigned int currentDMADirection;
    BOOL interruptTimedOut;
    unsigned int dmaDescriptorSize;  	// DMA descriptor size for interrupts
    BOOL isValidRequest;		// Can we do I/O of type requested?
}

+ (BOOL)probe: deviceDescription;
- (BOOL)reset;
- (void) initializeHardware;

- (BOOL) isValidRequest: (BOOL)isRead;

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
