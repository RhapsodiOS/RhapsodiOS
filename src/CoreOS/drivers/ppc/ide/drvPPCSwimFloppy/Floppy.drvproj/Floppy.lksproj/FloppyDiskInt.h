/*
 * FloppyDiskInt.h - FloppyDisk Internal category
 */

#import "FloppyDisk.h"

@interface FloppyDisk(Internal)
- (int)floppyInit:(int)unit;
- initResources:controller;
- free;
- (fdBuf_t *)allocFdBuf:(void *)pending;
- (void)freeFdBuf:(fdBuf_t *)fdBuf;
- (IOReturn)fdSimpleCommand:(fdCommand_t)command buffer:(void *)buf needsDisk:(BOOL)needsDisk;
- (IOReturn)fdSimpleIoReq:(fd_ioreq_t)fdIoReq needsDisk:(BOOL)needsDisk;
- (IOReturn)deviceRwCommon:(int)direction block:(unsigned)block length:(unsigned)length buffer:(void *)buffer client:(vm_task_t)client pending:(void *)pending actualLength:(unsigned *)actualLength;
- (void)timerEvent;
- (IOReturn)enqueueFdBuf:(fdBuf_t *)fdBuf;
- (IOReturn)fdRecal;
- (IOReturn)fdSeek:(int)cylinder head:(int)head;
- (IOReturn)fdGetStatus:(struct fd_drive_stat *)driveStat;
- (IOReturn)fdReadId:(int)head statp:(struct fd_rw_stat *)statp;
- (fd_return_t)rawReadInt:(int)sector sectCount:(int)sectCount buffer:(void *)buffer;
- (int)rwBlockCount:(int)block blockCount:(int)blockCount;
- (void)fdGenRwCmd:(int)block blockCount:(int)blockCount fdIoReq:(fd_ioreq_t)fdIoReq readFlag:(BOOL)readFlag;
- (void)fdLogToPhys:(int)block cmdp:(struct fd_rw_cmd *)cmdp;
- (void)fdIoComplete:(fdBuf_t *)fdBuf;
- (int)getCurrentDensity;
- (IOReturn)fdSendCmd:(fd_ioreq_t)fdIoReq;
@end

/* End of FloppyDiskInt.h */
