/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * AttoScsiInterface.h - Atto SCSI Controller Interface Structures
 */

#define MIN_SCSI_TAG    0x80
#define SRB_SIZE        0x2a4  /* Size of each SRB structure (676 bytes) */

/* Scatter-Gather List Constants */
#define MAX_SG_ENTRIES  65     /* Maximum SG entries (0x41) */
#define SG_TERMINATOR_OK    0x00000890  /* Normal SG list terminator */
#define SG_TERMINATOR_ERR   0x00000898  /* Error/overflow SG list terminator */
#define SG_ERROR_LENGTH     0x0f000000  /* Length for error terminator (15 in big-endian) */

/* SCSI Message Codes */
#define MSG_IDENTIFY            0x80    /* IDENTIFY message (+ disconnect bit) */
#define MSG_IDENTIFY_DISCONNECT 0xC0    /* IDENTIFY with disconnect privilege */
#define MSG_SIMPLE_QUEUE_TAG    0x20    /* SIMPLE QUEUE TAG message */
#define MSG_EXTENDED            0x01    /* EXTENDED MESSAGE */
#define MSG_WDTR                0x03    /* Wide Data Transfer Request code */
#define MSG_SDTR                0x01    /* Synchronous Data Transfer Request code */

/* Target Capability Flags (in targets[].flags and srb->targetCapabilities) */
#define kTargetCapTaggedQueuing     0x01    /* Target supports tagged queuing */
#define kTargetCapTagQueueEnabled   0x02    /* Tagged queuing enabled for target */
#define kTargetCapSDTRSupport       0x0C    /* SDTR support mask (bits 2-3) */
#define kTargetCapSDTRInitiator     0x10    /* We initiate SDTR */
#define kTargetCapWDTRSupport       0xE0    /* WDTR support mask (bits 5-7) */
#define kTargetCapWDTRNeeded        0x60    /* WDTR negotiation needed value */

/* Negotiation State Flags (in srb->targetCapabilities) */
#define kNegotiationWDTRSent        0x40    /* WDTR message sent */
#define kNegotiationSDTRSent        0x80    /* SDTR message sent */

/*
 * SRB Pool Page structure
 *
 * Each allocated page of memory for the SRB pool has this header,
 * followed by an array of SRB structures.
 */
typedef struct SRBPoolPage
{
    struct SRBPoolPage  *nextPage;      /* 0x00 - Next page in pool */
    struct SRBPoolPage  *prevPage;      /* 0x04 - Previous page in pool */
    u_int32_t           physicalAddr;   /* 0x08 - Physical address of page */
    queue_head_t        freeSRBs;       /* 0x0c - Head of free SRB list */
                                        /* 0x10 - Tail of free SRB list */
    u_int32_t           inUseCount;     /* 0x14 - Number of SRBs in use from this page */
    u_int8_t            padding[0xc];   /* 0x18-0x1f - Padding to SRB start */
    /* SRB structures start at offset 0x20 */
} SRBPoolPage;

/*
 * Abort Bdr Mailbox
 *
 * The mailbox is used to send an Abort or Bus Device Reset to a device.
 * This mailbox is 4 bytes long, and all the necessary information is
 * contained in this mailbox (no Nexus data associated).
 */
typedef struct IOAbortBdrMailBox
{
    u_int8_t    identify;    /* Identify msg (0xC0 + LUN)                      A0 */
    u_int8_t    tag;         /* Tag Message or Zero                            A1 */
    u_int8_t    scsi_id;     /* SCSI id of the target                          A2 */
    u_int8_t    message;     /* Abort(0x06) or Bdr(0x0C) or AbortTag(0x0D)     A3 */
} IOAbortBdrMailBox;

/* Adapter interface structure - script communication area */
typedef struct AdapterInterface
{
    Nexus       **nexusPtrsVirt;       /* Offset 0x00 - Virtual nexus pointer table (256 entries) */
    Nexus       **nexusPtrsPhys;       /* Offset 0x04 - Physical nexus pointer table (256 entries) */
    /* Nexus pointer table storage starts at offset 0x08 (256 * 4 = 1024 bytes = 0x400) */
    u_int8_t    padding_nexus[0x400];  /* Offset 0x08-0x407 - Storage for physical nexus pointers */
    u_int32_t   schedMailBox[256];     /* Offset 0x408 - Schedule mailbox array (256 * 4 = 0x400) */
    u_int8_t    targetClocks[64];      /* Offset 0x808 - Target clock registers */
    u_int8_t    padding_clocks[4];     /* Offset 0x848-0x84b - Padding */
    u_int32_t   saveDataLength;        /* Offset 0x84c - Save data pointer: length */
    u_int32_t   saveDataAddr;          /* Offset 0x850 - Save data pointer: address */
    u_int32_t   saveDataCmd;           /* Offset 0x854 - Save data pointer: command */
    u_int32_t   saveDataJump;          /* Offset 0x858 - Save data pointer: jump address */
} AdapterInterface;

