#ifndef RHAPSODIOS_AHCI_DISK_INTERNAL_H
#define RHAPSODIOS_AHCI_DISK_INTERNAL_H

#import "AHCIDisk.h"

#define AHCI_DISK_NO_WORK 0
#define AHCI_DISK_WORK_AVAILABLE 1
#define AHCI_DISK_COMMAND_TIMEOUT_SECONDS 10U
#define AHCI_DISK_FLUSH_TIMEOUT_SECONDS 30U

@interface AHCIDisk(Internal)
- (BOOL)initResourcesForPort:(AHCIPort *)port;
- (BOOL)identifyDevice;
- (BOOL)publish;
- (AHCIDiskRequest *)allocRequest:(void *)pending;
- (void)freeRequest:(AHCIDiskRequest *)request;
- (IOReturn)enqueueRequest:(AHCIDiskRequest *)request;
- (void)completeRequest:(AHCIDiskRequest *)request;
- (void)dispatchRequest:(AHCIDiskRequest *)request;
- (IOReturn)executeReadWrite:(AHCIDiskRequest *)request;
- (IOReturn)deviceRwCommon:(AHCIDiskCommand)command
                      block:(unsigned int)block
                     length:(unsigned int)length
                     buffer:(unsigned char *)buffer
                     client:(vm_task_t)client
                    pending:(void *)pending
               actualLength:(unsigned int *)actualLength;
volatile void AHCIDiskWorker(AHCIDisk *disk);
@end

#endif
