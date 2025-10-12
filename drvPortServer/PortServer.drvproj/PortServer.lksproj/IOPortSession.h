/*
 * IOPortSession.h
 * Port Server Driver - Port Session Interface
 */

#import <driverkit/IODevice.h>
#import <driverkit/generalFuncs.h>

@interface IOPortSession : IODevice
{
    id portServerKern;
    void *privateData;
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (void)free;

// Port session management
- (IOReturn)setName:(const char *)name;
- (IOReturn)setPortCount:(int)count;
- (IOReturn)setValues:(NXHashTable *)values;
- (IOReturn)getValue:(int)parameter value:(void *)value;
- (IOReturn)setState:(int)state;
- (IOReturn)watchState:(int)mask;
- (IOReturn)nextEvent:(void *)event data:(void *)data sleep:(BOOL)sleep;
- (IOReturn)executeEvent:(void *)event data:(void *)data;
- (IOReturn)enqueueData:(void *)buffer size:(unsigned int)size transferCount:(unsigned int *)transferCount;
- (IOReturn)dequeueData:(void *)buffer size:(unsigned int)size transferCount:(unsigned int *)transferCount;
- (IOReturn)acquirePort;
- (IOReturn)releasePort;

@end
