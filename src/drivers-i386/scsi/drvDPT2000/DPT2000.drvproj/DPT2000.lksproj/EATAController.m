/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * EATAController.m - DPT EATA ISA/EISA/PCI SCSI controller.
 *
 * HISTORY
 *
 * Reconstructed from DPTSCSIDriver_reloc.
 */

#import <sys/types.h>
#import <stdio.h>
#import <objc/Object.h>
#import <kernserv/queue.h>
#import <kernserv/prototypes.h>
#import <driverkit/return.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/scsiTypes.h>
#import <bsd/dev/scsireg.h>
#import <mach/message.h>
#import <mach/port.h>
#import <mach/mach_interface.h>
#import <mach/vm_param.h>
#import <machkit/NXLock.h>
#import <string.h>

#import <driverkit/machine/directDevice.h>
#if defined(i386) || defined(__i386__)
#import <driverkit/i386/kernelDriver.h>
#import <driverkit/i386/directDevice.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#else
typedef struct {
	unsigned char bytes[256];
} IOPCIConfigSpace;
@interface IODirectDevice(EATAPCI)
+ (IOReturn)getPCIConfigSpace:(IOPCIConfigSpace *)space
	withDeviceDescription:deviceDescription;
@end
#endif
#import "EATAController.h"
#import "EATAControllerPrivate.h"

#define PCI_NUM_BASE_ADDRESS	6
#define PCI_BASE_IO_BIT		0x01
#define PCI_BASE_IO(value)	((value) & 0xfffffffc)

static int EATAUnitNum;

static msg_header_t cmdMessageTemplate = {
	0,
	1,
	sizeof(msg_header_t),
	MSG_TYPE_NORMAL,
	PORT_NULL,
	PORT_NULL,
	IO_COMMAND_MSG
};

static unsigned int
eata_bswap32(unsigned int x)
{
	return (x << 24) | ((x & 0xff00) << 8) |
	    ((x >> 8) & 0xff00) | (x >> 24);
}

static unsigned short
eata_bswap16(unsigned short x)
{
	return (unsigned short)((x << 8) | (x >> 8));
}

BOOL
parseConfigSpace(id deviceDescription, const char *title,
		unsigned regSize, unsigned short *baseAddr)
{
	IOPCIConfigSpace	configSpace;
	IORange			portRange;
	unsigned		*basePtr;
	int			irq;
	int			i;
	BOOL			foundBase;
	IOReturn		irtn;

	foundBase = NO;
	bzero(&configSpace, sizeof(configSpace));
	irtn = [IODirectDevice getPCIConfigSpace:&configSpace
		withDeviceDescription:deviceDescription];
	if (irtn) {
		IOLog("%s: Can't get configSpace (%s); ABORTING\n",
		    title, [IODirectDevice stringFromReturn:irtn]);
		return NO;
	}

#if defined(i386) || defined(__i386__)
	basePtr = configSpace.BaseAddress;
	irq = configSpace.InterruptLine;
#else
	basePtr = (unsigned *)&configSpace;
	irq = 0;
#endif
	if (basePtr[0] == 0 || irq == 0) {
		IOLog("%s: Bogus config info (IRQ %d, Base 0x%x)\n",
		    title, irq, (unsigned)basePtr);
		return NO;
	}

	for (i = 0; i < PCI_NUM_BASE_ADDRESS; i++) {
		if (basePtr[i] & PCI_BASE_IO_BIT) {
			if (foundBase) {
				IOLog("%s: Multiple I/O Port Bases Found\n",
				    title);
				return NO;
			}
			foundBase = YES;
			portRange.start = PCI_BASE_IO(basePtr[i]);
		}
	}
	if (!foundBase) {
		IOLog("%s: No I/O Port Base Found\n", title);
		return NO;
	}

	portRange.size = regSize;
	*baseAddr = (unsigned short)portRange.start;

	irtn = [deviceDescription setInterruptList:&irq num:1];
	if (irtn) {
		IOLog("%s: Can't set interruptList to IRQ %d (%s)\n",
		    title, irq, [IODirectDevice stringFromReturn:irtn]);
		return NO;
	}
	irtn = [deviceDescription setPortRangeList:&portRange num:1];
	if (irtn) {
		IOLog("%s: Can't set portRangeList to port 0x%x (%s)\n",
		    title, portRange.start,
		    [IODirectDevice stringFromReturn:irtn]);
		return NO;
	}
	return YES;
}


