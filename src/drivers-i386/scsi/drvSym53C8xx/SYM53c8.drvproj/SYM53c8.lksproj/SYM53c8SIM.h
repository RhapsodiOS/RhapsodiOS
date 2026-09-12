/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * SYM53c8SIM.h - CAM SIM layer of the NCR SDMS engine in SYM53c8_reloc.
 *
 * HISTORY
 *
 * Oct 1998	Created.
 *
 * Every prototype, offset and immediate below is read out of the IDA
 * partition of record for SYM53c8_reloc (divergences.md, "Method").  The
 * SIM is the half of the CAM engine that owns _HBAs, _DEVs and _ROMs and
 * that the DriverKit class drives: -[SYM53c8 interruptOccurred] calls
 * SIMInterrupt, the ticktock callout calls SIMTickTock, and the init path
 * calls SIMInit / SIMAddPath.  The XPT half (xpt_*, F*, StartNewIO,
 * BeginScan, ...) lives in SYM53c8CAM.c and is only declared here.
 *
 * The overlays in SYM53c8Types.h (struct sym_hba, struct sym_dev,
 * struct cam_ccb) were sketched from convertReq: stores alone and are
 * narrower than, and in places disagree with, what the SIM instruction
 * stream requires.  The structures below are the SIM's own view of the
 * same objects; reconciling the two headers is a later pass.
 */

#ifndef _SYM53C8SIM_H_
#define _SYM53C8SIM_H_

#import "SYM53c8Types.h"

struct sim_q;
struct sim_fwctx;
struct sim_fw;
struct sim_rom;
struct sim_dev;
struct sim_hba;
struct sim_ccb;
struct sim16_ccb;

/*
 * Doubly linked queue element.  QInsert / QAppend / QDelete work on these;
 * a head is an element whose next and prev point at itself.  CCBs carry two
 * of them, the device/adapter link at +0x58 and the timeout link at +0x64.
 */
struct sim_q {
	struct sim_q		*next;			/* +0x00 */
	struct sim_q		*prev;			/* +0x04 */
	void			*owner;			/* +0x08 */
};

/*
 * The CAMcore context block.  hba->base and rom->ctx both point at one of
 * these; only the three bytes the SIM reads are named.
 */
struct sim_fwctx {
	unsigned char		rsvd00[3];		/* +0x00 */
	unsigned char		hbaType;		/* +0x03 */
	unsigned char		rsvd04;			/* +0x04 */
	unsigned char		initiatorId;		/* +0x05 */
	unsigned char		rsvd06[21];		/* +0x06 */
	unsigned char		intEnable;		/* +0x1B */
};

/*
 * The firmware register/state window, hba->base + 0x140.  _FRun writes the
 * command byte at +0x14 and reads the result at +0x15; the SIM reads the
 * rest.  +0x1E is an unaligned CCB pointer, so it is kept as bytes.
 */
struct sim_fw {
	struct sim_ccb		*active;		/* +0x00 */
	struct sim_ccb		*pending;		/* +0x04 */
	unsigned char		curid;			/* +0x08 */
	unsigned char		selid;			/* +0x09, >= 0x80 is idle */
	unsigned char		sellun;			/* +0x0A */
	unsigned char		rsvd0B[2];		/* +0x0B */
	unsigned char		contFlag;		/* +0x0D */
	unsigned char		abortFlag;		/* +0x0E */
	unsigned char		msgFlag;		/* +0x0F */
	unsigned int		msgOut;			/* +0x10 */
	unsigned char		command;		/* +0x14 */
	unsigned char		result;			/* +0x15 */
	short			sync;			/* +0x16 */
	unsigned char		lunmask;		/* +0x18 */
	unsigned char		rsvd19;			/* +0x19 */
	unsigned char		tag;			/* +0x1A */
	unsigned char		rsvd1B;			/* +0x1B */
	unsigned short		resetCause;		/* +0x1C */
	unsigned char		completed[4];		/* +0x1E struct sim_ccb * */
	unsigned char		rsvd22[8];		/* +0x22 */
	unsigned char		msgIn[4];		/* +0x2A */
};

