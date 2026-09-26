#include "macrisc_dt.h"

#define MACRISC_DEPTH 16
#define MACRISC_DMA_OFFSET 0x8000U
#define MACRISC_DMA_CHANNELS 32U
#define MACRISC_MPIC_SOURCES 64U        /* KeyLargo, Pangea, Intrepid */
#define MACRISC_VIA_WIDTH 7U

/* Nodes whose interrupts are decoded once #interrupt-cells is known. */
enum {
    kSlotVIA, kSlotPMU, kSlotNMI, kSlotSCCA, kSlotSCCB, kSlotMESH,
    kSlotFloppy, kSlotAudio, kSlotCount
};

typedef struct {
    int used;
    PEProperty aapl;
    PEProperty standard;
    unsigned char roles[3];
} MacRISCInterrupts;

typedef struct {
    PEResource resource;
    int dmaValid;
    unsigned int dma;
    MacRISCInterrupts irq;
} MacRISCATA;

typedef struct {
    PEFirmwareNode node;
    PEFirmwareNode next;
    unsigned int remaining;
    int inMacIO;
} MacRISCFrame;

typedef struct {
    const PEMacRISCFirmware *fw;
    PEMacRISCPlatform *platform;
    int malformed;
    int bootCPUFound;
    int macIOFound;
    unsigned int interruptCells;
    PEMacRISCIdentityInput identity;
    MacRISCInterrupts irq[kSlotCount];
    MacRISCATA ata[2];
    unsigned int ataCount;
} MacRISCCapture;

static PEProperty
macrisc_prop(MacRISCCapture *c, PEFirmwareNode node, const char *name)
{
    return c->fw->property(c->fw->context, node, name);
}

static int
macrisc_is(MacRISCCapture *c, PEFirmwareNode node, const char *name,
    const char *value)
{
    return PEPropertyHasString(macrisc_prop(c, node, name), value);
}

static int
macrisc_present(PEProperty property)
{
    return property.bytes != 0;
}

/* A one- or two-cell unsigned value such as a clock or cache size. */
static int
macrisc_read_value(PEProperty property, unsigned int *value)
{
    return PEReadAddress32(property, property.size / 4, value);
}

/* Same rules as PEKeyLargoParseMacIO, so both agree on the window. */
static int
macrisc_parse_macio(PEProperty address, PEProperty assigned, PEProperty reg,
    PEResource *macIO)
{
    unsigned int base;
    unsigned int size;
    unsigned int cell;
    int hasAddress;

    base = 0;
    hasAddress = macrisc_present(address);
    if (hasAddress && !PEReadAddress32(address, 1, &base))
        return 0;
    if (macrisc_present(assigned)) {
        if (assigned.size != 20 || !PEReadCell32(assigned, 1, &cell) ||
            cell != 0 || !PEReadCell32(assigned, 3, &cell) || cell != 0 ||
            !PEReadCell32(assigned, 2, &cell) ||
            !PEReadCell32(assigned, 4, &size))
            return 0;
    } else if (macrisc_present(reg)) {
        if (reg.size != 8 || !PEReadCell32(reg, 0, &cell) ||
            !PEReadCell32(reg, 1, &size))
            return 0;
    } else {
        return 0;
    }
    if (hasAddress && base != cell)
        return 0;
    base = cell;
    if (size == 0 || size > ~0U - base)
        return 0;
    return PEMacRISCSetResource(macIO, base, size);
}

/*
 * Mac-IO descendants give "reg" as offsets into the Mac-IO window, which is
 * how AppleMacIO and the legacy getters read them.  A well-formed
 * AAPL,address supplies the absolute base instead.  Range checks against
 * the window are left to PEMacRISCValidate so that its error names the
 * resource.
 */
static void
macrisc_child_resource(MacRISCCapture *c, PEFirmwareNode node,
    PEResource *resource)
{
    PEProperty reg;
    PEProperty address;
    unsigned int offset;
    unsigned int length;
    unsigned int base;
    const PEResource *macIO;

    macIO = &c->platform->macIO;
    if (!macIO->present)
        return;
    reg = macrisc_prop(c, node, "reg");
    address = macrisc_prop(c, node, "AAPL,address");
    if (resource->present || !PEReadCell32(reg, 0, &offset) ||
        !PEReadCell32(reg, 1, &length)) {
        c->malformed = 1;
        return;
    }
    if (macrisc_present(address)) {
        if (!PEReadCell32(address, 0, &base)) {
            c->malformed = 1;
            return;
        }
    } else {
        if (offset > ~0U - macIO->base) {
            c->malformed = 1;
            return;
        }
        base = macIO->base + offset;
    }
    if (!PEMacRISCSetResource(resource, base, length))
        c->malformed = 1;
}

