/*
 * FloppyCntIo.m - Low-level I/O methods for FloppyController
 *
 * This category contains low-level hardware I/O methods for interacting
 * with the floppy controller registers and handling interrupts.
 */

#import "FloppyCntIo.h"
#import "FloppyCnt.h"
#import "FloppyCmds.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/ioPorts.h>
#import <bsd/sys/systm.h>
#import <mach/message.h>
#import <mach/mach_error.h>
#import <stdio.h>

@implementation FloppyController(IO)

/*
 * Clear polling interrupt flag.
 * From decompiled code: issues SENSE INTERRUPT STATUS commands to clear polling state.
 *
 * This method clears any pending polling interrupts by:
 * 1. Waiting for interrupt with timeout
 * 2. Issuing SENSE INTERRUPT STATUS (0x08) command 4 times
 * 3. Reading 2 result bytes after each command
 *
 * This is necessary after certain operations that may leave the controller
 * in a polling state.
 */
- (IOReturn)_clearPollIntr
{
	unsigned char local_buffer[96];
	unsigned char result_byte;
	int outer_loop;
	int inner_loop;

	// Wait for interrupt with 500ms timeout
	[self _fcWaitIntr:local_buffer timeout:500];

	// Loop 4 times to clear all possible pending interrupts
	for (outer_loop = 0; outer_loop < 4; outer_loop++) {
		// Read 2 result bytes (ST0 and PCN from previous SENSE INTERRUPT STATUS)
		for (inner_loop = 0; inner_loop < 2; inner_loop++) {
			[self _fcGetByte:&result_byte];
		}

		// Send SENSE INTERRUPT STATUS command (0x08) for first 3 iterations
		if (outer_loop < 3) {
			[self _fcSendByte:0x08];
		}
	}

	return IO_R_SUCCESS;
}

/*
 * Send CONFIGURE command to controller.
 * From decompiled code: configures controller features and FIFO.
 *
 * The CONFIGURE command sets up implied seeks, FIFO threshold, and polling.
 * This command is only sent if bit 1 of _flags (offset 0x138) is set,
 * indicating the controller supports the CONFIGURE command.
 *
 * Parameters:
 *   configByte - Configuration byte (typically 0x18):
 *                Bits 0-3: FIFO threshold - 1
 *                Bit 4: Polling disable
 *                Bit 5: FIFO disable
 *                Bit 6: Implied seeks
 *
 * Command bytes:
 *   Byte 0: 0x13 (CONFIGURE command)
 *   Byte 1: 0x00 (reserved, must be 0)
 *   Byte 2: configByte (configuration settings)
 *   Byte 3: 0x00 (precompensation start track)
 */
- (IOReturn)_doConfigure:(unsigned char)configByte
{
	unsigned char cmdBuffer[96];
	IOReturn result;

	// Check if controller supports CONFIGURE command (bit 1 of _flags at offset 0x138)
	if ((_flags & 0x02) == 0) {
		// Controller doesn't support CONFIGURE, return success
		return IO_R_SUCCESS;
	}

	// Zero out command buffer
	bzero(cmdBuffer, 0x60);

	// Build CONFIGURE command at offset 0x0c (command bytes start)
	// Based on decompiled code layout:
	// local_58 is at offset -0x58 from buffer start, which is 0x0c into the 96-byte buffer
	cmdBuffer[0x0c] = 0x13;        // Command: CONFIGURE
	cmdBuffer[0x0d] = 0;           // Byte 1: reserved (0)
	cmdBuffer[0x0e] = 0x18;        // Byte 2: configuration byte (implied seeks enabled, FIFO enabled)
	cmdBuffer[0x0f] = 0;           // Byte 3: precompensation (0)

	// Set timeout at offset 0x04 (local_60)
	*(unsigned int *)(cmdBuffer + 0x04) = 5000;

	// Set unknown field at offset 0x08 (local_5c)
	*(unsigned int *)(cmdBuffer + 0x08) = 1;

	// Set command byte count at offset 0x4c (local_48)
	*(unsigned int *)(cmdBuffer + 0x4c) = 4;

	// Send command to controller
	result = [self _sendCmd:cmdBuffer];

	return result;
}

/*
 * Send PERPENDICULAR MODE command.
 * From decompiled code: sets perpendicular recording mode.
 *
 * This method is currently unused/stubbed in the original driver.
 * The PERPENDICULAR MODE command (0x12) would be used for 2.88MB ED
 * (Extended Density) floppies, but this appears to not be implemented.
 *
 * Parameters:
 *   perpendicularMode - Perpendicular mode bits (unused)
 *   gap              - Gap length (unused)
 *
 * Returns:
 *   Always returns 0 (IO_R_SUCCESS)
 */
