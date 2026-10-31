/*
 * FloppyDiskInt.m - FloppyDisk Internal category implementation
 *
 * Internal methods for floppy disk operations
 */

#import "FloppyDisk.h"
#import <machkit/NXLock.h>
#import <string.h>
#import <stdio.h>

@implementation FloppyDisk(Internal)

- (int)floppyInit:(int)unit
{
    char name[12];
    void *allocBuf = NULL;
    unsigned allocSize;

    donone("floppyInit unit %d\n", unit, 2, 3, 4, 5);
    queue_init(&ioQueueDisk);
    queue_init(&ioQueueNodisk);
    innerRetryCount = 3;
    outerRetryCount = 3;
    floppySectorBuffer = floppyMalloc(0x400, &allocBuf, &allocSize);
    if (floppySectorBuffer == NULL)
        donone("floppyMalloc failed;but ignoring\n");
    driveInfo = &fdDriveInfo;
    formatInfo.density_info = fdDensityInfo[0];
    formatInfo.sectsize_info = *fdDensitySectsize[0].ssi;
    formatInfo.total_sects = 0;
    formatInfo.flags = 0;
    timerRunning = 0;

    sprintf(name, "fd%d", unit);
    [self setUnit:unit];
    [self setName:name];
    [self setDriveName:driveInfo->gen_drive_info.di_name];
    [self setRemovable:YES];
    [self setLastReadyState:YES];
    if ([self updatePhysicalParameters] == IO_R_NO_DEVICE) {
        donone("floppyInit: drive not present\n", 1, 2, 3, 4, 5);
        return 1;
    }
    [super init];
    donone("floppyInit unit %d, SUCCESS\n", unit, 2, 3, 4, 5);
    return 0;
}

- initResources:controller
{
    donone("floppy initResources\n", 1, 2, 3, 4, 5);
    cntrlr = controller;
    ioQLock = [NXConditionLock alloc];
    [ioQLock initWith:0];
    IOForkThread(fdThread, self);
    return self;
}

- free
{
    donone("floppy free\n", 1, 2, 3, 4, 5);
    [self fdSimpleCommand:FDC_THREAD_ABORT buffer:NULL needsDisk:NO];
    [ioQLock free];
    return [super free];
}

- (fdBuf_t *)allocFdBuf:(void *)pending
{
    fdBuf_t *fdBuf;

    fdBuf = IOMalloc(sizeof(fdBuf_t));
    bzero(fdBuf, sizeof(fdBuf_t));
    if (pending == NULL) {
        fdBuf->waitLock = [NXConditionLock alloc];
        [fdBuf->waitLock initWith:0];
    } else
        fdBuf->pending = pending;
    return fdBuf;
}

- (void)freeFdBuf:(fdBuf_t *)fdBuf
{
    if (fdBuf->waitLock != nil)
        [fdBuf->waitLock free];
    IOFree(fdBuf, sizeof(fdBuf_t));
}

- (IOReturn)fdSimpleCommand:(fdCommand_t)command buffer:(void *)buf needsDisk:(BOOL)needsDisk
{
    fdBuf_t *fdBuf;
    IOReturn rtn;

    fdBuf = [self allocFdBuf:NULL];
    fdBuf->command = command;
    fdBuf->buf = buf;
    fdBuf->needsDisk = needsDisk;
    fdBuf->async = 0;
    rtn = [self enqueueFdBuf:fdBuf];
    [self freeFdBuf:fdBuf];
    return rtn;
}

- (IOReturn)fdSimpleIoReq:(fd_ioreq_t)fdIoReq needsDisk:(BOOL)needsDisk
{
    fdBuf_t *fdBuf;
    IOReturn rtn;

    fdBuf = [self allocFdBuf:NULL];
    fdBuf->command = FDC_IOREQ;
    fdBuf->fdIoReq = fdIoReq;
    fdBuf->needsDisk = needsDisk;
    fdBuf->async = 0;
    donone("FloppyDiskInt.m:fdSimpleIoReq:enqueing\n");
    rtn = [self enqueueFdBuf:fdBuf];
    [self freeFdBuf:fdBuf];
    return rtn;
}

