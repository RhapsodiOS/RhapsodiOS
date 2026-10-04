#ifndef _INTEL_PRO10_PCI_H_
#define _INTEL_PRO10_PCI_H_
#import "Intel82596Private.h"
@interface IntelPRO10PCI : Intel82596
{
    int connector;
    unsigned char RJ45Only;
    unsigned char autoDetectedPort;
}
+ (char)probe:(IODeviceDescription *)description;
- (void)_setConnectorType:(int)type;
- (void)doAutoConnectorDetect;
- initFromDeviceDescription:(IODeviceDescription *)description;
- (void)interruptOccurred;
- (void)initPLXchip;
- (void)resetPLXchip;
- (void)sendPortCommand:(int)command with:(unsigned int)value;
- (void)sendChannelAttention;
- (void)_enableAdapterInterrupts;
- (void)_disableAdapterInterrupts;
- (BOOL)resetAndEnable:(BOOL)enable;
@end
#endif
