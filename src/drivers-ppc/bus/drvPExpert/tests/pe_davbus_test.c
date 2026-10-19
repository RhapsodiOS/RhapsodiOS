#include <stdio.h>
#include <string.h>
#include "../powermac/chips/davbus_audio.h"
static unsigned int checks, failures;
#define CHECK(x) do { ++checks;if(!(x)){++failures;fprintf(stderr,"%d: %s\n",__LINE__,#x);} } while(0)
typedef struct { unsigned int value,writes,depth,irq,fail,owner,saved,active,gpio;
    unsigned int trace[16],drop,gpioOffset,gpioWrites,gpioDrop; } Fake;
static unsigned char readgpio(void *p,unsigned int offset) {Fake *f=p;CHECK(offset==(f->gpioOffset?f->gpioOffset:0x6f));CHECK(f->depth==1);return (unsigned char)f->gpio;}
static void writegpio(void *p,unsigned int offset,unsigned char value) {Fake *f=p;CHECK(offset==(f->gpioOffset?f->gpioOffset:0x6f));CHECK(f->depth==1);++f->gpioWrites;if(!f->gpioDrop)f->gpio=value;}
static unsigned int readreg(void *p) { Fake *f=p;CHECK(f->depth==1);return f->value; }
static kern_return_t writereg(void *p,unsigned int v)
{ Fake *f=p;CHECK(f->depth==1);f->trace[f->writes++]=v;
  if(f->fail==f->writes)return KERN_FAILURE;
  if(f->drop!=f->writes)f->value=v;
  return KERN_SUCCESS; }
