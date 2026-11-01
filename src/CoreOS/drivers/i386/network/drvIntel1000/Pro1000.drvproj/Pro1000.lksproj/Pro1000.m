/*
 * Pro1000.m - Intel 8254x gigabit ethernet driver for OPENSTEP /
 * NeXTSTEP i386.
 *
 * An IOEthernet subclass: driverLoader matches the card against
 * "Auto Detect IDs" in the config tables, calls +probe:, and the
 * instance attaches to the network stack as enN.
 *
 * Verified on an Intel 82547EI. The rest of the PCI 8254x family is
 * supported from the SDM and FreeBSD's per-part code but has not been
 * run on real hardware - those parts announce themselves as
 * [UNVERIFIED PART] in the log. PCIe parts are out of scope.
 *
 * Things worth knowing before changing this (all learned the hard way,
 * with the reasoning kept at each site):
 *
 *   - After asserting CTRL.RST, touch no register for ~1 s. On this
 *     part a read into a resetting device never completes and the
 *     machine stops dead.  -> pro1000MacReset()
 *   - -resetAndEnable: runs in the network stack's context and must not
 *     sleep. Long waits belong in -initFromDeviceDescription:.
 *   - Interrupts need three separate things to be right; see
 *     -enableAllInterrupts and the end of -interruptOccurred.
 *   - IOMalloc guarantees neither contiguity nor alignment. DMA memory
 *     goes through allocDmaBlock().
 *
 * Strict C89 + NeXT Objective-C (cc 2.7.2.1). Kernel context: no libc.
 */

#import <driverkit/IODevice.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/directDevice.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/i386/ioPorts.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOEthernet.h>
#import <driverkit/IONetwork.h>
#import <driverkit/IONetbufQueue.h>
#import <net/etherdefs.h>
#import <net/netbuf.h>

#define PRO1000_VENDOR	0x8086

/*
 * Supported parts: the PCI/PCI-X 8254x family, which one SDM covers as a
 * whole. They share the register set, the legacy descriptor formats and
 * the multicast hash, so most of this driver is family-wide; what
 * differs is captured in the flags below.
 *
 * PCIe parts (82571 onwards) are a different manual and are out of
 * scope - and cannot be fitted to this machine anyway, which has no
 * PCIe slots.
 *
 * VERIFIED ON HARDWARE: 82547EI only. Everything else here follows from
 * the SDM and FreeBSD's per-part code; treat it as untested until a
 * card is actually in the slot.
 */

/*
 * The I/O BAR opens a 32-byte window with two registers (SDM 13.2.2.1):
 * write the internal register offset to IOADDR, then read or write it
 * through IODATA.
 */
#define E1000_IOADDR	0x00
#define E1000_IODATA	0x04

/* Per-part quirks */
#define Q_PHY_RESET_FIRST	0x01	/* reset the PHY before the MAC   */
#define Q_HUB_IMS		0x02	/* IMS/IMC re-assert (CSA ordering)*/
#define Q_RESET_VIA_IO		0x04	/* global reset through I/O space  */
#define Q_FIBER			0x08	/* SerDes/TBI - not supported here */

typedef struct {
    unsigned short	device;
    unsigned char	quirks;
    char	       *name;
} ChipInfo;

static ChipInfo chipTable[] = {
    /* 82540 - the simplest of the family */
    { 0x100E, 0,			"82540EM" },
    { 0x1015, 0,			"82540EM (LOM)" },
    { 0x1016, 0,			"82540EP (LOM)" },
    { 0x1017, 0,			"82540EP" },
    { 0x101E, 0,			"82540EP (mobile)" },

    /* 82541 - IGP PHY, and it cannot acknowledge the 64-bit write used
     * for a memory-space global reset, so that one goes through I/O. */
    { 0x1013, Q_PHY_RESET_FIRST | Q_RESET_VIA_IO, "82541EI" },
    { 0x1018, Q_PHY_RESET_FIRST | Q_RESET_VIA_IO, "82541EI (mobile)" },
    { 0x1014, Q_PHY_RESET_FIRST | Q_RESET_VIA_IO, "82541ER (LOM)" },
    { 0x1078, Q_PHY_RESET_FIRST | Q_RESET_VIA_IO, "82541ER" },
    { 0x1076, Q_PHY_RESET_FIRST | Q_RESET_VIA_IO, "82541GI" },
    { 0x1077, Q_PHY_RESET_FIRST | Q_RESET_VIA_IO, "82541GI (mobile)" },
    { 0x107C, Q_PHY_RESET_FIRST | Q_RESET_VIA_IO, "82541PI" },

    /* 82544 */
    { 0x1008, 0,			"82544EI (copper)" },
    { 0x100C, 0,			"82544GC (copper)" },
    { 0x100D, 0,			"82544GC (LOM)" },
    { 0x1009, Q_FIBER,			"82544EI (fiber)" },

    /* 82545 */
    { 0x100F, 0,			"82545EM (copper)" },
    { 0x1026, 0,			"82545GM (copper)" },
    { 0x1011, Q_FIBER,			"82545EM (fiber)" },
    { 0x1027, Q_FIBER,			"82545GM (fiber)" },
    { 0x1028, Q_FIBER,			"82545GM (SerDes)" },

    /* 82546 */
    { 0x1010, 0,			"82546EB (copper)" },
    { 0x101D, 0,			"82546EB (quad copper)" },
    { 0x1079, 0,			"82546GB (copper)" },
    { 0x1012, Q_FIBER,			"82546EB (fiber)" },
    { 0x107A, Q_FIBER,			"82546GB (fiber)" },
    { 0x107B, Q_FIBER,			"82546GB (SerDes)" },

    /* 82547 - CSA attached; the only part verified on real hardware */
    { 0x1019, Q_PHY_RESET_FIRST | Q_HUB_IMS, "82547EI" },
    { 0x101A, Q_PHY_RESET_FIRST | Q_HUB_IMS, "82547EI (mobile)" },
    { 0x1075, Q_PHY_RESET_FIRST | Q_HUB_IMS, "82547GI" },

    { 0, 0, 0 }
};

/*
 * Rate limit for repeating conditions: true at 1, 10, 100, 1000, ...
 *
 * A fixed "every hundredth" produced 107 lines from a single six-second
 * flood, which buries everything else in the log. On a log scale the
 * same flood is five lines, and the counter in each line still gives
 * the exact total.
 */
static BOOL
logMilestone(unsigned long n)
{
    unsigned long m;

    for (m = 1UL; m != 0UL && m <= n; m *= 10UL) {
	if (m == n) {
	    return YES;
	}
    }
    return NO;
}

static ChipInfo *
chipLookup(unsigned short device)
{
    int i;

    for (i = 0; chipTable[i].name != 0; i++) {
	if (chipTable[i].device == device) {
	    return &chipTable[i];
	}
    }
    return (ChipInfo *)0;
}

/* BAR0 window. The 8254x register file is 128 KB. */
#define PRO1000_REG_SIZE	0x20000

/* Register offsets (SDM chapter 13) */
#define E1000_CTRL	0x00000		/* Device Control       */
#define E1000_STATUS	0x00008		/* Device Status        */
#define E1000_EECD	0x00010		/* EEPROM/Flash Control */
#define E1000_IMC	0x000D8		/* Interrupt Mask Clear */
#define E1000_RCTL	0x00100		/* Receive Control      */
#define E1000_RAL0	0x05400		/* Receive Address Low  0 */
#define E1000_RAH0	0x05404		/* Receive Address High 0 */
#define E1000_MANC	0x05820		/* Management Control   */
#define E1000_MTA	0x05200		/* Multicast Table Array (128 x 32) */
#define E1000_RDBAL	0x02800		/* RX Descriptor Base Low  */
#define E1000_RDBAH	0x02804		/* RX Descriptor Base High */
#define E1000_RDLEN	0x02808		/* RX Descriptor Length    */
#define E1000_RDH	0x02810		/* RX Descriptor Head      */
#define E1000_RDT	0x02818		/* RX Descriptor Tail      */
#define E1000_TDBAL	0x03800		/* TX Descriptor Base Low  */
#define E1000_TDBAH	0x03804		/* TX Descriptor Base High */
#define E1000_TDLEN	0x03808		/* TX Descriptor Length    */
#define E1000_TDH	0x03810		/* TX Descriptor Head      */
#define E1000_TDT	0x03818		/* TX Descriptor Tail      */
#define E1000_TCTL	0x00400		/* Transmit Control        */
#define E1000_TIPG	0x00410		/* Transmit Inter-Packet Gap */
#define E1000_ICR	0x000C0		/* Interrupt Cause Read      */
#define E1000_IMS	0x000D0		/* Interrupt Mask Set        */

/* CTRL bits */
#define E1000_CTRL_ASDE		0x00000020UL	/* auto-speed detect   */
#define E1000_CTRL_SLU		0x00000040UL	/* set link up         */
#define E1000_CTRL_FRCSPD	0x00000800UL	/* force speed         */
#define E1000_CTRL_FRCDPX	0x00001000UL	/* force duplex        */
#define E1000_CTRL_RST		0x04000000UL	/* global reset        */
#define E1000_CTRL_PHY_RST	0x80000000UL	/* PHY reset           */

/* STATUS bits */
#define E1000_STATUS_FD		0x00000001UL	/* full duplex         */
#define E1000_STATUS_LU		0x00000002UL	/* link up             */
#define E1000_STATUS_SPEED_MASK	0x000000C0UL
#define E1000_STATUS_SPEED_SHIFT 6

