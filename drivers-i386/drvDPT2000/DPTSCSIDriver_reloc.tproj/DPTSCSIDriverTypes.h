/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * DPT SCSI controller definitions (EATA protocol).
 *
 * HISTORY
 *
 * Created for Rhapsody OS - EATA chipset definitions
 */

#ifndef _DPTSCSIDRIVERTYPES_H
#define _DPTSCSIDRIVERTYPES_H

#import <driverkit/i386/driverTypes.h>
#import <kernserv/ns_timer.h>
#import <kernserv/queue.h>
#import <mach/boolean.h>
#import <bsd/dev/scsireg.h>

/*
 * EATA register offsets (from base I/O port)
 * Based on Linux eata.c driver definitions
 */
#define REG_DATA		0x00	/* Data register */
#define REG_STATUS		0x07	/* Status register (read) */
#define REG_CMD			0x07	/* Command register (write) */
#define REG_AUX_STATUS		0x08	/* Auxiliary status register */
#define REG_LOW			0x02	/* Address low byte */
#define REG_LM			0x03	/* Address low-mid byte */
#define REG_MID			0x04	/* Address mid byte */
#define REG_MSB			0x05	/* Address high byte */

/* Backwards compatibility aliases */
#define EATA_DATA		REG_DATA
#define EATA_CMD		REG_CMD
#define EATA_STATUS		REG_STATUS
#define EATA_AUX_STATUS		REG_AUX_STATUS

/*
 * EATA commands
 */
#define CMD_PIO_SETUPTEST	0xC6	/* PIO setup test */
#define CMD_READ_CONFIG_PIO	0xF0	/* Read config - PIO */
#define CMD_PIO_SEND_CP		0xF2	/* Send command packet - PIO */
#define CMD_RESET		0xF9	/* Reset controller */
#define CMD_IMMEDIATE		0xFA	/* Immediate command */
#define CMD_READ_CONFIG_DMA	0xFD	/* Read config - DMA */
#define CMD_DMA_SEND_CP		0xFF	/* Send command packet - DMA */

/* Backwards compatibility aliases */
#define EATA_CMD_PIO_DMA_SEND_CP	CMD_READ_CONFIG_PIO
#define EATA_CMD_SEND_CP		CMD_DMA_SEND_CP
#define EATA_CMD_RESET			CMD_RESET
#define EATA_CMD_IMMEDIATE		CMD_IMMEDIATE
#define EATA_CMD_READ_CONFIG		CMD_READ_CONFIG_DMA

/*
 * Status register bits
 */
#define EATA_STAT_BUSY		0x80
#define EATA_STAT_IRQ		0x02
#define EATA_STAT_ERROR		0x01
#define EATA_STAT_READY		0x00

/*
 * Auxiliary status register bits
 */
#define EATA_AUX_BUSY		0x01
#define EATA_AUX_IRQ_PENDING	0x02

/*
 * EATA Signature (Big Endian "EATA")
 */
#define EATA_SIGNATURE		0x45415441	/* "EATA" in big endian */
#define EATA_SIG_BE		0x45415441
#define EATA_CP_SIGNATURE	0x4350		/* "CP" */

/*
 * Scatter/gather descriptor
 */
struct eata_sg {
	unsigned int	addr;
	unsigned int	len;
};

#define EATA_SG_COUNT	17

/*
 * EATA Command Packet (CP)
 */
struct eata_cp {
	/* Hardware portion */
	unsigned char	cp_msg[4];		/* message bytes 0-3 */
	unsigned char	cp_scsi_addr;		/* SCSI target address */
	unsigned char	cp_flags1;		/* flags byte 1 */
	unsigned char	cp_flags2;		/* flags byte 2 */
	unsigned char	cp_flags3;		/* flags byte 3 */
	unsigned char	cp_cdb[12];		/* SCSI CDB */
	unsigned int	cp_dataLen;		/* data transfer length */
	unsigned int	cp_virt_cp;		/* virtual CP address */
	unsigned int	cp_dataAddr;		/* data buffer address */
	unsigned int	cp_sp_dma_addr;		/* status packet DMA addr */
	unsigned int	cp_sense_addr;		/* sense data address */
	unsigned char	cp_sense_len;		/* sense data length */
	unsigned char	cp_host_status;		/* host adapter status */
	unsigned char	cp_scsi_status;		/* SCSI status */
	unsigned char	cp_reserved;

