#import "HIM6X60.h"
#import "AIC6X60Inline.h"
#import "AIC6X60ControllerPrivate.h"
#import <driverkit/generalFuncs.h>

/*
 * HIM helpers this translation unit calls. Global C linkage.
 */
extern HIM_LUCB *HIM6X60GetLUCB(struct _HACB *hacb, int bus, unsigned char target, unsigned char lun);
extern void HIM6X60CompleteSCB(struct _HACB *hacb, struct _SCB *scb);
extern void HIM6X60Event(struct _HACB *hacb, int event, int extra);
extern void HIM6X60FlushDMA(struct _HACB *hacb);
extern void HIM6X60LogError(struct _HACB *hacb, struct _SCB *scb, int bus, int target, int lun, int code, int extra);
extern void HIM6X60Watchdog(struct _HACB *hacb, void (*proc)(void *), unsigned int milliseconds);
extern int HIM6X60ResetBus(struct _HACB *hacb, int abort);
extern void HIM6X60MapDMA(struct _HACB *hacb, struct _SCB *scb, unsigned char *virt, unsigned int phys, unsigned int length, unsigned char direction);
extern unsigned int HIM6X60GetPhysicalAddress(struct _HACB *hacb, struct _SCB *scb, unsigned char *virt, unsigned int offset, unsigned int *outLength);
extern void initiateIO(struct _HACB *hacb);
extern void linkScb(struct _SCB **head, struct _SCB *scb);
extern void linkScbPreemptive(struct _SCB **head, struct _SCB *scb);
extern int unlinkScb(struct _SCB **head, struct _SCB *scb);
extern void deferredIsr(struct _HACB *hacb);
extern void memset(void *b, int c, int len);
extern int memcmp(const void *s1, const void *s2, unsigned int n);
extern void *memcpy(void *dst, const void *src, unsigned int n);

extern int repinsb(IOEISAPortAddress port, unsigned char *addr, int count);
extern int repinsw(IOEISAPortAddress port, unsigned short *addr, int count);
extern int repinsd(IOEISAPortAddress port, unsigned long *addr, int count);
extern int repoutsb(IOEISAPortAddress port, unsigned char *addr, int count);
extern int repoutsw(IOEISAPortAddress port, unsigned short *addr, int count);
extern int repoutsd(IOEISAPortAddress port, unsigned long *addr, int count);

void selection(struct _HACB *hacb);
void reselection(struct _HACB *hacb);
void scsiBusFree(struct _HACB *hacb);
void scsiBusReset(struct _HACB *hacb);
void targetREQuest(struct _HACB *hacb);
int samePhaseREQuest(struct _HACB *hacb, unsigned char wait);
void interpretMessageIn(struct _HACB *hacb);
void prepareMessageOut(struct _HACB *hacb, unsigned char msg);
void negotiateSDTR(struct _HACB *hacb);
void updateSDTR(struct _HACB *hacb, unsigned int target, unsigned char cycles, unsigned char offset, unsigned char persist);
void resetSDTR(struct _HACB *hacb, unsigned int target);
void dataInPIO(struct _HACB *hacb);
void dataOutPIO(struct _HACB *hacb);
void dataPhaseDMA(struct _HACB *hacb);
void quiesceDmaAndSCSI(struct _HACB *hacb);
void updateDataPointer(struct _HACB *hacb);
void bitbucketAndABORT(struct _HACB *hacb, unsigned char status);

#define H8(h, off)	(*((unsigned char *)(h) + (off)))
#define H32(h, off)	(*(unsigned int *)((unsigned char *)(h) + (off)))
#define HP(h, off)	(*(struct _SCB **)((unsigned char *)(h) + (off)))

void
prepareMessageOut(struct _HACB *hacb, unsigned char msg)
{
	unsigned char al;

	H8(hacb, 0x3C) = 1;
	H8(hacb, 0x3D) = msg;
	al = inb(hacb->baseAddress + AIC_SCSISIG);
	outb(hacb->baseAddress + AIC_SCSISIG, (al & 0xE0) | 0x10);
}

void
bitbucketAndABORT(struct _HACB *hacb, unsigned char status)
{
	if (status != 0 && HP(hacb, 0x24) != 0) {
		HP(hacb, 0x24)->scbStatus = status;
		hacb->cs |= 0x01;
	}
	prepareMessageOut(hacb, 6);
	outb(hacb->baseAddress + AIC_SXFRCTL1, hacb->sXfrCtl1Image | AIC_BITBUCKET);
}

int
samePhaseREQuest(struct _HACB *hacb, unsigned char wait)
{
	unsigned short i;
	unsigned char al;

	i = 0;
	for (;;) {
		al = inb(hacb->baseAddress + AIC_DMASTAT);
		if (al & AIC_INTSTAT)
			break;
		al = inb(hacb->baseAddress + AIC_SSTAT0);
		if (al & AIC_SPIORDY)
			break;
		if (wait != 0)
			break;
		i++;
		if (i == 0xFFFF) {
			HIM6X60LogError(hacb, HP(hacb, 0x24), 0, hacb->busID,
			    hacb->lun, 4, hacb->scsiPhase);
			if (HP(hacb, 0x24) != 0)
				HP(hacb, 0x24)->scbStatus = 9;
			HIM6X60ResetBus(hacb, 0);
			return 0;
		}
	}
	al = inb(hacb->baseAddress + AIC_DMASTAT);
	return ((~al) >> 5) & 1;
}

