#ifndef RHAPSODIOS_AHCI_DISK_H
#define RHAPSODIOS_AHCI_DISK_H

#import <driverkit/IODisk.h>
#import <driverkit/kernelDiskMethods.h>
#import <kern/queue.h>
#import <bsd/dev/ata_hd_registry_core.h>
#import "AHCIDiskLogic.h"

#define AHCI_DISK_REQUEST_COUNT 128

typedef enum {
    AHCI_DISK_READ,
    AHCI_DISK_WRITE,
    AHCI_DISK_FLUSH,
    AHCI_DISK_THREAD_ABORT
} AHCIDiskCommand;

typedef struct {
    AHCIDiskCommand command;
    unsigned int block;
    unsigned int blocks;
    unsigned char *buffer;
    vm_task_t client;
    void *pending;
    ATAHDAsyncToken registryToken;
    id waitLock;
    unsigned int bytesTransferred;
    IOReturn status;
    queue_chain_t link;
    queue_chain_t poolLink;
} AHCIDiskRequest;

@class AHCIPort;

@interface AHCIDisk : IODisk<IODiskReadingAndWriting,
                              IOPhysicalDiskMethods>
{
@private
    AHCIPort *_port;
    AHCIDiskIdentify _identify;
    int _hdUnit;
    queue_head_t _requestQueue;
    queue_head_t _requestPool;
    id _queueLock;
    id _poolLock;
    AHCIDiskRequest _requests[AHCI_DISK_REQUEST_COUNT];
    BOOL _workerStarted;
    BOOL _deviceRegistered;
    BOOL _publicationPinned;
}

+ (AHCIDisk *)publishForPort:(AHCIPort *)port
           deviceDescription:(IODeviceDescription *)description;
- (BOOL)reidentifyFromWords:(const unsigned short *)words;
- (void)portBecameNotReady;
- (void)portBecameReady;

@end

#endif
