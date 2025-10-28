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
- (id)_allocFdBuf:(unsigned)size;
- (IOReturn)_deviceRwCommon:(BOOL)isRead block:(unsigned)block length:(unsigned)length buffer:(void *)buffer client:(vm_task_t)client pending:(void *)pending actualLength:(unsigned *)actualLength;
- (void)_enqueueFdBuf:(id)buffer;
- (IOReturn)_fdGenRwCmd:(unsigned)block blockCount:(unsigned)blockCount fdIoReq:(void *)fdIoReq readFlag:(BOOL)isRead;
- (IOReturn)_fdGetStatus:(void *)status;
- (void)_fdIoComplete:(void *)ioReq;
- (IOReturn)_fdLogToPhys:(unsigned)logicalBlock cmdp:(void *)cmdp;
- (IOReturn)_fdReadId:(unsigned)cylinder statp:(void *)statp;
- (IOReturn)_fdRecal;
- (IOReturn)_fdSeek:(unsigned)cylinder head:(unsigned)head;
- (IOReturn)_fdSendCmd:(void *)command;
- (IOReturn)_fdSimpleCommand:(unsigned)command buffer:(void *)buffer needsDisk:(BOOL)needsDisk;
- (IOReturn)_fdSimpleIoReq:(void *)ioReq needsDisk:(BOOL)needsDisk;
- (IOReturn)_floppyInit:(id)controller;
- (void)_free;
- (void)_freeFdBuf:(id)buffer;
- (unsigned)_getCurrentDensity;
- (IOReturn)_initResources:(id)controller;
- (IOReturn)_rawReadInt:(unsigned)sector sectCount:(unsigned)sectCount buffer:(void *)buffer;
- (IOReturn)_rwBlockCount:(unsigned)block blockCount:(unsigned)blockCount;
- (void)_timerEvent;

@end

/* End of FloppyDiskInt.h */
