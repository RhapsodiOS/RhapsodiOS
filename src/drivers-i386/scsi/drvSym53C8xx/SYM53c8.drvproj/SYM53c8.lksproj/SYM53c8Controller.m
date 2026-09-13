/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * SYM53c8Controller.m - DriverKit shell for the Symbios 53C8xx CAM/SIM.
 *
 * HISTORY
 *
 * Reconstructed from SYM53c8_reloc (divergences.md).
 */

#import <sys/types.h>
#import <string.h>
#import <objc/Object.h>
#import <kernserv/queue.h>
#import <kernserv/prototypes.h>
#import <kernserv/ns_timer.h>
#import <driverkit/return.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/scsiTypes.h>
#import <bsd/dev/scsireg.h>
#import <mach/message.h>
#import <mach/port.h>
#import <mach/mach_interface.h>
#import <machkit/NXLock.h>
#import <driverkit/i386/directDevice.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/IOSCSIController.h>

#import "SYM53c8Controller.h"
#import "SYM53c8Types.h"
#import "SYM53c8Thread.h"
#import "SYM53c8SIM.h"

extern unsigned int	page_size;
extern void		*bios_rom_vap;

ns_time_t		StartTime;

int			cmdQueueEnable;
unsigned char		inst_tbl[4];
unsigned char		shared[4];

static msg_header_t SYMMessageTemplate = {
	0,
	1,
	sizeof(msg_header_t),
	MSG_TYPE_NORMAL,
	PORT_NULL,
	PORT_NULL,
	IO_COMMAND_MSG
};

static int
symYesValue(const char *value)
{
	if (value == 0)
		return 0;
	return (strcmp(value, "YES") == 0);
}

static unsigned char
symCdbLen(unsigned char opcode)
{
	switch ((opcode >> 5) & 7) {
	case 0:
	case 6:
		return 6;
	case 1:
	case 2:
	case 7:
		return 10;
	case 5:
		return 12;
	default:
		return 0;
	}
}

static unsigned char
symHostId(unsigned char path)
{
	struct sim_hba *hba;

	hba = &HBAs[path];
	if (hba->base == 0)
		return 0;
	return ((unsigned char *)hba->base)[3];
}

@implementation SYM53c8

+ (BOOL)probe:deviceDescription
{
	SYM53c8		*sym;
	const char	*instStr;
	unsigned char	ch;
	int		inst;
	id		table;

	sym = [self alloc];
	table = [deviceDescription configTable];
	instStr = [table valueForStringKey:"Instance"];
	ch = instStr ? (unsigned char)instStr[0] : 0;
	switch (ch) {
	case '0':
		inst = 0;
		break;
	case '1':
		inst = 1;
		break;
	case '2':
		inst = 2;
		break;
	case '3':
		inst = 3;
		break;
	default:
		IOLog("SYM53c8: Unknown instance %s\n", instStr);
		IOLog("SYM53c8: Defaulting to instance 0\n");
		inst = 0;
		break;
	}
	IOLog("sc%d: Probing for device Symbios Logic SCSI Adapter instance %d.\n",
	    inst, inst);
	if (inst_tbl[inst] == 1) {
		IOLog("Already probed, return YES.\n");
		return YES;
	}
	[sym setPath:(unsigned char)inst];
	[table freeString:instStr];
	if ([deviceDescription getPCIdevice:0 function:0 bus:0]) {
		IOLog("SYM53c8: Can't find this PCI device; ABORTING\n");
		return NO;
	}
	if ([sym initFromDeviceDescription:deviceDescription] == nil)
		return NO;
	inst_tbl[inst] = 1;
	return YES;
}

