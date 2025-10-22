/*
 * FloppyDriveInt.m - Internal methods for IOFloppyDrive
 *
 * Internal category methods for low-level floppy controller operations
 */

#import "IOFloppyDrive.h"
#import "FloppyDriveInt.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

@implementation IOFloppyDrive(Internal)

/*
 * Allocate disk structure.
 * From decompiled code: determines disk type from geometry and allocates IOFloppyDisk.
 */
- (IOReturn)_allocateDisk
{
	id diskObject;
	unsigned diskType = 1;  // Default type
	BOOL isEjectable;
	
	// Check if disk is formatted and density is set
	// offset 0x18c: flags, bit 0 = formatted
	// offset 0x180: density (2 = high density)
	// offset 0x184: tracks (0x50 = 80)
	// offset 0x194: total bytes
	// offset 0x198: writePrecomp (non-zero check)
	// offset 0x19c: sector size (0x200 = 512)
	// offset 0x1a4: sectors per track
	
	if ((_flags & 1) && (_density == 2)) {
		// Check for 720KB disk (DD in HD drive)
		// 80 tracks, 737280 bytes (0xb4000), 512 bytes/sector, 9 sectors/track
		if ((_numCyls == 0x50) && 
		    (_totalBytes == 0xb4000) && 
		    (_writePrecomp != 0) &&
		    (_sectorSize == 0x200) && 
		    (_sectorsPerTrack == 9)) {
			diskType = 0x20;  // 720KB
		}
		// Check for 1.44MB disk (HD)
		// 80 tracks, 1474560 bytes (0x168000), 512 bytes/sector, 18 sectors/track
		else if ((_density == 2) &&
		         (_numCyls == 0x50) && 
		         (_totalBytes == 0x168000) &&
		         (_writePrecomp != 0) &&
		         (_sectorSize == 0x200) && 
		         (_sectorsPerTrack == 0x12)) {
			diskType = 0x100;  // 1.44MB
		}
		// Check for 2.88MB disk (ED)
		// 80 tracks, 2949120 bytes (0x2d0000), 512 bytes/sector, 36 sectors/track
		else if ((_density == 2) &&
		         (_numCyls == 0x50) && 
		         (_totalBytes == 0x2d0000) &&
		         (_writePrecomp != 0) &&
		         (_sectorSize == 0x200) && 
		         (_sectorsPerTrack == 0x24)) {
			diskType = 0x800;  // 2.88MB
		}
	}
	
	// Get ejectable flag from bit 2 of flags (offset 0x18c)
	isEjectable = (_flags >> 2) & 1;
	
	// Allocate IOFloppyDisk object
	// Call: [[IOFloppyDisk alloc] initFromDeviceDescription:drive:type:isEjectable:]
	diskObject = [[IOFloppyDisk alloc] initFromDeviceDescription:_deviceDescription
	                                                        drive:self
	                                                         type:diskType
	                                                  isEjectable:isEjectable];
	
	// Store disk object at offset 0x108
	_nextLogicalDisk = diskObject;
	
	return (diskObject != nil) ? IO_R_SUCCESS : IO_R_NO_MEMORY;
}

/*
 * Format a track.
 * From decompiled code: formats a track with C/H/R/N sector descriptors.
 */
