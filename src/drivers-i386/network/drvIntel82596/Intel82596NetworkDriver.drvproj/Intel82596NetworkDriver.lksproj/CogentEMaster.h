#ifndef _COGENT_E_MASTER_H_
#define _COGENT_E_MASTER_H_
#import "Intel82596Private.h"
@interface CogentEMaster : Intel82596
+ (BOOL)probe:(IODeviceDescription *)description;
- initFromDeviceDescription:(IODeviceDescription *)description;
- (void)clearIrqLatch;
- (void)sendChannelAttention;
- (void)sendPortCommand:(unsigned int)command with:(unsigned int)value;
@end
#endif
