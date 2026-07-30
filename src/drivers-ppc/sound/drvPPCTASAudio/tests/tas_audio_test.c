#include "tas_fixtures.h"

#include <stdio.h>
#include <string.h>

#define CHECK(expression) do { if (!(expression)) { \
    fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, \
        #expression); ++failures; } } while (0)

static int failures;

static TASStatus parse(TASFixture *fixture, TASMachineConfig *config)
{
    TASPropertyReader reader;
    reader = TASFixtureReader(fixture);
    return TASParseMachineConfig(&reader, config);
}

static void check_interrupt(const TASInterrupt *interrupt,
    unsigned long number, unsigned long sense)
{
    CHECK(interrupt->number == number);
    CHECK(interrupt->sense == sense);
}

static void check_gpio(const TASGPIODescriptor *gpio, unsigned long offset,
    int activeHigh)
{
    CHECK(gpio->offset == offset);
    CHECK(gpio->activeHigh == activeHigh);
}

static void test_tumbler_published_shape(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASFixtureTumbler(&fixture);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.codecKind == kTASCodecTAS3001C);
    CHECK(strcmp(config.codecCompatible, "tumbler") == 0);
    CHECK(config.i2sCell == 0UL);
    CHECK(config.i2s.address == 0x10000UL && config.i2s.length == 0x1000UL);
    CHECK(config.outputDBDMA.address == 0x08000UL);
    CHECK(config.inputDBDMA.address == 0x08100UL);
    check_interrupt(&config.codecInterrupt, 30, 1);
    check_interrupt(&config.outputInterrupt, 24, 2);
    check_interrupt(&config.inputInterrupt, 25, 3);
    CHECK(config.i2cAddress == 0x34UL && config.i2cPort == 1UL);
    check_gpio(&config.hardwareReset, 0x60, 1);
    check_gpio(&config.amplifierMute, 0x61, 0);
    check_gpio(&config.inputMux, 0x62, 1);
    CHECK(config.routes[kTASRouteHeadphone].present == 1);
    check_gpio(&config.routes[kTASRouteHeadphone].mute, 0x50, 0);
    check_gpio(&config.routes[kTASRouteHeadphone].detect, 0x54, 1);
    CHECK(config.routes[kTASRouteHeadphone].detect.hasIRQ == 1);
    CHECK(config.routes[kTASRouteHeadphone].detect.irq == 47UL);
    CHECK(config.routes[kTASRouteLineOut].present == 0);
}

static void test_snapper_primary_phandles_and_relative_gpio(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASFixtureSnapper(&fixture);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.codecKind == kTASCodecTAS3004);
    CHECK(strcmp(config.codecCompatible, "snapper") == 0);
    CHECK(config.i2cAddress == 0x35UL && config.i2cPort == 1UL);
    check_gpio(&config.hardwareReset, 0x72, 0);
    check_gpio(&config.amplifierMute, 0x73, 1);
    check_gpio(&config.inputMux, 0x74, 0);
    check_gpio(&config.routes[kTASRouteHeadphone].mute, 0x70, 1);
    check_gpio(&config.routes[kTASRouteHeadphone].detect, 0x71, 0);
}

static void test_discovers_roles_without_fixed_paths(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASFixtureSnapper(&fixture);
    TASFixtureSetPath(&fixture, kFixtureI2S, "/pci/mac-io@17/i2s@10000");
    TASFixtureSetPath(&fixture, kFixtureSoundBus, "/renamed/bus");
    TASFixtureSetPath(&fixture, kFixtureSoundChip, "/renamed/bus/chip");
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.codecKind == kTASCodecTAS3004);
}

static void test_rejects_non_sound_bus_role(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASFixtureSnapper(&fixture);
    TASFixtureSetName(&fixture, kFixtureSoundBus, "not-a-sound-bus");
    CHECK(parse(&fixture, &config) == kTASStatusNotMatched);
}

static void test_ref_is_required_for_aoakeylargo(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    unsigned long cells[1];
    TASFixtureSnapper(&fixture);
    TASFixtureRemove(&fixture, kFixtureSoundBus, "platform-tas-codec-ref");
    CHECK(parse(&fixture, &config) == kTASStatusNotMatched);
    TASFixtureSnapper(&fixture);
    cells[0] = 0x77;
    TASFixtureSetCells(&fixture, kFixtureSoundBus,
        "platform-tas-codec-ref", cells, 1);
    CHECK(parse(&fixture, &config) == kTASStatusUnresolved);
    TASFixtureSnapper(&fixture);
    TASFixtureDuplicatePhandle(&fixture, 0x30);
    CHECK(parse(&fixture, &config) == kTASStatusAmbiguous);
}

