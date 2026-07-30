#include <stdio.h>
#include <string.h>

#include <machdep/ppc/PEKeyLargo.h>
#include "../powermac/chips/keylargo_audio.h"

#define ARRAY_COUNT(a) (sizeof(a) / sizeof((a)[0]))

typedef struct {
    char kind;
    unsigned int reg;
    unsigned long value;
} TraceEntry;

typedef struct {
    unsigned char regs[256];
    unsigned char events[16];
    unsigned char acks[16];
    unsigned char data[16];
    unsigned int eventCount;
    unsigned int eventIndex;
    unsigned int dataIndex;
    int stallAt;
    int controllerStarted;
    tvalspec_t now;
    unsigned int fcr1;
    TraceEntry trace[128];
    unsigned int traceCount;
    int lockDepth;
    int callbacksOutsideLock;
} Fake;

static int failures;

#define CHECK(expr) do { \
    if (!(expr)) { \
        printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #expr); \
        failures++; \
    } \
} while (0)

static void trace(Fake *fake, char kind, unsigned int reg,
    unsigned long value)
{
    CHECK(fake->traceCount < ARRAY_COUNT(fake->trace));
    if (fake->traceCount < ARRAY_COUNT(fake->trace)) {
        fake->trace[fake->traceCount].kind = kind;
        fake->trace[fake->traceCount].reg = reg;
        fake->trace[fake->traceCount].value = value;
        fake->traceCount++;
    }
}

static void inside_lock(Fake *fake)
{
    if (fake->lockDepth != 1)
        fake->callbacksOutsideLock++;
}

static unsigned char fake_read8(void *context, unsigned int reg)
{
    Fake *fake = (Fake *)context;
    unsigned char value;

    inside_lock(fake);
    if (reg == kPEKeyWestRegISR && fake->controllerStarted) {
        if (fake->stallAt >= 0 &&
            fake->eventIndex >= (unsigned int)fake->stallAt)
            value = 0;
        else if (fake->eventIndex < fake->eventCount)
            value = fake->events[fake->eventIndex];
        else
            value = 0;
    } else if (reg == kPEKeyWestRegStatus &&
        fake->eventIndex < fake->eventCount) {
        value = fake->acks[fake->eventIndex];
    } else if (reg == kPEKeyWestRegData) {
        value = fake->data[fake->dataIndex++];
    } else {
        value = fake->regs[reg];
    }
    trace(fake, 'r', reg, value);
    return value;
}

static void fake_write8(void *context, unsigned int reg, unsigned char value)
{
    Fake *fake = (Fake *)context;

    inside_lock(fake);
    fake->regs[reg] = value;
    trace(fake, 'w', reg, value);
    if (reg == kPEKeyWestRegControl &&
        value == kPEKeyWestControlTransferAddress)
        fake->controllerStarted = 1;
    if (reg == kPEKeyWestRegISR && value != 0 &&
        fake->eventIndex < fake->eventCount &&
        value == fake->events[fake->eventIndex])
        fake->eventIndex++;
}

static unsigned int fake_read_fcr1(void *context)
{
    Fake *fake = (Fake *)context;

    inside_lock(fake);
    trace(fake, 'f', 0, fake->fcr1);
    return fake->fcr1;
}

static void fake_write_fcr1(void *context, unsigned int value)
{
    Fake *fake = (Fake *)context;

    inside_lock(fake);
    fake->fcr1 = value;
    trace(fake, 'F', 0, value);
}

static void fake_get_time(void *context, tvalspec_t *now)
{
    Fake *fake = (Fake *)context;

    inside_lock(fake);
    *now = fake->now;
    fake->now.tv_nsec++;
    trace(fake, 't', 0, now->tv_nsec);
}