- (IOReturn)_doPerpendicular:(unsigned char)perpendicularMode gap:(unsigned char)gap
{
	// From decompiled code: this method simply returns 0
	// No perpendicular mode support is implemented
	return 0;
}

/*
 * Send SPECIFY command to set controller timing.
 * From decompiled code: sets step rate, head unload, and head load times based on density.
 *
 * This method configures the FDC timing parameters and data rate register
 * based on the media density (1=500kbps, 2=300kbps, 3=1Mbps).
 *
 * Parameters:
 *   density - Media density setting:
 *             1 = 500 kbps (1.44MB, 1.2MB)
 *             2 = 300 kbps (720KB, 360KB)
 *             3 = 1 Mbps (2.88MB ED - not fully supported)
 *
 * SPECIFY command bytes:
 *   Byte 0: 0x03 (SPECIFY command)
 *   Byte 1: (step_rate << 4) | head_unload_time
 *   Byte 2: (head_load_time << 1) | non_dma_mode
 *
 * Data Rate Register (0x3F7):
 *   0 = 500 kbps (MFM)
 *   1 = 300 kbps (MFM)
 *   2 = 250 kbps (MFM)
 *   3 = 1 Mbps (MFM)
 */
- (IOReturn)_doSpecify:(unsigned int)density
{
	unsigned char cmdBuffer[96];
	unsigned char dataRateByte;
	unsigned char perpendicularGap;
	IOReturn result;

	// Zero out command buffer
	bzero(cmdBuffer, 0x60);

	// Build SPECIFY command at offset 0x0c
	cmdBuffer[0x0c] = 0x03;  // Command: SPECIFY

	// Set timing parameters based on density
	if (density == 2) {
		// 300 kbps (720KB, 360KB)
		dataRateByte = 0;
		cmdBuffer[0x0d] = 0xaf;  // Step rate and head unload time
		cmdBuffer[0x0e] = (cmdBuffer[0x0e] & 0x01) | 0x20;  // Head load time, preserve bit 0
		perpendicularGap = 0;
	} else if (density == 1) {
		// 500 kbps (1.44MB, 1.2MB)
		dataRateByte = 2;
		cmdBuffer[0x0d] = 0xaf;  // Step rate and head unload time
		cmdBuffer[0x0e] = (cmdBuffer[0x0e] & 0x01) | 0x20;  // Head load time, preserve bit 0
		perpendicularGap = 0;
	} else if (density == 3) {
		// 1 Mbps (2.88MB ED)
		dataRateByte = 3;
		cmdBuffer[0x0d] = 0xa4;  // Step rate and head unload time
		cmdBuffer[0x0e] = (cmdBuffer[0x0e] & 0x01) | 0x1e;  // Head load time, preserve bit 0
		perpendicularGap = 1;
	} else {
		// Invalid density
		IOLog("fc: Bogus density (%d) in doSpecify()\n", density);
		return IO_R_INVALID_ARG;
	}

	// Set data rate register (I/O port 0x3F7)
	outb(0x3f7, dataRateByte);

	// Increment data rate change counter (at offset 0x13c)
	// LOCK();
	_dataRateChangeCount++;
	// UNLOCK();

	// Set timeout and other fields
	*(unsigned int *)(cmdBuffer + 0x04) = 5000;  // timeout
	*(unsigned int *)(cmdBuffer + 0x08) = 1;

	// Set command byte count at offset 0x4c
	*(unsigned int *)(cmdBuffer + 0x4c) = 3;

	// Send SPECIFY command
	result = [self _sendCmd:cmdBuffer];

	// If controller supports CONFIGURE and density is 3 (1Mbps), send PERPENDICULAR command
	if (((_flags & 0x02) != 0) && (density == 3)) {
		result = [self _doPerpendicular:1 gap:perpendicularGap];
	}

	// Update density setting at offset 0x139
	if (result == IO_R_SUCCESS) {
		_currentDensity = (char)density;
	} else {
		_currentDensity = 0;
	}

	return result;
}

