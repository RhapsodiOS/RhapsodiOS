/*
 * IOPortSession.h
 * Port session interface for PortServer driver
 * 
 * Provides session management for serial port communication
 */

#ifndef _IOPORTSESSION_H_
#define _IOPORTSESSION_H_

#import <objc/Object.h>
#import <objc/Protocol.h>

/* ========================================================================
 * PortDevices Protocol - Protocol that port devices must conform to
 * ======================================================================== */

@protocol PortDevices
/* Port devices must implement the IOPortSession interface methods */
@end

/* Alias for compatibility */
#define IOPortDevice PortDevices

/* ========================================================================
 * IOPortSession Class Definition
 * ======================================================================== */

@interface IOPortSession : Object
{
    /* Session state block (0x34 bytes), allocated by initForDevice:result: */
    void *_priv;
}

/* Class methods */

/* Called once when class is first used - initializes port list and lock */
+ (id)initialize;

/* Initialization methods */

/* Initialize basic port session */
- init;

/* Initialize port session for specific device
 * device: Device name string
 * result: Pointer to result code (output parameter)
 * Returns: initialized session, or [self free]'s result on failure
 */
- initForDevice:(char *)device result:(int *)result;

/* Cleanup */
- free;

/* Port acquisition and release */

/* Acquire port with sleep option
 * sleep: Whether to sleep if port is busy
 * Returns: Result code (0 on success)
 */
- (int)acquire:(BOOL)sleep;

/* Acquire port with audit (extended acquisition)
 * sleep: Whether to sleep if port is busy
 * Returns: Result code (0 on success)
 */
- (int)acquireAudit:(BOOL)sleep;

/* Release port session
 * Returns: Result code (0 on success)
 */
- (int)release;

/* Port information */

/* Get port name
 * Returns: Port name string (const char *)
 */
- (const char *)name;

/* Check if port is locked
 * Returns: YES if locked, NO otherwise
 */
- (BOOL)locked;

/* State management */

/* Get current port state
 * Returns: Current state value
 */
- (unsigned long)getState;

/* Set port state with mask
 * state: New state value
 * mask: Bits to modify
 * Returns: Result code (0 on success)
 */
- (int)setState:(unsigned long)state mask:(unsigned long)mask;

/* Watch for state changes
 * state: Pointer to receive state (output parameter)
 * mask: State bits to watch
 * Returns: Result code (0 on success)
 */
- (int)watchState:(unsigned long *)state mask:(unsigned long)mask;

/* Event operations */

/* Execute immediate event
 * event: Event code
 * data: Event data
 * Returns: Result code (0 on success)
 */
- (int)executeEvent:(unsigned long)event data:(unsigned long)data;

/* Request event data
 * event: Event code
 * data: Pointer to receive data (output parameter)
 * Returns: Result code (0 on success)
 */
- (int)requestEvent:(unsigned long)event data:(unsigned long *)data;

/* Get next pending event
 * Returns: Next event code
 */
- (unsigned long)nextEvent;

/* Enqueue event with data
 * event: Event code
 * data: Event data
 * sleep: Whether to sleep if queue is full
 * Returns: Result code (0 on success)
 */
- (int)enqueueEvent:(unsigned long)event data:(unsigned long)data sleep:(BOOL)sleep;

/* Dequeue event with data
 * event: Pointer to receive event code (output parameter)
 * data: Pointer to receive event data (output parameter)
 * sleep: Whether to sleep if queue is empty
 * Returns: Result code (0 on success)
 */
- (int)dequeueEvent:(unsigned long *)event data:(unsigned long *)data sleep:(BOOL)sleep;

/* Data transfer operations */

/* Enqueue data for transmission
 * buffer: Data buffer
 * bufferSize: Size of data to enqueue
 * transferCount: Pointer to receive actual bytes transferred (output parameter)
 * sleep: Whether to sleep if buffer is full
 * Returns: Result code (0 on success)
 */
- (int)enqueueData:(char *)buffer
        bufferSize:(unsigned int)bufferSize
     transferCount:(unsigned int *)transferCount
             sleep:(BOOL)sleep;

/* Dequeue received data
 * buffer: Buffer to receive data
 * bufferSize: Maximum buffer size
 * transferCount: Pointer to receive actual bytes transferred (output parameter)
 * minCount: Minimum bytes required before returning
 * Returns: Result code (0 on success)
 */
- (int)dequeueData:(char *)buffer
        bufferSize:(unsigned int)bufferSize
     transferCount:(unsigned int *)transferCount
          minCount:(unsigned int)minCount;

@end


/* ========================================================================
 * IOPortSession Private Category
 * ======================================================================== */

@interface IOPortSession (Private)

/* Private: Acquire port with type and sleep option
 * type: Port type
 * sleep: Whether to sleep if port is busy
 * Returns: Result code (0 on success)
 */
- (int)acquirePort:(int)type sleep:(BOOL)sleep;

/* Private: Release acquired port */
- (void)releasePort;

/* Private: Take ownership of the port at the given type
 * type: Port type
 * sleep: Whether to sleep if operation would block
 * Returns: Result code (0 on success)
 */
- (int)getType:(int)type sleep:(BOOL)sleep;

/* Private: Request port type change
 * type: Requested port type
 * sleep: Whether to sleep if operation would block
 * Returns: Result code (0 on success)
 */
- (int)requestType:(int)type sleep:(BOOL)sleep;

@end

#endif /* _IOPORTSESSION_H_ */
