/*
 * IODeviceMaster.m
 * Device Master Implementation
 */

#import "IODeviceMaster.h"
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <syslog.h>
#import <mach/mach.h>

// Singleton instance
static id _thisTasksId = nil;

@implementation IODeviceMaster

+ new
{
    // Singleton pattern - only create one instance
    if (_thisTasksId == nil) {
        _thisTasksId = [super new];
        if (_thisTasksId != nil) {
            // Get the device master port from the kernel
            mach_port_t masterPort = device_master_self();
            ((IODeviceMaster *)_thisTasksId)->_privateData = (void *)(uintptr_t)masterPort;
        }
    }
    return _thisTasksId;
}

- (mach_port_t)createMachPort:(int)objectNumber
{
    mach_port_t port = MACH_PORT_NULL;
    mach_port_t masterPort = (mach_port_t)(uintptr_t)_privateData;

    // Call IOCreateMachPort with the master port, object number, and port pointer
    IOCreateMachPort(masterPort, objectNumber, &port);

    return port;
}

- free
{
    // Singleton - don't actually free, just return self
    // The singleton instance persists for the lifetime of the daemon
    return self;
}

- (int)getCharValues:(char *)values
        forParameter:(const char *)parameter
        objectNumber:(int)objectNumber
               count:(int *)count
{
    mach_port_t masterPort = (mach_port_t)(uintptr_t)_privateData;

    // Call IOGetCharValues with: masterPort, objectNumber, parameter, *count (in), values, count (out)
    IOGetCharValues(masterPort, objectNumber, parameter, *count, values, count);

    return 0;
}

- (int)getIntValues:(int *)values
       forParameter:(const char *)parameter
       objectNumber:(int)objectNumber
              count:(int *)count
{
    mach_port_t masterPort = (mach_port_t)(uintptr_t)_privateData;

    // Call IOGetIntValues with: masterPort, objectNumber, parameter, *count (in), values, count (out)
    IOGetIntValues(masterPort, objectNumber, parameter, *count, values, count);

    return 0;
}

- (int)lookUpByDeviceName:(const char *)deviceName
             objectNumber:(int *)objectNumber
               deviceKind:(const char **)deviceKind
{
    mach_port_t masterPort = (mach_port_t)(uintptr_t)_privateData;

    // Call IOLookupByDeviceName with: masterPort, deviceName, objectNumber, deviceKind
    IOLookupByDeviceName(masterPort, deviceName, objectNumber, deviceKind);

    return 0;
}

- (int)lookUpByObjectNumber:(int)objectNumber
                 deviceKind:(const char **)deviceKind
                 deviceName:(const char **)deviceName
{
    mach_port_t masterPort = (mach_port_t)(uintptr_t)_privateData;

    // Call IOLookupByObjectNumber with: masterPort, objectNumber, deviceKind, deviceName
    IOLookupByObjectNumber(masterPort, objectNumber, deviceKind, deviceName);

    return 0;
}

- (int)setCharValues:(const char *)values
        forParameter:(const char *)parameter
        objectNumber:(int)objectNumber
               count:(int)count
{
    mach_port_t masterPort = (mach_port_t)(uintptr_t)_privateData;

    // Call IOSetCharValues with: masterPort, objectNumber, parameter, values, count
    IOSetCharValues(masterPort, objectNumber, parameter, values, count);

    return 0;
}

- (int)setIntValues:(const int *)values
       forParameter:(const char *)parameter
       objectNumber:(int)objectNumber
              count:(int)count
{
    mach_port_t masterPort = (mach_port_t)(uintptr_t)_privateData;

    // Call IOSetIntValues with: masterPort, objectNumber, parameter, values, count
    IOSetIntValues(masterPort, objectNumber, parameter, values, count);

    return 0;
}

@end
