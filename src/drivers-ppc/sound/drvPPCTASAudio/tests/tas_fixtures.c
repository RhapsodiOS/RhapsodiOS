#include "tas_fixtures.h"

#include <string.h>

static void put_be32(unsigned char *bytes, unsigned long value)
{
    bytes[0] = (unsigned char)(value >> 24);
    bytes[1] = (unsigned char)(value >> 16);
    bytes[2] = (unsigned char)(value >> 8);
    bytes[3] = (unsigned char)value;
}

static TASFixtureProperty *property_slot(TASFixture *fixture, TASNode node,
    const char *name)
{
    unsigned long index;
    for (index = 0; index < fixture->propertyCount; ++index) {
        if (fixture->properties[index].node == node &&
            strcmp(fixture->properties[index].name, name) == 0)
            return &fixture->properties[index];
    }
    if (fixture->propertyCount == TAS_FIXTURE_MAX_PROPERTIES)
        return 0;
    index = fixture->propertyCount++;
    fixture->properties[index].node = node;
    fixture->properties[index].name = name;
    fixture->properties[index].length = 0;
    return &fixture->properties[index];
}

void TASFixtureSetCells(TASFixture *fixture, TASNode node, const char *name,
    const unsigned long *cells, unsigned long count)
{
    TASFixtureProperty *entry;
    unsigned long index;
    entry = property_slot(fixture, node, name);
    entry->length = count * 4UL;
    for (index = 0; index < count; ++index)
        put_be32(entry->bytes + index * 4UL, cells[index]);
}

void TASFixtureSetString(TASFixture *fixture, TASNode node, const char *name,
    const char *value)
{
    TASFixtureProperty *entry;
    unsigned long length;
    entry = property_slot(fixture, node, name);
    length = (unsigned long)strlen(value) + 1UL;
    memcpy(entry->bytes, value, (size_t)length);
    entry->length = length;
}

void TASFixtureSetEmpty(TASFixture *fixture, TASNode node, const char *name)
{
    TASFixtureProperty *entry;
    entry = property_slot(fixture, node, name);
    entry->length = 0;
}

static void add_node(TASFixture *fixture, TASNode id, const char *name,
    const char *path, TASNode parent, unsigned long phandle)
{
    TASFixtureNode *entry;
    entry = &fixture->nodes[fixture->nodeCount++];
    entry->node = id;
    entry->name = name;
    entry->path = path;
    entry->parent = parent;
    entry->phandle = phandle;
}

static void add_gpio(TASFixture *fixture, TASNode node, const char *role,
    unsigned long location, int absolute, unsigned long active,
    unsigned long irq)
{
    unsigned long cells[1];
    TASFixtureSetString(fixture, node, "audio-gpio", role);
    cells[0] = location;
    TASFixtureSetCells(fixture, node, absolute ? "AAPL,address" : "reg",
        cells, 1);
    cells[0] = active;
    TASFixtureSetCells(fixture, node, "audio-gpio-active-state", cells, 1);
    if (irq != 0) {
        cells[0] = irq;
        TASFixtureSetCells(fixture, node, "AAPL,interrupts", cells, 1);
    }
}

