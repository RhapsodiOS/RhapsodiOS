#define _CRT_SECURE_NO_WARNINGS 1

#include "tas_fixtures.h"
#include "TASCodec.h"

#include <stdio.h>
#include <string.h>

#define CHECK(expression) do { if (!(expression)) { \
    fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, \
        #expression); ++failures; } } while (0)

static int failures;

#define CODEC_EVENT_LIMIT 128

typedef struct {
    int kind;
    unsigned long value;
    unsigned char reg;
    unsigned long length;
    unsigned char data[TAS_CODEC_REGISTER_BYTES];
} CodecEvent;

typedef struct {
    CodecEvent events[CODEC_EVENT_LIMIT];
    unsigned long eventCount;
    unsigned long writeCount;
    unsigned long failWrite;
    unsigned long partialLength;
    unsigned long requiredMilliseconds;
    unsigned long failMuteCount;
} CodecMock;

static void codec_event(CodecMock *mock, int kind, unsigned long value)
{
    CodecEvent *event;
    event = &mock->events[mock->eventCount++];
    memset(event, 0, sizeof(*event));
    event->kind = kind;
    event->value = value;
}

static TASStatus codec_write(void *context, unsigned char reg,
    const unsigned char *bytes, unsigned long length,
    unsigned long deadlineMilliseconds, unsigned long *written)
{
    CodecMock *mock;
    CodecEvent *event;
    unsigned long ordinal;
    mock = (CodecMock *)context;
    ordinal = mock->writeCount++;
    event = &mock->events[mock->eventCount++];
    memset(event, 0, sizeof(*event));
    event->kind = 3;
    event->reg = reg;
    event->length = length;
    memcpy(event->data, bytes, (size_t)length);
    if (mock->requiredMilliseconds > deadlineMilliseconds) {
        *written = 0;
        return kTASStatusTimeout;
    }
    if (ordinal == mock->failWrite) {
        *written = mock->partialLength;
        return kTASStatusOK;
    }
    *written = length;
    return kTASStatusOK;
}

static TASStatus codec_reset(void *context, int asserted)
{
    codec_event((CodecMock *)context, 1, (unsigned long)asserted);
    return kTASStatusOK;
}

static TASStatus codec_delay(void *context, unsigned long microseconds)
{
    codec_event((CodecMock *)context, 2, microseconds);
    return kTASStatusOK;
}

static void codec_fail_mute(void *context)
{
    CodecMock *mock;
    mock = (CodecMock *)context;
    ++mock->failMuteCount;
    codec_event(mock, 4, 0UL);
}

static void codec_mock_init(CodecMock *mock)
{
    memset(mock, 0, sizeof(*mock));
    mock->failWrite = ~0UL;
}

static TASCodecCallbacks codec_callbacks(CodecMock *mock)
{
    TASCodecCallbacks callbacks;
    callbacks.context = mock;
    callbacks.writeRegister = codec_write;
    callbacks.setReset = codec_reset;
    callbacks.delayMicroseconds = codec_delay;
    callbacks.failMute = codec_fail_mute;
    return callbacks;
}

static unsigned long codec_count_write(const CodecMock *mock,
    unsigned char reg)
{
    unsigned long index;
    unsigned long count;
    count = 0;
    for (index = 0; index < mock->eventCount; ++index) {
        if (mock->events[index].kind == 3 && mock->events[index].reg == reg)
            ++count;
    }
    return count;
}

static const unsigned char tas3001WriteOrder[] = {
    0x01,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,
    0x13,0x14,0x15,0x16,0x17,0x18,0x01,
    0x02,0x04,0x05,0x06,0x07,0x08,0x01
};

static const unsigned char tas3004WriteOrder[] = {
    0x01,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,0x10,0x21,
    0x13,0x14,0x15,0x16,0x17,0x18,0x19,0x22,0x01,
    0x02,0x04,0x05,0x06,0x07,0x08,0x23,0x24,0x40,0x43,0x01
};

static void codec_check_write_order(const CodecMock *mock,
    const unsigned char *order, unsigned long count)
{
    unsigned long event;
    unsigned long write;
    write = 0;
    for (event = 0; event < mock->eventCount; ++event) {
        if (mock->events[event].kind == 3) {
            CHECK(write < count);
            if (write < count)
                CHECK(mock->events[event].reg == order[write]);
            ++write;
        }
    }
    CHECK(write == count);
}

static TASStatus parse(TASFixture *fixture, TASMachineConfig *config)
{
    TASPropertyReader reader;
    reader = TASFixtureReader(fixture);
    return TASParseMachineConfig(&reader, config);
}

