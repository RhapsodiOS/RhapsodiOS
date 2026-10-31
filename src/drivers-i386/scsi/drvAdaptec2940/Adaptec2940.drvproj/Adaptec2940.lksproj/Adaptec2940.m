/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * Adaptec2940.m - Adaptec 2940 PCI SCSI controller driver.
 *
 * HISTORY
 *
 * Created for Rhapsody OS
 */

#import "Adaptec2940.h"
#import "Adaptec2940HIM.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/align.h>
#import <machkit/NXLock.h>
#import <kernserv/prototypes.h>
#import <string.h>

@implementation Adaptec2940

static unsigned int a2940UnitNum;

/*
 * Probe for Adaptec 2940 hardware.
 */
+ (BOOL)probe:deviceDescription
{
	id instance = [self alloc];
	return [instance initFromDeviceDescription:deviceDescription] != nil;
}

/*
 * Initialize from device description.
 */
- initFromDeviceDescription:deviceDescription
{
	IOPCIConfigSpace configSpace;
	IORange portRange;
	unsigned int *baseAddress;
	unsigned int irq;
	unsigned int i;
	BOOL foundIOBase = NO;
	IOReturn result;
	id configTable;
	const char *value;
	char unitName[20];
	int adapter;
	int threadResult;

	configTable = [deviceDescription configTable];
	bzero(&configSpace, sizeof(configSpace));
	result = [IODirectDevice getPCIConfigSpace:&configSpace
		withDeviceDescription:deviceDescription];
	if (result != IO_R_SUCCESS) {
		IOLog("Adaptec2940: Can't get configSpace; ABORTING\n");
		return [self free];
	}

	baseAddress = configSpace.BaseAddress;
	irq = configSpace.InterruptLine;
	if (baseAddress[0] == 0 || irq == 0) {
		IOLog("Adaptec2940: Bogus config info (IRQ %d, Base 0x%x\n",
		    irq, baseAddress);
		return [self free];
	}

	/* The reference requires exactly one I/O BAR among all six PCI BARs. */
	for (i = 0; i < 6; ++i) {
		if ((baseAddress[i] & 1) != 0) {
			if (foundIOBase) {
				IOLog("Adaptec2940: Multiple I/O Port Bases Found\n");
				return [self free];
			}
			foundIOBase = YES;
			portRange.start = baseAddress[i] & 0xFC;
		}
	}
	if (!foundIOBase) {
		IOLog("Adaptec2940: No I/O Port Base Found\n");
		return [self free];
	}
	portRange.size = 256;
	ioBase = portRange.start;

	result = [deviceDescription setInterruptList:(int *)&irq num:1];
	if (result != IO_R_SUCCESS) {
		IOLog("Adaptec2940: Unable to reserve IRQ %d\n", irq);
		return [self free];
	}
	result = [deviceDescription setPortRangeList:&portRange num:1];
	if (result != IO_R_SUCCESS) {
		IOLog("Adaptec2940: Unable to reserve port range 0x%x-0x%x\n",
		    ioBase, ioBase + 255);
		return [self free];
	}

	if ([super initFromDeviceDescription:deviceDescription] == nil) {
		IOLog("Adaptec2940: [super initFromDeviceDescription] failed\n");
		return [super free];
	}
	result = [deviceDescription getPCIdevice:&deviceNumber
		function:&functionNumber bus:&busNumber];
	if (result != IO_R_SUCCESS) {
		IOLog("Adaptec2940: Can't find device using getPCIdevice (%s)\n",
		    [self stringFromReturn:result]);
		return [self free];
	}
	adapter = PH_FindHA(busNumber, deviceNumber);
	if (adapter == 0) {
		IOLog("Adaptec2940: HIM Layer Can't find Host Adaptor at Bus %d Device %d\n",
		    busNumber, deviceNumber);
		return [self free];
	}
	if ((adapter & 0x80) != 0) {
		IOLog("Adaptec2940: Host Adapter at Bus %d Device %d not enabled\n",
		    busNumber, deviceNumber);
		return [self free];
	}

	if ([super startIOThread] != IO_R_SUCCESS) {
		IOLog("Adaptec2940: [super startIOThread] failed\n");
		return [super free];
	}
	ioThreadRunning = 1;
	commandLock = [[NXLock alloc] init];
	scbQLength = 0;
	resetState = 0;
	autoSenseEnable = 0;
	needReinit = 0;

	value = [configTable valueForStringKey:"Bus Type"];
	busType = value != 0 && strcmp(value, "PCI") == 0 ? 3 : 0;
	if (value != 0)
		[configTable freeString:value];
	if (busType != 3) {
		IOLog("Adaptec2940: Illegal Bus Type in Instance table\n");
		return [self free];
	}

	levelIRQ = 0;
	value = [configTable valueForStringKey:"Level IRQs"];
	if (value != 0 && strcmp(value, "YES") == 0) {
		levelIRQ = 1;
	} else {
		if (value != 0)
			[configTable freeString:value];
		value = [configTable valueForStringKey:"Share IRQ Levels"];
		if (value != 0 && strcmp(value, "YES") == 0)
			levelIRQ = 1;
	}
	if (value != 0)
		[configTable freeString:value];
	value = [configTable valueForStringKey:"Cmd Queueing"];
	cmdQueueEnable = value != 0 && strcmp(value, "YES") == 0;
	if (value != 0)
		[configTable freeString:value];
	value = [configTable valueForStringKey:"Synchronous"];
	syncModeEnable = value != 0 && strcmp(value, "YES") == 0;
	if (value != 0)
		[configTable freeString:value];

	outstandingCount = 0;
	queue_init(&commandQ);
	queue_init(&activeQ);
	queue_init(&scbQ);
	queue_init(&scbBadQ);
	channelInfo[0].owner = NULL;
	channelInfo[0].hostInfo = NULL;
	interruptPortKern = IOConvertPort([self interruptPort]);
	[self resetStats];
	threadResult = port_set_backlog_EXTERNAL(task_self([self interruptPort]));
	if (threadResult != 0)
		IOLog("%s: error %d on port_set_backlog()\n", [self name], threadResult);

	[self setUnit:a2940UnitNum++];
	sprintf(unitName, "a2940_%d", a2940UnitNum - 1);
	[self setName:unitName];
	[self setDeviceKind:"Adaptec2940"];
	sprintf(unitName, "0x%x", ioBase);
	[self setLocation:unitName];
	channelInfo[0].hostInfo = (Adaptec2940HostInfo *)IOMalloc(140);
	bzero(channelInfo[0].hostInfo, 0x8C);
	hspStructSave = NULL;
	if ([self initHostAdaptor] != 0) {
		IOLog("\nError initHostAdaptor\n");
		return [self free];
	}
	result = [self enableAllInterrupts];
	if (result == IO_R_SUCCESS) {
		IOLog("Adaptec %s found at Bus %d Device %d\n",
		    "2940 Host Adapter", busNumber, deviceNumber);
		IOLog("%s: %d Targets per Bus\n", [self name], [self numberOfTargets:0]);
		IOLog("Resetting SCSI Bus...\n");
		IOSleep(10000);
		[self registerDevice];
		return self;
	}
	IOLog("Adaptec2940: enableAllInterrupts returned %d\n", result);
	return [self free];
}