/*
 * Read a byte from the controller FIFO.
 * From decompiled code: waits for RQM and DIO, then reads data register.
 *
 * This method reads a result byte from the FDC's data FIFO register.
 * It waits for the controller to be ready with DIO=1 (data direction FDC->CPU).
 *
 * Parameters:
 *   bytePtr - Pointer to store the read byte
 *
 * Returns:
 *   IOReturn status code (IO_R_SUCCESS or timeout error)
 *
 * I/O Registers:
 *   0x3F5 - Data FIFO (read when DIO=1)
 *
 * MSR (Main Status Register) bits:
 *   - Bit 7: RQM (1 = ready for data transfer)
 *   - Bit 6: DIO (1 = read from FDC, 0 = write to FDC)
 *   - Bit 5: NDMA (non-DMA mode)
 *   - Bit 4: CB (command busy)
 *   - Bits 0-3: Drive busy flags
 */
- (IOReturn)_fcGetByte:(unsigned char *)bytePtr
{
	IOReturn result;
	unsigned char dataByte;

	// Wait for controller ready with DIO=1 (data direction: FDC->CPU)
	// 0x40 = bit 6 (DIO) which must be set for reading
	result = [self _fcWaitPio:0x40];

	if (result == IO_R_SUCCESS) {
		// Read byte from data FIFO register (port 0x3F5)
		dataByte = inb(0x3f5);
		*bytePtr = dataByte;
	}

	return result;
}

/*
 * Send a byte to the controller FIFO.
 * From decompiled code: waits for RQM and !DIO, then writes data register.
 *
 * This method writes a command or parameter byte to the FDC's data FIFO register.
 * It waits for the controller to be ready with DIO=0 (data direction CPU->FDC).
 *
 * Parameters:
 *   byte - Byte to send to the controller
 *
 * Returns:
 *   IOReturn status code (IO_R_SUCCESS or timeout error)
 *
 * I/O Registers:
 *   0x3F5 - Data FIFO (write when DIO=0)
 */
- (IOReturn)_fcSendByte:(unsigned char)byte
{
	IOReturn result;

	// Wait for controller ready with DIO=0 (data direction: CPU->FDC)
	// Pass 0 to wait for RQM=1 and DIO=0
	result = [self _fcWaitPio:0];

	if (result == IO_R_SUCCESS) {
		// Write byte to data FIFO register (port 0x3F5)
		outb(0x3f5, byte);

		// Increment data rate change counter (at offset 0x13c)
		// LOCK();
		_dataRateChangeCount++;
		// UNLOCK();
	}

	return result;
}

/*
 * Wait for controller interrupt.
 * From decompiled code: waits for interrupt message with timeout.
 *
 * This method waits for an interrupt from the floppy controller by receiving
 * a message on the interrupt port. On non-EISA systems, it adds a 5ms delay
 * before waiting to avoid race conditions.
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure (used to pass to interrupt handler)
 *   timeout   - Timeout in milliseconds
 *
 * Returns:
 *   IOReturn status code:
 *     0 (IO_R_SUCCESS) if interrupt received
 *     1 (IO_R_TIMEOUT) if timeout occurred
 */
- (IOReturn)_fcWaitIntr:(void *)cmdParams timeout:(unsigned int)timeout
{
	BOOL isEISA;
	msg_header_t msg;
	kern_return_t msgResult;
	IOReturn result;

	// On non-EISA systems, add 5ms delay before waiting for interrupt
	// This helps avoid race conditions with the hardware
	isEISA = [self isEISAPresent];
	if (!isEISA) {
		IOSleep(5);
	}

	// Set up message header for receiving interrupt
	msg.msg_local_port = _interruptPort;  // Port at offset 0x134
	msg.msg_size = 0x18;  // Message size (24 bytes)

	// Wait for interrupt message with timeout
	msgResult = msg_receive(&msg, MSG_OPTION_NONE, timeout);

	// Check if message received successfully or timed out
	if ((msgResult == KERN_SUCCESS) || (msgResult == RCV_TIMED_OUT)) {
		// Call interrupt handler to process the interrupt
		result = [self _floppyInterrupt:cmdParams];
	} else {
		// Message receive error (timeout)
		result = IO_R_TIMEOUT;
	}

	return result;
}

/*
 * Wait for controller ready for PIO.
 * From decompiled code: waits for RQM bit in MSR.
 *
 * This method polls the Main Status Register (MSR) waiting for the controller
 * to be ready for programmed I/O (PIO) data transfer. It implements a two-level
 * timeout: fast polling (100 iterations) with periodic sleeps (5ms).
 *
 * Parameters:
 *   dioMask - Expected DIO bit value:
 *             0x40 (0b01000000) = wait for DIO=1 (read from FDC)
 *             0x00 (0b00000000) = wait for DIO=0 (write to FDC)
 *
 * Returns:
 *   IOReturn status code:
 *     0 (IO_R_SUCCESS) if controller ready
 *     1 (IO_R_TIMEOUT) if timeout occurred
 *     10 (IO_R_VM_FAILURE) if DIO direction mismatch (phase error)
 *
 * I/O Registers:
 *   0x3F4 - Main Status Register (MSR)
 *
 * MSR bits:
 *   - Bit 7: RQM (1 = ready for data transfer)
 *   - Bit 6: DIO (1 = read from FDC, 0 = write to FDC)
 *   - Bit 5: NDMA (non-DMA mode)
 *   - Bit 4: CB (command busy)
 *   - Bits 0-3: Drive busy flags
 */
