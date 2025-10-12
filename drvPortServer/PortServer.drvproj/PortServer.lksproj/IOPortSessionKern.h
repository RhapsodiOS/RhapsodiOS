/*
 * IOPortSessionKern.h
 * Port Server Driver - Kernel Session Manager
 */

#import <driverkit/IODevice.h>
#import "IOPortSession.h"

@interface IOPortSessionKern : IODevice
{
    id sessions[16];
    int sessionCount;
    NXHashTable *configTable;
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (void)free;

// Session management methods
- (IOReturn)setName:(const char *)name forSession:session;
- (IOReturn)setPortCount:(int)count forSession:session;
- (IOReturn)setValues:(NXHashTable *)values forSession:session;
- (IOReturn)getValue:(int)parameter value:(void *)value forSession:session;
- (IOReturn)setState:(int)state forSession:session;
- (IOReturn)watchState:(int)mask forSession:session;
- (IOReturn)nextEvent:(void *)event data:(void *)data sleep:(BOOL)sleep forSession:session;
- (IOReturn)executeEvent:(void *)event data:(void *)data forSession:session;
- (IOReturn)enqueueData:(void *)buffer size:(unsigned int)size transferCount:(unsigned int *)transferCount forSession:session;
- (IOReturn)dequeueData:(void *)buffer size:(unsigned int)size transferCount:(unsigned int *)transferCount forSession:session;
- (IOReturn)acquirePort:session;
- (IOReturn)releasePort:session;

@end
