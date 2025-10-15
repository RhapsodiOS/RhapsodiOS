/*---------------------------------------------------------------------------*\
*	                                                                      *
*	Copyright (c) 2001 by Jens Heise      	                              *
*	                                                                      *
*	erstellt am: 11.01.2001	              geaendert am: 11.01.2001        *
*									      *
*			Version: 1.0					      *
*	                                                                      *
*-----------------------------------------------------------------------------*
*	                                                                      *
*	This program is free software; you can redistribute it and/or         *
*	modify it under the terms of the GNU General Public License as        *
*	published by the Free Software Foundation; either version 2 of        *
*	the License, or (at your option) any later version.                   *
*	                                                                      *
*	This program is distributed in the hope that it will be useful,       *
*	but WITHOUT ANY WARRANTY; without even the implied warranty of        *
*	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU     *
*	General Public License for more details.                              *
*	                                                                      *
*	You should have received a copy of the GNU General Public License     *
*	along with this program; if not, write to the Free Software           *
*	Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.             *
*	                                                                      *
\*---------------------------------------------------------------------------*/
#import <driverkit/IOAudio.h>
#import <driverkit/i386/ioPorts.h>

#define	DRV_TITLE	"SoundBlaster128PCI"

@interface SoundBlaster128PCIDriver : IOAudio
{
}

+ (BOOL)probe:deviceDescription;

- initFromDeviceDescription:deviceDescription;
- free;

- (BOOL)reset;

- (IOEISADMABuffer)createDMABufferFor:(unsigned int *)physicalAddress length:(unsigned int)numBytes read:(BOOL)isRead needsLowMemory:(BOOL)lowerMem limitSize:(BOOL)limitSize;
- (BOOL)startDMAForChannel:(unsigned int)localChannel read:(BOOL)isRead buffer:(IOEISADMABuffer)buffer bufferSizeForInterrupts:(unsigned int)bufferSize;
- (void)stopDMAForChannel:(unsigned int)localChannel read:(BOOL)isRead;

- (IOAudioInterruptClearFunc)interruptClearFunc;
- (void)interruptOccurredForInput:(BOOL *)serviceInput forOutput:(BOOL *)serviceOutput;
- (BOOL)getHandler:(IOInterruptHandler *)handler level:(unsigned int *)ipl argument:(unsigned int *)arg forInterrupt:(unsigned int)localInterrupt;
- (void)timeoutOccurred;

- (void)updateSampleRate;

- (BOOL)acceptsContinuousSamplingRates;
- (void)getSamplingRatesLow:(int *)lowRate high:(int *)highRate;
- (void)getSamplingRates:(int *)rates count:(unsigned int *)numRates;
- (void)getDataEncodings: (NXSoundParameterTag *)encodings
                                count:(unsigned int *)numEncodings;
- (unsigned int)channelCountLimit;

- (void)updateOutputMute;
- (void)updateOutputAttenuationLeft;
- (void)updateOutputAttenuationRight;

- (void)updateInputGainLeft;
- (void)updateInputGainRight;
@end