/* Other bits used during reset */
#define E1000_TCTL_PSP		0x00000008UL	/* pad short packets   */
#define E1000_MANC_ARP_EN	0x00002000UL	/* HW ARP filtering    */
#define E1000_RAH_AV		0x80000000UL	/* address valid       */

/* RCTL bits */
#define E1000_RCTL_EN		0x00000002UL	/* receiver enable     */
#define E1000_RCTL_UPE		0x00000008UL	/* unicast promiscuous */
#define E1000_RCTL_MPE		0x00000010UL	/* multicast promisc.  */
#define E1000_RCTL_BAM		0x00008000UL	/* accept broadcast    */
#define E1000_RCTL_SZ_2048	0x00000000UL	/* 2048-byte buffers   */
#define E1000_RCTL_SECRC	0x04000000UL	/* strip ethernet CRC  */

/* TCTL bits. CT (collision threshold) and COLD (collision distance) are
 * the standard half-duplex values; harmless at full duplex. */
#define E1000_TCTL_EN		0x00000002UL	/* transmitter enable  */
#define E1000_TCTL_CT_SHIFT	4
#define E1000_TCTL_COLD_SHIFT	12

/*
 * Inter-packet gap for copper: IPGT 8, IPGR1 8, IPGR2 6. This is the
 * value every 8254x driver uses for copper media; leaving TIPG at its
 * reset value would transmit with the wrong gap.
 */
#define E1000_TIPG_COPPER	0x00602008UL

/*
 * Multicast Table Array: 128 registers of 32 bits = a 4096-bit vector.
 * An address is accepted when the bit its hash selects is set.
 */
#define MTA_REGS	128
#define MTA_MASK	0x0FFFUL	/* (MTA_REGS * 32) - 1 */

/* How many multicast addresses to remember. The table is a hash, so
 * removing one address means recomputing from the rest - which needs
 * the list kept. */
#define MAX_MCAST	32

/* Legacy TX descriptor command byte */
#define E1000_TXD_CMD_EOP	0x01		/* end of packet       */
#define E1000_TXD_CMD_IFCS	0x02		/* insert ethernet CRC */
#define E1000_TXD_CMD_RS	0x08		/* report status (DD)  */

/* Interrupt causes we ask for */
#define E1000_ICR_TXDW		0x00000001UL	/* TX descriptor written */
#define E1000_ICR_TXQE		0x00000002UL	/* TX queue empty        */
#define E1000_ICR_LSC		0x00000004UL	/* link status change    */
#define E1000_ICR_RXSEQ		0x00000008UL	/* receive sequence error */
#define E1000_ICR_RXDMT0	0x00000010UL	/* RX ring running low   */
#define E1000_ICR_RXO		0x00000040UL	/* receiver overrun      */
#define E1000_ICR_RXT0		0x00000080UL	/* RX timer / packet     */

/* RX descriptor status/error bits */
#define E1000_RXD_STAT_DD	0x01		/* descriptor done     */

/*
 * Receive error bits. This is FreeBSD's E1000_RXD_ERR_FRAME_ERR_MASK -
 * the errors that mean the frame itself is bad. TCPE and IPE are
 * deliberately left out: they are checksum-offload results, and with
 * offload disabled they carry no meaning.
 */
#define E1000_RXD_ERR_CE	0x01		/* CRC error           */
#define E1000_RXD_ERR_SE	0x02		/* symbol error        */
#define E1000_RXD_ERR_SEQ	0x04		/* sequence error      */
#define E1000_RXD_ERR_CXE	0x10		/* carrier extension   */
#define E1000_RXD_ERR_RXE	0x80		/* receive data error  */
#define E1000_RXD_ERR_FRAME	(E1000_RXD_ERR_CE | E1000_RXD_ERR_SE \
				 | E1000_RXD_ERR_SEQ | E1000_RXD_ERR_CXE \
				 | E1000_RXD_ERR_RXE)

/* TX descriptor status bits (written back because CMD_RS is set) */
#define E1000_TXD_STAT_DD	0x01		/* descriptor done     */
#define E1000_TXD_STAT_EC	0x02		/* excess collisions   */
#define E1000_TXD_STAT_LC	0x04		/* late collision      */
#define E1000_TXD_STAT_TU	0x08		/* transmit underrun   */
#define E1000_TXD_STAT_FAIL	(E1000_TXD_STAT_EC | E1000_TXD_STAT_LC \
				 | E1000_TXD_STAT_TU)

/*
 * Statistics registers.
 *
 * Offsets checked against two independent sources: FreeBSD's
 * e1000_regs.h and the SDM's own register listing (13.7).
 *
 * **Every one of these resets when read** (SDM 13.7), so a read returns
 * the count since the previous read and nothing can be counted twice.
 * They are also *not* initialised by hardware - the SDM says their
 * value after reset is unknown and that software must read them all to
 * clear them before enabling the receive and transmit channels. That is
 * what -_clearStatistics does; without it the first harvest would
 * report whatever garbage the registers powered up holding.
 *
 * They stick at 0xFFFFFFFF rather than wrapping, so they have to be
 * read often enough to stay well short of that.
 */
#define E1000_CRCERRS	0x04000		/* CRC errors                  */
#define E1000_ALGNERRC	0x04004		/* alignment errors            */
#define E1000_RXERRC	0x0400C		/* receive errors              */
#define E1000_MPC	0x04010		/* missed packets (RX FIFO full) */
#define E1000_SCC	0x04014		/* single collisions           */
#define E1000_ECOL	0x04018		/* excessive collisions        */
#define E1000_MCC	0x0401C		/* multiple collisions         */
#define E1000_LATECOL	0x04020		/* late collisions             */
#define E1000_COLC	0x04028		/* total collisions            */
#define E1000_DC	0x04030		/* defer count                 */
#define E1000_TNCRS	0x04034		/* transmit with no carrier    */
#define E1000_SEC	0x04038		/* sequence errors             */
#define E1000_CEXTERR	0x0403C		/* carrier extension errors    */
#define E1000_RLEC	0x04040		/* receive length errors       */
#define E1000_RNBC	0x040A0		/* receives with no buffer     */
#define E1000_RUC	0x040A4		/* receive undersize           */
#define E1000_RFC	0x040A8		/* receive fragment            */
#define E1000_ROC	0x040AC		/* receive oversize            */
#define E1000_RJC	0x040B0		/* receive jabber              */

/* EECD bits, for reporting what kind of NVM is fitted */
#define E1000_EECD_PRES		0x00000100UL	/* NVM present         */
#define E1000_EECD_TYPE		0x00002000UL	/* 1 = SPI, 0 = uwire  */


/* Mandatory settling time after asserting CTRL.RST. The SDM asks for
 * "approximately 1 s" before touching any register; touching one early
 * hangs this machine outright. 1200 ms leaves margin. */
#define RESET_WAIT_MS		1200

/* How long to wait for auto-negotiation after asking for link up.
 * Gigabit negotiation with a switch routinely takes a couple of
 * seconds; giving up sooner would report a false failure. */
#define LINK_WAIT_MS		4000
#define LINK_POLL_MS		100

/*
 * RX ring. RDLEN must be a multiple of 128 bytes, which 16 descriptors
 * x 16 bytes satisfies. Sixteen 2 KB buffers is enough to ride out a
 * burst without spending a page each on more.
 */
#define NRXDESC		16
#define RXDESC_BYTES	(NRXDESC * 16)
#define RXBUF_SIZE	2048
#define PAGE_BYTES	4096


/*
 * Legacy receive descriptor, 16 bytes, exactly as the hardware reads
 * it. The address is 64 bits in the layout even though the 82547EI
 * cannot use the upper half, so it is kept as two longs - C89 has no
 * 64-bit integer to rely on here.
 */
typedef struct {
    unsigned long	bufferAddrLow;
    unsigned long	bufferAddrHigh;
    unsigned short	length;
    unsigned short	checksum;
    unsigned char	status;
    unsigned char	errors;
    unsigned short	special;
} RxDesc;

/*
 * Legacy transmit descriptor, 16 bytes.
 */
typedef struct {
    unsigned long	bufferAddrLow;
    unsigned long	bufferAddrHigh;
    unsigned short	length;
    unsigned char	cso;
    unsigned char	cmd;
    unsigned char	status;
    unsigned char	css;
    unsigned short	special;
} TxDesc;

/* One descriptor is all a single test frame needs, but RDLEN/TDLEN must
 * still be a multiple of 128 bytes, so the ring is padded to 8. */
#define NTXDESC		8
#define TXDESC_BYTES	(NTXDESC * 16)
#define TXBUF_SIZE	2048



/* Consecutive transmit timeouts tolerated before the driver stops
 * trying. Resetting on every one is how a missing interrupt turns into
 * a machine-killing loop. */
#define MAX_TX_TIMEOUTS	3



/* ---------------------------------------------------------------- */
/* Register access                                                    */
/* ---------------------------------------------------------------- */

/*
 * Registers are 32-bit and must be accessed as such. `volatile' keeps
 * the compiler from reordering or eliding accesses to device memory.
 */
static unsigned long
regRead(vm_address_t base, unsigned int offset)
{
    return *(volatile unsigned long *)(base + offset);
}

static void
regWrite(vm_address_t base, unsigned int offset, unsigned long value)
{
    *(volatile unsigned long *)(base + offset) = value;
}

/*
 * Posted writes to a PCI device are not necessarily complete when the
 * store instruction retires. Reading any register forces them out
 * before the next step depends on them having landed.
 */
static void
regFlush(vm_address_t base)
{
    (void)regRead(base, E1000_STATUS);
}

