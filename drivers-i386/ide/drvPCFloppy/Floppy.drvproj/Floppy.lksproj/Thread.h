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
- (IOReturn)_bringCylinderOnline:(unsigned)cylinderNumber
                     isFormatted:(BOOL)isFormatted;

/*
 * Clear all pending operations on the queue.
 */
- (void)_clearOperationsOnQueue:(id)queue;

/*
 * Commit dirty cylinder to disk.
 */
- (IOReturn)_commitDirtyCylinder:(unsigned)cylinderNumber;

/*
 * Get read mode from configuration table.
 */
- (int)_getReadModeFromConfigTable:(id)configTable;

/*
 * Get write mode from configuration table.
 */
- (int)_getWriteModeFromConfigTable:(id)configTable;

/*
 * Main operation thread loop.
 */
- (void)_operationThread;

@end

/* End of Thread.h */