void
selection(struct _HACB *hacb)
{
	struct _SCB *scb;
	HIM_LUCB *lucb;
	unsigned char target;
	unsigned char rate;

	target = hacb->busID;
	scb = HP(hacb, 0x24);
	H8(hacb, 0x3C) = 1;
	if (scb == 0) {
		H8(hacb, 0x3D) = 0x0C;
		goto program;
	}
	unlinkScb(&hacb->eligibleScb, scb);
	H8(hacb, 0x4C) = 0xFF;
	lucb = HIM6X60GetLUCB(hacb, 0, scb->targetID, scb->lun);
	lucb->activeScb = scb;
	H32(hacb, 0x28) = (unsigned int)scb->dataPointer;
	H32(hacb, 0x2C) = scb->dataLength;
	H32(hacb, 0x38) = scb->dataOffset;
	H32(hacb, 0x30) = scb->segmentAddress;
	H32(hacb, 0x34) = scb->segmentLength;
	if (scb->function == 0x13)
		H8(hacb, 0x3D) = 0x0C;
	else if (hacb->ac & 0x08)
		H8(hacb, 0x3D) = scb->lun | 0x80;
	else if (scb->flags & 0x04)
		H8(hacb, 0x3D) = scb->lun | 0x80;
	else
		H8(hacb, 0x3D) = scb->lun | 0xC0;
	if (scb->function == 0x10) {
		H8(hacb, 0x3D + H8(hacb, 0x3C)) = 6;
		H8(hacb, 0x3C)++;
		goto program;
	}
	if (scb->function == 0x14) {
		H8(hacb, 0x3D + H8(hacb, 0x3C)) = 0x11;
		H8(hacb, 0x3C)++;
		goto program;
	}
	if (scb->function == 0x11) {
		H8(hacb, 0x3D + H8(hacb, 0x3C)) = 0x10;
		H8(hacb, 0x3C)++;
		goto program;
	}
	if ((hacb->negotiateSDTR & (1u << target)) && (scb->flags & 0x08) == 0) {
		unsigned char n = H8(hacb, 0x3C);
		*(unsigned int *)((unsigned char *)hacb + 0x3D + n) =
		    *(unsigned int *)&hacb->sdtrMsg;
		H8(hacb, 0x3D + n + 4) = hacb->sdtrMsg.reqAckOffset;
		H8(hacb, 0x3C) += 5;
	}
program:
	outb(hacb->baseAddress + AIC_CLRSINT1, AIC_BUSFREE);
	outb(hacb->baseAddress + AIC_SCSISEQ, AIC_ENAUTOATNP);
	outb(hacb->baseAddress + AIC_SIMODE0, 0);
	outb(hacb->baseAddress + AIC_SIMODE1, 0x29);
	if (hacb->syncOffset[target] != 0)
		rate = ((hacb->syncCycles[target] + 0xFE) << 4) |
		    hacb->syncOffset[target];
	else
		rate = 0;
	outb(hacb->baseAddress + AIC_SCSIRATE, rate);
}

void
reselection(struct _HACB *hacb)
{
	unsigned char selid, ownbit, id, rate;

	if (HP(hacb, 0x24) != 0) {
		HP(hacb, 0x24) = 0;
		hacb->lun = 0xFF;
		hacb->busID = 0xFF;
	}
	selid = inb(hacb->baseAddress + 0x05);
	ownbit = (unsigned char)(1u << hacb->ownID);
	selid ^= ownbit;
	id = 0xFF;
	if (selid != 0) {
		id = 0;
		while ((selid & 1) == 0) {
			selid >>= 1;
			id++;
			if (selid == 0)
				break;
		}
		if ((selid & 1) && selid != 1)
			id = 0xFF;
	}
	if (id == 0xFF) {
		HIM6X60LogError(hacb, 0, 0, 0xFF, 0xFF, 6, 0);
		HIM6X60ResetBus(hacb, 0);
		return;
	}
	hacb->busID = id;
	H8(hacb, 0x4C) = 0xFF;
	outb(hacb->baseAddress + AIC_SCSISEQ, AIC_ENAUTOATNP);
	outb(hacb->baseAddress + AIC_CLRSINT0, AIC_SELDI);
	outb(hacb->baseAddress + AIC_CLRSINT1, AIC_BUSFREE);
	outb(hacb->baseAddress + AIC_SIMODE0, 0);
	outb(hacb->baseAddress + AIC_SIMODE1, 0x29);
	if (hacb->syncOffset[id] != 0)
		rate = ((hacb->syncCycles[id] + 0xFE) << 4) | hacb->syncOffset[id];
	else
		rate = 0;
	outb(hacb->baseAddress + AIC_SCSIRATE, rate);
}

void
updateSDTR(struct _HACB *hacb, unsigned int target, unsigned char cycles, unsigned char offset, unsigned char persist)
{
	unsigned char slot, rate;

	hacb->syncCycles[target] = cycles;
	hacb->syncOffset[target] = offset;
	if (persist != 0)
		hacb->negotiateSDTR &= ~(1u << hacb->busID);
	slot = 0;
	if ((hacb->signature + 0xFFFFFFAD) <= 1)
		slot = ((hacb->ownID - (unsigned char)target) & 7) + 2;
	else if (hacb->signature == 0xAA55)
		slot = ((hacb->ownID - (unsigned char)target) & 7) + 3;
	else if (hacb->signature == 0x03020100)
		slot = (unsigned char)target + 8;
	if (offset != 0)
		rate = ((cycles + 0xFE) << 4) | offset;
	else
		rate = 0;
	outb(hacb->baseAddress + AIC_SCSIRATE, rate);
	if (slot != 0) {
		outb(hacb->baseAddress + AIC_DMACNTRL1, slot);
		if (offset != 0)
			outb(hacb->baseAddress + AIC_STACK,
			    ((cycles + 0xFE) << 4) | offset | 0x80);
		else
			outb(hacb->baseAddress + AIC_STACK, 0x80);
	}
}

