/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * EATAControllerPrivate.h - private selectors and command-buf layout.
 *
 * HISTORY
 *
 * Reconstructed from DPTSCSIDriver_reloc. Categories match the
 * compiled modules: EATAController.m (PrivateMethods) and
 * EATAThread.m (IOThread). EATAExported is a protocol name only.
 */

#ifndef _EATACONTROLLERPRIVATE_H
#define _EATACONTROLLERPRIVATE_H

#import <machkit/NXLock.h>
#import <mach/mach_types.h>
#import <mach/message.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/return.h>
#import <driverkit/scsiTypes.h>
#import <kernserv/queue.h>
#import <driverkit/machine/directDevice.h>
#import "EATAControllerTypes.h"

#if !(defined(i386) || defined(__i386__))
/*
 * ppc rbuild has no EISA device-description / ISA DMA selectors.
 * Declare them so the i386 bodies type-check.
 */
@interface Object(EATAEISADeviceDescription)
- (IOReturn)getEISASlotNumber:(unsigned int *)slotNum;
- (IOReturn)setPortRangeList:(IORange *)list num:(unsigned int)numRanges;
- (unsigned int)numPortRanges;
- (IORange *)portRangeList;
@end
@interface IODirectDevice(EATAEISADMA)
- (IOReturn)enableChannel:(unsigned int)localChannel;
- (IOReturn)setTransferMode:(int)mode forChannel:(unsigned int)localChannel;
- (void)reserveDMALock;
- (void)releaseDMALock;
- (IOEISADMABuffer)createDMABufferFor:(unsigned int *)physAddr
			      length:(unsigned int)length
				read:(BOOL)isRead
		      needsLowMemory:(BOOL)lowerMem
			   limitSize:(BOOL)limitSize;
- (void)freeDMABuffer:(IOEISADMABuffer)buffer;
- (void)abortDMABuffer:(IOEISADMABuffer)buffer;
@end
#endif

@interface Object(EATABusOwner)
- (unsigned)numReserved;
@end

/*
 * Op at command-buf +0x04. commandRequestOccurred compares eax against
 * 0 / 1 / 2 and sends threadExecuteRequest:, threadResetBus:initConfig:,
 * or IOExitThread.
 */
typedef enum {
	EO_Execute,		/* 0 */
	EO_Reset,		/* 1 */
	EO_Abort		/* 2 */
} EATAOp;

/*
 * Reason for -commandCompleted:reason:. interruptOccurred pushes 0,
 * timeoutOccurred pushes 1, threadResetBus:initConfig: pushes 2.
 */
typedef enum {
	CS_Complete,
	CS_Timeout,
	CS_Reset
} completeStatus;

/*
 * Stack / heap object passed to executeCmdBuf:. Offsets from
 * -[EATASCSIBus executeRequest:buffer:client:] and executeCmdBuf:.
 */
typedef struct EATACommandBuf {
	unsigned int		scsiChannel;	/* +0x00 */
	EATAOp			op;		/* +0x04 */
	IOSCSIRequest		*scsiReq;	/* +0x08 */
	void			*buffer;	/* +0x0C */
	vm_task_t		client;		/* +0x10 */
	sc_status_t		result;		/* +0x14 */
	NXConditionLock		*cmdLock;	/* +0x18 */
	queue_chain_t		link;		/* +0x1C / +0x20 */
} EATACommandBuf;

#define CMD_PENDING	0
#define CMD_COMPLETE	1

/*
 * Compiled from EATAController.m as EATAController(PrivateMethods).
 * executeCmdBuf: lives on the class method list; declared here with the
 * other non-exported controller entry points.
 */
@interface EATAController(PrivateMethods)

- (BOOL)probeAtPortBase:(unsigned short)port;
- (BOOL)readConfig;
- (BOOL)readDMAConfig;
- (IOReturn)executeCmdBuf:(EATACommandBuf *)cmdBuf;

@end

/*
 * Compiled from EATAThread.m as EATAController(IOThread).
 */
@interface EATAController(IOThread)

- (void)threadExecuteRequest:(EATACommandBuf *)cmdBuf;
- (void)commandCompleted:(struct ccb *)ccb
		  reason:(completeStatus)status;
- (void)clearResetInts;
- threadResetBus:(EATACommandBuf *)cmdBuf
      initConfig:(BOOL)initConfig;
- (struct ccb *)allocCcb:(BOOL)doDMA;
- (void)freeCcb:(struct ccb *)ccb;
- (void)completeDMA:(IOEISADMABuffer *)dmaList;
- (void)abortDMA:(IOEISADMABuffer *)dmaList;
- (struct ccb *)ccbFromCmd:(EATACommandBuf *)cmdBuf;

@end

int eata_busy(unsigned short ioBase, int count);
int eata_busy_0(unsigned short ioBase, int count);
BOOL parseConfigSpace(id deviceDescription, const char *title,
		unsigned regSize, unsigned short *baseAddr);
void eataTimeout(void *arg);

#endif /* _EATACONTROLLERPRIVATE_H */
