/*
 * IOFloppyDisk_Request.m
 * Request and operation method implementations for IOFloppyDisk
 */

#import "IOFloppyDisk_Request.h"
#import "IOFloppyDisk_Support.h"
#import "IOFloppyDrive.h"
#import <driverkit/generalFuncs.h>

// Request structure for I/O operations
typedef struct {
    unsigned int operation;     // 0=read, 1=write
    unsigned int offset;
    unsigned int length;
    void *buffer;
    vm_task_t client;
    unsigned int *actualLength;
    IOReturn status;
    BOOL completed;
} FloppyIORequest;

// Subrequest structure for track-based operations
typedef struct {
    unsigned int cylinder;
    unsigned int head;
    unsigned int sector;
    unsigned int count;
    void *buffer;
    IOReturn status;
} FloppySubrequest;

@implementation IOFloppyDisk(Request)

- (IOReturn)executeRequest:(void *)request
{
    FloppyIORequest *req;
    IOReturn status;
    unsigned int offset;
    unsigned int remaining;
    unsigned int transferred;
    unsigned int chunkSize;

    if (request == NULL) {
        IOLog("IOFloppyDisk(Request): NULL request\n");
        return IO_R_INVALID_ARG;
    }

    req = (FloppyIORequest *)request;

    IOLog("IOFloppyDisk(Request): Executing %s request offset:%d length:%d\n",
          req->operation == 0 ? "READ" : "WRITE",
          req->offset, req->length);

    // Validate parameters
    status = [self validateParameters:req->offset length:req->length];
    if (status != IO_R_SUCCESS) {
        IOLog("IOFloppyDisk(Request): Parameter validation failed\n");
        req->status = status;
        req->completed = YES;
        return status;
    }

    // Check media for read/write operations
    if (req->operation == 0) {
        status = [self checkMediaPresent];
    } else {
        status = [self checkWritable];
    }

    if (status != IO_R_SUCCESS) {
        IOLog("IOFloppyDisk(Request): Media check failed\n");
        req->status = status;
        req->completed = YES;
        // Statistics are tracked by the physical disk (IOFloppyDrive)
        return status;
    }

    // Process request in chunks
    offset = req->offset;
    remaining = req->length;
    transferred = 0;

    while (remaining > 0) {
        // Calculate chunk size (don't cross track boundaries)
        status = [self calculateTransferSize:offset
                                      length:remaining
                              maxTransferSize:&chunkSize];
        if (status != IO_R_SUCCESS) {
            IOLog("IOFloppyDisk(Request): Failed to calculate transfer size\n");
            break;
        }

        // Perform the I/O operation
        // Statistics are tracked by the physical disk (IOFloppyDrive)
        if (req->operation == 0) {
            // Read operation
            status = [self performReadRequest:offset
                                       length:chunkSize
                                       buffer:(void *)((char *)req->buffer + transferred)
                                       client:req->client];
        } else {
            // Write operation
            status = [self performWriteRequest:offset
                                        length:chunkSize
                                        buffer:(void *)((char *)req->buffer + transferred)
                                        client:req->client];
        }

        if (status != IO_R_SUCCESS) {
            IOLog("IOFloppyDisk(Request): I/O operation failed at offset %d\n", offset);
            break;
        }

        // Update progress
        offset += chunkSize;
        remaining -= chunkSize;
        transferred += chunkSize;
    }

    // Update request with results
    req->status = status;
    req->completed = YES;

    if (req->actualLength != NULL) {
        *req->actualLength = transferred;
    }

    IOLog("IOFloppyDisk(Request): Request completed, transferred %d bytes, status=0x%x\n",
          transferred, status);

    return status;
}

- (IOReturn)performReadRequest:(unsigned int)offset
                        length:(unsigned int)length
                        buffer:(void *)buffer
                        client:(vm_task_t)client
{
    unsigned int cylinder, head, sector;
    IOReturn status;

    // Convert offset to CHS
    status = [self convertOffset:offset
                      toCylinder:&cylinder
                            head:&head
                          sector:&sector];
    if (status != IO_R_SUCCESS) {
        return status;
    }

    // Delegate to drive
    if (_drive != nil && [_drive respondsToSelector:@selector(readAt:length:buffer:actualLength:client:)]) {
        unsigned int actualLength;
        status = [_drive readAt:offset
                         length:length
                         buffer:buffer
                   actualLength:&actualLength
                         client:client];

        IOLog("IOFloppyDisk(Request): Read C:%d H:%d S:%d count:%d status=0x%x\n",
              cylinder, head, sector, length / _blockSize, status);

        return status;
    } else {
        IOLog("IOFloppyDisk(Request): No drive available for read\n");
        return IO_R_NO_DEVICE;
    }
}

