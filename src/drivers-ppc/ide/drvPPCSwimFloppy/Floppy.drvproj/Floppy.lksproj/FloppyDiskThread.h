/*
 * FloppyDiskThread.h - FloppyDisk Thread category
 */

#import "FloppyDisk.h"

@interface FloppyDisk(Thread)
- (void)fdCmdDispatch:(fdBuf_t *)fdBuf;
- (IOReturn)fdEjectInt;
- (IOReturn)fdRwCommon:(fdBuf_t *)fdBuf;
- (void)logRwErr:(const char *)errType block:(int)block status:(fd_return_t)status readFlag:(BOOL)readFlag;
- (IOReturn)setDensityInt:(int)density;
- (IOReturn)setSectSizeInt:(int)sectSize;
- (IOReturn)setGapInt:(int)gapLength;
- (IOReturn)updatePhysicalParametersInt;
- (void)unlockIoQLock;
- (void)motorOffCheck;
@end

/* End of FloppyDiskThread.h */