	/* Software extension */
	struct eata_sg	sg_list[EATA_SG_COUNT];
	unsigned int	total_xfer_len;
	ns_time_t	startTime;
	port_t		timeoutPort;
	void		*cmdBuf;
	boolean_t	in_use;
	queue_chain_t	cpQ;
	union cdb	cdb;
	esense_reply_t	senseData;
};

/*
 * CP flags1 bits
 */
#define CP_INTERPRET		0x01	/* Interpret command */
#define CP_DATA_IN		0x02	/* Data in (target to host) */
#define CP_DATA_OUT		0x04	/* Data out (host to target) */
#define CP_SCATTER		0x08	/* Scatter/gather */
#define CP_DISCONNECT		0x10	/* Allow disconnect */
#define CP_IDENTIFY		0x20	/* Identify */
#define CP_PHYSICAL		0x40	/* Physical addressing */
#define CP_PRIORITY		0x80	/* Priority command */

/*
 * CP flags2 bits
 */
#define CP_NO_AUTO_SENSE	0x01	/* No auto request sense */
#define CP_REQSEN		0x40	/* Request sense command */

/*
 * Host status codes
 */
#define HS_OK			0x00	/* Command OK */
#define HS_SEL_TIMEOUT		0x11	/* Selection timeout */
#define HS_CMD_TIMEOUT		0x12	/* Command timeout */
#define HS_SCSI_HUNG		0x13	/* SCSI bus hung */
#define HS_RESET		0x14	/* SCSI bus reset */
#define HS_HBA_POWER_UP		0x15	/* HBA power up */
#define HS_HBA_PARITY		0x20	/* HBA parity error */

/*
 * EATA Status Packet (SP)
 * Returned by the controller after command completion
 */
struct eata_sp {
	unsigned char	hba_stat;	/* Host adapter status */
	unsigned char	scsi_stat;	/* SCSI status */
	unsigned char	reserved[2];
	unsigned int	residue_len;	/* Residual byte count */
	unsigned int	cp_addr;	/* CP address (physical) */
	unsigned char	sp_eoc;		/* End of Command flag */
	unsigned char	sp_sense_key;	/* Sense key */
	unsigned char	sp_filler[2];
};

/*
 * SP End of Command (EOC) flag
 */
#define SP_EOC			0x01	/* Command completed */

/*
 * EATA Configuration
 */
struct eata_config {
	unsigned char	signature[4];		/* EATA signature "EATA" */
	unsigned char	version;		/* EATA version */
	unsigned char	ocsEnabled;		/* OCS enabled */
	unsigned char	tarEnabled;		/* TAR enabled */
	unsigned char	trnEnabled;		/* TRNCTL enabled */
	unsigned int	moreSupported;		/* More supported */
	unsigned char	dmaChannel;		/* DMA channel */
	unsigned char	irqNumber;		/* IRQ number */
	unsigned char	scsi_id;		/* SCSI ID */
	unsigned char	scsi_id_flags;		/* SCSI ID flags */
	unsigned short	cpLength;		/* CP length */
	unsigned short	spLength;		/* SP length */
	unsigned short	queueSize;		/* Queue size */
	unsigned int	sgSize;			/* S/G size */
	unsigned char	firmware[3];		/* Firmware version */
	unsigned char	deviceType;		/* Device type */
	unsigned int	features;		/* Feature flags */
};

/*
 * Configuration data
 */
struct dpt_config {
	unsigned char	scsi_id;
	unsigned char	max_targets;
	unsigned char	max_luns;
	unsigned char	dma_channel;
	unsigned char	irq_level;
	boolean_t	wide_bus;
	boolean_t	ultra_enabled;
	unsigned int	io_base;
};

/*
 * EISA/ISA Device IDs
 */
#define DPT_EISA_ID1		0x12142834	/* DPT PM2012B/9X */
#define DPT_EISA_ID2		0x12142844	/* DPT PM2012B2/9X */
#define DPT_EISA_ID3		0x12142834	/* DPT PM2012A */

#endif /* _DPTSCSIDRIVERTYPES_H */
