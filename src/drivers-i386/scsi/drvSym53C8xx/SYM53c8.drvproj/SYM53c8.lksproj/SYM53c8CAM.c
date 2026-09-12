/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * SYM53c8CAM.c - CAM/XPT half of the NCR SDMS engine in SYM53c8_reloc.
 *
 * HISTORY
 *
 * Oct 1998	Created.
 *
 * Bodies follow IDA 9.2 of SYM53c8_reloc (divergences.md, "Method").
 * The SIM half lives in SYM53c8SIM.c. CAMcore SCRIPT bytes are the
 * __DATA,__data dump in SYM53c8Scripts.c.
 */

#import "SYM53c8SIM.h"
#import "SYM53c8Inline.h"
#import <driverkit/generalFuncs.h>
#import <objc/objc.h>
#import <objc/objc-runtime.h>
#import <kernserv/kern_server_types.h>

extern vm_task_t	IOVmTaskSelf(void);
extern int		IOPhysicalFromVirtual(vm_task_t, vm_offset_t, vm_offset_t *);
extern void		panic(const char *);

#define CAM_U8(p)	(*(unsigned char *)(void *)(p))
#define CAM_U16(p)	(*(unsigned short *)(void *)(p))
#define CAM_U32(p)	(*(unsigned int *)(void *)(p))
#define CAM_CCBP(p)	(*(struct sim_ccb **)(void *)(p))
#define CAM_FWB(fw, off)	(((unsigned char *)(void *)(fw))[off])
#define CAM_HBAB(h, off)	(((unsigned char *)(void *)(h))[off])
#define RAMCORE_OFF		2688
#define RAMCORE_PTR		(&SYM53c8Scripts[RAMCORE_OFF])
#define XPT_SIM_SLOTS		4
#define XPT_SIM_STRIDE		0x24
#define XPT_AEV_SLOTS		8
#define XPT_AEV_STRIDE		0x1C
#define DL_SLOTS		30
#define DL_STRIDE		192

extern unsigned char	SYM53c8Scripts[];
extern unsigned int	page_size;
extern unsigned int	page_mask;
extern unsigned char	Sync_dev[];
extern unsigned char	Wide_dev[];
extern int		vm_protect_EXTERNAL();
extern id		objc_msgSend(id, SEL, ...);
extern struct objc_selector *paLock;
extern struct objc_selector *paUnlockwith;
extern void		IOScheduleFunc(void (*fn)(), void *arg, int when);

struct xpt_sim {
	unsigned char		path;			/* +0x00 */
	unsigned char		initiatorId;		/* +0x01 */
	unsigned char		rsvd02[2];		/* +0x02 */
	unsigned int		(*action)();		/* +0x04 */
	unsigned int		ccb_len;		/* +0x08 */
	struct sim_ccb		*scan_ccb;		/* +0x0C */
	unsigned char		rsvd10[6];		/* +0x10 */
	unsigned char		byte16;			/* +0x16 */
	unsigned char		rsvd17[2];		/* +0x17 */
	unsigned char		byte19;			/* +0x19 */
	unsigned char		rsvd1A[6];		/* +0x1A */
	unsigned char		needscan;		/* +0x20 */
	unsigned char		found;			/* +0x21 */
	unsigned char		rsvd22[2];		/* +0x22 */
};

struct xpt_aev {
	unsigned char		mask;			/* +0x00 */
	unsigned char		rsvd01[3];		/* +0x01 */
	unsigned int		(*cb)();		/* +0x04 */
	unsigned char		*buf;			/* +0x08 */
	unsigned char		maxlen;			/* +0x0C */
	unsigned char		rsvd0D[3];		/* +0x0D */
	unsigned int		path;			/* +0x10 */
	unsigned int		id;			/* +0x14 */
	unsigned int		lun;			/* +0x18 */
};

struct xpt_bus {
	int			(*init)();		/* +0x00 */
	unsigned int		(*action)();		/* +0x04 */
};

void *			bios_rom_vap;
unsigned int		RAMcoreBase[2] = { 0x000C0000, 0 };
unsigned int		config32;
unsigned int		dlStack[DL_SLOTS];
int			dlFree;
unsigned char		datalists[DL_SLOTS * DL_STRIDE];
unsigned int		datacount;
unsigned char		bsiminited;
unsigned char		flag_112;
struct xpt_sim		SIMs[XPT_SIM_SLOTS];
int			numSIMs;
struct xpt_dev		Devtab[SYM_DEV_SLOTS];
int			numDevs;
struct xpt_aev		AEVs[XPT_AEV_SLOTS];
int			numAEVs;
int			newSIMs;
struct sim_ccb		*pi;
void			*pi_inq;
unsigned short		firstPath;
unsigned short		highPath;
int			haveBeenInitialized_94;
struct sim_ccb		*freeccb;
int			xptInited;
unsigned char		data[0x24];
static char		romSIMStr[21] = "BALLARD_SYNERGY_ROM_S";

static unsigned int	camcore(struct sim_hba *hba, unsigned char cmd);
static void		fw_put_msg(struct sim_fw *fw, unsigned char b);
static struct xpt_sim	*PathToSIMInfoPtr(unsigned char path);
static struct xpt_dev	*PathIDLUNToDeviceInfoPtr(unsigned char path,
						  unsigned char id,
						  unsigned char lun);
static unsigned int	xpt_sim_action(struct xpt_sim *sim, struct sim_ccb *ccb);
static void		xpt_wait_done(struct xpt_sim *sim, struct sim_ccb *ccb);
static void		cam_wait_action(struct xpt_sim *sim, struct sim_ccb *ccb);
void			CheckForStart(struct sim_hba *hba, int flag);
void			StartNewIO(struct sim_hba *hba);
unsigned int		WantMSG(struct sim_hba *hba);
unsigned int		GotMSG(struct sim_hba *hba, int flag);
void			ResetDevice(struct sim_hba *hba, unsigned int id,
				    unsigned int reason);
void			AbortedRequest(struct sim_hba *hba, struct sim_ccb *ccb);
int			bsim_doinit(void *arg);
int			InitStep(unsigned int path);
void			StuffAction(struct xpt_bus *bus);
int			BeginScan(struct xpt_sim *sim);
void			ScanStep(struct sim_ccb *ccb);
int			xpt_bus_register(struct xpt_bus *bus);
void			xpt_async(int opcode, unsigned int path,
				  unsigned int a, unsigned int b,
				  unsigned int c, unsigned int d);
void			ticktock(void *arg);
void			util_start_unit(struct sim_ccb *ccb, struct xpt_sim *sim);
unsigned int		GetCompleteMsg(struct sim_hba *hba);
unsigned int		GetMoreMsgBytes(struct sim_hba *hba);
unsigned int		DoBegin(struct sim_hba *hba, struct sim_dev *dp,
				struct sim_ccb *ccb);
void			SetQueueTag(struct sim_hba *hba, struct sim_ccb *ccb,
				    unsigned int force);
unsigned int		AddBufferToDatalist(struct sim_ccb *ccb,
					    unsigned char *virt,
					    unsigned int len);
unsigned int		BytesInDatalist(struct sim_ccb *ccb);
int			xpt_init(void);
int			XPTInit(unsigned short first);
struct sim_ccb		*xpt_ccb_alloc(void);
void			xpt_ccb_free(struct sim_ccb *ccb);
int			xpt_action(struct sim_ccb *ccb);

/*
 * CAMcore: write command at [*(HBA+4)+0x14], call [*(HBA+0x100)+0x0C]
 * with (rom->ctx, 0), return result at +0x15. Named __text has no in/out.
 */
static unsigned int
camcore(struct sim_hba *hba, unsigned char cmd)
{
	struct sim_rom *rom;
	unsigned int (*fn)();

	hba->fw->command = cmd;
	rom = hba->rom;
	fn = rom->run;
	fn(rom->ctx, 0);
	return (unsigned int)hba->fw->result;
}

static unsigned int
camcore_selcheck(struct sim_hba *hba, unsigned char cmd)
{
	camcore(hba, cmd);
	if ((unsigned char)(hba->fw->selid + 0x80) <= 1)
		CheckForStart(hba, 0);
	return (unsigned int)hba->fw->result;
}

static void
fw_put_msg(struct sim_fw *fw, unsigned char b)
{
	unsigned short n;

	n = CAM_U16(&fw->sync);
	CAM_FWB(fw, 0x2A + n) = b;
	CAM_U16(&fw->sync) = (unsigned short)(n + 1);
}

/* ---------------- memory / virt-to-phys ---------------- */

void *
MemAlloc(unsigned int size)
{
	return IOMalloc(size);
}

void *
xMemAlloc(unsigned int size)
{
	return IOMalloc(size);
}

void
MemFree(void *mem, unsigned int size)
{
	IOFree(mem, size);
}

unsigned int
VtoP(void *virt)
{
	vm_offset_t phys;
	vm_task_t task;

	task = IOVmTaskSelf();
	if (IOPhysicalFromVirtual(task, (vm_offset_t)virt, &phys) != 0)
		return 0;
	return (unsigned int)phys;
}

unsigned int
xVtoP(void *virt)
{
	vm_offset_t phys;

	if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_offset_t)virt, &phys) != 0)
		return 0;
	return (unsigned int)phys;
}

unsigned int
CVtoP(void *virt, vm_task_t task)
{
	vm_offset_t phys;
	int rc;

	rc = IOPhysicalFromVirtual(task, (vm_offset_t)virt, &phys);
	if (rc != 0) {
		IOLog("Error converting VtoP %x\n", rc);
		return 0;
	}
	return (unsigned int)phys;
}

void *
PtoV(unsigned int phys)
{
	unsigned int off;

	if (bios_rom_vap == 0)
		return 0;
	off = phys - 0xE0000;
	if (off > 0x3FFFF)
		return 0;
	return (void *)(phys + (unsigned int)bios_rom_vap + 0xFFF20000);
}

void *
GlobMemAlloc(unsigned int size)
{
	unsigned char *raw, *aligned, *end;

	raw = IOMalloc(size + page_size);
	aligned = (unsigned char *)(((unsigned int)raw + page_mask) & ~page_mask);
	end = aligned + size;
	if (end > raw + size + page_size)
		panic("GlobMemAlloc\n");
	return aligned;
}

void *
GetScreenPtr(void)
{
	return 0;
}

int
xDisableInterrupts(void)
{
	return 0;
}

void
xRestoreInterrupts(int state)
{
}

void
XPTClearMem(void *mem, unsigned short len)
{
	unsigned short i;

	for (i = 0; i < len; i++)
		((unsigned char *)mem)[i] = 0;
}

/* ---------------- print helpers ---------------- */

void
PutString(char *s)
{
	IOLog("%s", s);
}

void
PutChar(unsigned char c)
{
	IOLog("%c", c);
}

void
puthex(unsigned char n)
{
	n &= 0x0F;
	if (n > 9)
		PutChar((unsigned char)(n + 0x37));
	else
		PutChar((unsigned char)((n | 0x30) & 0x3F));
}

void
putbyte(unsigned char n)
{
	puthex((unsigned char)(n >> 4));
	puthex(n);
}

void
PutWord(unsigned short w)
{
	putbyte((unsigned char)(w >> 8));
	putbyte((unsigned char)w);
}

void
PrintNexus(unsigned char path, unsigned char id, unsigned char lun)
{
	IOLog("PATH %d, ID %d, LUN %d ", path, id, lun);
}

void
xPutString(char *s)
{
	IOLog("%s", s);
}

void
xPutChar(unsigned char c)
{
	IOLog("%c", c);
}

void
puthex_0(unsigned char n)
{
	n &= 0x0F;
	if (n > 9)
		xPutChar((unsigned char)(n + 0x37));
	else
		xPutChar((unsigned char)((n | 0x30) & 0x3F));
}

void
putbyte_0(unsigned char n)
{
	puthex_0((unsigned char)(n >> 4));
	puthex_0(n);
}

void
xPutWord(unsigned short w)
{
	putbyte_0((unsigned char)(w >> 8));
	putbyte_0((unsigned char)w);
}

void
xPrintNexus(unsigned char path, unsigned char id, unsigned char lun)
{
	IOLog("PATH %d, ID %d, LUN %d ", path, id, lun);
}

void
ROMSearchComplete(void)
{
	IOLog("ROMSearchComplete unmap ROM etc...\n");
}

void
ROMIntAndDMA(unsigned char a, unsigned char b, unsigned int c, unsigned int d)
{
	IOLog("intnum = %d dmachan = %d ROM addr 0x%lux ROM len %lud\n",
	      a, b, c, d);
}

