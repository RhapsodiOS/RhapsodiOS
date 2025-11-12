/*
 * DECchip21040.h
 * Driver for DEC 21040 Ethernet Controller
 */

#import "DECchip2104x.h"

@interface DECchip21040 : DECchip2104x
{
}

+ (BOOL)probe:(IOPCIDeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;

/* 21040-specific methods */
- (BOOL)initChip;
- (void)setupSIA;

@end
