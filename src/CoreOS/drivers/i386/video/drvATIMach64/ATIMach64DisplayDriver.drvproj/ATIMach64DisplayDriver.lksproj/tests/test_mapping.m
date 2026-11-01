#include <stdio.h>
#include <string.h>
#import <driverkit/IODeviceDescription.h>
#import "../ATIPrivate.h"
#import "../ATIData.h"
#import "mock_runtime.h"
#import <machdep/i386/gdt.h>

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "mapping check failed at line %d: %s\n", __LINE__, #condition); \
    return 1; } } while (0)

gdt_t testGDT[32];
gdt_t *gdt = testGDT;
unsigned char _bios16[1];
void _ATIbios32(ATIBIOSRegisters *registers) { (void)registers; }

static unsigned int trace[16];
static unsigned int traceCount;
static int biosResult;
static unsigned int biosAddress, biosVga, biosAperture;
static int setPCIResult, getPCIResult, queryResult;
static unsigned int pciReadback;
static unsigned char queryDataFixture[32];
static IORange fakeRanges[3];
static unsigned int fakeRangeCount;
static unsigned int memoryRangeCountCalls;
static int noRanges;
static IOReturn installResults[2];
static unsigned int installIndex, rangeCalls, rangeNums[4];

static void record(unsigned int event)
{
    if (traceCount < sizeof(trace) / sizeof(trace[0]))
        trace[traceCount++] = event;
}

static void putIvar(id object, unsigned int offset, const void *value, unsigned int size)
{
    memcpy((char *)object + offset, value, size);
}

@interface MappingBIOS : ATI_BIOS
@end

@implementation MappingBIOS
- init { return self; }
- (int)setApertureEnable:(char)enabled VGAAperture:(char)vga apertureAdrs:(unsigned int)address
{
    biosAddress = address;
    biosVga = (unsigned int)vga;
    biosAperture = (unsigned int)enabled;
    record(1);
    return biosResult;
}
@end

@interface MappingDescription : Object
@end

@implementation MappingDescription
- (IORange *)memoryRangeList { return noRanges ? (IORange *)0 : fakeRanges; }
- (unsigned int)numMemoryRanges { ++memoryRangeCountCalls; return fakeRangeCount; }
- (IOReturn)setMemoryRangeList:(IORange *)list num:(unsigned int)count
{
    if (rangeCalls < 4)
        rangeNums[rangeCalls] = count;
    ++rangeCalls;
    if (count == 0)
        return 0;
    if (installIndex >= 2)
        return IO_R_INVALID_ARG;
    {
        IOReturn result = installResults[installIndex++];
        if (result == 0 && count == 3)
            memcpy(fakeRanges, list, sizeof(fakeRanges));
        return result;
    }
}
@end

static MappingDescription *description;

@interface MappingATI : ATI
@end

@implementation MappingATI
- (const char *)name { return "mapping-test"; }
- (const char *)stringFromReturn:(IOReturn)value { (void)value; return "mock"; }
- (id)deviceDescription { return description; }
- (IOReturn)setPCIConfigData:(unsigned int)value atRegister:(unsigned int)reg
{
    record(2);
    if (reg != 16 || value != biosAddress)
        return IO_R_INVALID_ARG;
    return setPCIResult;
}
- (IOReturn)getPCIConfigData:(unsigned int *)value atRegister:(unsigned int)reg
{
    record(3);
    if (reg != 16)
        return IO_R_INVALID_ARG;
    *value = pciReadback;
    return getPCIResult;
}
- (int)getQueryData
{
    unsigned int queryAddress;

    record(4);
    if (queryResult == 0) {
        queryAddress = (unsigned int)queryDataFixture;
        putIvar(self, 596, &queryAddress, sizeof(queryAddress));
    }
    return queryResult;
}
@end

static void resetHardware(unsigned int address)
{
    memset(trace, 0, sizeof(trace));
    traceCount = 0;
    biosResult = setPCIResult = getPCIResult = queryResult = 0;
    pciReadback = address;
    biosAddress = biosVga = biosAperture = 0;
    memset(queryDataFixture, 0, sizeof(queryDataFixture));
    *(unsigned short *)(queryDataFixture + 16) = (unsigned short)(address >> 20);
}

