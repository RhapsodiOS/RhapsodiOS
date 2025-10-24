/*
 * IODeviceMaster.h - Device Master interface wrapper
 *
 * This provides an Objective-C wrapper around the IODeviceMaster
 * Mach port interface for communicating with kernel drivers.
 */

#import <objc/Object.h>
#import <mach/mach.h>

@interface IODeviceMaster : Object
{
    port_t deviceMasterPort;
}

// Class methods
+ new;

// Instance methods
- (kern_return_t)createMachPort:(port_t *)port objectNumber:(int)objNum;
- free;

// Parameter access methods
- (kern_return_t)getCharValues:(char *)values
                  forParameter:(const char *)paramName
                  objectNumber:(int)objNum
                         count:(unsigned int *)count;

- (kern_return_t)getIntValues:(unsigned int *)values
                 forParameter:(const char *)paramName
                 objectNumber:(int)objNum
                        count:(unsigned int *)count;

- (kern_return_t)setCharValues:(const char *)values
                  forParameter:(const char *)paramName
                  objectNumber:(int)objNum
                         count:(unsigned int)count;

- (kern_return_t)setIntValues:(const unsigned int *)values
                 forParameter:(const char *)paramName
                 objectNumber:(int)objNum
                        count:(unsigned int)count;

// Device lookup methods
- (kern_return_t)lookUpByDeviceName:(const char *)deviceName
                       objectNumber:(int *)objNum
                         deviceKind:(const char **)kind;

- (kern_return_t)lookUpByObjectNumber:(int)objNum
                           deviceKind:(const char **)kind
                           deviceName:(char **)name;

@end
