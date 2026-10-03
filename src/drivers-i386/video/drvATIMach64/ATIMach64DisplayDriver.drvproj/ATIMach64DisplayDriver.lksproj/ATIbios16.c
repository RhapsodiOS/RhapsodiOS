#include "ATIBIOSTypes.h"
#include <driverkit/generalFuncs.h>

unsigned int ATI_Bios_Offset;
unsigned int ATI_Bios_Selector;
unsigned int ATI_Bios_StackOffset;
unsigned int ATI_Bios_StackSelector;
unsigned short kernDataSel;

int ATIbios16(ATIBIOSRegisters *registers)
{
    kernDataSel = 0x10;
    if (registers->entryOffset > 0xffffU) {
        IOLog("ATIbios16: invalid offset (0x%x)\n", registers->entryOffset);
        return -1;
    }

    ATI_Bios_Offset = (unsigned short)registers->entryOffset;
    ATI_Bios_Selector = registers->codeSelector;
    registers->codeSelector = 0x90;
    registers->entryOffset = 0;
    _ATIbios32(registers);
    return 0;
}
