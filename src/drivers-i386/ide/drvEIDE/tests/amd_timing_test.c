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

static void fill_config(amdConfig_t *config, unsigned char value)
{
    memset(config->bytes, value, AMD_CONFIG_SIZE);
}

static amdDriveTiming_t drive(unsigned char present, unsigned char pio,
                              unsigned char type, unsigned char mode)
{
    amdDriveTiming_t timing;

    timing.present = present;
    timing.pioMode = pio;
    timing.transferType = type;
    timing.transferMode = mode;
    return timing;
}

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

static void test_pio_and_mwdma(void)
{
    static const unsigned char pioData[] = { 0x99, 0x65, 0x33, 0x22, 0x20 };
    static const unsigned char pioCommand[] = {
        0xa8, 0x93, 0x91, 0x22, 0x20
    };
    static const unsigned char mwdmaData[] = { 0x77, 0x21, 0x20 };
    amdConfig_t config;
    amdDriveTiming_t drives[2];
    unsigned char mode;

    drives[1] = drive(0, 0, AMD_XFER_PIO, 0);
    for (mode = 0; mode <= 4; ++mode) {
        fill_config(&config, 0);
        drives[0] = drive(1, mode, AMD_XFER_PIO, mode);
        AMDComputeConfig(&config, AMD_CHIP_756, AMD_CHANNEL_PRIMARY, drives);
        CHECK(CFG(config, 0x4b) == pioData[mode]);
        CHECK(CFG(config, 0x4a) == 0xa8);
        CHECK(CFG(config, 0x4f) == pioCommand[mode]);
    }

    for (mode = 0; mode <= 2; ++mode) {
        fill_config(&config, 0);
        drives[0] = drive(1, 4, AMD_XFER_MWDMA, mode);
        AMDComputeConfig(&config, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, drives);
        CHECK(CFG(config, 0x4b) == mwdmaData[mode]);
        CHECK(CFG(config, 0x4a) == 0xa8);
        CHECK(CFG(config, 0x4f) == 0x20);
    }
}

static void test_absent_and_mixed_drives(void)
{
    amdConfig_t config;
    amdDriveTiming_t drives[2];

    fill_config(&config, 0x55);
    drives[0] = drive(1, 4, AMD_XFER_PIO, 4);
    drives[1] = drive(0, 0, AMD_XFER_PIO, 0);
    AMDComputeConfig(&config, AMD_CHIP_756, AMD_CHANNEL_PRIMARY, drives);
    CHECK(CFG(config, 0x4b) == 0x20);
    CHECK(CFG(config, 0x4a) == 0xa8);
    CHECK(CFG(config, 0x4c) == 0x35);

    fill_config(&config, 0);
    drives[0] = drive(1, 4, AMD_XFER_PIO, 4);
    drives[1] = drive(1, 1, AMD_XFER_PIO, 1);
    AMDComputeConfig(&config, AMD_CHIP_756, AMD_CHANNEL_PRIMARY, drives);
    CHECK(CFG(config, 0x4b) == 0x20);
    CHECK(CFG(config, 0x4a) == 0x65);
    CHECK(CFG(config, 0x4f) == 0x93);
}

static void test_pio_dominates_mwdma(void)
{
    amdConfig_t config;
    amdDriveTiming_t drives[2];

    fill_config(&config, 0);
    drives[0] = drive(1, 0, AMD_XFER_MWDMA, 2);
    drives[1] = drive(0, 0, AMD_XFER_PIO, 0);
    AMDComputeConfig(&config, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, drives);
    CHECK(CFG(config, 0x4b) == 0x99);
    CHECK(CFG(config, 0x4f) == 0xa8);
    CHECK(CFG(config, 0x4c) == 0xb0);
}

static void test_secondary_compute_preserves_complete_snapshot(void)
{
    amdConfig_t config;
    amdConfig_t expected;
    amdDriveTiming_t drives[2];

    fill_config(&config, 0);
    expected = config;
    CFG(expected, 0x49) = 0x20;
    CFG(expected, 0x48) = 0xa8;
    CFG(expected, 0x4c) = 0x03;
    CFG(expected, 0x4e) = 0x20;
    drives[0] = drive(1, 4, AMD_XFER_PIO, 4);
    drives[1] = drive(0, 0, AMD_XFER_PIO, 0);

    AMDComputeConfig(&config, AMD_CHIP_756, AMD_CHANNEL_SECONDARY, drives);

    CHECK(memcmp(config.bytes, expected.bytes, AMD_CONFIG_SIZE) == 0);
}

