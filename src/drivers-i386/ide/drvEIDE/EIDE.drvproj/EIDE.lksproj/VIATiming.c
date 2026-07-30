#include "VIATiming.h"

typedef struct {
    unsigned long ideID;
    unsigned long bridgeID;
    unsigned char lo;
    unsigned char hi;
    viaChipInfo_t info;
} viaEntry_t;

static const viaEntry_t viaTable[] = {
    { VIA_IDE_586, VIA_BRIDGE_586, 0x00, 0x0f,
      { VIA_CHIP_586, "VT82C586", 4, 2, VIA_MODE_NONE } },
    { VIA_IDE_LATER, VIA_BRIDGE_586, 0x20, 0x2f,
      { VIA_CHIP_586A, "VT82C586A", 4, 2, 2 } },
    { VIA_IDE_LATER, VIA_BRIDGE_596, 0x00, 0x0f,
      { VIA_CHIP_596A, "VT82C596A", 4, 2, 2 } },
    { VIA_IDE_LATER, VIA_BRIDGE_686, 0x10, 0x2f,
      { VIA_CHIP_686A, "VT82C686A", 4, 2, 4 } }
};

const viaChipInfo_t *VIAFindChip(unsigned long ideID,
                                 unsigned long bridgeID,
                                 unsigned char revision)
{
    unsigned long i;

    for (i = 0; i < sizeof(viaTable) / sizeof(viaTable[0]); ++i) {
        if (viaTable[i].ideID == ideID &&
            viaTable[i].bridgeID == bridgeID &&
            revision >= viaTable[i].lo && revision <= viaTable[i].hi)
            return &viaTable[i].info;
    }

    return 0;
}
