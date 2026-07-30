#include "AMDTiming.h"

static const amdChipInfo_t amd756Early = {
    AMD_CHIP_756, "AMD-756", 4, AMD_MODE_NONE, 4
};

static const amdChipInfo_t amd756Later = {
    AMD_CHIP_756, "AMD-756", 4, 2, 4
};

static const amdChipInfo_t amd766 = {
    AMD_CHIP_766, "AMD-766", 4, 2, 5
};

const amdChipInfo_t *AMDFindChip(unsigned long pciID, unsigned char revision)
{
    if (pciID == AMD_IDE_756) {
        if (revision <= 3)
            return &amd756Early;
        return &amd756Later;
    }

    if (pciID == AMD_IDE_766)
        return &amd766;

    return 0;
}