- (IOReturn)_fcWaitPio:(unsigned int)dioMask
{
	unsigned char msrByte;
	int result;
	int timeRemaining;
	int fastPollCount;

	result = IO_R_SUCCESS;
	timeRemaining = 30;  // 30ms total timeout (6 iterations * 5ms)
	fastPollCount = 100;  // Fast poll iterations before sleep

	do {
		// Read Main Status Register (port 0x3F4)
		msrByte = inb(0x3f4);

		// Check if RQM (bit 7) is set - controller is ready
		if ((char)msrByte < 0) {  // Checks bit 7 (sign bit)
			// Controller is ready, check DIO bit direction
			if (dioMask != (msrByte & 0x40)) {
				// DIO direction mismatch - phase error
				result = IO_R_VM_FAILURE;  // 10
			}
			break;
		}

		// Decrement fast poll counter
		fastPollCount--;
		if (fastPollCount == 0) {
			// Exhausted fast poll iterations, sleep and retry
			IOSleep(5);
			timeRemaining -= 5;
			fastPollCount = 100;  // Reset fast poll counter
		}
	} while (timeRemaining != 0);

	// Check if we timed out
	if (timeRemaining == 0) {
		result = IO_R_TIMEOUT;  // 1
	}

	return result;
}

/*
 * Floppy interrupt handler.
 * From decompiled code: handles hardware interrupt from floppy controller.
 *
 * This method is called when an interrupt is received from the floppy controller.
 * It waits for the controller to be ready (RQM set), then either reads a result
 * byte or sends a SENSE INTERRUPT STATUS command depending on the DIO bit.
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure (or NULL)
 *
 * Returns:
 *   IOReturn status code:
 *     0 (IO_R_SUCCESS) if interrupt handled successfully
 *     1 (IO_R_TIMEOUT) if timeout waiting for controller ready
 *
 * Command parameters structure offsets used:
 *   0x28 - Result bytes buffer (stores interrupt result byte at offset 3)
 *   0x4c - Result byte count (incremented)
 */
- (IOReturn)_floppyInterrupt:(void *)cmdParams
{
	unsigned char msrByte;
	unsigned char resultByte;
	IOReturn result;
	int retryCount;
	int *resultByteCountPtr;

	// Wait for controller to be ready (RQM bit set)
	// Poll MSR with timeout (10000 iterations with 1ms sleep)
	retryCount = 0;
	do {
		msrByte = inb(0x3f4);
		if ((char)msrByte < 0) {  // Check bit 7 (RQM)
			break;
		}
		IOSleep(1);
		retryCount++;
	} while (retryCount < 10000);

	// Check if we timed out
	if (retryCount == 10000) {
		// Timeout - set error flag
		result = IO_R_TIMEOUT;
		goto set_error_flag;
	}

	// Controller is ready, check DIO bit to determine action
	if ((msrByte & 0x40) == 0) {
		// DIO=0 (CPU->FDC): Controller wants us to send a command
		// Send SENSE INTERRUPT STATUS command (0x08)
		result = [self _fcSendByte:0x08];
		if (result != IO_R_SUCCESS) {
			goto set_error_flag;
		}
	} else {
		// DIO=1 (FDC->CPU): Controller has a result byte for us
		// Read the result byte from data FIFO
		resultByte = inb(0x3f5);

		// Store result byte in cmdParams if provided
		if (cmdParams != NULL) {
			// Store at offset 0x28 (field7_0x25[3])
			*(unsigned char *)((char *)cmdParams + 0x28) = resultByte;

			// Increment result byte count at offset 0x4c (field13_0x49 + 3)
			resultByteCountPtr = (int *)((char *)cmdParams + 0x4c);
			*resultByteCountPtr = *resultByteCountPtr + 1;
		}
	}

	result = IO_R_SUCCESS;
	return result;

set_error_flag:
	// Set error flag (bit 0 of _flags at offset 0x138)
	_flags |= 0x01;
	return result;
}

