#define _CRT_SECURE_NO_WARNINGS 1

#include "tas_fixtures.h"
#include "TASCodec.h"
#include "PPCDBDMAAudio.h"

#include <stdio.h>
#include <stddef.h>
#include <string.h>

#define CHECK(expression) do { if (!(expression)) { \
    fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, \
        #expression); ++failures; } } while (0)

static int failures;

#define DMA_BUFFER_BYTES 70000UL

typedef struct {
    unsigned char bytes[PPC_DBDMA_MAX_RING_BYTES + 15UL];
    unsigned char scratch[PPC_DBDMA_MAX_RING_BYTES + 15UL];
} DMARingBytes;

typedef struct {
    const unsigned char *base;
    unsigned long length;
    unsigned long split;
    unsigned long firstPhysical;
    unsigned long secondPhysical;
    unsigned long calls;
    unsigned long failCall;
} DMATranslateMock;

typedef struct {
    unsigned long status[16];
    unsigned long statusCount;
    unsigned long statusIndex;
    unsigned long writes[16][2];
    unsigned long writeCount;
    unsigned long now;
    unsigned long tick;
    unsigned long timeCalls;
    unsigned long events[64];
    unsigned long eventCount;
    unsigned long failPublish;
    unsigned long failInvalidate;
    unsigned long failBarrier;
    unsigned long readAdvance;
    int publishedAckWasZero;
    void *lastAddress;
    unsigned long lastBytes;
} DMARegisterMock;

static unsigned char dmaBuffer[DMA_BUFFER_BYTES];

static PPCDBDMAStatus dma_translate(void *context, const void *address,
    unsigned long *physicalAddress, unsigned long *contiguousBytes)
{
    DMATranslateMock *mock;
    unsigned long offset;
    unsigned long available;
    mock = (DMATranslateMock *)context;
    ++mock->calls;
    if (mock->calls == mock->failCall)
        return kPPCDBDMAUnmappable;
    if ((const unsigned char *)address < mock->base)
        return kPPCDBDMAUnmappable;
    offset = (unsigned long)((const unsigned char *)address - mock->base);
    if (offset >= mock->length)
        return kPPCDBDMAUnmappable;
    if (offset < mock->split) {
        available = mock->split - offset;
        *physicalAddress = mock->firstPhysical + offset;
    } else {
        available = mock->length - offset;
        *physicalAddress = mock->secondPhysical + offset - mock->split;
    }
    *contiguousBytes = available;
    return kPPCDBDMAOK;
}

static unsigned long dma_read_register(void *context, unsigned long reg)
{
    DMARegisterMock *mock;
    mock = (DMARegisterMock *)context;
    mock->events[mock->eventCount++] = 4UL;
    mock->now += mock->readAdvance;
    if (reg != kPPCDBDMARegStatus || mock->statusIndex >= mock->statusCount)
        return 0UL;
    return mock->status[mock->statusIndex++];
}

static void dma_write_register(void *context, unsigned long reg,
    unsigned long value)
{
    DMARegisterMock *mock;
    mock = (DMARegisterMock *)context;
    mock->events[mock->eventCount++] = 3UL;
    if (mock->writeCount < 16UL) {
        mock->writes[mock->writeCount][0] = reg;
        mock->writes[mock->writeCount][1] = value;
    }
    ++mock->writeCount;
}

static unsigned long dma_now(void *context)
{
    DMARegisterMock *mock;
    unsigned long result;
    mock = (DMARegisterMock *)context;
    result = mock->now;
    mock->now += mock->tick;
    ++mock->timeCalls;
    return result;
}

static PPCDBDMAStatus dma_publish(void *context, void *address,
    unsigned long bytes)
{
    DMARegisterMock *mock;
    mock = (DMARegisterMock *)context;
    mock->events[mock->eventCount++] = 1UL;
    mock->lastAddress = address;
    mock->lastBytes = bytes;
    if (bytes == 4UL) {
        const unsigned char *value;
        value = (const unsigned char *)address;
        mock->publishedAckWasZero = value[0] == 0 && value[1] == 0 &&
            value[2] == 0 && value[3] == 0;
    }
    if (mock->failPublish != 0UL) {
        --mock->failPublish;
        if (mock->failPublish == 0UL)
            return kPPCDBDMACoherency;
    }
    return kPPCDBDMAOK;
}

static PPCDBDMAStatus dma_invalidate(void *context, void *address,
    unsigned long bytes)
{
    DMARegisterMock *mock;
    mock = (DMARegisterMock *)context;
    mock->events[mock->eventCount++] = 5UL;
    mock->lastAddress = address;
    mock->lastBytes = bytes;
    if (mock->failInvalidate != 0UL) {
        --mock->failInvalidate;
        if (mock->failInvalidate == 0UL)
            return kPPCDBDMACoherency;
    }
    return kPPCDBDMAOK;
}

static PPCDBDMAStatus dma_barrier(void *context)
{
    DMARegisterMock *mock;
    mock = (DMARegisterMock *)context;
    mock->events[mock->eventCount++] = 2UL;
    if (mock->failBarrier != 0UL) {
        --mock->failBarrier;
        if (mock->failBarrier == 0UL)
            return kPPCDBDMACoherency;
    }
    return kPPCDBDMAOK;
}

static void dma_translate_mock(DMATranslateMock *mock, unsigned long length,
    unsigned long split, unsigned long first, unsigned long second)
{
    memset(mock, 0, sizeof(*mock));
    mock->base = dmaBuffer;
    mock->length = length;
    mock->split = split;
    mock->firstPhysical = first;
    mock->secondPhysical = second;
    mock->failCall = ~0UL;
}

static PPCDBDMAStorage dma_storage(DMARingBytes *bytes,
    unsigned long physical)
{
    PPCDBDMAStorage storage;
    size_t address;
    address = (size_t)bytes->bytes;
    storage.logical = bytes->bytes + ((16U - (address & 15U)) & 15U);
    storage.physical = physical;
    storage.bytes = PPC_DBDMA_MAX_RING_BYTES;
    address = (size_t)bytes->scratch;
    storage.scratch = bytes->scratch + ((16U - (address & 15U)) & 15U);
    storage.scratchBytes = PPC_DBDMA_MAX_RING_BYTES;
    return storage;
}

static PPCDBDMAOps dma_ops(DMATranslateMock *translate,
    DMARegisterMock *registers)
{
    PPCDBDMAOps ops;
    memset(&ops, 0, sizeof(ops));
    ops.context = translate;
    ops.translate = dma_translate;
    if (registers != 0) {
        ops.registerContext = registers;
        ops.readRegister = dma_read_register;
        ops.writeRegister = dma_write_register;
        ops.now = dma_now;
        ops.coherencyContext = registers;
        ops.publish = dma_publish;
        ops.invalidate = dma_invalidate;
        ops.barrier = dma_barrier;
    }
    return ops;
}

static void dma_store_result(PPCDBDMARing *ring, unsigned long index,
    unsigned long status, unsigned long residual)
{
    unsigned long value;
    unsigned char *bytes;
    value = (status << 16) | residual;
    bytes = ring->descriptors + index * PPC_DBDMA_DESCRIPTOR_BYTES + 12UL;
    bytes[0] = (unsigned char)value;
    bytes[1] = (unsigned char)(value >> 8);
    bytes[2] = (unsigned char)(value >> 16);
    bytes[3] = (unsigned char)(value >> 24);
}

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
    unsigned long currentMilliseconds;
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
    if (mock->currentMilliseconds + mock->requiredMilliseconds >
        deadlineMilliseconds) {
        mock->currentMilliseconds = deadlineMilliseconds;
        *written = 0;
        return kTASStatusTimeout;
    }
    mock->currentMilliseconds += mock->requiredMilliseconds;
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

