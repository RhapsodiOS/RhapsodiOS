/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * SYM53c8SIM.c - CAM SIM layer of the NCR SDMS engine in SYM53c8_reloc.
 *
 * HISTORY
 *
 * Oct 1998	Created.
 *
 * Bodies follow IDA 9.2 of SYM53c8_reloc (divergences.md, "Method").
 * CAMcore / XPT callees live in SYM53c8CAM.c and are extern here.
 */

#import "SYM53c8SIM.h"
#import "SYM53c8Inline.h"
#import <driverkit/generalFuncs.h>
#import <kernserv/ns_timer.h>

#define SIM_U32(p)	(*(unsigned int *)(void *)(p))
#define SIM_CCBP(p)	(*(struct sim_ccb **)(void *)(p))

struct sim_hba		HBAs[SYM_HBA_SLOTS];
struct sim_dev		DEVs[SYM_DEV_SLOTS];
struct sim_ccb		*PendingAborts[8];
struct sim_q		simqs[SYM_DEV_SLOTS];
struct sim_q		*simqStack[SYM_DEV_SLOTS];
unsigned short		simqTOS;
unsigned short		TotalDEVs;
unsigned int		TickCount;
struct sim_q		timeq;
struct sim_rom		ROMs[SIM_ROM_SLOTS];
int			numROMs;
unsigned short		MaxCCBPrivateLen;
struct sim_q		q16to17;
struct sim_q		q17to16;
struct sim16_ccb	*ccb16[7];
struct sim_ccb		*ccb17[7];
struct sim16_ccb	CHSCCB;
unsigned int		carldiag;
int			SyncSCSIEnable;
int			WideSCSIEnable;
unsigned char		Sync_dev[32];
unsigned char		Wide_dev[32];
ns_time_t		EndTime;
char			*ourname_100 = "Ballard Synergy ";

char reset_cause[14][30] = {
	"cFRun: Parity Error",
	"CFRun: Phase Mismatch",
	"cFRun: Invalid icode (#2)",
	"cFRun: Invalid icode (#3)",
	"cFSetSync",
	"cFGetMsgByte",
	"cFMsgResponse",
	"cFSendMsg (#7)",
	"cFSendMsg (#8)",
	"cFSendMsg (#9)",
	"cFSendMsg (#10)",
	"cFRun: SCSI Gross Error",
	"cFRun: Unexpected Disconnect",
	"Unknown p4"
};

void		r16Comp(struct sim16_ccb *ccb16);
void		r17Comp(struct sim_ccb *ccb);

int
DisableInterrupts(void)
{
	return 0;
}

int
EnableInterrupts(void)
{
	return 0;
}

void
RestoreInterrupts(int state)
{
}

void
QInsert(struct sim_q *head, struct sim_q *elem, void *owner)
{
	int state;

	state = DisableInterrupts();
	elem->owner = owner;
	elem->next = head->next;
	elem->prev = head;
	head->next->prev = elem;
	head->next = elem;
	RestoreInterrupts(state);
}

void
QAppend(struct sim_q *head, struct sim_q *elem, void *owner)
{
	int state;

	state = DisableInterrupts();
	elem->owner = owner;
	elem->next = head;
	elem->prev = head->prev;
	head->prev->next = elem;
	head->prev = elem;
	RestoreInterrupts(state);
}

void
QDelete(struct sim_q *elem)
{
	int state;

	state = DisableInterrupts();
	if (elem->next != 0) {
		elem->next->prev = elem->prev;
		elem->prev->next = elem->next;
		elem->next = 0;
	}
	RestoreInterrupts(state);
}

struct sim_dev *
IDLUNToDP(struct sim_hba *hba, unsigned char id, unsigned char lun)
{
	unsigned char idx;

	idx = hba->devmap[id][lun];
	if (idx == 0xFF)
		return 0;
	return &DEVs[idx];
}

struct sim_rom *
PathToROMInfoPtr(unsigned char path)
{
	int i;

	for (i = 0; i < numROMs; i++) {
		if (ROMs[i].path == path)
			return &ROMs[i];
	}
	return 0;
}

int
GetNumROMs(void)
{
	return numROMs;
}

struct sim_rom *
GetROMTableBase(void)
{
	return ROMs;
}

unsigned int
GetWidth(unsigned char path)
{
	int i;

	for (i = 0; i <= 3; i++) {
		if (HBAs[i].path == path)
			return HBAs[i].width;
	}
	return 0;
}

void
SIMClearMem(void *mem, unsigned short len)
{
	unsigned short i;
	unsigned char *p;

	p = (unsigned char *)mem;
	for (i = 0; i < len; i++)
		p[i] = 0;
}

void
CallCompletion(struct sim16_ccb *ccb)
{
	PostTransfer16(ccb);
	if (ccb->complete != 0)
		(*ccb->complete)(ccb);
}

