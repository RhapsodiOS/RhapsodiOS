#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "../powermac/macrisc_dt.h"

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

int
main(void)
{
    test_capture_rackmac();
    test_capture_variants();
    test_capture_failures();
    if (failures)
        return 1;
    printf("MacRISC platform tests passed\n");
    return 0;
}
