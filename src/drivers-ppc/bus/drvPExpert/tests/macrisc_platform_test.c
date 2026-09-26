#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "../powermac/macrisc_dt.h"
#include "../powermac/families/macrisc.h"
#include <interrupts.h>
#include <machdep/ppc/dbdma.h>

static int failures;

#define CHECK(x) do { \
    if (!(x)) { \
        printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #x); \
        failures++; \
    } \
} while (0)

/* A tiny in-memory device tree behind the PEMacRISCFirmware seam. */
#define MAX_NODES 48
#define MAX_PROPS 16

typedef struct {
    const char *name;
    unsigned int offset;
    unsigned int size;
} FakeProp;

typedef struct FakeNode {
    FakeProp props[MAX_PROPS];
    unsigned int propCount;
    struct FakeNode *firstChild;
    struct FakeNode *lastChild;
    struct FakeNode *next;
    unsigned int childCount;
} FakeNode;

static unsigned char arena[16384];
static unsigned int arenaUsed;
static FakeNode nodes[MAX_NODES];
static unsigned int nodeCount;

static void
fake_reset(void)
{
    memset(arena, 0, sizeof(arena));
    memset(nodes, 0, sizeof(nodes));
    arenaUsed = 0;
    nodeCount = 0;
}

static void
add_bytes(FakeNode *node, const char *name, const void *bytes,
    unsigned int size)
{
    FakeProp *prop;

    if (node->propCount == MAX_PROPS || arenaUsed + size > sizeof(arena)) {
        printf("FAIL fake tree is full\n");
        failures++;
        return;
    }
    prop = &node->props[node->propCount++];
    prop->name = name;
    prop->offset = arenaUsed;
    prop->size = size;
    memcpy(arena + arenaUsed, bytes, size);
    arenaUsed += (size + 3) & ~3U;
}

static void
add_string(FakeNode *node, const char *name, const char *value)
{
    add_bytes(node, name, value, (unsigned int)strlen(value) + 1);
}

static void
add_cells(FakeNode *node, const char *name, unsigned int count, ...)
{
    unsigned char bytes[64];
    unsigned int i;
    unsigned int value;
    va_list args;

    va_start(args, count);
    for (i = 0; i < count; i++) {
        value = va_arg(args, unsigned int);
        bytes[i * 4] = (unsigned char)(value >> 24);
        bytes[i * 4 + 1] = (unsigned char)(value >> 16);
        bytes[i * 4 + 2] = (unsigned char)(value >> 8);
        bytes[i * 4 + 3] = (unsigned char)value;
    }
    va_end(args);
    add_bytes(node, name, bytes, count * 4);
}

static FakeNode *
add_node(FakeNode *parent, const char *name)
{
    FakeNode *node;

    if (nodeCount == MAX_NODES) {
        printf("FAIL fake tree has too many nodes\n");
        failures++;
        return &nodes[MAX_NODES - 1];
    }
    node = &nodes[nodeCount++];
    add_string(node, "name", name);
    if (parent != 0) {
        if (parent->lastChild != 0)
            parent->lastChild->next = node;
        else
            parent->firstChild = node;
        parent->lastChild = node;
        parent->childCount++;
    }
    return node;
}

static FakeProp *
find_prop(FakeNode *node, const char *name)
{
    unsigned int i;

    for (i = 0; i < node->propCount; i++)
        if (strcmp(node->props[i].name, name) == 0)
            return &node->props[i];
    return 0;
}

static void
remove_prop(FakeNode *node, const char *name)
{
    FakeProp *prop;

    prop = find_prop(node, name);
    if (prop != 0)
        prop->name = "removed";
}

static PEFirmwareNode
fake_root(void *context)
{
    (void)context;
    return nodeCount ? &nodes[0] : 0;
}

static unsigned int
fake_child_count(void *context, PEFirmwareNode node)
{
    (void)context;
    return ((FakeNode *)node)->childCount;
}

