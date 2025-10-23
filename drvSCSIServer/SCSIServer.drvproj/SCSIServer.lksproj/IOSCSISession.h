/*
 * IOSCSISession.h
 * SCSI session interface for SCSIServer driver
 *
 * Provides session management for SCSI device communication
 */

#ifndef _IOSCSISESSION_H_
#define _IOSCSISESSION_H_

#import <objc/Object.h>
#import <objc/Protocol.h>
#import <mach/mach.h>

/* ========================================================================
 * IOSCSIController Protocol - Protocol that SCSI controllers must conform to
 * ======================================================================== */

@protocol IOSCSIController
/* SCSI controllers must implement this protocol's methods */
@end

/* Legacy aliases for compatibility */
#define SCSIDevices IOSCSIController
#define IOSCSIDevice IOSCSIController

/* ========================================================================
 * IOSCSISession Class Definition
 * ======================================================================== */

@interface IOSCSISession : Object
{
    /* Instance variables - will hold method cache and device information */
}

/* Class methods */

/* Get list of available SCSI controller names
 * Returns: Array of controller name strings
 */
+ (id)controllerNameList;

/* Initialization methods */

/* Initialize basic SCSI session */
- init;

/* Initialize SCSI session for specific device
 * device: Device name string (const char *)
 * result: Pointer to result code (output parameter)
 * Returns: initialized session or nil on failure
 */
- initForDevice:(const char *)device result:(int *)result;

/* Cleanup */
- free;

/* Device information */

/* Get SCSI device name
 * Returns: Device name string (const char *)
 */
- (const char *)name;

@end


/* ========================================================================
 * IOSCSISession Private Category
 * ======================================================================== */

@interface IOSCSISession (Private)

/* Private: Initialize server with Mach task and send port
 * task: Mach task port
 * sendPort: Pointer to send port (output parameter)
 * Returns: self on success, result of [self free] on failure
 */
- (int)_initServerWithTask:(mach_port_t)task sendPort:(mach_port_t *)sendPort;

/* Private: Reserve a SCSI target and LUN for this session
 * target: SCSI target ID
 * lun: SCSI logical unit number
 * Returns: 0 on success, error code on failure
 */
- (int)_reserveTarget:(unsigned char)target lun:(unsigned char)lun;

@end

/* ========================================================================
 * C Functions for SCSI Session Management
 * ======================================================================== */

/* Reserve a legacy (non-SCSI-3) target/LUN for a session
 * session: IOSCSISession object
 * target: SCSI target ID (8-bit value)
 * lun: SCSI logical unit number (8-bit value)
 * Returns: 0 on success, error code on failure
 *
 * Legacy version using 8-bit target and LUN values.
 * Values are sign-extended to create the high 32 bits for internal use.
 */
int IOSCSISession_reserveTarget(id session, unsigned char target, unsigned char lun);

/* Release all SCSI units reserved by a session
 * session: IOSCSISession object
 * Returns: 0 (always)
 */
int IOSCSISession_releaseAllUnits(id session);

/* Free a SCSI session
 * session: IOSCSISession object
 * Returns: 0 (always)
 */
int IOSCSISession_free(id session);

/* Initialize SCSI session for a device
 * session: IOSCSISession object
 * deviceName: Name of the SCSI device
 * Returns: 0 on success, error code on failure
 */
int IOSCSISession_initForDevice(id session, const char *deviceName);

/* Get DMA alignment requirements for SCSI transfers
 * session: IOSCSISession object
 * alignment: Pointer to receive alignment value (output parameter)
 * Returns: 0 (always)
 */
int IOSCSISession_getDMAAlignment(id session, unsigned int *alignment);

/* Get maximum transfer size for SCSI operations
 * session: IOSCSISession object
 * maxTransfer: Pointer to receive max transfer size (output parameter)
 * Returns: 0 (always)
 */
int IOSCSISession_maxTransfer(id session, unsigned int *maxTransfer);

/* Wire memory in task's address space for DMA
 * address: Virtual address to wire
 * length: Length of memory region in bytes
 */
void IOTaskWireMemory(unsigned int address, int length);

/* Unwire previously wired memory
 * address: Virtual address to unwire
 * length: Length of memory region in bytes
 */
void IOTaskUnwireMemory(unsigned int address, int length);

/* Deallocate a Mach port in the task
 * port: Mach port to deallocate
 */
void IOTaskPortDeallocate(mach_port_t port);

/* Allocate and assign a name to a Mach port
 * name: Port name to assign
 */
void IOTaskPortAllocateName(mach_port_t name);

/* Execute a SCSI-3 request
 * session: IOSCSISession object
 * request: Pointer to SCSI request structure
 * client: Client task port
 * bufferSize: Size of data buffer
 * result: Pointer to receive result code (output parameter)
 * Returns: 0 (always)
 *
 * This is the main entry point for SCSI-3 requests. It automatically
 * determines whether to use simple or scatter-gather execution based
 * on the buffer size and request parameters.
 */
int IOSCSISession_executeSCSI3Request(id session, void *request,
                                     mach_port_t client, int bufferSize,
                                     int *result);

/* Execute a SCSI-3 request with scatter-gather support
 * session: IOSCSISession object
 * request: Pointer to SCSI request structure
 * client: Client task port
 * ioRanges: Pointer to array of I/O ranges for scatter-gather
 * rangeCount: Number of ranges (upper 3 bits contain count when shifted right by 3)
 * result: Pointer to receive result code (output parameter)
 * Returns: 0 (always)
 */
