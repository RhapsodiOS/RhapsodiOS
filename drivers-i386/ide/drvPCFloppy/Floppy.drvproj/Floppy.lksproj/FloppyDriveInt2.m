/*
 * FloppyDriveInt2.m - Additional internal methods for IOFloppyDrive
 *
 * Second internal category for higher-level floppy operations
 */

#import "IOFloppyDrive.h"
#import "FloppyDriveInt2.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

@implementation IOFloppyDrive(Internal2)

/*
 * Eject disk (internal).
 * From decompiled code: seeks to track 79 to unload heads, then turns off motor.
 */
- (IOReturn)_fdEjectInt
{
	IOReturn result;
	BOOL isFatal;
	const char *errorType;
	const char *errorString;
	const char *driveName;
	int retryCount;
	unsigned char cmdBuffer[0x60];

	isFatal = NO;
	retryCount = 0;

	// Retry up to 4 times (0, 1, 2, 3)
	do {
		// Seek to track 79 (0x4F) head 0 to unload/park heads
		result = [self _fdSeek:0x4f head:0];

		if (result != IO_R_SUCCESS) {
			// Check if this is the last retry (4th attempt)
			if (retryCount == 3) {
				isFatal = YES;
			}

			// Set error type message
			errorType = isFatal ? "FATAL" : "RETRYING";

			// Get error string for the return code
			errorString = [self stringFromReturn:result];

			// Get drive name
			driveName = [self name];

			// Log the error
			IOLog("%s seek: %s; %s", driveName, errorString, errorType);

			// If fatal, return the error
			if (isFatal) {
				return result;
			}
		}

		retryCount++;

		// Exit loop after 4 attempts
		if (retryCount > 3) {
			break;
		}
	} while (YES);

	// After successful seek (or 4 retries), send motor off command
	// Clear command buffer
	bzero(cmdBuffer, 0x60);

	// Set command type 4 (motor off/eject)
	*(unsigned *)(cmdBuffer + 0x5c) = 4;

	// Send command to FDC
	[self _fdSendCmd:cmdBuffer];

	// Set last ready state to 2 (not ready/ejected)
	[self setLastReadyState:2];

	return IO_R_SUCCESS;
}

/*
 * Common read/write operation.
 * From decompiled code: performs read/write with retry logic and error handling.
 */