static PEFirmwareNode
fake_first_child(void *context, PEFirmwareNode node)
{
    (void)context;
    return ((FakeNode *)node)->firstChild;
}

static PEFirmwareNode
fake_next_sibling(void *context, PEFirmwareNode node)
{
    (void)context;
    return ((FakeNode *)node)->next;
}

static PEProperty
fake_property(void *context, PEFirmwareNode node, const char *name)
{
    PEProperty property;
    FakeProp *prop;

    (void)context;
    property.bytes = 0;
    property.size = 0;
    prop = find_prop((FakeNode *)node, name);
    if (prop != 0) {
        property.bytes = arena + prop->offset;
        property.size = prop->size;
    }
    return property;
}

static PEMacRISCFirmware
fake_firmware(void)
{
    PEMacRISCFirmware firmware;

    firmware.context = 0;
    firmware.root = fake_root;
    firmware.childCount = fake_child_count;
    firmware.firstChild = fake_first_child;
    firmware.nextSibling = fake_next_sibling;
    firmware.property = fake_property;
    return firmware;
}

typedef struct {
    FakeNode *root, *cpu0, *cpu1, *host, *macIO, *mpic, *via, *gpio1;
    FakeNode *serial, *chA, *chB, *ata3, *ata4, *i2sA, *nvram;
} Tree;

static void
add_cpu(Tree *t, FakeNode **cpu, const char *name, unsigned int reg)
{
    FakeNode *l2;

    *cpu = add_node(t->root->firstChild, name);
    add_string(*cpu, "device_type", "cpu");
    add_cells(*cpu, "reg", 1, reg);
    add_cells(*cpu, "cpu-version", 1, 0x80010201U);
    add_cells(*cpu, "clock-frequency", 1, 1000000000U);
    add_cells(*cpu, "bus-frequency", 1, 133333333U);
    add_cells(*cpu, "timebase-frequency", 1, 33333333U);
    add_cells(*cpu, "d-cache-size", 1, 0x8000U);
    add_cells(*cpu, "d-cache-block-size", 1, 32U);
    add_cells(*cpu, "i-cache-size", 1, 0x8000U);
    l2 = add_node(*cpu, "l2-cache");
    add_string(l2, "device_type", "cache");
    add_cells(l2, "d-cache-size", 1, 0x40000U);
    add_bytes(l2, "cache-unified", "", 0);
}

