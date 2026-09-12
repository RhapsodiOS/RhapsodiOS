/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * EATAControllerTypes.h - EATA PIO/DMA layouts from DPTSCSIDriver_reloc.
 *
 * HISTORY
 *
 * Reconstructed from DPTSCSIDriver_reloc (IDA partition of record).
 */

#ifndef _EATACONTROLLERTYPES_H
#define _EATACONTROLLERTYPES_H

#import <driverkit/driverTypes.h>
#import <kernserv/queue.h>
#import <kernserv/clock_timer.h>
#import <mach/boolean.h>
#import <mach/port.h>
#import <bsd/dev/scsireg.h>

#if defined(i386) || defined(__i386__)
#import <driverkit/i386/ioPorts.h>
#else
/* PPC rbuild has no i386 PIO headers or IOEISADMABuffer. */
#ifndef IOEISADMABuffer
typedef void *IOEISADMABuffer;
#endif
#ifndef IOMallocLow
#define IOMallocLow		IOMalloc
#define IOFreeLow		IOFree
#endif
#ifndef IO_Cascade
#define IO_Demand	0
#define IO_Single	1
#define IO_Block	2
#define IO_Cascade	3
#endif
#define inb(port)		((unsigned char)0)
#define inw(port)		((unsigned short)0)
#define outb(port, val)		((void)0)
#endif

/*
 * Register offsets from ioBase. Every offset is an IDA immediate
 * (add dx/cx, N) on DPTSCSIDriver_reloc.
 */
#define EATA_DATA_OFF		0x00	/* 16-bit PIO config data */
#define EATA_ADDR0_OFF		0x02	/* physical address, LSB */
#define EATA_ADDR1_OFF		0x03
#define EATA_ADDR2_OFF		0x04
#define EATA_ADDR3_OFF		0x05	/* physical address, MSB */
#define EATA_STATUS_OFF		0x07	/* in: status; out: command */
#define EATA_CMD_OFF		0x07
#define EATA_AUX_STATUS_OFF	0x08	/* _eata_busy / _eata_busy_0 */

/*
 * Commands written to ioBase+7.
 */
#define EATA_CMD_READ_CONFIG_PIO	0xF0	/* readConfig */
#define EATA_CMD_RESET			0xF9	/* threadResetBus:initConfig: */
#define EATA_CMD_READ_CONFIG_DMA	0xFD	/* readDMAConfig */
#define EATA_CMD_SEND_CP		0xFF	/* threadExecuteRequest: */

/*
 * Status bits actually tested by the reloc.
 */
#define EATA_AUX_BUSY		0x01	/* test al, 1 on aux */
#define EATA_STAT_DRQ		0x08	/* test al, 8 on status while PIO */

/*
 * Config signature after the reloc bswap of bytes +4..+7.
 */
#define EATA_SIGNATURE		0x45415441	/* "EATA" */

#define EATA_CONFIG_SIZE	0x28
#define EATA_CP_SIZE		0x2c
#define EATA_SP_SIZE		0x18
#define EATA_CCB_SIZE		0x37c
#define EATA_SG_COUNT		64
#define EATA_CHANNEL_COUNT	3

#define EATA_BUS_EISA		0
#define EATA_BUS_ISA		1
#define EATA_BUS_PCI		2

#define EATA_PCI_REGISTER_SPACE	9
#define EATA_PCI_REGISTER_OFFSET	0x10
#define EATA_EISA_SLOT_BASE	0xC88
#define EATA_EISA_PORT_SIZE	8

/*
 * Immediate written to CP byte 1 (ccb+9).
 */
#define EATA_CP_IMMEDIATE	0x1A

/*
 * CP flags at ccb+8, polarity from ccbFromCmd:.
 */
#define EATA_CP_AUTO_REQ_SEN	0x04
#define EATA_CP_SCATTER		0x08
#define EATA_CP_DATA_OUT	0x40
#define EATA_CP_DATA_IN		0x80

/*
 * CP+8 (ccb+0x10): identify / physical.
 */
#define EATA_CP_LUN_MASK	0x07
#define EATA_CP_TARGET_MASK	0x1F
#define EATA_CP_PHYSICAL	0x40
#define EATA_CP_IDENTIFY	0x80

/*
 * eata_config — ObjC encoding of the config ivar at instance +0x140.
 * 40 bytes. Do not substitute a Linux dpt_config / eata_config.
 */
