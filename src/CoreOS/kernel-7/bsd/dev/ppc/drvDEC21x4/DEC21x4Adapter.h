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
 * DEC21x4Adapter.h
 *
 * Adapter state shared by the DEC21x4 driver methods and the DC21X4
 * media, SROM and MII helpers.  Plain C: the helper files include this
 * header without DEC21x4.h.
 *
 * HISTORY
 *
 * Reconstructed for RhapsodiOS from the DEC21x4 code linked into the
 * Mac OS X Server 1.2v3 (kernel 5.6) ppc mach_kernel.  Every field offset
 * below was taken from the loads and stores in that binary.
 */

#ifndef _DEC21X4ADAPTER_H
#define _DEC21X4ADAPTER_H

#import <sys/types.h>
#import <bsd/sys/systm.h>		/* bcopy, bzero */
#import <objc/objc.h>			/* BOOL */
#import <machdep/ppc/proc_reg.h>	/* lwbrx, stwbrx, eieio */

/*
 * PCI vendor/device words in Adapter->DeviceId.  The driver gives the
 * 21143 a private id; on the bus it shares 0x0019 with the 21142.
 */
#define DC21040_CFID		0x00021011
#define DC21041_CFID		0x00141011
#define DC21140_CFID		0x00091011
#define DC21142_CFID		0x00191011
#define DC21143_CFID		0x00ff1011

/*
 * CSRs.  Adapter->CsrOffset[n] holds the byte offset of CSRn; the driver
 * methods also reach the registers at fixed offsets from ioBase.
 */
#define DC21X4_CSR_COUNT	16
#define DC_CSR(n)		((n) * 8)

#define CSR0	0
#define CSR1	1
#define CSR2	2
#define CSR3	3
#define CSR4	4
#define CSR5	5
#define CSR6	6
#define CSR7	7
#define CSR8	8
#define CSR9	9
#define CSR10	10
#define CSR11	11
#define CSR12	12
#define CSR13	13
#define CSR14	14
#define CSR15	15

/* CSR0, bus mode */
#define DC_CSR0_SWR		0x00000001	/* software reset */
#define DC_CSR0_PBL_SHIFT	8		/* programmable burst length */
#define DC_CSR0_PBL_MASK	0x00003f00
#define DC_CSR0_CAL_8		0x00004000	/* cache alignment 8 longwords */
#define DC_CSR0_RME		0x00200000	/* read multiple */
#define DC_CSR0_RLE		0x00800000	/* read line */
#define DC_CSR0_WIE		0x01000000	/* write and invalidate */

/* CSR5 status / CSR7 interrupt enable */
#define DC_INT_TI		0x00000001	/* transmit complete */
#define DC_INT_TPS		0x00000002	/* transmit stopped */
#define DC_INT_TU		0x00000004	/* transmit buffer unavailable */
#define DC_INT_TJT		0x00000008	/* transmit jabber timeout */
#define DC_INT_LNP		0x00000010	/* link pass / autonegotiation done */
#define DC_INT_UNF		0x00000020	/* transmit underflow */
#define DC_INT_RI		0x00000040	/* receive complete */
#define DC_INT_RU		0x00000080	/* receive buffer unavailable */
#define DC_INT_RPS		0x00000100	/* receive stopped */
#define DC_INT_RWT		0x00000200	/* receive watchdog timeout */
#define DC_INT_ETI		0x00000400	/* early transmit */
#define DC_INT_GTE		0x00000800	/* general purpose timer expired */
#define DC_INT_LNF		0x00001000	/* link fail */
#define DC_INT_SE		0x00002000	/* system (bus) error */
#define DC_INT_ERI		0x00004000	/* early receive */
#define DC_INT_AIS		0x00008000	/* abnormal summary */
#define DC_INT_NIS		0x00010000	/* normal summary */
#define DC_INT_GPI		0x04000000	/* general purpose port (21142/3) */
#define DC_INT_LC		0x08000000	/* link changed (21143) */
#define DC_INT_ALL		0x0c01ffff
#define DC_INT_LINK		(DC_INT_GPI | DC_INT_LC | DC_INT_LNF | DC_INT_LNP)

