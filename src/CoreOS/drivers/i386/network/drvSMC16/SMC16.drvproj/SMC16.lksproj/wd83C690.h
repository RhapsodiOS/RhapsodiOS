/*
 * Copyright (c) 1992-1996 NeXT Software, Inc.
 *
 * WD83C690 Network Interface Chip.
 *
 * HISTORY
 *
 * 25 July 1992 
 *	Created.
 */
 
#import "SMC16Hdw.h"

#define NIC_PAGE_SIZE	256

/*
 * NIC access inlines
 */

static __inline__
vm_offset_t
nic_page_addr(SMC16_off_t page, vm_offset_t base)
{
    return (vm_offset_t)(base + (page * NIC_PAGE_SIZE));
}

static __inline__
vm_offset_t
nic_page_round(SMC16_off_t addr)
{
    return  (vm_offset_t)(((vm_offset_t)(addr) + NIC_PAGE_SIZE - 1) & 
    	~(NIC_PAGE_SIZE - 1));
}



/*
 * Register definitions
 */

/*
 * Command register.
 */

#define NIC_CMD_REG_OFF		0x00

typedef struct {
    unsigned char	stp	:1,	/* stop device */
			sta	:1,	/* start device */
			txp	:1,	/* begin packet xmt */
				:3,
			psel	:2;	/* register page select */
} nic_cmd_reg_t;

/*
 * Interrupt status register.
 */

#define NIC_ISTAT_REG_OFF	0x07
#define NIC_ISTAT_REG_R_PG	0x00	
#define NIC_ISTAT_REG_W_PG	0x00	

typedef struct {
    unsigned char	prx	:1,	/* packet recvd */
			ptx	:1,	/* packet xmtd */
			rxe	:1,	/* packet recvd w/error */
			txe	:1,	/* packet xmt error */
			ovw	:1,	/* recv ring overwrite warning */
			cnt	:1,	/* counter overflow warning */
				:1,
			rst	:1;	/* device stopped */
} nic_istat_reg_t;

/*
 * Interrupt mask register.
 */

#define NIC_IMASK_REG_OFF	0x0f
#define NIC_IMASK_REG_R_PG	0x02
#define NIC_IMASK_REG_W_PG	0x00

typedef struct {
    unsigned char	prxe	:1,	/* packet recvd enable */
			ptxe	:1,	/* packet xmtd enable */
			rxee	:1,	/* packet recvd w/error enable */
			txee	:1,	/* packet xmt error enable */
			ovwe	:1,	/* recv ring overwrite warning enb */
			cnte	:1,	/* counter overflow waring enable */
				:2;
} nic_imask_reg_t;

/*
 * Receive status register.
 */

#define NIC_RSTAT_REG_OFF	0x0C
#define NIC_RSTAT_REG_R_PG	0x00

typedef struct {
    unsigned char	prx	:1,	/* packet recvd w/o error */
    			crc	:1,	/* packet recvd w/crc error */
			fae	:1,	/* packet recvd w/framing error */
			over	:1,	/* recv fifo overflow */
			mpa	:1,	/* missed packet occurred */
			group	:1,	/* packet recvd is bcast or mcast */
			dis	:1,	/* receiver is in mon mode */
			dfr	:1;	/* jabber condition on wire */
} nic_rstat_reg_t;

/*
 * Transmit status register.
 */

#define NIC_TSTAT_REG_OFF	0x04
#define NIC_TSTAT_REG_R_PG	0x00

typedef struct {
    unsigned char	ptx	:1,	/* packet xmtd on wire */
			ndt	:1,	/* packet xmtd w/o initial deferment */
			twc	:1,	/* xmtd with collisions */
			abort	:1,	/* not xmtd due to excess. coll. */
			crl	:1,	/* packet xmtd but carrier was lost */
			under	:1,	/* xmt fifo underrun */
			cdh	:1,	/* heartbeat detected */
			owc	:1;	/* out of win. collision occurred */
} nic_tstat_reg_t;

/*
 * 83690 features register
 */

#define NIC_ENH_REG_OFF		0x27
#define NIC_ENH_REG_R_PG	0x02
#define NIC_ENH_REG_W_PG	0x02

typedef struct {
    unsigned char		:3,	
			slot	:2,	/* slot time */
#define NIC_SLOT_512_BIT	0
#define NIC_SLOT_256_BIT	2
#define NIC_SLOT_1024_BIT	3
				:1,	
			wait	:2;	/* wait states inserted into DMA */
} nic_enh_reg_t;