/*
 * Return maximum transfer size.
 */
- (unsigned)maxTransfer
{
	return (AIC_SG_COUNT * PAGE_SIZE);
}

- (char)checkScbAlign:(Adaptec2940SCB *)scb
{
	unsigned int address = (unsigned int)(unsigned long)scb;
	unsigned int head = (unsigned int)(unsigned long)((unsigned char *)self + 352);
	unsigned int tail = *(unsigned int *)((unsigned char *)self + 356);
	if (((~page_mask) & (address + 80)) == ((~page_mask) & (address + 224))) {
		return 0;
	}
	if (tail == head) {
		*(unsigned int *)(unsigned char *)head = address;
	} else {
		*(unsigned int *)(unsigned long)(tail + 248) = address;
	}
	*(unsigned int *)((unsigned char *)scb + 252) = tail;
	*(unsigned int *)((unsigned char *)scb + 248) = head;
	*(unsigned int *)((unsigned char *)self + 356) = address;
	return 1;
}

- (void)freeScb:(Adaptec2940SCB *)scb
{
	unsigned int head = (unsigned int)(unsigned long)((unsigned char *)self + 340);
	unsigned int tail = *(unsigned int *)((unsigned char *)self + 344);
	unsigned int scb_address = (unsigned int)(unsigned long)scb;
	if (scbQLength > 16 && *((unsigned char *)scb + 244) == 0) {
		IOFree(scb, 256);
		return;
	}
	if (tail == head)
		*(unsigned int *)(unsigned long)head = scb_address;
	else
		*(unsigned int *)(unsigned long)(tail + 248) = scb_address;
	*(unsigned int *)((unsigned char *)scb + 252) = tail;
	*(unsigned int *)((unsigned char *)scb + 248) = head;
	*(unsigned int *)((unsigned char *)self + 344) = scb_address;
	++scbQLength;
}

