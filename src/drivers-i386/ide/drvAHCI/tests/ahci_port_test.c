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

static int translate_fragmented(void *context,
                                unsigned long virtualAddress,
                                AHCIU32 *physicalAddress)
{
    TranslateFake *fake;
    unsigned long offset;

    fake = (TranslateFake *)context;
    offset = virtualAddress - fake->virtualBase;
    *physicalAddress = fake->physicalBase +
                       (AHCIU32)((offset / 4096U) * 8192U) +
                       (AHCIU32)(offset & 4095U);
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
    CHECK(arena.identifyOffset == 2048U);
    CHECK(arena.identifyBytes == 512U);
    CHECK(arena.usableBytes == 2560U);
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

    fake.discontinuity = 0x21000UL + AHCI_PORT_IDENTIFY_OFFSET;
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
    int comresetAsserted;
    int comresetReleased;
    unsigned int linkWaitedMilliseconds;
    unsigned int linkUpAtMilliseconds;
    unsigned int identifyCompleteAtMilliseconds;
    AHCICommandHeader *identifyHeader;
    unsigned short *identifyData;
    unsigned short identifyWord0;
    AHCIU32 identifyPortIS;
    AHCIU32 identifyTaskFile;
    AHCIU32 identifySERR;
} PortFake;

static AHCIU32 port_read(void *context, AHCIU32 offset)
{
    PortFake *fake;

    fake = (PortFake *)context;
    if (offset == AHCI_PORT_BASE(0) + AHCI_PX_SSTS &&
        fake->linkUpAtMilliseconds != 0 &&
        fake->linkWaitedMilliseconds >= fake->linkUpAtMilliseconds)
        fake->registers[AHCI_PX_SSTS / 4U] =
            AHCI_SSTS_DET_PRESENT | AHCI_SSTS_IPM_ACTIVE;
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
    if (offset == AHCI_PORT_BASE(0) + AHCI_PX_IS ||
        offset == AHCI_PORT_BASE(0) + AHCI_PX_SERR) {
        fake->registers[index] &= ~value;
        return;
    }
    if (offset == AHCI_PORT_BASE(0) + AHCI_PX_CMD) {
        if ((value & AHCI_PXCMD_FRE) != 0)
            value |= AHCI_PXCMD_FR;
        else if (!fake->fisStuck)
            value &= ~AHCI_PXCMD_FR;
        if ((value & AHCI_PXCMD_ST) != 0)
            value |= AHCI_PXCMD_CR;
        else
            value &= ~AHCI_PXCMD_CR;
    } else if (offset == AHCI_PORT_BASE(0) + AHCI_PX_SCTL) {
        if ((value & AHCI_SCTL_DET_MASK) == AHCI_SCTL_DET_COMRESET)
            fake->comresetAsserted = 1;
        else if (fake->comresetAsserted) {
            fake->comresetReleased = 1;
            fake->registers[AHCI_PX_IS / 4U] = AHCI_PXIS_PCS;
            fake->registers[AHCI_PX_SERR / 4U] = 0x00010001U;
        }
    }
    fake->registers[index] = value;
}

