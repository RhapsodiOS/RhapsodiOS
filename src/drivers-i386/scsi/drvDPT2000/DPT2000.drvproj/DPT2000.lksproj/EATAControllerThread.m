/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * EATAControllerThread.m - I/O thread methods for the DPT EATA controller.
 *
 * HISTORY
 *
 * Reconstructed from DPTSCSIDriver_reloc (EATAThread.m /
 * EATAController(IOThread)).
 */

#import "EATAController.h"
#import "EATAControllerPrivate.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#if defined(i386) || defined(__i386__)
#import <driverkit/i386/kernelDriver.h>
#import <driverkit/i386/directDevice.h>
#endif
#import <kernserv/prototypes.h>
#import <kernserv/queue.h>
#import <mach/vm_param.h>
#import <bsd/dev/scsireg.h>
#import <string.h>

#define SCSI_OPGROUP(opcode)	((opcode) & 0xe0)
#define OPGROUP_0		0x00
#define OPGROUP_1		0x20
#define OPGROUP_2		0x40
#define OPGROUP_5		0xa0
#define OPGROUP_6		0xc0
#define OPGROUP_7		0xe0

static unsigned int
eata_bswap32(unsigned int x)
{
	return (x << 24) | ((x & 0xff00) << 8) |
	    ((x >> 8) & 0xff00) | (x >> 24);
}

static void
eata_out_addr(unsigned short port, unsigned int phys, unsigned char cmd)
{
	outb(port + EATA_ADDR0_OFF, (unsigned char)phys);
	outb(port + EATA_ADDR1_OFF, (unsigned char)(phys >> 8));
	outb(port + EATA_ADDR2_OFF, (unsigned char)(phys >> 16));
	outb(port + EATA_ADDR3_OFF, (unsigned char)(phys >> 24));
	outb(port + EATA_CMD_OFF, cmd);
}


@implementation EATAController(IOThread)

- (void)threadExecuteRequest:(EATACommandBuf *)cmdBuf
{
	struct ccb	*ccb;
	unsigned int	phys;
	unsigned short	port;

	ccb = [self ccbFromCmd:cmdBuf];
	if (ccb == NULL) {
		cmdBuf->result = cmdBuf->scsiReq->driverStatus;
		[cmdBuf->cmdLock lock];
		[cmdBuf->cmdLock unlockWith:CMD_COMPLETE];
		return;
	}

	ccb->timeoutPort = interruptPortKern;
	IOScheduleFunc(eataTimeout, ccb, cmdBuf->scsiReq->timeoutLength);

	ccb->sp.eoc &= 0x80;
	ccb->sp.eoc |= 0x55;

	queue_enter(&outstandingQ, ccb, struct ccb *, ccbQ);
	outstandingCount++;

	ccb->cp.data_len = eata_bswap32(ccb->cp.data_len);
	ccb->cp.data_addr = eata_bswap32(ccb->cp.data_addr);
	ccb->cp.sp_addr = eata_bswap32(ccb->cp.sp_addr);
	ccb->cp.sense_addr = eata_bswap32(ccb->cp.sense_addr);

	while (eata_busy_0(ioBase, (int)0xFFFFFFFF))
		;

	port = ioBase;
	if (IOPhysicalFromVirtual(IOVmTaskSelf(),
		(vm_address_t)&ccb->cp, &phys)) {
		IOLog("EATA: Can't get physical address\n");
		phys = 0;
	}
	eata_out_addr(port, phys, EATA_CMD_SEND_CP);

	if (outstandingCount > maxQueueLen)
		maxQueueLen = outstandingCount;
	queueLenTotal += outstandingCount;
	totalCommands++;
}

