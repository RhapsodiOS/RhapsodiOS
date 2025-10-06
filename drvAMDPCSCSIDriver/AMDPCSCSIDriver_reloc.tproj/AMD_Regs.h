/* 	Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved. 
 *
 * AMD_Regs.h - register defintions for AMD 53C974/79C974 SCSI/PCI chip.
 *
 * HISTORY
 * 21 Oct 94    Doug Mitchell at NeXT
 *      Created. 
 */

#import "ioPorts.h"

#define AMD_PCI_REGISTER_SPACE		0x60
#define AMD_PCI_REGISTER_OFFSET		0	/* FIXME */

/*
 * SCSI registers. All are byte-wide.
 */
#define currXfrCntLow		0x00 		// r/o
#define startXfrCntLow		0x00		// w/o
#define currXfrCntMid		0x04 		// r/o
#define	startXfrCntMid		0x04 		// w/o
#define scsiFifo		0x08 		// r/w
#define scsiCmd			0x0c 		// r/w
#define scsiStat		0x10 		// r/o
#define scsiDestID		0x10 		// w/o
#define intrStatus		0x14 		// r/o
#define scsiTimeout		0x14 		// w/o
#define internState		0x18 		// r/o
#define syncPeriod		0x18 		// w/o
#define currFifoState		0x1c 		// r/o
#define syncOffset		0x1c 		// w/o
#define control1		0x20 		// r/w
#define clockFactor		0x24 		// w/o
#define control2		0x2c 		// r/w
#define control3		0x30 		// r/w
#define control4		0x34 		// r/w
#define currXfrCntHi		0x38 		// r/o
#define startXfrCntHi		0x38 		// w/o
	
/*
 * Macros for reading and writing SCSI registers.
 * These assume the presence of a local or instance variable ioBase. 
 */
#define REG_PORT(reg) 		(ioBase + reg) 	
#define READ_REG(reg) 		inb(REG_PORT(reg))
#define WRITE_REG(reg, data)	outb(REG_PORT(reg), data)

/* 
 * Miscellaneous commands.
 */
#define	SCMD_NOP		0x00	
#define	SCMD_CLEAR_FIFO		0x01
#define	SCMD_RESET_DEVICE	0x02
#define	SCMD_RESET_SCSI		0x03

/* 
 * idle state commands.
 */
#define	SCMD_SELECT		0x41	// select w/o ATN, cdb
#define	SCMD_SELECT_ATN		0x42	// select, ATN, 1 msg byte, cdb
#define	SCMD_SELECT_ATN_STOP	0x43	// select, ATN, 1 msg byte, stop
#define	SCMD_ENABLE_SELECT	0x44	// enable select/reselect 
#define	SCMD_DISABLE_SELECT	0x45	// disable select/reselect 
#define SCMD_SELECT_ATN_3	0x46	// select, ATN, 3 msg bytes, cdb	

/* 
 * initiator mode commands.
 */
#define	SCMD_TRANSFER_INFO	0x10	
#define	SCMD_INIT_CMD_CMPLT	0x11	
#define	SCMD_MSG_ACCEPTED	0x12	
#define	SCMD_TRANSFER_PAD	0x18	
#define	SCMD_SET_ATN		0x1a	
#define SCMD_CLR_ATN		0x1b

/* 
 * OR this with command to enable DMA.
 */
#define	SCMD_ENABLEDMA		0x80

/*
 * status register (scsiStat)
 */
#define SS_INTERRUPT		0x80	// interrupt pending
#define	SS_ILLEGALOP		0x40	// illegal operation
#define	SS_PARITYERROR		0x20	// SCSI bus parity error 
#define	SS_COUNTZERO		0x10	// transfer count == 0 
#define	SS_PHASEMASK		0x07	// SCSI bus phase mask 

/*
 * internal state register (internState)
 */
#define INS_SYNC_FULL		0x10	// sync offset buffer full
#define INS_STATE_MASK		0x07

/*
 * interrupt status register (intrStatus)
 */
