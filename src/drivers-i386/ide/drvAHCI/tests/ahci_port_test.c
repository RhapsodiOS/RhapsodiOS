#include <stdio.h>
#include <string.h>
#include "AHCIShared.h"
#include "AHCIPortLogic.h"

static int failures;

#define CHECK(expression) do { \
    if (!(expression)) { \
        fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #expression); \
        ++failures; \
    } \
} while (0)

typedef struct {
    unsigned long virtualBase;
    AHCIU32 physicalBase;
    unsigned long discontinuity;
    unsigned long failure;
} TranslateFake;

static int translate(void *context, unsigned long virtualAddress,
                     AHCIU32 *physicalAddress)
{
    TranslateFake *fake;

    fake = (TranslateFake *)context;
    if (virtualAddress == fake->failure)
        return 0;
    *physicalAddress = fake->physicalBase +
                       (AHCIU32)(virtualAddress - fake->virtualBase);
    if (fake->discontinuity != 0 && virtualAddress >= fake->discontinuity)
        *physicalAddress += 0x1000U;
    return 1;
}

static void test_arena_layout(void)
{
    AHCIPortArena arena;
    TranslateFake fake;
    unsigned long rawVirtual;

    rawVirtual = 0x10003UL;
    fake.virtualBase = rawVirtual;
    fake.physicalBase = 0x20003U;
    fake.discontinuity = 0;
    fake.failure = 0;
    CHECK(AHCIPortPrepareArena(rawVirtual, AHCI_PORT_ARENA_ALLOCATION_BYTES,
                               4096U, translate, &fake, &arena) ==
          AHCI_PORT_SUCCESS);
    CHECK(arena.virtualBase == 0x11000UL);
    CHECK(arena.physicalBase == 0x21000U);
    CHECK((arena.virtualBase & 4095UL) == 0);
    CHECK((arena.physicalBase & 4095U) == 0);
    CHECK(arena.commandListOffset == 0U);
    CHECK(arena.commandListBytes == 1024U);
    CHECK(arena.receivedFISOffset == 1024U);
    CHECK(arena.receivedFISBytes == 256U);
    CHECK(arena.commandTableOffset == 1280U);
    CHECK(arena.commandTableBytes == 640U);
    CHECK(arena.usableBytes == 1920U);
    CHECK(((arena.physicalBase + arena.commandTableOffset) & 127U) == 0);
}

static void test_arena_rejects_invalid_translations(void)
{
    AHCIPortArena arena;
    TranslateFake fake;
    unsigned long rawVirtual;

    rawVirtual = 0x20003UL;
    fake.virtualBase = rawVirtual;
    fake.physicalBase = 0xfffff003U;
    fake.discontinuity = 0;
    fake.failure = 0;
    CHECK(AHCIPortPrepareArena(rawVirtual, AHCI_PORT_ARENA_ALLOCATION_BYTES,
                               4096U, translate, &fake, &arena) ==
          AHCI_PORT_ADDRESS_ERROR);

    fake.physicalBase = 0x30003U;
    fake.failure = 0x21000UL + AHCI_PORT_COMMAND_TABLE_OFFSET;
    CHECK(AHCIPortPrepareArena(rawVirtual, AHCI_PORT_ARENA_ALLOCATION_BYTES,
                               4096U, translate, &fake, &arena) ==
          AHCI_PORT_ADDRESS_ERROR);

    fake.failure = 0;
    fake.discontinuity = 0x21000UL + AHCI_PORT_RECEIVED_FIS_OFFSET;
    CHECK(AHCIPortPrepareArena(rawVirtual, AHCI_PORT_ARENA_ALLOCATION_BYTES,
                               4096U, translate, &fake, &arena) ==
          AHCI_PORT_ADDRESS_ERROR);
}

enum {
    EVENT_WRITE = 1,
    EVENT_BARRIER,
    EVENT_DELAY
};

typedef struct {
    AHCIU32 registers[32];
    unsigned int eventType[256];
    AHCIU32 eventOffset[256];
    AHCIU32 eventValue[256];
    unsigned int eventCount;
    unsigned int delayedMilliseconds;
    int fisStuck;
} PortFake;

static AHCIU32 port_read(void *context, AHCIU32 offset)
{
    PortFake *fake;

    fake = (PortFake *)context;
    return fake->registers[(offset - AHCI_PORT_BASE(0)) / 4U];
}

static void record(PortFake *fake, unsigned int type, AHCIU32 offset,
                   AHCIU32 value)
{
    if (fake->eventCount < 256U) {
        fake->eventType[fake->eventCount] = type;
        fake->eventOffset[fake->eventCount] = offset;
        fake->eventValue[fake->eventCount] = value;
        ++fake->eventCount;
    }
}