void
negotiateSDTR(struct _HACB *hacb)
{
	unsigned int target;
	unsigned int period, clock;
	int cycles;
	unsigned char offset;

	target = hacb->busID;
	hacb->negotiateSDTR |= (unsigned char)(1u << target);
	if (H8(hacb, 0x49) == 0) {
		updateSDTR(hacb, target, 0, 0, 1);
		return;
	}
	clock = hacb->clockPeriod;
	cycles = (int)(clock + H8(hacb, 0x48) * 4 - 1) / (int)clock;
	if (cycles > 9) {
		prepareMessageOut(hacb, 7);
		updateSDTR(hacb, target, 0, 0, 1);
	} else {
		unsigned char periodByte = H8(hacb, 0x48);
		if (hacb->sdtrMsg.transferPeriod < periodByte)
			periodByte = hacb->sdtrMsg.transferPeriod;
		cycles = (int)(clock + periodByte * 4 - 1) / (int)clock;
		offset = H8(hacb, 0x49);
		if (hacb->sdtrMsg.reqAckOffset < offset)
			offset = hacb->sdtrMsg.reqAckOffset;
		updateSDTR(hacb, target, (unsigned char)cycles, offset, 0);
		if (memcmp((unsigned char *)hacb + 0x3D,
		    &hacb->sdtrMsg, 3) == 0)
			hacb->negotiateSDTR &= ~(1u << target);
		else {
			H8(hacb, 0x3C) = 5;
			*(unsigned int *)((unsigned char *)hacb + 0x3D) =
			    *(unsigned int *)&hacb->sdtrMsg;
			H8(hacb, 0x41) = hacb->sdtrMsg.reqAckOffset;
			if (H8(hacb, 0x48) > hacb->sdtrMsg.transferPeriod)
				H8(hacb, 0x40) = H8(hacb, 0x48);
			if (H8(hacb, 0x49) < hacb->sdtrMsg.reqAckOffset)
				H8(hacb, 0x41) = H8(hacb, 0x49);
		}
	}
	if (hacb->negotiateSDTR & (1u << target)) {
		unsigned char al = inb(hacb->baseAddress + AIC_SCSISIG);
		outb(hacb->baseAddress + AIC_SCSISIG, (al & 0xE0) | 0x10);
	}
}

void
resetSDTR(struct _HACB *hacb, unsigned int target)
{
	unsigned char buf[8];

	if (target == hacb->ownID) {
		memset(hacb->syncCycles, 0, 8);
		memset(hacb->syncOffset, 0, 8);
		if ((hacb->ac & 0xA0) == 0xA0)
			hacb->negotiateSDTR = 0xFF;
		else
			hacb->negotiateSDTR = 0;
	}
	memset(buf, (hacb->ac & 0xA0) == 0xA0 ? 0 : 0x80, 8);
	outb(hacb->baseAddress + AIC_SCSIRATE, 0);
	if ((hacb->signature + 0xFFFFFFAD) <= 1) {
		outb(hacb->baseAddress + AIC_DMACNTRL1, 3);
		repoutsb(hacb->baseAddress + AIC_STACK, buf, 7);
	} else if (hacb->signature == 0xAA55) {
		outb(hacb->baseAddress + AIC_DMACNTRL1, 4);
		repoutsb(hacb->baseAddress + AIC_STACK, buf, 7);
	} else if (hacb->signature == 0x03020100) {
		outb(hacb->baseAddress + AIC_DMACNTRL1, 8);
		repoutsb(hacb->baseAddress + AIC_STACK, buf, 8);
	}
	outb(hacb->baseAddress + AIC_DMACNTRL1, 0);
}

void
dataPhaseDMA(struct _HACB *hacb)
{
	if (H32(hacb, 0x34) == 0) {
		H32(hacb, 0x30) = HIM6X60GetPhysicalAddress(hacb, HP(hacb, 0x24),
		    (unsigned char *)H32(hacb, 0x28), H32(hacb, 0x38),
		    (unsigned int *)((unsigned char *)hacb + 0x34));
		if (H32(hacb, 0x2C) < H32(hacb, 0x34))
			H32(hacb, 0x34) = H32(hacb, 0x2C);
	}
	HIM6X60MapDMA(hacb, HP(hacb, 0x24),
	    (unsigned char *)H32(hacb, 0x28), H32(hacb, 0x30),
	    H32(hacb, 0x34), hacb->scsiPhase == 0x40);
	hacb->cs |= 0x04;
}

void
dataInPIO(struct _HACB *hacb)
{
	unsigned char mode, dmastat;
	unsigned int n, wait;

	mode = hacb->revision != 0 ? 0x90 : 0x80;
	outb(hacb->baseAddress + AIC_DMACNTRL0, mode);
	outb(hacb->baseAddress + AIC_SXFRCTL0, 0xE0);
refill:
	if (H32(hacb, 0x2C) == 0)
		goto enable_req;
	if (H32(hacb, 0x34) == 0) {
		if (H32(hacb, 0x2C) < H32(hacb, 0x34))
			H32(hacb, 0x34) = H32(hacb, 0x2C);
		if (H32(hacb, 0x34) == 0)
			goto refill;
	}
wait_fifo:
	wait = 0;
	for (;;) {
		dmastat = inb(hacb->baseAddress + AIC_DMASTAT);
		if (dmastat & 0x30)
			break;
		wait++;
		if (wait != 0xFFFFF)
			continue;
		if (inb(hacb->baseAddress + AIC_SCSISIG) & 2) {
			HIM6X60ResetBus(hacb, 0);
			continue;
		}
		outb(hacb->baseAddress + AIC_CLRSINT1, AIC_REQINIT);
		if (inb(hacb->baseAddress + AIC_SCSISIG) & 2)
			goto wait_fifo;
		goto enable_req;
	}
	if (dmastat & AIC_DFIFOFULL)
		n = 0x80;
	else {
		n = inb(hacb->baseAddress + AIC_FIFOSTAT);
		if (n == 0)
			return;
	}
	if (H32(hacb, 0x34) < n)
		n = H32(hacb, 0x34);
	if ((n & 3) == 0 && hacb->revision != 0) {
		if (mode != 0x90) {
			mode = 0x90;
			outb(hacb->baseAddress + AIC_DMACNTRL0, 0x90);
		}
		repinsd(hacb->baseAddress + AIC_DMADATA32,
		    (unsigned long *)H32(hacb, 0x28), (int)(n >> 2));
	} else if (n & 1) {
		if (mode != 0xC0) {
			mode = 0xC0;
			outb(hacb->baseAddress + AIC_DMACNTRL0, 0xC0);
		}
		repinsb(hacb->baseAddress + AIC_DMADATA,
		    (unsigned char *)H32(hacb, 0x28), (int)n);
	} else {
		if (mode != 0x80) {
			mode = 0x80;
			outb(hacb->baseAddress + AIC_DMACNTRL0, 0x80);
		}
		repinsw(hacb->baseAddress + AIC_DMADATA,
		    (unsigned short *)H32(hacb, 0x28), (int)(n >> 1));
	}
	H32(hacb, 0x28) += n;
	H32(hacb, 0x2C) -= n;
	H32(hacb, 0x38) += n;
	H32(hacb, 0x34) -= n;
	if (H32(hacb, 0x34) != 0)
		goto wait_fifo;
	goto refill;
enable_req:
	outb(hacb->baseAddress + AIC_SIMODE1, 0x39);
}

