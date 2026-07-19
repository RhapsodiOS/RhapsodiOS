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
#import <mach/boolean.h>
#import <bsd/dev/scsireg.h>

/*
 * Control register.
 */

#define AIC_CTRL_REG_OFF	0x00
typedef struct {
    unsigned char
					:4,
		    scsi_rst		:1,
		    intr_clr		:1,
		    sw_rst		:1,
		    hw_rst		:1;
} aic_ctrl_reg_t;

/*
 * Status register.
 */

#define AIC_STAT_REG_OFF	0x00
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
} aic_stat_reg_t;

/*
 * Interrupt status register.
 */

#define AIC_INTR_REG_OFF	0x02
typedef struct  {
    unsigned char
		    mb_in_full		:1,
		    mb_out_avail	:1,
		    cmd_done		:1,
		    scsi_rst		:1,
		    			:3,
		    intr		:1;
} aic_intr_reg_t;

/*
 * Command register.
 */

#define AIC_CMD_REG_OFF		0x01
typedef unsigned char	aic_cmd_reg_t;

/*
 * Board commands.
 */

#define	AIC_CMD_INIT		0x01
#define AIC_CMD_START_SCSI	0x02
#define AIC_CMD_DO_INQUIRY	0x04
#define AIC_CMD_GET_CONFIG	0x0b
#define AIC_CMD_GET_BIOS_INFO	0x28
#define AIC_CMD_SET_MB_ENABLE	0x29

/*
 * An in or out mailbox.
 */
#define AIC_MB_OUT_FREE		0
#define AIC_MB_OUT_START	1
#define AIC_MB_OUT_ABORT	2

#define AIC_MB_IN_FREE		0
#define AIC_MB_IN_SUCCESS	1
#define AIC_MB_IN_ABORTED	2
#define AIC_MB_IN_INVALID	3
#define AIC_MB_IN_ERROR		4

typedef struct {
    volatile unsigned char	mb_stat;
    volatile unsigned char	ccb_addr[3];
} aic_mb_t;

/*
 * The mailbox area.  Equal
 * number of incoming mailboxes
 * as outgoing ones.
 */

#define AIC_QUEUE_SIZE	16
#define AIC_MB_CNT	16
struct aic_mb_area {
    aic_mb_t		mb_out[AIC_MB_CNT];
    aic_mb_t		mb_in[AIC_MB_CNT];
};


/*
 * Mailbox area initialization
 * structure passed to AIC_CMD_MB_INIT.
 */

typedef struct {
	unsigned char	mb_cnt;
	unsigned char	mb_area_addr[3];
} aic_cmd_init_t;


typedef	struct {
	unsigned char	mb_status;
	unsigned char	mb_lock_code;
} aic_mb_lock_t;




/*
 * A scatter/gather
 * descriptor.
 */

struct aic_sg {
	unsigned char	len[3];
	unsigned char	addr[3];
};

/*
 * The controller command block.
 */

#define AIC_SG_COUNT			17

#define AIC_CCB_INITIATOR		0x00
#define AIC_CCB_TARGET			0x01
#define AIC_CCB_INITIATOR_SG		0x02
#define AIC_CCB_INITIATOR_RESID		0x03
#define AIC_CCB_INITIATOR_RESID_SG	0x04
#define AIC_CCB_DEV_RESET		0x81

#define AIC_HOST_SUCCESS		0x00
#define AIC_HOST_SEL_TIMEOUT		0x11
#define AIC_HOST_DATA_OVRUN		0x12
#define AIC_HOST_BAD_DISCONN		0x13
#define AIC_HOST_BAD_PHASE_SEQ		0x14
#define AIC_HOST_BAD_MB_OUT		0x15
#define AIC_HOST_BAD_OPER		0x16
#define AIC_HOST_BAD_LINK_LUN		0x17
#define AIC_HOST_INVALID_TDIR		0x18
#define AIC_HOST_DUPLICATED_CCB		0x19
#define AIC_HOST_INVALID_CCB		0x1a

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

    struct aic_sg	sg_list[AIC_SG_COUNT];
    IOEISADMABuffer	dmaList[AIC_SG_COUNT];
    unsigned int	total_xfer_len;
    aic_mb_t		*mb_out;
    ns_time_t		startTime;
    port_t		timeoutPort;
    void		*cmdBuf;	// keep AIC6X60Thread types opaque here...
    boolean_t		in_use;
    queue_chain_t	ccbQ;
};

/*
 *  The configuration data returned by the board.
 */
typedef struct aic_config {
	unsigned char	dma_channel;
	unsigned char	irq;
	unsigned char	scsi_id:3,
			mbz:5;
} aic_config_t;


/*
 *  Identification struct returned by the board.
 */
typedef struct aic_inquiry {
	unsigned char	board_id;
	unsigned char	special_options;
	unsigned char	firmware_rev1;
	unsigned char	firmware_rev2;
} aic_inquiry_t;

#define AIC_6X60		0x60


