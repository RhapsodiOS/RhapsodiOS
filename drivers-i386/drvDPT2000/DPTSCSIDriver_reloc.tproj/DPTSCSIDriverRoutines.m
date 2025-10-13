/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * DPTSCSIDriverRoutines.m - Utility routines for DPT SCSI driver.
 *
 * HISTORY
 *
 * Created for Rhapsody OS
 */

#import "DPTSCSIDriver.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <kernserv/prototypes.h>

@implementation DPTSCSIDriver(Private)

/*
 * Initialize EATA controller.
 */
- (IOReturn)eataInitController
{
	unsigned char status;
	struct eata_config eataConfig;
	int i;

	/* Read configuration */
	outb(ioBase + EATA_CMD, EATA_CMD_READ_CONFIG);

	/* Wait for command to complete */
	for (i = 0; i < 1000; i++) {
		IODelay(10);
		status = inb(ioBase + EATA_STATUS);
		if (!(status & EATA_STAT_BUSY)) {
			break;
		}
	}

	if (status & EATA_STAT_BUSY) {
		IOLog("%s: Controller not responding\n", [self name]);
		return IO_R_IO;
	}

	/* Read configuration data */
	unsigned char *configPtr = (unsigned char *)&eataConfig;
	for (i = 0; i < sizeof(struct eata_config); i++) {
		configPtr[i] = inb(ioBase + EATA_DATA);
	}

	/* Verify EATA signature */
	if (eataConfig.signature[0] != 'E' ||
	    eataConfig.signature[1] != 'A' ||
	    eataConfig.signature[2] != 'T' ||
	    eataConfig.signature[3] != 'A') {
		IOLog("%s: Invalid EATA signature\n", [self name]);
		return IO_R_IO;
	}

	/* Store configuration */
	config.scsi_id = eataConfig.scsi_id & 0x07;
	config.max_targets = 8;
	config.max_luns = 8;
	config.dma_channel = eataConfig.dmaChannel;
	config.irq_level = eataConfig.irqNumber;
	config.io_base = ioBase;
	config.wide_bus = NO;
	config.ultra_enabled = NO;

	scsiId = config.scsi_id;

	IOLog("%s: EATA Controller at 0x%x, IRQ %d, DMA %d, SCSI ID %d\n",
	      [self name], ioBase, config.irq_level, config.dma_channel, scsiId);

	return IO_R_SUCCESS;
}

/*
 * Reset EATA bus.
 */
- (IOReturn)eataResetBus
{
	unsigned char status;
	int i;

	IOLog("%s: Resetting SCSI bus\n", [self name]);

	/* Send reset command */
	outb(ioBase + EATA_CMD, EATA_CMD_RESET);

	/* Wait for reset to complete */
	for (i = 0; i < 5000; i++) {
		IODelay(1000);
		status = inb(ioBase + EATA_STATUS);
		if (!(status & EATA_STAT_BUSY)) {
			break;
		}
	}

	if (status & EATA_STAT_BUSY) {
		IOLog("%s: Reset timeout\n", [self name]);
		return IO_R_IO;
	}

	/* Wait for bus to settle */
	IOSleep(1000);

	return IO_R_SUCCESS;
}

/*
 * Allocate resources.
 */
- (IOReturn)eataAllocateResources
{
	int i;

	/* Allocate CP array */
	cpArray = (struct eata_cp *)IOMalloc(DPT_NUM_CPS * sizeof(struct eata_cp));
	if (cpArray == NULL) {
		IOLog("%s: Failed to allocate CP array\n", [self name]);
		return IO_R_NO_MEMORY;
	}

	/* Initialize CPs */
	bzero(cpArray, DPT_NUM_CPS * sizeof(struct eata_cp));
	for (i = 0; i < DPT_NUM_CPS; i++) {
		cpArray[i].in_use = FALSE;
	}

	numFreeCps = DPT_NUM_CPS;

	return IO_R_SUCCESS;
}

/*
 * Free resources.
 */
- (void)eataFreeResources
{
	if (cpArray) {
		IOFree(cpArray, DPT_NUM_CPS * sizeof(struct eata_cp));
		cpArray = NULL;
	}
}

/*
 * Allocate a CP.
 */
- (struct eata_cp *)allocCp
{
	int i;

	for (i = 0; i < DPT_NUM_CPS; i++) {
		if (!cpArray[i].in_use) {
			cpArray[i].in_use = TRUE;
			numFreeCps--;
			return &cpArray[i];
		}
	}

	return NULL;
}

/*
 * Free a CP.
 */
- (void)freeCp:(struct eata_cp *)cp
{
	if (cp) {
		cp->in_use = FALSE;
		cp->cmdBuf = NULL;
		numFreeCps++;
	}
}

@end
