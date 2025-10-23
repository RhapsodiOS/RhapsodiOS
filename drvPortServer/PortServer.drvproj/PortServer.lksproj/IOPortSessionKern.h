/*
 * IOPortSessionKern.h
 * Kernel-level parameter access for IOPortSession
 * 
 * Provides methods for getting/setting character and integer parameters
 */

#ifndef _IOPORTSESSIONKERN_H_
#define _IOPORTSESSIONKERN_H_

#import "IOPortSession.h"

/* ========================================================================
 * IOPortSessionKern Category Definition
 * ======================================================================== */

@interface IOPortSession (IOPortSessionKern)

/* Get character parameter values
 * values: Buffer to receive character values (output parameter)
 * parameter: Parameter identifier
 * count: Number of values to retrieve
 * Returns: Result code (0 on success)
 */
- (int)_getCharValues:(unsigned char *)values 
         forParameter:(int)parameter 
                count:(int)count;

/* Get integer parameter values
 * values: Buffer to receive integer values (output parameter)
 * parameter: Parameter identifier
 * count: Number of values to retrieve
 * Returns: Result code (0 on success)
 */
- (int)_getIntValues:(unsigned int *)values 
        forParameter:(int)parameter 
               count:(int)count;

/* Set character parameter values
 * values: Buffer containing character values to set
 * parameter: Parameter identifier
 * count: Number of values to set
 * Returns: Result code (0 on success)
 */
- (int)_setCharValues:(unsigned char *)values 
         forParameter:(int)parameter 
                count:(int)count;

/* Set integer parameter values
 * values: Buffer containing integer values to set
 * parameter: Parameter identifier
 * count: Number of values to set
 * Returns: Result code (0 on success)
 */
- (int)_setIntValues:(unsigned int *)values 
        forParameter:(int)parameter 
               count:(int)count;

/* Close kernel port session
 * sessionId: Session identifier/index
 * Returns: 0 on success
 *
 * Cleans up and closes a kernel port session by freeing the associated
 * port object and clearing the session state.
 */
- (int)iopsKernClose:(int)sessionId;

/* Dequeue data from kernel port session
 * session: IOPortSession object to dequeue from
 * msg: Message structure containing buffer info and transfer parameters
 * Returns: 0 on success, 0x16 (22) on copyout error
 *
 * Dequeues data from the port session into user space buffer.
 * The msg structure contains:
 *   field1_0x4: Result/error code (output)
 *   field2_0x8: User buffer pointer (updated)
 *   field3_0xc: Bytes remaining to transfer (updated)
 *   field4_0x10: Total bytes transferred (output)
 *   field5_0x14: Minimum bytes before return (updated)
 */
- (int)iopsKernDequeue:(id)session msg:(void *)msg;

/* Enqueue data to kernel port session
 * session: IOPortSession object to enqueue to
 * msg: Message structure containing buffer info and transfer parameters
 * Returns: 0 on success, 0x16 (22) on copyin error
 *
 * Enqueues data from user space buffer to the port session.
 * The msg structure contains:
 *   field1_0x4: Result/error code (output)
 *   field2_0x8: User buffer pointer (updated)
 *   field3_0xc: Bytes remaining to transfer (updated)
 *   field4_0x10: Total bytes transferred (output)
 *   field5_0x14: Sleep flag (byte at offset)
 */
- (int)iopsKernEnqueue:(id)session msg:(void *)msg;

/* Free kernel port session resources
 * Returns: 0 always
 *
 * Closes all active sessions and frees the map lock.
 * Resets the session count and clears the kernel ID map.
 */
- (id)iopsKernFree;

/* Initialize kernel port session subsystem
 * deviceDescription: Device description object containing configuration
 *
 * Reads "Maximum Sessions" from config table (max 64).
 * Initializes the map lock and session tracking arrays.
 */
- (void)iopsKernInit:(id)deviceDescription;

/* Handle kernel port session ioctl initialization
 * sessionId: Session identifier/index
 * data: Ioctl data buffer
 * Returns: 0 on success, 0x16 (22) on error
 *
 * Handles ioctl operations:
 *   data[0] == 0: Initialize session for device name at data[8]
 *   data[0] == 1: Get session name and copy to data[8]
 *   Other values: Return error
 */
- (int)iopsKernInitIoctl:(int)sessionId data:(char *)data;

/* Handle kernel port session message ioctl
 * sessionId: Session identifier/index
 * data: Ioctl data buffer with operation code and parameters
 * Returns: 0 on success, 0x16 (22) on error
 *
 * Dispatches ioctl operations (2-15) to appropriate session methods.
 */
- (int)iopsKernMsgIoctl:(int)sessionId data:(char *)data;

/* Get number of sessions
 * Returns: Number of sessions configured
 */
- (int)iopsKernNumSess;

/* Open kernel port session
 * sessionId: Session identifier/index to open
 * Returns: 0 on success, 0x13 (19) if not available, 0xd (13) if already open
 */
- (int)iopsKernOpen:(int)sessionId;

/* Handle server ioctl commands
 * command: Ioctl command code
 * data: Ioctl data buffer
 * Returns: 0 on success, various error codes on failure
 *
 * Handles two commands:
 *   0xc0047000: Lookup port server device
 *   0x40547001: Find free session slot
 */
- (int)iopsServerIoctlCommand:(int)command data:(char *)data;

@end

#endif /* _IOPORTSESSIONKERN_H_ */