/* DBDMA channel registers sit at Mac-IO 0x8000 + channel * 0x100. */
static int
macrisc_dma_channel(PEProperty reg, unsigned int entry,
    unsigned int *channel)
{
    unsigned int offset;

    if (!PEReadCell32(reg, entry * 2, &offset) ||
        offset < MACRISC_DMA_OFFSET ||
        offset >= MACRISC_DMA_OFFSET + MACRISC_DMA_CHANNELS * 0x100 ||
        (offset & 0xff) != 0)
        return 0;
    *channel = (offset - MACRISC_DMA_OFFSET) >> 8;
    return 1;
}

static void
macrisc_set_dma(MacRISCCapture *c, PEFirmwareNode node, unsigned int entry,
    const char *role)
{
    unsigned int channel;

    if (macrisc_dma_channel(macrisc_prop(c, node, "reg"), entry, &channel) &&
        !PEMacRISCSetDBDMA(&c->platform->dbdma, role, channel))
        c->malformed = 1;
}

static void
macrisc_stash(MacRISCCapture *c, MacRISCInterrupts *slot,
    PEFirmwareNode node, int role0, int role1, int role2)
{
    if (slot->used) {
        c->malformed = 1;
        return;
    }
    slot->used = 1;
    slot->aapl = macrisc_prop(c, node, "AAPL,interrupts");
    slot->standard = macrisc_prop(c, node, "interrupts");
    slot->roles[0] = (unsigned char)role0;
    slot->roles[1] = (unsigned char)role1;
    slot->roles[2] = (unsigned char)role2;
}

/* Record every sense cell under Mac-IO, assuming two-cell specifiers. */
static void
macrisc_record_senses(MacRISCCapture *c, PEFirmwareNode node)
{
    PEProperty interrupts;
    unsigned int entry;
    unsigned int source;
    unsigned int sense;
    unsigned char *senses;

    interrupts = macrisc_prop(c, node, "interrupts");
    if (interrupts.size == 0 || interrupts.size % 8 != 0)
        return;
    senses = c->platform->sourceSense;
    for (entry = 0; entry < interrupts.size / 8; entry++) {
        if (PEReadCell32(interrupts, entry * 2, &source) &&
            PEReadCell32(interrupts, entry * 2 + 1, &sense) &&
            source < PE_MACRISC_MAX_SOURCES && sense <= 3 &&
            senses[source] == PE_MACRISC_SENSE_UNKNOWN)
            senses[source] = (unsigned char)sense;
    }
}

static void
macrisc_visit_cpu(MacRISCCapture *c, PEFirmwareNode node)
{
    PEMacRISCPlatform *p;
    unsigned int reg;

    p = c->platform;
    p->cpuCount++;
    if (!macrisc_read_value(macrisc_prop(c, node, "reg"), &reg))
        reg = p->cpuCount - 1;
    /* The first CPU speaks for the machine unless CPU 0 turns up later. */
    if (c->bootCPUFound || (p->cpuCount > 1 && reg != 0))
        return;
    c->bootCPUFound = reg == 0;
    p->bootCPU = reg;
    if (!macrisc_read_value(macrisc_prop(c, node, "cpu-version"), &p->pvr))
        p->pvr = 0;
    if (!macrisc_read_value(macrisc_prop(c, node, "clock-frequency"),
        &p->cpuClockHz))
        p->cpuClockHz = 0;
    if (!macrisc_read_value(macrisc_prop(c, node, "bus-frequency"),
        &p->busClockHz))
        p->busClockHz = 0;
    if (!macrisc_read_value(macrisc_prop(c, node, "timebase-frequency"),
        &p->timebaseHz))
        p->timebaseHz = 0;
    if (!macrisc_read_value(macrisc_prop(c, node, "d-cache-size"),
        &p->dcacheSize))
        p->dcacheSize = 0;
    if (!macrisc_read_value(macrisc_prop(c, node, "d-cache-block-size"),
        &p->dcacheBlockSize))
        p->dcacheBlockSize = 0;
    if (!macrisc_read_value(macrisc_prop(c, node, "i-cache-size"),
        &p->icacheSize))
        p->icacheSize = 0;
    c->identity.pvr = p->pvr;
}

