/*
 * FloppyCmds.m - Command methods for FloppyController
 *
 * This category contains high-level command methods for executing
 * floppy controller operations.
 */

#import "FloppyCmds.h"
#import "FloppyCnt.h"
#import "FloppyArch.h"
#import "FloppyCntIo.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/ioPorts.h>

/*
 * Global counter (likely for statistics or debugging).
 * The name __xxx.86 from the decompiled code suggests a compiler-generated
 * or obfuscated variable name.
 */
static unsigned int _motorChangeCount = 0;

@implementation FloppyController(Cmds)

/*
 * Execute a command transfer.
 * From decompiled code: performs the actual command execution.
 *
 * This is the main command execution method that handles all floppy
 * controller commands (read, write, format, seek, etc.).
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure containing:
 *               - Command type
 *               - Drive number
 *               - Cylinder, head, sector
 *               - Buffer and length (for data transfers)
 *               - Result buffer
 *
 * Returns:
 *   IO_R_SUCCESS on success, error code otherwise
 */
- (IOReturn)_doCmdXfr:(void *)cmdParams
{
	// TODO: Implement command transfer execution
	// This should:
	// - Turn on motor if needed
	// - Seek to correct track if needed
	// - Set up DMA for data transfers
	// - Send command bytes to controller
	// - Wait for interrupt
	// - Read result bytes
	// - Handle errors and retries
	// - Turn off motor (or start motor timeout)

	return IO_R_SUCCESS;
}

/*
 * Eject the floppy disk.
 * From decompiled code: sets result to success.
 *
 * The actual eject sequence (seek to track 79, motor off) is likely
 * handled elsewhere or not implemented for PC floppy drives which
 * don't have motorized eject.
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure
 *
 * Returns:
 *   IO_R_SUCCESS (always)
 */
- (IOReturn)_doEject:(void *)cmdParams
{
	// Set result status to 0 (success) at offset 0x40
	*(unsigned int *)((char *)cmdParams + 0x40) = 0;

	return IO_R_SUCCESS;
}

/*
 * Turn off the drive motor.
 * From decompiled code: clears motor bit in DOR register.
 *
 * The DOR (Digital Output Register) at I/O port 0x3F2 controls:
 * - Bits 0-1: Drive select (which drive is active)
 * - Bit 2: Reset (0 = reset active, 1 = normal operation)
 * - Bit 3: DMA/IRQ enable
 * - Bits 4-7: Motor enable (bit 4 = drive 0, bit 5 = drive 1, etc.)
 *
 * Parameters:
 *   driveNum - Drive number (0-3)
 *
 * Returns:
 *   IO_R_SUCCESS
 */
- (IOReturn)_doMotorOff:(unsigned int)driveNum
{
	unsigned char motorBit;

	// Calculate motor enable bit for this drive
	// Motor bit = (0x10 << driveNum)
	// Drive 0: bit 4 (0x10), Drive 1: bit 5 (0x20), etc.
	motorBit = (unsigned char)(0x10 << (driveNum & 0x1f));

	// Clear the motor bit for this drive
	_dorRegister = _dorRegister & ~motorBit;

	// Set the drive select bits to this drive number
	_dorRegister = _dorRegister | (unsigned char)driveNum;

	// Write updated DOR value to hardware
	outb(0x3f2, _dorRegister);

	// Increment motor change counter (atomic operation with LOCK)
	// This is likely for statistics or debugging
	_motorChangeCount++;

	return IO_R_SUCCESS;
}

/*
 * Turn on the drive motor.
 * From decompiled code: sets motor bit in DOR register and waits for spin-up.
 *
 * This method checks if the motor is already running. If not, it turns on
 * the motor and waits for spin-up (1000ms).
 *
 * Parameters:
 *   driveNum - Drive number (0-3)
 *
 * Returns:
 *   IO_R_SUCCESS
 */