- (IOReturn)_fdFormatTrack : (unsigned)track
		       head : (unsigned)head
{
	IOReturn result;
	unsigned char *formatBuffer;
	unsigned bufferSize;
	vm_address_t allocAddr;
	unsigned allocSize;
	unsigned char *bufPtr;
	unsigned sector;
	unsigned char cmdBuffer[96];
	
	// Calculate buffer size (4 bytes per sector: C/H/R/N)
	bufferSize = _sectorsPerTrack << 2;  // offset 0x1a4
	
	// Allocate format buffer
	formatBuffer = (unsigned char *)floppyMalloc(bufferSize, &allocAddr, &allocSize);
	if (formatBuffer == NULL) {
		return (IOReturn)0xfffffd43;  // IO_R_NO_SPACE
	}
	
	// Build sector descriptor table (C/H/R/N for each sector)
	bufPtr = formatBuffer;
	for (sector = 1; sector <= _sectorsPerTrack; sector++) {
		*bufPtr++ = (unsigned char)track;           // C - Cylinder
		*bufPtr++ = (unsigned char)head;            // H - Head
		*bufPtr++ = (unsigned char)sector;          // R - Record (sector number)
		*bufPtr++ = _sectorSizeCode;                // N - sector size code (offset 0x1a0)
	}
	
	// Seek to track
	result = [self _fdSeek:track head:head];
	if (result != IO_R_SUCCESS) {
		IOFree(allocAddr, allocSize);
		return result;
	}
	
	// Build FDC format command
	bzero(cmdBuffer, 0x60);
	
	// Set command parameters at specific offsets
	cmdBuffer[0] = _fdcNumber;                      // FDC controller number (offset 400)
	*(unsigned *)(cmdBuffer + 4) = 5000;            // Timeout (5000ms)
	*(unsigned *)(cmdBuffer + 8) = 1;               // Command length
	*(unsigned *)(cmdBuffer + 0x14) = 6;            // Phase: format track
	*(unsigned *)(cmdBuffer + 0x58) = kernel_map;   // Kernel memory map
	*(unsigned *)(cmdBuffer + 0x5c) = 7;            // Result bytes expected
	*(unsigned *)(cmdBuffer + 0x60) = 0;            // Initial result value
	
	// FDC command bytes
	cmdBuffer[0x24] = 0x0D |                        // FORMAT TRACK command
	                  ((_writePrecomp & 1) << 6);   // Write precomp flag (offset 0x198)
	cmdBuffer[0x25] = ((unsigned char)head & 1) << 2; // Head select
	cmdBuffer[0x26] = _sectorSizeCode;              // N - sector size code (offset 0x1a0)
	cmdBuffer[0x27] = _sectorsPerTrack;             // Sectors per track (offset 0x1a4)
	cmdBuffer[0x28] = _formatGapLength;             // Gap length (offset 0x1a9)
	cmdBuffer[0x29] = 0x5A;                         // Fill byte (format pattern)
	
	// Set buffer pointer and size
	*(unsigned char **)(cmdBuffer + 0x30) = formatBuffer;
	*(int *)(cmdBuffer + 0x34) = bufferSize;
	
	// Send command to FDC
	result = [self _fdSendCmd:cmdBuffer];
	
	if (result == IO_R_SUCCESS) {
		// Convert FDC result to IO error code
		result = fdrToIo(*(unsigned *)(cmdBuffer + 0x58));
	}
	
	// Free format buffer
	IOFree(allocAddr, allocSize);
	
	return result;
}

/*
 * Generate read/write command.
 * From decompiled code: builds FDC READ/WRITE DATA command structure.
 */