typedef struct eata_config {
	unsigned int	config_data_len;	/* +0 */
	unsigned int	eata_signature;		/* +4 */
	unsigned char	mbz0:4,			/* +8 */
			version:4;
	unsigned char	overlap_ok:1,		/* +9 */
			target_mode_ok:1,
			truncate_needed:1,
			more_bit_ok:1,
			dma_ok:1,
			dma_channel_valid:1,
			is_ata:1,
			addr_valid:1;
	unsigned short	command_pad;		/* +10 */
	unsigned char	rsvd0;			/* +12 */
	unsigned char	host_addrs[3];		/* +13 */
	unsigned int	command_length;		/* +16 */
	unsigned int	status_length;		/* +20 */
	unsigned short	queue_size;		/* +24 */
	unsigned char	rsvd1[2];		/* +26 */
	unsigned short	sg_size;		/* +28 */
	unsigned char	irq:4,			/* +30 */
			edge_triggered:1,
			secondary:1,
			dma_channel:2;
	unsigned char	rsvd2;			/* +31 */
	unsigned char	isaIoDisable:1,		/* +32 */
			forceAddr:1,
			rsvd3:6;
	unsigned char	maxScsiId:5,		/* +33 */
			maxChannel:3;
	unsigned char	maxLun;			/* +34 */
	unsigned char	rsvd4:6,		/* +35 */
			pci:1,
			eisa:1;
	unsigned char	raidnum;		/* +36 */
	unsigned char	rsvd5;			/* +37 */
} eata_config_t;

/*
 * In-memory command packet at ccb+8, 0x2c bytes (bzero 2Ch in ccbFromCmd:).
 */
struct eata_cp {
	unsigned char	scsi_reset:1,		/* +0x00 flags */
			hba_init:1,
			auto_req_sen:1,
			scatter:1,
			rsvd_flags:1,
			interpret:1,
			data_out:1,
			data_in:1;
	unsigned char	immediate;		/* +0x01, reloc writes 0x1A */
	unsigned char	rsvd0[5];		/* +0x02 */
	unsigned char	target:5,		/* +0x07 */
			channel:3;
	unsigned char	lun:3,			/* +0x08 */
			rsvd_id:3,
			physical:1,
			identify:1;
	unsigned char	rsvd1[3];		/* +0x09 */
	unsigned char	cdb[12];		/* +0x0c */
	unsigned int	data_len;		/* +0x18 */
	unsigned int	virt_addr;		/* +0x1c */
	unsigned int	data_addr;		/* +0x20 */
	unsigned int	sp_addr;		/* +0x24 */
	unsigned int	sense_addr;		/* +0x28 */
};

/*
 * Status packet at ccb+0x34, 0x18 bytes (bzero 18h in ccbFromCmd:).
 * EOC is the sign bit of the first byte, not 0x01.
 */
struct eata_sp {
	unsigned char	eoc;			/* +0x00, sign bit set => done */
	unsigned char	status;			/* +0x01 SCSI/host status */
	unsigned char	rsvd0[2];
	unsigned int	residue;		/* +0x04 */
	unsigned char	rsvd1[16];
};

struct eata_sg {
	unsigned int	addr;
	unsigned int	len;
};

/*
 * In-memory CCB. sizeof == 0x37c (allocCcb: stride / bzero).
 */
struct ccb {
	queue_chain_t		ccbQ;		/* +0x00 / +0x04 */
	struct eata_cp		cp;		/* +0x08, 0x2c bytes */
	struct eata_sp		sp;		/* +0x34, 0x18 bytes */
	unsigned int		total_xfer_len;	/* +0x4c */
	void			*cmdBuf;	/* +0x50 */
	struct eata_sg		sg_list[EATA_SG_COUNT];	/* +0x54 */
	IOEISADMABuffer		dmaList[EATA_SG_COUNT];	/* +0x254 */
	/*
	 * ns_time_t at +0x354. Stored as two words so compilers that
	 * 8-align long long do not insert padding (0x354 % 8 == 4).
	 */
	unsigned int		startTime[2];	/* +0x354 / +0x358 */
	port_t			timeoutPort;	/* +0x35c */
	esense_reply_t		senseData;	/* +0x360 */
};

#endif /* _EATACONTROLLERTYPES_H */
