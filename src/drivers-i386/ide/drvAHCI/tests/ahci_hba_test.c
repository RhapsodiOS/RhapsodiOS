#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "AHCIHBA.h"

#define MAX_EVENTS 4096
#define NEVER_MS 0xffffffffU

typedef enum {
    EVENT_READ,
    EVENT_WRITE,
    EVENT_DELAY,
    EVENT_BARRIER
} EventKind;

typedef struct {
    EventKind kind;
    AHCIU32 offset;
    AHCIU32 value;
} Event;

typedef struct {
    AHCIU32 registers[12];
    Event events[MAX_EVENTS];
    unsigned int eventCount;
    unsigned int elapsed;
    unsigned int bohcClearAt;
    unsigned int resetClearAfter;
    unsigned int resetStart;
    int resetStarted;
} FakeHBA;

static int failures;

static void fail(const char *test, const char *message)
{
    fprintf(stderr, "%s: %s\n", test, message);
    ++failures;
}

static void record_event(FakeHBA *fake, EventKind kind, AHCIU32 offset,
                         AHCIU32 value)
{
    Event *event;

    if (fake->eventCount >= MAX_EVENTS) {
        fail("event log", "overflow");
        return;
    }
    event = &fake->events[fake->eventCount++];
    event->kind = kind;
    event->offset = offset;
    event->value = value;
}

static void refresh_hardware(FakeHBA *fake)
{
    if (fake->bohcClearAt != NEVER_MS &&
        fake->elapsed >= fake->bohcClearAt)
        fake->registers[AHCI_REG_BOHC / 4U] &=
            ~(AHCI_BOHC_BOS | AHCI_BOHC_BB);
    if (fake->resetStarted && fake->resetClearAfter != NEVER_MS &&
        fake->elapsed - fake->resetStart >= fake->resetClearAfter)
        fake->registers[AHCI_REG_GHC / 4U] &= ~AHCI_GHC_HR;
}

static AHCIU32 fake_read(void *context, AHCIU32 offset)
{
    FakeHBA *fake;
    AHCIU32 value;

    fake = (FakeHBA *)context;
    refresh_hardware(fake);
    value = fake->registers[offset / 4U];
    record_event(fake, EVENT_READ, offset, value);
    return value;
}

static void fake_write(void *context, AHCIU32 offset, AHCIU32 value)
{
    FakeHBA *fake;

    fake = (FakeHBA *)context;
    refresh_hardware(fake);
    record_event(fake, EVENT_WRITE, offset, value);
    if (offset == AHCI_REG_IS)
        fake->registers[offset / 4U] &= ~value;
    else
        fake->registers[offset / 4U] = value;
    if (offset == AHCI_REG_GHC && (value & AHCI_GHC_HR) != 0) {
        fake->resetStarted = 1;
        fake->resetStart = fake->elapsed;
    }
}

static void fake_delay(void *context, unsigned int milliseconds)
{
    FakeHBA *fake;

    fake = (FakeHBA *)context;
    record_event(fake, EVENT_DELAY, 0, (AHCIU32)milliseconds);
    fake->elapsed += milliseconds;
}

static void fake_barrier(void *context)
{
    FakeHBA *fake;

    fake = (FakeHBA *)context;
    record_event(fake, EVENT_BARRIER, 0, 0);
}

static void initialize_fake(FakeHBA *fake, AHCIHBAOps *ops)
{
    memset(fake, 0, sizeof(*fake));
    fake->registers[AHCI_REG_CAP / 4U] = 0;
    fake->registers[AHCI_REG_GHC / 4U] = AHCI_GHC_IE;
    fake->registers[AHCI_REG_IS / 4U] = 0x80000005U;
    fake->registers[AHCI_REG_PI / 4U] = 1U;
    fake->registers[AHCI_REG_VS / 4U] = 0x00010301U;
    fake->registers[AHCI_REG_CAP2 / 4U] = 0;
    fake->bohcClearAt = NEVER_MS;
    fake->resetClearAfter = 2U;
    ops->context = fake;
    ops->read = fake_read;
    ops->write = fake_write;
    ops->delay = fake_delay;
    ops->barrier = fake_barrier;
}

static int nth_write(const FakeHBA *fake, AHCIU32 offset, AHCIU32 value,
                     unsigned int occurrence)
{
    unsigned int index;
    unsigned int found;

    found = 0;
    for (index = 0; index < fake->eventCount; ++index) {
        if (fake->events[index].kind == EVENT_WRITE &&
            fake->events[index].offset == offset &&
            fake->events[index].value == value) {
            ++found;
            if (found == occurrence)
                return (int)index;
        }
    }
    return -1;
}

