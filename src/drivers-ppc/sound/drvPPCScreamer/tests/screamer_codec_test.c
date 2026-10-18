#include <stdio.h>
#include <string.h>
#include "screamer_fixtures.h"
#include "../PPCScreamer.drvproj/PPCScreamer.lksproj/ScreamerCodec.h"
static unsigned int checks, failures;
#define CHECK(x) do {++checks;if(!(x)){++failures;fprintf(stderr,"%d: %s\n",__LINE__,#x);}}while(0)
int main(void)
{
    ScreamerFixture f; ScreamerCodec c; ScreamerMachineConfig config;
    unsigned int value,old;
    FixtureInit(&f);FixtureCodecInit(&f,&c);
    f.readyAt=10;
    CHECK(ScreamerCodecWrite(&c,4,0x3cf,1000)==kScreamerOK);
    CHECK(f.lastCommand==0x43cf && f.lastWriteAt>=10 && c.shadow[4]==0x3cf);
    old=c.shadow[4]; f.holdBusy=1;
    CHECK(ScreamerCodecWrite(&c,4,0,1010)==kScreamerTimeout);
    CHECK(f.now==1010 && c.shadow[4]==old);
    CHECK(!(c.validMask&(1U<<4)));
    FixtureCodecInit(&f,&c);f.hardware[4]=0x123;
    CHECK(ScreamerCodecRead(&c,4,&value,1000)==kScreamerOK);
    CHECK(value==0x123 && f.commandWrites==2 && f.lastCommand==0x7009);
    FixtureCodecInit(&f,&c);f.failWrite=1;
    CHECK(ScreamerCodecWrite(&c,4,1,1000)==kScreamerIOError);
    CHECK(!(c.validMask&(1U<<4)));
    CHECK(ScreamerCodecWrite(&c,3,1,1000)==kScreamerInvalid);
    CHECK(ScreamerCodecWrite(&c,8,1,1000)==kScreamerInvalid);
    CHECK(ScreamerCodecWrite(&c,4,0x1000,1000)==kScreamerInvalid);
    FixtureCodecInit(&f,&c);
    CHECK(ScreamerDiscover(&f.reader,3,&config)==kScreamerOK);
    CHECK(ScreamerCodecInitialize(&c,&config,5000)==kScreamerOK);
    CHECK(f.now>=752 && f.now<5000);
    CHECK((c.shadow[1]&0x280)==0x280 && !(c.shadow[1]&0x40));
    CHECK(f.regs[0x40/4]==0);
    CHECK(f.regs[0]==0x11);
    FixtureCodecInit(&f,&c);
    CHECK(ScreamerCodecInitialize(&c,&config,750)==kScreamerTimeout);
    CHECK(f.now<=750 && !(c.shadow[1]&4));
    FixtureCodecInit(&f,&c);f.now=0xfffffff0UL;
    CHECK(ScreamerCodecWrite(&c,4,1,0x80000000UL)==kScreamerTimeout);
    CHECK(f.commandWrites==0);
    f.now=0;f.readyAt=1000;
    CHECK(ScreamerCodecWrite(&c,4,1,1000)==kScreamerTimeout);
    CHECK(f.commandWrites==0);
    CHECK(f.irqViolations==0);
    printf("codec: %u checks, %u failures\n",checks,failures);
    return failures!=0;
}