- (void)commandCompleted:(struct ccb *)ccb
		  reason:(completeStatus)status
{
	EATACommandBuf	*cmdBuf;
	IOSCSIRequest	*scsiReq;
	unsigned	hostStat;
	unsigned	residue;
	ns_time_t	now;
	ns_time_t	start;
	int		needReset;

	needReset = 0;
	cmdBuf = (EATACommandBuf *)ccb->cmdBuf;
	scsiReq = cmdBuf->scsiReq;
	scsiReq->scsiStatus = ccb->sp.status;

	switch (status) {
	    case CS_Timeout:
		scsiReq->driverStatus = SR_IOST_IOTO;
		break;
	    case CS_Reset:
		scsiReq->driverStatus = SR_IOST_RESET;
		break;
	    case CS_Complete:
		hostStat = ccb->sp.eoc & 0x7F;
		switch (hostStat) {
		    case 0:
			residue = eata_bswap32(ccb->sp.residue);
			ccb->sp.residue = residue;
			scsiReq->bytesTransferred =
			    scsiReq->maxTransfer - residue;
			if (config.dma_channel_valid)
				[self completeDMA:ccb->dmaList];
			if (scsiReq->scsiStatus == STAT_GOOD)
				scsiReq->driverStatus = SR_IOST_GOOD;
			else if (scsiReq->scsiStatus == STAT_CHECK) {
				scsiReq->driverStatus = SR_IOST_CHKSV;
				scsiReq->senseData = ccb->senseData;
			} else {
				scsiReq->driverStatus = SR_IOST_BADST;
				if (scsiReq->scsiStatus == STAT_BUSY)
					scsiReq->bytesTransferred = 0;
			}
			break;
		    case 1:
			if (config.dma_channel_valid)
				[self abortDMA:ccb->dmaList];
			scsiReq->driverStatus = SR_IOST_SELTO;
			break;
		    case 3:
			if (config.dma_channel_valid)
				[self abortDMA:ccb->dmaList];
			scsiReq->driverStatus = SR_IOST_RESET;
			IOLog("%s: Host Adaptor Reported Bus Reset\n",
			    [self name]);
			break;
		    case 4:
			break;
		    default:
			IOLog("EATA interrupt: bad status 0x%x\n", hostStat);
			scsiReq->driverStatus = SR_IOST_HW;
			needReset = 1;
			break;
		}
		break;
	}

	IOGetTimestamp(&now);
	memcpy(&start, ccb->startTime, sizeof(start));
	scsiReq->totalTime = now - start;
	IOUnscheduleFunc(eataTimeout, ccb);
	[self freeCcb:ccb];

	cmdBuf->result = scsiReq->driverStatus;
	[cmdBuf->cmdLock lock];
	[cmdBuf->cmdLock unlockWith:CMD_COMPLETE];

	if (needReset)
		[self threadResetBus:NULL initConfig:NO];
}

- (void)clearResetInts
{
	int i;

	for (i = 0; i <= 9; i++) {
		IOSleep(1000);
		(void)inb(ioBase + EATA_STATUS_OFF);
	}
}

- threadResetBus:(EATACommandBuf *)cmdBuf
      initConfig:(BOOL)initConfig
{
	struct ccb	*ccb;
	struct ccb	*next;

	(void)inb(ioBase + EATA_STATUS_OFF);
	outb(ioBase + EATA_CMD_OFF, EATA_CMD_RESET);
	(void)inb(ioBase + EATA_STATUS_OFF);

	if (initConfig)
		IOLog("Resetting SCSI Bus...\n");
	else
		IOLog("%s: Resetting SCSI Bus...\n", [self name]);

	if (initConfig)
		IOSleep(10000);
	else
		[self clearResetInts];

	ccb = (struct ccb *)queue_first(&outstandingQ);
	while (!queue_end(&outstandingQ, (queue_entry_t)ccb)) {
		next = (struct ccb *)queue_next(&ccb->ccbQ);
		queue_remove(&outstandingQ, ccb, struct ccb *, ccbQ);
		outstandingCount--;
		[self commandCompleted:ccb reason:CS_Reset];
		ccb = next;
	}

	if (cmdBuf) {
		cmdBuf->result = SR_IOST_GOOD;
		[cmdBuf->cmdLock lock];
		[cmdBuf->cmdLock unlockWith:CMD_COMPLETE];
	}

	if (levelIRQ && !initConfig)
		[self enableAllInterrupts];

	return self;
}

