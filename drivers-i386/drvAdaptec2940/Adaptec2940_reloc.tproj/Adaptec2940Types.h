/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * Adaptec 2940 SCSI controller definitions.
 *
 * HISTORY
 *
 * Created for Rhapsody OS - AIC-7xxx chipset definitions
 */

#ifndef _ADAPTEC2940TYPES_H
#define _ADAPTEC2940TYPES_H

#import <driverkit/i386/driverTypes.h>
#import <kernserv/ns_timer.h>
#import <kernserv/queue.h>
#import <mach/boolean.h>
#import <bsd/dev/scsireg.h>

/*
 * AIC-7xxx register offsets
 */
#define AIC_SCSISEQ		0x00
#define AIC_SXFRCTL0		0x01
#define AIC_SXFRCTL1		0x02
#define AIC_SCSISIG		0x03
#define AIC_SCSIBUS		0x03
#define AIC_SSTAT0		0x0b
#define AIC_SSTAT1		0x0c
#define AIC_SSTAT2		0x0d
#define AIC_SCSIID		0x05
#define AIC_SBLKCTL		0x1f
#define AIC_SEQCTL		0x60
#define AIC_SEQRAM		0x61
#define AIC_SEQADDR0		0x62
#define AIC_SEQADDR1		0x63
#define AIC_INTSTAT		0x91
#define AIC_CLRINT		0x92
#define AIC_ERROR		0x92
#define AIC_DFCNTRL		0x93
#define AIC_DFSTATUS		0x94
#define AIC_DFDAT		0x99
#define AIC_SCBPTR		0x90
#define AIC_SCBARRAY		0xa0
#define AIC_QINFIFO		0xd5
#define AIC_QOUTFIFO		0xd6
#define AIC_QINCNT		0xd7
#define AIC_QOUTCNT		0xd8

/*
 * SCSISEQ register bits
 */
#define TEMODEO		0x80
#define ENSELO		0x40
#define ENSELI		0x20
#define ENRSELI		0x10
#define ENAUTOATNO	0x08
#define ENAUTOATNI	0x04
#define ENAUTOATNP	0x02
#define SCSIRSTO	0x01

/*
 * INTSTAT register bits
 */
#define SEQINT		0x01
#define CMDCMPLT	0x02
#define SCSIINT		0x04
#define BRKADRINT	0x08
#define BAD_PHASE	0x01

/*
 * SSTAT1 register bits
 */
#define SELTO		0x80
#define ATNTARG		0x40
#define SCSIRSTI	0x20
#define PHASEMIS	0x10
#define BUSFREE		0x08
#define SCSIPERR	0x04
#define PHASECHG	0x02
#define REQINIT		0x01

/*
 * SEQCTL register bits
 */
#define PERRORDIS	0x80
#define PAUSEDIS	0x40
#define FAILDIS		0x20
#define FASTMODE	0x10
#define BRKADRINTEN	0x08
#define STEP		0x04
#define SEQRESET	0x02
#define LOADRAM		0x01

/*
 * Scatter/gather descriptor
 */
struct aic_sg {
	unsigned int	addr;
	unsigned int	len;
};

#define AIC_SG_COUNT	17

/*
 * SCSI Control Block (SCB)
 */
struct scb {
	/* Hardware portion */
	unsigned char	control;
	unsigned char	tcl;		/* target/channel/lun */
	unsigned char	target_status;
	unsigned char	sg_count;
	unsigned int	sg_ptr;
	unsigned int	residual_sg_count;
	unsigned int	residual_data_count;
	unsigned int	data_ptr;
	unsigned int	data_count;
	unsigned int	cmdptr;
	unsigned char	cmdlen;
	unsigned char	tag;
	unsigned char	next;
	unsigned char	prev;

	/* Software extension */
	struct aic_sg	sg_list[AIC_SG_COUNT];
	unsigned int	total_xfer_len;
	ns_time_t	startTime;
	port_t		timeoutPort;
	void		*cmdBuf;
	boolean_t	in_use;
	queue_chain_t	scbQ;
	union cdb	cdb;
	esense_reply_t	senseData;
};

/*
 * Configuration data
 */
struct adaptec2940_config {
	unsigned char	scsi_id;
	unsigned char	max_targets;
	unsigned char	max_luns;
	boolean_t	wide_bus;
	boolean_t	ultra_enabled;
};

/*
 * PCI Device IDs
 */
#define AIC_7850_DEVICE_ID	0x50789004
#define AIC_7860_DEVICE_ID	0x60789004
#define AIC_7870_DEVICE_ID	0x70789004
#define AIC_7871_DEVICE_ID	0x71789004
#define AIC_7872_DEVICE_ID	0x72789004
#define AIC_7873_DEVICE_ID	0x73789004
#define AIC_7874_DEVICE_ID	0x74789004
#define AIC_7880_DEVICE_ID	0x80789004
#define AIC_7881_DEVICE_ID	0x81789004
#define AIC_7882_DEVICE_ID	0x82789004
#define AIC_7883_DEVICE_ID	0x83789004
#define AIC_7884_DEVICE_ID	0x84789004
#define AIC_7895_DEVICE_ID	0x78959004

#endif /* _ADAPTEC2940TYPES_H */