static void lock(void *p) { Fake *f=p;CHECK(f->depth==0);++f->depth; }
static void unlock(void *p) { Fake *f=p;CHECK(f->depth==1);--f->depth; }
static boolean_t irq(void *p) { return ((Fake *)p)->irq?TRUE:FALSE; }
static void barrier(void *p) { CHECK(((Fake *)p)->depth==1); }
static void cell(unsigned char *p,unsigned int v)
{p[0]=(unsigned char)(v>>24);p[1]=(unsigned char)(v>>16);p[2]=(unsigned char)(v>>8);p[3]=(unsigned char)v;}
static void test_binding_resources(void)
{
    unsigned char reg[24],map[20];unsigned int base;
    CHECK(PEDAVBusFamilyForMacIO(0x106b,0x22)==1);
    CHECK(PEDAVBusFamilyForMacIO(0x106b,0x25)==2);
    CHECK(PEDAVBusFamilyForMacIO(0x106b,0x17)==3);
    CHECK(PEDAVBusFamilyForMacIO(0x106b,0x10)==3);
    CHECK(!PEDAVBusFamilyForMacIO(0x106b,0x3e));
    CHECK(!PEDAVBusFamilyForMacIO(0x106b,0x19));
    CHECK(!PEDAVBusFamilyForMacIO(0x1234,0x22));
    cell(reg,0x14000);cell(reg+4,0x1000);
    cell(reg+8,0x8800);cell(reg+12,0x100);
    cell(reg+16,0x8900);cell(reg+20,0x100);
    CHECK(PEDAVBusValidateRanges(reg,24,0x80800000U,0x80000,&base));
    CHECK(base==0x80814000U);
    CHECK(!PEDAVBusValidateRanges(reg,23,0x80800000U,0x80000,&base));
    CHECK(!PEDAVBusValidateRanges(reg,24,0xffff0000U,0x80000,&base));
    CHECK(!PEDAVBusValidateRanges(reg,24,0x80800000U,0x14000,&base));
    cell(reg+16,0x8800);
    CHECK(!PEDAVBusValidateRanges(reg,24,0x80800000U,0x80000,&base));
    cell(reg+16,0x8901);
    CHECK(!PEDAVBusValidateRanges(reg,24,0x80800000U,0x80000,&base));
    cell(reg+16,0x8900);cell(reg+20,0x80);
    CHECK(!PEDAVBusValidateRanges(reg,24,0x80800000U,0x80000,&base));
    cell(reg+20,0x100);cell(reg,0x30);
    CHECK(!PEDAVBusValidateRanges(reg,24,0x80800000U,0x80000,&base));
    cell(map,0);cell(map+4,0x82008010U);cell(map+8,0);
    cell(map+12,0x80800000U);cell(map+16,0x80000);
    CHECK(PEDAVBusValidateMacIORanges(map,20,0x80800000U,0x80000));
    CHECK(!PEDAVBusValidateMacIORanges(map,19,0x80800000U,0x80000));
    CHECK(!PEDAVBusValidateMacIORanges(map,20,0x80000000U,0x80000));
    CHECK(!PEDAVBusValidateMacIORanges(map,20,0x80800000U,0x100000));
    cell(map,1);CHECK(!PEDAVBusValidateMacIORanges(map,20,0x80800000U,0x80000));
    cell(map,0);cell(map+4,0x81008010U);
    CHECK(!PEDAVBusValidateMacIORanges(map,20,0x80800000U,0x80000));
}
static void test_families(void)
{
    Fake f; PEDAVBusTransport t; PEDAVBusInfo info;
    unsigned int family,step,writes;
    for(family=1;family<=3;++family) {
        memset(&f,0,sizeof(f));memset(&t,0,sizeof(t));
        t.context=&f;t.controllerBase=0x80014000U;t.family=family;
        t.readFCR1=readreg;t.writeFCR1=writereg;t.lock=lock;t.unlock=unlock;
        t.inInterruptContext=irq;t.barrier=barrier;
        t.owner=&f.owner;t.saved=&f.saved;t.active=&f.active;
        f.value=family==3?0xa50010a2U:0xa5000022U;
        PEDAVBusBindTransport(&t);
        CHECK(PEDAVBusGetInfo(t.controllerBase,&info)==KERN_SUCCESS);
        CHECK(info.family==family && !info.capabilities);
        CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusReady)==KERN_SUCCESS);
        writes=family==3?2:4;
        CHECK(f.writes==writes && f.active);
        if(family==3) {
            CHECK(f.trace[0]==0xa50030a2U && f.trace[1]==0xa50020a2U);
            CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusOff)==KERN_SUCCESS);
            CHECK(f.trace[2]==0xa50030a2U && f.trace[3]==0xa50010a2U);
        } else {
            CHECK(f.trace[0]==0xa5000000U && f.trace[1]==0xa5000080U);
            CHECK(f.trace[2]==0xa5000088U && f.trace[3]==0xa50000c8U);
            CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusOff)==KERN_SUCCESS);
            CHECK(f.value==0xa5000022U);
        }
        CHECK(!f.active && !f.owner && !f.depth);
        t.readGPIO=readgpio;t.writeGPIO=writegpio;
        if(family==3) {
            f.gpioOffset=0x37;f.gpio=0xf6;
            CHECK(PEDAVBusGetInfo(t.controllerBase,&info)==KERN_SUCCESS);
            CHECK(info.capabilities==2);
            CHECK(PEDAVBusSetAmplifier(t.controllerBase,1)==KERN_FAILURE);
            CHECK(PEDAVBusSetInputMux(t.controllerBase,0)==KERN_FAILURE);
            CHECK(!f.gpioWrites);
            CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusReady)==KERN_SUCCESS);
            CHECK(PEDAVBusSetInputMux(t.controllerBase,0)==KERN_SUCCESS && f.gpio==0xf4);
            CHECK(PEDAVBusSetInputMux(t.controllerBase,1)==KERN_SUCCESS && f.gpio==0xf5);
            CHECK(PEDAVBusSetInputMux(t.controllerBase,2)==KERN_INVALID_ARGUMENT);
            f.irq=1;
            CHECK(PEDAVBusSetInputMux(t.controllerBase,0)==KERN_INVALID_ARGUMENT);
            f.irq=0;f.gpioDrop=1;
            CHECK(PEDAVBusSetInputMux(t.controllerBase,0)==KERN_FAILURE);
            CHECK(f.gpio==0xf5);f.gpioDrop=0;
            CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusOff)==KERN_SUCCESS);
        } else CHECK(PEDAVBusSetInputMux(t.controllerBase,0)==KERN_FAILURE);
        f.writes=0;f.owner=kPEAudioMuxI2S0;
        CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusReady)==KERN_RESOURCE_SHORTAGE);
        CHECK(!f.writes);f.owner=0;
        for(step=1;step<=writes;++step) {
            memset(&f,0,sizeof(f));f.value=family==3?0x1000U:0x22U;
            f.fail=step;
            CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusReady)==KERN_FAILURE);
            CHECK(f.writes==step && !f.active && f.owner==kPEAudioMuxDAVbus);
            f.fail=0;
            CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusOff)==KERN_SUCCESS);
            CHECK(!f.owner && !f.active);
            memset(&f,0,sizeof(f));f.value=family==3?0x1000U:0x22U;
            f.drop=step;
            CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusReady)==KERN_FAILURE);
            CHECK(!f.active && f.owner==kPEAudioMuxDAVbus && f.writes==step);
        }
        for(step=1;step<=(family==3?2U:3U);++step) {
            memset(&f,0,sizeof(f));f.value=family==3?0x1000U:0x22U;
            CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusReady)==KERN_SUCCESS);
            f.writes=0;f.fail=step;
            CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusOff)==KERN_FAILURE);
            CHECK(f.owner==kPEAudioMuxDAVbus && !f.active);
            f.fail=0;
            CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusReady)==KERN_SUCCESS);
            CHECK(f.active);
            CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusOff)==KERN_SUCCESS);
        }
    }
    t.family=4;f.writes=0;
    CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusReady)==KERN_INVALID_ARGUMENT);
    CHECK(!f.writes);PEDAVBusBindTransport(&t);
    CHECK(PEDAVBusGetInfo(t.controllerBase,&info)==KERN_FAILURE);
}
int main(void)
{
    Fake f; PEDAVBusTransport t; PEDAVBusInfo info;
    memset(&f,0,sizeof(f));memset(&t,0,sizeof(t));
    t.context=&f;t.controllerBase=0x80014000U;t.family=kPEDAVBusKeyLargo;
    t.readFCR1=readreg;t.writeFCR1=writereg;t.lock=lock;t.unlock=unlock;
    t.inInterruptContext=irq;t.barrier=barrier;
    t.owner=&f.owner;t.saved=&f.saved;t.active=&f.active;
    t.readGPIO=readgpio;t.writeGPIO=writegpio;
    PEDAVBusBindTransport(&t);
    CHECK(PEDAVBusGetInfo(0x80014000U,&info)==KERN_SUCCESS);
    CHECK(info.family==kPEDAVBusKeyLargo);
    CHECK(PEDAVBusGetInfo(0x90000000U,&info)==KERN_INVALID_ARGUMENT);
    f.value=0xa5000002U;
    CHECK(PEDAVBusSetState(0x80014000U,kPEDAVBusReady)==KERN_SUCCESS);
    CHECK((f.value&0xffffff05U)==0xa5000000U);
    CHECK((f.value&0xc8U)==0xc8U && f.active);
    CHECK(f.owner==kPEAudioMuxDAVbus);
    f.gpio=0xa0;
    CHECK(PEDAVBusSetAmplifier(0x80014000U,1)==KERN_SUCCESS && f.gpio==0xa5);
    CHECK(PEDAVBusSetAmplifier(0x80014000U,0)==KERN_SUCCESS && f.gpio==0xa4);
    f.irq=1;CHECK(PEDAVBusSetAmplifier(0x80014000U,1)==KERN_INVALID_ARGUMENT);f.irq=0;
    CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusReady)==KERN_SUCCESS);
    CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusOff)==KERN_SUCCESS);
    CHECK(f.value==0xa5000002U && f.owner==kPEAudioMuxNone);
    f.owner=kPEAudioMuxI2S0;f.writes=0;
    CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusReady)==KERN_RESOURCE_SHORTAGE);
    CHECK(f.writes==0 && f.owner==kPEAudioMuxI2S0);
    f.owner=0;f.value|=0x1000U;
    CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusReady)==KERN_RESOURCE_SHORTAGE);
    CHECK(f.writes==0);
    f.value=0;f.irq=1;
    CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusReady)==KERN_INVALID_ARGUMENT);
    f.irq=0;f.fail=1;
    CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusReady)==KERN_FAILURE);
    CHECK(f.owner==kPEAudioMuxDAVbus && !f.active);
    f.fail=0;
    CHECK(PEDAVBusSetStateCore(&t,kPEDAVBusOff)==KERN_SUCCESS);
    CHECK(!f.owner && !f.depth);
    PEDAVBusBindTransport(0);
    CHECK(PEDAVBusSetState(0x80014000U,kPEDAVBusReady)==KERN_FAILURE);
    {
        unsigned char legacy[12]={0,0,0,17,0,0,0,8,0,0,0,9};
        unsigned int irq[3];
        CHECK(PEDAVBusParseInterrupts(legacy,12,irq));
        CHECK((irq[0]^0x18U)==9 && (irq[1]^0x18U)==16 && (irq[2]^0x18U)==17);
    }
    {
        unsigned char raw[24]={0,0,0,24,0,0,0,1,0,0,0,9,0,0,0,0,0,0,0,10,0,0,0,0};
        unsigned int irq[3];
        CHECK(PEDAVBusParseInterrupts(raw,24,irq));
        CHECK(irq[0]==24 && irq[1]==9 && irq[2]==10);
        raw[7]=2;CHECK(!PEDAVBusParseInterrupts(raw,24,irq));raw[7]=1;
        raw[19]=9;CHECK(!PEDAVBusParseInterrupts(raw,24,irq));
        CHECK(!PEDAVBusParseInterrupts(raw,20,irq));
    }
    test_families();
    test_binding_resources();
    printf("davbus: %u checks, %u failures\n",checks,failures);
    return failures!=0;
}