/*
 * Memory block register
 */

#define NIC_BLOCK_REG_OFF	0x06
#define NIC_BLOCK_REG_R_PG	0x02
#define NIC_BLOCK_REG_W_PG	0x02
 
/*
 * Receive boundary page register.
 */

#define NIC_BOUND_REG_OFF	0x03
#define NIC_BOUND_REG_R_PG	0x00
#define NIC_BOUND_REG_W_PG	0x00

/*
 * Receive current page register.
 */

#define NIC_CURR_REG_OFF	0x07
#define NIC_CURR_REG_R_PG	0x01
#define NIC_CURR_REG_W_PG	0x01

/*
 * Receive ring start page register.
 */

#define NIC_RSTART_REG_OFF	0x01
#define NIC_RSTART_REG_R_PG	0x02
#define NIC_RSTART_REG_W_PG	0x00

/*
 * Receive ring stop page register.
 */

#define NIC_RSTOP_REG_OFF	0x02
#define NIC_RSTOP_REG_R_PG	0x02
#define NIC_RSTOP_REG_W_PG	0x00

/*
 * Transmit start page register.
 */

#define NIC_TSTART_REG_OFF	0x04
#define NIC_TSTART_REG_R_PG	0x02
#define NIC_TSTART_REG_W_PG	0x00

/*
 * Transmit count registers.
 */

#define NIC_TCNTL_REG_OFF	0x05
#define NIC_TCNTH_REG_OFF	0x06
#define NIC_TCNT_REG_W_PG	0x00

/*
 * Station address registers.
 */

#define NIC_STA_REG_OFF		0x01
#define NIC_STA_REG_R_PG	0x01
#define NIC_STA_REG_W_PG	0x01

/*
 * Receive configuration register.
 */

#define NIC_RCON_REG_OFF	0x0c
#define NIC_RCON_REG_R_PG	0x02
#define NIC_RCON_REG_W_PG	0x00

typedef struct {
    unsigned char	sep	:1,	/* save error packets */
			runts	:1,	/* save runt packets */
			broad	:1,	/* receive broadcast packets */
			group	:1,	/* receive *all* multicast packets */
			prom	:1,	/* receive all packets */
			mon	:1,	/* monitor network */
				:2;
} nic_rcon_reg_t;

/*
 * Transmit configuration register.
 */

#define NIC_TCON_REG_OFF	0x0d
#define NIC_TCON_REG_R_PG	0x02
#define NIC_TCON_REG_W_PG	0x00

typedef struct {
    unsigned char	crcn	:1,	/* no CRC generation */
			lb	:2,	/* loopback mode */
#define NIC_XMT_LOOPB_NONE	0
#define NIC_XMT_LOOPB_INTER	1
#define NIC_XMT_LOOPB_EXTER_HI	2
#define NIC_XMT_LOOPB_EXTER_LO	3
				:5;
} nic_tcon_reg_t;

/*
 * Data configuration register.
 */

#define NIC_DCON_REG_OFF	0x0e
#define NIC_DCON_REG_R_PG	0x02
#define NIC_DCON_REG_W_PG	0x00

typedef struct {
    unsigned char	bus16	:1,	/* 16 bit DMA transfers */
				:4,
			bsize	:2,	/* DMA burst length */
#define NIC_DMA_BURST_2b	0
#define NIC_DMA_BURST_4b	1
#define NIC_DMA_BURST_8b	2
#define NIC_DMA_BURST_12b	3
				:1;
} nic_dcon_reg_t;

/*
 * Counter registers.
 */

/* Receive alignment errors */
#define NIC_ALICNT_REG_OFF	0x0d
#define NIC_ALICNT_REG_R_PG	0x00

/* Transmit collisions (last transmit) */
#define NIC_COLCNT_REG_OFF	0x05
#define NIC_COLCNT_REG_R_PG	0x00

/* Receive CRC errors */
#define NIC_CRCCNT_REG_OFF	0x0e
#define NIC_CRCCNT_REG_R_PG	0x00

/* Missed receive packets */
#define NIC_MPCNT_REG_OFF	0x0f
#define NIC_MPCNT_REG_R_PG	0x00

/*
 * Receive packet buffer header.
 */

typedef struct {
    nic_rstat_reg_t	rstat;
    unsigned char	next;
    unsigned short	len;
    unsigned char	data[0];
} nic_recv_hdr_t;