/* A dual-processor Xserve G4 as its firmware describes it. */
static void
build_rackmac(Tree *t)
{
    static const unsigned char compatible[] =
        "RackMac1,1\0MacRISC2\0MacRISC\0Power Macintosh";
    FakeNode *i2s;
    FakeNode *gpio;

    fake_reset();
    t->root = add_node(0, "device-tree");
    add_bytes(t->root, "compatible", compatible, sizeof(compatible));
    add_node(t->root, "cpus");
    add_cpu(t, &t->cpu0, "PowerPC,G4", 0);
    add_cpu(t, &t->cpu1, "PowerPC,G4", 1);

    t->nvram = add_node(t->root, "nvram");
    add_string(t->nvram, "compatible", "nvram,flash");
    add_cells(t->nvram, "reg", 2, 0xfff80000U, 0x20000U);

    t->host = add_node(t->root, "pci");
    add_string(t->host, "compatible", "uni-north");
    t->macIO = add_node(t->host, "mac-io");
    add_string(t->macIO, "device_type", "mac-io");
    add_string(t->macIO, "compatible", "Keylargo");
    add_cells(t->macIO, "device-id", 1, 0x22U);
    add_cells(t->macIO, "assigned-addresses", 5, 0x82013810U, 0U,
        0x80000000U, 0U, 0x80000U);

    t->mpic = add_node(t->macIO, "interrupt-controller");
    add_string(t->mpic, "device_type", "open-pic");
    add_cells(t->mpic, "reg", 2, 0x40000U, 0x40000U);
    add_cells(t->mpic, "#interrupt-cells", 1, 2U);

    t->via = add_node(t->macIO, "via-pmu");
    add_cells(t->via, "reg", 2, 0x16000U, 0x2000U);
    add_cells(t->via, "interrupts", 2, 0x19U, 1U);

    gpio = add_node(t->macIO, "gpio");
    add_cells(gpio, "reg", 2, 0x50U, 0x30U);
    t->gpio1 = add_node(gpio, "extint-gpio1");
    add_cells(t->gpio1, "interrupts", 2, 0x2fU, 1U);

    t->serial = add_node(t->macIO, "escc-legacy");
    add_cells(t->serial, "reg", 2, 0x12000U, 0x1000U);
    t->chA = add_node(t->serial, "ch-a");
    add_cells(t->chA, "reg", 6, 0x12004U, 0x10U, 0x8400U, 0x100U,
        0x8500U, 0x100U);
    add_cells(t->chA, "interrupts", 6, 0x16U, 1U, 0x04U, 0U, 0x05U, 0U);
    t->chB = add_node(t->serial, "ch-b");
    add_cells(t->chB, "reg", 6, 0x12000U, 0x10U, 0x8600U, 0x100U,
        0x8700U, 0x100U);
    add_cells(t->chB, "interrupts", 6, 0x17U, 1U, 0x06U, 0U, 0x07U, 0U);

    /* ata-3 comes first in the tree but has the higher offset. */
    t->ata3 = add_node(t->macIO, "ata-3");
    add_string(t->ata3, "device_type", "ata");
    add_cells(t->ata3, "reg", 4, 0x20000U, 0x1000U, 0x8a00U, 0x100U);
    add_cells(t->ata3, "interrupts", 4, 0x14U, 1U, 0x0aU, 0U);
    t->ata4 = add_node(t->macIO, "ata-4");
    add_string(t->ata4, "device_type", "ata");
    add_cells(t->ata4, "reg", 4, 0x1f000U, 0x1000U, 0x8b00U, 0x100U);
    add_cells(t->ata4, "interrupts", 4, 0x13U, 1U, 0x0bU, 0U);

    i2s = add_node(t->macIO, "i2s");
    add_cells(i2s, "reg", 2, 0x10000U, 0x1000U);
    t->i2sA = add_node(i2s, "i2s-a");
    add_cells(t->i2sA, "reg", 6, 0x10000U, 0x1000U, 0x8800U, 0x100U,
        0x8900U, 0x100U);
    add_cells(t->i2sA, "interrupts", 6, 0x1eU, 1U, 0x01U, 0U, 0x02U, 0U);
}

static PEMacRISCStatus
capture(PEMacRISCPlatform *p, PEPlatformError *error)
{
    PEMacRISCFirmware firmware;

    firmware = fake_firmware();
    return PEMacRISCCapture(&firmware, p, error);
}

