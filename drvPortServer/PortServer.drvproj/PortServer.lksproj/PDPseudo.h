/*
 * PDPseudo.h
 * Port Server Driver - Pseudo Device Interface
 */

#import <driverkit/IODevice.h>

@interface PDPseudo : IODevice
{
    void *privateData;
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (void)free;

// Pseudo device operations
- (IOReturn)acquire;
- (IOReturn)release;
- (IOReturn)setState:(int)state mask:(int)mask;
- (IOReturn)getState;
- (IOReturn)watchState:(int)mask;
- (IOReturn)nextEvent:(void *)event data:(void *)data sleep:(BOOL)sleep;
- (IOReturn)executeEvent:(void *)event data:(void *)data;
- (IOReturn)enqueueData:(void *)buffer size:(unsigned int)size transferCount:(unsigned int *)transferCount;
- (IOReturn)dequeueData:(void *)buffer size:(unsigned int)size transferCount:(unsigned int *)transferCount;
- (IOReturn)requestEvent:(void *)event data:(void *)data;

@end
