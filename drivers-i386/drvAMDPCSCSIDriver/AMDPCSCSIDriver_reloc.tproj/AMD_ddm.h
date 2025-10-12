/* 	Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved. 
 *
 *
 * DDM macros for AMD SCSI driver.
 */
 
#import <driverkit/debugging.h>

 /*
 * The index into IODDMMasks[].
 */
#define AMD_DDM_INDEX	2

#define DDM_EXPORTED	0x00000001	// exported methods
#define DDM_IOTHREAD	0x00000002	// I/O thread methods
#define DDM_INIT	0x00000004	// Initialization
#define DDM_INTR 	0x00000008	// Interrupt
#define DDM_CHIP	0x00000010	// chip-level
#define DDM_ERROR	0x00000020	// error
#define DDM_DMA		0x00000040	// DMA
#
#define DDM_CONSOLE_LOG		0		/* really hosed...*/

#if	DDM_CONSOLE_LOG

#undef	IODEBUG
#define IODEBUG(index, mask, x, a, b, c, d, e) { 			\
	if(IODDMMasks[index] & mask) {					\
		IOLog(x, a, b, c,d, e); 				\
	}								\
}

#endif	DDM_CONSOLE_LOG

/*
 * Normal ddm calls..
 */
#define ddm_exp(x, a, b, c, d, e) 					\
	IODEBUG(AMD_DDM_INDEX, DDM_EXPORTED, x, a, b, c, d, e)
	
#define ddm_thr(x, a, b, c, d, e) 					\
	IODEBUG(AMD_DDM_INDEX, DDM_IOTHREAD, x, a, b, c, d, e)

#define ddm_init(x, a, b, c, d, e) 					\
	IODEBUG(AMD_DDM_INDEX, DDM_INIT, x, a, b, c, d, e)

/*
 * catch both I/O thread events and interrupt events.
 */
#define ddm_intr(x, a, b, c, d, e) 					\
	IODEBUG(AMD_DDM_INDEX, (DDM_IOTHREAD | DDM_INTR), x, a, b, c, d, e)

#define ddm_chip(x, a, b, c, d, e) 					\
	IODEBUG(AMD_DDM_INDEX, DDM_CHIP, x, a, b, c, d, e)

#define ddm_err(x, a, b, c, d, e) 					\
	IODEBUG(AMD_DDM_INDEX, DDM_ERROR, x, a, b, c, d, e)

#define ddm_dma(x, a, b, c, d, e) 					\
	IODEBUG(AMD_DDM_INDEX, DDM_DMA, x, a, b, c, d, e)

