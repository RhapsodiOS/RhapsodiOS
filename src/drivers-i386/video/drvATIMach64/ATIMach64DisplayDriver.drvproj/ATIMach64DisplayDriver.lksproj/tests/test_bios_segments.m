#include <stdio.h>
#include <string.h>
#import <architecture/i386/table.h>
#import <machdep/i386/gdt.h>
#import "../ATI_BIOS.h"
#import "mock_runtime.h"

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "BIOS segment check failed at line %d: %s\n", __LINE__, #condition); \
    return 1; } } while (0)

typedef char ATI_bios_selector_must_match_reference_width[
    sizeof(ATI_Bios_Selector) == sizeof(unsigned short) ? 1 : -1];
typedef char ATI_bios_stack_offset_must_match_reference_width[
    sizeof(ATI_Bios_StackOffset) == sizeof(unsigned short) ? 1 : -1];
typedef char ATI_bios_stack_selector_must_match_reference_width[
    sizeof(ATI_Bios_StackSelector) == sizeof(unsigned short) ? 1 : -1];

gdt_t testGDT[32];
gdt_t *gdt = testGDT;
static unsigned char biosAH;
static unsigned int biosCalls;
static ATIBIOSRegisters biosOutput;
static int overrideBIOSOutput;
unsigned char _bios16[1];
/* The native fixture substitutes only the privileged assembly entry. */
void _ATIbios32(ATIBIOSRegisters *registers)
{
    ++biosCalls;
    ATI_mockCaptureBIOS(registers, 0);
    if (overrideBIOSOutput != 0) {
        registers->eax = biosOutput.eax;
        registers->ebx = biosOutput.ebx;
        registers->ecx = biosOutput.ecx;
        registers->edx = biosOutput.edx;
    }
    registers->eax = (registers->eax & 0xffff00ffU) | ((unsigned int)biosAH << 8);
}

static void setBIOSOutput(unsigned int eax, unsigned int ebx,
                          unsigned int ecx, unsigned int edx)
{
    biosOutput.eax = eax;
    biosOutput.ebx = ebx;
    biosOutput.ecx = ecx;
    biosOutput.edx = edx;
    overrideBIOSOutput = 1;
}

static unsigned char *entry(unsigned int selector)
{
    return (unsigned char *)gdt + selector;
}

static int testCodeDescriptorSaveRestore(void)
{
    unsigned char savedCode[8], savedAlias[8], savedStack[8];
    ATIBIOSRegisters registers;
    ATI_BIOS *bios;
    memset(testGDT, 0x5a, sizeof(testGDT));
    memcpy(savedCode, entry(0x80), 8);
    memcpy(savedAlias, entry(0x90), 8);
    memcpy(savedStack, entry(0x98), 8);
    ATI_mockReset();
    bios = [[ATI_BIOS alloc] initAtSegmentAddress:0x000c0000U];
    CHECK(bios != nil);
    memset(&registers, 0xcc, sizeof(registers));
    CHECK([bios initBIOSBuf:&registers function:0x4f] == 0x400);
    CHECK(registers.reserved0 == 0 && registers.eax == 0x4f);
    CHECK(registers.ebx == 0 && registers.ecx == 0 && registers.edx == 0);
    CHECK(registers.edi == 0 && registers.esi == 0);
    CHECK(registers.codeSelector == 0x80 && registers.dataSelector == 0x10);
    CHECK(registers.es == 0 && registers.flags == 0);
    CHECK(registers.entryOffset == 100 && registers.ebp == 0x400);
    CHECK(ATI_mockAllocationCount() == 2);
    CHECK(ATI_Bios_StackOffset == 2048 && ATI_Bios_StackSelector == 0x98);
    CHECK(entry(0x80)[0] == 0xff && entry(0x80)[1] == 0xff);
    CHECK(entry(0x80)[5] == 0x9a);
    CHECK(entry(0x90)[0] == 0xff && entry(0x90)[1] == 0xff);
    CHECK(entry(0x90)[5] == 0x9a);
    CHECK(entry(0x98)[0] == 0xff && entry(0x98)[1] == 0x07);
    CHECK(entry(0x98)[5] == 0x92);
    [bios restoreCodeSegments];
    CHECK(memcmp(savedCode, entry(0x80), 8) == 0);
    CHECK(memcmp(savedAlias, entry(0x90), 8) == 0);
    CHECK(memcmp(savedStack, entry(0x98), 8) == 0);
    CHECK(ATI_mockFreeCount() == 1);
    [bios free];
    CHECK(ATI_mockFreeCount() == 2);
    return 0;
}

