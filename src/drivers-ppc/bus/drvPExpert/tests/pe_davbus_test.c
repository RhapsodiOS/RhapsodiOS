#include <stdio.h>
#include <string.h>
#include "../powermac/chips/davbus_audio.h"
static unsigned int checks, failures;
#define CHECK(x) do { ++checks;if(!(x)){++failures;fprintf(stderr,"%d: %s\n",__LINE__,#x);} } while(0)
typedef struct { unsigned int value,writes,depth,irq,fail,owner,saved,active,gpio; } Fake;
static unsigned char readgpio(void *p,unsigned int offset) {CHECK(offset==0x6f);CHECK(((Fake *)p)->depth==1);return (unsigned char)((Fake *)p)->gpio;}
static void writegpio(void *p,unsigned int offset,unsigned char value) {CHECK(offset==0x6f);CHECK(((Fake *)p)->depth==1);((Fake *)p)->gpio=value;}
static unsigned int readreg(void *p) { Fake *f=p;CHECK(f->depth==1);return f->value; }
static kern_return_t writereg(void *p,unsigned int v)
{ Fake *f=p;CHECK(f->depth==1);++f->writes;if(f->fail)return KERN_FAILURE;f->value=v;return KERN_SUCCESS; }
static void lock(void *p) { Fake *f=p;CHECK(f->depth==0);++f->depth; }
static void unlock(void *p) { Fake *f=p;CHECK(f->depth==1);--f->depth; }
static boolean_t irq(void *p) { return ((Fake *)p)->irq?TRUE:FALSE; }
static void barrier(void *p) { CHECK(((Fake *)p)->depth==1); }
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
        unsigned char raw[24]={0,0,0,24,0,0,0,1,0,0,0,9,0,0,0,0,0,0,0,10,0,0,0,0};
        unsigned int irq[3];
        CHECK(PEDAVBusParseInterrupts(raw,24,irq));
        CHECK(irq[0]==24 && irq[1]==9 && irq[2]==10);
        raw[7]=2;CHECK(!PEDAVBusParseInterrupts(raw,24,irq));raw[7]=1;
        raw[19]=9;CHECK(!PEDAVBusParseInterrupts(raw,24,irq));
        CHECK(!PEDAVBusParseInterrupts(raw,20,irq));
    }
    printf("davbus: %u checks, %u failures\n",checks,failures);
    return failures!=0;
}