static TASStatus codec_delay(void *context, unsigned long microseconds,
    unsigned long deadlineMilliseconds)
{
    CodecMock *mock;
    unsigned long milliseconds;
    mock = (CodecMock *)context;
    milliseconds = (microseconds + 999UL) / 1000UL;
    codec_event(mock, 2, microseconds);
    if (mock->currentMilliseconds + milliseconds > deadlineMilliseconds) {
        mock->currentMilliseconds = deadlineMilliseconds;
        return kTASStatusTimeout;
    }
    mock->currentMilliseconds += milliseconds;
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
        CHECK(TASCodecSetMute(&codec, 0, 200UL) == kTASStatusOK);
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
        CHECK(codec.shadow[0x04][0] == 1 && codec.shadow[0x04][1] == 0 &&
            codec.shadow[0x04][2] == 0 && codec.shadow[0x04][3] == 0 &&
            codec.shadow[0x04][4] == 0x80 && codec.shadow[0x04][5] == 0);
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
    mock.requiredMilliseconds = 6UL;
    callbacks = codec_callbacks(&mock);
    CHECK(TASCodecBind(&codec, TAS3004CodecOps(), &callbacks) ==
        kTASStatusOK);
    CHECK(TASCodecInitialize(&codec, 1, 40UL) == kTASStatusTimeout);
    CHECK(mock.currentMilliseconds == 40UL && mock.writeCount == 1UL);
    CHECK(!codec.hardwareValid && mock.failMuteCount == 1UL);

    codec_mock_init(&mock);
    callbacks = codec_callbacks(&mock);
    CHECK(TASCodecBind(&codec, TAS3004CodecOps(), &callbacks) ==
        kTASStatusOK);
    CHECK(TASCodecInitialize(&codec, 1, 200UL) == kTASStatusOK);
    CHECK(TASCodecSetMute(&codec, 0, 200UL) == kTASStatusOK);
    mock.requiredMilliseconds = 49UL;
    CHECK(TASCodecSetVolume(&codec, 0x010000UL, 0x010000UL,
        mock.currentMilliseconds + 200UL) ==
        kTASStatusOK);
    mock.requiredMilliseconds = 167UL;
    CHECK(TASCodecSetVolume(&codec, 0x008000UL, 0x008000UL,
        mock.currentMilliseconds + 200UL) == kTASStatusOK);
    mock.requiredMilliseconds = 0UL;
    CHECK(TASCodecSetInputSource(&codec, kTASCodecInputAnalog,
        mock.currentMilliseconds + 200UL) ==
        kTASStatusOK);
    mock.requiredMilliseconds = 201UL;
    CHECK(TASCodecSetVolume(&codec, 0x010000UL, 0x010000UL,
        mock.currentMilliseconds + 200UL) ==
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

static void test_codec_restore_and_volume_state_are_atomic(void)
{
    const TASCodecOps *ops[2];
    unsigned long backend;
    unsigned long ordinal;
    unsigned long event;
    int sawMutedVolume;
    unsigned long writesBefore;
    unsigned long eventsBefore;
    unsigned char shadowBefore[TAS_CODEC_REGISTER_COUNT]
        [TAS_CODEC_REGISTER_BYTES];
    unsigned long lengthsBefore[TAS_CODEC_REGISTER_COUNT];
    TASCodec codec;
    TASCodec before;
    TASCodecCallbacks callbacks;
    CodecMock mock;
    ops[0] = TAS3001CCodecOps();
    ops[1] = TAS3004CodecOps();
    for (backend = 0; backend < 2UL; ++backend) {
        codec_mock_init(&mock);
        callbacks = codec_callbacks(&mock);
        CHECK(TASCodecBind(&codec, ops[backend], &callbacks) ==
            kTASStatusOK);
        before = codec;
        CHECK(TASCodecInitialize(&codec, 1, 0UL) == kTASStatusMalformed);
        CHECK(memcmp(&codec, &before, sizeof(codec)) == 0);
        CHECK(mock.writeCount == 0UL && mock.eventCount == 0UL);
        CHECK(TASCodecInitialize(&codec, 1, 200UL) == kTASStatusOK);
        CHECK(codec.muted == 1);
        CHECK(TASCodecSetVolume(&codec, 0x008000UL, 0x004000UL,
            mock.currentMilliseconds + 200UL) == kTASStatusOK);
        CHECK(mock.writeCount == ops[backend]->restoreCount);
        CHECK(codec.shadow[0x04][0] == 0 && codec.shadow[0x04][1] == 0x80 &&
            codec.shadow[0x04][2] == 0 && codec.shadow[0x04][3] == 0 &&
            codec.shadow[0x04][4] == 0x40 && codec.shadow[0x04][5] == 0);
        CHECK(TASCodecSetMute(&codec, 0,
            mock.currentMilliseconds + 200UL) == kTASStatusOK);
        CHECK(codec.muted == 0);
        CHECK(mock.events[mock.eventCount - 1UL].reg == 0x04);
        CHECK(memcmp(mock.events[mock.eventCount - 1UL].data,
            codec.shadow[0x04], 6) == 0);
        CHECK(TASCodecSetMute(&codec, 1,
            mock.currentMilliseconds + 200UL) == kTASStatusOK);
        CHECK(codec.muted == 1);
        CHECK(mock.events[mock.eventCount - 1UL].reg == 0x04);
        for (event = 0UL; event < 6UL; ++event)
            CHECK(mock.events[mock.eventCount - 1UL].data[event] == 0);
        CHECK(codec.shadow[0x04][1] == 0x80 &&
            codec.shadow[0x04][4] == 0x40);
        CHECK(TASCodecSetInputGain(&codec, 0x002000UL,
            mock.currentMilliseconds + 200UL) == kTASStatusOK);
        CHECK(TASCodecSetInputSource(&codec, kTASCodecInputDigital2,
            mock.currentMilliseconds + 200UL) == kTASStatusOK);

        memcpy(shadowBefore, codec.shadow, sizeof(shadowBefore));
        memcpy(lengthsBefore, codec.shadowLength, sizeof(lengthsBefore));
        before = codec;
        for (ordinal = 0; ordinal < ops[backend]->restoreCount; ++ordinal) {
            codec_mock_init(&mock);
            mock.failWrite = ordinal;
            mock.partialLength = 0UL;
            CHECK(TASCodecRestore(&codec, 200UL) != kTASStatusOK);
            CHECK(!codec.hardwareValid && mock.failMuteCount == 1UL);
            CHECK(mock.writeCount == ordinal + 1UL);
            CHECK(memcmp(codec.shadow, shadowBefore,
                sizeof(shadowBefore)) == 0);
            CHECK(memcmp(codec.shadowLength, lengthsBefore,
                sizeof(lengthsBefore)) == 0);
            CHECK(codec.muted == before.muted &&
                codec.inputGain == before.inputGain &&
                codec.inputSource == before.inputSource);
        }
        codec_mock_init(&mock);
        CHECK(TASCodecRestore(&codec, 200UL) == kTASStatusOK);
        CHECK(codec.hardwareValid && codec.muted == 1);
        CHECK(memcmp(codec.shadow, shadowBefore, sizeof(shadowBefore)) == 0);
        CHECK(codec.inputGain == before.inputGain &&
            codec.inputSource == before.inputSource);
        CHECK(mock.events[0].reg == 0x01 && mock.events[0].data[0] == 0xea);
        CHECK(mock.events[mock.eventCount - 1UL].reg == 0x01 &&
            mock.events[mock.eventCount - 1UL].data[0] == 0x6a);
        sawMutedVolume = 0;
        for (event = 0UL; event < mock.eventCount; ++event) {
            if (mock.events[event].kind == 3 &&
                mock.events[event].reg == 0x04) {
                unsigned long byte;
                sawMutedVolume = 1;
                for (byte = 0UL; byte < 6UL; ++byte)
                    CHECK(mock.events[event].data[byte] == 0);
            }
        }
        CHECK(sawMutedVolume);

        before = codec;
        writesBefore = mock.writeCount;
        eventsBefore = mock.eventCount;
        CHECK(TASCodecSetVolume(&codec, 0x010000UL, 0x010000UL, 0UL) ==
            kTASStatusMalformed);
        CHECK(TASCodecSetMute(&codec, 0, 0UL) == kTASStatusMalformed);
        CHECK(TASCodecSetInputGain(&codec, 0x010000UL, 0UL) ==
            kTASStatusMalformed);
        CHECK(TASCodecSetInputSource(&codec, kTASCodecInputDigital1, 0UL) ==
            kTASStatusMalformed);
        CHECK(TASCodecWrite(&codec, 0x05, codec.shadow[0x05], 1UL, 0UL) ==
            kTASStatusMalformed);
        CHECK(TASCodecRestore(&codec, 0UL) == kTASStatusMalformed);
        CHECK(memcmp(&codec, &before, sizeof(codec)) == 0);
        CHECK(mock.writeCount == writesBefore && mock.eventCount == eventsBefore);
    }
    CHECK(TASCodecFailOperation(0, kTASStatusTimeout) ==
        kTASStatusMalformed);
    CHECK(TASCodecReset(0, 1) == kTASStatusMalformed);
    CHECK(TASCodecDelay(0, 1UL, 1UL) == kTASStatusMalformed);
}

static void test_codec_multiregister_controls_commit_atomically(void)
{
    const TASCodecOps *ops[2];
    unsigned long backend;
    unsigned long writesBefore;
    unsigned long mutesBefore;
    unsigned char shadowBefore[TAS_CODEC_REGISTER_COUNT]
        [TAS_CODEC_REGISTER_BYTES];
    unsigned long lengthsBefore[TAS_CODEC_REGISTER_COUNT];
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
        CHECK(TASCodecInitialize(&codec, 1, 200UL) == kTASStatusOK);
        memcpy(shadowBefore, codec.shadow, sizeof(shadowBefore));
        memcpy(lengthsBefore, codec.shadowLength, sizeof(lengthsBefore));
        writesBefore = mock.writeCount;
        mutesBefore = mock.failMuteCount;
        mock.failWrite = writesBefore + 1UL;
        mock.partialLength = 0UL;
        CHECK(TASCodecSetInputSource(&codec, kTASCodecInputDigital2,
            200UL) != kTASStatusOK);
        CHECK(mock.writeCount == writesBefore + 2UL);
        CHECK(mock.failMuteCount == mutesBefore + 1UL);
        CHECK(!codec.hardwareValid);
        CHECK(codec.inputSource == kTASCodecInputDigital1);
        CHECK(memcmp(codec.shadow, shadowBefore, sizeof(shadowBefore)) == 0);
        CHECK(memcmp(codec.shadowLength, lengthsBefore,
            sizeof(lengthsBefore)) == 0);

        codec_mock_init(&mock);
        CHECK(TASCodecRestore(&codec, 200UL) == kTASStatusOK);
        CHECK(memcmp(codec.shadow, shadowBefore, sizeof(shadowBefore)) == 0);
        CHECK(memcmp(codec.shadowLength, lengthsBefore,
            sizeof(lengthsBefore)) == 0);

        codec_mock_init(&mock);
        CHECK(TASCodecSetInputSource(&codec, kTASCodecInputDigital2,
            200UL) == kTASStatusOK);
        CHECK(mock.writeCount == 2UL);
        CHECK(codec.inputSource == kTASCodecInputDigital2);
        CHECK(memcmp(codec.shadow[0x07], shadowBefore[0x07],
            codec.shadowLength[0x07]) != 0);
        CHECK(memcmp(codec.shadow[0x08], shadowBefore[0x08],
            codec.shadowLength[0x08]) != 0);
    }
}

static void test_dbdma_descriptor_words_and_directions(void)
{
    DMARingBytes outputBytes;
    DMARingBytes inputBytes;
    DMATranslateMock translate;
    PPCDBDMAOps ops;
    PPCDBDMARing output;
    PPCDBDMARing input;
    PPCDBDMAStorage storage;
    PPCDBDMADescriptor descriptor;
    CHECK(sizeof(PPCDBDMADescriptor) == PPC_DBDMA_DESCRIPTOR_BYTES);
    dma_translate_mock(&translate, 256UL, 256UL, 0x12345000UL,
        0x12345100UL);
    ops = dma_ops(&translate, 0);
    storage = dma_storage(&outputBytes, 0x00100000UL);
    memset(&output, 0xa5, sizeof(output));
    CHECK(PPCDBDMABuildRing(&output, &storage, kPPCDBDMAOutput,
        dmaBuffer, 256UL, 256UL, &ops) == kPPCDBDMAOK);
    CHECK(output.descriptorCount == 2UL && output.dataDescriptorCount == 1UL);
    CHECK(PPCDBDMALoadDescriptor(&output, 0UL, &descriptor) ==
        kPPCDBDMAOK);
    CHECK(descriptor.operation == 0x00300100UL);
    CHECK(descriptor.address == 0x12345000UL);
    CHECK(descriptor.dependency == 0UL && descriptor.result == 0UL);
    CHECK(output.descriptors[0] == 0x00 && output.descriptors[1] == 0x01 &&
        output.descriptors[2] == 0x30 && output.descriptors[3] == 0x00);
    CHECK(output.descriptors[4] == 0x00 && output.descriptors[5] == 0x50 &&
        output.descriptors[6] == 0x34 && output.descriptors[7] == 0x12);
    CHECK(output.descriptors[8] == 0x00 && output.descriptors[9] == 0x00 &&
        output.descriptors[10] == 0x00 && output.descriptors[11] == 0x00);
    CHECK(output.descriptors[12] == 0x00 && output.descriptors[13] == 0x00 &&
        output.descriptors[14] == 0x00 && output.descriptors[15] == 0x00);
    CHECK(PPCDBDMALoadDescriptor(&output, 1UL, &descriptor) ==
        kPPCDBDMAOK);
    CHECK(descriptor.operation == 0x600c0000UL);
    CHECK(descriptor.dependency == 0x00100000UL);
    CHECK(output.descriptors[16] == 0x00 && output.descriptors[17] == 0x00 &&
        output.descriptors[18] == 0x0c && output.descriptors[19] == 0x60);
    CHECK(output.descriptors[24] == 0x00 && output.descriptors[25] == 0x00 &&
        output.descriptors[26] == 0x10 && output.descriptors[27] == 0x00);

    translate.calls = 0UL;
    storage = dma_storage(&inputBytes, 0x00200000UL);
    CHECK(PPCDBDMABuildRing(&input, &storage, kPPCDBDMAInput,
        dmaBuffer, 256UL, 256UL, &ops) == kPPCDBDMAOK);
    CHECK(PPCDBDMALoadDescriptor(&input, 0UL, &descriptor) ==
        kPPCDBDMAOK);
    CHECK(descriptor.operation == 0x20300100UL);
    CHECK(input.direction == kPPCDBDMAInput && output.direction ==
        kPPCDBDMAOutput);
}

static void test_dbdma_splits_translation_count_and_periods(void)
{
    DMARingBytes bytes;
    DMATranslateMock translate;
    PPCDBDMAOps ops;
    PPCDBDMARing ring;
    PPCDBDMAStorage storage;
    PPCDBDMADescriptor descriptor;
    dma_translate_mock(&translate, 8192UL, 4096UL, 0x20000000UL,
        0x30000000UL);
    ops = dma_ops(&translate, 0);
    storage = dma_storage(&bytes, 0x00300000UL);
    CHECK(PPCDBDMABuildRing(&ring, &storage, kPPCDBDMAOutput,
        dmaBuffer, 8192UL, 4096UL, &ops) == kPPCDBDMAOK);
    CHECK(translate.calls == 2UL && ring.dataDescriptorCount == 2UL);
    CHECK(PPCDBDMALoadDescriptor(&ring, 0UL, &descriptor) ==
        kPPCDBDMAOK);
    CHECK(descriptor.operation == 0x00301000UL &&
        descriptor.address == 0x20000000UL);
    CHECK(PPCDBDMALoadDescriptor(&ring, 1UL, &descriptor) ==
        kPPCDBDMAOK);
    CHECK(descriptor.operation == 0x00301000UL &&
        descriptor.address == 0x30000000UL);

    dma_translate_mock(&translate, DMA_BUFFER_BYTES, DMA_BUFFER_BYTES,
        0x40000000UL, 0x40000000UL + DMA_BUFFER_BYTES);
    ops = dma_ops(&translate, 0);
    CHECK(PPCDBDMABuildRing(&ring, &storage, kPPCDBDMAInput,
        dmaBuffer, DMA_BUFFER_BYTES, DMA_BUFFER_BYTES, &ops) ==
        kPPCDBDMAOK);
    CHECK(ring.dataDescriptorCount == 2UL);
    CHECK(PPCDBDMALoadDescriptor(&ring, 0UL, &descriptor) ==
        kPPCDBDMAOK);
    CHECK((descriptor.operation & 0xffffUL) == 0xffffUL);
    CHECK((descriptor.operation & 0x00300000UL) == 0UL);
    CHECK(PPCDBDMALoadDescriptor(&ring, 1UL, &descriptor) ==
        kPPCDBDMAOK);
    CHECK((descriptor.operation & 0xffffUL) ==
        DMA_BUFFER_BYTES - 65535UL);
    CHECK((descriptor.operation & 0x00300000UL) == 0x00300000UL);
}

static void test_dbdma_rejects_invalid_and_is_atomic(void)
{
    DMARingBytes bytes;
    DMATranslateMock translate;
    PPCDBDMAOps ops;
    PPCDBDMARing ring;
    PPCDBDMARing before;
    PPCDBDMAStorage storage;
    unsigned char bytesBefore[PPC_DBDMA_MAX_RING_BYTES];
    dma_translate_mock(&translate, 8192UL, 4096UL, 0x50000000UL,
        0x60000000UL);
    translate.failCall = 2UL;
    ops = dma_ops(&translate, 0);
    storage = dma_storage(&bytes, 0x00400000UL);
    memset(&ring, 0x5a, sizeof(ring));
    memset(bytes.bytes, 0x6b, sizeof(bytes.bytes));
    before = ring;
    memcpy(bytesBefore, bytes.bytes, sizeof(bytesBefore));
    CHECK(PPCDBDMABuildRing(&ring, &storage, kPPCDBDMAOutput,
        dmaBuffer, 8192UL, 4096UL, &ops) == kPPCDBDMAUnmappable);
    CHECK(memcmp(&ring, &before, sizeof(ring)) == 0);
    CHECK(memcmp(bytes.bytes, bytesBefore, sizeof(bytesBefore)) == 0);
    CHECK(PPCDBDMABuildRing(0, &storage, kPPCDBDMAOutput, dmaBuffer,
        1UL, 1UL, &ops) == kPPCDBDMAInvalid);
    CHECK(PPCDBDMABuildRing(&ring, &storage, kPPCDBDMAOutput, dmaBuffer,
        0UL, 1UL, &ops) == kPPCDBDMAInvalid);
    CHECK(PPCDBDMABuildRing(&ring, &storage, kPPCDBDMAOutput, dmaBuffer,
        3UL, 2UL, &ops) == kPPCDBDMAInvalid);
    storage.logical = (unsigned char *)storage.logical + 1;
    CHECK(PPCDBDMABuildRing(&ring, &storage, kPPCDBDMAOutput, dmaBuffer,
        16UL, 16UL, &ops) == kPPCDBDMAMisaligned);
    storage = dma_storage(&bytes, 0x00400000UL);
    storage.physical = 0x00400001UL;
    CHECK(PPCDBDMABuildRing(&ring, &storage, kPPCDBDMAOutput, dmaBuffer,
        16UL, 16UL, &ops) == kPPCDBDMAMisaligned);
    storage.physical = 0x00400000UL;
    storage.bytes = PPC_DBDMA_MAX_RING_BYTES + 1UL;
    CHECK(PPCDBDMABuildRing(&ring, &storage, kPPCDBDMAOutput, dmaBuffer,
        16UL, 16UL, &ops) == kPPCDBDMAOversized);
    storage.bytes = PPC_DBDMA_MAX_RING_BYTES;
    storage.scratch = 0;
    CHECK(PPCDBDMABuildRing(&ring, &storage, kPPCDBDMAOutput, dmaBuffer,
        16UL, 16UL, &ops) == kPPCDBDMAInvalid);
    CHECK(memcmp(&ring, &before, sizeof(ring)) == 0);
    CHECK(memcmp(bytes.bytes, bytesBefore, sizeof(bytesBefore)) == 0);
    storage = dma_storage(&bytes, 0x00400000UL);
    storage.scratchBytes = PPC_DBDMA_DESCRIPTOR_BYTES;
    CHECK(PPCDBDMABuildRing(&ring, &storage, kPPCDBDMAOutput, dmaBuffer,
        16UL, 16UL, &ops) == kPPCDBDMAOversized);
    CHECK(memcmp(&ring, &before, sizeof(ring)) == 0);
    CHECK(memcmp(bytes.bytes, bytesBefore, sizeof(bytesBefore)) == 0);
    storage = dma_storage(&bytes, 0x00400000UL);
    storage.scratch = (unsigned char *)storage.scratch + 1;
    CHECK(PPCDBDMABuildRing(&ring, &storage, kPPCDBDMAOutput, dmaBuffer,
        16UL, 16UL, &ops) == kPPCDBDMAMisaligned);
    CHECK(memcmp(&ring, &before, sizeof(ring)) == 0);
    CHECK(memcmp(bytes.bytes, bytesBefore, sizeof(bytesBefore)) == 0);
    storage = dma_storage(&bytes, 0x00400000UL);
    storage.scratch = storage.logical;
    CHECK(PPCDBDMABuildRing(&ring, &storage, kPPCDBDMAOutput, dmaBuffer,
        16UL, 16UL, &ops) == kPPCDBDMAInvalid);
    CHECK(memcmp(&ring, &before, sizeof(ring)) == 0);
    CHECK(memcmp(bytes.bytes, bytesBefore, sizeof(bytesBefore)) == 0);
    storage = dma_storage(&bytes, 0x00400000UL);
    dma_translate_mock(&translate, 32UL, 32UL, 0xfffffff0UL, 0UL);
    ops = dma_ops(&translate, 0);
    CHECK(PPCDBDMABuildRing(&ring, &storage, kPPCDBDMAOutput, dmaBuffer,
        32UL, 32UL, &ops) == kPPCDBDMAOverflow);
}

static void test_dbdma_ring_physical_range_is_exact_and_atomic(void)
{
    DMARingBytes bytes;
    DMATranslateMock translate;
    PPCDBDMAOps ops;
    PPCDBDMARing ring;
    PPCDBDMARing before;
    PPCDBDMAStorage storage;
    PPCDBDMADescriptor branch;
    unsigned char bytesBefore[sizeof(bytes.bytes)];
    unsigned long tooWide;
    dma_translate_mock(&translate, 256UL, 256UL, 0x72000000UL,
        0x72000100UL);
    ops = dma_ops(&translate, 0);
    storage = dma_storage(&bytes, 0xfffffff0UL);
    memset(&ring, 0x39, sizeof(ring));
    memset(bytes.bytes, 0x4a, sizeof(bytes.bytes));
    before = ring;
    memcpy(bytesBefore, bytes.bytes, sizeof(bytesBefore));
    CHECK(PPCDBDMABuildRing(&ring, &storage, kPPCDBDMAOutput,
        dmaBuffer, 256UL, 256UL, &ops) == kPPCDBDMAOverflow);
    CHECK(memcmp(&ring, &before, sizeof(ring)) == 0);
    CHECK(memcmp(bytes.bytes, bytesBefore, sizeof(bytesBefore)) == 0);

    if (sizeof(unsigned long) > 4U) {
        tooWide = 0xffffffffUL;
        ++tooWide;
        storage.physical = tooWide;
        translate.calls = 0UL;
        CHECK(PPCDBDMABuildRing(&ring, &storage, kPPCDBDMAOutput,
            dmaBuffer, 256UL, 256UL, &ops) == kPPCDBDMAOverflow);
        CHECK(memcmp(&ring, &before, sizeof(ring)) == 0);
        CHECK(memcmp(bytes.bytes, bytesBefore, sizeof(bytesBefore)) == 0);
    }

    storage.physical = 0xffffffe0UL;
    translate.calls = 0UL;
    CHECK(PPCDBDMABuildRing(&ring, &storage, kPPCDBDMAOutput,
        dmaBuffer, 256UL, 256UL, &ops) == kPPCDBDMAOK);
    CHECK(ring.descriptorCount == 2UL);
    CHECK(PPCDBDMALoadDescriptor(&ring, 1UL, &branch) == kPPCDBDMAOK);
    CHECK(branch.dependency == 0xffffffe0UL);
}

static void test_dbdma_completion_progression_and_fault_isolation(void)
{
    DMARingBytes inputBytes;
    DMARingBytes outputBytes;
    DMATranslateMock translate;
    PPCDBDMAOps ops;
    PPCDBDMARing input;
    PPCDBDMARing output;
    PPCDBDMAStorage storage;
    PPCDBDMACompletion completion;
    DMARegisterMock coherency;
    dma_translate_mock(&translate, 512UL, 512UL, 0x61000000UL,
        0x61000200UL);
    memset(&coherency, 0, sizeof(coherency));
    ops = dma_ops(&translate, &coherency);
    storage = dma_storage(&inputBytes, 0x00500000UL);
    CHECK(PPCDBDMABuildRing(&input, &storage, kPPCDBDMAInput,
        dmaBuffer, 512UL, 256UL, &ops) == kPPCDBDMAOK);
    translate.calls = 0UL;
    storage = dma_storage(&outputBytes, 0x00600000UL);
    CHECK(PPCDBDMABuildRing(&output, &storage, kPPCDBDMAOutput,
        dmaBuffer, 512UL, 256UL, &ops) == kPPCDBDMAOK);
    CHECK(PPCDBDMAServiceCompletions(&input, &ops, &completion) ==
        kPPCDBDMAOK);
    CHECK(completion.descriptors == 0UL && completion.spurious);
    CHECK(coherency.eventCount == 2UL && coherency.events[0] == 5UL &&
        coherency.events[1] == 2UL);
    memset(&coherency, 0, sizeof(coherency));
    dma_store_result(&input, 0UL, 0x0001UL, 4UL);
    CHECK(PPCDBDMAServiceCompletions(&input, &ops, &completion) ==
        kPPCDBDMAOK);
    CHECK(completion.spurious && input.consumer == 0UL);
    CHECK(input.descriptors[12] == 0x04 && input.descriptors[14] == 0x01);
    memset(&coherency, 0, sizeof(coherency));
    dma_store_result(&input, 0UL, 0x0400UL, 4UL);
    dma_store_result(&input, 1UL, 0x0400UL, 0UL);
    CHECK(PPCDBDMAServiceCompletions(&input, &ops, &completion) ==
        kPPCDBDMAOK);
    CHECK(completion.descriptors == 2UL && completion.bytes == 508UL);
    CHECK(completion.lastStatus == 0x0400UL &&
        completion.lastResidual == 0UL && input.consumer == 0UL);
    CHECK(output.consumer == 0UL && output.state == kPPCDBDMAReady);
    CHECK(coherency.eventCount == 6UL && coherency.events[0] == 5UL &&
        coherency.events[1] == 2UL && coherency.events[2] == 1UL &&
        coherency.events[3] == 2UL && coherency.events[4] == 1UL &&
        coherency.events[5] == 2UL && coherency.publishedAckWasZero);
    CHECK(input.descriptors[12] == 0 && input.descriptors[13] == 0 &&
        input.descriptors[14] == 0 && input.descriptors[15] == 0);
    memset(&coherency, 0, sizeof(coherency));
    dma_store_result(&output, 0UL, kPPCDBDMADead, 1UL);
    CHECK(PPCDBDMAServiceCompletions(&output, &ops, &completion) ==
        kPPCDBDMAFault);
    CHECK(completion.descriptors == 1UL && completion.fault);
    CHECK(output.state == kPPCDBDMAFaulted);
    CHECK(output.consumer == 0UL);
    CHECK(input.state == kPPCDBDMAReady && input.faultStatus == 0UL);
}

static void test_dbdma_bounded_transitions(void)
{
    DMARingBytes bytes;
    DMATranslateMock translate;
    DMARegisterMock registers;
    PPCDBDMAOps ops;
    PPCDBDMARing ring;
    PPCDBDMAStorage storage;
    PPCDBDMATransition transition;
    dma_translate_mock(&translate, 256UL, 256UL, 0x70000000UL,
        0x70000100UL);
    memset(&registers, 0, sizeof(registers));
    registers.tick = 1UL;
    registers.status[0] = kPPCDBDMAActive;
    registers.status[1] = 0UL;
    registers.statusCount = 2UL;
    ops = dma_ops(&translate, &registers);
    storage = dma_storage(&bytes, 0x00700000UL);
    CHECK(PPCDBDMABuildRing(&ring, &storage, kPPCDBDMAOutput,
        dmaBuffer, 256UL, 256UL, &ops) == kPPCDBDMAOK);
    transition = PPCDBDMAStartRing(&ring, &ops, 10UL);
    CHECK(transition.status == kPPCDBDMAOK && !transition.sharedClockInvalidated);
    CHECK(ring.state == kPPCDBDMARunning);
    CHECK(registers.writeCount == 3UL);
    CHECK(registers.writes[0][0] == kPPCDBDMARegControl);
    CHECK(registers.writes[1][0] == kPPCDBDMARegCommandPtr &&
        registers.writes[1][1] == 0x00700000UL);
    CHECK(registers.writes[2][1] ==
        PPCDBDMASetControl(kPPCDBDMARun | kPPCDBDMAWake));
    CHECK(registers.events[0] == 1UL && registers.events[1] == 2UL &&
        registers.events[2] == 3UL);

    memset(&registers, 0, sizeof(registers));
    registers.tick = 1UL;
    registers.status[0] = kPPCDBDMAActive | kPPCDBDMAFlushBit;
    registers.status[1] = kPPCDBDMAFlushBit;
    registers.status[2] = 0UL;
    registers.statusCount = 3UL;
    ops = dma_ops(&translate, &registers);
    transition = PPCDBDMAStopRing(&ring, &ops, 10UL);
    CHECK(transition.status == kPPCDBDMAOK && ring.state == kPPCDBDMAStopped);
    CHECK(registers.timeCalls == 7UL);

    ring.state = kPPCDBDMARunning;
    memset(&registers, 0, sizeof(registers));
    registers.tick = 1UL;
    registers.status[0] = kPPCDBDMAFlushBit;
    registers.status[1] = 0UL;
    registers.statusCount = 2UL;
    ops = dma_ops(&translate, &registers);
    transition = PPCDBDMAFlushRing(&ring, &ops, 10UL);
    CHECK(transition.status == kPPCDBDMAOK &&
        ring.state == kPPCDBDMARunning);
    CHECK(registers.writeCount == 1UL && registers.timeCalls == 5UL);

    ring.state = kPPCDBDMAStopped;
    memset(&registers, 0, sizeof(registers));
    registers.tick = 1UL;
    registers.status[0] = kPPCDBDMAActive;
    registers.status[1] = 0UL;
    registers.statusCount = 2UL;
    ops = dma_ops(&translate, &registers);
    transition = PPCDBDMAResetRing(&ring, &ops, 10UL);
    CHECK(transition.status == kPPCDBDMAOK && ring.state == kPPCDBDMAReady);
    CHECK(registers.writeCount == 1UL && registers.timeCalls == 5UL);

    ring.state = kPPCDBDMARunning;
    memset(&registers, 0, sizeof(registers));
    registers.tick = 2UL;
    registers.status[0] = kPPCDBDMAActive;
    registers.status[1] = kPPCDBDMAActive;
    registers.status[2] = kPPCDBDMAActive;
    registers.statusCount = 3UL;
    ops = dma_ops(&translate, &registers);
    transition = PPCDBDMAStopRing(&ring, &ops, 3UL);
    CHECK(transition.status == kPPCDBDMATimeout);
    CHECK(!transition.sharedClockInvalidated && ring.state ==
        kPPCDBDMAFaulted);
    CHECK(registers.timeCalls != 0UL);
}

static void test_dbdma_coherency_deadlines_and_reset_restart(void)
{
    DMARingBytes bytes;
    DMATranslateMock translate;
    DMARegisterMock registers;
    PPCDBDMAOps ops;
    PPCDBDMARing ring;
    PPCDBDMAStorage storage;
    PPCDBDMACompletion completion;
    PPCDBDMATransition transition;
    unsigned long siblingConsumer;

    dma_translate_mock(&translate, 512UL, 512UL, 0x71000000UL,
        0x71000200UL);
    memset(&registers, 0, sizeof(registers));
    ops = dma_ops(&translate, &registers);
    storage = dma_storage(&bytes, 0x00710000UL);
    CHECK(PPCDBDMABuildRing(&ring, &storage, kPPCDBDMAOutput,
        dmaBuffer, 512UL, 256UL, &ops) == kPPCDBDMAOK);

    registers.failPublish = 1UL;
    transition = PPCDBDMAStartRing(&ring, &ops, 10UL);
    CHECK(transition.status == kPPCDBDMACoherency &&
        ring.state == kPPCDBDMAReady && registers.writeCount == 0UL);

    memset(&registers, 0, sizeof(registers));
    registers.now = 10UL;
    ops = dma_ops(&translate, &registers);
    transition = PPCDBDMAStartRing(&ring, &ops, 10UL);
    CHECK(transition.status == kPPCDBDMATimeout &&
        !transition.sharedClockInvalidated && ring.state == kPPCDBDMAReady &&
        registers.writeCount == 0UL && registers.eventCount == 0UL);
    transition = PPCDBDMAStartRing(&ring, &ops, 0UL);
    CHECK(transition.status == kPPCDBDMATimeout &&
        ring.state == kPPCDBDMAReady && registers.writeCount == 0UL);
    ring.state = kPPCDBDMARunning;
    transition = PPCDBDMAStopRing(&ring, &ops, 10UL);
    CHECK(transition.status == kPPCDBDMATimeout &&
        ring.state == kPPCDBDMARunning && registers.writeCount == 0UL);
    transition = PPCDBDMAFlushRing(&ring, &ops, 10UL);
    CHECK(transition.status == kPPCDBDMATimeout &&
        ring.state == kPPCDBDMARunning && registers.writeCount == 0UL);
    ring.state = kPPCDBDMAFaulted;
    transition = PPCDBDMAResetRing(&ring, &ops, 10UL);
    CHECK(transition.status == kPPCDBDMATimeout &&
        ring.state == kPPCDBDMAFaulted && registers.writeCount == 0UL);
    ring.state = kPPCDBDMAReady;

    memset(&registers, 0, sizeof(registers));
    registers.readAdvance = 10UL;
    ops = dma_ops(&translate, &registers);
    transition = PPCDBDMAStartRing(&ring, &ops, 10UL);
    CHECK(transition.status == kPPCDBDMATimeout &&
        ring.state == kPPCDBDMAFaulted && registers.writeCount == 1UL);
    ring.state = kPPCDBDMAReady;
    memset(&registers, 0, sizeof(registers));
    registers.tick = 1UL;
    ops = dma_ops(&translate, &registers);
    transition = PPCDBDMAStartRing(&ring, &ops, 4UL);
    CHECK(transition.status == kPPCDBDMATimeout &&
        ring.state == kPPCDBDMAFaulted && registers.writeCount == 1UL);
    ring.state = kPPCDBDMAReady;

    memset(&registers, 0, sizeof(registers));
    ops = dma_ops(&translate, &registers);
    registers.failInvalidate = 1UL;
    dma_store_result(&ring, 0UL, kPPCDBDMAActive, 0UL);
    CHECK(PPCDBDMAServiceCompletions(&ring, &ops, &completion) ==
        kPPCDBDMACoherency);
    CHECK(ring.consumer == 0UL && ring.state == kPPCDBDMAReady);

    memset(&registers, 0, sizeof(registers));
    ops = dma_ops(&translate, &registers);
    registers.failPublish = 1UL;
    CHECK(PPCDBDMAServiceCompletions(&ring, &ops, &completion) ==
        kPPCDBDMACoherency);
    CHECK(ring.consumer == 0UL && ring.state == kPPCDBDMAFaulted);
    CHECK(ring.descriptors[15] == 0x04);
    dma_store_result(&ring, ring.dataDescriptorCount, 0x1234UL, 7UL);

    memset(&registers, 0, sizeof(registers));
    ops = dma_ops(&translate, &registers);
    registers.status[0] = 0UL;
    registers.statusCount = 1UL;
    transition = PPCDBDMAResetRing(&ring, &ops, 10UL);
    CHECK(transition.status == kPPCDBDMAOK && ring.consumer == 0UL &&
        ring.state == kPPCDBDMAReady && ring.faultStatus == 0UL);
    CHECK(registers.eventCount == 4UL && registers.events[0] == 3UL &&
        registers.events[1] == 4UL && registers.events[2] == 1UL &&
        registers.events[3] == 2UL);
    CHECK(ring.descriptors[12] == 0 && ring.descriptors[14] == 0 &&
        ring.descriptors[28] == 0 && ring.descriptors[30] == 0);
    CHECK(ring.descriptors[44] == 0 && ring.descriptors[47] == 0);

    dma_store_result(&ring, 0UL, kPPCDBDMAActive, 0UL);
    memset(&registers, 0, sizeof(registers));
    registers.failBarrier = 2UL;
    ops = dma_ops(&translate, &registers);
    CHECK(PPCDBDMAServiceCompletions(&ring, &ops, &completion) ==
        kPPCDBDMACoherency);
    CHECK(ring.consumer == 0UL && ring.state == kPPCDBDMAFaulted &&
        registers.eventCount == 4UL && registers.events[0] == 5UL &&
        registers.events[1] == 2UL && registers.events[2] == 1UL &&
        registers.events[3] == 2UL && registers.publishedAckWasZero);
    memset(&registers, 0, sizeof(registers));
    ops = dma_ops(&translate, &registers);
    transition = PPCDBDMAResetRing(&ring, &ops, 10UL);
    CHECK(transition.status == kPPCDBDMAOK && ring.consumer == 0UL);

    dma_store_result(&ring, 0UL, kPPCDBDMAActive, 0UL);
    CHECK(PPCDBDMAServiceCompletions(&ring, &ops, &completion) ==
        kPPCDBDMAOK && ring.consumer == 1UL);
    dma_store_result(&ring, 1UL, kPPCDBDMAActive | kPPCDBDMADead, 0UL);
    CHECK(PPCDBDMAServiceCompletions(&ring, &ops, &completion) ==
        kPPCDBDMAFault && ring.consumer == 1UL);
    siblingConsumer = ring.consumer;
    memset(&registers, 0, sizeof(registers));
    ops = dma_ops(&translate, &registers);
    transition = PPCDBDMAResetRing(&ring, &ops, 10UL);
    CHECK(transition.status == kPPCDBDMAOK && siblingConsumer == 1UL &&
        ring.consumer == 0UL);
    memset(&registers, 0, sizeof(registers));
    ops = dma_ops(&translate, &registers);
    transition = PPCDBDMAStartRing(&ring, &ops, 10UL);
    CHECK(transition.status == kPPCDBDMAOK && registers.writeCount == 3UL &&
        registers.writes[1][1] == ring.descriptorPhysical);

    dma_store_result(&ring, 0UL, kPPCDBDMAActive, 0UL);
    CHECK(PPCDBDMAServiceCompletions(&ring, &ops, &completion) ==
        kPPCDBDMAOK && ring.consumer == 1UL);
    memset(&registers, 0, sizeof(registers));
    ops = dma_ops(&translate, &registers);
    transition = PPCDBDMAStopRing(&ring, &ops, 10UL);
    CHECK(transition.status == kPPCDBDMAOK &&
        ring.state == kPPCDBDMAStopped && ring.consumer == 1UL);
    transition = PPCDBDMAStartRing(&ring, &ops, 10UL);
    CHECK(transition.status == kPPCDBDMAInvalid &&
        ring.state == kPPCDBDMAStopped && registers.writeCount == 1UL);
    memset(&registers, 0, sizeof(registers));
    ops = dma_ops(&translate, &registers);
    transition = PPCDBDMAResetRing(&ring, &ops, 10UL);
    CHECK(transition.status == kPPCDBDMAOK && ring.consumer == 0UL &&
        ring.state == kPPCDBDMAReady && ring.descriptors[12] == 0UL);
    memset(&registers, 0, sizeof(registers));
    ops = dma_ops(&translate, &registers);
    transition = PPCDBDMAStartRing(&ring, &ops, 10UL);
    CHECK(transition.status == kPPCDBDMAOK &&
        registers.writes[1][1] == ring.descriptorPhysical);
}

static int audio_plan_has_unmute_before(const TASAudioActionPlan *plan,
    unsigned long limit)
{
    unsigned long index;
    for (index = 0UL; index < limit && index < plan->count; ++index) {
        if (plan->actions[index].operation == kTASAudioUnmuteSpeaker ||
            plan->actions[index].operation == kTASAudioUnmuteHeadphone ||
            plan->actions[index].operation == kTASAudioUnmuteLineOut)
            return 1;
    }
    return 0;
}

static int audio_action_is_codec(TASAudioActionOperation operation)
{
    return operation == kTASAudioCodecDigitalMute ||
        operation == kTASAudioSetCodecRoute ||
        operation == kTASAudioCodecAnalogLowPower ||
        operation == kTASAudioCodecMuteLowPower ||
        operation == kTASAudioCodecReset ||
        operation == kTASAudioCodecRestore ||
        operation == kTASAudioRestoreVolume ||
        operation == kTASAudioRestoreInputSource ||
        operation == kTASAudioRestoreInputGain;
}

static void audio_controls(TASAudioDesiredControls *controls, int muted)
{
    memset(controls, 0, sizeof(*controls));
    controls->rate = 44100UL;
    controls->leftVolume = 0x008000UL;
    controls->rightVolume = 0x004000UL;
    controls->inputGain = 0x002000UL;
    controls->inputSource = 1UL;
    controls->userMuted = muted;
}

static void audio_complete_prefix(TASAudioState *state, TASAudioToken *token,
    unsigned long count)
{
    unsigned long index;
    for (index = 0UL; index < count; ++index) {
        CHECK(TASAudioAuthorizeAction(state, token, index) == kTASStatusOK);
        CHECK(TASAudioAuthorizeAction(state, token, index) ==
            kTASStatusConflict);
        CHECK(TASAudioCompleteAction(state, token, index) == kTASStatusOK);
        CHECK(TASAudioCompleteAction(state, token, index) ==
            kTASStatusConflict);
    }
}

static void audio_complete_plan(TASAudioState *state, TASAudioToken *token)
{
    audio_complete_prefix(state, token, token->actionCount);
}

static void test_audio_route_state_machine(void)
{
    static const unsigned long detects[] = { 0UL,1UL,2UL,3UL };
    static const unsigned long routes[] = {
        kTASAudioRouteSpeaker, kTASAudioRouteHeadphone,
        kTASAudioRouteLineOut,
        kTASAudioRouteHeadphone | kTASAudioRouteLineOut
    };
    TASAudioDesiredControls controls;
    TASAudioState state;
    TASAudioState before;
    TASAudioActionPlan plan;
    TASAudioActionPlan failSafe;
    TASAudioToken token;
    TASAudioToken beforeToken;
    TASAudioToken stale;
    TASAudioToken rollbackToken;
    unsigned long index;
    unsigned long ordinal;
    unsigned long andedCount;
    audio_controls(&controls, 0);
    for (index = 0UL; index < 4UL; ++index) {
        CHECK(TASAudioStateInit(&state, kTASAudioRouteSpeaker |
            kTASAudioRouteHeadphone | kTASAudioRouteLineOut,
            kTASCodecTAS3004, kTASQuirkNone, &controls) == kTASStatusOK);
        CHECK(TASAudioPrepareRoute(&state, detects[index], &plan, &token) ==
            kTASStatusOK);
        CHECK(token.targetRoutes == routes[index]);
        CHECK(plan.actions[0].operation == kTASAudioMuteSpeaker);
        CHECK(plan.actions[1].operation == kTASAudioMuteHeadphone);
        CHECK(plan.actions[2].operation == kTASAudioMuteLineOut);
        CHECK(!audio_plan_has_unmute_before(&plan, 5UL));
        CHECK(TASAudioCommitTransition(&state, &token) ==
            kTASStatusConflict);
        CHECK(TASAudioAuthorizeAction(&state, &token, 1UL) ==
            kTASStatusConflict);
        CHECK(TASAudioCompleteAction(&state, &token, 0UL) ==
            kTASStatusConflict);
        audio_complete_plan(&state, &token);
        CHECK(TASAudioCommitTransition(&state, &token) == kTASStatusOK);
        CHECK(state.routeValid && state.hardwareValid &&
            state.currentRoutes == routes[index]);
    }
    CHECK(TASAudioStateInit(&state, kTASAudioRouteSpeaker |
        kTASAudioRouteHeadphone | kTASAudioRouteLineOut,
        kTASCodecTAS3004, kTASQuirkNone, &controls) == kTASStatusOK);
    CHECK(TASAudioPrepareRoute(&state, 0UL, &plan, &token) == kTASStatusOK);
    CHECK(TASAudioAuthorizeAction(&state, &token, 0UL) == kTASStatusOK);
    CHECK(TASAudioRecordDetectISR(&state, 1UL, &index) == kTASStatusOK);
    CHECK(TASAudioCompleteAction(&state, &token, 0UL) ==
        kTASStatusConflict);
    CHECK(TASAudioCommitTransition(&state, &token) == kTASStatusConflict);
    CHECK(TASAudioFailTransition(&state, &token, 450UL, &failSafe,
        &rollbackToken) == kTASStatusOK);
    CHECK(state.desiredDetects == 1UL && state.debouncePending);
    CHECK(TASAudioAbortRollback(&state, &rollbackToken) == kTASStatusOK);
    controls.userMuted = 1;
    CHECK(TASAudioStateInit(&state, kTASAudioRouteSpeaker |
        kTASAudioRouteHeadphone | kTASAudioRouteLineOut,
        kTASCodecTAS3004, kTASQuirkNone, &controls) == kTASStatusOK);
    CHECK(TASAudioPrepareRoute(&state, 3UL, &plan, &token) == kTASStatusOK);
    CHECK(token.targetRoutes == 0UL && !audio_plan_has_unmute_before(&plan,
        plan.count));

    controls.userMuted = 0;
    for (ordinal = 0UL; ordinal < 7UL; ++ordinal) {
        CHECK(TASAudioStateInit(&state, kTASAudioRouteSpeaker |
            kTASAudioRouteHeadphone | kTASAudioRouteLineOut,
            kTASCodecTAS3004, kTASQuirkNone, &controls) == kTASStatusOK);
        CHECK(TASAudioPrepareRoute(&state, 3UL, &plan, &token) ==
            kTASStatusOK);
        CHECK(ordinal < plan.count);
        audio_complete_prefix(&state, &token, ordinal);
        CHECK(TASAudioAuthorizeAction(&state, &token, ordinal) ==
            kTASStatusOK);
        CHECK(TASAudioFailTransition(&state, &token, 500UL, &failSafe,
            &rollbackToken) == kTASStatusOK);
        CHECK(!state.routeValid && !state.hardwareValid &&
            state.currentRoutes == 0UL && !state.outputsMuteKnown &&
            !state.dmaStoppedKnown && state.rollbackPending);
        CHECK(state.desiredDetects == 3UL && !state.desired.userMuted);
        CHECK(failSafe.count == 7UL &&
            !audio_plan_has_unmute_before(&failSafe, failSafe.count));
        audio_complete_plan(&state, &rollbackToken);
        CHECK(TASAudioCommitRollback(&state, &rollbackToken) ==
            kTASStatusOK);
        CHECK(state.outputsMuteKnown && state.outputsMuted &&
            state.dmaStoppedKnown && !state.rollbackPending);
    }

    CHECK(TASAudioStateInit(&state, kTASAudioRouteSpeaker |
        kTASAudioRouteHeadphone, kTASCodecTAS3001C,
        kTASQuirkANDedReset, &controls) == kTASStatusOK);
    CHECK(TASAudioPrepareRoute(&state, 1UL, &plan, &token) == kTASStatusOK);
    CHECK(plan.actions[0].operation == kTASAudioAssertAndedReset);
    CHECK(plan.actions[1].operation == kTASAudioReleaseAndedReset);
    CHECK(plan.actions[2].operation == kTASAudioCodecReset);
    CHECK(plan.actions[3].operation == kTASAudioCodecRestore);
    CHECK(plan.actions[4].operation == kTASAudioSetOutputMux);
    CHECK(plan.actions[5].operation == kTASAudioSetCodecRoute);
    andedCount = plan.count;
    CHECK(TASAudioStateInit(&state, kTASAudioRouteSpeaker |
        kTASAudioRouteLineOut, kTASCodecTAS3001C,
        kTASQuirkANDedReset, &controls) == kTASStatusUnsupported);

    stale = token;
    before = state;
    beforeToken = token;
    controls.leftVolume = 0x001000UL;
    CHECK(TASAudioSetDesiredControls(&state, &controls) ==
        kTASStatusConflict);
    CHECK(memcmp(&state, &before, sizeof(state)) == 0);
    CHECK(memcmp(&token, &beforeToken, sizeof(token)) == 0);
    audio_complete_plan(&state, &stale);
    CHECK(TASAudioCommitTransition(&state, &stale) == kTASStatusOK);
    CHECK(state.andedResetState == kTASAndedResetReleased);

    for (ordinal = 0UL; ordinal < andedCount; ++ordinal) {
        CHECK(TASAudioStateInit(&state, kTASAudioRouteSpeaker |
            kTASAudioRouteHeadphone, kTASCodecTAS3001C,
            kTASQuirkANDedReset, &controls) == kTASStatusOK);
        CHECK(TASAudioPrepareRoute(&state, 1UL, &plan, &token) ==
            kTASStatusOK);
        audio_complete_prefix(&state, &token, ordinal);
        CHECK(TASAudioAuthorizeAction(&state, &token, ordinal) ==
            kTASStatusOK);
        CHECK(TASAudioFailTransition(&state, &token, 700UL, &failSafe,
            &rollbackToken) == kTASStatusOK);
        CHECK(state.andedResetState == kTASAndedResetUnknown &&
            !state.outputsMuteKnown);
        CHECK(failSafe.actions[0].operation == kTASAudioAssertAndedReset);
        CHECK(failSafe.count == 5UL);
        for (index = 1UL; index < failSafe.count; ++index)
            CHECK(!audio_action_is_codec(failSafe.actions[index].operation));
        CHECK(TASAudioAuthorizeAction(&state, &rollbackToken, 0UL) ==
            kTASStatusOK);
        CHECK(TASAudioCompleteAction(&state, &rollbackToken, 0UL) ==
            kTASStatusOK);
        CHECK(TASAudioAbortRollback(&state, &rollbackToken) == kTASStatusOK);
        CHECK(state.rollbackPending && !state.outputsMuteKnown);
    }
}

static void test_audio_cancel_transition(void)
{
    TASAudioDesiredControls controls;
    TASAudioState state;
    TASAudioState before;
    TASAudioState reserved;
    TASAudioState newest;
    TASAudioActionPlan plan;
    TASAudioActionPlan rollbackPlan;
    TASAudioToken token;
    TASAudioToken wrong;
    TASAudioToken beforeToken;
    TASAudioToken rollback;
    TASAudioToken sample;
    TASAudioToken rejectedToken;
    unsigned long edge;
    unsigned long reservedGeneration;
    audio_controls(&controls, 0);

    CHECK(TASAudioStateInit(&state, kTASAudioRouteSpeaker |
        kTASAudioRouteHeadphone, kTASCodecTAS3001C, kTASQuirkANDedReset,
        &controls) == kTASStatusOK);
    CHECK(TASAudioRecordDetectISR(&state, 1UL, &edge) == kTASStatusOK);
    CHECK(TASAudioBuildDebounceSchedule(&state, edge, 100UL, &plan) ==
        kTASStatusOK);
    CHECK(TASAudioPrepareDebounceSample(&state, edge, 100UL, &plan,
        &sample) == kTASStatusOK);
    CHECK(TASAudioApplyDetectSample(&state, &sample, 1UL, 100UL, &plan,
        &rejectedToken) == kTASStatusUnresolved);
    before = state;
    CHECK(before.debouncePending && before.candidateValid &&
        before.debounceDeadline == 100UL + TAS_AUDIO_DEBOUNCE_CONFIRM_MS);
    CHECK(TASAudioPreparePower(&state, kTASPowerSuspended, 200UL, &plan,
        &token) == kTASStatusOK);
    CHECK(!state.debouncePending && !state.candidateValid);

    reserved = state;
    rejectedToken = token;
    ++rejectedToken.generation;
    newest = reserved;
    beforeToken = rejectedToken;
    CHECK(TASAudioCancelTransition(&reserved, &rejectedToken) ==
        kTASStatusConflict);
    CHECK(memcmp(&reserved, &newest, sizeof(reserved)) == 0);
    CHECK(memcmp(&rejectedToken, &beforeToken, sizeof(rejectedToken)) == 0);

    reserved = state;
    rejectedToken = token;
    CHECK(TASAudioAuthorizeAction(&reserved, &rejectedToken, 0UL) ==
        kTASStatusOK);
    newest = reserved;
    beforeToken = rejectedToken;
    CHECK(TASAudioCancelTransition(&reserved, &rejectedToken) ==
        kTASStatusConflict);
    CHECK(memcmp(&reserved, &newest, sizeof(reserved)) == 0);
    CHECK(memcmp(&rejectedToken, &beforeToken, sizeof(rejectedToken)) == 0);
    CHECK(TASAudioCompleteAction(&reserved, &rejectedToken, 0UL) ==
        kTASStatusOK);
    newest = reserved;
    beforeToken = rejectedToken;
    CHECK(TASAudioCancelTransition(&reserved, &rejectedToken) ==
        kTASStatusConflict);
    CHECK(memcmp(&reserved, &newest, sizeof(reserved)) == 0);
    CHECK(memcmp(&rejectedToken, &beforeToken, sizeof(rejectedToken)) == 0);

    CHECK(TASAudioCancelTransition(&state, &token) == kTASStatusOK);
    CHECK(state.powerState == before.powerState && state.startsBlocked ==
        before.startsBlocked && state.detectGeneration ==
        before.detectGeneration && state.desiredDetects ==
        before.desiredDetects && state.debouncePending ==
        before.debouncePending && state.debounceDeadline ==
        before.debounceDeadline && state.candidateValid ==
        before.candidateValid && state.candidateDetects ==
        before.candidateDetects && state.detectBlocked ==
        before.detectBlocked);
    CHECK(TASAudioPrepareDebounceSample(&state, state.detectGeneration,
        state.debounceDeadline, &plan, &sample) == kTASStatusOK);
    CHECK(TASAudioApplyDetectSample(&state, &sample, 1UL,
        state.debounceDeadline, &plan, &token) == kTASStatusOK);
    audio_complete_plan(&state, &token);
    CHECK(TASAudioCommitTransition(&state, &token) == kTASStatusOK);
    CHECK(state.currentRoutes == kTASAudioRouteHeadphone);

    CHECK(TASAudioStateInit(&state, kTASAudioRouteSpeaker |
        kTASAudioRouteHeadphone, kTASCodecTAS3001C, kTASQuirkANDedReset,
        &controls) == kTASStatusOK);
    CHECK(TASAudioRecordDetectISR(&state, 0UL, &edge) == kTASStatusOK);
    CHECK(TASAudioBuildDebounceSchedule(&state, edge, 300UL, &plan) ==
        kTASStatusOK);
    CHECK(TASAudioPreparePower(&state, kTASPowerSuspended, 400UL, &plan,
        &token) == kTASStatusOK);
    CHECK(TASAudioRecordDetectISR(&state, 1UL, &edge) == kTASStatusOK);
    newest = state;
    CHECK(TASAudioCancelTransition(&state, &token) == kTASStatusOK);
    CHECK(state.powerState == kTASPowerReady && !state.startsBlocked &&
        state.detectGeneration == newest.detectGeneration &&
        state.desiredDetects == newest.desiredDetects &&
        state.debouncePending == newest.debouncePending &&
        state.debounceDeadline == newest.debounceDeadline &&
        state.candidateValid == newest.candidateValid &&
        state.candidateDetects == newest.candidateDetects &&
        state.detectBlocked == newest.detectBlocked);
    CHECK(TASAudioBuildDebounceSchedule(&state, edge, 450UL, &plan) ==
        kTASStatusOK);
    CHECK(TASAudioPrepareDebounceSample(&state, edge, 450UL, &plan,
        &sample) == kTASStatusOK);
    CHECK(TASAudioApplyDetectSample(&state, &sample, 1UL, 450UL, &plan,
        &rejectedToken) == kTASStatusUnresolved);
    CHECK(TASAudioPrepareDebounceSample(&state, state.detectGeneration,
        state.debounceDeadline, &plan, &sample) == kTASStatusOK);
    CHECK(TASAudioApplyDetectSample(&state, &sample, 1UL,
        state.debounceDeadline, &plan, &token) == kTASStatusOK);
    audio_complete_plan(&state, &token);
    CHECK(TASAudioCommitTransition(&state, &token) == kTASStatusOK);
    CHECK(state.currentRoutes == kTASAudioRouteHeadphone);

    CHECK(TASAudioStateInit(&state, kTASAudioRouteSpeaker |
        kTASAudioRouteHeadphone, kTASCodecTAS3001C, kTASQuirkANDedReset,
        &controls) == kTASStatusOK);
    before = state;
    CHECK(TASAudioPrepareRoute(&state, 0UL, &plan, &token) == kTASStatusOK);
    reservedGeneration = state.generation;
    CHECK(TASAudioRecordDetectISR(&state, 1UL, &edge) == kTASStatusOK);
    wrong = token;
    ++wrong.generation;
    reserved = state;
    beforeToken = token;
    CHECK(TASAudioCancelTransition(&state, &wrong) == kTASStatusConflict);
    CHECK(memcmp(&state, &reserved, sizeof(state)) == 0);
    CHECK(memcmp(&token, &beforeToken, sizeof(token)) == 0);
    CHECK(TASAudioCancelTransition(&state, &token) == kTASStatusOK);
    CHECK(!state.transitionPending && state.generation ==
        reservedGeneration + 1UL && state.powerState == before.powerState &&
        state.hardwareValid == before.hardwareValid &&
        memcmp(&state.desired, &before.desired, sizeof(state.desired)) == 0 &&
        state.desiredDetects == 1UL && state.debouncePending);
    CHECK(token.kind == kTASAudioTokenNone);
    CHECK(TASAudioPrepareRoute(&state, 1UL, &plan, &token) == kTASStatusOK);
    audio_complete_plan(&state, &token);
    CHECK(TASAudioCommitTransition(&state, &token) == kTASStatusOK);
    CHECK(state.currentRoutes == kTASAudioRouteHeadphone);

    CHECK(TASAudioPrepareRoute(&state, 0UL, &plan, &token) == kTASStatusOK);
    CHECK(TASAudioAuthorizeAction(&state, &token, 0UL) == kTASStatusOK);
    reserved = state;
    beforeToken = token;
    CHECK(TASAudioCancelTransition(&state, &token) == kTASStatusConflict);
    CHECK(memcmp(&state, &reserved, sizeof(state)) == 0);
    CHECK(memcmp(&token, &beforeToken, sizeof(token)) == 0);
    CHECK(TASAudioCompleteAction(&state, &token, 0UL) == kTASStatusOK);
    beforeToken = token;
    CHECK(TASAudioCancelTransition(&state, &token) == kTASStatusConflict);
    CHECK(memcmp(&token, &beforeToken, sizeof(token)) == 0);
    CHECK(TASAudioFailTransition(&state, &token, 300UL, &rollbackPlan,
        &rollback) == kTASStatusOK);
    CHECK(TASAudioAbortRollback(&state, &rollback) == kTASStatusOK);

    CHECK(TASAudioStateInit(&state, kTASAudioRouteSpeaker |
        kTASAudioRouteHeadphone, kTASCodecTAS3001C, kTASQuirkANDedReset,
        &controls) == kTASStatusOK);
    CHECK(TASAudioPreparePower(&state, kTASPowerOff, 200UL, &plan,
        &token) == kTASStatusOK);
    audio_complete_plan(&state, &token);
    CHECK(TASAudioCommitTransition(&state, &token) == kTASStatusOK);
    before = state;
    CHECK(TASAudioPreparePower(&state, kTASPowerReady, 400UL, &plan,
        &token) == kTASStatusOK);
    reservedGeneration = state.generation;
    CHECK(state.powerState == kTASPowerWaking);
    CHECK(TASAudioRecordDetectISR(&state, 1UL, &edge) == kTASStatusOK);
    CHECK(TASAudioCancelTransition(&state, &token) == kTASStatusOK);
    CHECK(!state.transitionPending && state.generation ==
        reservedGeneration + 1UL && state.powerState == before.powerState &&
        state.startsBlocked == before.startsBlocked &&
        state.hardwareValid == before.hardwareValid &&
        memcmp(&state.desired, &before.desired, sizeof(state.desired)) == 0 &&
        state.desiredDetects == 1UL && state.debouncePending);
    CHECK(TASAudioPreparePower(&state, kTASPowerReady, 500UL, &plan,
        &token) == kTASStatusOK);
    audio_complete_plan(&state, &token);
    CHECK(TASAudioCommitTransition(&state, &token) == kTASStatusOK);
    CHECK(state.powerState == kTASPowerWaking && !state.transitionPending);

    CHECK(TASAudioPrepareDebounceSample(&state, state.detectGeneration,
        500UL, &plan, &sample) == kTASStatusOK);
    CHECK(TASAudioApplyDetectSample(&state, &sample, 1UL, 500UL, &plan,
        &token) == kTASStatusUnresolved);
    CHECK(TASAudioPrepareDebounceSample(&state, state.detectGeneration,
        500UL + TAS_AUDIO_DEBOUNCE_CONFIRM_MS, &plan, &sample) ==
        kTASStatusOK);
    CHECK(TASAudioApplyDetectSample(&state, &sample, 1UL,
        500UL + TAS_AUDIO_DEBOUNCE_CONFIRM_MS, &plan, &token) ==
        kTASStatusOK);
    CHECK(token.kind == kTASAudioTokenWakeRoute && state.transitionPending &&
        !state.debouncePending);
    reserved = state;
    rejectedToken = token;
    CHECK(TASAudioCancelTransition(&reserved, &rejectedToken) ==
        kTASStatusConflict);
    CHECK(memcmp(&reserved, &state, sizeof(state)) == 0);
    CHECK(memcmp(&rejectedToken, &token, sizeof(token)) == 0);

    CHECK(TASAudioRecordDetectISR(&state, 1UL, &edge) == kTASStatusOK);
    CHECK(TASAudioBuildDebounceSchedule(&state, edge, 550UL, &plan) ==
        kTASStatusOK);
    CHECK(TASAudioPrepareDebounceSample(&state, edge, 550UL, &plan,
        &sample) == kTASStatusOK);
    CHECK(TASAudioApplyDetectSample(&state, &sample, 1UL, 550UL, &plan,
        &rejectedToken) == kTASStatusUnresolved);
    CHECK(state.debouncePending && state.candidateValid &&
        state.debounceDeadline == 550UL + TAS_AUDIO_DEBOUNCE_CONFIRM_MS);
    reserved = state;
    rejectedToken = token;
    reserved.debouncePending = 0;
    before = reserved;
    beforeToken = rejectedToken;
    CHECK(TASAudioCancelTransition(&reserved, &rejectedToken) ==
        kTASStatusConflict);
    CHECK(memcmp(&reserved, &before, sizeof(reserved)) == 0);
    CHECK(memcmp(&rejectedToken, &beforeToken, sizeof(rejectedToken)) == 0);
    reserved = state;
    CHECK(TASAudioCancelTransition(&state, &token) == kTASStatusOK);
    CHECK(state.powerState == kTASPowerWaking && state.startsBlocked &&
        !state.transitionPending && state.detectGeneration ==
        reserved.detectGeneration && state.debouncePending ==
        reserved.debouncePending && state.debounceDeadline ==
        reserved.debounceDeadline && state.candidateValid ==
        reserved.candidateValid && state.candidateDetects ==
        reserved.candidateDetects && state.desiredDetects ==
        reserved.desiredDetects);
    CHECK(TASAudioPrepareDebounceSample(&state, state.detectGeneration,
        550UL + TAS_AUDIO_DEBOUNCE_CONFIRM_MS, &plan, &sample) ==
        kTASStatusOK);
    CHECK(TASAudioApplyDetectSample(&state, &sample, 1UL,
        550UL + TAS_AUDIO_DEBOUNCE_CONFIRM_MS, &plan, &token) ==
        kTASStatusOK);
    CHECK(token.kind == kTASAudioTokenWakeRoute);
    audio_complete_plan(&state, &token);
    CHECK(TASAudioCommitTransition(&state, &token) == kTASStatusOK);
    CHECK(state.powerState == kTASPowerReady && !state.startsBlocked);
}

static void test_audio_detect_debounce(void)
{
    TASAudioDesiredControls controls;
    TASAudioState state;
    TASAudioActionPlan plan;
    TASAudioActionPlan routePlan;
    TASAudioToken sample;
    TASAudioToken staleSample;
    TASAudioToken route;
    TASAudioState before;
    TASAudioActionPlan beforePlan;
    TASAudioToken beforeRoute;
    unsigned long first;
    unsigned long latest;
    audio_controls(&controls, 0);
    CHECK(TASAudioStateInit(&state, kTASAudioRouteSpeaker |
        kTASAudioRouteHeadphone | kTASAudioRouteLineOut,
        kTASCodecTAS3004, kTASQuirkNone, &controls) == kTASStatusOK);
    CHECK(TASAudioRecordDetectISR(&state, 0x81UL, &first) == kTASStatusOK);
    CHECK(state.currentRoutes == 0UL && !state.hardwareValid);
    CHECK(TASAudioBuildDebounceSchedule(&state, first, 110UL, &plan) ==
        kTASStatusOK && plan.count == 1UL &&
        plan.actions[0].operation == kTASAudioScheduleDebounce);
    CHECK(TASAudioRecordDetectISR(&state, 2UL, &latest) == kTASStatusOK);
    CHECK(TASAudioPrepareDebounceSample(&state, first, 110UL, &plan,
        &sample) == kTASStatusConflict);
    CHECK(TASAudioPrepareDebounceSample(&state, latest, 109UL, &plan,
        &sample) == kTASStatusTimeout);
    CHECK(TASAudioBuildDebounceSchedule(&state, latest, 120UL, &plan) ==
        kTASStatusOK);
    CHECK(TASAudioPrepareDebounceSample(&state, latest, 120UL, &plan,
        &sample) == kTASStatusOK && plan.count == 1UL &&
        plan.actions[0].operation == kTASAudioSampleDetects);
    staleSample = sample;
    CHECK(TASAudioApplyDetectSample(&state, &sample, 3UL, 150UL, &routePlan,
        &route) == kTASStatusUnresolved);
    latest = state.detectGeneration;
    CHECK(routePlan.count == 1UL && routePlan.actions[0].operation ==
        kTASAudioScheduleDebounce && routePlan.actions[0].deadline ==
        150UL + TAS_AUDIO_DEBOUNCE_CONFIRM_MS);
    CHECK(TASAudioApplyDetectSample(&state, &staleSample, 3UL, 120UL,
        &routePlan,
        &route) == kTASStatusConflict);
    CHECK(TASAudioPrepareDebounceSample(&state, latest,
        150UL + TAS_AUDIO_DEBOUNCE_CONFIRM_MS - 1UL, &plan, &sample) ==
        kTASStatusTimeout);
    CHECK(TASAudioPrepareDebounceSample(&state, latest,
        150UL + TAS_AUDIO_DEBOUNCE_CONFIRM_MS, &plan, &sample) ==
        kTASStatusOK);
    CHECK(TASAudioApplyDetectSample(&state, &sample, 1UL,
        150UL + TAS_AUDIO_DEBOUNCE_CONFIRM_MS, &routePlan,
        &route) == kTASStatusUnresolved);
    latest = state.detectGeneration;
    CHECK(routePlan.actions[0].deadline ==
        150UL + 2UL * TAS_AUDIO_DEBOUNCE_CONFIRM_MS);
    CHECK(TASAudioPrepareDebounceSample(&state, latest,
        150UL + 2UL * TAS_AUDIO_DEBOUNCE_CONFIRM_MS, &plan, &sample) ==
        kTASStatusOK);
    CHECK(TASAudioApplyDetectSample(&state, &sample, 1UL,
        150UL + 2UL * TAS_AUDIO_DEBOUNCE_CONFIRM_MS, &routePlan,
        &route) == kTASStatusOK);
    CHECK(route.targetRoutes == kTASAudioRouteHeadphone);
    audio_complete_plan(&state, &route);
    CHECK(TASAudioCommitTransition(&state, &route) == kTASStatusOK);

    CHECK(TASAudioRecordDetectISR(&state, 2UL, &latest) == kTASStatusOK);
    CHECK(TASAudioBuildDebounceSchedule(&state, latest, ~0UL - 3UL,
        &plan) == kTASStatusOK);
    CHECK(TASAudioPrepareDebounceSample(&state, latest, ~0UL - 3UL, &plan,
        &sample) == kTASStatusOK);
    before = state;
    memset(&routePlan, 0x5a, sizeof(routePlan));
    memset(&route, 0x5a, sizeof(route));
    beforePlan = routePlan;
    beforeRoute = route;
    CHECK(TASAudioApplyDetectSample(&state, &sample, 2UL, ~0UL - 3UL,
        &routePlan,
        &route) == kTASStatusOverflow);
    CHECK(memcmp(&state, &before, sizeof(state)) == 0);
    CHECK(memcmp(&routePlan, &beforePlan, sizeof(routePlan)) == 0);
    CHECK(memcmp(&route, &beforeRoute, sizeof(route)) == 0);

    state.detectGeneration = ~0UL;
    first = state.desiredDetects;
    CHECK(TASAudioRecordDetectISR(&state, 0UL, &latest) ==
        kTASStatusOverflow);
    CHECK(state.detectBlocked && state.desiredDetects == first);
}

static void audio_check_rollback_failures(unsigned long routes,
    TASCodecKind codec, unsigned long quirks, unsigned long expectedCount)
{
    TASAudioDesiredControls controls;
    TASAudioState state;
    TASAudioState before;
    TASAudioActionPlan plan;
    TASAudioActionPlan rollbackPlan;
    TASAudioToken token;
    TASAudioToken rollback;
    unsigned long ordinal;
    audio_controls(&controls, 0);
    for (ordinal = 0UL; ordinal < expectedCount; ++ordinal) {
        CHECK(TASAudioStateInit(&state, routes, codec, quirks, &controls) ==
            kTASStatusOK);
        CHECK(TASAudioPreparePower(&state, kTASPowerOff, 200UL, &plan,
            &token) == kTASStatusOK);
        CHECK(TASAudioAuthorizeAction(&state, &token, 0UL) == kTASStatusOK);
        CHECK(TASAudioFailTransition(&state, &token, 800UL, &rollbackPlan,
            &rollback) == kTASStatusOK);
        CHECK(rollbackPlan.count == expectedCount);
        audio_complete_prefix(&state, &rollback, ordinal);
        CHECK(TASAudioAuthorizeAction(&state, &rollback, ordinal) ==
            kTASStatusOK);
        before = state;
        CHECK(TASAudioCommitRollback(&state, &rollback) ==
            kTASStatusConflict);
        CHECK(memcmp(&state, &before, sizeof(state)) == 0);
        CHECK(TASAudioAbortRollback(&state, &rollback) == kTASStatusOK);
        CHECK(state.powerState == kTASPowerFault && state.rollbackPending &&
            !state.outputsMuteKnown && !state.dmaStoppedKnown);
    }
    CHECK(TASAudioPrepareRollback(&state, 900UL, &rollbackPlan, &rollback) ==
        kTASStatusOK);
    audio_complete_plan(&state, &rollback);
    CHECK(TASAudioCommitRollback(&state, &rollback) == kTASStatusOK);
    CHECK(state.outputsMuteKnown && state.dmaStoppedKnown &&
        !state.rollbackPending);
}

static void test_audio_power_state_machine(void)
{
    static const TASPowerState sleeps[] = {
        kTASPowerStandby, kTASPowerSuspended, kTASPowerOff
    };
    TASAudioDesiredControls controls;
    TASAudioDesiredControls changed;
    TASAudioState state;
    TASAudioState before;
    TASAudioActionPlan plan;
    TASAudioActionPlan failSafe;
    TASAudioActionPlan routePlan;
    TASAudioToken token;
    TASAudioToken beforeToken;
    TASAudioToken sampleToken;
    TASAudioToken routeToken;
    TASAudioToken rollbackToken;
    unsigned long sleepIndex;
    unsigned long ordinal;
    unsigned long index;
    audio_controls(&controls, 0);
    for (sleepIndex = 0UL; sleepIndex < 3UL; ++sleepIndex) {
        CHECK(TASAudioStateInit(&state, kTASAudioRouteSpeaker |
            kTASAudioRouteHeadphone | kTASAudioRouteLineOut,
            kTASCodecTAS3004, kTASQuirkNone, &controls) == kTASStatusOK);
        CHECK(TASAudioPrepareRoute(&state, 1UL, &routePlan, &routeToken) ==
            kTASStatusOK);
        audio_complete_plan(&state, &routeToken);
        CHECK(TASAudioCommitTransition(&state, &routeToken) == kTASStatusOK);
        CHECK(state.currentRoutes == kTASAudioRouteHeadphone);
        state.streamsRunning = 1;
        CHECK(TASAudioPreparePower(&state, sleeps[sleepIndex], 200UL,
            &plan, &token) == kTASStatusOK);
        CHECK(plan.actions[0].operation == kTASAudioBlockStarts);
        CHECK(plan.actions[1].operation == kTASAudioMuteSpeaker);
        CHECK(plan.actions[4].operation == kTASAudioStopOutputDMA);
        CHECK(plan.actions[5].operation == kTASAudioResetOutputDMA);
        CHECK(plan.actions[6].operation == kTASAudioStopInputDMA);
        CHECK(plan.actions[7].operation == kTASAudioResetInputDMA);
        CHECK(plan.actions[8].operation == kTASAudioCodecAnalogLowPower);
        CHECK(plan.actions[9].operation == kTASAudioDisableDetectIRQs);
        CHECK(plan.actions[plan.count - 1UL].operation ==
            kTASAudioGateI2SCell);
        before = state;
        beforeToken = token;
        changed = controls;
        changed.rightVolume = 0x001234UL;
        CHECK(TASAudioSetDesiredControls(&state, &changed) ==
            kTASStatusConflict);
        CHECK(memcmp(&state, &before, sizeof(state)) == 0);
        CHECK(memcmp(&token, &beforeToken, sizeof(token)) == 0);
        audio_complete_plan(&state, &token);
        CHECK(TASAudioCommitTransition(&state, &token) == kTASStatusOK);
        CHECK(state.powerState == sleeps[sleepIndex] && state.startsBlocked &&
            !state.streamsRunning && state.outputsMuted);

        changed = controls;
        changed.leftVolume = 0x001000UL + sleepIndex;
        changed.inputGain = 0x003000UL + sleepIndex;
        CHECK(TASAudioSetDesiredControls(&state, &changed) == kTASStatusOK);
        CHECK(TASAudioPreparePower(&state, kTASPowerReady, 400UL, &plan,
            &token) == kTASStatusOK);
        CHECK(plan.actions[0].operation == kTASAudioMuteSpeaker);
        CHECK(plan.actions[3].operation == kTASAudioEnableI2SCellClock);
        CHECK(plan.actions[4].operation == kTASAudioReleaseReset);
        CHECK(plan.actions[5].operation == kTASAudioApplyI2SRate &&
            plan.actions[5].value == 44100UL);
        CHECK(plan.actions[6].operation == kTASAudioCodecReset);
        CHECK(plan.actions[7].operation == kTASAudioCodecRestore);
        CHECK(plan.actions[8].operation == kTASAudioRebuildOutputDMA);
        CHECK(plan.actions[9].operation == kTASAudioRebuildInputDMA);
        CHECK(!audio_plan_has_unmute_before(&plan, plan.count));
        for (index = 0UL; index < plan.count; ++index)
            CHECK(plan.actions[index].operation != kTASAudioSetOutputMux &&
                plan.actions[index].operation != kTASAudioSetCodecRoute);
        audio_complete_plan(&state, &token);
        CHECK(TASAudioCommitTransition(&state, &token) == kTASStatusOK);
        CHECK(state.powerState == kTASPowerWaking && state.startsBlocked &&
            !state.streamsRunning && state.desired.leftVolume ==
            changed.leftVolume && state.desired.inputGain == changed.inputGain &&
            !state.routeValid && state.currentRoutes == 0UL &&
            state.outputsMuted && state.debouncePending);
        before = state;
        changed = state.desired;
        changed.leftVolume ^= 1UL;
        CHECK(TASAudioSetDesiredControls(&state, &changed) ==
            kTASStatusConflict);
        CHECK(memcmp(&state, &before, sizeof(state)) == 0);
        changed = state.desired;
        changed.rightVolume ^= 1UL;
        CHECK(TASAudioSetDesiredControls(&state, &changed) ==
            kTASStatusConflict);
        CHECK(memcmp(&state, &before, sizeof(state)) == 0);
        changed = state.desired;
        changed.userMuted = !changed.userMuted;
        CHECK(TASAudioSetDesiredControls(&state, &changed) ==
            kTASStatusConflict);
        CHECK(memcmp(&state, &before, sizeof(state)) == 0);
        changed = state.desired;
        changed.inputGain ^= 1UL;
        CHECK(TASAudioSetDesiredControls(&state, &changed) ==
            kTASStatusConflict);
        CHECK(memcmp(&state, &before, sizeof(state)) == 0);
        changed = state.desired;
        changed.inputSource = changed.inputSource == 0UL ? 1UL : 0UL;
        CHECK(TASAudioSetDesiredControls(&state, &changed) ==
            kTASStatusConflict);
        CHECK(memcmp(&state, &before, sizeof(state)) == 0);
        changed = state.desired;
        changed.rate = 48000UL;
        CHECK(TASAudioSetDesiredControls(&state, &changed) ==
            kTASStatusConflict);
        CHECK(memcmp(&state, &before, sizeof(state)) == 0);
        CHECK(TASAudioPrepareDebounceSample(&state, state.detectGeneration,
            400UL, &routePlan, &sampleToken) == kTASStatusOK);
        CHECK(TASAudioApplyDetectSample(&state, &sampleToken, 1UL, 400UL,
            &routePlan, &routeToken) == kTASStatusUnresolved);
        CHECK(TASAudioPrepareDebounceSample(&state, state.detectGeneration,
            400UL + TAS_AUDIO_DEBOUNCE_CONFIRM_MS, &routePlan,
            &sampleToken) == kTASStatusOK);
        CHECK(TASAudioApplyDetectSample(&state, &sampleToken, 1UL,
            400UL + TAS_AUDIO_DEBOUNCE_CONFIRM_MS,
            &routePlan, &routeToken) == kTASStatusOK);
        audio_complete_plan(&state, &routeToken);
        CHECK(TASAudioCommitTransition(&state, &routeToken) == kTASStatusOK);
        CHECK(state.routeValid &&
            state.currentRoutes == kTASAudioRouteHeadphone &&
            state.powerState == kTASPowerReady && !state.startsBlocked);
        changed = state.desired;
        changed.leftVolume ^= 1UL;
        CHECK(TASAudioSetDesiredControls(&state, &changed) == kTASStatusOK);
    }

    CHECK(TASAudioStateInit(&state, kTASAudioRouteSpeaker |
        kTASAudioRouteHeadphone, kTASCodecTAS3001C, kTASQuirkANDedReset,
        &controls) == kTASStatusOK);
    CHECK(TASAudioPreparePower(&state, kTASPowerSuspended, 200UL, &plan,
        &token) == kTASStatusOK);
    CHECK(plan.count == 8UL);
    CHECK(plan.actions[0].operation == kTASAudioBlockStarts);
    CHECK(plan.actions[1].operation == kTASAudioAssertAndedReset);
    CHECK(plan.actions[2].operation == kTASAudioStopOutputDMA);
    CHECK(plan.actions[3].operation == kTASAudioResetOutputDMA);
    CHECK(plan.actions[4].operation == kTASAudioStopInputDMA);
    CHECK(plan.actions[5].operation == kTASAudioResetInputDMA);
    CHECK(plan.actions[6].operation == kTASAudioDisableDetectIRQs);
    CHECK(plan.actions[7].operation == kTASAudioGateI2SCell);
    for (index = 2UL; index < plan.count; ++index)
        CHECK(!audio_action_is_codec(plan.actions[index].operation));
    audio_complete_plan(&state, &token);
    CHECK(TASAudioCommitTransition(&state, &token) == kTASStatusOK);
    CHECK(state.andedResetState == kTASAndedResetAsserted);
    CHECK(TASAudioPreparePower(&state, kTASPowerReady, 400UL, &plan,
        &token) == kTASStatusOK);
    CHECK(plan.count == 12UL);
    CHECK(plan.actions[0].operation == kTASAudioEnableI2SCellClock);
    CHECK(plan.actions[1].operation == kTASAudioReleaseAndedReset);
    CHECK(plan.actions[2].operation == kTASAudioApplyI2SRate);
    CHECK(plan.actions[3].operation == kTASAudioCodecReset);
    CHECK(plan.actions[4].operation == kTASAudioCodecRestore);
    CHECK(plan.actions[5].operation == kTASAudioRebuildOutputDMA);
    CHECK(plan.actions[6].operation == kTASAudioRebuildInputDMA);
    CHECK(plan.actions[7].operation == kTASAudioEnableDetectIRQs);
    CHECK(plan.actions[8].operation == kTASAudioScheduleDebounce);
    CHECK(plan.actions[9].operation == kTASAudioRestoreVolume);
    CHECK(plan.actions[10].operation == kTASAudioRestoreInputSource);
    CHECK(plan.actions[11].operation == kTASAudioRestoreInputGain);
    CHECK(!audio_plan_has_unmute_before(&plan, plan.count));
    audio_complete_plan(&state, &token);
    CHECK(TASAudioCommitTransition(&state, &token) == kTASStatusOK);
    CHECK(state.andedResetState == kTASAndedResetReleased);

    for (ordinal = 0UL; ordinal < plan.count; ++ordinal) {
        CHECK(TASAudioStateInit(&state, kTASAudioRouteSpeaker |
            kTASAudioRouteHeadphone, kTASCodecTAS3001C,
            kTASQuirkANDedReset, &controls) == kTASStatusOK);
        state.streamsRunning = 1;
        CHECK(TASAudioPreparePower(&state, kTASPowerSuspended, 200UL,
            &plan, &token) == kTASStatusOK);
        audio_complete_prefix(&state, &token, ordinal);
        CHECK(TASAudioAuthorizeAction(&state, &token, ordinal) ==
            kTASStatusOK);
        CHECK(TASAudioFailTransition(&state, &token, 500UL, &failSafe,
            &rollbackToken) == kTASStatusOK);
        CHECK(state.powerState == kTASPowerFault && state.startsBlocked &&
            !state.outputsMuteKnown && !state.dmaStoppedKnown &&
            state.rollbackPending &&
            !state.hardwareValid && state.desired.leftVolume ==
            controls.leftVolume);
        for (index = 0UL; index < failSafe.count; ++index)
            if (failSafe.actions[index].operation == kTASAudioStopOutputDMA ||
                failSafe.actions[index].operation == kTASAudioResetOutputDMA ||
                failSafe.actions[index].operation == kTASAudioStopInputDMA ||
                failSafe.actions[index].operation == kTASAudioResetInputDMA)
                CHECK(failSafe.actions[index].deadline == 500UL);
        audio_complete_plan(&state, &rollbackToken);
        CHECK(TASAudioCommitRollback(&state, &rollbackToken) ==
            kTASStatusOK);
    }

    audio_check_rollback_failures(kTASAudioRouteSpeaker |
        kTASAudioRouteHeadphone | kTASAudioRouteLineOut,
        kTASCodecTAS3004, kTASQuirkNone, 7UL);
    audio_check_rollback_failures(kTASAudioRouteSpeaker |
        kTASAudioRouteHeadphone, kTASCodecTAS3001C,
        kTASQuirkANDedReset, 5UL);

    CHECK(TASAudioStateInit(&state, kTASAudioRouteSpeaker |
        kTASAudioRouteHeadphone | kTASAudioRouteLineOut,
        kTASCodecTAS3004, kTASQuirkNone, &controls) == kTASStatusOK);
    CHECK(TASAudioRecordDetectISR(&state, 1UL, &index) == kTASStatusOK);
    CHECK(TASAudioBuildDebounceSchedule(&state, index, 100UL, &plan) ==
        kTASStatusOK);
    CHECK(TASAudioPreparePower(&state, kTASPowerSuspended, 200UL, &plan,
        &token) == kTASStatusOK);
    CHECK(state.startsBlocked && !state.debouncePending);
    CHECK(TASAudioPrepareDebounceSample(&state, index, 200UL, &plan,
        &token) == kTASStatusConflict);
    CHECK(TASAudioPrepareRoute(&state, 1UL, &plan, &token) ==
        kTASStatusConflict);

    CHECK(TASAudioStateInit(&state, kTASAudioRouteSpeaker |
        kTASAudioRouteHeadphone | kTASAudioRouteLineOut,
        kTASCodecTAS3004, kTASQuirkNone, &controls) == kTASStatusOK);
    CHECK(TASAudioPreparePower(&state, kTASPowerOff, 200UL, &plan,
        &token) == kTASStatusOK);
    audio_complete_plan(&state, &token);
    CHECK(TASAudioCommitTransition(&state, &token) == kTASStatusOK);
    CHECK(TASAudioPreparePower(&state, kTASPowerReady, 400UL, &plan,
        &token) == kTASStatusOK);
    for (ordinal = 0UL; ordinal < plan.count; ++ordinal) {
        TASAudioState wakeState;
        TASAudioActionPlan wakePlan;
        TASAudioToken wakeToken;
        CHECK(TASAudioStateInit(&wakeState, kTASAudioRouteSpeaker |
            kTASAudioRouteHeadphone | kTASAudioRouteLineOut,
            kTASCodecTAS3004, kTASQuirkNone, &controls) == kTASStatusOK);
        CHECK(TASAudioPreparePower(&wakeState, kTASPowerOff, 200UL,
            &wakePlan, &wakeToken) == kTASStatusOK);
        audio_complete_plan(&wakeState, &wakeToken);
        CHECK(TASAudioCommitTransition(&wakeState, &wakeToken) ==
            kTASStatusOK);
        CHECK(TASAudioPreparePower(&wakeState, kTASPowerReady, 400UL,
            &wakePlan, &wakeToken) == kTASStatusOK);
        CHECK(ordinal < wakePlan.count);
        audio_complete_prefix(&wakeState, &wakeToken, ordinal);
        CHECK(TASAudioAuthorizeAction(&wakeState, &wakeToken, ordinal) ==
            kTASStatusOK);
        CHECK(TASAudioFailTransition(&wakeState, &wakeToken, 600UL,
            &failSafe, &rollbackToken) == kTASStatusOK);
        CHECK(wakeState.powerState == kTASPowerFault &&
            !wakeState.outputsMuteKnown && !wakeState.dmaStoppedKnown &&
            !wakeState.debouncePending && !wakeState.hardwareValid);
        CHECK(!audio_plan_has_unmute_before(&failSafe, failSafe.count));
        for (index = 0UL; index < failSafe.count; ++index)
            if (failSafe.actions[index].operation == kTASAudioStopOutputDMA ||
                failSafe.actions[index].operation == kTASAudioResetOutputDMA ||
                failSafe.actions[index].operation == kTASAudioStopInputDMA ||
                failSafe.actions[index].operation == kTASAudioResetInputDMA)
                CHECK(failSafe.actions[index].deadline == 600UL);
        audio_complete_plan(&wakeState, &rollbackToken);
        CHECK(TASAudioCommitRollback(&wakeState, &rollbackToken) ==
            kTASStatusOK);
    }

    CHECK(TASAudioStateInit(&state, kTASAudioRouteSpeaker,
        kTASCodecTAS3004, kTASQuirkNone, &controls) == kTASStatusOK);
    state.generation = ~0UL;
    CHECK(TASAudioPrepareRoute(&state, 0UL, &plan, &token) ==
        kTASStatusOverflow);
    CHECK(state.transitionBlocked);
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
    test_codec_multiregister_controls_commit_atomically();
    test_codec_restore_and_volume_state_are_atomic();
    test_dbdma_descriptor_words_and_directions();
    test_dbdma_splits_translation_count_and_periods();
    test_dbdma_rejects_invalid_and_is_atomic();
    test_dbdma_ring_physical_range_is_exact_and_atomic();
    test_dbdma_completion_progression_and_fault_isolation();
    test_dbdma_bounded_transitions();
    test_dbdma_coherency_deadlines_and_reset_restart();
    test_audio_route_state_machine();
    test_audio_detect_debounce();
    test_audio_cancel_transition();
    test_audio_power_state_machine();
    if (failures != 0) {
        fprintf(stderr, "%d TAS audio checks failed\n", failures);
        return 1;
    }
    puts("TAS audio parser checks passed");
    return 0;
}
