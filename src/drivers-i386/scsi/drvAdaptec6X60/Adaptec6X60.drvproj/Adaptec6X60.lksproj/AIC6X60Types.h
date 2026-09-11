/*
 * Copyright (c) 1992-1998 NeXT Software, Inc.
 *
 * Adaptec AIC-6X60 SCSI controller definitions.
 *
 * HISTORY
 *
 * 28 Mar 1998 Adapted from AHA-1542 driver
 *	Created.
 */

#import <driverkit/i386/driverTypes.h>
#import <kernserv/ns_timer.h>
#import <kernserv/queue.h>

/*
 * AIC-6260/6360 register offsets relative to hacb.baseAddress.
 *
 * Every offset appears as an immediate in the IDA listing of a HIM /
 * sequencer function (add dx, N, inc dx, or in/out at the loaded base).
 * Bit names are from the AIC-6260/6360 programming guide.
 */

#define AIC_SCSISEQ		0x00	/* HIM6X60FindAdapter / HIM6X60Initialize in/out at dx */
#define AIC_SXFRCTL0		0x01	/* inc dx; FindAdapter in, Initialize out 12h/20h */
#define AIC_SXFRCTL1		0x02	/* add dx, 2; scsiBusFree / Initialize */
#define AIC_SCSISIG		0x03	/* add dx, 3; Initialize / dataInPIO / dataOutPIO */
#define AIC_SCSIRATE		0x04	/* add dx, 4; scsiBusFree / resetSDTR */
#define AIC_SCSIDAT		0x06	/* add dx, 6; scsiBusFree / targetREQuest */
#define AIC_SCSIBUS		0x07	/* add dx, 7; interpretMessageIn */
#define AIC_STCNT0		0x08	/* add dx, 8; HIM6X60DmaProgrammed */
#define AIC_STCNT1		0x09	/* add dx, 9; HIM6X60Initialize */
#define AIC_SSTAT0		0x0b	/* add dx, 0Bh; _isr in -> hacb.sStat0 */
#define AIC_CLRSINT0		0x0b	/* write; scsiBusFree / reselection */
#define AIC_SSTAT1		0x0c	/* add dx, 0Ch; _isr in -> hacb.sStat1 */
#define AIC_CLRSINT1		0x0c	/* write; _isr / scsiBusReset / selection */
#define AIC_SSTAT2		0x0d	/* add dx, 0Dh; FindAdapter / dataOutPIO */
#define AIC_SSTAT3		0x0e	/* add dx, 0Eh; FindAdapter / HIM6X60DmaProgrammed */
#define AIC_SSTAT4		0x0f	/* add dx, 0Fh; _isr in, then out 7 */
#define AIC_CLRSERR		0x0f
#define AIC_SIMODE0		0x10	/* add dx, 10h; Initialize / _isr */
#define AIC_SIMODE1		0x11	/* add dx, 11h; Initialize / selection / dataInPIO */
#define AIC_DMACNTRL0		0x12	/* add dx, 12h; ISR/IRQ in+out, dataInPIO */
#define AIC_DMACNTRL1		0x13	/* add dx, 13h; GetConfiguration / Initialize / ResetBus */
#define AIC_DMASTAT		0x14	/* add dx, 14h; IRQ/ISR test 20h */
#define AIC_FIFOSTAT		0x15	/* add dx, 15h; dataInPIO / HIM6X60DmaProgrammed */
#define AIC_DMADATA		0x16	/* add edx, 16h; dataOutPIO -> repoutsb / repoutsw */
#define AIC_DMADATA32		0x18	/* add edx, 18h; dataOutPIO -> repoutsd */
#define AIC_PORTA		0x1a	/* add dx, 1Ah; HIM6X60GetConfiguration in */
#define AIC_PORTB		0x1b	/* add dx, 1Bh; HIM6X60GetConfiguration in */
#define AIC_REV			0x1c	/* add dx, 1Ch; Initialize / GetConfiguration -> revision */
#define AIC_STACK		0x1d	/* add dx, 1Dh; GetConfiguration -> signature */

