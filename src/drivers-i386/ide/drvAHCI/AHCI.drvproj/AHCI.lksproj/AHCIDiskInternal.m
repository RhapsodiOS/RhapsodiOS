#import "AHCIDiskInternal.h"
#import "AHCIPort.h"
#import <bsd/dev/ata_hd_registry.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <machkit/NXLock.h>
#import <bsd/string.h>

extern unsigned int vm_page_size;

@implementation AHCIDisk(Internal)

- (BOOL)initResourcesForPort:(AHCIPort *)port
{
    unsigned int index;
    AHCIDiskRequest *request;

    _hdUnit = -1;
    _port = port;
    queue_init(&_requestQueue);
    queue_init(&_requestPool);
    _queueLock = [[NXConditionLock alloc] initWith:AHCI_DISK_NO_WORK];
    _poolLock = [NXLock new];
    if (_queueLock == nil || _poolLock == nil)
        return NO;
    [_poolLock lock];
    for (index = 0; index < AHCI_DISK_REQUEST_COUNT; ++index) {
        request = &_requests[index];
        bzero(request, sizeof(*request));
        request->waitLock = [[NXConditionLock alloc] initWith:NO];
        if (request->waitLock == nil) {
            [_poolLock unlock];
            return NO;
        }
        queue_enter(&_requestPool, request, AHCIDiskRequest *, poolLink);
    }
    [_poolLock unlock];
    IOForkThread((IOThreadFunc)AHCIDiskWorker, self);
    _workerStarted = YES;
    return YES;
}

- (BOOL)identifyDevice
{
    unsigned char fis[20];
    unsigned short *words;
    unsigned int transferred;
    IOReturn result;

    words = (unsigned short *)[_port identifyBuffer];
    if (words == 0)
        return NO;
    bzero(words, AHCI_DISK_SECTOR_BYTES);
    bzero(fis, sizeof(fis));
    fis[0] = 0x27U;
    fis[1] = 0x80U;
    result = [_port executeATA:AHCI_ATA_IDENTIFY_DEVICE fis:fis packet:0
                         buffer:words length:AHCI_DISK_SECTOR_BYTES
                          write:NO
                         client:IOVmTaskSelf()
                        timeout:AHCI_DISK_COMMAND_TIMEOUT_SECONDS
                    transferred:&transferred];
    if (result != IO_R_SUCCESS || transferred != AHCI_DISK_SECTOR_BYTES)
        return NO;
    return [self reidentifyFromWords:words];
}

- (BOOL)reidentifyFromWords:(const unsigned short *)words
{
    AHCIDiskIdentify identified;

    if (!AHCIDiskParseIdentify(words, &identified))
        return NO;
    if (_hdUnit >= 0 && !AHCIDiskIdentifyMatches(&_identify, &identified))
        return NO;
    _identify = identified;
    if (_hdUnit >= 0) {
        [self setDiskSize:_identify.capacity];
        [self setDriveName:_identify.model];
        [self portBecameReady];
    }
    return YES;
}

- (void)portBecameReady
{
    if (_queueLock == nil)
        return;
    [_queueLock lock];
    [self setLastReadyState:IO_Ready];
    [_queueLock unlockWith:queue_empty(&_requestQueue) ?
        AHCI_DISK_NO_WORK : AHCI_DISK_WORK_AVAILABLE];
}

- (void)portBecameNotReady
{
    if (_queueLock == nil)
        return;
    [_queueLock lock];
    [self setLastReadyState:IO_NotReady];
    [_queueLock unlockWith:queue_empty(&_requestQueue) ?
        AHCI_DISK_NO_WORK : AHCI_DISK_WORK_AVAILABLE];
}

- (IOReturn)flushCache
{
    AHCIDiskRequest *request;
    IOReturn result;

    request = [self allocRequest:0];
    request->command = AHCI_DISK_FLUSH;
    result = [self enqueueRequest:request];
    [self freeRequest:request];
    return result;
}

IOReturn AHCIDiskTransportFlush(id disk)
{
    return [(AHCIDisk *)disk flushCache];
}