void
dataOutPIO(struct _HACB *hacb)
{
	unsigned char mode, dmastat;
	unsigned int n, wait;

	mode = hacb->revision != 0 ? 0x98 : 0x88;
	outb(hacb->baseAddress + AIC_DMACNTRL0, mode);
	outb(hacb->baseAddress + AIC_SXFRCTL0, 0xE0);
refill:
	if (H32(hacb, 0x2C) == 0)
		goto drain;
	if (H32(hacb, 0x34) == 0) {
		if (H32(hacb, 0x2C) < H32(hacb, 0x34))
			H32(hacb, 0x34) = H32(hacb, 0x2C);
		if (H32(hacb, 0x34) == 0)
			goto refill;
	}
wait_fifo:
	wait = 0;
	for (;;) {
		dmastat = inb(hacb->baseAddress + AIC_DMASTAT);
		if (dmastat & 0x28)
			break;
		wait++;
		if (wait != 0xFFFFF)
			continue;
		if (inb(hacb->baseAddress + AIC_SCSISIG) & 2) {
			HIM6X60ResetBus(hacb, 0);
			continue;
		}
		outb(hacb->baseAddress + AIC_CLRSINT1, AIC_REQINIT);
		if (inb(hacb->baseAddress + AIC_SCSISIG) & 2)
			goto wait_fifo;
		goto enable_req;
	}
	if (dmastat & AIC_INTSTAT)
		return;
	if (dmastat & AIC_DFIFOEMP) {
		n = H32(hacb, 0x34);
		if (n > 0x80)
			n = 0x80;
	} else {
		n = H32(hacb, 0x34);
		if (n > 0x40)
			n = 0x40;
	}
	if ((n & 3) == 0 && hacb->revision != 0) {
		if (mode != 0x98) {
			mode = 0x98;
			outb(hacb->baseAddress + AIC_DMACNTRL0, 0x98);
		}
		repoutsd(hacb->baseAddress + AIC_DMADATA32,
		    (unsigned long *)H32(hacb, 0x28), (int)(n >> 2));
	} else if (n & 1) {
		if (mode != 0xC8) {
			mode = 0xC8;
			outb(hacb->baseAddress + AIC_DMACNTRL0, 0xC8);
		}
		repoutsb(hacb->baseAddress + AIC_DMADATA,
		    (unsigned char *)H32(hacb, 0x28), (int)n);
	} else {
		if (mode != 0x88) {
			mode = 0x88;
			outb(hacb->baseAddress + AIC_DMACNTRL0, 0x88);
		}
		repoutsw(hacb->baseAddress + AIC_DMADATA,
		    (unsigned short *)H32(hacb, 0x28), (int)(n >> 1));
	}
	H32(hacb, 0x28) += n;
	H32(hacb, 0x2C) -= n;
	H32(hacb, 0x38) += n;
	H32(hacb, 0x34) -= n;
	if (H32(hacb, 0x34) != 0)
		goto wait_fifo;
	goto refill;
drain:
	for (;;) {
		dmastat = inb(hacb->baseAddress + AIC_DMASTAT);
		if (dmastat & AIC_INTSTAT)
			return;
		dmastat = inb(hacb->baseAddress + AIC_DMASTAT);
		if ((dmastat & AIC_DFIFOEMP) == 0)
			continue;
		if ((inb(hacb->baseAddress + AIC_SSTAT2) & 0x10) == 0)
			continue;
		break;
	}
enable_req:
	outb(hacb->baseAddress + AIC_SIMODE1, 0x39);
}

void
updateDataPointer(struct _HACB *hacb)
{
	struct _SCB *scb;
	unsigned int n, stcnt, fifo;
	unsigned char al;

	scb = HP(hacb, 0x24);
	if (hacb->cs & 1) {
		hacb->cs &= ~1;
		outb(hacb->baseAddress + AIC_SXFRCTL0, 0x32);
		outb(hacb->baseAddress + AIC_SXFRCTL0, 0x20);
		outb(hacb->baseAddress + AIC_SXFRCTL1, hacb->sXfrCtl1Image);
		outb(hacb->baseAddress + AIC_DMACNTRL0, AIC_RSTFIFO);
		return;
	}
	if ((hacb->ac & 0x40) && (short)scb->flags >= 0) {
		stcnt = inb(hacb->baseAddress + AIC_STCNT0);
		stcnt |= (unsigned int)inb(hacb->baseAddress + AIC_STCNT1) << 8;
		stcnt |= (unsigned int)inb(hacb->baseAddress + AIC_STCNT2) << 16;
		hacb->scsiCount = stcnt;
		n = stcnt;
		if (hacb->scsiPhase != 0) {
			al = inb(hacb->baseAddress + AIC_DMASTAT);
			if ((char)al < 0 && H32(hacb, 0x34) <= stcnt)
				n = H32(hacb, 0x34);
			else {
				fifo = inb(hacb->baseAddress + AIC_FIFOSTAT);
				fifo += inb(hacb->baseAddress + AIC_SSTAT2) & 0x0F;
				n = hacb->scsiCount - fifo;
			}
		}
		H32(hacb, 0x28) += n;
		H32(hacb, 0x2C) -= n;
		H32(hacb, 0x38) += n;
		H32(hacb, 0x30) += n;
		H32(hacb, 0x34) -= n;
		if (inb(hacb->baseAddress + AIC_SSTAT1) & AIC_PHASEMIS)
			goto flush;
		al = inb(hacb->baseAddress + AIC_DMACNTRL0);
		outb(hacb->baseAddress + AIC_DMACNTRL0, al & 0x7F);
		return;
	}
	if ((hacb->maskedSStat1 & AIC_PHASEMIS) == 0)
		return;
	if (hacb->scsiPhase == 0x40)
		dataInPIO(hacb);
	else {
		fifo = inb(hacb->baseAddress + AIC_FIFOSTAT);
		n = fifo + (inb(hacb->baseAddress + AIC_SSTAT2) & 0x0F);
		if (n != 0) {
			H32(hacb, 0x28) -= n;
			H32(hacb, 0x2C) += n;
			H32(hacb, 0x38) -= n;
			H32(hacb, 0x34) += n;
		}
	}
flush:
	outb(hacb->baseAddress + AIC_SXFRCTL0, 0x32);
	outb(hacb->baseAddress + AIC_SXFRCTL0, 0x20);
	outb(hacb->baseAddress + AIC_DMACNTRL0, AIC_RSTFIFO);
}