- (IOReturn)_fdGenRwCmd : (unsigned)startBlock
	       blockCount : (unsigned)blockCount
		 fdIoReq : (void *)fdIoReq
		 readFlag : (BOOL)readFlag
{
	unsigned char *cmdStruct = (unsigned char *)fdIoReq;
	unsigned char *cmdBytes;
	unsigned char unit;
	unsigned char command;

	// The command bytes are at offset 0x9 + 3 in the structure
	// Based on decompiled code: field3_0x9[3..11] are the FDC command bytes
	// This corresponds to offset 0x24 in the command buffer (matching format track)
	cmdBytes = cmdStruct + 0x24;

	// Clear 9 bytes of command
	bzero(cmdBytes, 9);

	// Convert logical block to physical C/H/R
	// This fills in cmdBytes[2], cmdBytes[3], cmdBytes[4] (C, H, R)
	[self _fdLogToPhys:startBlock cmdp:cmdBytes];

	// Build command byte 0: command code with flags
	// READ DATA = 6 (0x06), WRITE DATA = 5 (0x05)
	// With MFM mode, these become 0x46 and 0x45
	command = readFlag ? 6 : 5;
	cmdBytes[0] = cmdBytes[0] & 0x7f;  // Clear bit 7
	cmdBytes[0] = cmdBytes[0] & 0xbf;  // Clear bit 6
	cmdBytes[0] = cmdBytes[0] | ((_writePrecomp & 1) << 6);  // Set write precomp bit
	cmdBytes[0] = (cmdBytes[0] & 0xe0) | command;  // Set command bits 0-4

	// Build command byte 1: head and unit select
	// Format: (head << 2) | (unit & 3)
	unit = [self unit];
	cmdBytes[1] = cmdBytes[1] & 0xfb;  // Clear bit 2
	cmdBytes[1] = cmdBytes[1] | ((cmdBytes[3] & 1) << 2);  // Head from C/H/R
	cmdBytes[1] = (cmdBytes[1] & 0xfc) | (unit & 3);  // Unit number

	// Build remaining FDC READ/WRITE DATA command bytes
	// cmdBytes[2] = C (cylinder) - already set by _fdLogToPhys
	// cmdBytes[3] = H (head) - already set by _fdLogToPhys
	// cmdBytes[4] = R (sector) - already set by _fdLogToPhys
	cmdBytes[5] = _sectorSizeCode;  // N - sector size code (offset 0x1a0)
	cmdBytes[6] = cmdBytes[4] + (unsigned char)blockCount - 1;  // EOT - end sector
	cmdBytes[7] = _readWriteGapLength;  // GPL - gap length (offset 0x1a8)
	cmdBytes[8] = 0xFF;  // DTL - data length (0xFF when N != 0)

	// Set control fields in the command structure
	// Timeout in milliseconds
	*(unsigned *)(cmdStruct + 4) = 20000;  // field1_0x1 + 3 = 0x4

	// Command length
	*(unsigned *)(cmdStruct + 8) = 1;  // field2_0x5 + 3 = 0x8

	// Phase/operation parameter
	*(unsigned *)(cmdStruct + 0x1c) = 9;  // field4_0x19 + 3 = 0x1c

	// Result bytes expected
	*(unsigned *)(cmdStruct + 0x38) = 7;  // field8_0x35 + 3 = 0x38

	// Set read/write direction flag (bit 1)
	if (readFlag) {
		cmdStruct[0x3c] |= 2;  // Set bit 1 for read
	} else {
		cmdStruct[0x3c] &= ~2;  // Clear bit 1 for write
	}

	return IO_R_SUCCESS;
}

/*
 * Get floppy controller status.
 * From decompiled code: sends SENSE DRIVE STATUS command to FDC.
 */
- (IOReturn)_fdGetStatus : (unsigned char *)status
{
	IOReturn result;
	unsigned char cmdBuffer[0x60];
	
	// Clear command buffer
	bzero(cmdBuffer, 0x60);
	
	// Set command parameters
	// Offset 0x5c (local_5c): command type = 5 (SENSE DRIVE STATUS)
	// Offset 0x60 (local_60): timeout = 5000ms
	*(unsigned *)(cmdBuffer + 0x5c) = 5;
	*(unsigned *)(cmdBuffer + 0x60) = 5000;
	
	// Send command to FDC
	result = [self _fdSendCmd:cmdBuffer];
	
	// Copy status from offset 0x14 (local_14) to output parameter
	if (status != NULL) {
		*status = cmdBuffer[0x14];
	}
	
	return result;
}

/*
 * Convert logical block to physical cylinder/head/sector.
 * From decompiled code: converts LBA to CHS addressing for FDC commands.
 */
- (IOReturn)_fdLogToPhys : (unsigned)logicalBlock
		     cmdp : (void *)cmdp
{
	unsigned char *cmd = (unsigned char *)cmdp;
	unsigned trackNumber;
	unsigned cylinder;
	unsigned head;
	unsigned sector;
	
	// Convert logical block to track number
	// trackNumber = block / sectorsPerTrack
	trackNumber = logicalBlock / _sectorsPerTrack;  // offset 0x1a4
	
	// Calculate cylinder (track / heads)
	cylinder = trackNumber / _density;  // offset 0x180 (appears to be numHeads)
	
	// Calculate head (track % heads)
	head = trackNumber % _density;
	
	// Calculate sector (1-based: (block % sectorsPerTrack) + 1)
	sector = (logicalBlock % _sectorsPerTrack) + 1;
	
	// Store in command buffer at offsets 2, 3, 4 (C, H, R)
	cmd[2] = (unsigned char)cylinder;  // C - Cylinder
	cmd[3] = (unsigned char)head;      // H - Head
	cmd[4] = (unsigned char)sector;    // R - Record (sector, 1-based)
	
	return IO_R_SUCCESS;
}

