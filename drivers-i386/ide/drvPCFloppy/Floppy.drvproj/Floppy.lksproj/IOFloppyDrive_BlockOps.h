/*
 * IOFloppyDrive_BlockOps.h
 * Block operations for IOFloppyDrive
 */

#import "IOFloppyDrive.h"

/*
 * Block operations category for IOFloppyDrive
 * Contains block-level read/write operations
 */
@interface IOFloppyDrive(BlockOps)

// Block read/write operations
- (IOReturn)rwBlockCount:(void *)blockStruct blockCount:(unsigned int *)count;
- (IOReturn)fdGenCwdBlockCount:(void *)blockInfo count:(unsigned int *)count;
- (IOReturn)genCwdBlockCount:(unsigned int *)count;

// Sector size operations
- (IOReturn)getSectSizeInt:(unsigned int *)size;
- (IOReturn)getSectSizeInfo:(void *)info;
- (IOReturn)fdGetSectSizeInfo:(void *)info;

// Status operations
- (IOReturn)fdGetStatus:(void *)status;
- (IOReturn)updateStatus:(void *)status;
- (IOReturn)updateReadyStateInt:(void *)state;

// Seek operations
- (IOReturn)fdSeekHead:(unsigned int)head;
- (IOReturn)fdSeekTrack:(unsigned int)track;

@end
