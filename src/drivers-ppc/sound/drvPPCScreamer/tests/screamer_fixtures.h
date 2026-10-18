#ifndef SCREAMER_FIXTURES_H
#define SCREAMER_FIXTURES_H
#include "../PPCScreamer.drvproj/PPCScreamer.lksproj/ScreamerCore.h"
#include "../PPCScreamer.drvproj/PPCScreamer.lksproj/ScreamerCodec.h"
#define FIXTURE_PROPERTIES 64
typedef struct {
    unsigned int node, length;
    const char *name;
    unsigned char bytes[2048];
} FixtureProperty;
typedef struct {
    FixtureProperty properties[FIXTURE_PROPERTIES];
    unsigned int propertyCount, parents[8], count;
    ScreamerDeliveredResources delivered;
    ScreamerPropertyReader reader;
    unsigned long now,readyAt,lastWriteAt;
    unsigned int regs[24],hardware[8],lastCommand,commandWrites,writeCalls;
    unsigned int holdBusy,failWrite,irqContext,irqViolations,sense,writeDelay;
} ScreamerFixture;
void FixtureInit(ScreamerFixture *);
void FixtureSawtooth(ScreamerFixture *);
void FixtureSetProperty(ScreamerFixture *, unsigned int, const char *, const void *, unsigned int);
void FixtureCell(ScreamerFixture *, unsigned int, const char *, unsigned int);
void FixtureSetRange(ScreamerFixture *, unsigned int, unsigned int, unsigned int);
void FixtureSetInterrupt(ScreamerFixture *, unsigned int, unsigned int);
void FixtureCodecInit(ScreamerFixture *, ScreamerCodec *);
#endif