void
CallComp(struct sim_hba *hba, struct sim_ccb *ccb)
{
	unsigned short inq0, inq2;
	int is_inquiry;
	unsigned int path, target, lun;
	struct sim_dev *dev;
	unsigned short extra;
	unsigned short syncbit, widebits;
	int slot, n;
	unsigned int *src, *dst;
	unsigned int simflags;
	void (*complete)();
	int abort_i;
	struct sim_ccb *abort_ccb;

	inq0 = 0;
	inq2 = 0;
	is_inquiry = 0;
	path = ccb->path;
	target = ccb->target;
	lun = ccb->lun;
	if ((ccb->flags0 & 1) == 0 && ccb->cdb[0] == 0x12) {
		is_inquiry = 1;
		inq0 = PeekAtData(ccb, 0);
		inq2 = PeekAtData(ccb, 2);
	}
	if (hba->negstate[target] == 0
	    && ccb->status == 1
	    && ccb->scsi_status == 0
	    && is_inquiry != 0
	    && inq0 != 0xFFFF
	    && inq2 != 0xFFFF) {
		inq2 &= 3;
		dev = IDLUNToDP(hba, (unsigned char)target, (unsigned char)lun);
		extra = PeekAtData(ccb, 7);
		syncbit = extra & 0x10;
		if (SyncSCSIEnable != 0)
			Sync_dev[path * 7 + target] = (unsigned char)syncbit;
		else
			Sync_dev[path * 7 + target] = 0;
		if (inq2 > 1)
			hba->negstate[target] = 3;
		else
			hba->negstate[target] = 1;
		widebits = extra & 0x60;
		if (WideSCSIEnable != 0)
			Wide_dev[path * 7 + target] = (unsigned char)widebits;
		else
			Wide_dev[path * 7 + target] = 0;
		if (widebits != 0 && dev != 0 && WideSCSIEnable != 0
		    && (dev->wide & 3) == 0 && hba->width != 0)
			dev->wide |= 4;
		if (syncbit != 0 && dev != 0 && SyncSCSIEnable != 0
		    && dev->sync == 0)
			dev->sync = 2;
		dev->flags = (unsigned char)((dev->flags & 0xFC) | 2);
	}
	dev = IDLUNToDP(hba, (unsigned char)target, (unsigned char)lun);
	if (ccb->xferCount != 0) {
		DoneWithCurrentData(ccb);
		PostTransfer17(ccb, hba->base->initiatorId);
	}
	if (ccb->flags1 & 8) {
		dev = IDLUNToDP(hba, (unsigned char)target, (unsigned char)lun);
		if (dev != 0) {
			dev->frozen = 1;
			ccb->status |= 0x40;
		}
	}
	if (ccb->status == 0x0A || (is_inquiry != 0 && inq0 == 0x7F)) {
		if (ccb->status == 0x0A)
			lun = 0xFF;
		for (slot = 0; slot <= 0x1B; slot++) {
			if (DEVs[slot].path == (unsigned char)path
			    && DEVs[slot].id == (unsigned char)target
			    && (lun == 0xFF
				|| DEVs[slot].lun == (unsigned char)lun)
			    && DEVs[slot].frozen == 0) {
				simqStack[simqTOS] = DEVs[slot].queue;
				simqTOS++;
				for (n = slot + 1; n <= 0x1B; n++) {
					src = (unsigned int *)&DEVs[n];
					dst = (unsigned int *)&DEVs[n - 1];
					dst[0] = src[0];
					dst[1] = src[1];
					dst[2] = src[2];
					dst[3] = src[3];
				}
				DEVs[0x1B].id = 0xFF;
				TotalDEVs--;
				slot--;
			}
		}
		{
			int id, ln;

			for (id = 0; id <= 7; id++) {
				for (ln = 0; ln <= 7; ln++)
					hba->devmap[id][ln] = 0xFF;
			}
		}
		for (slot = 0; slot <= 0x1B; slot++) {
			if (DEVs[slot].id != 0xFF
			    && DEVs[slot].path == hba->path) {
				hba->devmap[DEVs[slot].id][DEVs[slot].lun]
				    = (unsigned char)slot;
			}
		}
	}
	simflags = ccb->simFlags;
	if ((ccb->flags0 & 8) == 0) {
		complete = ccb->complete;
		if (complete != 0)
			(*complete)(ccb);
	}
	if (simflags & 0x10000000) {
		for (abort_i = 0; abort_i <= 7; abort_i++) {
			abort_ccb = PendingAborts[abort_i];
			if (abort_ccb != 0 && abort_ccb->link_ccb == ccb) {
				PendingAborts[abort_i] = 0;
				abort_ccb->status = 1;
			}
		}
	}
}

int
CCBInSIMQueue(struct sim_hba *hba, struct sim_ccb *ccb)
{
	struct sim_fw *fw;
	struct sim_dev *dev;
	struct sim_q *q;

	fw = hba->fw;
	if (fw->pending == ccb && fw->selid <= 7)
		return 0;
	dev = IDLUNToDP(hba, ccb->target, ccb->lun);
	if (dev == 0)
		return 0;
	q = dev->queue;
	q = q->next;
	if (q == 0)
		return 0;
	while (q != dev->queue) {
		if (q->owner == ccb)
			return 1;
		q = q->next;
		if (q == 0)
			break;
	}
	return 0;
}

