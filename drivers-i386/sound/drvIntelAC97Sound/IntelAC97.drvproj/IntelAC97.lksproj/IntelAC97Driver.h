/*
 * IntelAC97Driver.h
 *
 * Intel AC'97 Audio Driver for RhapsodiOS
 * Supports Intel ICH, ICH2, ICH3, ICH4, ICH5 and compatible chipsets
 *
 * Copyright (c) 2025
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

#import <driverkit/IOAudio.h>
#import <driverkit/i386/ioPorts.h>

#define DRV_TITLE       "IntelAC97"

@interface IntelAC97Driver : IOAudio
{
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

- (void)stopDMAForChannel:(unsigned int)localChannel read:(BOOL)isRead;

- (IOAudioInterruptClearFunc)interruptClearFunc;
- (void)interruptOccurredForInput:(BOOL *)serviceInput
                        forOutput:(BOOL *)serviceOutput;

- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(unsigned int *)arg
      forInterrupt:(unsigned int)localInterrupt;

- (void)timeoutOccurred;

/* Sample rate control */
- (void)updateSampleRate;
- (BOOL)acceptsContinuousSamplingRates;
- (void)getSamplingRatesLow:(int *)lowRate high:(int *)highRate;
- (void)getSamplingRates:(int *)rates count:(unsigned int *)numRates;

/* Data encoding */
- (void)getDataEncodings:(NXSoundParameterTag *)encodings
                   count:(unsigned int *)numEncodings;
- (unsigned int)channelCountLimit;

/* Volume/mixer control */
- (void)updateOutputMute;
- (void)updateOutputAttenuationLeft;
- (void)updateOutputAttenuationRight;
- (void)updateInputGainLeft;
- (void)updateInputGainRight;

@end