#define	IS_SCSIRESET		0x80	// SCSI bus reset detected 
#define	IS_ILLEGALCMD		0x40	// illegal cmd issued 
#define	IS_DISCONNECT		0x20	// target disconnected 
#define	IS_SERVICE_REQ		0x10	
#define	IS_SUCCESSFUL_OP	0x08	
#define	IS_RESELECTED		0x04	// reselected as initiator 

/*
 * FIFO state register (currFifoState)
 */
#define FS_FIFO_LEVEL_MASK	0x1f

/*
 * Sync offset register (syncOffset)
 * We're not messing with these RAD/RAA bits just yet...
 */
#define SOR_RAD_MASK		0xc0	// req/ack deassertion
#define SOR_RAD_DEFAULT		0x00	
#define SOR_RAA_MASK		0x30	// req/ack assertion
#define SOR_RAA_DEFAULT		0x00

/*
 * Control register 1 (control1)
 */
#define CR1_EXTEND_TIMING	0x80	// extended timing mode
#define CR1_RESET_INTR_DIS	0x40	// disable SCSI reset interrupt
#define CR1_PERR_ENABLE		0x10	// enable parity error reporting
#define CR1_SCSI_ID		0x07	// SCSI ID bits

/*
 * Control register 2 (control2)
 */
#define CR2_ENABLE_FEAT		0x40	// enable extended features

/*
 * Control register 3 (control3)
 */
#define CR3_ADDL_ID_CHECK	0x80	// enable additional ID check
#define CR3_FAST_SCSI		0x10	// enable fast SCSI 
#define CR3_FAST_CLOCK		0x08	// fast clock

/*
 * Control register 4 (control4)
 */
#define CR4_GLITCH_MASK		0xc0	// glitch eater bits
#define CR4_GLITCH_12		0x00	// 12 ns
#define CR4_GLITCH_25		0x80	// 25 ns
#define CR4_GLITCH_35		0x40	// 35 ns
#define CR4_GLITCH_0		0xc0	// 0 ns
#define CR4_REDUCE_PWR		0x20	// reduced power mode
#define CR4_ACTIVE_NEG_MASK	0x0c	// active negation control bits
#define CR4_ACTIVE_NEG_DISABLE	0x00	// active negation disabled
#define CR4_ACTIVE_NEG_RA	0x08	// active negation on REQ and ACK
#define CR4_ACTIVE_NEG_ALL	0x04	// active negation on REQ, ACK, data

/*
 * DMA registers. All are 32 bits.
 */
#define dmaCommand		0x40		// r/w
#define dmaStartCount		0x44		// r/w
#define dmaStartAddrs		0x48		// r/w
#define dmaWorkByteCount	0x4c		// r/o
#define dmaWorkAddrs		0x50		// r/o
#define dmaStatus		0x54		// r/o
#define dmaStartMdlAddrs	0x58		// r/w
#define dmaWorkMdlAddrs		0x5c		// r/o

/*
 * Macros for reading and writing DMA registers.
 * These assume the presence of a local or instance variable ioBase. 
 */
#define READ_REGL(reg) 		inl(REG_PORT(reg))
#define WRITE_REGL(reg, data)	outl(REG_PORT(reg), data);

/*
 * DMA command register (dmaCommand)
 */
#define DC_DIR			0x80		// direction
#define DC_DIR_READ		0x80		// scsi --> memory
#define DC_DIR_WRITE		0x00		// scsi <-- memory
#define DC_INTR_ENABLE		0x40		// enable DMA interrupts
#define DC_PAGE_INTR_ENABLE	0x20		// enable per-page interrupts
#define DC_MDL			0x10		// enable MDL 
#define DC_DIAG			0x04		// diagnostic
#define DC_CMD_MASK		0x03		// command bits
#define DC_CMD_IDLE		0x00
#define DC_CMD_BLAST		0x01
#define DC_CMD_ABORT		0x02
#define DC_CMD_START		0x03

/*
 * DMA status register (dmaStatus)
 */