static const char *
speedText(unsigned long status)
{
    switch ((status & E1000_STATUS_SPEED_MASK) >> E1000_STATUS_SPEED_SHIFT) {
    case 0:  return "10Mb/s";
    case 1:  return "100Mb/s";
    case 2:  return "1000Mb/s";
    default: return "1000Mb/s (reserved encoding)";
    }
}

static void
reportLink(vm_address_t base, const char *when)
{
    unsigned long status;

    status = regRead(base, E1000_STATUS);

    if (status & E1000_STATUS_LU) {
	IOLog("Pro1000: %s link UP, %s, %s (STATUS 0x%08x)\n",
	      when,
	      speedText(status),
	      (status & E1000_STATUS_FD) ? "full duplex" : "half duplex",
	      (unsigned int)status);
    } else {
	/* With no link the speed and duplex fields hold whatever the
	 * last negotiation left behind, so reporting them would invite
	 * a wrong conclusion. */
	IOLog("Pro1000: %s link DOWN (STATUS 0x%08x)\n",
	      when, (unsigned int)status);
    }
}

/*
 * Read station address 0. The hardware loads this from NVM at reset, so
 * it is both the canonical source for the MAC address and a way to tell
 * whether the NVM reload actually happened.
 */
static void
readStationAddress(vm_address_t base, unsigned char *mac, int *validOut)
{
    unsigned long ral, rah;

    ral = regRead(base, E1000_RAL0);
    rah = regRead(base, E1000_RAH0);

    mac[0] = (unsigned char)( ral        & 0xFFUL);
    mac[1] = (unsigned char)((ral >>  8) & 0xFFUL);
    mac[2] = (unsigned char)((ral >> 16) & 0xFFUL);
    mac[3] = (unsigned char)((ral >> 24) & 0xFFUL);
    mac[4] = (unsigned char)( rah        & 0xFFUL);
    mac[5] = (unsigned char)((rah >>  8) & 0xFFUL);

    *validOut = (rah & E1000_RAH_AV) ? 1 : 0;
}

static void
logMac(const char *label, unsigned char *mac, int valid)
{
    IOLog("Pro1000: %s %02x:%02x:%02x:%02x:%02x:%02x %s\n",
	  label, mac[0], mac[1], mac[2], mac[3], mac[4], mac[5],
	  valid ? "(valid)" : "(NOT marked valid)");
}

/* ---------------------------------------------------------------- */
/* Reset and link setup                                              */
/* ---------------------------------------------------------------- */

/*
 * Reset sequence for the 82541/82547, following the SDM and FreeBSD's
 * e1000_reset_hw_82541(). The ordering matters:
 *
 *   - interrupts masked and the engines stopped first, so nothing is in
 *     flight across the reset
 *   - the PHY is reset BEFORE the MAC on these parts
 *   - 20 ms afterwards for the NVM reload to finish; reading registers
 *     before that returns values that are not yet restored
 *
 * The 82541 needs the global reset issued through I/O space because it
 * cannot acknowledge the 64-bit write; the 82547 does not, so a normal
 * memory write is used here.
 */
static void
pro1000Quiesce(vm_address_t base)
{
    regWrite(base, E1000_IMC, 0xFFFFFFFFUL);
    regWrite(base, E1000_RCTL, 0UL);
    regWrite(base, E1000_TCTL, E1000_TCTL_PSP);
    regFlush(base);

    /* let any outstanding bus transactions drain before a reset */
    IOSleep(10);
}

/*
 * On the 82541/82547 the PHY must be reset before the MAC.
 */
static void
pro1000PhyReset(vm_address_t base, unsigned long ctrl)
{
    regWrite(base, E1000_CTRL, ctrl | E1000_CTRL_PHY_RST);
    regFlush(base);
    IOSleep(5);
}

/*
 * Global device reset.
 *
 * This hung the machine hard until the wait below was got right. The
 * SDM's CTRL.RST description is explicit:
 *
 *   "To ensure that global device reset has fully completed and that
 *    the Ethernet controller responds to subsequent access, wait
 *    approximately 1 s after setting and before attempting to check to
 *    see if the bit has cleared or to access any other device register."
 *
 * So there must be NO register access whatsoever between asserting RST
 * and the end of that wait - not even the read-back that normally
 * flushes a posted write. On an ordinary PCI part a read of a
 * non-responding target ends in a master abort and returns all-ones,
 * which is why other drivers get away with flushing here. The 82547EI
 * answers on a CSA port wired into the memory controller, and there
 * that read simply never completes: the CPU stalls on the bus and the
 * whole machine stops. The write is posted and lands on its own.
 *
 * The 82541 has to issue this through I/O space because it cannot
 * acknowledge the 64-bit write; the 82547 does not, so a normal memory
 * write is used.
 */
static void
pro1000MacReset(vm_address_t base, unsigned long ctrl,
		unsigned char quirks, unsigned short ioBase)
{
    unsigned long manc;

    IOLog("Pro1000: asserting global RST (no register access for %d ms)\n",
	  RESET_WAIT_MS);

    if ((quirks & Q_RESET_VIA_IO) && ioBase != 0) {
	/*
	 * The 82541 cannot acknowledge the 64-bit write a memory-space
	 * reset turns into, so the SDM and FreeBSD both issue this one
	 * through the I/O BAR instead: write the register offset to
	 * IOADDR, then the value to IODATA.
	 *
	 * [UNVERIFIED] No 82541 has been in this machine.
	 */
	outl((IOEISAPortAddress)(ioBase + E1000_IOADDR),
	     (unsigned long)E1000_CTRL);
	outl((IOEISAPortAddress)(ioBase + E1000_IODATA),
	     ctrl | E1000_CTRL_RST);
    } else {
	regWrite(base, E1000_CTRL, ctrl | E1000_CTRL_RST);
    }

    /* Deliberately no regFlush() here - see above. */
    IOSleep(RESET_WAIT_MS);

    IOLog("Pro1000: global RST survived, CTRL 0x%08x\n",
	  (unsigned int)regRead(base, E1000_CTRL));

    /* ASF-enabled boards leave hardware ARP filtering on, which would
     * silently eat frames the driver expects to receive. */
    manc = regRead(base, E1000_MANC);
    if (manc & E1000_MANC_ARP_EN) {
	regWrite(base, E1000_MANC, manc & ~E1000_MANC_ARP_EN);
	regFlush(base);
	IOLog("Pro1000: MANC 0x%08x - hardware ARP filtering turned off\n",
	      (unsigned int)manc);
    }
}

/*
 * Ask for link without waiting for the result.
 *
 * The blocking version below is fine from the load-time path, but
 * -resetAndEnable: is called from the network stack (an ifconfig
 * ioctl), and sleeping for seconds there wedges the machine - that is
 * exactly how this driver hung it. Setting the bits is all that is
 * needed anyway: the PHY negotiates on its own and the result arrives
 * as an LSC interrupt.
 */
static void
pro1000RequestLink(vm_address_t base)
{
    unsigned long ctrl;

    ctrl = regRead(base, E1000_CTRL);
    ctrl |= (E1000_CTRL_SLU | E1000_CTRL_ASDE);
    ctrl &= ~(E1000_CTRL_FRCSPD | E1000_CTRL_FRCDPX);
    regWrite(base, E1000_CTRL, ctrl);
    regFlush(base);
}

/*
 * Ask for link and let the PHY negotiate. On this family the PHY runs
 * clause 40 auto-negotiation on its own; the driver only has to set the
 * link up and enable auto-speed detection, then read the result. Any
 * forced speed/duplex bits left over would override that, so they are
 * cleared.
 *
 * Returns 1 if the link came up within LINK_WAIT_MS.
 */
static int
pro1000SetupLink(vm_address_t base)
{
    unsigned long ctrl, status;
    int waited;

    ctrl = regRead(base, E1000_CTRL);
    ctrl |= (E1000_CTRL_SLU | E1000_CTRL_ASDE);
    ctrl &= ~(E1000_CTRL_FRCSPD | E1000_CTRL_FRCDPX);
    regWrite(base, E1000_CTRL, ctrl);
    regFlush(base);


    for (waited = 0; waited < LINK_WAIT_MS; waited += LINK_POLL_MS) {
	status = regRead(base, E1000_STATUS);
	if (status & E1000_STATUS_LU) {
	    IOLog("Pro1000: link came up after %d ms\n", waited);
	    return 1;
	}
	IOSleep(LINK_POLL_MS);
    }

    IOLog("Pro1000: no link after %d ms\n", LINK_WAIT_MS);
    return 0;
}

/* ---------------------------------------------------------------- */
/* Receive path                                                       */
/* ---------------------------------------------------------------- */

/*
 * DMA memory has to satisfy two things IOMalloc does not promise:
 * the block must be physically contiguous, and the device must be given
 * its physical address. Getting either wrong means the NIC writes into
 * whatever physical memory the wrong address lands on - which is how a
 * driver corrupts the kernel rather than merely failing.
 *
 * The idiom below is NeXT's own (AMDPCSCSIDriver does the same):
 * allocate twice what is needed and use whichever half does not cross a
 * page boundary. Anything inside a single page is contiguous by
 * definition, so no contiguity assumption is left to chance.
 *
 * Returns the usable virtual address, or 0. The caller must free
 * `*allocOut' (of size 2*size), not the returned pointer.
 */
