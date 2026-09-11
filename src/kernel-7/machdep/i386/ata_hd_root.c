#include "../../bsd/dev/ata_hd_registry_core.h"
#include "ata_hd_root.h"

int ATAHDParseRoot(const char *name, unsigned int *unit,
                   unsigned int *partition)
{
    unsigned int parsedUnit;
    unsigned int parsedPartition;
    unsigned int digits;
    char character;

    if (name == 0 || unit == 0 || partition == 0)
        return ATA_HD_REGISTRY_INVALID;
    if (name[0] != 'h' || name[1] != 'd')
        return ATA_HD_REGISTRY_INVALID;

    name += 2;
    parsedUnit = 0;
    digits = 0;
    while (*name >= '0' && *name <= '9') {
        if (digits == 2 || (digits == 0 && *name == '0' &&
                            name[1] >= '0' && name[1] <= '9'))
            return ATA_HD_REGISTRY_INVALID;
        parsedUnit = parsedUnit * 10 + (unsigned int)(*name - '0');
        ++digits;
        ++name;
    }

    if (digits == 0 || parsedUnit >= ATA_HD_UNITS)
        return ATA_HD_REGISTRY_INVALID;

    parsedPartition = 0;
    character = *name;
    if (character != '\0') {
        if (character < 'a' || character > 'h' || name[1] != '\0')
            return ATA_HD_REGISTRY_INVALID;
        parsedPartition = (unsigned int)(character - 'a');
    }

    *unit = parsedUnit;
    *partition = parsedPartition;
    return ATA_HD_REGISTRY_SUCCESS;
}
