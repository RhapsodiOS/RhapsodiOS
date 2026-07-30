#include <limits.h>

#include "ata_hd_registry_core.h"

void ATAHDRegistryCoreInit(ATAHDRegistryCore *registry)
{
    unsigned int unit;
    unsigned int partition;

    if (registry == 0)
        return;

    for (unit = 0; unit < ATA_HD_UNITS; ++unit) {
        registry->owners[unit] = 0;
        for (partition = 0; partition < ATA_HD_PARTITIONS; ++partition)
            registry->openCounts[unit][partition] = 0;
    }
}

int ATAHDRegistryAllocate(ATAHDRegistryCore *registry, void *owner)
{
    unsigned int unit;

    if (registry == 0 || owner == 0)
        return ATA_HD_REGISTRY_INVALID;

    for (unit = 0; unit < ATA_HD_UNITS; ++unit) {
        if (registry->owners[unit] == owner)
            return ATA_HD_REGISTRY_DUPLICATE;
    }

    for (unit = 0; unit < ATA_HD_UNITS; ++unit) {
        if (registry->owners[unit] == 0) {
            registry->owners[unit] = owner;
            return (int)unit;
        }
    }

    return ATA_HD_REGISTRY_FULL;
}

void *ATAHDRegistryOwner(const ATAHDRegistryCore *registry, unsigned int unit)
{
    if (registry == 0 || unit >= ATA_HD_UNITS)
        return 0;
    return registry->owners[unit];
}

int ATAHDRegistryOpen(ATAHDRegistryCore *registry, unsigned int unit,
                      unsigned int partition)
{
    if (registry == 0 || unit >= ATA_HD_UNITS ||
        partition >= ATA_HD_PARTITIONS)
        return ATA_HD_REGISTRY_INVALID;
    if (registry->owners[unit] == 0)
        return ATA_HD_REGISTRY_NOT_FOUND;
    if (registry->openCounts[unit][partition] == UINT_MAX)
        return ATA_HD_REGISTRY_OVERFLOW;
    ++registry->openCounts[unit][partition];
    return ATA_HD_REGISTRY_SUCCESS;
}

int ATAHDRegistryClose(ATAHDRegistryCore *registry, unsigned int unit,
                       unsigned int partition)
{
    if (registry == 0 || unit >= ATA_HD_UNITS ||
        partition >= ATA_HD_PARTITIONS)
        return ATA_HD_REGISTRY_INVALID;
    if (registry->owners[unit] == 0)
        return ATA_HD_REGISTRY_NOT_FOUND;
    if (registry->openCounts[unit][partition] == 0)
        return ATA_HD_REGISTRY_INVALID;

    --registry->openCounts[unit][partition];
    return ATA_HD_REGISTRY_SUCCESS;
}

int ATAHDRegistryRemove(ATAHDRegistryCore *registry, unsigned int unit)
{
    unsigned int partition;

    if (registry == 0 || unit >= ATA_HD_UNITS)
        return ATA_HD_REGISTRY_INVALID;
    if (registry->owners[unit] == 0)
        return ATA_HD_REGISTRY_NOT_FOUND;

    for (partition = 0; partition < ATA_HD_PARTITIONS; ++partition) {
        if (registry->openCounts[unit][partition] != 0)
            return ATA_HD_REGISTRY_BUSY;
    }

    registry->owners[unit] = 0;
    for (partition = 0; partition < ATA_HD_PARTITIONS; ++partition)
        registry->openCounts[unit][partition] = 0;
    return ATA_HD_REGISTRY_SUCCESS;
}
