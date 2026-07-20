/*
 * FloppyArch.m - Architecture-specific methods for FloppyController
 *
 * This category contains platform-specific (i386) DMA methods for the
 * floppy controller driver.
 */

#import "FloppyArch.h"
#import "FloppyCnt.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/directDevice.h>
#import <driverkit/i386/dma.h>
#import <kernserv/kern_server_types.h>
#import <mach/vm_map.h>

// External kernel variables
extern kern_server_t kernel_map;
extern unsigned int page_size;

@implementation FloppyController(Arch)

/*
 * Start a DMA transfer.
 * From decompiled code: sets up ISA/EISA DMA controller for floppy transfer.
 *
 * This method configures the DMA controller to perform a transfer between
 * the floppy controller and memory. For ISA systems, it uses a bounce buffer
 * for transfers larger than one page.
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure containing:
 *               - offset 0x04: VM map
 *               - offset 0x20: Buffer address
 *               - offset 0x24: Byte count
 *               - offset 0x3c: Flags (bit 1 = read/write direction)
 *   dmaStruct - Pointer to DMA transfer structure to be filled in
 *
 * Returns:
 *   0 on success, 4 (IO_R_INVALID_ARG) on error
 */
- (int)_dmaStart:(void *)cmdParams dmaStruct:(DMATransferStruct *)dmaStruct
{
	unsigned int byteCount;
	unsigned int vmMap;
	unsigned int bufferAddr;
	unsigned int pmap;
	void *physAddr;
	unsigned int physAddrInt;
	BOOL isRead;
	BOOL isEISA;
	int result;

	// Get byte count from cmdParams (offset 0x24)
	byteCount = *(unsigned int *)((char *)cmdParams + 0x24);

	// Get VM map from cmdParams (offset 0x04)
	vmMap = *(unsigned int *)((char *)cmdParams + 0x04);

	// Get buffer address from cmdParams (offset 0x20)
	bufferAddr = *(unsigned int *)((char *)cmdParams + 0x20);

	// Get physical address from virtual address
	pmap = _vm_map_pmap_EXTERNAL(vmMap, bufferAddr);
	physAddr = (void *)_pmap_resident_extract(pmap);

	result = 0;

	// Check if byte count is valid (<= 1MB for EISA, <= page_size for ISA)
	if ((byteCount < 0x100001) &&
	    ((isEISA = [self isEISAPresent]) || (byteCount <= page_size))) {

		// Get read/write flag from cmdParams (offset 0x3c, bit 1)
		isRead = (*(unsigned char *)((char *)cmdParams + 0x3c) & 0x02) != 0;

		// Set DMA direction flag in dmaStruct (bit 3)
		if (!isRead) {
			// Write to device (clear bit 3)
			dmaStruct->field4_0x14.bitField0_1 &= 0xf7;
		} else {
			// Read from device (set bit 3)
			dmaStruct->field4_0x14.bitField0_1 |= 0x08;
		}

		// Clear bit 3 of controller flags
		_flags &= 0xf7;

		// Check if we need to use bounce buffer (ISA only)
		if (!isEISA) {
			// Set bit 3 of controller flags (using bounce buffer)
			_flags |= 0x08;

			// If writing to device, copy data to bounce buffer
			if (!isRead) {
				bcopy(physAddr, _dmaBuffer, byteCount);
			}

			// Get physical address of bounce buffer
			pmap = _vm_map_pmap_EXTERNAL((unsigned int)kernel_map,
			                              (unsigned int)_dmaBuffer);
			physAddrInt = _pmap_resident_extract(pmap);
			dmaStruct->physAddr = physAddrInt;
		} else {
			// EISA - use buffer directly
			dmaStruct->physAddr = (unsigned int)physAddr;
		}

		// Set byte count
		dmaStruct->byteCount = byteCount;

		// Set DMA channel (always 2 for floppy)
		dmaStruct->channel = 2;

		// Clear bit 1 (auto-init)
		dmaStruct->field4_0x14.bitField0_1 &= 0xfd;

		// Set bit 2
		dmaStruct->field4_0x14.bitField0_1 |= 0x04;

		// Clear bit 4
		dmaStruct->field4_0x14.bitField0_1 &= 0xef;

		// Clear bit 5
		dmaStruct->field4_0x14.bitField0_1 &= 0xdf;

		// Reserve DMA lock
		[self reserveDMALock];

		// Mask the DMA channel
		_dma_mask_chan(2);

		// Set transfer mode (ISA vs EISA)
		_dma_chan_xfer_mode(2, !isEISA);

		// Start the DMA transfer
		result = _dma_xfer_chan(2, dmaStruct);

		if (result != 1) {
			// Transfer failed
			result = 4;  // IO_R_INVALID_ARG
			[self releaseDMALock];
		} else {
			result = 0;  // Success
		}
	} else {
		// Byte count too large
		result = 4;  // IO_R_INVALID_ARG
		IOLog("Floppy: DMA byte count > 64K\n");
	}

	return result;
}

