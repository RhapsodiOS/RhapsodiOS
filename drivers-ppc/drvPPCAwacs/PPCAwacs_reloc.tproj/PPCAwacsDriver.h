/*
 * Copyright (c) 2025 RhapsodiOS Project
 *
 * AWACS Audio Driver for PowerMac/PowerBook
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

#import <driverkit/IOAudio.h>
#import <driverkit/ppc/IOTreeDevice.h>
#import <driverkit/ppc/IODBDMA.h>

#define DRV_TITLE       "PPCAwacs"

@interface PPCAwacsDriver : IOAudio
{
@private
    void *_awacs_private;  /* Pointer to awacs_state structure */
}

+ (BOOL)probe:deviceDescription;

- initFromDeviceDescription:deviceDescription;
- free;

- (BOOL)reset;

- (IOEISADMABuffer)createDMABufferFor:(unsigned int *)physicalAddress
                               length:(unsigned int)numBytes
                                 read:(BOOL)isRead
                       needsLowMemory:(BOOL)lowerMem
                            limitSize:(BOOL)limitSize;

- (BOOL)startDMAForChannel:(unsigned int)localChannel
                      read:(BOOL)isRead
                    buffer:(IOEISADMABuffer)buffer
   bufferSizeForInterrupts:(unsigned int)bufferSize;

- (void)stopDMAForChannel:(unsigned int)localChannel
                     read:(BOOL)isRead;

- (IOAudioInterruptClearFunc)interruptClearFunc;

- (void)interruptOccurredForInput:(BOOL *)serviceInput
                        forOutput:(BOOL *)serviceOutput;

- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(unsigned int *)arg
      forInterrupt:(unsigned int)localInterrupt;

- (void)timeoutOccurred;

- (void)updateSampleRate;

- (BOOL)acceptsContinuousSamplingRates;

- (void)getSamplingRatesLow:(int *)lowRate
                       high:(int *)highRate;

- (void)getSamplingRates:(int *)rates
                   count:(unsigned int *)numRates;

- (void)getDataEncodings:(NXSoundParameterTag *)encodings
                   count:(unsigned int *)numEncodings;

- (unsigned int)channelCountLimit;

- (void)updateOutputMute;
- (void)updateOutputAttenuationLeft;
- (void)updateOutputAttenuationRight;

- (void)updateInputGainLeft;
- (void)updateInputGainRight;

/* Extended methods for AWACS-specific controls */
- (void)setInputSource:(unsigned int)source;
- (unsigned int)getInputSource;

@end
