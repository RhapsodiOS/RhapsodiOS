#import "Intel82595.h"
#import "i82595io.h"

@implementation IntelEEPro10Plus
+ (BOOL)probe:(IODeviceDescription *)description
{
    IOEISADeviceDescription *device = (IOEISADeviceDescription *)description;
    IORange *range;
    id instance;
    if (![device numPortRanges]) {
        IOLog("IntelEEPro10+: No I/O port range configured - aborting\n");
        return NO;
    }
    range = [device portRangeList];
    if ((range->start & 15) || range->size < 16) {
        IOLog("IntelEEPro10+: Invalid I/O port range configured - aborting\n");
        return NO;
    }
    if (![device numInterrupts]) {
        IOLog("IntelEEPro10+: No interrupt configured - aborting\n");
        return NO;
    }
    if (![Intel82595 probeIDRegisterAt:range->start]) {
        IOLog("IntelEEPro10+: Adapter not found at address 0x%x - aborting\n", range->start);
        return NO;
    }
    instance = [self alloc];
    if (instance != nil) return [instance initFromDeviceDescription:description] != nil;
    IOLog("IntelEEPro10+: Unable to allocate an instance - aborting\n");
    return NO;
}

- (BOOL)busConfig { [self irqConfig]; return YES; }

- (BOOL)coldInit
{
    i82595eeprom *eeprom = [[i82595eeprom alloc] initWithBase:ioBase CurrentBank:&currentBank];
    unsigned char *data;
    int i;
    if (eeprom == nil) { IOLog("82595eeprom returned nil\n"); return NO; }
    data = [eeprom getContents];
    for (i = 0; i < 6; i++) myAddress.ether_addr_octet[i] = data[9 - i];
    [eeprom free];
    return YES;
}

- (BOOL)resetChip
{
    COMMAND(0x1e);
    IODelay(200);
    IOSleep(1);
    currentBank = 3;
    i595Bank(ioBase, &currentBank, 0);
    return YES;
}

- (BOOL)irqConfig
{
    static const unsigned short irqMap[8] = {3, 4, 5, 7, 9, 10, 11, 12};
    unsigned char i, value;
    for (i = 0; i < 8; i++) if (irq == irqMap[i]) break;
    if (i == 8) {
        IOLog("%s: Invalid IRQ Level (%d) configured.\n", [self name], irq);
        return NO;
    }
    value = READ8(1, 2);
    WRITE8(1, 2, (value & 0xf8) | i);
    return YES;
}
- (unsigned int)onboardMemoryPresent { return 32768; }
- (const char *)description { return "Intel EtherExpress PRO/10+ ISA"; }
@end