void
BusNowOperational(unsigned int path, unsigned char irq, unsigned short addr)
{
	IOLog("BusNowOperational path = %ld intnum = %d ROM addr 0x%x\n",
	      path, irq, addr);
}

/* ---------------- ROM window ---------------- */

int
IsRAMSeg(unsigned short seg)
{
	int i;

	if (RAMcoreBase[0] == 0)
		return 0;
	for (i = 0; RAMcoreBase[i] != 0; i++) {
		if ((int)RAMcoreBase[i] >> 4 == (int)seg)
			return 1;
	}
	return 0;
}

void *
ROMGetAddress(unsigned short seg, unsigned short off)
{
	if (IsRAMSeg(seg))
		return RAMCORE_PTR + off;
	return PtoV(((unsigned int)seg << 4) + off);
}

unsigned int
ROMReadByte(unsigned short seg, unsigned short off)
{
	unsigned char *p;

	if (IsRAMSeg(seg))
		p = RAMCORE_PTR + off;
	else
		p = PtoV(((unsigned int)seg << 4) + off);
	if (flag_112 != 0)
		flag_112 = 0;
	return p[0];
}

unsigned int
ROMReadWord(unsigned short seg, unsigned short off)
{
	unsigned char *p;

	if (IsRAMSeg(seg))
		p = RAMCORE_PTR + off;
	else
		p = PtoV(((unsigned int)seg << 4) + off);
	return *(unsigned short *)(void *)p;
}

unsigned int
ROMReadLong(unsigned short seg, unsigned short off)
{
	unsigned char *p;

	if (IsRAMSeg(seg))
		p = RAMCORE_PTR + off;
	else
		p = PtoV(((unsigned int)seg << 4) + off);
	return *(unsigned int *)(void *)p;
}

void *
ROMMakeCopy(unsigned short seg, unsigned short off, unsigned short len)
{
	unsigned char *dst, *src, *p;
	unsigned short n;

	dst = GlobMemAlloc(len);
	p = dst;
	if (dst == 0)
		return 0;
	if (IsRAMSeg(seg))
		src = RAMCORE_PTR + off;
	else
		src = PtoV(((unsigned int)seg << 4) + off);
	n = len;
	while (n) {
		*p++ = *src++;
		n--;
	}
	return dst;
}

void
ROMCopyPatched(void *base, unsigned short len)
{
	int rc;

	rc = vm_protect_EXTERNAL(IOVmTaskSelf(), (vm_offset_t)base, len, 0, 5);
	if (rc != 0)
		IOLog("vm_protect failed rc = %d\n", rc);
}

/* ---------------- F* CAMcore commands ---------------- */

unsigned int
FRun(struct sim_hba *hba)
{
	return camcore(hba, 2);
}

unsigned int
FRespRes(struct sim_hba *hba)
{
	return camcore_selcheck(hba, 3);
}

unsigned short
FCalcSync(struct sim_hba *hba, unsigned int id, unsigned int flag)
{
	hba->fw->command = 4;
	CAM_U16(&hba->fw->sync) = (unsigned short)id;
	CAM_U16(&hba->fw->lunmask) = (unsigned short)flag;
	return (unsigned short)camcore_selcheck(hba, 4);
}

unsigned int
FSetSync(struct sim_hba *hba, unsigned int a, unsigned int b,
	 unsigned int c, unsigned int d)
{
	struct sim_fw *fw;

	fw = hba->fw;
	fw->command = 5;
	CAM_U16(&fw->sync) = (unsigned short)a;
	CAM_U16(&fw->lunmask) = (unsigned short)b;
	CAM_U16(&fw->tag) = (unsigned short)(c & 0xFF);
	CAM_U16(&fw->resetCause) = (unsigned short)(d & 0xFF);
	return camcore_selcheck(hba, 5);
}

unsigned int
FGetMsgByte(struct sim_hba *hba)
{
	return camcore_selcheck(hba, 7);
}

unsigned int
FMsgResponse(struct sim_hba *hba)
{
	return camcore_selcheck(hba, 8);
}

unsigned int
FSendMsg(struct sim_hba *hba)
{
	return camcore_selcheck(hba, 9);
}

unsigned int
FResetBus(struct sim_hba *hba)
{
	return camcore_selcheck(hba, 0x0A);
}

unsigned int
FResumeXFer(struct sim_hba *hba)
{
	return camcore_selcheck(hba, 0x0D);
}

void
FWideInit(struct sim_hba *hba)
{
	hba->fw->command = 0x0E;
	CAM_U32(hba->fw->completed) = (unsigned int)hba;
	camcore_selcheck(hba, 0x0E);
}

unsigned int
FSetWide(struct sim_hba *hba, unsigned int a, unsigned int b, unsigned int c)
{
	struct sim_fw *fw;

	fw = hba->fw;
	fw->command = 0x0F;
	CAM_U16(&fw->sync) = (unsigned short)(a & 0xFF);
	CAM_U16(&fw->tag) = (unsigned short)(b & 0xFF);
	CAM_U16(&fw->resetCause) = (unsigned short)(c & 0xFF);
	return camcore_selcheck(hba, 0x0F);
}

int
GetIRQ(unsigned int slot)
{
	struct sim_hba *hba;
	int irq;

	irq = -1;
	if ((int)(GetNumROMs() - 1) < (int)slot)
		return -1;
	hba = &HBAs[slot];
	if (((unsigned char *)hba->base)[2] == 0)
		return irq;
	if (hba->path == 0xFF)
		return irq;
	return ((unsigned char *)hba->base)[4];
}

/* ---------------- glue ---------------- */

void
requestCompleted(struct sim_ccb *ccb)
{
	struct _scsireq *req;

	req = *(struct _scsireq **)(void *)&ccb->rsvd18[0];
	objc_msgSend(req->reqLock, (SEL)paLock);
	objc_msgSend(req->reqLock, (SEL)paUnlockwith, 1);
}

void
ticktock(void *arg)
{
	SIMTickTock();
	IOScheduleFunc(ticktock, arg, 1);
}

static unsigned int
xpt_sim_action(struct xpt_sim *sim, struct sim_ccb *ccb)
{
	return sim->action(ccb);
}

static void
xpt_wait_done(struct xpt_sim *sim, struct sim_ccb *ccb)
{
	while (ccb->status == 0)
		sim->action((struct sim_ccb *)((char *)sim + 0x10));
}

static void
cam_wait_action(struct xpt_sim *sim, struct sim_ccb *ccb)
{
	sim->action(ccb);
	xpt_wait_done(sim, ccb);
}

static unsigned int
hba_resmsg(struct sim_hba *hba, unsigned int id)
{
	return CAM_U32(&hba->resmsg[id * 4]);
}

static void
hba_set_resmsg(struct sim_hba *hba, unsigned int id, unsigned int v)
{
	CAM_U32(&hba->resmsg[id * 4]) = v;
}

static unsigned int (*rom_fn8(struct sim_rom *rom))()
{
	return *(unsigned int (**)())(void *)((char *)rom + 8);
}

/* ---------------- device table ---------------- */

struct sim_dev *
AddToDeviceList(struct sim_hba *hba, unsigned int id, unsigned int lun)
{
	int slot;
	struct sim_dev *dp;
	struct sim_q *q;

	for (slot = 0; slot <= 0x1B; slot++) {
		if (DEVs[slot].id == 0xFF)
			break;
	}
	if (slot > 0x1B)
		return 0;
	hba->devmap[id][lun] = (unsigned char)slot;
	dp = &DEVs[slot];
	dp->path = hba->path;
	dp->id = (unsigned char)id;
	dp->lun = (unsigned char)lun;
	simqTOS--;
	q = simqStack[simqTOS];
	dp->queue = q;
	q->next = q;
	q->prev = q;
	dp->frozen = 0;
	dp->sync = 0;
	dp->wide = 0;
	dp->flags = 2;
	TotalDEVs++;
	return dp;
}

void
DeletePathFromDeviceTable(unsigned char path)
{
	int i, j;

	for (i = 0; i < numDevs; ) {
		if (Devtab[i].path != path) {
			i++;
			continue;
		}
		for (j = i + 1; j < numDevs; j++) {
			unsigned int *dst = (unsigned int *)(void *)&Devtab[i];
			unsigned int *src = (unsigned int *)(void *)&Devtab[j];
			int n;

			for (n = 0; n < SYM_DEVTAB_DWORDS; n++)
				dst[n] = src[n];
		}
		numDevs--;
	}
}

static struct xpt_sim *
PathToSIMInfoPtr(unsigned char path)
{
	int i;
	struct xpt_sim *sim;

	sim = SIMs;
	for (i = 0; i < numSIMs; i++, sim++) {
		if (sim->path == path)
			return sim;
	}
	return 0;
}

static struct xpt_dev *
PathIDLUNToDeviceInfoPtr(unsigned char path, unsigned char id, unsigned char lun)
{
	int i;
	struct xpt_dev *d;

	d = Devtab;
	for (i = 0; i < numDevs; i++, d++) {
		if (d->path == path && d->id == id && d->lun == lun)
			return d;
	}
	return 0;
}

void
InitializeQueueTags(struct sim_hba *hba)
{
	int i;

	for (i = 0; i <= 0x7F; i++)
		CAM_HBAB(hba, 0x7B + i) = (unsigned char)(i + 3);
	CAM_HBAB(hba, 0xFB) = 0x80;
}

struct sim_ccb *
FindRunningRequest(struct sim_hba *hba, unsigned int id, unsigned int lun,
		   unsigned int tag)
{
	struct sim_q *q;
	struct sim_ccb *ccb;

	q = hba->actq.next;
	if (q == 0)
		return 0;
	while (q != &hba->actq) {
		ccb = (struct sim_ccb *)q->owner;
		if (ccb->target == (unsigned char)id &&
		    ccb->lun == (unsigned char)lun &&
		    (unsigned short)ccb->requeue == (unsigned short)tag)
			return ccb;
		q = q->next;
		if (q == 0)
			break;
	}
	return 0;
}

void
SetQueueTag(struct sim_hba *hba, struct sim_ccb *ccb, unsigned int force)
{
	struct sim_dev *dp;
	unsigned char tag;
	unsigned int id, lun;

	id = ccb->target;
	lun = ccb->lun;
	dp = IDLUNToDP(hba, (unsigned char)id, (unsigned char)lun);
	tag = 0;
	if (ccb->cdb[0] == 3)
		tag = 2;
	else if (dp->rsvd0C[0] > 0x7F)
		tag = 0;
	else if ((ccb->flags0 & 2) == 0)
		tag = 0;
	else if ((dp->flags & 3) == 2)
		tag = 0;
	else if (force != 0)
		tag = 2;
	else if (CAM_HBAB(hba, 0xFB) != 0) {
		CAM_HBAB(hba, 0xFB)--;
		tag = CAM_HBAB(hba, 0x7B + CAM_HBAB(hba, 0xFB));
	}
	if (tag == 0) {
		if (dp->rsvd0C[0] == 0) {
			dp->rsvd0C[0] = 0xFF;
			if ((int)id <= 7)
				CAM_FWB(hba->fw, lun + id * 8 + 0x32) = 0xFF;
		}
	} else {
		dp->rsvd0C[0]++;
		if ((int)id <= 7)
			CAM_FWB(hba->fw, lun + id * 8 + 0x32)++;
	}
	ccb->requeue = tag;
}

void
FreeQueueTag(struct sim_hba *hba, struct sim_ccb *ccb)
{
	struct sim_dev *dp;
	unsigned int id, lun;

	if (ccb->requeue == 1)
		return;
	id = ccb->target;
	lun = ccb->lun;
	dp = IDLUNToDP(hba, (unsigned char)id, (unsigned char)lun);
	if (dp->rsvd0C[0] == 0xFF) {
		dp->rsvd0C[0] = 0;
		if ((int)id <= 7)
			CAM_FWB(hba->fw, lun + id * 8 + 0x32) = 0;
	} else {
		dp->rsvd0C[0]--;
		if ((int)id <= 7)
			CAM_FWB(hba->fw, lun + id * 8 + 0x32)--;
	}
	if ((dp->flags & 3) == 0 && ccb->scsi_status == 0) {
		dp->flags &= 0xFC;
		dp->flags |= 3;
	}
	if (ccb->requeue != 2) {
		CAM_HBAB(hba, 0x7B + CAM_HBAB(hba, 0xFB)) = ccb->requeue;
		CAM_HBAB(hba, 0xFB)++;
	}
	ccb->requeue = 1;
}