- (void)createScbs:(unsigned int)base size:(unsigned int)size
{
	unsigned int scb_address = base;
	unsigned int limit = size + base - 255;
	unsigned int head = (unsigned int)(unsigned long)((unsigned char *)self + 340);
	if (scb_address < limit) {
		do {
			Adaptec2940SCB *scb = (Adaptec2940SCB *)(unsigned long)scb_address;
			unsigned int tail;
			if ([self checkScbAlign:scb] != 0) {
				*((unsigned char *)scb + 244) = 1;
			} else {
				bzero(scb, 256);
				*(unsigned int *)((unsigned char *)scb + 76) = scb_address;
				*((unsigned char *)scb + 244) = 1;
				tail = *(unsigned int *)((unsigned char *)self + 344);
				if (tail == head)
					*(unsigned int *)(unsigned long)head = scb_address;
				else
					*(unsigned int *)(unsigned long)(tail + 248) = scb_address;
				*(unsigned int *)((unsigned char *)scb + 252) = tail;
				*(unsigned int *)((unsigned char *)scb + 248) = head;
				*(unsigned int *)((unsigned char *)self + 344) = scb_address;
				++scbQLength;
			}
			scb_address += 256;
		} while (limit > scb_address);
	}
}

- (void)commandCompleted:(Adaptec2940SCB *)scb
{
	unsigned char *scb_bytes = (unsigned char *)scb;
	unsigned int *command_data = *(unsigned int **)(scb_bytes + 224);
	unsigned int *request = *(unsigned int **)((unsigned char *)command_data + 8);
	unsigned int timestamp[2];
	unsigned int start_low = *(unsigned int *)(scb_bytes + 228);
	unsigned int start_high = *(unsigned int *)(scb_bytes + 232);
	unsigned int elapsed_low;
	unsigned int elapsed_high;
	id lock = *(id *)((unsigned char *)command_data + 24);
	IOGetTimestamp(timestamp);
	elapsed_low = timestamp[0] - start_low;
	elapsed_high = timestamp[1] - start_high - (timestamp[0] < start_low);
	request[10] = elapsed_low;
	request[11] = elapsed_high;
	request[7] = command_data[5];
	IOUnscheduleFunc(a2940Timeout, scb);
	[self freeScb:scb];
	[lock lock];
	[lock unlockWith:1];
}