/*
 * One _ROMs slot, stride 100.  _FindROMs fills these in; the SIM only
 * dispatches through them.  rom->run / rom->poll / rom->action are the
 * CAMcore entry points _FRun and friends call as [rom+0x0C].
 */
struct sim_rom {
	struct sim_fwctx	*ctx;			/* +0x00 */
	unsigned char		simType;		/* +0x04, 0x16 or 0x17 */
	unsigned char		path;			/* +0x05 */
	unsigned char		irq;			/* +0x06 */
	unsigned char		rsvd07[5];		/* +0x07 */
	unsigned int		(*run)();		/* +0x0C */
	unsigned int		(*poll)();		/* +0x10 */
	unsigned int		(*action)();		/* +0x14 */
	unsigned char		rsvd18[2];		/* +0x18 */
	char			name[16];		/* +0x1A */
	unsigned char		rsvd2A[48];		/* +0x2A */
	unsigned short		active;			/* +0x5A */
	unsigned char		rsvd5C[8];		/* +0x5C */
};

#define SIM_ROM_SLOTS			4
#define SIM_ROM_TYPE16			0x16
#define SIM_ROM_TYPE17			0x17

/*
 * One _DEVs slot, stride 16.  Empty slots carry id 0xFF.
 */
struct sim_dev {
	unsigned char		path;			/* +0x00 */
	unsigned char		id;			/* +0x01 */
	unsigned char		lun;			/* +0x02 */
	unsigned char		rsvd03;			/* +0x03 */
	struct sim_q		*queue;			/* +0x04 */
	unsigned char		frozen;			/* +0x08 */
	unsigned char		sync;			/* +0x09 */
	unsigned char		wide;			/* +0x0A */
	unsigned char		flags;			/* +0x0B */
	unsigned char		rsvd0C[4];		/* +0x0C */
};

/*
 * One _HBAs slot, stride 0x140.  _SIMAddPath hands it the CAMcore work
 * area; everything past +0x100 is SIM bookkeeping indexed by target.
 */
struct sim_hba {
	struct sim_fwctx	*base;			/* +0x000 */
	struct sim_fw		*fw;			/* +0x004 */
	unsigned char		devmap[8][8];		/* +0x008 */
	struct sim_dev		*devs;			/* +0x048 */
	struct sim_q		actq;			/* +0x04C */
	struct sim_q		snsq;			/* +0x058 */
	unsigned short		snscount;		/* +0x064 */
	unsigned char		rsvd066[2];		/* +0x066 */
	struct sim_ccb		*snsccb;		/* +0x068 */
	unsigned char		path;			/* +0x06C */
	unsigned char		syncPeriod;		/* +0x06D */
	unsigned char		syncOffset;		/* +0x06E */
	unsigned char		width;			/* +0x06F */
	unsigned char		rsvd070;		/* +0x070 */
	unsigned char		msgState;		/* +0x071 */
	unsigned char		rsvd072[8];		/* +0x072 */
	unsigned char		running;		/* +0x07A */
	unsigned char		rsvd07B[129];		/* +0x07B */
	unsigned short		queued;			/* +0x0FC */
	unsigned char		resume;			/* +0x0FE */
	unsigned char		rsvd0FF;		/* +0x0FF */
	struct sim_rom		*rom;			/* +0x100 */
	unsigned char		ndone;			/* +0x104 */
	unsigned char		rsvd105[2];		/* +0x105 */
	unsigned char		done[8];		/* +0x107 */
	unsigned char		negstate[8];		/* +0x10F */
	unsigned char		resmsg[32];		/* +0x117, 8 unaligned longs */
	unsigned char		frozen[8];		/* +0x137 */
	unsigned char		rsvd13F;		/* +0x13F */
};

/*
 * The CAM CCB as the SIM reads and writes it.  The header through +0x57 is
 * the CAM SCSI I/O block _xpt_ccb_alloc hands out; +0x58 through +0x9B is
 * SIM private, and _MaxCCBPrivateLen more bytes follow.
 */
