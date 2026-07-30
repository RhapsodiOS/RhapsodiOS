#include <stdio.h>
#include <stdlib.h>
#include <limits.h>

#include "ata_hd_registry_core.h"

static int failures;

typedef struct EIDEMockOwner {
    unsigned int channel;
} EIDEMockOwner;

typedef struct AHCIMockOwner {
    unsigned int port;
} AHCIMockOwner;

#define CHECK(expression)                                                     \
    do {                                                                      \
        if (!(expression)) {                                                  \
            fprintf(stderr, "%s:%d: CHECK failed: %s\n",                    \
                    __FILE__, __LINE__, #expression);                        \
            ++failures;                                                       \
        }                                                                     \
    } while (0)

static void test_lowest_free_and_owner_lookup(void)
{
    ATAHDRegistryCore registry;
    EIDEMockOwner eideOwner;
    AHCIMockOwner ahciOwner;

    eideOwner.channel = 1;
    ahciOwner.port = 7;
    ATAHDRegistryCoreInit(&registry);
    CHECK(ATAHDRegistryAllocate(&registry, &eideOwner) == 0);
    CHECK(ATAHDRegistryAllocate(&registry, &ahciOwner) == 1);
    CHECK(ATAHDRegistryAllocate(&registry, &eideOwner) ==
          ATA_HD_REGISTRY_DUPLICATE);
    CHECK(ATAHDRegistryAllocate(&registry, &ahciOwner) ==
          ATA_HD_REGISTRY_DUPLICATE);
    CHECK(ATAHDRegistryOwner(&registry, 0) == &eideOwner);
    CHECK(ATAHDRegistryOwner(&registry, 1) == &ahciOwner);
    CHECK(eideOwner.channel == 1);
    CHECK(ahciOwner.port == 7);
    CHECK(ATAHDRegistryOwner(&registry, ATA_HD_UNITS) == NULL);
}

static void test_duplicate_and_invalid_inputs(void)
{
    ATAHDRegistryCore registry;
    int owner;

    ATAHDRegistryCoreInit(&registry);
    CHECK(ATAHDRegistryAllocate(&registry, &owner) == 0);
    CHECK(ATAHDRegistryAllocate(&registry, &owner) == ATA_HD_REGISTRY_DUPLICATE);
    CHECK(ATAHDRegistryAllocate(NULL, &owner) == ATA_HD_REGISTRY_INVALID);
    CHECK(ATAHDRegistryAllocate(&registry, NULL) == ATA_HD_REGISTRY_INVALID);
    CHECK(ATAHDRegistryOpen(NULL, 0, 0) == ATA_HD_REGISTRY_INVALID);
    CHECK(ATAHDRegistryOpen(&registry, 0, ATA_HD_PARTITIONS) ==
          ATA_HD_REGISTRY_INVALID);
    CHECK(ATAHDRegistryOpen(&registry, 1, 0) == ATA_HD_REGISTRY_NOT_FOUND);
    CHECK(ATAHDRegistryClose(&registry, 0, 0) == ATA_HD_REGISTRY_INVALID);
    CHECK(ATAHDRegistryRemove(NULL, 0) == ATA_HD_REGISTRY_INVALID);
}

static void test_capacity_and_reuse(void)
{
    ATAHDRegistryCore registry;
    int owners[ATA_HD_UNITS + 1];
    unsigned int unit;

    ATAHDRegistryCoreInit(&registry);
    for (unit = 0; unit < ATA_HD_UNITS; ++unit)
        CHECK(ATAHDRegistryAllocate(&registry, &owners[unit]) == (int)unit);
    CHECK(ATAHDRegistryAllocate(&registry, &owners[ATA_HD_UNITS]) ==
          ATA_HD_REGISTRY_FULL);
    CHECK(ATAHDRegistryRemove(&registry, 7) == ATA_HD_REGISTRY_SUCCESS);
    CHECK(ATAHDRegistryOwner(&registry, 7) == NULL);
    CHECK(ATAHDRegistryAllocate(&registry, &owners[ATA_HD_UNITS]) == 7);
}

static void test_open_counts_and_busy_removal(void)
{
    ATAHDRegistryCore registry;
    int owner;

    ATAHDRegistryCoreInit(&registry);
    CHECK(ATAHDRegistryAllocate(&registry, &owner) == 0);
    CHECK(ATAHDRegistryOpen(&registry, 0, 0) == ATA_HD_REGISTRY_SUCCESS);
    CHECK(ATAHDRegistryOpen(&registry, 0, 0) == ATA_HD_REGISTRY_SUCCESS);
    CHECK(ATAHDRegistryOpen(&registry, 0, 1) == ATA_HD_REGISTRY_SUCCESS);
    CHECK(ATAHDRegistryRemove(&registry, 0) == ATA_HD_BUSY);
    CHECK(ATAHDRegistryClose(&registry, 0, 0) == ATA_HD_REGISTRY_SUCCESS);
    CHECK(ATAHDRegistryRemove(&registry, 0) == ATA_HD_BUSY);
    CHECK(ATAHDRegistryClose(&registry, 0, 1) == ATA_HD_REGISTRY_SUCCESS);
    CHECK(ATAHDRegistryRemove(&registry, 0) == ATA_HD_BUSY);
    CHECK(ATAHDRegistryClose(&registry, 0, 0) == ATA_HD_REGISTRY_SUCCESS);
    CHECK(ATAHDRegistryClose(&registry, 0, 0) == ATA_HD_REGISTRY_INVALID);
    CHECK(ATAHDRegistryRemove(&registry, 0) == ATA_HD_REGISTRY_SUCCESS);

    CHECK(ATAHDRegistryAllocate(&registry, &owner) == 0);
    registry.openCounts[0][2] = UINT_MAX;
    CHECK(ATAHDRegistryOpen(&registry, 0, 2) == ATA_HD_REGISTRY_OVERFLOW);
}

int main(void)
{
    test_lowest_free_and_owner_lookup();
    test_duplicate_and_invalid_inputs();
    test_capacity_and_reuse();
    test_open_counts_and_busy_removal();

    if (failures != 0) {
        fprintf(stderr, "ata_hd_registry_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }

    printf("ata_hd_registry_test: all tests passed\n");
    return EXIT_SUCCESS;
}
