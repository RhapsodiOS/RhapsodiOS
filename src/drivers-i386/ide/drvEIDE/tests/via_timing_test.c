#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "VIATiming.h"

static int failures;

#define CFG(config, offset) \
    ((config).bytes[(offset) - VIA_CONFIG_BASE])

#define CHECK(expression)                                                     \
    do {                                                                      \
        if (!(expression)) {                                                  \
            fprintf(stderr, "%s:%d: CHECK failed: %s\n",                    \
                    __FILE__, __LINE__, #expression);                         \
            ++failures;                                                       \
        }                                                                     \
    } while (0)

static void fill_config(viaConfig_t *config, unsigned char value)
{
    memset(config->bytes, value, sizeof(config->bytes));
}

static void fill_config_sequence(viaConfig_t *config)
{
    unsigned char i;

    for (i = 0; i < VIA_CONFIG_SIZE; ++i)
        config->bytes[i] = (unsigned char)(0x40 + i);
}

static viaDriveTiming_t drive(unsigned char present, unsigned char pioMode,
                              unsigned char transferType,
                              unsigned char transferMode)
{
    viaDriveTiming_t timing;

    timing.present = present;
    timing.pioMode = pioMode;
    timing.transferType = transferType;
    timing.transferMode = transferMode;
    return timing;
}

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

static void test_586_primary_pio4(void)
{
    viaConfig_t config;
    viaDriveTiming_t drives[2];

    fill_config(&config, 0x5a);
    CFG(config, 0x40) = 0x03;
    drives[0] = drive(1, 4, VIA_XFER_PIO, 4);
    drives[1] = drive(0, 0, VIA_XFER_PIO, 0);

    VIAComputeConfig(&config, VIA_CHIP_586, VIA_CHANNEL_PRIMARY, drives);

    CHECK(CFG(config, 0x43) == 0x3a);
    CHECK(CFG(config, 0x4b) == 0x20);
    CHECK(CFG(config, 0x4c) == 0x1a);
    CHECK(CFG(config, 0x4d) == 0x0a);
    CHECK(CFG(config, 0x4f) == 0x20);
    CHECK(CFG(config, 0x48) == 0x5a);
    CHECK(CFG(config, 0x4e) == 0x5a);
    CHECK(CFG(config, 0x50) == 0x5a);
    CHECK(CFG(config, 0x51) == 0x5a);
    CHECK(CFG(config, 0x52) == 0x5a);
    CHECK(CFG(config, 0x53) == 0x5a);
}

static void test_586a_primary_mwdma1(void)
{
    viaConfig_t config;
    viaDriveTiming_t drives[2];

    fill_config(&config, 0xa5);
    CFG(config, 0x40) = 0x02;
    drives[0] = drive(1, 4, VIA_XFER_MWDMA, 1);
    drives[1] = drive(0, 0, VIA_XFER_PIO, 0);

    VIAComputeConfig(&config, VIA_CHIP_586A, VIA_CHANNEL_PRIMARY, drives);

    CHECK(CFG(config, 0x43) == 0x85);
    CHECK(CFG(config, 0x4b) == 0x21);
    CHECK(CFG(config, 0x4d) == 0xa5);
}

static void test_586_secondary_reset(void)
{
    viaConfig_t config;

    fill_config(&config, 0x5a);
    CFG(config, 0x40) = 0x01;

    VIAResetConfig(&config, VIA_CHIP_586, VIA_CHANNEL_SECONDARY);

    CHECK(CFG(config, 0x43) == 0x7a);
    CHECK(CFG(config, 0x48) == 0xa8);
    CHECK(CFG(config, 0x49) == 0xa8);
    CHECK(CFG(config, 0x4a) == 0x5a);
    CHECK(CFG(config, 0x4b) == 0x5a);
    CHECK(CFG(config, 0x4c) == 0x5f);
    CHECK(CFG(config, 0x4d) == 0x50);
    CHECK(CFG(config, 0x4e) == 0xff);
    CHECK(CFG(config, 0x4f) == 0x5a);
}

static void test_mixed_drives_share_slower_command_timing(void)
{
    viaConfig_t config;
    viaDriveTiming_t drives[2];

    fill_config(&config, 0x00);
    drives[0] = drive(1, 3, VIA_XFER_PIO, 3);
    drives[1] = drive(1, 1, VIA_XFER_PIO, 1);

    VIAComputeConfig(&config, VIA_CHIP_596A, VIA_CHANNEL_PRIMARY, drives);

    CHECK(CFG(config, 0x4b) == 0x22);
    CHECK(CFG(config, 0x4a) == 0x65);
    CHECK(CFG(config, 0x4c) == 0x10);
    CHECK(CFG(config, 0x4f) == 0x93);
}

static void test_all_pio_modes(void)
{
    static const unsigned char expectedSetup[] = { 2, 1, 0, 0, 0 };
    static const unsigned char expectedData[] = {
        0x99, 0x65, 0x33, 0x22, 0x20
    };
    static const unsigned char expectedCommand[] = {
        0xa8, 0x93, 0x91, 0x22, 0x20
    };
    viaConfig_t config;
    viaDriveTiming_t drives[2];
    unsigned char mode;

    drives[1] = drive(0, 0, VIA_XFER_PIO, 0);
    for (mode = 0; mode < 5; ++mode) {
        fill_config(&config, 0x00);
        drives[0] = drive(1, mode, VIA_XFER_PIO, mode);
        VIAComputeConfig(&config, VIA_CHIP_596A,
                         VIA_CHANNEL_PRIMARY, drives);
        CHECK(((CFG(config, 0x4c) >> 6) & 0x03) ==
              expectedSetup[mode]);
        CHECK(CFG(config, 0x4b) == expectedData[mode]);
        CHECK(CFG(config, 0x4f) == expectedCommand[mode]);
    }
}

static void test_all_mwdma_modes(void)
{
    static const unsigned char expectedSetup[] = { 1, 1, 0 };
    static const unsigned char expectedData[] = { 0x77, 0x21, 0x20 };
    viaConfig_t config;
    viaDriveTiming_t drives[2];
    unsigned char mode;

    drives[1] = drive(0, 0, VIA_XFER_PIO, 0);
    for (mode = 0; mode < 3; ++mode) {
        fill_config(&config, 0x00);
        drives[0] = drive(1, 4, VIA_XFER_MWDMA, mode);
        VIAComputeConfig(&config, VIA_CHIP_596A,
                         VIA_CHANNEL_PRIMARY, drives);
        CHECK(((CFG(config, 0x4c) >> 6) & 0x03) ==
              expectedSetup[mode]);
        CHECK(CFG(config, 0x4b) == expectedData[mode]);
        CHECK(CFG(config, 0x4f) == 0x20);
    }
}

static void test_zero_present_drives_changes_only_global_fields(void)
{
    viaConfig_t config;
    viaConfig_t expected;
    viaDriveTiming_t drives[2];

    fill_config_sequence(&config);
    CFG(config, 0x40) = 0x03;
    expected = config;
    CFG(expected, 0x43) =
        (unsigned char)((CFG(expected, 0x43) & 0x9f) | 0x20);
    CFG(expected, 0x4d) &= 0x0f;
    drives[0] = drive(0, 4, VIA_XFER_PIO, 4);
    drives[1] = drive(0, 4, VIA_XFER_MWDMA, 2);

    VIAComputeConfig(&config, VIA_CHIP_586, VIA_CHANNEL_PRIMARY, drives);

    CHECK(memcmp(config.bytes, expected.bytes, VIA_CONFIG_SIZE) == 0);
}

static void test_absent_sibling_fields_stay_unchanged(void)
{
    viaConfig_t config;
    viaConfig_t expected;
    viaDriveTiming_t drives[2];

    fill_config_sequence(&config);
    expected = config;
    CFG(expected, 0x4b) = 0x20;
    CFG(expected, 0x4c) &= 0x3f;
    CFG(expected, 0x4f) = 0x20;
    drives[0] = drive(1, 4, VIA_XFER_PIO, 4);
    drives[1] = drive(0, 0, VIA_XFER_PIO, 0);

    VIAComputeConfig(&config, VIA_CHIP_596A,
                     VIA_CHANNEL_PRIMARY, drives);

    CHECK(memcmp(config.bytes, expected.bytes, VIA_CONFIG_SIZE) == 0);
}

static void test_later_chip_resets_preserve_owned_fields(void)
{
    static const viaChip_t chips[] = {
        VIA_CHIP_586A, VIA_CHIP_596A, VIA_CHIP_686A
    };
    viaConfig_t config;
    viaConfig_t expected;
    unsigned char i;

    for (i = 0; i < sizeof(chips) / sizeof(chips[0]); ++i) {
        fill_config_sequence(&config);
        CFG(config, 0x40) = 0x02;
        expected = config;
        if (chips[i] == VIA_CHIP_586A)
            CFG(expected, 0x43) &= 0x9f;
        CFG(expected, 0x4a) = 0xa8;
        CFG(expected, 0x4b) = 0xa8;
        CFG(expected, 0x4c) |= 0xf0;
        CFG(expected, 0x4f) = 0xff;

        VIAResetConfig(&config, chips[i], VIA_CHANNEL_PRIMARY);

        CHECK(memcmp(config.bytes, expected.bytes, VIA_CONFIG_SIZE) == 0);
    }
}

static void check_invalid_compute_is_unchanged(viaChip_t chip,
                                                unsigned char channel,
                                                viaDriveTiming_t master,
                                                viaDriveTiming_t slave)
{
    viaConfig_t config;
    viaConfig_t expected;
    viaDriveTiming_t drives[2];

    fill_config_sequence(&config);
    expected = config;
    drives[0] = master;
    drives[1] = slave;

    VIAComputeConfig(&config, chip, channel, drives);

    CHECK(memcmp(config.bytes, expected.bytes, VIA_CONFIG_SIZE) == 0);
}

static void test_invalid_compute_inputs_fail_closed(void)
{
    viaDriveTiming_t valid;
    viaDriveTiming_t absent;

    valid = drive(1, 4, VIA_XFER_PIO, 4);
    absent = drive(0, 0, VIA_XFER_PIO, 0);
    check_invalid_compute_is_unchanged(VIA_CHIP_NONE,
                                       VIA_CHANNEL_PRIMARY, valid, absent);
    check_invalid_compute_is_unchanged((viaChip_t)(VIA_CHIP_686A + 1),
                                       VIA_CHANNEL_PRIMARY, valid, absent);
    check_invalid_compute_is_unchanged(VIA_CHIP_596A, 2, valid, absent);
    check_invalid_compute_is_unchanged(VIA_CHIP_596A,
                                       VIA_CHANNEL_PRIMARY,
                                       drive(1, 5, VIA_XFER_PIO, 4), absent);
    check_invalid_compute_is_unchanged(VIA_CHIP_596A,
                                       VIA_CHANNEL_PRIMARY,
                                       drive(1, 4, VIA_XFER_MWDMA, 3),
                                       absent);
    check_invalid_compute_is_unchanged(VIA_CHIP_596A,
                                       VIA_CHANNEL_PRIMARY, valid,
                                       drive(1, 5, VIA_XFER_PIO, 4));
}

static void check_invalid_reset_is_unchanged(viaChip_t chip,
                                             unsigned char channel)
{
    viaConfig_t config;
    viaConfig_t expected;

    fill_config_sequence(&config);
    expected = config;

    VIAResetConfig(&config, chip, channel);

    CHECK(memcmp(config.bytes, expected.bytes, VIA_CONFIG_SIZE) == 0);
}

static void test_invalid_reset_inputs_fail_closed(void)
{
    check_invalid_reset_is_unchanged(VIA_CHIP_NONE, VIA_CHANNEL_PRIMARY);
    check_invalid_reset_is_unchanged((viaChip_t)(VIA_CHIP_686A + 1),
                                     VIA_CHANNEL_PRIMARY);
    check_invalid_reset_is_unchanged(VIA_CHIP_596A, 2);
}

static void test_udma_input_is_not_rejected(void)
{
    viaConfig_t config;
    viaDriveTiming_t drives[2];

    fill_config(&config, 0x00);
    drives[0] = drive(1, 4, VIA_XFER_UDMA, 0xff);
    drives[1] = drive(0, 0, VIA_XFER_PIO, 0);

    VIAComputeConfig(&config, VIA_CHIP_686A,
                     VIA_CHANNEL_PRIMARY, drives);

    CHECK(CFG(config, 0x4b) == 0x20);
    CHECK(CFG(config, 0x4f) == 0x20);
}

static void test_cable_detection_is_disabled(void)
{
    viaConfig_t config;

    fill_config(&config, 0xff);
    CHECK(VIADetect80WireCable(&config, VIA_CHIP_586,
                               VIA_CHANNEL_PRIMARY) == 0);
    CHECK(VIADetect80WireCable(&config, VIA_CHIP_586A,
                               VIA_CHANNEL_SECONDARY) == 0);
    CHECK(VIADetect80WireCable(&config, VIA_CHIP_596A,
                               VIA_CHANNEL_PRIMARY) == 0);
    CHECK(VIADetect80WireCable(&config, VIA_CHIP_686A,
                               VIA_CHANNEL_SECONDARY) == 0);
}

int main(void)
{
    test_chip_lookup();
    test_586_primary_pio4();
    test_586a_primary_mwdma1();
    test_586_secondary_reset();
    test_mixed_drives_share_slower_command_timing();
    test_all_pio_modes();
    test_all_mwdma_modes();
    test_zero_present_drives_changes_only_global_fields();
    test_absent_sibling_fields_stay_unchanged();
    test_later_chip_resets_preserve_owned_fields();
    test_invalid_compute_inputs_fail_closed();
    test_invalid_reset_inputs_fail_closed();
    test_udma_input_is_not_rejected();
    test_cable_detection_is_disabled();

    if (failures != 0) {
        fprintf(stderr, "via_timing_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }

    printf("via_timing_test: all tests passed\n");
    return EXIT_SUCCESS;
}