static vm_address_t
allocDmaBlock(int size, vm_address_t *allocOut, unsigned long *physOut)
{
    vm_address_t alloc, use;
    unsigned      phys;
    IOReturn      ret;

    *allocOut = 0;
    *physOut  = 0;

    alloc = (vm_address_t)IOMalloc(size * 2);
    if (alloc == 0) {
	IOLog("Pro1000: IOMalloc(%d) failed\n", size * 2);
	return 0;
    }
    *allocOut = alloc;

    use = alloc;
    if ((alloc & ~(PAGE_BYTES - 1)) != ((alloc + size - 1) & ~(PAGE_BYTES - 1))) {
	/* first half straddles a page; the second half cannot */
	use = alloc + size;
    }

    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_offset_t)use, &phys);
    if (ret != IO_R_SUCCESS) {
	IOLog("Pro1000: IOPhysicalFromVirtual(0x%x) failed, ret %d\n",
	      (unsigned int)use, (int)ret);
	return 0;
    }

    /* Re-check on the physical side: if the end of the block is not
     * physically adjacent to the start, the virtual block spans two
     * frames and is unusable however it looked virtually. */
    {
	unsigned physEnd;

	ret = IOPhysicalFromVirtual(IOVmTaskSelf(),
				    (vm_offset_t)(use + size - 1), &physEnd);
	if (ret != IO_R_SUCCESS
	    || (unsigned long)physEnd != (unsigned long)phys + size - 1) {
	    IOLog("Pro1000: block at 0x%x is not physically contiguous\n",
		  (unsigned int)use);
	    return 0;
	}
    }

    *physOut = (unsigned long)phys;
    return use;
}

/*
 * Allocate the descriptor ring and its buffers, reporting every address
 * so a wrong one is visible in the log rather than only in its
 * consequences. Returns 1 on success; on failure the caller still has
 * to call rxFree() to release whatever was obtained.
 */
static int
rxAlloc(vm_address_t *ringAllocOut, vm_address_t *ringOut,
	unsigned long *ringPhysOut,
	vm_address_t *bufAllocs, vm_address_t *bufs, unsigned long *bufPhys)
{
    int i;

    *ringOut = allocDmaBlock(RXDESC_BYTES, ringAllocOut, ringPhysOut);
    if (*ringOut == 0) {
	return 0;
    }

    /* The ring base must be 16-byte aligned (SDM 13.4.28). IOMalloc
     * returns better than that in practice, but assuming so silently is
     * how alignment bugs hide. */
    if (*ringPhysOut & 0x0FUL) {
	IOLog("Pro1000: ring phys 0x%x is not 16-byte aligned\n",
	      (unsigned int)*ringPhysOut);
	return 0;
    }

    for (i = 0; i < NRXDESC; i++) {
	bufs[i] = allocDmaBlock(RXBUF_SIZE, &bufAllocs[i], &bufPhys[i]);
	if (bufs[i] == 0) {
	    IOLog("Pro1000: buffer %d allocation failed\n", i);
	    return 0;
	}
    }

    return 1;
}

static void
rxFree(vm_address_t ringAlloc, vm_address_t *bufAllocs)
{
    int i;

    for (i = 0; i < NRXDESC; i++) {
	if (bufAllocs[i] != 0) {
	    IOFree((void *)bufAllocs[i], RXBUF_SIZE * 2);
	    bufAllocs[i] = 0;
	}
    }
    if (ringAlloc != 0) {
	IOFree((void *)ringAlloc, RXDESC_BYTES * 2);
    }
}




/* ---------------------------------------------------------------- */
/* Transmit path                                                      */
/* ---------------------------------------------------------------- */


/*
 * Hand one frame to the hardware and wait for it to say it is done.
 * Returns 1 if the descriptor was written back within TX_WAIT_MS.
 */


/* ---------------------------------------------------------------- */
/* P2 sequence                                                        */
/* ---------------------------------------------------------------- */


/* ---------------------------------------------------------------- */
/* Standalone path: find the device without DriverKit's help          */


/* ---------------------------------------------------------------- */
/* DriverKit path                                                     */
/* ---------------------------------------------------------------- */

/* ---------------------------------------------------------------- */
/* Address filtering                                                  */
/* ---------------------------------------------------------------- */

/*
 * Hash a multicast address to a bit in the Multicast Table Array.
 *
 * This is the filter type 0 variant of the algorithm in the SDM
 * (and in FreeBSD's e1000_hash_mc_addr_generic): with 128 registers the
 * vector is 4096 bits, so the mask is 0xFFF and the shift is 4.
 *
 *   hash = ((addr[4] >> 4) | (addr[5] << 4)) & 0xFFF
 *
 * RCTL.MO is left at its reset value, which selects the same variant.
 */
static unsigned long
mcastHash(unsigned char *addr)
{
    return MTA_MASK & (((unsigned long)addr[4] >> 4)
		       | ((unsigned long)addr[5] << 4));
}

/*
 * Rebuild the whole table from the kept list.
 *
 * Incremental removal is not possible: two addresses can hash to the
 * same bit, so clearing the bit for one would silently stop accepting
 * the other. Recomputing from the list is the only correct way.
 */
/* ---------------------------------------------------------------- */
/* DriverKit instance - the real driver                               */
/* ---------------------------------------------------------------- */

/*
 * Everything above this line is the staged proving harness, reachable
 * through the CALL entry without DriverKit's help. What follows is the
 * driver proper: an IOEthernet subclass that the framework instantiates
 * and attaches to the network stack.
 *
 * `+probe:' is invoked by /usr/etc/driverLoader (not by kl_util), which
 * matches "Auto Detect IDs" in Default.table against the PCI bus.
 */

@interface Pro1000 : IOEthernet
{
    vm_address_t	regBase;	/* mapped BAR0                */
    unsigned long	regPhys;
    ChipInfo	       *chip;		/* which 8254x this is        */
    unsigned short	ioBase;		/* I/O window, Q_RESET_VIA_IO */
    int			irqCount;	/* what the framework handed us */
    enet_addr_t		myAddress;
    IONetwork	       *network;
    id			transmitQueue;

    vm_address_t	rxRingAlloc, rxRing;
    unsigned long	rxRingPhys;
    vm_address_t	rxBufAllocs[NRXDESC], rxBufs[NRXDESC];
    unsigned long	rxBufPhys[NRXDESC];
    int			rxNext;

    vm_address_t	txRingAlloc, txRing;
    unsigned long	txRingPhys;
    vm_address_t	txBufAllocs[NTXDESC], txBufs[NTXDESC];
    unsigned long	txBufPhys[NTXDESC];
    int			txTimeouts;
    int			txDone;		/* oldest descriptor not yet reaped */

    /* Error accounting. The OS counters are write-only from here, so
     * these keep a running total for the log. */
    unsigned long	rxMissed;	/* MPC  - RX FIFO had no room     */
    unsigned long	rxNoBuffer;	/* RNBC - ring had no descriptor  */
    unsigned long	rxBadFrames;	/* descriptors flagged in error   */
    unsigned long	rxNoMbufs;	/* nb_alloc failed                */
    unsigned long	txDropped;	/* transmit queue was full        */
    unsigned long	txFailed;	/* descriptor reported EC/LC/TU   */
    unsigned long	rxOverruns;	/* RXO interrupts                 */
    unsigned long	txLinkStalls;	/* watchdogs fired with no link   */
    unsigned int	irqSinceHarvest;
    BOOL		linkUp;		/* last known carrier state       */

    enet_addr_t		mcast[MAX_MCAST];
    int			mcastCount;
    BOOL		mcastMode;
    BOOL		promiscMode;
}
+ (BOOL)probe:(IODeviceDescription *)devDesc;
- initFromDeviceDescription:(IODeviceDescription *)devDesc;
- (void)_rearmInterrupts;
- (void)_writeMulticastTable;
- (void)_applyReceiveFilter;
- (void)_clearStatistics;
- (void)_harvestStatistics;
- (void)_reapTransmit;
@end

@implementation Pro1000

+ (BOOL)probe:(IODeviceDescription *)devDesc
{
    Pro1000 *dev;


    dev = [self alloc];
    if (dev == nil) {
	return NO;
    }
    return [dev initFromDeviceDescription:devDesc] != nil;
}