void
RespondToBusReset(struct sim_hba *hba)
{
	unsigned char id;
	struct sim_ccb *sns;

	hba->fw->selid = 0x82;
	hba->fw->curid = 0xFF;
	hba->fw->active = 0;
	hba->resume = 0;
	for (id = 0; id <= 7; id++)
		ResetDevice(hba, id, 0x0E);
	hba->queued = 0;
	InitializeQueueTags(hba);
	sns = hba->snsccb;
	if (sns->link_ccb != 0) {
		CallComp(hba, sns);
		hba->snsccb->link_ccb = 0;
	}
	xpt_async(1, hba->path, 0xFFFFFFFF, 0xFFFFFFFF, 0, 0);
}

unsigned short
RespondToComp(struct sim_hba *hba, struct sim_ccb *ccb)
{
	struct sim_dev *dev;
	unsigned char idx;
	int bad_sync;
	unsigned char tag;
	unsigned short result;
	struct sim_ccb *parent;
	struct sim_ccb *linked;

	bad_sync = 0;
	result = 0x0C;
	if (ccb == 0) {
		int i;

		for (i = 0; i <= 0x1B; i++)
			DEVs[i].flags &= 0xE3;
		return result;
	}
	idx = hba->devmap[ccb->target][ccb->lun];
	dev = &DEVs[idx];
	if (hba->ndone <= 7) {
		hba->done[hba->ndone] = idx;
		hba->ndone++;
	}
	if (hba->fw->sync < 0) {
		ccb->status = 0x0A;
		bad_sync = 1;
		tag = 0;
	} else {
		tag = (unsigned char)hba->fw->sync;
		if (tag == 0)
			FreeQueueTag(hba, ccb);
	}
	QDelete(&ccb->qlink);
	if (hba->snsccb == ccb) {
		CallComp(hba, ccb);
		hba->snscount--;
		parent = hba->snsccb->link_ccb;
		hba->snsccb->link_ccb = 0;
		parent->sense_resid = (unsigned char)hba->snsccb->resid;
		if (hba->snsccb->scsi_status == 0)
			parent->status = 0x84;
		else
			parent->status = 0x10;
		if ((parent->flags1 & 4) == 0) {
			dev->frozen = 1;
			parent->status |= 0x40;
		}
		ccb = parent;
	} else if (bad_sync == 0) {
		if (ccb->scsi_status == 0x22) {
			ccb->status = 0x18;
			if ((ccb->flags1 & 4) == 0)
				dev->frozen = 1;
		} else if (bad_sync == 0) {
			if (ccb->scsi_status & 0xEF) {
				if ((ccb->flags1 & 4) == 0)
					dev->frozen = 1;
				if ((ccb->flags0 & 0x20) == 0
				    && ccb->scsi_status == 2) {
					QAppend(&hba->snsq, &ccb->qlink, ccb);
					hba->snscount++;
					AutosenseSetup(hba);
					ccb = 0;
				} else {
					ccb->status = 4;
					if ((ccb->flags1 & 4) == 0)
						ccb->status = 0x44;
				}
			} else if (bad_sync == 0)
				ccb->status = 1;
		}
	}
	if (ccb == 0)
		return result;
	QDelete(&ccb->timelink);
	if (tag != 0) {
		if ((ccb->flags0 & 4) == 0)
			return 3;
		linked = ccb->next_ccb;
		SIMStart(linked);
		linked->requeue = ccb->requeue;
		QDelete(&linked->qlink);
		QAppend(&hba->actq, &linked->qlink, linked);
		hba->fw->active = linked;
		hba->fw->curid = linked->target;
		PreTransfer17(linked, hba->base->initiatorId);
		if (linked->xferCount == 0)
			result = 3;
		else {
			SetFrag(linked, hba->base->initiatorId);
			result = (unsigned short)FResumeXFer(hba);
		}
	}
	CallComp(hba, ccb);
	return result;
}

int
SIM16Start(struct sim16_ccb *ccb)
{
	struct sim_rom *rom;
	unsigned int rc;

	if (ccb->lun != 0) {
		ccb->status = 0x0A;
		if (ccb->op == 2)
			CallCompletion(ccb);
		return (int)ccb;
	}
	if (ccb->target > 7) {
		ccb->status = 0x21;
		if (ccb->op == 2)
			CallCompletion(ccb);
		return (int)ccb;
	}
	rom = PathToROMInfoPtr(ccb->path);
	if (rom == 0) {
		ccb->status = 7;
		if (ccb->op == 2)
			CallCompletion(ccb);
		return (int)ccb;
	}
	if (ccb->op == 2) {
		PreTransfer16(ccb, rom->ctx->initiatorId);
		rc = (*rom->run)(rom->ctx, ccb);
		if (rc <= 1)
			return (int)rc;
		if (rc > 2)
			CallCompletion((struct sim16_ccb *)rc);
		do {
			rc = (*rom->poll)(rom->ctx);
		} while (rc > 1);
		return (int)rc;
	}
	if (ccb->op != 0x22) {
		ccb->status = 0x16;
		return (int)ccb;
	}
	(*rom->action)(rom->ctx, ccb);
	return (int)ccb;
}

void
SIM16Int(struct sim_rom *rom)
{
	unsigned int rc;

	do {
		rc = (*rom->poll)(rom->ctx);
		if (rc > 2)
			CallCompletion((struct sim16_ccb *)rc);
	} while (rc > 1);
}

