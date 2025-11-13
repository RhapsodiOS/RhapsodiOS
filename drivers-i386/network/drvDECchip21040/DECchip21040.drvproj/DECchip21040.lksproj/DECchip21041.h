/*
 * DECchip21041.h
 * Driver for DEC 21041 Ethernet Controller
 */

#import "DECchip2104x.h"

@interface DECchip21041 : DECchip2104x
{
@private
    unsigned char _sromAddressBits;    /* SROM address width (6 or 8 bits) */
    unsigned int _sromWordOffset;      /* SROM word offset for MAC address */
}

- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;
- (IOReturn)setInterface:(unsigned int)interfaceType;
- (void)getStationAddress:(enet_addr_t *)addr;
- (IOReturn)selectInterface;

@end
