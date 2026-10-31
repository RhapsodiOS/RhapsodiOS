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
 * DEC21x4.h
 *
 * Interface definition for the DEC 21x4x (21040/21041/21140/21142/21143)
 * mbuf-based Ethernet driver.
 *
 * HISTORY
 *
 * Reconstructed for RhapsodiOS from the DEC21x4 code linked into the
 * Mac OS X Server 1.2v3 (kernel 5.6) ppc mach_kernel.  The instance
 * variables match that kernel's class metadata (instance size 0x8f4).
 */

#ifndef _DEC21X4_H
#define _DEC21X4_H

#import <driverkit/kernelDriver.h>
#import <driverkit/IOEthernet.h>
#import <driverkit/ppc/IOPCIDevice.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/IOPower.h>
#import <driverkit/IOEthernetPrivate.h>		/* debugger methods */
#import <bsd/sys/param.h>
#import <bsd/sys/mbuf.h>
#import <kernserv/machine/spl.h>
#import <bsd/net/etherdefs.h>

#import "DEC21x4Adapter.h"

#define DEC21X4_MAX_INSTANCES	32

#define TX_RING_MAX		256
#define RX_RING_MAX		128

#define RX_BUFFER_SIZE		1520
#define MIN_FRAME_SIZE		60

/*
 * Descriptors live in little-endian memory and are never swapped as a
 * whole; the bitfields below are declared in memory byte order so each
 * names the right little-endian bit.
 */
typedef union {
    u_long	data;
    struct {					/* RDES0 */
	u_long	tl	:1,	/* <7>  frame too long */
		cs	:1,	/* <6>  collision seen */
		ft	:1,	/* <5>  frame type */
		rw	:1,	/* <4>  receive watchdog */
		re	:1,	/* <3>  MII error */
		db	:1,	/* <2>  dribbling bit */
		ce	:1,	/* <1>  CRC error */
		zer	:1,	/* <0> */
		es	:1,	/* <15> error summary */
		de	:1,	/* <14> descriptor error */
		dt	:2,	/* <13:12> data type */
		rf	:1,	/* <11> runt frame */
		mf	:1,	/* <10> multicast frame */
		fs	:1,	/* <9>  first descriptor */
		ls	:1,	/* <8>  last descriptor */
		fl_lo	:8,	/* <23:16> frame length <7:0> */
		own	:1,	/* <31> */
		ff	:1,	/* <30> filtering fail */
		fl_hi	:6;	/* <29:24> frame length <13:8> */
    } rx;
    struct {					/* TDES0 */
	u_long	hf	:1,	/* <7>  heartbeat fail */
		cc	:4,	/* <6:3> collision count */
		lf	:1,	/* <2>  link fail */
		uf	:1,	/* <1>  underflow */
		de	:1,	/* <0>  deferred */
		es	:1,	/* <15> error summary */
		to	:1,	/* <14> jabber timeout */
			:2,
		lo	:1,	/* <11> loss of carrier */
		nc	:1,	/* <10> no carrier */
		lc	:1,	/* <9>  late collision */
		ec	:1,	/* <8>  excessive collisions */
			:8,
		own	:1,	/* <31> */
			:7;
    } tx;
} dcDescStatus_t;

typedef union {
    u_long	data;
    struct {					/* TDES1 / RDES1 */
	u_long	bs1_lo	:8,	/* <7:0>   buffer 1 size <7:0> */
		bs2_lo	:5,	/* <15:11> buffer 2 size <4:0> */
		bs1_hi	:3,	/* <10:8>  buffer 1 size <10:8> */
		dpd	:1,	/* <23> disable padding */
		ft0	:1,	/* <22> filtering type 0 */
		bs2_hi	:6,	/* <21:16> buffer 2 size <10:5> */
		ic	:1,	/* <31> interrupt on completion */
		ls	:1,	/* <30> last segment */
		fs	:1,	/* <29> first segment */
		ft1	:1,	/* <28> filtering type 1 */
		set	:1,	/* <27> setup frame */
		ac	:1,	/* <26> add CRC disable */
		ter	:1,	/* <25> end of ring (RDES1 RER) */
		tch	:1;	/* <24> second address chained */
    } bits;
} dcDescControl_t;