- initFromDeviceDescription:(IODeviceDescription *)devDesc
{
    IOPCIConfigSpace	config;
    IOReturn		ret;
    vm_address_t	virt;
    unsigned char	mac[6];
    int			valid, i;

    if ([super initFromDeviceDescription:devDesc] == nil) {
	return nil;
    }

    ret = [IODirectDevice getPCIConfigSpace:&config
		      withDeviceDescription:devDesc];
    if (ret != IO_R_SUCCESS) {
	IOLog("Pro1000: getPCIConfigSpace failed, ret %d\n", (int)ret);
	return nil;
    }

    /*
     * Check the vendor as well as the device. The config tables already
     * match on vendor+device, so this should never fire - but the chip
     * table is keyed on device ID alone, and another vendor reusing one
     * of these IDs would otherwise be driven as if it were an Intel
     * part.
     */
    if (config.VendorID != PRO1000_VENDOR) {
	IOLog("Pro1000: vendor %04x is not Intel\n",
	      (unsigned int)config.VendorID);
	return nil;
    }

    chip = chipLookup(config.DeviceID);
    if (chip == (ChipInfo *)0) {
	IOLog("Pro1000: device %04x is not a supported 8254x\n",
	      (unsigned int)config.DeviceID);
	return nil;
    }

    /*
     * Fiber and SerDes parts negotiate the link through the MAC's own
     * clause 37 PCS (SDM 8.6), not through an internal PHY as the
     * copper parts do (SDM 8.5). This driver only implements the copper
     * path, so refuse rather than bring the card half-up: a link that
     * never comes up is easier to diagnose than one that appears to
     * work and drops frames.
     */
    if (chip->quirks & Q_FIBER) {
	IOLog("Pro1000: %s is a fiber/SerDes part - not supported"
	      " (this driver implements the copper path only)\n",
	      chip->name);
	return nil;
    }

    IOLog("Pro1000: %s [%04x:%04x]%s\n", chip->name,
	  (unsigned int)config.VendorID, (unsigned int)config.DeviceID,
	  (config.DeviceID == 0x1019) ? "" : "  [UNVERIFIED PART]");

    /*
     * Find the I/O window. Only the 82541 needs it (its global reset has
     * to be issued there), but locating it costs nothing.
     *
     * Which BAR carries I/O is not the same across the family, so the
     * BARs are scanned rather than assuming BAR2 - that assumption
     * happens to hold on the 82547EI in this machine and would be a
     * silent trap on a part where it does not.
     */
    ioBase = 0;
    for (i = 0; i < 6; i++) {
	unsigned long bar = config.BaseAddress[i];

	if ((bar & 1UL) == 0UL) {
	    continue;			/* memory BAR */
	}
	if ((bar & 0xFFFFFFFCUL) == 0UL) {
	    continue;			/* unassigned */
	}
	if ((bar & 0xFFFFFFFCUL) > 0xFFFFUL) {
	    continue;			/* beyond what inb/outl can reach */
	}
	ioBase = (unsigned short)(bar & 0xFFFCUL);
	break;
    }

    if (chip->quirks & Q_RESET_VIA_IO) {
	/*
	 * Refuse rather than guess. Issuing the reset through a window
	 * the BIOS never enabled would write to ports that are not this
	 * device's, and on hardware nobody here can test that is not a
	 * risk worth taking.
	 */
	if (ioBase == 0) {
	    IOLog("Pro1000: %s needs an I/O BAR for its reset but none"
		  " is assigned\n", chip->name);
	    return nil;
	}
	if ((config.Command & 0x0001) == 0) {
	    IOLog("Pro1000: %s needs I/O space decoding enabled"
		  " (PCI command 0x%04x)\n",
		  chip->name, (unsigned int)config.Command);
	    return nil;
	}
	IOLog("Pro1000: I/O window at 0x%04x (used for reset)\n",
	      (unsigned int)ioBase);
    }

    if (config.BaseAddress[0] & 1UL) {
	IOLog("Pro1000: BAR0 is an I/O BAR - expected memory\n");
	return nil;
    }
    regPhys = config.BaseAddress[0] & 0xFFFFFFF0UL;
    if (regPhys == 0) {
	IOLog("Pro1000: BAR0 not assigned\n");
	return nil;
    }

    virt = 0;
    ret = IOMapPhysicalIntoIOTask((unsigned)regPhys, PRO1000_REG_SIZE,
				  &virt);
    if (ret != IO_R_SUCCESS || virt == 0) {
	IOLog("Pro1000: cannot map BAR0 0x%x, ret %d\n",
	      (unsigned int)regPhys, (int)ret);
	return nil;
    }
    regBase = virt;

    IOLog("Pro1000: %04x:%04x at BAR0 0x%x -> 0x%x, config IRQ %d\n",
	  (unsigned int)config.VendorID, (unsigned int)config.DeviceID,
	  (unsigned int)regPhys, (unsigned int)regBase,
	  (int)config.InterruptLine);

    /*
     * What the framework thinks it has is what decides whether
     * interrupts are ever delivered - not what config space says. When
     * they stopped arriving, this was the first thing worth knowing.
     */
    {
	unsigned long eecd = regRead(regBase, E1000_EECD);

	IOLog("Pro1000: EECD 0x%08x - NVM %s, type %s\n",
	      (unsigned int)eecd,
	      (eecd & E1000_EECD_PRES) ? "present" : "ABSENT",
	      (eecd & E1000_EECD_TYPE) ? "SPI" : "Microwire");
    }

    /* Reported on the summary line at the end of -resetAndEnable:; a
     * count of zero there is the signature of a missing "IRQ Levels". */
    irqCount = [devDesc numInterrupts];

    /*
     * Reset before reading the station address: the hardware reloads
     * receive address 0 from NVM as part of the reset, so what is read
     * afterwards is known to have come from the card rather than from
     * whatever the BIOS happened to leave behind.
     */
    pro1000Quiesce(regBase);
    {
	unsigned long ctrl = regRead(regBase, E1000_CTRL);

	if (chip->quirks & Q_PHY_RESET_FIRST) {
	    pro1000PhyReset(regBase, ctrl);
	}
	pro1000MacReset(regBase, ctrl, chip->quirks, ioBase);
    }

    readStationAddress(regBase, mac, &valid);
    if (!valid) {
	IOLog("Pro1000: station address not valid after reset\n");
	IOUnmapPhysicalFromIOTask(regBase, PRO1000_REG_SIZE);
	return nil;
    }
    for (i = 0; i < 6; i++) {
	myAddress.ether_addr_octet[i] = mac[i];
    }
    logMac("station address", mac, valid);

    /* --- DMA rings ----------------------------------------------- */

    rxRingAlloc = 0;
    txRingAlloc = 0;
    for (i = 0; i < NTXDESC; i++) {
	txBufAllocs[i] = 0;
	txBufs[i] = 0;
	txBufPhys[i] = 0;
    }
    for (i = 0; i < NRXDESC; i++) {
	rxBufAllocs[i] = 0;
	rxBufs[i] = 0;
	rxBufPhys[i] = 0;
    }

    if (!rxAlloc(&rxRingAlloc, &rxRing, &rxRingPhys,
		 rxBufAllocs, rxBufs, rxBufPhys)) {
	IOLog("Pro1000: RX ring allocation failed\n");
	rxFree(rxRingAlloc, rxBufAllocs);
	IOUnmapPhysicalFromIOTask(regBase, PRO1000_REG_SIZE);
	return nil;
    }

    txRing = allocDmaBlock(TXDESC_BYTES, &txRingAlloc, &txRingPhys);
    if (txRing == 0 || (txRingPhys & 0x0FUL) != 0) {
	IOLog("Pro1000: TX ring allocation failed\n");
	[self free];
	return nil;
    }

    /*
     * One buffer per descriptor. Sharing a single buffer across the
     * ring limited the driver to one frame in flight - a second send
     * would have overwritten a frame the hardware was still reading.
     */
    for (i = 0; i < NTXDESC; i++) {
	txBufs[i] = allocDmaBlock(TXBUF_SIZE, &txBufAllocs[i],
				  &txBufPhys[i]);
	if (txBufs[i] == 0) {
	    IOLog("Pro1000: TX buffer %d allocation failed\n", i);
	    [self free];
	    return nil;
	}
    }

    rxNext      = 0;
    txTimeouts  = 0;
    mcastCount  = 0;
    mcastMode   = NO;
    promiscMode = NO;

    /*
     * Bring the link up here, where blocking is allowed. By the time
     * the stack calls -resetAndEnable:YES the PHY has usually finished
     * negotiating, so that path never has to wait.
     */
    (void)pro1000SetupLink(regBase);
    reportLink(regBase, "after init:");

    transmitQueue = [[IONetbufQueue alloc] initWithMaxCount:32];
    network = [super attachToNetworkWithAddress:myAddress];

    IOLog("Pro1000: attached to network stack\n");
    return self;
}

- free
{
    if ([self isRunning]) {
	[self resetAndEnable:NO];
    }
    if (transmitQueue != nil) {
	[transmitQueue free];
	transmitQueue = nil;
    }

    rxFree(rxRingAlloc, rxBufAllocs);
    rxRingAlloc = 0;
    {
	int i;

	for (i = 0; i < NTXDESC; i++) {
	    if (txBufAllocs[i] != 0) {
		IOFree((void *)txBufAllocs[i], TXBUF_SIZE * 2);
		txBufAllocs[i] = 0;
	    }
	}
    }
    if (txRingAlloc != 0) {
	IOFree((void *)txRingAlloc, TXDESC_BYTES * 2);
	txRingAlloc = 0;
    }
    if (regBase != 0) {
	IOUnmapPhysicalFromIOTask(regBase, PRO1000_REG_SIZE);
	regBase = 0;
    }
    return [super free];
}

/*
 * Called by the framework to bring the hardware up and down. Everything
 * here has already been proven by the staged harness above; the only new
 * part is that the rings stay programmed instead of being torn down at
 * the end.
 */
