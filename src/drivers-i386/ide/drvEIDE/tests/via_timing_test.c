#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "VIATiming.h"

static int failures;

#define CHECK(expression)                                                     \
    do {                                                                      \
        if (!(expression)) {                                                  \
            fprintf(stderr, "%s:%d: CHECK failed: %s\n",                    \
                    __FILE__, __LINE__, #expression);                         \
            ++failures;                                                       \
        }                                                                     \
    } while (0)

static void check_chip(unsigned long ideID, unsigned long bridgeID,
                       unsigned char revision, viaChip_t chip,
                       const char *name, unsigned char maxUDMA)
{
    const viaChipInfo_t *info;

    info = VIAFindChip(ideID, bridgeID, revision);
    CHECK(info != NULL);
    if (info == NULL)
        return;

    CHECK(info->chip == chip);
    CHECK(strcmp(info->name, name) == 0);
    CHECK(info->maxPIO == 4);
    CHECK(info->maxMWDMA == 2);
    CHECK(info->maxUDMA == maxUDMA);
}

static void test_chip_lookup(void)
{
    check_chip(VIA_IDE_586, VIA_BRIDGE_586, 0x00, VIA_CHIP_586,
               "VT82C586", VIA_MODE_NONE);
    check_chip(VIA_IDE_586, VIA_BRIDGE_586, 0x0f, VIA_CHIP_586,
               "VT82C586", VIA_MODE_NONE);
    CHECK(VIAFindChip(VIA_IDE_586, VIA_BRIDGE_586, 0x10) == NULL);

    check_chip(VIA_IDE_LATER, VIA_BRIDGE_586, 0x20, VIA_CHIP_586A,
               "VT82C586A", 2);
    check_chip(VIA_IDE_LATER, VIA_BRIDGE_586, 0x2f, VIA_CHIP_586A,
               "VT82C586A", 2);
    CHECK(VIAFindChip(VIA_IDE_LATER, VIA_BRIDGE_586, 0x1f) == NULL);
    CHECK(VIAFindChip(VIA_IDE_LATER, VIA_BRIDGE_586, 0x30) == NULL);

    check_chip(VIA_IDE_LATER, VIA_BRIDGE_596, 0x00, VIA_CHIP_596A,
               "VT82C596A", 2);
    check_chip(VIA_IDE_LATER, VIA_BRIDGE_596, 0x0f, VIA_CHIP_596A,
               "VT82C596A", 2);
    CHECK(VIAFindChip(VIA_IDE_LATER, VIA_BRIDGE_596, 0x10) == NULL);

    check_chip(VIA_IDE_LATER, VIA_BRIDGE_686, 0x10, VIA_CHIP_686A,
               "VT82C686A", 4);
    check_chip(VIA_IDE_LATER, VIA_BRIDGE_686, 0x2f, VIA_CHIP_686A,
               "VT82C686A", 4);
    CHECK(VIAFindChip(VIA_IDE_LATER, VIA_BRIDGE_686, 0x0f) == NULL);
    CHECK(VIAFindChip(VIA_IDE_LATER, VIA_BRIDGE_686, 0x30) == NULL);

    CHECK(VIAFindChip(VIA_IDE_LATER, VIA_BRIDGE_586, 0x00) == NULL);
    CHECK(VIAFindChip(VIA_IDE_586, VIA_BRIDGE_596, 0x00) == NULL);
    CHECK(VIAFindChip(0x12345678UL, VIA_BRIDGE_586, 0x00) == NULL);
    CHECK(VIAFindChip(VIA_IDE_LATER, 0x12345678UL, 0x00) == NULL);
}

int main(void)
{
    test_chip_lookup();

    if (failures != 0) {
        fprintf(stderr, "via_timing_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }

    printf("via_timing_test: all tests passed\n");
    return EXIT_SUCCESS;
}
