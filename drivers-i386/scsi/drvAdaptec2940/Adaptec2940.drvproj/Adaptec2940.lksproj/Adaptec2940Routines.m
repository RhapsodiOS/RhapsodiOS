/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * Adaptec2940Routines.m - Hardware routines for Adaptec 2940.
 *
 * HISTORY
 *
 * Created for Rhapsody OS
 */

#import "Adaptec2940.h"
#import <driverkit/generalFuncs.h>
#import <kernserv/prototypes.h>
#import <string.h>

@implementation Adaptec2940(Private)

/*
 * Initialize the AIC-7xxx controller.
 */
- (IOReturn)aicInitController
{
	unsigned char sblkctl, scsiid;
	int i;

	/* Pause the sequencer */
	outb(ioBase + AIC_SEQCTL, SEQRESET | FASTMODE);
	IODelay(1000);

	/* Reset SCSI bus */
	outb(ioBase + AIC_SCSISEQ, SCSIRSTO);
	IODelay(1000);
	outb(ioBase + AIC_SCSISEQ, 0);
	IODelay(1000);

	/* Get SCSI ID */
	scsiid = inb(ioBase + AIC_SCSIID) & 0x0f;
	config.scsi_id = scsiid;
	config.max_targets = 8;
	config.max_luns = 8;

	/* Check for wide bus */
	sblkctl = inb(ioBase + AIC_SBLKCTL);
	config.wide_bus = (sblkctl & 0x02) ? TRUE : FALSE;
	if (config.wide_bus) {
		config.max_targets = 16;
	}

	/* Clear interrupts */
	outb(ioBase + AIC_CLRINT, 0xff);

	IOLog("%s: AIC-7xxx SCSI ID %d, %s bus\n",
	      [self name],
	      config.scsi_id,
	      config.wide_bus ? "Wide" : "Narrow");

	return IO_R_SUCCESS;
}

/*
 * Reset the SCSI bus.
 */
- (IOReturn)aicResetBus
{
	int i;

	/* Assert SCSI reset */
	outb(ioBase + AIC_SCSISEQ, SCSIRSTO);
	IODelay(25000);  /* 25ms reset pulse */

	/* Deassert reset */
	outb(ioBase + AIC_SCSISEQ, 0);
	IODelay(250000);  /* 250ms recovery time */

	/* Clear any pending interrupts */
	outb(ioBase + AIC_CLRINT, 0xff);

	/* Abort all outstanding commands */
	while (!queue_empty(&outstandingQ)) {
		struct scb *scb;
		queue_remove_first(&outstandingQ, scb, struct scb *, scbQ);
		outstandingCount--;

		if (scb->cmdBuf) {
			Adaptec2940CommandBuf *cmdBuf = (Adaptec2940CommandBuf *)scb->cmdBuf;
			cmdBuf->scsiReq->driverStatus = SR_IOST_RESET;
			[self completeRequest:cmdBuf->scsiReq];
			IOFree(cmdBuf, sizeof(Adaptec2940CommandBuf));
		}

		[self freeScb:scb];
	}

	IOLog("%s: SCSI bus reset complete\n", [self name]);

	return IO_R_SUCCESS;
}

/*
 * Allocate controller resources.
 */
- (IOReturn)aicAllocateResources
{
	int i;

	/* Allocate SCB array */
	scbArray = (struct scb *)IOMalloc(AIC_NUM_SCBS * sizeof(struct scb));
	if (scbArray == NULL) {
		IOLog("%s: Cannot allocate SCB array\n", [self name]);
		return IO_R_NO_MEMORY;
	}

	/* Initialize SCBs */
	bzero(scbArray, AIC_NUM_SCBS * sizeof(struct scb));
	for (i = 0; i < AIC_NUM_SCBS; i++) {
		scbArray[i].in_use = FALSE;
		scbArray[i].tag = i;
		scbArray[i].next = (i + 1) % AIC_NUM_SCBS;
		scbArray[i].prev = (i - 1 + AIC_NUM_SCBS) % AIC_NUM_SCBS;
	}

	numFreeScbs = AIC_NUM_SCBS;

	return IO_R_SUCCESS;
}

/*
 * Free controller resources.
 */
- (void)aicFreeResources
{
	if (scbArray) {
		IOFree(scbArray, AIC_NUM_SCBS * sizeof(struct scb));
		scbArray = NULL;
	}
}

@end
