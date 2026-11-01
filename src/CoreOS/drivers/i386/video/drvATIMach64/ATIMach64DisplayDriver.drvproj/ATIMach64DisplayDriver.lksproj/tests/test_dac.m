#include <stdio.h>
#include <string.h>
#import "../ATIPrivate.h"
#import "../ATIData.h"
#import "mock_runtime.h"
#import <machdep/i386/gdt.h>

extern unsigned int SetGammaValue(int red, int green, int blue, int brightness);
extern int isATI68880RevC(void);

gdt_t testGDT[32];
gdt_t *gdt = testGDT;
unsigned char _bios16[1];
void _ATIbios32(ATIBIOSRegisters *registers) { (void)registers; }

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "DAC check failed at line %d: %s\n", __LINE__, #condition); \
    return 1; } } while (0)

static IODisplayInfo fixtureDisplayInfo;

@interface ATIDACTest : ATI
- (IODisplayInfo *)displayInfo;
@end

@implementation ATIDACTest
- (IODisplayInfo *)displayInfo { return &fixtureDisplayInfo; }
@end

static void setIvar(id object, unsigned int offset, const void *value, unsigned int size)
{
    memcpy((char *)object + offset, value, size);
}

static unsigned int getU32Ivar(id object, unsigned int offset)
{
    unsigned int value;
    memcpy(&value, (char *)object + offset, sizeof(value));
    return value;
}

static int testGammaValueAndRevisionPortOrder(void)
{
    unsigned int result;
    const ATI_mockPortEvent *events;

    ATI_mockReset();
    result = SetGammaValue(128, 64, 32, 32);
    CHECK(result == 16);
    CHECK(ATI_mockPortEventCount() == 3);
    events = ATI_mockPortEvents();
    CHECK(events[0].port == 0x5eed && events[0].value == 64 && events[0].isWrite);
    CHECK(events[1].port == 0x5eed && events[1].value == 32 && events[1].isWrite);
    CHECK(events[2].port == 0x5eed && events[2].value == 16 && events[2].isWrite);

    ATI_mockReset();
    ATI_mockSetPortInput(0x62ec, 0x10);
    ATI_mockSetPortInput(0x5eef, 0xd0);
    CHECK(isATI68880RevC() == 1);
    CHECK(ATI_mockPortEventCount() == 3);
    events = ATI_mockPortEvents();
    CHECK(events[0].port == 0x62ec && events[0].value == 0x10 && !events[0].isWrite);
    CHECK(events[1].port == 0x62ec && events[1].value == 0x13 && events[1].isWrite);
    CHECK(events[2].port == 0x5eef && events[2].value == 0xd0 && !events[2].isWrite);
    return 0;
}

static int testDefaultGammaAndBrightnessBounds(void)
{
    ATIDACTest *driver;
    int oldBrightness;
    int brightness = 64;
    unsigned int nullPointer = 0;
    const ATI_mockPortEvent *events;

    ATI_mockReset();
    memset(&fixtureDisplayInfo, 0, sizeof(fixtureDisplayInfo));
    fixtureDisplayInfo.bitsPerPixel = IO_8BitsPerPixel;
    driver = [[ATIDACTest alloc] init];
    setIvar(driver, 568, &brightness, sizeof(brightness));
    setIvar(driver, 552, &nullPointer, sizeof(nullPointer));
    CHECK([driver setGammaTable] == driver);
    CHECK(ATI_mockPortEventCount() == 771);
    events = ATI_mockPortEvents();
    CHECK(events[0].port == 0x62ec && !events[0].isWrite);
    CHECK(events[1].port == 0x62ec && events[1].value == 0 && events[1].isWrite);
    CHECK(events[2].port == 0x5eec && events[2].value == 0 && events[2].isWrite);
    CHECK(events[3].port == 0x5eed && events[3].value == gamma8[0] && events[3].isWrite);

    oldBrightness = (int)getU32Ivar(driver, 568);
    ATI_mockReset();
    CHECK([driver setBrightness:-1 token:0] == nil);
    CHECK(getU32Ivar(driver, 568) == (unsigned int)oldBrightness);
    CHECK(ATI_mockPortEventCount() == 0);
    CHECK([driver setBrightness:65 token:0] == nil);
    CHECK(ATI_mockPortEventCount() == 0);
    [driver free];
    return 0;
}

static int testTransferTableChannelExtractionAndSparseCount(void)
{
    ATIDACTest *driver;
    unsigned char query[32];
    unsigned int queryAddress;
    char supportsGrey = 1;
    int brightness = 64;
    unsigned int table[3] = { 0x11223344, 0x55667788, 0x99aabbcc };
    const ATI_mockPortEvent *events;

    ATI_mockReset();
    memset(&fixtureDisplayInfo, 0, sizeof(fixtureDisplayInfo));
    fixtureDisplayInfo.bitsPerPixel = IO_8BitsPerPixel;
    fixtureDisplayInfo.colorSpace = IO_RGBColorSpace;
    memset(query, 0, sizeof(query));
    query[9] = 70;
    query[12] = 1;
    driver = [[ATIDACTest alloc] init];
    queryAddress = (unsigned int)query;
    setIvar(driver, 596, &queryAddress, sizeof(queryAddress));
    setIvar(driver, 605, &supportsGrey, sizeof(supportsGrey));
    setIvar(driver, 568, &brightness, sizeof(brightness));
    CHECK([driver setTransferTable:table count:3] == driver);
    CHECK(getU32Ivar(driver, 564) == 3);
    CHECK(ATI_mockPortEventCount() == 768);
    events = ATI_mockPortEvents();
    CHECK(events[3].value == 0x11 && events[4].value == 0x22 && events[5].value == 0x33);
    CHECK(events[258].value == 0x55 && events[259].value == 0x66 && events[260].value == 0x77);
    CHECK(events[513].value == 0x99 && events[514].value == 0xaa && events[515].value == 0xbb);
    [driver free];
    CHECK(ATI_mockFreeCount() == 1);
    return 0;
}

int main(void)
{
    if (testGammaValueAndRevisionPortOrder()) return 1;
    if (testDefaultGammaAndBrightnessBounds()) return 1;
    if (testTransferTableChannelExtractionAndSparseCount()) return 1;
    return 0;
}
