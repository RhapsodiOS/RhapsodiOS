#ifndef _INTEL82596_H_
#define _INTEL82596_H_

#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOEthernet.h>
#import <driverkit/IOEthernetPrivate.h>
#import <driverkit/IONetbufQueue.h>
#import <net/etherdefs.h>
#import <net/netbuf.h>
#import "Intel82596Layout.h"

@class Intel82596Buf;

@interface Intel82596 : IOEthernet
{
    I596_BASE_IVARS;
}
- free;
- (char)hwInit;
- (char)swInit;
- (char)coldInit;
- (char)config;
- (char)iaSetup;
- (char)mcSetup;
- (void)interruptOccurred;
- (void)timeoutOccurred;
- (char)acknowledgeInterrupts:(unsigned short)status;
- (char)setThrottleTimers;
- (char)processRecInterrupt;
- (char)processXmtInterrupt;
- (void)transmit:(netbuf_t)packet;
- (char)enablePromiscuousMode;
- (void)disablePromiscuousMode;
- (char)enableMulticastMode;
- (void)disableMulticastMode;
- (void)addMulticastAddress:(enet_addr_t *)address;
- (void)removeMulticastAddress:(enet_addr_t *)address;
- (void)sendPacket:(void *)packet length:(unsigned int)length;
- (void)receivePacket:(void *)packet length:(unsigned int *)length timeout:(unsigned int)timeout;
- (int)getPowerState:(int *)state;
- (int)setPowerState:(int)state;
- (int)getPowerManagement:(int *)state;
- (int)setPowerManagement:(int)state;
@end

#endif
