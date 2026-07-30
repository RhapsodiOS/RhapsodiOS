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
        registry->active[unit] = 0;
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
            registry->active[unit] = 0;
            return (int)unit;
        }
    }

    return ATA_HD_REGISTRY_FULL;
}

int ATAHDRegistryIsActive(const ATAHDRegistryCore *registry,
                          unsigned int unit)
{
    if (registry == 0 || unit >= ATA_HD_UNITS)
        return 0;
    return registry->active[unit] != 0;
}

int ATAHDRegistryActivateBatch(ATAHDRegistryCore *registry,
                               const unsigned int *units,
                               void *const *owners,
                               unsigned int count)
{
    unsigned int index;
    unsigned int previous;

    if (registry == 0 || count > ATA_HD_UNITS)
        return ATA_HD_REGISTRY_INVALID;
    if (count == 0)
        return ATA_HD_REGISTRY_SUCCESS;
    if (units == 0 || owners == 0)
        return ATA_HD_REGISTRY_INVALID;

    for (index = 0; index < count; ++index) {
        if (units[index] >= ATA_HD_UNITS || owners[index] == 0 ||
            registry->owners[units[index]] != owners[index] ||
            registry->active[units[index]] != 0)
            return ATA_HD_REGISTRY_INVALID;
        for (previous = 0; previous < index; ++previous) {
            if (units[previous] == units[index])
                return ATA_HD_REGISTRY_INVALID;
        }
    }

    for (index = 0; index < count; ++index)
        registry->active[units[index]] = 1;
    return ATA_HD_REGISTRY_SUCCESS;
}

int ATAHDRegistryActivate(ATAHDRegistryCore *registry, unsigned int unit,
                          void *owner)
{
    return ATAHDRegistryActivateBatch(registry, &unit, &owner, 1);
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
    if (registry->active[unit] == 0)
        return ATA_HD_REGISTRY_INACTIVE;
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

int ATAHDRegistryPublishPinnedOpen(ATAHDRegistryCore *registry,
                                   unsigned int unit,
                                   unsigned int partition,
                                   unsigned char *present)
{
    if (registry == 0 || present == 0 || unit >= ATA_HD_UNITS ||
        partition >= ATA_HD_PARTITIONS || registry->owners[unit] == 0 ||
        registry->openCounts[unit][partition] == 0)
        return ATA_HD_REGISTRY_INVALID;
    if (*present == 0) {
        *present = 1;
        return ATA_HD_REGISTRY_SUCCESS;
    }

    return ATAHDRegistryClose(registry, unit, partition);
}

int ATAHDRegistryCloseIfPresent(ATAHDRegistryCore *registry,
                                unsigned int unit, unsigned int partition,
                                unsigned char *present)
{
    int result;

    if (present == 0 || *present == 0)
        return ATA_HD_REGISTRY_INVALID;

    result = ATAHDRegistryClose(registry, unit, partition);
    if (result == ATA_HD_REGISTRY_SUCCESS)
        *present = 0;
    return result;
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
            return ATA_HD_BUSY;
    }

    registry->owners[unit] = 0;
    registry->active[unit] = 0;
    for (partition = 0; partition < ATA_HD_PARTITIONS; ++partition)
        registry->openCounts[unit][partition] = 0;
    return ATA_HD_REGISTRY_SUCCESS;
}
