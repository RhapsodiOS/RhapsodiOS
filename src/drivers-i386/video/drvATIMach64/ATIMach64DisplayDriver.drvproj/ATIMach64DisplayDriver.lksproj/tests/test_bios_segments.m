#include <stdio.h>
#include <string.h>
#import <architecture/i386/table.h>
#import <machdep/i386/gdt.h>
#import "../ATI_BIOS.h"
#import "mock_runtime.h"

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "BIOS segment check failed at line %d: %s\n", __LINE__, #condition); \
    return 1; } } while (0)

gdt_t testGDT[32];
gdt_t *gdt = testGDT;
static unsigned char biosAH;
static unsigned int biosCalls;
unsigned char _bios16[1];
/* The native fixture substitutes only the privileged assembly entry. */
void _ATIbios32(ATIBIOSRegisters *registers)
{
    ++biosCalls;
    ATI_mockCaptureBIOS(registers, 0);
    registers->eax = (registers->eax & 0xffff00ffU) | ((unsigned int)biosAH << 8);
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
    bios = [[ATI_BIOS alloc] initAtSegmentAddress:0x400c0000U];
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
    bios = [[ATI_BIOS alloc] initAtSegmentAddress:0x400c0000U];
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
    bios = [[ATI_BIOS alloc] initAtSegmentAddress:0x400c0000U];
    CHECK(bios != nil);
    status = [bios loadCRTC_comm:3 gamma:1 pitchSize:1 resolution:0x81
                         crtTable:&crtc function:0x4f name:"segment fixture"];
    CHECK(status == 0 && biosCalls == 1);
    CHECK(ATI_mockLastBIOSRegisters()->eax == 0x004fU);
    CHECK(ATI_Bios_Selector == 0x8153U);
    CHECK(ATI_Bios_Offset == 100 && kernDataSel == 0x10);
    CHECK(ATI_mockLastBIOSRegisters()->es == 0x88);
    CHECK(ATI_mockLastBIOSRegisters()->codeSelector == 0x90);
    CHECK(ATI_mockLastBIOSRegisters()->entryOffset == 0);

    biosAH = 0x86;
    status = [bios loadCRTC_comm:3 gamma:0 pitchSize:0 resolution:0x81
                         crtTable:&crtc function:0x4f name:"AH fixture"];
    CHECK(status == 2);
    status = [bios loadCRTC_comm:3 gamma:0 pitchSize:0 resolution:0x80
                         crtTable:&crtc function:0x4f name:"invalid resolution"];
    CHECK(status == 3);
    CHECK(biosCalls == 2);
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

int main(void)
{
    if (testCodeDescriptorSaveRestore()) return 1;
    if (testOptionalDataDescriptorBounds()) return 1;
    if (testBIOSWrapperAndCommonCRTCStatus()) return 1;
    if (testBIOSWrapperEntryOffsetBoundary()) return 1;
    return 0;
}
