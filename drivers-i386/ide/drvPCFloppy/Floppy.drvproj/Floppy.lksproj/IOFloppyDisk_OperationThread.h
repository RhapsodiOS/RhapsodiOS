/*
 * IOFloppyDisk_OperationThread.h
 * Operation thread methods for IOFloppyDisk
 */

#import "IOFloppyDisk.h"

/*
 * OperationThread category for IOFloppyDisk
 * Handles threaded I/O operations
 */
@interface IOFloppyDisk(OperationThread)

// Thread creation and management
- (IOReturn)createOperationThread;
- (IOReturn)destroyOperationThread;
- (IOReturn)startOperationThread;
- (IOReturn)stopOperationThread;

// Thread local operations
- (IOReturn)getOperationThreadLocal:(id *)result;
- (IOReturn)setOperationThreadLocal:(id)thread;
- (IOReturn)closeOperationThreadLocal;

// Thread state
- (BOOL)isOperationThreadRunning;
- (void *)getThreadFromConfigTable;

// Clear operations
- (IOReturn)clearOperationStatsQueue:(void *)queue;
- (IOReturn)clearOperationStats;

// Thread entry point
- (void)operationThreadMain:(id)arg;

// Statistics accessors
- (unsigned int)operationThreadReadCount;
- (unsigned int)operationThreadWriteCount;
- (unsigned int)operationThreadErrorCount;

@end