void
AbortedRequest(struct sim_hba *hba, struct sim_ccb *ccb)
{
	struct sim_dev *dp;

	dp = IDLUNToDP(hba, ccb->target, ccb->lun);
	FreeQueueTag(hba, ccb);
	QDelete(&ccb->qlink);
	QDelete(&ccb->timelink);
	if (ccb->simFlags & 2)
		ccb->status = 0x0B;
	else
		ccb->status = 2;
	if ((ccb->flags1 & 4) == 0) {
		dp->frozen = 1;
		ccb->status |= 0x40;
	}
	CallComp(hba, ccb);
}

void
AutosenseSetup(struct sim_hba *hba)
{
	struct sim_ccb *sns, *parent;
	struct sim_q *q;

	if (hba->snscount == 0)
		return;
	sns = hba->snsccb;
	if (sns->link_ccb != 0)
		return;
	if (hba->snsq.next == 0)
		return;
	if (hba->snsq.next == &hba->snsq)
		return;
	q = hba->snsq.next;
	parent = (struct sim_ccb *)q->owner;
	sns->target = parent->target;
	sns->lun = parent->lun;
	sns->flags0 &= 0x3F;
	sns->flags0 |= (unsigned char)(parent->flags0 & 2);
	if (parent->sense_len != 0 && parent->sense_ptr != 0) {
		sns->flags0 |= 0x40;
		sns->data = parent->sense_ptr;
		sns->dxfer_len = parent->sense_len;
		sns->cdb[4] = (unsigned char)sns->dxfer_len;
	} else {
		sns->flags0 |= 0xC0;
		sns->data = 0;
		sns->dxfer_len = 0;
		sns->cdb[4] = 0;
	}
	sns->cdb[1] = (unsigned char)(sns->lun << 5);
	sns->resid = sns->dxfer_len;
	sns->xferLeft = sns->dxfer_len;
	sns->deadline = 0;
	sns->link_ccb = parent;
}

void
CheckForStart(struct sim_hba *hba, int flag)
{
	struct sim_fw *fw;
	struct sim_ccb *ccb;
	unsigned int selid;

	fw = hba->fw;
	selid = fw->selid;
	if (selid == 0x80) {
		ccb = fw->pending;
		if (ccb != 0) {
			if (hba->snsccb == ccb) {
				QDelete(&ccb->link_ccb->qlink);
			} else {
				hba->queued--;
				QDelete(&ccb->qlink);
				QAppend(&hba->actq, &ccb->qlink, ccb);
			}
		}
		fw->selid = 0x82;
	} else if (selid == 0x81) {
		ccb = fw->pending;
		if (ccb != 0) {
			FreeQueueTag(hba, ccb);
			if (hba->snsccb == ccb && ccb->deadline < TickCount) {
				ccb->scsi_status = 2;
				RespondToComp(hba, ccb);
			}
		}
		fw->selid = 0x82;
	} else if (selid == 0x82)
		fw->selid = 0x82;
	if (flag != 0)
		StartNewIO(hba);
}

/* ---------------- datalist / transfer ---------------- */

unsigned short
PeekAtData(struct sim_ccb *ccb, int off)
{
	return ((unsigned char *)ccb->data)[off];
}

void
DoneWithCurrentData(struct sim_ccb *ccb)
{
	datacount = 0;
	CAM_U16(&ccb->rsvd7A[0]) = 0;
	CAM_U32(&ccb->rsvd70[0]) = CAM_U32(&ccb->rsvd7A[2]);
}

unsigned int
BytesInDatalist(struct sim_ccb *ccb)
{
	unsigned int sum, i, n;
	unsigned int *dl;

	sum = 0;
	n = CAM_U16(&ccb->rsvd7A[0]);
	dl = (unsigned int *)CAM_U32(&ccb->rsvd70[0]);
	for (i = 0; i < n; i++)
		sum += dl[i * 3];
	return sum;
}

void
PreTransfer17(struct sim_ccb *ccb, unsigned int initiatorId)
{
	void *dl;
	void *cdbvirt;

	(void)initiatorId;
	if (dlFree == 0) {
		ccb->xferCount = 0;
		return;
	}
	ccb->xferCount = 0x10;
	CAM_U16(&ccb->rsvd7A[0]) = 0;
	dlFree--;
	dl = (void *)dlStack[dlFree];
	CAM_U32(&ccb->rsvd70[0]) = (unsigned int)dl;
	CAM_U32(&ccb->rsvd70[4]) = VtoP(dl);
	CAM_U32(&ccb->rsvd7A[2]) = (unsigned int)dl;
	ccb->my_addr = VtoP(ccb);
	if (ccb->flags0 & 1)
		cdbvirt = *(void **)(void *)ccb->cdb;
	else
		cdbvirt = ccb->cdb;
	CAM_U32(&ccb->rsvd84[4]) = (unsigned int)cdbvirt;
	CAM_U32(&ccb->rsvd84[0]) = VtoP(cdbvirt);
	datacount = 0;
}

void
PostTransfer17(struct sim_ccb *ccb, unsigned int initiatorId)
{
	(void)initiatorId;
	if (ccb->xferCount == 0)
		return;
	if (CAM_U32(&ccb->rsvd7A[2]) == 0)
		return;
	dlStack[dlFree] = CAM_U32(&ccb->rsvd7A[2]);
	dlFree++;
	ccb->xferCount = 0;
	CAM_U32(&ccb->rsvd7A[2]) = 0;
}

void
PreTransfer16(struct sim16_ccb *ccb, unsigned int initiatorId)
{
	int i;

	(void)initiatorId;
	if ((short)ccb->byte10 < 0)
		return;
	CAM_U16((char *)ccb + 0x56) = 0;
	CAM_U32((char *)ccb + 0x5C) = ccb->arg0;
	CAM_U16((char *)ccb + 0x68) = ccb->w12;
	for (i = 0; i <= 0xF; i++)
		((unsigned char *)ccb)[0x6A + i] = ccb->cdb[i];
	CAM_U32((char *)ccb + 0x58) = VtoP((void *)CAM_U32((char *)ccb + 0x5C));
}

void
PostTransfer16(struct sim16_ccb *ccb)
{
	(void)ccb;
}

unsigned int
AddBufferToDatalist(struct sim_ccb *ccb, unsigned char *virt, unsigned int len)
{
	vm_task_t task;
	unsigned int *dl;
	unsigned int n, chunk, pages, aligned;
	struct _scsireq *req;

	req = *(struct _scsireq **)(void *)&ccb->rsvd18[0];
	task = (vm_task_t)req->client;
	if (ccb->func_code == 3)
		task = IOVmTaskSelf();
	if (ccb->osd_rsvd != 0xBEEFBEEF)
		task = IOVmTaskSelf();
	if (CAM_U16(&ccb->rsvd7A[0]) >= ccb->xferCount)
		return (len != 0);
	if (len == 0)
		return 0;
	aligned = ((unsigned int)virt + page_mask) & ~page_mask;
	if (aligned != (unsigned int)virt) {
		chunk = aligned - (unsigned int)virt;
		if (len <= chunk) {
			chunk = len;
			len = 0;
		} else
			len -= chunk;
		n = CAM_U16(&ccb->rsvd7A[0]);
		dl = (unsigned int *)CAM_U32(&ccb->rsvd70[0]);
		dl[n * 3] = chunk;
		dl[n * 3 + 1] = (unsigned int)virt;
		dl[n * 3 + 2] = CVtoP(virt, task);
		CAM_U16(&ccb->rsvd7A[0]) = (unsigned short)(n + 1);
		virt += chunk;
	}
	pages = 0;
	while (len >= page_size) {
		if ((int)pages > 0xF)
			break;
		n = CAM_U16(&ccb->rsvd7A[0]);
		dl = (unsigned int *)CAM_U32(&ccb->rsvd70[0]);
		dl[n * 3] = page_size;
		dl[n * 3 + 1] = (unsigned int)virt;
		dl[n * 3 + 2] = CVtoP(virt, task);
		CAM_U16(&ccb->rsvd7A[0]) = (unsigned short)(n + 1);
		len -= page_size;
		virt += page_size;
		pages++;
	}
	if (len != 0 && (int)pages <= 0xF) {
		n = CAM_U16(&ccb->rsvd7A[0]);
		dl = (unsigned int *)CAM_U32(&ccb->rsvd70[0]);
		dl[n * 3] = len;
		dl[n * 3 + 1] = (unsigned int)virt;
		dl[n * 3 + 2] = CVtoP(virt, task);
		CAM_U16(&ccb->rsvd7A[0]) = (unsigned short)(n + 1);
		len = 0;
	}
	return (len != 0);
}

void
SetFrag(struct sim_ccb *ccb, unsigned int initiatorId)
{
	unsigned int done, i, nsg;
	unsigned int *sg;
	unsigned int off;

	(void)initiatorId;
	if ((ccb->flags0 & 0xC0) == 0 || (ccb->flags0 & 0xC0) == 0xC0)
		return;
	if (ccb->dxfer_len == 0 || ccb->resid == 0)
		return;
	DoneWithCurrentData(ccb);
	off = ccb->dxfer_len - ccb->resid;
	if (ccb->flags0 & 0x10) {
		sg = (unsigned int *)ccb->data;
		nsg = ccb->sglist_cnt;
		done = 0;
		for (i = 0; i < nsg; i++) {
			if (off < done + sg[1]) {
				unsigned int skip = (done < off) ? (off - done) : 0;

				if (!AddBufferToDatalist(ccb,
				    (unsigned char *)sg[0] + skip, sg[1] - skip))
					break;
			}
			done += sg[1];
			sg += 2;
		}
	} else {
		AddBufferToDatalist(ccb, (unsigned char *)ccb->data + off, ccb->resid);
	}
	if (ccb->resid > BytesInDatalist(ccb))
		ccb->simFlags |= 4;
	else
		ccb->simFlags &= ~4U;
}

unsigned int
DoBegin(struct sim_hba *hba, struct sim_dev *dp, struct sim_ccb *ccb)
{
	struct sim_fw *fw;

	if (ccb->xferCount == 0) {
		PreTransfer17(ccb, hba->base->initiatorId);
		if (ccb->xferCount == 0)
			return 0;
	}
	SetFrag(ccb, hba->base->initiatorId);
	if (ccb->flags1 & 0x40) {
		if (dp->sync & 1)
			dp->sync = 1;
		else
			dp->sync = 2;
	} else if (ccb->flags1 & 0x20) {
		if (dp->sync & 1)
			dp->sync = 3;
		else
			dp->sync = 0;
	}
	fw = hba->fw;
	fw->pending = ccb;
	if ((CAM_U32(&dp->frozen) & 0x40200) == 0 &&
	    ccb->requeue != 0 && ccb->requeue != 2 && (dp->flags & 3) == 0) {
		fw->contFlag = 1;
		fw->sellun = (unsigned char)(ccb->lun | 0xC0);
		if ((char)ccb->flags1 >= 0 && ccb->requeue == 2)
			fw->sellun &= 0xBF;
		fw->msgFlag = 1;
		ccb->simFlags |= 0x20000000;
	} else {
		fw->msgFlag = 0;
		fw->contFlag = 1;
		fw->sellun = (unsigned char)(ccb->lun | 0xC0);
		if ((char)ccb->flags1 >= 0 && ccb->requeue == 2)
			fw->sellun &= 0xBF;
		if (ccb->requeue != 0 && ccb->requeue != 2) {
			fw->tag = (unsigned char)((ccb->tag_action & 3) | 0x20);
			fw->lunmask = ccb->requeue;
			fw->contFlag = 3;
		}
	}
	fw->msgOut = hba_resmsg(hba, ccb->target);
	fw->selid = ccb->target;
	return 1;
}