void
Start17On16(struct sim_ccb *ccb17, struct sim16_ccb *ccb16p)
{
	T17To16(ccb17, ccb16p);
	ccb16p->ccb17 = ccb17;
	ccb16p->complete = (void (*)())r16Comp;
	SIM16Start(ccb16p);
}

void
Start16On17(struct sim16_ccb *ccb16p, struct sim_ccb *ccb17)
{
	T16To17(ccb16p, ccb17);
	ccb17->link_ccb = (struct sim_ccb *)ccb16p;
	ccb17->complete = (void (*)())r17Comp;
	SIMStart(ccb17);
}

void
r16Comp(struct sim16_ccb *ccb16p)
{
	struct sim_ccb *ccb17;
	int i;
	struct sim_q *q;
	struct sim_ccb *queued;
	void (*complete)();

	ccb17 = ccb16p->ccb17;
	ccb17->status = Stat16To17(ccb16p->status);
	ccb17->scsi_status = ccb16p->scsi_status;
	ccb17->resid = ccb16p->opflags;
	if (ccb17->scsi_status == 2
	    && (signed char)ccb17->status >= 0
	    && (ccb16p->word8 & 0x20000000) == 0) {
		ccb16p->word8 = 0x60800000;
		ccb16p->byte10 = 0;
		ccb16p->flags = 1;
		ccb16p->w12 = 6;
		ccb16p->arg_ffff = 0xFFFFFFFF;
		ccb16p->opflags = ccb17->sense_len;
		ccb16p->arg0 = (unsigned int)ccb17->sense_ptr;
		ccb16p->w14 = 0;
		ccb16p->arg1 = 0;
		ccb16p->cdb[0] = 3;
		ccb16p->cdb[1] = 0;
		ccb16p->cdb[2] = 0;
		ccb16p->cdb[3] = 0;
		ccb16p->cdb[4] = (unsigned char)ccb16p->opflags;
		ccb16p->cdb[5] = 0;
		ccb16p->ccb17 = 0;
		ccb16p->complete = 0;
		SIM16Start(ccb16p);
		ccb17->status |= 0x80;
	}
	if (q17to16.next != 0 && q17to16.next != &q17to16) {
		q = q17to16.next;
		queued = (struct sim_ccb *)q->owner;
		QDelete(&queued->qlink);
		Start17On16(queued, ccb16p);
	} else {
		for (i = 0; i <= 6; i++) {
			if (ccb16[i] == 0) {
				ccb16[i] = ccb16p;
				break;
			}
		}
	}
	if ((ccb17->flags0 & 8) == 0) {
		complete = ccb17->complete;
		if (complete != 0)
			(*complete)(ccb17);
	}
}

void
r17Comp(struct sim_ccb *ccb)
{
	struct sim16_ccb *ccb16p;
	int i;
	struct sim_q *q;
	struct sim16_ccb *queued;
	void (*complete)();
	short w10;

	ccb16p = (struct sim16_ccb *)ccb->link_ccb;
	ccb16p->status = Stat17To16(ccb->status);
	ccb16p->scsi_status = ccb->scsi_status;
	ccb16p->opflags = ccb->resid;
	if (q16to17.next != 0 && q16to17.next != &q16to17) {
		q = q16to17.next;
		queued = (struct sim16_ccb *)q->owner;
		QDelete(&queued->qlink);
		Start16On17(queued, ccb);
	} else {
		for (i = 0; i <= 6; i++) {
			if (ccb17[i] == 0) {
				ccb17[i] = ccb;
				break;
			}
		}
	}
	w10 = (short)(ccb16p->byte10 | ((unsigned short)ccb16p->flags << 8));
	if ((ccb16p->word8 & 0x08000000) == 0 && w10 >= 0) {
		complete = ccb16p->complete;
		if (complete != 0)
			(*complete)(ccb16p);
	}
}

void
Do17On16(struct sim_ccb *ccb)
{
	int i;
	struct sim16_ccb *scratch;

	if (ccb->func_code != SIM_FUNC_IO) {
		ccb->status = 1;
		return;
	}
	for (i = 0; i <= 6; i++) {
		if (ccb16[i] != 0)
			break;
	}
	if (i <= 6) {
		scratch = ccb16[i];
		ccb16[i] = 0;
		Start17On16(ccb, scratch);
		return;
	}
	QAppend(&q17to16, &ccb->qlink, ccb);
}

void
Do16On17(struct sim16_ccb *ccb)
{
	int i;
	struct sim_ccb *scratch;

	if (ccb->op != 2) {
		ccb->status = 1;
		return;
	}
	for (i = 0; i <= 6; i++) {
		if (ccb17[i] != 0)
			break;
	}
	if (i <= 6) {
		scratch = ccb17[i];
		ccb17[i] = 0;
		Start16On17(ccb, scratch);
		return;
	}
	QAppend(&q16to17, &ccb->qlink, ccb);
}

void
SIM17Init(void)
{
	int i;

	for (i = 0; i <= 3; i++) {
		HBAs[i].path = 0xFF;
		HBAs[i].devs = DEVs;
	}
	for (i = 0; i <= 0x1B; i++) {
		DEVs[i].id = 0xFF;
		simqStack[i] = &simqs[i];
	}
	simqTOS = 0x1C;
	timeq.prev = &timeq;
	timeq.next = &timeq;
}