struct sim_ccb {
	unsigned int		my_addr;		/* +0x00 */
	unsigned short		ccb_len;		/* +0x04 */
	unsigned char		func_code;		/* +0x06 */
	unsigned char		status;			/* +0x07 */
	unsigned char		rsvd08;			/* +0x08 */
	unsigned char		path;			/* +0x09 */
	unsigned char		target;			/* +0x0A */
	unsigned char		lun;			/* +0x0B */
	unsigned char		flags0;			/* +0x0C */
	unsigned char		flags1;			/* +0x0D */
	unsigned char		flags2;			/* +0x0E */
	unsigned char		flags3;			/* +0x0F */
	struct sim_ccb		*link_ccb;		/* +0x10 abort target / autosense parent */
	struct sim_ccb		*next_ccb;		/* +0x14 */
	unsigned char		rsvd18[4];		/* +0x18 */
	void			(*complete)();		/* +0x1C */
	void			*data;			/* +0x20 */
	unsigned int		dxfer_len;		/* +0x24 */
	unsigned char		*sense_ptr;		/* +0x28 */
	unsigned char		sense_len;		/* +0x2C */
	unsigned char		cdb_len;		/* +0x2D */
	unsigned short		sglist_cnt;		/* +0x2E */
	unsigned int		osd_rsvd;		/* +0x30 */
	unsigned char		scsi_status;		/* +0x34 */
	unsigned char		sense_resid;		/* +0x35 */
	unsigned short		rsvd36;			/* +0x36 */
	unsigned int		resid;			/* +0x38 */
	unsigned char		cdb[12];		/* +0x3C */
	unsigned int		timeout;		/* +0x48 */
	unsigned char		*msg_ptr;		/* +0x4C */
	unsigned short		msgb_len;		/* +0x50 */
	unsigned short		vu_flags;		/* +0x52 */
	unsigned char		tag_action;		/* +0x54 */
	unsigned char		rsvd55[3];		/* +0x55 */
	struct sim_q		qlink;			/* +0x58 */
	struct sim_q		timelink;		/* +0x64 */
	unsigned char		rsvd70[8];		/* +0x70 */
	unsigned short		xferCount;		/* +0x78 */
	unsigned char		rsvd7A[6];		/* +0x7A */
	unsigned int		xferLeft;		/* +0x80 */
	unsigned char		rsvd84[8];		/* +0x84 */
	unsigned int		simFlags;		/* +0x8C */
	unsigned int		deadline;		/* +0x90 */
	unsigned char		requeue;		/* +0x94 */
	unsigned char		rsvd95[7];		/* +0x95 */
};

#define SIM_CCB_FIXEDLEN		0x9C

/*
 * The same CCB seen through the func code 3 path-inquiry reply that
 * _SIM17Action builds.
 */
struct sim_pathinq {
	unsigned char		hdr[0x10];		/* +0x00 */
	unsigned char		version_num;		/* +0x10 */
	unsigned char		hba_inquiry;		/* +0x11 */
	unsigned char		target_sprt;		/* +0x12 */
	unsigned char		rsvd13;			/* +0x13 */
	unsigned short		hba_eng_cnt;		/* +0x14 */
	unsigned char		sim_type;		/* +0x16 */
	unsigned char		initiator_id;		/* +0x17 */
	unsigned char		rsvd18[12];		/* +0x18 */
	unsigned int		priv_data_size;		/* +0x24 */
	unsigned int		async_flags;		/* +0x28 */
	unsigned char		rsvd2C;			/* +0x2C */
	unsigned char		hba_path_id;		/* +0x2D */
	unsigned char		rsvd2E[2];		/* +0x2E */
	char			sim_vid[16];		/* +0x30 */
	char			hba_vid[16];		/* +0x40 */
};

/*
 * The 16-bit SIM's CCB, 0xC0 bytes.  _SIM16Start and _SIM16Action take one,
 * and _CHSCCB is the SIM's own scratch copy.
 */
