#import "Intel82595.h"
#import "i82595io.h"

@implementation IntelEEPro10
+ (BOOL)probe:(IODeviceDescription *)description
{
    IOEISADeviceDescription *device = (IOEISADeviceDescription *)description;
    IORange *range;
    id instance;
    if (![device numPortRanges]) {
        IOLog("IntelEEPro10: No I/O port range configured - aborting\n");
        return NO;
    }
    range = [device portRangeList];
    if ((range->start & 15) || range->size < 16) {
        IOLog("IntelEEPro10: Invalid I/O port range configured - aborting\n");
        return NO;
    }
    if (![device numInterrupts]) {
        IOLog("IntelEEPro10: No interrupt configured - aborting\n");
        return NO;
    }
    if (![Intel82595 probeIDRegisterAt:range->start]) {
        IOLog("IntelEEPro10: Adapter not found at address 0x%x - aborting\n", range->start);
        return NO;
    }
    instance = [self alloc];
    if (instance != nil) return [instance initFromDeviceDescription:description] != nil;
    IOLog("IntelEEPro10: Unable to allocate an instance - aborting\n");
    return NO;
}

- (void)intelEEPro10PnPInit
{
    static const unsigned char io_address_enable_str[32] = {
        0x6a,0xb5,0xda,0xed,0xf6,0xfb,0x7d,0xbe,
        0xdf,0x6f,0x37,0x1b,0x0d,0x86,0xc3,0x61,
        0xb0,0x58,0x2c,0x16,0x8b,0x45,0xa2,0xd1,
        0xe8,0x74,0x3a,0x9d,0xce,0xe7,0x73,0x43
    };
    int i;
    outb(0x279, 0);
    outb(0x279, 0);
    for (i = 0; i < 32; i++) outb(0x279, io_address_enable_str[i]);
}

- (BOOL)coldInit
{
    unsigned short word;
    int i;
    for (i = 0; i < 3; i++) {
        if (!i595AddressWord(ioBase, &currentBank, i + 2, &word)) {
            IOLog("%s: unable to read Ethernet address from EEPROM\n", [self name]);
            return NO;
        }
        ((unsigned short *)myAddress.ether_addr_octet)[2 - i] = (word >> 8) | (word << 8);
    }
    return YES;
}

- (BOOL)resetChip
{
    [self intelEEPro10PnPInit];
    COMMAND(0x1e);
    IODelay(200);
    currentBank = 3;
    i595Bank(ioBase, &currentBank, 0);
    return YES;
}

- (BOOL)irqConfig
{
    /* PRO/10's first three encodings differ from the generic ISA map. */
    static const unsigned short irqMap[5] = {9, 3, 5, 10, 11};
    unsigned char i, value;
    for (i = 0; i < 5; i++) if (irq == irqMap[i]) break;
    if (i == 5) {
        IOLog("%s: Invalid IRQ Level (%d) configured.\n", [self name], irq);
        return NO;
    }
    value = READ8(1, 2);
    WRITE8(1, 2, (value & 0xf8) | i);
    return YES;
}
- (unsigned int)onboardMemoryPresent { return 32768; }
- (const char *)description { return "Intel EtherExpress PRO /10"; }
@end