int
SIMAddPath(void *mem, unsigned char path)
{
	int i;
	struct sim_hba *hba;
	unsigned char *base;
	struct sim_ccb *sns;
	unsigned int sns_len;
	int id, lun;

	for (i = 0; i <= 3; i++) {
		if (HBAs[i].path == 0xFF)
			break;
	}
	if (i > 3)
		return 1;
	hba = &HBAs[i];
	base = (unsigned char *)mem;
	hba->base = (struct sim_fwctx *)base;
	hba->fw = (struct sim_fw *)(base + 0x140);
	hba->path = path;
	hba->rom = PathToROMInfoPtr(path);
	hba->actq.next = &hba->actq;
	hba->actq.prev = &hba->actq;
	hba->snsq.next = &hba->snsq;
	hba->snsq.prev = &hba->snsq;
	sns_len = (unsigned int)MaxCCBPrivateLen + SIM_CCB_FIXEDLEN;
	hba->snsccb = (struct sim_ccb *)MemAlloc(sns_len);
	if (hba->snsccb == 0) {
		hba->path = 0xFF;
		return 1;
	}
	sns = hba->snsccb;
	SIMClearMem(sns, (unsigned short)sns_len);
	sns->ccb_len = (unsigned short)sns_len;
	sns->my_addr = VtoP(sns);
	sns->func_code = SIM_FUNC_IO;
	sns->path = hba->path;
	sns->flags0 = 0x28;
	sns->flags1 = 0x94;
	sns->cdb_len = 6;
	sns->cdb[0] = 3;
	sns->complete = 0;
	sns->qlink.next = &sns->qlink;
	sns->qlink.prev = &sns->qlink;
	for (id = 0; id <= 7; id++) {
		for (lun = 0; lun <= 7; lun++)
			hba->devmap[id][lun] = 0xFF;
	}
	if (FCalcSync(hba, 0xFF, 1) != 0) {
		hba->path = 0xFF;
		return 1;
	}
	hba->syncPeriod = *((unsigned char *)&hba->fw->sync);
	hba->syncOffset = hba->fw->lunmask;
	hba->fw->sync = 0;
	FWideInit(hba);
	hba->width = *((unsigned char *)&hba->fw->sync);
	hba->rsvd070 = 0;
	hba->fw->selid = 0x82;
	hba->fw->curid = 0xFF;
	hba->fw->active = 0;
	InitializeQueueTags(hba);
	return 0;
}

unsigned short
SIMActionInit(void)
{
	int nrom, i, slot;
	struct sim_rom *roms;
	unsigned int len;

	q16to17.prev = &q16to17;
	q16to17.next = &q16to17;
	q17to16.prev = &q17to16;
	q17to16.next = &q17to16;
	nrom = GetNumROMs();
	roms = GetROMTableBase();
	for (i = 0; i < nrom; i++) {
		if (roms[i].simType == SIM_ROM_TYPE17) {
			for (slot = 0; slot <= 6; slot++) {
				len = (unsigned int)MaxCCBPrivateLen
				    + SIM_CCB_FIXEDLEN;
				ccb17[slot] = (struct sim_ccb *)MemAlloc(len);
				if (ccb17[slot] == 0)
					return 1;
				SIMClearMem(ccb17[slot], (unsigned short)len);
				ccb17[slot]->my_addr = VtoP(ccb17[slot]);
				ccb17[slot]->ccb_len = (unsigned short)len;
			}
			break;
		}
	}
	for (i = 0; i < nrom; i++) {
		if (roms[i].simType == SIM_ROM_TYPE16) {
			for (slot = 0; slot <= 6; slot++) {
				ccb16[slot] = (struct sim16_ccb *)MemAlloc(
				    SIM16_CCB_LEN);
				if (ccb16[slot] == 0)
					return 1;
				SIMClearMem(ccb16[slot], SIM16_CCB_LEN);
			}
			break;
		}
	}
	return 0;
}

int
SIMInit(void *arg)
{
	int state, i, rc;

	state = DisableInterrupts();
	for (i = 0; i <= 3; i++) {
		ROMs[i].path = 0xFF;
		ROMs[i].simType = 0;
	}
	numROMs = 0;
	if (FindROMs() != 0)
		rc = 1;
	else if (SIMActionInit() != 0)
		rc = 1;
	else {
		SIM17Init();
		rc = InitROMs(arg);
	}
	RestoreInterrupts(state);
	return rc;
}