static void
macrisc_visit_macio(MacRISCCapture *c, PEFirmwareNode node,
    PEFirmwareNode parent)
{
    if (c->macIOFound) {
        c->malformed = 1;
        return;
    }
    c->macIOFound = 1;
    c->identity.hostCompatible = macrisc_prop(c, parent, "compatible");
    c->identity.macIOCompatible = macrisc_prop(c, node, "compatible");
    c->identity.macIODeviceID = macrisc_prop(c, node, "device-id");
    /* An unreadable window leaves macIO absent for validation to report. */
    (void)macrisc_parse_macio(macrisc_prop(c, node, "AAPL,address"),
        macrisc_prop(c, node, "assigned-addresses"),
        macrisc_prop(c, node, "reg"), &c->platform->macIO);
}

static void
macrisc_visit_ata(MacRISCCapture *c, PEFirmwareNode node)
{
    MacRISCATA *ata;
    unsigned int channel;

    if (c->ataCount == 2) {
        c->malformed = 1;
        return;
    }
    ata = &c->ata[c->ataCount++];
    macrisc_child_resource(c, node, &ata->resource);
    ata->dmaValid = macrisc_dma_channel(macrisc_prop(c, node, "reg"), 1,
        &channel);
    if (ata->dmaValid)
        ata->dma = channel;
    macrisc_stash(c, &ata->irq, node, kPERoleATA0, kPERoleATA0DMA,
        kPERoleNone);
}

static void
macrisc_visit_macio_child(MacRISCCapture *c, PEFirmwareNode node,
    PEFirmwareNode parent)
{
    PEMacRISCPlatform *p;
    PEProperty interruptCells;

    p = c->platform;
    macrisc_record_senses(c, node);
    if (macrisc_is(c, node, "device_type", "open-pic")) {
        macrisc_child_resource(c, node, &p->mpic);
        p->mpicSources = MACRISC_MPIC_SOURCES;
        interruptCells = macrisc_prop(c, node, "#interrupt-cells");
        if (macrisc_present(interruptCells) &&
            (!PEReadAddress32(interruptCells, 1, &c->interruptCells) ||
            (c->interruptCells != 1 && c->interruptCells != 2)))
            c->malformed = 1;
    } else if (macrisc_is(c, node, "name", "via-pmu") ||
        macrisc_is(c, node, "name", "via-cuda")) {
        if (macrisc_is(c, node, "name", "via-pmu"))
            p->hasPMU = 1;
        else
            p->hasCUDA = 1;
        macrisc_child_resource(c, node, &p->via);
        macrisc_stash(c, &c->irq[kSlotVIA], node, kPERoleVIA, kPERoleNone,
            kPERoleNone);
    } else if (macrisc_is(c, node, "name", "escc-legacy")) {
        macrisc_child_resource(c, node, &p->serial);
    } else if (macrisc_is(c, parent, "name", "escc-legacy") &&
        macrisc_is(c, node, "name", "ch-a")) {
        macrisc_set_dma(c, node, 1, "scc-a-tx");
        macrisc_set_dma(c, node, 2, "scc-a-rx");
        macrisc_stash(c, &c->irq[kSlotSCCA], node, kPERoleSCCA,
            kPERoleSCCATx, kPERoleSCCARx);
    } else if (macrisc_is(c, parent, "name", "escc-legacy") &&
        macrisc_is(c, node, "name", "ch-b")) {
        macrisc_set_dma(c, node, 1, "scc-b-tx");
        macrisc_set_dma(c, node, 2, "scc-b-rx");
        macrisc_stash(c, &c->irq[kSlotSCCB], node, kPERoleSCCB,
            kPERoleSCCBTx, kPERoleSCCBRx);
    } else if (macrisc_is(c, node, "name", "mesh")) {
        macrisc_child_resource(c, node, &p->mesh);
        macrisc_set_dma(c, node, 1, "mesh");
        macrisc_stash(c, &c->irq[kSlotMESH], node, kPERoleMESH,
            kPERoleMESHDMA, kPERoleNone);
    } else if (macrisc_is(c, node, "name", "swim3")) {
        macrisc_child_resource(c, node, &p->floppy);
        macrisc_set_dma(c, node, 1, "floppy");
        macrisc_stash(c, &c->irq[kSlotFloppy], node, kPERoleFloppy,
            kPERoleFloppyDMA, kPERoleNone);
    } else if (macrisc_is(c, node, "device_type", "ata")) {
        macrisc_visit_ata(c, node);
    } else if (macrisc_is(c, node, "name", "i2s-a")) {
        macrisc_child_resource(c, node, &p->audio);
        macrisc_set_dma(c, node, 1, "audio-out");
        macrisc_set_dma(c, node, 2, "audio-in");
        macrisc_stash(c, &c->irq[kSlotAudio], node, kPERoleAudio,
            kPERoleAudioOut, kPERoleAudioIn);
    } else if (macrisc_is(c, node, "name", "extint-gpio1") ||
        macrisc_is(c, node, "name", "pmu-interrupt")) {
        macrisc_stash(c, &c->irq[kSlotPMU], node, kPERolePMU, kPERoleNone,
            kPERoleNone);
    } else if (macrisc_is(c, node, "name", "programmer-switch")) {
        macrisc_stash(c, &c->irq[kSlotNMI], node, kPERoleNMI, kPERoleNone,
            kPERoleNone);
    }
}