static void port_write(void *context, AHCIU32 offset, AHCIU32 value)
{
    PortFake *fake;
    AHCIU32 index;

    fake = (PortFake *)context;
    index = (offset - AHCI_PORT_BASE(0)) / 4U;
    record(fake, EVENT_WRITE, offset, value);
    if (offset == AHCI_PORT_BASE(0) + AHCI_PX_CMD) {
        if ((value & AHCI_PXCMD_FRE) != 0)
            value |= AHCI_PXCMD_FR;
        else if (!fake->fisStuck)
            value &= ~AHCI_PXCMD_FR;
        if ((value & AHCI_PXCMD_ST) != 0)
            value |= AHCI_PXCMD_CR;
        else
            value &= ~AHCI_PXCMD_CR;
    }
    fake->registers[index] = value;
}

static void port_delay(void *context, unsigned int milliseconds)
{
    PortFake *fake;

    fake = (PortFake *)context;
    fake->delayedMilliseconds += milliseconds;
    record(fake, EVENT_DELAY, 0, milliseconds);
}

static void port_barrier(void *context)
{
    PortFake *fake;

    fake = (PortFake *)context;
    record(fake, EVENT_BARRIER, 0, 0);
}

static int write_position(const PortFake *fake, AHCIU32 registerOffset)
{
    unsigned int i;

    for (i = 0; i < fake->eventCount; ++i) {
        if (fake->eventType[i] == EVENT_WRITE &&
            fake->eventOffset[i] == AHCI_PORT_BASE(0) + registerOffset)
            return (int)i;
    }
    return -1;
}

static void init_active_fake(PortFake *fake, AHCIU32 signature)
{
    memset(fake, 0, sizeof(*fake));
    fake->registers[AHCI_PX_CMD / 4U] = AHCI_PXCMD_ST | AHCI_PXCMD_FRE |
                                             AHCI_PXCMD_CR | AHCI_PXCMD_FR |
                                             AHCI_PXCMD_CPD;
    fake->registers[AHCI_PX_SSTS / 4U] = AHCI_SSTS_DET_PRESENT |
                                              AHCI_SSTS_IPM_ACTIVE;
    fake->registers[AHCI_PX_SCTL / 4U] = 0x20U;
    fake->registers[AHCI_PX_SIG / 4U] = signature;
}

static void test_engine_sequence_and_classification(void)
{
    AHCIPortOps ops;
    AHCIPortArena arena;
    PortFake fake;
    AHCIDeviceKind kind;
    AHCIU32 command;

    init_active_fake(&fake, AHCI_SIG_ATA);
    memset(&arena, 0, sizeof(arena));
    arena.physicalBase = 0x4000U;
    arena.commandListOffset = AHCI_PORT_COMMAND_LIST_OFFSET;
    arena.receivedFISOffset = AHCI_PORT_RECEIVED_FIS_OFFSET;
    arena.commandTableOffset = AHCI_PORT_COMMAND_TABLE_OFFSET;
    ops.context = &fake;
    ops.read = port_read;
    ops.write = port_write;
    ops.delay = port_delay;
    ops.barrier = port_barrier;

    CHECK(AHCIPortInitializeHardware(&ops, 0U, AHCI_CAP_SSS, &arena,
                                     &kind) == AHCI_PORT_SUCCESS);
    CHECK(kind == AHCI_DEVICE_SATA);
    CHECK(write_position(&fake, AHCI_PX_CLB) >= 0);
    CHECK(write_position(&fake, AHCI_PX_CLB) <
          write_position(&fake, AHCI_PX_IS));
    CHECK(fake.registers[AHCI_PX_CLB / 4U] == 0x4000U);
    CHECK(fake.registers[AHCI_PX_CLBU / 4U] == 0);
    CHECK(fake.registers[AHCI_PX_FB / 4U] == 0x4400U);
    CHECK(fake.registers[AHCI_PX_FBU / 4U] == 0);
    CHECK(fake.registers[AHCI_PX_IE / 4U] == AHCI_PORT_INITIAL_IE_MASK);
    CHECK(fake.registers[AHCI_PX_SCTL / 4U] == 0x20U);
    command = fake.registers[AHCI_PX_CMD / 4U];
    CHECK((command & (AHCI_PXCMD_ST | AHCI_PXCMD_FRE |
                      AHCI_PXCMD_CR | AHCI_PXCMD_FR)) ==
          (AHCI_PXCMD_ST | AHCI_PXCMD_FRE |
           AHCI_PXCMD_CR | AHCI_PXCMD_FR));
    CHECK((command & (AHCI_PXCMD_POD | AHCI_PXCMD_SUD)) ==
          (AHCI_PXCMD_POD | AHCI_PXCMD_SUD));
    CHECK(fake.delayedMilliseconds == 0U);
}