void
SIMStart(struct sim_ccb *ccb)
{
	unsigned short path, tgt, lun;
	struct sim_hba *hba;
	struct sim_dev *dev;
	unsigned int func;
	struct sim_ccb *target;
	int slot;
	unsigned int flags;

	path = ccb->path;
	tgt = ccb->target;
	lun = ccb->lun;
	for (hba = HBAs; hba < &HBAs[SYM_HBA_SLOTS]; hba++) {
		if ((unsigned short)hba->path == path)
			break;
	}
	if (hba >= &HBAs[SYM_HBA_SLOTS]) {
		ccb->status = 7;
		if (ccb->func_code == SIM_FUNC_IO) {
			ccb->xferCount = 0;
			CallComp(hba, ccb);
		}
		return;
	}
	if (hba->frozen[tgt] != 0) {
		ccb->status = 5;
		if (ccb->func_code == SIM_FUNC_IO) {
			ccb->xferCount = 0;
			CallComp(hba, ccb);
		}
		return;
	}
	dev = IDLUNToDP(hba, (unsigned char)tgt, (unsigned char)lun);
	if (dev == 0) {
		if (ccb->func_code == SIM_FUNC_IO
		    || ccb->func_code == SIM_FUNC_RESET_DEV) {
			AddToDeviceList(hba, tgt, lun);
			dev = IDLUNToDP(hba, (unsigned char)tgt,
					(unsigned char)lun);
			if (dev == 0) {
				if (ccb->func_code == SIM_FUNC_IO) {
					ccb->status = 8;
					ccb->xferCount = 0;
					CallComp(hba, ccb);
				} else {
					ccb->status = 1;
					CallComp(hba, ccb);
				}
				return;
			}
		}
	}
	func = ccb->func_code;
	if (func == 0 || func - 1 > 0x12)
		return;
	switch (func - 1) {
	case 0:
		ccb->status = 0;
		ccb->scsi_status = 0xFF;
		ccb->simFlags = 0;
		ccb->requeue = 1;
		if (ccb->timeout == 0xFFFFFFFF)
			ccb->deadline = 0;
		else if (ccb->timeout == 0)
			ccb->deadline = TickCount + 0xB4;
		else
			ccb->deadline = TickCount + ccb->timeout + 1;
		carldiag = ccb->deadline;
		QAppend(&timeq, &ccb->timelink, ccb);
		ccb->resid = ccb->dxfer_len;
		ccb->xferLeft = ccb->dxfer_len;
		ccb->xferCount = 0;
		dev = IDLUNToDP(hba, (unsigned char)tgt, (unsigned char)lun);
		if (dev != 0) {
			if (ccb->flags1 & 0x10)
				QInsert(dev->queue, &ccb->qlink, ccb);
			else
				QAppend(dev->queue, &ccb->qlink, ccb);
			hba->queued++;
		}
		if (hba->running == 0)
			SIMRun(path);
		return;
	case 3:
		dev = IDLUNToDP(hba, (unsigned char)tgt, (unsigned char)lun);
		if (dev != 0)
			dev->frozen = 0;
		ccb->status = 1;
		SIMInterrupt(0xFF);
		return;
	case 15:
	case 18:
		target = ccb->link_ccb;
		if (CCBInSIMQueue(hba, target)) {
			hba->queued--;
			QDelete(&target->qlink);
			QDelete(&target->timelink);
			target->status = 2;
			CallComp(hba, target);
			ccb->status = 1;
			return;
		}
		if (hba->fw->selid <= 0x7F && hba->fw->pending == target) {
			ccb->status = 1;
			return;
		}
		if (target->status != 0) {
			ccb->status = 1;
			return;
		}
		for (slot = 0; slot <= 7; slot++) {
			if (PendingAborts[slot] == 0)
				break;
		}
		if (slot > 7) {
			ccb->status = 1;
			return;
		}
		PendingAborts[slot] = ccb;
		ccb->status = 0;
		flags = target->simFlags;
		if (ccb->func_code == SIM_FUNC_ABORT)
			flags |= 0x80000000;
		else
			flags |= 0x40000000;
		target->simFlags = flags;
		target->simFlags |= 0x10000000;
		dev = IDLUNToDP(hba, ccb->target, ccb->lun);
		if (dev != 0) {
			if (ccb->func_code == SIM_FUNC_ABORT)
				dev->flags |= 4;
			else
				dev->flags |= 8;
		}
		if (hba->fw->active == target)
			hba->fw->abortFlag = 1;
		if (ccb->status == 0 && hba->running == 0) {
			do {
				SIMRun(path);
			} while (ccb->status == 0 && hba->running == 0);
		}
		ccb->status = 1;
		return;
	case 16:
		FResetBus(hba);
		RespondToBusReset(hba);
		FRun(hba);
		ccb->status = 1;
		return;
	case 17:
		dev = IDLUNToDP(hba, (unsigned char)tgt, 0);
		if (dev != 0) {
			dev->flags |= 0x10;
			if ((dev->flags & 0x10) != 0 && hba->running == 0) {
				do {
					SIMRun(path);
				} while ((dev->flags & 0x10) != 0
					 && hba->running == 0);
			}
		}
		ccb->status = 1;
		return;
	default:
		return;
	}
}

