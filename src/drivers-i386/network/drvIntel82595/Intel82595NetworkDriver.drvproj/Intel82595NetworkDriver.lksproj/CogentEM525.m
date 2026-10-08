#import "Intel82595.h"
#import "i82595io.h"

@implementation CogentEM525
+ (BOOL)probe:(IODeviceDescription *)description
{
    IOEISADeviceDescription *device = (IOEISADeviceDescription *)description;
    IORange *range;
    id instance;
    if (![device numPortRanges]) {
        IOLog("CogentEM525: No I/O port range configured - aborting\n");
        return NO;
    }
    range = [device portRangeList];
    if ((range->start & 15) || range->size < 16) {
        IOLog("CogentEM525: Invalid I/O port range configured - aborting\n");
        return NO;
    }
    if (![device numInterrupts]) {
        IOLog("CogentEM525: No interrupt configured - aborting\n");
        return NO;
    }
    if (![Intel82595 probeIDRegisterAt:range->start]) {
        IOLog("CogentEM525: Adapter not found at address 0x%x - aborting\n", range->start);
        return NO;
    }
    instance = [self alloc];
    if (instance != nil) return [instance initFromDeviceDescription:description] != nil;
    IOLog("CogentEM525: Unable to allocate an instance - aborting\n");
    return NO;
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
        ((unsigned short *)myAddress.ether_addr_octet)[2 - i] = word;
    }
    if (myAddress.ether_addr_octet[0] == 0 && myAddress.ether_addr_octet[1] == 0 &&
        myAddress.ether_addr_octet[2] == 0x92) return YES;
    IOLog("%s: Found non-Cogent Ethernet address in EEPROM.\n", [self name]);
    return NO;
}
- (const char *)description { return "Cogent eMASTER+ EM525 AT"; }
@end
