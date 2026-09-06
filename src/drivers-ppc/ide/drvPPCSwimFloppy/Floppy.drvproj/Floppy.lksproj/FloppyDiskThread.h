/*
 * FloppyDiskThread.h - FloppyDisk Thread category
 *
 * Thread-based operations for floppy disk
 */

#import "FloppyDisk.h"

@interface FloppyDisk(Thread)

// Thread methods
- (void)fdCmdDispatch:(void *)command;
- (IOReturn)fdEjectInt;
- (IOReturn)fdRwCommon:(void *)ioReq;
- (void)logRwErr:(void *)ioReq block:(unsigned)block status:(IOReturn)status readFlag:(BOOL)isRead;
- (void)motorOffCheck;
- (IOReturn)setDensityInt:(unsigned)density;
- (IOReturn)setGapInt:(unsigned)gap;
- (IOReturn)setSectSizeInt:(unsigned)sectSize;
- (void)unlockIoQLock;
- (IOReturn)updatePhysicalParametersInt;

@end

/* End of FloppyDiskThread.h */