static int testOptionalDataDescriptorBounds(void)
{
    unsigned char original[8];
    ATI_BIOS *bios;
    memset(testGDT, 0x37, sizeof(testGDT));
    memcpy(original, entry(0x88), 8);
    bios = [[ATI_BIOS alloc] initAtSegmentAddress:0x000c0000U];
    CHECK(bios != nil);
    CHECK([bios createDataSegment:0x40005000U size:30] == 0);
    CHECK(entry(0x88)[0] == 29 && entry(0x88)[1] == 0);
    CHECK(entry(0x88)[5] == 0x92);
    [bios restoreDataSegment];
    CHECK(memcmp(original, entry(0x88), 8) == 0);

    CHECK([bios createDataSegment:0x40005000U size:0x10000U] == 0);
    CHECK(entry(0x88)[0] == 0xff && entry(0x88)[1] == 0xff);
    CHECK((entry(0x88)[6] & 0x80) == 0);
    [bios restoreDataSegment];

    CHECK([bios createDataSegment:0x40005000U size:0] == 0);
    CHECK(entry(0x88)[0] == 0xff && entry(0x88)[1] == 0xff);
    CHECK((entry(0x88)[6] & 0x80) != 0);
    [bios restoreDataSegment];

    memcpy(original, entry(0x88), 8);
    CHECK([bios createDataSegment:0x40005000U size:0x10001U] == 3);
    CHECK(memcmp(original, entry(0x88), 8) == 0);
    [bios free];
    return 0;
}

static int testBIOSWrapperAndCommonCRTCStatus(void)
{
    ATI_BIOS *bios;
    ATI_CRTCRecord crtc;
    int status;
    memset(testGDT, 0, sizeof(testGDT));
    memset(&crtc, 0x6c, sizeof(crtc));
    ATI_mockReset();
    biosCalls = 0;
    biosAH = 0;
    bios = [[ATI_BIOS alloc] initAtSegmentAddress:0x000c0000U];
    CHECK(bios != nil);
    status = [bios loadCRTC_comm:3 gamma:1 pitchSize:1 resolution:0x81
                         crtTable:&crtc function:0x4f name:"segment fixture"];
    CHECK(status == 0 && biosCalls == 1);
    CHECK(ATI_mockLastBIOSRegisters()->eax == 0x004fU);
    CHECK(ATI_Bios_Selector == 0x80U);
    CHECK(ATI_Bios_Offset == 100 && kernDataSel == 0x10);
    CHECK(ATI_mockLastBIOSRegisters()->edx == 0x88);
    CHECK(ATI_mockLastBIOSRegisters()->ebx == 0);
    CHECK(ATI_mockLastBIOSRegisters()->codeSelector == 0x90);
    CHECK(ATI_mockLastBIOSRegisters()->entryOffset == 0);

    status = [bios loadCRTC_comm:0x120003 gamma:1 pitchSize:1 resolution:0x81
                         crtTable:&crtc function:0x4f name:"mode width fixture"];
    CHECK(status == 0 && biosCalls == 2);
    CHECK(ATI_mockLastBIOSRegisters()->ecx == 0x8153U);

    biosAH = 0x86;
    status = [bios loadCRTC_comm:3 gamma:0 pitchSize:0 resolution:0x81
                         crtTable:&crtc function:0x4f name:"AH fixture"];
    CHECK(status == 2);
    status = [bios loadCRTC_comm:3 gamma:0 pitchSize:0 resolution:0x80
                         crtTable:&crtc function:0x4f name:"invalid resolution"];
    CHECK(status == 3);
    CHECK(biosCalls == 3);
    [bios free];
    return 0;
}

