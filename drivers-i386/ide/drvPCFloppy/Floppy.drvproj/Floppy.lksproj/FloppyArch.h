/*
 * FloppyArch.h - Architecture-specific methods for FloppyController
 *
 * This category contains platform-specific (i386) DMA methods
 */

#ifdef DRIVER_PRIVATE

#ifndef _BSD_DEV_I386_FLOPPYARCH_H_
#define _BSD_DEV_I386_FLOPPYARCH_H_

#import "FloppyCnt.h"
#import <driverkit/return.h>

/*
 * DMA transfer structure for ISA/EISA DMA operations.
 * This is the hardware DMA descriptor structure.
 */
typedef struct {
	unsigned int    physAddr;       // offset 0x00: Physical address for DMA
	unsigned int    byteCount;      // offset 0x04: Number of bytes to transfer
	unsigned int    channel;        // offset 0x08: DMA channel number
	unsigned int    field_0x0c;     // offset 0x0c: Reserved/padding
	unsigned int    field_0x10;     // offset 0x10: Reserved/padding
	struct {
		unsigned char bitField0_1;  // offset 0x14: DMA flags/control bits
		                            //   bit 1: ?
		                            //   bit 2: Auto-init
		                            //   bit 3: Read/write direction (1=read from device)
		                            //   bit 4: ?
		                            //   bit 5: ?
	} field4_0x14;
} DMATransferStruct;

/*
 * Architecture-specific category for FloppyController.
 * Contains DMA-related methods for i386 platform.
 */
@interface FloppyController(Arch)

/*
 * Start a DMA transfer.
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure
 *   dmaStruct - Pointer to DMA transfer structure
 *
 * Returns:
 *   0 on success, 4 (IO_R_INVALID_ARG) on error
 */
- (int)_dmaStart:(void *)cmdParams dmaStruct:(DMATransferStruct *)dmaStruct;

/*
 * Complete a DMA transfer.
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure
 *   dmaStruct - Pointer to DMA transfer structure
 *
 * Returns:
 *   0 on success
 */
- (int)_dmaDone:(void *)cmdParams dmaStruct:(DMATransferStruct *)dmaStruct;

@end

#endif // _BSD_DEV_I386_FLOPPYARCH_H_

#endif // DRIVER_PRIVATE

/* End of FloppyArch.h */
