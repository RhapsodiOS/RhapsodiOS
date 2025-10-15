/*
 * IOFloppyDrive_Internal.h
 * Internal methods for IOFloppyDrive
 */

#import "IOFloppyDrive.h"

/*
 * Internal category for IOFloppyDrive
 * Contains internal drive management methods
 */
@interface IOFloppyDrive(Internal)

// Sector operations
- (IOReturn)setSectSizeInt:(unsigned int)size;
- (IOReturn)setSectSizeInfo:(void *)sizeInfo;
- (unsigned int)getSectSizeInt;

// Read/Write internal
- (IOReturn)rwReadInt:(void *)buffer
               offset:(unsigned int)offset
               length:(unsigned int)length
               client:(vm_task_t)client;

- (IOReturn)rwBlockCount:(void *)blockInfo;
- (IOReturn)fdSectInit:(void *)sectInfo;

// Format operations
- (IOReturn)formatTrack:(unsigned int)head;
- (IOReturn)formatHead:(unsigned int)head;
- (IOReturn)allocateDisk:(void *)diskInfo;

// Device control
- (IOReturn)fdGenCwd:(void *)cwd blockCount:(unsigned int)count;
- (IOReturn)readFlag:(unsigned int *)flag;
- (IOReturn)fdReadInt:(void *)sectInfo;

@end
