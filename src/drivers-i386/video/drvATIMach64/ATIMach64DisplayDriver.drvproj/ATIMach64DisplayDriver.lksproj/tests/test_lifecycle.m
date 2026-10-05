#include <stdio.h>
#include <string.h>
#import <machdep/i386/gdt.h>
#import "../ATIPrivate.h"
#import "../ATIData.h"
#import "mock_runtime.h"

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "lifecycle check failed at line %d: %s\n", __LINE__, #condition); \
    return 1; } } while (0)

gdt_t testGDT[32];
gdt_t *gdt = testGDT;
unsigned char _bios16[1];
void _ATIbios32(ATIBIOSRegisters *registers) { (void)registers; }

static IODisplayInfo fixtureMode;
static unsigned char fixtureVRAM[32];
static unsigned int trace[16], traceCount;
static int apertureResult, crtcResult, vgaResult;
static unsigned int apertureCalls, crtcCalls, vgaCalls, gammaCalls, biosFreeCalls;
static unsigned int crtcMode, crtcGamma, crtcPitch, crtcResolution;

static void record(unsigned int event)
{
    if (traceCount < sizeof(trace) / sizeof(trace[0]))
        trace[traceCount++] = event;
}

static void putIvar(id object, unsigned int offset, const void *value, unsigned int size)
{
    memcpy((char *)object + offset, value, size);
}

static unsigned int getIvar(id object, unsigned int offset)
{
    unsigned int value;
    memcpy(&value, (char *)object + offset, sizeof(value));
    return value;
}

@interface LifecycleBIOS : ATI_BIOS
@end

@implementation LifecycleBIOS
- init { return self; }
- free { ++biosFreeCalls; return [super free]; }
- (int)setApertureEnable:(char)enabled VGAAperture:(char)vga apertureAdrs:(unsigned int)address
{
    ++apertureCalls;
    record(1);
    if (enabled != 1 || vga != 0 || address != 0)
        return 99;
    return apertureResult;
}
- (int)loadCRTCSetMode:(unsigned int)mode gamma:(char)gamma pitchSize:(unsigned int)pitch
          resolution:(unsigned int)resolution crtTable:(ATI_CRTCRecord *)table
{
    (void)table;
    ++crtcCalls;
    record(2);
    crtcMode = mode;
    crtcGamma = (unsigned int)gamma;
    crtcPitch = pitch;
    crtcResolution = resolution;
    return crtcResult;
}
- (int)setVGAMode:(char)mode gamma:(char)gamma
{
    ++vgaCalls;
    record(3);
    if (mode != 1 || gamma != 0)
        return 99;
    return vgaResult;
}
@end

@interface LifecycleATI : ATI
- (IODisplayInfo *)displayInfo;
@end

@implementation LifecycleATI
- (const char *)name { return "lifecycle-test"; }
- (IODisplayInfo *)displayInfo { return &fixtureMode; }
- (id)setGammaTable { ++gammaCalls; record(4); return self; }
@end

static void resetFixture(void)
{
    memset(&fixtureMode, 0, sizeof(fixtureMode));
    fixtureMode.width = 1024;
    fixtureMode.bitsPerPixel = IO_8BitsPerPixel;
    memset(fixtureVRAM, 0xa5, sizeof(fixtureVRAM));
    memset(trace, 0, sizeof(trace));
    traceCount = apertureCalls = crtcCalls = vgaCalls = gammaCalls = biosFreeCalls = 0;
    apertureResult = crtcResult = vgaResult = 0;
    crtcMode = crtcGamma = crtcPitch = crtcResolution = 0;
}

static int testLinearAndVGATransitionsAndCleanup(void)
{
    LifecycleATI *driver;
    LifecycleBIOS *bios;
    unsigned int state = 0;
    unsigned int pointer;
    unsigned int vramBytes = 16;
    unsigned int index;
    unsigned int *transfer;
    unsigned char *query;
    unsigned int supportsGamma = 1;
    unsigned int supportsGrey256 = 1;

    ATI_mockReset();
    resetFixture();
    driver = [[LifecycleATI alloc] init];
    bios = [[LifecycleBIOS alloc] init];
    CHECK(driver != nil && bios != nil);
    pointer = (unsigned int)fixtureVRAM;
    putIvar(driver, 576, &pointer, sizeof(pointer));
    putIvar(driver, 580, &vramBytes, sizeof(vramBytes));
    putIvar(driver, 584, &state, sizeof(state));
    putIvar(driver, 592, &bios, sizeof(bios));
    putIvar(driver, 604, &supportsGamma, sizeof(unsigned char));
    putIvar(driver, 605, &supportsGrey256, sizeof(unsigned char));

    apertureResult = 1;
    [driver enterLinearMode];
    CHECK(apertureCalls == 1 && crtcCalls == 0 && gammaCalls == 0);
    CHECK(getIvar(driver, 584) == 0 && fixtureVRAM[0] == 0xa5);

    apertureResult = 0;
    crtcResult = 2;
    [driver enterLinearMode];
    CHECK(apertureCalls == 2 && crtcCalls == 1 && gammaCalls == 0);
    CHECK(getIvar(driver, 584) == 0 && fixtureVRAM[0] == 0xa5);
    CHECK(crtcPitch == 0 && crtcResolution == 129);

    crtcResult = 0;
    [driver enterLinearMode];
    CHECK(apertureCalls == 3 && crtcCalls == 2 && gammaCalls == 1);
    CHECK(getIvar(driver, 584) == 1);
    CHECK(crtcMode == displayInfoToColorDepth(&fixtureMode) && crtcGamma == 1);
    CHECK(crtcPitch == 0 && crtcResolution == 129);
    for (index = 0; index < vramBytes; ++index)
        CHECK(fixtureVRAM[index] == 0);
    CHECK(trace[traceCount - 1] == 4);

    transfer = (unsigned int *)IOMalloc(12);
    CHECK(transfer != 0);
    pointer = (unsigned int)transfer;
    putIvar(driver, 552, &pointer, sizeof(pointer));
    index = 4;
    putIvar(driver, 564, &index, sizeof(index));
    vgaResult = 2;
    [driver revertToVGAMode];
    CHECK(vgaCalls == 1 && getIvar(driver, 584) == 1);
    CHECK(ATI_mockFreeCount() == 0);
    vgaResult = 0;
    [driver revertToVGAMode];
    CHECK(vgaCalls == 2 && getIvar(driver, 584) == 2);
    CHECK(getIvar(driver, 552) == 0);
    CHECK(ATI_mockFreeCount() == 1);
    CHECK(traceCount == 8 && trace[0] == 1 && trace[1] == 1 &&
          trace[2] == 2 && trace[3] == 1 && trace[4] == 2 &&
          trace[5] == 4 && trace[6] == 3 && trace[7] == 3);

    query = (unsigned char *)IOMalloc(8);
    CHECK(query != 0);
    pointer = (unsigned int)query;
    putIvar(driver, 596, &pointer, sizeof(pointer));
    index = 8;
    putIvar(driver, 600, &index, sizeof(index));
    [driver free];
    CHECK(ATI_mockFreeCount() == 2);
    CHECK(biosFreeCalls == 1);
    return 0;
}

int main(void)
{
    if (testLinearAndVGATransitionsAndCleanup()) return 1;
    return 0;
}
