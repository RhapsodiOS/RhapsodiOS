#import "HIM6X60.h"
#import "AIC6X60Inline.h"
#import "AIC6X60ControllerPrivate.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/i386/directDevice.h>
#import <kernserv/ns_timer.h>
#import <mach/message.h>
#import <objc/objc-runtime.h>

/*
 * Sequencer entry points the HIM dispatches. Global C linkage matches
 * the reference (_selection, not static).
 */
extern void selection(struct _HACB *hacb);
extern void reselection(struct _HACB *hacb);
extern void scsiBusFree(struct _HACB *hacb);
extern void scsiBusReset(struct _HACB *hacb);
extern void targetREQuest(struct _HACB *hacb);
extern void updateDataPointer(struct _HACB *hacb);
extern void quiesceDmaAndSCSI(struct _HACB *hacb);
extern void dataInPIO(struct _HACB *hacb);
extern void dataOutPIO(struct _HACB *hacb);

extern int repinsb(IOEISAPortAddress port, unsigned char *addr, int count);

typedef struct {
	unsigned char	busy;
	unsigned char	_pad[3];
	struct _SCB	*queuedScb;
	struct _SCB	*activeScb;
} HIM_LUCB;

static void (*savewatchdog)(void *arg);

msg_header_t timeoutMsgTemplate = {
	0,
	1,
	sizeof(msg_header_t),
	MSG_TYPE_NORMAL,
	PORT_NULL,
	PORT_NULL,
	IO_TIMEOUT_MSG
};

extern unsigned int page_size;
extern unsigned int page_mask;

void memset(void *b, int c, int len);
void himTimeout(struct _SCB *scb);
int HIM6X60FindAdapter(unsigned int ioBase);
int HIM6X60GetStackContents(struct _HACB *hacb, unsigned char *buffer, unsigned short length);
int HIM6X60GetConfiguration(struct _HACB *hacb);
int HIM6X60TerminateSCB(struct _HACB *hacb, struct _SCB *scb, struct _SCB *targetScb);
void initiateIO(struct _HACB *hacb);
int HIM6X60ResetBus(struct _HACB *hacb, int abort);
void HIM6X60DisableINT(struct _HACB *hacb);
int HIM6X60EnableINT(struct _HACB *hacb);
void HIM6X60AssertINT(struct _HACB *hacb);
int HIM6X60IRQ(struct _HACB *hacb);
void deferredIsr(struct _HACB *hacb);
void watchdog(struct _HACB *hacb);
void isr(struct _HACB *hacb);
void HIM6X60DmaProgrammed(struct _HACB *hacb);
void linkScbPreemptive(struct _SCB **head, struct _SCB *scb);
void linkScb(struct _SCB **head, struct _SCB *scb);
int unlinkScb(struct _SCB **head, struct _SCB *scb);
void HIM6X60CompleteSCB(struct _HACB *hacb, struct _SCB *scb);
void HIM6X60Event(struct _HACB *hacb, int event, int extra);
void HIM6X60FlushDMA(struct _HACB *hacb);
HIM_LUCB *HIM6X60GetLUCB(struct _HACB *hacb, int bus, unsigned char target, unsigned char lun);
unsigned int HIM6X60GetPhysicalAddress(struct _HACB *hacb, struct _SCB *scb, unsigned char *virt, unsigned int offset, unsigned int *outLength);
void HIM6X60LogError(struct _HACB *hacb, struct _SCB *scb, int bus, int target, int lun, int code, int extra);
void HIM6X60MapDMA(struct _HACB *hacb, struct _SCB *scb, unsigned char *virt, unsigned int phys, unsigned int length, unsigned char direction);
void HIM6X60Watchdog(struct _HACB *hacb, void (*proc)(void *), unsigned int milliseconds);

#define H8(h, off)	(*((unsigned char *)(h) + (off)))
#define H32(h, off)	(*(unsigned int *)((unsigned char *)(h) + (off)))
#define HP(h, off)	(*(struct _SCB **)((unsigned char *)(h) + (off)))

void
memset(void *b, int c, int len)
{
	unsigned char *p = (unsigned char *)b;

	while (len--)
		*p++ = (unsigned char)c;
}

HIM_LUCB *
HIM6X60GetLUCB(struct _HACB *hacb, int bus, unsigned char target, unsigned char lun)
{
	unsigned int index;

	(void)bus;
	index = lun + ((unsigned int)target << 3);
	index = index + index * 2;
	return (HIM_LUCB *)((unsigned char *)hacb + 0x8c + index * 4);
}

void
HIM6X60CompleteSCB(struct _HACB *hacb, struct _SCB *scb)
{
	(void)hacb;
	scb->completed = 1;
}

void
HIM6X60Event(struct _HACB *hacb, int event, int extra)
{
	(void)hacb;
	(void)event;
	(void)extra;
}

void
linkScbPreemptive(struct _SCB **head, struct _SCB *scb)
{
	scb->chain = *head;
	*head = scb;
}

void
linkScb(struct _SCB **head, struct _SCB *scb)
{
	struct _SCB **p;

	p = head;
	if (*p != 0) {
		p = (struct _SCB **)*p;
		while (*p != 0)
			p = (struct _SCB **)*p;
	}
	scb->chain = *p;
	*p = scb;
}

