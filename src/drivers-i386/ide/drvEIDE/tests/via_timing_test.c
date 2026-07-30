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
    test_cable_detection_is_disabled();

    if (failures != 0) {
        fprintf(stderr, "via_timing_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }

    printf("via_timing_test: all tests passed\n");
    return EXIT_SUCCESS;
}
