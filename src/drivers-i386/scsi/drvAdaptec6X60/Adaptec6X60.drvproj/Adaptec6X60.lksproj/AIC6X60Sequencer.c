#import "HIM6X60.h"
#import "AIC6X60Inline.h"
#import "AIC6X60ControllerPrivate.h"
#import <driverkit/generalFuncs.h>
#import <string.h>

/*
 * HIM helpers this translation unit calls. Global C linkage.
 */
typedef struct {
	unsigned char	busy;
	unsigned char	_pad[3];
	struct _SCB	*queuedScb;
	struct _SCB	*activeScb;
} HIM_LUCB;

extern HIM_LUCB *HIM6X60GetLUCB(struct _HACB *hacb, int bus, unsigned char target, unsigned char lun);
extern void HIM6X60CompleteSCB(struct _HACB *hacb, struct _SCB *scb);
extern void HIM6X60Event(void);
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
void samePhaseREQuest(struct _HACB *hacb, unsigned char wait);
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
	if (H8(hacb, 0x56 + target) != 0)
		rate = ((H8(hacb, 0x4E + target) + 0xFE) << 4) |
		    H8(hacb, 0x56 + target);
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
	if (H8(hacb, 0x56 + id) != 0)
		rate = ((H8(hacb, 0x4E + id) + 0xFE) << 4) | H8(hacb, 0x56 + id);
	else
		rate = 0;
	outb(hacb->baseAddress + AIC_SCSIRATE, rate);
}

void
updateSDTR(struct _HACB *hacb, unsigned int target, unsigned char cycles, unsigned char offset, unsigned char persist)
{
	unsigned char slot, rate;

	H8(hacb, 0x4E + target) = cycles;
	H8(hacb, 0x56 + target) = offset;
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
		memset((unsigned char *)hacb + 0x4E, 0, 8);
		memset((unsigned char *)hacb + 0x56, 0, 8);
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
	unsigned char mode;
	unsigned int n;

	mode = hacb->revision != 0 ? 0x90 : 0x80;
	outb(hacb->baseAddress + AIC_DMACNTRL0, mode);
	outb(hacb->baseAddress + AIC_SXFRCTL0, 0xE0);
	if (H32(hacb, 0x2C) == 0)
		return;
	if (H32(hacb, 0x34) == 0) {
		if (H32(hacb, 0x2C) < H32(hacb, 0x34))
			H32(hacb, 0x34) = H32(hacb, 0x2C);
	}
	n = H32(hacb, 0x34);
	if (n == 0)
		return;
	if ((n & 3) == 0)
		repinsd(hacb->baseAddress + AIC_DMADATA32,
		    (unsigned long *)H32(hacb, 0x28), (int)(n >> 2));
	else if ((n & 1) == 0)
		repinsw(hacb->baseAddress + AIC_DMADATA,
		    (unsigned short *)H32(hacb, 0x28), (int)(n >> 1));
	else
		repinsb(hacb->baseAddress + AIC_DMADATA,
		    (unsigned char *)H32(hacb, 0x28), (int)n);
	H32(hacb, 0x28) += n;
	H32(hacb, 0x2C) -= n;
	H32(hacb, 0x34) = 0;
}

void
dataOutPIO(struct _HACB *hacb)
{
	unsigned char mode;
	unsigned int n;

	mode = hacb->revision != 0 ? 0x98 : 0x88;
	outb(hacb->baseAddress + AIC_DMACNTRL0, mode);
	outb(hacb->baseAddress + AIC_SXFRCTL0, 0xE0);
	if (H32(hacb, 0x2C) == 0)
		return;
	if (H32(hacb, 0x34) == 0) {
		if (H32(hacb, 0x2C) < H32(hacb, 0x34))
			H32(hacb, 0x34) = H32(hacb, 0x2C);
	}
	n = H32(hacb, 0x34);
	if (n == 0)
		return;
	if ((n & 3) == 0)
		repoutsd(hacb->baseAddress + AIC_DMADATA32,
		    (unsigned long *)H32(hacb, 0x28), (int)(n >> 2));
	else if ((n & 1) == 0)
		repoutsw(hacb->baseAddress + AIC_DMADATA,
		    (unsigned short *)H32(hacb, 0x28), (int)(n >> 1));
	else
		repoutsb(hacb->baseAddress + AIC_DMADATA,
		    (unsigned char *)H32(hacb, 0x28), (int)n);
	H32(hacb, 0x28) += n;
	H32(hacb, 0x2C) -= n;
	H32(hacb, 0x34) = 0;
}