/* SRB Nexus structure - embedded in SRB at offset 0x48 */
typedef struct Nexus
{
    u_int8_t    targetParms[4];        /* 0x00-0x03 */
    u_int32_t   ppSGList;              /* 0x04-0x07 */
    u_int32_t   msgLength;             /* 0x08-0x0b */
    u_int32_t   msgData;               /* 0x0c-0x0f */
    u_int32_t   cdbLength;             /* 0x10-0x13 */
    u_int32_t   cdbData;               /* 0x14-0x17 */
    u_int32_t   currentDataPtr;        /* 0x18-0x1b */
    u_int32_t   savedDataPtr;          /* 0x1c-0x1f */
    u_int8_t    tag;                   /* 0x20 */
    u_int8_t    dataXferCalled;        /* 0x21 */
    u_int8_t    wideResidCount;        /* 0x22 */
    u_int8_t    reserved;              /* 0x23 */
} Nexus;

/* Scatter-Gather List Entry */
typedef struct SGEntry
{
    u_int32_t   physAddr;              /* Physical address */
    u_int32_t   length;                /* Transfer length */
} SGEntry;

/* SRB structure */
typedef struct SRB
{
    struct SRB  *nextSRB;              /* 0x00 - Queue link: next */
    struct SRB  *prevSRB;              /* 0x04 - Queue link: prev */
    u_int32_t   srbPhysAddr;           /* 0x08 - Physical address of this SRB */
    void        *srbCmdLock;           /* 0x0c - NXConditionLock */
    u_int32_t   srbTimeoutStart;       /* 0x10 - Initial timeout value */
    u_int32_t   srbTimeout;            /* 0x14 - Current timeout countdown */
    u_int8_t    srbCmd;                /* 0x18 - SRB command (offset -0x30 from nexus) */
    u_int8_t    srbState;              /* 0x19 - SRB state/phase */
    u_int8_t    targetCapabilities;    /* 0x1a - Target negotiation capabilities */
    u_int8_t    srbRetryCount;         /* 0x1b - Retry count / state */
    u_int8_t    scsiStatus;            /* 0x1c - SCSI status byte */
    u_int8_t    padding1d;             /* 0x1d */
    u_int8_t    transferPeriod;        /* 0x1e - Negotiated transfer period */
    u_int8_t    target;                /* 0x1f - SCSI target ID */
    u_int8_t    lun;                   /* 0x20 - SCSI LUN */
    u_int8_t    tag;                   /* 0x21 - SCSI tag (cached from nexus) */
    u_int8_t    srbSCSIResult;         /* 0x22 - SCSI result code (offset -0x26 from nexus) */
    u_int8_t    transferOffset;        /* 0x23 - Negotiated transfer offset */
    u_int32_t   srbFlags;              /* 0x24 - SRB flags/state (ORed with SG lengths) */
    void        *srbVMTask;            /* 0x28 - VM task for this request */
    void        *ioMemoryDescriptor;   /* 0x2c - IOMemoryDescriptor or data buffer pointer */
    u_int32_t   xferDoneVirt;          /* 0x30 - Current virtual transfer position */
    u_int32_t   xferDonePhys;          /* 0x34 - Saved transfer position */
    u_int32_t   xferEndOffset;         /* 0x38 - End offset for transfer */
    u_int32_t   xferOffset;            /* 0x3c - Current transfer offset */
    void        *senseDataBuffer;      /* 0x40 - Pointer to autosense buffer */
    void        *requestDataBuffer;    /* 0x44 - Pointer to request data buffer */
    u_int8_t    senseDataLength;       /* 0x47 - Autosense buffer length */
    Nexus       nexus;                 /* 0x48-0x6b (0x24 bytes) */
    u_int8_t    scsiCDB[16];           /* 0x6c-0x7b - SCSI Command Descriptor Block */
    u_int8_t    padding5[0xc];         /* 0x7c-0x87 */
    u_int32_t   sgCount;               /* 0x88 - Scatter-gather entry count */
    SGEntry     sgList[1];             /* 0x8c - Scatter-gather list (variable length) */
} SRB;

/* SRB command states */
enum srbCmdLock
{
    ksrbCmdPending = 1,
    ksrbCmdComplete
};

/* SRB commands */
enum srbQCmd
{
    ksrbCmdExecuteReq       = 0x01,
    ksrbCmdResetSCSIBus     = 0x02,
    ksrbCmdAbortReq         = 0x03,
    ksrbCmdBusDevReset      = 0x04,
    ksrbCmdProcessTimeout   = 0x05,
};

/* SCSI result codes */
#define SR_IOST_IOTO   5  /* I/O timeout */
#define SR_IOST_RESET  20 /* SCSI bus reset */
