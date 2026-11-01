/*
 * Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved.
 * Copyright (c) 2025 RhapsodiOS Project. All rights reserved.
 *
 * HISTORY
 * 10-Nov-25   Created for ESS ES1x88 AudioDrive support
 *             Based on SoundBlaster16 driver
 */

#import <driverkit/IOAudio.h>
#import <driverkit/i386/ioPorts.h>

@interface ES1x88AudioDriver : IOAudio
{
@private
    unsigned int currentDMADirection;
    BOOL interruptTimedOut;
    const char *hardwareName;            // Hardware chip name (ES688, ES1688, etc.)
    unsigned char inputSource;           // Input source selection (0=Mic, 1=Line, 2=CD, 3=Mix)
}

+ (BOOL)probe: deviceDescription;
- (BOOL)reset;
- (void) initializeHardware;

- (BOOL) startDMAForChannel: (unsigned int) localChannel
        read: (BOOL) isRead
        buffer: (IOEISADMABuffer) buffer
        bufferSizeForInterrupts: (unsigned int) division;

- (void) stopDMAForChannel: (unsigned int) localChannel read: (BOOL) isRead;

- (void) interruptOccurredForInput: (BOOL *) serviceInput
                         forOutput: (BOOL *) serviceOutput;

- (void)configureHardwareForDataTransfer:(unsigned int)transferCount;

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

- (void)setAnalogInputSource:(NXSoundParameterTag)val;

- (void) updateInputGainLeft;
- (void) updateInputGainRight;
- (void) updateOutputMute;
- (void) updateOutputAttenuationLeft;
- (void) updateOutputAttenuationRight;

@end
