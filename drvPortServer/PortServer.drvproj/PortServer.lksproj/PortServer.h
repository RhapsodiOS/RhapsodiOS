/*
 * PortServer.h
 * Main PortServer driver class
 */

#ifndef _PORTSERVER_H_
#define _PORTSERVER_H_

#import <objc/Object.h>

/* ========================================================================
 * PortServer Class Definition
 * ======================================================================== */

@interface PortServer : Object
{
    /* Instance variables */
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
- initFromDeviceDescription:(void *)deviceDescription;

/* IOPS (IOPortSession) operations */
- (const char *)iopsName;

/* State management */
- (int)state;

/* Parameter access */
- (int)getIntValues:(unsigned int *)values
       forParameter:(int)parameter
              count:(int)count;

- (int)setIntValues:(unsigned int *)values
       forParameter:(int)parameter
              count:(int)count;

@end

#endif /* _PORTSERVER_H_ */