static void
test_capture_rackmac(void)
{
    static unsigned char saved[sizeof(arena)];
    PEMacRISCPlatform p;
    PEPlatformError error;
    Tree t;

    build_rackmac(&t);
    memcpy(saved, arena, sizeof(arena));
    CHECK(capture(&p, &error) == kPEMacRISCSupported);
    CHECK(error == kPEPlatformValid);
    CHECK(memcmp(saved, arena, sizeof(arena)) == 0);

    CHECK(strcmp(p.model, "RackMac1,1") == 0 && p.listedModel);
    CHECK(p.cpuFamily == kPECPU745x && p.macIOFamily == kPEMacIOKeyLargo);
    CHECK(p.cpuCount == 2 && p.bootCPU == 0 && p.pvr == 0x80010201U);
    CHECK(p.cpuClockHz == 1000000000U && p.busClockHz == 133333333U);
    CHECK(p.timebaseHz == 33333333U);
    CHECK(p.dcacheSize == 0x8000U && p.dcacheBlockSize == 32U);
    CHECK(p.icacheSize == 0x8000U && p.l2CacheSize == 0x40000U);
    CHECK(p.cachesUnified);

    CHECK(p.macIO.base == 0x80000000U && p.macIO.length == 0x80000U);
    CHECK(p.mpic.base == 0x80040000U && p.mpic.length == 0x40000U);
    CHECK(p.mpicSources == 64);
    CHECK(p.via.base == 0x80016000U && p.hasPMU && !p.hasCUDA);
    CHECK(p.hasCascade && p.cascadeSource == 25 && p.cascadeWidth == 7);
    CHECK(p.hasPMUInterrupt && p.pmuInterruptSource == 47);
    CHECK(p.serial.base == 0x80012000U);
    CHECK(p.nvram.base == 0xfff80000U);
    CHECK(p.ata0.base == 0x8001f000U && p.ata1.base == 0x80020000U);
    CHECK(p.audio.base == 0x80010000U);
    CHECK(!p.mesh.present && !p.floppy.present && !p.ethernet.present);

    CHECK(p.dbdma.ata0 == 0x0b && p.dbdma.ata1 == 0x0a);
    CHECK(p.dbdma.sccATx == 4 && p.dbdma.sccARx == 5);
    CHECK(p.dbdma.sccBTx == 6 && p.dbdma.sccBRx == 7);
    CHECK(p.dbdma.audioOut == 8 && p.dbdma.audioIn == 9);
    CHECK(p.dbdma.mesh == -1 && p.dbdma.floppy == -1 && p.dbdma.curio == -1);

    CHECK(p.sourceRole[0x13] == kPERoleATA0 && p.sourceSense[0x13] == 1);
    CHECK(p.sourceRole[0x0b] == kPERoleATA0DMA && p.sourceSense[0x0b] == 0);
    CHECK(p.sourceRole[0x14] == kPERoleATA1);
    CHECK(p.sourceRole[0x16] == kPERoleSCCA);
    CHECK(p.sourceRole[0x04] == kPERoleSCCATx);
    CHECK(p.sourceRole[0x17] == kPERoleSCCB);
    CHECK(p.sourceRole[0x19] == kPERoleVIA);
    CHECK(p.sourceRole[0x2f] == kPERolePMU);
    CHECK(p.sourceRole[0x1e] == kPERoleAudio);
    CHECK(p.sourceRole[0x30] == kPERoleNone);
    CHECK(p.sourceSense[0x30] == PE_MACRISC_SENSE_UNKNOWN);
}

static void
test_capture_variants(void)
{
    PEMacRISCPlatform p;
    PEPlatformError error;
    Tree t;

    /* Missing optional devices stay absent rather than aliasing Mac-IO. */
    build_rackmac(&t);
    t.macIO->childCount--;          /* drops the trailing i2s subtree */
    t.ata4->next = 0;
    remove_prop(t.ata3, "device_type");
    CHECK(capture(&p, &error) == kPEMacRISCSupported);
    CHECK(p.ata0.base == 0x8001f000U && !p.ata1.present);
    CHECK(p.dbdma.ata1 == -1 && !p.audio.present && p.dbdma.audioOut == -1);

    /* AAPL,interrupts wins over the two-cell form. */
    build_rackmac(&t);
    add_cells(t.via, "AAPL,interrupts", 1, 0x1aU);
    CHECK(capture(&p, &error) == kPEMacRISCSupported);
    CHECK(p.cascadeSource == 0x1a);

    /* One-cell specifiers carry no sense. */
    build_rackmac(&t);
    find_prop(t.mpic, "#interrupt-cells")->name = "removed";
    add_cells(t.mpic, "#interrupt-cells", 1, 1U);
    remove_prop(t.via, "interrupts");
    add_cells(t.via, "interrupts", 1, 0x19U);
    remove_prop(t.gpio1, "interrupts");
    add_cells(t.gpio1, "interrupts", 1, 0x2fU);
    remove_prop(t.ata4, "interrupts");
    add_cells(t.ata4, "interrupts", 2, 0x13U, 0x0bU);
    remove_prop(t.ata3, "interrupts");
    add_cells(t.ata3, "interrupts", 2, 0x14U, 0x0aU);
    remove_prop(t.chA, "interrupts");
    add_cells(t.chA, "interrupts", 3, 0x16U, 0x04U, 0x05U);
    remove_prop(t.chB, "interrupts");
    remove_prop(t.i2sA, "interrupts");
    CHECK(capture(&p, &error) == kPEMacRISCSupported);
    CHECK(p.cascadeSource == 0x19 && p.sourceRole[0x0b] == kPERoleATA0DMA);
    CHECK(p.sourceRole[0x05] == kPERoleSCCARx);
    CHECK(p.sourceRole[0x17] == kPERoleNone);
    CHECK(p.sourceSense[0x13] == PE_MACRISC_SENSE_UNKNOWN);

    /* A CUDA desktop, an unlisted model, and a later CPU 0. */
    build_rackmac(&t);
    t.via->props[0].name = "removed";
    add_string(t.via, "name", "via-cuda");
    remove_prop(t.root, "compatible");
    add_bytes(t.root, "compatible", "PowerMac9,9\0MacRISC2", 21);
    find_prop(t.cpu0, "reg")->name = "removed";
    add_cells(t.cpu0, "reg", 1, 1U);
    find_prop(t.cpu1, "reg")->name = "removed";
    add_cells(t.cpu1, "reg", 1, 0U);
    find_prop(t.cpu1, "timebase-frequency")->name = "removed";
    add_cells(t.cpu1, "timebase-frequency", 1, 25000000U);
    CHECK(capture(&p, &error) == kPEMacRISCCompatibleUnlisted);
    CHECK(p.hasCUDA && !p.hasPMU && !p.listedModel);
    CHECK(p.bootCPU == 0 && p.timebaseHz == 25000000U);
}