void
SIMRun(unsigned short path)
{
	struct sim_hba *hba;
	unsigned short result;
	int started;
	struct sim_fw *fw;
	struct sim_ccb *ccb;
	unsigned char tgt, lun;
	int cause;
	unsigned int id;
	unsigned char sel;

	result = 0;
	for (hba = HBAs; hba < &HBAs[SYM_HBA_SLOTS]; hba++) {
		if ((unsigned short)hba->path == path)
			break;
	}
	if (hba >= &HBAs[SYM_HBA_SLOTS])
		return;
	if (hba->running != 0)
		return;
	hba->running = 1;
	started = 0;
	for (;;) {
		if (started == 0) {
			if (hba->resume != 0) {
				hba->resume = 0;
				result = (unsigned short)FResumeXFer(hba);
			} else {
				result = (unsigned short)FRun(hba);
				CheckForStart(hba, 0);
			}
		}
		while (result == 0) {
			CheckForStart(hba, 1);
			result = (unsigned short)FRun(hba);
			sel = (unsigned char)(hba->fw->selid + 0x80);
			if (sel > 1)
				break;
			CheckForStart(hba, 0);
		}
		started = 1;
		if ((unsigned int)result > 0x0E)
			goto defcase;
		switch (result) {
		case 3:
			fw = hba->fw;
			if (hba->msgState == 7 && fw->msgFlag != 0
			    && (((fw->msgIn[1] & 0xFC) == 0x20)
				|| ((fw->msgIn[0] & 0xFC) == 0x20)
				|| (fw->msgIn[1] == 1 && fw->msgIn[3] == 3)
				|| (fw->msgIn[0] == 1 && fw->msgIn[2] == 3))) {
				hba->msgState = 8;
				fw->msgFlag = 0;
				fw->contFlag = 1;
				ccb = fw->pending;
				fw->selid = ccb->target;
				fw->sellun = (unsigned char)(ccb->lun | 0x80);
				goto defcase;
			}
			fw = hba->fw;
			ccb = fw->active;
			if (ccb == 0)
				ccb = fw->pending;
			tgt = ccb->target;
			lun = ccb->lun;
			cause = fw->resetCause;
			if (cause > 0x0D)
				cause = 0x0D;
			IOLog("BUS RESET issued due to '%s' on ha=%d id=%d lun=%d\n",
			      reset_cause[cause], (int)hba->path, (int)tgt,
			      (int)lun);
			FResetBus(hba);
			/* FALLTHROUGH */
		case 1:
			RespondToBusReset(hba);
			goto defcase;
		case 14:
			fw = hba->fw;
			SetFrag(fw->active, hba->base->initiatorId);
			result = (unsigned short)FResumeXFer(hba);
			goto after;
		case 2:
			result = RespondToComp(hba,
					       SIM_CCBP(hba->fw->completed));
			goto after;
		case 4:
			fw = hba->fw;
			tgt = (unsigned char)fw->sync;
			ccb = FindRunningRequest(hba, tgt, fw->lunmask & 7,
						 fw->tag);
			if (ccb == 0) {
				result = 3;
				continue;
			}
			fw->active = ccb;
			fw->curid = tgt;
			ccb->resid = ccb->xferLeft;
			SetFrag(ccb, hba->base->initiatorId);
			if (ccb->simFlags & 0xC0000000)
				fw->abortFlag = 1;
			id = tgt;
			hba->fw->msgOut = SIM_U32(&hba->resmsg[id * 4]);
			result = (unsigned short)FRespRes(hba);
			goto after;
		case 5:
			result = (unsigned short)GotMSG(hba, 1);
			goto after;
		case 6:
			result = (unsigned short)WantMSG(hba);
			goto after;
		default:
			break;
		}
	defcase:
		started = 0;
	after:
		if (result != 0)
			continue;
		break;
	}
	hba->running--;
}

void
SIMInterrupt(unsigned char irq)
{
	int state, i;
	struct sim_rom *rom;

	state = DisableInterrupts();
	if (irq == 0xFF) {
		for (i = 0; i < numROMs; i++) {
			rom = &ROMs[i];
			if (rom->active != 0) {
				if (rom->simType == SIM_ROM_TYPE17)
					SIMRun(rom->path);
				else
					SIM16Int(rom);
			}
		}
	} else {
		for (i = 0; i < numROMs; i++) {
			rom = &ROMs[i];
			if (rom->active != 0 && rom->irq == irq) {
				if (rom->simType == SIM_ROM_TYPE17)
					SIMRun(rom->path);
				else
					SIM16Int(rom);
			}
		}
	}
	RestoreInterrupts(state);
}

void
SIMTickTock(void)
{
	int state;
	struct sim_q *q;
	struct sim_ccb *ccb;
	struct sim_hba *hba;
	int i;
	unsigned char tgt, lun;
	unsigned int late;
	struct sim_dev *dev;

	state = DisableInterrupts();
	TickCount++;
	q = timeq.next;
	while (q != 0 && q != &timeq) {
		ccb = (struct sim_ccb *)q->owner;
		if (ccb->deadline == 0) {
			q = q->next;
			continue;
		}
		if (TickCount < ccb->deadline) {
			q = q->next;
			continue;
		}
		IOGetTimestamp(&EndTime);
		tgt = ccb->target;
		lun = ccb->lun;
		late = TickCount - ccb->deadline;
		for (i = 0; i <= 3; i++) {
			if (HBAs[i].path == ccb->path)
				break;
		}
		hba = &HBAs[i];
		if (CCBInSIMQueue(hba, ccb)) {
			hba->queued--;
			QDelete(&ccb->qlink);
			QDelete(&ccb->timelink);
			ccb->status = 0x0B;
			CallComp(hba, ccb);
			q = timeq.next;
			continue;
		}
		if (late > 0x32) {
			FResetBus(hba);
			RespondToBusReset(hba);
			q = timeq.next;
			continue;
		}
		ccb->simFlags |= 0x80000000;
		ccb->simFlags |= 2;
		dev = IDLUNToDP(hba, tgt, lun);
		if (dev != 0)
			dev->flags |= 4;
		if (hba->fw->active == ccb)
			hba->fw->abortFlag = 1;
		q = q->next;
	}
	RestoreInterrupts(state);
}

