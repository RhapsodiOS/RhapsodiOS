/*
 * DECchip21041.h
 * Driver for DEC 21041 Ethernet Controller
 */

#import "DECchip2104x.h"

@interface DECchip21041 : DECchip2104x
{
@private
    unsigned int _mediaType;
}

+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;

/* 21041-specific methods */
- (BOOL)initChip;
- (void)setupSIA;
- (BOOL)selectMedia:(unsigned int)mediaType;

@end
