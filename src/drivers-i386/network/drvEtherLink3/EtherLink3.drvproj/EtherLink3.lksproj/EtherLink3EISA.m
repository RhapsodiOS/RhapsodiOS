/* 3Com EtherLink III EISA probe. */

#import "EtherLink3.h"
#import <driverkit/generalFuncs.h>

@implementation EtherLink3EISA

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    EtherLink3EISA *driver = [[self alloc] init];
    int slot;
    unsigned short ioBase;
    unsigned int irq;

    if (driver == nil)
        return NO;

    if ([deviceDescription getEISASlotNumber:&slot] != 0) {
        IOLog("EtherLinkIII: couldn't get slot number\n");
        [driver free];
        return NO;
    }

    ioBase = (unsigned short)(slot << 12);
    outw(ioBase + 14, 0x0800);
    irq = (inw(ioBase + 8) >> 12) & 0x0f;
    if ([deviceDescription setInterruptList:&irq num:1] != nil) {
        IOLog("EtherLink III EISA: failed to add irq");
        [driver free];
        return NO;
    }

    [driver setISA:NO];
    [driver setIOBase:ioBase];
    [driver setIRQ:irq];
    return [driver initFromDeviceDescription:deviceDescription] != nil;
}

@end