static void
test_capture_failures(void)
{
    PEMacRISCPlatform p;
    PEPlatformError error;
    FakeNode *node;
    unsigned int i;
    Tree t;

    build_rackmac(&t);
    remove_prop(t.cpu0, "cpu-version");
    add_cells(t.cpu0, "cpu-version", 1, 0x00390200U);
    remove_prop(t.cpu1, "cpu-version");
    CHECK(capture(&p, &error) == kPEMacRISCUnsupportedCPU);
    CHECK(p.cpuFamily == kPECPU970);

    build_rackmac(&t);
    remove_prop(t.host, "compatible");
    add_string(t.host, "compatible", "u3-ht");
    CHECK(capture(&p, &error) == kPEMacRISCUnsupportedHost);

    build_rackmac(&t);
    remove_prop(t.mpic, "reg");
    add_cells(t.mpic, "reg", 2, 0x70000U, 0x40000U);
    CHECK(capture(&p, &error) == kPEMacRISCMalformed);
    CHECK(error == kPEPlatformBadMPICRange);

    build_rackmac(&t);
    remove_prop(t.mpic, "reg");
    add_cells(t.mpic, "reg", 1, 0x40000U);
    CHECK(capture(&p, &error) == kPEMacRISCMalformed);

    build_rackmac(&t);
    remove_prop(t.macIO, "assigned-addresses");
    add_cells(t.macIO, "assigned-addresses", 4, 0x82013810U, 0U,
        0x80000000U, 0U);
    CHECK(capture(&p, &error) == kPEMacRISCMalformed);
    CHECK(error == kPEPlatformMissingMacIO);

    build_rackmac(&t);
    remove_prop(t.via, "interrupts");
    CHECK(capture(&p, &error) == kPEMacRISCMalformed);
    CHECK(error == kPEPlatformBadCascade);

    build_rackmac(&t);
    remove_prop(t.serial, "reg");
    CHECK(capture(&p, &error) == kPEMacRISCMalformed);

    build_rackmac(&t);
    remove_prop(t.nvram, "compatible");
    CHECK(capture(&p, &error) == kPEMacRISCMalformed);
    CHECK(error == kPEPlatformMissingNVRAM);

    build_rackmac(&t);
    remove_prop(t.ata4, "interrupts");
    add_cells(t.ata4, "interrupts", 4, 0x16U, 1U, 0x0bU, 0U);
    CHECK(capture(&p, &error) == kPEMacRISCMalformed);

    build_rackmac(&t);
    remove_prop(t.ata4, "interrupts");
    add_cells(t.ata4, "interrupts", 4, 0x40U, 1U, 0x0bU, 0U);
    CHECK(capture(&p, &error) == kPEMacRISCMalformed);

    /* Seventeen nested nodes exceed the traversal stack. */
    build_rackmac(&t);
    node = t.root;
    for (i = 0; i < 17; i++)
        node = add_node(node, "deep");
    CHECK(capture(&p, &error) == kPEMacRISCMalformed);

    CHECK(PEMacRISCCapture(0, &p, &error) == kPEMacRISCMalformed);
}