- initFromDeviceDescription:deviceDescription
{
	id			table;
	const char		*value;
	IOPCIConfigSpace	cfg;
	IORange			ioRange;
	IOReturn		irtn;
	vm_address_t		biosVirt;
	unsigned char		lun;
	unsigned char		hostId;
	int			i;
	id			lock;

	queue_init(&commandQ);
	commandLock = [[NXLock alloc] init];
	reqPoolLock = [[NXConditionLock new] initWith:POOL_HAS_REQS];
	availReqs = 0;
	for (i = 0; i < SYM_REQS_COUNT; i++) {
		lock = [[NXConditionLock alloc] initWith:REQ_IDLE];
		reqs[i].reqLock = lock;
		[self freeReq:&reqs[i]];
	}
	levelIRQ = 0;

	table = [deviceDescription configTable];
	value = [table valueForStringKey:"Share IRQ Levels"];
	if (symYesValue(value)) {
		levelIRQ = 1;
		shared[path] = 1;
	}
	if (value)
		[table freeString:value];

	if (path == 0) {
		value = [table valueForStringKey:"Cmd Queueing"];
		cmdQueueEnable = symYesValue(value);
		if (value)
			[table freeString:value];

		value = [table valueForStringKey:"Synchronous"];
		SyncSCSIEnable = symYesValue(value);
		if (value)
			[table freeString:value];

		value = [table valueForStringKey:"Wide SCSI"];
		WideSCSIEnable = symYesValue(value);
		if (value)
			[table freeString:value];
	}

	bzero(&cfg, sizeof(cfg));
	irtn = [IODirectDevice getPCIConfigSpace:&cfg
		withDeviceDescription:deviceDescription];
	if (irtn) {
		IOLog("SYM53c8: Can't get configSpace; ABORTING\n");
		return [self free];
	}

	interrupt = cfg.InterruptLine;
	if ((cfg.BaseAddress[0] & SYM_PCI_IO_SPACE) == 0) {
		IOLog("SYM53c8: No I/O Port Base Found\n");
		return [self free];
	}
	ioRange.start = cfg.BaseAddress[0] & SYM_PCI_IO_MASK;
	ioRange.size = SYM_PCI_IO_RANGE;
	irtn = [deviceDescription setPortRangeList:&ioRange num:1];
	if (irtn) {
		IOLog("%s: Can't set portRangeList to port 0x%x (%s)\n",
		    [self name], ioRange.start,
		    [IODirectDevice stringFromReturn:irtn]);
		return [self free];
	}
	[deviceDescription setInterruptList:(int *)&interrupt num:1];

	if ([super initFromDeviceDescription:deviceDescription] == nil) {
		IOLog("%s: super initFromDeviceDescription failed.",
		    [self name]);
		return [self free];
	}

	intPortKern = IOConvertPort([self interruptPort],
	    IO_KernelIOTask, IO_Kernel);
	ioThreadRunning = 1;

	if (path == 0) {
		irtn = IOMapPhysicalIntoIOTask(SYM_BIOS_WINDOW_PHYS,
		    SYM_BIOS_WINDOW_SIZE, &biosVirt);
		if (irtn) {
			IOLog("%s: IOMapPhysicalIntoIOTask failed IO_RETURN = %d\n",
			    [self name], irtn);
			return [self free];
		}
		bios_rom_vap = (void *)biosVirt;
		xpt_init();
		IOUnmapPhysicalFromIOTask(biosVirt, SYM_BIOS_WINDOW_SIZE);
		bios_rom_vap = 0;
		IOScheduleFunc(ticktock, self, 1);
	} else {
		[self threadResetSCSIBus];
	}

	if ([self enableInterrupt:0]) {
		IOLog("%s: Unable to enable interrupt\n", [self name]);
		return [self free];
	}

	irtn = port_set_backlog(task_self(), [self interruptPort], 0x10);
	if (irtn) {
		IOLog("%s: error %d on port_set_backlog()\n",
		    [self name], irtn);
	}

	hostId = symHostId(path);
	for (lun = 0; lun <= 7; lun++) {
		if ([self reserveTarget:hostId lun:lun forOwner:self]) {
			IOLog("%s: reserveTarget t=%d l=%d failed\n",
			    [self name], hostId, lun);
			return [self free];
		}
	}

	[self resetStats];
	outstandingCount = 0;
	[self manualTURScan];
	[self registerDevice];
	return self;
}

- (void)setPath:(unsigned char)thePath
{
	path = thePath;
}

- free
{
	SYMCommandBuf	cmdBuf;
	int		i;

	if (ioThreadRunning) {
		cmdBuf.op = SO_Abort;
		cmdBuf.req = 0;
		cmdBuf.lock = 0;
		[self executeCmdBuf:&cmdBuf];
	}
	if (commandLock)
		[commandLock free];
	for (i = 0; i < SYM_REQS_COUNT; i++) {
		if (reqs[i].reqLock)
			[reqs[i].reqLock free];
	}
	return [super free];
}

- (unsigned)maxTransfer
{
	return page_size * 15;
}

- (unsigned)numberOfTargets
{
	return 8;
}

- (void)resetStats
{
	queueLenTotal = 0;
	maxQueueLen = 0;
	totalCommands = 0;
}

- (unsigned)numQueueSamples
{
	return totalCommands;
}

- (unsigned)sumQueueLengths
{
	return queueLenTotal;
}

- (unsigned)maxQueueLength
{
	return maxQueueLen;
}

