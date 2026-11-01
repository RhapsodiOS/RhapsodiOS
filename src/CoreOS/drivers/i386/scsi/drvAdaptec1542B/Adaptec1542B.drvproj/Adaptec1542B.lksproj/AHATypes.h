/*
 * Copyright (c) 1992-1996 NeXT Software, Inc.
 *
 * Adaptec AHA-1542 SCSI controller definitions.
 *
 * HISTORY
 *
 * 10 July 1992 David E. Bohman at NeXT
 *	Created.
 */
 
#import <driverkit/i386/driverTypes.h>
#import <kernserv/ns_timer.h>
#import <kernserv/queue.h>
#import <mach/boolean.h>
#import <bsd/dev/scsireg.h>

/*
 * Control register.
 */

#define AHA_CTRL_REG_OFF	0x00
typedef struct {
    unsigned char
					:4,
		    scsi_rst		:1,
		    intr_clr		:1,
		    sw_rst		:1,
		    hw_rst		:1;
} aha_ctrl_reg_t;

/*
 * Status register.
 */

#define AHA_STAT_REG_OFF	0x00
typedef struct {
    unsigned char
		    cmd_err		:1,
					:1,
		    datain_full		:1,
		    dataout_full	:1,
		    idle		:1,
		    mb_init_needed	:1,
		    selftst_fail	:1,
		    selftst		:1;
} aha_stat_reg_t;

/*
 * Interrupt status register.
 */

#define AHA_INTR_REG_OFF	0x02
typedef struct  {
    unsigned char
		    mb_in_full		:1,
		    mb_out_avail	:1,
		    cmd_done		:1,
		    scsi_rst		:1,
		    			:3,
		    intr		:1;
} aha_intr_reg_t;

/*
 * Command register.
 */

#define AHA_CMD_REG_OFF		0x01
typedef unsigned char	aha_cmd_reg_t;

/*
 * Board commands.
 */

#define	AHA_CMD_INIT		0x01
#define AHA_CMD_START_SCSI	0x02
#define AHA_CMD_DO_INQUIRY	0x04
#define AHA_CMD_GET_CONFIG	0x0b
#define AHA_CMD_GET_BIOS_INFO	0x28
#define AHA_CMD_SET_MB_ENABLE	0x29

/*
 * An in or out mailbox.
 */
#define AHA_MB_OUT_FREE		0
#define AHA_MB_OUT_START	1
#define AHA_MB_OUT_ABORT	2

#define AHA_MB_IN_FREE		0
#define AHA_MB_IN_SUCCESS	1
#define AHA_MB_IN_ABORTED	2
#define AHA_MB_IN_INVALID	3
#define AHA_MB_IN_ERROR		4

typedef struct {
    volatile unsigned char	mb_stat;
    volatile unsigned char	ccb_addr[3];
} aha_mb_t;

/*
 * The mailbox area.  Equal
 * number of incoming mailboxes
 * as outgoing ones.
 */

#define AHA_QUEUE_SIZE	16
#define AHA_MB_CNT	16
struct aha_mb_area {
    aha_mb_t		mb_out[AHA_MB_CNT];
    aha_mb_t		mb_in[AHA_MB_CNT];
};


/*
 * Mailbox area initialization
 * structure passed to AHA_CMD_MB_INIT.
 */

typedef struct {
	unsigned char	mb_cnt;
	unsigned char	mb_area_addr[3];
} aha_cmd_init_t;


typedef	struct {
	unsigned char	mb_status;
	unsigned char	mb_lock_code;
} aha_mb_lock_t;




/*
 * A scatter/gather
 * descriptor.
 */

struct aha_sg {
	unsigned char	len[3];
	unsigned char	addr[3];
};

/*
 * The controller command block.
 */

#define AHA_SG_COUNT			17

#define AHA_CCB_INITIATOR		0x00
#define AHA_CCB_TARGET			0x01
#define AHA_CCB_INITIATOR_SG		0x02
#define AHA_CCB_INITIATOR_RESID		0x03
#define AHA_CCB_INITIATOR_RESID_SG	0x04
#define AHA_CCB_DEV_RESET		0x81

#define AHA_HOST_SUCCESS		0x00
#define AHA_HOST_SEL_TIMEOUT		0x11
#define AHA_HOST_DATA_OVRUN		0x12
#define AHA_HOST_BAD_DISCONN		0x13
#define AHA_HOST_BAD_PHASE_SEQ		0x14
#define AHA_HOST_BAD_MB_OUT		0x15
#define AHA_HOST_BAD_OPER		0x16
#define AHA_HOST_BAD_LINK_LUN		0x17
#define AHA_HOST_INVALID_TDIR		0x18
#define AHA_HOST_DUPLICATED_CCB		0x19
#define AHA_HOST_INVALID_CCB		0x1a

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
     * The sense data does not necessarliy go right here; it goes 
     * cdb_len bytes after the start of cdb. Allocating an entire
     * esense_reply_t here guarantees we'll always have enough
     * space. This is how Adaptec designed the interface.
     */
    esense_reply_t	senseData;
    
    /* Software extension to ccb */
    
    struct aha_sg	sg_list[AHA_SG_COUNT];
    IOEISADMABuffer	dmaList[AHA_SG_COUNT];
    unsigned int	total_xfer_len;
    aha_mb_t		*mb_out;
    ns_time_t		startTime;
    port_t		timeoutPort;
    void		*cmdBuf;	// keep AHAThread types opaque here...
    boolean_t		in_use;
    queue_chain_t	ccbQ;
};

/*
 *  The configuration data returned by the board.
 */
typedef struct aha_config {
	unsigned char	dma_channel;
	unsigned char	irq;
	unsigned char	scsi_id:3,
			mbz:5;
} aha_config_t;


/*
 *  Identification struct returned by the board.
 */
typedef struct aha_inquiry {
	unsigned char	board_id;
	unsigned char	special_options;
	unsigned char	firmware_rev1;
	unsigned char	firmware_rev2;
} aha_inquiry_t;

#define AHA_1540_16HEAD		0x00
#define	AHA_1540_64HEAD		0x30
#define AHA_154xB		0x41
#define	AHA_1640		0x42
#define	AHA_174xA		0x43		/* AHA 174x in standard mode */
#define	AHA_154xC		0x44


