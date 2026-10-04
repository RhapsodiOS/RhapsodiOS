#ifndef _COGENT_E_MASTER_H_
#define _COGENT_E_MASTER_H_
#import "Intel82596Private.h"
@interface CogentEMaster : Intel82596
+ (char)probe:(IODeviceDescription *)description;
- initFromDeviceDescription:(IODeviceDescription *)description;
- (void)clearIrqLatch;
- (void)sendChannelAttention;
- (void)sendPortCommand:(int)command with:(unsigned int)value;
@end
#endif