void
StartNewIO(struct sim_hba *hba)
{
	struct sim_ccb *sense;
	struct sim_dev *dp;
	struct sim_q *q;
	struct sim_ccb *ccb;
	unsigned int walked, id, lun;
	struct sim_fw *fw;

	if (hba->fw->selid <= 0x7F)
		return;
	sense = 0;
	ccb = hba->snsccb;
	if (ccb->link_ccb != 0 && hba->snsq.next != 0 &&
	    hba->snsq.next != &hba->snsq &&
	    ((struct sim_ccb *)hba->snsq.next->owner) == ccb->link_ccb) {
		sense = ccb;
		if (sense->xferCount == 0) {
			PreTransfer17(sense, hba->base->initiatorId);
			if (sense->xferCount == 0)
				return;
		}
		SetFrag(sense, hba->base->initiatorId);
		sense->requeue = 1;
		SetQueueTag(hba, sense, 1);
		if (sense->requeue == 1)
			return;
		if (sense->deadline == 0)
			sense->deadline = 0xE6;
	} else if (ccb->link_ccb == 0) {
		if ((unsigned short)CAM_HBAB(hba, 0x70) >= TotalDEVs)
			CAM_HBAB(hba, 0x70) = 0;
		walked = 0;
		if (TotalDEVs != 0) {
			do {
				if (walked != 0) {
					CAM_HBAB(hba, 0x70)++;
					if ((unsigned short)CAM_HBAB(hba, 0x70) >= TotalDEVs)
						CAM_HBAB(hba, 0x70) = 0;
				}
				dp = &DEVs[CAM_HBAB(hba, 0x70)];
				if (dp->id == 0xFF) {
					CAM_HBAB(hba, 0x70) = 0;
					goto next_dev;
				}
				if (dp->path != hba->path)
					goto next_dev;
				if (dp->flags & 0x1C) {
					if (hba->fw->curid != dp->id)
						goto skip_ident;
				}
				q = dp->queue;
				if (q->next == 0 || q->next == q)
					goto next_dev;
				if (dp->rsvd0C[0] > 0x7F || dp->frozen != 0)
					goto next_dev;
				ccb = (struct sim_ccb *)q->next->owner;
				if (hba->snscount != 0 && (ccb->flags1 & 0x10) == 0)
					goto next_dev;
				SetQueueTag(hba, ccb, 0);
				if (ccb->requeue == 1)
					goto next_dev;
				if (DoBegin(hba, dp, ccb) != 0)
					return;
				FreeQueueTag(hba, ccb);
			next_dev:
				walked++;
			} while ((int)walked < (int)TotalDEVs);
		}
	}
skip_ident:
	if (sense == 0)
		return;
	id = sense->target;
	lun = sense->lun;
	dp = IDLUNToDP(hba, (unsigned char)id, (unsigned char)lun);
	if (sense->flags1 & 0x40) {
		if (dp->sync & 1)
			dp->sync = 1;
		else
			dp->sync = 2;
	} else if (sense->flags1 & 0x20) {
		if (dp->sync & 1)
			dp->sync = 3;
		else
			dp->sync = 0;
	}
	fw = hba->fw;
	fw->pending = sense;
	if ((CAM_U32(&dp->frozen) & 0x40200) == 0 &&
	    sense->requeue != 0 && sense->requeue != 2 && (dp->flags & 3) == 0) {
		fw->contFlag = 1;
		fw->sellun = (unsigned char)(lun | 0xC0);
		if ((char)sense->flags1 >= 0 && sense->requeue == 2)
			fw->sellun &= 0xBF;
		fw->msgFlag = 1;
		sense->simFlags |= 0x20000000;
	} else {
		fw->msgFlag = 0;
		fw->contFlag = 1;
		fw->sellun = (unsigned char)(sense->lun | 0xC0);
		if ((char)sense->flags1 >= 0 && sense->requeue == 2)
			fw->sellun &= 0xBF;
		if (sense->requeue != 0 && sense->requeue != 2) {
			fw->tag = (unsigned char)((sense->tag_action & 3) | 0x20);
			fw->lunmask = sense->requeue;
			fw->contFlag = 3;
		}
	}
	fw->msgOut = hba_resmsg(hba, id);
	fw->selid = (unsigned char)id;
}

void
ResetDevice(struct sim_hba *hba, unsigned int id, unsigned int reason)
{
	struct sim_q *q, *next;
	struct sim_ccb *ccb, *parent;
	struct sim_dev *dp;
	int lun, slot, i;
	unsigned char path;

	path = hba->path;
	hba->frozen[id]++;
	q = hba->actq.next;
	while (q != 0 && q != &hba->actq) {
		ccb = (struct sim_ccb *)q->owner;
		next = q->next;
		FreeQueueTag(hba, ccb);
		if (ccb->target == (unsigned char)id) {
			QDelete(&ccb->qlink);
			QDelete(&ccb->timelink);
			ccb->status = (unsigned char)reason;
			CallComp(hba, ccb);
		}
		q = next;
	}
	for (lun = 0; lun <= 7; lun++) {
		dp = IDLUNToDP(hba, (unsigned char)id, (unsigned char)lun);
		if (dp == 0)
			continue;
		q = dp->queue->next;
		while (q != 0 && q != dp->queue) {
			ccb = (struct sim_ccb *)q->owner;
			next = q->next;
			hba->queued--;
			FreeQueueTag(hba, ccb);
			QDelete(&ccb->qlink);
			QDelete(&ccb->timelink);
			ccb->status = (unsigned char)reason;
			CallComp(hba, ccb);
			q = next;
		}
	}
	parent = hba->snsccb->link_ccb;
	if (parent != 0 && parent->target == (unsigned char)id) {
		QDelete(&parent->qlink);
		QInsert(&hba->snsq, &parent->qlink, parent);
		CallComp(hba, hba->snsccb);
		hba->snsccb->link_ccb = 0;
	}
	q = hba->snsq.next;
	while (q != 0 && q != &hba->snsq) {
		ccb = (struct sim_ccb *)q->owner;
		next = q->next;
		if (ccb->target == (unsigned char)id) {
			QDelete(&ccb->qlink);
			QDelete(&ccb->timelink);
			ccb->status = 4;
			CallComp(hba, ccb);
		}
		q = next;
	}
	for (slot = 0; slot <= 0x1B; slot++) {
		if (DEVs[slot].id != (unsigned char)id)
			continue;
		dp = IDLUNToDP(hba, (unsigned char)id, DEVs[slot].lun);
		dp->sync = 0;
		dp->wide = 0;
		dp->rsvd0C[0] = 0;
		if ((dp->flags & 0x20) == 0 &&
		    Sync_dev[id + path * 7] != 0)
			dp->sync = 2;
		if ((dp->flags & 0x40) == 0 && hba->width != 0 &&
		    Wide_dev[id + path * 7] != 0)
			dp->wide |= 4;
		for (i = 0; i <= 6; i++)
			CAM_FWB(hba->fw, i + id * 8 + 0x32) = 0;
		dp->flags &= 0x63;
	}
	for (lun = 7; lun >= 0; lun--) {
		FSetSync(hba, 0, 0, id, (unsigned int)lun);
		FSetWide(hba, 0, id, (unsigned int)lun);
	}
	hba_set_resmsg(hba, id, hba->fw->msgOut);
	hba->frozen[id]--;
	if (reason == 0x17)
		xpt_async(0x10, hba->path, id, 0xFFFFFFFF, 0, 0);
}

/* ---------------- messages ---------------- */

unsigned int
WhatMsgIsIt(unsigned char *msg)
{
	if (msg[0] != 1)
		return 0x6C;
	if (msg[2] == 1)
		return 1;
	if (msg[2] == 0)
		return 0;
	if (msg[2] == 3)
		return 3;
	return 0x6C;
}

unsigned int
GetMoreMsgBytes(struct sim_hba *hba)
{
	struct sim_fw *fw;
	unsigned int i, n;

	if (FGetMsgByte(hba) != 0) {
		FResetBus(hba);
		return 0;
	}
	fw = hba->fw;
	n = CAM_U16(&fw->sync);
	for (i = 0; i < n; i++) {
		CAM_HBAB(hba, 0x71 + CAM_HBAB(hba, 0x79)) = CAM_FWB(fw, 0x22 + i);
		CAM_HBAB(hba, 0x79)++;
	}
	return 1;
}

unsigned int
GetCompleteMsg(struct sim_hba *hba)
{
	struct sim_fw *fw;
	unsigned int i, n, need, before;

	fw = hba->fw;
	CAM_HBAB(hba, 0x79) = (unsigned char)CAM_U16(&fw->sync);
	n = CAM_U16(&fw->sync);
	for (i = 0; i < n; i++)
		CAM_HBAB(hba, 0x71 + i) = CAM_FWB(fw, 0x22 + i);
	if (CAM_HBAB(hba, 0x71) == 1) {
		if (CAM_HBAB(hba, 0x79) == 1) {
			if (GetMoreMsgBytes(hba) == 0)
				return 0;
		}
		need = CAM_HBAB(hba, 0x72);
		need -= 2; /* extended length already has 1 byte? IDA: add eax, -2 then loop */
		if (CAM_HBAB(hba, 0x79) == 1)
			goto more;
		need = CAM_HBAB(hba, 0x72);
		i = CAM_HBAB(hba, 0x79);
		need = i + 0xFFFFFFFE;
		goto collect;
	}
	if ((CAM_HBAB(hba, 0x71) & 0xF0) == 0x20) {
		need = 2;
		goto collect;
	}
	FResetBus(hba);
	return 0;
more:
	need = 1;
collect:
	while (need > 0) {
		before = CAM_HBAB(hba, 0x79);
		if (GetMoreMsgBytes(hba) == 0)
			return 0;
		if (CAM_HBAB(hba, 0x79) == before)
			need = 1;
		need -= CAM_HBAB(hba, 0x79) - before;
	}
	return 1;
}

/* ---------------- 16/17 CCB translators ---------------- */

void
T16To17(struct sim16_ccb *s, struct sim_ccb *d)
{
	unsigned char *cdb;
	int i;
	unsigned int dir;

	d->func_code = 1;
	d->path = s->path;
	d->target = s->target;
	d->lun = s->lun;
	d->flags0 = 0;
	d->flags1 = 4;
	d->flags2 = 0;
	d->flags3 = 0;
	if ((short)CAM_U16((char *)s + 0x10) < 0) {
		d->data = (void *)CAM_U32((char *)s + 0x5C);
		d->sense_ptr = (unsigned char *)CAM_U32((char *)s + 0x64);
		d->cdb_len = (unsigned char)CAM_U16((char *)s + 0x68);
		cdb = (unsigned char *)s + 0x6A;
		d->vu_flags = 0x8000;
	} else {
		d->data = (void *)s->arg0;
		d->sense_ptr = (unsigned char *)s->arg1;
		d->cdb_len = (unsigned char)s->w12;
		if (CAM_U8((char *)s + 0x0B) & 1)
			cdb = *(unsigned char **)(void *)&s->cdb[0];
		else
			cdb = s->cdb;
		d->vu_flags = 0;
	}
	if (s->flags & 1)
		d->vu_flags |= 0x100;
	d->dxfer_len = s->opflags;
	d->resid = s->opflags;
	d->sense_len = (unsigned char)s->w14;
	for (i = 0; i <= 0xB; i++)
		d->cdb[i] = cdb[i];
	d->timeout = s->arg_ffff;
	if ((s->rsvd0E[1] & 0x20) == 0 && s->arg1 != 0 && s->w14 == 0)
		d->flags0 |= 0x20;
	if (CAM_U8((char *)s + 0x0A) & 0x80)
		d->flags1 |= 0x80;
	if (CAM_U8((char *)s + 0x0A) & 0x40)
		d->flags1 |= 0x40;
	else if (CAM_U8((char *)s + 0x0A) & 0x20)
		d->flags1 |= 0x20;
	if (s->rsvd0E[1] & 0x10)
		d->flags0 |= 0x10;
	dir = s->word8 & 0xC0000000;
	if (dir == 0x80000000)
		d->flags0 |= 0x80;
	else if (dir == 0x40000000)
		d->flags0 |= 0x40;
	else if (dir == 0xC0000000)
		d->flags0 |= 0xC0;
}

void
T17To16(struct sim_ccb *s, struct sim16_ccb *d)
{
	unsigned char *cdb;
	int i;
	unsigned int dir;

	d->op = 2;
	d->path = s->path;
	d->word8 = 0;
	d->target = s->target;
	d->lun = s->lun;
	CAM_U16((char *)d + 0x10) = 0;
	d->w12 = s->cdb_len;
	d->w14 = s->sense_len;
	d->opflags = s->dxfer_len;
	d->arg_ffff = s->timeout;
	d->arg0 = (unsigned int)s->data;
	d->arg1 = (unsigned int)s->sense_ptr;
	if (s->flags0 & 1)
		cdb = *(unsigned char **)(void *)s->cdb;
	else
		cdb = s->cdb;
	for (i = 0; i < (int)s->cdb_len && i <= 0xB; i++)
		d->cdb[i] = cdb[i];
	if (s->flags0 & 0x20)
		d->word8 |= 0x20000000;
	if ((char)s->flags1 < 0)
		d->word8 |= 0x800000;
	if (s->flags1 & 0x40)
		d->word8 |= 0x400000;
	else if (s->flags1 & 0x20)
		d->word8 |= 0x200000;
	dir = s->flags0 & 0xC0;
	if (dir == 0x80)
		d->word8 |= 0x80000000;
	else if (dir == 0x40)
		d->word8 |= 0x40000000;
	else if (dir == 0xC0)
		d->word8 |= 0xC0000000;
	if (s->vu_flags & 0x100)
		CAM_U16((char *)d + 0x10) = 0x100;
}