/*
 * Read sector ID.
 * From decompiled code: sends READ ID command to get current sector's C/H/R/N.
 */
- (IOReturn)_fdReadId : (unsigned)head
		statp : (unsigned char *)statp
{
	IOReturn result;
	unsigned char cmdBuffer[0x60];
	
	// Clear command buffer
	bzero(cmdBuffer, 0x60);
	
	// Build READ ID command (0x0A)
	cmdBuffer[0x24] = 0x0A |                        // READ ID command
	                  ((_writePrecomp & 1) << 6);   // Write precomp flag (offset 0x198)
	cmdBuffer[0x24] = cmdBuffer[0x24] & 0x80 | 10 | ((_writePrecomp & 1) << 6);
	
	// Set head selection
	cmdBuffer[0x25] = cmdBuffer[0x25] & 0xfb;       // Clear bit 2
	cmdBuffer[0x25] = cmdBuffer[0x25] | ((head & 1) << 2);  // Head select
	
	// Set command parameters
	*(unsigned *)(cmdBuffer + 4) = 20000;           // Timeout (20000ms)
	*(unsigned *)(cmdBuffer + 8) = 1;               // Command length
	*(unsigned *)(cmdBuffer + 0x1c) = 2;            // Phase
	*(unsigned *)(cmdBuffer + 0x20) = 0;
	*(unsigned *)(cmdBuffer + 0x24) = 0;
	*(unsigned *)(cmdBuffer + 0x38) = 7;            // Result bytes expected
	*(unsigned *)(cmdBuffer + 0x3c) = 0;
	
	// Send command to FDC
	result = [self _fdSendCmd:cmdBuffer];
	
	if (result == IO_R_SUCCESS) {
		// Convert FDC result to IO error code
		result = fdrToIo(*(unsigned *)(cmdBuffer + 0x40));
	}
	
	// Copy 7 status bytes to output (C, H, R, N, ST0, ST1, ST2)
	if (statp != NULL) {
		// Extract result bytes from buffer offsets 0x28-0x2e
		statp[0] = cmdBuffer[0x28];  // ST0
		statp[1] = cmdBuffer[0x29];  // ST1
		statp[2] = cmdBuffer[0x2a];  // ST2
		statp[3] = cmdBuffer[0x2b];  // C (cylinder)
		statp[4] = cmdBuffer[0x2c];  // H (head)
		statp[5] = cmdBuffer[0x2d];  // R (sector)
		statp[6] = cmdBuffer[0x2e];  // N (size code)
	}
	
	return result;
}

/*
 * Recalibrate drive (seek to track 0).
 * From decompiled code: sends RECALIBRATE command to move heads to track 0.
 */
- (IOReturn)_fdRecal
{
	IOReturn result;
	unsigned char cmdBuffer[0x60];
	unsigned char unit;
	
	// Clear command buffer
	bzero(cmdBuffer, 0x60);
	
	// Build RECALIBRATE command (0x07)
	cmdBuffer[0x24] = 7;  // RECALIBRATE command
	
	// Get unit number and set in command byte 1
	unit = [self unit];
	cmdBuffer[0x25] = cmdBuffer[0x25] & 3;  // Clear upper bits
	cmdBuffer[0x25] = (cmdBuffer[0x25] & 0xfc) | (unit & 3);  // Set unit bits
	
	// Set command parameters
	*(unsigned *)(cmdBuffer + 4) = 20000;   // Timeout (20000ms)
	*(unsigned *)(cmdBuffer + 8) = 1;       // Command length
	*(unsigned *)(cmdBuffer + 0x1c) = 2;    // Phase
	*(unsigned *)(cmdBuffer + 0x20) = 0;
	*(unsigned *)(cmdBuffer + 0x24) = 0;
	*(unsigned *)(cmdBuffer + 0x38) = 2;    // Result bytes expected
	
	// Send command to FDC
	result = [self _fdSendCmd:cmdBuffer];
	
	if (result == IO_R_SUCCESS) {
		// Convert FDC result to IO error code
		result = fdrToIo(*(unsigned *)(cmdBuffer + 0x40));
	}
	
	return result;
}