- (IOReturn)_fdRwCommon : (BOOL)isRead
		    block : (unsigned)block
		 blockCnt : (unsigned)blockCnt
		   buffer : (unsigned char *)buffer
		   client : (vm_task_t)client
	     actualLength : (unsigned *)actualLength
{
	unsigned sectorSize;
	unsigned remainingBlocks;
	void *currentBuffer;
	void *bounceBuffer;
	unsigned currentBlock;
	int retryCount;
	int recalCount;
	BOOL retryInProgress;
	IOReturn result;
	unsigned char cmdBuffer[0x60];
	unsigned blocksToTransfer;
	int adjustedBlockCount;
	unsigned actualBytes;
	int fdcStatus;
	BOOL isContiguous;
	int eisaPresent;
	unsigned long long startTime, endTime;
	const char *statsMethod;

	// Get sector size from offset 0x19c
	sectorSize = _sectorSize;

	// Check if disk is formatted (bit 0 at offset 0x18c)
	if ((_flags & 1) == 0) {
		return (IOReturn)0xfffffbb3;  // Not formatted error
	}

	// Initialize counters
	retryCount = 0;
	recalCount = 0;
	retryInProgress = NO;
	remainingBlocks = blockCnt;
	currentBuffer = buffer;
	currentBlock = block;

	// Get bounce buffer from offset 0x1b0
	bounceBuffer = _bounceBuffer;

	// Get start timestamp
	IOGetTimestamp(&startTime);

	// Main transfer loop
	while (remainingBlocks != 0) {
		// Check if EISA present (can do larger transfers)
		eisaPresent = eisa_present();
		blocksToTransfer = remainingBlocks;

		// If not EISA, limit to page size
		if ((eisaPresent == 0) && (page_size / sectorSize < remainingBlocks)) {
			blocksToTransfer = page_size / sectorSize;
		}

		// Check if buffer is physically contiguous
		isContiguous = physContBlocks(currentBuffer, client, blocksToTransfer, sectorSize);

		// If not contiguous, can only transfer 1 block at a time
		if (!isContiguous) {
			blocksToTransfer = 1;
		}

		// Adjust block count to not exceed track boundary
		adjustedBlockCount = [self _rwBlockCount:currentBlock blockCount:blocksToTransfer];

		// Generate FDC read/write command
		[self _fdGenRwCmd:currentBlock
		       blockCount:adjustedBlockCount
			 fdIoReq:cmdBuffer
			 readFlag:isRead];

		// Set command length
		*(unsigned *)(cmdBuffer + 0x5c) = 1;

		// Calculate expected bytes
		*(unsigned *)(cmdBuffer + 0x34) = adjustedBlockCount * sectorSize;

		// Set up buffer pointer and VM task
		if (isContiguous) {
			// Use user buffer directly
			*(void **)(cmdBuffer + 0x30) = currentBuffer;
			*(vm_task_t *)(cmdBuffer + 0x54) = client;
		} else {
			// Use bounce buffer
			*(void **)(cmdBuffer + 0x30) = bounceBuffer;
			*(vm_task_t *)(cmdBuffer + 0x54) = kernel_map;

			// For write, copy data to bounce buffer
			if (!isRead) {
				vFloppyCopy(currentBuffer, client, bounceBuffer, kernel_map, sectorSize);
			}
		}

		// Send command to FDC
		result = [self _fdSendCmd:cmdBuffer];

		// Get FDC status from offset 0x40
		fdcStatus = *(int *)(cmdBuffer + 0x40);

		// Get actual bytes transferred from offset 0x3c
		actualBytes = *(unsigned *)(cmdBuffer + 0x3c);

		// Special case: if status 6 and actualBytes != 0, adjust by sector size
		if ((fdcStatus == 6) && (actualBytes != 0)) {
			actualBytes = actualBytes - sectorSize;
		}

		// Calculate blocks actually transferred
		blocksToTransfer = actualBytes / sectorSize;

		// For read with bounce buffer, copy data back
		if ((blocksToTransfer != 0) && (!isContiguous) && isRead) {
			vFloppyCopy(bounceBuffer, kernel_map, currentBuffer, client, sectorSize);
		}

		// Update counters
		remainingBlocks -= blocksToTransfer;
		currentBlock += blocksToTransfer;
		currentBuffer = (void *)((char *)currentBuffer + actualBytes);

		// If send command failed, treat as FDC error
		if (result != IO_R_SUCCESS) {
			fdcStatus = 4;
		}

		// Handle FDC status codes
		switch (fdcStatus) {
		case 0:  // Success
			if (retryInProgress) {
				retryInProgress = NO;
				retryCount = 0;
				recalCount = 0;
				goto update_stats;
			}
			break;

		case 1:   // Various error codes that warrant retry
		case 6:
		case 7:
		case 8:
		case 9:
		case 0xb:
		case 0xc:
		case 0xe:
		case 0xf:
		case 0x10:
		case 0x13:
			if (!retryInProgress) {
				retryInProgress = YES;
			}

			retryCount++;

			if (retryCount == 3) {
				// After 3 retries, recalibrate
				recalCount++;

				if (recalCount == 6) {
					// Give up after 6 recalibrations
					[self _logRwErr:"FATAL"
						      block:currentBlock
						     status:(unsigned char *)&fdcStatus
						   readFlag:isRead];
					goto transfer_done;
				}

				[self _logRwErr:"RECALIBRATING"
					      block:currentBlock
					     status:(unsigned char *)&fdcStatus
					   readFlag:isRead];

				[self _fdRecal];
				retryCount = 0;
			} else {
				[self _logRwErr:"RETRYING"
					      block:currentBlock
					     status:(unsigned char *)&fdcStatus
					   readFlag:isRead];
			}

update_stats:
			if (retryInProgress) {
				if (isRead) {
					[self incrementReadRetries];
				} else {
					[self incrementWriteRetries];
				}
			}
			break;

		default:  // Fatal error
			[self _logRwErr:"FATAL"
				      block:currentBlock
				     status:(unsigned char *)&fdcStatus
				   readFlag:isRead];
			goto transfer_done;
		}
	}

transfer_done:
	// Calculate actual bytes transferred
	*actualLength = sectorSize * (blockCnt - remainingBlocks);

	// Convert FDC status to IOReturn
	result = fdrToIo(fdcStatus);

	// Record statistics
	if (fdcStatus == 0) {
		// Success - record timing and byte counts
		IOGetTimestamp(&endTime);

		if (isRead) {
			[self addToBytesRead:*actualLength
				   totalTime:(endTime - startTime)
				  latentTime:0
				 extraParam1:0
				 extraParam2:0];
		} else {
			[self addToBytesWritten:*actualLength
				      totalTime:(endTime - startTime)
				     latentTime:0
				    extraParam1:0
				    extraParam2:0];
		}
	} else {
		// Error - increment error counters
		if (isRead) {
			[self incrementReadErrors];
		} else {
			[self incrementWriteErrors];
		}
	}

	return result;
}

