/*
 * DECchip2104xKernelServerInstance.h
 * Kernel server instance for DECchip 21040/21041 Network Driver
 */

#import <objc/Object.h>
#import <driverkit/return.h>

@class DECchip2104x;
@class IODeviceDescription;

@interface DECchip2104xKernelServerInstance : Object
{
    DECchip2104x *_driver;
    void *_privateData;
    BOOL _isOpen;
}

/* Initialization */
- init;
- free;

/* Driver association */
- (void)setDriver:(DECchip2104x *)driver;
- (DECchip2104x *)driver;

/* Kernel server methods */
- (IOReturn)_init;
- (IOReturn)_initDeviceDescription:(IODeviceDescription *)deviceDescription;
- (IOReturn)_openChannel:(unsigned int)channel;
- (IOReturn)_closeChannel:(unsigned int)channel;
- (IOReturn)_getStatus:(void *)status;
- (IOReturn)_setParameter:(const char *)param value:(unsigned int)value;
- (IOReturn)_getParameter:(const char *)param value:(unsigned int *)value;

/* Network interface methods */
- (IOReturn)_transmitPacket:(void *)packet length:(unsigned int)length;
- (IOReturn)_receivePacket:(void *)packet length:(unsigned int *)length;
- (IOReturn)_setPromiscuousMode:(BOOL)enable;
- (IOReturn)_addMulticastAddress:(unsigned char *)addr;
- (IOReturn)_removeMulticastAddress:(unsigned char *)addr;

/* Statistics */
- (IOReturn)_getStatistics:(void *)stats;
- (IOReturn)_resetStatistics;

/* Power management */
- (IOReturn)_getPowerState:(unsigned int *)state;
- (IOReturn)_setPowerState:(unsigned int)state;

/* Hardware control */
- (IOReturn)_reset;
- (IOReturn)_enable;
- (IOReturn)_disable;

@end
