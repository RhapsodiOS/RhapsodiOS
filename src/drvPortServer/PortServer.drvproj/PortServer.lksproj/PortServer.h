/*
 * PortServer.h
 * Main PortServer driver class
 */

#ifndef _PORTSERVER_H_
#define _PORTSERVER_H_

#import <driverkit/IODevice.h>

#import "ttyiops.h"

/* ========================================================================
 * PortServer Class Definition
 * ======================================================================== */

@interface PortServer : IODevice
{
    /* The reference declares exactly one ivar, at offset 264, which is what
     * takes instance_size from IODevice's 264 to 616. */
    ttyiops_state state;
}

/* Class methods */

/* Return device style - returns 1 */
+ (int)deviceStyle;

/* Probe for port server device
 * deviceDescription: Device description to probe
 * Returns: 1 if probe successful, 0 otherwise
 */
+ (char)probe:(id)deviceDescription;

/* Get required protocols
 * Returns: Array of required protocol pointers
 */
+ (id *)requiredProtocols;

/* Get or allocate server major number
 * deviceDescription: Device description
 * Returns: Major device number, -1 on failure
 */
+ (int)serverMajor:(id)deviceDescription;

/* Initialization */
- initFromDeviceDescription:(id)deviceDescription;

/* IOPS (IOPortSession) operations */
- (const char *)iopsName;

/* State management */
- (ttyiops_state *)state;

/* Parameter access */
- (int)getIntValues:(unsigned int *)values
       forParameter:(IOParameterName)parameterName
              count:(unsigned int *)count;

- (int)setIntValues:(unsigned int *)values
       forParameter:(IOParameterName)parameterName
              count:(unsigned int)count;

@end

#endif /* _PORTSERVER_H_ */
