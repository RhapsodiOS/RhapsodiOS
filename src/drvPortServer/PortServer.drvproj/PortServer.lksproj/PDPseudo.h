/*
 * PDPseudo.h
 * Pseudo serial device for PortServer driver
 */

#ifndef _PDPSEUDO_H_
#define _PDPSEUDO_H_

#import <driverkit/IODevice.h>
#import "IOPortSession.h"

/* ========================================================================
 * PDPseudo Class Definition
 * ======================================================================== */

@interface PDPseudo : IODevice <PortDevices>
{
    /* Instance variables */
}

/* Class methods */

/* Return device style - returns 2 */
+ (int)deviceStyle;

/* Probe for pseudo device
 * deviceDescription: Device description to probe
 * Returns: 1 if probe successful, 0 otherwise
 */
+ (char)probe:(id)deviceDescription;

/* Initialization */
- initFromDeviceDescription:(id)deviceDescription;

/* Port operations */
- (int)acquire:(BOOL)sleep;
- (int)release;

/* State management */
- (unsigned long)getState;
- (int)setState:(unsigned long)state mask:(unsigned long)mask;
- (int)watchState:(unsigned long *)state mask:(unsigned long)mask;

/* Event operations */
- (unsigned long)nextEvent;
- (int)executeEvent:(unsigned long)event data:(unsigned long)data;
- (int)requestEvent:(unsigned long)event data:(unsigned long *)data;
- (int)enqueueEvent:(unsigned long)event data:(unsigned long)data sleep:(BOOL)sleep;
- (int)dequeueEvent:(unsigned long *)event data:(unsigned long *)data sleep:(BOOL)sleep;

/* Data transfer operations */
- (int)enqueueData:(char *)buffer
        bufferSize:(unsigned int)bufferSize
     transferCount:(unsigned int *)transferCount
             sleep:(BOOL)sleep;

- (int)dequeueData:(char *)buffer
        bufferSize:(unsigned int)bufferSize
     transferCount:(unsigned int *)transferCount
          minCount:(unsigned int)minCount;

@end

#endif /* _PDPSEUDO_H_ */