int
unlinkScb(struct _SCB **head, struct _SCB *scb)
{
	struct _SCB **p;

	p = head;
	if (*p == 0)
		return 0;
	for (;;) {
		if (*p == scb) {
			*p = scb->chain;
			scb->chain = 0;
			return 1;
		}
		p = (struct _SCB **)*p;
		if (*p == 0)
			return 0;
	}
}

void
HIM6X60AssertINT(struct _HACB *hacb)
{
	unsigned char al;

	al = inb(hacb->baseAddress + AIC_DMACNTRL0);
	outb(hacb->baseAddress + AIC_DMACNTRL0, al | AIC_SWINT);
}

void
HIM6X60DisableINT(struct _HACB *hacb)
{
	unsigned int prev;
	unsigned char al;

	prev = hacb->disableINT;
	hacb->disableINT++;
	if (prev == 0) {
		al = inb(hacb->baseAddress + AIC_DMACNTRL0);
		outb(hacb->baseAddress + AIC_DMACNTRL0, al & ~AIC_INTEN);
	}
}

int
HIM6X60EnableINT(struct _HACB *hacb)
{
	unsigned char al;

	if (hacb->disableINT == 0) {
		al = inb(hacb->baseAddress + AIC_DMACNTRL0);
		outb(hacb->baseAddress + AIC_DMACNTRL0, al | AIC_INTEN);
		return 1;
	}
	hacb->disableINT--;
	if (hacb->disableINT != 0)
		return 0;
	al = inb(hacb->baseAddress + AIC_DMACNTRL0);
	outb(hacb->baseAddress + AIC_DMACNTRL0, al | AIC_INTEN);
	return 1;
}

int
HIM6X60ResetBus(struct _HACB *hacb, int abort)
{
	if (abort != 0)
		return 0;
	outb(hacb->baseAddress + AIC_DMACNTRL1, 0);
	outb(hacb->baseAddress + AIC_SCSISEQ, AIC_SCSIRSTO);
	IODelay(25);
	outb(hacb->baseAddress + AIC_SCSISEQ, 0);
	return 1;
}

int
HIM6X60FindAdapter(unsigned int ioBase)
{
	unsigned short dx;
	int found;

	found = 0;
	dx = (unsigned short)ioBase;
	if ((inb(dx) & 0x49) != 0)
		return found;
	if ((inb(dx + AIC_SXFRCTL0) & 0xDF) != 0)
		return found;
	if ((inb(dx + AIC_SXFRCTL1) & 0xC1) != 0)
		return found;
	if ((inb(dx + AIC_SSTAT0) & 0x42) != 0)
		return found;
	if (inb(dx + AIC_SSTAT2) != 0x10)
		return found;
	if (inb(dx + AIC_SSTAT3) != 0)
		return found;
	if ((inb(dx + AIC_DMASTAT) & 0x19) != 0x08)
		return found;
	found = 1;
	return found;
}

int
HIM6X60GetStackContents(struct _HACB *hacb, unsigned char *buffer, unsigned short length)
{
	unsigned short stackSize;
	unsigned int n;
	unsigned char cl;

	memset(buffer, 0, length);
	if (inb(hacb->baseAddress + AIC_REV) != 0)
		stackSize = 0x20;
	else
		stackSize = 0x10;
	if (buffer == 0)
		return stackSize;
	cl = 0;
	if (stackSize != 0x10)
		cl = 0x40;
	outb(hacb->baseAddress + AIC_DMACNTRL1, cl);
	n = stackSize;
	if (stackSize > length)
		n = length;
	repinsb(hacb->baseAddress + AIC_STACK, buffer, (int)n);
	outb(hacb->baseAddress + AIC_DMACNTRL1, 0);
	return stackSize;
}

void
himTimeout(struct _SCB *scb)
{
	msg_header_t msg;
	unsigned char *cdb;

	msg = timeoutMsgTemplate;
	if (scb->in_use == 0 || scb->completed != 0)
		return;
	scb->timedOut = 1;
	msg.msg_remote_port = (port_t)scb->timeout_Port;
	cdb = scb->cdb;
	IOLog("AIC timeout SCB %x %x\n", scb, cdb ? cdb[0] : 0);
	msg_send_from_kernel(&msg, 0, 0);
}

void
HIM6X60LogError(struct _HACB *hacb, struct _SCB *scb, int bus, int target, int lun, int code, int extra)
{
	(void)hacb;
	(void)scb;
	(void)bus;
	(void)target;
	(void)lun;
	IOLog("HIM error error %x %x\n", code, extra);
}

void
HIM6X60Watchdog(struct _HACB *hacb, void (*proc)(void *), unsigned int milliseconds)
{
	ns_time_t nsec;

	if (milliseconds == 0) {
		ns_untimeout((func)savewatchdog, hacb);
		return;
	}
	nsec = (ns_time_t)milliseconds * 1000ULL;
	savewatchdog = proc;
	ns_timeout((func)proc, hacb, nsec, 3);
}

