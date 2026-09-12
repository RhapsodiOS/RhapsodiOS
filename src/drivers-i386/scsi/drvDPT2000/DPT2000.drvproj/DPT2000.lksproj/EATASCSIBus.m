/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * EATASCSIBus.m - per-channel SCSI bus sitting on an EATAController.
 *
 * HISTORY
 *
 * Reconstructed from DPTSCSIDriver_reloc (SCSIBus.m).
 */

#import <sys/types.h>
#import <stdio.h>
#import <string.h>
#import <objc/Protocol.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/return.h>
#import <driverkit/scsiTypes.h>
#import <bsd/dev/scsireg.h>
#import <kernserv/prototypes.h>

#import "EATASCSIBus.h"
#import "EATAController.h"
#import "EATAControllerPrivate.h"

static Protocol *protocols[] = {
	@protocol(EATAExported),
	nil
};


@implementation EATASCSIBus

+ (BOOL)probe:deviceDescription
{
	id		direct;
	id		bus;
	unsigned	channel;
	BOOL		found;

	direct = [deviceDescription directDevice];
	found = NO;
	for (channel = 0; channel < EATA_CHANNEL_COUNT; channel++) {
		bus = [self alloc];
		if ([direct acquireSCSIBus:channel owner:bus]) {
			found = YES;
			[bus initSCSIBus:deviceDescription channel:channel];
		} else
			[bus free];
	}
	return found;
}

+ (IODeviceStyle)deviceStyle
{
	return IO_IndirectDevice;
}

+ (Protocol **)requiredProtocols
{
	return protocols;
}

- (unsigned)maxTransfer
{
	return [_direct maxTransfer];
}

- (int)numberOfTargets
{
	return [_direct numberOfTargets];
}

- free
{
	return [super free];
}

- (void)resetStats
{
	if (_scsiChannel == 0)
		[_direct resetStats];
}

- (unsigned)numQueueSamples
{
	return [_direct numQueueSamples];
}

- (unsigned)sumQueueLengths
{
	return [_direct sumQueueLengths];
}

- (unsigned)maxQueueLength
{
	return [_direct maxQueueLength];
}

- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiReq
		       buffer:(void *)buffer
		       client:(vm_task_t)client
{
	EATACommandBuf	cmdBuf;
	sc_status_t	status;

	if (scsiReq->cdb.cdb_opcode == C6OP_STARTSTOP &&
	    (scsiReq->cdb.cdb_c6.c6_len & 0x02)) {
		status = [self flushCacheForTarget:scsiReq->target
					       lun:scsiReq->lun];
		if (status)
			IOLog("%s: Cache Flush failed (%d)\n",
			    [self name], status);
	}

	cmdBuf.scsiChannel = _scsiChannel;
	cmdBuf.op = EO_Execute;
	cmdBuf.scsiReq = scsiReq;
	cmdBuf.buffer = buffer;
	cmdBuf.client = client;
	[_direct executeCmdBuf:&cmdBuf];
	return cmdBuf.result;
}

- (sc_status_t)resetSCSIBus
{
	EATACommandBuf	cmdBuf;

	cmdBuf.scsiChannel = _scsiChannel;
	cmdBuf.op = EO_Reset;
	[_direct executeCmdBuf:&cmdBuf];
	return cmdBuf.result;
}

- (IOReturn)getPowerState:(PMPowerState *)state
{
	(void)state;
	return IO_R_UNSUPPORTED;
}

- (IOReturn)setPowerState:(PMPowerState)state
{
	if (state == PM_OFF) {
		[self flushAllCache];
		return IO_R_SUCCESS;
	}
	return IO_R_UNSUPPORTED;
}

- (IOReturn)getPowerManagement:(PMPowerManagementState *)state
{
	(void)state;
	return IO_R_UNSUPPORTED;
}

- (IOReturn)setPowerManagement:(PMPowerManagementState)state
{
	(void)state;
	return IO_R_UNSUPPORTED;
}

@end


@implementation EATASCSIBus(PrivateMethods)

- initSCSIBus:deviceDescription channel:(unsigned)channel
{
	unsigned	hostId;
	unsigned	lun;
	char		locBuf[32];

	_direct = [deviceDescription directDevice];
	_scsiChannel = channel;

	if ([self initFromDeviceDescription:deviceDescription] == nil) {
		IOLog("EATA SCSIBus: [super initFromDeviceDescription] "
		    "Failed for channel %d\n", _scsiChannel);
		return nil;
	}

	hostId = [_direct scsiBusId:_scsiChannel];
	sprintf(locBuf, "%s SCSI Bus %d Target %d",
	    [_direct name], _scsiChannel, hostId);
	[self setLocation:locBuf];

	for (lun = 0; lun < 8; lun++) {
		if ([self reserveTarget:(unsigned char)(hostId & 0xff)
				   lun:(unsigned char)lun
			      forOwner:self]) {
			IOLog("%s: reserveTarget t=%d l=%d failed\n",
			    [self name], hostId, lun);
			return nil;
		}
	}

	[self registerDevice];
	return self;
}

- (sc_status_t)flushCacheForTarget:(unsigned char)target
			       lun:(unsigned char)lun
{
	EATACommandBuf	cmdBuf;
	IOSCSIRequest	scsiReq;

	bzero(&cmdBuf, sizeof(cmdBuf));
	bzero(&scsiReq, sizeof(scsiReq));

	scsiReq.cdb.cdb_c6.c6_opcode = 0x1E;
	scsiReq.cdb.cdb_c6.c6_lun = lun;
	scsiReq.target = target;
	scsiReq.lun = lun;
	scsiReq.maxTransfer = 0;
	scsiReq.timeoutLength = 0x1E;

	cmdBuf.op = EO_Execute;
	cmdBuf.scsiReq = &scsiReq;
	cmdBuf.scsiChannel = _scsiChannel;
	[_direct executeCmdBuf:&cmdBuf];
	return cmdBuf.result;
}

- (void)flushAllCache
{
	unsigned	hostId;
	unsigned	target;
	unsigned	lun;

	hostId = [_direct scsiBusId:_scsiChannel];
	for (target = 0; target < 8; target++) {
		if (target == hostId)
			continue;
		for (lun = 0; lun < 8; lun++) {
			if ([self reserveTarget:(unsigned char)target
					   lun:(unsigned char)lun
				      forOwner:self])
				[self flushCacheForTarget:(unsigned char)target
						      lun:(unsigned char)lun];
			else
				[self releaseTarget:(unsigned char)target
						lun:(unsigned char)lun
					   forOwner:self];
		}
	}
}

@end
