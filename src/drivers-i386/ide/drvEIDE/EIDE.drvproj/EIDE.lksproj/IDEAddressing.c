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

int IDEBuildTaskfile(ideTaskfile_t *tf, unsigned char mode,
    unsigned char drive, unsigned int block, unsigned int count,
    unsigned int capacity, unsigned char lba48, unsigned int heads,
    unsigned int sectorsPerTrack)
{
    if (!tf || !count || count > 256 || !capacity ||
        block >= capacity || count > capacity - block) return IDE_ADDRESS_INVALID;
    memset(tf, 0, sizeof(*tf));
    tf->sectorCount = (unsigned char)count;
    tf->deviceHead = (unsigned char)(0xa0 | (drive ? 0x10 : 0));
    if (mode == IDE_ADDRESS_CHS) {
        unsigned int track, cylinder, head;
        if (!heads || heads > 16 || !sectorsPerTrack) return IDE_ADDRESS_INVALID;
        track = block / sectorsPerTrack;
        cylinder = track / heads;
        head = track % heads;
        if (cylinder > 0xffff) return IDE_ADDRESS_INVALID;
        tf->lbaLow = (unsigned char)(block % sectorsPerTrack + 1);
        tf->lbaMid = (unsigned char)cylinder;
        tf->lbaHigh = (unsigned char)(cylinder >> 8);
        tf->deviceHead |= (unsigned char)head;
        return IDE_ADDRESS_OK;
    }
    if (mode != IDE_ADDRESS_LBA) return IDE_ADDRESS_INVALID;
    tf->deviceHead |= 0x40;
    if (block > 0x0fffffffUL || count - 1 > 0x0fffffffUL - block) {
        if (!lba48) return IDE_ADDRESS_UNSUPPORTED;
        tf->useLBA48 = 1;
        tf->sectorCountHigh = (unsigned char)(count >> 8);
        tf->lbaLowHigh = (unsigned char)(block >> 24);
    } else tf->deviceHead |= (unsigned char)(block >> 24);
    tf->lbaLow = (unsigned char)block;
    tf->lbaMid = (unsigned char)(block >> 8);
    tf->lbaHigh = (unsigned char)(block >> 16);
    return IDE_ADDRESS_OK;
}

unsigned int IDEExtendedCommand(unsigned int command)
{
    switch (command) {
    case 0x20: return 0x24;
    case 0x30: return 0x34;
    case 0xc4: return 0x29;
    case 0xc5: return 0x39;
    case 0xc8: return 0x25;
    case 0xca: return 0x35;
    case 0x40: return 0x42;
    default: return 0;
    }
}

unsigned int IDETaskfileWriteSequence(const ideTaskfile_t *tf,
    ideTaskWrite_t writes[11])
{
    unsigned int n = 0;

#define IDE_PUT(taskRegister, taskValue)        \
    do {                                        \
        writes[n].reg = (taskRegister);         \
        writes[n].value = (taskValue);          \
        ++n;                                    \
    } while (0)

    IDE_PUT(IDE_TASK_DEVICE, tf->deviceHead);
    if (tf->useLBA48) {
        IDE_PUT(IDE_TASK_FEATURES, tf->featuresHigh);
        IDE_PUT(IDE_TASK_COUNT, tf->sectorCountHigh);
        IDE_PUT(IDE_TASK_LBA_LOW, tf->lbaLowHigh);
        IDE_PUT(IDE_TASK_LBA_MID, tf->lbaMidHigh);
        IDE_PUT(IDE_TASK_LBA_HIGH, tf->lbaHighHigh);
        IDE_PUT(IDE_TASK_FEATURES, tf->features);
        IDE_PUT(IDE_TASK_COUNT, tf->sectorCount);
        IDE_PUT(IDE_TASK_LBA_LOW, tf->lbaLow);
        IDE_PUT(IDE_TASK_LBA_MID, tf->lbaMid);
        IDE_PUT(IDE_TASK_LBA_HIGH, tf->lbaHigh);
    } else {
        IDE_PUT(IDE_TASK_LBA_LOW, tf->lbaLow);
        IDE_PUT(IDE_TASK_COUNT, tf->sectorCount);
        IDE_PUT(IDE_TASK_LBA_MID, tf->lbaMid);
        IDE_PUT(IDE_TASK_LBA_HIGH, tf->lbaHigh);
    }

#undef IDE_PUT

    return n;
}