/* CSR6, operation mode */
#define DC_CSR6_SR		0x00000002	/* start receive */
#define DC_CSR6_PR		0x00000040	/* promiscuous */
#define DC_CSR6_PM		0x00000080	/* pass all multicast */
#define DC_CSR6_FD		0x00000200	/* full duplex */
#define DC_CSR6_ST		0x00002000	/* start transmit */
#define DC_CSR6_CAE		0x00020000	/* capture effect enable */
#define DC_CSR6_PS		0x00040000	/* port select: MII/SYM */
#define DC_CSR6_HBD		0x00080000	/* heartbeat disable */
#define DC_CSR6_SF		0x00200000	/* store and forward */
#define DC_CSR6_TTM		0x00400000	/* transmit threshold mode (10 Mb/s) */
#define DC_CSR6_PCS		0x00800000	/* PCS function */
#define DC_CSR6_SCR		0x01000000	/* scrambler mode */
#define DC_CSR6_MBO		0x02000000	/* must be one (21140A/21143) */
#define DC_CSR6_SC		0x80000000	/* special capture effect */
#define DC_CSR6_MEDIA_MASK	0x03ccc200	/* bits taken from a media block */

/* CSR12 on the 21041/21142/21143 (SIA status) */
#define DC_CSR12_LS100		0x00000002	/* 100 Mb/s link fail */
#define DC_CSR12_LS10		0x00000004	/* 10 Mb/s link fail */
#define DC_CSR12_ANS_MASK	0x00007000	/* autonegotiation state */
#define DC_CSR12_ANS_COMPLETE	0x00005000
#define DC_CSR12_LPN		0x00008000	/* link partner negotiable */

/*
 * Media codes (Adapter->MediaType low byte, SelectedMedium, SROM media
 * blocks).  Codes 9 and up name the same media on an MII PHY.
 */
#define DC21X4_MEDIA_10BASET		0
#define DC21X4_MEDIA_10BASE2		1
#define DC21X4_MEDIA_10BASE5		2
#define DC21X4_MEDIA_100BASETX		3
#define DC21X4_MEDIA_10BASET_FD		4
#define DC21X4_MEDIA_100BASETX_FD	5
#define DC21X4_MEDIA_100BASET4		6
#define DC21X4_MEDIA_100BASEFX		7
#define DC21X4_MEDIA_100BASEFX_FD	8
#define DC21X4_MEDIA_COUNT		9
#define DC21X4_MII_MEDIA_AUTOSENSE	9
#define DC21X4_MEDIA_STRING_COUNT	18

#define DC21X4_MEDIA_NONE		0xff	/* SwitchMedia: pick the next medium */
#define DC21X4_MEDIA_TP_NWAY		0x100	/* SwitchMedia: restart TP Nway */

/* MediaType / MiiMediaType flag bits above the media code */
#define DC21X4_MEDIA_NWAY		0x0100
#define DC21X4_MEDIA_FULL_DUPLEX	0x0200
#define DC21X4_MEDIA_NO_LINK_TEST	0x0400
#define DC21X4_MEDIA_AUTOSENSE		0x0800

/* DC21X4IndicateMediaStatus() states */
#define DC21X4_LINK_FAIL		0
#define DC21X4_LINK_PASS		1
#define DC21X4_MII_LINK_PASS		2

/* Adapter->TimerState */
#define DC21X4_TIMER_IDLE		0
#define DC21X4_TIMER_AUTOSENSE		1
#define DC21X4_TIMER_NWAY_LINK_FAIL	2
#define DC21X4_TIMER_NWAY_LINK_PASS	3
#define DC21X4_TIMER_NWAY_10_CHECK	4
#define DC21X4_TIMER_NWAY_100_CHECK	5
#define DC21X4_TIMER_TP_NWAY		6
#define DC21X4_TIMER_TP_NWAY_RETRY	7

#define DC21X4_MAX_GEP_SEQUENCE		5
#define DC21X4_MAX_PHY			1	/* PHY table entries */
#define DC21X4_MII_PHY_ALLOC_SIZE	128

