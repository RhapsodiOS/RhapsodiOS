#ifndef TAS_FIXTURES_H
#define TAS_FIXTURES_H

#include "TASCore.h"

#define TAS_FIXTURE_MAX_NODES 16
#define TAS_FIXTURE_MAX_PROPERTIES 64
#define TAS_FIXTURE_MAX_BYTES 96

typedef struct {
    TASNode node;
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
void TASFixtureDuplicatePhandle(TASFixture *fixture, unsigned long phandle);

#endif
