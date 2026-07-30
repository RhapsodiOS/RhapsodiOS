#include "tas_fixtures.h"

#include <string.h>

#define NODE_I2S 1UL
#define NODE_SOUND 2UL
#define NODE_I2C 3UL
#define NODE_CODEC 4UL
#define NODE_HP_MUTE 5UL
#define NODE_HP_DETECT 6UL
#define NODE_I2S_CONTROLLER 7UL

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
    TASFixtureProperty *property;
    unsigned long index;
    property = property_slot(fixture, node, name);
    property->length = count * 4UL;
    for (index = 0; index < count; ++index)
        put_be32(property->bytes + index * 4UL, cells[index]);
}

void TASFixtureSetString(TASFixture *fixture, TASNode node, const char *name,
    const char *value)
{
    TASFixtureProperty *property;
    unsigned long length;
    property = property_slot(fixture, node, name);
    length = (unsigned long)strlen(value) + 1UL;
    memcpy(property->bytes, value, (size_t)length);
    property->length = length;
}

void TASFixtureSetEmpty(TASFixture *fixture, TASNode node, const char *name)
{
    TASFixtureProperty *property;
    property = property_slot(fixture, node, name);
    property->length = 0;
}

static void node(TASFixture *fixture, TASNode id, const char *path,
    TASNode parent, unsigned long phandle)
{
    TASFixtureNode *entry;
    entry = &fixture->nodes[fixture->nodeCount++];
    entry->node = id;
    entry->path = path;
    entry->parent = parent;
    entry->phandle = phandle;
}

static void base_fixture(TASFixture *fixture, const char *compatible,
    unsigned long codecAddress, unsigned long port)
{
    unsigned long cells[8];
    memset(fixture, 0, sizeof(*fixture));
    node(fixture, NODE_I2S_CONTROLLER, "/mac-io/i2s", 0, 0x0f);
    node(fixture, NODE_I2S, "/mac-io/i2s/i2s-a", NODE_I2S_CONTROLLER, 0x10);
    node(fixture, NODE_SOUND, "/mac-io/i2s/i2s-a/sound", NODE_I2S, 0x11);
    node(fixture, NODE_I2C, "/mac-io/i2c/i2c-bus@1", 0, 0x20);
    node(fixture, NODE_CODEC, "/mac-io/i2c/i2c-bus@1/deq", NODE_I2C, 0x30);
    node(fixture, NODE_HP_MUTE, "/mac-io/gpio/headphone-mute", 0, 0x40);
    node(fixture, NODE_HP_DETECT, "/mac-io/gpio/headphone-detect", 0, 0x41);
    TASFixtureSetString(fixture, NODE_SOUND, "compatible", compatible);
    TASFixtureSetString(fixture, NODE_SOUND, "model", "PowerMac4,2");
    cells[0] = 0x30;
    TASFixtureSetCells(fixture, NODE_SOUND, "platform-tas-codec-ref", cells, 1);
    cells[0] = 0x10000; cells[1] = 0x1000;
    cells[2] = 0x08000; cells[3] = 0x0100;
    cells[4] = 0x08100; cells[5] = 0x0100;
    TASFixtureSetCells(fixture, NODE_I2S_CONTROLLER, "reg", cells, 6);
    cells[0] = 24; cells[1] = 25;
    TASFixtureSetCells(fixture, NODE_I2S_CONTROLLER, "interrupts", cells, 2);
    cells[0] = codecAddress;
    TASFixtureSetCells(fixture, NODE_CODEC, "reg", cells, 1);
    cells[0] = port;
    TASFixtureSetCells(fixture, NODE_I2C, "reg", cells, 1);
    cells[0] = 0x40;
    TASFixtureSetCells(fixture, NODE_SOUND, "platform-headphone-mute", cells, 1);
    cells[0] = 0x41;
    TASFixtureSetCells(fixture, NODE_SOUND, "platform-headphone-detect", cells, 1);
    cells[0] = 0x50; cells[1] = 0x04;
    TASFixtureSetCells(fixture, NODE_HP_MUTE, "reg", cells, 2);
    cells[0] = 0;
    TASFixtureSetCells(fixture, NODE_HP_MUTE, "audio-gpio-active-state", cells, 1);
    cells[0] = 0x54; cells[1] = 0x08;
    TASFixtureSetCells(fixture, NODE_HP_DETECT, "reg", cells, 2);
    cells[0] = 1;
    TASFixtureSetCells(fixture, NODE_HP_DETECT, "audio-gpio-active-state", cells, 1);
    cells[0] = 47;
    TASFixtureSetCells(fixture, NODE_HP_DETECT, "AAPL,interrupts", cells, 1);
    cells[0] = 44100; cells[1] = 48000;
    TASFixtureSetCells(fixture, NODE_SOUND, "sample-rates", cells, 2);
    cells[0] = 0x37;
    TASFixtureSetCells(fixture, NODE_SOUND, "layout-id", cells, 1);
}

void TASFixtureTumbler(TASFixture *fixture)
{
    base_fixture(fixture, "tumbler", 0x68, 1);
}

void TASFixtureSnapper(TASFixture *fixture)
{
    base_fixture(fixture, "snapper", 0x35, 2);
}

static int fixture_get(void *context, TASNode nodeId, const char *name,
    const unsigned char **bytes, unsigned long *length)
{
    TASFixture *fixture;
    unsigned long index;
    fixture = (TASFixture *)context;
    for (index = 0; index < fixture->propertyCount; ++index) {
        TASFixtureProperty *property;
        property = &fixture->properties[index];
        if (property->node == nodeId && strcmp(property->name, name) == 0) {
            *bytes = property->bytes;
            *length = property->length;
            return 1;
        }
    }
    return 0;
}

static int fixture_find(void *context, const char *path, TASNode *nodeId)
{
    TASFixture *fixture;
    unsigned long index;
    fixture = (TASFixture *)context;
    for (index = 0; index < fixture->nodeCount; ++index) {
        if (strcmp(fixture->nodes[index].path, path) == 0) {
            *nodeId = fixture->nodes[index].node;
            return 1;
        }
    }
    return 0;
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
    reader.context = fixture;
    reader.getProperty = fixture_get;
    reader.findNode = fixture_find;
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

void TASFixtureDuplicatePhandle(TASFixture *fixture, unsigned long phandle)
{
    node(fixture, 99, "/duplicate", 0, phandle);
}