static int fake_compare_time(void *context, const tvalspec_t *left,
    const tvalspec_t *right)
{
    Fake *fake = (Fake *)context;

    inside_lock(fake);
    trace(fake, 'c', 0, left->tv_nsec);
    if (left->tv_sec != right->tv_sec)
        return left->tv_sec < right->tv_sec ? -1 : 1;
    if (left->tv_nsec == right->tv_nsec)
        return 0;
    return left->tv_nsec < right->tv_nsec ? -1 : 1;
}

static void fake_lock(void *context)
{
    Fake *fake = (Fake *)context;

    CHECK(fake->lockDepth == 0);
    fake->lockDepth++;
    trace(fake, 'L', 0, 0);
}

static void fake_unlock(void *context)
{
    Fake *fake = (Fake *)context;

    CHECK(fake->lockDepth == 1);
    trace(fake, 'U', 0, 0);
    fake->lockDepth--;
}

static PEKeyLargoTransport transport_for(Fake *fake)
{
    PEKeyLargoTransport transport;

    transport.context = fake;
    transport.read8 = fake_read8;
    transport.write8 = fake_write8;
    transport.readFCR1LE = fake_read_fcr1;
    transport.writeFCR1LE = fake_write_fcr1;
    transport.getTime = fake_get_time;
    transport.compareTime = fake_compare_time;
    transport.lock = fake_lock;
    transport.unlock = fake_unlock;
    return transport;
}

static void init_fake(Fake *fake)
{
    memset(fake, 0, sizeof(*fake));
    fake->stallAt = -1;
}

static PEKeyWestI2CRequest request_for(unsigned char *buffer,
    unsigned int length, PEKeyWestDirection direction)
{
    PEKeyWestI2CRequest request;

    request.port = 2;
    request.address = 0x34;
    request.subaddress = 0x15;
    request.direction = direction;
    request.buffer = buffer;
    request.length = length;
    request.deadline.tv_sec = 0;
    request.deadline.tv_nsec = 20;
    return request;
}

static int saw_write(const Fake *fake, unsigned int reg, unsigned long value)
{
    unsigned int i;

    for (i = 0; i < fake->traceCount; i++) {
        if (fake->trace[i].kind == 'w' && fake->trace[i].reg == reg &&
            fake->trace[i].value == value)
            return 1;
    }
    return 0;
}

static void expect_serialized_and_clean(const Fake *fake)
{
    CHECK(fake->traceCount >= 2);
    CHECK(fake->trace[0].kind == 'L');
    CHECK(fake->trace[fake->traceCount - 1].kind == 'U');
    CHECK(fake->callbacksOutsideLock == 0);
    CHECK(fake->lockDepth == 0);
    CHECK(saw_write(fake, kPEKeyWestRegControl, kPEKeyWestControlStop));
    CHECK(saw_write(fake, kPEKeyWestRegControl, 0));
    CHECK(saw_write(fake, kPEKeyWestRegIER, 0));
}

static void test_keywest_write_success(void)
{
    Fake fake;
    PEKeyLargoTransport transport;
    PEKeyWestI2CRequest request;
    unsigned char bytes[2] = { 0xa5, 0x5a };

    init_fake(&fake);
    fake.events[0] = kPEKeyWestInterruptAddress;
    fake.events[1] = kPEKeyWestInterruptData;
    fake.events[2] = kPEKeyWestInterruptData;
    fake.events[3] = kPEKeyWestInterruptStop;
    fake.acks[0] = kPEKeyWestStatusLastACK;
    fake.acks[1] = kPEKeyWestStatusLastACK;
    fake.acks[2] = kPEKeyWestStatusLastACK;
    fake.eventCount = 4;
    transport = transport_for(&fake);
    request = request_for(bytes, 2, kPEKeyWestWrite);

    CHECK(PEKeyWestI2CTransferCore(&transport, &request) == KERN_SUCCESS);
    CHECK(saw_write(&fake, kPEKeyWestRegMode,
        (2U << 4) | kPEKeyWestModeStandardSubaddress));
    CHECK(saw_write(&fake, kPEKeyWestRegAddress, 0x68));
    CHECK(!saw_write(&fake, kPEKeyWestRegAddress, 0x34));
    CHECK(saw_write(&fake, kPEKeyWestRegSubaddress, 0x15));
    CHECK(saw_write(&fake, kPEKeyWestRegData, 0xa5));
    CHECK(saw_write(&fake, kPEKeyWestRegData, 0x5a));
    expect_serialized_and_clean(&fake);
}