void
quiesceDmaAndSCSI(struct _HACB *hacb)
{
	unsigned short i;
	unsigned char al;

	i = 0;
	if (hacb->revision == 1)
		HIM6X60Watchdog(hacb, 0, 0);
	if (hacb->scsiPhase == 0) {
		for (;;) {
			if (inb(hacb->baseAddress + AIC_SSTAT0) & AIC_DMADONE)
				break;
			if (inb(hacb->baseAddress + AIC_SSTAT1) & AIC_PHASEMIS) {
				al = inb(hacb->baseAddress + AIC_DMASTAT);
				if ((char)al < 0)
					break;
				if (al & AIC_DFIFOFULL)
					break;
			}
			i++;
			if (i == 0xFFFF)
				break;
		}
		goto finish;
	}
	for (;;) {
		if (inb(hacb->baseAddress + AIC_SSTAT0) & AIC_DMADONE) {
			if (inb(hacb->baseAddress + AIC_DMASTAT) & AIC_DFIFOFULL)
				break;
			if (inb(hacb->baseAddress + AIC_SSTAT1) & AIC_PHASEMIS)
				break;
		}
		if (inb(hacb->baseAddress + AIC_SSTAT1) & AIC_PHASEMIS) {
			if (inb(hacb->baseAddress + AIC_DMASTAT) & AIC_DFIFOEMP)
				break;
		}
		i++;
		if (i == 0xFFFF)
			break;
		if (hacb->revision != 1)
			continue;
		if ((char)inb(hacb->baseAddress + AIC_DMASTAT) >= 0)
			continue;
		if (inb(hacb->baseAddress + AIC_SSTAT0) & AIC_DMADONE)
			continue;
		HIM6X60LogError(hacb, HP(hacb, 0x24), 0, hacb->busID,
		    hacb->lun, 0x8001, hacb->scsiPhase);
		al = inb(hacb->baseAddress + AIC_DMACNTRL0);
		outb(hacb->baseAddress + AIC_DMACNTRL0, al & 0x7F);
		al = inb(hacb->baseAddress + AIC_DMACNTRL0);
		outb(hacb->baseAddress + AIC_DMACNTRL0, al | 0x80);
	}
finish:
	outb(hacb->baseAddress + AIC_SXFRCTL0, 0xA0);
	outb(hacb->baseAddress + AIC_CLRSINT0, AIC_DMADONE);
	HIM6X60FlushDMA(hacb);
	hacb->cs &= ~0x04;
}

void
scsiBusFree(struct _HACB *hacb)
{
	struct _SCB *scb, *linked, *next;
	HIM_LUCB *lucb;
	unsigned char dl;

	if (hacb->cs & 0x04) {
		if (hacb->revision == 1)
			HIM6X60Watchdog(hacb, 0, 0);
		HIM6X60FlushDMA(hacb);
		hacb->cs &= ~0x04;
	}
	outb(hacb->baseAddress + AIC_SCSISEQ, 0);
	outb(hacb->baseAddress + AIC_SXFRCTL0, 0x32);
	outb(hacb->baseAddress + AIC_SXFRCTL1, hacb->sXfrCtl1Image);
	outb(hacb->baseAddress + AIC_SCSIRATE, 0);
	outb(hacb->baseAddress + AIC_SCSISIG, 0);
	outb(hacb->baseAddress + AIC_SCSIDAT, 0);
	outb(hacb->baseAddress + AIC_DMACNTRL0, AIC_RSTFIFO);
	outb(hacb->baseAddress + AIC_CLRSINT0, 0x5F);
	outb(hacb->baseAddress + AIC_CLRSINT1, 0xFF);
	outb(hacb->baseAddress + AIC_SIMODE0, 0x20);
	outb(hacb->baseAddress + AIC_SIMODE1, 0x20);
	outb(hacb->baseAddress + AIC_SCSISEQ, AIC_ENRESELI);
	scb = 0;
	if (hacb->maskedSStat1 & AIC_SCSIRSTI) {
		scsiBusReset(hacb);
		goto reinit;
	}
	if (HP(hacb, 0x24) == 0)
		goto reinit;
	scb = HP(hacb, 0x24);
	if ((signed char)hacb->maskedSStat1 < 0) {
		if (scb->function == 0)
			scb->scbStatus = 0x0A;
		else
			HIM6X60ResetBus(hacb, 0);
	} else if (hacb->cs & 0x02) {
		hacb->cs &= ~0x02;
		if (hacb->scsiPhase != 0xA0)
			goto check_complete;
		if (scb->scbStatus & 0x7F)
			goto unlink_active;
		dl = 1;
		if (H8(hacb, 0x3D) == 6)
			dl = 2;
		scb->scbStatus = dl;
	} else {
		scb->scbStatus = 0x13;
		HIM6X60LogError(hacb, scb, 0, hacb->busID, hacb->lun,
		    2, hacb->scsiPhase);
	}
check_complete:
	if ((scb->scbStatus & 0x7F) == 0) {
		scb = 0;
		goto reinit;
	}
unlink_active:
	unlinkScb(&hacb->eligibleScb, scb);
	lucb = HIM6X60GetLUCB(hacb, 0, scb->targetID, scb->lun);
	if (lucb == 0)
		goto reinit;
	lucb->activeScb = 0;
	if (lucb->queuedScb == 0 || (hacb->cs & 0x20))
		lucb->busy = 0;
	else {
		lucb->busy = 1;
		next = lucb->queuedScb;
		unlinkScb(&lucb->queuedScb, next);
		hacb->cQueuedScb--;
		linkScb(&hacb->eligibleScb, next);
		hacb->cActiveScb++;
	}
reinit:
	hacb->scsiPhase = 0xFF;
	hacb->lun = 0xFF;
	hacb->busID = 0xFF;
	memset((unsigned char *)hacb + 0x24, 0, 0x28);
	initiateIO(hacb);
	if (scb == 0)
		goto freeze;
	linked = scb->linkedScb;
	if (linked != 0) {
		if (linked->function == 0x10) {
			if (scb->scbStatus == 2)
				linked->scbStatus = 1;
			else
				linked->scbStatus = 3;
		} else if (linked->function == 0x14) {
			if ((scb->scbStatus & 0x7F) == 4 && scb->targetStatus == 0x22)
				linked->scbStatus = 1;
			else
				linked->scbStatus = 0x25;
		}
	}
	HIM6X60CompleteSCB(hacb, scb);
	hacb->cActiveScb--;
	if (linked != 0)
		HIM6X60CompleteSCB(hacb, linked);
freeze:
	if (hacb->cActiveScb != 0)
		return;
	while (hacb->queueFreezeScb != 0) {
		scb = hacb->queueFreezeScb;
		unlinkScb(&hacb->queueFreezeScb, scb);
		scb->scbStatus = 1;
		HIM6X60CompleteSCB(hacb, scb);
	}
	if (hacb->revision != 0)
		outb(hacb->baseAddress + AIC_DMACNTRL1, 0x80);
}