static void test_comreset_only_for_recoverable_link(void)
{
    AHCIPortOps ops;
    AHCIPortArena arena;
    PortFake fake;
    AHCIDeviceKind kind;

    init_active_fake(&fake, AHCI_SIG_ATAPI);
    fake.registers[AHCI_PX_SSTS / 4U] = 1U;
    memset(&arena, 0, sizeof(arena));
    arena.physicalBase = 0x8000U;
    arena.commandListOffset = AHCI_PORT_COMMAND_LIST_OFFSET;
    arena.receivedFISOffset = AHCI_PORT_RECEIVED_FIS_OFFSET;
    arena.commandTableOffset = AHCI_PORT_COMMAND_TABLE_OFFSET;
    ops.context = &fake;
    ops.read = port_read;
    ops.write = port_write;
    ops.delay = port_delay;
    ops.barrier = port_barrier;

    CHECK(AHCIPortInitializeHardware(&ops, 0U, 0, &arena, &kind) ==
          AHCI_PORT_SUCCESS);
    CHECK(kind == AHCI_DEVICE_NONE);
    CHECK(fake.delayedMilliseconds >= AHCI_COMRESET_ASSERT_MS);
    CHECK(fake.registers[AHCI_PX_IE / 4U] == AHCI_PORT_INITIAL_IE_MASK);

    init_active_fake(&fake, 0);
    fake.registers[AHCI_PX_SSTS / 4U] = 0;
    CHECK(AHCIPortInitializeHardware(&ops, 0U, 0, &arena, &kind) ==
          AHCI_PORT_SUCCESS);
    CHECK(kind == AHCI_DEVICE_NONE);
    CHECK(fake.delayedMilliseconds == 0U);
    CHECK((fake.registers[AHCI_PX_CMD / 4U] &
           (AHCI_PXCMD_ST | AHCI_PXCMD_FRE |
            AHCI_PXCMD_CR | AHCI_PXCMD_FR)) == 0);
}

static void test_stop_masks_interrupts_and_stops_both_engines(void)
{
    AHCIPortOps ops;
    PortFake fake;

    init_active_fake(&fake, AHCI_SIG_ATA);
    fake.registers[AHCI_PX_IE / 4U] = 0xffffffffU;
    ops.context = &fake;
    ops.read = port_read;
    ops.write = port_write;
    ops.delay = port_delay;
    ops.barrier = port_barrier;
    CHECK(AHCIPortStopHardware(&ops, 0U) == AHCI_PORT_SUCCESS);
    CHECK(fake.registers[AHCI_PX_IE / 4U] == 0);
    CHECK((fake.registers[AHCI_PX_CMD / 4U] &
           (AHCI_PXCMD_ST | AHCI_PXCMD_FRE |
            AHCI_PXCMD_CR | AHCI_PXCMD_FR)) == 0);
}

static void test_empty_port_refuses_release_when_fis_will_not_stop(void)
{
    AHCIPortOps ops;
    AHCIPortArena arena;
    PortFake fake;
    AHCIDeviceKind kind;
    AHCIPortResult result;

    init_active_fake(&fake, 0);
    fake.registers[AHCI_PX_SSTS / 4U] = 0;
    fake.fisStuck = 1;
    memset(&arena, 0, sizeof(arena));
    arena.physicalBase = 0xc000U;
    arena.commandListOffset = AHCI_PORT_COMMAND_LIST_OFFSET;
    arena.receivedFISOffset = AHCI_PORT_RECEIVED_FIS_OFFSET;
    arena.commandTableOffset = AHCI_PORT_COMMAND_TABLE_OFFSET;
    ops.context = &fake;
    ops.read = port_read;
    ops.write = port_write;
    ops.delay = port_delay;
    ops.barrier = port_barrier;
    result = AHCIPortInitializeHardware(&ops, 0U, 0, &arena, &kind);
    CHECK(result == AHCI_PORT_ENGINE_TIMEOUT);
    CHECK(!AHCIPortArenaMayRelease(result));
}

static void test_sparse_pi_includes_port_31(void)
{
    unsigned char ports[AHCI_MAX_PORTS];
    unsigned int count;
    unsigned int pi;

    pi = 0x80000005U;
    CHECK(AHCIPortCountImplemented(pi) == 3U);
    CHECK(AHCIPortImplemented(pi, 0U));
    CHECK(!AHCIPortImplemented(pi, 1U));
    CHECK(AHCIPortImplemented(pi, 2U));
    CHECK(AHCIPortImplemented(pi, 31U));
    CHECK(!AHCIPortImplemented(pi, 32U));

    memset(ports, 0xff, sizeof(ports));
    count = AHCIPortCollectImplemented(0x80000001U, ports,
                                       AHCI_MAX_PORTS);
    CHECK(count == 2U);
    CHECK(ports[0] == 0U);
    CHECK(ports[1] == 31U);
    CHECK(ports[2] == 0xffU);
}

static void test_arena_release_requires_a_stopped_engine(void)
{
    CHECK(AHCIPortArenaMayRelease(AHCI_PORT_SUCCESS));
    CHECK(!AHCIPortArenaMayRelease(AHCI_PORT_ENGINE_TIMEOUT));
    CHECK(!AHCIPortArenaMayRelease(AHCI_PORT_BAD_ARGUMENT));
}

int main(void)
{
    test_arena_layout();
    test_arena_rejects_invalid_translations();
    test_engine_sequence_and_classification();
    test_comreset_only_for_recoverable_link();
    test_stop_masks_interrupts_and_stops_both_engines();
    test_empty_port_refuses_release_when_fis_will_not_stop();
    test_sparse_pi_includes_port_31();
    test_arena_release_requires_a_stopped_engine();
    if (failures != 0)
        return 1;
    printf("ahci_port_test: all tests passed\n");
    return 0;
}
