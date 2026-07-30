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

static void test_tumbler_complete(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASFixtureTumbler(&fixture);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.codecKind == kTASCodecTAS3001C);
    CHECK(config.i2s.address == 0x10000UL && config.i2s.length == 0x1000UL);
    CHECK(config.outputDBDMA.address == 0x08000UL);
    CHECK(config.inputDBDMA.address == 0x08100UL);
    CHECK(config.outputIRQ == 24UL && config.inputIRQ == 25UL);
    CHECK(config.i2cAddress == 0x34UL && config.i2cPort == 1UL);
    CHECK(config.routes[kTASRouteHeadphone].present == 1);
    CHECK(config.routes[kTASRouteHeadphone].mute.activeHigh == 0);
    CHECK(config.routes[kTASRouteHeadphone].detect.activeHigh == 1);
    CHECK(config.routes[kTASRouteHeadphone].detect.irq == 47UL);
    CHECK(config.rateCount == 2UL && config.rates[1] == 48000UL);
    CHECK(config.layoutID == 0x37UL);
}

static void test_snapper_and_direct_address(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASFixtureSnapper(&fixture);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.codecKind == kTASCodecTAS3004);
    CHECK(config.i2cAddress == 0x35UL && config.i2cPort == 2UL);
}

static void test_interrupt_alias_and_old_codec_fallback(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    unsigned long cells[2];
    TASFixtureTumbler(&fixture);
    TASFixtureRemove(&fixture, 7, "interrupts");
    cells[0] = 31; cells[1] = 32;
    TASFixtureSetCells(&fixture, 7, "AAPL,interrupts", cells, 2);
    TASFixtureRemove(&fixture, 2, "platform-tas-codec-ref");
    TASFixtureSetPath(&fixture, 4, "/mac-io/i2c/deq");
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.outputIRQ == 31UL && config.inputIRQ == 32UL);
}

static void test_i2c_port_select_alias(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    unsigned long cells[1];
    TASFixtureSnapper(&fixture);
    TASFixtureRemove(&fixture, 3, "reg");
    cells[0] = 3;
    TASFixtureSetCells(&fixture, 3, "AAPL,i2c-port-select", cells, 1);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.i2cPort == 3UL);
}

static void test_old_gpio_names(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASFixtureTumbler(&fixture);
    TASFixtureRemove(&fixture, 2, "platform-headphone-mute");
    TASFixtureRemove(&fixture, 2, "platform-headphone-detect");
    TASFixtureSetString(&fixture, 5, "audio-gpio", "headphone-mute");
    TASFixtureSetString(&fixture, 6, "audio-gpio", "headphone-detect");
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.routes[kTASRouteHeadphone].present == 1);
}

static void test_exact_compatible(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASFixtureTumbler(&fixture);
    TASFixtureSetString(&fixture, 2, "compatible", "awacs");
    CHECK(parse(&fixture, &config) == kTASStatusNotMatched);
    TASFixtureSetString(&fixture, 2, "compatible", "burgundy");
    CHECK(parse(&fixture, &config) == kTASStatusNotMatched);
    TASFixtureSetString(&fixture, 2, "compatible", "tumbler-extra");
    CHECK(parse(&fixture, &config) == kTASStatusNotMatched);
}

static void test_malformed_resources(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    unsigned long cells[7];
    TASFixtureTumbler(&fixture);
    memset(cells, 0, sizeof(cells));
    TASFixtureSetCells(&fixture, 7, "reg", cells, 5);
    CHECK(parse(&fixture, &config) == kTASStatusMalformed);
    TASFixtureTumbler(&fixture);
    TASFixtureSetCells(&fixture, 7, "interrupts", cells, 1);
    CHECK(parse(&fixture, &config) == kTASStatusMalformed);
    TASFixtureTumbler(&fixture);
    TASFixtureRemove(&fixture, 7, "reg");
    CHECK(parse(&fixture, &config) == kTASStatusMissing);
}

static void test_phandle_failures(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    unsigned long cells[1];
    TASFixtureTumbler(&fixture);
    cells[0] = 0x77;
    TASFixtureSetCells(&fixture, 2, "platform-tas-codec-ref", cells, 1);
    CHECK(parse(&fixture, &config) == kTASStatusUnresolved);
    TASFixtureTumbler(&fixture);
    TASFixtureDuplicatePhandle(&fixture, 0x30);
    CHECK(parse(&fixture, &config) == kTASStatusAmbiguous);
}