unsigned int
HIM6X60GetPhysicalAddress(struct _HACB *hacb, struct _SCB *scb, unsigned char *virt, unsigned int offset, unsigned int *outLength)
{
	unsigned int phys;
	unsigned int remain;
	AIC6X60CommandBuf *cmd;

	(void)hacb;
	(void)offset;
	cmd = (AIC6X60CommandBuf *)scb->osRequestBlock;
	if (IOPhysicalFromVirtual(cmd->client, (vm_address_t)virt, &phys) != 0)
		IOPanic("AIC: can't get physical address\n");
	remain = (phys + page_mask) & ~page_mask;
	remain -= phys;
	if (remain == 0)
		remain = page_size;
	*outLength = remain;
	return phys;
}

void
HIM6X60FlushDMA(struct _HACB *hacb)
{
	id controller;

	controller = (id)hacb->controllerId;
	objc_msgSend(controller, sel_getUid("disableChannel:"), 0);
	if (*(void **)((unsigned char *)controller + 0x1078) != 0) {
		objc_msgSend(controller, sel_getUid("freeDMABuffer:"),
		    *(void **)((unsigned char *)controller + 0x1078));
		*(void **)((unsigned char *)controller + 0x1078) = 0;
	}
}

void
HIM6X60MapDMA(struct _HACB *hacb, struct _SCB *scb, unsigned char *virt, unsigned int phys, unsigned int length, unsigned char direction)
{
	id controller;
	id buffer;
	IOReturn rtn;
	const char *str;

	(void)scb;
	(void)virt;
	controller = (id)hacb->controllerId;
	buffer = objc_msgSend(controller,
	    sel_getUid("createDMABufferFor:length:read:needsLowMemory:limitSize:"),
	    &phys, length, direction != 0, 1, 0);
	*(id *)((unsigned char *)controller + 0x1078) = buffer;
	if (buffer == 0)
		IOLog("AIC DMA buffer create failed %x %x\n", direction, length);
	rtn = (IOReturn)objc_msgSend(controller, sel_getUid("enableChannel:"), 0);
	if (rtn != 0) {
		str = (const char *)objc_msgSend(controller,
		    sel_getUid("stringFromReturn:"), rtn);
		IOLog("AIC DMA channel enable failed %s\n", str);
	}
	rtn = (IOReturn)objc_msgSend(controller,
	    sel_getUid("startDMAForBuffer:channel:"),
	    *(id *)((unsigned char *)controller + 0x1078), 0);
	if (rtn != 0)
		IOLog("AIC DMA start failed\n");
	HIM6X60DmaProgrammed(hacb);
}

void
HIM6X60DmaProgrammed(struct _HACB *hacb)
{
	unsigned char fifo, s2, s3, count, dmac;

	outb(hacb->baseAddress + AIC_SIMODE0, AIC_DMADONE);
	fifo = inb(hacb->baseAddress + AIC_FIFOSTAT);
	if (fifo != 0) {
		s2 = inb(hacb->baseAddress + AIC_SSTAT2);
		s3 = inb(hacb->baseAddress + AIC_SSTAT3);
		count = fifo + ((s2 & 0x0f) - (s3 & 0x0f));
		if (count != 0)
			outb(hacb->baseAddress + AIC_STCNT0, count);
	}
	dmac = 0xA0;
	if (hacb->dmaChannel == 0)
		dmac = 0xE0;
	if (hacb->scsiPhase == 0)
		dmac |= 0x08;
	if (hacb->disableINT == 0)
		dmac |= AIC_INTEN;
	outb(hacb->baseAddress + AIC_DMACNTRL0, dmac);
	outb(hacb->baseAddress + AIC_SXFRCTL0, 0xE0);
	if (hacb->irqConnected != 0 && hacb->revision == 1)
		HIM6X60Watchdog(hacb, (void (*)(void *))watchdog, 0xC350);
}

int
HIM6X60ISR(struct _HACB *hacb)
{
	unsigned char al;
	unsigned int prev;

	al = inb(hacb->baseAddress + AIC_DMASTAT);
	if ((al & AIC_INTSTAT) == 0)
		return 0;
	hacb->cs |= 0x80;
	prev = hacb->disableINT;
	hacb->disableINT++;
	if (prev == 0) {
		al = inb(hacb->baseAddress + AIC_DMACNTRL0);
		outb(hacb->baseAddress + AIC_DMACNTRL0, al & 0xFA);
	}
	do {
		isr(hacb);
		al = inb(hacb->baseAddress + AIC_DMASTAT);
	} while (al & AIC_INTSTAT);
	if (hacb->disableINT != 0) {
		hacb->disableINT--;
		if (hacb->disableINT != 0)
			goto done;
	}
	al = inb(hacb->baseAddress + AIC_DMACNTRL0);
	outb(hacb->baseAddress + AIC_DMACNTRL0, al | AIC_INTEN);
done:
	hacb->cs &= 0x7F;
	return 1;
}

