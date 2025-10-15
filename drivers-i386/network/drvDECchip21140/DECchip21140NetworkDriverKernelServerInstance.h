/*
 * DECchip21140NetworkDriverKernelServerInstance.h
 * Kernel server instance for DECchip 21140 Network Driver
 */

#import <objc/Object.h>
#import <driverkit/return.h>

@class DECchip21140NetworkDriver;
@class IODeviceDescription;

@interface DECchip21140NetworkDriverKernelServerInstance : Object
{
    DECchip21140NetworkDriver *_driver;
    void *_privateData;
    BOOL _isOpen;
}

/* Initialization */
- init;
- free;

/* Driver association */
- (void)setDriver:(DECchip21140NetworkDriver *)driver;
- (DECchip21140NetworkDriver *)driver;

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
