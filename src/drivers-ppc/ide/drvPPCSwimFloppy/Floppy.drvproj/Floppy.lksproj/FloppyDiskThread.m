/*
 * FloppyDiskThread.m - FloppyDisk Thread category implementation
 *
 * Methods run on the I/O thread, and the thread's main loop.
 */

#import "FloppyDisk.h"
#import <machkit/NXLock.h>

static struct fd_sectsize_info *fdGetSectSizeInfo(int density);

@implementation FloppyDisk(Thread)

- (void)fdCmdDispatch:(fdBuf_t *)fdBuf
{
    IOReturn rtn = IO_R_SUCCESS;
    fdBuf_t *abortBuf;

    donone("fdCmdDispatch: fdBuf 0x%x cmd = %s\n", fdBuf,
        IOFindNameForValue(fdBuf->command, fdOpValues), 3, 4, 5);
    switch (fdBuf->command) {
    case FDC_IOREQ:
        rtn = [self fdSendCmd:fdBuf->fdIoReq];
        break;
    case FDC_READ:
    case FDC_WRITE:
        rtn = [self fdRwCommon:fdBuf];
        break;
    case FDC_EJECT:
        rtn = [self fdEjectInt];
        break;
    case FDC_ABORT:
        [ioQLock lock];
        while (!queue_empty(&ioQueueDisk)) {
            abortBuf = (fdBuf_t *)queue_first(&ioQueueDisk);
            queue_remove(&ioQueueDisk, abortBuf, fdBuf_t *, link);
            [ioQLock unlock];
            abortBuf->status = IO_R_NO_DISK;
            if (abortBuf->fdIoReq != NULL)
                abortBuf->fdIoReq->status = FDR_VOLUNAVAIL;
            [self fdIoComplete:abortBuf];
            [ioQLock lock];
        }
        [ioQLock unlock];
        break;
    case FDC_PROBEDISK:
        break;
    case FDC_SET_DENSITY:
        rtn = [self setDensityInt:*(int *)fdBuf->buf];
        break;
    case FDC_SET_SECTSIZE:
        rtn = [self setSectSizeInt:*(int *)fdBuf->buf];
        break;
    case FDC_SET_GAP:
        rtn = [self setGapInt:*(int *)fdBuf->buf];
        break;
    case FDC_SET_INNER_RETRY:
        innerRetryCount = *(int *)fdBuf->buf;
        break;
    case FDC_SET_OUTER_RETRY:
        outerRetryCount = *(int *)fdBuf->buf;
        break;
    case FDC_GET_INNER_RETRY:
    case FDC_GET_OUTER_RETRY:
        /* Reference returns innerRetryCount for both. */
        *(int *)fdBuf->buf = innerRetryCount;
        break;
    case FDC_GET_FORMAT:
        donone("FDC_GET_FORMAT: in FloppyDiskThread.m\n");
        memcpy(fdBuf->buf, &formatInfo, sizeof(struct fd_format_info));
        break;
    case FDC_GET_PHYS_PARAMS:
        rtn = [self updatePhysicalParametersInt];
        break;
    case FDC_THREAD_ABORT:
        fdBuf->status = IO_R_SUCCESS;
        donone("fdCmdDispatch: TERMINATING IO THREAD\n", 1, 2, 3, 4, 5);
        [self fdIoComplete:fdBuf];
        IOExitThread();
        break;
    case FDC_TIMER_EVENT:
        [self motorOffCheck];
        break;
    default:
        donone("%s: Bogus fdBuf->command in fdCmdDispatch\n", [self name],
            2, 3, 4, 5);
        IOPanic("FloppyThread");
        break;
    }
    if (fdBuf->async) {
        donone("fdCmdDispatch: ASYNC; DONE: cmd = %s\n",
            IOFindNameForValue(fdBuf->command, fdOpValues), 2, 3, 4, 5);
        [self freeFdBuf:fdBuf];
    } else {
        fdBuf->status = rtn;
        donone("fdCmdDispatch: DONE: cmd = %s status = %s\n",
            IOFindNameForValue(fdBuf->command, fdOpValues),
            [self stringFromReturn:fdBuf->status], 3, 4, 5);
        [self fdIoComplete:fdBuf];
    }
}