- (BOOL)resetAndEnable:(BOOL)enable
{
    unsigned long rctl, tctl;
    int i;

    /*
     * This runs in the network stack's context (an ifconfig ioctl), so
     * it must not sleep. The full device reset - which needs a
     * mandatory 1.2 s settle - is done once in
     * -initFromDeviceDescription:, where blocking is safe. Here we only
     * stop the engines, reprogram the rings, and ask for link; the PHY
     * negotiates on its own and reports back through LSC.
     *
     * Doing it the other way round hung the machine: a multi-second
     * IOSleep on this path never returns to a usable system.
     */
    [self disableAllInterrupts];
    [self setRunning:NO];

    regWrite(regBase, E1000_RCTL, 0UL);
    regWrite(regBase, E1000_TCTL, 0UL);
    regFlush(regBase);
    IODelay(1000);		/* busy-wait 1 ms - safe at any SPL */

    if (!enable) {
	return YES;
    }

    /* RX ring */
    for (i = 0; i < NRXDESC; i++) {
	RxDesc *r = &((RxDesc *)rxRing)[i];

	r->bufferAddrLow  = rxBufPhys[i];
	r->bufferAddrHigh = 0UL;
	r->length	  = 0;
	r->checksum	  = 0;
	r->status	  = 0;
	r->errors	  = 0;
	r->special	  = 0;
    }
    rxNext = 0;
    regWrite(regBase, E1000_RDBAL, rxRingPhys);
    regWrite(regBase, E1000_RDBAH, 0UL);
    regWrite(regBase, E1000_RDLEN, (unsigned long)RXDESC_BYTES);
    regWrite(regBase, E1000_RDH, 0UL);
    regWrite(regBase, E1000_RDT, (unsigned long)(NRXDESC - 1));

    /* TX ring */
    for (i = 0; i < NTXDESC; i++) {
	TxDesc *t = &((TxDesc *)txRing)[i];

	t->bufferAddrLow  = 0UL;
	t->bufferAddrHigh = 0UL;
	t->length	  = 0;
	t->cso		  = 0;
	t->cmd		  = 0;
	t->status	  = 0;
	t->css		  = 0;
	t->special	  = 0;
    }
    regWrite(regBase, E1000_TDBAL, txRingPhys);
    regWrite(regBase, E1000_TDBAH, 0UL);
    regWrite(regBase, E1000_TDLEN, (unsigned long)TXDESC_BYTES);
    regWrite(regBase, E1000_TDH, 0UL);
    regWrite(regBase, E1000_TDT, 0UL);
    regWrite(regBase, E1000_TIPG, E1000_TIPG_COPPER);
    txDone = 0;

    /* Before the engines start, as the SDM requires - the counters
     * power up holding unknown values. */
    [self _clearStatistics];

    pro1000RequestLink(regBase);

    tctl = E1000_TCTL_EN | E1000_TCTL_PSP
	 | (0x0FUL << E1000_TCTL_CT_SHIFT)
	 | (0x40UL << E1000_TCTL_COLD_SHIFT);
    regWrite(regBase, E1000_TCTL, tctl);

    rctl = E1000_RCTL_EN | E1000_RCTL_BAM | E1000_RCTL_SZ_2048
	 | E1000_RCTL_SECRC;
    regWrite(regBase, E1000_RCTL, rctl);
    regFlush(regBase);

    if ([self enableAllInterrupts] != IO_R_SUCCESS) {
	IOLog("Pro1000: enableAllInterrupts failed\n");
	[self setRunning:NO];
	return NO;
    }

    /*
     * The framework tracks enablement through -setRunning:, not through
     * a flag of our own. Leaving this out means the stack never
     * considers the interface live, which is exactly what happened the
     * first time: en1 appeared but nothing ever ran.
     */
    [self setRunning:YES];

    /*
     * Carry the identity on this line, not only on the one +probe:
     * prints.
     *
     * At boot the driver is loaded from /etc/rc before syslogd is
     * running, and syslogd only captures from wherever it attaches -
     * the text has been seen starting mid-word. Which boot lines
     * survive is therefore a matter of timing, and a boot where none
     * of them do has been observed. Carrying the identity here at
     * least gives it every chance: this line is also printed whenever
     * the interface is re-enabled, long after syslogd is up.
     */
    linkUp = (regRead(regBase, E1000_STATUS) & E1000_STATUS_LU) ? YES : NO;

    IOLog("Pro1000: %s enabled%s, %d irq, RCTL 0x%08x TCTL 0x%08x"
	  " STATUS 0x%08x\n",
	  chip->name,
	  (chip->device == 0x1019) ? "" : " [UNVERIFIED PART]",
	  irqCount,
	  (unsigned int)regRead(regBase, E1000_RCTL),
	  (unsigned int)regRead(regBase, E1000_TCTL),
	  (unsigned int)regRead(regBase, E1000_STATUS));
    return YES;
}

- (IOReturn)enableAllInterrupts
{
    /*
     * The 82547GI/EI needs IMS and IMC cleared before the mask is
     * asserted. This is not a general 8254x step - it is specific to
     * this part, and the SDM (13.4.20 / 13.4.21) is explicit about why:
     *
     *   "For the 82547GI/EI, programmers need to first write (clear)
     *    the IMS and IMC registers due to a Hub Link bus being
     *    occupied. This results in an interrupt de-assertion message
     *    that can't to be sent out. When a future interrupt assertion
     *    message is generated, two messages are re-ordered and sent
     *    out. This signals APIC that the 82547GI/EI is in a de-asserted
     *    state when it is actually in an asserted state, which causes a
     *    system dead lock. To avoid a system dead lock, first clear the
     *    IMS and IMC registers by writing FFFFh and then re-assert IRQ
     *    enable."
     *
     * This part signals interrupts as CSA hub-interface messages rather
     * than over a pin, which is why message ordering can strand the
     * APIC in the wrong state. Omitting it gave exactly the documented
     * outcome here: the first interrupt arrived, none ever followed,
     * and the machine eventually locked up.
     */
    [self _rearmInterrupts];
    return [super enableAllInterrupts];
}

/*
 * The IMS/IMC re-assert sequence, applied every time interrupts are
 * (re-)enabled - which on this part means after every interrupt, not
 * just at startup.
 *
 * Measured: with this done only once at enable time, the first
 * interrupt arrived and nothing followed. A transmit completed in
 * hardware (TDH reached TDT) with no interrupt for three seconds; the
 * moment a reset re-enabled interrupts, the pending causes arrived all
 * at once as ICR 0x83 (TXDW|TXQE|RXT0). The interrupt was raised and
 * stranded, exactly the state the SDM describes.
 */
- (void)_rearmInterrupts
{
    if (chip->quirks & Q_HUB_IMS) {
	regWrite(regBase, E1000_IMS, 0xFFFFUL);
	regWrite(regBase, E1000_IMC, 0xFFFFUL);
	regFlush(regBase);
    }

    /*
     * TXQE as well as TXDW. The SDM defines TXQE as "all descriptors
     * have been processed - head equals tail", and Minix's e1000 driver
     * treats the two as interchangeable:
     *
     *     if (cause & (E1000_REG_ICR_TXQE | E1000_REG_ICR_TXDW))
     *             netdriver_send();
     *
     * TXDW alone is the precise per-descriptor signal; TXQE is kept as
     * a backstop.
     */
    regWrite(regBase, E1000_IMS,
	     E1000_ICR_RXT0 | E1000_ICR_RXDMT0
	     | E1000_ICR_RXO | E1000_ICR_RXSEQ
	     | E1000_ICR_TXDW | E1000_ICR_TXQE
	     | E1000_ICR_LSC);
    regFlush(regBase);
}

- (void)disableAllInterrupts
{
    if (regBase != 0) {
	regWrite(regBase, E1000_IMC, 0xFFFFFFFFUL);
	regFlush(regBase);
    }
    [super disableAllInterrupts];
}

/*
 * Read every statistics register once, discarding the values.
 *
 * The SDM requires this: the counters are not hardware initialised,
 * their value after reset is unknown, and "software should read the
 * contents of all registers in order to clear them prior to enabling
 * the receive and transmit channels". Skipping it makes the first
 * harvest report power-on garbage as errors.
 */
- (void)_clearStatistics
{
    static const int stats[] = {
	E1000_CRCERRS, E1000_ALGNERRC, E1000_RXERRC, E1000_MPC,
	E1000_SCC,     E1000_ECOL,     E1000_MCC,    E1000_LATECOL,
	E1000_COLC,    E1000_DC,       E1000_TNCRS,  E1000_SEC,
	E1000_CEXTERR, E1000_RLEC,     E1000_RNBC,   E1000_RUC,
	E1000_RFC,     E1000_ROC,      E1000_RJC
    };
    int i;

    for (i = 0; i < (int)(sizeof(stats) / sizeof(stats[0])); i++) {
	(void)regRead(regBase, stats[i]);
    }

    rxMissed	    = 0UL;
    rxNoBuffer	    = 0UL;
    rxOverruns	    = 0UL;
    irqSinceHarvest = 0;
}

/*
 * Fold the hardware's error counters into the interface statistics that
 * `netstat -i' shows.
 *
 * Only the counters that describe frames the driver cannot otherwise
 * see are taken:
 *
 *   MPC  - the receive FIFO was full, so the frame never reached a
 *          descriptor at all
 *   RNBC - a frame arrived while head and tail were equal, meaning the
 *          ring was out of descriptors
 *
 * CRCERRS, RLEC and RXERRC are deliberately *not* added. Those frames
 * do reach a descriptor, where -_serviceReceive already counts them
 * from the error byte; adding the registers as well would report every
 * such frame twice.
 */
- (void)_harvestStatistics
{
    unsigned long missed, noBuffer, collisions;

    if (regBase == 0) {
	return;
    }

    missed	= regRead(regBase, E1000_MPC);
    noBuffer	= regRead(regBase, E1000_RNBC);
    collisions	= regRead(regBase, E1000_COLC);

    rxMissed   += missed;
    rxNoBuffer += noBuffer;
    irqSinceHarvest = 0;

    if (network == nil) {
	return;
    }

    if (missed != 0UL || noBuffer != 0UL) {
	[network incrementInputErrorsBy:(unsigned)(missed + noBuffer)];
    }
    if (collisions != 0UL) {
	[network incrementCollisionsBy:(unsigned)collisions];
    }
}