- (struct ccb *)allocCcb:(BOOL)doDMA
{
	struct ccb	*page;
	struct ccb	*ccb;
	struct ccb	*end;
	vm_offset_t	mask;

	if (ccbFree == NULL) {
		if (config.dma_channel_valid)
			page = (struct ccb *)IOMallocLow(page_size);
		else
			page = (struct ccb *)IOMalloc(page_size);

		end = (struct ccb *)((char *)page + page_size - EATA_CCB_SIZE);
		mask = ~page_mask;
		ccb = page;
		while (ccb <= end) {
			if (((vm_offset_t)ccb & mask) ==
			    (((vm_offset_t)ccb + EATA_CCB_SIZE) & mask)) {
				ccb->ccbQ.next = (queue_entry_t)ccbFree;
				ccbFree = ccb;
			}
			ccb = (struct ccb *)((char *)ccb + EATA_CCB_SIZE);
		}
	}

	ccb = ccbFree;
	ccbFree = (struct ccb *)ccb->ccbQ.next;
	bzero(ccb, EATA_CCB_SIZE);

	if (doDMA) {
		dmaLockCount++;
		if (dmaLockCount == 1)
			[super reserveDMALock];
	}
	return ccb;
}

- (void)freeCcb:(struct ccb *)ccb
{
	BOOL didDMA;

	didDMA = (ccb->total_xfer_len != 0);
	ccb->ccbQ.next = (queue_entry_t)ccbFree;
	ccbFree = ccb;
	if (didDMA) {
		dmaLockCount--;
		if (dmaLockCount == 0)
			[super releaseDMALock];
	}
}

- (void)completeDMA:(IOEISADMABuffer *)dmaList
{
	unsigned i;

	for (i = 0; i <= 0x3F; i++) {
		if (dmaList[i] == 0)
			return;
		[self freeDMABuffer:dmaList[i]];
	}
}

- (void)abortDMA:(IOEISADMABuffer *)dmaList
{
	unsigned i;

	for (i = 0; i <= 0x3F; i++) {
		if (dmaList[i] == 0)
			return;
		[self abortDMABuffer:dmaList[i]];
	}
}