struct sim16_ccb {
	unsigned char		rsvd00[2];		/* +0x00 */
	unsigned char		op;			/* +0x02 */
	unsigned char		status;			/* +0x03 */
	unsigned char		scsi_status;		/* +0x04 */
	unsigned char		path;			/* +0x05 */
	unsigned char		rsvd06[2];		/* +0x06 */
	unsigned int		word8;			/* +0x08 */
	unsigned char		target;			/* +0x0C */
	unsigned char		lun;			/* +0x0D */
	unsigned char		rsvd0E[2];		/* +0x0E */
	unsigned char		byte10;			/* +0x10 */
	unsigned char		flags;			/* +0x11 */
	unsigned short		w12;			/* +0x12 */
	unsigned short		w14;			/* +0x14 */
	unsigned char		rsvd16[6];		/* +0x16 */
	unsigned int		opflags;		/* +0x1C */
	unsigned int		arg_ffff;		/* +0x20 */
	unsigned int		arg0;			/* +0x24 */
	unsigned int		arg1;			/* +0x28 */
	unsigned int		arg2;			/* +0x2C */
	unsigned char		rsvd30[4];		/* +0x30 */
	struct sim_ccb		*ccb17;			/* +0x34 */
	void			(*complete)();		/* +0x38 */
	unsigned char		rsvd3C[8];		/* +0x3C */
	unsigned char		cdb[6];			/* +0x44 */
	unsigned char		rsvd4A[0x3A];		/* +0x4A */
	struct sim_q		qlink;			/* +0x84 */
	unsigned char		rsvd90[0x30];		/* +0x90 */
};

#define SIM16_CCB_LEN			0xC0

/*
 * CCB func codes the SIM dispatches on.  Named for what the bodies do; the
 * reference has no NCR header to take spellings from.
 */
#define SIM_FUNC_NOOP			0x00
#define SIM_FUNC_IO			0x01
#define SIM_FUNC_PATH_INQ		0x03
#define SIM_FUNC_REL_SIMQ		0x04
#define SIM_FUNC_ASYNC_CB		0x05
#define SIM_FUNC_ABORT			0x10
#define SIM_FUNC_RESET_BUS		0x11
#define SIM_FUNC_RESET_DEV		0x12
#define SIM_FUNC_TERM_IO		0x13
#define SIM_FUNC_VENDOR			0x82

/*
 * SIM state that the rest of the CAM engine indexes directly.
 */
extern struct sim_hba		HBAs[SYM_HBA_SLOTS];
extern struct sim_dev		DEVs[SYM_DEV_SLOTS];
extern struct sim_ccb		*PendingAborts[8];
extern struct sim_q		simqs[SYM_DEV_SLOTS];
extern struct sim_q		*simqStack[SYM_DEV_SLOTS];
extern unsigned short		simqTOS;
extern unsigned short		TotalDEVs;
extern unsigned int		TickCount;
extern struct sim_q		timeq;
extern struct sim_rom		ROMs[SIM_ROM_SLOTS];
extern int			numROMs;
extern unsigned short		MaxCCBPrivateLen;
extern struct sim_q		q16to17;
extern struct sim_q		q17to16;
extern struct sim16_ccb		*ccb16[7];
extern struct sim_ccb		*ccb17[7];
extern struct sim16_ccb		CHSCCB;

/*
 * DriverKit-facing SIM entry points.  -[SYM53c8 interruptOccurred] calls
 * SIMInterrupt; the ticktock callout calls SIMTickTock; the init path calls
 * SIMInit then SIMAddPath.  SIM16Action / SIM17Action are what XPT hands a
 * CCB to.
 */
extern int			SIMInit(void *arg);
extern void			SIM17Init(void);
extern int			SIMAddPath(void *mem, unsigned char path);
extern unsigned short		SIMActionInit(void);
extern void			SIMStart(struct sim_ccb *ccb);
extern void			SIMRun(unsigned short path);
extern void			SIMInterrupt(unsigned char irq);
extern void			SIMTickTock(void);
extern unsigned short		RespondToComp(struct sim_hba *hba, struct sim_ccb *ccb);
extern void			CallComp(struct sim_hba *hba, struct sim_ccb *ccb);
extern void			CallCompletion(struct sim16_ccb *ccb);
extern void			RespondToBusReset(struct sim_hba *hba);
extern int			CCBInSIMQueue(struct sim_hba *hba, struct sim_ccb *ccb);
extern int			SIM16Start(struct sim16_ccb *ccb);
extern void			SIM16Int(struct sim_rom *rom);
extern int			SIM16Action(struct sim16_ccb *ccb);
extern int			SIM17Action(struct sim_ccb *ccb);

