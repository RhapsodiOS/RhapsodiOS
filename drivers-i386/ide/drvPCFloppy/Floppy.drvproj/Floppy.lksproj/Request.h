/*
 * Request.h - Request management methods for IOFloppyDisk
 *
 * Category methods for I/O request processing and subrequest management
 */

#import <driverkit/return.h>

// Forward declaration
@class IOFloppyDisk;

/*
 * Request methods category for IOFloppyDisk.
 */
@interface IOFloppyDisk(Request)

/*
 * Abort all subrequests on a cylinder.
 */
- (void)_abortSubrequestsOnCylinder:(unsigned)cylinderNumber;

/*
 * Check cylinder state for a subrequest.
 */
- (IOReturn)_checkCylinderStateForSubrequest:(id)subrequest;

/*
 * Construct an I/O request.
 */
- (id)_constructRequest:(IOReturn *)statusPtr
             blockStart:(unsigned)blockStart
              byteCount:(unsigned)byteCount
                 buffer:(void *)buffer
              bufferMap:(vm_task_t)bufferMap;

/*
 * Execute an I/O request.
 */
- (void)_executeRequest:(id)request;

/*
 * Execute a subrequest.
 */
- (IOReturn)_executeSubrequest:(id)subrequest;

/*
 * Free an I/O request.
 */
- (void)_freeRequest:(id)request;

/*
 * Impose cylinder state for a subrequest.
 */
- (IOReturn)_imposeCylinderStateForSubrequest:(id)subrequest;

/*
 * Pop and process subrequests waiting on a cylinder.
 */
- (void)_popSubrequestsOnCylinder:(unsigned)cylinderNumber;

/*
 * Remove imposed cylinder state for a subrequest.
 */
- (void)_unimposeCylinderStateForSubrequest:(id)subrequest;

@end

/* End of Request.h */
