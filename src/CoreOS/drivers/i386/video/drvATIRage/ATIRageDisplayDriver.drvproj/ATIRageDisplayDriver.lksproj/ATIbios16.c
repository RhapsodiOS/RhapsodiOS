#define KERNEL_PRIVATE 1
#define DRIVER_PRIVATE 1

#include "ATI_BIOS.h"
#include <driverkit/generalFuncs.h>

int ATIbios16(ATI_BIOSRegisters *registers)
{
    kernDataSel = 0x10;
    if (registers->entry_offset > 0xFFFF) {
        IOLog("ATIbios16: invalid offset (0x%x)\n", registers->entry_offset);
        return -1;
    }

    ATI_Bios_Offset = (unsigned short)registers->entry_offset;
    ATI_Bios_Selector = registers->code_selector;
    registers->code_selector = 0x90;
    registers->entry_offset = 0;
    _ATIbios32(registers);
    return 0;
}