/*
 * Flush pending interrupt messages.
 * From decompiled code: clears any queued interrupt messages.
 *
 * This method drains any pending interrupt messages from the interrupt port.
 * It uses a non-blocking receive (timeout=0) to check for stray interrupts,
 * and if found, processes them and reads any remaining result bytes.
 *
 * Returns:
 *   Always returns 0 (IO_R_SUCCESS)
 */
- (IOReturn)_flushIntrMsgs
{
	msg_header_t msg;
	kern_return_t msgResult;
	IOReturn intrResult;
	unsigned char cmdBuffer[96];
	unsigned char *resultBytesPtr;
	int resultByteCount;
	int i;
	IOReturn getByteResult;

	// Set up message header for receiving interrupt
	msg.msg_local_port = _interruptPort;  // Port at offset 0x134
	msg.msg_size = 0x18;  // Message size (24 bytes)

	// Try to receive interrupt message with no timeout (non-blocking)
	msgResult = msg_receive(&msg, MSG_OPTION_NONE, 0);

	// Check if message received successfully or timed out
	if ((msgResult == KERN_SUCCESS) || (msgResult == RCV_TIMED_OUT)) {
		// Got a stray interrupt - process it

		// Zero out command buffer
		bzero(cmdBuffer, 0x60);

		// Call interrupt handler to process the interrupt
		intrResult = [self _floppyInterrupt:cmdBuffer];

		if (intrResult == IO_R_SUCCESS) {
			// Read any remaining result bytes from the FIFO
			// The interrupt handler may have stored one byte and updated count at offset 0x4c
			resultByteCount = *(int *)(cmdBuffer + 0x4c);

			// Calculate pointer to next result byte location
			// Starting at offset 0x28 + resultByteCount
			resultBytesPtr = cmdBuffer + 0x28 + resultByteCount;

			// Read up to 16 total result bytes
			for (i = resultByteCount; i < 0x10; i++) {
				getByteResult = [self _fcGetByte:resultBytesPtr];
				if (getByteResult != IO_R_SUCCESS) {
					// No more bytes available
					break;
				}
				resultBytesPtr++;
			}
		}

		// Log the stray interrupt
		printf("FloppyCntIo:flushIntMsgs:Stray Interrupt\n");
	}

	// Always return success
	return IO_R_SUCCESS;
}

/*
 * Get drive status using SENSE DRIVE STATUS command.
 * From decompiled code: reads ST3 status register for a drive.
 *
 * This method queries the drive status by sending SENSE DRIVE STATUS command.
 * It checks motor state, optionally reads the digital input register, and
 * determines write-protect status.
 *
 * Parameters:
 *   cmdParams - Pointer to command parameters structure containing:
 *               - offset 0x14: Drive number
 *               - offset 0x50: Status flags (updated with results)
 *
 * Command parameters structure offsets:
 *   0x14 - Drive number
 *   0x40 - Result code (updated)
 *   0x50 - Status flags (bits set/cleared based on results)
 *          Bit 1: Write protect status
 *          Bit 2: Motor status
 *          Bit 3: From ST3 bit 3 (write protect in some modes)
 *          Bit 4: Set initially
 *
 * ST3 (Status Register 3) bits:
 *   - Bit 7: Fault
 *   - Bit 6: Write protect
 *   - Bit 5: Ready
 *   - Bit 4: Track 0
 *   - Bit 3: Two-sided / write protect
 *   - Bit 2: Head address
 *   - Bits 0-1: Drive select
 */
