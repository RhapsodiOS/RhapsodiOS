#ifndef RHAPSODIOS_AHCI_PORT_H
#define RHAPSODIOS_AHCI_PORT_H

#import <objc/Object.h>
#import <driverkit/return.h>
#import <driverkit/driverTypes.h>
#import <machkit/NXConditionLock.h>
#import "AHCIShared.h"
#import "AHCIPortLogic.h"

@class AHCIPort;
typedef BOOL (*AHCIRecoveryValidator)(void *context, AHCIPort *port,
                                      AHCIDeviceKind kind);

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
    unsigned char receivedFISSnapshot[AHCI_PORT_RECEIVED_FIS_BYTES];
    unsigned int requestedBytes;
    unsigned long timeoutDeadlineSeconds;
    AHCITimeoutChain timeoutChain;
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
    AHCIRecoveryValidator recoveryValidator;
    void *recoveryValidatorContext;
    BOOL recoveryValidationInProgress;
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
- (BOOL)setRecoveryValidator:(AHCIRecoveryValidator)validator
                      context:(void *)context;
- (IOReturn)executeATA:(unsigned char)command
                   fis:(const unsigned char *)fis
                packet:(const unsigned char *)packet
                buffer:(void *)buffer
                length:(unsigned int)length
                 write:(BOOL)write
               timeout:(unsigned int)seconds
           transferred:(unsigned int *)actual;
- (IOReturn)executeRecoveryATA:(unsigned char)command
                           fis:(const unsigned char *)fis
                        packet:(const unsigned char *)packet
                        buffer:(void *)buffer
                        length:(unsigned int)length
                         write:(BOOL)write
                       timeout:(unsigned int)seconds
                   transferred:(unsigned int *)actual;

@end

#endif
