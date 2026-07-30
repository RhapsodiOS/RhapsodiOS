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
    CFG(expected, 0x51) = 0x03;
    CFG(expected, 0x50) = 0x03;
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
    CFG(expected, 0x51) = 0x1b;
    CFG(expected, 0x50) = 0x1b;

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
    CFG(expected, 0x41) = 0x1a;
    CFG(expected, 0x53) = 0x1b;
    CFG(expected, 0x52) = 0x1b;
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

static void check_only_offsets_changed(const amdConfig_t *before,
                                       const amdConfig_t *after,
                                       const unsigned char *allowed,
                                       unsigned char allowedCount)
{
    unsigned char index;
    unsigned char allowedIndex;
    int isAllowed;

    for (index = 0; index < AMD_CONFIG_SIZE; ++index) {
        isAllowed = 0;
        for (allowedIndex = 0; allowedIndex < allowedCount; ++allowedIndex) {
            if (index == allowed[allowedIndex] - AMD_CONFIG_BASE)
                isAllowed = 1;
        }
        if (!isAllowed)
            CHECK(before->bytes[index] == after->bytes[index]);
    }
}

static void test_udma_encoding_and_disable(void)
{
    static const unsigned char encoding[] = { 2, 1, 0, 4, 5, 6 };
    amdConfig_t config;
    amdConfig_t before;
    amdDriveTiming_t drives[2];
    unsigned char mode;

    drives[1] = drive(0, 0, AMD_XFER_PIO, 0);
    for (mode = 0; mode <= 5; ++mode) {
        fill_config(&config, 0x38);
        drives[0] = drive(1, 4, AMD_XFER_UDMA, mode);
        AMDComputeConfig(&config, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, drives);
        CHECK(CFG(config, 0x53) == (unsigned char)(0xf8 | encoding[mode]));
        CHECK(CFG(config, 0x52) == 0x3b);
        CHECK((CFG(config, 0x53) & 0x38) == 0x38);
        CHECK((CFG(config, 0x52) & 0x38) == 0x38);
    }

    fill_config(&config, 0x38);
    drives[0] = drive(1, 4, AMD_XFER_UDMA, 4);
    AMDComputeConfig(&config, AMD_CHIP_756, AMD_CHANNEL_PRIMARY, drives);
    CHECK(CFG(config, 0x53) == 0xfd);
    CHECK(CFG(config, 0x52) == 0x3b);

    fill_config(&config, 0x5a);
    before = config;
    drives[0] = drive(1, 4, AMD_XFER_UDMA, 5);
    AMDComputeConfig(&config, AMD_CHIP_756, AMD_CHANNEL_PRIMARY, drives);
    CHECK(memcmp(config.bytes, before.bytes, AMD_CONFIG_SIZE) == 0);

    fill_config(&config, 0x38);
    drives[0] = drive(1, 4, AMD_XFER_PIO, 4);
    AMDComputeConfig(&config, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, drives);
    CHECK(CFG(config, 0x53) == 0x3b);
    CHECK(CFG(config, 0x52) == 0x3b);
}

static void test_reset_disables_current_udma_only(void)
{
    amdConfig_t config;
    amdConfig_t before;

    fill_config(&config, 0x38);
    CFG(config, 0x50) = 0xe1;
    CFG(config, 0x51) = 0xe2;
    before = config;
    AMDResetConfig(&config, AMD_CHIP_766, AMD_CHANNEL_PRIMARY);
    CHECK(CFG(config, 0x53) == 0x3b);
    CHECK(CFG(config, 0x52) == 0x3b);
    CHECK(CFG(config, 0x50) == CFG(before, 0x50));
    CHECK(CFG(config, 0x51) == CFG(before, 0x51));
    CHECK((CFG(config, 0x53) & 0x38) == 0x38);
    CHECK((CFG(config, 0x52) & 0x38) == 0x38);
}

static void check_cable_detection(const amdConfig_t *config, amdChip_t chip,
                                  unsigned char channel, int expected)
{
    amdConfig_t before;

    before = *config;
    CHECK(AMDDetect80WireCable(config, chip, channel) == expected);
    CHECK(memcmp(config->bytes, before.bytes, AMD_CONFIG_SIZE) == 0);
}