/*
 * SCSISEQ bits.
 */
#define AIC_SCSIRSTO		0x01
#define AIC_ENAUTOATNP		0x02
#define AIC_ENAUTOATNI		0x04
#define AIC_ENAUTOATNO		0x08
#define AIC_ENRESELI		0x10
#define AIC_ENSELI		0x20
#define AIC_ENSELO		0x40
#define AIC_TEMODEO		0x80

/*
 * SXFRCTL0 bits.
 */
#define AIC_CLRCHN		0x02
#define AIC_SPIOEN		0x08
#define AIC_CLRSTCNT		0x10

/*
 * SXFRCTL1 bits.
 */
#define AIC_ENSTIMER		0x04
#define AIC_ENSPCHK		0x20
#define AIC_BITBUCKET		0x80

/*
 * SSTAT0 / CLRSINT0 / SIMODE0 bits.
 */
#define AIC_DMADONE		0x01
#define AIC_SPIORDY		0x02
#define AIC_SDONE		0x04
#define AIC_SWRAP		0x08
#define AIC_SELINGO		0x10
#define AIC_SELDI		0x20
#define AIC_SELDO		0x40
#define AIC_TARGET		0x80

/*
 * SSTAT1 / CLRSINT1 / SIMODE1 bits.
 */
#define AIC_REQINIT		0x01
#define AIC_PHASECHG		0x02
#define AIC_SCSIPERR		0x04
#define AIC_BUSFREE		0x08
#define AIC_PHASEMIS		0x10
#define AIC_SCSIRSTI		0x20
#define AIC_ATNTARG		0x40
#define AIC_SELTO		0x80

/*
 * DMACNTRL0 bits.
 */
#define AIC_SWINT		0x01
#define AIC_RSTFIFO		0x02
#define AIC_INTEN		0x04
#define AIC_ENDMA		0x80

/*
 * DMASTAT bits. IRQ/ISR: in at base+0x14, test 0x20.
 */
#define AIC_DFIFOEMP		0x08
#define AIC_DFIFOFULL		0x10
#define AIC_INTSTAT		0x20
#define AIC_WORDRDY		0x40
#define AIC_ATDONE		0x80

#define AIC_HACB_SIZE		0x390	/* initFromDeviceDescription: mov [esi+244h], 390h */
#define AIC_SCB_SIZE		0x54	/* interruptOccurred pool stride */
#define AIC_SCB_COUNT		32	/* numFreeScbs = 0x20 */

struct _SCB;

/*
 * Host adapter control block. sizeof 1488 / 0x390.
 * Unknown ObjC (?) unions are opaque so IDA-confirmed displacements land.
 */
