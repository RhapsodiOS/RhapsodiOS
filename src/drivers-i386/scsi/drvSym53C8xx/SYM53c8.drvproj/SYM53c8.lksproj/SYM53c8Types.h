/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * SYM53c8Types.h - CAM/SIM layouts from SYM53c8_reloc.
 *
 * HISTORY
 *
 * Oct 1998	Created from BusLogic driver.
 * Reconstructed from SYM53c8_reloc instance_vars / convertReq stores
 * (divergences.md). Offsets are IDA immediates; do not treat this as a
 * Linux ncr53c8xx header.
 */

#ifndef _SYM53C8TYPES_H
#define _SYM53C8TYPES_H

#import <driverkit/i386/driverTypes.h>
#import <driverkit/scsiTypes.h>
#import <kernserv/queue.h>
#import <mach/boolean.h>

/*
 * ObjC instance_size and the first SYM53c8 ivar. IOSCSIController occupies
 * the 0x244-byte prefix.
 */
#define SYM53C8_INSTANCE_SIZE		0x600
#define SYM53C8_IVAR_BASE		0x244

#define SYM_SCSIREQ_SIZE		0x1C
#define SYM_REQS_COUNT			32

/*
 * PCI config sampled by -[SYM53c8 initFromDeviceDescription:].
 * BAR0 is an I/O BAR (bit 0 set); and 0xFC yields the port base; range
 * length is 0x100. interruptLine is at config +0x3C.
 */
#define SYM_PCI_BAR0_OFF		0x10
#define SYM_PCI_INTLINE_OFF		0x3C
#define SYM_PCI_IO_SPACE		0x01
#define SYM_PCI_IO_MASK			0xFC
#define SYM_PCI_IO_RANGE		0x100

/*
 * ISA BIOS window mapped when path == 0, then unmapped after _xpt_init.
 */
#define SYM_BIOS_WINDOW_PHYS		0xE0000
#define SYM_BIOS_WINDOW_SIZE		0x20000

/*
 * SIM _HBAs: stride 0x140, 4 slots (walk from _HBAs until 0xA8C4).
 * Firmware register window pointer at +4; path byte at +0x6C;
 * CAMcore vtable at +0x100.
 */
#define SYM_HBA_STRIDE			0x140
#define SYM_HBA_SLOTS			4
#define SYM_HBA_FW_WINDOW		0x04
#define SYM_HBA_PATH			0x6C
#define SYM_HBA_CAMCORE			0x100

/*
 * _FRun / _FResumeXFer / _FResetBus write a command byte to
 * [*(HBA+4)+0x14] (ISTAT-sized offset on the firmware window) and call
 * [*(HBA+0x100)+0x0C].
 */
#define SYM_FW_ISTAT_OFF		0x14
#define SYM_FW_CMD_RUN			0x02
#define SYM_FW_CMD_RESUME		0x0D
#define SYM_FW_CMD_RESET		0x0A
#define SYM_CAMCORE_FN			0x0C

/*
 * SIM _DEVs: stride 16, 28 slots. Empty test is id == 0xFF.
 * Slot +0x0B is written 2.
 */
#define SYM_DEV_STRIDE			16
#define SYM_DEV_SLOTS			28
#define SYM_DEV_EMPTY_ID		0xFF
#define SYM_DEV_SLOT_FLAG		0x02

/*
 * XPT _Devtab: stride 0x28. Delete copies 0x0A dwords when compacting.
 */
#define SYM_DEVTAB_STRIDE		0x28
#define SYM_DEVTAB_DWORDS		0x0A

/*
 * convertReq:ToXpt:buffer:client: immediates on the CAM CCB.
 * +0x2C is the compiled function-code byte 0x1A — not named XPT_SCSI_IO;
 * no NCR header in this binary agrees on that symbol.
 */
#define CAM_CCB_FUNC_CODE		0x1A
#define CAM_CCB_SENTINEL		0xBEEFBEEF
#define CAM_CCB_BYTE54			0x20

/*
 * Flags written at CAM CCB +0x0C / +0x0D.
 */