/*
 * SIM primitives the XPT half also calls.
 */
extern int			DisableInterrupts(void);
extern int			EnableInterrupts(void);
extern void			RestoreInterrupts(int state);
extern void			QInsert(struct sim_q *head, struct sim_q *elem, void *owner);
extern void			QAppend(struct sim_q *head, struct sim_q *elem, void *owner);
extern void			QDelete(struct sim_q *elem);
extern struct sim_dev		*IDLUNToDP(struct sim_hba *hba, unsigned char id,
					   unsigned char lun);
extern struct sim_rom		*PathToROMInfoPtr(unsigned char path);
extern int			GetNumROMs(void);
extern struct sim_rom		*GetROMTableBase(void);
extern unsigned int		GetWidth(unsigned char path);
extern void			SIMClearMem(void *mem, unsigned short len);
extern void			Do17On16(struct sim_ccb *ccb);
extern void			Do16On17(struct sim16_ccb *ccb);
extern void			Start17On16(struct sim_ccb *ccb17,
					    struct sim16_ccb *ccb16);
extern void			Start16On17(struct sim16_ccb *ccb16,
					    struct sim_ccb *ccb17);

/*
 * CAM / XPT half. Bodies are in SYM53c8CAM.c.
 */
extern unsigned short		FindROMs(void);
extern int			InitROMs(void *arg);
extern void			*MemAlloc(unsigned int size);
extern unsigned int		VtoP(void *virt);
extern unsigned short		FCalcSync(struct sim_hba *hba, unsigned int id,
					  unsigned int flag);
extern void			FWideInit(struct sim_hba *hba);
extern void			InitializeQueueTags(struct sim_hba *hba);
extern unsigned int		FRun(struct sim_hba *hba);
extern unsigned int		FResumeXFer(struct sim_hba *hba);
extern unsigned int		FResetBus(struct sim_hba *hba);
extern unsigned int		FRespRes(struct sim_hba *hba);
extern void			CheckForStart(struct sim_hba *hba, int flag);
extern struct sim_ccb		*FindRunningRequest(struct sim_hba *hba,
						    unsigned int id,
						    unsigned int lun,
						    unsigned int tag);
extern void			SetFrag(struct sim_ccb *ccb,
					unsigned int initiatorId);
extern unsigned int		GotMSG(struct sim_hba *hba, int flag);
extern unsigned int		WantMSG(struct sim_hba *hba);
extern void			FreeQueueTag(struct sim_hba *hba,
					     struct sim_ccb *ccb);
extern void			AutosenseSetup(struct sim_hba *hba);
extern void			PreTransfer17(struct sim_ccb *ccb,
					      unsigned int initiatorId);
extern void			PostTransfer17(struct sim_ccb *ccb,
					       unsigned int initiatorId);
extern void			PreTransfer16(struct sim16_ccb *ccb,
					      unsigned int initiatorId);
extern void			PostTransfer16(struct sim16_ccb *ccb);
extern unsigned short		PeekAtData(struct sim_ccb *ccb, int off);
extern void			DoneWithCurrentData(struct sim_ccb *ccb);
extern struct sim_dev		*AddToDeviceList(struct sim_hba *hba,
						unsigned int id,
						unsigned int lun);
extern void			ResetDevice(struct sim_hba *hba,
					    unsigned int id,
					    unsigned int reason);
extern void			xpt_async(int opcode, unsigned int path,
					  unsigned int a, unsigned int b,
					  unsigned int c, unsigned int d);
extern void			T17To16(struct sim_ccb *ccb17,
					struct sim16_ccb *ccb16);
extern void			T16To17(struct sim16_ccb *ccb16,
					struct sim_ccb *ccb17);
extern unsigned char		Stat16To17(unsigned int status);
extern unsigned char		Stat17To16(unsigned int status);
extern void			StuffAction(void *bus);

#endif /* _SYM53C8SIM_H_ */
