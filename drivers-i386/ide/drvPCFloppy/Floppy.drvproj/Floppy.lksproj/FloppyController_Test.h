/*
 * FloppyController_Test.h
 * Test and diagnostic methods for FloppyController
 */

#import "FloppyController.h"

/*
 * Test category for FloppyController
 * Contains test and diagnostic methods
 */
@interface FloppyController(Test)

// Reset operations
- (IOReturn)fcReset;
- (IOReturn)fcSendByte:(unsigned char)byte;
- (IOReturn)fcGetByte:(unsigned char *)byte;

// Test operations
- (IOReturn)test;
- (IOReturn)thappyTest;
- (IOReturn)densityValues:(unsigned int *)density;

// Version and configuration
- (IOReturn)doControllerVersion:(unsigned char *)version;
- (IOReturn)initFromDeviceDescription:(IODeviceDescription *)desc;

@end
