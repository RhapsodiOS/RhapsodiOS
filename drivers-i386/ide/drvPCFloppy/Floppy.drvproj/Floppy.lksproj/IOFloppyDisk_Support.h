/*
 * IOFloppyDisk_Support.h
 * Support methods for IOFloppyDisk
 */

#import "IOFloppyDisk.h"

/*
 * Support category for IOFloppyDisk
 * Contains utility and support methods
 */
@interface IOFloppyDisk(Support)

// Utility methods
- (IOReturn)validateParameters:(unsigned int)offset length:(unsigned int)length;
- (IOReturn)convertOffset:(unsigned int)offset
               toCylinder:(unsigned int *)cyl
                     head:(unsigned int *)head
                   sector:(unsigned int *)sec;

// Cache management
- (void)invalidateCache;
- (void)flushCache;

// Media checking
- (IOReturn)checkMediaPresent;
- (IOReturn)checkWritable;

// Alignment and transfer calculation
- (IOReturn)alignOffset:(unsigned int)offset
          alignedOffset:(unsigned int *)aligned
                 length:(unsigned int)length
          alignedLength:(unsigned int *)alignedLen;

- (IOReturn)calculateTransferSize:(unsigned int)offset
                           length:(unsigned int)length
                   maxTransferSize:(unsigned int *)maxSize;

@end
