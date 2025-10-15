/*
 * DEC21142KernelServerInstance.m
 * Kernel Server Instance for DEC21142 Network Driver
 */

#import "DEC21142KernelServerInstance.h"
#import "DEC21142.h"
#import <driverkit/generalFuncs.h>
#import <string.h>

@implementation DEC21142KernelServerInstance

/*
 * Initialize with driver
 */
- initWithDriver:(DEC21142 *)driver
{
    [super init];

    _driver = driver;
    _reserved1 = NULL;
    _reserved2 = NULL;
    _reserved3 = NULL;

    return self;
}

/*
 * Free instance
 */
- free
{
    _driver = nil;
    _reserved1 = NULL;
    _reserved2 = NULL;
    _reserved3 = NULL;

    return [super free];
}

/*
 * Initialize instance
 */
- (int)_init
{
    if (!_driver) {
        return -1;
    }

    return 0;
}

/*
 * Initialize device description
 */
- (int)_initDeviceDescription
{
    if (!_driver) {
        return -1;
    }

    return 0;
}

/*
 * Initialize interrupts
 */
- (int)_initInterrupts
{
    if (!_driver) {
        return -1;
    }

    return [_driver enableAllInterrupts] ? 0 : -1;
}

/*
 * Initialize networking
 */
- (int)_initNetworking
{
    if (!_driver) {
        return -1;
    }

    return 0;
}

/*
 * Initialize transmit queues
 */
- (int)_initTransmitQueues
{
    if (!_driver) {
        return -1;
    }

    return 0;
}

/*
 * Initialize receive queues
 */
- (int)_initReceiveQueues
{
    if (!_driver) {
        return -1;
    }

    return 0;
}

/*
 * Open channel
 */
- (int)_openChannel
{
    if (!_driver) {
        return -1;
    }

    return [_driver resetAndEnable:YES] ? 0 : -1;
}

/*
 * Close channel
 */
- (int)_closeChannel
{
    if (!_driver) {
        return -1;
    }

    return [_driver resetAndEnable:NO] ? 0 : -1;
}

/*
 * Enable multicast mode
 */
- (int)_enableMulticastMode
{
    if (!_driver) {
        return -1;
    }

    [_driver setMulticastMode:YES];
    return 0;
}

/*
 * Disable multicast mode
 */
- (int)_disableMulticastMode
{
    if (!_driver) {
        return -1;
    }

    [_driver setMulticastMode:NO];
    return 0;
}

/*
 * Enable promiscuous mode
 */
- (int)_enablePromiscuousMode
{
    if (!_driver) {
        return -1;
    }

    [_driver setPromiscuousMode:YES];
    return 0;
}

/*
 * Disable promiscuous mode
 */
- (int)_disablePromiscuousMode
{
    if (!_driver) {
        return -1;
    }

    [_driver setPromiscuousMode:NO];
    return 0;
}

/*
 * Get setup filter
 */
- (int)_getSetupFilter
{
    if (!_driver) {
        return -1;
    }

    return 0;
}

/*
 * Set multicast address
 */
- (int)_setMulticastAddr
{
    if (!_driver) {
        return -1;
    }

    return 0;
}

/*
 * Set address
 */
- (int)_setAddress:(void *)addr
{
    if (!_driver || !addr) {
        return -1;
    }

    return 0;
}

/*
 * Get station address
 */
- (int)_getStationAddress:(void *)addr
{
    if (!_driver || !addr) {
        return -1;
    }

    return [_driver getHardwareAddress:(enet_addr_t *)addr] ? 0 : -1;
}

/*
 * Select interface
 */
- (int)_selectInterface:(int)interface
{
    if (!_driver) {
        return -1;
    }

    return 0;
}

/*
 * Set owner state
 */
- (int)_setOwnerState
{
    if (!_driver) {
        return -1;
    }

    return 0;
}

/*
 * Set network state
 */
- (int)_setNetworkState
{
    if (!_driver) {
        return -1;
    }

    return 0;
}

/*
 * Get owner state
 */
- (int)_getOwnerState
{
    if (!_driver) {
        return -1;
    }

    return 0;
}

/*
 * Scan transmit queue
 */
- (int)_scanTransmitQueue
{
    if (!_driver) {
        return -1;
    }

    return 0;
}

/*
 * Transmit interrupt occurred
 */
- (int)_transmitInterruptOccurred
{
    if (!_driver) {
        return -1;
    }

    [_driver clearTimeout];
    return 0;
}

/*
 * Receive interrupt occurred
 */
- (int)_receiveInterruptOccurred
{
    if (!_driver) {
        return -1;
    }

    [_driver receivePacket];
    return 0;
}

/*
 * Start transmit
 */
- (int)_startTransmit
{
    if (!_driver) {
        return -1;
    }

    [_driver startTransmit];
    return 0;
}

/*
 * Start receive
 */
- (int)_startReceive
{
    if (!_driver) {
        return -1;
    }

    [_driver startReceive];
    return 0;
}

/*
 * Reset transmit
 */
- (int)_resetTransmit
{
    if (!_driver) {
        return -1;
    }

    [_driver stopTransmit];
    return 0;
}

/*
 * Reset receive
 */
- (int)_resetReceive
{
    if (!_driver) {
        return -1;
    }

    [_driver stopReceive];
    return 0;
}

/*
 * Get driver
 */
- (DEC21142 *)driver
{
    return _driver;
}

/*
 * Set driver
 */
- (void)setDriver:(DEC21142 *)driver
{
    _driver = driver;
}

@end