@implementation EATAController

+ (BOOL)probe:deviceDescription
{
	EATAController	*controller;
	id		configTable;
	const char	*cardType;
	unsigned short	port;
	IORange		range;
	unsigned int	slot;
	IOReturn	irtn;
	int		bus;
	BOOL		ok;

	controller = [self alloc];
	configTable = [deviceDescription configTable];
	cardType = [configTable valueForStringKey:"Card Type"];
	if (cardType == NULL) {
		IOLog("DPT2000: No Bus Type in config Table\n");
		[controller free];
		return NO;
	}

	if (strcmp(cardType, "EISA") == 0) {
		[configTable freeString:cardType];
		cardType = NULL;
		irtn = [deviceDescription getEISASlotNumber:&slot];
		if (irtn) {
			IOLog("DPT2000: Can't get slot number (%s)\n",
			    [self stringFromReturn:irtn]);
			[controller free];
			return NO;
		}
		port = (unsigned short)((slot << 12) + EATA_EISA_SLOT_BASE);
		range.start = port;
		range.size = EATA_EISA_PORT_SIZE;
		irtn = [deviceDescription setPortRangeList:&range num:1];
		if (irtn) {
			IOLog("DPT2000: Can't set portRangeList\n");
			[controller free];
			return NO;
		}
		bus = EATA_BUS_EISA;
	} else if (strcmp(cardType, "ISA") == 0) {
		if ([deviceDescription numPortRanges] != 1) {
			IOLog("DPT2000: No I/O Ports Configured\n");
			[configTable freeString:cardType];
			[controller free];
			return NO;
		}
		range = [deviceDescription portRangeList][0];
		port = (unsigned short)range.start;
		bus = EATA_BUS_ISA;
		[configTable freeString:cardType];
		cardType = NULL;
	} else if (strcmp(cardType, "PCI") == 0) {
		bus = EATA_BUS_PCI;
		ok = parseConfigSpace(deviceDescription, "EATAController",
		    EATA_PCI_REGISTER_SPACE, &port);
		if (!ok) {
			[configTable freeString:cardType];
			[controller free];
			return NO;
		}
		port += EATA_PCI_REGISTER_OFFSET;
	} else {
		IOLog("DPT2000: Bad Bus Type (%s) in config table\n",
		    cardType);
		[configTable freeString:cardType];
		[controller free];
		return NO;
	}

	controller->ioBase = port;
	controller->busType = bus;
	if (![controller probeAtPortBase:port]) {
		IOLog("DPT Host Adaptor Not found at Port 0x%x\n", port);
		[controller free];
		return NO;
	}
	return ([controller initFromDeviceDescription:deviceDescription]
	    ? YES : NO);
}

- initFromDeviceDescription:deviceDescription
{
	id		configTable;
	const char	*shareIRQ;
	unsigned	channelCount;
	unsigned	i;
	unsigned	irq;
	char		nameBuf[16];
	char		locBuf[32];

	if ([super initFromDeviceDescription:deviceDescription] == nil)
		return [super free];

	if ([super startIOThread] != IO_R_SUCCESS) {
		IOLog("EATAController: [super startIOThread] failed\n");
		return [super free];
	}

	interruptPortKern = IOConvertPort([self interruptPort],
	    IO_KernelIOTask, IO_Kernel);
	ioThreadRunning = YES;
	queue_init(&outstandingQ);
	queue_init(&commandQ);
	outstandingCount = 0;
	ccbFree = NULL;
	dmaLockCount = 0;
	commandLock = [[NXLock alloc] init];

	[self setUnit:EATAUnitNum];
	sprintf(nameBuf, "DPT_%d", EATAUnitNum);
	EATAUnitNum++;
	[self setName:nameBuf];
	[self setDeviceKind:"EATAController"];
	irq = config.irq;
	sprintf(locBuf, "port 0x%x irq %d", ioBase, irq);
	[self setLocation:locBuf];

	if (config.dma_channel_valid) {
		[self setTransferMode:IO_Cascade forChannel:0];
		if ([self enableChannel:0] != IO_R_SUCCESS)
			return [self free];
	}
	if (![self readDMAConfig]) {
		IOLog("DPT2000: Read DMA Configuration FAILED; Aborting\n");
		return [self free];
	}

	if (config.config_data_len > 0x21)
		channelCount = config.maxChannel + 1;
	else
		channelCount = 1;

	for (i = 0; i < EATA_CHANNEL_COUNT; i++) {
		channelInfo[i].owner = nil;
		channelInfo[i].present = (i < channelCount) ? 1 : 0;
	}

	[self resetStats];
	levelIRQ = 0;
	configTable = [deviceDescription configTable];
	shareIRQ = [configTable valueForStringKey:"Share IRQ Levels"];
	if (shareIRQ) {
		if (strcmp(shareIRQ, "YES") == 0)
			levelIRQ = 1;
		[configTable freeString:shareIRQ];
	}

	[self enableAllInterrupts];
	[self registerDevice];
	return self;
}