static int testHardwareMappingSuccessAndEarlyErrors(void)
{
    MappingATI *driver;
    MappingBIOS *bios;
    unsigned char isPCI = 1;
    const unsigned int address = 0x40000000;

    memset(testGDT, 0, sizeof(testGDT));
    ATI_mockReset();
    resetHardware(address);
    driver = [[MappingATI alloc] init];
    bios = [[MappingBIOS alloc] init];
    CHECK(driver != nil && bios != nil);
    putIvar(driver, 588, &isPCI, sizeof(isPCI));
    putIvar(driver, 592, &bios, sizeof(bios));
    CHECK([driver changeHardwareMapping:address] == 0);
    CHECK(biosAddress == address && biosVga == 0 && biosAperture == 1);
    CHECK(traceCount == 4 && trace[0] == 1 && trace[1] == 2 &&
          trace[2] == 3 && trace[3] == 4);

    resetHardware(address);
    biosResult = 2;
    CHECK([driver changeHardwareMapping:address] == 1);
    CHECK(traceCount == 1 && trace[0] == 1);

    resetHardware(address);
    setPCIResult = IO_R_INVALID_ARG;
    CHECK([driver changeHardwareMapping:address] == 1);
    CHECK(traceCount == 2 && trace[0] == 1 && trace[1] == 2);

    ATI_mockReset();
    resetHardware(address);
    pciReadback ^= 0x1000;
    CHECK([driver changeHardwareMapping:address] == 1);
    CHECK(strcmp(ATI_mockLastLogFormat(),
          "%s: Set Aperture Addrs to 0x%x;  PCI Config Register reported 0x%x\n") == 0);

    ATI_mockReset();
    resetHardware(address);
    *(unsigned short *)(queryDataFixture + 16) = 0x123;
    CHECK([driver changeHardwareMapping:address] == 1);
    CHECK(strcmp(ATI_mockLastLogFormat(),
          "%s: Set Aperture Addrs to 0x%x;  BIOS reported 0x%x\n") == 0);

    resetHardware(address);
    pciReadback ^= 0x1000;
    CHECK([driver changeHardwareMapping:address] == 1);
    CHECK(traceCount == 3 && trace[2] == 3);
    [driver free];
    return 0;
}

static int testTableMappingRollback(void)
{
    MappingATI *driver;
    const unsigned int oldAddress = 0x10000000;
    const unsigned int newAddress = 0x40000000;

    ATI_mockReset();
    memset(fakeRanges, 0, sizeof(fakeRanges));
    fakeRanges[0].start = oldAddress;
    fakeRanges[0].size = 0x200000;
    fakeRanges[1].start = 0x000a0000;
    fakeRanges[1].size = 0x20000;
    fakeRanges[2].start = 0x000c0000;
    fakeRanges[2].size = 0x30000;
    fakeRangeCount = 3;
    noRanges = 0;
    installResults[0] = IO_R_INVALID_ARG;
    installResults[1] = 0;
    installIndex = rangeCalls = 0;
    description = [[MappingDescription alloc] init];
    driver = [[MappingATI alloc] init];
    CHECK(driver != nil && description != nil);
    CHECK([driver changeTableMapping:newAddress] == IO_R_INVALID_ARG);
    CHECK(rangeCalls == 4 && rangeNums[0] == 0 && rangeNums[1] == 3 &&
          rangeNums[2] == 0 && rangeNums[3] == 3);
    CHECK(fakeRanges[0].start == oldAddress && fakeRanges[0].size == 0x200000);
    CHECK(fakeRanges[1].start == 0x000a0000 && fakeRanges[2].start == 0x000c0000);

    ATI_mockReset();
    installResults[0] = IO_R_INVALID_ARG;
    installResults[1] = IO_R_INVALID_ARG;
    installIndex = rangeCalls = 0;
    CHECK([driver changeTableMapping:newAddress] == IO_R_INVALID_ARG);
    CHECK(ATI_mockLogCount() == 1);
    CHECK(strcmp(ATI_mockLastLogFormat(),
          "%s: WARNING: Error (%s) restoringMemory Range to 0x%x\n") == 0);

    rangeCalls = installIndex = 0;
    fakeRangeCount = 2;
    memoryRangeCountCalls = 0;
    CHECK([driver changeTableMapping:newAddress] == -701);
    CHECK(memoryRangeCountCalls == 1);
    CHECK(rangeCalls == 0);
    fakeRangeCount = 3;
    noRanges = 1;
    CHECK([driver changeTableMapping:newAddress] == -701);
    CHECK(rangeCalls == 0);
    [description free];
    [driver free];
    return 0;
}

static int testMemoryMapRestoration(void)
{
    MappingATI *driver;
    unsigned int memory[16];
    unsigned int original[16];
    unsigned int address = (unsigned int)memory;
    unsigned int index;

    for (index = 0; index < 16; ++index)
        memory[index] = original[index] = 0xdead0000U + index;
    driver = [[MappingATI alloc] init];
    CHECK(driver != nil);
    putIvar(driver, 576, &address, sizeof(address));
    CHECK([driver verifyMemoryMap] == 1);
    CHECK(memcmp(memory, original, sizeof(memory)) == 0);
    [driver free];
    return 0;
}

int main(void)
{
    if (testHardwareMappingSuccessAndEarlyErrors()) return 1;
    if (testTableMappingRollback()) return 1;
    if (testMemoryMapRestoration()) return 1;
    return 0;
}
