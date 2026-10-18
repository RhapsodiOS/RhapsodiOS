/* Copyright (c) 2026 RhapsodiOS Project. */
#ifndef PPC_SCREAMER_H
#define PPC_SCREAMER_H
#ifdef SCREAMER_ADAPTER_TEST
#import "screamer_adapter_shim.h"
#else
#import <driverkit/IOAudio.h>
#import <driverkit/IOPower.h>
#import <driverkit/IODeviceDescription.h>
#endif
#include "ScreamerRuntime.h"

@interface PPCScreamer : IOAudio <IOPower>
{
@public
    ScreamerRuntime runtime;
    ScreamerMachineConfig machineConfig;
    id operationLock,interruptLock;
    void *registers[3];
    void *ringPages[2],*scratch[2];
    unsigned int mapped,ioAudioPublished,interruptClosing,interruptSuspended;
    unsigned int pendingIRQs;
    unsigned int formatRejected;
    unsigned long timerToken;
    PMPowerState currentPowerState;
}
+ (BOOL)probe:(IODeviceDescription *)description;
- (BOOL)reset;
- (void)screamerServicePeriods:(unsigned int *)periods;
- (IOReturn)getPowerState:(PMPowerState *)state;
- (IOReturn)setPowerState:(PMPowerState)state;
- (IOReturn)getPowerManagement:(PMPowerManagementState *)state;
- (IOReturn)setPowerManagement:(PMPowerManagementState)state;
- free;
- (BOOL)startDMAForChannel:(unsigned int)channel read:(BOOL)read
    buffer:(IODMABuffer)buffer bufferSizeForInterrupts:(unsigned int)period;
- (void)stopDMAForChannel:(unsigned int)channel read:(BOOL)read;
- (void)interruptOccurredForInput:(BOOL *)input forOutput:(BOOL *)output;
- (BOOL)getHandler:(IOInterruptHandler *)handler level:(unsigned int *)level
    argument:(unsigned int *)argument forInterrupt:(unsigned int)interrupt;
- (BOOL)_setParameter:(NXSoundParameterTag)tag toInt:(int)value forObject:(id)object;
- (int)_intValueForParameter:(NXSoundParameterTag)tag forObject:(id)object;
- (void)_getSupportedParameters:(NXSoundParameterTag *)list count:(unsigned int *)count forObject:(id)object;
- (BOOL)_getValues:(NXSoundParameterTag *)list count:(unsigned int *)count
    forParameter:(NXSoundParameterTag)tag forObject:(id)object;
@end
#endif
