/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * SYM53c8Types.h - Symbios Logic NCR 53C8xx SCSI controller definitions.
 *
 * HISTORY
 *
 * Oct 1998	Created from BusLogic driver.
 */

#import <driverkit/i386/driverTypes.h>
#import <kernserv/ns_timer.h>
#import <kernserv/queue.h>
#import <mach/boolean.h>
#import <bsd/dev/scsireg.h>

/*
 * NCR 53C8xx Register Offsets
 */
#define SYM_SCNTL0_OFF		0x00	/* SCSI Control 0 */
#define SYM_SCNTL1_OFF		0x01	/* SCSI Control 1 */
#define SYM_SCNTL2_OFF		0x02	/* SCSI Control 2 */
#define SYM_SCNTL3_OFF		0x03	/* SCSI Control 3 */
#define SYM_SCID_OFF		0x04	/* SCSI Chip ID */
#define SYM_SXFER_OFF		0x05	/* SCSI Transfer */
#define SYM_SDID_OFF		0x06	/* SCSI Destination ID */
#define SYM_GPREG_OFF		0x07	/* General Purpose */
#define SYM_SFBR_OFF		0x08	/* SCSI First Byte Received */
#define SYM_SOCL_OFF		0x09	/* SCSI Output Control Latch */
#define SYM_SSID_OFF		0x0A	/* SCSI Selector ID */
#define SYM_SBCL_OFF		0x0B	/* SCSI Bus Control Lines */
#define SYM_DSTAT_OFF		0x0C	/* DMA Status */
#define SYM_SSTAT0_OFF		0x0D	/* SCSI Status 0 */
#define SYM_SSTAT1_OFF		0x0E	/* SCSI Status 1 */
#define SYM_SSTAT2_OFF		0x0F	/* SCSI Status 2 */
#define SYM_DSA_OFF		0x10	/* Data Structure Address */
#define SYM_ISTAT_OFF		0x14	/* Interrupt Status */
#define SYM_CTEST0_OFF		0x18	/* Chip Test 0 */
#define SYM_CTEST1_OFF		0x19	/* Chip Test 1 */
#define SYM_CTEST2_OFF		0x1A	/* Chip Test 2 */
#define SYM_CTEST3_OFF		0x1B	/* Chip Test 3 */
#define SYM_TEMP_OFF		0x1C	/* Temporary Stack */
#define SYM_DFIFO_OFF		0x20	/* DMA FIFO */
#define SYM_CTEST4_OFF		0x21	/* Chip Test 4 */
#define SYM_CTEST5_OFF		0x22	/* Chip Test 5 */
#define SYM_CTEST6_OFF		0x23	/* Chip Test 6 */
#define SYM_DBC_OFF		0x24	/* DMA Byte Counter */
#define SYM_DCMD_OFF		0x27	/* DMA Command */
#define SYM_DNAD_OFF		0x28	/* DMA Next Address */
#define SYM_DSP_OFF		0x2C	/* DMA SCRIPTS Pointer */
#define SYM_DSPS_OFF		0x30	/* DMA SCRIPTS Pointer Save */
#define SYM_SCRATCHA_OFF	0x34	/* General Purpose Scratch A */
#define SYM_DMODE_OFF		0x38	/* DMA Mode */
#define SYM_DIEN_OFF		0x39	/* DMA Interrupt Enable */
#define SYM_SBR_OFF		0x3A	/* Scratch Byte Register */
#define SYM_DCNTL_OFF		0x3B	/* DMA Control */
#define SYM_ADDER_OFF		0x3C	/* Sum output of adder */
#define SYM_SIEN0_OFF		0x40	/* SCSI Interrupt Enable 0 */
#define SYM_SIEN1_OFF		0x41	/* SCSI Interrupt Enable 1 */
#define SYM_SIST0_OFF		0x42	/* SCSI Interrupt Status 0 */
#define SYM_SIST1_OFF		0x43	/* SCSI Interrupt Status 1 */
#define SYM_SLPAR_OFF		0x44	/* SCSI Longitudinal Parity */
#define SYM_MACNTL_OFF		0x46	/* Memory Access Control */
#define SYM_GPCNTL_OFF		0x47	/* General Purpose Control */
#define SYM_STIME0_OFF		0x48	/* SCSI Timer 0 */
#define SYM_STIME1_OFF		0x49	/* SCSI Timer 1 */
#define SYM_RESPID_OFF		0x4A	/* Response ID */
#define SYM_STEST0_OFF		0x4C	/* SCSI Test 0 */
#define SYM_STEST1_OFF		0x4D	/* SCSI Test 1 */
#define SYM_STEST2_OFF		0x4E	/* SCSI Test 2 */
#define SYM_STEST3_OFF		0x4F	/* SCSI Test 3 */
#define SYM_SIDL_OFF		0x50	/* SCSI Input Data Latch */
#define SYM_STEST4_OFF		0x52	/* SCSI Test 4 */
#define SYM_SODL_OFF		0x54	/* SCSI Output Data Latch */
#define SYM_SCRATCHB_OFF	0x5C	/* General Purpose Scratch B */

/*
 * ISTAT register bits
 */
#define SYM_ISTAT_DIP		0x01	/* DMA Interrupt Pending */
#define SYM_ISTAT_SIP		0x02	/* SCSI Interrupt Pending */
#define SYM_ISTAT_INTF		0x04	/* Interrupt on Fly */
#define SYM_ISTAT_CON		0x08	/* Connected */
#define SYM_ISTAT_SEM		0x10	/* Semaphore */
#define SYM_ISTAT_SIGP		0x20	/* Signal Process */
#define SYM_ISTAT_SRST		0x40	/* Software Reset */
#define SYM_ISTAT_ABRT		0x80	/* Abort Operation */