typedef struct {
    dcDescStatus_t	status;
    dcDescControl_t	control;
    u_long		buffer1;	/* physical, little-endian */
    u_long		buffer2;
} dcDescriptor_t;

/* Raw (unswapped) TDES0/RDES0 bits, for the adapter error masks. */
#define DC_DESC_OWN		0x00000080

/* Raw (unswapped) TDES1/RDES1 bits, as stored in dcDescControl_t.data. */
#define DC_TDES1_IC		0x00000080	/* <31> interrupt on completion */
#define DC_TDES1_LS		0x00000040	/* <30> last segment */
#define DC_TDES1_FS		0x00000020	/* <29> first segment */
#define DC_TDES1_SET		0x00000008	/* <27> setup frame */
#define DC_TDES1_TER		0x00000002	/* <25> end of ring (RDES1 RER) */
#define DC_TDES1_FT0		0x00004000	/* <22> filtering type 0: hash */

/* DC_INT_RI as seen through an unswapped CSR5 access. */
#define DC_RAW_INT_RI		0x40000000

/* Little-endian descriptor words. */
#define DC_SWAP_LONG(x)							\
	(((u_long)(x) >> 24) | (((u_long)(x) >> 8) & 0xff00) |		\
	 (((u_long)(x) << 8) & 0xff0000) | ((u_long)(x) << 24))

#define DC_SET_BUFFER_SIZES(_d, _s1, _s2) {				\
	(_d)->control.bits.bs1_lo = (_s1) & 0xff;				\
	(_d)->control.bits.bs1_hi = (_s1) >> 8;				\
	(_d)->control.bits.bs2_lo = (_s2) & 0x1f;				\
	(_d)->control.bits.bs2_hi = (_s2) >> 5;				\
}

/* Setup frame: 16 entries of three longwords, address in the low half. */
#define SETUP_ADDRESS_COUNT	16
#define SETUP_FRAME_SIZE	192

typedef struct {
    u_long	address[SETUP_ADDRESS_COUNT][3];
} dcSetupBuffer_t;

/* -_allocateDescMemory:size: bookkeeping; field names are in the metadata. */
typedef struct {
    void		*ptr;		/* page-aligned descriptors */
    unsigned int	size;
    void		*ptrReal;	/* IOMalloc result */
    unsigned int	sizeReal;
} dcDescMemory_t;

typedef struct {
    unsigned int	tx_page_crossed;
    unsigned int	tx_alignment;
    unsigned int	tx_ring_full;
    unsigned int	tx_rollback;
    unsigned int	tx_low_water;
    unsigned int	tx_coalesced;
    unsigned int	tx_coalesce_err;
    unsigned int	tx_f;
    unsigned int	tx_int;
    unsigned int	tx_lo;
    unsigned int	tx_nc;
    unsigned int	tx_col;
    unsigned int	tx_lc;
    unsigned int	tx_ec;
    unsigned int	tx_uf;
    unsigned int	tx_to;
    unsigned int	tx_to_int;
    unsigned int	tx_de;
    unsigned int	tx_fifo_max;
    unsigned int	tx_queue_full;
    unsigned int	rx_page_crossed;
    unsigned int	rx_alignment;
    unsigned int	rx_MCLGET_failed;
    unsigned int	rx_MGETHDR_failed;
    unsigned int	rx_short_frame;
    unsigned int	rx_long_frame;
    unsigned int	rx_f;
    unsigned int	rx_int;
    unsigned int	rx_rf;
    unsigned int	rx_tl;
    unsigned int	rx_cs;
    unsigned int	rx_ce;
    unsigned int	rx_de;
    unsigned int	rx_rj;
    unsigned int	rx_db;
    unsigned int	rx_re;
    unsigned int	rx_csr8_missed;
    unsigned int	rx_csr8_overflow;
    unsigned int	link_events;
    unsigned int	link_speed;
    unsigned int	link_status;
    char		link_duplex;
} dcDriverStats_t;