- (void)scbComplete:(Adaptec2940SCB *)scb
{
	unsigned char *scbBytes = (unsigned char *)scb;
	Adaptec2940RequestMessage *message;
	unsigned char *request;
	unsigned char scbStatus;
	unsigned char hostStatus;
	unsigned int residual = 0;
	unsigned int requestLength;

	if (resetState == 2)
		return;

	message = (Adaptec2940RequestMessage *)scb->command_buffer;
	request = (unsigned char *)message->request;
	request[32] = scb->target_status;
	queue_remove(&activeQ, scb, Adaptec2940SCB *, queue_link);
	--outstandingCount;
	scbStatus = scbBytes[9];
	hostStatus = scbBytes[43];

	if (scbStatus == 2) {
		IOLog("%s: I/O Complete, Aborted Command (target %d)\n", [self name], request[0]);
		message->status = 12;
		[self commandCompleted:scb];
		*((unsigned char *)self + 360) |= 0x10;
		return;
	}
	if (scbStatus == 0) {
		IOLog("%s: I/O Complete with SCB still pending\n", [self name]);
		message->status = 14;
		[self commandCompleted:scb];
		return;
	}
	if (scbStatus != 1 && scbStatus != 4) {
		if (scbStatus == 0x80)
			IOLog("%s: I/O Complete, Invalid SCB Command\n", [self name]);
		else
			IOLog("%s: I/O Complete, Invalid SCB Status (0x%x)\n", [self name], scbStatus);
		message->status = 14;
		[self commandCompleted:scb];
		*((unsigned char *)self + 360) |= 0x10;
		return;
	}

	requestLength = *(unsigned int *)(request + 16);
	if (hostStatus == 18) {
		residual = scb->residual_data_count;
		if (residual != 0) {
			if (requestLength < residual) {
				IOLog("%s: Host Adaptor reported resid count of %d After a Transfer of %d bytes\n",
				      [self name], residual, requestLength);
				residual = requestLength;
			}
		} else {
			IOLog("%s: Data Overrun on target %d\n", [self name], request[0]);
			*(unsigned int *)(request + 36) = requestLength;
			message->status = 4;
		}
	}
	*(unsigned int *)(request + 36) = scb->total_transfer_length - residual;

	switch (hostStatus) {
	case 0:
	case 18:
		if (request[32] == 0)
			message->status = 0;
		else if (request[32] == 2)
			message->status = (*((unsigned char *)self + 360) & 1) ? 2 : 3;
		else
			message->status = 13;
		if (hostStatus == 18 && residual == 0)
			message->status = 4;
		break;
	case 4:
	case 5:
		IOLog("%s: Host aborted command (SP_HaStat = %u)\n", [self name], hostStatus);
		message->status = 6;
		break;
	case 0x11:
		message->status = 1;
		break;
	case 0x13:
		message->status = 12;
		break;
	case 0x14:
	case 0x17:
	case 0x1c:
	case 0x21:
		message->status = 6;
		break;
	case 0x1b:
		message->status = 3;
		break;
	case 0x20:
		IOLog("%s: Host adaptor hardware error\n", [self name]);
		message->status = 22;
		[self commandCompleted:scb];
		*((unsigned char *)self + 360) |= 0x10;
		return;
	case 0x22:
	case 0x23:
		message->status = 20;
		break;
	default:
		break;
	}
	[self commandCompleted:scb];
}

- (int)setIntValues:(unsigned int *)values forParameter:(char *)parameter count:(unsigned int)count
{
	unsigned char *flags = (unsigned char *)self + 360;
	const char *value_name;
	if (strcmp(parameter, "A2940_AutoSense") == 0) {
		if (count != 1)
			return -706;
		*flags = (*flags & (unsigned char)~1) | (values[0] != 0);
		value_name = values[0] != 0 ? "Enabled" : "Disabled";
		IOLog("%s: autoSense %s\n", [self name], value_name);
		return 0;
	}
	if (strcmp(parameter, "A2940_CmdQueue") == 0) {
		if (count != 1)
			return -706;
		*flags = (*flags & (unsigned char)~2) | ((values[0] != 0) << 1);
		value_name = values[0] != 0 ? "Enabled" : "Disabled";
		IOLog("%s: cmdQueue %s\n", [self name], value_name);
		return 0;
	}
	if (strcmp(parameter, "A2940_Sync") == 0) {
		if (count != 1)
			return -706;
		*flags = (*flags & (unsigned char)~4) | ((values[0] != 0) << 2);
		value_name = values[0] != 0 ? "Enabled" : "Disabled";
		IOLog("%s: syncMode %s\n", [self name], value_name);
		return 0;
	}
	return [super setIntValues:values forParameter:parameter count:count];
}