int
HIM6X60IRQ(struct _HACB *hacb)
{
	unsigned char al;
	unsigned int prev;

	al = inb(hacb->baseAddress + AIC_DMASTAT);
	if ((al & AIC_INTSTAT) == 0)
		return 0;
	hacb->cs |= 0x80;
	prev = hacb->disableINT;
	hacb->disableINT++;
	if (prev == 0) {
		al = inb(hacb->baseAddress + AIC_DMACNTRL0);
		outb(hacb->baseAddress + AIC_DMACNTRL0, al & 0xFA);
	}
	if (hacb->irqConnected == 0) {
		hacb->irqConnected = 1;
		HIM6X60Watchdog(hacb, 0, 0);
	}
	do {
		isr(hacb);
		al = inb(hacb->baseAddress + AIC_DMASTAT);
	} while (al & AIC_INTSTAT);
	if (hacb->disableINT != 0) {
		hacb->disableINT--;
		if (hacb->disableINT != 0)
			goto done;
	}
	al = inb(hacb->baseAddress + AIC_DMACNTRL0);
	outb(hacb->baseAddress + AIC_DMACNTRL0, al | AIC_INTEN);
done:
	hacb->cs &= 0x7F;
	return 1;
}

void
deferredIsr(struct _HACB *hacb)
{
	hacb->cs |= 0x40;
	if (hacb->scsiPhase == 0)
		dataOutPIO(hacb);
	else
		dataInPIO(hacb);
	while (inb(hacb->baseAddress + AIC_DMASTAT) & AIC_INTSTAT)
		isr(hacb);
	hacb->cs &= 0xBF;
	HIM6X60EnableINT(hacb);
}

void
watchdog(struct _HACB *hacb)
{
	unsigned char al;

	if (HIM6X60ISR(hacb)) {
		if (hacb->irqConnected == 0 && hacb->IRQ != 0xFF) {
			hacb->IRQ = 0xFF;
			HIM6X60LogError(hacb, 0, 0, 0, 0, 8, 0);
		}
	} else if (hacb->cs & 0x04) {
		al = inb(hacb->baseAddress + AIC_DMASTAT);
		if ((al & 0x80) != 0 &&
		    (inb(hacb->baseAddress + AIC_SSTAT0) & AIC_DMADONE) == 0) {
			HIM6X60LogError(hacb, HP(hacb, 0x24), 0, hacb->busID,
			    hacb->lun, 0x8001, hacb->scsiPhase);
			al = inb(hacb->baseAddress + AIC_DMACNTRL0);
			outb(hacb->baseAddress + AIC_DMACNTRL0, al & 0x7F);
			al = inb(hacb->baseAddress + AIC_DMACNTRL0);
			outb(hacb->baseAddress + AIC_DMACNTRL0, al | 0x80);
		}
	}
	if ((hacb->cs & 0x04) && hacb->revision == 1)
		HIM6X60Watchdog(hacb, (void (*)(void *))watchdog, 0xC350);
	else if (hacb->irqConnected == 0 &&
	    (hacb->scsiPhase == 0xFF ? hacb->cActiveScb != 0 : 1))
		HIM6X60Watchdog(hacb, (void (*)(void *))watchdog, 0x2710);
}

void
isr(struct _HACB *hacb)
{
	unsigned char al;

	hacb->sStat0 = inb(hacb->baseAddress + AIC_SSTAT0);
	hacb->maskedSStat0 = inb(hacb->baseAddress + AIC_SIMODE0) & hacb->sStat0;
	hacb->sStat1 = inb(hacb->baseAddress + AIC_SSTAT1);
	hacb->maskedSStat1 = inb(hacb->baseAddress + AIC_SIMODE1) & hacb->sStat1;
	al = inb(hacb->baseAddress + AIC_SSTAT4);
	if (al != 0) {
		outb(hacb->baseAddress + AIC_CLRSERR, 7);
		if (HP(hacb, 0x24) != 0)
			HP(hacb, 0x24)->scbStatus = 0x14;
		HIM6X60ResetBus(hacb, 0);
		return;
	}
	if (hacb->maskedSStat1 & 0xA8) {
		scsiBusFree(hacb);
		return;
	}
	if (hacb->maskedSStat0 & AIC_SELINGO) {
		outb(hacb->baseAddress + AIC_CLRSINT1, AIC_BUSFREE);
		outb(hacb->baseAddress + AIC_SIMODE0, 0x60);
		outb(hacb->baseAddress + AIC_SIMODE1, 0xA8);
		return;
	}
	if (hacb->maskedSStat0 & AIC_SELDI) {
		reselection(hacb);
		return;
	}
	if (hacb->maskedSStat0 & AIC_SELDO) {
		selection(hacb);
		return;
	}
	if (hacb->cs & 0x04)
		quiesceDmaAndSCSI(hacb);
	if ((inb(hacb->baseAddress + AIC_SSTAT1) & AIC_REQINIT) == 0) {
		al = inb(hacb->baseAddress + AIC_SIMODE1);
		outb(hacb->baseAddress + AIC_SIMODE1, al | AIC_REQINIT);
		return;
	}
	if ((hacb->scsiPhase & 0xA0) == 0)
		updateDataPointer(hacb);
	targetREQuest(hacb);
}