static void test_secondary_reset_preserves_complete_snapshot(void)
{
    amdConfig_t config;
    amdConfig_t expected;

    fill_config(&config, 0x5a);
    expected = config;
    CFG(expected, 0x49) = 0xa8;
    CFG(expected, 0x48) = 0xa8;
    CFG(expected, 0x4c) = 0x5f;
    CFG(expected, 0x4e) = 0xff;

    AMDResetConfig(&config, AMD_CHIP_756, AMD_CHANNEL_SECONDARY);

    CHECK(memcmp(config.bytes, expected.bytes, AMD_CONFIG_SIZE) == 0);
}

static void test_absent_primary_preserves_complete_snapshot(void)
{
    amdConfig_t config;
    amdConfig_t expected;
    amdDriveTiming_t drives[2];

    fill_config(&config, 0x5a);
    expected = config;
    CFG(expected, 0x4b) = 0xa8;
    CFG(expected, 0x4a) = 0xa8;
    CFG(expected, 0x4c) = 0xfa;
    CFG(expected, 0x4f) = 0xff;
    drives[0] = drive(0, 0, AMD_XFER_PIO, 0);
    drives[1] = drive(0, 0, AMD_XFER_PIO, 0);

    AMDComputeConfig(&config, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, drives);

    CHECK(memcmp(config.bytes, expected.bytes, AMD_CONFIG_SIZE) == 0);
}

static void check_invalid_compute_is_unchanged(amdChip_t chip,
                                                unsigned char channel,
                                                amdDriveTiming_t master,
                                                amdDriveTiming_t slave)
{
    amdConfig_t config;
    amdConfig_t expected;
    amdDriveTiming_t drives[2];

    fill_config(&config, 0x5a);
    expected = config;
    drives[0] = master;
    drives[1] = slave;

    AMDComputeConfig(&config, chip, channel, drives);

    CHECK(memcmp(config.bytes, expected.bytes, AMD_CONFIG_SIZE) == 0);
}

static void test_invalid_compute_inputs_preserve_snapshot(void)
{
    amdDriveTiming_t absent;
    amdDriveTiming_t valid;

    absent = drive(0, 0, AMD_XFER_PIO, 0);
    valid = drive(1, 4, AMD_XFER_PIO, 4);
    check_invalid_compute_is_unchanged(AMD_CHIP_NONE,
                                       AMD_CHANNEL_PRIMARY, valid, absent);
    check_invalid_compute_is_unchanged(AMD_CHIP_756, 2, valid, absent);
    check_invalid_compute_is_unchanged(AMD_CHIP_756,
                                       AMD_CHANNEL_PRIMARY,
                                       drive(1, 5, AMD_XFER_PIO, 5), absent);
    check_invalid_compute_is_unchanged(AMD_CHIP_766,
                                       AMD_CHANNEL_PRIMARY,
                                       drive(1, 4, AMD_XFER_MWDMA, 3), absent);
}

static void test_reset_preserves_sibling_channel(void)
{
    amdConfig_t config;
    amdConfig_t before;

    fill_config(&config, 0x5a);
    before = config;
    AMDResetConfig(&config, AMD_CHIP_756, AMD_CHANNEL_PRIMARY);
    CHECK(CFG(config, 0x4b) == 0xa8);
    CHECK(CFG(config, 0x4a) == 0xa8);
    CHECK(CFG(config, 0x4c) == 0xfa);
    CHECK(CFG(config, 0x4f) == 0xff);
    CHECK(CFG(config, 0x48) == CFG(before, 0x48));
    CHECK(CFG(config, 0x49) == CFG(before, 0x49));
    CHECK(CFG(config, 0x4e) == CFG(before, 0x4e));
}

int main(void)
{
    test_chip_lookup();
    test_pio_and_mwdma();
    test_absent_and_mixed_drives();
    test_pio_dominates_mwdma();
    test_secondary_compute_preserves_complete_snapshot();
    test_secondary_reset_preserves_complete_snapshot();
    test_absent_primary_preserves_complete_snapshot();
    test_invalid_compute_inputs_preserve_snapshot();
    test_reset_preserves_sibling_channel();

    if (failures != 0) {
        fprintf(stderr, "amd_timing_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }

    printf("amd_timing_test: all tests passed\n");
    return EXIT_SUCCESS;
}
