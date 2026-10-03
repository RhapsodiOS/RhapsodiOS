/* Reconstructed IOSCSIController adapter for the Adaptec controller. */
#import <stdio.h>
#import <objc/Protocol.h>
#import <driverkit/generalFuncs.h>
#import <kernserv/prototypes.h>
#import "Adaptec2940.h"
#import "SCSIBus.h"

static Protocol *protocols[] = {
	@protocol(IOSCSIControllerExported),
	nil
};

@implementation SCSIBus

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
	id direct = [deviceDescription directDevice];
	id bus;
	unsigned int channel = 0;
	BOOL found = NO;

	while (1) {
		bus = [self alloc];
		if (![direct acquireSCSIBus:channel owner:bus])
			break;
		found = YES;
		[bus initSCSIBus:deviceDescription channel:channel++];
		if (channel != 0)
			return found;
	}
	[bus free];
	return found;
}

+ (int)deviceStyle
{
	return IO_IndirectDevice;
}

+ (Protocol **)requiredProtocols
{
	return protocols;
}

- (unsigned int)maxTransfer
{
	return [_direct maxTransfer];
}

- (id)free
{
	return [super free];
}

- (void)resetStats
{
	if (_scsiChannel == 0)
		[_direct resetStats];
}

- (unsigned int)numQueueSamples
{
	return [_direct numQueueSamples];
}

- (unsigned int)sumQueueLengths
{
	return [_direct sumQueueLengths];
}

- (unsigned int)maxQueueLength
{
	return [_direct maxQueueLength];
}

- (int)numberOfTargets
{
	return [_direct numberOfTargets:_scsiChannel];
}

- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiReq
		       buffer:(void *)buffer
		       client:(vm_task_t)client
{
	int request[9];

	request[0] = _scsiChannel;
	request[1] = 0;
	request[2] = (int)scsiReq;
	request[3] = (int)buffer;
	request[4] = (int)client;
	[_direct executeCmdBuf:(Adaptec2940RequestMessage *)request];
	return request[5];
}

- (sc_status_t)resetSCSIBus
{
	int request[9];

	request[0] = _scsiChannel;
	request[1] = 1;
	[_direct executeCmdBuf:(Adaptec2940RequestMessage *)request];
	return request[5];
}

- initSCSIBus:(IODeviceDescription *)deviceDescription channel:(unsigned int)channel
{
	unsigned int target;
	unsigned int busID;
	char location[32];
	const char *directName;

	_direct = [deviceDescription directDevice];
	_scsiChannel = channel;
	if ([super initFromDeviceDescription:deviceDescription] != nil) {
		busID = [_direct scsiBusId:_scsiChannel];
		directName = [_direct name];
		sprintf(location, "%s SCSI Bus %d Target %d", directName,
		        _scsiChannel, busID);
		[self setLocation:location];
		for (target = 0; target <= 7; ++target) {
			if ([self reserveTarget:(unsigned char)busID
			                     lun:(unsigned char)target
			                  forOwner:self] != 0) {
				IOLog("%s: reserveTarget t=%d l=%d failed\n",
				      [self name], busID, target);
				return nil;
			}
		}
		[self registerDevice];
		return self;
	}

	IOLog("SCSIBus2940: [super initFromDeviceDescription] Failed for channel %d\n",
	      _scsiChannel);
	return nil;
}

@end
