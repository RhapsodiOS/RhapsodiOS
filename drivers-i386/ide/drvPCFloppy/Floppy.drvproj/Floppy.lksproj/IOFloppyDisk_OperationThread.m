/*
 * IOFloppyDisk_OperationThread.m
 * Operation thread method implementations for IOFloppyDisk
 */

#import "IOFloppyDisk_OperationThread.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/IODevice.h>
#import <mach/mach.h>
#import <mach/cthreads.h>

// Private structure for operation thread state
typedef struct {
    IOFloppyDisk *disk;
    BOOL shouldRun;
    BOOL isRunning;
    id lock;
    void *queue;
    unsigned int readCount;
    unsigned int writeCount;
    unsigned int errorCount;
} OperationThreadState;

@implementation IOFloppyDisk(OperationThread)

- (IOReturn)createOperationThread
{
    OperationThreadState *state;

    [_lock lock];

    if (_operationThread != nil) {
        [_lock unlock];
        IOLog("IOFloppyDisk(OperationThread): Thread already exists\n");
        return IO_R_SUCCESS;
    }

    // Allocate thread state
    state = (OperationThreadState *)IOMalloc(sizeof(OperationThreadState));
    if (state == NULL) {
        [_lock unlock];
        IOLog("IOFloppyDisk(OperationThread): Failed to allocate thread state\n");
        return IO_R_NO_MEMORY;
    }

    // Initialize thread state
    state->disk = self;
    state->shouldRun = NO;
    state->isRunning = NO;
    state->lock = [[NSLock alloc] init];
    state->queue = NULL;
    state->readCount = 0;
    state->writeCount = 0;
    state->errorCount = 0;

    if (state->lock == nil) {
        IOFree(state, sizeof(OperationThreadState));
        [_lock unlock];
        IOLog("IOFloppyDisk(OperationThread): Failed to create thread lock\n");
        return IO_R_NO_MEMORY;
    }

    _operationThread = (id)state;

    [_lock unlock];

    IOLog("IOFloppyDisk(OperationThread): Operation thread created\n");
    return IO_R_SUCCESS;
}

- (IOReturn)destroyOperationThread
{
    OperationThreadState *state;

    [_lock lock];

    if (_operationThread == nil) {
        [_lock unlock];
        IOLog("IOFloppyDisk(OperationThread): No thread to destroy\n");
        return IO_R_SUCCESS;
    }

    state = (OperationThreadState *)_operationThread;

    // Stop thread if running
    if (state->isRunning) {
        [_lock unlock];
        [self stopOperationThread];
        [_lock lock];
    }

    // Clean up thread state
    if (state->lock != nil) {
        [state->lock free];
        state->lock = nil;
    }

    if (state->queue != NULL) {
        IOFree(state->queue, sizeof(void *));
        state->queue = NULL;
    }

    IOFree(state, sizeof(OperationThreadState));
    _operationThread = nil;

    [_lock unlock];

    IOLog("IOFloppyDisk(OperationThread): Operation thread destroyed\n");
    return IO_R_SUCCESS;
}

- (IOReturn)startOperationThread
{
    OperationThreadState *state;
    IOReturn status;

    [_lock lock];

    if (_operationThread == nil) {
        [_lock unlock];
        // Create thread if it doesn't exist
        status = [self createOperationThread];
        if (status != IO_R_SUCCESS) {
            return status;
        }
        [_lock lock];
    }

    state = (OperationThreadState *)_operationThread;

    if (state->isRunning) {
        [_lock unlock];
        IOLog("IOFloppyDisk(OperationThread): Thread already running\n");
        return IO_R_SUCCESS;
    }

    // Mark thread as should run
    [state->lock lock];
    state->shouldRun = YES;
    [state->lock unlock];

    [_lock unlock];

    // Start the thread
    IOLog("IOFloppyDisk(OperationThread): Starting operation thread\n");

    // Detach thread to run operationThreadMain
    [NSThread detachNewThreadSelector:@selector(operationThreadMain:)
                             toTarget:self
                           withObject:nil];

    return IO_R_SUCCESS;
}

- (IOReturn)stopOperationThread
{
    OperationThreadState *state;
    int timeout;

    [_lock lock];

    if (_operationThread == nil) {
        [_lock unlock];
        IOLog("IOFloppyDisk(OperationThread): No thread to stop\n");
        return IO_R_SUCCESS;
    }

    state = (OperationThreadState *)_operationThread;

    if (!state->isRunning) {
        [_lock unlock];
        IOLog("IOFloppyDisk(OperationThread): Thread not running\n");
        return IO_R_SUCCESS;
    }

    // Signal thread to stop
    [state->lock lock];
    state->shouldRun = NO;
    [state->lock unlock];

    [_lock unlock];

    IOLog("IOFloppyDisk(OperationThread): Stopping operation thread\n");

    // Wait for thread to stop (with timeout)
    timeout = 100; // 100 * 10ms = 1 second
    while (timeout > 0) {
        [_lock lock];
        if (!state->isRunning) {
            [_lock unlock];
            IOLog("IOFloppyDisk(OperationThread): Thread stopped\n");
            return IO_R_SUCCESS;
        }
        [_lock unlock];

        IOSleep(10); // Sleep 10ms
        timeout--;
    }

    IOLog("IOFloppyDisk(OperationThread): Warning - thread did not stop within timeout\n");
    return IO_R_TIMEOUT;
}