/*
 * Seek to specific track and head.
 * From decompiled code: sends SEEK command to position heads at specified track.
 */
- (IOReturn)_fdSeek : (unsigned)track
		 head : (unsigned)head
{
	IOReturn result;
	unsigned char cmdBuffer[0x60];
	int fdcNumber;
	
	// Clear command buffer
	bzero(cmdBuffer, 0x60);
	
	// Build SEEK command (0x0F)
	cmdBuffer[0x24] = 0x0F;  // SEEK command
	
	// Set head and unit in command byte 1
	cmdBuffer[0x25] = cmdBuffer[0x25] & 3;  // Clear upper bits
	cmdBuffer[0x25] = cmdBuffer[0x25] | ((head & 1) << 2);  // Set head bit
	
	// Set track/cylinder in command byte 2
	cmdBuffer[0x26] = (unsigned char)track;
	
	// Get FDC number from offset 400 (_fdcNumber), default to 2 if 0
	fdcNumber = _fdcNumber;
	if (fdcNumber == 0) {
		fdcNumber = 2;
	}
	cmdBuffer[0] = (unsigned char)fdcNumber;
	
	// Set command parameters
	*(unsigned *)(cmdBuffer + 4) = 5000;    // Timeout (5000ms)
	*(unsigned *)(cmdBuffer + 8) = 1;       // Command length
	*(unsigned *)(cmdBuffer + 0x1c) = 3;    // Phase
	*(unsigned *)(cmdBuffer + 0x20) = 0;
	*(unsigned *)(cmdBuffer + 0x24) = 0;
	*(unsigned *)(cmdBuffer + 0x38) = 2;    // Result bytes expected
	
	// Send command to FDC
	result = [self _fdSendCmd:cmdBuffer];
	
	if (result == IO_R_SUCCESS) {
		// Convert FDC result to IO error code
		result = fdrToIo(*(unsigned *)(cmdBuffer + 0x40));
	}
	
	return result;
}

/*
 * Send command to floppy controller.
 * From decompiled code: sends command buffer to FDC via controller object.
 */
- (IOReturn)_fdSendCmd : (unsigned char *)cmd
{
	IOReturn result;
	char fdcNumber;
	unsigned char unit;
	
	// Get FDC number from offset 400 (_fdcNumber)
	fdcNumber = _fdcNumber;
	cmd[0] = fdcNumber;
	
	// If FDC number is 0, default to 2
	if (fdcNumber == 0) {
		cmd[0] = 2;
	}
	
	// Get unit number and store at offset 0x10 (field after field2_0x5)
	unit = [self unit];
	cmd[0x10] = unit;
	
	// Get timestamp and store at offset 0x170
	IOGetTimestamp((unsigned long long *)((char *)self + 0x170));
	
	// Call fcCmdXfr: method on FDC controller object (offset 0x164)
	result = [_fdController fcCmdXfr:cmd];
	
	// Check flag at offset 0x50 bit 2 (field15_0x4e + 2, bit 4)
	if ((cmd[0x50] & 4) == 0) {
		// Clear motor timer active flag (bit 0 at offset 0x178)
		_motorTimerActive = _motorTimerActive & 0xfe;
		// Unschedule motor off timer
		IOUnscheduleFunc(fdTimer, self);
	} else if ((_motorTimerActive & 1) == 0) {
		// Set motor timer active flag
		_motorTimerActive = _motorTimerActive | 1;
		// Schedule motor off timer for 2 seconds
		IOScheduleFunc(fdTimer, self, 2);
	}
	
	return result;
}