static void test_cable_detection_does_not_write(void)
{
    amdConfig_t config;

    fill_config(&config, 0x5a);
    CFG(config, 0x42) = 0;
    check_cable_detection(&config, AMD_CHIP_756, AMD_CHANNEL_PRIMARY, 1);
    check_cable_detection(&config, AMD_CHIP_756, AMD_CHANNEL_SECONDARY, 1);
    check_cable_detection(&config, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, 0);

    CFG(config, 0x42) = 0x01;
    check_cable_detection(&config, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, 1);
    check_cable_detection(&config, AMD_CHIP_766, AMD_CHANNEL_SECONDARY, 0);
    CFG(config, 0x42) = 0x02;
    check_cable_detection(&config, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, 1);
    check_cable_detection(&config, AMD_CHIP_766, AMD_CHANNEL_SECONDARY, 0);
    CFG(config, 0x42) = 0x04;
    check_cable_detection(&config, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, 0);
    check_cable_detection(&config, AMD_CHIP_766, AMD_CHANNEL_SECONDARY, 1);
    CFG(config, 0x42) = 0x08;
    check_cable_detection(&config, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, 0);
    check_cable_detection(&config, AMD_CHIP_766, AMD_CHANNEL_SECONDARY, 1);
    check_cable_detection(&config, AMD_CHIP_NONE, AMD_CHANNEL_PRIMARY, 0);
    check_cable_detection(&config, AMD_CHIP_766, 2, 0);
    CHECK(AMDDetect80WireCable(NULL, AMD_CHIP_766, AMD_CHANNEL_PRIMARY) == 0);
}

static void test_766_fifo_policy(void)
{
    amdConfig_t config;
    amdDriveTiming_t drives[2];

    drives[0] = drive(0, 0, AMD_XFER_PIO, 0);
    drives[1] = drive(0, 0, AMD_XFER_PIO, 0);
    fill_config(&config, 0xff);
    AMDComputeConfig(&config, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, drives);
    CHECK(CFG(config, 0x41) == 0x3f);
    fill_config(&config, 0xff);
    AMDComputeConfig(&config, AMD_CHIP_766, AMD_CHANNEL_SECONDARY, drives);
    CHECK(CFG(config, 0x41) == 0xcf);
    fill_config(&config, 0xff);
    AMDResetConfig(&config, AMD_CHIP_766, AMD_CHANNEL_PRIMARY);
    CHECK(CFG(config, 0x41) == 0x3f);
    fill_config(&config, 0xff);
    AMDResetConfig(&config, AMD_CHIP_766, AMD_CHANNEL_SECONDARY);
    CHECK(CFG(config, 0x41) == 0xcf);

    fill_config(&config, 0);
    AMDResetConfig(&config, AMD_CHIP_766, AMD_CHANNEL_PRIMARY);
    CHECK(CFG(config, 0x41) == 0);
    fill_config(&config, 0xa5);
    AMDResetConfig(&config, AMD_CHIP_756, AMD_CHANNEL_PRIMARY);
    CHECK(CFG(config, 0x41) == 0xa5);
    fill_config(&config, 0xa5);
    AMDComputeConfig(&config, AMD_CHIP_756, AMD_CHANNEL_PRIMARY, drives);
    CHECK(CFG(config, 0x41) == 0xa5);
}

static void test_complete_ownership_and_invalid_udma(void)
{
    static const unsigned char amd766Primary[] = {
        0x41, 0x4a, 0x4b, 0x4c, 0x4f, 0x52, 0x53
    };
    static const unsigned char amd766Secondary[] = {
        0x41, 0x48, 0x49, 0x4c, 0x4e, 0x50, 0x51
    };
    static const unsigned char amd756Primary[] = {
        0x4a, 0x4b, 0x4c, 0x4f, 0x52, 0x53
    };
    amdConfig_t config;
    amdConfig_t before;
    amdDriveTiming_t drives[2];

    drives[0] = drive(1, 4, AMD_XFER_UDMA, 5);
    drives[1] = drive(0, 0, AMD_XFER_PIO, 0);
    fill_config(&config, 0x5a);
    CFG(config, 0x52) = 0x38;
    CFG(config, 0x53) = 0x38;
    before = config;
    AMDComputeConfig(&config, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, drives);
    check_only_offsets_changed(&before, &config, amd766Primary, 7);
    CHECK((CFG(config, 0x52) & 0x38) == 0x38);
    CHECK((CFG(config, 0x53) & 0x38) == 0x38);

    fill_config(&config, 0x5a);
    before = config;
    AMDResetConfig(&config, AMD_CHIP_766, AMD_CHANNEL_SECONDARY);
    check_only_offsets_changed(&before, &config, amd766Secondary, 7);

    fill_config(&config, 0x5a);
    before = config;
    drives[0] = drive(1, 4, AMD_XFER_UDMA, 4);
    AMDComputeConfig(&config, AMD_CHIP_756, AMD_CHANNEL_PRIMARY, drives);
    check_only_offsets_changed(&before, &config, amd756Primary, 6);
    CHECK(CFG(config, 0x41) == CFG(before, 0x41));

    fill_config(&config, 0x5a);
    before = config;
    drives[0] = drive(1, 4, AMD_XFER_UDMA, 6);
    AMDComputeConfig(&config, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, drives);
    CHECK(memcmp(config.bytes, before.bytes, AMD_CONFIG_SIZE) == 0);
    AMDComputeConfig(NULL, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, drives);
    AMDResetConfig(NULL, AMD_CHIP_766, AMD_CHANNEL_PRIMARY);
}