- (IOReturn)getOperationThreadLocal:(id *)result
{
    OperationThreadState *state;

    if (result == NULL) {
        return IO_R_INVALID_ARG;
    }

    [_lock lock];

    if (_operationThread == nil) {
        [_lock unlock];
        *result = nil;
        return IO_R_SUCCESS;
    }

    state = (OperationThreadState *)_operationThread;
    *result = (id)state;

    [_lock unlock];

    return IO_R_SUCCESS;
}

- (IOReturn)setOperationThreadLocal:(id)thread
{
    [_lock lock];
    _operationThread = thread;
    [_lock unlock];

    IOLog("IOFloppyDisk(OperationThread): Thread local set\n");
    return IO_R_SUCCESS;
}

- (IOReturn)closeOperationThreadLocal
{
    [_lock lock];

    if (_operationThread != nil) {
        IOLog("IOFloppyDisk(OperationThread): Closing thread local\n");
        [self destroyOperationThread];
    }

    [_lock unlock];

    return IO_R_SUCCESS;
}

- (BOOL)isOperationThreadRunning
{
    OperationThreadState *state;
    BOOL result;

    [_lock lock];

    if (_operationThread == nil) {
        [_lock unlock];
        return NO;
    }

    state = (OperationThreadState *)_operationThread;
    [state->lock lock];
    result = state->isRunning;
    [state->lock unlock];

    [_lock unlock];

    return result;
}

- (void *)getThreadFromConfigTable
{
    // Get thread from configuration table
    // For floppy, we just return our operation thread state
    [_lock lock];
    void *result = _operationThread;
    [_lock unlock];

    return result;
}

- (IOReturn)clearOperationStatsQueue:(void *)queue
{
    OperationThreadState *state;

    if (queue == NULL) {
        IOLog("IOFloppyDisk(OperationThread): NULL queue\n");
        return IO_R_INVALID_ARG;
    }

    [_lock lock];

    if (_operationThread == nil) {
        [_lock unlock];
        IOLog("IOFloppyDisk(OperationThread): No thread state\n");
        return IO_R_SUCCESS;
    }

    state = (OperationThreadState *)_operationThread;

    [state->lock lock];

    // Clear the queue (just reset the pointer for now)
    if (state->queue != NULL) {
        IOFree(state->queue, sizeof(void *));
        state->queue = NULL;
    }

    [state->lock unlock];
    [_lock unlock];

    IOLog("IOFloppyDisk(OperationThread): Queue cleared\n");
    return IO_R_SUCCESS;
}

- (IOReturn)clearOperationStats
{
    OperationThreadState *state;

    [_lock lock];

    if (_operationThread == nil) {
        [_lock unlock];
        return IO_R_SUCCESS;
    }

    state = (OperationThreadState *)_operationThread;

    [state->lock lock];

    // Reset statistics
    state->readCount = 0;
    state->writeCount = 0;
    state->errorCount = 0;

    [state->lock unlock];
    [_lock unlock];

    IOLog("IOFloppyDisk(OperationThread): Statistics cleared\n");
    return IO_R_SUCCESS;
}

- (void)operationThreadMain:(id)arg
{
    OperationThreadState *state;
    BOOL shouldContinue;

    IOLog("IOFloppyDisk(OperationThread): Thread main started\n");

    [_lock lock];

    if (_operationThread == nil) {
        [_lock unlock];
        IOLog("IOFloppyDisk(OperationThread): No thread state, exiting\n");
        return;
    }

    state = (OperationThreadState *)_operationThread;

    // Mark thread as running
    [state->lock lock];
    state->isRunning = YES;
    shouldContinue = state->shouldRun;
    [state->lock unlock];

    [_lock unlock];

    // Main operation loop
    while (shouldContinue) {
        // Process pending I/O operations
        if (_pendingRequest != NULL) {
            IOLog("IOFloppyDisk(OperationThread): Processing pending request\n");

            // Process the request (would normally delegate to request handler)
            // For now, just clear it
            [_lock lock];
            if (_pendingRequest != NULL) {
                IOFree(_pendingRequest, sizeof(void *));
                _pendingRequest = NULL;
            }
            [_lock unlock];

            // Increment read count
            [state->lock lock];
            state->readCount++;
            [state->lock unlock];
        }

        // Sleep briefly to avoid busy-waiting
        IOSleep(10); // Sleep 10ms

        // Check if we should continue running
        [state->lock lock];
        shouldContinue = state->shouldRun;
        [state->lock unlock];
    }

    // Mark thread as not running
    [state->lock lock];
    state->isRunning = NO;
    [state->lock unlock];

    IOLog("IOFloppyDisk(OperationThread): Thread main exiting\n");
}

// Statistics accessors

- (unsigned int)operationThreadReadCount
{
    OperationThreadState *state;
    unsigned int count = 0;

    [_lock lock];

    if (_operationThread != nil) {
        state = (OperationThreadState *)_operationThread;
        [state->lock lock];
        count = state->readCount;
        [state->lock unlock];
    }

    [_lock unlock];

    return count;
}

- (unsigned int)operationThreadWriteCount
{
    OperationThreadState *state;
    unsigned int count = 0;

    [_lock lock];

    if (_operationThread != nil) {
        state = (OperationThreadState *)_operationThread;
        [state->lock lock];
        count = state->writeCount;
        [state->lock unlock];
    }

    [_lock unlock];

    return count;
}

- (unsigned int)operationThreadErrorCount
{
    OperationThreadState *state;
    unsigned int count = 0;

    [_lock lock];

    if (_operationThread != nil) {
        state = (OperationThreadState *)_operationThread;
        [state->lock lock];
        count = state->errorCount;
        [state->lock unlock];
    }

    [_lock unlock];

    return count;
}

@end
