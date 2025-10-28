/*
 * FloppyDiskThread.h - FloppyDisk Thread category
 *
 * Thread-based operations for floppy disk
 */

#import "FloppyDisk.h"

@interface FloppyDisk(Thread)

// Thread methods
- (void)_fdCmdDispatch:(void *)command;
- (IOReturn)_fdEjectInt;
- (IOReturn)_fdRwCommon:(void *)ioReq;
- (void)_logRwErr:(void *)ioReq block:(unsigned)block status:(IOReturn)status readFlag:(BOOL)isRead;
- (void)_motorOffCheck;
- (IOReturn)_setDensityInt:(unsigned)density;
- (IOReturn)_setGapInt:(unsigned)gap;
- (IOReturn)_setSectSizeInt:(unsigned)sectSize;
- (void)_unlockIoQLock;
- (IOReturn)_updatePhysicalParametersInt;

@end

/* End of FloppyDiskThread.h */