/*
 * DSTAT register bits
 */
#define SYM_DSTAT_IID		0x01	/* Illegal Instruction Detected */
#define SYM_DSTAT_WTD		0x02	/* Watchdog Timeout Detected */
#define SYM_DSTAT_SIR		0x04	/* SCRIPTS Interrupt Instruction */
#define SYM_DSTAT_SSI		0x08	/* Single Step Interrupt */
#define SYM_DSTAT_ABRT		0x10	/* Aborted */
#define SYM_DSTAT_BF		0x20	/* Bus Fault */
#define SYM_DSTAT_MDPE		0x40	/* Master Data Parity Error */
#define SYM_DSTAT_DFE		0x80	/* DMA FIFO Empty */

/*
 * SIST0 register bits
 */
#define SYM_SIST0_PAR		0x01	/* Parity Error */
#define SYM_SIST0_RST		0x02	/* SCSI Reset */
#define SYM_SIST0_UDC		0x04	/* Unexpected Disconnect */
#define SYM_SIST0_SGE		0x08	/* SCSI Gross Error */
#define SYM_SIST0_SEL		0x10	/* Selected */
#define SYM_SIST0_STO		0x20	/* Selection Timeout */
#define SYM_SIST0_CMP		0x40	/* Function Complete */
#define SYM_SIST0_MA		0x80	/* Phase Mismatch */

/*
 * SIST1 register bits
 */
#define SYM_SIST1_HTH		0x01	/* Handshake to Handshake Timer Expired */
#define SYM_SIST1_GEN		0x02	/* General Purpose Timer Expired */
#define SYM_SIST1_STO		0x04	/* Selection/Reselection Timeout */
#define SYM_SIST1_SBMC		0x10	/* SCSI Bus Mode Change */

/*
 * SCSI phases
 */
#define SYM_PHASE_DATAOUT	0x00
#define SYM_PHASE_DATAIN	0x01
#define SYM_PHASE_COMMAND	0x02
#define SYM_PHASE_STATUS	0x03
#define SYM_PHASE_MSGOUT	0x06
#define SYM_PHASE_MSGIN		0x07

/*
 * Command/Control Block (CCB)
 */

#define SYM_QUEUE_SIZE		16
#define SYM_SG_COUNT		17

struct sym_sg {
	unsigned int	addr;
	unsigned int	len;
};

struct ccb {
	/* Hardware portion */
	unsigned char	opcode;
	unsigned char	target:4,
			lun:4;
	unsigned char	cdb_len;
	unsigned char	tag_msg;
	unsigned int	data_len;
	unsigned int	data_addr;
	unsigned char	tag;
	unsigned char	reserved[3];
	union cdb	cdb;
	esense_reply_t	senseData;

	/* Software extension */
	struct sym_sg	sg_list[SYM_SG_COUNT];
	IOEISADMABuffer	dmaList[SYM_SG_COUNT];
	unsigned int	total_xfer_len;
	ns_time_t	startTime;
	port_t		timeoutPort;
	void		*cmdBuf;
	boolean_t	in_use;
	queue_chain_t	ccbQ;
	unsigned char	host_status;
	unsigned char	scsi_status;
};

/*
 * Host status codes
 */
#define SYM_HOST_SUCCESS		0x00
#define SYM_HOST_SEL_TIMEOUT		0x11
#define SYM_HOST_DATA_OVRUN		0x12
#define SYM_HOST_BUS_FREE		0x13
#define SYM_HOST_BAD_PHASE		0x14
#define SYM_HOST_RESET			0x16
#define SYM_HOST_ABORTED		0x17
#define SYM_HOST_PARITY_ERROR		0x18
#define SYM_HOST_ERROR			0x19

/*
 * Configuration data
 */
typedef struct sym_config {
	unsigned char	irq;
	unsigned char	scsi_id;
	unsigned char	max_target;
	unsigned char	max_lun;
	unsigned int	io_base;
	unsigned int	io_size;
} sym_config_t;

/*
 * Inquiry data
 */
typedef struct sym_inquiry {
	unsigned char	chip_id;
	unsigned char	chip_rev;
	unsigned char	features;
} sym_inquiry_t;

/*
 * Chip IDs
 */
#define SYM_CHIP_810		0x01
#define SYM_CHIP_810A		0x02
#define SYM_CHIP_825		0x03
#define SYM_CHIP_815		0x04
#define SYM_CHIP_825A		0x06
#define SYM_CHIP_860		0x08
#define SYM_CHIP_875		0x0F
#define SYM_CHIP_895		0x0C

/*
 * SCRIPTS instruction opcodes
 */
#define SYM_SCRIPT_MOVE		0x00000000
#define SYM_SCRIPT_SELECT	0x40000000
#define SYM_SCRIPT_WAIT		0x48000000
#define SYM_SCRIPT_DISCONNECT	0x48000000
#define SYM_SCRIPT_RESELECT	0x50000000
#define SYM_SCRIPT_SET		0x58000000
#define SYM_SCRIPT_CLEAR	0x60000000
#define SYM_SCRIPT_LOAD		0xE0000000
#define SYM_SCRIPT_STORE	0xE1000000
#define SYM_SCRIPT_INT		0x98080000
#define SYM_SCRIPT_JUMP		0x80080000
#define SYM_SCRIPT_CALL		0x88080000
#define SYM_SCRIPT_RETURN	0x90080000

