/*
 * SCSIServer.h
 * Main SCSIServer driver class
 */

#ifndef _SCSISERVER_H_
#define _SCSISERVER_H_

#import <driverkit/IODevice.h>
#import <objc/Protocol.h>
#import <mach/mach.h>

/* ========================================================================
 * SCSIServer Class Definition
 * ======================================================================== */

@interface SCSIServer : IODevice
{
    /* Instance variables for SCSI controller management
     *
     * The decompiled code shows these offsets (relative to object base):
     * offset +0x108: Array of 8 controller name pointers (char *[8])
     * offset +0x128: Controller count (int)
     *
     * Since IODevice base class occupies the first 0x108 bytes,
     * these are the first instance variables in SCSIServer.
     */
    char *_controllerNames[8];   /* Array of controller names (offset +0x108) */
    int _controllerCount;         /* Number of registered controllers (offset +0x128) */
}

/* Class methods */

/* Get device style
 * Returns: 1 (IO_DirectDevice style)
 */
+ (int)deviceStyle;

/* Probe for SCSI server device
 * deviceDescription: Device description to probe
 * Returns: 1 (YES) if probe successful, 0 (NO) otherwise
 *
 * Only the first probe creates a SCSIServer instance.
 * Subsequent probes register additional controllers.
 */
+ (BOOL)probe:(id)deviceDescription;

/* Get required protocols
 * Returns: Array of required protocol pointers terminated with NULL
 */
+ (Protocol **)requiredProtocols;

/* Initialization */

/* Initialize from device description
 * deviceDescription: Device description structure
 * Returns: initialized object or nil on failure
 */
- initFromDeviceDescription:(id)deviceDescription;

/* SCSI Controller Management */

/* Register a SCSI controller with the server
 * controller: SCSI controller object to register
 * Returns: self on success, nil on failure
 *
 * Maximum of 8 controllers can be registered.
 */
- (id)registerSCSIController:(id)controller;

/* Session Management */

/* Handle server connection from client
 * connection: Pointer to connection port (output parameter)
 * taskPort: Task port for the connecting client
 * Returns: 0 on success, -702 on failure
 *
 * The connection port is returned via the connection pointer parameter.
 */
- (int)serverConnect:(mach_port_t *)connection taskPort:(mach_port_t)taskPort;

/* Parameter Access */

/* Get character string parameter values
 * values: Buffer to receive string values (output parameter)
 * parameter: Parameter identifier (string)
 * count: Pointer to count (input/output parameter)
 * Returns: Result code (0 on success)
 */
- (int)getCharValues:(unsigned char *)values
        forParameter:(const char *)parameter
               count:(unsigned int *)count;

@end

#endif /* _SCSISERVER_H_ */