- (IOReturn)deviceRwCommon:(int)direction block:(unsigned)block length:(unsigned)length buffer:(void *)buffer client:(vm_task_t)client pending:(void *)pending actualLength:(unsigned *)actualLength
{
    IOReturn rtn;
    unsigned blockSize;
    unsigned bytesXfr;

    rtn = [self isDiskReady:YES];
    if (rtn == IO_R_NO_DISK) {
        donone("Floppy deviceRwCommon: disk not present\n", 1, 2, 3, 4, 5);
        donone("Floppy deviceRwCommon: disk not present\n");
        return rtn;
    }
    if (rtn != IO_R_SUCCESS) {
        donone("%s deviceRwCommon: bogus return from isDiskReady (%s)\n",
            [self name], [self stringFromReturn:rtn]);
        return rtn;
    }
    if (![self isFormatted]) {
        donone("deviceRwCommon:unformatted\n");
        return IO_R_UNFORMATTED;
    }
    blockSize = [self blockSize];
    donone("blksize=%d,dev_size=%d\n", blockSize, [self diskSize]);
    if (length != (length / blockSize) * blockSize) {
        donone("deviceRwCommon: unaligned length\n", 1, 2, 3, 4, 5);
        return IO_R_INVALID;
    }
    GetBusyFlag();
    if (client == (vm_task_t)kernel_map)
        DataSource = 1;
    else
        DataSource = 2;
    rtn = FloppyPluginIO(&bytesXfr, length, buffer, block * blockSize,
        direction == FDC_READ ? 0 : 1, 0);
    /* Reference stores unconditionally; the async callers pass NULL. */
    if (actualLength != NULL)
        *actualLength = bytesXfr;
    ResetBusyFlag();
    return rtn;
}

- (void)timerEvent
{
    fdBuf_t *fdBuf;

    fdBuf = [self allocFdBuf:NULL];
    fdBuf->command = FDC_TIMER_EVENT;
    fdBuf->needsDisk = 0;
    fdBuf->async = 1;
    [self enqueueFdBuf:fdBuf];
}

- (IOReturn)enqueueFdBuf:(fdBuf_t *)fdBuf
{
    queue_head_t *q;

    fdBuf->status = IO_R_INVALID;
    [ioQLock lock];
    if (fdBuf->needsDisk)
        q = &ioQueueDisk;
    else
        q = &ioQueueNodisk;
    queue_enter(q, fdBuf, fdBuf_t *, link);
    [ioQLock unlockWith:1];
    if (fdBuf->pending != NULL || fdBuf->async)
        return IO_R_SUCCESS;
    [fdBuf->waitLock lockWhen:1];
    [fdBuf->waitLock unlock];
    donone("enqueueFdBuf: I/O Complete fdBuf 0x%x status %s\n", fdBuf,
        [self stringFromReturn:fdBuf->status], 3, 4, 5);
    return fdBuf->status;
}