/*
 * Config-table "Network Connection" names.  Static, so every .m file
 * that imports this header carries its own copy, as the binary does.
 */
typedef struct {
    char		*name;
    unsigned int	mediaType;
} dcConnector_t;

#define CONNECTOR_COUNT		12

static const dcConnector_t connectorTable[CONNECTOR_COUNT] = {
    { "AutoSense",		DC21X4_MEDIA_AUTOSENSE | DC21X4_MEDIA_NWAY },
    { "AutoSense No Nway",	DC21X4_MEDIA_AUTOSENSE },
    { "10Base2 (BNC)",		DC21X4_MEDIA_10BASE2 },
    { "10Base5 (AUI)",		DC21X4_MEDIA_10BASE5 },
    { "10BaseT",		DC21X4_MEDIA_10BASET },
    { "10BaseT Full Duplex",	DC21X4_MEDIA_FULL_DUPLEX | DC21X4_MEDIA_10BASET_FD },
    { "10BaseT No Link Test",	DC21X4_MEDIA_NO_LINK_TEST | DC21X4_MEDIA_10BASET },
    { "100BaseTX",		DC21X4_MEDIA_100BASETX },
    { "100BaseTX Full Duplex",	DC21X4_MEDIA_FULL_DUPLEX | DC21X4_MEDIA_100BASETX_FD },
    { "100BaseT4",		DC21X4_MEDIA_100BASET4 },
    { "100BaseFX",		DC21X4_MEDIA_100BASEFX },
    { "100BaseFX Full Duplex",	DC21X4_MEDIA_FULL_DUPLEX | DC21X4_MEDIA_100BASEFX_FD },
};

/*
 * SROM images patched in for boards with broken SROMs
 * (-patchSROM:withSize:offset:verbose:).
 */
#define SROM_SIZE		128
#define SROM_MARKER_COUNT	8

typedef struct {
    u_short	offset;		/* byte offset into the SROM */
    u_short	indirect;	/* if non-zero, add srom[indirect] to offset */
    u_char	value;
} dcSromMarker_t;

typedef struct {
    char		*name;
    u_long		deviceId;
    int			enetAddressOffset;
    dcSromMarker_t	markers[SROM_MARKER_COUNT];
    u_short		srom[SROM_SIZE / 2];	/* byte-swapped on copy */
} dcSromPatch_t;

extern const dcSromPatch_t	patchTable[];
extern const int		patchTableCount;

/* (irq, driver) pairs scanned by dc_intr(). */
typedef struct {
    int		irq;
    id		driver;
} dcIrqEntry_t;

@interface DEC21x4 : IOEthernet
{
    unsigned int	ioBase;
    unsigned short	irq;
    IONetwork		*networkInterface;
    struct ifnet	*ifp;
    char		multicastEnabled;
    char		isPromiscuous;
    char		ready;
    unsigned int	_linkChangeInterruptCount;

    struct mbuf		*txMbuf[TX_RING_MAX];
    struct mbuf		*rxMbuf[RX_RING_MAX];
    struct mbuf		*KDB_txBuf;

    dcDescriptor_t	*rxRing;
    dcDescriptor_t	*txRing;
    unsigned short	rxRingSize;
    unsigned short	txRingSize;
    unsigned int	maxQueueSize;
    unsigned int	txPutIndex;
    unsigned int	txDoneIndex;
    unsigned int	txNumFree;
    unsigned int	txIntCount;
    unsigned short	txIntThreshold;
    unsigned int	rxDoneIndex;
    vm_task_t		driver_task;
    char		disableFlush;

    dcDescMemory_t	txDescMem;
    dcDescMemory_t	rxDescMem;
    dcSetupBuffer_t	*setupBuffer;
    unsigned int	setupBufferPhysical;