void
updateDataPointer(struct _HACB *hacb)
{
	struct _SCB *scb = HP(hacb, 0x24);

	if (scb == 0)
		return;
	scb->dataPointer = (unsigned char *)H32(hacb, 0x28);
	scb->dataLength = H32(hacb, 0x2C);
	scb->dataOffset = H32(hacb, 0x38);
	scb->segmentAddress = H32(hacb, 0x30);
	scb->segmentLength = H32(hacb, 0x34);
}

void
quiesceDmaAndSCSI(struct _HACB *hacb)
{
	unsigned short i;
	unsigned char al;

	if (hacb->revision == 1)
		HIM6X60Watchdog(hacb, 0, 0);
	i = 0;
	if (hacb->scsiPhase == 0) {
		for (;;) {
			al = inb(hacb->baseAddress + AIC_SSTAT0);
			if (al & AIC_DMADONE)
				break;
			al = inb(hacb->baseAddress + AIC_SSTAT1);
			if ((al & AIC_PHASEMIS) == 0) {
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
	}
	if (i == 0xFFFF)
		HIM6X60LogError(hacb, HP(hacb, 0x24), 0, hacb->busID,
		    hacb->lun, 0x8001, hacb->scsiPhase);
	HIM6X60FlushDMA(hacb);
	hacb->cs &= ~0x04;
}

void
scsiBusFree(struct _HACB *hacb)
{
	struct _SCB *scb;
	HIM_LUCB *lucb;

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
	outb(hacb->baseAddress + AIC_CLRSINT1, AIC_BUSFREE);
	scb = HP(hacb, 0x24);
	if (scb != 0) {
		unlinkScb(&hacb->eligibleScb, scb);
		lucb = HIM6X60GetLUCB(hacb, 0, scb->targetID, scb->lun);
		if (lucb && lucb->activeScb == scb)
			lucb->activeScb = 0;
		if (lucb && lucb->queuedScb != 0) {
			struct _SCB *next = lucb->queuedScb;
			unlinkScb(&lucb->queuedScb, next);
			linkScb(&hacb->eligibleScb, next);
		}
		HIM6X60CompleteSCB(hacb, scb);
		HP(hacb, 0x24) = 0;
		if (hacb->cActiveScb)
			hacb->cActiveScb--;
	}
	hacb->busID = 0xFF;
	hacb->lun = 0xFF;
	hacb->scsiPhase = 0xFF;
	initiateIO(hacb);
}

void
scsiBusReset(struct _HACB *hacb)
{
	unsigned char t, l;
	HIM_LUCB *lucb;
	struct _SCB *scb;

	outb(hacb->baseAddress + AIC_CLRSINT1, AIC_SCSIRSTI);
	resetSDTR(hacb, hacb->ownID);
	for (t = 0; t <= 7; t++) {
		for (l = 0; l <= 7; l++) {
			lucb = HIM6X60GetLUCB(hacb, 0, t, l);
			if (lucb == 0)
				continue;
			while (lucb->queuedScb != 0) {
				scb = lucb->queuedScb;
				unlinkScb(&lucb->queuedScb, scb);
				scb->scbStatus = 0x14;
				HIM6X60CompleteSCB(hacb, scb);
			}
			if (lucb->activeScb != 0) {
				scb = lucb->activeScb;
				lucb->activeScb = 0;
				scb->scbStatus = 0x14;
				HIM6X60CompleteSCB(hacb, scb);
			}
			lucb->busy = 0;
		}
	}
	while (hacb->eligibleScb != 0) {
		scb = hacb->eligibleScb;
		unlinkScb(&hacb->eligibleScb, scb);
		scb->scbStatus = 0x14;
		HIM6X60CompleteSCB(hacb, scb);
	}
	while (hacb->deferredScb != 0) {
		scb = hacb->deferredScb;
		unlinkScb(&hacb->deferredScb, scb);
		HIM6X60CompleteSCB(hacb, scb);
	}
	HIM6X60Event();
	hacb->cQueuedScb = 0;
	hacb->cActiveScb = 0;
	HP(hacb, 0x24) = 0;
	hacb->busID = 0xFF;
	hacb->lun = 0xFF;
}

void
interpretMessageIn(struct _HACB *hacb)
{
	unsigned char msg;
	unsigned char idx;
	HIM_LUCB *lucb;

	msg = inb(hacb->baseAddress + AIC_SCSIBUS);
	idx = H8(hacb, 0x44);
	H8(hacb, 0x45 + idx) = msg;
	H8(hacb, 0x44)++;
	if ((signed char)H8(hacb, 0x45) < 0) {
		if (hacb->lun == 0xFF)
			prepareMessageOut(hacb, 6);
		return;
	}
	if (H8(hacb, 0x45) == 0x01) {
		negotiateSDTR(hacb);
		return;
	}
	if (H8(hacb, 0x45) == 0x03) {
		updateSDTR(hacb, hacb->busID, 0, 0, 1);
		return;
	}
	if (H8(hacb, 0x45) == 0x07 || H8(hacb, 0x45) == 0x0C) {
		if (HP(hacb, 0x24) != 0)
			HIM6X60CompleteSCB(hacb, HP(hacb, 0x24));
		return;
	}
	if ((H8(hacb, 0x45) & 0x80) && hacb->lun == 0xFF) {
		hacb->lun = H8(hacb, 0x45) & 7;
		lucb = HIM6X60GetLUCB(hacb, 0, hacb->busID, hacb->lun);
		if (lucb && lucb->activeScb)
			HP(hacb, 0x24) = lucb->activeScb;
	}
}

void
targetREQuest(struct _HACB *hacb)
{
	struct _SCB *scb;
	unsigned char sig, phase, spio;
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
		if ((signed char)scb->flags >= 0 && H32(hacb, 0x2C) != 0) {
			if ((hacb->ac & 0x40) && (short)scb->flags >= 0)
				dataPhaseDMA(hacb);
			else if (hacb->cs & 0x40)
				dataOutPIO(hacb);
			else {
				hacb->disableINT++;
				deferredIsr(hacb);
			}
		} else if (H32(hacb, 0x2C) == 0)
			bitbucketAndABORT(hacb, 0x12);
		else
			dataOutPIO(hacb);
		return;
	}
	if (phase == 0x40) {
		if (scb == 0) {
			bitbucketAndABORT(hacb, 0);
			return;
		}
		if (scb->function & 0x408000) {
			bitbucketAndABORT(hacb, 0x14);
			HIM6X60LogError(hacb, scb, 0, hacb->busID, hacb->lun,
			    5, hacb->scsiPhase);
			return;
		}
		if (H32(hacb, 0x2C) == 0)
			bitbucketAndABORT(hacb, 0x12);
		else if ((hacb->ac & 0x40) && (short)scb->flags >= 0)
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
		if (scb == 0 || scb->cdb == 0)
			return;
		n = scb->cdbLength;
		if (n)
			repoutsb(hacb->baseAddress + AIC_SCSIDAT, scb->cdb, (int)n);
		return;
	}
	if (phase == 0xA0) {
		unsigned char len = H8(hacb, 0x3C);
		if (len)
			repoutsb(hacb->baseAddress + AIC_SCSIDAT,
			    (unsigned char *)hacb + 0x3D, len);
		H8(hacb, 0x3C) = 0;
		return;
	}
	if (phase == 0xC0) {
		unsigned char status = inb(hacb->baseAddress + AIC_SCSIDAT);
		if (scb != 0)
			scb->targetStatus = status;
		hacb->targetStatus = status;
		return;
	}
	if (phase == 0xE0) {
		interpretMessageIn(hacb);
		return;
	}
	HIM6X60LogError(hacb, scb, 0, hacb->busID, hacb->lun, 5, phase);
	prepareMessageOut(hacb, 7);
}