/*
 * Raw read from disk (internal).
 * From decompiled code: performs raw sector read using FDC commands.
 */
- (IOReturn)_rawReadInt : (unsigned)startSector
	       sectCount : (unsigned)sectCount
		  buffer : (unsigned char *)buffer
{
	IOReturn result;
	unsigned char cmdBuffer[0x60];
	unsigned expectedBytes;
	unsigned actualBytes;
	
	// Clear command buffer
	bzero(cmdBuffer, 0x60);
	
	// Generate read command
	[self _fdGenRwCmd:startSector
	       blockCount:sectCount
		 fdIoReq:cmdBuffer
		 readFlag:YES];  // 1 = read operation
	
	// Set buffer pointer at offset 0x30
	*(unsigned char **)(cmdBuffer + 0x30) = buffer;
	
	// Calculate expected byte count (sectCount * sectorSize)
	expectedBytes = sectCount * _sectorSize;  // offset 0x19c
	*(unsigned *)(cmdBuffer + 0x34) = expectedBytes;
	
	// Set VM task (kernel task)
	*(unsigned *)(cmdBuffer + 0x54) = IOVmTaskSelf();
	
	// Send command to FDC
	result = [self _fdSendCmd:cmdBuffer];
	
	// Check if actual bytes transferred matches expected
	actualBytes = *(unsigned *)(cmdBuffer + 0x3c);
	if ((result == IO_R_SUCCESS) && (expectedBytes != actualBytes)) {
		// Set error if byte count mismatch
		result = (IOReturn)0x13;  // Error code for transfer mismatch
	}
	
	return result;
}

/*
 * Read/write block count operation.
 * From decompiled code: adjusts block count to not exceed track boundary.
 */
- (IOReturn)_rwBlockCount : (unsigned)startBlock
	       blockCount : (unsigned)blockCount
{
	unsigned char cmd[16];
	unsigned char sector;
	unsigned adjustedCount;
	
	// Convert logical block to physical C/H/R
	[self _fdLogToPhys:startBlock cmdp:cmd];
	
	// Get sector number from cmd[4] (R - sector is 1-based)
	sector = cmd[4];
	
	// Check if blockCount + sector would exceed track boundary
	// If (sectorsPerTrack + 1) < (blockCount + sector), adjust count
	if (_sectorsPerTrack + 1 < blockCount + sector) {
		// Adjust block count to read only to end of track
		adjustedCount = (_sectorsPerTrack - sector) + 1;
		return adjustedCount;
	}
	
	// Return original block count if it fits within track
	return blockCount;
}

/*
 * Update drive ready state (internal).
 * From decompiled code: checks drive status and returns ready state.
 */
- (void)_updateReadyStateInt
{
	IOReturn result;
	unsigned char cmdBuffer[0x60];
	unsigned char status;
	int readyState;
	
	// Clear command buffer
	bzero(cmdBuffer, 0x60);
	
	// Set command parameters for SENSE DRIVE STATUS
	// Offset 0x5c: command type = 5 (SENSE DRIVE STATUS)
	// Offset 0x60: timeout = 5000ms
	*(unsigned *)(cmdBuffer + 0x5c) = 5;
	*(unsigned *)(cmdBuffer + 0x60) = 5000;
	
	// Send command to FDC
	result = [self _fdSendCmd:cmdBuffer];
	
	// Get status byte from offset 0x14
	status = cmdBuffer[0x14];
	
	if (result == IO_R_SUCCESS) {
		// Check status bits:
		// Bit 4 (0x10): Ready bit
		// Bits 0-1 (0x03): Unit select
		if (((status & 0x10) == 0) || ((status & 3) == 0)) {
			// Not ready or unit 0
			readyState = 2;
		} else {
			// Ready
			readyState = 0;
		}
	} else {
		// Command failed
		readyState = 1;
	}
	
	// Store ready state (assuming there's a field for this)
	// The decompiled code returns the state, but this is a void method
	// so we might be storing it in an instance variable
}

@end