static void base_fixture(TASFixture *fixture)
{
    unsigned long cells[8];
    memset(fixture, 0, sizeof(*fixture));
    add_node(fixture, kFixtureMacIO, "mac-io", "/mac-io", 0, 0x08);
    add_node(fixture, kFixtureI2S, "i2s", "/mac-io/i2s", kFixtureMacIO,
        0x0f);
    add_node(fixture, kFixtureSoundBus, "i2s-a", "/mac-io/i2s/i2s-a",
        kFixtureI2S, 0x10);
    add_node(fixture, kFixtureSoundChip, "sound",
        "/mac-io/i2s/i2s-a/sound", kFixtureSoundBus, 0x11);
    add_node(fixture, kFixtureI2C, "i2c", "/mac-io/i2c",
        kFixtureMacIO, 0x20);
    add_node(fixture, kFixtureI2CBus, "i2c-bus@1",
        "/mac-io/i2c/i2c-bus@1", kFixtureI2C, 0x21);
    add_node(fixture, kFixtureCodec, "deq",
        "/mac-io/i2c/i2c-bus@1/deq", kFixtureI2CBus, 0x30);
    add_node(fixture, kFixtureGPIO, "gpio", "/mac-io/gpio",
        kFixtureMacIO, 0x39);
    add_node(fixture, kFixtureHeadphoneMute, "headphone-mute",
        "/mac-io/gpio/headphone-mute", kFixtureGPIO, 0x40);
    add_node(fixture, kFixtureHeadphoneDetect, "headphone-detect",
        "/mac-io/gpio/headphone-detect", kFixtureGPIO, 0x41);
    add_node(fixture, kFixtureHardwareReset, "audio-hw-reset",
        "/mac-io/gpio/audio-hw-reset", kFixtureGPIO, 0x42);
    add_node(fixture, kFixtureAmplifierMute, "amp-mute",
        "/mac-io/gpio/amp-mute", kFixtureGPIO, 0x43);
    add_node(fixture, kFixtureInputMux, "codec-input-data-mux",
        "/mac-io/gpio/codec-input-data-mux", kFixtureGPIO, 0x44);
    add_node(fixture, kFixtureLineOutMute, "line-output-mute",
        "/mac-io/gpio/line-output-mute", kFixtureGPIO, 0x45);
    add_node(fixture, kFixtureLineOutDetect, "line-output-detect",
        "/mac-io/gpio/line-output-detect", kFixtureGPIO, 0x46);
    cells[0] = 0x80000000UL;
    TASFixtureSetCells(fixture, kFixtureMacIO, "AAPL,address", cells, 1);
    cells[0] = 0x10000; cells[1] = 0x1000;
    cells[2] = 0x08000; cells[3] = 0x0100;
    cells[4] = 0x08100; cells[5] = 0x0100;
    TASFixtureSetCells(fixture, kFixtureI2S, "reg", cells, 6);
    cells[0] = 30; cells[1] = 1;
    cells[2] = 24; cells[3] = 2;
    cells[4] = 25; cells[5] = 3;
    TASFixtureSetCells(fixture, kFixtureI2S, "interrupts", cells, 6);
    cells[0] = 0;
    TASFixtureSetCells(fixture, kFixtureSoundBus, "reg", cells, 1);
    cells[0] = 1;
    TASFixtureSetCells(fixture, kFixtureI2CBus, "reg", cells, 1);
    cells[0] = 44100; cells[1] = 48000;
    TASFixtureSetCells(fixture, kFixtureSoundChip, "sample-rates", cells, 2);
    cells[0] = 0x37;
    TASFixtureSetCells(fixture, kFixtureSoundChip, "layout-id", cells, 1);
    TASFixtureSetString(fixture, kFixtureSoundChip, "model", "PowerMac4,2");
}

void TASFixtureTumbler(TASFixture *fixture)
{
    unsigned long cells[1];
    base_fixture(fixture);
    TASFixtureSetString(fixture, kFixtureSoundChip, "compatible", "tumbler");
    cells[0] = 0x68;
    TASFixtureSetCells(fixture, kFixtureCodec, "i2c-address", cells, 1);
    TASFixtureSetString(fixture, kFixtureCodec, "compatible", "tumbler");
    TASFixtureReparent(fixture, kFixtureCodec, kFixtureI2C);
    TASFixtureSetPath(fixture, kFixtureCodec, "/mac-io/i2c/deq");
    cells[0] = 1;
    TASFixtureSetCells(fixture, kFixtureCodec, "AAPL,i2c-port-select",
        cells, 1);
    add_gpio(fixture, kFixtureHeadphoneMute, "headphone-mute",
        0x80000050UL, 1, 0, 0);
    add_gpio(fixture, kFixtureHeadphoneDetect, "headphone-detect",
        0x80000054UL, 1, 1, 47);
    add_gpio(fixture, kFixtureHardwareReset, "audio-hw-reset",
        0x80000060UL, 1, 1, 0);
    add_gpio(fixture, kFixtureAmplifierMute, "amp-mute",
        0x80000061UL, 1, 0, 0);
    add_gpio(fixture, kFixtureInputMux, "codec-input-data-mux",
        0x80000062UL, 1, 1, 0);
}

static void add_primary_ref(TASFixture *fixture, const char *propertyName,
    unsigned long phandle)
{
    unsigned long cells[1];
    cells[0] = phandle;
    TASFixtureSetCells(fixture, kFixtureSoundBus, propertyName, cells, 1);
}

void TASFixtureSnapper(TASFixture *fixture)
{
    unsigned long cells[1];
    base_fixture(fixture);
    TASFixtureSetString(fixture, kFixtureSoundChip, "compatible",
        "AOAKeylargo");
    TASFixtureSetString(fixture, kFixtureCodec, "compatible", "snapper");
    add_primary_ref(fixture, "platform-tas-codec-ref", 0x30);
    add_primary_ref(fixture, "platform-headphone-mute", 0x40);
    add_primary_ref(fixture, "platform-headphone-detect", 0x41);
    add_primary_ref(fixture, "platform-hw-reset", 0x42);
    add_primary_ref(fixture, "platform-amp-mute", 0x43);
    add_primary_ref(fixture, "platform-codec-input-data-mux", 0x44);
    cells[0] = 0x6a;
    TASFixtureSetCells(fixture, kFixtureCodec, "reg", cells, 1);
    add_gpio(fixture, kFixtureHeadphoneMute, "headphone-mute", 0x70,
        0, 1, 0);
    add_gpio(fixture, kFixtureHeadphoneDetect, "headphone-detect", 0x71,
        0, 0, 48);
    add_gpio(fixture, kFixtureHardwareReset, "audio-hw-reset", 0x72,
        0, 0, 0);
    add_gpio(fixture, kFixtureAmplifierMute, "amp-mute", 0x73,
        0, 1, 0);
    add_gpio(fixture, kFixtureInputMux, "codec-input-data-mux", 0x74,
        0, 0, 0);
}