    DC21X4_ADAPTER	*Adapter;
    unsigned int	MediaCapableSaved;
    char		captureEffect;
    unsigned int	txThresh10;
    unsigned int	txThresh100;
    unsigned int	maxBurstLen;
    unsigned char	sromAddressBits;
    char		*userSROMData;
    char		dumpSROM;
    char		patchSROM;
    int			enetAddressOffset;
    char		logMediaTypes;
    int			filterMode;

    IMP			_inputPacketFunc;
    IMP			_transmitFunc;
    IMP			_transmitMbufFunc;

    dcDriverStats_t	drvstat;
    struct ifqueue	kdbQueue;

    IMP			_kdbLock;
    IMP			_kdbUnlock;

    struct mbuf		*Qhead;
    struct mbuf		*Qtail;
    unsigned int	Qcount;
}

+ (BOOL)probe:(IOPCIDevice *)devDesc;
- initFromDeviceDescription:(IODeviceDescription *)devDesc;
- free;

- (BOOL)enablePromiscuousMode;
- (void)disablePromiscuousMode;
- (BOOL)enableMulticastMode;
- (void)disableMulticastMode;
- (void)addMulticastAddress:(enet_addr_t *)addr;
- (void)removeMulticastAddress:(enet_addr_t *)addr;

- (IOReturn)getCharValues:(unsigned char *)parameterArray
	     forParameter:(IOParameterName)parameterName
		    count:(unsigned int *)count;

- (IOReturn)getPowerState:(PMPowerState *)state_p;
- (IOReturn)setPowerState:(PMPowerState)state;
- (IOReturn)getPowerManagement:(PMPowerManagementState *)state_p;
- (IOReturn)setPowerManagement:(PMPowerManagementState)state;

- (void)mbufsPlease;

@end

@interface DEC21x4(DEC21x4Init)
- (BOOL)resetAndEnable:(BOOL)enable;
- (BOOL)_initRegisters;
- (BOOL)_initAdapter;
- (BOOL)verifyMediaSupport:(unsigned int)mediaType;
@end

@interface DEC21x4(DEC21x4KDB)
- (void)receivePacket:(void *)pkt length:(unsigned int *)pkt_len
	      timeout:(unsigned int)timeout;
- (void)sendPacket:(void *)pkt length:(unsigned int)pkt_len;
@end

@interface DEC21x4(Private)
- (void)enableAdapterInterrupts;
- (void)disableAdapterInterrupts;
- (BOOL)_allocateDescMemory:(dcDescMemory_t *)descMem size:(unsigned int)size;
- (void)_freeDescMemory:(dcDescMemory_t *)descMem;
- (BOOL)_allocateMemory;
- (BOOL)_initTxRing;
- (BOOL)_initRxRing;
- (void)_startTransmit;
- (void)_startReceive;
- (void)transmit:(netbuf_t)pkt;			/* an mbuf chain */
- (int)transmitMbuf:(struct mbuf *)m;		/* TRANSMIT_ */
- (BOOL)_loadSetupFilter:(BOOL)pollForCompletion filterMode:(int)mode;
- (BOOL)_setAddressFiltering:(BOOL)pollForCompletion;
- (void)_setupPerfectFiltering;
- (void)_initHashFilter;
- (void)_updateHashFilter:(enet_addr_t *)addr;
- (void)_setupHashFiltering;
@end

@interface DEC21x4(DEC21x4SRom)
- (void)dumpSROM:(unsigned char *)srom size:(unsigned int)size;
- (void)_getStationAddress:(enet_addr_t *)ea;
- (BOOL)matchSROM:(unsigned char *)srom
       forMarkers:(const dcSromMarker_t *)markers;
- (BOOL)patchSROM:(unsigned char *)srom withSize:(unsigned int)size
	   offset:(int *)offset verbose:(BOOL)verbose;
- (BOOL)parseSROM:(BOOL)logMedia;
@end