static unsigned int delay_total(const FakeHBA *fake, unsigned int value)
{
    unsigned int index;
    unsigned int total;

    total = 0;
    for (index = 0; index < fake->eventCount; ++index) {
        if (fake->events[index].kind == EVENT_DELAY &&
            fake->events[index].value == value)
            total += value;
    }
    return total;
}

static unsigned int write_count(const FakeHBA *fake)
{
    unsigned int index;
    unsigned int count;

    count = 0;
    for (index = 0; index < fake->eventCount; ++index) {
        if (fake->events[index].kind == EVENT_WRITE)
            ++count;
    }
    return count;
}

static void test_global_initialization_order(void)
{
    static const char name[] = "global initialization order";
    FakeHBA fake;
    AHCIHBAOps ops;
    AHCIHBAInfo info;
    AHCIHBAResult result;
    int firstAE;
    int reset;
    int secondAE;
    int interruptDisable;
    int staleClear;

    initialize_fake(&fake, &ops);
    result = AHCIHBAInitialize(&ops, &info);
    if (result != AHCI_HBA_SUCCESS)
        fail(name, "initialization failed");
    firstAE = nth_write(&fake, AHCI_REG_GHC, AHCI_GHC_AE | AHCI_GHC_IE, 1);
    reset = nth_write(&fake, AHCI_REG_GHC,
                      AHCI_GHC_AE | AHCI_GHC_IE | AHCI_GHC_HR, 1);
    secondAE = nth_write(&fake, AHCI_REG_GHC,
                         AHCI_GHC_AE | AHCI_GHC_IE, 2);
    interruptDisable = nth_write(&fake, AHCI_REG_GHC, AHCI_GHC_AE, 1);
    staleClear = nth_write(&fake, AHCI_REG_IS, 0xffffffffU, 1);
    if (firstAE < 0 || reset <= firstAE || secondAE <= reset ||
        interruptDisable <= secondAE || staleClear <= interruptDisable)
        fail(name, "AE/reset/IE/IS write order is wrong");
    if ((fake.registers[AHCI_REG_GHC / 4U] & AHCI_GHC_IE) != 0)
        fail(name, "global interrupts left enabled");
    if (fake.registers[AHCI_REG_IS / 4U] != 0)
        fail(name, "stale global interrupt status not cleared");
    if (info.version != 0x00010301U || info.capabilities != 0 ||
        info.capabilities2 != 0 || info.portsImplemented != 1U)
        fail(name, "capability snapshot is wrong");
}

static void test_bohc_busy_handoff(void)
{
    static const char name[] = "BOHC busy handoff";
    FakeHBA fake;
    AHCIHBAOps ops;
    AHCIHBAInfo info;
    AHCIHBAResult result;
    int ownership;

    initialize_fake(&fake, &ops);
    fake.registers[AHCI_REG_CAP2 / 4U] = AHCI_CAP2_BOH;
    fake.registers[AHCI_REG_BOHC / 4U] = AHCI_BOHC_BOS | AHCI_BOHC_BB;
    fake.bohcClearAt = AHCI_BOHC_BB_OBSERVE_MS + 5U;
    result = AHCIHBAInitialize(&ops, &info);
    if (result != AHCI_HBA_SUCCESS)
        fail(name, "handoff failed");
    ownership = nth_write(&fake, AHCI_REG_BOHC,
                          AHCI_BOHC_BOS | AHCI_BOHC_BB | AHCI_BOHC_OOS, 1);
    if (ownership < 0)
        fail(name, "OOS was not requested");
    if (delay_total(&fake, AHCI_BOHC_BB_OBSERVE_MS) !=
        AHCI_BOHC_BB_OBSERVE_MS)
        fail(name, "25 ms busy observation missing");
    if (delay_total(&fake, AHCI_POLL_INTERVAL_MS) != 7U)
        fail(name, "busy cleanup polling duration is wrong");
}

static void test_bohc_timeouts(void)
{
    static const char busyName[] = "BOHC busy timeout";
    static const char ownerName[] = "BOHC ownership timeout";
    FakeHBA fake;
    AHCIHBAOps ops;
    AHCIHBAInfo info;
    AHCIHBAResult result;

    initialize_fake(&fake, &ops);
    fake.registers[AHCI_REG_CAP2 / 4U] = AHCI_CAP2_BOH;
    fake.registers[AHCI_REG_BOHC / 4U] = AHCI_BOHC_BOS | AHCI_BOHC_BB;
    result = AHCIHBAInitialize(&ops, &info);
    if (result != AHCI_HBA_BOHC_TIMEOUT)
        fail(busyName, "persistent BB was accepted");
    if (fake.elapsed != AHCI_BOHC_BB_OBSERVE_MS +
                        AHCI_BOHC_HANDOFF_TIMEOUT_MS)
        fail(busyName, "handoff wait was not bounded");

    initialize_fake(&fake, &ops);
    fake.registers[AHCI_REG_CAP2 / 4U] = AHCI_CAP2_BOH;
    fake.registers[AHCI_REG_BOHC / 4U] = AHCI_BOHC_BOS;
    result = AHCIHBAInitialize(&ops, &info);
    if (result != AHCI_HBA_BOHC_TIMEOUT)
        fail(ownerName, "persistent BOS was accepted");
    if (fake.elapsed != AHCI_BOHC_BB_OBSERVE_MS)
        fail(ownerName, "BOS-only failure was not bounded");
}