static void test_addresses(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    unsigned long cells[1];
    unsigned long bad[] = { 0x69, 0x6b, 0x00, 0x07, 0x78, 0x80 };
    unsigned long index;
    for (index = 0; index < sizeof(bad) / sizeof(bad[0]); ++index) {
        TASFixtureTumbler(&fixture);
        cells[0] = bad[index];
        TASFixtureSetCells(&fixture, 4, "reg", cells, 1);
        CHECK(parse(&fixture, &config) == kTASStatusMalformed);
    }
    TASFixtureTumbler(&fixture);
    cells[0] = 0x34;
    TASFixtureSetCells(&fixture, 4, "i2c-address", cells, 1);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    cells[0] = 0x35;
    TASFixtureSetCells(&fixture, 4, "i2c-address", cells, 1);
    CHECK(parse(&fixture, &config) == kTASStatusConflict);
}

static void test_incomplete_route_and_quirk(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    unsigned long cells[1];
    TASFixtureTumbler(&fixture);
    TASFixtureRemove(&fixture, 6, "AAPL,interrupts");
    CHECK(parse(&fixture, &config) == kTASStatusMissing);
    TASFixtureTumbler(&fixture);
    TASFixtureRemove(&fixture, 2, "platform-headphone-detect");
    CHECK(parse(&fixture, &config) == kTASStatusMissing);
    TASFixtureTumbler(&fixture);
    TASFixtureSetEmpty(&fixture, 2, "platform-anded-reset");
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.quirks == kTASQuirkANDedReset);
    cells[0] = 0x40;
    TASFixtureSetCells(&fixture, 2, "platform-lineout-mute", cells, 1);
    cells[0] = 0x41;
    TASFixtureSetCells(&fixture, 2, "platform-lineout-detect", cells, 1);
    CHECK(parse(&fixture, &config) == kTASStatusUnsupported);
}

static void test_unknown_model_complete_known_incomplete(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASFixtureTumbler(&fixture);
    TASFixtureSetString(&fixture, 2, "model", "FutureMac99,1");
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(strcmp(config.model, "FutureMac99,1") == 0);
    TASFixtureTumbler(&fixture);
    TASFixtureRemove(&fixture, 3, "reg");
    CHECK(parse(&fixture, &config) == kTASStatusMissing);
}

static void test_overflow_and_exact_lengths(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    unsigned long cells[6];
    TASFixtureTumbler(&fixture);
    cells[0] = 0xfffffff0UL; cells[1] = 0x20;
    cells[2] = 0x08000; cells[3] = 0x100;
    cells[4] = 0x08100; cells[5] = 0x100;
    TASFixtureSetCells(&fixture, 7, "reg", cells, 6);
    CHECK(parse(&fixture, &config) == kTASStatusOverflow);
    TASFixtureTumbler(&fixture);
    TASFixtureSetString(&fixture, 2, "compatible", "tumbler");
    fixture.properties[0].length = 7;
    CHECK(parse(&fixture, &config) == kTASStatusMalformed);
}

static void test_failure_does_not_publish_partial_config(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASMachineConfig before;
    TASFixtureTumbler(&fixture);
    memset(&config, 0xa5, sizeof(config));
    before = config;
    TASFixtureRemove(&fixture, 7, "reg");
    CHECK(parse(&fixture, &config) == kTASStatusMissing);
    CHECK(memcmp(&config, &before, sizeof(config)) == 0);
}

int main(void)
{
    test_tumbler_complete();
    test_snapper_and_direct_address();
    test_interrupt_alias_and_old_codec_fallback();
    test_i2c_port_select_alias();
    test_old_gpio_names();
    test_exact_compatible();
    test_malformed_resources();
    test_phandle_failures();
    test_addresses();
    test_incomplete_route_and_quirk();
    test_unknown_model_complete_known_incomplete();
    test_overflow_and_exact_lengths();
    test_failure_does_not_publish_partial_config();
    if (failures != 0) {
        fprintf(stderr, "%d TAS audio checks failed\n", failures);
        return 1;
    }
    puts("TAS audio parser checks passed");
    return 0;
}