unsigned char
Stat16To17(unsigned int status)
{
	unsigned char s = (unsigned char)status;
	unsigned int i = (unsigned int)s - 12;

	if (i > 0x1B)
		return s;
	switch (s) {
	case 0x0C: return 0x3F;
	case 0x20: return 0x38;
	case 0x21: return 0x39;
	case 0x22:
	case 0x25:
	case 0x27: return 0x3A;
	case 0x23: return 0x3B;
	case 0x24: return 0x3C;
	case 0x26: return 0x11;
	default:   return s;
	}
}

unsigned char
Stat17To16(unsigned int status)
{
	unsigned char s = (unsigned char)status;
	unsigned int i = (unsigned int)s - 17;

	if (i > 0x2E)
		return s;
	switch (s) {
	case 0x11: return 0x26;
	case 0x38: return 0x20;
	case 0x39: return 0x21;
	case 0x3A: return 0x22;
	case 0x3B: return 0x23;
	case 0x3C: return 0x24;
	case 0x3F: return 0x0C;
	default:   return s;
	}
}

/* ---------------- XPT ---------------- */

void
StuffAction(struct xpt_bus *bus)
{
	bus->action = (unsigned int (*)())SIM17Action;
}

struct sim_ccb *
xpt_ccb_alloc(void)
{
	struct sim_ccb *ccb;

	ccb = freeccb;
	if (ccb == 0)
		return 0;
	freeccb = ccb->link_ccb;
	ccb->link_ccb = 0;
	return ccb;
}

void
xpt_ccb_free(struct sim_ccb *ccb)
{
	int i;

	for (i = 0; i <= 0x3F; i++)
		((unsigned int *)(void *)ccb)[i] = 0;
	ccb->func_code = 1;
	ccb->my_addr = xVtoP(ccb);
	ccb->ccb_len = 0x100;
	ccb->link_ccb = freeccb;
	freeccb = ccb;
}

int
XPTInit(unsigned short first)
{
	if (haveBeenInitialized_94 != 0)
		return 0;
	haveBeenInitialized_94 = 1;
	numSIMs = 0;
	numDevs = 0;
	numAEVs = 0;
	newSIMs = 0;
	pi = xMemAlloc(0x54);
	if (pi == 0)
		return 1;
	XPTClearMem(pi, 0x54);
	pi->my_addr = xVtoP(pi);
	pi->ccb_len = 0x54;
	pi->func_code = 3;
	pi_inq = xMemAlloc(0x24);
	if (pi_inq == 0)
		return 1;
	firstPath = first;
	return 0;
}

int
bsim_doinit(void *arg)
{
	int i;

	dlFree = 0;
	for (i = 0; i <= 0x1D; i++) {
		dlStack[i] = (unsigned int)&datalists[i * DL_STRIDE];
		dlFree++;
	}
	SIMInit(arg);
	bsiminited = 1;
	return 0;
}

int
xpt_init(void)
{
	struct sim_ccb *p;
	int i;
	struct xpt_bus bus;

	if (xptInited != 0)
		return 0;
	xptInited = 1;
	p = IOMalloc(0x4000);
	freeccb = 0;
	for (i = 0; i <= 0x3F; i++) {
		xpt_ccb_free(p);
		p = (struct sim_ccb *)((char *)p + 0x100);
	}
	XPTInit(0);
	bus.action = (unsigned int (*)())SIM17Action;
	bus.init = (int (*)())bsim_doinit;
	xpt_bus_register(&bus);
	return 0;
}

int
xpt_bus_register(struct xpt_bus *bus)
{
	int state, path;
	struct xpt_sim *sim;

	state = xDisableInterrupts();
	if (numSIMs > 3) {
		xRestoreInterrupts(state);
		return -1;
	}
	path = firstPath;
	if ((unsigned char)path <= 0xFD) {
		while (PathToSIMInfoPtr((unsigned char)path) != 0) {
			path++;
			if ((unsigned char)path > 0xFD)
				break;
		}
	}
	sim = &SIMs[numSIMs];
	numSIMs++;
	sim->path = (unsigned char)path;
	sim->action = bus->action;
	sim->scan_ccb = 0;
	sim->needscan = 1;
	sim->found = 0;
	newSIMs++;
	if (highPath < (unsigned short)(unsigned char)path)
		highPath = (unsigned short)(unsigned char)path;
	bus->init((unsigned int)(unsigned char)path);
	if (BeginScan(sim) != 0) {
		xRestoreInterrupts(state);
		return -1;
	}
	xpt_async(0x20, sim->path, 0xFFFFFFFF, 0xFFFFFFFF, 0, 0);
	xRestoreInterrupts(state);
	return (int)(unsigned char)path;
}

void
xpt_async(int opcode, unsigned int path, unsigned int a, unsigned int b,
	  unsigned int c, unsigned int d)
{
	int state, i, n, j;
	struct xpt_aev *aev;
	unsigned int extra;

	extra = d;
	state = xDisableInterrupts();
	aev = AEVs;
	for (i = 0; i < numAEVs; i++, aev++) {
		if (path != 0xFFFFFFFF && aev->path != path)
			continue;
		if (a != 0xFFFFFFFF && aev->id != a)
			continue;
		if (b != 0xFFFFFFFF && aev->lun != b)
			continue;
		if ((opcode & 0x80) && (char)aev->mask < 0)
			aev->cb(0x80, path, 0, 0, 0, 0);
		if ((opcode & 0x40) && (aev->mask & 0x40)) {
			aev->buf[0] = (unsigned char)extra;
			aev->cb(0x40, 0xFF, 0, 0, aev->buf, 1);
		}
		if ((opcode & 0x20) && (aev->mask & 0x20)) {
			aev->buf[0] = (unsigned char)extra;
			aev->cb(0x20, 0xFF, 0, 0, aev->buf, 1);
		}
		if ((opcode & 0x10) && (aev->mask & 0x10))
			aev->cb(0x10, path, a, 0, 0, 0);
		if ((opcode & 8) && (aev->mask & 8)) {
			n = (int)extra;
			if ((int)aev->maxlen < n)
				n = aev->maxlen;
			for (j = 0; j < n; j++)
				aev->buf[j] = ((unsigned char *)c)[j];
			aev->cb(8, path, a, b, aev->buf, n);
		}
		if ((opcode & 2) && (aev->mask & 2))
			aev->cb(2, path, a, b, 0, 0);
		if ((opcode & 1) && (aev->mask & 1))
			aev->cb(1, path, 0, 0, 0, 0);
	}
	xRestoreInterrupts(state);
}

int
XPTDeregisterBus(unsigned char path)
{
	int state, idx, i, j;
	struct xpt_sim *sim;
	struct xpt_aev *aev;

	state = xDisableInterrupts();
	sim = PathToSIMInfoPtr(path);
	if (sim == 0) {
		xRestoreInterrupts(state);
		return 0;
	}
	if (sim->ccb_len != 0) {
		MemFree(sim->scan_ccb, sim->ccb_len);
		sim->ccb_len = 0;
	}
	idx = sim - SIMs;
	for (; idx + 1 < numSIMs; idx++)
		SIMs[idx] = SIMs[idx + 1];
	numSIMs--;
	DeletePathFromDeviceTable(path);
	xpt_async(0x40, path, 0xFFFFFFFF, 0xFFFFFFFF, 0, 0);
	for (i = 0; i < numAEVs; ) {
		aev = &AEVs[i];
		if (aev->path != path) {
			i++;
			continue;
		}
		for (j = i + 1; j < numAEVs; j++)
			AEVs[i] = AEVs[j];
		numAEVs--;
	}
	xRestoreInterrupts(state);
	return 0;
}

int
xpt_action(struct sim_ccb *ccb)
{
	int state, rc, i;
	struct xpt_sim *sim;
	struct xpt_dev *dev;
	struct xpt_aev *aev;

	state = xDisableInterrupts();
	rc = 0;
	if (ccb == 0) {
		xRestoreInterrupts(state);
		return 0;
	}
	sim = PathToSIMInfoPtr(ccb->path);
	if (sim == 0) {
		if (ccb->func_code == 3 && ccb->path == 0xFF)
			goto pathinq_xpt;
		ccb->status = 7;
		if (ccb->func_code == 1 && (ccb->flags0 & 8) == 0 &&
		    ccb->complete != 0)
			ccb->complete(ccb);
		xRestoreInterrupts(state);
		return 1;
	}
	switch (ccb->func_code) {
	case 7:
		sim->needscan = 1;
		newSIMs++;
		BeginScan(sim);
		ccb->status = 1;
		break;
	case 6:
		dev = PathIDLUNToDeviceInfoPtr(ccb->path, ccb->target, ccb->lun);
		if (dev != 0) {
			ccb->status = 1;
			break;
		}
		if (numDevs > 0x1B) {
			ccb->status = 4;
			break;
		}
		dev = &Devtab[numDevs++];
		dev->path = ccb->path;
		dev->id = ccb->target;
		dev->lun = ccb->lun;
		for (i = 0; i <= 0x23; i++)
			dev->_pad[i] = 0;
		dev->_pad[0] = CAM_U8((char *)ccb + 0x10);
		ccb->status = 1;
		break;
	case 2:
		dev = 0;
		for (i = 0; i < numDevs; i++) {
			if (Devtab[i].path == ccb->path &&
			    Devtab[i].id == ccb->target &&
			    Devtab[i].lun == ccb->lun) {
				dev = &Devtab[i];
				break;
			}
		}
		if (dev == 0) {
			ccb->status = 8;
			break;
		}
		CAM_U8((char *)ccb + 0x14) = dev->_pad[0];
		if (CAM_U32((char *)ccb + 0x10) != 0) {
			unsigned char *dst = (unsigned char *)CAM_U32((char *)ccb + 0x10);
			for (i = 0; i <= 0x23; i++)
				dst[i] = ((unsigned char *)dev)[4 + i];
		}
		ccb->status = 1;
		break;
	case 5:
		aev = 0;
		for (i = 0; i < numAEVs; i++) {
			if (AEVs[i].path == ccb->path &&
			    AEVs[i].id == ccb->target &&
			    AEVs[i].lun == ccb->lun) {
				aev = &AEVs[i];
				break;
			}
		}
		if (aev == 0) {
			if (numAEVs > 7) {
				ccb->status = 4;
				break;
			}
			aev = &AEVs[numAEVs++];
		}
		aev->mask = CAM_U8((char *)ccb + 0x10);
		aev->cb = *(unsigned int (**)())(void *)((char *)ccb + 0x14);
		aev->buf = *(unsigned char **)(void *)((char *)ccb + 0x18);
		aev->maxlen = CAM_U8((char *)ccb + 0x1C);
		aev->path = ccb->path;
		aev->id = ccb->target;
		aev->lun = ccb->lun;
		if (aev->mask == 0 || aev->cb == 0) {
			i = aev - AEVs;
			for (; i + 1 < numAEVs; i++)
				AEVs[i] = AEVs[i + 1];
			numAEVs--;
		}
		goto defaction;
	default:
	defaction:
		sim->action(ccb);
		if (ccb->func_code == 3) {
			CAM_U8((char *)ccb + 0x13) = 0;
			CAM_U8((char *)ccb + 0x28) |= 0xE0;
			CAM_U8((char *)ccb + 0x2C) = (unsigned char)highPath;
		}
		ccb->status = 1;
		break;
	}
	xRestoreInterrupts(state);
	return rc;
pathinq_xpt:
	CAM_U8((char *)ccb + 0x13) = 0;
	CAM_U8((char *)ccb + 0x28) |= 0xE0;
	CAM_U8((char *)ccb + 0x2C) = (unsigned char)highPath;
	ccb->status = 1;
	xRestoreInterrupts(state);
	return 0;
}