static void test_reset_timeout(void)
{
    static const char name[] = "reset timeout";
    FakeHBA fake;
    AHCIHBAOps ops;
    AHCIHBAInfo info;
    AHCIHBAResult result;

    initialize_fake(&fake, &ops);
    fake.resetClearAfter = NEVER_MS;
    result = AHCIHBAInitialize(&ops, &info);
    if (result != AHCI_HBA_RESET_TIMEOUT)
        fail(name, "persistent HR was accepted");
    if (fake.elapsed != AHCI_HBA_RESET_TIMEOUT_MS)
        fail(name, "reset wait was not bounded to one second");
}

static void test_pi_validation(void)
{
    static const char zeroName[] = "zero PI";
    static const char highName[] = "PI above NP";
    static const char port31Name[] = "NP31 safety";
    FakeHBA fake;
    AHCIHBAOps ops;
    AHCIHBAInfo info;
    AHCIHBAResult result;

    initialize_fake(&fake, &ops);
    fake.registers[AHCI_REG_PI / 4U] = 0;
    result = AHCIHBAInitialize(&ops, &info);
    if (result != AHCI_HBA_INVALID_PI || write_count(&fake) != 0)
        fail(zeroName, "zero PI did not fail before writes");

    initialize_fake(&fake, &ops);
    fake.registers[AHCI_REG_PI / 4U] = 2U;
    result = AHCIHBAInitialize(&ops, &info);
    if (result != AHCI_HBA_INVALID_PI || write_count(&fake) != 0)
        fail(highName, "PI above CAP.NP did not fail before writes");

    initialize_fake(&fake, &ops);
    fake.registers[AHCI_REG_CAP / 4U] = AHCI_CAP_NP_MASK;
    fake.registers[AHCI_REG_PI / 4U] = 0x80000000U;
    result = AHCIHBAInitialize(&ops, &info);
    if (result != AHCI_HBA_SUCCESS)
        fail(port31Name, "port 31 was rejected or shifted unsafely");
}

static void test_register_and_argument_failures(void)
{
    static const char registerName[] = "invalid registers";
    static const char argumentName[] = "invalid callbacks";
    static const char laterName[] = "later version";
    FakeHBA fake;
    AHCIHBAOps ops;
    AHCIHBAInfo info;
    AHCIHBAResult result;

    initialize_fake(&fake, &ops);
    fake.registers[AHCI_REG_VS / 4U] = 0;
    result = AHCIHBAInitialize(&ops, &info);
    if (result != AHCI_HBA_INVALID_REGISTERS || write_count(&fake) != 0)
        fail(registerName, "zero VS was accepted");

    initialize_fake(&fake, &ops);
    fake.registers[AHCI_REG_CAP / 4U] = 0xffffffffU;
    result = AHCIHBAInitialize(&ops, &info);
    if (result != AHCI_HBA_INVALID_REGISTERS || write_count(&fake) != 0)
        fail(registerName, "all-one CAP was accepted");

    initialize_fake(&fake, &ops);
    ops.barrier = NULL;
    result = AHCIHBAInitialize(&ops, &info);
    if (result != AHCI_HBA_BAD_ARGUMENT || write_count(&fake) != 0)
        fail(argumentName, "missing callback was accepted");

    initialize_fake(&fake, &ops);
    fake.registers[AHCI_REG_VS / 4U] = 0x00020000U;
    result = AHCIHBAInitialize(&ops, &info);
    if (result != AHCI_HBA_SUCCESS || info.version != 0x00020000U)
        fail(laterName, "later AHCI version was rejected");
}

int main(void)
{
    test_global_initialization_order();
    test_bohc_busy_handoff();
    test_bohc_timeouts();
    test_reset_timeout();
    test_pi_validation();
    test_register_and_argument_failures();
    if (failures != 0) {
        fprintf(stderr, "ahci_hba_test: %d failure(s)\n", failures);
        return EXIT_FAILURE;
    }
    printf("ahci_hba_test: all tests passed\n");
    return EXIT_SUCCESS;
}