void
scsiBusReset(struct _HACB *hacb)
{
	unsigned char t, l;
	HIM_LUCB *lucb;
	struct _SCB *scb, *linked;
	int hadResetScb;

	outb(hacb->baseAddress + AIC_CLRSINT1, AIC_SCSIRSTI);
	resetSDTR(hacb, hacb->ownID);
	hadResetScb = 0;
	for (t = 0; t <= 7; t++) {
		if (t == hacb->ownID)
			continue;
		for (l = 0; l <= 7; l++) {
			lucb = HIM6X60GetLUCB(hacb, 0, t, l);
			if (lucb == 0)
				continue;
			lucb->busy = 0;
			if (lucb->activeScb != 0) {
				scb = lucb->activeScb;
				unlinkScb(&hacb->eligibleScb, scb);
				lucb->activeScb = 0;
				if ((signed char)scb->scbStatus < 0)
					scb->scbStatus = 0x10;
				else if (scb->scbStatus == 0)
					scb->scbStatus = 0x0E;
				linked = scb->linkedScb;
				if (linked != 0)
					linked->scbStatus = 1;
				HIM6X60CompleteSCB(hacb, scb);
				hacb->cActiveScb--;
				if (linked != 0)
					HIM6X60CompleteSCB(hacb, linked);
			}
			while (lucb->queuedScb != 0) {
				scb = lucb->queuedScb;
				unlinkScb(&lucb->queuedScb, scb);
				hacb->cQueuedScb--;
				scb->scbStatus = 0x0E;
				HIM6X60CompleteSCB(hacb, scb);
			}
		}
	}
	while (hacb->eligibleScb != 0) {
		scb = hacb->eligibleScb;
		unlinkScb(&hacb->eligibleScb, scb);
		if ((signed char)scb->scbStatus < 0)
			scb->scbStatus = 0x10;
		else if (scb->scbStatus == 0)
			scb->scbStatus = 0x0E;
		linked = scb->linkedScb;
		if (linked != 0)
			linked->scbStatus = 1;
		HIM6X60CompleteSCB(hacb, scb);
		hacb->cActiveScb--;
		if (linked != 0)
			HIM6X60CompleteSCB(hacb, linked);
	}
	while (hacb->resetScb != 0) {
		scb = hacb->resetScb;
		unlinkScb(&hacb->resetScb, scb);
		scb->scbStatus = 1;
		HIM6X60CompleteSCB(hacb, scb);
		hadResetScb = 1;
	}
	if (hadResetScb) {
		HIM6X60Event(hacb, 2, 0);
		return;
	}
	while (hacb->deferredScb != 0) {
		scb = hacb->deferredScb;
		unlinkScb(&hacb->deferredScb, scb);
		lucb = HIM6X60GetLUCB(hacb, 0, scb->targetID, scb->lun);
		if (lucb == 0)
			continue;
		if (lucb->busy == 0) {
			lucb->busy = 1;
			linkScb(&hacb->eligibleScb, scb);
			hacb->cActiveScb++;
		} else {
			linkScb(&lucb->queuedScb, scb);
			hacb->cQueuedScb++;
		}
	}
}

