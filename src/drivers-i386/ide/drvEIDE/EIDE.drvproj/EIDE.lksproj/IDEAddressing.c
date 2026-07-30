#include <string.h>

#include "IDEAddressing.h"

void IDEParseIdentifyCapacity(
    const unsigned short identify[IDE_IDENTIFY_WORDS],
    ideCapacity_t *capacity)
{
    unsigned int lba28;
    unsigned int lba48Low;

    memset(capacity, 0, sizeof(*capacity));

    capacity->lbaSupported =
        (identify[IDE_IDENTIFY_CAPABILITIES] & IDE_CAP_LBA) != 0;
    lba28 = ((unsigned int)identify[IDE_IDENTIFY_LBA28_HIGH] << 16) |
            identify[IDE_IDENTIFY_LBA28_LOW];
    if (lba28 > IDE_LBA28_SECTORS)
        lba28 = IDE_LBA28_SECTORS;
    if (capacity->lbaSupported)
        capacity->lba28Sectors = lba28;

    lba48Low = ((unsigned int)identify[101] << 16) | identify[100];
    if ((identify[IDE_IDENTIFY_COMMAND_SET_ENABLED_2] & IDE_CAP_LBA48) &&
        (lba48Low != 0 || identify[102] != 0 || identify[103] != 0)) {
        capacity->lba48Supported = 1;
        if (identify[102] != 0 || identify[103] != 0) {
            capacity->sectors = IDE_MAX_ADDRESSABLE_SECTORS;
            capacity->clamped = 1;
        } else {
            capacity->sectors = lba48Low;
        }
    } else {
        capacity->sectors = capacity->lba28Sectors;
    }
}