- (IOReturn)_getDriveStatus:(void *)cmdParams
{
	unsigned char *statusFlagsPtr;
	unsigned char driveNum;
	unsigned char motorBit;
	unsigned char dirByte;
	unsigned char cmdBuffer[96];
	IOReturn result;
	int density;

	// Get pointer to status flags at offset 0x50
	statusFlagsPtr = (unsigned char *)((char *)cmdParams + 0x50);

	// Set bit 4 of status flags
	*statusFlagsPtr |= 0x10;

	// Get drive number at offset 0x14
	driveNum = *(unsigned char *)((char *)cmdParams + 0x14);

	// Check if motor is already on for this drive
	motorBit = (unsigned char)(0x10 << (driveNum & 0x1f));
	if ((motorBit & _dorRegister) == 0) {
		// Motor is off, turn it on
		[self _doMotorOn:driveNum];
	} else {
		// Motor is already on, set bit 2 of status flags
		*statusFlagsPtr |= 0x04;

		// Read Digital Input Register (DIR) at port 0x3F7
		// Bit 7 indicates disk change
		dirByte = inb(0x3f7);
		if ((char)dirByte >= 0) {
			// Disk change bit not set, proceed to simplified status check
			goto simplified_status_check;
		}
	}

	// Set bit 2 of status flags (motor status)
	*statusFlagsPtr |= 0x04;

	// Send SENSE DRIVE STATUS command (0x04)
	bzero(cmdBuffer, 0x60);

	// Get current density at offset 0x139
	density = _currentDensity;
	*(int *)(cmdBuffer + 0x00) = density;

	// Set command parameters
	*(unsigned int *)(cmdBuffer + 0x08) = 1;  // Command type or flags
	*(unsigned int *)(cmdBuffer + 0x4c) = 2;  // Command byte count

	// Build command bytes at offset 0x0c
	cmdBuffer[0x0c] = (cmdBuffer[0x0c] & 0xc0) | 0x4a;  // Command with flags (likely 0x04 | MT flag)
	cmdBuffer[0x0d] = (cmdBuffer[0x0d] & 0xf8) | (driveNum & 0x03);  // Drive select

	// Set timeout
	*(unsigned int *)(cmdBuffer + 0x04) = 500;

	// Set expected result byte count at offset 0x2c
	*(unsigned int *)(cmdBuffer + 0x2c) = 7;

	// Send the command
	result = [self _sendCmd:cmdBuffer];

	// Check result
	if (result == IO_R_TIMEOUT) {
		goto handle_timeout_or_phase_error;
	} else if (result == IO_R_VM_FAILURE) {  // 10 = phase error
		goto handle_timeout_or_phase_error;
	} else if (result != IO_R_SUCCESS) {
		goto handle_error;
	}

	// Success path
	goto get_write_protect_status;

handle_timeout_or_phase_error:
	if ((result != IO_R_NO_DEVICE) && (result != IO_R_VM_FAILURE)) {
		goto handle_error;
	}
	// Set error flag (bit 0 of _flags)
	_flags |= 0x01;

handle_error:
	if (result == IO_R_TIMEOUT) {
		// Set timeout flag (bit 2 of _flags)
		_flags |= 0x04;
	}

	// Clear bits 0-1 of status flags
	*statusFlagsPtr &= 0xfc;
	// Clear bit 2 (motor status)
	*statusFlagsPtr &= 0xfb;
	// Turn off motor
	[self _doMotorOff:driveNum];
	return IO_R_SUCCESS;

simplified_status_check:
	// Clear bits 0-1 of status flags
	*statusFlagsPtr &= 0xfc;
	// Set bit 1 (write protect detected)
	*statusFlagsPtr |= 0x02;

get_write_protect_status:
	// Send simplified SENSE DRIVE STATUS to get write protect status
	bzero(cmdBuffer, 0x60);

	// Set command parameters
	*(unsigned int *)(cmdBuffer + 0x08) = 1;
	*(unsigned int *)(cmdBuffer + 0x4c) = 2;  // Command byte count

	// Build command bytes
	cmdBuffer[0x0c] = 0x04;  // SENSE DRIVE STATUS command
	cmdBuffer[0x0d] = (cmdBuffer[0x0d] & 0xf8) | (driveNum & 0x03);  // Drive select

	// Set timeout
	*(unsigned int *)(cmdBuffer + 0x04) = 2000;

	// Set expected result byte count at offset 0x2c
	*(unsigned int *)(cmdBuffer + 0x2c) = 1;

	// Send the command
	result = [self _sendCmd:cmdBuffer];

	if (result != IO_R_SUCCESS) {
		return IO_R_SUCCESS;
	}

	// Clear bit 3 of status flags
	*statusFlagsPtr &= 0xf7;

	// Extract write protect bit (bit 3 of ST3 at offset 0x40 in cmdBuffer)
	// and set bit 3 of status flags if write protected
	*statusFlagsPtr |= (*(unsigned char *)(cmdBuffer + 0x40) >> 3) & 0x08;

	return IO_R_SUCCESS;
}