static int fixture_get(void *context, TASNode nodeId, const char *name,
    const unsigned char **bytes, unsigned long *length)
{
    TASFixture *fixture;
    unsigned long index;
    fixture = (TASFixture *)context;
    if (fixture->nullSuccessProperty != 0 &&
        fixture->nullSuccessNode == nodeId &&
        strcmp(fixture->nullSuccessProperty, name) == 0) {
        *bytes = 0;
        *length = 4;
        return 1;
    }
    for (index = 0; index < fixture->propertyCount; ++index) {
        TASFixtureProperty *entry;
        entry = &fixture->properties[index];
        if (entry->node == nodeId && strcmp(entry->name, name) == 0) {
            *bytes = entry->bytes;
            *length = entry->length;
            return 1;
        }
    }
    return 0;
}

static int fixture_find(void *context, const char *path, TASNode *nodeId)
{
    TASFixture *fixture;
    unsigned long index;
    int after;
    fixture = (TASFixture *)context;
    if (path[0] == '/') {
        for (index = 0; index < fixture->nodeCount; ++index) {
            if (strcmp(fixture->nodes[index].path, path) == 0) {
                *nodeId = fixture->nodes[index].node;
                return 1;
            }
        }
        *nodeId = 0;
        return 0;
    }
    after = *nodeId == 0;
    if (fixture->stuckCursor) {
        *nodeId = kFixtureMacIO;
        return 1;
    }
    for (index = 0; index < fixture->nodeCount; ++index) {
        if (!after) {
            if (fixture->nodes[index].node == *nodeId)
                after = 1;
            continue;
        }
        if (strcmp(path, "*") == 0 ||
            strcmp(fixture->nodes[index].name, path) == 0) {
            *nodeId = fixture->nodes[index].node;
            return 1;
        }
    }
    *nodeId = 0;
    return 0;
}

static unsigned long fixture_find_nodes(void *context, const char *name,
    TASNode *nodes, unsigned long capacity)
{
    TASFixture *fixture;
    unsigned long index;
    unsigned long count;
    fixture = (TASFixture *)context;
    if (fixture->acceleratorOvercount)
        return TAS_FIXTURE_MAX_NODES + 1UL;
    count = 0;
    for (index = 0; index < fixture->nodeCount; ++index) {
        if (strcmp(fixture->nodes[index].name, name) == 0) {
            if (count < capacity)
                nodes[count] = fixture->nodes[index].node;
            ++count;
        }
    }
    return count;
}

static unsigned long fixture_find_property_nodes(void *context,
    const char *name, const char *value, TASNode *nodes,
    unsigned long capacity)
{
    TASFixture *fixture;
    unsigned long index;
    unsigned long count;
    fixture = (TASFixture *)context;
    count = 0;
    for (index = 0; index < fixture->propertyCount; ++index) {
        TASFixtureProperty *entry;
        entry = &fixture->properties[index];
        if (strcmp(entry->name, name) == 0 && entry->length != 0 &&
            entry->bytes[entry->length - 1UL] == 0 &&
            strcmp((const char *)entry->bytes, value) == 0) {
            if (count < capacity)
                nodes[count] = entry->node;
            ++count;
        }
    }
    return count;
}

static unsigned long fixture_resolve(void *context, unsigned long phandle,
    TASNode *nodeId)
{
    TASFixture *fixture;
    unsigned long index;
    unsigned long count;
    fixture = (TASFixture *)context;
    count = 0;
    for (index = 0; index < fixture->nodeCount; ++index) {
        if (fixture->nodes[index].phandle == phandle) {
            *nodeId = fixture->nodes[index].node;
            ++count;
        }
    }
    return count;
}

static int fixture_parent(void *context, TASNode nodeId, TASNode *parent)
{
    TASFixture *fixture;
    unsigned long index;
    fixture = (TASFixture *)context;
    for (index = 0; index < fixture->nodeCount; ++index) {
        if (fixture->nodes[index].node == nodeId) {
            *parent = fixture->nodes[index].parent;
            return 1;
        }
    }
    return 0;
}