void
ScanStep(struct sim_ccb *ccb)
{
	struct xpt_sim *sim;
	struct xpt_dev *dev;
	int retries, i, n;
	unsigned char *inq;

	retries = 0;
again:
	sim = PathToSIMInfoPtr(ccb->path);
	if (sim == 0)
		return;
	if (ccb->link_ccb != 0) {
		if (ccb->status == 0x0E) {
			retries++;
			if (retries == 1)
				goto issue;
		}
		retries = 0;
		if (ccb->status == 0x0A)
			ccb->lun = 7;
		if (ccb->status != 1 && ccb->status != 0x0F)
			goto next;
		if (ccb->resid == 0x24)
			goto next;
		inq = pi_inq;
		if (inq[0] == 0x7F)
			goto next;
		dev = PathIDLUNToDeviceInfoPtr(sim->path, ccb->target, ccb->lun);
		if (dev == 0) {
			if (numDevs > 0x1B)
				goto next;
			dev = &Devtab[numDevs++];
			sim->found = 1;
		}
		if (dev != 0) {
			dev->path = sim->path;
			dev->id = ccb->target;
			dev->lun = ccb->lun;
			dev->_pad[0] = (unsigned char)(inq[0] & 0x1F);
			n = 0x24 - ccb->resid;
			for (i = 0; i <= 0x23; i++) {
				if ((unsigned int)i < (unsigned int)n)
					((unsigned char *)dev)[4 + i] = inq[i];
				else
					((unsigned char *)dev)[4 + i] = 0;
			}
			xPrintNexus(dev->path, dev->id, dev->lun);
			xPutString(" is ");
			inq[0x20] = 0;
			xPutString((char *)inq + 8);
			xPutString("\n");
		}
	next:
		ccb->lun++;
		if (ccb->lun > 7) {
			ccb->lun = 0;
			ccb->target++;
			if (ccb->target == sim->initiatorId)
				ccb->target++;
			if (ccb->target > 7)
				return;
		}
	}
issue:
	ccb->cdb[1] = (unsigned char)(ccb->lun << 5);
	ccb->link_ccb = (struct sim_ccb *)1;
	if (numDevs > 0x1B)
		return;
	((unsigned char *)pi_inq)[0] = 0x7F;
	sim->action(ccb);
	sim->byte19 = ccb->path;
	sim->byte16 = 0;
	if (ccb->status == 0)
		xpt_wait_done(sim, ccb);
	goto again;
}

int
BeginScan(struct xpt_sim *sim)
{
	struct sim_ccb *ccb;
	int i;
	unsigned char saved;

	if (sim->needscan == 0)
		return 0;
	newSIMs--;
	sim->needscan = 0;
	pi->path = sim->path;
	sim->action(pi);
	sim->initiatorId = ((struct sim_pathinq *)pi)->hba_path_id ?
		((unsigned char *)pi)[0x2D] : ((unsigned char *)pi)[0x2D];
	sim->initiatorId = ((unsigned char *)pi)[0x2D];
	sim->ccb_len = ((unsigned int *)(void *)pi)[0x24 / 4] + 0x58;
	ccb = sim->scan_ccb;
	if (ccb == 0) {
		ccb = xMemAlloc(sim->ccb_len);
		sim->scan_ccb = ccb;
		if (ccb == 0)
			return 1;
		XPTClearMem(ccb, (unsigned short)sim->ccb_len);
		ccb->my_addr = xVtoP(ccb);
	}
	ccb->ccb_len = (unsigned short)sim->ccb_len;
	ccb->func_code = 1;
	ccb->path = sim->path;
	ccb->target = 0;
	ccb->lun = 0;
	ccb->flags0 = 0x60;
	ccb->flags1 = 0x84;
	ccb->link_ccb = 0;
	ccb->complete = 0;
	ccb->flags0 |= 8;
	ccb->data = pi_inq;
	ccb->dxfer_len = 0x24;
	ccb->cdb_len = 6;
	ccb->cdb[0] = 0x12;
	ccb->cdb[1] = 0;
	ccb->cdb[2] = 0;
	ccb->cdb[3] = 0;
	ccb->cdb[4] = 0x24;
	ccb->cdb[5] = 0;
	ccb->timeout = 0xFFFFFFFF;
	ccb->vu_flags = 0x100;
	ScanStep(ccb);
	if (sim->found != 0) {
		sim->found = 0;
		xpt_async(0x80, sim->path, 0xFFFFFFFF, 0xFFFFFFFF, 0, 0);
	}
	ccb->cdb[4] = 0;
	ccb->cdb[0] = 0;
	saved = ccb->cdb[1];
	sim->byte19 = ccb->path;
	sim->byte16 = 0;
	for (i = 0; i < numDevs; i++) {
		if (Devtab[i].path != sim->byte19)
			continue;
		ccb->target = Devtab[i].id;
		ccb->lun = Devtab[i].lun;
		util_start_unit(ccb, sim);
	}
	ccb->cdb[1] = saved;
	return 0;
}

/* ---------------- PCI / ROM init ---------------- */

void
pcidir(unsigned int *eaxp, unsigned int *ebxp, unsigned int *ecxp,
       unsigned int *edxp, void (*fn)())
{
	unsigned int a, b, c, d;

	a = *eaxp;
	b = *ebxp;
	c = *ecxp;
	d = *edxp;
	asm volatile (
		"pushl %%cs\n\t"
		"call *%4"
		: "+a"(a), "+b"(b), "+c"(c), "+d"(d)
		: "m"(fn)
		: "memory"
	);
	*eaxp = a;
	*ebxp = b;
	*ecxp = c;
	*edxp = d;
}

void
pci_initialize(void *ctx)
{
	unsigned int eax, ebx, ecx, edx, fn, sum, hits;
	unsigned int seg;
	int i;

	eax = ebx = ecx = edx = 0;
	hits = 0;
	for (seg = 0xE000; seg <= 0xFFFF; seg++) {
		if (ROMReadByte((unsigned short)seg, 0) != '_' ||
		    ROMReadByte((unsigned short)seg, 1) != '3' ||
		    ROMReadByte((unsigned short)seg, 2) != '2' ||
		    ROMReadByte((unsigned short)seg, 3) != '_')
			goto next;
		sum = 0;
		for (i = 0; i <= 0xF; i++)
			sum += (unsigned char)ROMReadByte((unsigned short)seg, (unsigned short)i);
		if (sum != 0)
			goto next;
		hits++;
		fn = (unsigned int)PtoV(ROMReadLong((unsigned short)seg, 4));
		eax = 0x49435024;
		ebx = 0;
		pcidir(&eax, &ebx, &ecx, &edx, (void (*)())fn);
		if ((char)eax < 0) {
			((unsigned int *)ctx)[4] = 0;
			goto next;
		}
		((unsigned int *)ctx)[4] = (unsigned int)PtoV(ebx) + edx;
	next:
		if (hits != 0)
			return;
	}
}

int
InitStep(unsigned int path)
{
	int state, i;
	struct sim_rom *rom;
	int rc;

	state = DisableInterrupts();
	for (i = 0; i < numROMs; i++) {
		if (ROMs[i].path == 0xFF)
			break;
	}
	if (i >= numROMs) {
		RestoreInterrupts(state);
		return 0;
	}
	rom = &ROMs[i];
	rom->path = (unsigned char)path;
	PutString("PATH ");
	PutChar((unsigned char)(path + '0'));
	if (rom->simType == 0x17) {
		PutString(" is a Rev. 3.00x CAMcore (R) at ");
		if (SIMAddPath(rom->ctx, rom->path) != 0) {
			RestoreInterrupts(state);
			return -1;
		}
	} else
		PutString(" is a Rev. 1.60x CAMcore (R) at ");
	PutWord((unsigned short)(((unsigned int *)rom->ctx)[0x3C / 4] >> 4));
	PutChar('0');
	PutString(" with IMAGE=");
	PutWord(CAM_U16((char *)rom->ctx + 0x1E));
	PutChar(':');
	PutWord(CAM_U16((char *)rom->ctx + 0x1C));
	PutString(" IRQ=");
	PutChar((unsigned char)(rom->irq / 10 + '0'));
	PutChar((unsigned char)(rom->irq % 10 + '0'));
	PutString(" DMA=");
	if (((unsigned char *)rom->ctx)[5] == 0xFF)
		PutString("No");
	else
		PutChar((unsigned char)(((unsigned char *)rom->ctx)[5] + '0'));
	PutString("\r\n");
	rom->active = 1;
	if (CAM_U16((char *)rom + 0x62) == 0)
		BusNowOperational(path, rom->irq, CAM_U16((char *)rom + 0x18));
	RestoreInterrupts(state);
	return 0;
}

int
InitROMs(void *arg)
{
	int i, n;
	struct sim_rom *rom;
	struct sim_fwctx *ctx;
	struct xpt_bus bus;
	unsigned int (*fn)();

	for (i = 0; i < numROMs; i++) {
		rom = &ROMs[i];
		PutString("Initializing CAMcore (R) ");
		PutChar((unsigned char)(i + '0'));
		PutString(" at ");
		PutWord((unsigned short)(((unsigned int *)rom->ctx)[0x3C / 4] >> 4));
		PutChar('0');
		PutString("...\r");
		if (rom->simType == 0x17) {
			((unsigned char *)rom->ctx)[0x154] = 0x10;
			((unsigned char *)rom->ctx)[0x155] = 0xFF;
			CAM_U16((char *)rom->ctx + 0x156) = CAM_U16((char *)rom + 0x62);
		}
		fn = rom_fn8(rom);
		fn(rom->ctx);
		rom->irq = ((unsigned char *)rom->ctx)[4];
		ctx = rom->ctx;
		ROMIntAndDMA(ctx->hbaType, ((unsigned char *)ctx)[5],
			     CAM_U32((char *)ctx + 0x0C),
			     ((unsigned char *)CAM_U32((char *)ctx + 0x1C))[2] << 9);
		if (rom->simType == 0x17)
			ctx->intEnable = 1;
	}
	for (i = 0; i < numROMs; i++) {
		StuffAction(&bus);
		bus.init = (int (*)())InitStep;
		if (arg == (void *)0xFFFFFFFF)
			n = xpt_bus_register(&bus);
		else {
			n = InitStep((unsigned int)arg);
			arg = (void *)0xFFFFFFFF;
		}
		if (n == -1)
			return 1;
	}
	for (i = 0; i <= 0x4D; i++)
		PutChar(' ');
	PutString("\r");
	return 0;
}