static void test_keywest_read_success(void)
{
    Fake fake;
    PEKeyLargoTransport transport;
    PEKeyWestI2CRequest request;
    unsigned char bytes[2] = { 0, 0 };

    init_fake(&fake);
    fake.events[0] = kPEKeyWestInterruptAddress;
    fake.events[1] = kPEKeyWestInterruptData;
    fake.events[2] = kPEKeyWestInterruptData;
    fake.events[3] = kPEKeyWestInterruptStop;
    fake.acks[0] = kPEKeyWestStatusLastACK;
    fake.data[0] = 0x31;
    fake.data[1] = 0x42;
    fake.eventCount = 4;
    transport = transport_for(&fake);
    request = request_for(bytes, 2, kPEKeyWestRead);

    CHECK(PEKeyWestI2CTransferCore(&transport, &request) == KERN_SUCCESS);
    CHECK(bytes[0] == 0x31 && bytes[1] == 0x42);
    CHECK(saw_write(&fake, kPEKeyWestRegMode,
        (2U << 4) | kPEKeyWestModeCombined));
    CHECK(saw_write(&fake, kPEKeyWestRegAddress, 0x69));
    CHECK(saw_write(&fake, kPEKeyWestRegControl,
        kPEKeyWestControlSendACK));
    expect_serialized_and_clean(&fake);
}

static void test_keywest_nacks(void)
{
    Fake fake;
    PEKeyLargoTransport transport;
    PEKeyWestI2CRequest request;
    unsigned char byte = 0x55;

    init_fake(&fake);
    fake.events[0] = kPEKeyWestInterruptAddress;
    fake.events[1] = kPEKeyWestInterruptStop;
    fake.eventCount = 2;
    transport = transport_for(&fake);
    request = request_for(&byte, 1, kPEKeyWestWrite);
    CHECK(PEKeyWestI2CTransferCore(&transport, &request) ==
        KERN_PE_KEYWEST_NACK);
    expect_serialized_and_clean(&fake);

    init_fake(&fake);
    fake.events[0] = kPEKeyWestInterruptAddress;
    fake.events[1] = kPEKeyWestInterruptData;
    fake.events[2] = kPEKeyWestInterruptStop;
    fake.acks[0] = kPEKeyWestStatusLastACK;
    fake.eventCount = 3;
    transport = transport_for(&fake);
    CHECK(PEKeyWestI2CTransferCore(&transport, &request) ==
        KERN_PE_KEYWEST_NACK);
    expect_serialized_and_clean(&fake);
}

static void test_keywest_initial_busy(void)
{
    Fake fake;
    PEKeyLargoTransport transport;
    PEKeyWestI2CRequest request;
    unsigned char byte = 0;

    init_fake(&fake);
    fake.regs[kPEKeyWestRegStatus] = kPEKeyWestStatusBusy;
    transport = transport_for(&fake);
    request = request_for(&byte, 1, kPEKeyWestRead);
    CHECK(PEKeyWestI2CTransferCore(&transport, &request) ==
        KERN_PE_KEYWEST_BUSY);
    expect_serialized_and_clean(&fake);
}

