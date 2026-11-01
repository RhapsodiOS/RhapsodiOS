#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#import <machdep/i386/gdt.h>
#import <driverkit/IOConfigTable.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOFrameBufferDisplay.h>
#import "../ATIPrivate.h"
#import "../ATIData.h"
#import "mock_runtime.h"

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "init mapping check failed at line %d: %s\n", __LINE__, #condition); \
    return 1; } } while (0)

gdt_t testGDT[32];
gdt_t *gdt = testGDT;
unsigned char _bios16[1];
void _ATIbios32(ATIBIOSRegisters *registers) { (void)registers; }

static unsigned char queryFixture[32];
static IORange memoryRanges[3];
static unsigned char fakeVRAM[32];
static unsigned int events[8], eventAddresses[8], eventCount;
static unsigned int tableCallCount, hardwareCallCount;
static unsigned int expectedMapAddress = 0x07800000;
static const char *testMapStyle;
static int failFirstTableMapping, failFirstHardwareMapping;
static int failTableMappingAtFallback, failHardwareMappingAtFallback;

static void putIvar(id object, unsigned int offset, const void *value, unsigned int size)
{
    memcpy((char *)object + offset, value, size);
}

@interface InitConfig : IOConfigTable
@end

@implementation InitConfig
- (const char *)valueForStringKey:(const char *)key
{
    const char *value = 0;
    if (strcmp(key, "Frame Buffer Mapping") == 0)
        value = testMapStyle;
    else if (strcmp(key, "Display Mode") == 0)
        value = "640x480@60Hz";
    if (value == 0)
        return 0;
    {
        char *copy = malloc(strlen(value) + 1);
        strcpy(copy, value);
        return copy;
    }
}
- (void)freeString:(const char *)string { free((void *)string); }
@end

@interface InitDescription : IODeviceDescription
{
    InitConfig *table;
}
- (id)initWithConfig:(InitConfig *)config;
@end

@implementation InitDescription
- (id)initWithConfig:(InitConfig *)config { table = config; return self; }
- (IOConfigTable *)configTable { return table; }
- (IORange *)memoryRangeList { return memoryRanges; }
@end

@interface InitATI : ATI
@end

@implementation InitATI
- (const char *)name { return "init-mapping-test"; }
- (const char *)stringFromReturn:(IOReturn)value { (void)value; return "reserved"; }
- (int)getQueryData
{
    unsigned int address = (unsigned int)queryFixture;
    putIvar(self, 596, &address, sizeof(address));
    return 0;
}
- (void)updateModeList { }
- (int)parseModeString:(const char *)modeString
{
    int selected = 0;
    (void)modeString;
    putIvar(self, 572, &selected, sizeof(selected));
    return 0;
}
- (int)changeTableMapping:(unsigned int)address
{
    ++tableCallCount;
    events[eventCount] = 1;
    eventAddresses[eventCount++] = address;
    return (failFirstTableMapping != 0 && tableCallCount == 1) ||
           (failTableMappingAtFallback != 0 && address == 0x07800000) ? 1 : 0;
}
- (int)changeHardwareMapping:(unsigned int)address
{
    ++hardwareCallCount;
    events[eventCount] = 2;
    eventAddresses[eventCount++] = address;
    return (failFirstHardwareMapping != 0 && hardwareCallCount == 1) ||
           (failHardwareMappingAtFallback != 0 && address == 0x07800000) ? 1 : 0;
}
- (vm_address_t)mapFrameBufferAtPhysicalAddress:(unsigned int)address length:(int)length
{
    events[eventCount] = 3;
    eventAddresses[eventCount++] = address;
    if (address != expectedMapAddress || length != 0x200000)
        return 0;
    return (vm_address_t)fakeVRAM;
}
- (char)verifyMemoryMap { return 1; }
@end