- (int)getIntValues:(unsigned int *)values forParameter:(char *)parameter count:(unsigned int *)count
{
	unsigned char flags = *((unsigned char *)self + 360);
	if (strcmp(parameter, "A2940_AutoSense") == 0) {
		if (*count != 1)
			return -706;
		values[0] = flags & 1;
		return 0;
	}
	if (strcmp(parameter, "A2940_CmdQueue") == 0) {
		if (*count != 1)
			return -706;
		values[0] = (flags >> 1) & 1;
		return 0;
	}
	if (strcmp(parameter, "A2940_Sync") == 0) {
		if (*count != 1)
			return -706;
		values[0] = (flags >> 2) & 1;
		return 0;
	}
	return [super getIntValues:values forParameter:parameter count:count];
}

- (Adaptec2940SCB *)allocScb
{
	Adaptec2940SCB *scb;
	unsigned char alignment_mark;
	unsigned int head = (unsigned int)(unsigned long)((unsigned char *)self + 340);
	if (scbQLength != 0) {
		unsigned int previous;
		unsigned int next;
		scb = (Adaptec2940SCB *)(unsigned long)*(unsigned int *)(unsigned char *)head;
		previous = *(unsigned int *)((unsigned char *)scb + 248);
		next = *(unsigned int *)((unsigned char *)scb + 252);
		if (previous == head)
			*(unsigned int *)((unsigned char *)self + 344) = next;
		else
			*(unsigned int *)(unsigned long)(previous + 252) = next;
		if (next == head)
			*(unsigned int *)(unsigned char *)head = previous;
		else
			*(unsigned int *)(unsigned long)(next + 248) = previous;
		--scbQLength;
		alignment_mark = *((unsigned char *)scb + 244);
	} else {
		scb = (Adaptec2940SCB *)IOMalloc(256);
		if ([self checkScbAlign:scb] != 0) {
			scb = [self allocScb];
			alignment_mark = *((unsigned char *)scb + 244);
		} else {
			alignment_mark = 0;
		}
	}
	bzero(scb, 256);
	*(unsigned int *)((unsigned char *)scb + 76) = (unsigned int)(unsigned long)scb;
	*((unsigned char *)scb + 244) = alignment_mark;
	return scb;
}

- (int)numberOfTargets:(int)channel
{
	return *((unsigned char *)channelInfo[channel].hostInfo +
	         A2940_CHANNEL_TARGET_COUNT_OFFSET);
}

- (char)acquireSCSIBus:(unsigned int)channel owner:(id)owner
{
	Adaptec2940ChannelInfo *info = &channelInfo[channel];

	if (channel != 0 || info->owner != nil || info->hostInfo == nil) {
		return 0;
	}
	info->owner = owner;
	return 1;
}

- (void)releaseSCSIBus:(unsigned int)channel owner:(id)owner
{
	if (channelInfo[channel].owner == owner) {
		channelInfo[channel].owner = nil;
	} else {
		IOLog("%s releaseSCSIBus: Incorrect Owner\n", [self name]);
	}
}

- (int)scsiBusId:(unsigned int)channel
{
	return *((unsigned char *)channelInfo[channel].hostInfo +
	         A2940_CHANNEL_BUS_ID_OFFSET);
}

/*
 * Free driver resources.
 */
