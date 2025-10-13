/*
 * PortServer.h
 * Port Server Driver - Main Driver Interface
 */

#import <driverkit/IODevice.h>

@interface PortServer : IODevice
{
    int portCount;
    int maxSessions;
    id portSessions[16];
    void *privateData;
}

+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- (void)free;

// Port server operations
- (IOReturn)initProtocols:(int)protocol;
- (IOReturn)probe;
- (IOReturn)setInValues:(NXHashTable *)values forParameter:(const char *)parameter count:(int)count;
- (IOReturn)setOutValues:(NXHashTable *)values forParameter:(const char *)parameter count:(int)count;
- (IOReturn)portServerInit;
- (IOReturn)state;
- (IOReturn)portVersionMajor:(int *)major minor:(int *)minor;

@end