static void
macrisc_visit(MacRISCCapture *c, PEFirmwareNode node, PEFirmwareNode parent,
    int parentIsRoot, int inMacIO)
{
    PEMacRISCPlatform *p;
    unsigned int offset;
    unsigned int length;
    PEProperty reg;

    p = c->platform;
    if (inMacIO) {
        macrisc_visit_macio_child(c, node, parent);
    } else if (macrisc_is(c, node, "device_type", "cpu")) {
        macrisc_visit_cpu(c, node);
    } else if (macrisc_is(c, node, "name", "l2-cache")) {
        if (p->l2CacheSize == 0 &&
            !macrisc_read_value(macrisc_prop(c, node, "d-cache-size"),
            &p->l2CacheSize))
            p->l2CacheSize = 0;
        if (macrisc_present(macrisc_prop(c, node, "cache-unified")))
            p->cachesUnified = 1;
    } else if (macrisc_is(c, node, "device_type", "mac-io") ||
        macrisc_is(c, node, "name", "mac-io")) {
        macrisc_visit_macio(c, node, parent);
    } else if (parentIsRoot && macrisc_is(c, node, "name", "nvram") &&
        macrisc_is(c, node, "compatible", "nvram,flash")) {
        reg = macrisc_prop(c, node, "reg");
        if (p->nvram.present || !PEReadCell32(reg, 0, &offset) ||
            !PEReadCell32(reg, 1, &length) ||
            !PEMacRISCSetResource(&p->nvram, offset, length))
            c->malformed = 1;
    }
}

/* Depth-first walk with a fixed stack; returns 0 if the tree is too deep. */
static int
macrisc_walk(MacRISCCapture *c)
{
    const PEMacRISCFirmware *fw;
    MacRISCFrame stack[MACRISC_DEPTH];
    MacRISCFrame *top;
    PEFirmwareNode root;
    PEFirmwareNode child;
    unsigned int depth;
    int inMacIO;

    fw = c->fw;
    root = fw->root(fw->context);
    if (root == 0)
        return 0;
    c->identity.model = fw->property(fw->context, root, "compatible");
    c->identity.rootCompatible = c->identity.model;
    stack[0].node = root;
    stack[0].remaining = fw->childCount(fw->context, root);
    stack[0].next = stack[0].remaining ? fw->firstChild(fw->context, root) :
        0;
    stack[0].inMacIO = 0;
    depth = 1;
    while (depth != 0) {
        top = &stack[depth - 1];
        if (top->remaining == 0 || top->next == 0) {
            depth--;
            continue;
        }
        child = top->next;
        top->remaining--;
        top->next = top->remaining ?
            fw->nextSibling(fw->context, child) : 0;
        inMacIO = top->inMacIO;
        macrisc_visit(c, child, top->node, depth == 1, inMacIO);
        if (fw->childCount(fw->context, child) == 0)
            continue;
        if (depth == MACRISC_DEPTH)
            return 0;
        stack[depth].node = child;
        stack[depth].remaining = fw->childCount(fw->context, child);
        stack[depth].next = fw->firstChild(fw->context, child);
        stack[depth].inMacIO = inMacIO || macrisc_is(c, child,
            "device_type", "mac-io") || macrisc_is(c, child, "name",
            "mac-io");
        depth++;
    }
    return 1;
}

