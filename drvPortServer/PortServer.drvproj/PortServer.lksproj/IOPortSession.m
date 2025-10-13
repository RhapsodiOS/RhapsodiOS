/*
 * IOPortSession.m
 * Port Server Driver - Port Session Implementation
 */

#import "IOPortSession.h"
#import "IOPortSessionKern.h"
#import <mach/mach.h>
#import <kernserv/prototypes.h>

@implementation IOPortSession

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    return YES;
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    if ([super initFromDeviceDescription:deviceDescription] == nil)
        return nil;

    portServerKern = nil;
    privateData = NULL;

    return self;
}

- (void)free
{
    if (privateData != NULL) {
        IOFree(privateData, sizeof(void *));
        privateData = NULL;
    }
    [super free];
}

- (IOReturn)setName:(const char *)name
{
    if (portServerKern)
        return [portServerKern setName:name forSession:self];
    return IO_R_INVALID_ARG;
}

- (IOReturn)setPortCount:(int)count
{
    if (portServerKern)
        return [portServerKern setPortCount:count forSession:self];
    return IO_R_INVALID_ARG;
}

- (IOReturn)setValues:(NXHashTable *)values
{
    if (portServerKern)
        return [portServerKern setValues:values forSession:self];
    return IO_R_INVALID_ARG;
}

- (IOReturn)getValue:(int)parameter value:(void *)value
{
    if (portServerKern)
        return [portServerKern getValue:parameter value:value forSession:self];
    return IO_R_INVALID_ARG;
}

- (IOReturn)setState:(int)state
{
    if (portServerKern)
        return [portServerKern setState:state forSession:self];
    return IO_R_INVALID_ARG;
}

- (IOReturn)watchState:(int)mask
{
    if (portServerKern)
        return [portServerKern watchState:mask forSession:self];
    return IO_R_INVALID_ARG;
}

- (IOReturn)nextEvent:(void *)event data:(void *)data sleep:(BOOL)sleep
{
    if (portServerKern)
        return [portServerKern nextEvent:event data:data sleep:sleep forSession:self];
    return IO_R_INVALID_ARG;
}

- (IOReturn)executeEvent:(void *)event data:(void *)data
{
    if (portServerKern)
        return [portServerKern executeEvent:event data:data forSession:self];
    return IO_R_INVALID_ARG;
}

- (IOReturn)enqueueData:(void *)buffer size:(unsigned int)size transferCount:(unsigned int *)transferCount
{
    if (portServerKern)
        return [portServerKern enqueueData:buffer size:size transferCount:transferCount forSession:self];
    return IO_R_INVALID_ARG;
}

- (IOReturn)dequeueData:(void *)buffer size:(unsigned int)size transferCount:(unsigned int *)transferCount
{
    if (portServerKern)
        return [portServerKern dequeueData:buffer size:size transferCount:transferCount forSession:self];
    return IO_R_INVALID_ARG;
}

- (IOReturn)acquirePort
{
    if (portServerKern)
        return [portServerKern acquirePort:self];
    return IO_R_INVALID_ARG;
}

- (IOReturn)releasePort
{
    if (portServerKern)
        return [portServerKern releasePort:self];
    return IO_R_INVALID_ARG;
}

@end
