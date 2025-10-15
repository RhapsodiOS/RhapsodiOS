/*
 * IOFloppyDisk_Request.h
 * Request and operation methods for IOFloppyDisk
 */

#import "IOFloppyDisk.h"

/*
 * Request category for IOFloppyDisk
 * Handles I/O request operations
 */
@interface IOFloppyDisk(Request)

// Request operations
- (IOReturn)executeRequest:(void *)request;
- (IOReturn)checkCylinderStatesOfSubrequest:(void *)subrequest;
- (IOReturn)unimpsSubRequest:(void *)subrequest;

// Operation thread methods
- (IOReturn)getOperationThreadLocal:(id *)result;
- (void *)getThreadFromConfigTable;
- (IOReturn)closeOperationThreadLocal;

// Clear operations
- (IOReturn)clearOperationStatsQueue:(void *)queue;

// Request creation and management
- (void *)createReadRequest:(unsigned int)offset
                     length:(unsigned int)length
                     buffer:(void *)buffer
                     client:(vm_task_t)client
              actualLength:(unsigned int *)actualLength;

- (void *)createWriteRequest:(unsigned int)offset
                      length:(unsigned int)length
                      buffer:(void *)buffer
                      client:(vm_task_t)client
               actualLength:(unsigned int *)actualLength;

- (void)destroyRequest:(void *)request;
- (IOReturn)submitRequest:(void *)request;
- (IOReturn)waitForRequestCompletion:(void *)request;

// Internal request handlers
- (IOReturn)performReadRequest:(unsigned int)offset
                        length:(unsigned int)length
                        buffer:(void *)buffer
                        client:(vm_task_t)client;

- (IOReturn)performWriteRequest:(unsigned int)offset
                         length:(unsigned int)length
                         buffer:(void *)buffer
                         client:(vm_task_t)client;

@end