- (IOReturn)fdRecal
{
    fdIoReq_t ioReq;
    IOReturn rtn;

    donone("fdRecal\n", 1, 2, 3, 4, 5);
    bzero(&ioReq, sizeof(ioReq));
    ioReq.cmd_blk[0] = FCCMD_RECAL;
    ioReq.cmd_blk[1] = 1;		/* drive_sel */
    ioReq.timeout = 20000;
    ioReq.command = FDCMD_CMD_XFR;
    ioReq.num_cmd_bytes = 2;
    ioReq.addrs = 0;
    ioReq.byte_count = 0;
    ioReq.num_stat_bytes = sizeof(struct fd_int_stat);
    rtn = [self fdSendCmd:&ioReq];
    if (rtn == IO_R_SUCCESS)
        rtn = fdrToIo(ioReq.status);
    donone("fdRecal: returning %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    return rtn;
}

- (IOReturn)fdSeek:(int)cylinder head:(int)head
{
    fdIoReq_t ioReq;
    IOReturn rtn;
    int density;

    donone("fdSeek head %d cyl %d\n", head, cylinder, 3, 4, 5);
    bzero(&ioReq, sizeof(ioReq));
    ioReq.cmd_blk[0] = FCCMD_SEEK;
    ioReq.cmd_blk[1] = ((head & 1) << 2) | 1;	/* hds, drive_sel */
    ioReq.cmd_blk[2] = cylinder;
    density = [self getCurrentDensity];
    if (density == FD_DENS_NONE)
        density = FD_DENS_4;
    ioReq.density = density;
    ioReq.timeout = 5000;
    ioReq.command = FDCMD_CMD_XFR;
    ioReq.num_cmd_bytes = SIZEOF_SEEK_CMD;
    ioReq.addrs = 0;
    ioReq.byte_count = 0;
    ioReq.num_stat_bytes = sizeof(struct fd_int_stat);
    rtn = [self fdSendCmd:&ioReq];
    if (rtn == IO_R_SUCCESS)
        rtn = fdrToIo(ioReq.status);
    donone("fdSeek: returning %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    return rtn;
}

- (IOReturn)fdGetStatus:(struct fd_drive_stat *)driveStat
{
    fdIoReq_t ioReq;
    IOReturn rtn;

    donone("fdGetStatus\n", 1, 2, 3, 4, 5);
    bzero(&ioReq, sizeof(ioReq));
    ioReq.command = FDCMD_GET_STATUS;
    ioReq.timeout = 5000;
    rtn = [self fdSendCmd:&ioReq];
    donone("fdGetStatus: returning %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    *driveStat = ioReq.drive_stat;
    return rtn;
}

- (IOReturn)fdReadId:(int)head statp:(struct fd_rw_stat *)statp
{
    fdIoReq_t ioReq;
    struct fd_readid_cmd *cmdp = (struct fd_readid_cmd *)ioReq.cmd_blk;
    IOReturn rtn;

    donone("fdReadId head %d\n", head, 2, 3, 4, 5);
    bzero(&ioReq, sizeof(ioReq));
    cmdp->opcode = FCCMD_READID;
    cmdp->mfm = formatInfo.density_info.mfm;
    cmdp->hds = head;
    cmdp->drive_sel = 1;
    ioReq.timeout = 20000;
    ioReq.command = FDCMD_CMD_XFR;
    ioReq.num_cmd_bytes = 2;
    ioReq.addrs = 0;
    ioReq.byte_count = 0;
    ioReq.num_stat_bytes = SIZEOF_RW_STAT;
    ioReq.flags = 0;
    rtn = [self fdSendCmd:&ioReq];
    if (rtn == IO_R_SUCCESS)
        rtn = fdrToIo(ioReq.status);
    donone("fdReadId: returning %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    *statp = *(struct fd_rw_stat *)ioReq.stat_blk;
    return rtn;
}

- (fd_return_t)rawReadInt:(int)sector sectCount:(int)sectCount buffer:(void *)buffer
{
    fdIoReq_t ioReq;
    fd_return_t status;

    donone("fd rawReadInt: sect %d count %d\n", sector, sectCount, 3, 4, 5);
    bzero(&ioReq, sizeof(ioReq));
    [self fdGenRwCmd:sector blockCount:sectCount fdIoReq:&ioReq readFlag:YES];
    ioReq.addrs = buffer;
    ioReq.byte_count = sectCount * formatInfo.sectsize_info.sect_size;
    if ([self fdSendCmd:&ioReq] == IO_R_SUCCESS &&
        ioReq.bytes_xfr != ioReq.byte_count) {
        donone("rawReadInt: expected %d bytes; got %d\n",
            ioReq.byte_count, ioReq.bytes_xfr, 3, 4, 5);
        status = FDR_DMAOURUN;
    } else
        status = ioReq.status;
    donone("rawReadInt: returning %s\n", IOFindNameForValue(status, fdrValues),
        2, 3, 4, 5);
    return status;
}

- (int)rwBlockCount:(int)block blockCount:(int)blockCount
{
    struct fd_rw_cmd rwCmd;
    int blocksToDo;

    [self fdLogToPhys:block cmdp:&rwCmd];
    if (rwCmd.sector + blockCount > formatInfo.sectsize_info.sects_per_trk + 1)
        blocksToDo = formatInfo.sectsize_info.sects_per_trk - rwCmd.sector + 1;
    else
        blocksToDo = blockCount;
    donone("rwBlockCount: block 0x%x blockCount 0x%x blocksToDo 0x%x\n",
        block, blockCount, blocksToDo, 4, 5);
    return blocksToDo;
}

- (void)fdGenRwCmd:(int)block blockCount:(int)blockCount fdIoReq:(fd_ioreq_t)fdIoReq readFlag:(BOOL)readFlag
{
    struct fd_rw_cmd *cmdp = (struct fd_rw_cmd *)fdIoReq->cmd_blk;

    donone("fdGenRwCmd: block 0x%x blockCount 0x%x read = %d\n",
        block, blockCount, readFlag, 4, 5);
    bzero(cmdp, SIZEOF_RW_CMD);
    [self fdLogToPhys:block cmdp:cmdp];
    cmdp->mt = 0;
    cmdp->mfm = formatInfo.density_info.mfm;
    cmdp->opcode = readFlag ? FCCMD_READ : FCCMD_WRITE;
    cmdp->hds = cmdp->head;
    cmdp->drive_sel = 1;
    cmdp->sector_size = formatInfo.sectsize_info.n;
    cmdp->eot = cmdp->sector + blockCount - 1;
    cmdp->gap_length = formatInfo.sectsize_info.rw_gap_length;
    cmdp->dtl = 0xff;
    fdIoReq->timeout = 20000;
    fdIoReq->command = FDCMD_CMD_XFR;
    fdIoReq->num_cmd_bytes = SIZEOF_RW_CMD;
    fdIoReq->num_stat_bytes = SIZEOF_RW_STAT;
    if (readFlag)
        fdIoReq->flags |= FD_IOF_DMA_RD;
    else
        fdIoReq->flags &= ~FD_IOF_DMA_DIR;
}

- (void)fdLogToPhys:(int)block cmdp:(struct fd_rw_cmd *)cmdp
{
    unsigned track = block / formatInfo.sectsize_info.sects_per_trk;

    cmdp->cylinder = track / formatInfo.disk_info.tracks_per_cyl;
    cmdp->head = track % formatInfo.disk_info.tracks_per_cyl;
    cmdp->sector = block % formatInfo.sectsize_info.sects_per_trk + 1;
}

- (void)fdIoComplete:(fdBuf_t *)fdBuf
{
    donone("%s fdIoComplete: fdBuf 0x%x status %s\n", [self name], fdBuf,
        [self stringFromReturn:fdBuf->status], 4, 5);
    if (fdBuf->pending != NULL) {
        [self completeTransfer:fdBuf->pending withStatus:fdBuf->status
            actualLength:fdBuf->bytesXfr];
        [self freeFdBuf:fdBuf];
    } else {
        [fdBuf->waitLock lock];
        [fdBuf->waitLock unlockWith:1];
    }
}

- (int)getCurrentDensity
{
    return formatInfo.density_info.density;
}

- (IOReturn)fdSendCmd:(fd_ioreq_t)fdIoReq
{
    fd_return_t rtn;

    donone("FloppyDiskInt.m:fdSendCmd:%s\n",
        IOFindNameForValue(fdIoReq->command, fdCommandValues));
    donone("fdSendCmd: sending %s\n",
        IOFindNameForValue(fdIoReq->command, fdCommandValues), 2, 3, 4, 5);
    fdIoReq->density = [self getCurrentDensity];
    if (fdIoReq->density == FD_DENS_NONE)
        fdIoReq->density = FD_DENS_4;
    fdIoReq->unit = [self unit];
    IOGetTimestamp(&lastAccess);
    rtn = [cntrlr fcCmdXfr:fdIoReq driveInfo:driveInfo];
    donone("fdSendCmd: returning from %s status %s\n",
        IOFindNameForValue(fdIoReq->command, fdCommandValues),
        IOFindNameForValue(fdIoReq->status, fdrValues), 3, 4, 5);
    if (fdIoReq->drive_stat.motor_on) {
        if (!timerRunning) {
            timerRunning = 1;
            IOScheduleFunc(fdTimer, self, 2);
        }
    } else {
        timerRunning = 0;
        IOUnscheduleFunc(fdTimer, self);
    }
    donone("fdSendCmd:rtn=%d,setting to 0\n", rtn);
    return IO_R_SUCCESS;
}

@end

void fdTimer(void *disk)
{
    FloppyDisk *fd = disk;

    if (fd->timerRunning)
        [fd timerEvent];
}

/* End of FloppyDiskInt.m */