void
interpretMessageIn(struct _HACB *hacb)
{
	unsigned char msg, st;
	unsigned int x;
	struct _SCB *scb;
	HIM_LUCB *lucb;

	msg = inb(hacb->baseAddress + AIC_SCSIBUS);
	H8(hacb, 0x45 + H8(hacb, 0x44)) = msg;
	H8(hacb, 0x44)++;
	if ((signed char)H8(hacb, 0x45) < 0) {
		if (hacb->lun != 0xFF) {
			prepareMessageOut(hacb, 6);
			goto ack_reset;
		}
		hacb->lun = H8(hacb, 0x45) & 7;
		lucb = HIM6X60GetLUCB(hacb, 0, hacb->busID, hacb->lun);
		scb = lucb->activeScb;
		HP(hacb, 0x24) = scb;
		if (scb == 0) {
			prepareMessageOut(hacb, 0x0C);
			HIM6X60LogError(hacb, 0, 0, hacb->busID, 0xFF, 3,
			    H8(hacb, 0x45));
			goto ack_reset;
		}
		if (scb->function == 0x10) {
			unlinkScb(&hacb->eligibleScb, scb);
			prepareMessageOut(hacb, 6);
			goto ack_reset;
		}
		if (scb->function == 0x14) {
			unlinkScb(&hacb->eligibleScb, scb);
			prepareMessageOut(hacb, 0x11);
			goto ack_reset;
		}
		H32(hacb, 0x28) = (unsigned int)scb->dataPointer;
		H32(hacb, 0x2C) = scb->dataLength;
		H32(hacb, 0x38) = scb->dataOffset;
		H32(hacb, 0x30) = scb->segmentAddress;
		H32(hacb, 0x34) = scb->segmentLength;
		goto ack_reset;
	}
	scb = HP(hacb, 0x24);
	if (scb == 0) {
		prepareMessageOut(hacb, 0x0C);
		goto ack_reset;
	}
	msg = H8(hacb, 0x45);
	if (msg > 7)
		goto reject;
	switch (msg) {
	case 0:
		if ((signed char)scb->scbStatus < 0) {
			if (H8(hacb, 0x4C) != 0)
				scb->scbStatus = 0x10;
			else
				scb->scbStatus |= 4;
			goto ack_reset;
		}
		x = scb->dataLength - H32(hacb, 0x2C) + scb->provisionalTransfer;
		scb->transferLength += x;
		scb->transferResidual -= x;
		st = H8(hacb, 0x4C);
		scb->targetStatus = st;
		if (st > 0x28)
			goto st_bad;
		switch (st) {
		case 0x00:
		case 0x04:
		case 0x10:
		case 0x14:
			if (hacb->cs & 0x10) {
				hacb->cs &= ~0x10;
				scb->scbStatus = 0x0F;
			} else
				scb->scbStatus = 1;
			break;
		case 0x02:
		case 0x22:
			if (scb->scbStatus != 0)
				break;
			if ((scb->flags & 0x20) == 0 && scb->senseData != 0 &&
			    scb->senseDataLength != 0) {
				scb->function = 0;
				scb->flags |= 0x8000;
				scb->scbStatus = 0x80;
				scb->dataPointer = scb->senseData;
				scb->dataLength = scb->senseDataLength;
				scb->dataOffset = 0;
				scb->segmentAddress = 0;
				scb->segmentLength = scb->senseDataLength;
				linkScbPreemptive(&hacb->eligibleScb, scb);
				break;
			}
			/* FALLTHROUGH */
		default:
st_bad:
			scb->scbStatus = 4;
			break;
		case 0x08:
		case 0x28:
			scb->scbStatus = 5;
			break;
		}
		goto ack_reset;
	case 1:
		if (H8(hacb, 0x44) == 1)
			goto ack_keep;
		if (H8(hacb, 0x44) < H8(hacb, 0x46) + 2)
			goto ack_keep;
		if (H8(hacb, 0x47) == 1 && (signed char)hacb->ac < 0) {
			negotiateSDTR(hacb);
			goto ack_reset;
		}
		prepareMessageOut(hacb, 7);
		goto ack_reset;
	case 2:
		if ((signed char)scb->scbStatus >= 0) {
			x = scb->dataLength - H32(hacb, 0x2C);
			scb->transferLength += x;
			scb->transferResidual -= x;
		}
		scb->dataPointer = (unsigned char *)H32(hacb, 0x28);
		scb->dataLength = H32(hacb, 0x2C);
		scb->dataOffset = H32(hacb, 0x38);
		scb->segmentAddress = H32(hacb, 0x30);
		scb->segmentLength = H32(hacb, 0x34);
		goto ack_reset;
	case 3:
		H32(hacb, 0x28) = (unsigned int)scb->dataPointer;
		H32(hacb, 0x2C) = scb->dataLength;
		H32(hacb, 0x38) = scb->dataOffset;
		H32(hacb, 0x30) = scb->segmentAddress;
		H32(hacb, 0x34) = scb->segmentLength;
		scb->provisionalTransfer = 0;
		goto ack_reset;
	case 4:
		if ((signed char)scb->scbStatus >= 0)
			scb->provisionalTransfer =
			    scb->dataLength - H32(hacb, 0x2C);
		scb->scbStatus = 0x10;
		break;
	case 5:
	case 6:
reject:
		prepareMessageOut(hacb, 7);
		goto ack_reset;
	case 7:
		if ((signed char)H8(hacb, 0x3D) < 0)
			scb->scbStatus = 0x20;
		else if (memcmp((unsigned char *)hacb + 0x3D,
		    &hacb->sdtrMsg, 3) == 0)
			updateSDTR(hacb, hacb->busID, 0, 0, 1);
		else if (scb->linkedScb != 0) {
			scb->function = 0;
			scb->linkedScb->scbStatus = 0x0D;
			HIM6X60CompleteSCB(hacb, scb->linkedScb);
			scb->linkedScb = 0;
		} else
			scb->scbStatus = 0x0D;
		H8(hacb, 0x3C) = 1;
		H8(hacb, 0x3D) = 8;
		goto ack_reset;
	}
	hacb->cs |= 0x02;
ack_reset:
	H8(hacb, 0x44) = 0;
ack_keep:
	inb(hacb->baseAddress + AIC_SCSIDAT);
}