/*
 * Reset the i82077 floppy controller.
 * From decompiled code: performs hardware reset and re-initialization.
 *
 * This method performs a complete hardware reset of the floppy controller:
 * 1. Flushes pending interrupts
 * 2. Asserts reset (DOR bit 2 = 0)
 * 3. Deasserts reset (DOR bit 2 = 1)
 * 4. Clears polling interrupts
 * 5. Sends CONFIGURE and SPECIFY commands
 * 6. Optionally recalibrates drive 0
 *
 * Parameters:
 *   message - Error message string or NULL for silent reset
 *
 * Returns:
 *   IOReturn status code from SPECIFY command
 *
 * Digital Output Register (DOR - port 0x3F2) bits:
 *   - Bit 0-1: Drive select
 *   - Bit 2: Reset (0=reset, 1=normal)
 *   - Bit 3: DMA enable
 *   - Bit 4: Motor A enable
 *   - Bit 5: Motor B enable
 *   - Bit 6: Motor C enable
 *   - Bit 7: Motor D enable
 */
- (IOReturn)i82077Reset:(const char *)message
{
	unsigned char dataRateByte;
	unsigned char currentDensity;
	unsigned char dorValue;
	IOReturn configResult;
	IOReturn specifyResult;
	int density;

	// Log reset message if provided
	if (message != NULL) {
		IOLog("Floppy Controller Reset: %s\n", message);
	}

	// Reset loop - retries if CONFIGURE fails
	do {
		// Flush any pending interrupt messages
		[self _flushIntrMsgs];

		// Assert reset by clearing DOR (all bits = 0, including reset bit 2)
		_dorRegister = 0;
		outb(0x3f2, 0);
		// LOCK();
		_dataRateChangeCount++;
		// UNLOCK();

		// Wait 500 microseconds for reset to take effect
		IODelay(500);

		// Deassert reset by setting bit 2 of DOR
		_dorRegister = 4;
		outb(0x3f2, 4);
		// LOCK();
		_dataRateChangeCount++;
		// UNLOCK();

		// Set data rate register based on current density
		currentDensity = _currentDensity;
		if (currentDensity == 2) {
			// 300 kbps
			dataRateByte = 0;
		} else if (currentDensity < 3) {
			if (currentDensity == 1) {
				// 500 kbps (actually 250 kbps for standard PC)
				dataRateByte = 2;
			} else {
				// Invalid density, clear it
				_currentDensity = 0;
				dataRateByte = 2;  // Default to 500 kbps
			}
		} else if (currentDensity == 3) {
			// 1 Mbps (ED)
			dataRateByte = 0;
		} else {
			// Invalid density, clear it
			_currentDensity = 0;
			dataRateByte = 2;  // Default to 500 kbps
		}

		// Set data rate register (port 0x3F7)
		outb(0x3f7, dataRateByte);
		// LOCK();
		_dataRateChangeCount++;
		// UNLOCK();

		// Clear polling interrupts generated by reset
		[self _clearPollIntr];

		// Determine density for CONFIGURE command
		if (_currentDensity == 0) {
			density = 2;  // Default to 500 kbps
		} else {
			density = _currentDensity;
		}

		// Send CONFIGURE command
		configResult = [self _doConfigure:density];

		if (configResult == IO_R_SUCCESS) {
			// CONFIGURE succeeded, continue with SPECIFY

			// Determine density for SPECIFY command
			if (_currentDensity == 0) {
				density = 2;  // Default to 500 kbps
			} else {
				density = _currentDensity;
			}

			// Send SPECIFY command
			specifyResult = [self _doSpecify:density];

			// Update error flag (bit 0 of _flags) based on SPECIFY result
			_flags &= 0xfe;  // Clear bit 0
			if (specifyResult != IO_R_SUCCESS) {
				_flags |= 0x01;  // Set bit 0 if error
			}

			// Update DMA enable bit (bit 3 of DOR) based on error flag
			if ((_flags & 0x01) == 0) {
				// No error, enable DMA (set bit 3)
				dorValue = _dorRegister | 0x08;
			} else {
				// Error, disable DMA (clear bit 3)
				dorValue = _dorRegister & 0xf7;
			}
			_dorRegister = dorValue;
			outb(0x3f2, _dorRegister);
			// LOCK();
			_dataRateChangeCount++;
			// UNLOCK();

			// Wait 20ms for controller to stabilize
			IOSleep(20);

			// Initialize last error code to 0xffff (no error)
			_lastErrorCode = 0xffff;

			// Recalibrate drive 0 if motor A is not already on
			if ((_dorRegister & 0x10) == 0) {
				// Motor A is off, turn it on first
				[self _doMotorOn:0];
				[self _recal];
				[self _doMotorOff:0];
			} else {
				// Motor A is already on, just recalibrate
				[self _recal];
			}

			return specifyResult;
		}

		// CONFIGURE failed, clear bit 1 of _flags and retry
		_flags &= 0xfd;

	} while (1);  // Loop forever until CONFIGURE succeeds
}