/*
 * One SROM media block (SIA or GEP medium), indexed by media code.
 */
typedef struct {
    u_long	GeneralPurposeCtrl;		/* 0x00 */
    u_long	GeneralPurposeData;		/* 0x04 */
    u_long	Csr13;				/* 0x08 SIA connectivity */
    u_long	Csr14;				/* 0x0c SIA tx/rx */
    u_long	Csr15;				/* 0x10 SIA general (low half) */
    u_long	Mode;				/* 0x14 CSR6 bits for this medium */
    u_long	Polarity;			/* 0x18 sense bit active level */
    u_long	SenseMask;			/* 0x1c GEP link-sense bit, 0 if none */
} DC21X4_MEDIA_TABLE;				/* 0x20 */

/*
 * SROM MII PHY block (extended block types 1 and 3).
 */
typedef struct {
    u_char	Present;			/* 0x00 */
    u_char	reserved0[3];			/* 0x01 */
    int		GepSequenceLength;		/* 0x04 */
    int		ResetSequenceLength;		/* 0x08 */
    u_short	MediaCapabilities;		/* 0x0c */
    u_short	NwayAdvertisement;		/* 0x0e */
    u_short	FullDuplexBits;			/* 0x10 */
    u_short	TxThresholdBits;		/* 0x12 */
    u_short	GeneralPurposeCtrl;		/* 0x14 */
    u_short	GepSequence[DC21X4_MAX_GEP_SEQUENCE];	/* 0x16 */
    u_short	ResetSequence[DC21X4_MAX_GEP_SEQUENCE];	/* 0x20 */
    u_short	reserved1;			/* 0x2a */
    u_long	Interrupt;			/* 0x2c CSR15 PHY interrupt bits */
} DC21X4_PHY_MEDIA;				/* 0x30 */

/*
 * Per-adapter state, IOMalloc(sizeof(DC21X4_ADAPTER)) in
 * -initFromDeviceDescription:.  Left untagged so the Adapter ivar keeps
 * the binary's ^{?} type encoding.
 */
struct _MII_PHY_INFO;

