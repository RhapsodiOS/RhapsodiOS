/*
 * FloppyController_Device.h
 * Device management methods for FloppyController
 */

#import "FloppyController.h"

/*
 * Device management category for FloppyController
 * Contains device registration and management methods
 */
@interface FloppyController(Device)

// Device registration
- (IOReturn)initFromDeviceDescription:(IODeviceDescription *)deviceDesc;
- (IOReturn)getDmaStart:(void **)start;
- (IOReturn)dmaDestruct:(void *)dmaInfo;

// Device info
- (IOReturn)fcGetByte:(unsigned char *)byte;
- (IOReturn)fcSendByte:(unsigned char)byte;
- (IOReturn)fcWaitInt:(unsigned int)timeout;

// Timeout management
- (IOReturn)timeoutThread:(void *)arg;
- (IOReturn)thappyTimeout:(void *)arg;
- (IOReturn)floppy_timeout:(unsigned int)ms;

// Perpendicular mode
- (IOReturn)doPerpendicular:(unsigned int)gap;
- (IOReturn)flushIntFlags:(unsigned int *)flags;

@end