static void
test_routes(void)
{
    static const char *const sawtooth[] = {
        "PowerMac3,1", "PowerMac3,2", "PowerMac3,3", "PowerMac5,1",
        "PowerBook2,1"
    };
    static const char *const legacy[] = {
        "AAPL,9500", "AAPL,3400-2400", "AAPL,PowerMac-G3", "iMac",
        "PowerMac1,1", "PowerMac1,2", "PowerMac2,1", "PowerBook1,1"
    };
    unsigned int i;

    for (i = 0; i < sizeof(sawtooth) / sizeof(sawtooth[0]); i++) {
        CHECK(PEMacRISCSelectRoute(sawtooth[i], kPEMacRISCSupported) ==
            kPERouteSawtooth);
        CHECK(PEMacRISCSelectRoute(sawtooth[i], kPEMacRISCMalformed) ==
            kPERouteSawtooth);
    }
    for (i = 0; i < sizeof(legacy) / sizeof(legacy[0]); i++)
        CHECK(PEMacRISCSelectRoute(legacy[i], kPEMacRISCSupported) ==
            kPERouteLegacy);
    CHECK(PEMacRISCSelectRoute("RackMac1,1", kPEMacRISCSupported) ==
        kPERouteMacRISC);
    CHECK(PEMacRISCSelectRoute("PowerBook9,9",
        kPEMacRISCCompatibleUnlisted) == kPERouteMacRISC);
    CHECK(PEMacRISCSelectRoute("PowerMac7,2", kPEMacRISCUnsupportedCPU) ==
        kPERouteUnsupported);
    CHECK(PEMacRISCSelectRoute("PowerBook3,4", kPEMacRISCMalformed) ==
        kPERouteUnsupported);
    CHECK(PEMacRISCSelectRoute("PowerMac3,10", kPEMacRISCNotMatched) ==
        kPERouteUnsupported);
    CHECK(PEMacRISCSelectRoute("PowerMac3,1x", kPEMacRISCSupported) ==
        kPERouteMacRISC);
    CHECK(PEMacRISCSelectRoute(0, kPEMacRISCSupported) ==
        kPERouteUnsupported);
}

static void
test_publish(void)
{
    PEMacRISCPlatform p;
    PEMacRISCPublishedIO io;
    PEPlatformError error;
    Tree t;

    build_rackmac(&t);
    CHECK(capture(&p, &error) == kPEMacRISCSupported);
    CHECK(PEMacRISCPublish(&p, &io));
    CHECK(io.ioBase == 0x80000000U && io.ioSize == 0x80000U);
    CHECK(io.interruptBase == 0x80040000U);
    CHECK(io.dmaBase == 0x80008000U && io.viaBase == 0x80016000U);
    CHECK(io.serialBase == 0x80012000U && io.audioBase == 0x80010000U);
    CHECK(io.nvramAddress == 0xfff80000U && io.nvramData == 0);
    CHECK(io.ata0Base == 0x8001f000U && io.ata1Base == 0x80020000U);
    /* Absent devices publish 0, never a Mac-IO base alias. */
    CHECK(io.meshBase == 0 && io.floppyBase == 0 && io.ethernetBase == 0);

    p.mpic.present = 0;
    CHECK(!PEMacRISCPublish(&p, &io));
    CHECK(!PEMacRISCPublish(&p, 0));
}

