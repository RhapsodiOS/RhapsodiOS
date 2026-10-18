#include <string.h>
#include <assert.h>
#include "screamer_fixtures.h"
static ScreamerStatus readreg(void *p,unsigned int reg,unsigned int *v)
{
    ScreamerFixture *f=p;
    if(f->irqContext && reg!=0) ++f->irqViolations;
    if(reg==0x20) *v=(f->now>=f->readyAt?(1U<<22):0)|
        (f->hardware[(f->lastCommand>>1)&7]<<4)|(f->sense&15U);
    else if(reg==0x10) *v=f->holdBusy?0x01000000U:0;
    else *v=f->regs[reg/4];
    return kScreamerOK;
}
static ScreamerStatus writereg(void *p,unsigned int reg,unsigned int v)
{
    ScreamerFixture *f=p;
    if(f->irqContext && reg!=0) ++f->irqViolations;
    if(++f->writeCalls==f->failWrite) return kScreamerIOError;
    f->now+=f->writeDelay;
    f->regs[reg/4]=v;f->lastWriteAt=f->now;
    if(reg==0x10) {
        f->lastCommand=v;++f->commandWrites;
        if((v>>12)!=7) f->hardware[(v>>12)&7]=v&0xfff;
    }
    return kScreamerOK;
}
static unsigned long now(void *p) {return ((ScreamerFixture *)p)->now;}
static void sleepms(void *p,unsigned long ms)
{
    ScreamerFixture *f=p;
    assert(ms<=5000);
    if(f->irqContext) ++f->irqViolations;
    f->now=(f->now+ms)&0xffffffffUL;
}
static void barrier(void *p) {(void)p;}
void FixtureCodecInit(ScreamerFixture *f,ScreamerCodec *c)
{
    f->now=f->readyAt=f->lastWriteAt=0;
    f->lastCommand=f->commandWrites=f->writeCalls=0;
    f->holdBusy=f->failWrite=f->irqContext=f->irqViolations=0;
    memset(f->regs,0,sizeof(f->regs));memset(f->hardware,0,sizeof(f->hardware));
    memset(c,0,sizeof(*c));c->ops.context=f;
    c->ops.readLE32=readreg;c->ops.writeLE32=writereg;
    c->ops.nowMS=now;c->ops.sleepMS=sleepms;c->ops.barrier=barrier;
}
static int property(void *ctx, unsigned int node, const char *name, ScreamerBytes *b)
{
    ScreamerFixture *f = (ScreamerFixture *)ctx;
    unsigned int i;
    for (i = 0; i < f->propertyCount; ++i)
        if (f->properties[i].node == node && !strcmp(f->properties[i].name, name)) {
            b->bytes = f->properties[i].bytes;
            b->length = f->properties[i].length;
            return 1;
        }
    b->bytes = 0; b->length = 0;
    return 0;
}
static unsigned int parent(void *ctx, unsigned int node)
{
    return node < 8 ? ((ScreamerFixture *)ctx)->parents[node] : 0;
}
static void be32(unsigned char *p, unsigned int v)
{
    p[0] = (unsigned char)(v >> 24); p[1] = (unsigned char)(v >> 16);
    p[2] = (unsigned char)(v >> 8); p[3] = (unsigned char)v;
}
void FixtureSetProperty(ScreamerFixture *f, unsigned int n, const char *name,
    const void *data, unsigned int length)
{
    FixtureProperty *p;
    unsigned int i;
    assert(length <= sizeof(f->properties[0].bytes));
    for (i = 0; i < f->propertyCount; ++i)
        if (f->properties[i].node == n && !strcmp(f->properties[i].name, name))
            break;
    assert(i < FIXTURE_PROPERTIES);
    if (i == f->propertyCount) ++f->propertyCount;
    p = &f->properties[i]; p->node = n; p->name = name; p->length = length;
    if (length) memcpy(p->bytes, data, length);
}
void FixtureCell(ScreamerFixture *f, unsigned int n, const char *name, unsigned int v)
{
    unsigned char b[4]; be32(b, v); FixtureSetProperty(f, n, name, b, 4);
}
void FixtureSetRange(ScreamerFixture *f, unsigned int i, unsigned int a, unsigned int len)
{
    assert(i < 3); f->delivered.ranges[i].address = a; f->delivered.ranges[i].length = len;
}
void FixtureSetInterrupt(ScreamerFixture *f, unsigned int i, unsigned int irq)
{
    assert(i < 3); f->delivered.interrupts[i] = irq;
}
void FixtureInit(ScreamerFixture *f)
{
    unsigned char r[24], map[12], irq[12], rates[8];
    static const char objects[] =
        "output model OutputPort port-connection 2 port-type 0x6973706b\0"
        "output model OutputPort port-connection 1 port-type 0x6864706e\0"
        "input model InputPort port-connection 2 port-type 0x6c696e65\0"
        "input model InputPort port-connection 3 port-type 0x63642020\0"
        "detect model InSenseBitsDetect bit-mask 2 bit-match 2 device 2\0";
    memset(f, 0, sizeof(*f));
    f->count = 4; f->parents[2] = 1; f->parents[3] = 2; f->parents[4] = 3;
    f->reader.context = f; f->reader.nodeCount = 4;
    f->reader.getProperty = property; f->reader.getParent = parent;
    f->reader.delivered = &f->delivered;
    f->delivered.rangeCount = f->delivered.interruptCount = 3;
    FixtureSetProperty(f, 1, "model", "PowerMac3,1", 11);
    FixtureCell(f, 1, "#address-cells", 1); FixtureCell(f, 1, "#size-cells", 1);
    FixtureSetProperty(f, 2, "compatible", "keylargo", 9);
    FixtureCell(f, 2, "#address-cells", 1); FixtureCell(f, 2, "#size-cells", 1);
    be32(map, 0); be32(map+4, 0x80000000U); be32(map+8, 0x80000);
    FixtureSetProperty(f, 2, "ranges", map, sizeof(map));
    FixtureSetProperty(f, 3, "name", "davbus", 7);
    be32(r, 0x14000); be32(r+4, 0x100);
    be32(r+8, 0x8800); be32(r+12, 0x100);
    be32(r+16, 0x8900); be32(r+20, 0x100);
    FixtureSetProperty(f, 3, "reg", r, sizeof(r));
    FixtureSetRange(f, 0, 0x80014000U, 0x100);
    FixtureSetRange(f, 1, 0x80008800U, 0x100);
    FixtureSetRange(f, 2, 0x80008900U, 0x100);
    be32(irq,17); be32(irq+4,8); be32(irq+8,9);
    FixtureSetProperty(f,3,"interrupts",irq,sizeof(irq));
    FixtureSetInterrupt(f,0,17); FixtureSetInterrupt(f,1,8); FixtureSetInterrupt(f,2,9);
    FixtureSetProperty(f,4,"compatible","screamer",9);
    be32(rates,44100); be32(rates+4,22050);
    FixtureSetProperty(f,4,"sample-rates",rates,8);
    FixtureSetProperty(f,4,"sound-objects",objects,sizeof(objects)-1);
}
/* Relevant properties transcribed from the PowerMac3,1 4.2.8f1 OF dump
 * cited in SOURCES.md. No serial numbers or unrelated firmware are included. */
