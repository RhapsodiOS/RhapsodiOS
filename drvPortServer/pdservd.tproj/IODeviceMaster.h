/*
 * IODeviceMaster.h
 * Device Master Interface
 */

#ifndef _IODEVICEMASTER_H_
#define _IODEVICEMASTER_H_

#import <objc/Object.h>
#import <mach/mach.h>

@interface IODeviceMaster : Object
{
    @private
    void *_privateData;
}

/*
 * Factory method to create a new IODeviceMaster instance
 */
+ new;

/*
 * Create a Mach port for communication with a device
 * objectNumber: The device object number
 * Returns: The created Mach port
 */
- (mach_port_t)createMachPort:(int)objectNumber;

/*
 * Free the IODeviceMaster instance
 */
- free;

/*
 * Get character values for a parameter
 * values: Buffer to receive character values
 * parameter: Parameter name
 * objectNumber: Device object number
 * count: Number of values to retrieve
 * Returns: Error code (0 = success)
 */
- (int)getCharValues:(char *)values
        forParameter:(const char *)parameter
        objectNumber:(int)objectNumber
               count:(int *)count;

/*
 * Get integer values for a parameter
 * values: Buffer to receive integer values
 * parameter: Parameter name
 * objectNumber: Device object number
 * count: Number of values to retrieve
 * Returns: Error code (0 = success)
 */
- (int)getIntValues:(int *)values
       forParameter:(const char *)parameter
       objectNumber:(int)objectNumber
              count:(int *)count;

/*
 * Look up a device by its name
 * deviceName: Name of the device to find
 * objectNumber: Pointer to receive the object number
 * deviceKind: Pointer to receive the device kind
 * Returns: Error code (0 = success)
 */
- (int)lookUpByDeviceName:(const char *)deviceName
             objectNumber:(int *)objectNumber
               deviceKind:(const char **)deviceKind;

/*
 * Look up a device by its object number
 * objectNumber: The object number to look up
 * deviceKind: Pointer to receive the device kind
 * deviceName: Pointer to receive the device name
 * Returns: Error code (0 = success)
 */
- (int)lookUpByObjectNumber:(int)objectNumber
                 deviceKind:(const char **)deviceKind
                 deviceName:(const char **)deviceName;

/*
 * Set character values for a parameter
 * values: Character values to set
 * parameter: Parameter name
 * objectNumber: Device object number
 * count: Number of values to set
 * Returns: Error code (0 = success)
 */
- (int)setCharValues:(const char *)values
        forParameter:(const char *)parameter
        objectNumber:(int)objectNumber
               count:(int)count;

/*
 * Set integer values for a parameter
 * values: Integer values to set
 * parameter: Parameter name
 * objectNumber: Device object number
 * count: Number of values to set
 * Returns: Error code (0 = success)
 */
- (int)setIntValues:(const int *)values
       forParameter:(const char *)parameter
       objectNumber:(int)objectNumber
              count:(int)count;

@end

#endif /* _IODEVICEMASTER_H_ */
