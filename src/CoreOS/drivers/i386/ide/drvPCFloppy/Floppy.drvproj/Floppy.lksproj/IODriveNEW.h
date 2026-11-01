/*
 * IODriveNEW.h - Base drive class interface
 *
 * Base class for disk drives with statistics tracking
 */

#import <driverkit/IODevice.h>
#import <driverkit/return.h>

@interface IODriveNEW : IODevice
{
	// Disk object
	id _diskId;                       // offset 0x108
	
	// Ready state
	int _lastReadyState;               // offset 0x10c
	
	// Drive name (24 bytes: 0x110 to 0x127)
	char _driveName[24];               // offset 0x110
	
	// Read statistics
	unsigned _readOps;                    // offset 0x128
	unsigned _bytesRead;                    // offset 0x12c (300 decimal)
	unsigned _readTotalTime;                // offset 0x130
	unsigned _readLatentTime;               // offset 0x134
	unsigned _readRetries;                  // offset 0x138
	unsigned _readErrors;                   // offset 0x13c
	
	// Write statistics
	unsigned _writeOps;                   // offset 0x140
	unsigned _bytesWritten;                 // offset 0x144
	unsigned _writeTotalTime;               // offset 0x148
	unsigned _writeLatentTime;              // offset 0x14c
	unsigned _writeRetries;                 // offset 0x150
	unsigned _writeErrors;                  // offset 0x154
	
	// Other statistics
	unsigned _otherRetries;                 // offset 0x158
	unsigned _otherErrors;                  // offset 0x15c
}

/*
 * Add to bytes read statistics.
 */
- (void)addToBytesRead:(unsigned)bytes
              totalTime:(unsigned long long)totalTime
             latentTime:(unsigned long long)latentTime;

/*
 * Add to bytes written statistics.
 */
- (void)addToBytesWritten:(unsigned)bytes
                 totalTime:(unsigned long long)totalTime
                latentTime:(unsigned long long)latentTime;

/*
 * Get drive name.
 */
- (const char *)driveName;

/*
 * Eject media (subclass responsibility).
 */
- (IOReturn)ejectMedia;

/*
 * Get integer parameter values.
 */
- (IOReturn)getIntValues:(unsigned *)values
             forParameter:(IOParameterName)parameterName
                    count:(unsigned *)count;

/*
 * Increment other errors counter.
 */
- (void)incrementOtherErrors;

/*
 * Increment other retries counter.
 */
- (void)incrementOtherRetries;

/*
 * Increment read errors counter.
 */
- (void)incrementReadErrors;

/*
 * Increment read retries counter.
 */
- (void)incrementReadRetries;

/*
 * Increment write errors counter.
 */
- (void)incrementWriteErrors;

/*
 * Increment write retries counter.
 */
- (void)incrementWriteRetries;

/*
 * Get last ready state.
 */
- (unsigned)lastReadyState;

/*
 * Register device with system.
 */
- (IOReturn)registerDevice;

/*
 * Set drive name.
 */
- (void)setDriveName:(const char *)name;

/*
 * Set last ready state.
 */
- (void)setLastReadyState:(unsigned)state;

@end

/* End of IODriveNEW.h */