#define CAM_CCB_FLAGS_IN		0x80
#define CAM_CCB_FLAGS_OUT		0x40
#define CAM_CCB_FLAGS_OR		0x20
#define CAM_CCB_FLAGS_TAGGED		0x02
#define CAM_CCB_FLAGS2_OR		0x04
#define CAM_CCB_FLAGS2_10		0x10
#define CAM_CCB_FLAGS2_20		0x20
#define CAM_CCB_FLAGS2_40		0x40
#define CAM_CCB_FLAGS2_80		0x80

struct _scsireq;
struct cam_ccb;

/*
 * CAM / XPT CCB returned by _xpt_ccb_alloc. Free-list link is +0x10.
 * _xpt_ccb_alloc has no size immediate; fields below are convertReq stores.
 */
struct cam_ccb {
	unsigned char		_pad0[0x09];		/* +0x00 */
	unsigned char		path;			/* +0x09 */
	unsigned char		target;			/* +0x0A */
	unsigned char		lun;			/* +0x0B */
	unsigned char		flags;			/* +0x0C */
	unsigned char		flags2;			/* +0x0D */
	unsigned char		_pad1[2];		/* +0x0E */
	void			*freelink;		/* +0x10 */
	unsigned char		_pad2[4];		/* +0x14 */
	struct _scsireq		*scsireq;		/* +0x18 */
	void			(*complete)();		/* +0x1C */
	void			*data;			/* +0x20 */
	unsigned int		dxfer_len;		/* +0x24 */
	unsigned char		*cdb_ptr;		/* +0x28 */
	unsigned char		func_code;		/* +0x2C, 0x1A */
	unsigned char		cdb_len;		/* +0x2D */
	unsigned char		_pad3[2];		/* +0x2E */
	unsigned int		sentinel;		/* +0x30, 0xBEEFBEEF */
	unsigned char		_pad4[8];		/* +0x34 */
	unsigned char		cdb[12];		/* +0x3C */
	unsigned int		timeout;		/* +0x48 */
	unsigned char		_pad5[8];		/* +0x4C */
	unsigned char		byte54;			/* +0x54, 0x20 */
};

/*
 * One reqs[] slot / allocReq object. Encoded size 28 bytes.
 */
struct _scsireq {
	struct cam_ccb		*XPTReq;		/* +0x00 */
	struct _scsireq		*next;			/* +0x04 */
	id			reqLock;		/* +0x08 NXConditionLock */
	IOSCSIRequest		*NeXTReq;		/* +0x0C */
	unsigned int		client;			/* +0x10 */
	id			self;			/* +0x14 SYM53c8 */
	int			biodone;		/* +0x18 */
};

/*
 * SIM HBA slot, 0x140 bytes.
 */
struct sym_hba {
	unsigned char		_pad0[SYM_HBA_FW_WINDOW];
	void			*fw_window;		/* +0x04 */
	unsigned char		_pad1[SYM_HBA_PATH - 8];
	unsigned char		path;			/* +0x6C */
	unsigned char		_pad2[SYM_HBA_CAMCORE - (SYM_HBA_PATH + 1)];
	void			*camcore;		/* +0x100 */
	unsigned char		_pad3[SYM_HBA_STRIDE - (SYM_HBA_CAMCORE + 4)];
};

/*
 * SIM device-list slot, 16 bytes.
 */
struct sym_dev {
	unsigned char		path;			/* +0 */
	unsigned char		id;			/* +1 */
	unsigned char		lun;			/* +2 */
	unsigned char		_pad0;			/* +3 */
	void			*queue;			/* +4 from _simqStack */
	unsigned char		zero8;			/* +8 */
	unsigned char		zero9;			/* +9 */
	unsigned char		zeroA;			/* +0xA */
	unsigned char		slot_flag;		/* +0xB = 2 */
	unsigned char		_pad1[4];		/* +0xC */
};

/*
 * XPT device table entry, 0x28 bytes. path@0, id@1, lun@2.
 */
struct xpt_dev {
	unsigned char		path;			/* +0 */
	unsigned char		id;			/* +1 */
	unsigned char		lun;			/* +2 */
	unsigned char		_pad[SYM_DEVTAB_STRIDE - 3];
};

#endif /* _SYM53C8TYPES_H */
