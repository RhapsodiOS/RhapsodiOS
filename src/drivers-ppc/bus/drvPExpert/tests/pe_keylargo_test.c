#include <stdio.h>
#include <string.h>

#include <machdep/ppc/PEKeyLargo.h>
#include "../powermac/chips/keylargo_audio.h"

#define ARRAY_COUNT(a) (sizeof(a) / sizeof((a)[0]))
#define EXPECTED_PE_KEYLARGO_SUBSYSTEM 4001

typedef char pe_nack_abi_value[
    KERN_PE_KEYWEST_NACK ==
    (err_kern | err_sub(EXPECTED_PE_KEYLARGO_SUBSYSTEM) | 1) ? 1 : -1];
typedef char pe_busy_abi_value[
    KERN_PE_KEYWEST_BUSY ==
    (err_kern | err_sub(EXPECTED_PE_KEYLARGO_SUBSYSTEM) | 2) ? 1 : -1];
typedef char pe_arbitration_abi_value[
    KERN_PE_KEYWEST_ARBITRATION_LOST ==
    (err_kern | err_sub(EXPECTED_PE_KEYLARGO_SUBSYSTEM) | 3) ? 1 : -1];
typedef char pe_timeout_abi_value[
    KERN_PE_KEYWEST_TIMEOUT ==
    (err_kern | err_sub(EXPECTED_PE_KEYLARGO_SUBSYSTEM) | 4) ? 1 : -1];
typedef char pe_not_ready_abi_value[
    KERN_PE_KEYLARGO_NOT_READY ==
    (err_kern | err_sub(EXPECTED_PE_KEYLARGO_SUBSYSTEM) | 5) ? 1 : -1];

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
    int directionRead;
    int eventPresented;
    int dataWritten;
    int dataRead;
    int readDataCompleted;
    int stopIssued;
    int arbitrationAt;
    int invalidTransitions;
    unsigned int timeReads;
    tvalspec_t now;
    unsigned int fcr1;
    TraceEntry trace[128];
    unsigned int traceCount;
    int lockDepth;
    int callbacksOutsideLock;
    int interruptContext;
    unsigned int maxOffset;
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

static unsigned int remaining_data_events(const Fake *fake)
{
    unsigned int index;
    unsigned int count = 0;

    for (index = fake->eventIndex; index < fake->eventCount; index++) {
        if (fake->events[index] == kPEKeyWestInterruptData)
            count++;
    }
    return count;
}

static int event_is_ready(const Fake *fake)
{
    unsigned char event;
    unsigned int remaining;

    if (!fake->controllerStarted || fake->eventIndex >= fake->eventCount)
        return 0;
    event = fake->events[fake->eventIndex];
    if (event == kPEKeyWestInterruptAddress)
        return fake->eventIndex == 0;
    if (event == kPEKeyWestInterruptData) {
        if (!fake->directionRead)
            return fake->dataWritten;
        remaining = remaining_data_events(fake);
        if (remaining > 1)
            return (fake->regs[kPEKeyWestRegControl] &
                kPEKeyWestControlSendACK) != 0;
        return (fake->regs[kPEKeyWestRegControl] &
            kPEKeyWestControlSendACK) == 0;
    }
    if (event == kPEKeyWestInterruptStop)
        return (fake->directionRead && fake->readDataCompleted) ||
            fake->stopIssued;
    return 0;
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
        else if (event_is_ready(fake)) {
            value = fake->events[fake->eventIndex];
            fake->eventPresented = 1;
        } else
            value = 0;
    } else if (reg == kPEKeyWestRegStatus && fake->eventPresented &&
        fake->eventIndex < fake->eventCount) {
        value = fake->acks[fake->eventIndex];
    } else if (reg == kPEKeyWestRegData) {
        if (!fake->eventPresented || !fake->directionRead ||
            fake->events[fake->eventIndex] != kPEKeyWestInterruptData)
            fake->invalidTransitions++;
        fake->dataRead = 1;
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
        value == kPEKeyWestControlTransferAddress) {
        fake->controllerStarted = 1;
        fake->directionRead =
            (fake->regs[kPEKeyWestRegAddress] & 1) != 0;
    }
    if (reg == kPEKeyWestRegControl &&
        value == kPEKeyWestControlStop)
        fake->stopIssued = 1;
    if (reg == kPEKeyWestRegControl && value == 0 &&
        fake->directionRead && fake->eventPresented &&
        fake->eventIndex < fake->eventCount &&
        fake->events[fake->eventIndex] == kPEKeyWestInterruptData &&
        remaining_data_events(fake) > 1)
        fake->invalidTransitions++;
    if (reg == kPEKeyWestRegData) {
        if (!fake->controllerStarted || fake->directionRead ||
            fake->eventIndex >= fake->eventCount ||
            fake->events[fake->eventIndex] != kPEKeyWestInterruptData)
            fake->invalidTransitions++;
        fake->dataWritten = 1;
    }
    if (reg == kPEKeyWestRegISR && value != 0 &&
        fake->eventIndex < fake->eventCount &&
        value == fake->events[fake->eventIndex] &&
        fake->eventPresented) {
        if (value == kPEKeyWestInterruptData && fake->directionRead &&
            !fake->dataRead)
            fake->invalidTransitions++;
        if (value == kPEKeyWestInterruptData && fake->directionRead &&
            remaining_data_events(fake) == 1)
            fake->readDataCompleted = 1;
        fake->eventIndex++;
        fake->eventPresented = 0;
        fake->dataWritten = 0;
        fake->dataRead = 0;
    }
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
    fake->timeReads++;
    fake->now.tv_nsec++;
    if (fake->now.tv_nsec >= NSEC_PER_SEC) {
        fake->now.tv_nsec = 0;
        fake->now.tv_sec++;
    }
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

