/* 3Com EtherLink III PCMCIA probe. */

#import "EtherLink3.h"
#import <driverkit/generalFuncs.h>

@implementation EtherLink3PCMCIA

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    EtherLink3PCMCIA *driver = [[self alloc] init];
    IORange *portRange;
    unsigned short ioBase;
    short status;

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
    [driver setISA:NO];
    [driver setIOBase:ioBase];
    [driver setIRQ:3];
    [driver setDoAuto:YES];

    outw(ioBase + 14, 0x0800);
    outw(ioBase + 6, (inw(ioBase + 6) & 0xc060) | 0x80);
    do {
        status = inw(ioBase + 10);
    } while (status < 0);
    outw(ioBase + 10, 0x83);
    do {
        status = inw(ioBase + 10);
    } while (status < 0);
    outw(ioBase + 2, inw(ioBase + 12));

    return [driver initFromDeviceDescription:deviceDescription] != nil;
}

@end