- (struct ccb *)ccbFromCmd:(EATACommandBuf *)cmdBuf
{
	IOSCSIRequest		*scsiReq;
	struct ccb		*ccb;
	cdb_t			*cdbp;
	unsigned int		cdb_ctrl;
	unsigned int		opgroup;
	vm_offset_t		addr;
	vm_offset_t		phys;
	vm_size_t		len;
	unsigned int		pages;
	unsigned int		thisLength;
	unsigned int		i;
	id			owner;
	struct eata_cp		*cp;
	struct eata_sg		*sg;
	IOEISADMABuffer		*dmaBuf;
	ns_time_t		now;

	scsiReq = cmdBuf->scsiReq;
	addr = (vm_offset_t)cmdBuf->buffer;
	len = scsiReq->maxTransfer;
	cdbp = &scsiReq->cdb;

	opgroup = SCSI_OPGROUP(cdbp->cdb_opcode);
	switch (opgroup) {
	    case OPGROUP_0:
	    case OPGROUP_6:
		cdb_ctrl = cdbp->cdb_c6.c6_ctrl;
		break;
	    case OPGROUP_1:
	    case OPGROUP_2:
	    case OPGROUP_7:
		cdb_ctrl = cdbp->cdb_c10.c10_ctrl;
		break;
	    case OPGROUP_5:
		cdb_ctrl = cdbp->cdb_c12.c12_ctrl;
		break;
	    default:
		scsiReq->driverStatus = SR_IOST_CMDREJ;
		return NULL;
	}

	if ((cdb_ctrl & CTRL_LINKFLAG) != CTRL_NOLINK) {
		scsiReq->driverStatus = SR_IOST_CMDREJ;
		return NULL;
	}

	ccb = [self allocCcb:(scsiReq->maxTransfer ? YES : NO)];
	if (ccb == NULL)
		return NULL;

	if (len == 0)
		pages = 0;
	else {
		pages = (round_page(addr + len) - trunc_page(addr)) /
		    page_size;
	}
	if (configSgSize <= pages)
		pages = configSgSize;

	bzero(&ccb->sp, EATA_SP_SIZE);
	ccb->cmdBuf = cmdBuf;
	ccb->total_xfer_len = 0;
	IOGetTimestamp(&now);
	memcpy(ccb->startTime, &now, sizeof(now));

	cp = &ccb->cp;
	bzero(cp, EATA_CP_SIZE);
	cp->cdb[0] = ((unsigned char *)cdbp)[0];
	cp->cdb[1] = ((unsigned char *)cdbp)[1];
	cp->cdb[2] = ((unsigned char *)cdbp)[2];
	cp->cdb[3] = ((unsigned char *)cdbp)[3];
	cp->cdb[4] = ((unsigned char *)cdbp)[4];
	cp->cdb[5] = ((unsigned char *)cdbp)[5];
	cp->cdb[6] = ((unsigned char *)cdbp)[6];
	cp->cdb[7] = ((unsigned char *)cdbp)[7];
	cp->cdb[8] = ((unsigned char *)cdbp)[8];
	cp->cdb[9] = ((unsigned char *)cdbp)[9];
	cp->cdb[10] = ((unsigned char *)cdbp)[10];
	cp->cdb[11] = ((unsigned char *)cdbp)[11];

	cp->data_in = scsiReq->read ? 1 : 0;
	cp->data_out = scsiReq->read ? 0 : 1;
	cp->scatter = (pages > 1) ? 1 : 0;
	cp->auto_req_sen = 1;
	cp->immediate = EATA_CP_IMMEDIATE;

	if (IOPhysicalFromVirtual(IOVmTaskSelf(),
		(vm_address_t)&ccb->senseData, &phys)) {
		IOLog("EATA: Can't get physical address\n");
		phys = 0;
	}
	cp->sense_addr = phys;

	if (IOPhysicalFromVirtual(IOVmTaskSelf(),
		(vm_address_t)&ccb->sp, &phys)) {
		IOLog("EATA: Can't get physical address\n");
		phys = 0;
	}
	cp->sp_addr = phys;

	cp->target = scsiReq->target & EATA_CP_TARGET_MASK;
	cp->lun = scsiReq->lun & EATA_CP_LUN_MASK;
	cp->identify = 1;
	cp->channel = cmdBuf->scsiChannel;

	owner = channelInfo[cmdBuf->scsiChannel].owner;
	if ([owner numReserved] > 9 && scsiReq->disconnect)
		cp->physical = 1;

	if (pages == 0) {
		cp->data_addr = 0;
		cp->data_len = 0;
		return ccb;
	}

	if (pages == 1) {
		if (IOPhysicalFromVirtual(cmdBuf->client, addr, &phys)) {
			IOLog("EATA: Can't get physical address\n");
			phys = 0;
		}
		if (config.dma_channel_valid) {
			ccb->dmaList[0] = [self createDMABufferFor:&phys
			    length:len
			    read:scsiReq->read
			    needsLowMemory:YES
			    limitSize:NO];
			if (ccb->dmaList[0] == 0) {
				[self abortDMA:ccb->dmaList];
				scsiReq->driverStatus = SR_IOST_INT;
				[self freeCcb:ccb];
				return NULL;
			}
		}
		cp->data_addr = phys;
		cp->data_len = len;
		ccb->total_xfer_len = len;
		return ccb;
	}

	sg = ccb->sg_list;
	dmaBuf = ccb->dmaList;
	cp->data_len = 0;
	if (IOPhysicalFromVirtual(IOVmTaskSelf(),
		(vm_address_t)sg, &phys)) {
		IOLog("EATA: Can't get physical address\n");
		phys = 0;
	}
	cp->data_addr = phys;

	for (i = 0; i < pages; i++) {
		thisLength = (page_mask + 1 + addr) & ~page_mask;
		thisLength -= addr;
		if (len < thisLength)
			thisLength = len;

		if (IOPhysicalFromVirtual(cmdBuf->client, addr, &phys)) {
			IOLog("EATA: Can't get physical address\n");
			phys = 0;
		}
		if (config.dma_channel_valid) {
			*dmaBuf = [self createDMABufferFor:&phys
			    length:thisLength
			    read:scsiReq->read
			    needsLowMemory:YES
			    limitSize:NO];
			if (*dmaBuf == 0) {
				[self abortDMA:ccb->dmaList];
				scsiReq->driverStatus = SR_IOST_INT;
				[self freeCcb:ccb];
				return NULL;
			}
		}
		sg->addr = eata_bswap32(phys);
		sg->len = eata_bswap32(thisLength);
		cp->data_len += 8;
		ccb->total_xfer_len += thisLength;
		addr += thisLength;
		len -= thisLength;
		sg++;
		dmaBuf++;
	}

	return ccb;
}

@end