/*
 * Inspect the transmit descriptors the hardware has finished with.
 *
 * Completion alone was never checked before: the driver only cancelled
 * its watchdog and moved on, so a frame the hardware gave up on - too
 * many collisions, a late collision, a FIFO underrun - was
 * indistinguishable from one that went out cleanly.
 *
 * The descriptors carry that verdict because CMD_RS is set on every
 * one, which asks the hardware to write status back.
 */
- (void)_reapTransmit
{
    TxDesc *ring = (TxDesc *)txRing;
    int	    head;
    int	    guard = NTXDESC;

    head = (int)regRead(regBase, E1000_TDH);

    /*
     * A device that has stopped responding reads back as all-ones, and
     * this runs in the interrupt handler: walking towards a head of
     * 0xFFFFFFFF would spin forever with interrupts off, which on this
     * machine means it never comes back. Range-check before trusting
     * it, and bound the loop as well - the ring cannot need more than
     * NTXDESC steps, so anything more means the state is wrong.
     */
    if (head < 0 || head >= NTXDESC) {
	return;
    }

    while (txDone != head && guard-- > 0) {
	unsigned char status = ring[txDone].status;

	if ((status & E1000_TXD_STAT_DD)
	    && (status & E1000_TXD_STAT_FAIL)) {
	    txFailed++;
	    if (network != nil) {
		[network incrementOutputErrors];
	    }
	    if (logMilestone(txFailed)) {
		IOLog("Pro1000: transmit error, status 0x%02x (%s%s%s),"
		      " %d so far\n",
		      (unsigned int)status,
		      (status & E1000_TXD_STAT_EC) ? "excess collisions " : "",
		      (status & E1000_TXD_STAT_LC) ? "late collision " : "",
		      (status & E1000_TXD_STAT_TU) ? "underrun" : "",
		      (int)txFailed);
	    }
	}

	ring[txDone].status = 0;
	txDone = (txDone + 1) % NTXDESC;
    }
}

/*
 * Move every completed receive descriptor up the stack and hand it back
 * to the hardware.
 */
- (void)_serviceReceive
{
    RxDesc *ring = (RxDesc *)rxRing;
    int     budget = NRXDESC * 4;

    /*
     * Bounded on purpose. An unbounded "drain until empty" loop can be
     * refilled by the hardware as fast as it is emptied, and on a busy
     * segment that never returns. Whatever is left is picked up by the
     * next interrupt.
     */
    /*
     * Only DD is examined, not EOP. A frame can only span descriptors
     * if it exceeds the 2 KB buffer, and RCTL.LPE is off - the hardware
     * rejects anything longer than a standard frame before it reaches
     * the ring. So a descriptor that is done holds a whole packet.
     */
    while (budget-- > 0 && (ring[rxNext].status & E1000_RXD_STAT_DD)) {
	unsigned int length = (unsigned int)ring[rxNext].length;
	netbuf_t     pkt    = NULL;

	if ((ring[rxNext].errors & E1000_RXD_ERR_FRAME) != 0
	    || length < 14 || length > RXBUF_SIZE) {
	    /*
	     * A frame the hardware marked bad, or one whose length
	     * cannot be right. Counted here rather than from CRCERRS
	     * and friends so that each bad frame is reported once.
	     */
	    rxBadFrames++;
	    if (network != nil) {
		[network incrementInputErrors];
	    }
	    if (logMilestone(rxBadFrames)) {
		IOLog("Pro1000: receive error, errors 0x%02x length %d,"
		      " %d so far\n",
		      (unsigned int)ring[rxNext].errors, (int)length,
		      (int)rxBadFrames);
	    }
	} else {
	    pkt = nb_alloc(length);
	    if (pkt == NULL) {
		/*
		 * Out of netbufs. The descriptor is still returned
		 * below - starving the hardware of descriptors on top
		 * of a memory shortage would turn a transient problem
		 * into a stalled receiver.
		 */
		rxNoMbufs++;
		if (network != nil) {
		    [network incrementInputErrors];
		}
		if (logMilestone(rxNoMbufs)) {
		    IOLog("Pro1000: no netbuf for a %d byte frame,"
			  " %d dropped so far\n",
			  (int)length, (int)rxNoMbufs);
		}
	    } else {
		IOCopyMemory((void *)rxBufs[rxNext], nb_map(pkt),
			     length, 1);
	    }
	}

	/* Return the descriptor before doing anything that can block:
	 * the ring is small and the hardware should never be left
	 * waiting on us. */
	ring[rxNext].status = 0;
	ring[rxNext].errors = 0;
	regWrite(regBase, E1000_RDT, (unsigned long)rxNext);
	rxNext = (rxNext + 1) % NRXDESC;

	if (pkt != NULL) {
	    /*
	     * The MTA is a hash, so two groups can share a bit and a
	     * frame can get through the hardware filter without actually
	     * being wanted. The superclass does the exact-match check.
	     */
	    if ([super isUnwantedMulticastPacket:
			   (ether_header_t *)nb_map(pkt)]) {
		nb_free(pkt);
	    } else {
		[network handleInputPacket:pkt extra:0];
	    }
	}
    }
}

- (void)interruptOccurred
{
    static BOOL	  nLogged = NO;
    unsigned long cause;

    /*
     * Service until the device reports nothing more, the way SMC16's
     * handler does. A cause raised while we are already inside would
     * otherwise sit unserviced waiting for a next interrupt that may
     * never come. Reading ICR clears it, so the loop terminates as soon
     * as the device is quiet.
     */
    do {
	cause = regRead(regBase, E1000_ICR);

	/*
	 * One line for the first interrupt, as proof that delivery
	 * works at all. Anything more floods the log under load; when
	 * delivery itself was in question this logged the first twelve
	 * with their causes, which is what identified the problem.
	 */
	if (!nLogged) {
	    nLogged = YES;
	    IOLog("Pro1000: interrupts flowing, first ICR 0x%08x\n",
		  (unsigned int)cause);
	}

	if (cause == 0UL) {
	    break;
	}

	if (cause & (E1000_ICR_RXT0 | E1000_ICR_RXDMT0)) {
	    [self _serviceReceive];
	}

	/*
	 * Receiver overrun: frames arrived faster than the ring could
	 * be drained, or the FIFO filled because the bus could not keep
	 * up. The hardware recovers by itself as soon as descriptors
	 * become free - servicing the ring above is that recovery - so
	 * there is nothing to reset here. What was missing was any
	 * record that it happened at all.
	 *
	 * MPC and RNBC say how many frames were lost, so harvest them
	 * now rather than waiting for the periodic sweep.
	 */
	if (cause & (E1000_ICR_RXO | E1000_ICR_RXSEQ)) {
	    [self _serviceReceive];
	    [self _harvestStatistics];

	    rxOverruns++;
	    if (logMilestone(rxOverruns)) {
		/*
		 * The interface's own error count is echoed back so the
		 * log shows what the rest of the system sees, not just
		 * what this driver believes. They should track.
		 */
		IOLog("Pro1000: receive overrun %d (ICR 0x%08x),"
		      " %d missed %d without a descriptor, if errors %d\n",
		      (int)rxOverruns, (unsigned int)cause,
		      (int)rxMissed, (int)rxNoBuffer,
		      (network != nil) ? (int)[network inputErrors] : -1);
	    }
	}

	if (cause & (E1000_ICR_TXDW | E1000_ICR_TXQE)) {
	    netbuf_t queued;

	    [self _reapTransmit];

	    /*
	     * Cancel the watchdog armed by -transmit:. Leaving it
	     * running meant every successful transmit still timed out
	     * three seconds later, and each timeout reset the device -
	     * a loop that looked like broken transmit when the hardware
	     * had in fact sent every frame (TDH always reached TDT).
	     */
	    [self clearTimeout];
	    txTimeouts = 0;

	    queued = [transmitQueue dequeue];
	    if (queued != NULL) {
		[self transmit:queued];
	    }
	}

	/*
	 * Link status change.
	 *
	 * The SDM says "indication that the link is not up disables MAC
	 * operation", which reads as though transmits would stop
	 * completing. Measured, they do not: over a two-minute unplug
	 * with TCP retransmitting throughout, the watchdog in
	 * -timeoutOccurred never fired once. The descriptor engine goes
	 * on completing descriptors without a carrier and the frames are
	 * simply lost on the wire.
	 *
	 * Speed and duplex need no programming of ours. CTRL.SLU|ASDE
	 * was set at enable time, and auto-speed detection makes the
	 * MAC follow whatever the PHY negotiated; we only read the
	 * result back to report it.
	 */
	if (cause & E1000_ICR_LSC) {
	    unsigned long status = regRead(regBase, E1000_STATUS);
	    BOOL	  nowUp  = (status & E1000_STATUS_LU) ? YES : NO;

	    if (nowUp != linkUp) {
		linkUp = nowUp;

		if (nowUp) {
		    netbuf_t pending;

		    /*
		     * Carrier is back. Any watchdogs that fired while
		     * it was gone were expected and must not count
		     * towards the give-up threshold, so clear them, and
		     * push whatever queued up behind the outage.
		     */
		    txTimeouts = 0;
		    [self clearTimeout];
		    reportLink(regBase, "carrier back -");

		    pending = [transmitQueue dequeue];
		    if (pending != NULL) {
			[self transmit:pending];
		    }
		} else {
		    IOLog("Pro1000: link down - carrier lost,"
			  " frames sent from now on go nowhere\n");
		}
	    }
	}
    } while (cause != 0UL);

    /*
     * Periodic sweep. The statistics registers stick at 0xFFFFFFFF
     * instead of wrapping, so they have to be read long before they can
     * get there; on the other hand reading nineteen registers on every
     * interrupt would be a real cost at gigabit rates. Every 4096
     * interrupts is far more often than any counter could saturate and
     * cheap enough to disappear into the noise.
     */
    if (++irqSinceHarvest >= 4096) {
	[self _harvestStatistics];
    }

    /*
     * Re-enable at the framework level, not just in IMS.
     *
     * Measured: after a transmit, TXDW was set in the device but no
     * interrupt was delivered for three seconds. It arrived the instant
     * -resetAndEnable: ran, and the only thing that does which this
     * handler did not is [super disableAllInterrupts] followed by
     * [super enableAllInterrupts]. Re-asserting IMS alone was not
     * enough - tried, same three-second gap - so the state that needs
     * clearing is the framework's IRQ, not the device's mask.
     */
    [self disableAllInterrupts];
    [self enableAllInterrupts];
}