void
targetREQuest(struct _HACB *hacb)
{
	struct _SCB *scb;
	unsigned char sig, phase, spio, orig, remaining;
	unsigned int n;

	scb = HP(hacb, 0x24);
	sig = inb(hacb->baseAddress + AIC_SCSISIG);
	hacb->scsiPhase = sig & 0xE0;
	spio = (hacb->sStat0 >> 1) & 1;
	outb(hacb->baseAddress + AIC_SIMODE0, 0);
	outb(hacb->baseAddress + AIC_SIMODE1, 0x38);
	outb(hacb->baseAddress + AIC_SXFRCTL0, 0x30);
	outb(hacb->baseAddress + AIC_SCSISIG, sig & 0xF0);
	outb(hacb->baseAddress + AIC_CLRSINT1, AIC_PHASECHG);
	phase = hacb->scsiPhase;
	if (phase == 0x00) {
		if (scb == 0) {
			bitbucketAndABORT(hacb, 0);
			return;
		}
		if ((signed char)scb->flags >= 0)
			goto abort_14;
		if (H32(hacb, 0x2C) == 0)
			goto abort_12;
		if ((hacb->ac & 0x40) && (short)scb->flags >= 0)
			dataPhaseDMA(hacb);
		else if (hacb->cs & 0x40)
			dataOutPIO(hacb);
		else {
			hacb->disableINT++;
			deferredIsr(hacb);
		}
		return;
	}
	if (phase == 0x40) {
		if (scb == 0) {
			bitbucketAndABORT(hacb, 0);
			return;
		}
		if ((*(unsigned int *)&scb->function & 0x408000) == 0)
			goto abort_14;
		if (H32(hacb, 0x2C) == 0)
			goto abort_12;
		if ((hacb->ac & 0x40) && (short)scb->flags >= 0)
			dataPhaseDMA(hacb);
		else if (hacb->cs & 0x40)
			dataInPIO(hacb);
		else {
			hacb->disableINT++;
			deferredIsr(hacb);
		}
		return;
	}
	if (phase == 0x80) {
		outb(hacb->baseAddress + AIC_DMACNTRL0, 0xCA);
		outb(hacb->baseAddress + AIC_SXFRCTL0, 0xE0);
		if ((signed char)scb->scbStatus < 0) {
			hacb->requestSenseCdb[4] = scb->senseDataLength;
			repoutsb(hacb->baseAddress + AIC_DMADATA,
			    hacb->requestSenseCdb, 6);
		} else
			repoutsb(hacb->baseAddress + AIC_DMADATA,
			    scb->cdb, scb->cdbLength);
		return;
	}
	if (phase == 0xA0) {
		if (inb(hacb->baseAddress + AIC_SSTAT1) & AIC_SCSIPERR) {
			if (hacb->revision == 0)
				outb(hacb->baseAddress + AIC_SXFRCTL1,
				    hacb->sXfrCtl1Image & 0xDF);
			outb(hacb->baseAddress + AIC_CLRSINT1, AIC_SCSIPERR);
			hacb->cs |= 0x10;
			prepareMessageOut(hacb, 5);
			HIM6X60LogError(hacb, HP(hacb, 0x24), 0, hacb->busID,
			    hacb->lun, 1, hacb->scsiPhase);
		} else if (H8(hacb, 0x3C) == 0)
			prepareMessageOut(hacb, 6);
		outb(hacb->baseAddress + AIC_DMACNTRL0, 0);
		outb(hacb->baseAddress + AIC_SXFRCTL0, 0x28);
		orig = H8(hacb, 0x3C);
		if (orig != 0) {
			n = orig;
			do {
				if (samePhaseREQuest(hacb, spio) == 0)
					break;
				if (H8(hacb, 0x3C) == 1)
					outb(hacb->baseAddress + AIC_CLRSINT1,
					    AIC_ATNTARG);
				remaining = H8(hacb, 0x3C);
				outb(hacb->baseAddress + AIC_SCSIDAT,
				    H8(hacb, 0x3D + n - remaining));
				H8(hacb, 0x3C)--;
				spio = 0;
			} while (H8(hacb, 0x3C) != 0);
		}
		if (orig > 1 && (signed char)H8(hacb, 0x3D) < 0)
			memcpy((unsigned char *)hacb + 0x3D,
			    (unsigned char *)hacb + 0x3E, orig - 1);
		if ((signed char)H8(hacb, 0x3D) >= 0) {
			if (H8(hacb, 0x3D) == 0x0C) {
				resetSDTR(hacb, hacb->busID);
				hacb->cs |= 0x02;
			} else if (H8(hacb, 0x3D) == 6 || H8(hacb, 0x3D) == 0x10)
				hacb->cs |= 0x02;
			else if (H8(hacb, 0x3D) == 5)
				hacb->cs &= ~0x10;
			else if (H8(hacb, 0x3D) == 9)
				hacb->cs &= ~0x08;
			else if (memcmp((unsigned char *)hacb + 0x3D,
			    &hacb->sdtrMsg, 3) == 0) {
				if (H8(hacb, 0x3C) != 0)
					updateSDTR(hacb, hacb->busID, 0, 0, 1);
				else if (memcmp((unsigned char *)hacb + 0x45,
				    &hacb->sdtrMsg, 3) == 0)
					hacb->negotiateSDTR &=
					    (unsigned char)~(1u << hacb->busID);
			}
		}
		if (H8(hacb, 0x3C) != 0) {
			outb(hacb->baseAddress + AIC_CLRSINT1, AIC_ATNTARG);
			H8(hacb, 0x3C) = 0;
		}
		return;
	}
	if (phase == 0xC0) {
		outb(hacb->baseAddress + AIC_DMACNTRL0, 0);
		outb(hacb->baseAddress + AIC_SXFRCTL0, 0x28);
		for (;;) {
			if (samePhaseREQuest(hacb, spio) == 0)
				return;
			if (inb(hacb->baseAddress + AIC_SSTAT1) & AIC_SCSIPERR) {
				if (hacb->revision == 0)
					outb(hacb->baseAddress + AIC_SXFRCTL1,
					    hacb->sXfrCtl1Image & 0xDF);
				outb(hacb->baseAddress + AIC_CLRSINT1,
				    AIC_SCSIPERR);
				H8(hacb, 0x4C) = 0xFF;
				hacb->cs |= 0x10;
				prepareMessageOut(hacb, 5);
				HIM6X60LogError(hacb, HP(hacb, 0x24), 0,
				    hacb->busID, hacb->lun, 1, hacb->scsiPhase);
				inb(hacb->baseAddress + AIC_SCSIDAT);
			} else
				H8(hacb, 0x4C) = inb(hacb->baseAddress +
				    AIC_SCSIDAT);
			spio = 0;
		}
	}
	if (phase == 0xE0) {
		outb(hacb->baseAddress + AIC_DMACNTRL0, 0);
		outb(hacb->baseAddress + AIC_SXFRCTL0, 0x28);
		for (;;) {
			if (samePhaseREQuest(hacb, spio) == 0)
				return;
			if (inb(hacb->baseAddress + AIC_SSTAT1) & AIC_SCSIPERR) {
				if (hacb->revision == 0)
					outb(hacb->baseAddress + AIC_SXFRCTL1,
					    hacb->sXfrCtl1Image & 0xDF);
				outb(hacb->baseAddress + AIC_CLRSINT1,
				    AIC_SCSIPERR);
				H8(hacb, 0x44) = 0;
				hacb->cs |= 0x08;
				prepareMessageOut(hacb, 9);
				HIM6X60LogError(hacb, HP(hacb, 0x24), 0,
				    hacb->busID, hacb->lun, 1, hacb->scsiPhase);
			}
			if (hacb->cs & 0x08)
				inb(hacb->baseAddress + AIC_SCSIDAT);
			else
				interpretMessageIn(hacb);
			spio = 0;
		}
	}
	HIM6X60LogError(hacb, scb, 0, hacb->busID, hacb->lun, 5, phase);
	prepareMessageOut(hacb, 7);
	return;
abort_12:
	bitbucketAndABORT(hacb, 0x12);
	return;
abort_14:
	bitbucketAndABORT(hacb, 0x14);
	HIM6X60LogError(hacb, HP(hacb, 0x24), 0, hacb->busID, hacb->lun,
	    5, hacb->scsiPhase);
}