static void test_multiple_i2s_candidates_are_ambiguous(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASFixtureTumbler(&fixture);
    TASFixtureAddSecondI2S(&fixture);
    CHECK(parse(&fixture, &config) == kTASStatusAmbiguous);
}

static void test_old_codec_fallback_parent_and_port(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASFixtureSnapper(&fixture);
    TASFixtureUseOldCodecFallback(&fixture);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.i2cPort == 1UL && config.i2cAddress == 0x35UL);
    TASFixtureReparent(&fixture, kFixtureCodec, kFixtureMacIO);
    CHECK(parse(&fixture, &config) == kTASStatusNotMatched);
}

static void test_i2c_port_child_and_alias(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    unsigned long cells[1];
    TASFixtureSnapper(&fixture);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.i2cPort == 1UL);
    TASFixtureRemove(&fixture, kFixtureI2CBus, "reg");
    cells[0] = 3;
    TASFixtureSetCells(&fixture, kFixtureI2CBus, "AAPL,i2c-port-select",
        cells, 1);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.i2cPort == 3UL);
}

static void test_i2c_address_forms_and_conflict(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    unsigned long cells[1];
    TASFixtureSnapper(&fixture);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.i2cAddress == 0x35UL);
    cells[0] = 0x35;
    TASFixtureSetCells(&fixture, kFixtureCodec, "reg", cells, 1);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    cells[0] = 0x34;
    TASFixtureSetCells(&fixture, kFixtureCodec, "i2c-address", cells, 1);
    CHECK(parse(&fixture, &config) == kTASStatusConflict);
}

static void test_interrupt_pairs_and_alias(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    unsigned long cells[6];
    TASFixtureTumbler(&fixture);
    TASFixtureRemove(&fixture, kFixtureI2S, "interrupts");
    cells[0] = 40; cells[1] = 4; cells[2] = 41;
    cells[3] = 5; cells[4] = 42; cells[5] = 6;
    TASFixtureSetCells(&fixture, kFixtureI2S, "AAPL,interrupts", cells, 6);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    check_interrupt(&config.codecInterrupt, 40, 4);
    check_interrupt(&config.outputInterrupt, 41, 5);
    check_interrupt(&config.inputInterrupt, 42, 6);
    TASFixtureSetCells(&fixture, kFixtureI2S, "AAPL,interrupts", cells, 5);
    CHECK(parse(&fixture, &config) == kTASStatusMalformed);
}

static void test_gpio_exact_lengths_and_locations(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    unsigned long cells[2];
    TASFixtureSnapper(&fixture);
    cells[0] = 0x72; cells[1] = 0x73;
    TASFixtureSetCells(&fixture, kFixtureHardwareReset, "reg", cells, 2);
    CHECK(parse(&fixture, &config) == kTASStatusMalformed);
    TASFixtureTumbler(&fixture);
    TASFixtureSetCells(&fixture, kFixtureHardwareReset, "AAPL,address",
        cells, 2);
    CHECK(parse(&fixture, &config) == kTASStatusMalformed);
    TASFixtureTumbler(&fixture);
    cells[0] = 0x7fffffffUL;
    TASFixtureSetCells(&fixture, kFixtureHardwareReset, "AAPL,address",
        cells, 1);
    CHECK(parse(&fixture, &config) == kTASStatusOverflow);
    TASFixtureSnapper(&fixture);
    cells[0] = 0x100000UL;
    TASFixtureSetCells(&fixture, kFixtureHardwareReset, "reg", cells, 1);
    CHECK(parse(&fixture, &config) == kTASStatusOverflow);
    TASFixtureSnapper(&fixture);
    TASFixtureRemove(&fixture, kFixtureHardwareReset,
        "audio-gpio-active-state");
    CHECK(parse(&fixture, &config) == kTASStatusMissing);
}

static void test_required_gpio_roles(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASFixtureSnapper(&fixture);
    TASFixtureRemove(&fixture, kFixtureSoundBus, "platform-hw-reset");
    TASFixtureRemove(&fixture, kFixtureHardwareReset, "audio-gpio");
    CHECK(parse(&fixture, &config) == kTASStatusMissing);
    TASFixtureSnapper(&fixture);
    TASFixtureRemove(&fixture, kFixtureSoundBus, "platform-amp-mute");
    TASFixtureRemove(&fixture, kFixtureAmplifierMute, "audio-gpio");
    CHECK(parse(&fixture, &config) == kTASStatusMissing);
    TASFixtureSnapper(&fixture);
    TASFixtureRemove(&fixture, kFixtureSoundBus,
        "platform-codec-input-data-mux");
    TASFixtureRemove(&fixture, kFixtureInputMux, "audio-gpio");
    CHECK(parse(&fixture, &config) == kTASStatusMissing);
}