void
initiateIO(struct _HACB *hacb)
{
	struct _SCB *scb;
	unsigned char id;

	if (hacb->resetScb != 0 && hacb->cActiveScb == 0) {
		HIM6X60ResetBus(hacb, 0);
		return;
	}
	if (hacb->busID != 0xFF)
		return;
	if (hacb->eligibleScb == 0)
		return;
	scb = hacb->eligibleScb;
	HP(hacb, 0x24) = scb;
	hacb->busID = scb->targetID;
	hacb->lun = scb->lun;
	if (hacb->disableINT == 0)
		outb(hacb->baseAddress + AIC_DMACNTRL0, AIC_INTEN);
	outb(hacb->baseAddress + AIC_DMACNTRL1, 0);
	outb(hacb->baseAddress + AIC_SXFRCTL1, hacb->sXfrCtl1Image);
	outb(hacb->baseAddress + AIC_SIMODE0, 0x70);
	outb(hacb->baseAddress + AIC_SIMODE1, 0xA0);
	id = (hacb->ownID << 4) | hacb->busID;
	outb(hacb->baseAddress + 0x05, id);
	outb(hacb->baseAddress + AIC_SCSISEQ, 0x58);
	if (hacb->irqConnected == 0)
		HIM6X60Watchdog(hacb, (void (*)(void *))watchdog, 0x2710);
}

int
HIM6X60QueueSCB(struct _HACB *hacb, struct _SCB *scb)
{
	HIM_LUCB *lucb;
	struct _SCB *next;
	unsigned int phys;
	unsigned char t, l;

	if (scb->length <= 0x53) {
		scb->scbStatus = 0x15;
		return scb->scbStatus;
	}
	if (scb->function != 0 && scb->function != 0x13 &&
	    scb->function != 0x11 && scb->function != 0x14) {
		if (scb->function == 0x12) {
			linkScb(&hacb->resetScb, scb);
			goto done;
		}
		if (scb->function == 0x81) {
			hacb->cs |= 0x20;
			if (hacb->cActiveScb == 0) {
				scb->scbStatus = 1;
				goto done_status;
			}
			scb->scbStatus = 0;
			linkScb(&hacb->queueFreezeScb, scb);
			goto done;
		}
		if (scb->function == 0x82) {
			while (hacb->queueFreezeScb != 0) {
				struct _SCB *fr = hacb->queueFreezeScb;
				unlinkScb(&hacb->queueFreezeScb, fr);
				fr->scbStatus = 1;
				HIM6X60CompleteSCB(hacb, fr);
			}
			hacb->cs &= 0xDF;
			for (t = 0; t <= 7; t++) {
				if (t == hacb->ownID)
					continue;
				for (l = 0; l <= 7; l++) {
					lucb = HIM6X60GetLUCB(hacb, 0, t, l);
					if (lucb == 0 || lucb->queuedScb == 0)
						continue;
					next = lucb->queuedScb;
					lucb->busy = 1;
					unlinkScb(&lucb->queuedScb, next);
					hacb->cQueuedScb--;
					linkScb(&hacb->eligibleScb, next);
					hacb->cActiveScb++;
					initiateIO(hacb);
				}
			}
			scb->scbStatus = 1;
			goto done;
		}
		goto done;
	}
	scb->transferResidual = scb->dataLength;
	lucb = HIM6X60GetLUCB(hacb, 0, scb->targetID, scb->lun);
	if (lucb == 0)
		return 0;
	if (scb->function == 0 && (scb->flags & 0xC0) != 0) {
		if ((hacb->ac & 0x40) != 0 && (short)scb->flags >= 0) {
			phys = HIM6X60GetPhysicalAddress(hacb, scb,
			    scb->dataPointer, 0, &scb->segmentLength);
			scb->segmentAddress = phys;
			if (scb->dataLength < scb->segmentLength)
				scb->segmentLength = scb->dataLength;
		} else if (scb->flags & 0x4000) {
			if (scb->dataLength < scb->segmentLength)
				scb->segmentLength = scb->dataLength;
		} else
			scb->segmentLength = scb->dataLength;
	}
	if (hacb->resetScb != 0) {
		linkScb(&hacb->deferredScb, scb);
		goto done;
	}
	if ((hacb->cs & 0x20) == 0) {
		if (lucb->busy == 0) {
			lucb->busy = 1;
			linkScb(&hacb->eligibleScb, scb);
			hacb->cActiveScb++;
			initiateIO(hacb);
			goto done;
		}
	}
	linkScb(&lucb->queuedScb, scb);
	hacb->cQueuedScb++;
done:
	return scb->scbStatus;
done_status:
	return scb->scbStatus;
}

int
HIM6X60AbortSCB(struct _HACB *hacb, struct _SCB *scb, struct _SCB *targetScb)
{
	HIM_LUCB *lucb;
	struct _SCB *next;

	if (scb->length <= 0x53) {
		scb->scbStatus = 0x15;
		return scb->scbStatus;
	}
	lucb = HIM6X60GetLUCB(hacb, 0, scb->targetID, scb->lun);
	if (lucb == 0)
		goto not_found;
	if (HP(hacb, 0x24) == targetScb) {
		targetScb->linkedScb = scb;
		if (targetScb->scbStatus == 0)
			targetScb->function = 0x10;
		else
			HIM6X60ResetBus(hacb, 0);
		goto complete_if;
	}
	if (lucb->activeScb == targetScb) {
		if (targetScb->scbStatus != 0)
			goto not_found;
		targetScb->function = 0x10;
		targetScb->linkedScb = scb;
		linkScbPreemptive(&hacb->eligibleScb, targetScb);
		initiateIO(hacb);
		goto complete_if;
	}
	if (unlinkScb(&hacb->eligibleScb, targetScb)) {
		hacb->cActiveScb--;
		targetScb->scbStatus = 2;
		lucb->activeScb = 0;
		if (lucb->queuedScb != 0) {
			if (hacb->cs & 0x20)
				lucb->busy = 0;
			else {
				lucb->busy = 1;
				next = lucb->queuedScb;
				unlinkScb(&lucb->queuedScb, next);
				hacb->cQueuedScb--;
				linkScb(&hacb->eligibleScb, next);
				hacb->cActiveScb++;
			}
		}
		goto complete_if;
	}
	if (unlinkScb(&lucb->queuedScb, targetScb)) {
		hacb->cQueuedScb--;
		targetScb->scbStatus = 2;
		goto complete_if;
	}
	targetScb = 0;
not_found:
	scb->scbStatus = 3;
complete_if:
	if (targetScb != 0 && targetScb->scbStatus == 2)
		HIM6X60CompleteSCB(hacb, targetScb);
	scb->scbStatus = 1;
	return scb->scbStatus;
}

