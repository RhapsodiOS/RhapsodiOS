/* Copyright (c) 1999 Apple Computer, Inc. */

#ifndef _ADAPTEC2940_SCSIBUS_H
#define _ADAPTEC2940_SCSIBUS_H

#import <objc/Protocol.h>
#import <driverkit/IOMemoryDescriptor.h>
#import <driverkit/IOSCSIController.h>
#import <driverkit/return.h>
#import <driverkit/scsiTypes.h>

@class Adaptec2940;

/* IDA class layout: IOSCSIController prefix 580 bytes, then these two ivars. */
@interface SCSIBus : IOSCSIController
{
	id _direct;                 /* 580 */
	unsigned int _scsiChannel;  /* 584 */
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
+ (int)deviceStyle;
+ (Protocol **)requiredProtocols;
- (unsigned int)maxTransfer;
- (id)free;
- (void)resetStats;
- (unsigned int)numQueueSamples;
- (unsigned int)sumQueueLengths;
- (unsigned int)maxQueueLength;
- (int)numberOfTargets;
- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiReq
                       buffer:(void *)buffer
                       client:(vm_task_t)client;
- (sc_status_t)resetSCSIBus;
- initSCSIBus:(IODeviceDescription *)deviceDescription channel:(unsigned int)channel;

@end

#endif /* _ADAPTEC2940_SCSIBUS_H */
