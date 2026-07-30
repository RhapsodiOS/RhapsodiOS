#define _CRT_SECURE_NO_WARNINGS

#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <string.h>

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

static char *read_source(const char *path)
{
    FILE *file;
    char *text;
    long length;
    size_t count;

    file = fopen(path, "rb");
    if (file == NULL)
        return NULL;
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return NULL;
    }
    length = ftell(file);
    if (length < 0 || fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return NULL;
    }
    text = (char *)malloc((size_t)length + 1);
    if (text == NULL) {
        fclose(file);
        return NULL;
    }
    count = fread(text, 1, (size_t)length, file);
    fclose(file);
    if (count != (size_t)length) {
        free(text);
        return NULL;
    }
    text[length] = '\0';
    return text;
}

static void test_registry_integration_source_contract(void)
{
    char *header;
    char *registry;
    char *autoconf;
    char *diskMethods;
    char *probe;
    char *initCall;
    char *bootInitCall;

    header = read_source("../../../../kernel-7/bsd/dev/ata_hd_registry.h");
    registry = read_source("../../../../kernel-7/bsd/dev/ata_hd_registry.m");
    autoconf = read_source(
        "../../../../kernel-7/driverkit/i386/autoconf_i386.m");
    diskMethods = read_source(
        "../../../../driverkit-3/libDriver/Kernel/kernelDiskMethods.m");
    CHECK(header != NULL);
    CHECK(registry != NULL);
    CHECK(autoconf != NULL);
    CHECK(diskMethods != NULL);
    if (header == NULL || registry == NULL || autoconf == NULL ||
        diskMethods == NULL)
        goto done;

    CHECK(strstr(header, "typedef int (*ata_hd_ioctl_fn)") != NULL);
    CHECK(strstr(header, "BOOL ata_hd_registry_init(void);") != NULL);
    CHECK(strstr(header, "ata_hd_map_set_live") != NULL);
    CHECK(strstr(header, "ata_hd_map_clear_partition") != NULL);
    CHECK(strstr(header, "ata_hd_activate_units") != NULL);
    CHECK(strstr(registry, "*mapOut = NULL;") != NULL);
    CHECK(strstr(registry, "if (ata_hd_lock == nil)") == NULL);
    CHECK(strstr(registry,
                 "ATAHDRegistryIsActive(&ata_hd_core, unit)") != NULL);
    CHECK(strstr(registry, "return map->liveId;") != NULL);
    CHECK(strstr(diskMethods, "ata_hd_map_set_live") != NULL);
    CHECK(strstr(diskMethods, "ata_hd_map_clear_live") != NULL);
    CHECK(strstr(diskMethods, "ata_hd_map_set_partition") != NULL);
    CHECK(strstr(diskMethods, "ata_hd_map_clear_partition") != NULL);

    probe = strstr(autoconf, "probeNativeDevices(void)");
    CHECK(probe != NULL);
    if (probe != NULL) {
        initCall = strstr(probe, "ata_hd_registry_init()");
        bootInitCall = strstr(probe, "bootDriverInit();");
        CHECK(initCall != NULL);
        CHECK(bootInitCall != NULL);
        if (initCall != NULL && bootInitCall != NULL)
            CHECK(initCall < bootInitCall);
    }

done:
    free(header);
    free(registry);
    free(autoconf);
    free(diskMethods);
}

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
    CHECK(ATAHDRegistryActivate(NULL, 0, &owner) ==
          ATA_HD_REGISTRY_INVALID);
    CHECK(ATAHDRegistryActivate(&registry, 0, NULL) ==
          ATA_HD_REGISTRY_INVALID);
    CHECK(ATAHDRegistryClose(&registry, 0, 0) == ATA_HD_REGISTRY_INVALID);
    CHECK(ATAHDRegistryRemove(NULL, 0) == ATA_HD_REGISTRY_INVALID);
}

static void test_reserved_units_are_inactive_until_activation(void)
{
    ATAHDRegistryCore registry;
    int owner;

    ATAHDRegistryCoreInit(&registry);
    CHECK(ATAHDRegistryAllocate(&registry, &owner) == 0);
    CHECK(ATAHDRegistryIsActive(&registry, 0) == 0);
    CHECK(ATAHDRegistryOpen(&registry, 0, 0) == ATA_HD_REGISTRY_INACTIVE);
    CHECK(ATAHDRegistryActivate(&registry, 0, &owner) ==
          ATA_HD_REGISTRY_SUCCESS);
    CHECK(ATAHDRegistryIsActive(&registry, 0) == 1);
    CHECK(ATAHDRegistryActivate(&registry, 0, &owner) ==
          ATA_HD_REGISTRY_INVALID);
    CHECK(ATAHDRegistryOpen(&registry, 0, 0) ==
          ATA_HD_REGISTRY_SUCCESS);
    CHECK(ATAHDRegistryClose(&registry, 0, 0) ==
          ATA_HD_REGISTRY_SUCCESS);
    CHECK(ATAHDRegistryRemove(&registry, 0) == ATA_HD_REGISTRY_SUCCESS);

    CHECK(ATAHDRegistryAllocate(&registry, &owner) == 0);
    CHECK(ATAHDRegistryRemove(&registry, 0) == ATA_HD_REGISTRY_SUCCESS);
}

