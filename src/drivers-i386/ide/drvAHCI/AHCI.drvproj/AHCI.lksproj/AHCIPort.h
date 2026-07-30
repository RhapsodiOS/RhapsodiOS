#ifndef RHAPSODIOS_AHCI_PORT_H
#define RHAPSODIOS_AHCI_PORT_H

#import <objc/Object.h>
#import "AHCIShared.h"
#import "AHCIPortLogic.h"

@interface AHCIPort : Object
{
    AHCIMMIOContext *mmio;
    unsigned int portNumber;
    void *rawArena;
    unsigned int rawArenaBytes;
    AHCIPortArena arena;
    AHCIDeviceKind deviceKind;
    BOOL hardwareTouched;
}

- initWithMMIO:(AHCIMMIOContext *)context
           port:(unsigned int)number
   capabilities:(AHCIU32)capabilities;
- free;
- (unsigned int)portNumber;
- (AHCIDeviceKind)deviceKind;
- (void)handleInterrupt;

@end

#endif
