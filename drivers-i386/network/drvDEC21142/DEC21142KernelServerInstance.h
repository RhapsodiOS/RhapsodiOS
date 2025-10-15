/*
 * DEC21142KernelServerInstance.h
 * Kernel Server Instance for DEC21142 Network Driver
 */

#import <objc/Object.h>
#import <driverkit/return.h>

@class DEC21142;

@interface DEC21142KernelServerInstance : Object
{
    DEC21142 *_driver;
    void *_reserved1;
    void *_reserved2;
    void *_reserved3;
}

/* Initialization */
- initWithDriver:(DEC21142 *)driver;
- free;

/* Server instance methods from binary exports */
- (int)_init;
- (int)_initDeviceDescription;
- (int)_initInterrupts;
- (int)_initNetworking;
- (int)_initTransmitQueues;
- (int)_initReceiveQueues;
- (int)_openChannel;
- (int)_closeChannel;
- (int)_enableMulticastMode;
- (int)_disableMulticastMode;
- (int)_enablePromiscuousMode;
- (int)_disablePromiscuousMode;
- (int)_getSetupFilter;
- (int)_setMulticastAddr;
- (int)_setAddress:(void *)addr;
- (int)_getStationAddress:(void *)addr;
- (int)_selectInterface:(int)interface;
- (int)_setOwnerState;
- (int)_setNetworkState;
- (int)_getOwnerState;
- (int)_scanTransmitQueue;
- (int)_transmitInterruptOccurred;
- (int)_receiveInterruptOccurred;
- (int)_startTransmit;
- (int)_startReceive;
- (int)_resetTransmit;
- (int)_resetReceive;

/* Management methods */
- (DEC21142 *)driver;
- (void)setDriver:(DEC21142 *)driver;

@end
