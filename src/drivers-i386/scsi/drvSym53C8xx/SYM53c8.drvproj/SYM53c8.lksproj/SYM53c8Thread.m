/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * SYM53c8Thread.m - I/O thread methods for the Symbios 53C8xx driver.
 *
 * HISTORY
 *
 * Reconstructed from SYM53c8_reloc (divergences.md).
 */

#import <kernserv/prototypes.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/scsiTypes.h>
#import <bsd/dev/scsireg.h>
#import <machkit/NXLock.h>
#import <kernserv/ns_timer.h>

#import "SYM53c8Controller.h"
#import "SYM53c8Types.h"
#import "SYM53c8Thread.h"
#import "SYM53c8SIM.h"

ns_time_t		StartTime;

@implementation SYM53c8(IOThread)

- (int)threadExecuteRequest:(struct _scsireq *)req
{
	int	rc;

	IOGetTimestamp(&StartTime);
	rc = xpt_action(req->XPTReq);
	if (rc) {
		IOLog("XPTAction: Error returned from XPTAction %ld\n",
		    (long)rc);
		xpt_ccb_free(req->XPTReq);
		req->NeXTReq->driverStatus = SR_IOST_INVALID;
		[req->reqLock lock];
		[req->reqLock unlockWith:REQ_IDLE];
		[self freeReq:req];
		return 0;
	}
	if (outstandingCount > maxQueueLen)
		maxQueueLen = outstandingCount;
	queueLenTotal += outstandingCount;
	totalCommands++;
	outstandingCount++;
	return 0;
}

- (void)threadResetSCSIBus
{
	struct sim_ccb	*ccb;
	int		rc;

	IOLog("%s: Resetting SCSI bus...", [self name]);
	ccb = xpt_ccb_alloc();
	if (ccb == 0)
		return;
	ccb->func_code = SIM_FUNC_RESET_BUS;
	ccb->path = path;
	ccb->flags0 |= 0x08;
	ccb->flags1 |= CAM_CCB_FLAGS2_OR;
	rc = xpt_action(ccb);
	if (rc == 0)
		IOLog("OK\n");
	else
		IOLog("Failed\n");
	xpt_ccb_free(ccb);
}

@end