typedef struct {
    u_int	PortOffset;			/* 0x000 mapped CSR base */
    u_char	NwayEnabled;			/* 0x004 */
    u_char	reserved0[3];			/* 0x005 */
    u_long	RevisionNumber;			/* 0x008 PCI revision */
    u_long	CsrOffset[DC21X4_CSR_COUNT];	/* 0x00c read as u_short */
    u_char	PermanentAddress[6];		/* 0x04c */
    u_char	SromChecksumValid;		/* 0x052 21040 address ROM */
    u_char	reserved1;			/* 0x053 */
    u_long	DeviceId;			/* 0x054 DC21x4x_CFID */
    u_long	Csr15Shadow;			/* 0x058 21142/3 GEP in CSR15<31:16> */
    u_long	MediaNwayAdvertisement;		/* 0x05c CSR14/CSR6 bits to advertise */
    u_long	NwayLocalAbility;		/* 0x060 CSR12 link code word bits */
    u_char	AutoSenseCapable;		/* 0x064 */
    u_char	DefaultMediumFound;		/* 0x065 */
    u_char	reserved2[2];			/* 0x066 */
    u_long	OperationMode;			/* 0x068 CSR6 shadow */
    u_long	Threshold10Mbps;		/* 0x06c CSR6 TR bits */
    u_long	Threshold100Mbps;		/* 0x070 */
    u_long	LinkSpeed;			/* 0x074 in 100 b/s units */
    u_long	MediaType;			/* 0x078 code | DC21X4_MEDIA_ flags */
    u_long	MediaCapable;			/* 0x07c 1 << media code */
    u_long	DefaultMedium;			/* 0x080 */
    u_long	SelectedMedium;			/* 0x084 */
    int		MediaCount;			/* 0x088 entries in MediaPrecedence */
    int		GepSequenceLength;		/* 0x08c */
    u_short	GepSequence[DC21X4_MAX_GEP_SEQUENCE];	/* 0x090 */
    u_short	reserved3;			/* 0x09a */
    u_long	MediaSenseDelay;		/* 0x09c 21040 BNC test, x10 ms, min 30 */
    u_long	MediaPrecedence[DC21X4_MEDIA_COUNT];	/* 0x0a0 */
    DC21X4_MEDIA_TABLE Media[DC21X4_MEDIA_COUNT];	/* 0x0c4 */
    u_char	FullDuplex;			/* 0x1e4 */
    u_char	PhyMediaInSrom;			/* 0x1e5 SROM has an MII block */
    u_char	PhyPresent;			/* 0x1e6 */
    u_char	PhyNwayCapable;			/* 0x1e7 */
    u_char	TpLinkPassPending;		/* 0x1e8 */
    u_char	PhyIsolated;			/* 0x1e9 */
    u_char	PhyResetDone;			/* 0x1ea */
    u_char	NwayInProgress;			/* 0x1eb */
    u_char	ForceNway;			/* 0x1ec Nway on early 21041/21142 revs */
    u_char	UseMediaTypeForPhy;		/* 0x1ed */
    u_char	SkipAutoSense;			/* 0x1ee */
    u_char	KeepSiaLinkInterrupts;		/* 0x1ef SROM 1179/0204 */
    u_char	Phy100Sia10;			/* 0x1f0 PHY for 100, SIA for 10 Mb/s */
    u_char	NwayOnFirstLinkPass;		/* 0x1f1 */
    u_char	InitInProgress;			/* 0x1f2 */
    u_char	TestPacketMode;			/* 0x1f3 MediaDetect test frame */
    u_long	PhyNumber;			/* 0x1f4 */
    u_long	MiiMediaType;			/* 0x1f8 MII media code | flags */
    u_char	SromFormatVersion;		/* 0x1fc */
    u_char	reserved4[3];			/* 0x1fd */
    u_long	InterruptMask;			/* 0x200 CSR7 shadow */
    u_long	InterruptDispatchMask;		/* 0x204 */
    u_long	InterruptStatusMask;		/* 0x208 */
    u_long	LinkStatus;			/* 0x20c DC21X4_LINK_ */
    u_long	PreviousLinkStatus;		/* 0x210 */
    u_long	NwayPollCount;			/* 0x214 */
    u_long	MediaErrorCount[2];		/* 0x218 tested by AutoSense, never counted */
    u_long	NwayRetryCount;			/* 0x220 */
    u_long	NwayLinkPartner;		/* 0x224 saved CSR12 */
    u_long	TimerState;			/* 0x228 DC21X4_TIMER_ */
    u_short	PhyCount;			/* 0x22c */
    u_short	MiiCapabilities;		/* 0x22e */
    u_short	ActivePhy;			/* 0x230 0xff while isolated */
    u_short	reserved5;			/* 0x232 */
    struct _MII_PHY_INFO *Phy[DC21X4_MAX_PHY];	/* 0x234 */
    DC21X4_PHY_MEDIA PhyMediaInfo[DC21X4_MAX_PHY];	/* 0x238 */
    u_long	NwayProtocol;			/* 0x268 */
    u_long	TxErrorMaskDefault;		/* 0x26c raw (little-endian) TDES0 bits */
    u_long	TxErrorMask;			/* 0x270 */
    u_long	RxErrorMask;			/* 0x274 raw RDES0 bits */
    u_long	TestPacketPollCount;		/* 0x278 */
    u_long	TestPacketStatus;		/* 0x27c raw TDES0 */
    void	*Driver;			/* 0x280 the DEC21x4 instance */
} DC21X4_ADAPTER;				/* 0x284 */

/*
 * MII PHY state; one IOMalloc(DC21X4_MII_PHY_ALLOC_SIZE) block per PHY.
 */
#define MII_PHY_REGS	32