- free
{
	if (ioThreadRunning) {
		Adaptec2940RequestMessage stopMessage;
		stopMessage.command = 2;
		[self executeCmdBuf:&stopMessage];
	}
	if (commandLock) {
		[commandLock free];
	}
	if (hspStructSave) {
		IOFree(hspStructSave, hspStructFreeSize);
		hspStructSave = NULL;
	}
	if (channelInfo[0].hostInfo)
		IOFree(channelInfo[0].hostInfo, A2940_HOST_INFO_SIZE);
	if (scbQLength != 0) {
		Adaptec2940SCB *scb;
		do {
			queue_remove_first(&scbQ, scb, Adaptec2940SCB *, queue_link);
			--scbQLength;
			if (scb->in_use == 0)
				IOFree(scb, A2940_SCB_SIZE);
		} while (scbQLength != 0);
	}
	if (scbBadQ.next != NULL && !queue_empty(&scbBadQ)) {
		Adaptec2940SCB *scb;
		do {
			queue_remove_first(&scbBadQ, scb, Adaptec2940SCB *, queue_link);
			if (scb->in_use == 0)
				IOFree(scb, A2940_SCB_SIZE);
		} while (!queue_empty(&scbBadQ));
	}

	return [super free];
}

- (void)resetStats
{
	queueLenTotal = 0;
	maxQueueLen = 0;
	totalCommands = 0;
}

- (unsigned int)numQueueSamples
{
	return totalCommands;
}

- (unsigned int)sumQueueLengths
{
	return queueLenTotal;
}

- (unsigned int)maxQueueLength
{
	return maxQueueLen;
}

/*
 * Interrupt handler.
 */
- (void)interruptOccurred
{
	int hostAddress = (int)(unsigned long)channelInfo[0].hostInfo;
	char intStatus = (char)PH_IntHandler(hostAddress);

	if (levelIRQ != 0) {
		if ((intStatus & 0x60) != 0) {
			while ((PH_IntHandler(hostAddress) & 0x60) != 0)
				;
		}
		if ((unsigned char)PH_PollInt(hostAddress) != 0)
			PH_IntHandler(hostAddress);
		[self enableAllInterrupts];
	}
	PH_EnableInt(hostAddress);
	if (needReinit) {
		[self threadResetBus:nil channel:reinitChannel reason:"Fatal Command Error"];
		needReinit = 0;
	}
}

- (void)interruptOccurredAt:(int)localNum
{
	IOLog("%s: interruptOccurredAt:%d\n", [self name], localNum);
}

- (void)otherOccurred:(int)id
{
	IOLog("%s: otherOccurred:%d\n", [self name], id);
}

- (void)receiveMsg
{
	IOLog("%s: receiveMsg\n", [self name]);
	[super receiveMsg];
}

- (void)timeoutOccurred
{
	ns_time_t now;
	queue_entry *entry;
	int resetNeeded = 0;

	IOGetTimestamp(&now);
	if (PH_PollInt(channelInfo[0].hostInfo) != 0) {
		IOLog("Adaptec2940: Missed Interrupt\n");
		PH_IntHandler(channelInfo[0].hostInfo);
	}

	entry = activeQ.next;
	while (entry != (queue_entry *)&activeQ) {
		Adaptec2940SCB *scb = (Adaptec2940SCB *)entry;
		Adaptec2940RequestMessage *message = (Adaptec2940RequestMessage *)scb->command_buffer;
		queue_entry *next = (queue_entry *)scb->queue_link.next;
		unsigned int timeoutSeconds = *(unsigned int *)((unsigned char *)message->request + 20);
		ns_time_t deadline = scb->start_time + (ns_time_t)1000000000ULL * timeoutSeconds;

		if (now >= deadline) {
			queue_remove(&activeQ, scb, Adaptec2940SCB *, queue_link);
			--outstandingCount;
			message->status = 5;
			if (message->channel == 0)
				resetNeeded = 1;
			[self commandCompleted:scb];
		}
		entry = next;
	}
	if (resetNeeded)
		[self threadResetBus:nil channel:0 reason:"I/O Timeout"];
}

