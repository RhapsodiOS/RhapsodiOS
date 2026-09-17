/*
 * FloppyDiskInt.h - FloppyDisk Internal category
 *
 * Internal methods for floppy disk operations
 */

#import "FloppyDisk.h"

@interface FloppyDisk(Internal)

// Helper method for async completion
- (void)completeTransfer:(void *)pending withStatus:(IOReturn)status actualTransfer:(unsigned)actualLength;

// Internal methods
- (id)allocFdBuf:(unsigned)size;
- (IOReturn)deviceRwCommon:(BOOL)isRead block:(unsigned)block length:(unsigned)length buffer:(void *)buffer client:(vm_task_t)client pending:(void *)pending actualLength:(unsigned *)actualLength;
- (void)enqueueFdBuf:(id)buffer;
- (IOReturn)fdGenRwCmd:(unsigned)block blockCount:(unsigned)blockCount fdIoReq:(void *)fdIoReq readFlag:(BOOL)isRead;
- (IOReturn)fdGetStatus:(void *)status;
- (void)fdIoComplete:(void *)ioReq;
- (IOReturn)fdLogToPhys:(unsigned)logicalBlock cmdp:(void *)cmdp;
- (IOReturn)fdReadId:(unsigned)cylinder statp:(void *)statp;
- (IOReturn)fdRecal;
- (IOReturn)fdSeek:(unsigned)cylinder head:(unsigned)head;
- (IOReturn)fdSendCmd:(void *)command;
- (IOReturn)fdSimpleCommand:(unsigned)command buffer:(void *)buffer needsDisk:(BOOL)needsDisk;
- (IOReturn)fdSimpleIoReq:(void *)ioReq needsDisk:(BOOL)needsDisk;
- (IOReturn)floppyInit:(id)controller;
- (void)free;
- (void)freeFdBuf:(id)buffer;
- (unsigned)getCurrentDensity;
- (IOReturn)initResources:(id)controller;
- (IOReturn)rawReadInt:(unsigned)sector sectCount:(unsigned)sectCount buffer:(void *)buffer;
- (IOReturn)rwBlockCount:(unsigned)block blockCount:(unsigned)blockCount;
- (void)timerEvent;

@end

/* End of FloppyDiskInt.h */