- (IOReturn)fdEjectInt
{
    struct fd_ioreq ioReq;
    IOReturn rtn;
    BOOL fatal = NO;
    int retry;

    /* The reference seeks innerRetryCount + 1 times even when a seek succeeds. */
    for (retry = 0; retry <= innerRetryCount; retry++) {
        rtn = [self fdSeek:79 head:0];
        if (rtn == IO_R_SUCCESS)
            continue;
        if (retry == innerRetryCount)
            fatal = YES;
        donone("%s seek: %s; %s\n", [self name], [self stringFromReturn:rtn],
            fatal ? "FATAL" : "RETRYING");
        if (fatal)
            return rtn;
    }
    bzero(&ioReq, sizeof(ioReq));
    ioReq.command = FDCMD_EJECT;
    rtn = [self fdSendCmd:&ioReq];
    if (rtn == IO_R_SUCCESS)
        rtn = fdrToIo(ioReq.status);
    donone("fdEjectInt: returning %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    [self setLastReadyState:(rtn == IO_R_SUCCESS) ? IO_NoDisk : IO_NotReady];
    return rtn;
}

- (IOReturn)fdRwCommon:(fdBuf_t *)fdBuf
{
    unsigned block = fdBuf->block;
    unsigned blocksLeft = fdBuf->blockCount;
    char *buf = fdBuf->buf;
    unsigned sectSize = formatInfo.sectsize_info.sect_size;
    BOOL readFlag = (fdBuf->command == FDC_READ);
    int innerRetry = 0;
    int outerRetry = 0;
    BOOL retrying = NO;
    struct fd_ioreq ioReq;
    IOReturn rtn;
    int blockCount;
    unsigned blocksXfr;
    ns_time_t startTime, endTime;

    donone("fdRwCommon: block 0x%x count 0x%x\n", block, blocksLeft, 3, 4, 5);
    IOGetTimestamp(&startTime);

    /* Reference: with blockCount 0 the uninitialised ioReq.status is used. */
    while (blocksLeft != 0) {
        blockCount = [self rwBlockCount:block blockCount:blocksLeft];
        [self fdGenRwCmd:block blockCount:blockCount fdIoReq:&ioReq
            readFlag:readFlag];
        ioReq.command = FDCMD_CMD_XFR;
        ioReq.byte_count = blockCount * sectSize;
        ioReq.addrs = buf;
        ioReq.map = (struct vm_map *)fdBuf->client;
        rtn = [self fdSendCmd:&ioReq];

        /* the sector with the CRC error was not transferred */
        if (ioReq.status == FDR_DATACRC && ioReq.bytes_xfr != 0)
            ioReq.bytes_xfr -= sectSize;
        blocksXfr = ioReq.bytes_xfr / sectSize;
        blocksLeft -= blocksXfr;
        block += blocksXfr;
        buf += ioReq.bytes_xfr;

        if (fdBuf->singleShot)
            break;
        if (rtn != IO_R_SUCCESS)
            ioReq.status = FDR_REJECT;

        switch (ioReq.status) {
        case FDR_SUCCESS:
            if (!retrying)
                continue;
            donone("fdRwCommon: RETRY SUCCEEDED\n", 1, 2, 3, 4, 5);
            retrying = NO;
            innerRetry = 0;
            outerRetry = 0;
            break;
        case FDR_TIMEOUT:
        case FDR_DATACRC:
        case FDR_HDRCRC:
        case FDR_MEDIA:
        case FDR_SEEK:
        case FDR_DRIVE_FAIL:
        case FDR_NOHDR:
        case FDR_NO_ADDRS_MK:
        case FDR_CNTRL_MK:
        case FDR_NO_DATA_MK:
        case FDR_DMAOURUN:
            retrying = YES;
            if (++innerRetry != innerRetryCount) {
                [self logRwErr:"RETRYING" block:block status:ioReq.status
                    readFlag:readFlag];
                break;
            }
            if (++outerRetry == outerRetryCount)
                goto fatal;
            [self logRwErr:"RECALIBRATING" block:block status:ioReq.status
                readFlag:readFlag];
            [self fdRecal];
            innerRetry = 0;
            break;
        default:
            goto fatal;
        }
        if (retrying) {
            if (readFlag)
                [self incrementReadRetries];
            else
                [self incrementWriteRetries];
        }
    }
    goto done;

fatal:
    [self logRwErr:"FATAL" block:block status:ioReq.status readFlag:readFlag];
done:
    fdBuf->bytesXfr = (fdBuf->blockCount - blocksLeft) * sectSize;
    rtn = fdBuf->status = fdrToIo(ioReq.status);
    if (ioReq.status != FDR_SUCCESS) {
        if (readFlag)
            [self incrementReadErrors];
        else
            [self incrementWriteErrors];
    } else {
        IOGetTimestamp(&endTime);
        if (readFlag)
            [self addToBytesRead:fdBuf->bytesXfr totalTime:endTime - startTime
                latentTime:0];
        else
            [self addToBytesWritten:fdBuf->bytesXfr
                totalTime:endTime - startTime latentTime:0];
    }
    donone("fdRwCommon: returning %s\n", [self stringFromReturn:rtn], 2, 3, 4, 5);
    return rtn;
}

- (void)logRwErr:(const char *)errType block:(int)block status:(fd_return_t)status readFlag:(BOOL)readFlag
{
    donone("%s: Sector %d cmd = %s; %s: %s\n", [self name], block,
        readFlag ? "Read" : "Write", IOFindNameForValue(status, fdrValues),
        errType);
}

- (IOReturn)setDensityInt:(int)density
{
    BOOL useMax = NO;
    struct fd_density_info *densityInfo;

    donone("setDensityInt: density %s\n",
        IOFindNameForValue(density, densityValues), 2, 3, 4, 5);
    if (density == 0) {
        useMax = YES;
        density = formatInfo.disk_info.max_density;
    }
    /* stops at the matching entry or the terminating one */
    for (densityInfo = fdDensityInfo; densityInfo->density != 0; densityInfo++)
        if (densityInfo->density == density)
            break;
    formatInfo.density_info = *densityInfo;
    [self setSectSizeInt:formatInfo.sectsize_info.sect_size];
    if (useMax)
        formatInfo.flags &= ~FFI_FORMATTED;
    return IO_R_SUCCESS;
}

- (IOReturn)setSectSizeInt:(int)sectSize
{
    struct fd_sectsize_info *ssi;
    unsigned sectsPerTrk;

    donone("setSectSizeInt: sectSize %d\n", sectSize, 2, 3, 4, 5);
    for (ssi = fdGetSectSizeInfo(formatInfo.density_info.density);
         ssi->sect_size != 0; ssi++)
        if (ssi->sect_size == sectSize)
            break;
    if (ssi->sect_size == 0)
        return IO_R_INVALID_ARG;

    /* The reference keeps the old sects_per_trk over the table's value. */
    sectsPerTrk = formatInfo.sectsize_info.sects_per_trk;
    formatInfo.sectsize_info = *ssi;
    formatInfo.sectsize_info.sects_per_trk = sectsPerTrk;
    formatInfo.total_sects = formatInfo.disk_info.tracks_per_cyl *
        sectsPerTrk * formatInfo.disk_info.num_cylinders;
    formatInfo.flags = (formatInfo.flags | FFI_FORMATTED) & ~FFI_LABELVALID;
    [self setBlockSize:sectSize];
    [self setDiskSize:formatInfo.disk_info.tracks_per_cyl *
        formatInfo.sectsize_info.sects_per_trk *
        formatInfo.disk_info.num_cylinders];
    return IO_R_SUCCESS;
}

- (IOReturn)setGapInt:(int)gapLength
{
    donone("setGapInt: rwGap = %d\n", gapLength, 2, 3, 4, 5);
    formatInfo.sectsize_info.rw_gap_length = gapLength;
    return IO_R_SUCCESS;
}

- (IOReturn)updatePhysicalParametersInt
{
    int writeProtected;

    donone("fd updatePhysicalParametersInt\n", 1, 2, 3, 4, 5);
    [self setFormattedInternal:NO];
    GetBusyFlag();
    FloppyFormatInfo(&formatInfo);
    formatInfo.density_info.density = formatInfo.disk_info.max_density;
    [self setFormattedInternal:YES];
    [self setSectSizeInt:512];
    formatInfo.flags |= FFI_FORMATTED;
    writeProtected = FloppyWriteProtected();
    if (formatInfo.sectsize_info.sects_per_trk == 10)
        writeProtected = 1;
    [self setWriteProtected:writeProtected];
    if (writeProtected)
        formatInfo.flags |= FFI_WRITEPROTECT;
    else
        formatInfo.flags &= ~FFI_WRITEPROTECT;
    ResetBusyFlag();
    return IO_R_SUCCESS;
}

- (void)unlockIoQLock
{
    IODiskReadyState readyState = [self lastReadyState];

    if (!queue_empty(&ioQueueNodisk) ||
        (!queue_empty(&ioQueueDisk) && readyState != IO_NoDisk))
        [ioQLock unlockWith:1];
    else
        [ioQLock unlockWith:0];
}

- (void)motorOffCheck
{
    struct fd_ioreq ioReq;
    ns_time_t now;

    if ([self lastReadyState] == IO_NoDisk) {
        donone("motorOffCheck:  no disk; quitting\n", 1, 2, 3, 4, 5);
        return;
    }
    IOGetTimestamp(&now);
    if (lastAccess + 2000000000ULL > now) {
        donone("motorOffCheck: scheduling fdTimer\n", 1, 2, 3, 4, 5);
        timerRunning = 1;
        IOScheduleFunc(fdTimer, self, 2);
    } else {
        bzero(&ioReq, sizeof(ioReq));
        ioReq.command = FDCMD_MOTOR_OFF;
        [self fdSendCmd:&ioReq];
    }
}

@end

/*
 * I/O thread. Requests that need no disk run first; requests that need a
 * disk wait while there is none, and then the volume check is posted.
 */
void fdThread(void *arg)
{
    FloppyDisk *disk = arg;
    fdBuf_t *fdBuf;

    donone("fdThread: starting\n", 1, 2, 3, 4, 5);
    for (;;) {
        [disk->ioQLock lockWhen:1];
        while (!queue_empty(&disk->ioQueueNodisk)) {
            fdBuf = (fdBuf_t *)queue_first(&disk->ioQueueNodisk);
            queue_remove(&disk->ioQueueNodisk, fdBuf, fdBuf_t *, link);
            [disk->ioQLock unlock];
            [disk fdCmdDispatch:fdBuf];
            [disk->ioQLock lock];
        }
        while (!queue_empty(&disk->ioQueueDisk) &&
               [disk lastReadyState] != IO_NoDisk) {
            fdBuf = (fdBuf_t *)queue_first(&disk->ioQueueDisk);
            queue_remove(&disk->ioQueueDisk, fdBuf, fdBuf_t *, link);
            [disk->ioQLock unlock];
            [disk fdCmdDispatch:fdBuf];
            [disk->ioQLock lock];
        }
        if (!queue_empty(&disk->ioQueueDisk) &&
            [disk lastReadyState] == IO_NoDisk) {
            [disk unlockIoQLock];
            donone("fdThread: volCheckRequest()\n", 1, 2, 3, 4, 5);
            volCheckRequest(disk, 0);
        } else
            [disk unlockIoQLock];
    }
}

static struct fd_sectsize_info *fdGetSectSizeInfo(int density)
{
    fdDensitySectsize_t *ds;

    for (ds = fdDensitySectsize; ds->ssi != NULL; ds++)
        if (ds->density == density)
            return ds->ssi;
    IOPanic("fdGetSectSizeInfo: bad density\n");
    return NULL;
}

/* End of FloppyDiskThread.m */
