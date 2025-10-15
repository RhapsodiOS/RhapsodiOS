/*
 * DECchip2104xKernelServerInstance.m
 * Kernel server instance implementation for DECchip 21040/21041 Network Driver
 */

#import "DECchip2104xKernelServerInstance.h"
#import "DECchip2104x.h"
#import <driverkit/IODeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <string.h>

@implementation DECchip2104xKernelServerInstance

/*
 * Initialize kernel server instance
 */
- init
{
    [super init];

    _driver = nil;
    _privateData = NULL;
    _isOpen = NO;

    return self;
}

/*
 * Free resources
 */
- free
{
    if (_privateData) {
        IOFree(_privateData, 1024); /* Adjust size as needed */
        _privateData = NULL;
    }

    _driver = nil;

    return [super free];
}

/*
 * Set associated driver
 */
- (void)setDriver:(DECchip2104x *)driver
{
    _driver = driver;
}

/*
 * Get associated driver
 */
- (DECchip2104x *)driver
{
    return _driver;
}

/*
 * Initialize
 */
- (IOReturn)_init
{
    if (!_driver) {
        return IO_R_NO_DEVICE;
    }

    /* Allocate private data if needed */
    if (!_privateData) {
        _privateData = IOMalloc(1024);
        if (!_privateData) {
            return IO_R_NO_MEMORY;
        }
        bzero(_privateData, 1024);
    }

    return IO_R_SUCCESS;
}

/*
 * Initialize from device description
 */
- (IOReturn)_initDeviceDescription:(IODeviceDescription *)deviceDescription
{
    if (!_driver) {
        return IO_R_NO_DEVICE;
    }

    /* Driver is already initialized in its init method */
    return IO_R_SUCCESS;
}

/*
 * Open channel
 */
- (IOReturn)_openChannel:(unsigned int)channel
{
    if (!_driver) {
        return IO_R_NO_DEVICE;
    }

    if (_isOpen) {
        return IO_R_BUSY;
    }

    /* Enable the hardware */
    if (![_driver resetAndEnable:YES]) {
        return IO_R_IO;
    }

    _isOpen = YES;

    return IO_R_SUCCESS;
}

/*
 * Close channel
 */
- (IOReturn)_closeChannel:(unsigned int)channel
{
    if (!_driver) {
        return IO_R_NO_DEVICE;
    }

    if (!_isOpen) {
        return IO_R_SUCCESS;
    }

    /* Disable the hardware */
    [_driver resetAndEnable:NO];

    _isOpen = NO;

    return IO_R_SUCCESS;
}

/*
 * Get status
 */
- (IOReturn)_getStatus:(void *)status
{
    if (!_driver || !status) {
        return IO_R_INVALID_ARG;
    }

    /* Fill in status information */
    /* This would typically include link state, speed, duplex mode, etc. */

    return IO_R_SUCCESS;
}

/*
 * Set parameter
 */
- (IOReturn)_setParameter:(const char *)param value:(unsigned int)value
{
    if (!_driver || !param) {
        return IO_R_INVALID_ARG;
    }

    /* Handle various parameters */
    if (strcmp(param, "promiscuous") == 0) {
        [_driver setPromiscuousMode:(value ? YES : NO)];
        return IO_R_SUCCESS;
    }

    if (strcmp(param, "fullDuplex") == 0) {
        /* Full duplex mode setting */
        return IO_R_SUCCESS;
    }

    return IO_R_INVALID_ARG;
}

/*
 * Get parameter
 */
- (IOReturn)_getParameter:(const char *)param value:(unsigned int *)value
{
    if (!_driver || !param || !value) {
        return IO_R_INVALID_ARG;
    }

    /* Handle various parameters */
    if (strcmp(param, "linkState") == 0) {
        *value = _driver->_linkUp ? 1 : 0;
        return IO_R_SUCCESS;
    }

    if (strcmp(param, "fullDuplex") == 0) {
        *value = _driver->_fullDuplex ? 1 : 0;
        return IO_R_SUCCESS;
    }

    if (strcmp(param, "mediaType") == 0) {
        *value = _driver->_mediaType;
        return IO_R_SUCCESS;
    }

    return IO_R_INVALID_ARG;
}