- (IOReturn)performWriteRequest:(unsigned int)offset
                         length:(unsigned int)length
                         buffer:(void *)buffer
                         client:(vm_task_t)client
{
    unsigned int cylinder, head, sector;
    IOReturn status;

    // Convert offset to CHS
    status = [self convertOffset:offset
                      toCylinder:&cylinder
                            head:&head
                          sector:&sector];
    if (status != IO_R_SUCCESS) {
        return status;
    }

    // Delegate to drive
    if (_drive != nil && [_drive respondsToSelector:@selector(writeAt:length:buffer:actualLength:client:)]) {
        unsigned int actualLength;
        status = [_drive writeAt:offset
                          length:length
                          buffer:buffer
                    actualLength:&actualLength
                          client:client];

        IOLog("IOFloppyDisk(Request): Write C:%d H:%d S:%d count:%d status=0x%x\n",
              cylinder, head, sector, length / _blockSize, status);

        return status;
    } else {
        IOLog("IOFloppyDisk(Request): No drive available for write\n");
        return IO_R_NO_DEVICE;
    }
}

- (IOReturn)checkCylinderStatesOfSubrequest:(void *)subrequest
{
    FloppySubrequest *sub;

    if (subrequest == NULL) {
        return IO_R_INVALID_ARG;
    }

    sub = (FloppySubrequest *)subrequest;

    // Check if cylinder is within valid range
    if (sub->cylinder >= _cylinders) {
        IOLog("IOFloppyDisk(Request): Invalid cylinder %d (max %d)\n",
              sub->cylinder, _cylinders - 1);
        return IO_R_INVALID_ARG;
    }

    // Check if head is valid
    if (sub->head >= _heads) {
        IOLog("IOFloppyDisk(Request): Invalid head %d (max %d)\n",
              sub->head, _heads - 1);
        return IO_R_INVALID_ARG;
    }

    // Check if sector is valid (sectors are 1-based)
    if (sub->sector < 1 || sub->sector > _sectorsPerTrack) {
        IOLog("IOFloppyDisk(Request): Invalid sector %d (range 1-%d)\n",
              sub->sector, _sectorsPerTrack);
        return IO_R_INVALID_ARG;
    }

    // Check if sector count is valid
    if (sub->count == 0 || sub->sector + sub->count - 1 > _sectorsPerTrack) {
        IOLog("IOFloppyDisk(Request): Invalid sector count %d (sector %d)\n",
              sub->count, sub->sector);
        return IO_R_INVALID_ARG;
    }

    IOLog("IOFloppyDisk(Request): Subrequest valid - C:%d H:%d S:%d count:%d\n",
          sub->cylinder, sub->head, sub->sector, sub->count);

    return IO_R_SUCCESS;
}

- (IOReturn)unimpsSubRequest:(void *)subrequest
{
    FloppySubrequest *sub;

    if (subrequest == NULL) {
        return IO_R_INVALID_ARG;
    }

    sub = (FloppySubrequest *)subrequest;

    IOLog("IOFloppyDisk(Request): Unimplemented subrequest - C:%d H:%d S:%d count:%d\n",
          sub->cylinder, sub->head, sub->sector, sub->count);

    // Mark as unsupported
    sub->status = IO_R_UNSUPPORTED;

    return IO_R_UNSUPPORTED;
}

- (IOReturn)getOperationThreadLocal:(id *)result
{
    if (result == NULL) {
        return IO_R_INVALID_ARG;
    }

    [_lock lock];
    *result = _operationThread;
    [_lock unlock];

    return IO_R_SUCCESS;
}

- (void *)getThreadFromConfigTable
{
    void *result;

    [_lock lock];
    result = _operationThread;
    [_lock unlock];

    return result;
}

- (IOReturn)closeOperationThreadLocal
{
    IOReturn status;

    IOLog("IOFloppyDisk(Request): Closing operation thread local\n");

    [_lock lock];

    if (_operationThread != nil) {
        [_lock unlock];

        // Stop the operation thread first
        status = [self stopOperationThread];
        if (status != IO_R_SUCCESS) {
            IOLog("IOFloppyDisk(Request): Failed to stop operation thread\n");
            return status;
        }

        // Then destroy it
        status = [self destroyOperationThread];
        if (status != IO_R_SUCCESS) {
            IOLog("IOFloppyDisk(Request): Failed to destroy operation thread\n");
            return status;
        }

        IOLog("IOFloppyDisk(Request): Operation thread closed successfully\n");
        return IO_R_SUCCESS;
    }

    [_lock unlock];

    IOLog("IOFloppyDisk(Request): No operation thread to close\n");
    return IO_R_SUCCESS;
}