static void port_delay(void *context, unsigned int milliseconds)
{
    PortFake *fake;

    fake = (PortFake *)context;
    fake->delayedMilliseconds += milliseconds;
    if (fake->comresetReleased)
        fake->linkWaitedMilliseconds += milliseconds;
    if (fake->identifyCompleteAtMilliseconds != 0 &&
        fake->delayedMilliseconds >= fake->identifyCompleteAtMilliseconds &&
        (fake->registers[AHCI_PX_CI / 4U] & 1U) != 0) {
        fake->registers[AHCI_PX_CI / 4U] = 0;
        fake->registers[AHCI_PX_IS / 4U] = fake->identifyPortIS;
        fake->registers[AHCI_PX_TFD / 4U] = fake->identifyTaskFile;
        fake->registers[AHCI_PX_SERR / 4U] = fake->identifySERR;
        if (fake->identifyHeader != 0)
            fake->identifyHeader->prdbc = 512U;
        if (fake->identifyData != 0)
            fake->identifyData[0] = fake->identifyWord0;
    }
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

static unsigned int write_count(const PortFake *fake,
                                AHCIU32 registerOffset)
{
    unsigned int count;
    unsigned int i;

    count = 0;
    for (i = 0; i < fake->eventCount; ++i) {
        if (fake->eventType[i] == EVENT_WRITE &&
            fake->eventOffset[i] == AHCI_PORT_BASE(0) + registerOffset)
            ++count;
    }
    return count;
}

static int register_writes_have_barriers(const PortFake *fake,
                                         AHCIU32 registerOffset)
{
    unsigned int i;

    for (i = 0; i < fake->eventCount; ++i) {
        if (fake->eventType[i] == EVENT_WRITE &&
            fake->eventOffset[i] == AHCI_PORT_BASE(0) + registerOffset) {
            if (i + 1U >= fake->eventCount ||
                fake->eventType[i + 1U] != EVENT_BARRIER)
                return 0;
        }
    }
    return 1;
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
    CHECK(fake.registers[AHCI_PX_IS / 4U] == 0);
    CHECK(fake.registers[AHCI_PX_SERR / 4U] == 0);
    CHECK(write_count(&fake, AHCI_PX_IS) == 2U);
    CHECK(write_count(&fake, AHCI_PX_SERR) == 2U);
    CHECK(register_writes_have_barriers(&fake, AHCI_PX_IS));
    CHECK(register_writes_have_barriers(&fake, AHCI_PX_SERR));

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

typedef struct {
    AHCIU32 registers[32];
    unsigned int delayedMilliseconds;
    unsigned int crClearAt;
    unsigned int frClearAt;
} BoundaryFake;

static AHCIU32 boundary_read(void *context, AHCIU32 offset)
{
    BoundaryFake *fake;
    AHCIU32 value;

    fake = (BoundaryFake *)context;
    value = fake->registers[(offset - AHCI_PORT_BASE(0)) / 4U];
    if (offset == AHCI_PORT_BASE(0) + AHCI_PX_CMD) {
        if (fake->crClearAt != 0 &&
            fake->delayedMilliseconds >= fake->crClearAt)
            value &= ~AHCI_PXCMD_CR;
        if (fake->frClearAt != 0 &&
            fake->delayedMilliseconds >= fake->frClearAt)
            value &= ~AHCI_PXCMD_FR;
        fake->registers[AHCI_PX_CMD / 4U] = value;
    }
    return value;
}

static void boundary_write(void *context, AHCIU32 offset, AHCIU32 value)
{
    BoundaryFake *fake;
    AHCIU32 index;
    AHCIU32 old;

    fake = (BoundaryFake *)context;
    index = (offset - AHCI_PORT_BASE(0)) / 4U;
    old = fake->registers[index];
    if (offset == AHCI_PORT_BASE(0) + AHCI_PX_CMD)
        value = (value & ~(AHCI_PXCMD_CR | AHCI_PXCMD_FR)) |
                (old & (AHCI_PXCMD_CR | AHCI_PXCMD_FR));
    fake->registers[index] = value;
}

static void boundary_delay(void *context, unsigned int milliseconds)
{
    BoundaryFake *fake;

    fake = (BoundaryFake *)context;
    fake->delayedMilliseconds += milliseconds;
}

static void boundary_barrier(void *context)
{
    (void)context;
}

static AHCIPortResult run_stop_boundary(unsigned int crClearAt,
                                        unsigned int frClearAt,
                                        unsigned int *delayed)
{
    AHCIPortOps ops;
    BoundaryFake fake;
    AHCIPortResult result;

    memset(&fake, 0, sizeof(fake));
    fake.registers[AHCI_PX_CMD / 4U] = AHCI_PXCMD_ST |
        AHCI_PXCMD_FRE | AHCI_PXCMD_CR | AHCI_PXCMD_FR;
    fake.crClearAt = crClearAt;
    fake.frClearAt = frClearAt;
    ops.context = &fake;
    ops.read = boundary_read;
    ops.write = boundary_write;
    ops.delay = boundary_delay;
    ops.barrier = boundary_barrier;
    result = AHCIPortStopHardware(&ops, 0U);
    *delayed = fake.delayedMilliseconds;
    return result;
}

static void test_exact_engine_timeout_boundaries(void)
{
    unsigned int delayed;

    CHECK(run_stop_boundary(500U, 500U, &delayed) == AHCI_PORT_SUCCESS);
    CHECK(delayed == 500U);
    CHECK(run_stop_boundary(501U, 0U, &delayed) ==
          AHCI_PORT_ENGINE_TIMEOUT);
    CHECK(delayed == 500U);
    CHECK(run_stop_boundary(1U, 501U, &delayed) == AHCI_PORT_SUCCESS);
    CHECK(delayed == 501U);
    CHECK(run_stop_boundary(1U, 502U, &delayed) ==
          AHCI_PORT_ENGINE_TIMEOUT);
    CHECK(delayed == 501U);
}

static void test_exact_link_timeout_boundary(void)
{
    AHCIPortOps ops;
    AHCIPortArena arena;
    PortFake fake;
    AHCIDeviceKind kind;

    memset(&arena, 0, sizeof(arena));
    arena.physicalBase = 0x10000U;
    arena.commandListOffset = AHCI_PORT_COMMAND_LIST_OFFSET;
    arena.receivedFISOffset = AHCI_PORT_RECEIVED_FIS_OFFSET;
    arena.commandTableOffset = AHCI_PORT_COMMAND_TABLE_OFFSET;
    ops.context = &fake;
    ops.read = port_read;
    ops.write = port_write;
    ops.delay = port_delay;
    ops.barrier = port_barrier;

    init_active_fake(&fake, AHCI_SIG_ATAPI);
    fake.registers[AHCI_PX_SSTS / 4U] = 1U;
    fake.linkUpAtMilliseconds = AHCI_LINK_TIMEOUT_MS;
    CHECK(AHCIPortInitializeHardware(&ops, 0U, 0, &arena, &kind) ==
          AHCI_PORT_SUCCESS);
    CHECK(kind == AHCI_DEVICE_ATAPI);
    CHECK(fake.linkWaitedMilliseconds == AHCI_LINK_TIMEOUT_MS);

    init_active_fake(&fake, AHCI_SIG_ATAPI);
    fake.registers[AHCI_PX_SSTS / 4U] = 1U;
    fake.linkUpAtMilliseconds = AHCI_LINK_TIMEOUT_MS + 1U;
    CHECK(AHCIPortInitializeHardware(&ops, 0U, 0, &arena, &kind) ==
          AHCI_PORT_SUCCESS);
    CHECK(kind == AHCI_DEVICE_NONE);
    CHECK(fake.linkWaitedMilliseconds == AHCI_LINK_TIMEOUT_MS);
}

static void test_port_31_register_window(void)
{
    CHECK(AHCI_PORT_BASE(31U) == 0x1080U);
    CHECK(AHCI_PORT_BASE(31U) + 0x7cU == 0x10fcU);
    CHECK(AHCI_PORT_BASE(31U) + 0x7cU < AHCI_ABAR_LENGTH);
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

static void test_buffer_translation_coalesces_pages(void)
{
    TranslateFake fake;
    AHCISegment segments[32];
    unsigned int count;

    fake.virtualBase = 0x10003UL;
    fake.physicalBase = 0x20003U;
    fake.discontinuity = 0;
    fake.failure = 0;
    CHECK(AHCIPortBuildSegments(0x10003UL, 8192U, 4096U, translate, &fake,
                                segments, 32U, &count) ==
          AHCI_PORT_SUCCESS);
    CHECK(count == 1U);
    CHECK(segments[0].address == 0x20003U);
    CHECK(segments[0].length == 8192U);

    fake.discontinuity = 0x11000UL;
    CHECK(AHCIPortBuildSegments(0x10003UL, 8192U, 4096U, translate, &fake,
                                segments, 32U, &count) ==
          AHCI_PORT_SUCCESS);
    CHECK(count == 2U);
}

static void test_buffer_translation_rejects_unsafe_requests(void)
{
    TranslateFake fake;
    AHCISegment segments[32];
    unsigned int count;

    fake.virtualBase = 0x1000UL;
    fake.physicalBase = 0xfffff800U;
    fake.discontinuity = 0;
    fake.failure = 0;
    CHECK(AHCIPortBuildSegments(0x1000UL, 8192U, 4096U, translate, &fake,
                                segments, 32U, &count) ==
          AHCI_PORT_ADDRESS_ERROR);
    fake.physicalBase = 0x2000U;
    CHECK(AHCIPortBuildSegments(0x1000UL, 0, 4096U, translate, &fake,
                                segments, 32U, &count) ==
          AHCI_PORT_BAD_ARGUMENT);
    CHECK(AHCIPortBuildSegments(0x1000UL, AHCI_MAX_TRANSFER_BYTES + 1U,
                                4096U, translate, &fake, segments, 32U,
                                &count) == AHCI_PORT_BAD_ARGUMENT);
    fake.virtualBase = 0x1000UL;
    fake.physicalBase = 0x2000U;
    CHECK(AHCIPortBuildSegments(0x1000UL, AHCI_MAX_TRANSFER_BYTES,
                                4096U, translate_fragmented, &fake,
                                segments, 31U, &count) ==
          AHCI_PORT_ADDRESS_ERROR);
    CHECK(AHCIPortBuildSegments(0x1000UL, AHCI_MAX_TRANSFER_BYTES,
                                4096U, translate_fragmented, &fake,
                                segments, 32U, &count) ==
          AHCI_PORT_SUCCESS);
    CHECK(count == 32U);
}

static void test_slot_zero_command_layout(void)
{
    unsigned char table[AHCI_PORT_COMMAND_TABLE_BYTES];
    AHCICommandHeader header;
    AHCISegment segment;
    unsigned char fis[20];
    unsigned char packet[12];

    memset(fis, 0x5a, sizeof(fis));
    memset(packet, 0xa5, sizeof(packet));
    segment.address = 0x3000U;
    segment.length = 4096U;
    CHECK(AHCIPortBuildSlot(&header, table, 0x9000U, fis, packet, 12U,
                            &segment, 1U, 4096U, 0, 1));
    CHECK(header.ctba == 0x9000U);
    CHECK(header.ctbau == 0);
    CHECK(header.prdtl == 1U);
    CHECK((header.flags & 0x1fU) == 5U);
    CHECK((header.flags & (1U << 5)) != 0);
    CHECK(memcmp(table, fis, sizeof(fis)) == 0);
    CHECK(memcmp(table + 64U, packet, sizeof(packet)) == 0);
    CHECK(((AHCIPRDTEntry *)(table + 128U))[0].dba == 0x3000U);
}

static void test_recovery_is_port_local_and_bounded(void)
{
    AHCIPortOps ops;
    AHCIPortArena arena;
    PortFake fake;

    init_active_fake(&fake, AHCI_SIG_ATA);
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
    CHECK(AHCIPortRecoverHardware(&ops, 0U, &arena) ==
          AHCI_PORT_SUCCESS);
    CHECK(fake.comresetAsserted);
    CHECK(fake.comresetReleased);
    CHECK(fake.registers[AHCI_PX_CLB / 4U] == 0xc000U);
    CHECK(fake.registers[AHCI_PX_IE / 4U] == AHCI_PORT_INITIAL_IE_MASK);

    init_active_fake(&fake, AHCI_SIG_ATA);
    fake.fisStuck = 1;
    CHECK(AHCIPortRecoverHardware(&ops, 0U, &arena) ==
          AHCI_PORT_ENGINE_TIMEOUT);
    CHECK(fake.delayedMilliseconds == AHCI_ENGINE_TIMEOUT_MS);
}

static void test_recovery_identify_is_polling_only_and_validates_data(void)
{
    union {
        AHCIU32 align;
        unsigned char bytes[AHCI_PORT_ARENA_USABLE_BYTES];
    } storage;
    AHCIPortOps ops;
    AHCIPortArena arena;
    PortFake fake;
    unsigned char *table;

    memset(&storage, 0, sizeof(storage));
    memset(&arena, 0, sizeof(arena));
    arena.physicalBase = 0x20000U;
    arena.commandListOffset = AHCI_PORT_COMMAND_LIST_OFFSET;
    arena.commandTableOffset = AHCI_PORT_COMMAND_TABLE_OFFSET;
    arena.identifyOffset = AHCI_PORT_IDENTIFY_OFFSET;
    arena.identifyBytes = AHCI_PORT_IDENTIFY_BYTES;
    ops.context = &fake;
    ops.read = port_read;
    ops.write = port_write;
    ops.delay = port_delay;
    ops.barrier = port_barrier;
    table = storage.bytes + AHCI_PORT_COMMAND_TABLE_OFFSET;

    init_active_fake(&fake, AHCI_SIG_ATA);
    fake.identifyCompleteAtMilliseconds = 2U;
    fake.identifyHeader = (AHCICommandHeader *)storage.bytes;
    fake.identifyData = (unsigned short *)(storage.bytes +
                                           AHCI_PORT_IDENTIFY_OFFSET);
    fake.identifyWord0 = 0x0040U;
    fake.identifyPortIS = AHCI_PXIS_DHRS;
    CHECK(AHCIPortRecoveryIdentify(&ops, 0U, &arena,
                                   (AHCICommandHeader *)storage.bytes,
                                   table, fake.identifyData,
                                   AHCI_DEVICE_SATA) == AHCI_PORT_SUCCESS);
    CHECK(table[2] == 0xecU);
    CHECK(fake.registers[AHCI_PX_IE / 4U] == 0);
    CHECK(fake.registers[AHCI_PX_IS / 4U] == 0);
    CHECK(fake.registers[AHCI_PX_SERR / 4U] == 0);
    CHECK(fake.delayedMilliseconds == 2U);

    memset(&storage, 0, sizeof(storage));
    init_active_fake(&fake, AHCI_SIG_ATAPI);
    fake.identifyCompleteAtMilliseconds = 1U;
    fake.identifyHeader = (AHCICommandHeader *)storage.bytes;
    fake.identifyData = (unsigned short *)(storage.bytes +
                                           AHCI_PORT_IDENTIFY_OFFSET);
    fake.identifyWord0 = 0x8000U;
    CHECK(AHCIPortRecoveryIdentify(&ops, 0U, &arena,
                                   (AHCICommandHeader *)storage.bytes,
                                   table, fake.identifyData,
                                   AHCI_DEVICE_ATAPI) == AHCI_PORT_SUCCESS);
    CHECK(table[2] == 0xa1U);

    memset(&storage, 0, sizeof(storage));
    init_active_fake(&fake, AHCI_SIG_ATA);
    fake.identifyCompleteAtMilliseconds = 1U;
    fake.identifyHeader = (AHCICommandHeader *)storage.bytes;
    fake.identifyData = (unsigned short *)(storage.bytes +
                                           AHCI_PORT_IDENTIFY_OFFSET);
    fake.identifyWord0 = 0x8000U;
    CHECK(AHCIPortRecoveryIdentify(&ops, 0U, &arena,
                                   (AHCICommandHeader *)storage.bytes,
                                   table, fake.identifyData,
                                   AHCI_DEVICE_SATA) ==
          AHCI_PORT_COMMAND_ERROR);

    memset(&storage, 0, sizeof(storage));
    init_active_fake(&fake, AHCI_SIG_ATA);
    fake.identifyCompleteAtMilliseconds = 1U;
    fake.identifyHeader = (AHCICommandHeader *)storage.bytes;
    fake.identifyData = (unsigned short *)(storage.bytes +
                                           AHCI_PORT_IDENTIFY_OFFSET);
    fake.identifyWord0 = 0x0040U;
    fake.identifyPortIS = AHCI_PXIS_TFES;
    CHECK(AHCIPortRecoveryIdentify(&ops, 0U, &arena,
                                   (AHCICommandHeader *)storage.bytes,
                                   table, fake.identifyData,
                                   AHCI_DEVICE_SATA) ==
          AHCI_PORT_COMMAND_ERROR);

    memset(&storage, 0, sizeof(storage));
    init_active_fake(&fake, AHCI_SIG_ATA);
    fake.identifyHeader = (AHCICommandHeader *)storage.bytes;
    fake.identifyData = (unsigned short *)(storage.bytes +
                                           AHCI_PORT_IDENTIFY_OFFSET);
    CHECK(AHCIPortRecoveryIdentify(&ops, 0U, &arena,
                                   (AHCICommandHeader *)storage.bytes,
                                   table, fake.identifyData,
                                   AHCI_DEVICE_SATA) ==
          AHCI_PORT_COMMAND_TIMEOUT);
    CHECK(fake.delayedMilliseconds == AHCI_RECOVERY_IDENTIFY_TIMEOUT_MS);

    memset(&storage, 0, sizeof(storage));
    init_active_fake(&fake, AHCI_SIG_ATA);
    fake.registers[AHCI_PX_TFD / 4U] = AHCI_TFD_BSY;
    fake.identifyCompleteAtMilliseconds = 1U;
    fake.identifyHeader = (AHCICommandHeader *)storage.bytes;
    fake.identifyData = (unsigned short *)(storage.bytes +
                                           AHCI_PORT_IDENTIFY_OFFSET);
    fake.identifyWord0 = 0x0040U;
    CHECK(AHCIPortRecoveryIdentify(&ops, 0U, &arena,
                                   (AHCICommandHeader *)storage.bytes,
                                   table, fake.identifyData,
                                   AHCI_DEVICE_SATA) ==
          AHCI_PORT_COMMAND_TIMEOUT);
    CHECK(fake.delayedMilliseconds == AHCI_TFD_TIMEOUT_MS);
    CHECK(fake.registers[AHCI_PX_CI / 4U] == 0);
    CHECK(fake.registers[AHCI_PX_IE / 4U] == 0);
}

static void test_completion_interrupts_are_enabled(void)
{
    CHECK((AHCI_PORT_INITIAL_IE_MASK & AHCI_PXIS_DHRS) != 0);
    CHECK((AHCI_PORT_INITIAL_IE_MASK & AHCI_PXIS_PSS) != 0);
    CHECK((AHCI_PORT_INITIAL_IE_MASK & AHCI_PXIS_DSS) != 0);
    CHECK((AHCI_PORT_INITIAL_IE_MASK & AHCI_PXIS_SDBS) != 0);
    CHECK((AHCI_PORT_INITIAL_IE_MASK & AHCI_PXIS_DPS) != 0);
}

static void test_received_fis_snapshot_covers_d2h_and_pio(void)
{
    volatile unsigned char source[256];
    unsigned char snapshot[256];

    memset((void *)source, 0, sizeof(source));
    memset(snapshot, 0, sizeof(snapshot));
    source[0x20] = 0x5f;
    source[0x40] = 0x34;
    source[0xff] = 0xa5;
    AHCICopyVolatileBytes(snapshot, source, sizeof(snapshot));
    CHECK(snapshot[0x20] == 0x5f);
    CHECK(snapshot[0x40] == 0x34);
    CHECK(snapshot[0xff] == 0xa5);
}

int main(void)
{
    test_arena_layout();
    test_arena_rejects_invalid_translations();
    test_engine_sequence_and_classification();
    test_comreset_only_for_recoverable_link();
    test_stop_masks_interrupts_and_stops_both_engines();
    test_empty_port_refuses_release_when_fis_will_not_stop();
    test_exact_engine_timeout_boundaries();
    test_exact_link_timeout_boundary();
    test_port_31_register_window();
    test_sparse_pi_includes_port_31();
    test_arena_release_requires_a_stopped_engine();
    test_buffer_translation_coalesces_pages();
    test_buffer_translation_rejects_unsafe_requests();
    test_slot_zero_command_layout();
    test_recovery_is_port_local_and_bounded();
    test_recovery_identify_is_polling_only_and_validates_data();
    test_completion_interrupts_are_enabled();
    test_received_fis_snapshot_covers_d2h_and_pio();
    if (failures != 0)
        return 1;
    printf("ahci_port_test: all tests passed\n");
    return 0;
}
