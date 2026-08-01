#ifndef RHAPSODIOS_AHCI_ATAPI_H
#define RHAPSODIOS_AHCI_ATAPI_H

#import <driverkit/IOSCSIController.h>
#import <driverkit/IODeviceDescription.h>
#import <machkit/NXLock.h>
#import "AHCIATAPILogic.h"

@class AHCIPort;

#define AHCI_ATAPI_IDENTIFY_PACKET_DEVICE 0xa1
#define AHCI_ATAPI_IDENTIFY_TIMEOUT_SECONDS 10U
#define AHCI_ATAPI_PACKET_TIMEOUT_SECONDS 30U

@interface AHCIATAPIController : IOSCSIController
{
@private
    AHCIPort *_port;
    NXLock *_stateLock;
    unsigned int _packetLength;
    AHCIATAPIIdentity _identity;
    unsigned int _activeRequests;
    BOOL _online;
    BOOL _destroying;
    BOOL _deviceRegistered;
}

+ (AHCIATAPIController *)publishForPort:(AHCIPort *)port
                      identifyWords:(const unsigned short *)words
                 deviceDescription:(IODeviceDescription *)description;
- (BOOL)reidentifyFromWords:(const unsigned short *)words;
- (void)portBecameNotReady;
- (void)portBecameReady;

@end

#endif