- (IOReturn)_doMotorOn:(unsigned int)driveNum
{
	unsigned char motorBit;

	// Calculate motor enable bit for this drive
	// Motor bit = (0x10 << driveNum)
	// Drive 0: bit 4 (0x10), Drive 1: bit 5 (0x20), etc.
	motorBit = (unsigned char)(0x10 << (driveNum & 0x1f));

	// Check if motor is already on
	if ((motorBit & _dorRegister) == 0) {
		// Motor is off, turn it on

		// Set motor bit, drive select bits, and preserve other bits
		_dorRegister = motorBit | (unsigned char)driveNum | _dorRegister;

		// Write updated DOR value to hardware
		outb(0x3f2, _dorRegister);

		// Increment motor change counter (atomic operation with LOCK)
		_motorChangeCount++;

		// Wait for motor spin-up (1000ms = 1 second)
		IOSleep(1000);
	}

	return IO_R_SUCCESS;
}

/*
 * Send a command to the floppy controller.
 * From decompiled code: sends command bytes, handles DMA, waits for interrupt, reads results.
 *
 * This is the core command execution method. It handles all FDC commands including
 * data transfer commands (read/write/format) with DMA support.
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure containing:
 *               - offset 0x04: Timeout value
 *               - offset 0x0c: Command bytes buffer
 *               - offset 0x1c: Number of command bytes
 *               - offset 0x24: DMA byte count
 *               - offset 0x28: Result bytes buffer
 *               - offset 0x38: Number of expected result bytes
 *               - offset 0x3c: Flags (bit 1 = read/write)
 *               - offset 0x40: Result status (output)
 *               - offset 0x44: Bytes sent count (output)
 *               - offset 0x48: Transferred bytes count (output)
 *               - offset 0x4c: Result bytes received count (output)
 *
 * Returns:
 *   0 on success, error code otherwise
 */