static TASStatus parse_four_callbacks(TASFixture *fixture,
    TASMachineConfig *config)
{
    TASPropertyReader reader;
    reader = TASFixtureReader(fixture);
    reader.findNodes = 0;
    reader.findPropertyNodes = 0;
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

static void test_four_callback_reader_contract(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASFixtureTumbler(&fixture);
    CHECK(parse_four_callbacks(&fixture, &config) == kTASStatusOK);
    CHECK(config.codecKind == kTASCodecTAS3001C);
    TASFixtureSnapper(&fixture);
    CHECK(parse_four_callbacks(&fixture, &config) == kTASStatusOK);
    CHECK(config.codecKind == kTASCodecTAS3004);
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

static void test_bus_and_chip_codec_refs_are_reconciled(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASMachineConfig before;
    unsigned long cells[2];
    TASFixtureSnapper(&fixture);
    cells[0] = 0x30;
    TASFixtureSetCells(&fixture, kFixtureSoundChip,
        "platform-tas-codec-ref", cells, 1);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    TASFixtureRemove(&fixture, kFixtureSoundBus,
        "platform-tas-codec-ref");
    CHECK(parse(&fixture, &config) == kTASStatusOK);

    memset(&config, 0xa5, sizeof(config));
    before = config;
    TASFixtureSnapper(&fixture);
    cells[0] = 0x43;
    TASFixtureSetCells(&fixture, kFixtureSoundChip,
        "platform-tas-codec-ref", cells, 1);
    CHECK(parse(&fixture, &config) == kTASStatusConflict);
    CHECK(memcmp(&config, &before, sizeof(config)) == 0);

    TASFixtureSnapper(&fixture);
    cells[0] = 0x30; cells[1] = 0x30;
    TASFixtureSetCells(&fixture, kFixtureSoundChip,
        "platform-tas-codec-ref", cells, 2);
    config = before;
    CHECK(parse(&fixture, &config) == kTASStatusMalformed);
    CHECK(memcmp(&config, &before, sizeof(config)) == 0);

    TASFixtureSnapper(&fixture);
    cells[0] = 0x77;
    TASFixtureSetCells(&fixture, kFixtureSoundChip,
        "platform-tas-codec-ref", cells, 1);
    config = before;
    CHECK(parse(&fixture, &config) == kTASStatusUnresolved);
    CHECK(memcmp(&config, &before, sizeof(config)) == 0);
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

static void test_old_endpoint_identity_is_topological(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASFixtureTumbler(&fixture);
    TASFixtureRemove(&fixture, kFixtureCodec, "compatible");
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.codecKind == kTASCodecTAS3001C);
    TASFixtureSetString(&fixture, kFixtureCodec, "compatible", "snapper");
    CHECK(parse(&fixture, &config) == kTASStatusConflict);
    TASFixtureSetString(&fixture, kFixtureSoundChip, "compatible",
        "AOAKeylargo");
    TASFixtureRemove(&fixture, kFixtureCodec, "compatible");
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

static void set_codec_address(TASFixture *fixture, unsigned long address)
{
    unsigned long cells[1];
    TASFixtureRemove(fixture, kFixtureCodec, "reg");
    TASFixtureRemove(fixture, kFixtureCodec, "i2c-address");
    cells[0] = address;
    TASFixtureSetCells(fixture, kFixtureCodec, "reg", cells, 1);
}

static void test_codec_specific_address_matrix(void)
{
    static const unsigned long values[] = {
        0x68, 0x34, 0x6a, 0x35, 0x36, 0x50
    };
    static const int tumblerOK[] = { 1, 1, 0, 0, 0, 0 };
    static const int snapperOK[] = { 0, 0, 1, 1, 0, 0 };
    TASFixture fixture;
    TASMachineConfig config;
    unsigned long index;
    TASStatus status;
    for (index = 0; index < sizeof(values) / sizeof(values[0]); ++index) {
        TASFixtureTumbler(&fixture);
        set_codec_address(&fixture, values[index]);
        status = parse(&fixture, &config);
        CHECK((status == kTASStatusOK) == tumblerOK[index]);
        TASFixtureSnapper(&fixture);
        set_codec_address(&fixture, values[index]);
        status = parse(&fixture, &config);
        CHECK((status == kTASStatusOK) == snapperOK[index]);
    }
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

static void test_duplicate_interrupt_aliases(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    unsigned long cells[6];
    TASFixtureTumbler(&fixture);
    cells[0] = 30; cells[1] = 1; cells[2] = 24;
    cells[3] = 2; cells[4] = 25; cells[5] = 3;
    TASFixtureSetCells(&fixture, kFixtureI2S, "AAPL,interrupts", cells, 6);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    cells[4] = 26;
    TASFixtureSetCells(&fixture, kFixtureI2S, "AAPL,interrupts", cells, 6);
    CHECK(parse(&fixture, &config) == kTASStatusConflict);
}

static void test_interrupt_numbers_are_distinct_and_nonzero(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    unsigned long cells[6];
    TASFixtureTumbler(&fixture);
    cells[0] = 0; cells[1] = 1; cells[2] = 24;
    cells[3] = 2; cells[4] = 25; cells[5] = 3;
    TASFixtureSetCells(&fixture, kFixtureI2S, "interrupts", cells, 6);
    CHECK(parse(&fixture, &config) == kTASStatusMalformed);
    cells[0] = 24;
    TASFixtureSetCells(&fixture, kFixtureI2S, "interrupts", cells, 6);
    CHECK(parse(&fixture, &config) == kTASStatusConflict);
}

static void test_gpio_role_aliases_and_ownership(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    unsigned long cells[1];
    TASFixtureSnapper(&fixture);
    cells[0] = 0x42;
    TASFixtureSetCells(&fixture, kFixtureSoundChip, "platform-hw-reset",
        cells, 1);
    TASFixtureSetCells(&fixture, kFixtureSoundBus,
        "platform-codec-input-data-mu", cells, 1);
    cells[0] = 0x44;
    TASFixtureSetCells(&fixture, kFixtureSoundBus,
        "platform-codec-input-data-mu", cells, 1);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    cells[0] = 0x43;
    TASFixtureSetCells(&fixture, kFixtureSoundChip, "platform-hw-reset",
        cells, 1);
    CHECK(parse(&fixture, &config) == kTASStatusConflict);
    TASFixtureSnapper(&fixture);
    cells[0] = 0x43;
    TASFixtureSetCells(&fixture, kFixtureSoundBus,
        "platform-codec-input-data-mu", cells, 1);
    CHECK(parse(&fixture, &config) == kTASStatusConflict);
    TASFixtureSnapper(&fixture);
    TASFixtureAddForeignReset(&fixture);
    CHECK(parse(&fixture, &config) == kTASStatusNotMatched);
}

static void test_ranges_do_not_overlap(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    unsigned long cells[6];
    TASFixtureTumbler(&fixture);
    cells[0] = 0x10000; cells[1] = 0x1000;
    cells[2] = 0x10800; cells[3] = 0x100;
    cells[4] = 0x08100; cells[5] = 0x100;
    TASFixtureSetCells(&fixture, kFixtureI2S, "reg", cells, 6);
    CHECK(parse(&fixture, &config) == kTASStatusConflict);
    cells[2] = 0x08000; cells[3] = 0x200;
    cells[4] = 0x08100; cells[5] = 0x100;
    TASFixtureSetCells(&fixture, kFixtureI2S, "reg", cells, 6);
    CHECK(parse(&fixture, &config) == kTASStatusConflict);
}

static void test_hostile_readers_are_bounded_and_atomic(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASMachineConfig before;
    TASPropertyReader reader;
    TASFixtureTumbler(&fixture);
    memset(&config, 0xa5, sizeof(config));
    before = config;
    reader = TASFixtureReader(&fixture);
    reader.findNodes = 0;
    reader.findPropertyNodes = 0;
    fixture.stuckCursor = 1;
    CHECK(TASParseMachineConfig(&reader, &config) != kTASStatusOK);
    CHECK(memcmp(&config, &before, sizeof(config)) == 0);
    TASFixtureTumbler(&fixture);
    TASFixtureAddJunkNodes(&fixture, 65);
    reader = TASFixtureReader(&fixture);
    reader.findNodes = 0;
    reader.findPropertyNodes = 0;
    config = before;
    CHECK(TASParseMachineConfig(&reader, &config) != kTASStatusOK);
    CHECK(memcmp(&config, &before, sizeof(config)) == 0);
    TASFixtureTumbler(&fixture);
    fixture.acceleratorOvercount = 1;
    reader = TASFixtureReader(&fixture);
    config = before;
    CHECK(TASParseMachineConfig(&reader, &config) != kTASStatusOK);
    CHECK(memcmp(&config, &before, sizeof(config)) == 0);
    TASFixtureTumbler(&fixture);
    fixture.nullSuccessNode = kFixtureI2S;
    fixture.nullSuccessProperty = "reg";
    reader = TASFixtureReader(&fixture);
    config = before;
    CHECK(TASParseMachineConfig(&reader, &config) != kTASStatusOK);
    CHECK(memcmp(&config, &before, sizeof(config)) == 0);
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
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.routes[kTASRouteHeadphone].present == 0);
}

static void remove_headphone_detect(TASFixture *fixture)
{
    TASFixtureRemove(fixture, kFixtureSoundBus,
        "platform-headphone-detect");
    TASFixtureRemove(fixture, kFixtureHeadphoneDetect, "audio-gpio");
}

static void remove_headphone_mute(TASFixture *fixture)
{
    TASFixtureRemove(fixture, kFixtureSoundBus, "platform-headphone-mute");
    TASFixtureRemove(fixture, kFixtureHeadphoneMute, "audio-gpio");
}

static void test_anded_reset_alternative_resources(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASFixtureSnapper(&fixture);
    TASFixtureSetEmpty(&fixture, kFixtureSoundChip, "has-anded-reset");
    TASFixtureRemove(&fixture, kFixtureSoundBus, "platform-hw-reset");
    TASFixtureRemove(&fixture, kFixtureHardwareReset, "audio-gpio");
    remove_headphone_detect(&fixture);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.quirks == kTASQuirkANDedReset);
    CHECK(config.routes[kTASRouteHeadphone].present == 0);
    CHECK(config.routes[kTASRouteHeadphone].mute.offset == 0x70UL);
    remove_headphone_mute(&fixture);
    CHECK(parse(&fixture, &config) == kTASStatusMissing);
    TASFixtureSnapper(&fixture);
    TASFixtureRemove(&fixture, kFixtureSoundBus, "platform-hw-reset");
    TASFixtureRemove(&fixture, kFixtureHardwareReset, "audio-gpio");
    CHECK(parse(&fixture, &config) == kTASStatusMissing);
}

static int file_contains(const char *path, const char *text)
{
    FILE *file;
    char buffer[1024];
    size_t count;
    file = fopen(path, "rb");
    if (file == 0)
        return 0;
    count = fread(buffer, 1, sizeof(buffer) - 1U, file);
    fclose(file);
    buffer[count] = 0;
    return strstr(buffer, text) != 0;
}

static void test_table_and_legacy_matches_are_disjoint(void)
{
    CHECK(file_contains("../PPCTASAudio.drvproj/Default.table",
        "\"Matching\" = \"i2s\";"));
    CHECK(!file_contains("../PPCTASAudio.drvproj/Default.table", "awacs"));
    CHECK(!file_contains("../PPCTASAudio.drvproj/Default.table", "burgundy"));
    CHECK(file_contains("../../drvPPCAwacs/PPCAwacs.drvproj/Default.table",
        "awacs davbus"));
    CHECK(file_contains(
        "../../drvPPCBurgundy/PPCBurgundy.drvproj/Default.table",
        "burgundy davbus"));
    CHECK(file_contains("Makefile.host", ".PHONY: all test clean"));
}

static void test_non_tas_compatibles_never_match(void)
{
    static const char *values[] = {
        "awacs", "burgundy", "davbus", "tumbler-extra", "snapper-extra"
    };
    TASFixture fixture;
    TASMachineConfig config;
    unsigned long index;
    for (index = 0; index < sizeof(values) / sizeof(values[0]); ++index) {
        TASFixtureTumbler(&fixture);
        TASFixtureSetString(&fixture, kFixtureSoundChip, "compatible",
            values[index]);
        CHECK(parse(&fixture, &config) == kTASStatusNotMatched);
    }
    TASFixtureSnapper(&fixture);
    TASFixtureSetString(&fixture, kFixtureCodec, "compatible", "onyx");
    CHECK(parse(&fixture, &config) == kTASStatusNotMatched);
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

static void check_clock(const TASMachineConfig *config, unsigned long rate,
    unsigned long source, unsigned long mclkDivisor)
{
    TASI2SClock clock;
    memset(&clock, 0xa5, sizeof(clock));
    CHECK(TASSelectI2SClock(config, rate, &clock) == kTASStatusOK);
    CHECK(clock.rate == rate);
    CHECK(clock.sourceHz == source);
    CHECK(clock.mclkDivisor == mclkDivisor);
    CHECK(clock.sclkDivisor == 4UL);
    CHECK(clock.frameRatio == 64UL);
    CHECK(clock.dataWord == 0x02000200UL);
    CHECK(clock.codecSlotBits == 20UL);
    CHECK(clock.pcmBits == 16UL);
    CHECK(clock.channels == 2UL);
}

static void test_exact_i2s_clock_vectors_and_rate_policy(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASMachineConfig configBefore;
    TASI2SClock clock;
    TASI2SClock before;
    unsigned long rates[] = { 32000UL, 35280UL, 36000UL, 38400UL,
        44100UL, 48000UL, 35999UL, 38401UL };
    TASFixtureTumbler(&fixture);
    TASFixtureSetCells(&fixture, kFixtureSoundChip, "sample-rates", rates,
        sizeof(rates) / sizeof(rates[0]));
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.rateCount == 6UL);
    CHECK(config.rates[0] == 32000UL);
    CHECK(config.rates[1] == 35280UL);
    CHECK(config.rates[2] == 36000UL);
    CHECK(config.rates[3] == 38400UL);
    CHECK(config.rates[4] == 44100UL);
    CHECK(config.rates[5] == 48000UL);
    check_clock(&config, 32000UL, 49152000UL, 6UL);
    check_clock(&config, 35280UL, 45158400UL, 5UL);
    check_clock(&config, 36000UL, 18432000UL, 2UL);
    check_clock(&config, 38400UL, 49152000UL, 5UL);
    check_clock(&config, 44100UL, 45158400UL, 4UL);
    check_clock(&config, 48000UL, 49152000UL, 4UL);

    memset(&clock, 0xa5, sizeof(clock));
    before = clock;
    CHECK(TASSelectI2SClock(&config, 35999UL, &clock) ==
        kTASStatusUnsupported);
    CHECK(memcmp(&clock, &before, sizeof(clock)) == 0);
    CHECK(TASSelectI2SClock(&config, 38401UL, &clock) ==
        kTASStatusUnsupported);
    CHECK(memcmp(&clock, &before, sizeof(clock)) == 0);
    CHECK(TASSelectI2SClock(&config, 31999UL, &clock) ==
        kTASStatusUnsupported);
    CHECK(memcmp(&clock, &before, sizeof(clock)) == 0);
    CHECK(TASSelectI2SClock(&config, 0xffffffffUL, &clock) ==
        kTASStatusUnsupported);
    CHECK(memcmp(&clock, &before, sizeof(clock)) == 0);

    rates[0] = 44100UL; rates[1] = 35999UL; rates[2] = 36001UL;
    rates[3] = 35279UL; rates[4] = 35281UL; rates[5] = 38399UL;
    rates[6] = 38401UL;
    TASFixtureTumbler(&fixture);
    TASFixtureSetCells(&fixture, kFixtureSoundChip, "sample-rates", rates, 7);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.rateCount == 1UL && config.rates[0] == 44100UL);

    rates[0] = 44100UL; rates[1] = 44100UL; rates[2] = 48000UL;
    TASFixtureTumbler(&fixture);
    TASFixtureSetCells(&fixture, kFixtureSoundChip, "sample-rates", rates, 3);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(config.rateCount == 2UL);
    CHECK(config.rates[0] == 44100UL && config.rates[1] == 48000UL);
    before = clock;
    CHECK(TASSelectI2SClock(&config, 32000UL, &clock) ==
        kTASStatusUnsupported);
    CHECK(memcmp(&clock, &before, sizeof(clock)) == 0);
    config.rateCount = TAS_MAX_RATES + 1UL;
    CHECK(TASSelectI2SClock(&config, 44100UL, &clock) ==
        kTASStatusMalformed);
    CHECK(memcmp(&clock, &before, sizeof(clock)) == 0);

    rates[0] = 32000UL; rates[1] = 48000UL;
    TASFixtureTumbler(&fixture);
    TASFixtureSetCells(&fixture, kFixtureSoundChip, "sample-rates", rates, 2);
    memset(&config, 0xa5, sizeof(config));
    configBefore = config;
    CHECK(parse(&fixture, &config) == kTASStatusUnsupported);
    CHECK(memcmp(&config, &configBefore, sizeof(config)) == 0);

    TASFixtureTumbler(&fixture);
    TASFixtureSetEmpty(&fixture, kFixtureSoundChip, "sample-rates");
    CHECK(parse(&fixture, &config) == kTASStatusMalformed);
    CHECK(memcmp(&config, &configBefore, sizeof(config)) == 0);
}

static void test_shared_i2s_clock_acquisition(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASSharedClock state;
    TASSharedClock before;
    TASI2SClock clock;
    TASFixtureTumbler(&fixture);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    TASSharedClockInit(&state);
    CHECK(state.generation == 1UL && state.activeMask == 0UL);
    CHECK(TASAcquireI2SStream(&config, &state, kTASStreamOutput,
        44100UL, &clock) == kTASStatusOK);
    CHECK(state.activeRate == 44100UL && state.referenceCount == 1UL);
    CHECK(state.activeMask == kTASStreamMaskOutput);
    before = state;
    memset(&clock, 0xa5, sizeof(clock));
    {
        TASI2SClock clockBefore;
        clockBefore = clock;
        CHECK(TASAcquireI2SStream(&config, &state, kTASStreamInput,
            48000UL, &clock) == kTASStatusConflict);
        CHECK(memcmp(&state, &before, sizeof(state)) == 0);
        CHECK(memcmp(&clock, &clockBefore, sizeof(clock)) == 0);
    }
    CHECK(TASAcquireI2SStream(&config, &state, kTASStreamInput,
        44100UL, &clock) == kTASStatusOK);
    CHECK(state.activeRate == 44100UL && state.referenceCount == 2UL);
    CHECK(state.activeMask == (kTASStreamMaskOutput | kTASStreamMaskInput));
    before = state;
    state.referenceCount = 1UL;
    {
        TASSharedClock malformed;
        malformed = state;
        CHECK(TASReleaseI2SStream(&state, kTASStreamOutput) ==
            kTASStatusMalformed);
        CHECK(memcmp(&state, &malformed, sizeof(state)) == 0);
    }
    state = before;
    CHECK(TASReleaseI2SStream(&state, kTASStreamOutput) == kTASStatusOK);
    CHECK(state.activeRate == 44100UL && state.referenceCount == 1UL);
    CHECK(state.activeMask == kTASStreamMaskInput);
    before = state;
    CHECK(TASReleaseI2SStream(&state, kTASStreamOutput) ==
        kTASStatusConflict);
    CHECK(memcmp(&state, &before, sizeof(state)) == 0);
    CHECK(TASReleaseI2SStream(&state, kTASStreamInput) == kTASStatusOK);
    CHECK(state.activeRate == 0UL && state.referenceCount == 0UL);
    CHECK(state.activeMask == 0UL);
    CHECK(TASAcquireI2SStream(&config, &state, kTASStreamOutput,
        48000UL, &clock) == kTASStatusOK);
    CHECK(state.activeRate == 48000UL);

    before = state;
    state.activeMask = 4UL;
    {
        TASSharedClock malformed;
        TASI2SClock clockBefore;
        malformed = state;
        clockBefore = clock;
        CHECK(TASAcquireI2SStream(&config, &state, kTASStreamInput,
            48000UL, &clock) == kTASStatusMalformed);
        CHECK(memcmp(&state, &malformed, sizeof(state)) == 0);
        CHECK(memcmp(&clock, &clockBefore, sizeof(clock)) == 0);
        CHECK(TASReleaseI2SStream(&state, kTASStreamOutput) ==
            kTASStatusMalformed);
        CHECK(memcmp(&state, &malformed, sizeof(state)) == 0);
    }
    state = before;
    CHECK(TASReleaseI2SStream(&state, kTASStreamOutput) == kTASStatusOK);
}

static unsigned long count_plan_operation(const TASI2SRegisterPlan *plan,
    TASI2SPlanOperation operation)
{
    unsigned long index;
    unsigned long count;
    count = 0;
    for (index = 0; index < plan->count; ++index) {
        if (plan->steps[index].operation == operation)
            ++count;
    }
    return count;
}

static void test_i2s_transition_plans_and_stop_timeout(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASI2SClock clock;
    TASSharedClock state;
    TASI2STransition transition;
    TASI2SStoppedToken stopped;
    TASI2SStoppedToken stoppedBefore;
    TASI2SRegisterPlan plan;
    TASI2SRegisterPlan before;
    unsigned long noOpGeneration;
    TASFixtureTumbler(&fixture);
    CHECK(parse(&fixture, &config) == kTASStatusOK);
    CHECK(TASSelectI2SClock(&config, 44100UL, &clock) == kTASStatusOK);
    TASSharedClockInit(&state);
    CHECK(TASAcquireI2SStream(&config, &state, kTASStreamOutput,
        44100UL, &clock) == kTASStatusOK);
    CHECK(TASAcquireI2SStream(&config, &state, kTASStreamInput,
        44100UL, &clock) == kTASStatusOK);
    noOpGeneration = state.generation;
    CHECK(TASPrepareI2STransition(&config, &state, 44100UL,
        &transition) == kTASStatusOK);
    CHECK(transition.noOp == 1);
    CHECK(state.generation == noOpGeneration);
    CHECK(TASPrepareI2STransition(&config, &state, 48000UL,
        &transition) == kTASStatusConflict);
    CHECK(TASSetI2SStreamQuiesced(&state, kTASStreamOutput, 1) ==
        kTASStatusOK);
    CHECK(TASPrepareI2STransition(&config, &state, 48000UL,
        &transition) == kTASStatusConflict);
    CHECK(TASSetI2SStreamQuiesced(&state, kTASStreamInput, 1) ==
        kTASStatusOK);
    CHECK(TASPrepareI2STransition(&config, &state, 48000UL,
        &transition) == kTASStatusConflict);
    CHECK(TASSetI2SOutputsMuted(&state, 1) == kTASStatusOK);
    CHECK(TASPrepareI2STransition(&config, &state, 48000UL,
        &transition) == kTASStatusOK);
    CHECK(state.activeRate == 44100UL);
    CHECK(transition.clock.rate == 48000UL);
    CHECK(TASBuildI2SStopPlan(&state, &transition, 25UL, &plan) ==
        kTASStatusOK);
    CHECK(plan.count == 2UL);
    CHECK(plan.steps[0].operation == kTASI2SRequestClockStop);
    CHECK(plan.steps[0].value == 0UL);
    CHECK(plan.steps[1].operation == kTASI2SAwaitClockStopped);
    CHECK(plan.steps[1].value == 25UL);
    CHECK(count_plan_operation(&plan, kTASI2SConfigureFormat) == 0UL);
    CHECK(count_plan_operation(&plan, kTASI2SWriteDataWord) == 0UL);

    memset(&stopped, 0xa5, sizeof(stopped));
    stoppedBefore = stopped;
    CHECK(TASObserveI2SClockStopped(&state, &transition, 0, &stopped) ==
        kTASStatusTimeout);
    CHECK(memcmp(&stopped, &stoppedBefore, sizeof(stopped)) == 0);
    memset(&plan, 0xa5, sizeof(plan));
    before = plan;
    CHECK(TASBuildI2SFormatPlan(&state, &stopped, &plan) ==
        kTASStatusMalformed);
    CHECK(memcmp(&plan, &before, sizeof(plan)) == 0);
    CHECK(TASObserveI2SClockStopped(&state, &transition, 1, &stopped) ==
        kTASStatusOK);
    CHECK(TASSetI2SOutputsMuted(&state, 0) == kTASStatusOK);
    CHECK(TASBuildI2SFormatPlan(&state, &stopped, &plan) ==
        kTASStatusConflict);
    CHECK(memcmp(&plan, &before, sizeof(plan)) == 0);

    CHECK(TASSetI2SOutputsMuted(&state, 1) == kTASStatusOK);
    CHECK(TASPrepareI2STransition(&config, &state, 48000UL,
        &transition) == kTASStatusOK);
    CHECK(TASObserveI2SClockStopped(&state, &transition, 1, &stopped) ==
        kTASStatusOK);
    CHECK(TASBuildI2SFormatPlan(&state, &stopped, &plan) == kTASStatusOK);
    CHECK(plan.count == 5UL);
    CHECK(plan.steps[0].operation == kTASI2SSetCellClockHeld);
    CHECK(plan.steps[1].operation == kTASI2SConfigureFormat);
    CHECK(plan.steps[1].sourceHz == 49152000UL);
    CHECK(plan.steps[1].mclkDivisor == 4UL);
    CHECK(plan.steps[1].sclkDivisor == 4UL);
    CHECK(plan.steps[1].frameRatio == 64UL);
    CHECK(plan.steps[1].codecSlotBits == 20UL);
    CHECK(plan.steps[1].pcmBits == 16UL);
    CHECK(plan.steps[1].channels == 2UL);
    CHECK(plan.steps[2].operation == kTASI2SWriteDataWord);
    CHECK(plan.steps[2].value == 0x02000200UL);
    CHECK(plan.steps[3].operation == kTASI2SBarrier);
    CHECK(plan.steps[4].operation == kTASI2SSetCellRunning);
    CHECK(state.activeRate == 44100UL);
}

static void prepare_stopped(const TASMachineConfig *config,
    const TASSharedClock *state, unsigned long rate,
    TASI2SStoppedToken *stopped)
{
    TASI2STransition transition;
    CHECK(TASPrepareI2STransition(config, state, rate, &transition) ==
        kTASStatusOK);
    CHECK(TASObserveI2SClockStopped(state, &transition, 1, stopped) ==
        kTASStatusOK);
}

static void test_i2s_transition_generation_boundaries(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASSharedClock state;
    TASSharedClock before;
    TASI2SClock clock;
    TASI2SClock clockBefore;
    TASI2STransition transition;
    TASI2STransition transitionBefore;
    TASI2SStoppedToken stopped;
    TASI2SStoppedToken stoppedBefore;
    TASSharedClock overflowState;
    TASSharedClock overflowStateBefore;
    TASI2SStoppedToken overflowStopped;
    TASI2SStoppedToken overflowStoppedBefore;
    TASI2SRegisterPlan plan;
    TASFixtureTumbler(&fixture);
    CHECK(parse(&fixture, &config) == kTASStatusOK);

    TASSharedClockInit(&state);
    state.generation = ~0UL;
    before = state;
    memset(&clock, 0xa5, sizeof(clock));
    clockBefore = clock;
    CHECK(TASAcquireI2SStream(&config, &state, kTASStreamOutput,
        44100UL, &clock) == kTASStatusOverflow);
    CHECK(memcmp(&state, &before, sizeof(state)) == 0);
    CHECK(memcmp(&clock, &clockBefore, sizeof(clock)) == 0);

    TASSharedClockInit(&state);
    CHECK(TASAcquireI2SStream(&config, &state, kTASStreamOutput,
        44100UL, &clock) == kTASStatusOK);
    state.generation = ~0UL;
    before = state;
    CHECK(TASReleaseI2SStream(&state, kTASStreamOutput) ==
        kTASStatusOverflow);
    CHECK(memcmp(&state, &before, sizeof(state)) == 0);
    CHECK(TASSetI2SStreamQuiesced(&state, kTASStreamOutput, 0) ==
        kTASStatusOK);
    CHECK(memcmp(&state, &before, sizeof(state)) == 0);
    CHECK(TASSetI2SStreamQuiesced(&state, kTASStreamOutput, 1) ==
        kTASStatusOverflow);
    CHECK(memcmp(&state, &before, sizeof(state)) == 0);
    CHECK(TASSetI2SOutputsMuted(&state, 0) == kTASStatusOK);
    CHECK(memcmp(&state, &before, sizeof(state)) == 0);
    CHECK(TASSetI2SOutputsMuted(&state, 1) == kTASStatusOverflow);
    CHECK(memcmp(&state, &before, sizeof(state)) == 0);
    memset(&transition, 0xa5, sizeof(transition));
    CHECK(TASPrepareI2STransition(&config, &state, 44100UL,
        &transition) == kTASStatusOK);
    CHECK(transition.noOp == 1);
    CHECK(memcmp(&state, &before, sizeof(state)) == 0);
    CHECK(TASBuildI2SStopPlan(&state, &transition, 25UL, &plan) ==
        kTASStatusOK);
    CHECK(plan.count == 0UL);
    memset(&stopped, 0xa5, sizeof(stopped));
    stoppedBefore = stopped;
    CHECK(TASObserveI2SClockStopped(&state, &transition, 1, &stopped) ==
        kTASStatusMalformed);
    CHECK(memcmp(&stopped, &stoppedBefore, sizeof(stopped)) == 0);
    stopped.transition = transition;
    stopped.observedStopped = 1;
    CHECK(TASBuildI2SFormatPlan(&state, &stopped, &plan) == kTASStatusOK);
    CHECK(plan.count == 0UL);
    stoppedBefore = stopped;
    CHECK(TASCommitI2STransition(&state, &stopped) ==
        kTASStatusMalformed);
    CHECK(memcmp(&state, &before, sizeof(state)) == 0);
    CHECK(memcmp(&stopped, &stoppedBefore, sizeof(stopped)) == 0);
    memset(&transition, 0xa5, sizeof(transition));
    transitionBefore = transition;
    CHECK(TASPrepareI2STransition(&config, &state, 48000UL,
        &transition) == kTASStatusOverflow);
    CHECK(memcmp(&transition, &transitionBefore, sizeof(transition)) == 0);

    state.generation = ~0UL - 1UL;
    state.quiescedMask = state.activeMask;
    state.outputsMuted = 1;
    CHECK(TASPrepareI2STransition(&config, &state, 48000UL,
        &transition) == kTASStatusOK);
    CHECK(TASBuildI2SStopPlan(&state, &transition, 25UL, &plan) ==
        kTASStatusOK);
    CHECK(TASObserveI2SClockStopped(&state, &transition, 1, &stopped) ==
        kTASStatusOK);
    CHECK(TASBuildI2SFormatPlan(&state, &stopped, &plan) == kTASStatusOK);
    overflowState = state;
    overflowStopped = stopped;
    overflowState.generation = ~0UL;
    overflowStopped.transition.generation = ~0UL;
    overflowStateBefore = overflowState;
    overflowStoppedBefore = overflowStopped;
    CHECK(TASCommitI2STransition(&overflowState, &overflowStopped) ==
        kTASStatusOverflow);
    CHECK(memcmp(&overflowState, &overflowStateBefore,
        sizeof(overflowState)) == 0);
    CHECK(memcmp(&overflowStopped, &overflowStoppedBefore,
        sizeof(overflowStopped)) == 0);
    CHECK(TASCommitI2STransition(&state, &stopped) == kTASStatusOK);
    CHECK(state.activeRate == 48000UL && state.generation == ~0UL);
    CHECK(stopped.observedStopped == 0);
    before = state;
    stoppedBefore = stopped;
    CHECK(TASCommitI2STransition(&state, &stopped) ==
        kTASStatusMalformed);
    CHECK(memcmp(&state, &before, sizeof(state)) == 0);
    CHECK(memcmp(&stopped, &stoppedBefore, sizeof(stopped)) == 0);
    CHECK(TASBuildI2SFormatPlan(&state, &stopped, &plan) ==
        kTASStatusMalformed);
}

static void test_i2s_tokens_stale_after_shared_state_mutations(void)
{
    TASFixture fixture;
    TASMachineConfig config;
    TASSharedClock state;
    TASI2SClock clock;
    TASI2SStoppedToken stopped;
    TASI2SRegisterPlan plan;
    TASFixtureTumbler(&fixture);
    CHECK(parse(&fixture, &config) == kTASStatusOK);

    TASSharedClockInit(&state);
    prepare_stopped(&config, &state, 44100UL, &stopped);
    CHECK(TASAcquireI2SStream(&config, &state, kTASStreamOutput,
        44100UL, &clock) == kTASStatusOK);
    CHECK(TASBuildI2SFormatPlan(&state, &stopped, &plan) ==
        kTASStatusConflict);

    CHECK(TASSetI2SStreamQuiesced(&state, kTASStreamOutput, 1) ==
        kTASStatusOK);
    CHECK(TASSetI2SOutputsMuted(&state, 1) == kTASStatusOK);
    prepare_stopped(&config, &state, 48000UL, &stopped);
    CHECK(TASReleaseI2SStream(&state, kTASStreamOutput) == kTASStatusOK);
    CHECK(TASBuildI2SFormatPlan(&state, &stopped, &plan) ==
        kTASStatusConflict);

    CHECK(TASAcquireI2SStream(&config, &state, kTASStreamOutput,
        44100UL, &clock) == kTASStatusOK);
    CHECK(TASSetI2SStreamQuiesced(&state, kTASStreamOutput, 1) ==
        kTASStatusOK);
    prepare_stopped(&config, &state, 48000UL, &stopped);
    CHECK(TASSetI2SStreamQuiesced(&state, kTASStreamOutput, 0) ==
        kTASStatusOK);
    CHECK(TASBuildI2SFormatPlan(&state, &stopped, &plan) ==
        kTASStatusConflict);

    CHECK(TASSetI2SStreamQuiesced(&state, kTASStreamOutput, 1) ==
        kTASStatusOK);
    prepare_stopped(&config, &state, 48000UL, &stopped);
    CHECK(TASSetI2SOutputsMuted(&state, 0) == kTASStatusOK);
    CHECK(TASBuildI2SFormatPlan(&state, &stopped, &plan) ==
        kTASStatusConflict);
}

static unsigned long expected_3001_width(unsigned long reg)
{
    if (reg == 0x01UL) return 1UL;
    if (reg == 0x02UL) return 2UL;
    if (reg == 0x04UL) return 6UL;
    if (reg == 0x05UL || reg == 0x06UL) return 1UL;
    if (reg == 0x07UL || reg == 0x08UL) return 3UL;
    if ((reg >= 0x0aUL && reg <= 0x0fUL) ||
        (reg >= 0x13UL && reg <= 0x18UL)) return 15UL;
    return 0UL;
}

static unsigned long expected_3004_width(unsigned long reg)
{
    if (reg == 0x01UL || reg == 0x05UL || reg == 0x06UL ||
        reg == 0x40UL || reg == 0x43UL) return 1UL;
    if (reg == 0x02UL || reg == 0x04UL) return 6UL;
    if (reg == 0x07UL || reg == 0x08UL) return 9UL;
    if ((reg >= 0x0aUL && reg <= 0x10UL) ||
        (reg >= 0x13UL && reg <= 0x19UL) || reg == 0x21UL ||
        reg == 0x22UL) return 15UL;
    if (reg == 0x23UL || reg == 0x24UL) return 3UL;
    return 0UL;
}

static void test_codec_register_schemas(void)
{
    const TASCodecOps *tumbler;
    const TASCodecOps *snapper;
    unsigned long reg;
    unsigned char bytes[6];
    TASCodec codec;
    TASCodecCallbacks callbacks;
    CodecMock mock;
    tumbler = TAS3001CCodecOps();
    snapper = TAS3004CodecOps();
    CHECK(strcmp(tumbler->name, "TAS3001C") == 0 && tumbler->supportsDRC);
    CHECK(strcmp(snapper->name, "TAS3004") == 0 && snapper->supportsDRC);
    for (reg = 0; reg <= 0x43UL; ++reg) {
        CHECK(TASCodecRegisterWidth(tumbler, (unsigned char)reg) ==
            expected_3001_width(reg));
        CHECK(TASCodecRegisterWidth(snapper, (unsigned char)reg) ==
            expected_3004_width(reg));
    }
    codec_mock_init(&mock);
    callbacks = codec_callbacks(&mock);
    CHECK(TASCodecBind(&codec, snapper, &callbacks) == kTASStatusOK);
    memset(bytes, 0, sizeof(bytes));
    CHECK(TASCodecWrite(&codec, 0x02, bytes, 5UL, 200UL) ==
        kTASStatusMalformed);
    CHECK(TASCodecWrite(&codec, 0x02, bytes, 6UL, 200UL) == kTASStatusOK);
    CHECK(TASCodecWrite(&codec, 0x29, bytes, 6UL, 200UL) ==
        kTASStatusUnsupported);
}

static void check_neutral_biquad(const CodecEvent *event)
{
    unsigned long index;
    CHECK(event->length == 15UL);
    CHECK(event->data[0] == 0x10);
    for (index = 1; index < 15UL; ++index)
        CHECK(event->data[index] == 0);
}

static void test_codec_golden_initialization(void)
{
    const TASCodecOps *ops[2];
    unsigned long backend;
    unsigned long event;
    TASCodec codec;
    TASCodecCallbacks callbacks;
    CodecMock mock;
    ops[0] = TAS3001CCodecOps();
    ops[1] = TAS3004CodecOps();
    for (backend = 0; backend < 2UL; ++backend) {
        codec_mock_init(&mock);
        callbacks = codec_callbacks(&mock);
        CHECK(TASCodecBind(&codec, ops[backend], &callbacks) ==
            kTASStatusOK);
        CHECK(TASCodecInitialize(&codec, 0, 200UL) ==
            kTASStatusMalformed);
        CHECK(mock.eventCount == 0UL);
        CHECK(TASCodecInitialize(&codec, 1, 200UL) == kTASStatusOK);
        CHECK(codec.hardwareValid && codec.shadowComplete);
        CHECK(codec_count_write(&mock, 0x01) == 3UL);
        if (backend == 0) {
            codec_check_write_order(&mock, tas3001WriteOrder,
                sizeof(tas3001WriteOrder));
            CHECK(mock.events[0].kind == 1 && mock.events[0].value == 1UL);
            CHECK(mock.events[1].kind == 2 && mock.events[1].value >= 2UL);
            CHECK(mock.events[2].kind == 1 && mock.events[2].value == 0UL);
            CHECK(mock.events[3].kind == 2 && mock.events[3].value >= 5000UL);
            for (event = 0x0aUL; event <= 0x0fUL; ++event)
                CHECK(codec_count_write(&mock, (unsigned char)event) == 1UL);
            for (event = 0x13UL; event <= 0x18UL; ++event)
                CHECK(codec_count_write(&mock, (unsigned char)event) == 1UL);
        } else {
            codec_check_write_order(&mock, tas3004WriteOrder,
                sizeof(tas3004WriteOrder));
            CHECK(mock.events[0].kind == 2 && mock.events[0].value >= 5000UL);
            CHECK(mock.events[1].kind == 1 && mock.events[1].value == 1UL);
            CHECK(mock.events[2].kind == 2 && mock.events[2].value >= 20000UL);
            CHECK(mock.events[3].kind == 1 && mock.events[3].value == 0UL);
            CHECK(mock.events[4].kind == 2 && mock.events[4].value >= 10000UL);
            for (event = 0x0aUL; event <= 0x10UL; ++event)
                CHECK(codec_count_write(&mock, (unsigned char)event) == 1UL);
            for (event = 0x13UL; event <= 0x19UL; ++event)
                CHECK(codec_count_write(&mock, (unsigned char)event) == 1UL);
            CHECK(codec_count_write(&mock, 0x21) == 1UL);
            CHECK(codec_count_write(&mock, 0x22) == 1UL);
            CHECK(codec.shadowLength[0x02] == 6UL);
            CHECK(codec.shadow[0x02][0] == 1);
        }
        for (event = 0; event < mock.eventCount; ++event) {
            if (mock.events[event].kind == 3 &&
                expected_3001_width(mock.events[event].reg) == 15UL)
                check_neutral_biquad(&mock.events[event]);
            if (mock.events[event].kind == 3 &&
                expected_3004_width(mock.events[event].reg) == 15UL)
                check_neutral_biquad(&mock.events[event]);
        }
        CHECK(codec.shadow[0x01][0] == 0x6a);
        CHECK(codec.shadowLength[0x04] == 6UL);
    }
}

static void test_codec_shadow_failures_and_restore(void)
{
    const TASCodecOps *ops[2];
    unsigned long backend;
    unsigned long ordinal;
    unsigned long partial;
    unsigned long event;
    unsigned long length;
    unsigned char failedReg;
    unsigned char previous[6];
    TASCodec codec;
    TASCodecCallbacks callbacks;
    CodecMock golden;
    CodecMock mock;
    ops[0] = TAS3001CCodecOps();
    ops[1] = TAS3004CodecOps();
    for (backend = 0; backend < 2UL; ++backend) {
        codec_mock_init(&golden);
        callbacks = codec_callbacks(&golden);
        CHECK(TASCodecBind(&codec, ops[backend], &callbacks) == kTASStatusOK);
        CHECK(TASCodecInitialize(&codec, 1, 200UL) == kTASStatusOK);
        for (ordinal = 0; ordinal < golden.writeCount; ++ordinal) {
            length = 0;
            failedReg = 0;
            {
                unsigned long seen;
                seen = 0;
                for (event = 0; event < golden.eventCount; ++event) {
                    if (golden.events[event].kind == 3) {
                        if (seen == ordinal) {
                            length = golden.events[event].length;
                            failedReg = golden.events[event].reg;
                            break;
                        }
                        ++seen;
                    }
                }
            }
            for (partial = 0; partial < length; ++partial) {
                codec_mock_init(&mock);
                mock.failWrite = ordinal;
                mock.partialLength = partial;
                callbacks = codec_callbacks(&mock);
                CHECK(TASCodecBind(&codec, ops[backend], &callbacks) ==
                    kTASStatusOK);
                CHECK(TASCodecInitialize(&codec, 1, 200UL) != kTASStatusOK);
                CHECK(!codec.hardwareValid && mock.failMuteCount == 1UL);
                CHECK(mock.writeCount == ordinal + 1UL);
                CHECK(failedReg != 0);
            }
        }

        codec_mock_init(&mock);
        callbacks = codec_callbacks(&mock);
        CHECK(TASCodecBind(&codec, ops[backend], &callbacks) == kTASStatusOK);
        CHECK(TASCodecInitialize(&codec, 1, 200UL) == kTASStatusOK);
        memcpy(previous, codec.shadow[0x04], 6);
        mock.failWrite = mock.writeCount;
        mock.partialLength = 3UL;
        CHECK(TASCodecSetVolume(&codec, 0x010000UL, 0x008000UL, 200UL) !=
            kTASStatusOK);
        CHECK(memcmp(previous, codec.shadow[0x04], 6) == 0);
        mock.failWrite = ~0UL;
        CHECK(TASCodecSetVolume(&codec, 0x010000UL, 0x008000UL, 200UL) ==
            kTASStatusOK);
        CHECK(codec.shadow[0x04][0] == 1 && codec.shadow[0x04][1] == 0 &&
            codec.shadow[0x04][2] == 0 && codec.shadow[0x04][3] == 0 &&
            codec.shadow[0x04][4] == 0x80 && codec.shadow[0x04][5] == 0);
        CHECK(TASCodecSetMute(&codec, 1, 200UL) == kTASStatusOK);
        for (event = 0; event < 6UL; ++event)
            CHECK(codec.shadow[0x04][event] == 0);
        codec_mock_init(&mock);
        codec.callbacks = codec_callbacks(&mock);
        codec.hardwareValid = 0;
        CHECK(TASCodecRestore(&codec, 200UL) == kTASStatusOK);
        CHECK(mock.writeCount == ops[backend]->restoreCount);
        codec_check_write_order(&mock, backend == 0 ? tas3001WriteOrder :
            tas3004WriteOrder, backend == 0 ? sizeof(tas3001WriteOrder) :
            sizeof(tas3004WriteOrder));
        CHECK(codec.hardwareValid);
    }
}

static void test_codec_clock_stretch_and_controls(void)
{
    TASCodec codec;
    TASCodecCallbacks callbacks;
    CodecMock mock;
    codec_mock_init(&mock);
    callbacks = codec_callbacks(&mock);
    CHECK(TASCodecBind(&codec, TAS3004CodecOps(), &callbacks) ==
        kTASStatusOK);
    CHECK(TASCodecInitialize(&codec, 1, 200UL) == kTASStatusOK);
    mock.requiredMilliseconds = 49UL;
    CHECK(TASCodecSetVolume(&codec, 0x010000UL, 0x010000UL, 200UL) ==
        kTASStatusOK);
    mock.requiredMilliseconds = 167UL;
    CHECK(TASCodecSetInputGain(&codec, 0x008000UL, 200UL) == kTASStatusOK);
    CHECK(TASCodecSetInputSource(&codec, kTASCodecInputAnalog, 200UL) ==
        kTASStatusOK);
    mock.requiredMilliseconds = 201UL;
    CHECK(TASCodecSetVolume(&codec, 0x010000UL, 0x010000UL, 200UL) ==
        kTASStatusTimeout);
    CHECK(!codec.hardwareValid && mock.failMuteCount == 1UL);

    codec_mock_init(&mock);
    callbacks = codec_callbacks(&mock);
    CHECK(TASCodecBind(&codec, TAS3001CCodecOps(), &callbacks) ==
        kTASStatusOK);
    CHECK(TASCodecInitialize(&codec, 1, 200UL) == kTASStatusOK);
    CHECK(TASCodecSetInputSource(&codec, kTASCodecInputAnalog, 200UL) ==
        kTASStatusUnsupported);
}

int main(void)
{
    test_tumbler_published_shape();
    test_snapper_primary_phandles_and_relative_gpio();
    test_discovers_roles_without_fixed_paths();
    test_rejects_non_sound_bus_role();
    test_four_callback_reader_contract();
    test_ref_is_required_for_aoakeylargo();
    test_bus_and_chip_codec_refs_are_reconciled();
    test_multiple_i2s_candidates_are_ambiguous();
    test_old_codec_fallback_parent_and_port();
    test_old_endpoint_identity_is_topological();
    test_i2c_port_child_and_alias();
    test_i2c_address_forms_and_conflict();
    test_codec_specific_address_matrix();
    test_interrupt_pairs_and_alias();
    test_duplicate_interrupt_aliases();
    test_interrupt_numbers_are_distinct_and_nonzero();
    test_gpio_role_aliases_and_ownership();
    test_ranges_do_not_overlap();
    test_hostile_readers_are_bounded_and_atomic();
    test_gpio_exact_lengths_and_locations();
    test_required_gpio_roles();
    test_routes_and_published_anded_reset();
    test_anded_reset_alternative_resources();
    test_table_and_legacy_matches_are_disjoint();
    test_non_tas_compatibles_never_match();
    test_resources_addresses_and_policy();
    test_config_is_atomic_on_new_errors();
    test_exact_i2s_clock_vectors_and_rate_policy();
    test_shared_i2s_clock_acquisition();
    test_i2s_transition_plans_and_stop_timeout();
    test_i2s_transition_generation_boundaries();
    test_i2s_tokens_stale_after_shared_state_mutations();
    test_codec_register_schemas();
    test_codec_golden_initialization();
    test_codec_shadow_failures_and_restore();
    test_codec_clock_stretch_and_controls();
    if (failures != 0) {
        fprintf(stderr, "%d TAS audio checks failed\n", failures);
        return 1;
    }
    puts("TAS audio parser checks passed");
    return 0;
}