- (void)threadResetBus:(Adaptec2940RequestMessage *)message
		channel:(unsigned int)channel
		reason:(const char *)reason
{
	Adaptec2940HostInfo *hostInfo;
	int resetResult;

	if (resetState != 0)
		return;
	resetState = 1;
	hostInfo = channelInfo[channel].hostInfo;
	resetState = 2;
	while (activeQ.next != (queue_entry *)&activeQ) {
		Adaptec2940SCB *scb = (Adaptec2940SCB *)activeQ.next;
		Adaptec2940RequestMessage *activeMessage =
			(Adaptec2940RequestMessage *)scb->command_buffer;
		queue_remove(&activeQ, scb, Adaptec2940SCB *, queue_link);
		--outstandingCount;
		activeMessage->status = 20;
		PH_Special(0, (int)(unsigned long)hostInfo, (int)(unsigned long)scb);
		[self commandCompleted:scb];
	}
	resetResult = PH_Special(2, (int)(unsigned long)hostInfo, 0);
	if (resetResult != 0)
		IOLog("%s: Hard reset Error (rtn = %d)\n", [self name], resetResult);
	IOLog("%s: Resetting SCSI Bus %d (%s)...\n", [self name], channel, reason);
	[self initHostAdaptor];
	IOSleep(10000);
	if (message != nil) {
		message->status = 0;
		[message->condition_lock lock];
		[message->condition_lock unlockWith:1];
	}
	resetState = 0;
	outstandingCount = 0;
	if (levelIRQ != 0)
		[self enableAllInterrupts];
}

- (unsigned int)initHostAdaptor
{
	Adaptec2940HostInfo *hostInfo = channelInfo[0].hostInfo;
	unsigned int hostBytes;
	unsigned int physicalAddress;
	unsigned int status;
	unsigned int target;
	unsigned int hostSize;
	int irq;

	if (hostInfo != NULL) {
		bzero(hostInfo, A2940_HOST_INFO_SIZE);
		hostInfo->bytes[18] = 0;
		*(unsigned int *)(hostInfo->bytes + 12) = 192;
		hostInfo->bytes[8] = busNumber;
		hostInfo->bytes[9] = deviceNumber;
		*(unsigned short *)(hostInfo->bytes + 66) = 0xffff;
		PH_GetConfig((int)(unsigned long)hostInfo);

		irq = [self deviceDescription] ? [[self deviceDescription] interrupt] : 0;
		if (irq != hostInfo->bytes[19]) {
			IOLog("Adaptec2940: Improper IRQ in Configuration (HA IRQ = %d, Config IRQ = %d)\n",
			      hostInfo->bytes[19], irq);
			return 1;
		}
		if (*(unsigned int *)(hostInfo->bytes + 4) != ioBase) {
			IOLog("Adaptec2940: kernel base addrs 0x%x, HIM base addrs 0x%x\n",
			      ioBase, *(unsigned int *)(hostInfo->bytes + 4));
			return 1;
		}
		if (hspStructSave == NULL) {
			hostSize = *(unsigned short *)(hostInfo->bytes + 60);
			if (page_size < hostSize)
				IOPanic("Adaptec2940: hspStruct larger thanpage size");
			hspStructFreeSize = 2 * hostSize;
			hspStructSave = (void *)IOMalloc(hspStructFreeSize);
			hostBytes = (unsigned int)(unsigned long)hspStructSave;
			if (((~page_mask) & hostBytes) == ((~page_mask) & (hostBytes + hostSize)))
				[self createScbs:hostBytes + hostSize size:hostSize];
			else
				[self createScbs:hostBytes size:hostSize];
		}
		hostBytes = (unsigned int)(unsigned long)hspStructSave;
		bzero((void *)(unsigned long)hostBytes, *(unsigned short *)(hostInfo->bytes + 60));
		*(unsigned int *)(hostInfo->bytes + 100) = (unsigned int)(unsigned long)self;
		*(unsigned int *)(hostInfo->bytes + 52) = hostBytes;
		status = IOVmTaskSelf((void *)(unsigned long)hostBytes, &physicalAddress);
		IOPhysicalFromVirtual(status);
		*(unsigned int *)(hostInfo->bytes + 56) = physicalAddress;
		if (hostInfo->bytes[31] > 0x20) {
			IOLog("2940: Invalid MaxTargets (%d)\n", hostInfo->bytes[31]);
			return 1;
		}
		for (target = 0; target < hostInfo->bytes[31]; ++target) {
			if ((*((unsigned char *)self + 360) & 4) == 0)
				hostInfo->bytes[target + 32] &= (unsigned char)~1;
		}
		hostInfo->bytes[12] &= (unsigned char)~2;
		status = PH_InitHA((int)(unsigned long)hostInfo);
		if (status != 0) {
			IOLog("Adaptec2940: Couldn't initialize Host Adaptor (PH_InitHA() returned %d\n", status);
			return status;
		}
		*(unsigned int *)(channelInfo[0].hostInfo->bytes + 12) &= 0xffffff3f;
		physicalAddress = *(unsigned int *)(channelInfo[0].hostInfo->bytes + 56);
		PH_EnableInt((int)(unsigned long)hostInfo);
	}
	[self enableAllInterrupts];
	return 0;
}

