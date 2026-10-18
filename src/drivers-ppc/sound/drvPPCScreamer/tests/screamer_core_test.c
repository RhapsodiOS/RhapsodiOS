#include <stdio.h>
#include <string.h>
#include "screamer_fixtures.h"
static unsigned int checks, failures;
#define CHECK(x) do { ++checks; if (!(x)) { ++failures; \
    fprintf(stderr,"%s:%d: %s\n",__FILE__,__LINE__,#x); } } while (0)
int main(void)
{
    ScreamerFixture f; ScreamerMachineConfig c, before;
    unsigned int code, i;
    FixtureInit(&f);
    CHECK(ScreamerDiscover(&f.reader,3,&c) == kScreamerOK);
    CHECK(c.ranges[0].address == 0x80014000U);
    CHECK(c.ranges[1].address == 0x80008800U);
    CHECK(c.profile.headphoneMask == 4 && c.profile.headphoneMatch == 4);
    CHECK(c.profile.inputBits[kScreamerInputLine] == 0x400U);
    CHECK(c.profile.inputBits[kScreamerInputCD] == 0x200U);
    CHECK(c.profile.speakerPort == 2 && c.profile.headphonePort == 1);
    CHECK(ScreamerRateCode(&c,44100,&code)==kScreamerOK && code==0);
    CHECK(ScreamerRateCode(&c,22050,&code)==kScreamerOK && code==2);
    CHECK(ScreamerRateCode(&c,48000,&code)==kScreamerUnsupported);
    before=c;
    FixtureSetRange(&f,1,0x80008900U,0x100);
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerInvalid);
    CHECK(memcmp(&c,&before,sizeof(c))==0);
    FixtureInit(&f); FixtureCell(&f,4,"sample-rates",22050);
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerUnresolved);
    FixtureInit(&f); FixtureSetProperty(&f,4,"sample-rates","abc",3);
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerInvalid);
    FixtureInit(&f); FixtureSetProperty(&f,4,"sound-objects","bogus",5);
    CHECK(ScreamerDiscover(&f.reader,3,&c)!=kScreamerOK);
    FixtureInit(&f); FixtureSetInterrupt(&f,1,9);
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerInvalid);
    FixtureInit(&f); FixtureSetProperty(&f,4,"model","burgundy",9);
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerUnsupported);
    FixtureInit(&f); f.reader.nodeCount=5; f.parents[5]=3;
    FixtureSetProperty(&f,5,"compatible","screamer",9);
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerUnresolved);
    FixtureInit(&f); f.parents[2]=3;
    CHECK(ScreamerDiscover(&f.reader,3,&c)!=kScreamerOK);
    FixtureInit(&f);
    FixtureCell(&f,2,"AAPL,address",0x80000000U);
    FixtureSetProperty(&f,2,"ranges",0,0);
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerOK);
    CHECK(c.ranges[2].address==0x80008900U);
    FixtureCell(&f,2,"AAPL,address",0xfffff000U);
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerInvalid);
    FixtureInit(&f); FixtureCell(&f,2,"AAPL,address",0x90000000U);
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerInvalid);
    CHECK(ScreamerQuantize(0,32768)==0);
    CHECK(ScreamerQuantize(32768,32768)==15);
    CHECK(ScreamerQuantize(32769,32768)==15);
    CHECK(ScreamerQuantize(16384,32768)==8);
    CHECK(ScreamerQuantize(0xffffffffU,0xffffffffU)==15);
    for(i=0;i<16;++i) CHECK(ScreamerQuantize(i,15)==i);
    FixtureSawtooth(&f);
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerOK);
    CHECK(c.rateCount==2 && c.rates[0]==22050 && c.rates[1]==44100);
    CHECK(c.profile.powerKind==7 && c.profile.initOutput==1);
    CHECK(c.profile.speakerPort==2 && c.profile.headphonePort==1 && c.profile.headphoneMask==4);
    CHECK(c.profile.inputBits[kScreamerInputMic]==0x400U && c.profile.inputBits[kScreamerInputLine]==0x400U);
    FixtureCell(&f,2,"AAPL,address",0x90000000U);
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerInvalid);
    printf("core: %u checks, %u failures\n",checks,failures);
    return failures!=0;
}