/*
 * Transmit packet
 */
- (IOReturn)_transmitPacket:(void *)packet length:(unsigned int)length
{
    if (!_driver || !packet || length == 0) {
        return IO_R_INVALID_ARG;
    }

    if (!_isOpen) {
        return IO_R_NOT_OPEN;
    }

    /* Send packet via driver */
    [_driver transmitPacket:packet length:length];

    return IO_R_SUCCESS;
}

/*
 * Receive packet
 */
- (IOReturn)_receivePacket:(void *)packet length:(unsigned int *)length
{
    if (!_driver || !packet || !length) {
        return IO_R_INVALID_ARG;
    }

    if (!_isOpen) {
        return IO_R_NOT_OPEN;
    }

    /* Receive handled via interrupts */
    return IO_R_SUCCESS;
}

/*
 * Set promiscuous mode
 */
- (IOReturn)_setPromiscuousMode:(BOOL)enable
{
    if (!_driver) {
        return IO_R_NO_DEVICE;
    }

    [_driver setPromiscuousMode:enable];

    return IO_R_SUCCESS;
}

/*
 * Add multicast address
 */
- (IOReturn)_addMulticastAddress:(unsigned char *)addr
{
    enet_addr_t etherAddr;

    if (!_driver || !addr) {
        return IO_R_INVALID_ARG;
    }

    bcopy(addr, etherAddr.ea_byte, 6);
    [_driver addMulticastAddress:&etherAddr];

    return IO_R_SUCCESS;
}

/*
 * Remove multicast address
 */
- (IOReturn)_removeMulticastAddress:(unsigned char *)addr
{
    enet_addr_t etherAddr;

    if (!_driver || !addr) {
        return IO_R_INVALID_ARG;
    }

    bcopy(addr, etherAddr.ea_byte, 6);
    [_driver removeMulticastAddress:&etherAddr];

    return IO_R_SUCCESS;
}

/*
 * Get statistics
 */
- (IOReturn)_getStatistics:(void *)stats
{
    if (!_driver || !stats) {
        return IO_R_INVALID_ARG;
    }

    /* Update statistics first */
    [_driver updateStats];

    /* Copy statistics to output buffer */
    /* This would copy from _driver's stats ivars to stats structure */

    return IO_R_SUCCESS;
}

/*
 * Reset statistics
 */
- (IOReturn)_resetStatistics
{
    if (!_driver) {
        return IO_R_NO_DEVICE;
    }

    [_driver resetStats];

    return IO_R_SUCCESS;
}

/*
 * Get power state
 */
- (IOReturn)_getPowerState:(unsigned int *)state
{
    if (!_driver || !state) {
        return IO_R_INVALID_ARG;
    }

    return [_driver getPowerState];
}

/*
 * Set power state
 */
- (IOReturn)_setPowerState:(unsigned int)state
{
    if (!_driver) {
        return IO_R_NO_DEVICE;
    }

    return [_driver setPowerState:state];
}

/*
 * Reset hardware
 */
- (IOReturn)_reset
{
    if (!_driver) {
        return IO_R_NO_DEVICE;
    }

    [_driver resetChip];

    return IO_R_SUCCESS;
}

/*
 * Enable hardware
 */
- (IOReturn)_enable
{
    if (!_driver) {
        return IO_R_NO_DEVICE;
    }

    if (![_driver resetAndEnable:YES]) {
        return IO_R_IO;
    }

    return IO_R_SUCCESS;
}

/*
 * Disable hardware
 */
- (IOReturn)_disable
{
    if (!_driver) {
        return IO_R_NO_DEVICE;
    }

    [_driver resetAndEnable:NO];

    return IO_R_SUCCESS;
}

@end