- (void)commandRequestOccurred
{
	Adaptec2940RequestMessage *message;

	[commandLock lock];
	while (!queue_empty(&commandQ)) {
		queue_remove_first(&commandQ, message, Adaptec2940RequestMessage *, queue_link);
		[commandLock unlock];
		switch (message->command) {
		case 0:
			[self threadExecuteRequest:message];
			break;
		case 1:
			[self threadResetBus:message channel:message->channel
				       reason:"Reset Command Received"];
			break;
		case 2:
			[message->condition_lock lock];
			[message->condition_lock unlockWith:1];
			IOExitThread();
			break;
		default:
			break;
		}
		[commandLock lock];
	}
	[commandLock unlock];
}

/*
 * Execute SCSI request.
 */
- (sc_status_t)executeRequest:(IOSCSIRequest *)scsiReq
			buffer:(void *)buffer
			client:(vm_task_t)client
{
	Adaptec2940CommandBuf *cmdBuf;
	IOReturn result;

	cmdBuf = (Adaptec2940CommandBuf *)IOMalloc(sizeof(Adaptec2940CommandBuf));
	if (cmdBuf == NULL) {
		return SR_IOST_MEMALL;
	}

	cmdBuf->scsiReq = scsiReq;
	cmdBuf->buffer = buffer;
	cmdBuf->client = client;
	cmdBuf->scb = NULL;

	result = [self executeCmdBuf:cmdBuf];

	if (result != IO_R_SUCCESS) {
		IOFree(cmdBuf, sizeof(Adaptec2940CommandBuf));
		return SR_IOST_HW;
	}

	return SR_IOST_GOOD;
}

/*
 * Reset SCSI bus.
 */
- (sc_status_t)resetSCSIBus
{
	IOReturn result;

	result = [self aicResetBus];

	return (result == IO_R_SUCCESS) ? SR_IOST_GOOD : SR_IOST_HW;
}

@end

/* 0x231c: route a completed SCB through the controller's Objective-C handler. */
void *PH_ScbCompleted(int scbAddress)
{
	unsigned char *scb = (unsigned char *)(unsigned long)(unsigned int)scbAddress;
	unsigned char *host = (unsigned char *)(unsigned long)*(unsigned int *)(scb + 4);
	id receiver = *(id *)(host + 100);
	Adaptec2940SCB *completed = (Adaptec2940SCB *)(unsigned long)
		*(unsigned int *)(scb + 76);
	[receiver scbComplete:completed];
	return 0;
}
