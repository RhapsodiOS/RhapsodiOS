/* 	Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved. 
 *
 * AMD_ChipPrivate.h - private structs and #defines for AMD_Chip category.
 *
 * HISTORY
 * 1 Nov 94    Doug Mitchell at NeXT
 *      Created. 
 */
 
/*
 * opcode groups
 */
#define	SCSI_OPGROUP(opcode)	((opcode) & 0xe0)

#define	OPGROUP_0		0x00	/* six byte commands */
#define	OPGROUP_1		0x20	/* ten byte commands */
#define	OPGROUP_2		0x40	/* ten byte commands */
#define	OPGROUP_5		0xa0	/* twelve byte commands */
#define	OPGROUP_6		0xc0	/* six byte, vendor unique commands */
#define	OPGROUP_7		0xe0	/* ten byte, vendor unique commands */

/*
 * scsi bus phases
 */
#define	PHASE_DATAOUT		0x0
#define	PHASE_DATAIN		0x1
#define	PHASE_COMMAND		0x2
#define	PHASE_STATUS		0x3
#define	PHASE_MSGOUT		0x6
#define	PHASE_MSGIN		0x7

/*
 * message codes
 */
#define	MSG_CMDCMPLT		0x00	/* to host: command complete */
#define MSG_EXTENDED		0x01	/* both ways: extended message */
#define	MSG_SAVEPTRS		0x02	/* to host: save data pointers */
#define	MSG_RESTOREPTRS		0x03	/* to host: restore pointers */
#define	MSG_DISCONNECT		0x04	/* to host: disconnect */
#define	MSG_IDETERR		0x05	/* to disk: initiator detected error */
#define	MSG_ABORT		0x06	/* to disk: abort op, go to bus free */
#define	MSG_MSGREJECT		0x07	/* both ways: last msg unimplemented */
#define	MSG_NOP			0x08	/* to disk: no-op message */
#define	MSG_MSGPARERR		0x09	/* to disk: parity error last 
					   message */
#define	MSG_LNKCMDCMPLT		0x0a	/* to host: linked command complete */
#define	MSG_LNKCMDCMPLTFLAG	0x0b	/* to host: flagged linked cmd cmplt */
#define	MSG_DEVICERESET		0x0c	/* to disk: reset and go to bus free */
#define MSG_SIMPLE_QUEUE_TAG	0x20	/* both ways: simple queue tag */
#define MSG_HEAD_QUEUE_TAG	0x21	/* to disk: head of queue tag */
#define MSG_ORDERED_QUEUE_TAG	0x22	/* to disk: ordered queue tag */
#define	MSG_IDENTIFYMASK	0x80	/* both ways: thread identification */
#define	MSG_ID_DISCONN		0x40	/*	can disconnect/reconnect */
#define	MSG_ID_LUNMASK		0x07	/*	target LUN */

/*
 * Extended message codes
 */
#define MSG_SDTR		0x01	/* sync data transfer request */
#define MSG_SDTR_LENGTH		5	/* total SDTR message length */

/*
 * Delay, in ms, after SCSI reset.
 */
#define AMD_SCSI_RESET_DELAY	10000

/* 
 * Private methods, used only by AMD_Chip module.
 */

@interface AMD_SCSI(ChipPrivate)

/*
 * Determine what kind of SCSI interrupt is pending, if any.
 */

typedef enum { 
	SINT_NONE, 			/* no interrupt */
	SINT_DEVICE,			/* 53C974 */
	SINT_DMA,			/* DMA (not currently used) */
	SINT_OTHER			/* ?? */
} sintPending_t;

- (sintPending_t)scsiInterruptPending;


/*
 * Methods invoked upon interrupt. One per legal scState.
 */
- (void)fsmDisconnected;
- (void)fsmSelecting;
- (void)fsmInitiator;
- (void)fsmCompleting;
- (void)fsmDMAing;
- (void)fsmAcceptingMsg;
- (void)fsmSendingMsg;
- (void)fsmSelecting;
- (void)fsmGettingMsg;
- (void)fsmSelecting;
- (void)fsmSendingCmd;

/*
 * This is is called after an interrupt leaves us as SCS_INITIATOR.
 */
- (void)fsmPhaseChange;

- (void)messageOut 	: (unsigned char)msg;

/*
 * Load syncPeriod, syncOffset for activeCmd per perTarget values.
 */
- (void)targetContext 	: (unsigned)target;

/*
 * Parse and validate 5-byte SDTR message. If valid, save in perTarget 
 * and in hardware. Returns YES if valid, else NO.
 * 
 * Specified message buffer could be from either currMsgIn[] or 
 * currMsgOut[].
 */
- (BOOL)parseSDTR    		: (unsigned char *)sdtrMessage;

/*
 * Cons up an SDTR message appropriate for both our hardware and a possible
 * target-generated SDTR message. If inboundMsg is NULL, we just use
 * the parameters we want.
 */
- (void)createSDTR		: (unsigned char *)outboundMsg	// required
		     inboundMsg : (unsigned char *)inboundMsg;
	
/*
 * Disable specified mode for activeCmd's target.
 */
 
typedef enum {
	AM_CmdQueue,
	AM_Sync,
} AMD_Mode;	

- (void)disableMode : (AMD_Mode)mode;

@end
