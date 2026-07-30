#ifndef TAS_FIXTURES_H
#define TAS_FIXTURES_H

#include "TASCore.h"

#define TAS_FIXTURE_MAX_NODES 32
#define TAS_FIXTURE_MAX_PROPERTIES 96
#define TAS_FIXTURE_MAX_BYTES 96

enum {
    kFixtureSoundBus = 1,
    kFixtureSoundChip = 2,
    kFixtureI2CBus = 3,
    kFixtureCodec = 4,
    kFixtureHeadphoneMute = 5,
    kFixtureHeadphoneDetect = 6,
    kFixtureI2S = 7,
    kFixtureMacIO = 8,
    kFixtureI2C = 9,
    kFixtureGPIO = 10,
    kFixtureHardwareReset = 11,
    kFixtureAmplifierMute = 12,
    kFixtureInputMux = 13,
    kFixtureLineOutMute = 14,
    kFixtureLineOutDetect = 15
};

typedef struct {
    TASNode node;
    const char *name;
    const char *path;
    TASNode parent;
    unsigned long phandle;
} TASFixtureNode;

typedef struct {
    TASNode node;
    const char *name;
    unsigned char bytes[TAS_FIXTURE_MAX_BYTES];
    unsigned long length;
} TASFixtureProperty;

typedef struct {
    TASFixtureNode nodes[TAS_FIXTURE_MAX_NODES];
    unsigned long nodeCount;
    TASFixtureProperty properties[TAS_FIXTURE_MAX_PROPERTIES];
    unsigned long propertyCount;
} TASFixture;

void TASFixtureTumbler(TASFixture *fixture);
void TASFixtureSnapper(TASFixture *fixture);
TASPropertyReader TASFixtureReader(TASFixture *fixture);
void TASFixtureRemove(TASFixture *fixture, TASNode node, const char *name);
void TASFixtureSetCells(TASFixture *fixture, TASNode node, const char *name,
    const unsigned long *cells, unsigned long count);
void TASFixtureSetString(TASFixture *fixture, TASNode node, const char *name,
    const char *value);
void TASFixtureSetEmpty(TASFixture *fixture, TASNode node, const char *name);
void TASFixtureSetPath(TASFixture *fixture, TASNode node, const char *path);
void TASFixtureSetName(TASFixture *fixture, TASNode node, const char *name);
void TASFixtureReparent(TASFixture *fixture, TASNode node, TASNode parent);
void TASFixtureDuplicatePhandle(TASFixture *fixture, unsigned long phandle);
void TASFixtureUseOldCodecFallback(TASFixture *fixture);
void TASFixtureAddSecondI2S(TASFixture *fixture);

#endif
