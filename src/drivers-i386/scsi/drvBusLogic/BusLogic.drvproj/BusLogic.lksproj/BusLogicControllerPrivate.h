/*
 * Copyright (c) 1996 NeXT Software, Inc.
 *
 * BusLogicControllerPrivate.h - Private definitions for BusLogic driver.
 *
 * HISTORY
 *
 * Oct 1998	Created from Adaptec 1542 driver.
 */

#import <driverkit/debugging.h>
#import <kernserv/queue.h>
#import <machkit/NXConditionLock.h>

/*
 * DDM masks and macros.
 *
 * BusLogicController.m calls ddm_init/ddm_exp/ddm_thr throughout, but this
 * header never defined them -- the driver was created from the Adaptec 1542
 * driver, which carries them in AHAControllerPrivate.h, and they were lost in
 * the copy.  Without them the calls compile as implicit functions and fail to
 * link.  The index follows the same convention: each driver takes its own slot
 * in IODDMMasks[].
 */
#define BLC_DDM_INDEX	2

#define DDM_EXPORTED	0x00000001	/* exported methods */
#define DDM_IOTHREAD	0x00000002	/* I/O thread methods */
#define DDM_INIT	0x00000004	/* initialization */

#define ddm_exp(x, a, b, c, d, e)					\
	IODEBUG(BLC_DDM_INDEX, DDM_EXPORTED, x, a, b, c, d, e)

#define ddm_thr(x, a, b, c, d, e)					\
	IODEBUG(BLC_DDM_INDEX, DDM_IOTHREAD, x, a, b, c, d, e)

#define ddm_init(x, a, b, c, d, e)					\
	IODEBUG(BLC_DDM_INDEX, DDM_INIT, x, a, b, c, d, e)

/*
 * Host bus the board plugs into, from the "Card Type" key in the config
 * table. Only ISA boards use the machine's DMA controller.
 */
#define BL_BUS_ISA		0
#define BL_BUS_EISA		1
#define BL_BUS_VL		2
#define BL_BUS_PCI		3

/*
 * Number of I/O ports the board occupies, claimed on the PCI path.
 */
#define BL_PCI_REGISTER_SPACE	4

/*
 * Command request operations.
 */
typedef enum {
	BO_Execute,
	BO_Reset,
	BO_Abort
} BLOperation;

/*
 * Completion status.
 */
typedef enum {
	CS_Complete,
	CS_Timeout,
	CS_Reset
} completeStatus;

/*
 * States for cmdLock NXConditionLock.
 */
#define CMD_PENDING		0
#define CMD_COMPLETE		1

/*
 * A request to the I/O thread.
 */
typedef struct {
	queue_chain_t	link;
	BLOperation	op;
	IOSCSIRequest	*scsiReq;
	void		*buffer;
	vm_task_t	client;
	sc_status_t	result;
	id		cmdLock;	/* NXConditionLock */
} BLCommandBuf;