/*
 * Log read/write error.
 * From decompiled code: logs FDC error with operation type and status.
 */
- (void)_logRwErr : (unsigned)operation
	      block : (unsigned)block
	     status : (unsigned char *)status
	   readFlag : (BOOL)readFlag
{
	const char *statusString;
	const char *operationType;
	const char *driveName;
	int fdcStatus;

	// Get FDC status value
	fdcStatus = *(int *)status;

	// Find name for FDC status value in fdrValues table
	statusString = (const char *)IOFindNameForValue(fdcStatus, &fdrValues, (const char *)operation);

	// Set operation type based on read flag
	operationType = readFlag ? "Read" : "Write";

	// Get drive name
	driveName = [self name];

	// Log the error
	IOLog("%s: Sector %d cmd = %s; %s: %s",
	      driveName, block, operationType,
	      (const char *)operation, statusString);
}


/*
 * Check if motor should be turned off.
 * From decompiled code: checks timeout and turns off motor after 2 seconds.
 */
- (void)_motorOffCheck
{
	int lastReadyState;
	unsigned long long currentTime;
	unsigned currentTimeLow, currentTimeHigh;
	unsigned lastTimeLow, lastTimeHigh;
	unsigned timeoutTimeLow, timeoutTimeHigh;
	unsigned char cmdBuffer[0x60];

	// Check if disk is ejected/not ready
	lastReadyState = [self lastReadyState];
	if (lastReadyState == 2) {
		return;  // Don't turn off motor if already ejected
	}

	// Get current timestamp
	IOGetTimestamp(&currentTime);
	currentTimeLow = (unsigned)(currentTime & 0xFFFFFFFF);
	currentTimeHigh = (unsigned)(currentTime >> 32);

	// Get last operation timestamp from offset 0x170
	lastTimeLow = *(unsigned *)((char *)self + 0x170);
	lastTimeHigh = *(unsigned *)((char *)self + 0x174);

	// Calculate timeout time (last time + 2 seconds = 2000000000 ns)
	// Add 2000000000 to low word, handle carry to high word
	timeoutTimeLow = lastTimeLow + 2000000000;
	timeoutTimeHigh = lastTimeHigh;
	if (timeoutTimeLow < lastTimeLow) {  // Carry occurred (0x88ca6bff < lastTimeLow)
		timeoutTimeHigh++;
	}

	// Check if timeout has not yet expired
	if ((currentTimeHigh < timeoutTimeHigh) ||
	    ((currentTimeHigh == timeoutTimeHigh) && (currentTimeLow < timeoutTimeLow))) {
		// Timeout not reached, reschedule timer
		_motorTimerActive = _motorTimerActive | 1;
		IOScheduleFunc(fdTimer, self, 2);
	} else {
		// Timeout reached, turn off motor
		bzero(cmdBuffer, 0x60);

		// Set command type 4 (motor off)
		*(unsigned *)(cmdBuffer + 0x5c) = 4;

		// Send command to FDC
		[self _fdSendCmd:cmdBuffer];
	}
}