- free
{
	EATACommandBuf cmdBuf;

	if (ioThreadRunning) {
		cmdBuf.op = EO_Abort;
		[self executeCmdBuf:&cmdBuf];
	}
	if (commandLock) {
		[commandLock free];
		commandLock = nil;
	}
	return [super free];
}

- (void)interruptOccurred
{
	struct ccb	*ccb;
	struct ccb	*next;

	(void)inb(ioBase + EATA_STATUS_OFF);

	ccb = (struct ccb *)queue_first(&outstandingQ);
	while (!queue_end(&outstandingQ, (queue_entry_t)ccb)) {
		next = (struct ccb *)queue_next(&ccb->ccbQ);
		if ((signed char)ccb->sp.eoc < 0) {
			queue_remove(&outstandingQ, ccb, struct ccb *, ccbQ);
			outstandingCount--;
			[self commandCompleted:ccb reason:CS_Complete];
		}
		ccb = next;
	}

	if (levelIRQ)
		[self enableAllInterrupts];
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
	struct ccb	*ccb;
	struct ccb	*next;
	ns_time_t	now;
	ns_time_t	expire;
	EATACommandBuf	*cmdBuf;
	IOSCSIRequest	*scsiReq;
	BOOL		timedOut;

	timedOut = NO;
	IOGetTimestamp(&now);

	ccb = (struct ccb *)queue_first(&outstandingQ);
	while (!queue_end(&outstandingQ, (queue_entry_t)ccb)) {
		next = (struct ccb *)queue_next(&ccb->ccbQ);
		cmdBuf = (EATACommandBuf *)ccb->cmdBuf;
		scsiReq = cmdBuf->scsiReq;
		memcpy(&expire, ccb->startTime, sizeof(expire));
		expire += 1000000000ULL *
		    (unsigned long long)scsiReq->timeoutLength;
		if (now >= expire) {
			queue_remove(&outstandingQ, ccb, struct ccb *, ccbQ);
			outstandingCount--;
			[self commandCompleted:ccb reason:CS_Timeout];
			timedOut = YES;
		}
		ccb = next;
	}

	if (timedOut)
		[self threadResetBus:NULL initConfig:NO];
}

