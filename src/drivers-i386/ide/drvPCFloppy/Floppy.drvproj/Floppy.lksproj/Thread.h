/*
 * Thread.h - Operation thread support methods for IOFloppyDisk
 *
 * Category methods for background operation thread and cylinder cache management
 */

#import <driverkit/return.h>

// Forward declaration
@class IOFloppyDisk;

/*
 * OperationThreadLocal methods category for IOFloppyDisk.
 */
@interface IOFloppyDisk(OperationThreadLocal)

/*
 * Bring a cylinder online (read into cache).
 */
- (IOReturn)bringCylinderOnline:(unsigned)cylinderNumber
                     isFormatted:(BOOL)isFormatted;

/*
 * Clear all pending operations on the queue.
 */
- (void)clearOperationsOnQueue:(id)queue;

/*
 * Commit dirty cylinder to disk.
 */
- (IOReturn)commitDirtyCylinder:(unsigned)cylinderNumber;

/*
 * Get read mode from configuration table.
 */
- (int)getReadModeFromConfigTable:(id)configTable;

/*
 * Get write mode from configuration table.
 */
- (int)getWriteModeFromConfigTable:(id)configTable;

/*
 * Main operation thread loop.
 */
- (void)operationThread;

@end

/* End of Thread.h */