int
SIM16Action(struct sim16_ccb *ccb)
{
	int state;
	struct sim_rom *rom;
	int rc;

	state = DisableInterrupts();
	ccb->status = 0;
	rom = PathToROMInfoPtr(ccb->path);
	if (rom == 0) {
		ccb->status = 7;
		if (ccb->op == 2 && ccb->complete != 0)
			(*ccb->complete)(ccb);
		RestoreInterrupts(state);
		return (int)ccb;
	}
	if (ccb->op == 0x24) {
		SIMInterrupt(0xFF);
		RestoreInterrupts(state);
		return (int)ccb;
	}
	if (ccb->op == 0x22) {
		if (rom->simType == SIM_ROM_TYPE17)
			rom->ctx->intEnable = 0;
		(*rom->action)(rom->ctx, ccb);
		if (rom->simType == SIM_ROM_TYPE17)
			rom->ctx->intEnable = 1;
		RestoreInterrupts(state);
		return (int)ccb;
	}
	if (rom->simType == SIM_ROM_TYPE17) {
		Do16On17(ccb);
		if (ccb->flags & 0x81) {
			while (ccb->status == 0)
				SIMInterrupt(0xFF);
			RestoreInterrupts(state);
			return (int)ccb;
		}
		if (ccb->status != 0) {
			RestoreInterrupts(state);
			return (int)ccb;
		}
		RestoreInterrupts(state);
		return 0;
	}
	if (ccb->op == 2) {
		rc = SIM16Start(ccb);
		RestoreInterrupts(state);
		return rc;
	}
	ccb->status = 6;
	RestoreInterrupts(state);
	return (int)ccb;
}

int
SIM17Action(struct sim_ccb *ccb)
{
	int state;
	struct sim_rom *rom;
	struct sim_pathinq *inq;
	int width;
	int i;
	int rc;

	state = DisableInterrupts();
	ccb->status = 0;
	rom = PathToROMInfoPtr(ccb->path);
	if (rom == 0) {
		ccb->status = 7;
		rc = 0xFFFFFFFF;
		RestoreInterrupts(state);
		return rc;
	}
	if ((unsigned int)ccb->func_code == 0) {
		SIMInterrupt(0xFF);
		ccb->status = 1;
	} else if (ccb->func_code == SIM_FUNC_IO
		   || ccb->func_code == SIM_FUNC_REL_SIMQ
		   || (ccb->func_code >= SIM_FUNC_ABORT
		       && ccb->func_code <= SIM_FUNC_TERM_IO)) {
		if (rom->simType == SIM_ROM_TYPE17)
			SIMStart(ccb);
		else
			Do17On16(ccb);
	} else if (ccb->func_code == SIM_FUNC_PATH_INQ) {
		inq = (struct sim_pathinq *)ccb;
		inq->hdr[7] = 1;
		inq->version_num = 0x30;
		if (rom->simType == SIM_ROM_TYPE16)
			inq->hba_inquiry = 0;
		else {
			inq->hba_inquiry = 0x9A;
			width = (int)GetWidth(ccb->path);
			if (width > 0)
				inq->hba_inquiry |= 0x20;
			if (width > 1)
				inq->hba_inquiry |= 0x40;
		}
		inq->target_sprt = 0;
		inq->hba_eng_cnt = 0;
		inq->priv_data_size = (unsigned int)MaxCCBPrivateLen + 0x44;
		inq->async_flags = 0x13;
		inq->hba_path_id = rom->ctx->hbaType;
		for (i = 0; i <= 0x0F; i++)
			inq->sim_vid[i] = ourname_100[i];
		inq->sim_type = rom->simType;
		inq->initiator_id = rom->ctx->initiatorId;
		for (i = 0; i <= 0x0F; i++)
			inq->hba_vid[i] = rom->name[i];
	} else if (ccb->func_code == SIM_FUNC_ASYNC_CB)
		ccb->status = 1;
	else if ((ccb->func_code >= 0x20 && ccb->func_code <= 0x21)
		 || (ccb->func_code >= 0x30 && ccb->func_code <= 0x31))
		ccb->status = 0x3A;
	else if (ccb->func_code == SIM_FUNC_VENDOR) {
		CHSCCB.op = 0x22;
		CHSCCB.arg1 = (unsigned int)ccb->sense_ptr;
		CHSCCB.arg2 = (unsigned int)ccb->msg_ptr;
		CHSCCB.arg0 = (unsigned int)ccb->data;
		CHSCCB.opflags = 0x0C;
		if (rom->simType == SIM_ROM_TYPE17)
			rom->ctx->intEnable = 0;
		(*rom->action)(rom->ctx, &CHSCCB);
		if (rom->simType == SIM_ROM_TYPE17)
			rom->ctx->intEnable = 1;
		ccb->status = CHSCCB.status;
		ccb->rsvd08 = 0x6C;
	} else
		ccb->status = 6;
	RestoreInterrupts(state);
	return 0;
}

