/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * EATASCSIBus.h - per-channel SCSI bus sitting on an EATAController.
 *
 * HISTORY
 *
 * Reconstructed from DPTSCSIDriver_reloc (instance_size 0x24c,
 * superclass IOSCSIController).
 */


#import <driverkit/IOSCSIController.h>
#import <driverkit/IOPower.h>
#import <driverkit/return.h>
#import <driverkit/scsiTypes.h>
#import <mach/mach_types.h>


@interface EATASCSIBus : IOSCSIController <IOPower>
{
	id		_direct;		/* +0x244, the EATAController */
	unsigned	_scsiChannel;		/* +0x248 */
}

+ (BOOL)probe:deviceDescription;
+ (IODeviceStyle)deviceStyle;
+ (Protocol **)requiredProtocols;

- (unsigned)maxTransfer;
- (int)numberOfTargets;
- free;
- (void)resetStats;
- (unsigned)numQueueSamples;
- (unsigned)sumQueueLengths;
- (unsigned)maxQueueLength;
- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiReq
		       buffer:(void *)buffer
		       client:(vm_task_t)client;
- (sc_status_t)resetSCSIBus;

- (IOReturn)getPowerState:(PMPowerState *)state;
- (IOReturn)setPowerState:(PMPowerState)state;
- (IOReturn)getPowerManagement:(PMPowerManagementState *)state;
- (IOReturn)setPowerManagement:(PMPowerManagementState)state;

@end

#import "EATASCSIBusPrivate.h"
