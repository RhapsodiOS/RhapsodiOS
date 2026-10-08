/* 3Com EtherLink III ISA Plug and Play probe. */

#import "EtherLink3.h"
#import <driverkit/generalFuncs.h>

@implementation EtherLink3PnP

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    EtherLink3PnP *driver = [[self alloc] init];
    IORange *portRange;
    unsigned short ioBase;
    unsigned short vendorID;
    unsigned short productID;

    if (driver == nil)
        return NO;
    if ([deviceDescription numInterrupts] == 0) {
        IOLog("EtherLinkIII: Interrupt level not configured - aborting\n");
        [driver free];
        return NO;
    }
    if ([deviceDescription numPortRanges] == 0) {
        IOLog("EtherLinkIII: I/O ports not configured - aborting\n");
        [driver free];
        return NO;
    }
    portRange = [deviceDescription portRangeList];
    if (portRange->size <= 15) {
        [driver free];
        return NO;
    }

    ioBase = (unsigned short)portRange->start;
    vendorID = inw(ioBase);
    productID = inw(ioBase + 2);
    if (vendorID != 0x6d50 || (productID & 0xf0ff) != 0x9050) {
        IOLog("EtherLinkIII: ISA/PnP adapter not found at address 0x%04x - aborting\n", ioBase);
        [driver free];
        return NO;
    }

    [driver setISA:NO];
    [driver setIOBase:ioBase];
    [driver setIRQ:[deviceDescription interrupt]];
    return [driver initFromDeviceDescription:deviceDescription] != nil;
}

@end