static void
test_clock_conversion(void)
{
    PEMacRISCPlatform p;
    unsigned int numerator;
    unsigned int denominator;
    unsigned int period;

    PEMacRISCPlatformInit(&p);
    p.busClockHz = 100000000U;
    p.timebaseHz = 25000000U;
    CHECK(PEMacRISCComputeClockConversion(&p, &numerator, &denominator,
        &period));
    CHECK(numerator == 4000U && denominator == 100U);
    CHECK(period == 0x28000000U);

    p.busClockHz = 133333333U;
    p.timebaseHz = 33333333U;
    CHECK(PEMacRISCComputeClockConversion(&p, &numerator, &denominator,
        &period));
    CHECK(denominator == 133U && (period >> 24) == 30U);
    CHECK((period & 0xffffffU) == 5U);  /* 10 ns remainder * 2^24 / tb */

    p.timebaseHz = 0;
    CHECK(!PEMacRISCComputeClockConversion(&p, &numerator, &denominator,
        &period));
    p.timebaseHz = 3000000U;            /* 333 ns does not fit in 8 bits */
    CHECK(!PEMacRISCComputeClockConversion(&p, &numerator, &denominator,
        &period));
    p.timebaseHz = 25000000U;
    p.busClockHz = 999999U;
    CHECK(!PEMacRISCComputeClockConversion(&p, &numerator, &denominator,
        &period));
    CHECK(!PEMacRISCComputeClockConversion(0, &numerator, &denominator,
        &period));
}

static void
test_mpic_table(void)
{
    struct powermac_interrupt interrupts[PE_MACRISC_MAX_SOURCES];
    unsigned long mapping[PE_MACRISC_MAX_SOURCES * 2];
    PEMacRISCPlatform p;
    PEPlatformError error;
    unsigned int s;
    Tree t;

    build_rackmac(&t);
    CHECK(capture(&p, &error) == kPEMacRISCSupported);
    CHECK(p.cpuCount == 2);
    p.sourceSense[0x31] = 2;
    p.sourceSense[0x32] = 3;
    CHECK(PEMacRISCBuildMPIC(&p, interrupts, mapping));
    for (s = 0; s < PE_MACRISC_MAX_SOURCES; s++) {
        CHECK((mapping[s * 2] & 0xffUL) == s);
        CHECK((mapping[s * 2] & 0x80000000UL) != 0);    /* masked */
        CHECK(mapping[s * 2 + 1] == 1);                 /* CPU 0 only */
        CHECK(interrupts[s].i_handler == 0);
    }
    /* Sense cell 1: level, active low; device priority 2. */
    CHECK(mapping[0x13 * 2] == 0x80420013UL);
    CHECK(interrupts[0x13].i_device == PMAC_DEV_IDE0);
    /* Sense cell 0: edge, active high; DMA priority 4. */
    CHECK(mapping[0x0b * 2] == 0x80840000UL + 0x0b);
    CHECK(interrupts[0x0b].i_device == PMAC_DMA_IDE0);
    CHECK(interrupts[0x14].i_device == PMAC_DEV_IDE1);
    CHECK(interrupts[0x0a].i_device == PMAC_DMA_IDE1);
    CHECK(interrupts[0x16].i_device == PMAC_DEV_SCC_A);
    CHECK(interrupts[0x04].i_device == PMAC_DMA_SCC_A_TX);
    CHECK(interrupts[0x17].i_device == PMAC_DEV_SCC_B);
    CHECK(interrupts[0x08].i_device == -1);
    CHECK(interrupts[0x01].i_device == PMAC_DMA_AUDIO_OUT);
    /* VIA cascade: priority 1, handler installed by configure_macrisc. */
    CHECK(mapping[0x19 * 2] == 0x80410019UL);
    CHECK(interrupts[0x19].i_device == -1);
    /* PMU GPIO and unknown sources keep direct identities. */
    CHECK(interrupts[0x2f].i_device == -1);
    CHECK(PEMPIClogicalForSource(interrupts, 64, 0x2f) ==
        PMAC_DEV_MPIC_DIRECT_BASE + 0x2f);
    CHECK(mapping[0x30 * 2] == 0x80420030UL);
    CHECK(mapping[0x31 * 2] == 0x80c20031UL);           /* level, high */
    CHECK(mapping[0x32 * 2] == 0x80020032UL);           /* edge, low */
    CHECK(PEMPICsourceForDevice(interrupts, 64, PMAC_DEV_IDE0) == 0x13);

    p.mpic.present = 0;
    CHECK(!PEMacRISCBuildMPIC(&p, interrupts, mapping));
}