struct _HACB {
	unsigned int		length;			/* +0x00 */
	unsigned short		baseAddress;		/* +0x04; mov dx, [ebx+4] */
	unsigned char		_opaque_baseAddress[2];
	unsigned char		scsiPhase;		/* +0x08 */
	unsigned char		ownID;			/* +0x09 */
	unsigned char		busID;			/* +0x0a */
	unsigned char		lun;			/* +0x0b */
	unsigned char		ac;			/* +0x0c; IDA byte */
	unsigned char		cs;			/* +0x0d; IRQ/ISR bit 7 */
	unsigned char		_opaque_ac_cs[2];	/* +0x0e */
	unsigned int		disableINT;		/* +0x10 */
	struct _SCB		*deferredScb;		/* +0x14 */
	struct _SCB		*eligibleScb;		/* +0x18; selection lea [esi+18h] */
	struct _SCB		*queueFreezeScb;	/* +0x1c */
	struct _SCB		*resetScb;		/* +0x20 */
	unsigned char		nx[0x2a];		/* +0x24..+0x4d; [0] is SCB* in _isr */
	unsigned char		targetStatus;		/* +0x4e */
	unsigned char		reservedForAlignment1;	/* +0x4f */
	unsigned char		syncCycles[8];		/* +0x50 */
	unsigned char		syncOffset[8];		/* +0x58 */
	unsigned int		cQueuedScb;		/* +0x60 */
	unsigned int		cActiveScb;		/* +0x64 */
	unsigned char		negotiateSDTR;		/* +0x68 */
	struct {
		unsigned char	extMsgCode;		/* +0x69 */
		unsigned char	extMsgLength;		/* +0x6a */
		unsigned char	extMsgType;		/* +0x6b */
		unsigned char	transferPeriod;		/* +0x6c */
		unsigned char	reqAckOffset;		/* +0x6d */
	} sdtrMsg;
	unsigned char		requestSenseCdb[6];	/* +0x6e; [0] = 3 */
	unsigned char		sStat0;			/* +0x74 */
	unsigned char		maskedSStat0;		/* +0x75 */
	unsigned char		sStat1;			/* +0x76 */
	unsigned char		maskedSStat1;		/* +0x77 */
	unsigned short		selectTimeLimit;	/* +0x78 */
	unsigned char		sXfrCtl1Image;		/* +0x7a */
	unsigned char		irqConnected;		/* +0x7b */
	unsigned char		clockPeriod;		/* +0x7c */
	unsigned char		IRQ;			/* +0x7d */
	unsigned char		dmaChannel;		/* +0x7e */
	unsigned char		revision;		/* +0x7f */
	unsigned char		dmaBusOnTime;		/* +0x80 */
	unsigned char		dmaBusOffTime;		/* +0x81 */
	unsigned char		_opaque_signature[2];	/* +0x82; align signature */
	unsigned int		signature;		/* +0x84 */
	unsigned int		scsiCount;		/* +0x88 */
	struct {
		unsigned char	busy;			/* GetLUCB: 0x8c + index*12 */
		unsigned char	_opaque[3];
		struct _SCB	*queuedScb;
		struct _SCB	*activeScb;
	} lucb[64];					/* +0x8c, stride 12 */
	void			*controllerId;		/* +0x38c */
};

/*
 * HIM SCB. sizeof 84 / 0x54. Field order from __instance_vars him_scb encoding.
 */
struct _SCB {
	struct _SCB		*chain;			/* +0x00 */
	unsigned int		length;			/* +0x04 */
	void			*osRequestBlock;	/* +0x08 */
	struct _SCB		*linkedScb;		/* +0x0c */
	unsigned char		function;		/* +0x10 */
	unsigned char		scbStatus;		/* +0x11 */
	unsigned short		flags;			/* +0x12 */
	unsigned char		targetStatus;		/* +0x14 */
	unsigned char		scsiBus;		/* +0x15 */
	unsigned char		targetID;		/* +0x16 */
	unsigned char		lun;			/* +0x17 */
	unsigned char		queueTag;		/* +0x18 */
	unsigned char		tagType;		/* +0x19 */
	unsigned char		cdbLength;		/* +0x1a */
	unsigned char		senseDataLength;	/* +0x1b */
	unsigned char		*cdb;			/* +0x1c */
	unsigned char		*senseData;		/* +0x20 */
	unsigned char		*dataPointer;		/* +0x24 */
	unsigned int		dataLength;		/* +0x28 */
	unsigned int		dataOffset;		/* +0x2c */
	unsigned int		segmentAddress;		/* +0x30 */
	unsigned int		segmentLength;		/* +0x34 */
	unsigned int		transferLength;		/* +0x38 */
	unsigned int		transferResidual;	/* +0x3c */
	unsigned int		provisionalTransfer;	/* +0x40 */
	char			in_use;			/* +0x44 */
	char			timedOut;		/* +0x45 */
	char			completed;		/* +0x46 */
	unsigned char		_pad;			/* +0x47 */
	unsigned int		timeout_Port;		/* +0x48 */
	ns_time_t		startTime;		/* +0x4c */
};