static void test_keywest_timeout_at_every_phase(void)
{
    int phase;

    for (phase = 0; phase < 4; phase++) {
        Fake fake;
        PEKeyLargoTransport transport;
        PEKeyWestI2CRequest request;
        unsigned char bytes[2] = { 1, 2 };

        init_fake(&fake);
        fake.events[0] = kPEKeyWestInterruptAddress;
        fake.events[1] = kPEKeyWestInterruptData;
        fake.events[2] = kPEKeyWestInterruptData;
        fake.events[3] = kPEKeyWestInterruptStop;
        fake.acks[0] = kPEKeyWestStatusLastACK;
        fake.acks[1] = kPEKeyWestStatusLastACK;
        fake.acks[2] = kPEKeyWestStatusLastACK;
        fake.eventCount = 4;
        fake.stallAt = phase;
        transport = transport_for(&fake);
        request = request_for(bytes, 2, kPEKeyWestWrite);
        request.deadline.tv_nsec = 3;
        CHECK(PEKeyWestI2CTransferCore(&transport, &request) ==
            KERN_PE_KEYWEST_TIMEOUT);
        expect_serialized_and_clean(&fake);
    }
}

static void test_gpio_polarities_and_semantics(void)
{
    Fake fake;
    PEKeyLargoTransport transport;
    PEAudioGPIO high;
    PEAudioGPIO low;
    boolean_t active;

    init_fake(&fake);
    transport = transport_for(&fake);
    high.offset = 0x70;
    high.activeHigh = TRUE;
    low.offset = 0x71;
    low.activeHigh = FALSE;
    fake.regs[high.offset] = kPEAudioGPIOInputData | 0x80;
    fake.regs[low.offset] = 0x80;
    CHECK(PEAudioGPIOReadCore(&transport, &high, &active) == KERN_SUCCESS);
    CHECK(active == TRUE);
    CHECK(PEAudioGPIOReadCore(&transport, &low, &active) == KERN_SUCCESS);
    CHECK(active == TRUE);

    fake.regs[high.offset] = 0x80;
    fake.regs[low.offset] = 0x80;
    CHECK(PEAudioGPIOWriteCore(&transport, &high, TRUE) == KERN_SUCCESS);
    CHECK(fake.regs[high.offset] ==
        (0x80 | kPEAudioGPIOOutputEnable | kPEAudioGPIOOutputData));
    CHECK(PEAudioGPIOWriteCore(&transport, &low, TRUE) == KERN_SUCCESS);
    CHECK(fake.regs[low.offset] == (0x80 | kPEAudioGPIOOutputEnable));
    CHECK(PEAudioGPIOWriteCore(&transport, &high, FALSE) == KERN_SUCCESS);
    CHECK(fake.regs[high.offset] == (0x80 | kPEAudioGPIOOutputEnable));
    CHECK(PEAudioGPIOWriteCore(&transport, &low, FALSE) == KERN_SUCCESS);
    CHECK(fake.regs[low.offset] ==
        (0x80 | kPEAudioGPIOOutputEnable | kPEAudioGPIOOutputData));
    CHECK(fake.callbacksOutsideLock == 0);
}

static unsigned int cell_mask(unsigned int cell)
{
    unsigned int shift = cell == 0 ? 10 : 17;
    return 15U << shift;
}

static unsigned int expected_state(unsigned int cell, PEI2SCellState state)
{
    unsigned int shift = cell == 0 ? 10 : 17;
    unsigned int cellBit = 1U << shift;
    unsigned int resetBit = 1U << (shift + 1);
    unsigned int clockBit = 1U << (shift + 2);
    unsigned int interfaceBit = 1U << (shift + 3);

    if (state == kPEI2SCellDisabledReset)
        return resetBit;
    if (state == kPEI2SCellEnabledClockHeld)
        return resetBit | clockBit | cellBit | interfaceBit;
    return clockBit | cellBit | interfaceBit;
}

