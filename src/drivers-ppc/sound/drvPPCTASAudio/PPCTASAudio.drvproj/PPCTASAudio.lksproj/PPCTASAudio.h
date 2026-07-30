#ifndef PPC_TAS_AUDIO_H
#define PPC_TAS_AUDIO_H

#import <driverkit/IOAudio.h>
#import <driverkit/IOPower.h>
#import <driverkit/IODeviceDescription.h>

#include "TASRuntime.h"

@interface PPCTASAudio : IOAudio <IOPower>
{
@private
    TASRuntime runtime;
    TASMachineConfig machineConfig;
    TASAudioDesiredControls desiredControls;
    IODeviceDescription *tasDeviceDescription;
    void *i2sRegisters;
    void *outputDBDMARegisters;
    void *inputDBDMARegisters;
    void *ringAllocations[4];
    PPCDBDMAStorage ringStorage[2];
    PPCDBDMAOps dmaOps[2];
    unsigned long debounceCalloutGeneration;
    unsigned long debounceCalloutDeadline;
    unsigned long debounceCalloutToken;
    unsigned long pollCalloutToken;
    unsigned long workerRetryCalloutToken;
    PMPowerState currentPowerState;
    int closing;
    int ioAudioInitialized;
    int debounceCalloutPending;
    int pollCalloutPending;
    int workerRetryCalloutPending;
    id interruptLock;
    id operationLock;
    id stateLock;
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- (BOOL)reset;
- free;
- (BOOL)startDMAForChannel:(unsigned int)localChannel
                      read:(BOOL)isRead
                    buffer:(IODMABuffer)buffer
   bufferSizeForInterrupts:(unsigned int)bufferSize;
- (void)stopDMAForChannel:(unsigned int)localChannel read:(BOOL)isRead;
- (void)interruptOccurredForInput:(BOOL *)serviceInput
                        forOutput:(BOOL *)serviceOutput;
- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(void **)argument
      forInterrupt:(unsigned int)localInterrupt;
- (unsigned int)channelCount;
- (unsigned int)channelCountLimit;
- (BOOL)acceptsContinuousSamplingRates;
- (void)getSamplingRatesLow:(int *)lowRate high:(int *)highRate;
- (void)getSamplingRates:(int *)rates count:(unsigned int *)numRates;
- (void)getDataEncodings:(NXSoundParameterTag *)encodings
                    count:(unsigned int *)numEncodings;
- (BOOL)isInputActive;
- (BOOL)isOutputActive;
- (void)updateInputGainLeft;
- (void)updateInputGainRight;
- (void)updateOutputMute;
- (void)updateOutputAttenuationLeft;
- (void)updateOutputAttenuationRight;
- (void)setInput:(NXSoundParameterTag)tag enable:(BOOL)enable;
- (void)setOutput:(NXSoundParameterTag)tag enable:(BOOL)enable;
- (void)setAnalogInputSource:(NXSoundParameterTag)tag;
- (IOAudioInterruptClearFunc)interruptClearFunc;
- (IOReturn)getPowerState:(PMPowerState *)state;
- (IOReturn)setPowerState:(PMPowerState)state;
- (IOReturn)getPowerManagement:(PMPowerManagementState *)state;
- (IOReturn)setPowerManagement:(PMPowerManagementState)state;

@end

#endif