static int testBIOSWrapperEntryOffsetBoundary(void)
{
    ATIBIOSRegisters registers;
    unsigned int beforeCalls;

    memset(&registers, 0, sizeof(registers));
    ATI_mockReset();
    biosCalls = 0;
    registers.codeSelector = 0x1234;
    registers.entryOffset = 0xffff;
    CHECK(ATIbios16(&registers) == 0);
    CHECK(biosCalls == 1 && ATI_Bios_Offset == 0xffff);
    CHECK(ATI_Bios_Selector == 0x1234 && registers.codeSelector == 0x90);
    CHECK(registers.entryOffset == 0 && kernDataSel == 0x10);

    beforeCalls = biosCalls;
    registers.entryOffset = 0x10000;
    CHECK(ATIbios16(&registers) == -1);
    CHECK(biosCalls == beforeCalls && registers.entryOffset == 0x10000);
    CHECK(ATI_mockLogCount() == 1);
    return 0;
}

static int testROMPresenceAndInitScan(void)
{
    static const char signature[] = "761295520";
    unsigned int segmentAddress;
    unsigned char *rom;

    ATI_mockReset();
    rom = ATI_mockROM();
    memcpy(rom + 0x1000 + 118, signature, 9);
    segmentAddress = 0;
    CHECK([ATI_BIOS ATIPresent:&segmentAddress] == 1);
    CHECK(segmentAddress == 0xc1000);

    memset(rom, 0, ATI_MOCK_ROM_SIZE);
    memcpy(rom + 0x2f000 + 118, signature, 9);
    segmentAddress = 0;
    CHECK([ATI_BIOS ATIPresent:&segmentAddress] == 1);
    CHECK(segmentAddress == 0xef000);

    memset(rom, 0, ATI_MOCK_ROM_SIZE);
    segmentAddress = 0;
    CHECK([ATI_BIOS ATIPresent:&segmentAddress] == 0);
    CHECK(segmentAddress == 0xf0000);

    ATI_mockReset();
    memcpy(ATI_mockROM(), signature, 9);
    {
        ATI_BIOS *bios = [[ATI_BIOS alloc] init];
        CHECK(bios != nil);
        CHECK(ATI_mockAllocationCount() == 1);
        [bios free];
        CHECK(ATI_mockFreeCount() == 1);
    }
    return 0;
}

static int testBIOSServicePackingAndBounds(void)
{
    ATI_BIOS *bios;
    unsigned int beforeCalls;
    int status;

    memset(testGDT, 0, sizeof(testGDT));
    ATI_mockReset();
    biosCalls = 0;
    overrideBIOSOutput = 0;
    biosAH = 0;
    bios = [[ATI_BIOS alloc] initAtSegmentAddress:0x000c0000U];
    CHECK(bios != nil);

    CHECK([bios setVGAMode:0 gamma:1] == 0);
    CHECK(ATI_mockLastBIOSRegisters()->eax == 1);
    CHECK(ATI_mockLastBIOSRegisters()->ecx == 0x81);
    CHECK([bios setVGAMode:0 gamma:0] == 0);
    CHECK(ATI_mockLastBIOSRegisters()->ecx == 1);
    CHECK([bios setVGAMode:1 gamma:1] == 0);
    CHECK(ATI_mockLastBIOSRegisters()->ecx == 0x80);
    biosAH = 0x86;
    CHECK([bios setVGAMode:1 gamma:0] == 2);
    CHECK(ATI_mockLastBIOSRegisters()->ecx == 0);

    biosAH = 0;
    beforeCalls = biosCalls;
    CHECK([bios setApertureEnable:1 VGAAperture:1 apertureAdrs:0x12345] == 3);
    CHECK(biosCalls == beforeCalls);
    CHECK([bios setApertureEnable:1 VGAAperture:1 apertureAdrs:0x08000000] == 0);
    CHECK(ATI_mockLastBIOSRegisters()->eax == 5);
    CHECK(ATI_mockLastBIOSRegisters()->ecx == 0x85);
    CHECK(ATI_mockLastBIOSRegisters()->ebx == 0x80);

    CHECK([bios setDPMSMode:4] == 0);
    CHECK(ATI_mockLastBIOSRegisters()->eax == 12);
    CHECK(ATI_mockLastBIOSRegisters()->ecx == 0);
    beforeCalls = biosCalls;
    CHECK([bios setDPMSMode:5] == 3 && biosCalls == beforeCalls);
    CHECK(strcmp(ATI_mockLastLogFormat(),
          "ATI_BIOS set DPMS mode: %x not valid mode\n") == 0);
    CHECK([bios setAPMState:3] == 0);
    CHECK(ATI_mockLastBIOSRegisters()->eax == 14);
    CHECK(ATI_mockLastBIOSRegisters()->ecx == 3);
    beforeCalls = biosCalls;
    CHECK([bios setAPMState:4] == 3 && biosCalls == beforeCalls);
    CHECK(strcmp(ATI_mockLastLogFormat(),
          "ATI_BIOS set APM state: %x not valid mode\n") == 0);

    status = [bios querySize:0 size:&beforeCalls];
    CHECK(status == 0 && beforeCalls == 4096);
    [bios free];
    return 0;
}