TASPropertyReader TASFixtureReader(TASFixture *fixture)
{
    TASPropertyReader reader;
    memset(&reader, 0, sizeof(reader));
    reader.context = fixture;
    reader.getProperty = fixture_get;
    reader.findNode = fixture_find;
    reader.findNodes = fixture_find_nodes;
    reader.findPropertyNodes = fixture_find_property_nodes;
    reader.resolvePhandle = fixture_resolve;
    reader.getParent = fixture_parent;
    return reader;
}

void TASFixtureRemove(TASFixture *fixture, TASNode nodeId, const char *name)
{
    unsigned long index;
    for (index = 0; index < fixture->propertyCount; ++index) {
        if (fixture->properties[index].node == nodeId &&
            strcmp(fixture->properties[index].name, name) == 0) {
            fixture->properties[index] =
                fixture->properties[--fixture->propertyCount];
            return;
        }
    }
}

void TASFixtureSetPath(TASFixture *fixture, TASNode nodeId, const char *path)
{
    unsigned long index;
    for (index = 0; index < fixture->nodeCount; ++index) {
        if (fixture->nodes[index].node == nodeId)
            fixture->nodes[index].path = path;
    }
}

void TASFixtureSetName(TASFixture *fixture, TASNode nodeId, const char *name)
{
    unsigned long index;
    for (index = 0; index < fixture->nodeCount; ++index) {
        if (fixture->nodes[index].node == nodeId)
            fixture->nodes[index].name = name;
    }
}

void TASFixtureReparent(TASFixture *fixture, TASNode nodeId, TASNode parent)
{
    unsigned long index;
    for (index = 0; index < fixture->nodeCount; ++index) {
        if (fixture->nodes[index].node == nodeId)
            fixture->nodes[index].parent = parent;
    }
}

void TASFixtureDuplicatePhandle(TASFixture *fixture, unsigned long phandle)
{
    add_node(fixture, 99, "duplicate", "/duplicate", 0, phandle);
}

void TASFixtureUseOldCodecFallback(TASFixture *fixture)
{
    unsigned long cells[1];
    TASFixtureRemove(fixture, kFixtureSoundBus, "platform-tas-codec-ref");
    TASFixtureSetString(fixture, kFixtureSoundChip, "compatible", "snapper");
    TASFixtureReparent(fixture, kFixtureCodec, kFixtureI2C);
    TASFixtureSetPath(fixture, kFixtureCodec, "/mac-io/i2c/deq");
    cells[0] = 1;
    TASFixtureSetCells(fixture, kFixtureCodec, "AAPL,i2c-port-select",
        cells, 1);
}

void TASFixtureAddSecondI2S(TASFixture *fixture)
{
    unsigned long cells[6];
    add_node(fixture, 20, "i2s", "/mac-io/i2s@2", kFixtureMacIO, 0x50);
    add_node(fixture, 21, "i2s-b", "/mac-io/i2s@2/i2s-b", 20, 0x51);
    add_node(fixture, 22, "sound", "/mac-io/i2s@2/i2s-b/audio", 21,
        0x52);
    TASFixtureSetString(fixture, 22, "compatible", "tumbler");
    TASFixtureSetString(fixture, 22, "model", "FutureMac99,2");
    cells[0] = 44100; cells[1] = 48000;
    TASFixtureSetCells(fixture, 22, "sample-rates", cells, 2);
    cells[0] = 1;
    TASFixtureSetCells(fixture, 21, "reg", cells, 1);
    cells[0] = 0x20000; cells[1] = 0x1000;
    cells[2] = 0x09000; cells[3] = 0x100;
    cells[4] = 0x09100; cells[5] = 0x100;
    TASFixtureSetCells(fixture, 20, "reg", cells, 6);
    cells[0] = 31; cells[1] = 1; cells[2] = 26;
    cells[3] = 2; cells[4] = 27; cells[5] = 3;
    TASFixtureSetCells(fixture, 20, "interrupts", cells, 6);
}

void TASFixtureAddJunkNodes(TASFixture *fixture, unsigned long count)
{
    unsigned long index;
    for (index = 0; index < count; ++index)
        add_node(fixture, 100UL + index, "junk", "/junk", 0,
            200UL + index);
}

void TASFixtureAddForeignReset(TASFixture *fixture)
{
    unsigned long cells[1];
    add_node(fixture, 90, "mac-io", "/foreign/mac-io", 0, 0x90);
    add_node(fixture, 91, "gpio", "/foreign/mac-io/gpio", 90, 0x91);
    TASFixtureReparent(fixture, kFixtureHardwareReset, 91);
    cells[0] = 0x90000000UL;
    TASFixtureSetCells(fixture, 90, "AAPL,address", cells, 1);
}
