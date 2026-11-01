#include <stdio.h>
#include <string.h>
#include "screamer_fixtures.h"

static unsigned int checks,failures;
#define CHECK(x) do {++checks;if(!(x)){++failures;fprintf(stderr,"%d: %s\n",__LINE__,#x);}} while(0)
/* Source-backed object combinations, not captured machine firmware. */
static const char common[]=
    "output model OutputPort port-connection 2 port-type 0x6973706b\0"
    "output model OutputPort port-connection 1 port-type 0x6864706e\0"
    "input model InputPort port-connection 1 port-type 0x696d6963\0"
    "input model InputPort port-connection 2 port-type 0x73696e6a\0"
    "detect model InSenseBitsDetect bit-mask 1 bit-match 1 device 2\0";
static void setup(ScreamerFixture *f,const char *machine,const char *power,const char *bus)
{
    unsigned char objects[1200];unsigned int n=(unsigned int)sizeof(common)-1;
    FixtureInit(f);memcpy(objects,common,n);memcpy(objects+n,power,strlen(power)+1);
    FixtureSetProperty(f,1,"model",machine,(unsigned int)strlen(machine)+1);
    FixtureSetProperty(f,2,"compatible",bus,(unsigned int)strlen(bus)+1);
    FixtureSetProperty(f,4,"sound-objects",objects,n+(unsigned int)strlen(power)+1);
}
int main(void)
{
    ScreamerFixture f;ScreamerMachineConfig c;unsigned int i;
    static const char * const towers[]={"PowerMac3,2","PowerMac3,3"};
    setup(&f,"PowerBook3,1","feature model Proj10PowerControl","Keylargo");
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerOK);
    CHECK(c.profile.powerKind==10 && c.profile.headphoneMask==8);
    setup(&f,"PowerBook1,1","feature model Proj6PowerControl","paddington");
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerOK);
    CHECK(c.profile.powerKind==6);
    setup(&f,"PowerMac4,1","feature model Proj7PowerControl","pangea");
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerOK);
    setup(&f,"PowerBook3,1","feature model Proj10PowerControl","intrepid");
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerUnsupported);
    /* Real Pismo object property, with the same root/bus/resources as the dump. */
    FixturePismo(&f);
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerOK);
    CHECK(c.profile.powerKind==10 && c.profile.initOutput==0);
    CHECK(c.profile.inputBits[kScreamerInputMic]==0x800U);
    CHECK(c.profile.inputBits[kScreamerInputLine]==0x400U);
    CHECK(c.profile.micMuxMask==0x800U && c.profile.micMuxValue==0);
    CHECK(c.profile.monoMic==1);
    FixtureIMac(&f,"PowerMac2,1",0);
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerOK);
    CHECK(c.profile.headphoneMask==7 && c.profile.frontMask==6);
    CHECK(c.profile.speakerKind==5 && c.profile.speakerParam==0);
    CHECK(c.profile.phaseInversion==1 && c.profile.monoMic==1);
    CHECK(c.profile.inputBits[kScreamerInputMic]==0x800U);
    FixtureLombard(&f);
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerOK);
    CHECK(c.profile.source==1 && c.profile.powerKind==6 && c.profile.muxKind==9);
    CHECK(c.profile.headphoneMask==8 && c.profile.headphoneMatch==8);
    CHECK(c.profile.inputBits[kScreamerInputMic]==0x800U && c.profile.inputBits[kScreamerInputCD]==0x200U);
    FixtureCell(&f,4,"device-id",3);
    CHECK(ScreamerDiscover(&f.reader,3,&c)!=kScreamerOK);
    FixtureLombard(&f);FixtureSetProperty(&f,4,"sound-objects","bogus",6);
    CHECK(ScreamerDiscover(&f.reader,3,&c)!=kScreamerOK);
    for(i=0;i<2;++i) {
        FixtureSawtooth(&f);FixtureSetProperty(&f,1,"model",towers[i],12);
        CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerOK && c.profile.powerKind==7);
    }
    FixtureIMac(&f,"PowerMac2,2",1);
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerOK && c.profile.speakerParam==1);
    FixtureIMac(&f,"PowerMac4,1",1);FixtureSetProperty(&f,2,"compatible","pangea",7);
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerOK && c.platformFamily==2);
    FixtureIMac(&f,"PowerMac4,1",0);
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerInvalid);
    FixturePismo(&f);FixtureSetProperty(&f,2,"compatible","heathrow",9);
    CHECK(ScreamerDiscover(&f.reader,3,&c)==kScreamerUnsupported);
    FixtureLombard(&f);FixtureCell(&f,4,"sub-frame",1);
    CHECK(ScreamerDiscover(&f.reader,3,&c)!=kScreamerOK);
    FixtureLombard(&f);FixtureSetProperty(&f,4,"model","awacs",6);
    CHECK(ScreamerDiscover(&f.reader,3,&c)!=kScreamerOK);
    printf("profiles: %u checks, %u failures\n",checks,failures);
    return failures!=0;
}