/*
 * Set disk density (internal).
 * From decompiled code: looks up density parameters and configures drive.
 */
- (IOReturn)_setDensityInt : (unsigned)density
{
	int *densityInfoPtr;
	BOOL wasZero;

	// Check if density is 0, set to default (2 = high density)
	wasZero = (density == 0);
	if (wasZero) {
		density = 2;
	}

	// Look up density in fdDensityInfo table
	// Table is array of 3-int entries: [density, totalBytes, writePrecomp]
	densityInfoPtr = (int *)&fdDensityInfo;

	// Search for matching density
	while (*densityInfoPtr != 0) {
		if (*densityInfoPtr == density) {
			break;
		}
		densityInfoPtr += 3;  // Move to next entry
	}

	// Set drive parameters from table
	_fdcNumber = *densityInfoPtr;          // offset 400 (actually density value)
	_totalBytes = densityInfoPtr[1];       // offset 0x194
	_writePrecomp = densityInfoPtr[2];     // offset 0x198

	// Update sector size configuration
	[self _setSectSizeInt:_sectorSize];    // offset 0x19c

	// If density was 0, clear formatted flag (bit 0 at offset 0x18c)
	if (wasZero) {
		_flags = _flags & 0xfffffffe;
	}

	return IO_R_SUCCESS;
}

/*
 * Set sector size (internal).
 * From decompiled code: looks up sector size parameters and configures drive.
 */
- (IOReturn)_setSectSizeInt : (unsigned)sectorSize
{
	int *sectSizeInfoPtr;

	// Get sector size info table for current FDC/density (offset 400)
	sectSizeInfoPtr = (int *)fdGetSectSizeInfo(_fdcNumber);

	if (*sectSizeInfoPtr == 0) {
		// No valid entries in table
		return (IOReturn)0xfffffd3e;  // IO_R_INVALID
	}

	// Search for matching sector size in table
	// Table is array of 4-int entries: [sectorSize, sizeCode, sectorsPerTrack, gapLength]
	while (*sectSizeInfoPtr != 0) {
		if (*sectSizeInfoPtr == sectorSize) {
			break;
		}
		sectSizeInfoPtr += 4;  // Move to next entry
	}

	if (*sectSizeInfoPtr == 0) {
		// Sector size not found in table
		return (IOReturn)0xfffffd3e;  // IO_R_INVALID
	}

	// Set drive parameters from table
	_sectorSize = sectSizeInfoPtr[0];          // offset 0x19c
	_sectorSizeCode = sectSizeInfoPtr[1];      // offset 0x1a0 (N parameter)
	_sectorsPerTrack = sectSizeInfoPtr[2];     // offset 0x1a4
	_readWriteGapLength = sectSizeInfoPtr[3];  // offset 0x1a8

	// Calculate total blocks (density * sectorsPerTrack * numCyls)
	// density at offset 0x180, numCyls at offset 0x184
	_numBlocks = _density * _sectorsPerTrack * _numCyls;  // offset 0x1ac

	// Set formatted flag (bit 0 at offset 0x18c)
	_flags = _flags | 1;

	// Clear bit 1 at offset 0x18c
	_flags = _flags & 0xfffffffd;

	return IO_R_SUCCESS;
}

/*
 * Update physical parameters (internal).
 * From decompiled code: probes disk to determine geometry and density.
 */