int
HIM6X60TerminateSCB(struct _HACB *hacb, struct _SCB *scb, struct _SCB *targetScb)
{
	HIM_LUCB *lucb;
	struct _SCB *next;

	if (scb->length <= 0x53) {
		scb->scbStatus = 0x15;
		return scb->scbStatus;
	}
	lucb = HIM6X60GetLUCB(hacb, 0, scb->targetID, scb->lun);
	if (lucb == 0)
		goto not_found;
	if (HP(hacb, 0x24) == targetScb) {
		targetScb->linkedScb = scb;
		if (targetScb->scbStatus == 0)
			targetScb->function = 0x14;
		else
			HIM6X60ResetBus(hacb, 0);
		goto complete_if;
	}
	if (lucb->activeScb == targetScb) {
		if (targetScb->scbStatus != 0)
			goto not_found;
		targetScb->function = 0x14;
		targetScb->linkedScb = scb;
		linkScbPreemptive(&hacb->eligibleScb, targetScb);
		initiateIO(hacb);
		goto complete_if;
	}
	if (unlinkScb(&hacb->eligibleScb, targetScb)) {
		hacb->cActiveScb--;
		targetScb->scbStatus = 0x24;
		lucb->activeScb = 0;
		if (lucb->queuedScb != 0) {
			if (hacb->cs & 0x20)
				lucb->busy = 0;
			else {
				lucb->busy = 1;
				next = lucb->queuedScb;
				unlinkScb(&lucb->queuedScb, next);
				hacb->cQueuedScb--;
				linkScb(&hacb->eligibleScb, next);
				hacb->cActiveScb++;
			}
		}
		goto complete_if;
	}
	if (unlinkScb(&lucb->queuedScb, targetScb)) {
		hacb->cQueuedScb--;
		targetScb->scbStatus = 0x24;
		goto complete_if;
	}
	targetScb = 0;
not_found:
	scb->scbStatus = 0x25;
complete_if:
	if (targetScb != 0 && targetScb->scbStatus == 0x24)
		HIM6X60CompleteSCB(hacb, targetScb);
	scb->scbStatus = 1;
	return scb->scbStatus;
}

