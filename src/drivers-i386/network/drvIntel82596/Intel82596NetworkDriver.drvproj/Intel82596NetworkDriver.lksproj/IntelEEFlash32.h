#ifndef _INTEL_EE_FLASH32_H_
#define _INTEL_EE_FLASH32_H_
#import "Intel82596Private.h"
@interface IntelEEFlash32 : Intel82596
+ (BOOL)probe:(IODeviceDescription *)description;
- initFromDeviceDescription:(IODeviceDescription *)description;
- (void)clearIrqLatch;
- (void)interruptOccurred;
- (void)doAutoConnectorDetect;
- (BOOL)checksum_OK:(unsigned int)data;
- (void)sendChannelAttention;
- (void)sendPortCommand:(unsigned int)command with:(unsigned int)value;
@end
#endif