/*
 * Recalibrate drive (seek to track 0).
 * From decompiled code: sends RECALIBRATE command.
 *
 * This method sends the RECALIBRATE command to move the drive heads to track 0.
 * The command is asynchronous and generates an interrupt when complete.
 *
 * Returns:
 *   IOReturn status code from sendCmd
 *
 * RECALIBRATE command format:
 *   Byte 0: 0x07 (RECALIBRATE command)
 *   Byte 1: Drive select (bits 0-1)
 *
 * The command waits for an interrupt (with 20 second timeout) and expects
 * 2 result bytes from SENSE INTERRUPT STATUS.
 */
- (IOReturn)_recal
{
	unsigned char cmdBuffer[96];
	IOReturn result;

	// Zero out command buffer
	bzero(cmdBuffer, 0x60);

	// Build RECALIBRATE command at offset 0x0c
	cmdBuffer[0x0c] = 0x07;  // RECALIBRATE command
	cmdBuffer[0x0d] = cmdBuffer[0x0d] & 0x03;  // Drive select (preserve bits 0-1, clear others)

	// Set current density at offset 0x00
	cmdBuffer[0x00] = _currentDensity;

	// Set command parameters
	*(unsigned int *)(cmdBuffer + 0x08) = 1;  // Command type/flags

	// Set command byte count at offset 0x4c
	*(unsigned int *)(cmdBuffer + 0x4c) = 2;

	// Set timeout at offset 0x04 (20 seconds)
	*(unsigned int *)(cmdBuffer + 0x04) = 20000;

	// Set expected result byte count at offset 0x2c
	*(unsigned int *)(cmdBuffer + 0x2c) = 2;

	// Clear additional fields at offsets 0x44 and 0x40
	*(unsigned int *)(cmdBuffer + 0x44) = 0;
	*(unsigned int *)(cmdBuffer + 0x40) = 0;

	// Send the RECALIBRATE command
	result = [self _sendCmd:cmdBuffer];

	// Wait 30ms for mechanical settling
	IOSleep(30);

	return result;
}

/*
 * Seek to a specific track.
 * From decompiled code: sends SEEK command to position heads.
 *
 * This method sends the SEEK command to move the drive heads to a specific track/cylinder.
 * The command is asynchronous and generates an interrupt when complete.
 *
 * Parameters:
 *   track   - Track (cylinder) number to seek to
 *   head    - Head number (0 or 1)
 *   density - Density setting (stored in command buffer)
 *
 * Returns:
 *   IOReturn status code from sendCmd
 *
 * SEEK command format:
 *   Byte 0: 0x0F (SEEK command)
 *   Byte 1: (head << 2) | drive (bits 0-1 preserved from local_57)
 *   Byte 2: New Cylinder Number (NCN)
 *
 * The command waits for an interrupt (with 500ms timeout) and expects
 * 2 result bytes from SENSE INTERRUPT STATUS.
 */
- (IOReturn)_seek:(unsigned int)track head:(unsigned int)head density:(unsigned int)density
{
	unsigned char cmdBuffer[96];
	IOReturn result;

	// Zero out command buffer
	bzero(cmdBuffer, 0x60);

	// Set density at offset 0x00
	cmdBuffer[0x00] = (unsigned char)density;

	// Set command parameters
	*(unsigned int *)(cmdBuffer + 0x08) = 1;  // Command type/flags

	// Set command byte count at offset 0x4c
	*(unsigned int *)(cmdBuffer + 0x4c) = 3;

	// Build SEEK command at offset 0x0c
	cmdBuffer[0x0c] = 0x0f;  // SEEK command

	// Build drive/head byte at offset 0x0d
	// Preserve bits 0-1 (drive select), set head at bit 2
	cmdBuffer[0x0d] = (cmdBuffer[0x0d] & 0x03) | (((unsigned char)head & 0x01) << 2);

	// Set new cylinder number (NCN) at offset 0x0e
	cmdBuffer[0x0e] = (unsigned char)track;

	// Set timeout at offset 0x04 (500ms)
	*(unsigned int *)(cmdBuffer + 0x04) = 500;

	// Set expected result byte count at offset 0x2c
	*(unsigned int *)(cmdBuffer + 0x2c) = 2;

	// Clear additional fields at offsets 0x44 and 0x40
	*(unsigned int *)(cmdBuffer + 0x44) = 0;
	*(unsigned int *)(cmdBuffer + 0x40) = 0;

	// Send the SEEK command
	result = [self _sendCmd:cmdBuffer];

	return result;
}

@end

/* End of FloppyCntIo.m */