- (IOReturn)_sendCmd:(void *)cmdParams
{
	DMATransferStruct dmaStruct;
	IOReturn result = 0;
	BOOL dmaActive = NO;
	BOOL timeoutOccurred = NO;
	BOOL needsInterrupt;
	BOOL errorDetected = NO;
	unsigned char cmdOpcode;
	unsigned char *cmdBytesPtr;
	unsigned char *resultBytesPtr;
	unsigned int i;
	unsigned int cmdByteCount;
	unsigned int resultByteCount;
	unsigned int dmaByteCount;
	unsigned int timeout;
	unsigned char isRead;
	unsigned char byte;
	unsigned char st0, st1, st2;

	// Get command opcode (offset 0x0c + 3) and mask to 5 bits
	cmdOpcode = *(unsigned char *)((char *)cmdParams + 0x0f) & 0x1f;

	// Initialize result fields
	*(unsigned int *)((char *)cmdParams + 0x40) = 0xffffffff;  // Result status
	*(unsigned int *)((char *)cmdParams + 0x44) = 0;           // Bytes sent
	*(unsigned int *)((char *)cmdParams + 0x48) = 0;           // Transferred bytes
	*(unsigned int *)((char *)cmdParams + 0x4c) = 0;           // Result bytes received

	// Get read/write flag (offset 0x3c, bit 1), inverted
	isRead = ((*(unsigned char *)((char *)cmdParams + 0x3c) >> 1) ^ 1) & 1;

	// Get DMA byte count (offset 0x24)
	dmaByteCount = *(unsigned int *)((char *)cmdParams + 0x24);

	// Start DMA if byte count > 0
	if (dmaByteCount > 0) {
		result = [self _dmaStart:cmdParams dmaStruct:&dmaStruct];
		_get_dma_addr(2);  // Debug/verify
		_get_dma_count(2); // Debug/verify

		if (result != 0) {
			goto cleanup;
		}
		dmaActive = YES;
	}

	// Determine if this command needs an interrupt
	switch (cmdOpcode) {
	case 0x03:  // SPECIFY
	case 0x04:  // SENSE DRIVE STATUS
	case 0x08:  // SENSE INTERRUPT STATUS
	case 0x0e:  // DUMPREG
	case 0x10:  // VERSION
	case 0x12:  // PERPENDICULAR MODE
	case 0x13:  // CONFIGURE
		needsInterrupt = NO;
		break;
	default:
		// Flush any pending interrupt messages
		result = [self _flushIntrMsgs];
		if (result != 0) {
			goto cleanup;
		}
		needsInterrupt = YES;
		break;
	}

	// Send command bytes
	cmdBytesPtr = (unsigned char *)((char *)cmdParams + 0x0c + 3);
	cmdByteCount = *(unsigned int *)((char *)cmdParams + 0x1c);

	for (i = 0; i < cmdByteCount; i++) {
		byte = cmdBytesPtr[i];
		result = [self _fcSendByte:byte];

		if (result != 0) {
			// Set controller hung flag on phase error
			if (result == 10) {  // Bad phase
				_flags |= 0x01;
			}
			goto cleanup;
		}

		// Increment bytes sent counter
		*(unsigned int *)((char *)cmdParams + 0x44) += 1;
	}

	// Wait for interrupt if needed
	if (needsInterrupt) {
		timeout = *(unsigned int *)((char *)cmdParams + 0x04);

		// Use longer timeout for SEEK (0x04) and RECAL (0x0a)
		if ((cmdOpcode != 0x04 && cmdOpcode != 0x0a) && timeout < 2001) {
			timeout = 2000;
		}

		result = [self _fcWaitIntr:cmdParams timeout:timeout];
	}

	if (result != 0) {
		if (result == 1) {  // Timeout
			timeoutOccurred = YES;
		}
		// Don't goto cleanup yet if timeout - still try to read results
	}

	if (timeoutOccurred) {
		goto cleanup;
	}

	// Read result bytes
	resultByteCount = *(unsigned int *)((char *)cmdParams + 0x38);
	resultBytesPtr = (unsigned char *)((char *)cmdParams + 0x28) +
	                 *(unsigned int *)((char *)cmdParams + 0x4c) + 3;

	for (i = *(unsigned int *)((char *)cmdParams + 0x4c); i < resultByteCount; i++) {
		result = [self _fcGetByte:resultBytesPtr];

		if (result != 0) {
			// Allow phase error if we got at least one result byte
			if (result != 10 || *(unsigned int *)((char *)cmdParams + 0x4c) == 0) {
				goto cleanup;
			}
			break;
		}

		*(unsigned int *)((char *)cmdParams + 0x4c) += 1;
		resultBytesPtr++;
	}

	// Complete DMA if active
	if (dmaActive) {
		result = [self _dmaDone:cmdParams dmaStruct:&dmaStruct];
		_get_dma_addr(2);  // Debug/verify
		_get_dma_count(2); // Debug/verify
		dmaActive = NO;

		if (result != 0) {
			goto cleanup;
		}
	}

	if (result != 0) {
		goto cleanup;
	}

	// Analyze results for data transfer commands
	switch (cmdOpcode) {
	case 0x02:  // READ TRACK
	case 0x05:  // WRITE DATA
	case 0x06:  // READ DATA
	case 0x09:  // WRITE DELETED DATA
	case 0x0a:  // READ ID
	case 0x0c:  // READ DELETED DATA
	case 0x0d:  // FORMAT TRACK
	case 0x16:  // VERIFY
		// Check if we got result bytes
		if (*(unsigned int *)((char *)cmdParams + 0x4c) == 0) {
			result = 0x12;  // No results
			break;
		}

		// Get status registers
		st0 = ((unsigned char *)((char *)cmdParams + 0x28))[3];
		st1 = ((unsigned char *)((char *)cmdParams + 0x28))[4];
		st2 = ((unsigned char *)((char *)cmdParams + 0x28))[5];

		// Check ST0 bits 7-6 (error bits)
		if ((st0 & 0xc0) == 0) {
			// Success - calculate transferred bytes for read/write
			if (isRead == 1 && dmaByteCount != 0) {
				if (cmdOpcode == 0x05 || cmdOpcode == 0x09) {
					// WRITE commands - calculate from end sector
					unsigned char sectorSize = ((unsigned char *)((char *)cmdParams + 0x0c))[8];
					unsigned char endSector = ((unsigned char *)((char *)cmdParams + 0x28))[8];
					unsigned char startSector = ((unsigned char *)((char *)cmdParams + 0x0c))[7];

					*(unsigned int *)((char *)cmdParams + 0x48) =
						(1 << ((sectorSize + 7) & 0x1f)) * (endSector - startSector);
				} else {
					*(unsigned int *)((char *)cmdParams + 0x48) = dmaByteCount;
				}
			}

			// Check ST1 for errors
			if ((st1 & 0x20) != 0) {
				result = 7;  // CRC error
				if ((st2 & 0x20) != 0) {
					result = 6;  // Deleted mark
				}
			} else if ((st1 & 0x10) != 0) {
				result = 0x13;  // Overrun
			} else if ((st1 & 0x04) != 0) {
				result = 0x0c;  // No data
			} else if ((st1 & 0x02) != 0) {
				result = 0x0d;  // Write protect
			} else if ((st1 & 0x01) != 0) {
				result = 0x0e;  // Missing address mark
			} else {
				// Check ST2
				if ((st2 & 0x40) != 0) {
					result = 0x0f;  // Deleted mark in data field
				} else if ((st2 & 0x12) != 0) {
					result = 9;  // Bad cylinder/sector
				} else if ((st2 & 0x01) != 0) {
					result = 0x10;  // Bad track
				}
			}

			break;
		}

		// ST0 error detected
		errorDetected = YES;

		if (st1 == 0x80 || (st0 & 0x10) != 0) {
			result = 0x0b;  // Equipment check
		} else if (*(unsigned int *)((char *)cmdParams + 0x4c) < 7) {
			result = 8;  // Incomplete results
		} else {
			// Analyze detailed error status
			if (isRead == 1 && dmaByteCount != 0) {
				if (cmdOpcode == 0x05 || cmdOpcode == 0x09) {
					unsigned char sectorSize = ((unsigned char *)((char *)cmdParams + 0x0c))[8];
					unsigned char endSector = ((unsigned char *)((char *)cmdParams + 0x28))[8];
					unsigned char startSector = ((unsigned char *)((char *)cmdParams + 0x0c))[7];

					*(unsigned int *)((char *)cmdParams + 0x48) =
						(1 << ((sectorSize + 7) & 0x1f)) * (endSector - startSector);
				} else {
					*(unsigned int *)((char *)cmdParams + 0x48) = dmaByteCount;
				}
			}

			// Detailed error analysis (same as success path above)
			if ((st1 & 0x20) != 0) {
				result = 7;
				if ((st2 & 0x20) != 0) {
					result = 6;
				}
			} else if ((st1 & 0x10) != 0) {
				result = 0x13;
			} else if ((st1 & 0x04) != 0) {
				result = 0x0c;
			} else if ((st1 & 0x02) != 0) {
				result = 0x0d;
			} else if ((st1 & 0x01) != 0) {
				result = 0x0e;
			} else {
				if ((st2 & 0x40) != 0) {
					result = 0x0f;
				} else if ((st2 & 0x12) != 0) {
					result = 9;
				} else if ((st2 & 0x01) != 0) {
					result = 0x10;
				}
			}
		}

		if (errorDetected) {
			*(unsigned int *)((char *)cmdParams + 0x48) = 0;
		}
		break;

	case 0x07:  // RECALIBRATE
		// Check for successful recalibrate (SE=1, PCN=0, IC=0)
		if ((((unsigned char *)((char *)cmdParams + 0x28))[3] & 0x20) != 0 &&
		    ((unsigned char *)((char *)cmdParams + 0x28))[4] == 0 &&
		    (((unsigned char *)((char *)cmdParams + 0x28))[3] & 0x10) == 0) {
			_field_140 = 0;
			goto cleanup;
		}
		break;

	case 0x0f:  // SEEK
		// Check seek status
		if ((((unsigned char *)((char *)cmdParams + 0x28))[3] & 0x20) != 0) {
			if (((unsigned char *)((char *)cmdParams + 0x0c))[3] >= 0x80) {
				_field_140 = 0xffff;
				goto cleanup;
			}
			if (((unsigned char *)((char *)cmdParams + 0x0c))[5] ==
			    ((unsigned char *)((char *)cmdParams + 0x28))[4]) {
				_field_140 = ((unsigned char *)((char *)cmdParams + 0x0c))[5];
				goto cleanup;
			}
		}
		break;
	}

	result = 9;  // Generic error

cleanup:
	// Abort DMA if still active
	if (dmaActive) {
		_dma_mask_chan(2);
		_dma_xfer_abort(&dmaStruct);
		[self releaseDMALock];
	}

	// Set result to timeout if flag is set
	if (timeoutOccurred) {
		result = 1;
	}

	// Mark controller state as bad on error
	if (result != 0) {
		_field_140 = 0xffff;
	}

	return result;
}

@end

/* End of FloppyCmds.m */
