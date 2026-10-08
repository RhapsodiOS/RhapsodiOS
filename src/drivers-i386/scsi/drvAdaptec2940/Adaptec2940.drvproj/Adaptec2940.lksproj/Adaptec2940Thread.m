/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * Adaptec2940Thread.m - Thread and command execution for Adaptec 2940.
 *
 * HISTORY
 *
 * Created for Rhapsody OS
 */

#import "Adaptec2940.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <kernserv/prototypes.h>
#import <string.h>

extern int msg_send_from_kernel(void *message, int send_size, int receive_size);

static const unsigned int CmdMessageTemplate[6] = {
	0x01000000, 0x00000018, 0, 0, 0, 0x00232324
};

@implementation Adaptec2940(Private)

/*
 * Execute command buffer in thread context.
 */
- (void)threadExecuteRequest:(Adaptec2940RequestMessage *)message
{
	unsigned char *request = (unsigned char *)message->request;
	Adaptec2940HostInfo *hostInfo = channelInfo[message->channel].hostInfo;
	Adaptec2940SCB *scb = [self allocScb];
	unsigned char cdbGroup = request[2] & 0xe0;
	unsigned char reservedBits;
	unsigned int commandLength;
	unsigned int bufferAddress = (unsigned int)(unsigned long)message->buffer;
	unsigned int remaining = *(unsigned int *)(request + 16);
	unsigned int originalLength = remaining;
	unsigned int pageCount = remaining == 0 ? 0 :
		((((bufferAddress + remaining + page_mask) & ~page_mask) -
		  (bufferAddress & ~page_mask)) / page_size);
	unsigned int physicalAddress;
	unsigned int status;
	unsigned int index;
	unsigned int cursor = bufferAddress;
	int useSimpleQueue = 0;

	if (cdbGroup == 0) {
		commandLength = 6;
		reservedBits = request[7];
	} else if (cdbGroup == 0x20 || cdbGroup == 0x40) {
		commandLength = 10;
		reservedBits = request[11];
	} else if (cdbGroup == 0xa0) {
		commandLength = 12;
		reservedBits = request[13];
	} else if (cdbGroup == 0xc0 || cdbGroup == 0xe0) {
		commandLength = (request[27] & 0xf0) ? request[27] >> 4 :
			(cdbGroup == 0xc0 ? 6 : 10);
		reservedBits = 0;
	} else {
		goto invalid_request;
	}
	if ((reservedBits & 3) != 0 || pageCount > A2940_SG_MAX)
		goto invalid_request;

	scb->host_info = hostInfo;
	scb->scb_status = 2;
	if ((*((unsigned char *)self + 360) & 1) != 0) {
		scb->flags |= 0x80;
		*(unsigned int *)((unsigned char *)scb + 48) = sizeof(esense_reply_t);
		status = IOPhysicalFromVirtual(message->client_task,
			(vm_offset_t)(request + 56), (vm_offset_t *)&scb->sense_physical);
		if (status != 0) {
			IOLog("%s: Can't get physical address of sense data\n", [self name]);
			scb->flags &= (unsigned char)~0x80;
		}
	} else {
		scb->flags &= (unsigned char)~0x80;
	}

	if ((request[24] & 1) != 0) {
		useSimpleQueue = ((*((unsigned char *)self + 360) & 2) != 0) &&
			((request[24] & 2) == 0);
		if (useSimpleQueue || [channelInfo[message->channel].owner numReserved] > 9)
			scb->control |= 0x40;
		if (useSimpleQueue) {
			scb->control |= 0x20;
			scb->control &= 0xfc;
		} else {
			scb->control &= (unsigned char)~0x20;
		}
	} else {
		scb->control &= (unsigned char)~0x20;
	}
	if (pageCount > 1)
		scb->control |= 0x80;
	scb->target_channel_lun = (unsigned char)(16 * request[0]);
	scb->target_channel_lun |= hostInfo->bytes[18];
	scb->target_channel_lun |= request[1];
	status = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_offset_t)scb->cdb,
		(vm_offset_t *)&physicalAddress);
	if (status != 0) {
		IOLog("%s: Can't get physical address of CDB\n", [self name]);
		IOPanic("Adaptec2940");
	}
	scb->command_pointer = physicalAddress;
	scb->command_length = (unsigned char)commandLength;
	bcopy(request + 2, scb->cdb, 12);
	scb->command_buffer = message;
	IOGetTimestamp(&scb->start_time);
	scb->timeout_port = interruptPortKern;
	scb->total_transfer_length = 0;

	for (index = 0; index < pageCount; ++index) {
		unsigned int pageEnd = (cursor + page_mask + 1) & ~page_mask;
		unsigned int chunk = remaining < pageEnd - cursor ? remaining : pageEnd - cursor;
		status = IOPhysicalFromVirtual(message->client_task, (vm_offset_t)cursor,
			(vm_offset_t *)&physicalAddress);
		if (status != 0) {
			IOLog("%s: Can't get physical address\n", [self name]);
			goto physical_failure;
		}
		scb->sg_list[index].address = physicalAddress;
		scb->sg_list[index].length = chunk;
		scb->total_transfer_length += chunk;
		cursor += chunk;
		remaining -= chunk;
	}
	if (pageCount != 0) {
		status = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_offset_t)scb->sg_list,
			(vm_offset_t *)&physicalAddress);
		if (status != 0) {
			IOLog("%s: Can't get physical address of sg list\n", [self name]);
			IOPanic("Adaptec2940");
		}
		scb->sg_count = (unsigned char)pageCount;
		scb->sg_pointer = physicalAddress;
	} else {
		scb->sg_count = 0;
	}
	PH_ScbSend((int)(unsigned long)scb);
	if (scb->host_status == 1 || scb->host_status == 2 || scb->host_status == 4) {
		IOLog("%s: Premature SCB completion\n", [self name]);
		message->status = 14;
		goto complete_request;
	}
	if (scb->host_status == 0x80) {
		IOLog("%s: Host Adaptor Rejected Command\n", [self name]);
		message->status = 14;
		goto complete_request;
	}

	queue_enter(&activeQ, scb, Adaptec2940SCB *, queue_link);
	IOScheduleFunc(a2940Timeout, scb, *(unsigned int *)(request + 20));
	++outstandingCount;
	if (outstandingCount > maxQueueLen)
		maxQueueLen = outstandingCount;
	queueLenTotal += outstandingCount;
	++totalCommands;
	return;