- (void)transmit:(netbuf_t)pkt
{
    TxDesc      *ring = (TxDesc *)txRing;
    unsigned int length;
    int          head, tail, next;

    if (![self isRunning]) {
	nb_free(pkt);
	return;
    }

    /*
     * Ring state comes from the hardware pointers, the way Minix's
     * driver does it: the queue is full when advancing the tail would
     * make it equal the head, because that value means empty.
     *
     * Each descriptor has its own buffer, so several frames may be in
     * flight at once - which is what lets the ring actually pipeline
     * rather than serialising on a single shared buffer.
     */
    head = (int)regRead(regBase, E1000_TDH);
    tail = (int)regRead(regBase, E1000_TDT);
    next = (tail + 1) % NTXDESC;

    if (next == head) {
	/*
	 * IONetbufQueue frees the netbuf "without notice" once maxCount
	 * is reached - its own header says so. Notice it here, or a
	 * host that outruns the ring loses frames with nothing to show
	 * for it.
	 */
	if ([transmitQueue count] >= [transmitQueue maxCount]) {
	    txDropped++;
	    if (network != nil) {
		[network incrementOutputErrors];
	    }
	    if (logMilestone(txDropped)) {
		IOLog("Pro1000: transmit queue full, %d frames dropped\n",
		      (int)txDropped);
	    }
	}
	[transmitQueue enqueue:pkt];
	return;
    }

    length = nb_size(pkt);
    if (length > TXBUF_SIZE) {
	txDropped++;
	if (network != nil) {
	    [network incrementOutputErrors];
	}
	nb_free(pkt);
	return;
    }

    [self performLoopback:pkt];
    IOCopyMemory(nb_map(pkt), (void *)txBufs[tail], length, 4);
    nb_free(pkt);

    ring[tail].bufferAddrLow  = txBufPhys[tail];
    ring[tail].bufferAddrHigh = 0UL;
    ring[tail].length	      = (unsigned short)length;
    ring[tail].cso	      = 0;
    ring[tail].cmd	      = E1000_TXD_CMD_EOP | E1000_TXD_CMD_IFCS
			      | E1000_TXD_CMD_RS;
    ring[tail].status	      = 0;
    ring[tail].css	      = 0;
    ring[tail].special	      = 0;

    /*
     * Arm the watchdog before starting the transfer, not after. A
     * 60-byte frame at gigabit is on the wire in well under a
     * microsecond, so the completion interrupt can beat the arming
     * call - and then the timeout it was meant to cancel is set
     * afterwards and fires on a transmit that succeeded.
     */
    [self setRelativeTimeout:3000];

    regWrite(regBase, E1000_TDT, (unsigned long)next);
}

- (void)_writeMulticastTable
{
    unsigned long shadow[MTA_REGS];
    unsigned long hash;
    int i, reg, bit;

    for (i = 0; i < MTA_REGS; i++) {
	shadow[i] = 0UL;
    }

    for (i = 0; i < mcastCount; i++) {
	hash = mcastHash((unsigned char *)mcast[i].ether_addr_octet);
	reg  = (int)((hash >> 5) & (unsigned long)(MTA_REGS - 1));
	bit  = (int)(hash & 0x1FUL);
	shadow[reg] |= (1UL << bit);
    }

    for (i = 0; i < MTA_REGS; i++) {
	regWrite(regBase, E1000_MTA + (unsigned int)(i * 4), shadow[i]);
    }
    regFlush(regBase);
}

/*
 * Apply promiscuous / multicast state to RCTL without disturbing the
 * rest of the register.
 */
- (void)_applyReceiveFilter
{
    unsigned long rctl;

    rctl = regRead(regBase, E1000_RCTL);
    rctl &= ~(E1000_RCTL_UPE | E1000_RCTL_MPE);

    if (promiscMode) {
	rctl |= (E1000_RCTL_UPE | E1000_RCTL_MPE);
    } else if (mcastMode && mcastCount == 0) {
	/*
	 * Multicast wanted but no specific addresses registered: accept
	 * all of it rather than none. An empty hash table would drop
	 * every multicast frame, which is not what "multicast mode" is
	 * asking for.
	 */
	rctl |= E1000_RCTL_MPE;
    }

    regWrite(regBase, E1000_RCTL, rctl);
    regFlush(regBase);
}

- (BOOL)enablePromiscuousMode
{
    promiscMode = YES;
    [self _applyReceiveFilter];
    IOLog("Pro1000: promiscuous mode on\n");
    return YES;
}

- (void)disablePromiscuousMode
{
    promiscMode = NO;
    [self _applyReceiveFilter];
    IOLog("Pro1000: promiscuous mode off\n");
}

- (BOOL)enableMulticastMode
{
    mcastMode = YES;
    [self _applyReceiveFilter];
    return YES;
}

- (void)disableMulticastMode
{
    mcastMode = NO;
    [self _applyReceiveFilter];
}

- (void)addMulticastAddress:(enet_addr_t *)address
{
    int i;

    for (i = 0; i < mcastCount; i++) {
	if (memcmp((char *)mcast[i].ether_addr_octet,
		   (char *)address->ether_addr_octet, 6) == 0) {
	    return;			/* already known */
	}
    }

    if (mcastCount >= MAX_MCAST) {
	/*
	 * Out of room. Accepting all multicast is wrong-but-working;
	 * silently dropping the address would lose frames the stack
	 * expects.
	 */
	IOLog("Pro1000: multicast list full (%d) - accepting all\n",
	      MAX_MCAST);
	mcastMode = YES;
	mcastCount = 0;
	[self _applyReceiveFilter];
	return;
    }

    memcpy((char *)mcast[mcastCount].ether_addr_octet,
	   (char *)address->ether_addr_octet, 6);
    mcastCount++;

    [self _writeMulticastTable];
    [self _applyReceiveFilter];
}

- (void)removeMulticastAddress:(enet_addr_t *)address
{
    int i, j;

    for (i = 0; i < mcastCount; i++) {
	if (memcmp((char *)mcast[i].ether_addr_octet,
		   (char *)address->ether_addr_octet, 6) == 0) {
	    for (j = i; j < mcastCount - 1; j++) {
		memcpy((char *)mcast[j].ether_addr_octet,
		       (char *)mcast[j + 1].ether_addr_octet, 6);
	    }
	    mcastCount--;
	    [self _writeMulticastTable];
	    [self _applyReceiveFilter];
	    return;
	}
    }
}

/*
 * A transmit timeout normally means one frame was lost and a reset gets
 * things moving again. But if the completion interrupt never arrives at
 * all, every frame times out, and resetting on each one turns into a
 * loop that resets the device forever - which is what wedged this
 * machine. So give up after a few and say why, instead.
 */
- (void)timeoutOccurred
{
    unsigned long status = regRead(regBase, E1000_STATUS);

    /*
     * A transmit that has not completed because there is no cable in
     * the socket is not a fault. Treating it as one would reach the
     * give-up path below, which disables interrupts - including the
     * link-status interrupt that reports the cable being plugged back
     * in - and the port would stay dead until the machine was rebooted.
     *
     * Measured, and it corrects what the SDM's "indication that the
     * link is not up disables MAC operation" suggests: with the cable
     * out for two minutes and TCP retransmitting throughout, this
     * watchdog never fired once. The descriptor engine keeps consuming
     * and writing back descriptors with no carrier - the frames are
     * simply lost on the wire - so TXDW still arrives. The guard below
     * is therefore defensive rather than a fix for something observed.
     *
     * The register is read fresh rather than trusting the cached flag,
     * because the watchdog can fire before the LSC interrupt for the
     * same event has been serviced.
     */
    if (!(status & E1000_STATUS_LU)) {
	linkUp = NO;
	txLinkStalls++;
	if (logMilestone(txLinkStalls)) {
	    IOLog("Pro1000: transmit stalled with no link (%d),"
		  " waiting for carrier\n", (int)txLinkStalls);
	}
	return;
    }

    IOLog("Pro1000: transmit timeout %d, TDH %d TDT %d STATUS 0x%08x\n",
	  txTimeouts + 1,
	  (int)regRead(regBase, E1000_TDH),
	  (int)regRead(regBase, E1000_TDT),
	  (unsigned int)status);

    if (++txTimeouts >= MAX_TX_TIMEOUTS) {
	IOLog("Pro1000: %d consecutive timeouts - stopping. Transmit"
	      " completes in hardware (TDH reaches TDT) but the TXDW"
	      " interrupt never arrives.\n", txTimeouts);
	[self disableAllInterrupts];
	[self setRunning:NO];
	while ([transmitQueue count] > 0) {
	    nb_free([transmitQueue dequeue]);
	}
	return;
    }

    [self resetAndEnable:YES];
}

@end