typedef struct {
    unsigned char channel;
    unsigned char unit;
    unsigned char udmaOffset;
    unsigned char siblingUDMAOffset;
    unsigned char dataOffset;
    unsigned char siblingDataOffset;
    unsigned char fifo;
    unsigned char setup;
    unsigned char commandOffset;
} amdUDMA3Position_t;

static void test_udma3_all_positions_preserve_complete_snapshot(void)
{
    static const amdUDMA3Position_t positions[] = {
        { AMD_CHANNEL_PRIMARY, 0, 0x53, 0x52, 0x4b, 0x4a, 0x38, 0x38, 0x4f },
        { AMD_CHANNEL_PRIMARY, 1, 0x52, 0x53, 0x4a, 0x4b, 0x38, 0xc8, 0x4f },
        { AMD_CHANNEL_SECONDARY, 0, 0x51, 0x50, 0x49, 0x48, 0x08, 0x33, 0x4e },
        { AMD_CHANNEL_SECONDARY, 1, 0x50, 0x51, 0x48, 0x49, 0x08, 0x3c, 0x4e }
    };
    amdConfig_t config;
    amdConfig_t expected;
    amdDriveTiming_t drives[2];
    unsigned char position;

    for (position = 0; position < 4; ++position) {
        fill_config(&config, 0x38);
        expected = config;
        CFG(expected, 0x41) = positions[position].fifo;
        CFG(expected, positions[position].udmaOffset) = 0xfc;
        CFG(expected, positions[position].siblingUDMAOffset) = 0x3b;
        CFG(expected, positions[position].dataOffset) = 0x20;
        CFG(expected, positions[position].siblingDataOffset) = 0xa8;
        CFG(expected, 0x4c) = positions[position].setup;
        CFG(expected, positions[position].commandOffset) = 0x20;
        drives[0] = drive(0, 0, AMD_XFER_PIO, 0);
        drives[1] = drive(0, 0, AMD_XFER_PIO, 0);
        drives[positions[position].unit] =
            drive(1, 4, AMD_XFER_UDMA, 3);

        AMDComputeConfig(&config, AMD_CHIP_766,
                         positions[position].channel, drives);

        CHECK(CFG(config, positions[position].udmaOffset) == 0xfc);
        CHECK(CFG(config, positions[position].siblingUDMAOffset) == 0x3b);
        CHECK(memcmp(config.bytes, expected.bytes, AMD_CONFIG_SIZE) == 0);
    }
}

static void test_compute_validation_is_atomic(void)
{
    amdConfig_t config;
    amdConfig_t before;
    amdDriveTiming_t drives[2];

    fill_config(&config, 0x5a);
    before = config;
    drives[0] = drive(1, 4, AMD_XFER_PIO, 4);
    drives[1] = drive(1, 5, AMD_XFER_PIO, 5);
    AMDComputeConfig(&config, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, drives);
    CHECK(memcmp(config.bytes, before.bytes, AMD_CONFIG_SIZE) == 0);

    fill_config(&config, 0x5a);
    before = config;
    drives[0] = drive(1, 4, AMD_XFER_MWDMA, 2);
    drives[1] = drive(1, 4, AMD_XFER_MWDMA, 3);
    AMDComputeConfig(&config, AMD_CHIP_766, AMD_CHANNEL_PRIMARY, drives);
    CHECK(memcmp(config.bytes, before.bytes, AMD_CONFIG_SIZE) == 0);

    fill_config(&config, 0x5a);
    before = config;
    drives[0] = drive(1, 4, AMD_XFER_UDMA, 4);
    drives[1] = drive(1, 4, AMD_XFER_UDMA, 5);
    AMDComputeConfig(&config, AMD_CHIP_756, AMD_CHANNEL_PRIMARY, drives);
    CHECK(memcmp(config.bytes, before.bytes, AMD_CONFIG_SIZE) == 0);
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
    test_udma_encoding_and_disable();
    test_reset_disables_current_udma_only();
    test_cable_detection_does_not_write();
    test_766_fifo_policy();
    test_complete_ownership_and_invalid_udma();
    test_udma3_all_positions_preserve_complete_snapshot();
    test_compute_validation_is_atomic();

    if (failures != 0) {
        fprintf(stderr, "amd_timing_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }

    printf("amd_timing_test: all tests passed\n");
    return EXIT_SUCCESS;
}