- (struct _scsireq *)allocReq
{
	struct _scsireq	*req;
	int		cond;

	[reqPoolLock lockWhen:POOL_HAS_REQS];
	req = freereq;
	if (req == 0) {
		[reqPoolLock unlockWith:POOL_EMPTY];
		IOPanic("SYM53C8xx: No Free Requests");
		return 0;
	}
	[req->reqLock lock];
	[req->reqLock unlockWith:CMD_PENDING];
	freereq = req->next;
	req->next = 0;
	availReqs--;
	cond = (availReqs == 0) ? POOL_EMPTY : POOL_HAS_REQS;
	[reqPoolLock unlockWith:cond];
	return req;
}

- (void)freeReq:(struct _scsireq *)req
{
	[reqPoolLock lock];
	req->next = freereq;
	freereq = req;
	availReqs++;
	[reqPoolLock unlockWith:POOL_HAS_REQS];
}

- convertReq:(IOSCSIRequest *)scsiReq
	ToXpt:(struct _scsireq *)req
	buffer:(void *)buffer
	client:(vm_task_t)client
{
	struct sim_ccb	*ccb;
	unsigned char	*src;
	unsigned char	len;
	unsigned int	i;
	unsigned char	*cdb;

	req->XPTReq = 0;
	ccb = xpt_ccb_alloc();
	req->XPTReq = ccb;
	if (ccb == 0)
		return self;

	req->self = self;
	ccb->osd_rsvd = CAM_CCB_SENTINEL;
	req->client = (unsigned int)client;
	req->NeXTReq = scsiReq;
	ccb->path = path;
	ccb->target = scsiReq->target;
	ccb->lun = scsiReq->lun;
	ccb->flags0 = scsiReq->read ? CAM_CCB_FLAGS_OUT : CAM_CCB_FLAGS_IN;
	ccb->flags0 |= CAM_CCB_FLAGS_OR;
	if (scsiReq->disconnect == 0)
		ccb->flags1 |= CAM_CCB_FLAGS2_80;
	ccb->flags1 |= CAM_CCB_FLAGS2_OR;
	if (Sync_dev[path * 7 + scsiReq->target]) {
		ccb->flags1 &= ~CAM_CCB_FLAGS2_20;
		ccb->flags1 |= CAM_CCB_FLAGS2_40;
	} else {
		ccb->flags1 |= CAM_CCB_FLAGS2_20;
		ccb->flags1 &= ~CAM_CCB_FLAGS2_40;
	}
	ccb->tag_action = CAM_CCB_BYTE54;
	*(struct _scsireq **)(void *)&ccb->rsvd18[0] = req;
	ccb->complete = requestCompleted;
	ccb->data = buffer;
	ccb->dxfer_len = scsiReq->maxTransfer;
	ccb->sense_ptr = (unsigned char *)&scsiReq->senseData;
	ccb->sense_len = 0x1A;
	len = symCdbLen(((unsigned char *)&scsiReq->cdb)[0]);
	ccb->cdb_len = len;
	src = (unsigned char *)&scsiReq->cdb;
	cdb = ccb->cdb;
	for (i = 0; i < len; i++)
		cdb[i] = src[i];
	ccb->timeout = scsiReq->timeoutLength;
	if (ccb->cdb[0] == 3)
		ccb->flags1 |= CAM_CCB_FLAGS2_10;
	else if (cmdQueueEnable)
		ccb->flags0 |= CAM_CCB_FLAGS_TAGGED;
	return self;
}

- (void)updateStatus:(struct _scsireq *)req
{
	IOSCSIRequest	*scsiReq;
	struct sim_ccb	*ccb;
	unsigned	st;

	scsiReq = req->NeXTReq;
	ccb = req->XPTReq;
	st = ccb->status & 0x3F;
	switch (st) {
	case 1:
		scsiReq->scsiStatus = 0;
		scsiReq->driverStatus = SR_IOST_GOOD;
		break;
	case 8:
	case 0x0A:
		scsiReq->scsiStatus = 0;
		scsiReq->driverStatus = SR_IOST_SELTO;
		break;
	case 0x0B:
		scsiReq->scsiStatus = 0;
		scsiReq->driverStatus = SR_IOST_IOTO;
		break;
	case 4:
		scsiReq->scsiStatus = ccb->scsi_status;
		scsiReq->driverStatus = SR_IOST_CHKSNV;
		break;
	case 0x10:
		scsiReq->scsiStatus = 2;
		scsiReq->driverStatus = SR_IOST_CHKSNV;
		break;
	case 0x0E:
		scsiReq->scsiStatus = 0;
		scsiReq->driverStatus = SR_IOST_RESET;
		break;
	case 5:
	case 0x3F:
		scsiReq->scsiStatus = 8;
		scsiReq->driverStatus = SR_IOST_CMDREJ;
		break;
	case 6:
	case 7:
	case 0x15:
	case 0x38:
	case 0x39:
		scsiReq->scsiStatus = 0;
		scsiReq->driverStatus = SR_IOST_CMDREJ;
		break;
	default:
		IOLog("%s: error 0x%x\n", [self name], ccb->status);
		scsiReq->driverStatus = SR_IOST_HW;
		break;
	}
	scsiReq->bytesTransferred = scsiReq->maxTransfer - (int)ccb->resid;
}

- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiReq
	buffer:(void *)buffer
	client:(vm_task_t)client
{
	struct _scsireq	*req;
	SYMCommandBuf	cmdBuf;

	req = [self allocReq];
	[self convertReq:scsiReq ToXpt:req buffer:buffer client:client];
	cmdBuf.op = SO_Execute;
	cmdBuf.req = req;
	cmdBuf.lock = 0;
	[self executeCmdBuf:&cmdBuf];
	[self updateStatus:req];
	xpt_ccb_free(req->XPTReq);
	[self freeReq:req];
	outstandingCount--;
	return scsiReq->driverStatus;
}

- (sc_status_t)resetSCSIBus
{
	SYMCommandBuf	cmdBuf;

	cmdBuf.op = SO_Reset;
	cmdBuf.req = 0;
	cmdBuf.lock = 0;
	[self executeCmdBuf:&cmdBuf];
	return 0;
}

- (void)commandRequestOccurred
{
	SYMCommandBuf	*cmdBuf;

	[commandLock lock];
	while (!queue_empty(&commandQ)) {
		cmdBuf = (SYMCommandBuf *)queue_first(&commandQ);
		queue_remove(&commandQ, cmdBuf, SYMCommandBuf *, link);
		[commandLock unlock];
		switch (cmdBuf->op) {
		case SO_Reset:
			[self threadResetSCSIBus];
			[cmdBuf->lock lock];
			[cmdBuf->lock unlockWith:CMD_COMPLETE];
			break;
		case SO_Abort:
			[cmdBuf->lock lock];
			[cmdBuf->lock unlockWith:CMD_COMPLETE];
			IOExitThread();
			break;
		case SO_Execute:
			[self threadExecuteRequest:cmdBuf->req];
			break;
		default:
			break;
		}
		[commandLock lock];
	}
	[commandLock unlock];
}

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

- (void)interruptOccurred
{
	SIMInterrupt((unsigned char)interrupt);
	if ([self enableAllInterrupts])
		IOLog("%s: Unable to enable interrupt\n", [self name]);
}

- (void)manualTURScan
{
	IOSCSIRequest	scsiReq;
	unsigned	target;
	unsigned char	hostId;

	if (path == 0)
		return;
	hostId = symHostId(path);
	for (target = 0; target <= 7; target++) {
		if (target == hostId)
			continue;
		bzero(&scsiReq, sizeof(scsiReq));
		scsiReq.target = (unsigned char)target;
		scsiReq.lun = 0;
		scsiReq.maxTransfer = 0;
		scsiReq.timeoutLength = 4;
		[self executeRequest:&scsiReq buffer:0 client:IOVmTaskSelf()];
	}
}

- (int)executeCmdBuf:(SYMCommandBuf *)cmdBuf
{
	msg_header_t	msg;
	id		lock;
	kern_return_t	krtn;
	int		rtn;

	msg = SYMMessageTemplate;
	rtn = 0;
	if (cmdBuf->op == SO_Execute)
		lock = cmdBuf->req->reqLock;
	else {
		lock = [[NXConditionLock alloc] initWith:CMD_PENDING];
		cmdBuf->lock = lock;
	}

	[commandLock lock];
	queue_enter(&commandQ, cmdBuf, SYMCommandBuf *, link);
	[commandLock unlock];

	msg.msg_remote_port = intPortKern;
	krtn = msg_send_from_kernel(&msg, MSG_OPTION_NONE, 0);
	if (krtn) {
		IOLog("%s: msg_send_from_kernel() returned %d\n",
		    [self name], krtn);
		rtn = IO_R_IPC_FAILURE;
	} else {
		[lock lockWhen:CMD_COMPLETE];
	}

	if (cmdBuf->op != SO_Execute)
		[lock free];
	else
		[lock unlockWith:REQ_IDLE];
	return rtn;
}

@end