- (void)commandRequestOccurred
{
	EATACommandBuf *cmdBuf;

	[commandLock lock];
	while (!queue_empty(&commandQ)) {
		cmdBuf = (EATACommandBuf *)queue_first(&commandQ);
		queue_remove(&commandQ, cmdBuf, EATACommandBuf *, link);
		[commandLock unlock];

		switch (cmdBuf->op) {
		    case EO_Reset:
			[self threadResetBus:cmdBuf initConfig:NO];
			break;
		    case EO_Abort:
			[cmdBuf->cmdLock lock];
			[cmdBuf->cmdLock unlockWith:CMD_COMPLETE];
			IOExitThread();
			break;
		    case EO_Execute:
			[self threadExecuteRequest:cmdBuf];
			break;
		    default:
			break;
		}

		[commandLock lock];
	}
	[commandLock unlock];
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

- (void)resetStats
{
	queueLenTotal = 0;
	maxQueueLen = 0;
	totalCommands = 0;
}

- (BOOL)acquireSCSIBus:(unsigned)channel owner:owner
{
	if (channel > 2)
		return NO;
	if (channelInfo[channel].owner != nil)
		return NO;
	if (!channelInfo[channel].present)
		return NO;
	channelInfo[channel].owner = owner;
	return YES;
}

- (void)releaseSCSIBus:(unsigned)channel owner:owner
{
	if (channelInfo[channel].owner == owner)
		channelInfo[channel].owner = nil;
	else
		IOLog("%s releaseSCSIBus: Incorrect Owner\n", [self name]);
}

- (unsigned)maxTransfer
{
	return page_size << 6;
}

- (unsigned)scsiBusId:(unsigned)channel
{
	return config.host_addrs[2 - channel];
}

- (unsigned)numberOfTargets
{
	return config.maxScsiId + 1;
}

- (IOReturn)executeCmdBuf:(EATACommandBuf *)cmdBuf
{
	msg_header_t	msg = cmdMessageTemplate;
	kern_return_t	krtn;
	IOReturn	rtn = IO_R_SUCCESS;

	cmdBuf->cmdLock = [[NXConditionLock alloc] initWith:CMD_PENDING];
	[commandLock lock];
	queue_enter(&commandQ, cmdBuf, EATACommandBuf *, link);
	[commandLock unlock];

	msg.msg_remote_port = interruptPortKern;
	krtn = msg_send_from_kernel(&msg, MSG_OPTION_NONE, 0);
	if (krtn) {
		IOLog("%s: msg_send_from_kernel() returned %d\n",
		    [self name], krtn);
		rtn = IO_R_IPC_FAILURE;
	}

	[cmdBuf->cmdLock lockWhen:CMD_COMPLETE];
	[cmdBuf->cmdLock free];
	return rtn;
}

@end


@implementation EATAController(PrivateMethods)

- (BOOL)probeAtPortBase:(unsigned short)port
{
	ioBase = port;
	[self threadResetBus:NULL initConfig:YES];
	if (![self readConfig])
		return NO;
	/*
	 * dma_ok set and is_ata clear: (flags & 0x50) == 0x10.
	 */
	if (config.dma_ok && !config.is_ata)
		return YES;
	return NO;
}

- (BOOL)readConfig
{
	unsigned short	*wp;
	unsigned	i;
	unsigned char	status;
	int		wait;

	bzero(&config, EATA_CONFIG_SIZE);
	if (eata_busy(ioBase, 0xC350))
		return NO;

	outb(ioBase + EATA_CMD_OFF, EATA_CMD_READ_CONFIG_PIO);

	wait = 0x186A0;
	do {
		status = inb(ioBase + EATA_STATUS_OFF);
		if (status & EATA_STAT_DRQ)
			break;
		wait--;
	} while (wait);

	if ((status & EATA_STAT_DRQ) == 0)
		return NO;

	wp = (unsigned short *)&config;
	for (i = 0; i < (EATA_CONFIG_SIZE / 2); i++)
		wp[i] = inw(ioBase + EATA_DATA_OFF);

	for (i = 0; i < 0xED; i++)
		(void)inw(ioBase + EATA_DATA_OFF);

	config.config_data_len = eata_bswap32(config.config_data_len);
	config.eata_signature = eata_bswap32(config.eata_signature);
	config.command_pad = eata_bswap16(config.command_pad);
	config.command_length = eata_bswap32(config.command_length);
	config.status_length = eata_bswap32(config.status_length);
	config.queue_size = eata_bswap16(config.queue_size);
	config.sg_size = eata_bswap16(config.sg_size);

	if (config.maxScsiId != 7 && config.maxScsiId != 15)
		config.maxScsiId = 7;

	return (config.eata_signature == EATA_SIGNATURE);
}

- (BOOL)readDMAConfig
{
	unsigned char	*buf;
	unsigned int	phys;
	unsigned int	sig;
	unsigned short	sg;
	BOOL		ok;
	unsigned short	port;

	buf = IOMallocLow(EATA_CONFIG_SIZE);
	((unsigned int *)buf)[1] = 0;

	while (eata_busy(ioBase, (int)0xFFFFFFFF))
		;

	port = ioBase;
	if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)buf, &phys)) {
		IOLog("EATA: Can't get physical address\n");
		phys = 0;
	}

	outb(port + EATA_ADDR0_OFF, (unsigned char)phys);
	outb(port + EATA_ADDR1_OFF, (unsigned char)(phys >> 8));
	outb(port + EATA_ADDR2_OFF, (unsigned char)(phys >> 16));
	outb(port + EATA_ADDR3_OFF, (unsigned char)(phys >> 24));
	outb(port + EATA_CMD_OFF, EATA_CMD_READ_CONFIG_DMA);

	while (eata_busy(ioBase, (int)0xFFFFFFFF))
		;

	sig = eata_bswap32(((unsigned int *)buf)[1]);
	sg = eata_bswap16(*(unsigned short *)(buf + 0x1C));
	configSgSize = sg;
	ok = (sig == EATA_SIGNATURE);

	IOFreeLow(buf, EATA_CONFIG_SIZE);
	return ok;
}

@end