- (AHCIDiskRequest *)allocRequest:(void *)pending
{
    AHCIDiskRequest *request;
    id waitLock;

    for (;;) {
        [_poolLock lock];
        if (!queue_empty(&_requestPool))
            break;
        [_poolLock unlock];
        IOSleep(10);
    }
    request = (AHCIDiskRequest *)queue_first(&_requestPool);
    queue_remove(&_requestPool, request, AHCIDiskRequest *, poolLink);
    waitLock = request->waitLock;
    bzero(request, sizeof(*request));
    request->waitLock = waitLock;
    [request->waitLock initWith:NO];
    request->pending = pending;
    [_poolLock unlock];
    return request;
}

- (void)freeRequest:(AHCIDiskRequest *)request
{
    [_poolLock lock];
    queue_enter(&_requestPool, request, AHCIDiskRequest *, poolLink);
    [_poolLock unlock];
}

- (IOReturn)enqueueRequest:(AHCIDiskRequest *)request
{
    request->status = IO_R_INVALID;
    [_queueLock lock];
    queue_enter(&_requestQueue, request, AHCIDiskRequest *, link);
    [_queueLock unlockWith:AHCI_DISK_WORK_AVAILABLE];
    if (request->pending != 0)
        return IO_R_SUCCESS;
    [request->waitLock lockWhen:YES];
    [request->waitLock unlock];
    return request->status;
}

- (void)completeRequest:(AHCIDiskRequest *)request
{
    if (request->pending != 0) {
        ata_hd_async_complete(request->pending);
        [self completeTransfer:request->pending withStatus:request->status
                  actualLength:request->bytesTransferred];
        [self freeRequest:request];
    } else {
        [request->waitLock lock];
        [request->waitLock unlockWith:YES];
    }
}

- (IOReturn)deviceRwCommon:(AHCIDiskCommand)command
                      block:(unsigned int)block
                     length:(unsigned int)length
                     buffer:(unsigned char *)buffer
                     client:(vm_task_t)client
                    pending:(void *)pending
               actualLength:(unsigned int *)actualLength
{
    AHCIDiskRequest *request;
    unsigned int blocks;
    IOReturn result;

    if (![self isDiskReady:NO]) {
        if (!AHCIDiskClipRequest(_identify.capacity, block, length, &blocks))
            return IO_R_INVALID_ARG;
    } else {
        return IO_R_NO_DISK;
    }
    request = [self allocRequest:pending];
    request->command = command;
    request->block = block;
    request->blocks = blocks;
    request->buffer = buffer;
    request->client = client;
    result = [self enqueueRequest:request];
    if (pending == 0) {
        if (actualLength != 0)
            *actualLength = request->bytesTransferred;
        [self freeRequest:request];
    }
    return result;
}

static void AHCIDiskBuildFIS(unsigned char fis[20], unsigned int block,
                             unsigned int blocks, int extended)
{
    bzero(fis, 20U);
    fis[0] = 0x27U;
    fis[1] = 0x80U;
    fis[4] = (unsigned char)block;
    fis[5] = (unsigned char)(block >> 8);
    fis[6] = (unsigned char)(block >> 16);
    fis[7] = extended ? 0x40U :
             (unsigned char)(0xe0U | ((block >> 24) & 0x0fU));
    fis[12] = (unsigned char)blocks;
    if (extended) {
        fis[8] = (unsigned char)(block >> 24);
        fis[13] = (unsigned char)(blocks >> 8);
    }
}

