#ifndef RHAPSODIOS_AHCI_PORT_H
#define RHAPSODIOS_AHCI_PORT_H

#import <objc/Object.h>
#import <driverkit/return.h>
#import <driverkit/driverTypes.h>
#import <machkit/NXConditionLock.h>
#import "AHCIShared.h"
#import "AHCIPortLogic.h"

@interface AHCIPort : Object
{
    AHCIMMIOContext *mmio;
    unsigned int portNumber;
    AHCIU32 portCapabilities;
    void *rawArena;
    unsigned int rawArenaBytes;
    AHCIPortArena arena;
    AHCIDeviceKind deviceKind;
    BOOL hardwareTouched;
    NXConditionLock *commandLock;
    AHCICommandArbiter commandArbiter;
    AHCICompletionSnapshot completionSnapshot;
    unsigned char receivedFISSnapshot[64];
    unsigned int requestedBytes;
    unsigned long timeoutDeadlineSeconds;
    unsigned int armedGeneration;
    BOOL timeoutArmed;
    BOOL destroying;
    BOOL deferredArenaRelease;
    BOOL quiesceComplete;
    unsigned int activeExecutors;
    IOReturn commandResult;
    id controller;
    BOOL online;
    BOOL controllerResetting;
    BOOL skipCommandRecovery;
}

- initWithMMIO:(AHCIMMIOContext *)context
           port:(unsigned int)number
   capabilities:(AHCIU32)capabilities;
- free;
- (unsigned int)portNumber;
- (AHCIDeviceKind)deviceKind;
- (void)handleInterrupt;
- (void)setController:(id)owner;
- (BOOL)controllerDidReset;
- (void)controllerResetFailed;
- (void)controllerWillReset;
- (IOReturn)executeATA:(unsigned char)command
                   fis:(const unsigned char *)fis
                packet:(const unsigned char *)packet
                buffer:(void *)buffer
                length:(unsigned int)length
                 write:(BOOL)write
               timeout:(unsigned int)seconds
           transferred:(unsigned int *)actual;

@end

#endif