int main(void)
{
    InitConfig *config;
    InitDescription *description;
    InitATI *driver;
    unsigned char biosMiB = 0x50;

    ATI_mockReset();
    memset(queryFixture, 0, sizeof(queryFixture));
    memset(memoryRanges, 0, sizeof(memoryRanges));
    memset(events, 0, sizeof(events));
    memset(eventAddresses, 0, sizeof(eventAddresses));
    memset(ATI_mockROM(), 0, ATI_MOCK_ROM_SIZE);
    memcpy(ATI_mockROM(), "761295520", 9);
    queryFixture[11] = 2;
    memcpy(queryFixture + 16, &biosMiB, 1);
    memoryRanges[0].start = 0x04000000;
    eventCount = tableCallCount = hardwareCallCount = 0;
    testMapStyle = "BIOS";
    failFirstTableMapping = 1;
    failFirstHardwareMapping = 0;

    config = [[InitConfig alloc] init];
    description = [[InitDescription alloc] initWithConfig:config];
    driver = [[InitATI alloc] initFromDeviceDescription:description];
    CHECK(driver != nil);
    CHECK(tableCallCount == 2);
    CHECK(hardwareCallCount == 1);
    CHECK(eventCount >= 3);
    CHECK(events[0] == 1 && eventAddresses[0] == 0x05000000);
    CHECK(events[1] == 1 && eventAddresses[1] == 0x07800000);
    CHECK(events[2] == 2 && eventAddresses[2] == 0x07800000);
    [driver free];
    [description free];
    [config free];

    ATI_mockReset();
    memset(queryFixture, 0, sizeof(queryFixture));
    memset(events, 0, sizeof(events));
    memset(eventAddresses, 0, sizeof(eventAddresses));
    memset(ATI_mockROM(), 0, ATI_MOCK_ROM_SIZE);
    memcpy(ATI_mockROM(), "761295520", 9);
    queryFixture[11] = 2;
    memcpy(queryFixture + 16, &biosMiB, 1);
    eventCount = tableCallCount = hardwareCallCount = 0;
    testMapStyle = "Table";
    failFirstTableMapping = 0;
    failFirstHardwareMapping = 1;

    config = [[InitConfig alloc] init];
    description = [[InitDescription alloc] initWithConfig:config];
    driver = [[InitATI alloc] initFromDeviceDescription:description];
    CHECK(driver != nil);
    CHECK(tableCallCount == 1);
    CHECK(hardwareCallCount == 2);
    CHECK(eventCount >= 4);
    CHECK(events[0] == 2 && eventAddresses[0] == 0x04000000);
    CHECK(events[1] == 1 && eventAddresses[1] == 0x07800000);
    CHECK(events[2] == 2 && eventAddresses[2] == 0x07800000);
    [driver free];
    [description free];
    [config free];

    ATI_mockReset();
    memset(queryFixture, 0, sizeof(queryFixture));
    memset(memoryRanges, 0, sizeof(memoryRanges));
    memset(events, 0, sizeof(events));
    memset(eventAddresses, 0, sizeof(eventAddresses));
    memset(ATI_mockROM(), 0, ATI_MOCK_ROM_SIZE);
    memcpy(ATI_mockROM(), "761295520", 9);
    queryFixture[11] = 2;
    queryFixture[18] = 0x80;
    biosMiB = 0x80;
    memcpy(queryFixture + 16, &biosMiB, 1);
    memoryRanges[0].start = 0x08100000;
    eventCount = tableCallCount = hardwareCallCount = 0;
    testMapStyle = 0;
    failFirstTableMapping = 0;
    failFirstHardwareMapping = 0;

    config = [[InitConfig alloc] init];
    description = [[InitDescription alloc] initWithConfig:config];
    driver = [[InitATI alloc] initFromDeviceDescription:description];
    CHECK(driver != nil);
    CHECK(tableCallCount == 1);
    CHECK(hardwareCallCount == 1);
    CHECK(eventCount >= 3);
    CHECK(events[0] == 1 && eventAddresses[0] == 0x07800000);
    CHECK(events[1] == 2 && eventAddresses[1] == 0x07800000);
    CHECK(events[2] == 3 && eventAddresses[2] == 0x07800000);
    [driver free];
    [description free];
    [config free];

    ATI_mockReset();
    memset(queryFixture, 0, sizeof(queryFixture));
    memset(memoryRanges, 0, sizeof(memoryRanges));
    memset(events, 0, sizeof(events));
    memset(eventAddresses, 0, sizeof(eventAddresses));
    memset(ATI_mockROM(), 0, ATI_MOCK_ROM_SIZE);
    memcpy(ATI_mockROM(), "761295520", 9);
    queryFixture[11] = 2;
    queryFixture[18] = 0x80;
    biosMiB = 0x50;
    memcpy(queryFixture + 16, &biosMiB, 1);
    memoryRanges[0].start = 0x08100000;
    expectedMapAddress = 0x05000000;
    eventCount = tableCallCount = hardwareCallCount = 0;
    testMapStyle = 0;
    failFirstTableMapping = 0;
    failFirstHardwareMapping = 0;

    config = [[InitConfig alloc] init];
    description = [[InitDescription alloc] initWithConfig:config];
    driver = [[InitATI alloc] initFromDeviceDescription:description];
    CHECK(driver != nil);
    CHECK(tableCallCount == 1);
    CHECK(hardwareCallCount == 0);
    CHECK(eventCount >= 2);
    CHECK(events[0] == 1 && eventAddresses[0] == 0x05000000);
    CHECK(events[1] == 3 && eventAddresses[1] == 0x05000000);
    [driver free];
    [description free];
    [config free];

    ATI_mockReset();
    memset(queryFixture, 0, sizeof(queryFixture));
    memset(memoryRanges, 0, sizeof(memoryRanges));
    memset(events, 0, sizeof(events));
    memset(eventAddresses, 0, sizeof(eventAddresses));
    memset(ATI_mockROM(), 0, ATI_MOCK_ROM_SIZE);
    memcpy(ATI_mockROM(), "761295520", 9);
    queryFixture[11] = 2;
    queryFixture[18] = 0x80;
    biosMiB = 0x80;
    memcpy(queryFixture + 16, &biosMiB, 1);
    memoryRanges[0].start = 0x04000000;
    expectedMapAddress = 0x04000000;
    eventCount = tableCallCount = hardwareCallCount = 0;
    testMapStyle = 0;
    failFirstTableMapping = 0;
    failFirstHardwareMapping = 0;

    config = [[InitConfig alloc] init];
    description = [[InitDescription alloc] initWithConfig:config];
    driver = [[InitATI alloc] initFromDeviceDescription:description];
    CHECK(driver != nil);
    CHECK(tableCallCount == 0);
    CHECK(hardwareCallCount == 1);
    CHECK(eventCount >= 2);
    CHECK(events[0] == 2 && eventAddresses[0] == 0x04000000);
    CHECK(events[1] == 3 && eventAddresses[1] == 0x04000000);
    [driver free];
    [description free];
    [config free];

    ATI_mockReset();
    memset(queryFixture, 0, sizeof(queryFixture));
    memset(memoryRanges, 0, sizeof(memoryRanges));
    memset(events, 0, sizeof(events));
    memset(eventAddresses, 0, sizeof(eventAddresses));
    memset(ATI_mockROM(), 0, ATI_MOCK_ROM_SIZE);
    memcpy(ATI_mockROM(), "761295520", 9);
    queryFixture[11] = 2;
    biosMiB = 0x50;
    memcpy(queryFixture + 16, &biosMiB, 1);
    memoryRanges[0].start = 0x04000000;
    expectedMapAddress = 0x07800000;
    eventCount = tableCallCount = hardwareCallCount = 0;
    testMapStyle = "BIOS";
    failFirstTableMapping = 1;
    failFirstHardwareMapping = 0;
    failTableMappingAtFallback = 1;
    failHardwareMappingAtFallback = 0;

    config = [[InitConfig alloc] init];
    description = [[InitDescription alloc] initWithConfig:config];
    driver = [[InitATI alloc] initFromDeviceDescription:description];
    (void)driver;
    CHECK(tableCallCount == 2);
    CHECK(hardwareCallCount == 0);
    CHECK(eventCount == 2);
    CHECK(events[0] == 1 && eventAddresses[0] == 0x05000000);
    CHECK(events[1] == 1 && eventAddresses[1] == 0x07800000);
    [description free];
    [config free];

    ATI_mockReset();
    memset(queryFixture, 0, sizeof(queryFixture));
    memset(memoryRanges, 0, sizeof(memoryRanges));
    memset(events, 0, sizeof(events));
    memset(eventAddresses, 0, sizeof(eventAddresses));
    memset(ATI_mockROM(), 0, ATI_MOCK_ROM_SIZE);
    memcpy(ATI_mockROM(), "761295520", 9);
    queryFixture[11] = 2;
    biosMiB = 0x50;
    memcpy(queryFixture + 16, &biosMiB, 1);
    memoryRanges[0].start = 0x04000000;
    eventCount = tableCallCount = hardwareCallCount = 0;
    testMapStyle = "Table";
    failFirstTableMapping = 0;
    failFirstHardwareMapping = 1;
    failTableMappingAtFallback = 0;
    failHardwareMappingAtFallback = 1;

    config = [[InitConfig alloc] init];
    description = [[InitDescription alloc] initWithConfig:config];
    driver = [[InitATI alloc] initFromDeviceDescription:description];
    (void)driver;
    CHECK(tableCallCount == 1);
    CHECK(hardwareCallCount == 2);
    CHECK(eventCount == 3);
    CHECK(events[0] == 2 && eventAddresses[0] == 0x04000000);
    CHECK(events[1] == 1 && eventAddresses[1] == 0x07800000);
    CHECK(events[2] == 2 && eventAddresses[2] == 0x07800000);
    [description free];
    [config free];
    return 0;
}