static int
macrisc_interrupt(const MacRISCCapture *c, const MacRISCInterrupts *slot,
    unsigned int entry, unsigned int *source, unsigned int *sense)
{
    *sense = PE_MACRISC_SENSE_UNKNOWN;
    if (slot->aapl.size != 0 && slot->aapl.size % 4 == 0)
        return PEReadCell32(slot->aapl, entry, source);
    if (slot->standard.size == 0 ||
        slot->standard.size % (4 * c->interruptCells) != 0 ||
        !PEReadCell32(slot->standard, entry * c->interruptCells, source))
        return 0;
    if (c->interruptCells == 2 &&
        !PEReadCell32(slot->standard, entry * 2 + 1, sense))
        *sense = PE_MACRISC_SENSE_UNKNOWN;
    return 1;
}

static void
macrisc_assign(MacRISCCapture *c, const MacRISCInterrupts *slot)
{
    PEMacRISCPlatform *p;
    unsigned int entry;
    unsigned int source;
    unsigned int sense;

    p = c->platform;
    for (entry = 0; entry < 3; entry++) {
        if (slot->roles[entry] == kPERoleNone ||
            !macrisc_interrupt(c, slot, entry, &source, &sense))
            continue;
        if (source >= PE_MACRISC_MAX_SOURCES ||
            (p->sourceRole[source] != kPERoleNone &&
            p->sourceRole[source] != slot->roles[entry])) {
            c->malformed = 1;
            return;
        }
        p->sourceRole[source] = slot->roles[entry];
        if (sense <= 3)
            p->sourceSense[source] = (unsigned char)sense;
        if (slot->roles[entry] == kPERoleVIA) {
            p->hasCascade = 1;
            p->cascadeSource = source;
            p->cascadeWidth = MACRISC_VIA_WIDTH;
        } else if (slot->roles[entry] == kPERolePMU) {
            p->hasPMUInterrupt = 1;
            p->pmuInterruptSource = source;
        }
    }
}

/* The ATA node with the lower register offset is ata0, as legacy code has it. */
static void
macrisc_finish_ata(MacRISCCapture *c)
{
    PEMacRISCPlatform *p;
    MacRISCATA *first;
    MacRISCATA *second;
    MacRISCATA *swap;

    p = c->platform;
    if (c->ataCount == 0)
        return;
    first = &c->ata[0];
    second = c->ataCount == 2 ? &c->ata[1] : 0;
    if (second != 0 && second->resource.base < first->resource.base) {
        swap = first;
        first = second;
        second = swap;
    }
    p->ata0 = first->resource;
    if (first->dmaValid && !PEMacRISCSetDBDMA(&p->dbdma, "ata0", first->dma))
        c->malformed = 1;
    macrisc_assign(c, &first->irq);
    if (second == 0)
        return;
    p->ata1 = second->resource;
    if (second->dmaValid &&
        !PEMacRISCSetDBDMA(&p->dbdma, "ata1", second->dma))
        c->malformed = 1;
    second->irq.roles[0] = kPERoleATA1;
    second->irq.roles[1] = kPERoleATA1DMA;
    macrisc_assign(c, &second->irq);
}

PEMacRISCStatus
PEMacRISCCapture(const PEMacRISCFirmware *firmware,
    PEMacRISCPlatform *platform, PEPlatformError *error)
{
    MacRISCCapture c;
    PEMacRISCStatus status;
    unsigned char *bytes;
    unsigned int i;

    if (error != 0)
        *error = kPEPlatformValid;
    if (firmware == 0 || platform == 0 || error == 0)
        return kPEMacRISCMalformed;
    bytes = (unsigned char *)&c;
    for (i = 0; i < sizeof(c); i++)
        bytes[i] = 0;
    c.fw = firmware;
    c.platform = platform;
    c.interruptCells = 2;
    PEMacRISCPlatformInit(platform);
    if (!macrisc_walk(&c))
        return kPEMacRISCMalformed;

    status = PEMacRISCClassify(&c.identity, &platform->cpuFamily,
        &platform->macIOFamily, platform->model);
    platform->listedModel = status == kPEMacRISCSupported;
    if (status != kPEMacRISCSupported &&
        status != kPEMacRISCCompatibleUnlisted)
        return status;

    if (c.interruptCells != 2)
        for (i = 0; i < PE_MACRISC_MAX_SOURCES; i++)
            platform->sourceSense[i] = PE_MACRISC_SENSE_UNKNOWN;
    for (i = 0; i < kSlotCount; i++)
        if (c.irq[i].used)
            macrisc_assign(&c, &c.irq[i]);
    macrisc_finish_ata(&c);
    if (c.malformed)
        return kPEMacRISCMalformed;
    *error = PEMacRISCValidate(platform);
    return *error == kPEPlatformValid ? status : kPEMacRISCMalformed;
}