unsigned short
FindROMs(void)
{
	unsigned int seg, off, pci, romlen, copyoff, copylen, rel, nboards;
	int i, slot;
	struct sim_rom *rom;
	unsigned char *ctx;
	unsigned int (*cfg)();
	unsigned int v;

	for (seg = 0xC000; ; ) {
		if (numROMs > 3)
			break;
		if (ROMReadByte((unsigned short)seg, 0) != 0x55 ||
		    ROMReadByte((unsigned short)seg, 1) != 0xAA)
			goto nextseg;
		for (i = 0; i <= 0x13; i++) {
			if ((unsigned char)romSIMStr[i] !=
			    (unsigned char)ROMReadByte((unsigned short)seg,
						       (unsigned short)(i + 0x55)))
				break;
		}
		if (i <= 0x13)
			goto nextseg;
		pci = (unsigned char)ROMReadByte((unsigned short)seg, 0x71);
		pci = (pci > 1);
		if (pci) {
			if (ROMReadWord((unsigned short)seg, 0x89) == 0)
				pci = 0;
			else
				romlen = ROMReadWord((unsigned short)seg, 0x89);
		}
		if (!pci)
			romlen = (unsigned short)(ROMReadByte((unsigned short)seg, 2) << 9);
		if (ROMReadWord((unsigned short)seg, (unsigned short)romlen) != 0x514D)
			goto nextseg;
		if (ROMReadWord((unsigned short)seg, (unsigned short)(romlen + 0x1C)) != 1)
			goto nextseg;
		nboards = 1;
		for (slot = 0; nboards; slot++) {
			rom = &ROMs[numROMs];
			numROMs++;
			rom->active = 0;
			CAM_U16((char *)rom + 0x62) = (unsigned short)slot;
			CAM_U16((char *)rom + 0x60) =
				(unsigned short)ROMReadLong((unsigned short)seg, 0xAB);
			if (MaxCCBPrivateLen < CAM_U16((char *)rom + 0x60))
				MaxCCBPrivateLen = CAM_U16((char *)rom + 0x60);
			v = ROMReadLong((unsigned short)seg, 0xA7);
			if ((unsigned short)v == 0)
				v = 0x1000;
			ctx = GlobMemAlloc((unsigned short)v);
			rom->ctx = (struct sim_fwctx *)ctx;
			if (ctx == 0)
				return 1;
			if (CAM_U32(ctx + 0x0C) != (seg << 4))
				SIMClearMem(ctx, (unsigned short)v);
			else
				ctx[2] = 0;
			if ((unsigned char)ROMReadByte((unsigned short)seg, 0x71) > 2)
				rom->simType = 0x17;
			else
				rom->simType = 0x16;
			CAM_U32(ctx + 0x3C) = seg << 4;
			CAM_U32(ctx + 8) = VtoP(ctx);
			CAM_U32(ctx + 0x0C) = CAM_U32(ctx + 0x3C);
			CAM_U32(ctx + 0x1C) = (unsigned int)ROMGetAddress((unsigned short)seg, 0);
			pci_initialize(ctx);
			off = pci ? 0x6F : 0x14;
			off = ROMReadWord((unsigned short)seg, (unsigned short)off);
			for (i = 0; i <= 0x1F; i++)
				((unsigned char *)rom)[0x1A + i] =
					(unsigned char)ROMReadByte((unsigned short)seg,
								   (unsigned short)(off++));
			off = pci ? 0x7F : 0x16;
			off = ROMReadWord((unsigned short)seg, (unsigned short)off);
			for (i = 0; i <= 0x1F; i++)
				((unsigned char *)rom)[0x3A + i] =
					(unsigned char)ROMReadByte((unsigned short)seg,
								   (unsigned short)(off++));
			CAM_U32(ctx + 0x34) = (unsigned int)GetScreenPtr();
			CAM_U16((char *)rom + 0x18) = (unsigned short)seg;
			v = ROMReadWord((unsigned short)seg, (unsigned short)(romlen + 4));
			copylen = (v << 9);
			v = ROMReadWord((unsigned short)seg, (unsigned short)(romlen + 2));
			copylen = copylen + v - 0x200;
			v = ROMReadWord((unsigned short)seg, (unsigned short)(romlen + 8));
			copylen -= v << 4;
			copyoff = (unsigned short)((v << 4) + romlen);
			CAM_U32((char *)rom + 0x5C) =
				(unsigned int)ROMMakeCopy((unsigned short)seg,
							  (unsigned short)copyoff,
							  (unsigned short)copylen);
			if (CAM_U32((char *)rom + 0x5C) == 0)
				return 1;
			rel = ROMReadWord((unsigned short)seg, (unsigned short)(romlen + 0x18)) + romlen;
			for (i = 0; ; i++) {
				if (i >= (int)ROMReadWord((unsigned short)seg,
							  (unsigned short)(romlen + 6)))
					break;
				if (ROMReadLong((unsigned short)seg, 0) == 0) {
					numROMs--;
					goto nextseg;
				}
				v = ROMReadLong((unsigned short)seg,
						(unsigned short)(rel + i * 4)) & 0x7FFFFFFF;
				v += CAM_U32((char *)rom + 0x5C);
				*(unsigned int *)v += CAM_U32((char *)rom + 0x5C);
			}
			ROMCopyPatched((void *)CAM_U32((char *)rom + 0x5C),
				       (unsigned short)copylen);
			rom->run = (unsigned int (*)())(ROMReadLong((unsigned short)seg, (unsigned short)(copyoff + 0x20)) + CAM_U32((char *)rom + 0x5C));
			rom->poll = (unsigned int (*)())(ROMReadLong((unsigned short)seg, (unsigned short)(copyoff + 0x24)) + CAM_U32((char *)rom + 0x5C));
			rom->action = (unsigned int (*)())(ROMReadLong((unsigned short)seg, (unsigned short)(copyoff + 0x28)) + CAM_U32((char *)rom + 0x5C));
			config32 = ROMReadLong((unsigned short)seg, (unsigned short)(copyoff + 0x1C)) + CAM_U32((char *)rom + 0x5C);
			if (pci)
				CAM_U32((char *)rom + 0x14) = ROMReadLong((unsigned short)seg, (unsigned short)(copyoff + 0x2C)) + CAM_U32((char *)rom + 0x5C);
			else
				CAM_U32((char *)rom + 0x14) = 0;
			cfg = (unsigned int (*)())config32;
			if (CAM_U32((char *)rom + 0x5C) != config32 &&
			    slot == 0 && rom->simType == 0x17) {
				ctx[0x154] = 0x10;
				ctx[0x155] = 0;
				cfg(ctx);
				if (ctx[0x155] != 0x10)
					nboards = CAM_U16(ctx + 0x156);
			}
			PutString("Board Count = ");
			PutWord((unsigned short)nboards);
			PutString("\r\n");
			if (nboards == 0) {
				numROMs--;
				goto nextseg;
			}
			v = ROMReadLong((unsigned short)seg, 0x73);
			if (v == 0)
				v = ROMReadWord((unsigned short)seg, 0x77) + CAM_U32(ctx + 0x3C);
			else
				v = ROMReadLong((unsigned short)seg, 0x73);
			CAM_U32(ctx + 0x24) = v;
			v = ROMReadWord((unsigned short)seg, 0x7B);
			if (v != 0)
				CAM_U32(ctx + 0x28) = v + CAM_U32(ctx + 0x3C);
			if (CAM_U32((char *)rom + 0x5C) != config32 &&
			    rom->simType == 0x17) {
				ctx[0x154] = 0x10;
				ctx[0x155] = 0xFE;
				CAM_U16(ctx + 0x156) = (unsigned short)slot;
				cfg(ctx);
			}
			if (CAM_U32(ctx + 0x24) == 0)
				CAM_U32(ctx + 0x24) = (unsigned int)PtoV(0);
			if (CAM_U32(ctx + 0x28) == 0)
				CAM_U32(ctx + 0x28) = (unsigned int)PtoV(0);
			nboards--;
		}
	nextseg:
		seg += 0x80;
		if (seg <= 0xC000)
			break;
	}
	ROMSearchComplete();
	return 0;
}

/* ---------------- util ---------------- */

void
util_print_hex_data(unsigned int n, unsigned char *p)
{
	unsigned int i;

	for (i = 0; i < n; i++) {
		if (i % 20 == 0)
			IOLog("\n");
		IOLog(" %c", (char)p[i]);
	}
	IOLog("\n");
}

int
util_direct_access_check(struct sim_ccb *ccb, struct xpt_sim *sim)
{
	ccb->cdb[0] = 0x12;
	ccb->cdb[1] = (unsigned char)(ccb->lun << 5);
	ccb->cdb[2] = 0;
	ccb->cdb[3] = 0;
	ccb->cdb[4] = 0x24;
	ccb->cdb[5] = 0;
	cam_wait_action(sim, ccb);
	if (ccb->scsi_status != 0) {
		cam_wait_action(sim, ccb);
		if (ccb->scsi_status == 2) {
			ccb->cdb[0] = 3;
			ccb->cdb[4] = 0x24;
			cam_wait_action(sim, ccb);
			if (ccb->scsi_status == 0) {
				IOLog("INQUIRY failed on SCSI Id %d; Sense Data:", ccb->target);
				util_print_hex_data(0x24, data);
				return -1;
			}
			IOLog("INQUIRY's REQUEST SENSE failed with status %x on SCSI Id %d\n",
			      ccb->scsi_status, ccb->target);
			return -1;
		}
		if (ccb->scsi_status != 0) {
			IOLog("INQUIRY failed with status %x on SCSI Id %d\n",
			      ccb->scsi_status, ccb->target);
			return -1;
		}
	}
	if (data[0] == 0)
		return 1;
	return 0;
}

void
util_start_unit(struct sim_ccb *ccb, struct xpt_sim *sim)
{
	ccb->data = data;
	if (util_direct_access_check(ccb, sim) != 0)
		return;
	ccb->cdb[0] = 0;
	ccb->cdb[4] = 0;
	cam_wait_action(sim, ccb);
	if (ccb->scsi_status == 0)
		return;
	if (ccb->scsi_status != 2)
		goto unexpected;
	ccb->cdb[0] = 3;
	ccb->cdb[4] = 0x24;
	cam_wait_action(sim, ccb);
	if (ccb->scsi_status != 0)
		goto unexpected;
	if (data[2] != 6 || data[0xC] != 0x29)
		goto tur_sense;
	ccb->cdb[0] = 0;
	ccb->cdb[4] = 0;
	cam_wait_action(sim, ccb);
	if (ccb->scsi_status == 0)
		return;
	if (ccb->scsi_status != 2)
		goto unexpected;
	ccb->cdb[0] = 3;
	ccb->cdb[4] = 0x24;
	cam_wait_action(sim, ccb);
	if (ccb->scsi_status != 0)
		goto unexpected;
	if (data[2] != 2)
		goto tur2;
	if (data[0xC] == 4 && data[0xD] == 2)
		goto start;
	if (data[0xC] != 0x3A || data[0xD] != 0)
		goto tur2;
start:
	ccb->cdb[0] = 0x1B;
	ccb->cdb[4] = 1;
	cam_wait_action(sim, ccb);
	if (ccb->scsi_status == 0)
		return;
	if (ccb->scsi_status != 2)
		goto unexpected;
	ccb->cdb[0] = 3;
	ccb->cdb[4] = 0x24;
	cam_wait_action(sim, ccb);
	if (ccb->scsi_status != 0)
		goto unexpected;
	if (data[0xC] == 0x3A && data[0xD] == 0)
		return;
	IOLog("START UNIT failed on SCSI Id %d; Sense Data:", ccb->target);
	util_print_hex_data(0x24, data);
	return;
tur2:
	IOLog("Unexpected 2nd TUR sense data on SCSI Id %d; Sense Data:", ccb->target);
	util_print_hex_data(0x24, data);
	return;
tur_sense:
	IOLog("Unexpected TUR sense data on SCSI Id %d; Sense Data:", ccb->target);
	util_print_hex_data(0x24, data);
	return;
unexpected:
	IOLog("Unexpected status %x on SCSI Id %d; CDB:", ccb->scsi_status, ccb->target);
	util_print_hex_data(6, ccb->cdb);
}

void
util_stop_unit(struct sim_ccb *ccb, struct xpt_sim *sim)
{
	ccb->data = data;
	if (util_direct_access_check(ccb, sim) != 0)
		return;
	ccb->cdb[0] = 0;
	ccb->cdb[4] = 0;
	cam_wait_action(sim, ccb);
	if (ccb->scsi_status != 2) {
		if (ccb->scsi_status == 0)
			goto stop;
		goto unexpected;
	}
	ccb->cdb[0] = 3;
	ccb->cdb[4] = 0x24;
	cam_wait_action(sim, ccb);
	if (ccb->scsi_status != 0)
		goto unexpected;
	if (data[2] == 2 && data[0xC] == 4 && data[0xD] == 2)
		return;
	if (data[2] != 6 || data[0xC] != 0x29)
		goto tur_sense;
	ccb->cdb[0] = 0;
	ccb->cdb[4] = 0;
	cam_wait_action(sim, ccb);
	if (ccb->scsi_status != 2) {
		if (ccb->scsi_status == 0)
			goto stop;
		goto unexpected;
	}
	ccb->cdb[0] = 3;
	ccb->cdb[4] = 0x24;
	cam_wait_action(sim, ccb);
	if (ccb->scsi_status != 0)
		goto unexpected;
	IOLog("2nd TUR failed on SCSI Id %d during STOP UNIT; Sense Data:", ccb->target);
	util_print_hex_data(0x24, data);
	return;
stop:
	ccb->cdb[0] = 0x1B;
	ccb->cdb[4] = 1;
	cam_wait_action(sim, ccb);
	if (ccb->scsi_status == 0)
		return;
	ccb->cdb[0] = 3;
	ccb->cdb[4] = 0x24;
	cam_wait_action(sim, ccb);
	if (ccb->scsi_status == 0) {
		IOLog("STOP UNIT failed on SCSI Id %d; Sense Data:", ccb->target);
		util_print_hex_data(0x24, data);
		return;
	}
unexpected:
	IOLog("Unexpected status %x on SCSI Id %d during STOP UNIT; CDB:",
	      ccb->scsi_status, ccb->target);
	util_print_hex_data(6, ccb->cdb);
	return;
tur_sense:
	IOLog("Unexpected TUR sense data on SCSI Id %d; Sense Data:", ccb->target);
	util_print_hex_data(0x24, data);
}

/* ---------------- WantMSG / GotMSG ---------------- */

static void
dev_clear_neg(unsigned int id, unsigned char mask, unsigned char orv)
{
	int i;

	for (i = 0; i <= 0x1B; i++) {
		if (DEVs[i].id == (unsigned char)id) {
			DEVs[i].flags &= mask;
			DEVs[i].flags |= orv;
		}
	}
}

