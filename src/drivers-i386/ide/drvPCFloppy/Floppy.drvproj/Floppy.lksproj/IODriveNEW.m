/*
 * IODriveNEW.m - Base drive class implementation
 *
 * Base class for disk drives with statistics tracking
 */

#import "IODriveNEW.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

@implementation IODriveNEW

/*
 * Add to bytes read statistics.
 * From decompiled code: updates read statistics counters.
 */
- (void)addToBytesRead:(unsigned)bytes
              totalTime:(unsigned long long)totalTime
             latentTime:(unsigned long long)latentTime
{
	int timeInMs;
	
	// Increment read count
	_readCount++;
	
	// Add to total bytes read
	_bytesRead += bytes;
	
	// Convert totalTime from nanoseconds to milliseconds and add
	timeInMs = (int)(totalTime / 1000000);
	_readTotalTime += timeInMs;
	
	// Convert latentTime from nanoseconds to milliseconds and add
	timeInMs = (int)(latentTime / 1000000);
	_readLatentTime += timeInMs;
}

/*
 * Add to bytes written statistics.
 * From decompiled code: updates write statistics counters.
 */
- (void)addToBytesWritten:(unsigned)bytes
                 totalTime:(unsigned long long)totalTime
                latentTime:(unsigned long long)latentTime
{
	int timeInMs;
	
	// Increment write count
	_writeCount++;
	
	// Add to total bytes written
	_bytesWritten += bytes;
	
	// Convert totalTime from nanoseconds to milliseconds and add
	timeInMs = (int)(totalTime / 1000000);
	_writeTotalTime += timeInMs;
	
	// Convert latentTime from nanoseconds to milliseconds and add
	timeInMs = (int)(latentTime / 1000000);
	_writeLatentTime += timeInMs;
}

/*
 * Get drive name.
 * From decompiled code: returns stored drive name string.
 */
- (const char *)driveName
{
	// Return pointer to drive name string
	return _driveName;
}

/*
 * Eject media (subclass responsibility).
 * From decompiled code: frees disk object and sets ready state to not ready.
 */
- (IOReturn)ejectMedia
{
	// Free the disk object and store result
	_diskObject = [_diskObject free];
	
	// Set ready state to 2 (not ready)
	[self setLastReadyState:2];
	
	return IO_R_SUCCESS;
}

/*
 * Get integer parameter values.
 * From decompiled code: returns various drive parameters based on parameterName.
 */
- (IOReturn)getIntValues:(unsigned *)values
             forParameter:(IOParameterName)parameterName
                    count:(unsigned *)count
{
	unsigned maxCount;
	unsigned statsArray[14];
	int i;
	IOReturn result;
	
	// Get max count (default to 512 if not specified)
	maxCount = *count;
	if (maxCount == 0) {
		maxCount = 0x200;
	}
	
	// Check if parameter name is "IODiskStats"
	if (strcmp(parameterName, "IODiskStats") == 0) {
		// Fill stats array from instance variables
		statsArray[0] = _readCount;
		statsArray[1] = _bytesRead;
		statsArray[2] = _readTotalTime;
		statsArray[3] = _readLatentTime;
		statsArray[4] = _readRetries;
		statsArray[5] = _readErrors;
		statsArray[6] = _writeCount;
		statsArray[7] = _bytesWritten;
		statsArray[8] = _writeTotalTime;
		statsArray[9] = _writeLatentTime;
		statsArray[10] = _writeRetries;
		statsArray[11] = _writeErrors;
		statsArray[12] = _otherRetries;
		statsArray[13] = _otherErrors;
		
		// Copy stats to output array
		*count = 0;
		for (i = 0; i < 14; i++) {
			if (*count == maxCount) {
				break;
			}
			values[i] = statsArray[i];
			*count = *count + 1;
		}
		
		result = IO_R_SUCCESS;
	} else {
		// Call superclass for other parameters
		result = [super getIntValues:values forParameter:parameterName count:count];
	}
	
	return result;
}

/*
 * Increment other errors counter.
 * From decompiled code: increments other error statistics.
 */
- (void)incrementOtherErrors
{
	// Increment other errors counter
	_otherErrors++;
}

/*
 * Increment other retries counter.
 * From decompiled code: increments other retry statistics.
 */
- (void)incrementOtherRetries
{
	// Increment other retries counter
	_otherRetries++;
}

/*
 * Increment read errors counter.
 * From decompiled code: increments read error statistics.
 */
- (void)incrementReadErrors
{
	// Increment read errors counter
	_readErrors++;
}

/*
 * Increment read retries counter.
 * From decompiled code: increments read retry statistics.
 */
- (void)incrementReadRetries
{
	// Increment read retries counter
	_readRetries++;
}

/*
 * Increment write errors counter.
 * From decompiled code: increments write error statistics.
 */
- (void)incrementWriteErrors
{
	// Increment write errors counter
	_writeErrors++;
}

/*
 * Increment write retries counter.
 * From decompiled code: increments write retry statistics.
 */
- (void)incrementWriteRetries
{
	// Increment write retries counter
	_writeRetries++;
}

/*
 * Get last ready state.
 * From decompiled code: returns stored ready state value.
 */
- (unsigned)lastReadyState
{
	// Return ready state
	return _lastReadyState;
}

/*
 * Register device with system.
 * From decompiled code: clears statistics and registers device in device tree.
 */
- (IOReturn)registerDevice
{
	IOReturn result;
	
	// Clear all statistics counters
	_readCount = 0;
	_bytesRead = 0;
	_readTotalTime = 0;
	_readLatentTime = 0;
	_readRetries = 0;
	_readErrors = 0;
	_writeCount = 0;
	_bytesWritten = 0;
	_writeTotalTime = 0;
	_writeLatentTime = 0;
	_writeRetries = 0;
	_writeErrors = 0;
	_otherRetries = 0;
	_otherErrors = 0;
	
	// Call superclass registerDevice
	result = [super registerDevice];
	
	return result;
}

/*
 * Set drive name.
 * From decompiled code: stores drive name string with length limit.
 */
- (void)setDriveName:(const char *)name
{
	size_t length;
	size_t copyLength;
	
	// Calculate string length
	length = strlen(name);
	
	// Limit to 0x17 (23) characters
	copyLength = length;
	if (copyLength > 0x17) {
		copyLength = 0x17;
	}
	
	// Copy drive name
	strncpy(_driveName, name, copyLength);
	
	// Null-terminate at the end of the buffer
	_driveName[23] = '\0';
}

/*
 * Set last ready state.
 * From decompiled code: stores ready state value.
 */
- (void)setLastReadyState:(unsigned)state
{
	// Store ready state
	_lastReadyState = state;
}

@end

/* End of IODriveNEW.m */
