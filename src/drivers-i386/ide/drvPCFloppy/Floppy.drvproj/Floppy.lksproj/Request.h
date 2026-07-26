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
- (void)abortSubrequestsOnCylinder:(unsigned)cylinderNumber;

/*
 * Check cylinder state for a subrequest.
 */
- (IOReturn)checkCylinderStateForSubrequest:(id)subrequest;

/*
 * Construct an I/O request.
 */
- (id)constructRequest:(IOReturn *)statusPtr
             blockStart:(unsigned)blockStart
              byteCount:(unsigned)byteCount
                 buffer:(void *)buffer
              bufferMap:(vm_task_t)bufferMap;

/*
 * Execute an I/O request.
 */
- (IOReturn)executeRequest:(id)request;

/*
 * Execute a subrequest.
 */
- (IOReturn)executeSubrequest:(id)subrequest;

/*
 * Free an I/O request.
 */
- (void)freeRequest:(id)request;

/*
 * Impose cylinder state for a subrequest.
 */
- (IOReturn)imposeCylinderStateForSubrequest:(id)subrequest;

/*
 * Pop and process subrequests waiting on a cylinder.
 */
- (void)popSubrequestsOnCylinder:(unsigned)cylinderNumber;

/*
 * Remove imposed cylinder state for a subrequest.
 */
- (IOReturn)unimposeCylinderStateForSubrequest:(id)subrequest;

@end

/* End of Request.h */