- (void)_updatePhysicalParametersInt
{
	IOReturn result;
	unsigned char status;
	unsigned *diskInfoPtr;
	unsigned diskType;
	unsigned density;
	unsigned numCyls;
	unsigned numHeads;
	int *sectSizeInfoPtr;
	int retryCount;
	int track;
	int sectorTest;
	unsigned char readIdStatus[8];
	void *bounceBuffer;

	// Clear formatted flag (bit 0 at offset 0x18c)
	_flags = _flags & 0xfffffffe;

	// Reset to default density
	[self _setDensityInt:0];

	// Try to recalibrate drive (up to 3 attempts)
	retryCount = 0;
	do {
		result = [self _fdRecal];
		if (result == IO_R_SUCCESS) {
			break;
		}
		retryCount++;
	} while (retryCount < 3);

	if (result != IO_R_SUCCESS) {
		return;  // Recalibrate failed
	}

	// Get drive status
	result = [self _fdGetStatus:&status];
	if (result != IO_R_SUCCESS) {
		IOLog("fd updatePhysicalParametersInt: GET STATUS FAILED");
		return;
	}

	// Check ready bit (bit 4)
	if ((status & 0x10) == 0) {
		return;  // Drive not ready
	}

	// Check unit select (bits 0-1)
	if ((status & 3) == 0) {
		return;  // No unit selected
	}

	// Check write protect bit (bit 3) and store in flags
	if ((status & 8) == 0) {
		_flags = _flags & 0xfffffffb;  // Clear write protect flag
	} else {
		_flags = _flags | 4;  // Set write protect flag (bit 2)
	}

	// Look up disk info based on unit select bits
	diskInfoPtr = (unsigned *)&fdDiskInfo;
	while (*diskInfoPtr != 0) {
		if (*diskInfoPtr == (status & 3)) {
			break;
		}
		diskInfoPtr += 4;  // Move to next entry
	}

	// Set disk parameters from table
	// Table: [diskType, density/numHeads, numCyls, numHeads]
	_diskType = diskInfoPtr[0];       // offset 0x17c
	_density = diskInfoPtr[1];        // offset 0x180
	_numCyls = diskInfoPtr[2];        // offset 0x184
	numHeads = diskInfoPtr[3];        // offset 0x188

	// Probe for density by trying different densities
	// Start at highest density and work down
	track = 1;
	for (density = numHeads; density != 0; density--) {
		_fdcNumber = density;  // offset 400

		// Try to seek and read ID at this density (3 attempts)
		retryCount = 0;
		do {
			result = [self _fdSeek:track head:0];
			if (result == IO_R_SUCCESS) {
				result = [self _fdReadId:0 statp:readIdStatus];
				if (result == IO_R_SUCCESS) {
					break;  // Success at this density
				}
			}
			track++;
			retryCount++;
		} while (retryCount < 3);

		if (result == IO_R_SUCCESS) {
			break;  // Found working density
		}
	}

	// Set the detected density
	[self _setDensityInt:density];

	if (density == 0) {
		return;  // No valid density found
	}

	// Probe for sector size
	bounceBuffer = _bounceBuffer;  // offset 0x1b0
	sectSizeInfoPtr = (int *)fdGetSectSizeInfo(density);

	// Try each sector size in the table
	while (*sectSizeInfoPtr != 0) {
		[self _setSectSizeInt:*sectSizeInfoPtr];

		// Try to read sectors at different positions (3 attempts)
		sectorTest = 0;
		retryCount = 0;
		do {
			result = [self _rawReadInt:sectorTest
				       sectCount:1
					  buffer:bounceBuffer];
			if (result == IO_R_SUCCESS) {
				break;  // Success with this sector size
			}
			// Try next sector (skip by sectorsPerTrack)
			sectorTest = sectorTest + 1 + sectSizeInfoPtr[2];
			retryCount++;
		} while (retryCount < 3);

		if (result == IO_R_SUCCESS) {
			break;  // Found working sector size
		}

		sectSizeInfoPtr += 4;  // Try next sector size
	}

	// Set formatted flag if we successfully detected parameters
	if (*sectSizeInfoPtr != 0) {
		_flags = _flags | 1;
	}
}

@end