static void
test_dbdma_table(void)
{
    powermac_dbdma_channels_t channels;
    PEMacRISCPlatform p;
    PEPlatformError error;
    Tree t;

    build_rackmac(&t);
    CHECK(capture(&p, &error) == kPEMacRISCSupported);
    CHECK(PEMacRISCBuildDBDMA(&p.dbdma, &channels));
    CHECK(channels.dbdma_channel_ide0 == 0x0b);
    CHECK(channels.dbdma_channel_ide1 == 0x0a);
    CHECK(channels.dbdma_channel_scc_xmit_a == 4);
    CHECK(channels.dbdma_channel_scc_recv_a == 5);
    CHECK(channels.dbdma_channel_scc_xmit_b == 6);
    CHECK(channels.dbdma_channel_scc_recv_b == 7);
    CHECK(channels.dbdma_channel_audio_out == 8);
    CHECK(channels.dbdma_channel_audio_in == 9);
    CHECK(channels.dbdma_channel_curio == -1);
    CHECK(channels.dbdma_channel_mesh == -1);
    CHECK(channels.dbdma_channel_floppy == -1);
    CHECK(channels.dbdma_channel_ethernet_tx == -1);
    CHECK(channels.dbdma_channel_ethernet_rx == -1);
    CHECK(!PEMacRISCBuildDBDMA(0, &channels));
}

static void
test_pmu_interrupts(void)
{
    PEMacRISCPlatform p;
    PEPlatformError error;
    unsigned int list[2];
    Tree t;

    build_rackmac(&t);
    CHECK(capture(&p, &error) == kPEMacRISCSupported);
    CHECK(PEMacRISCPMUInterruptList(&p, list) == 2);
    CHECK(list[0] == 66 && list[1] == 47);
    /* What pmu.m sees after DriverKit's XOR: Sawtooth's 0x5a and 47. */
    CHECK((list[0] ^ 0x18) == 0x5a && (list[1] ^ 0x18) == (47 ^ 0x18));
    CHECK(PEMPICsourceForInterrupt(0, 64, 64 + 7, list[1] ^ 0x18) == 47);

    p.hasPMUInterrupt = 0;              /* no extint-gpio1: invent nothing */
    CHECK(PEMacRISCPMUInterruptList(&p, list) == 0);
    p.hasPMUInterrupt = 1;
    p.hasPMU = 0;
    p.hasCUDA = 1;                      /* CUDA machines have no PMU */
    CHECK(PEMacRISCPMUInterruptList(&p, list) == 0);
    p.hasPMU = 1;
    p.hasCUDA = 0;
    p.pmuInterruptSource = 64;
    CHECK(PEMacRISCPMUInterruptList(&p, list) == 0);
    CHECK(PEMacRISCPMUInterruptList(0, list) == 0);
    CHECK(PEMacRISCPMUInterruptList(&p, 0) == 0);
}

int
main(void)
{
    test_routes();
    test_pmu_interrupts();
    test_mpic_table();
    test_dbdma_table();
    test_publish();
    test_clock_conversion();
    test_capture_rackmac();
    test_capture_variants();
    test_capture_failures();
    if (failures)
        return 1;
    printf("MacRISC platform tests passed\n");
    return 0;
}