static int testBIOSQueryOutputPacking(void)
{
    ATI_BIOS *bios;
    unsigned char refresh[20];
    unsigned char queryBuffer[64];
    unsigned int query, address, depth, memory;
    char hardCoded, smallAperture, asicType, asicRevision;
    unsigned int dpms, apm;
    unsigned int ioAddress;
    char relocatable;

    memset(testGDT, 0, sizeof(testGDT));
    ATI_mockReset();
    biosCalls = 0;
    biosAH = 0;
    setBIOSOutput(0x000000fc, 0xabcd5000, 0x56789abc, 0x89abcdef);
    bios = [[ATI_BIOS alloc] initAtSegmentAddress:0x400c0000U];
    CHECK(bios != nil);
    CHECK([bios shortQuery:&query hardCoded:&hardCoded smallAperture:&smallAperture
                   address:&address colorDepth:&depth memorySize:&memory
                   asicType:&asicType asicRev:&asicRevision] == 0);
    CHECK(query == 0x3c && hardCoded == 1 && smallAperture == 1);
    CHECK(address == 0x5000 && depth == 0x9a && memory == 0xbc);
    CHECK((unsigned char)asicType == 0xcd && (unsigned char)asicRevision == 0xef);

    CHECK([bios getDPMSMode:&dpms] == 0 && dpms == 0);
    CHECK([bios getAPMState:&apm] == 0 && apm == 0);
    CHECK([bios getIOBaseAddress:&ioAddress relocatable:&relocatable] == 0);
    CHECK(relocatable == 0 && ioAddress == 0x89abcdef);

    memset(queryBuffer, 0x6c, sizeof(queryBuffer));
    CHECK([bios deviceQuery:0 bufferSize:sizeof(queryBuffer) buffer:queryBuffer] == 0);
    CHECK(ATI_mockLastBIOSRegisters()->eax == 9);
    CHECK(ATI_mockLastBIOSRegisters()->ebx == 0);
    CHECK(ATI_mockLastBIOSRegisters()->ecx == 1);
    CHECK(ATI_mockLastBIOSRegisters()->edx == 0x88);
    CHECK(queryBuffer[0] == 0 && queryBuffer[sizeof(queryBuffer) - 1] == 0);
    CHECK([bios getRefreshRate:(char *)refresh] == 0);
    CHECK(ATI_mockLastBIOSRegisters()->eax == 21);
    CHECK(ATI_mockLastBIOSRegisters()->ebx == 0);
    CHECK(ATI_mockLastBIOSRegisters()->edx == 0x88);

    biosAH = 0x86;
    query = 0xfeedbeef;
    CHECK([bios shortQuery:&query hardCoded:&hardCoded smallAperture:&smallAperture
                   address:&address colorDepth:&depth memorySize:&memory
                   asicType:&asicType asicRev:&asicRevision] == 2);
    CHECK(query == 0xfeedbeef);
    [bios free];
    return 0;
}

int main(void)
{
    if (testCodeDescriptorSaveRestore()) return 1;
    if (testOptionalDataDescriptorBounds()) return 1;
    if (testBIOSWrapperAndCommonCRTCStatus()) return 1;
    if (testBIOSWrapperEntryOffsetBoundary()) return 1;
    if (testROMPresenceAndInitScan()) return 1;
    if (testBIOSServicePackingAndBounds()) return 1;
    if (testBIOSQueryOutputPacking()) return 1;
    return 0;
}
