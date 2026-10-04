#import "Intel82595.h"
#import "i82595io.h"
#import <driverkit/i386/IOPCMCIADeviceDescription.h>
#import <driverkit/i386/IOPCMCIATuple.h>

@implementation CogentEM595
+ (BOOL)probe:(IODeviceDescription *)description
{
    IOEISADeviceDescription *device = (IOEISADeviceDescription *)description;
    IORange *range;
    id instance;
    if (![device numPortRanges]) {
        IOLog("CogentEM595: No I/O port range configured - aborting\n");
        return NO;
    }
    range = [device portRangeList];
    if ((range->start & 15) || range->size < 16) {
        IOLog("CogentEM595: Invalid I/O port range configured - aborting\n");
        return NO;
    }
    if (![device numInterrupts]) {
        IOLog("CogentEM595: No interrupt configured - aborting\n");
        return NO;
    }
    if (![Intel82595 probeIDRegisterAt:range->start]) {
        IOLog("CogentEM595: Adapter not found at address 0x%x - aborting\n", range->start);
        return NO;
    }
    instance = [self alloc];
    if (instance != nil) return [instance initFromDeviceDescription:description] != nil;
    IOLog("CogentEM595: Unable to allocate an instance - aborting\n");
    return NO;
}

- (BOOL)coldInit
{
    unsigned int count = [(IOPCMCIADeviceDescription *)[self deviceDescription] numTuples];
    id *tuples;
    unsigned char *data;
    unsigned int i, j;
    if (count == 0) {
        IOLog("%s: cannot access CIS tuples\n", [self name]);
        return NO;
    }
    tuples = [(IOPCMCIADeviceDescription *)[self deviceDescription] tupleList];
    if (tuples == NULL) {
        IOLog("%s: cannot access CIS tuples list\n", [self name]);
        return NO;
    }
    for (i = 0; i < count; i++) {
        if ([tuples[i] code] == 0x22) {
            data = [tuples[i] data];
            [tuples[i] length];
            for (j = 0; j < 6; j++) myAddress.ether_addr_octet[j] = data[9 + j];
            return YES;
        }
    }
    return NO;
}
- (const char *)description { return "Cogent eMASTER+ EM595 PCMCIA"; }
@end