static void test_i2s_states_preserve_bits_and_order(void)
{
    unsigned int cell;
    PEI2SCellState state;

    for (cell = 0; cell < 2; cell++) {
        for (state = kPEI2SCellDisabledReset;
            state <= kPEI2SCellRunning; state++) {
            Fake fake;
            PEKeyLargoTransport transport;
            unsigned int unrelated = 0x80000001U;
            unsigned int mask = cell_mask(cell);
            unsigned int expected = expected_state(cell, state);
            unsigned int writes[4];
            unsigned int writeCount = 0;
            unsigned int shift = cell == 0 ? 10 : 17;
            unsigned int cellBit = 1U << shift;
            unsigned int resetBit = 1U << (shift + 1);
            unsigned int clockBit = 1U << (shift + 2);
            unsigned int interfaceBit = 1U << (shift + 3);
            unsigned int i;

            init_fake(&fake);
            if (state == kPEI2SCellDisabledReset)
                fake.fcr1 = unrelated |
                    expected_state(cell, kPEI2SCellRunning);
            else
                fake.fcr1 = unrelated |
                    expected_state(cell, kPEI2SCellDisabledReset);
            transport = transport_for(&fake);
            CHECK(PEI2SSetCellStateCore(&transport, cell, state) ==
                KERN_SUCCESS);
            CHECK((fake.fcr1 & ~mask) == unrelated);
            CHECK((fake.fcr1 & mask) == expected);
            for (i = 0; i < fake.traceCount; i++) {
                if (fake.trace[i].kind == 'F') {
                    CHECK(writeCount < ARRAY_COUNT(writes));
                    if (writeCount < ARRAY_COUNT(writes))
                        writes[writeCount++] =
                            (unsigned int)fake.trace[i].value & mask;
                }
            }
            if (state == kPEI2SCellDisabledReset) {
                CHECK(writeCount == 4);
                CHECK(writes[0] == mask);
                CHECK(writes[1] ==
                    (resetBit | clockBit | cellBit));
                CHECK(writes[2] == (resetBit | clockBit));
                CHECK(writes[3] == resetBit);
            } else {
                CHECK(writeCount ==
                    (state == kPEI2SCellRunning ? 4U : 3U));
                CHECK(writes[0] == (resetBit | clockBit));
                CHECK(writes[1] ==
                    (resetBit | clockBit | cellBit));
                CHECK(writes[2] == (resetBit | clockBit | cellBit |
                    interfaceBit));
                if (state == kPEI2SCellRunning)
                    CHECK(writes[3] ==
                        (clockBit | cellBit | interfaceBit));
            }
            CHECK(fake.trace[0].kind == 'L');
            CHECK(fake.trace[fake.traceCount - 1].kind == 'U');
            CHECK(fake.callbacksOutsideLock == 0);
        }
    }
}

static void test_public_wrappers_are_not_ready(void)
{
    PEKeyWestI2CRequest request;
    PEAudioGPIO gpio;
    boolean_t active;
    unsigned char byte = 0;

    request = request_for(&byte, 1, kPEKeyWestWrite);
    gpio.offset = 0;
    gpio.activeHigh = TRUE;
    CHECK(PEKeyWestI2CTransfer(&request) == KERN_PE_KEYLARGO_NOT_READY);
    CHECK(PEAudioGPIORead(&gpio, &active) == KERN_PE_KEYLARGO_NOT_READY);
    CHECK(PEAudioGPIOWrite(&gpio, TRUE) == KERN_PE_KEYLARGO_NOT_READY);
    CHECK(PEI2SSetCellState(0, kPEI2SCellRunning) ==
        KERN_PE_KEYLARGO_NOT_READY);
}

int main(void)
{
    test_keywest_write_success();
    test_keywest_read_success();
    test_keywest_nacks();
    test_keywest_initial_busy();
    test_keywest_timeout_at_every_phase();
    test_gpio_polarities_and_semantics();
    test_i2s_states_preserve_bits_and_order();
    test_public_wrappers_are_not_ready();
    if (failures != 0) {
        printf("pe_keylargo_test: %d failure(s)\n", failures);
        return 1;
    }
    printf("pe_keylargo_test: all tests passed\n");
    return 0;
}