int
HIM6X60GetConfiguration(struct _HACB *hacb)
{
	unsigned int sig;
	unsigned char porta, portb, rev, cl, stack;
	unsigned char checksum;
	unsigned int i;
	unsigned char start;

	if (hacb->length <= 0x38F)
		return 0;
	if (HIM6X60FindAdapter(hacb->baseAddress) == 0)
		return 0;
	outb(hacb->baseAddress + AIC_DMACNTRL1, 0);
	sig = inb(hacb->baseAddress + AIC_STACK);
	hacb->signature = sig;
	if ((sig + 0xFFFFFFAE) <= 1) {
		checksum = (unsigned char)hacb->signature;
		outb(hacb->baseAddress + AIC_DMACNTRL1, 0x41);
		for (i = 1; i <= 0x1F; i++) {
			if (i <= 2 || (i - 0x0C) <= 3 || i <= 0x11) {
				stack = inb(hacb->baseAddress + AIC_STACK);
				(void)stack;
			} else
				checksum += inb(hacb->baseAddress + AIC_STACK);
		}
		if (checksum == 0xFF)
			outb(hacb->baseAddress + AIC_DMACNTRL1, 1);
	} else if (hacb->signature == 0x55) {
		sig = inb(hacb->baseAddress + AIC_STACK);
		hacb->signature = (sig << 8) | 0x55;
	} else if (hacb->signature == 0) {
		sig = inb(hacb->baseAddress + AIC_STACK);
		hacb->signature = sig << 8;
		sig = inb(hacb->baseAddress + AIC_STACK);
		hacb->signature |= sig << 16;
		sig = inb(hacb->baseAddress + AIC_STACK);
		hacb->signature |= sig << 24;
		if (hacb->signature == 0x03020100) {
			if (inb(hacb->baseAddress + AIC_STACK) != 4 ||
			    inb(hacb->baseAddress + AIC_STACK) != 5 ||
			    inb(hacb->baseAddress + AIC_STACK) != 6 ||
			    inb(hacb->baseAddress + AIC_STACK) != 7)
				hacb->signature = 0;
		}
	} else
		hacb->signature = 0;

	sig = hacb->signature;
	if ((sig + 0xFFFFFFAE) > 1 && sig != 0x54 && sig != 0xAA55) {
		porta = inb(hacb->baseAddress + AIC_PORTA);
		portb = inb(hacb->baseAddress + AIC_PORTB);
		cl = porta;
		if (portb == 0xFF) {
			hacb->ac |= 0x02;
			hacb->ownID = 7;
			hacb->IRQ = 0x0B;
			hacb->dmaChannel = 0;
			hacb->ac |= 0x10;
			rev = inb(hacb->baseAddress + AIC_REV);
			hacb->revision = rev;
			hacb->ac = (hacb->ac & 0xFE) | (rev != 0);
			hacb->ac = (hacb->ac & 0xF7) | 0x20;
			hacb->ac &= 0xBF;
			goto defaults;
		}
		hacb->ownID = cl & 7;
		hacb->IRQ = ((cl & 0x18) >> 3) + 9;
		hacb->dmaChannel = (cl & 0x60) >> 5;
		if (hacb->dmaChannel != 0)
			hacb->dmaChannel += 4;
		hacb->ac = (hacb->ac & 0xEF) | (((cl >> 7) ^ 1) << 4);
		rev = inb(hacb->baseAddress + AIC_REV);
		hacb->revision = rev;
		if (rev == 0)
			hacb->ac &= 0xFE;
		else if (hacb->signature == 0x52)
			;
		else if (hacb->signature == 0)
			hacb->ac = (hacb->ac & 0xFE) | ((portb >> 4) & 1);
		else
			hacb->ac = (hacb->ac & 0xFE) | (portb & 1);
		hacb->ac = (hacb->ac & 0xF7) | (((~(portb >> 2)) & 1) << 3);
		hacb->ac = (hacb->ac & 0xDF) | ((portb << 2) & 0x20);
		{
			unsigned int edx = 0;
			if ((char)portb < 0 && hacb->revision == 0 &&
			    hacb->dmaChannel == 0)
				edx = 1;
			hacb->ac = (hacb->ac & 0xBF) | (edx << 6);
		}
	} else {
		porta = inb(hacb->baseAddress + AIC_STACK);
		(void)porta;
	}

defaults:
	hacb->scsiPhase = 0xFF;
	hacb->lun = 0xFF;
	hacb->busID = 0xFF;
	hacb->ac |= 0x80;
	hacb->clockPeriod = 0x32;
	hacb->negotiateSDTR = (hacb->ac & 0x20) ? 0xFF : 0;
	hacb->sdtrMsg.extMsgCode = 1;
	hacb->sdtrMsg.extMsgLength = 3;
	hacb->sdtrMsg.extMsgType = 1;
	if (hacb->ac & 1)
		hacb->sdtrMsg.transferPeriod = (hacb->clockPeriod >> 1) & 0x7F;
	else
		hacb->sdtrMsg.transferPeriod = hacb->clockPeriod;
	hacb->sdtrMsg.reqAckOffset = 8;
	hacb->requestSenseCdb[0] = 3;
	hacb->selectTimeLimit = 0x100;
	hacb->dmaBusOnTime = 0x0F;
	hacb->dmaBusOffTime = 1;

	sig = hacb->signature;
	if ((sig + 0xFFFFFFAE) <= 1 || sig == 0x54 || sig == 0xAA55) {
		start = (sig == 0xAA55) ? 3 : 2;
		for (i = 0; i <= 7; i++) {
			if (i == hacb->ownID)
				continue;
			outb(hacb->baseAddress + AIC_DMACNTRL1,
			    ((hacb->ownID - i) & 7) + start);
			stack = inb(hacb->baseAddress + AIC_STACK);
			if (stack == 0x80) {
				hacb->negotiateSDTR &= ~(1u << i);
				continue;
			}
			if ((char)stack < 0) {
				hacb->negotiateSDTR &= ~(1u << i);
				hacb->syncCycles[i] = ((stack & 0x70) >> 4) + 2;
				hacb->syncOffset[i] = stack & 0x0F;
			}
		}
	} else if (sig == 0x03020100) {
		outb(hacb->baseAddress + AIC_DMACNTRL1, 8);
		for (i = 0; i <= 7; i++) {
			stack = inb(hacb->baseAddress + AIC_STACK);
			if (stack == 0x80) {
				hacb->negotiateSDTR &= ~(1u << i);
				continue;
			}
			if ((char)stack < 0) {
				hacb->negotiateSDTR &= ~(1u << i);
				hacb->syncCycles[i] = ((stack & 0x70) >> 4) + 2;
				hacb->syncOffset[i] = stack & 0x0F;
			}
		}
		outb(hacb->baseAddress + AIC_DMACNTRL1, 0);
	} else
		hacb->ac |= 0x04;
	return 1;
}