- (IOReturn)clearOperationStatsQueue:(void *)queue
{
    typedef struct {
        void *entries;
        unsigned int count;
        unsigned int capacity;
        id lock;
    } StatsQueue;

    StatsQueue *statsQueue;

    if (queue == NULL) {
        return IO_R_INVALID_ARG;
    }

    IOLog("IOFloppyDisk(Request): Clearing operation stats queue\n");

    statsQueue = (StatsQueue *)queue;

    // Lock the queue for thread safety
    if (statsQueue->lock != nil) {
        [statsQueue->lock lock];
    }

    // Free all queue entries
    if (statsQueue->entries != NULL) {
        IOFree(statsQueue->entries, statsQueue->capacity * sizeof(void *));
        statsQueue->entries = NULL;
    }

    // Reset counters
    statsQueue->count = 0;
    statsQueue->capacity = 0;

    if (statsQueue->lock != nil) {
        [statsQueue->lock unlock];
    }

    IOLog("IOFloppyDisk(Request): Stats queue cleared\n");

    return IO_R_SUCCESS;
}

// Request creation and management

- (void *)createReadRequest:(unsigned int)offset
                     length:(unsigned int)length
                     buffer:(void *)buffer
                     client:(vm_task_t)client
              actualLength:(unsigned int *)actualLength
{
    FloppyIORequest *req;

    req = (FloppyIORequest *)IOMalloc(sizeof(FloppyIORequest));
    if (req == NULL) {
        IOLog("IOFloppyDisk(Request): Failed to allocate request\n");
        return NULL;
    }

    req->operation = 0;  // Read
    req->offset = offset;
    req->length = length;
    req->buffer = buffer;
    req->client = client;
    req->actualLength = actualLength;
    req->status = IO_R_SUCCESS;
    req->completed = NO;

    IOLog("IOFloppyDisk(Request): Created read request %p\n", req);

    return req;
}

- (void *)createWriteRequest:(unsigned int)offset
                      length:(unsigned int)length
                      buffer:(void *)buffer
                      client:(vm_task_t)client
               actualLength:(unsigned int *)actualLength
{
    FloppyIORequest *req;

    req = (FloppyIORequest *)IOMalloc(sizeof(FloppyIORequest));
    if (req == NULL) {
        IOLog("IOFloppyDisk(Request): Failed to allocate request\n");
        return NULL;
    }

    req->operation = 1;  // Write
    req->offset = offset;
    req->length = length;
    req->buffer = buffer;
    req->client = client;
    req->actualLength = actualLength;
    req->status = IO_R_SUCCESS;
    req->completed = NO;

    IOLog("IOFloppyDisk(Request): Created write request %p\n", req);

    return req;
}

- (void)destroyRequest:(void *)request
{
    if (request != NULL) {
        IOLog("IOFloppyDisk(Request): Destroying request %p\n", request);
        IOFree(request, sizeof(FloppyIORequest));
    }
}

- (IOReturn)submitRequest:(void *)request
{
    FloppyIORequest *req;

    if (request == NULL) {
        return IO_R_INVALID_ARG;
    }

    req = (FloppyIORequest *)request;

    IOLog("IOFloppyDisk(Request): Submitting request %p\n", request);

    // Store as pending request
    [_lock lock];

    if (_pendingRequest != NULL) {
        [_lock unlock];
        IOLog("IOFloppyDisk(Request): Request already pending\n");
        return IO_R_BUSY;
    }

    _pendingRequest = request;
    [_lock unlock];

    // Execute request immediately (synchronous for now)
    return [self executeRequest:request];
}

- (IOReturn)waitForRequestCompletion:(void *)request
{
    FloppyIORequest *req;
    int timeout;

    if (request == NULL) {
        return IO_R_INVALID_ARG;
    }

    req = (FloppyIORequest *)request;

    IOLog("IOFloppyDisk(Request): Waiting for request %p completion\n", request);

    // Wait for completion (with timeout)
    timeout = 1000; // 1000 * 10ms = 10 seconds
    while (timeout > 0 && !req->completed) {
        IOSleep(10);
        timeout--;
    }

    if (!req->completed) {
        IOLog("IOFloppyDisk(Request): Request timeout\n");
        return IO_R_TIMEOUT;
    }

    IOLog("IOFloppyDisk(Request): Request completed with status 0x%x\n", req->status);

    return req->status;
}

@end