static kern_return_t fake_transfer_status(void *context)
{
    Fake *fake = (Fake *)context;

    inside_lock(fake);
    trace(fake, 'e', 0, fake->eventIndex);
    if (fake->arbitrationAt >= 0 &&
        fake->eventIndex >= (unsigned int)fake->arbitrationAt)
        return KERN_PE_KEYWEST_ARBITRATION_LOST;
    return KERN_SUCCESS;
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

static boolean_t fake_in_interrupt(void *context)
{
    Fake *fake = (Fake *)context;

    return fake->interruptContext ? TRUE : FALSE;
}

static boolean_t fake_valid_offset(void *context, unsigned int offset,
    unsigned int length)
{
    Fake *fake = (Fake *)context;

    return length != 0 && offset < fake->maxOffset &&
        length <= fake->maxOffset - offset;
}

static PEKeyLargoTransport transport_for(Fake *fake)
{
    PEKeyLargoTransport transport;

    transport.speed = kPEKeyWestSpeed100kHz;
    transport.context = fake;
    transport.read8 = fake_read8;
    transport.write8 = fake_write8;
    transport.readGPIO8 = fake_read8;
    transport.writeGPIO8 = fake_write8;
    transport.readFCR1LE = fake_read_fcr1;
    transport.writeFCR1LE = fake_write_fcr1;
    transport.getTime = fake_get_time;
    transport.compareTime = fake_compare_time;
    transport.transferStatus = fake_transfer_status;
    transport.lock = fake_lock;
    transport.unlock = fake_unlock;
    transport.inInterruptContext = fake_in_interrupt;
    transport.validOffset = fake_valid_offset;
    return transport;
}

static void init_fake(Fake *fake)
{
    memset(fake, 0, sizeof(*fake));
    fake->stallAt = -1;
    fake->arbitrationAt = -1;
    fake->maxOffset = sizeof(fake->regs);
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

static unsigned int count_writes(const Fake *fake, unsigned int reg,
    unsigned long value)
{
    unsigned int index;
    unsigned int count = 0;

    for (index = 0; index < fake->traceCount; index++) {
        if (fake->trace[index].kind == 'w' &&
            fake->trace[index].reg == reg &&
            fake->trace[index].value == value)
            count++;
    }
    return count;
}

static void expect_trace_in_order(const Fake *fake,
    const TraceEntry *expected, unsigned int expectedCount)
{
    unsigned int actualIndex = 0;
    unsigned int expectedIndex;

    for (expectedIndex = 0; expectedIndex < expectedCount;
        expectedIndex++) {
        while (actualIndex < fake->traceCount &&
            (fake->trace[actualIndex].kind != expected[expectedIndex].kind ||
            fake->trace[actualIndex].reg != expected[expectedIndex].reg ||
            fake->trace[actualIndex].value !=
            expected[expectedIndex].value))
            actualIndex++;
        CHECK(actualIndex < fake->traceCount);
        if (actualIndex < fake->traceCount)
            actualIndex++;
    }
}

static void expect_cleanup_order(const Fake *fake)
{
    static const TraceEntry expected[] = {
        { 'w', kPEKeyWestRegControl, 0 },
        { 'w', kPEKeyWestRegIER, 0 },
        { 'w', kPEKeyWestRegStatus, 0 },
        { 'w', kPEKeyWestRegISR, kPEKeyWestInterruptMask },
        { 'U', 0, 0 }
    };
    unsigned int start;
    unsigned int index;

    CHECK(fake->traceCount >= ARRAY_COUNT(expected));
    if (fake->traceCount < ARRAY_COUNT(expected))
        return;
    start = fake->traceCount - ARRAY_COUNT(expected);
    for (index = 0; index < ARRAY_COUNT(expected); index++) {
        CHECK(fake->trace[start + index].kind == expected[index].kind);
        CHECK(fake->trace[start + index].reg == expected[index].reg);
        CHECK(fake->trace[start + index].value == expected[index].value);
    }
}

static void expect_serialized_and_clean(const Fake *fake)
{
    CHECK(fake->traceCount >= 2);
    CHECK(fake->trace[0].kind == 'L');
    CHECK(fake->trace[fake->traceCount - 1].kind == 'U');
    CHECK(fake->callbacksOutsideLock == 0);
    CHECK(fake->lockDepth == 0);
    CHECK(saw_write(fake, kPEKeyWestRegControl, kPEKeyWestControlStop));
    CHECK(count_writes(fake, kPEKeyWestRegControl,
        kPEKeyWestControlStop) == 1);
    CHECK(saw_write(fake, kPEKeyWestRegControl, 0));
    CHECK(saw_write(fake, kPEKeyWestRegIER, 0));
    CHECK(fake->invalidTransitions == 0);
    expect_cleanup_order(fake);
}

static void test_error_abi_values(void)
{
    kern_return_t errors[5];
    unsigned int index;
    unsigned int other;

    errors[0] = KERN_PE_KEYWEST_NACK;
    errors[1] = KERN_PE_KEYWEST_BUSY;
    errors[2] = KERN_PE_KEYWEST_ARBITRATION_LOST;
    errors[3] = KERN_PE_KEYWEST_TIMEOUT;
    errors[4] = KERN_PE_KEYLARGO_NOT_READY;
    for (index = 0; index < ARRAY_COUNT(errors); index++) {
        CHECK(err_get_system(errors[index]) == err_get_system(err_kern));
        CHECK(err_get_sub(errors[index]) ==
            EXPECTED_PE_KEYLARGO_SUBSYSTEM);
        CHECK(err_get_code(errors[index]) == (int)(index + 1));
        for (other = index + 1; other < ARRAY_COUNT(errors); other++)
            CHECK(errors[index] != errors[other]);
    }
}

static void test_keywest_write_success(void)
{
    Fake fake;
    PEKeyLargoTransport transport;
    PEKeyWestI2CRequest request;
    unsigned char bytes[2] = { 0xa5, 0x5a };
    static const TraceEntry expected[] = {
        { 'w', kPEKeyWestRegMode,
            (2U << 4) | kPEKeyWestModeStandardSubaddress },
        { 'w', kPEKeyWestRegAddress, 0x68 },
        { 'w', kPEKeyWestRegSubaddress, 0x15 },
        { 'w', kPEKeyWestRegControl,
            kPEKeyWestControlTransferAddress },
        { 'w', kPEKeyWestRegData, 0xa5 },
        { 'w', kPEKeyWestRegData, 0x5a },
        { 'w', kPEKeyWestRegControl, kPEKeyWestControlStop }
    };

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
    expect_trace_in_order(&fake, expected, ARRAY_COUNT(expected));
    expect_serialized_and_clean(&fake);
}

static void test_keywest_read_success(void)
{
    Fake fake;
    PEKeyLargoTransport transport;
    PEKeyWestI2CRequest request;
    unsigned char bytes[2] = { 0, 0 };
    static const TraceEntry expected[] = {
        { 'w', kPEKeyWestRegMode, (2U << 4) | kPEKeyWestModeCombined },
        { 'w', kPEKeyWestRegAddress, 0x69 },
        { 'w', kPEKeyWestRegSubaddress, 0x15 },
        { 'w', kPEKeyWestRegControl,
            kPEKeyWestControlTransferAddress },
        { 'w', kPEKeyWestRegControl, kPEKeyWestControlSendACK },
        { 'r', kPEKeyWestRegData, 0x31 },
        { 'w', kPEKeyWestRegISR, kPEKeyWestInterruptData },
        { 'w', kPEKeyWestRegControl, 0 },
        { 'r', kPEKeyWestRegData, 0x42 },
        { 'w', kPEKeyWestRegControl, kPEKeyWestControlStop }
    };

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
    expect_trace_in_order(&fake, expected, ARRAY_COUNT(expected));
    expect_serialized_and_clean(&fake);
}

static void test_keywest_one_byte_read_order(void)
{
    Fake fake;
    PEKeyLargoTransport transport;
    PEKeyWestI2CRequest request;
    unsigned char byte = 0;
    static const TraceEntry expected[] = {
        { 'w', kPEKeyWestRegControl,
            kPEKeyWestControlTransferAddress },
        { 'r', kPEKeyWestRegData, 0x7c },
        { 'w', kPEKeyWestRegControl, kPEKeyWestControlStop },
        { 'w', kPEKeyWestRegControl, 0 }
    };

    init_fake(&fake);
    fake.events[0] = kPEKeyWestInterruptAddress;
    fake.events[1] = kPEKeyWestInterruptData;
    fake.events[2] = kPEKeyWestInterruptStop;
    fake.acks[0] = kPEKeyWestStatusLastACK;
    fake.data[0] = 0x7c;
    fake.eventCount = 3;
    transport = transport_for(&fake);
    request = request_for(&byte, 1, kPEKeyWestRead);

    CHECK(PEKeyWestI2CTransferCore(&transport, &request) == KERN_SUCCESS);
    CHECK(byte == 0x7c);
    CHECK(!saw_write(&fake, kPEKeyWestRegControl,
        kPEKeyWestControlSendACK));
    expect_trace_in_order(&fake, expected, ARRAY_COUNT(expected));
    expect_serialized_and_clean(&fake);
}

static void test_keywest_nacks(void)
{
    Fake fake;
    PEKeyLargoTransport transport;
    PEKeyWestI2CRequest request;
    unsigned char byte = 0x55;
    static const TraceEntry addressNACK[] = {
        { 'w', kPEKeyWestRegControl,
            kPEKeyWestControlTransferAddress },
        { 'r', kPEKeyWestRegISR, kPEKeyWestInterruptAddress },
        { 'r', kPEKeyWestRegStatus, 0 },
        { 'w', kPEKeyWestRegISR, kPEKeyWestInterruptAddress },
        { 'w', kPEKeyWestRegControl, kPEKeyWestControlStop },
        { 'r', kPEKeyWestRegISR, kPEKeyWestInterruptStop }
    };
    static const TraceEntry dataNACK[] = {
        { 'w', kPEKeyWestRegData, 0x55 },
        { 'r', kPEKeyWestRegISR, kPEKeyWestInterruptData },
        { 'r', kPEKeyWestRegStatus, 0 },
        { 'w', kPEKeyWestRegISR, kPEKeyWestInterruptData },
        { 'w', kPEKeyWestRegControl, kPEKeyWestControlStop },
        { 'r', kPEKeyWestRegISR, kPEKeyWestInterruptStop }
    };

    init_fake(&fake);
    fake.events[0] = kPEKeyWestInterruptAddress;
    fake.events[1] = kPEKeyWestInterruptStop;
    fake.eventCount = 2;
    transport = transport_for(&fake);
    request = request_for(&byte, 1, kPEKeyWestWrite);
    CHECK(PEKeyWestI2CTransferCore(&transport, &request) ==
        KERN_PE_KEYWEST_NACK);
    expect_trace_in_order(&fake, addressNACK, ARRAY_COUNT(addressNACK));
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
    expect_trace_in_order(&fake, dataNACK, ARRAY_COUNT(dataNACK));
    expect_serialized_and_clean(&fake);
}

static void test_keywest_arbitration_loss(void)
{
    Fake fake;
    PEKeyLargoTransport transport;
    PEKeyWestI2CRequest request;
    unsigned char byte = 0x55;

    init_fake(&fake);
    fake.events[0] = kPEKeyWestInterruptAddress;
    fake.events[1] = kPEKeyWestInterruptData;
    fake.events[2] = kPEKeyWestInterruptStop;
    fake.acks[0] = kPEKeyWestStatusLastACK;
    fake.eventCount = 3;
    fake.arbitrationAt = 1;
    transport = transport_for(&fake);
    request = request_for(&byte, 1, kPEKeyWestWrite);

    CHECK(PEKeyWestI2CTransferCore(&transport, &request) ==
        KERN_PE_KEYWEST_ARBITRATION_LOST);
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
    fake.controllerStarted = 1;
    fake.events[0] = kPEKeyWestInterruptStop;
    fake.eventCount = 1;
    transport = transport_for(&fake);
    request = request_for(&byte, 1, kPEKeyWestRead);
    CHECK(PEKeyWestI2CTransferCore(&transport, &request) ==
        KERN_PE_KEYWEST_BUSY);
    CHECK(fake.eventIndex == 1);
    expect_serialized_and_clean(&fake);
}

static void test_keywest_initial_busy_recovery_timeout(void)
{
    Fake fake;
    PEKeyLargoTransport transport;
    PEKeyWestI2CRequest request;
    unsigned char byte = 0;

    init_fake(&fake);
    fake.regs[kPEKeyWestRegStatus] = kPEKeyWestStatusBusy;
    fake.controllerStarted = 1;
    transport = transport_for(&fake);
    request = request_for(&byte, 1, kPEKeyWestRead);
    request.deadline.tv_nsec = 3;
    CHECK(PEKeyWestI2CTransferCore(&transport, &request) ==
        KERN_PE_KEYWEST_TIMEOUT);
    CHECK(fake.timeReads == 4);
    expect_serialized_and_clean(&fake);

    init_fake(&fake);
    fake.regs[kPEKeyWestRegStatus] = kPEKeyWestStatusBusy;
    fake.controllerStarted = 1;
    fake.arbitrationAt = 0;
    transport = transport_for(&fake);
    request = request_for(&byte, 1, kPEKeyWestRead);
    CHECK(PEKeyWestI2CTransferCore(&transport, &request) ==
        KERN_PE_KEYWEST_ARBITRATION_LOST);
    expect_serialized_and_clean(&fake);
}

static void test_keywest_bus_speeds(void)
{
    static const unsigned char speeds[] = {
        kPEKeyWestSpeed100kHz,
        kPEKeyWestSpeed50kHz,
        kPEKeyWestSpeed25kHz
    };
    unsigned int index;

    for (index = 0; index < ARRAY_COUNT(speeds); index++) {
        Fake fake;
        PEKeyLargoTransport transport;
        PEKeyWestI2CRequest request;
        unsigned char byte = 0x5a;

        init_fake(&fake);
        fake.events[0] = kPEKeyWestInterruptAddress;
        fake.events[1] = kPEKeyWestInterruptData;
        fake.events[2] = kPEKeyWestInterruptStop;
        fake.acks[0] = kPEKeyWestStatusLastACK;
        fake.acks[1] = kPEKeyWestStatusLastACK;
        fake.eventCount = 3;
        transport = transport_for(&fake);
        transport.speed = speeds[index];
        request = request_for(&byte, 1, kPEKeyWestWrite);
        CHECK(PEKeyWestI2CTransferCore(&transport, &request) ==
            KERN_SUCCESS);
        CHECK(saw_write(&fake, kPEKeyWestRegMode,
            (request.port << 4) | kPEKeyWestModeStandardSubaddress |
            speeds[index]));
    }
}

static void test_keywest_rejects_reserved_addresses_before_mmio(void)
{
    static const unsigned char addresses[] = { 0x00, 0x07, 0x78, 0x7f };
    unsigned int index;

    for (index = 0; index < ARRAY_COUNT(addresses); index++) {
        Fake fake;
        PEKeyLargoTransport transport;
        PEKeyWestI2CRequest request;
        unsigned char byte = 0;

        init_fake(&fake);
        transport = transport_for(&fake);
        request = request_for(&byte, 1, kPEKeyWestWrite);
        request.address = addresses[index];
        CHECK(PEKeyWestI2CTransferCore(&transport, &request) ==
            KERN_INVALID_ARGUMENT);
        CHECK(fake.traceCount == 0);
    }
}

static void test_keywest_timeout_at_every_phase(void)
{
    int phase;

    for (phase = 0; phase < 4; phase++) {
        Fake fake;
        PEKeyLargoTransport transport;
        PEKeyWestI2CRequest request;
        unsigned char bytes[2] = { 1, 2 };
        static const TraceEntry expected[] = {
            { 'w', kPEKeyWestRegControl,
                kPEKeyWestControlTransferAddress },
            { 'w', kPEKeyWestRegControl, kPEKeyWestControlStop },
            { 'w', kPEKeyWestRegControl, 0 }
        };

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
        expect_trace_in_order(&fake, expected, ARRAY_COUNT(expected));
        expect_serialized_and_clean(&fake);
    }
}

static void test_keywest_deadline_edges(void)
{
    Fake fake;
    PEKeyLargoTransport transport;
    PEKeyWestI2CRequest request;
    unsigned char byte = 0;

    init_fake(&fake);
    fake.events[0] = kPEKeyWestInterruptAddress;
    fake.eventCount = 1;
    fake.stallAt = 0;
    fake.now.tv_sec = 5;
    transport = transport_for(&fake);
    request = request_for(&byte, 1, kPEKeyWestRead);
    request.deadline.tv_sec = 5;
    request.deadline.tv_nsec = 0;
    CHECK(PEKeyWestI2CTransferCore(&transport, &request) ==
        KERN_PE_KEYWEST_TIMEOUT);
    CHECK(fake.timeReads == 1);
    expect_serialized_and_clean(&fake);

    init_fake(&fake);
    fake.events[0] = kPEKeyWestInterruptAddress;
    fake.eventCount = 1;
    fake.stallAt = 0;
    fake.now.tv_sec = 0;
    fake.now.tv_nsec = NSEC_PER_SEC - 1;
    transport = transport_for(&fake);
    request = request_for(&byte, 1, kPEKeyWestRead);
    request.deadline.tv_sec = 1;
    request.deadline.tv_nsec = 1;
    CHECK(PEKeyWestI2CTransferCore(&transport, &request) ==
        KERN_PE_KEYWEST_TIMEOUT);
    CHECK(fake.timeReads == 3);
    expect_serialized_and_clean(&fake);
}

static void test_keywest_read_timeouts_around_ack(void)
{
    int phase;

    for (phase = 0; phase < 4; phase++) {
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
        fake.data[0] = 0x11;
        fake.data[1] = 0x22;
        fake.eventCount = 4;
        fake.stallAt = phase;
        transport = transport_for(&fake);
        request = request_for(bytes, 2, kPEKeyWestRead);
        request.deadline.tv_nsec = 3;

        CHECK(PEKeyWestI2CTransferCore(&transport, &request) ==
            KERN_PE_KEYWEST_TIMEOUT);
        if (phase >= 1)
            CHECK(saw_write(&fake, kPEKeyWestRegControl,
                kPEKeyWestControlSendACK));
        if (phase >= 2)
            CHECK(saw_write(&fake, kPEKeyWestRegControl, 0));
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

static void test_public_wrappers_validate_before_ready(void)
{
    PEKeyWestI2CRequest request;
    PEAudioGPIO gpio;
    boolean_t active;
    unsigned char byte = 0;

    request = request_for(&byte, 1, kPEKeyWestWrite);
    gpio.offset = 0;
    gpio.activeHigh = TRUE;
    CHECK(PEKeyWestI2CTransfer(0) == KERN_INVALID_ARGUMENT);
    request.port = 16;
    CHECK(PEKeyWestI2CTransfer(&request) == KERN_INVALID_ARGUMENT);
    request.port = 0;
    request.address = 0x07;
    CHECK(PEKeyWestI2CTransfer(&request) == KERN_INVALID_ARGUMENT);
    request.address = 0x78;
    CHECK(PEKeyWestI2CTransfer(&request) == KERN_INVALID_ARGUMENT);
    request.address = 0x80;
    CHECK(PEKeyWestI2CTransfer(&request) == KERN_INVALID_ARGUMENT);
    request.address = 0x34;
    request.buffer = 0;
    CHECK(PEKeyWestI2CTransfer(&request) == KERN_INVALID_ARGUMENT);
    request.buffer = &byte;
    request.length = 0;
    CHECK(PEKeyWestI2CTransfer(&request) == KERN_INVALID_ARGUMENT);
    request.length = 1;
    request.direction = (PEKeyWestDirection)2;
    CHECK(PEKeyWestI2CTransfer(&request) == KERN_INVALID_ARGUMENT);
    request.direction = kPEKeyWestWrite;
    request.deadline.tv_nsec = NSEC_PER_SEC;
    CHECK(PEKeyWestI2CTransfer(&request) == KERN_INVALID_ARGUMENT);
    CHECK(PEAudioGPIORead(0, &active) == KERN_INVALID_ARGUMENT);
    CHECK(PEAudioGPIORead(&gpio, 0) == KERN_INVALID_ARGUMENT);
    gpio.activeHigh = (boolean_t)2;
    CHECK(PEAudioGPIORead(&gpio, &active) == KERN_INVALID_ARGUMENT);
    gpio.activeHigh = TRUE;
    CHECK(PEAudioGPIOWrite(&gpio, (boolean_t)2) == KERN_INVALID_ARGUMENT);
    CHECK(PEI2SSetCellState(2, kPEI2SCellRunning) ==
        KERN_INVALID_ARGUMENT);
    CHECK(PEI2SSetCellState(0, (PEI2SCellState)3) ==
        KERN_INVALID_ARGUMENT);
}

static void test_public_binding_ranges_and_interrupt_context(void)
{
    Fake fake;
    PEKeyLargoTransport transport;
    PEKeyWestI2CRequest request;
    PEAudioGPIO gpio;
    boolean_t active;
    unsigned char byte = 0;

    init_fake(&fake);
    transport = transport_for(&fake);
    request = request_for(&byte, 1, kPEKeyWestWrite);
    gpio.offset = 0x20;
    gpio.activeHigh = TRUE;
    PEKeyLargoBindTransport(&transport);
    CHECK(PEAudioGPIORead(&gpio, &active) == KERN_SUCCESS);
    gpio.offset = fake.maxOffset;
    CHECK(PEAudioGPIORead(&gpio, &active) == KERN_INVALID_ARGUMENT);
    gpio.offset = 0x20;
    fake.interruptContext = 1;
    CHECK(PEKeyWestI2CTransfer(&request) == KERN_INVALID_ARGUMENT);
    CHECK(PEAudioGPIORead(&gpio, &active) == KERN_INVALID_ARGUMENT);
    CHECK(PEAudioGPIOWrite(&gpio, TRUE) == KERN_INVALID_ARGUMENT);
    CHECK(PEI2SSetCellState(0, kPEI2SCellRunning) ==
        KERN_INVALID_ARGUMENT);
    CHECK(fake.traceCount == 3);
    PEKeyLargoBindTransport(0);
}

int main(void)
{
    test_error_abi_values();
    test_keywest_write_success();
    test_keywest_read_success();
    test_keywest_one_byte_read_order();
    test_keywest_nacks();
    test_keywest_arbitration_loss();
    test_keywest_initial_busy();
    test_keywest_initial_busy_recovery_timeout();
    test_keywest_bus_speeds();
    test_keywest_rejects_reserved_addresses_before_mmio();
    test_keywest_timeout_at_every_phase();
    test_keywest_deadline_edges();
    test_keywest_read_timeouts_around_ack();
    test_gpio_polarities_and_semantics();
    test_i2s_states_preserve_bits_and_order();
    test_public_wrappers_are_not_ready();
    test_public_wrappers_validate_before_ready();
    test_public_binding_ranges_and_interrupt_context();
    if (failures != 0) {
        printf("pe_keylargo_test: %d failure(s)\n", failures);
        return 1;
    }
    printf("pe_keylargo_test: all tests passed\n");
    return 0;
}