typedef struct _MII_PHY_INFO {
    u_char	Present;			/* 0x00 */
    u_char	reserved0;			/* 0x01 */
    u_short	PhyAddress;			/* 0x02 */
    u_long	PhyId;				/* 0x04 MII regs 2:3 */
    u_short	PhyCapabilities;		/* 0x08 */
    u_short	PhyMediaAdvertisement;		/* 0x0a local Nway ability */
    u_short	PhyRegs[MII_PHY_REGS];		/* 0x0c register shadow */
    u_short	PreviousControl;		/* 0x4c control saved by isolate */
    u_short	PreviousConnectionStatus;	/* 0x4e */

    BOOL	(*PhyInit)(DC21X4_ADAPTER *, struct _MII_PHY_INFO *);	/* 0x50 */
    void	(*PhyGetCapabilities)(struct _MII_PHY_INFO *, u_short *);	/* 0x54 */
    BOOL	(*PhySetConnectionType)(DC21X4_ADAPTER *,
		    struct _MII_PHY_INFO *, u_short, u_short);			/* 0x58 */
    BOOL	(*PhyGetConnectionType)(DC21X4_ADAPTER *,
		    struct _MII_PHY_INFO *, u_short *);				/* 0x5c */
    BOOL	(*PhyGetConnectionStatus)(DC21X4_ADAPTER *,
		    struct _MII_PHY_INFO *, u_short *);				/* 0x60 */
    void	(*PhyAdminStatus)(DC21X4_ADAPTER *,
		    struct _MII_PHY_INFO *, u_long *);				/* 0x64 */
    void	(*PhyAdminControl)(DC21X4_ADAPTER *,
		    struct _MII_PHY_INFO *, u_long);				/* 0x68 */
    BOOL	(*PhyReadRegister)(DC21X4_ADAPTER *,
		    struct _MII_PHY_INFO *, u_short, u_short *);		/* 0x6c */
    void	(*PhyWriteRegister)(DC21X4_ADAPTER *,
		    struct _MII_PHY_INFO *, u_short, u_short);			/* 0x70 */
    void	(*PhyNwayGetLocalAbility)(DC21X4_ADAPTER *,
		    struct _MII_PHY_INFO *, u_short *);				/* 0x74 */
    void	(*PhyNwaySetLocalAbility)(DC21X4_ADAPTER *,
		    struct _MII_PHY_INFO *, u_short);				/* 0x78 */
    void	(*PhyNwayGetPartnerAbility)(DC21X4_ADAPTER *,
		    struct _MII_PHY_INFO *, u_short *);				/* 0x7c */
} MII_PHY_INFO;					/* 0x80 */

/* MII status register */
#define MII_STATUS_100BASETX	0x2000
#define MII_STATUS_MEDIA_MASK	0xf800
#define MII_STATUS_NWAY_DONE	0x0020
#define MII_STATUS_NWAY_ABLE	0x0008
#define MII_STATUS_LINK		0x0004

/* MiiGenAdminControl / PhyAdminControl requests and PhyAdminStatus states */
#define MII_ADMIN_RESET		0
#define MII_ADMIN_OPERATIONAL	1
#define MII_ADMIN_ISOLATE	2
#define MII_ADMIN_POWER_DOWN	3
#define MII_ADMIN_FORCE_10	4
#define MII_ADMIN_FORCE_10_FD	5
#define MII_ADMIN_RESTORE	6

/* PhyGetConnectionStatus results: mode in the high byte, link in the low */
#define MII_CONN_FORCED		0x0200
#define MII_CONN_NWAY		0x0400
#define MII_CONN_NWAY_PENDING	0x03ff
#define MII_CONN_READ_ERROR	0xfffd
#define MII_LINK_FAIL		0
#define MII_LINK_PASS		1	/* link still up since the last poll */
#define MII_LINK_UP		2	/* link bit read from the PHY */

/*
 * CSR access.  The offset parameter is u_short, as in the sibling
 * DECchip2104x driver; that is what narrows the CsrOffset[] loads.
 */
static __inline__ unsigned int
readCsr(unsigned int base, unsigned short offset)
{
    return lwbrx(base + offset);
}

static __inline__ void
writeCsr(unsigned int base, unsigned short offset, unsigned int value)
{
    stwbrx(value, base + offset);
    eieio();
}