/* -transmitMbuf: results */
#define TRANSMIT_OK		0
#define TRANSMIT_QUEUE		1	/* no room; keep on the queue */
#define TRANSMIT_DROP		2

#define FILTER_PERFECT		0
#define FILTER_HASH		1

/* DEC21x4.m */
extern dcIrqEntry_t	irq_table[DEC21X4_MAX_INSTANCES];
extern int		inst;

/* DEC21x4Private.m */
BOOL	IOUpdateTxDescriptorFromMbuf(DEC21x4 *self, struct mbuf **mp,
	    unsigned int *offset, dcDescriptor_t *desc);
void	dc_increment_out_errors(DEC21x4 *self, int count);
void	dc_increment_in_errors(DEC21x4 *self, int count);
void	dc_increment_collisions(DEC21x4 *self, int count);
void	dc_increment_out_packets(DEC21x4 *self, int count);
void	tx_err_record(dcDescStatus_t *status, dcDriverStats_t *stats);
void	dc_intr_tx(DEC21x4 *self);
void	dc_intr(int irq, void *ssp, void *arg);

/* Kernel routines no header declares. */
extern void	fast_bcopy(const void *from, void *to, unsigned int len);
extern void	m_copydata(struct mbuf *m, int off, int len, caddr_t cp);

/*
 * Serial ROM access through CSR9, for GET_SROM and -parseSROM:.  Every
 * access keeps the ROM selected for reading (RD | SR); CS, CLK and DI
 * are driven, DO is sampled.
 */
#define SROM_CSR9		DC_CSR(CSR9)
#define SROM_CSR9_IDLE		0x00004800	/* RD | SR */
#define SROM_CSR9_CS		0x00000001	/* chip select */
#define SROM_CSR9_CLK		0x00000002	/* serial clock */
#define SROM_CSR9_DI_SHIFT	2		/* data to the ROM */
#define SROM_CSR9_DO_SHIFT	3		/* data from the ROM */
#define SROM_DELAY		10		/* microseconds per clock phase */

static __inline__ void
sromClockIn(unsigned int base, unsigned int bit)
{
    unsigned int data = SROM_CSR9_IDLE | SROM_CSR9_CS |
	(bit << SROM_CSR9_DI_SHIFT);

    writeCsr(base, SROM_CSR9, data);
    IODelay(SROM_DELAY);
    writeCsr(base, SROM_CSR9, data | SROM_CSR9_CLK);
    IODelay(SROM_DELAY);
    writeCsr(base, SROM_CSR9, data);
    IODelay(SROM_DELAY);
}

/*
 * Read one SROM word.  The result is in SROM byte order: stored as a
 * u_short, its low byte lands first in memory.
 */
static __inline__ u_short
sromReadWord(unsigned int base, unsigned int addr, unsigned int addrBits)
{
    unsigned int i;
    unsigned int bit;
    u_short data;
    int j;

    /* reset, select the ROM, then send the read command (110) */
    writeCsr(base, SROM_CSR9, SROM_CSR9_IDLE);
    IODelay(SROM_DELAY);
    sromClockIn(base, 0);
    sromClockIn(base, 1);
    sromClockIn(base, 1);
    sromClockIn(base, 0);

    for (i = 0; i < addrBits; i++)
	sromClockIn(base, (addr >> (addrBits - i - 1)) & 1);

    data = 0;
    for (j = 0; j < 16; j++) {
	writeCsr(base, SROM_CSR9, SROM_CSR9_IDLE | SROM_CSR9_CS | SROM_CSR9_CLK);
	IODelay(SROM_DELAY);
	bit = (readCsr(base, SROM_CSR9) >> SROM_CSR9_DO_SHIFT) & 1;
	IODelay(SROM_DELAY);
	writeCsr(base, SROM_CSR9, SROM_CSR9_IDLE | SROM_CSR9_CS);
	IODelay(SROM_DELAY);
	data = (data << 1) | bit;
    }

    return (data >> 8) | (data << 8);
}

#endif /* _DEC21X4_H */
