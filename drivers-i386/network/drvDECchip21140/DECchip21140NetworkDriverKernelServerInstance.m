/*
 * DECchip21140NetworkDriverKernelServerInstance.m
 * Kernel server instance for DECchip 21140 Network Driver
 */

#import "DECchip21140NetworkDriverKernelServerInstance.h"
#import "DECchip21140NetworkDriver.h"
#import <driverkit/IODeviceDescription.h>
#import <driverkit/generalFuncs.h>

@implementation DECchip21140NetworkDriverKernelServerInstance

- init
{
    [super init];
    _driver = nil;
    _privateData = NULL;
    _isOpen = NO;
    return self;
}

- free
{
    if (_privateData) {
        IOFree(_privateData, sizeof(void *));
        _privateData = NULL;
    }
    return [super free];
}

- (void)setDriver:(DECchip21140NetworkDriver *)driver
{
    _driver = driver;
}

- (DECchip21140NetworkDriver *)driver
{
    return _driver;
}

- (IOReturn)_init
{
    return IO_R_SUCCESS;
}

- (IOReturn)_initDeviceDescription:(IODeviceDescription *)deviceDescription
{
    if (!_driver) {
        return IO_R_INVALID_ARG;
    }
    return IO_R_SUCCESS;
}

- (IOReturn)_openChannel:(unsigned int)channel
{
    if (_isOpen) {
        return IO_R_BUSY;
    }
    _isOpen = YES;
    return IO_R_SUCCESS;
}

- (IOReturn)_closeChannel:(unsigned int)channel
{
    if (!_isOpen) {
        return IO_R_NOT_OPEN;
    }
    _isOpen = NO;
    return IO_R_SUCCESS;
}

- (IOReturn)_getStatus:(void *)status
{
    if (!_driver) {
        return IO_R_INVALID_ARG;
    }
    return IO_R_SUCCESS;
}

- (IOReturn)_setParameter:(const char *)param value:(unsigned int)value
{
    if (!_driver || !param) {
        return IO_R_INVALID_ARG;
    }
    return IO_R_SUCCESS;
}

- (IOReturn)_getParameter:(const char *)param value:(unsigned int *)value
{
    if (!_driver || !param || !value) {
        return IO_R_INVALID_ARG;
    }
    return IO_R_SUCCESS;
}

- (IOReturn)_transmitPacket:(void *)packet length:(unsigned int)length
{
    if (!_driver || !packet || length == 0) {
        return IO_R_INVALID_ARG;
    }

    [_driver transmitPacket:packet length:length];
    return IO_R_SUCCESS;
}

- (IOReturn)_receivePacket:(void *)packet length:(unsigned int *)length
{
    if (!_driver || !packet || !length) {
        return IO_R_INVALID_ARG;
    }

    [_driver receivePacket];
    return IO_R_SUCCESS;
}

- (IOReturn)_setPromiscuousMode:(BOOL)enable
{
    if (!_driver) {
        return IO_R_INVALID_ARG;
    }

    [_driver setPromiscuousMode:enable];
    return IO_R_SUCCESS;
}

- (IOReturn)_addMulticastAddress:(unsigned char *)addr
{
    if (!_driver || !addr) {
        return IO_R_INVALID_ARG;
    }

    [_driver addMulticastAddress:(enet_addr_t *)addr];
    return IO_R_SUCCESS;
}

- (IOReturn)_removeMulticastAddress:(unsigned char *)addr
{
    if (!_driver || !addr) {
        return IO_R_INVALID_ARG;
    }

    [_driver removeMulticastAddress:(enet_addr_t *)addr];
    return IO_R_SUCCESS;
}

- (IOReturn)_getStatistics:(void *)stats
{
    if (!_driver || !stats) {
        return IO_R_INVALID_ARG;
    }

    [_driver getStatistics];
    return IO_R_SUCCESS;
}

- (IOReturn)_resetStatistics
{
    if (!_driver) {
        return IO_R_INVALID_ARG;
    }

    [_driver resetStats];
    return IO_R_SUCCESS;
}

- (IOReturn)_getPowerState:(unsigned int *)state
{
    if (!_driver || !state) {
        return IO_R_INVALID_ARG;
    }

    *state = [_driver getPowerState];
    return IO_R_SUCCESS;
}

- (IOReturn)_setPowerState:(unsigned int)state
{
    if (!_driver) {
        return IO_R_INVALID_ARG;
    }

    return [_driver setPowerState:state];
}

- (IOReturn)_reset
{
    if (!_driver) {
        return IO_R_INVALID_ARG;
    }

    [_driver resetChip];
    return IO_R_SUCCESS;
}

- (IOReturn)_enable
{
    if (!_driver) {
        return IO_R_INVALID_ARG;
    }

    [_driver resetAndEnable:YES];
    return IO_R_SUCCESS;
}

- (IOReturn)_disable
{
    if (!_driver) {
        return IO_R_INVALID_ARG;
    }

    [_driver resetAndEnable:NO];
    return IO_R_SUCCESS;
}

@end
