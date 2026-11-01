#include <stddef.h>
#include <stdio.h>
#include "../ATIBIOSTypes.h"
#include <driverkit/displayDefs.h>

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "ABI check failed at line %d: %s\n", __LINE__, #condition); \
    return 1; } } while (0)

int main(void)
{
    CHECK(sizeof(ATIBIOSRegisters) == 48);
    CHECK(offsetof(ATIBIOSRegisters, eax) == 4);
    CHECK(offsetof(ATIBIOSRegisters, ebx) == 8);
    CHECK(offsetof(ATIBIOSRegisters, ecx) == 12);
    CHECK(offsetof(ATIBIOSRegisters, edx) == 16);
    CHECK(offsetof(ATIBIOSRegisters, edi) == 20);
    CHECK(offsetof(ATIBIOSRegisters, esi) == 24);
    CHECK(offsetof(ATIBIOSRegisters, ebp) == 28);
    CHECK(offsetof(ATIBIOSRegisters, codeSelector) == 32);
    CHECK(offsetof(ATIBIOSRegisters, dataSelector) == 34);
    CHECK(offsetof(ATIBIOSRegisters, es) == 36);
    CHECK(offsetof(ATIBIOSRegisters, flags) == 40);
    CHECK(offsetof(ATIBIOSRegisters, entryOffset) == 44);
    CHECK(sizeof(IODisplayInfo) == 136);
    CHECK(offsetof(IODisplayInfo, width) == 0);
    CHECK(offsetof(IODisplayInfo, pixelEncoding) == 32);
    CHECK(offsetof(IODisplayInfo, parameters) == 100);
    CHECK(offsetof(IODisplayInfo, modeUnavailableFlag) == 128);
    return 0;
}
