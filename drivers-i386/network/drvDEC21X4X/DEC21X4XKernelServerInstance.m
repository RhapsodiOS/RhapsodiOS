/*
 * DEC21X4XKernelServerInstance.m
 * Kernel Server Instance for DEC21X4X Network Driver
 */

#import "DEC21X4XKernelServerInstance.h"
#import "DEC21X4X.h"
#import <driverkit/generalFuncs.h>
#import <string.h>

@implementation DEC21X4XKernelServerInstance

/*
 * Initialize with driver
 */
- initWithDriver:(DEC21X4X *)driver
{
    [super init];

    _driver = driver;
    _transmitQueues = NULL;
    _receiveQueues = NULL;
    _queueCount = 0;
    _isOpen = NO;
    _reserved1 = NULL;
    _reserved2 = NULL;

    return self;
}

/*
 * Free instance
 */
- free
{
    if (_transmitQueues) {
        IOFree(_transmitQueues, _queueCount * sizeof(void *));
        _transmitQueues = NULL;
    }

    if (_receiveQueues) {
        IOFree(_receiveQueues, _queueCount * sizeof(void *));
        _receiveQueues = NULL;
    }

    _driver = nil;
    _reserved1 = NULL;
    _reserved2 = NULL;

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
 * Initialize SIA registers (for 21040/21041)
 */
- (int)_initSIARegisters
{
    if (!_driver) {
        return -1;
    }

    /* Initialize SIA (Serial Interface Adapter) registers */
    /* These are used for 10BaseT/10Base2 on 21040/21041 */
    return 0;
}

/*
 * Initialize adapter
 */
- (int)_initAdapter
{
    if (!_driver) {
        return -1;
    }

    return [_driver initChip] ? 0 : -1;
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

    _queueCount = 1;
    _transmitQueues = IOMalloc(_queueCount * sizeof(void *));
    if (!_transmitQueues) {
        return -1;
    }

    bzero(_transmitQueues, _queueCount * sizeof(void *));

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

    _receiveQueues = IOMalloc(_queueCount * sizeof(void *));
    if (!_receiveQueues) {
        return -1;
    }

    bzero(_receiveQueues, _queueCount * sizeof(void *));

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

    if ([_driver resetAndEnable:YES]) {
        _isOpen = YES;
        return 0;
    }

    return -1;
}

/*
 * Close channel
 */
- (int)_closeChannel
{
    if (!_driver) {
        return -1;
    }

    if ([_driver resetAndEnable:NO]) {
        _isOpen = NO;
        return 0;
    }

    return -1;
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
 * Set address filtering
 */
- (int)_setAddressFiltering
{
    if (!_driver) {
        return -1;
    }

    [_driver sendSetupFrame];
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

    [_driver updateMulticastList];
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
 * Get driver name for parameter count media support
 */
- (unsigned int)_getDriverName_forParameter_count_mediaSupport
{
    return 0;
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
 * Get transmit queue size
 */
- (int)_transmitQueueSize
{
    if (!_driver) {
        return -1;
    }

    return [_driver transmitQueueSize];
}

/*
 * Get transmit queue count
 */
- (unsigned int)_transmitQueueCount
{
    if (!_driver) {
        return 0;
    }

    return [_driver transmitQueueSize];
}

/*
 * Get pending transmit count
 */
- (int)_pendingTransmitCount
{
    if (!_driver) {
        return 0;
    }

    return [_driver pendingTransmitCount];
}

/*
 * Allocate network buffer
 */
- (int)_allocateNetbuf
{
    if (!_driver) {
        return -1;
    }

    [_driver allocateNetbuf];
    return 0;
}

/*
 * Alternate enable promiscuous mode
 */
- (int)_enablePromiscuousMode
{
    if (!_driver) {
        return -1;
    }

    [_driver enablePromiscuousMode];
    return 0;
}

/*
 * Timeout occurred
 */
- (int)_timeoutOccurred
{
    if (!_driver) {
        return -1;
    }

    return [_driver timeoutOccurred_timeout];
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
 * Send packet with length
 */
- (int)_sendPacket_length:(void *)packet length:(unsigned int)len
{
    if (!_driver || !packet) {
        return -1;
    }

    [_driver transmitPacket:packet length:len];
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
 * Receive packet with length
 */
- (int)_receivePacket_length:(void *)packet
{
    if (!_driver || !packet) {
        return -1;
    }

    return 0;
}

/*
 * Check connection support and connection type
 */
- (void)_checkConnectionSupport_ConnectionType
{
    if (_driver) {
        [_driver checkConnectionSupport];
    }
}

/*
 * Convert connection to control
 */
- (void)_convertConnectionToControl
{
    if (_driver) {
        [_driver convertConnectionToControl];
    }
}

/*
 * Handle link change interrupt
 */
- (void)_handleLinkChangeInterrupt
{
    if (_driver) {
        [_driver handleLinkChangeInterrupt];
    }
}

/*
 * Handle link fail interrupt
 */
- (void)_handleLinkFailInterrupt
{
    if (_driver) {
        [_driver handleLinkFailInterrupt];
    }
}

/*
 * Handle link pass interrupt
 */
- (void)_handleLinkPassInterrupt
{
    if (_driver) {
        [_driver handleLinkPassInterrupt];
    }
}

/*
 * Select media
 */
- (int)_selectMedia:(int)media
{
    if (!_driver) {
        return -1;
    }

    [_driver selectMedia:media];
    return 0;
}

/*
 * Detect media
 */
- (int)_detectMedia
{
    if (!_driver) {
        return -1;
    }

    return [_driver detectMedia];
}

/*
 * Set auto-sense timer
 */
- (void)_setAutoSenseTimer
{
    if (_driver) {
        [_driver setAutoSenseTimer];
    }
}

/*
 * Start auto-sense timer
 */
- (void)_startAutoSenseTimer
{
    if (_driver) {
        [_driver startAutoSenseTimer];
    }
}

/*
 * Check link
 */
- (void)_checkLink
{
    if (_driver) {
        [_driver checkLink];
    }
}

/*
 * Set PHY connection
 */
- (int)_setPhyConnection:(int)connectionType
{
    if (!_driver) {
        return -1;
    }

    [_driver setPhyConnection:connectionType];
    return 0;
}

/*
 * Get PHY control
 */
- (int)_getPhyControl
{
    if (!_driver) {
        return -1;
    }

    return [_driver getPhyControl];
}

/*
 * Set PHY control
 */
- (void)_setPhyControl:(int)control
{
    if (_driver) {
        [_driver setPhyControl:control];
    }
}

/*
 * Initialize descriptors
 */
- (int)_initDescriptors
{
    if (!_driver) {
        return -1;
    }

    return [_driver initDescriptors] ? 0 : -1;
}

/*
 * Setup RX descriptors
 */
- (int)_setupRxDescriptors
{
    if (!_driver) {
        return -1;
    }

    return [_driver setupDMA] ? 0 : -1;
}

/*
 * Setup TX descriptors
 */
- (int)_setupTxDescriptors
{
    if (!_driver) {
        return -1;
    }

    return 0;
}

/*
 * Get statistics
 */
- (void)_getStatistics
{
    if (_driver) {
        [_driver getStatistics];
    }
}

/*
 * Update statistics
 */
- (void)_updateStats
{
    if (_driver) {
        [_driver updateStats];
    }
}

/*
 * Reset statistics
 */
- (void)_resetStats
{
    if (_driver) {
        [_driver resetStats];
    }
}

/*
 * Get values with count
 */
- (unsigned int)_getValues_count
{
    return 0;
}

/*
 * Do auto for select
 */
- (void)_doAutoForSelect
{
    /* Auto-selection logic */
}

/*
 * Write general register
 */
- (void)_writeGenRegister:(int)reg value:(unsigned int)value
{
    if (_driver) {
        [_driver writeGenRegister:reg value:value];
    }
}

/*
 * Verify checksum, write Hi, get driver name
 */
- (void)_verifyChecksum_writeHi_getDriverName
{
    if (_driver) {
        [_driver verifyChecksum_writeHi_getDriverName];
    }
}

/*
 * Schedule function, send packet, unschedule function
 */
- (void)_scheduleFunc_sendPacket_unscheduleFunc
{
    if (_driver) {
        [_driver scheduleFunc_sendPacket_unscheduleFunc];
    }
}

/*
 * Get driver
 */
- (DEC21X4X *)driver
{
    return _driver;
}

/*
 * Set driver
 */
- (void)setDriver:(DEC21X4X *)driver
{
    _driver = driver;
}

/*
 * Check if open
 */
- (BOOL)isOpen
{
    return _isOpen;
}

/*
 * Set open state
 */
- (void)setOpen:(BOOL)open
{
    _isOpen = open;
}

@end