static void add_lineout(TASFixture *fixture)
{
    unsigned long cells[1];
    cells[0] = 0x45;
    TASFixtureSetCells(fixture, kFixtureSoundBus, "platform-lineout-mute",
        cells, 1);
    cells[0] = 0x46;
    TASFixtureSetCells(fixture, kFixtureSoundBus, "platform-lineout-detect",
        cells, 1);
    cells[0] = 0x75;
    TASFixtureSetCells(fixture, kFixtureLineOutMute, "reg", cells, 1);
    cells[0] = 0;
    TASFixtureSetCells(fixture, kFixtureLineOutMute,
        "audio-gpio-active-state", cells, 1);
    cells[0] = 0x76;
    TASFixtureSetCells(fixture, kFixtureLineOutDetect, "reg", cells, 1);
    cells[0] = 1;
    TASFixtureSetCells(fixture, kFixtureLineOutDetect,
        "audio-gpio-active-state", cells, 1);
    cells[0] = 49;
    TASFixtureSetCells(fixture, kFixtureLineOutDetect, "interrupts",
        cells, 1);
}

static void test_routes_and_published_anded_reset(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASFixtureSnapper(&fixture);
    add_lineout(&fixture);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.routes[kTASRouteLineOut].present == 1);
    TASFixtureSetEmpty(&fixture, kFixtureSoundChip, "has-anded-reset");
    CHECK(parse(&fixture, &config) == kTASStatusUnsupported);
    TASFixtureSnapper(&fixture);
    TASFixtureSetEmpty(&fixture, kFixtureSoundChip, "has-anded-reset");
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.quirks == kTASQuirkANDedReset);
    TASFixtureRemove(&fixture, kFixtureSoundBus, "platform-headphone-detect");
    TASFixtureRemove(&fixture, kFixtureHeadphoneDetect, "audio-gpio");
    CHECK(parse(&fixture, &config) == kTASStatusMissing);
}

static void test_resources_addresses_and_policy(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    unsigned long cells[6];
    unsigned long address[1];
    unsigned long bad[] = { 0x69, 0x6b, 0x00, 0x07, 0x78, 0x80 };
    unsigned long index;
    TASFixtureTumbler(&fixture);
    cells[0] = 0xfffffff0UL; cells[1] = 0x20;
    cells[2] = 0x08000; cells[3] = 0x100;
    cells[4] = 0x08100; cells[5] = 0x100;
    TASFixtureSetCells(&fixture, kFixtureI2S, "reg", cells, 6);
    CHECK(parse(&fixture, &config) == kTASStatusOverflow);
    for (index = 0; index < sizeof(bad) / sizeof(bad[0]); ++index) {
        TASFixtureTumbler(&fixture);
        address[0] = bad[index];
        TASFixtureSetCells(&fixture, kFixtureCodec, "reg", address, 1);
        CHECK(parse(&fixture, &config) == kTASStatusMalformed);
    }
    TASFixtureTumbler(&fixture);
    TASFixtureSetString(&fixture, kFixtureSoundChip, "model",
        "FutureMac99,1");
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    TASFixtureRemove(&fixture, kFixtureI2S, "reg");
    CHECK(parse(&fixture, &config) == kTASStatusMissing);
}

static void test_config_is_atomic_on_new_errors(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASMachineConfig before;
    TASFixtureSnapper(&fixture);
    memset(&config, 0xa5, sizeof(config));
    before = config;
    TASFixtureRemove(&fixture, kFixtureSoundBus, "platform-hw-reset");
    TASFixtureRemove(&fixture, kFixtureHardwareReset, "audio-gpio");
    CHECK(parse(&fixture, &config) == kTASStatusMissing);
    CHECK(memcmp(&config, &before, sizeof(config)) == 0);
}

int main(void)
{
    test_tumbler_published_shape();
    test_snapper_primary_phandles_and_relative_gpio();
    test_discovers_roles_without_fixed_paths();
    test_rejects_non_sound_bus_role();
    test_ref_is_required_for_aoakeylargo();
    test_multiple_i2s_candidates_are_ambiguous();
    test_old_codec_fallback_parent_and_port();
    test_i2c_port_child_and_alias();
    test_i2c_address_forms_and_conflict();
    test_interrupt_pairs_and_alias();
    test_gpio_exact_lengths_and_locations();
    test_required_gpio_roles();
    test_routes_and_published_anded_reset();
    test_resources_addresses_and_policy();
    test_config_is_atomic_on_new_errors();
    if (failures != 0) {
        fprintf(stderr, "%d TAS audio checks failed\n", failures);
        return 1;
    }
    puts("TAS audio parser checks passed");
    return 0;
}