#define DC21X4_READ_CSR(_a, _n) \
	readCsr((_a)->PortOffset, (_a)->CsrOffset[_n])
#define DC21X4_WRITE_CSR(_a, _n, _v) \
	writeCsr((_a)->PortOffset, (_a)->CsrOffset[_n], (_v))

/*
 * Glue in DEC21x4.m.
 */
void		mediaTimeoutOccurred(DC21X4_ADAPTER *Adapter);
void		sendPacket(DC21X4_ADAPTER *Adapter, void *pkt, unsigned int len);
const char	*getDriverName(DC21X4_ADAPTER *Adapter);

/*
 * SROM helpers in DEC21x4SRom.m.
 */
BOOL		DC21040Parser(DC21X4_ADAPTER *Adapter);
u_long		CRC32(u_char *data, int len);
BOOL		VerifyChecksum(u_char *data);
void		DC21X4ParseExtendedBlock(DC21X4_ADAPTER *Adapter, u_char **block,
		    u_short generalPurposeCtrl, u_char *mediaCode);
void		DC21X4ParseFixedBlock(DC21X4_ADAPTER *Adapter, u_char **block,
		    u_short generalPurposeCtrl, u_char *mediaCode);
BOOL		DC21X4ParseSRom(DC21X4_ADAPTER *Adapter, u_char *srom);
void		SRomLocalAdvertisement(DC21X4_ADAPTER *Adapter, u_char mediaCode);

/*
 * Media control (DEC21x4Media.c).
 */
void		scheduleFunc(void (*function)(), void *arg, int msecs);
void		unscheduleFunc(void (*function)(), void *arg);
void		DC21X4WriteGepRegister(DC21X4_ADAPTER *Adapter, u_long data);
void		DC21X4InitializeGepRegisters(DC21X4_ADAPTER *Adapter, BOOL phy);
void		DC21X4InitializeMediaRegisters(DC21X4_ADAPTER *Adapter, BOOL phy);
void		DC2104InitializeSiaRegisters(DC21X4_ADAPTER *Adapter);
void		DC21X4StartAdapter(DC21X4_ADAPTER *Adapter);
void		DC21X4StopAdapter(DC21X4_ADAPTER *Adapter);
void		DC21X4StopReceiverAndTransmitter(DC21X4_ADAPTER *Adapter);
void		HandleGepInterrupt(DC21X4_ADAPTER *Adapter);
void		HandleLinkFailInterrupt(DC21X4_ADAPTER *Adapter, u_long *status);
void		HandleLinkPassInterrupt(DC21X4_ADAPTER *Adapter, u_long *status);
void		HandleLinkChangeInterrupt(DC21X4_ADAPTER *Adapter);
void		SwitchMediumToTpNway(DC21X4_ADAPTER *Adapter);
void		DC21X4EnableInterrupt(DC21X4_ADAPTER *Adapter);
void		DC21X4DisableInterrupt(DC21X4_ADAPTER *Adapter);
BOOL		DC21X4PhyInit(DC21X4_ADAPTER *Adapter);
BOOL		DC21X4SetPhyConnection(DC21X4_ADAPTER *Adapter);
void		SetMacConnection(DC21X4_ADAPTER *Adapter);
BOOL		DC21X4MiiAutoDetect(DC21X4_ADAPTER *Adapter);
BOOL		DC21X4MiiAutoSense(DC21X4_ADAPTER *Adapter);
void		SelectNonMiiPort(DC21X4_ADAPTER *Adapter);
void		DC21X4SetPhyControl(DC21X4_ADAPTER *Adapter, u_short control);
BOOL		DC21X4MediaDetect(DC21X4_ADAPTER *Adapter);
BOOL		DC2114Sense100BaseTxLink(DC21X4_ADAPTER *Adapter);
void		DC21X4DynamicAutoSense(void *systemSpecific1,
		    DC21X4_ADAPTER *Adapter, void *systemSpecific2,
		    void *systemSpecific3);
