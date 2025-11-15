/*
 * Copyright (c) 1996 NeXT Software, Inc.
 *
 * BusLogicTypes.h - BusLogic SCSI controller definitions.
 *
 * HISTORY
 *
 * Oct 1998	Created from Adaptec 1542 driver.
 */

#import <driverkit/i386/driverTypes.h>
#import <kernserv/ns_timer.h>
#import <kernserv/queue.h>
#import <mach/boolean.h>
#import <bsd/dev/scsireg.h>

/*
 * Control register.
 */

#define BL_CTRL_REG_OFF		0x00
typedef struct {
    unsigned char
				:4,
	    scsi_rst		:1,
	    intr_clr		:1,
	    soft_rst		:1,
	    hard_rst		:1;
} bl_ctrl_reg_t;

/*
 * Status register.
 */

#define BL_STAT_REG_OFF		0x00
typedef struct {
    unsigned char
	    cmd_invalid		:1,
	    rsvd		:1,
	    datain_full		:1,
	    cmd_param_busy	:1,
	    host_busy		:1,
	    diag_fail		:1,
	    diag_active		:1,
	    init_required	:1;
} bl_stat_reg_t;

/*
 * Interrupt status register.
 */

#define BL_INTR_REG_OFF		0x02
typedef struct  {
    unsigned char
	    mb_in_full		:1,
	    mb_out_avail	:1,
	    cmd_complete	:1,
	    scsi_rst		:1,
	    			:3,
	    intr_pending	:1;
} bl_intr_reg_t;

/*
 * Command register.
 */

#define BL_CMD_REG_OFF		0x01
typedef unsigned char	bl_cmd_reg_t;

/*
 * Board commands.
 */

#define	BL_CMD_TEST_CMDC_INT	0x00
#define BL_CMD_INIT_MBOX	0x01
#define BL_CMD_START_SCSI	0x02
#define BL_CMD_EXECUTE_BIOS	0x03
#define BL_CMD_INQUIRY		0x04
#define BL_CMD_ENABLE_OMBR	0x05
#define BL_CMD_SET_SEL_TIMEOUT	0x06
#define BL_CMD_SET_TIMEBUS	0x07
#define BL_CMD_SET_TIMEDISC	0x08
#define BL_CMD_SET_XFER_RATE	0x09
#define BL_CMD_INQUIRY_DEV	0x0a
#define BL_CMD_GET_CONFIG	0x0b
#define BL_CMD_TARGET_MODE	0x0c
#define BL_CMD_INQUIRY_SETUP	0x0d
#define BL_CMD_WRITE_CH2	0x1a
#define BL_CMD_READ_CH2		0x1b
#define BL_CMD_WRITE_FIFO	0x1c
#define BL_CMD_READ_FIFO	0x1d
#define BL_CMD_ECHO_DATA	0x1f
#define BL_CMD_ADAPTER_DIAG	0x20
#define BL_CMD_SET_ADAPTER_OPT	0x21
#define BL_CMD_GET_ADAPTER_OPT	0x22
#define BL_CMD_SET_EEPROM	0x23
#define BL_CMD_GET_EEPROM	0x24
#define BL_CMD_ENABLE_STRICT	0x25
#define BL_CMD_WRITE_AUTOSCSI	0x26
#define BL_CMD_READ_AUTOSCSI	0x27
#define BL_CMD_SET_PREEMPT_TIME	0x28
#define BL_CMD_SET_TIMEOFF	0x29

/*
 * An in or out mailbox.
 */
#define BL_MB_OUT_FREE		0x00
#define BL_MB_OUT_START		0x01
#define BL_MB_OUT_ABORT		0x02

#define BL_MB_IN_FREE		0x00
#define BL_MB_IN_SUCCESS	0x01
#define BL_MB_IN_ABORTED	0x02
#define BL_MB_IN_INVALID	0x03
#define BL_MB_IN_ERROR		0x04

typedef struct {
    volatile unsigned char	mb_stat;
    volatile unsigned char	ccb_addr[3];
} bl_mb_t;

/*
 * The mailbox area.  Equal
 * number of incoming mailboxes
 * as outgoing ones.
 */

#define BL_QUEUE_SIZE	16
#define BL_MB_CNT	16
struct bl_mb_area {
    bl_mb_t		mb_out[BL_MB_CNT];
    bl_mb_t		mb_in[BL_MB_CNT];
};


