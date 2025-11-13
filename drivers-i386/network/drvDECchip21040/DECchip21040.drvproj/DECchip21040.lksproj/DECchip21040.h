/*
 * DECchip21040.h
 * Driver for DEC 21040 Ethernet Controller
 */

#import "DECchip2104x.h"

@interface DECchip21040 : DECchip2104x
{
}

- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;
- (IOReturn)setInterface:(unsigned int)interfaceType;
- (void)getStationAddress:(enet_addr_t *)addr;
- (IOReturn)selectInterface;

@end
