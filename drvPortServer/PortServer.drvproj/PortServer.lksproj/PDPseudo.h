/*
 * PDPseudo.h
 * Pseudo serial device for PortServer driver
 */

#ifndef _PDPSEUDO_H_
#define _PDPSEUDO_H_

#import <objc/Object.h>
#import "IOPortSession.h"

/* ========================================================================
 * PDPseudo Class Definition
 * ======================================================================== */

@interface PDPseudo : Object
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
- initFromDeviceDescription:(void *)deviceDescription;

/* Port operations */
- (int)acquire:(int)param;
- (void)release;

/* State management */
- (unsigned int)getState;
- (void)setState:(unsigned int)state mask:(unsigned int)mask;
- (void)watchState:(unsigned int *)state mask:(unsigned int)mask;

/* Event operations */
- (unsigned int)nextEvent;
- (void)executeEvent:(unsigned int)event data:(unsigned int)data;
- (void)requestEvent:(unsigned int)event data:(unsigned int *)data;
- (int)enqueueEvent:(unsigned int)event data:(unsigned int)data sleep:(int)sleep;
- (int)dequeueEvent:(unsigned int *)event data:(unsigned int *)data sleep:(int)sleep;

/* Data transfer operations */
- (int)enqueueData:(void *)buffer
        bufferSize:(unsigned int)bufferSize
     transferCount:(unsigned int *)transferCount
             sleep:(int)sleep;

- (int)dequeueData:(void *)buffer
        bufferSize:(unsigned int)bufferSize
     transferCount:(unsigned int *)transferCount
          minCount:(unsigned int)minCount;

@end

#endif /* _PDPSEUDO_H_ */