BOOL		DC21X4AutoSense(DC21X4_ADAPTER *Adapter);
void		DC21X4SwitchMedia(DC21X4_ADAPTER *Adapter, u_long medium);
void		DC21X4StartAutoSenseTimer(DC21X4_ADAPTER *Adapter, u_long msecs);
void		DC21X4StartTimer(DC21X4_ADAPTER *Adapter, u_long msecs);
void		DC21X4StopAutoSenseTimer(DC21X4_ADAPTER *Adapter);
void		DC21X4EnableNway(DC21X4_ADAPTER *Adapter);
void		DC21X4DisableNway(DC21X4_ADAPTER *Adapter);
void		DC21X4IndicateMediaStatus(DC21X4_ADAPTER *Adapter, u_long status);

/*
 * MII (DEC21x4MII.c).
 */
BOOL		MiiGenInit(DC21X4_ADAPTER *Adapter);
u_short		MiiGenGetCapabilities(DC21X4_ADAPTER *Adapter);
BOOL		MiiGenCheckConnection(DC21X4_ADAPTER *Adapter, u_short connection);
BOOL		MiiGenSetConnection(DC21X4_ADAPTER *Adapter, u_long connection,
		    u_short advertisement);
BOOL		MiiGenGetConnectionStatus(DC21X4_ADAPTER *Adapter, u_short *status);
BOOL		MiiGenGetConnection(DC21X4_ADAPTER *Adapter, u_short *connection);
void		MiiGenAdminStatus(DC21X4_ADAPTER *Adapter, u_long *status);
BOOL		MiiGenAdminControl(DC21X4_ADAPTER *Adapter, u_short control);
BOOL		FindAndInitMiiPhys(DC21X4_ADAPTER *Adapter);
void		MiiFreeResources(DC21X4_ADAPTER *Adapter);
BOOL		MiiPhyInit(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy);
void		MiiPhyGetCapabilities(MII_PHY_INFO *Phy, u_short *capabilities);
BOOL		MiiPhySetConnectionType(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy,
		    u_short connection, u_short advertisement);
BOOL		MiiPhyGetConnectionType(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy,
		    u_short *connection);
BOOL		MiiPhyGetConnectionStatus(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy,
		    u_short *status);
void		MiiPhyAdminControl(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy,
		    u_long control);
void		MiiPhyAdminStatus(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy,
		    u_long *status);
BOOL		MiiPhyReadRegister(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy,
		    u_short reg, u_short *data);
void		MiiPhyWriteRegister(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy,
		    u_short reg, u_short data);
void		MiiPhyNwayGetLocalAbility(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy,
		    u_short *ability);
void		MiiPhyNwaySetLocalAbility(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy,
		    u_short ability);
void		MiiPhyNwayGetPartnerAbility(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy,
		    u_short *ability);
BOOL		FindMiiPhyDevice(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy);
void		WriteMii(DC21X4_ADAPTER *Adapter, u_long data, int count);
void		MiiOutThreeState(DC21X4_ADAPTER *Adapter);
void		InitPhyInfoEntries(MII_PHY_INFO *Phy);
void		ConvertConnectionToControl(MII_PHY_INFO *Phy, u_short *connection);
void		ConvertMediaTypeToNwayLocalAbility(u_short mediaType, u_short *ability);
BOOL		ConvertNwayToConnectionType(u_short nway, u_short *connection);
BOOL		CheckConnectionSupport(MII_PHY_INFO *Phy, u_short connection);
void		HandleBroadcomMediaChangeFrom10To100(DC21X4_ADAPTER *Adapter,
		    MII_PHY_INFO *Phy);
BOOL		GetBroadcomPhyConnectionType(DC21X4_ADAPTER *Adapter, MII_PHY_INFO *Phy,
		    u_short *connection);

/*
 * Tables defined in DEC21x4MII.c and used elsewhere.
 */
extern char		*MediumString[DC21X4_MEDIA_STRING_COUNT];
extern const u_short	MediaBitTable[DC21X4_MEDIA_STRING_COUNT];
extern const u_short	ConvertMediaTypeToMiiType[DC21X4_MEDIA_COUNT];

#endif /* _DEC21X4ADAPTER_H */