#define DS_BLAST_COMPLETE	0x20		// DMA Blast command complete
#define DS_SCSI_INTR		0x10		// SCSI interrupt pending
#define DS_DMA_COMPLETE		0x08		// DMA transfer complete
#define DS_ABORT		0x04		// DMA transfer aborted
#define DS_DMA_ERROR		0x02		// DMA error occurred
#define DS_POWER_DOWN		0x01		// power down pin state

/*
 * Misc. chip constants.
 */
#define AMD_DMA_PAGE_SIZE	0x1000
#define AMD_DMA_PAGE_MASK	0xfff
#define AMD_TRUNC_PAGE(x)	((vm_offset_t)(((vm_offset_t)(x)) & \
				    ~AMD_DMA_PAGE_MASK))
#define AMD_ROUND_PAGE(x)	((vm_offset_t)((((vm_offset_t)(x)) + \
				    AMD_DMA_PAGE_MASK) & ~AMD_DMA_PAGE_MASK))

/*
 * DMA alignment requirements.
 */
#define AMD_READ_START_ALIGN	4
#define AMD_WRITE_START_ALIGN	4
#define AMD_READ_LENGTH_ALIGN	0
#define AMD_WRITE_LENGTH_ALIGN	0

/*
 * We are ID 7, by convention.
 */
#define AMD_SCSI_ID		7

/*
 * Default clock rate, in MHz, in case it's not in the instance table.
 */
#define AMD_DEFAULT_CLOCK	40

/*
 * Clock Conversion factor.
 */
#define AMD_CLOCK_FACTOR(clockRate) ((clockRate + 4) / 5)

/*
 * Calculate select timeout register based on clock rate, select timeout,
 * and clocking factor.
 * 
 * The offical formula is:
 *	reg = ((select timeout in s) * (clock rate in hz)) /
 *		(8192 * clock factor)
 *
 * Change select timeout to ms and clock rate to MHz, amd multiply
 * numerator by 1000...
 *
 *      reg = ((select timeout in ms) * (clock rate in Mhz) * 1000) /
 *		(8192 * clock factor)
 */
static inline unsigned amdSelectTimeout(
	unsigned selto,		// ms
	unsigned clockRate)	// MHz
{
	unsigned denom;		// for roundup
	unsigned factor;
	
	factor = AMD_CLOCK_FACTOR(clockRate);
	denom = 8192 * factor;
	
	return (((selto * clockRate * 1000) + denom - 1) / denom);
}

/*
 * 79C974 actually times out a bit faster than the official formula says it 
 * should. SCSI spec says timeout should be 250 ms; let's cut some slack...
 */
#define AMD_SELECT_TO	300

/*
 * Sync negotiation constants and inlines.
 */

/*
 * Max sync offset of 53C974.
 */
#define AMD_MAX_SYNC_OFFSET	15

/*
 * Macros to convert the value in perTargetData.syncXferPeriod to and
 * from the value specified in a SDTR message.
 */
#define NS_PERIOD_TO_SDTR(period)	(period / 4)
#define SDTR_TO_NS_PERIOD(sdtr)		(sdtr * 4)

/*
 * Default (and desired) minimum clock periods in ns.
 */
#define MIN_PERIOD_FASTCLK_FASTSCSI	100
#define MIN_PERIOD_NORM			200

/*
 * Routine to convert the value in perTargetData.syncXferPeriod to
 * the value used in syncPeriod register. The value of syncPeriod
 * rounds up to round down the frequency.
 */
static inline unsigned nsPeriodToSyncPeriodReg(
	unsigned char nsPeriod,		// desired period in ns
	unsigned fastSCSI,		// value of control3.CR3_FAST_SCSI
	unsigned clockRate)		// in MHz
{
	BOOL		fastClock;
	unsigned	clockPeriod;	// in ns
	
	fastClock = (clockRate > 25) ? YES : NO;
	clockPeriod = 1000 / clockRate;
	
	if(fastClock && !fastSCSI) {
		/*
		 * reg = (clocks per period) - 1.
		 */
		return (((nsPeriod + clockPeriod - 1) / clockPeriod) - 1);
	}
	else {
		/*
		 * reg = clocks per period.
		 */
		return ((nsPeriod + clockPeriod - 1) / clockPeriod);
	}
}