/*
 * Mailbox area initialization
 * structure passed to BL_CMD_INIT_MBOX.
 */

typedef struct {
	unsigned char	mb_cnt;
	unsigned char	mb_area_addr[3];
} bl_cmd_init_t;


typedef	struct {
	unsigned char	mb_status;
	unsigned char	mb_lock_code;
} bl_mb_lock_t;




/*
 * A scatter/gather
 * descriptor.
 */

struct bl_sg {
	unsigned char	len[3];
	unsigned char	addr[3];
};

/*
 * The controller command block.
 */

#define BL_SG_COUNT			17

#define BL_CCB_INITIATOR		0x00
#define BL_CCB_TARGET			0x01
#define BL_CCB_INITIATOR_SG		0x02
#define BL_CCB_INITIATOR_RESID		0x03
#define BL_CCB_INITIATOR_RESID_SG	0x04
#define BL_CCB_BUS_RESET		0x81

#define BL_HOST_SUCCESS			0x00
#define BL_HOST_SEL_TIMEOUT		0x11
#define BL_HOST_DATA_OVRUN		0x12
#define BL_HOST_BUS_FREE		0x13
#define BL_HOST_BAD_PHASE_SEQ		0x14
#define BL_HOST_BAD_OPCODE		0x15
#define BL_HOST_INVALID_CCB		0x16
#define BL_HOST_LINKED_CCB_LUN_MISMATCH	0x17
#define BL_HOST_INVALID_DIR		0x18
#define BL_HOST_DUPLICATE_CCB		0x19
#define BL_HOST_INVALID_CCB_OR_SG	0x1a
#define BL_HOST_AUTO_SENSE_FAIL		0x1b
#define BL_HOST_TAGGED_QUEUE_REJ	0x1c
#define BL_HOST_HARDWARE_ERROR		0x20
#define BL_HOST_TARGET_INIT_ABORT	0x21
#define BL_HOST_HOST_ABORT		0x22
#define BL_HOST_HOST_ABORT_FAIL		0x23
#define BL_HOST_BDR_NOT_RECOVER		0x25
#define BL_HOST_BDR_SENT		0x26

struct ccb {
    unsigned char	oper;
    unsigned char	lun		:3,
			data_in		:1,
			data_out	:1,
			target		:3;
    unsigned char	cdb_len;
    unsigned char	reqsense_len;	/* 1 means no auto reqsense */
    unsigned char	data_len[3];
    unsigned char	data_addr[3];
    unsigned char	link_addr[3];
    unsigned char	link_id;
    unsigned char	host_status;
    unsigned char	target_status;
    unsigned char	mbz[2];
    union cdb		cdb;

    /*
     * *** Hack alert ***
     *
     * The sense data does not necessarily go right here; it goes
     * cdb_len bytes after the start of cdb. Allocating an entire
     * esense_reply_t here guarantees we'll always have enough
     * space. This is how BusLogic designed the interface.
     */
    esense_reply_t	senseData;

    /* Software extension to ccb */

    struct bl_sg	sg_list[BL_SG_COUNT];
    IOEISADMABuffer	dmaList[BL_SG_COUNT];
    unsigned int	total_xfer_len;
    bl_mb_t		*mb_out;
    ns_time_t		startTime;
    port_t		timeoutPort;
    void		*cmdBuf;	// keep BLThread types opaque here...
    boolean_t		in_use;
    queue_chain_t	ccbQ;
};

/*
 *  The configuration data returned by the board.
 */
typedef struct bl_config {
	unsigned char	dma_channel;
	unsigned char	irq;
	unsigned char	scsi_id:4,
			rsvd:4;
} bl_config_t;


/*
 *  Identification struct returned by the board.
 */
typedef struct bl_inquiry {
	unsigned char	board_id;
	unsigned char	firmware_version[3];
} bl_inquiry_t;

#define BL_BOARD_545S		0x42	/* VL Bus - BIOS 4.xx */
#define BL_BOARD_545C		0x41	/* VL Bus - BIOS 3.3x */
#define BL_BOARD_542D		0x40	/* MCA */
#define BL_BOARD_542B		0x30	/* ISA/EISA - Wide */