- (IOReturn)executeReadWrite:(AHCIDiskRequest *)request
{
    unsigned int block;
    unsigned int remaining;
    unsigned char *buffer;
    unsigned char fis[20];
    AHCIDiskSegment segment;
    unsigned int transferred;
    IOReturn result;
    int extended;

    block = request->block;
    remaining = request->blocks;
    buffer = request->buffer;
    request->bytesTransferred = 0;
    while (remaining != 0) {
        if (!AHCIDiskPlanSegment(block, remaining,
                                 request->command == AHCI_DISK_WRITE,
                                 _identify.lba48,
                                 (unsigned int)((unsigned long)buffer &
                                     (vm_page_size - 1U)),
                                 vm_page_size, &segment))
            return IO_R_INVALID_ARG;
        extended = segment.command == AHCI_ATA_READ_DMA_EXT ||
                   segment.command == AHCI_ATA_WRITE_DMA_EXT;
        AHCIDiskBuildFIS(fis, block, segment.blocks, extended);
        result = [_port executeATA:segment.command fis:fis packet:0
                             buffer:buffer length:segment.bytes
                              write:request->command == AHCI_DISK_WRITE
                             client:request->client
                            timeout:AHCI_DISK_COMMAND_TIMEOUT_SECONDS
                        transferred:&transferred];
        request->bytesTransferred += transferred;
        if (result != IO_R_SUCCESS || transferred != segment.bytes)
            return result == IO_R_SUCCESS ? IO_R_IO : result;
        remaining -= segment.blocks;
        block += segment.blocks;
        buffer += segment.bytes;
    }
    return IO_R_SUCCESS;
}

- (void)dispatchRequest:(AHCIDiskRequest *)request
{
    unsigned char fis[20];
    unsigned int transferred;

    if (request->command == AHCI_DISK_READ ||
        request->command == AHCI_DISK_WRITE) {
        if ([self isDiskReady:NO] != IO_R_SUCCESS)
            request->status = IO_R_NO_DISK;
        else
            request->status = [self executeReadWrite:request];
    } else if (request->command == AHCI_DISK_FLUSH) {
        bzero(fis, sizeof(fis));
        fis[0] = 0x27U;
        fis[1] = 0x80U;
        request->status = [_port executeATA:
            (_identify.lba48 ? AHCI_ATA_FLUSH_CACHE_EXT :
                               AHCI_ATA_FLUSH_CACHE)
                                           fis:fis packet:0 buffer:0
                                        length:0 write:NO
                                        client:IOVmTaskSelf()
                                       timeout:AHCI_DISK_FLUSH_TIMEOUT_SECONDS
                                   transferred:&transferred];
    } else if (request->command == AHCI_DISK_THREAD_ABORT) {
        request->status = IO_R_SUCCESS;
        [self completeRequest:request];
        IOExitThread();
    } else {
        request->status = IO_R_INVALID;
    }
    [self completeRequest:request];
}

volatile void AHCIDiskWorker(AHCIDisk *disk)
{
    AHCIDiskRequest *request;

    for (;;) {
        [disk->_queueLock lockWhen:AHCI_DISK_WORK_AVAILABLE];
        request = (AHCIDiskRequest *)queue_first(&disk->_requestQueue);
        queue_remove(&disk->_requestQueue, request, AHCIDiskRequest *, link);
        [disk->_queueLock unlockWith:
            queue_empty(&disk->_requestQueue) ? AHCI_DISK_NO_WORK :
                                                AHCI_DISK_WORK_AVAILABLE];
        [disk dispatchRequest:request];
    }
}

- free
{
    AHCIDiskRequest *request;
    IOReturn result;
    unsigned int index;

    if (_publicationPinned) {
        IOLog("AHCIDisk: retaining uncertain publication hd%d.\n",
              _hdUnit);
        return self;
    }
    if (_deviceRegistered) {
        [self unregisterDevice];
        _deviceRegistered = NO;
    }
    if (_hdUnit >= 0) {
        result = ata_hd_unregister(_hdUnit);
        if (result != IO_R_SUCCESS) {
            IOLog("AHCIDisk: hd%d remains pinned while registry is busy.\n",
                  _hdUnit);
            return self;
        }
        _hdUnit = -1;
    }
    if (_workerStarted) {
        request = [self allocRequest:0];
        request->command = AHCI_DISK_THREAD_ABORT;
        (void)[self enqueueRequest:request];
        [self freeRequest:request];
        _workerStarted = NO;
    }
    if (_queueLock != nil) {
        [_queueLock free];
        _queueLock = nil;
    }
    if (_poolLock != nil) {
        [_poolLock free];
        _poolLock = nil;
    }
    for (index = 0; index < AHCI_DISK_REQUEST_COUNT; ++index) {
        if (_requests[index].waitLock != nil) {
            [_requests[index].waitLock free];
            _requests[index].waitLock = nil;
        }
    }
    _port = nil;
    return [super free];
}

@end