void FixtureSawtooth(ScreamerFixture *f)
{
    unsigned char assigned[20],rates[12],map[20],irq[24];
    static const char *records[]={
        "init operation 2 param 00000001 param-size 4" ,
        "feature index 0 model Proj7PowerControl" ,
        "feature index 1 model USBSubwoofer" ,
        "feature index 2 model NotifySSprockets" ,
        "detect bit-mask 2 bit-match 2 device 2 index 0 model InSenseBitsDetect" ,
        "detect bit-mask 4 bit-match 4 device 16 index 1 model InSenseBitsDetect" ,
        "detect bit-mask 1 bit-match 0 device 32 index 2 model InSenseBitsDetect" ,
        "input icon-id -16526 index 0 name-id -20520 port-connection 2 port-type 0x656D6963 zero-gain 0 model ExternalMic" ,
        "input icon-id -16526 index 1 name-id -20528 port-connection 2 port-type 0x73696E6A zero-gain 0 model InputPort" ,
        "input icon-id -20184 index 2 name-id -20540 port-connection 3 port-type 0x6d6f646d zero-gain 0 model InputPort" ,
        "input index 3 model NoInput" ,
        "output device-mask 2 device-match 0 icon-id -16563 index 0 name-id -20525 port-connection 2 port-type 0x6973706B model OutputPort" ,
        "output device-mask 2 device-match 2 icon-id -16563 index 1 name-id -20524 port-connection 1 port-type 0x6864706E model OutputPort" };
    unsigned char objects[1200];
    unsigned int pos=0,i,length;
    for(i=0;i<sizeof(records)/sizeof(records[0]);++i) {
        length=(unsigned int)strlen(records[i])+1;memcpy(objects+pos,records[i],length);pos+=length;
    }
    objects[pos++]=0;
    FixtureInit(f);f->parents[2]=5;f->parents[5]=1;f->reader.nodeCount=5;
    FixtureCell(f,5,"#address-cells",3);FixtureCell(f,5,"#size-cells",2);
    FixtureSetProperty(f,2,"compatible","Keylargo",9);
    be32(assigned,0x82013810U);be32(assigned+4,0);be32(assigned+8,0x80000000U);
    be32(assigned+12,0);be32(assigned+16,0x80000);
    FixtureSetProperty(f,2,"assigned-addresses",assigned,20);
    be32(map,0);memcpy(map+4,assigned,12);be32(map+16,0x80000);
    FixtureSetProperty(f,2,"ranges",map,20);
    FixtureSetProperty(f,4,"model","343S0184",9);
    FixtureSetProperty(f,4,"compatible","screamer\0awacs\0",16);
    be32(rates,2);be32(rates+4,0x56220000U);be32(rates+8,0xac440000U);
    FixtureSetProperty(f,4,"sample-rates",rates,12);
    FixtureSetProperty(f,4,"sound-objects",objects,pos);
    be32(irq,24);be32(irq+4,1);be32(irq+8,9);be32(irq+12,0);be32(irq+16,10);be32(irq+20,0);
    FixtureSetProperty(f,3,"interrupts",irq,24);
    FixtureSetInterrupt(f,0,24);FixtureSetInterrupt(f,1,9);FixtureSetInterrupt(f,2,10);
}
