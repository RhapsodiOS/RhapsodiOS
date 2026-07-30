#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "AMDTiming.h"

static int failures;

#define CFG(config, offset) \
    ((config).bytes[(offset) - AMD_CONFIG_BASE])

#define CHECK(expression)                                                     \
    do {                                                                      \
        if (!(expression)) {                                                  \
            fprintf(stderr, "%s:%d: CHECK failed: %s\n",                    \
                    __FILE__, __LINE__, #expression);                         \
            ++failures;                                                       \
        }                                                                     \
    } while (0)

static void check_chip(unsigned long pciID, unsigned char revision,
                       amdChip_t chip, unsigned char maxMWDMA,
                       unsigned char maxUDMA)
{
    const amdChipInfo_t *info;

    info = AMDFindChip(pciID, revision);
    CHECK(info != NULL);
    if (info == NULL)
        return;

    CHECK(info->chip == chip);
    CHECK(strcmp(info->name, chip == AMD_CHIP_756 ? "AMD-756" : "AMD-766") == 0);
    CHECK(info->maxPIO == 4);
    CHECK(info->maxMWDMA == maxMWDMA);
    CHECK(info->maxUDMA == maxUDMA);
}

static void test_chip_lookup(void)
{
    check_chip(AMD_IDE_756, 3, AMD_CHIP_756, AMD_MODE_NONE, 4);
    check_chip(AMD_IDE_756, 4, AMD_CHIP_756, 2, 4);
    check_chip(AMD_IDE_766, 0, AMD_CHIP_766, 2, 5);
    check_chip(AMD_IDE_756, 0, AMD_CHIP_756, AMD_MODE_NONE, 4);
    check_chip(AMD_IDE_756, 2, AMD_CHIP_756, AMD_MODE_NONE, 4);
    CHECK(AMDFindChip(0x74011022UL, 0) == NULL);
    CHECK(AMDFindChip(0x74411022UL, 0) == NULL);
    CHECK(AMDFindChip(0x7411106bUL, 0) == NULL);
}

int main(void)
{
    test_chip_lookup();

    if (failures != 0) {
        fprintf(stderr, "amd_timing_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }

    printf("amd_timing_test: all tests passed\n");
    return EXIT_SUCCESS;
}
