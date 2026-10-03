#ifndef _INTEL82596_H_
#define _INTEL82596_H_

#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOEthernet.h>
#import <driverkit/IONetbufQueue.h>
#import <net/etherdefs.h>
#import <net/netbuf.h>
#import "Intel82596Layout.h"

@class Intel82596Buf;

@interface Intel82596 : IOEthernet
{
    I596_BASE_IVARS;
}
- initFromDeviceDescription:(IODeviceDescription *)description;
- free;
- (BOOL)hwInit;
- (BOOL)swInit;
- (BOOL)coldInit;
- (BOOL)config;
- (BOOL)iaSetup;
- (BOOL)mcSetup;
- (void)interruptOccurred;
- (void)timeoutOccurred;
- (BOOL)acknowledgeInterrupts:(unsigned short)status;
- (BOOL)setThrottleTimers;
- (BOOL)processRecInterrupt;
- (BOOL)processXmtInterrupt;
- (void)transmit:(netbuf_t)packet;
- (BOOL)enablePromiscuousMode;
- (void)disablePromiscuousMode;
- (BOOL)enableMulticastMode;
- (void)disableMulticastMode;
- (void)addMulticastAddress:(enet_addr_t *)address;
- (void)removeMulticastAddress:(enet_addr_t *)address;
- (void)sendPacket:(void *)packet length:(unsigned int)length;
- (void)receivePacket:(void *)packet length:(unsigned int *)length timeout:(unsigned int)timeout;
- (IOReturn)getPowerState:(IOPMPowerState *)state;
- (IOReturn)setPowerState:(IOPMPowerState)state;
- (IOReturn)getPowerManagement:(IOPMPowerManagementState *)state;
- (IOReturn)setPowerManagement:(IOPMPowerManagementState)state;
@end

#endif