invalid_request:
	message->status = 7;
	goto complete_request;
physical_failure:
	message->status = 14;
complete_request:
	[self freeScb:scb];
	*(int *)(request + 28) = message->status;
	[message->condition_lock lock];
	[message->condition_lock unlockWith:1];
}

/*
 * Run pending commands.
 */
- (void)runPendingCommands
{
	Adaptec2940CommandBuf *cmdBuf;

	[commandLock lock];

	/* Process commands from command queue */
	while (!queue_empty(&commandQ)) {
		queue_remove_first(&commandQ, cmdBuf, Adaptec2940CommandBuf *, link);
		[self threadExecuteRequest:cmdBuf];
	}

	/* Process pending queue if space available */
	while (!queue_empty(&pendingQ) && outstandingCount < AIC_QUEUE_SIZE) {
		queue_remove_first(&pendingQ, cmdBuf, Adaptec2940CommandBuf *, link);
		[self threadExecuteRequest:cmdBuf];
	}

	[commandLock unlock];
}

/*
 * Process completed command.
 */
- (void)processCmdComplete:(struct scb *)scb
{
	Adaptec2940CommandBuf *cmdBuf;
	IOSCSIRequest *scsiReq;
	sc_status_t status;

	if (!scb || !scb->in_use) {
		return;
	}

	cmdBuf = (Adaptec2940CommandBuf *)scb->cmdBuf;
	if (!cmdBuf) {
		[self freeScb:scb];
		return;
	}

	scsiReq = cmdBuf->scsiReq;

	/* Remove from outstanding queue */
	queue_remove(&outstandingQ, scb, struct scb *, scbQ);
	outstandingCount--;

	/* Determine status */
	if (scb->target_status == STAT_GOOD) {
		status = SR_IOST_GOOD;
		scsiReq->bytesTransferred = scb->total_xfer_len - scb->residual_data_count;
	} else if (scb->target_status == STAT_CHECK_CONDITION) {
		status = SR_IOST_CHKSV;
		scsiReq->bytesTransferred = 0;
		if (scsiReq->senseData) {
			bcopy(&scb->senseData, scsiReq->senseData, sizeof(esense_reply_t));
		}
	} else {
		status = SR_IOST_SELTO;
		scsiReq->bytesTransferred = 0;
	}

	scsiReq->driverStatus = status;

	/* Complete the request */
	[self completeRequest:scsiReq];

	/* Free resources */
	[self freeScb:scb];
	IOFree(cmdBuf, sizeof(Adaptec2940CommandBuf));

	/* Run more pending commands */
	[self runPendingCommands];
}

/*
 * Execute command buffer.
 */
- (int)executeCmdBuf:(Adaptec2940RequestMessage *)message
{
	unsigned int commandMessage[6];
	int result = 0;
	int sendResult;

	bcopy(CmdMessageTemplate, commandMessage, sizeof(commandMessage));
	message->status = 100;
	message->condition_lock = [[NXConditionLock alloc] initWith:0];
	[commandLock lock];
	queue_enter(&commandQ, message, Adaptec2940RequestMessage *, queue_link);
	[commandLock unlock];

	commandMessage[4] = interruptPortKern;
	sendResult = msg_send_from_kernel(commandMessage, 0, 0);
	if (sendResult != 0) {
		IOLog("%s: msg_send_from_kernel() returned %d\n", [self name], sendResult);
		result = -703;
	} else {
		[message->condition_lock lockWhen:1];
	}
	[message->condition_lock free];

	return result;
}

@end
