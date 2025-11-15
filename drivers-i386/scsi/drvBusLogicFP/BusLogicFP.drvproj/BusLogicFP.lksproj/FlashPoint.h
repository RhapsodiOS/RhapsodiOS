/*
 * FlashPoint.h -- FlashPoint SCCB Manager Interface
 *
 * Copyright 1995-1996 by Mylex Corporation.  All Rights Reserved
 * Modified for Rhapsody/OpenStep by Apple Computer, Inc.
 */

#ifndef _FLASHPOINT_H
#define _FLASHPOINT_H

#import <sys/types.h>

/* Basic type definitions for compatibility */
#ifndef u32
typedef unsigned int u32;
#endif
#ifndef u16
typedef unsigned short u16;
#endif
#ifndef u8
typedef unsigned char u8;
#endif

#define MAX_CARDS	8
#define CRCMASK		0xA001
#define FAILURE		0xFFFFFFFFL

/* Forward declaration */
struct sccb;
typedef void (*CALL_BK_FN)(struct sccb *);

/* SCCB Manager Info Structure */
struct sccb_mgr_info {
	u32 si_baseaddr;
	unsigned char si_present;
	unsigned char si_intvect;
	unsigned char si_id;
	unsigned char si_lun;
	u16 si_fw_revision;
	u16 si_per_targ_init_sync;
	u16 si_per_targ_fast_nego;
	u16 si_per_targ_ultra_nego;
	u16 si_per_targ_no_disc;
	u16 si_per_targ_wide_nego;
	u16 si_flags;
	unsigned char si_card_family;
	unsigned char si_bustype;
	unsigned char si_card_model[3];
	unsigned char si_relative_cardnum;
	unsigned char si_reserved[4];
	u32 si_OS_reserved;
	unsigned char si_XlatInfo[4];
	u32 si_reserved2[5];
	u32 si_secondary_range;
};

/* Configuration flags */
#define SCSI_PARITY_ENA		0x0001
#define LOW_BYTE_TERM		0x0010
#define HIGH_BYTE_TERM		0x0020
#define BUSTYPE_PCI			0x3
#define SUPPORT_16TAR_32LUN	0x0002
#define SOFT_RESET			0x0004
#define EXTENDED_TRANSLATION 0x0008
#define POST_ALL_UNDERRRUNS	0x0040
#define FLAG_SCAM_ENABLED	0x0080
#define FLAG_SCAM_LEVEL2	0x0100

#define HARPOON_FAMILY		0x02

/* SCCB Structure */
struct sccb {
	unsigned char OperationCode;
	unsigned char ControlByte;
	unsigned char CdbLength;
	unsigned char RequestSenseLength;
	u32 DataLength;
	void *DataPointer;
	unsigned char CcbRes[2];
	unsigned char HostStatus;
	unsigned char TargetStatus;
	unsigned char TargID;
	unsigned char Lun;
	unsigned char Cdb[12];
	unsigned char CcbRes1;
	unsigned char Reserved1;
	u32 Reserved2;
	u32 SensePointer;

	CALL_BK_FN SccbCallback;
	u32 SccbIOPort;
	unsigned char SccbStatus;
	unsigned char SCCBRes2;
	u16 SccbOSFlags;

	u32 Sccb_XferCnt;
	u32 Sccb_ATC;
	u32 SccbVirtDataPtr;
	u32 Sccb_res1;
	u32 Sccb_MGRFlags;
	u32 Sccb_sgseg;
	unsigned char Sccb_scsimsg;
	unsigned char Sccb_tag;
	unsigned char Sccb_scsistat;
	unsigned char Sccb_idmsg;
	struct sccb *Sccb_forwardlink;
	struct sccb *Sccb_backlink;
	u32 Sccb_savedATC;
	unsigned char Save_Cdb[6];
	unsigned char Save_CdbLen;
	unsigned char Sccb_XferState;
	u32 Sccb_SGoffset;
};

/* Operation codes */
#define SCATTER_GATHER_COMMAND		0x02
#define RESIDUAL_COMMAND			0x03
#define RESIDUAL_SG_COMMAND			0x04
#define RESET_COMMAND				0x81

/* Control byte flags */
#define F_USE_CMD_Q					0x20
#define TAG_TYPE_MASK				0xC0
#define SCCB_DATA_XFER_OUT			0x10
#define SCCB_DATA_XFER_IN			0x08
#define NO_AUTO_REQUEST_SENSE		0x01

/* SCCB status codes */
#define SCCB_COMPLETE				0x00
#define SCCB_DATA_UNDER_RUN			0x0C
#define SCCB_SELECTION_TIMEOUT		0x11
#define SCCB_DATA_OVER_RUN			0x12
#define SCCB_PHASE_SEQUENCE_FAIL	0x14
#define SCCB_GROSS_FW_ERR			0x27
#define SCCB_BM_ERR					0x30
#define SCCB_PARITY_ERR				0x34

#define SCCB_IN_PROCESS				0x00
#define SCCB_SUCCESS				0x01
#define SCCB_ABORT					0x02
#define SCCB_ERROR					0x04

/* Limits */
#define QUEUE_DEPTH					255
#define MAX_SCSI_TAR				16
#define MAX_LUN						32
#define LUN_MASK					0x1f

/* FlashPoint SCCB Manager API */
extern void *FlashPoint_ProbeHostAdapter(struct sccb_mgr_info *pCardInfo);
extern unsigned long FlashPoint_HardwareResetHostAdapter(void *pCurrCard);
extern void FlashPoint_StartCCB(void *pCurrCard, struct sccb *p_Sccb);
extern int FlashPoint_AbortCCB(void *pCurrCard, struct sccb *p_Sccb);
extern unsigned char FlashPoint_InterruptPending(void *pCurrCard);
extern int FlashPoint_HandleInterrupt(void *pCurrCard);
extern void FlashPoint_ReleaseHostAdapter(void *pCurrCard);

#endif /* _FLASHPOINT_H */