static void test_batch_activation_is_all_or_none(void)
{
    ATAHDRegistryCore registry;
    int firstOwner;
    int secondOwner;
    int wrongOwner;
    unsigned int units[2];
    void *owners[2];

    ATAHDRegistryCoreInit(&registry);
    CHECK(ATAHDRegistryAllocate(&registry, &firstOwner) == 0);
    CHECK(ATAHDRegistryAllocate(&registry, &secondOwner) == 1);
    units[0] = 0;
    units[1] = 1;
    owners[0] = &firstOwner;
    owners[1] = &wrongOwner;
    CHECK(ATAHDRegistryActivateBatch(&registry, units, owners, 2) ==
          ATA_HD_REGISTRY_INVALID);
    CHECK(ATAHDRegistryIsActive(&registry, 0) == 0);
    CHECK(ATAHDRegistryIsActive(&registry, 1) == 0);

    owners[1] = &secondOwner;
    CHECK(ATAHDRegistryActivateBatch(&registry, units, owners, 2) ==
          ATA_HD_REGISTRY_SUCCESS);
    CHECK(ATAHDRegistryIsActive(&registry, 0) == 1);
    CHECK(ATAHDRegistryIsActive(&registry, 1) == 1);

    units[1] = 0;
    CHECK(ATAHDRegistryActivateBatch(&registry, units, owners, 2) ==
          ATA_HD_REGISTRY_INVALID);
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
    CHECK(ATAHDRegistryActivate(&registry, 0, &owner) ==
          ATA_HD_REGISTRY_SUCCESS);
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
    CHECK(ATAHDRegistryActivate(&registry, 0, &owner) ==
          ATA_HD_REGISTRY_SUCCESS);
    registry.openCounts[0][2] = UINT_MAX;
    CHECK(ATAHDRegistryOpen(&registry, 0, 2) == ATA_HD_REGISTRY_OVERFLOW);
}

static void test_vnode_presence_balances_core_transitions(void)
{
    ATAHDRegistryCore registry;
    int owner;
    unsigned char blockOpen;
    unsigned char rawOpen;

    ATAHDRegistryCoreInit(&registry);
    CHECK(ATAHDRegistryAllocate(&registry, &owner) == 0);
    CHECK(ATAHDRegistryActivate(&registry, 0, &owner) ==
          ATA_HD_REGISTRY_SUCCESS);
    blockOpen = 0;
    rawOpen = 0;

    CHECK(ATAHDRegistryOpen(&registry, 0, 0) ==
          ATA_HD_REGISTRY_SUCCESS);
    CHECK(ATAHDRegistryPublishPinnedOpen(&registry, 0, 0, &blockOpen) ==
          ATA_HD_REGISTRY_SUCCESS);
    CHECK(ATAHDRegistryOpen(&registry, 0, 0) ==
          ATA_HD_REGISTRY_SUCCESS);
    CHECK(ATAHDRegistryPublishPinnedOpen(&registry, 0, 0, &blockOpen) ==
          ATA_HD_REGISTRY_SUCCESS);
    CHECK(registry.openCounts[0][0] == 1);

    CHECK(ATAHDRegistryOpen(&registry, 0, 0) ==
          ATA_HD_REGISTRY_SUCCESS);
    CHECK(ATAHDRegistryPublishPinnedOpen(&registry, 0, 0, &rawOpen) ==
          ATA_HD_REGISTRY_SUCCESS);
    CHECK(registry.openCounts[0][0] == 2);
    CHECK(ATAHDRegistryRemove(&registry, 0) == ATA_HD_BUSY);

    CHECK(ATAHDRegistryCloseIfPresent(&registry, 0, 0, &rawOpen) ==
          ATA_HD_REGISTRY_SUCCESS);
    CHECK(ATAHDRegistryCloseIfPresent(&registry, 0, 0, &rawOpen) ==
          ATA_HD_REGISTRY_INVALID);
    CHECK(registry.openCounts[0][0] == 1);
    CHECK(blockOpen == 1);

    CHECK(ATAHDRegistryCloseIfPresent(&registry, 0, 0, &blockOpen) ==
          ATA_HD_REGISTRY_SUCCESS);
    CHECK(registry.openCounts[0][0] == 0);
    CHECK(ATAHDRegistryRemove(&registry, 0) == ATA_HD_REGISTRY_SUCCESS);
}

int main(void)
{
    test_registry_integration_source_contract();
    test_lowest_free_and_owner_lookup();
    test_duplicate_and_invalid_inputs();
    test_reserved_units_are_inactive_until_activation();
    test_batch_activation_is_all_or_none();
    test_capacity_and_reuse();
    test_open_counts_and_busy_removal();
    test_vnode_presence_balances_core_transitions();

    if (failures != 0) {
        fprintf(stderr, "ata_hd_registry_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }

    printf("ata_hd_registry_test: all tests passed\n");
    return EXIT_SUCCESS;
}
