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

void ATAHDAsyncTokenCoreInit(ATAHDAsyncTokenCore *tokens)
{
    unsigned int index;

    if (tokens == 0)
        return;
    tokens->nextGeneration = 0;
    for (index = 0; index < ATA_HD_ASYNC_PINS; ++index) {
        tokens->pins[index].pending = 0;
        tokens->pins[index].unit = 0;
        tokens->pins[index].partition = 0;
        tokens->pins[index].generation = 0;
        tokens->pins[index].state = ATA_HD_ASYNC_PIN_FREE;
    }
}

int ATAHDAsyncTokenReserve(ATAHDAsyncTokenCore *tokens, void *pending,
                           unsigned int unit, unsigned int partition,
                           ATAHDAsyncToken *tokenOut)
{
    unsigned int index;
    unsigned int freeIndex;
    ATAHDAsyncPin *pin;

    if (tokenOut != 0) {
        tokenOut->index = 0;
        tokenOut->generation = 0;
    }
    if (tokens == 0 || pending == 0 || tokenOut == 0 ||
        unit >= ATA_HD_UNITS || partition >= ATA_HD_PARTITIONS)
        return ATA_HD_REGISTRY_INVALID;
    freeIndex = ATA_HD_ASYNC_PINS;
    for (index = 0; index < ATA_HD_ASYNC_PINS; ++index) {
        if (tokens->pins[index].state == ATA_HD_ASYNC_PIN_RESERVED &&
            tokens->pins[index].pending == pending)
            return ATA_HD_REGISTRY_DUPLICATE;
        if (freeIndex == ATA_HD_ASYNC_PINS &&
            tokens->pins[index].state == ATA_HD_ASYNC_PIN_FREE)
            freeIndex = index;
    }
    if (freeIndex == ATA_HD_ASYNC_PINS)
        return ATA_HD_BUSY;

    pin = &tokens->pins[freeIndex];
    ++tokens->nextGeneration;
    if (tokens->nextGeneration == 0)
        ++tokens->nextGeneration;
    pin->generation = tokens->nextGeneration;
    pin->pending = pending;
    pin->unit = unit;
    pin->partition = partition;
    pin->state = ATA_HD_ASYNC_PIN_RESERVED;
    tokenOut->index = freeIndex;
    tokenOut->generation = pin->generation;
    return ATA_HD_REGISTRY_SUCCESS;
}

int ATAHDAsyncTokenForPending(const ATAHDAsyncTokenCore *tokens,
                              void *pending, ATAHDAsyncToken *tokenOut)
{
    unsigned int index;

    if (tokenOut != 0) {
        tokenOut->index = 0;
        tokenOut->generation = 0;
    }
    if (tokens == 0 || pending == 0 || tokenOut == 0)
        return ATA_HD_REGISTRY_INVALID;
    for (index = 0; index < ATA_HD_ASYNC_PINS; ++index) {
        if (tokens->pins[index].state == ATA_HD_ASYNC_PIN_RESERVED &&
            tokens->pins[index].pending == pending) {
            tokenOut->index = index;
            tokenOut->generation = tokens->pins[index].generation;
            return ATA_HD_REGISTRY_SUCCESS;
        }
    }
    return ATA_HD_REGISTRY_NOT_FOUND;
}

int ATAHDAsyncTokenClaim(ATAHDAsyncTokenCore *tokens,
                         ATAHDAsyncToken token)
{
    ATAHDAsyncPin *pin;

    if (tokens == 0 || token.index >= ATA_HD_ASYNC_PINS ||
        token.generation == 0)
        return ATA_HD_REGISTRY_INVALID;
    pin = &tokens->pins[token.index];
    if (pin->state != ATA_HD_ASYNC_PIN_RESERVED ||
        pin->generation != token.generation)
        return ATA_HD_REGISTRY_INVALID;
    pin->pending = 0;
    pin->state = ATA_HD_ASYNC_PIN_CLAIMED;
    return ATA_HD_REGISTRY_SUCCESS;
}

int ATAHDAsyncTokenRelease(ATAHDAsyncTokenCore *tokens,
                           ATAHDAsyncToken token, unsigned int *unitOut,
                           unsigned int *partitionOut)
{
    ATAHDAsyncPin *pin;

    if (tokens == 0 || unitOut == 0 || partitionOut == 0 ||
        token.index >= ATA_HD_ASYNC_PINS || token.generation == 0)
        return ATA_HD_REGISTRY_INVALID;
    pin = &tokens->pins[token.index];
    if (pin->state == ATA_HD_ASYNC_PIN_FREE ||
        pin->generation != token.generation)
        return ATA_HD_REGISTRY_INVALID;
    *unitOut = pin->unit;
    *partitionOut = pin->partition;
    pin->pending = 0;
    pin->unit = 0;
    pin->partition = 0;
    pin->state = ATA_HD_ASYNC_PIN_FREE;
    return ATA_HD_REGISTRY_SUCCESS;
}