int
HIM6X60Initialize(struct _HACB *hacb)
{
	unsigned int bit, ecx, esi;
	unsigned char cl, rev;
	unsigned short sel;
	unsigned int wrote, readb;
	unsigned short p0, p1, p2;
	unsigned char b0, b1, b2;

	outb(hacb->baseAddress + AIC_DMACNTRL1, 0);
	rev = inb(hacb->baseAddress + AIC_REV);
	hacb->revision = rev;
	if (rev != 0)
		ecx = hacb->ac & 1;
	else
		ecx = 0;
	hacb->ac = (hacb->ac & 0xFE) | (unsigned char)ecx;
	if ((signed char)hacb->ac >= 0) {
		hacb->ac &= 0xDF;
		ecx = (hacb->ac >> 2) & 1;
		if (hacb->negotiateSDTR != 0xFF)
			ecx |= 1;
		hacb->ac = (hacb->ac & 0xFB) | ((unsigned char)ecx << 2);
	} else if ((hacb->ac & 0x20) == 0)
		hacb->negotiateSDTR = 0;
	esi = (hacb->ac >> 6) & 1;
	ecx = 0;
	if (hacb->revision == 0 && hacb->dmaChannel != 0)
		ecx = 1;
	hacb->ac = (hacb->ac & 0xBF) | ((unsigned char)((esi & ecx) << 6));
	if (hacb->ac & 1)
		cl = (hacb->clockPeriod >> 1) & 0x7F;
	else
		cl = hacb->clockPeriod;
	hacb->sdtrMsg.transferPeriod = cl;
	sel = (unsigned short)((hacb->selectTimeLimit + 0x1F) & 0xFFE0);
	hacb->selectTimeLimit = sel;
	if (sel == 0x20)
		hacb->sXfrCtl1Image = 0x1C;
	else if (hacb->selectTimeLimit == 0x40)
		hacb->sXfrCtl1Image = 0x14;
	else if (hacb->selectTimeLimit == 0x80)
		hacb->sXfrCtl1Image = 0x0C;
	else {
		hacb->selectTimeLimit = 0x100;
		hacb->sXfrCtl1Image = 4;
	}
	if (hacb->dmaBusOnTime > 0x0F)
		hacb->dmaBusOnTime = 0x0F;
	if (hacb->dmaBusOffTime > 0x0F)
		hacb->dmaBusOffTime = 0x0F;
	outb(hacb->baseAddress + AIC_SCSISEQ, 0);
	outb(hacb->baseAddress + AIC_SXFRCTL0, 0x12);
	outb(hacb->baseAddress + AIC_SXFRCTL0, 0x20);
	if (hacb->ac & 0x10)
		hacb->sXfrCtl1Image |= AIC_ENSPCHK;
	outb(hacb->baseAddress + AIC_SXFRCTL1, hacb->sXfrCtl1Image);
	outb(hacb->baseAddress + AIC_SCSISIG, 0);
	outb(hacb->baseAddress + AIC_SCSIRATE, 0);
	outb(hacb->baseAddress + AIC_SCSIDAT, 0);
	outb(hacb->baseAddress + 0x05, hacb->ownID << 4);
	outb(hacb->baseAddress + AIC_CLRSINT0, 0x7F);
	outb(hacb->baseAddress + AIC_CLRSINT1, 0xFF);
	outb(hacb->baseAddress + AIC_CLRSERR, 7);
	outb(hacb->baseAddress + AIC_SIMODE0, 0);
	outb(hacb->baseAddress + AIC_SIMODE1, 0);
	outb(hacb->baseAddress + AIC_DMACNTRL0, AIC_RSTFIFO);
	outb(hacb->baseAddress + AIC_DMADATA32,
	    (hacb->dmaBusOnTime << 4) | hacb->dmaBusOffTime);
	if (inb(hacb->baseAddress + AIC_DMASTAT) & AIC_INTSTAT)
		return 0;
	p0 = hacb->baseAddress + AIC_STCNT0;
	p1 = hacb->baseAddress + AIC_STCNT1;
	p2 = hacb->baseAddress + 0x0A;
	for (esi = 0; esi <= 0xFFFFFF; esi += 0x333333) {
		cl = (unsigned char)esi;
		outb(p0, cl);
		outb(p1, cl);
		outb(p2, cl);
		b0 = inb(p0);
		b1 = inb(p1);
		b2 = inb(p2);
		wrote = (unsigned int)b0 | ((unsigned int)b1 << 8) |
		    ((unsigned int)b2 << 16);
		readb = esi;
		if (readb != wrote)
			return 0;
	}
	if ((hacb->ac & 0x04) == 0) {
		if (inb(hacb->baseAddress + AIC_SCSISIG) == 0)
			goto ok;
		outb(hacb->baseAddress + AIC_SIMODE1, AIC_SCSIRSTI);
		outb(hacb->baseAddress + AIC_SCSISEQ, AIC_SCSIRSTO);
		IODelay(25);
		outb(hacb->baseAddress + AIC_SCSISEQ, 0);
		if (HIM6X60ISR(hacb) == 0)
			return 0;
		if ((hacb->sStat1 & AIC_SCSIRSTI) == 0)
			return 0;
	}
ok:
	outb(hacb->baseAddress + AIC_SCSISEQ, AIC_ENRESELI);
	outb(hacb->baseAddress + AIC_SIMODE0, AIC_SELDI);
	outb(hacb->baseAddress + AIC_SIMODE1, AIC_SELDI);
	outb(hacb->baseAddress + AIC_DMACNTRL0, AIC_INTEN);
	outb(hacb->baseAddress + AIC_DMACNTRL1, 0x80);
	return 1;
}