#ifndef MACRISC_HOST_TEST

#include <machdep/ppc/boot.h>
#include <machdep/ppc/DeviceTree.h>
#include <sys/systm.h>

/*
 * This runs from identify_machine1(), before VM is up, so it walks the
 * flattened tree directly: DTCreateEntryIterator() and DTEnterEntry()
 * allocate.
 */
static DeviceTreeNode *
macrisc_dt_skip_properties(DeviceTreeNode *node)
{
    DeviceTreeNodeProperty *property;
    unsigned long index;

    property = (DeviceTreeNodeProperty *)(node + 1);
    for (index = 0; index < node->nProperties; index++)
        property = (DeviceTreeNodeProperty *)((char *)(property + 1) +
            ((property->length + 3) & ~3UL));
    return (DeviceTreeNode *)property;
}

static PEFirmwareNode
macrisc_dt_root(void *context)
{
    DTEntry root;

    (void)context;
    if (DTLookupEntry(0, "/", &root) != kSuccess)
        return 0;
    return (PEFirmwareNode)root;
}

static unsigned int
macrisc_dt_child_count(void *context, PEFirmwareNode node)
{
    (void)context;
    return (unsigned int)((DeviceTreeNode *)node)->nChildren;
}

static PEFirmwareNode
macrisc_dt_first_child(void *context, PEFirmwareNode node)
{
    (void)context;
    return (PEFirmwareNode)macrisc_dt_skip_properties(
        (DeviceTreeNode *)node);
}

/* Skip a whole subtree: each node consumed adds its children to skip. */
static PEFirmwareNode
macrisc_dt_next_sibling(void *context, PEFirmwareNode node)
{
    DeviceTreeNode *entry;
    unsigned long pending;

    (void)context;
    entry = (DeviceTreeNode *)node;
    pending = 1;
    while (pending != 0) {
        pending = pending - 1 + entry->nChildren;
        entry = macrisc_dt_skip_properties(entry);
    }
    return (PEFirmwareNode)entry;
}

static PEProperty
macrisc_dt_property(void *context, PEFirmwareNode node, const char *name)
{
    PEProperty property;
    void *bytes;
    int size;

    (void)context;
    property.bytes = 0;
    property.size = 0;
    if (DTGetProperty((DTEntry)node, name, &bytes, &size) == kSuccess &&
        size >= 0) {
        property.bytes = (const unsigned char *)bytes;
        property.size = (unsigned int)size;
    }
    return property;
}

static PEMacRISCPlatform macrisc_platform;
static int macrisc_platform_valid;

PEMacRISCStatus
PEMacRISCDiscoverDeviceTree(PEPlatformError *error)
{
    PEMacRISCFirmware firmware;
    PEMacRISCStatus status;

    firmware.context = 0;
    firmware.root = macrisc_dt_root;
    firmware.childCount = macrisc_dt_child_count;
    firmware.firstChild = macrisc_dt_first_child;
    firmware.nextSibling = macrisc_dt_next_sibling;
    firmware.property = macrisc_dt_property;
    macrisc_platform_valid = 0;
    status = PEMacRISCCapture(&firmware, &macrisc_platform, error);
    macrisc_platform_valid = status == kPEMacRISCSupported ||
        status == kPEMacRISCCompatibleUnlisted;
    return status;
}

const PEMacRISCPlatform *
PEMacRISCGetPlatform(void)
{
    return macrisc_platform_valid ? &macrisc_platform : 0;
}

void
PEMacRISCPrintFailure(PEMacRISCStatus status, PEPlatformError error)
{
    printf("MacRISC: %s rejected: status %d error %d\n",
        macrisc_platform.model[0] ? macrisc_platform.model : "unknown",
        (int)status, (int)error);
}

#endif /* !MACRISC_HOST_TEST */