/*
 * Complete a DMA transfer.
 * From decompiled code: cleans up after DMA transfer completes.
 *
 * This method waits for DMA completion, verifies the transfer, and copies
 * data from the bounce buffer if necessary (ISA read operations).
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure containing:
 *               - offset 0x04: VM map
 *               - offset 0x20: Buffer address
 *               - offset 0x24: Byte count
 *   dmaStruct - Pointer to DMA transfer structure
 *
 * Returns:
 *   0 on success
 */
- (int)_dmaDone:(void *)cmdParams dmaStruct:(DMATransferStruct *)dmaStruct
{
	unsigned int vmMap;
	unsigned int bufferAddr;
	unsigned int pmap;
	void *physAddr;
	int retries;
	int isDone;
	unsigned int remainingCount;
	unsigned int transferredBytes;
	unsigned int requestedBytes;

	// Get VM map and buffer address from cmdParams
	vmMap = *(unsigned int *)((char *)cmdParams + 0x04);
	bufferAddr = *(unsigned int *)((char *)cmdParams + 0x20);

	// Get physical address
	pmap = _vm_map_pmap_EXTERNAL(vmMap, bufferAddr);
	physAddr = (void *)_pmap_resident_extract(pmap);

	// Wait for DMA to complete (up to 2 retries with 2ms delay)
	retries = 2;
	while (1) {
		isDone = _is_dma_done(2);
		if (isDone != 0) {
			break;
		}

		retries--;
		if (retries == -1) {
			break;
		}

		IOSleep(2);
	}

	// Mask the DMA channel
	_dma_mask_chan(2);

	// Get remaining byte count from DMA controller
	remainingCount = _get_dma_count(2);

	// Get requested byte count (offset 0x24)
	requestedBytes = *(unsigned int *)((char *)cmdParams + 0x24);

	// Verify that remaining count is not greater than requested
	if (requestedBytes < remainingCount) {
		panic("FloppyArch: Invalid dma byte count\n");
	}

	// Calculate actual transferred bytes
	transferredBytes = requestedBytes - remainingCount;

	// Store transferred byte count in cmdParams (offset 0x48)
	*(unsigned int *)((char *)cmdParams + 0x48) = transferredBytes;

	// Store in dmaStruct as well
	dmaStruct->byteCount = transferredBytes;

	// If using bounce buffer and this was a read operation, copy data back
	if ((_flags & 0x08) != 0) {
		// Check if this was a read operation (bit 3 of dmaStruct flags)
		if ((dmaStruct->field4_0x14.bitField0_1 & 0x08) != 0) {
			// Copy from bounce buffer to user buffer
			bcopy(_dmaBuffer, physAddr, transferredBytes);
		}

		// Clear bounce buffer flag (bit 3 of controller flags)
		_flags &= 0xf7;
	}

	// Complete the DMA transfer
	_dma_xfer_done(dmaStruct);

	// Release the DMA lock
	[self releaseDMALock];

	return 0;
}

@end

/* End of FloppyArch.m */