unsigned int
GotMSG(struct sim_hba *hba, int flag)
{
	struct sim_fw *fw;
	struct sim_ccb *ccb;
	struct sim_dev *dp;
	unsigned int id, lun, kind, i, acc, r;
	unsigned char per, off, wid, per2;

	fw = hba->fw;
	ccb = fw->active;
	if (ccb == 0) {
		FResetBus(hba);
		return 1;
	}
	id = ccb->target;
	lun = ccb->lun;
	if (flag == 0) {
		if (GetCompleteMsg(hba) == 0)
			return 0x0C;
		if (CAM_HBAB(hba, 0x79) == 0)
			return 0x0C;
	}
	if (CAM_HBAB(hba, 0x71) == 1) {
		kind = WhatMsgIsIt(&CAM_HBAB(hba, 0x71));
		if (kind != 1 && kind != 3)
			goto reject;
		per = CAM_HBAB(hba, 0x75);
		off = CAM_HBAB(hba, 0x74);
		wid = off;
		if (kind == 1) {
			if (hba->syncPeriod < per)
				per = hba->syncPeriod;
			if (hba->syncOffset > off)
				off = hba->syncOffset;
		} else if (hba->width < wid)
			wid = hba->width;
		for (i = 0; i < 2; i++) {
			if (kind == 1) {
				FSetSync(hba, per, off, id, lun);
				CAM_U16(&fw->sync) = 5;
				CAM_FWB(fw, 0x2A) = 1;
				CAM_FWB(fw, 0x2B) = 3;
				CAM_FWB(fw, 0x2C) = 1;
				CAM_FWB(fw, 0x2D) = off;
				CAM_FWB(fw, 0x2E) = per;
			} else {
				FSetWide(hba, wid, id, lun);
				CAM_U16(&fw->sync) = 4;
				CAM_FWB(fw, 0x2A) = 1;
				CAM_FWB(fw, 0x2B) = 2;
				CAM_FWB(fw, 0x2C) = 3;
				CAM_FWB(fw, 0x2D) = wid;
			}
			hba_set_resmsg(hba, id, fw->msgOut);
			if (i == 0)
				r = FSendMsg(hba);
			else
				r = FMsgResponse(hba);
			if ((unsigned short)r == 9)
				continue;
			break;
		}
		if ((unsigned short)r == 0x0A || (unsigned short)r == 3) {
			dp = IDLUNToDP(hba, (unsigned char)id, (unsigned char)lun);
			if (kind == 3)
				dp->wide = wid;
			return (unsigned short)r;
		}
		{
			unsigned int expect = (kind == 1) ? 5 : 4;
			if (CAM_U16(&fw->lunmask) == expect) {
				dp = IDLUNToDP(hba, (unsigned char)id, (unsigned char)lun);
				if (kind == 3)
					dp->wide = wid;
				return (unsigned short)r;
			}
		}
		if (kind == 1)
			FSetSync(hba, 0, 0, id, lun);
		else
			FSetWide(hba, 0, id, lun);
		hba_set_resmsg(hba, id, fw->msgOut);
		return (unsigned short)r;
	reject:
		if (kind == 0) {
			acc = 0;
			for (i = 3; i <= 6; i++)
				acc = (acc << 8) + CAM_FWB(fw, 0x22 + i);
			ccb->resid += acc;
			SetFrag(ccb, hba->base->initiatorId);
			hba->resume = 1;
			CAM_U16(&fw->sync) = 0;
			r = FMsgResponse(hba);
			goto done;
		}
		CAM_U16(&fw->sync) = 1;
		CAM_FWB(fw, 0x2A) = 7;
		r = FMsgResponse(hba);
		goto done;
	}
	if (CAM_HBAB(hba, 0x71) == 3) {
		CAM_U16(&fw->sync) = 0;
		ccb->resid = ccb->xferLeft;
		SetFrag(ccb, hba->base->initiatorId);
		hba->resume = 1;
		r = FMsgResponse(hba);
		goto done;
	}
	CAM_U16(&fw->sync) = 1;
	if (CAM_HBAB(hba, 0x71) == 7)
		CAM_FWB(fw, 0x2A) = 8;
	else
		CAM_FWB(fw, 0x2A) = 7;
	r = FMsgResponse(hba);
done:
	if ((unsigned short)r == 9)
		return 6;
	if ((unsigned short)r == 7)
		return 5;
	if ((unsigned short)r == 8 || (unsigned short)r == 2)
		return (unsigned short)r;
	return 0x0C;
}

unsigned int
WantMSG(struct sim_hba *hba)
{
	struct sim_fw *fw;
	struct sim_ccb *ccb;
	struct sim_dev *dp;
	struct sim_q *q;
	unsigned int id, lun, flags, r, kind;
	unsigned int phase, action, ident;
	int i;

	fw = hba->fw;
	ident = fw->lunmask;
	phase = 0;
	action = 0;
restart:
	fw->abortFlag = 0;
	id = fw->curid;
	ccb = fw->active;
	if (CAM_HBAB(hba, 0x106) == 0 && ccb != 0 &&
	    (ccb->simFlags & 0x200000) && ident == 1) {
		CAM_HBAB(hba, 0x106) = 1;
		dp = IDLUNToDP(hba, (unsigned char)id, 0);
		if (dp != 0 && (dp->flags & 0x10)) {
			CAM_U16(&fw->sync) = 1;
			CAM_FWB(fw, 0x2A) = 0x0C;
			dev_clear_neg(id, 0xEF, 0);
			phase = 1;
			action = 2;
			if (ccb != 0)
				flags = ccb->simFlags;
			goto send;
		}
	}
	if (ccb == 0) {
		if (ident != 0)
			lun = fw->sellun & 7;
		else
			lun = 0xFF;
		q = hba->actq.next;
		while (q != 0 && q != &hba->actq) {
			ccb = (struct sim_ccb *)q->owner;
			if ((ccb->simFlags & 0xC0000000) &&
			    ccb->target == (unsigned char)id &&
			    (lun == 0xFF || ccb->lun == (unsigned char)lun)) {
				ccb = (struct sim_ccb *)q->owner;
				break;
			}
			q = q->next;
			ccb = 0;
		}
		if (ccb != 0)
			flags = ccb->simFlags | 0x20000000;
		else
			flags = 0;
	} else
		flags = ccb->simFlags;
	if (ccb == 0) {
		dev_clear_neg(id, 0xF3, 0);
		CAM_U16(&fw->sync) = 1;
		CAM_FWB(fw, 0x2A) = 6;
		phase = 1;
		goto send;
	}
	lun = ccb->lun;
	CAM_U16(&fw->sync) = 0;
	phase = 3;
	action = 1;
	if (flags & 0x20000000) {
		if (CAM_HBAB(hba, 0x106) == 0) {
			fw_put_msg(fw, (unsigned char)(ccb->lun | 0x80));
			if (ccb->requeue != 0 && ccb->requeue != 2)
				CAM_FWB(fw, 0x2A + CAM_U16(&fw->sync) - 1) |= 0x40;
		}
		if (ccb->requeue != 0 && ccb->requeue != 2) {
			fw_put_msg(fw, (unsigned char)((ccb->tag_action & 3) | 0x20));
			fw_put_msg(fw, ccb->requeue);
		}
		flags &= ~0x20000000U;
	}
	if (flags & 0xC0000000) {
		dp = IDLUNToDP(hba, (unsigned char)id, (unsigned char)lun);
		dp->flags &= 0xF3;
		q = hba->actq.next;
		while (q != 0 && q != &hba->actq) {
			struct sim_ccb *o = (struct sim_ccb *)q->owner;
			if ((o->simFlags & 0xC0000000) &&
			    o->target == (unsigned char)id &&
			    o->lun == (unsigned char)lun && o != ccb) {
				if ((int)o->simFlags < 0)
					dp->flags |= 4;
				if (o->simFlags & 0x40000000)
					dp->flags |= 8;
				break;
			}
			q = q->next;
		}
		if ((int)flags < 0) {
			if (ccb->requeue != 0 && (unsigned char)(ccb->requeue - 1) > 1)
				fw_put_msg(fw, 0x0D);
			else
				fw_put_msg(fw, 6);
			phase = 1;
			action = 3;
		} else {
			fw_put_msg(fw, 0x11);
			phase = 1;
			action = 1;
		}
		flags &= 0x3FFFFFFF;
		goto send;
	}
	if (flags & 1)
		fw_put_msg(fw, 5);
	else {
		dp = IDLUNToDP(hba, (unsigned char)id, (unsigned char)lun);
		if (CAM_U32(&dp->frozen) & 0x40200) {
			unsigned int wdtr = dp->wide & 4;
			fw_put_msg(fw, 1);
			if (wdtr == 0) {
				fw_put_msg(fw, 3);
				fw_put_msg(fw, 1);
				if (dp->sync & 1) {
					fw_put_msg(fw, 0);
					fw_put_msg(fw, 0);
				} else {
					if (hba->negstate[id] != 3 &&
					    hba->syncOffset <= 0x31)
						fw_put_msg(fw, 0x32);
					else
						fw_put_msg(fw, hba->syncOffset);
					fw_put_msg(fw, hba->syncPeriod);
				}
			} else {
				fw_put_msg(fw, 2);
				fw_put_msg(fw, 3);
				if (hba->width & 2)
					fw_put_msg(fw, 2);
				else
					fw_put_msg(fw, hba->width);
				dp->wide &= 0xFB;
			}
			phase = 2;
			goto send;
		}
	}
	if (CAM_U16(&fw->sync) == 0) {
		CAM_FWB(fw, 0x2A) = 8;
		CAM_U16(&fw->sync) = 1;
		phase = 3;
		action = 1;
	}
send:
	r = FSendMsg(hba);
	r = (unsigned short)r;
	if (r < 2)
		return r == 0 ? 0 : 1;
	switch (r - 2) {
	case 0:
	case 6:
		if (ccb != 0)
			ccb->simFlags = flags;
		goto after;
	case 5:
		if (GetCompleteMsg(hba) == 0)
			goto after;
		if (CAM_HBAB(hba, 0x79) == 0)
			goto after;
		action = 4;
		if (CAM_HBAB(hba, 0x71) == 1)
			goto extmsg;
		goto after;
	case 7:
		goto restart;
	case 8:
		if (phase != 1)
			goto after;
		if (ccb != 0)
			ccb->simFlags = flags;
		goto after;
	case 1:
	case 2:
	case 3:
	case 4:
		if (phase != 2)
			break;
		dp = IDLUNToDP(hba, (unsigned char)id, (unsigned char)lun);
		{
			unsigned int wdtr = dp->wide & 4;
			for (i = 0; i <= 0x1B; i++) {
				if (DEVs[i].id != (unsigned char)id)
					continue;
				if (DEVs[i].lun != (unsigned char)lun)
					continue;
				if (wdtr == 0)
					DEVs[i].sync = 0;
				else
					DEVs[i].wide = 0;
				if (wdtr == 0)
					DEVs[i].flags |= 0x20;
				else
					DEVs[i].flags |= 0x40;
			}
			if (wdtr == 0)
				FSetSync(hba, 0, 0, id, lun);
			else
				FSetWide(hba, 0, id, lun);
			hba_set_resmsg(hba, id, fw->msgOut);
		}
		FResetBus(hba);
		return 1;
	default:
		break;
	}
after:
	if (action == 2) {
		ResetDevice(hba, id, 0x17);
		return 0x0C;
	}
	if (action == 3) {
		AbortedRequest(hba, ccb);
		return 0x0C;
	}
	if (action == 4) {
		CAM_U16(&fw->sync) = 0;
		r = FMsgResponse(hba);
		if ((unsigned short)r == 9)
			return 6;
		if ((unsigned short)r == 7)
			return 5;
		if ((unsigned short)r == 8 || (unsigned short)r == 2)
			goto restart;
		return 3;
	}
	return GotMSG(hba, 0);
extmsg:
	kind = WhatMsgIsIt(&CAM_HBAB(hba, 0x71));
	if (phase == 2) {
		if (kind == 1)
			FSetSync(hba, CAM_HBAB(hba, 0x75), CAM_HBAB(hba, 0x74), id, lun);
		else if (kind == 3)
			FSetWide(hba, CAM_HBAB(hba, 0x74), id, lun);
		else
			return 0x0C;
		if (kind == 3 && kind == 1) {
			/* keep IDA path: SDTR reply after WDTR */
		}
		if (kind == 1) {
			/* fall through */
		}
		hba_set_resmsg(hba, id, fw->msgOut);
		dp = IDLUNToDP(hba, (unsigned char)id, (unsigned char)lun);
		if (kind == 1) {
			if (CAM_HBAB(hba, 0x75) != 0)
				dp->sync = 1;
			else
				dp->sync = 0;
		} else
			dp->wide = CAM_HBAB(hba, 0x74);
	}
	return GotMSG(hba, 0);
}