int IOSCSISession_executeSCSI3RequestScatter(id session, void *request,
                                             mach_port_t client, void *ioRanges,
                                             unsigned int rangeCount, int *result);

/* Execute a SCSI-3 request with out-of-line scatter-gather support
 * session: IOSCSISession object
 * request: Pointer to SCSI request structure
 * client: Client task port
 * oolData: Out-of-line data pointer
 * oolDataSize: Size of out-of-line data
 * result: Pointer to receive result code (output parameter)
 * Returns: 0 (always)
 *
 * This function wires the OOL memory before executing the SCSI request,
 * then unwires and deallocates it after completion.
 */
int IOSCSISession_executeSCSI3RequestOOLScatter(id session, void *request,
                                                mach_port_t client, void *oolData,
                                                int oolDataSize, int *result);

/* Convert SCSI status to IOReturn code
 * session: IOSCSISession object
 * scStatus: SCSI status code
 */
void IOSCSISession_returnFromScStatus(id session, unsigned int scStatus);

/* Reset the SCSI bus
 * session: IOSCSISession object
 * result: Pointer to receive result code (output parameter)
 * Returns: 0 (always)
 */
int IOSCSISession_resetSCSIBus(id session, unsigned int *result);

/* Execute a legacy SCSI request (pre-SCSI-3 format)
 * session: IOSCSISession object
 * request: Pointer to legacy SCSI request structure
 * client: Client task port
 * bufferSize: Size of data buffer
 * result: Pointer to receive result code (output parameter)
 * Returns: 0 (always)
 *
 * This is the legacy entry point for pre-SCSI-3 requests. It uses
 * different request structure offsets than the SCSI-3 version.
 * Uses buffer at offset +0x14 instead of +0x24.
 */
int IOSCSISession_executeRequest(id session, void *request,
                                 mach_port_t client, int bufferSize,
                                 int *result);

/* Execute a legacy SCSI request with scatter-gather support
 * session: IOSCSISession object
 * request: Pointer to legacy SCSI request structure
 * client: Client task port
 * ioRanges: Pointer to array of I/O ranges for scatter-gather
 * rangeCount: Number of ranges (upper 3 bits contain count when shifted right by 3)
 * result: Pointer to receive result code (output parameter)
 * Returns: 0 (always)
 *
 * Legacy version using different request structure offsets:
 * - Buffer at offset +0x14 (not +0x24)
 * - Direction at offset +0x10 (not +0x20)
 * - Status at offset +0x20 (not +0x30)
 */
int IOSCSISession_executeRequestScatter(id session, void *request,
                                        mach_port_t client, void *ioRanges,
                                        unsigned int rangeCount, int *result);

/* Execute a legacy SCSI request with out-of-line scatter-gather support
 * session: IOSCSISession object
 * request: Pointer to legacy SCSI request structure
 * client: Client task port
 * oolData: Out-of-line data pointer
 * oolDataSize: Size of out-of-line data
 * result: Pointer to receive result code (output parameter)
 * Returns: 0 (always)
 *
 * Legacy version that wires OOL memory before executing the SCSI request,
 * then unwires and deallocates it after completion. Uses legacy request
 * structure offsets.
 */
int IOSCSISession_executeRequestOOLScatter(id session, void *request,
                                           mach_port_t client, void *oolData,
                                           int oolDataSize, int *result);

/* Get number of SCSI targets supported by the controller
 * session: IOSCSISession object
 * numTargets: Pointer to receive number of targets (output parameter)
 * Returns: 0 (always)
 */
int IOSCSISession_numberOfTargets(id session, unsigned int *numTargets);

/* Release a SCSI-3 target/LUN reservation
 * session: IOSCSISession object
 * target: Pointer to 64-bit SCSI target ID (2 x 32-bit values)
 * lun: Pointer to 64-bit SCSI LUN (2 x 32-bit values)
 * Returns: 0 (always)
 *
 * Releases a previously reserved target/LUN if it exists in the reservation list.
 * Uses 64-bit target and LUN values (high 32 bits, low 32 bits).
 */
int IOSCSISession_releaseSCSI3Target(id session, unsigned int *target, unsigned int *lun);

/* Reserve a SCSI-3 target/LUN for exclusive access
 * session: IOSCSISession object
 * target: Pointer to 64-bit SCSI target ID (2 x 32-bit values)
 * lun: Pointer to 64-bit SCSI LUN (2 x 32-bit values)
 * Returns: 0 on success, error code on failure
 *
 * Attempts to reserve a SCSI-3 target/LUN for this session.
 * If the controller allows the reservation, it's added to the session's
 * reservation list. Uses 64-bit target and LUN values.
 */
int IOSCSISession_reserveSCSI3Target(id session, unsigned int *target, unsigned int *lun);

/* Release a legacy (non-SCSI-3) target/LUN reservation
 * session: IOSCSISession object
 * target: SCSI target ID (8-bit value)
 * lun: SCSI logical unit number (8-bit value)
 * Returns: 0 (always)
 *
 * Legacy version using 8-bit target and LUN values instead of 64-bit.
 * Values are sign-extended to create the high 32 bits.
 */
int IOSCSISession_releaseTarget(id session, unsigned char target, unsigned char lun);

#endif /* _IOSCSISESSION_H_ */
