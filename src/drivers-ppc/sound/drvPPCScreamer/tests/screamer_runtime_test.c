#include <stdio.h>
#include <string.h>
#include <stddef.h>
#include "screamer_fixtures.h"
#include "../PPCScreamer.drvproj/PPCScreamer.lksproj/ScreamerRuntime.h"
static unsigned int checks,failures;
#define CHECK(x) do{++checks;if(!(x)){++failures;fprintf(stderr,"%d: %s\n",__LINE__,#x);}}while(0)
typedef struct {
    unsigned char audio[8192],desc[4112],scratch[4112];
    unsigned long now,control,pointer;
    unsigned int holdStop,cacheError,unmappable,published,starts;
} DMAFake;
static DMAFake dma[2];
static ScreamerFixture fixture;
static PPCDBDMAStatus translate(void *p,const void *v,unsigned long *phys,unsigned long *bytes)
{
    DMAFake *f=p;
    size_t off=(const unsigned char *)v-f->audio;
    if(f->unmappable || off>=sizeof(f->audio)) return kPPCDBDMAUnmappable;
    *phys=(off<1024?0x200000UL:0x500000UL)+(unsigned long)off;
    *bytes=off<1024?1024UL-(unsigned long)off:8192UL-(unsigned long)off;
    return kPPCDBDMAOK;
}
static unsigned long readreg(void *p,unsigned long reg)
{
    DMAFake *f=p;
    if(reg==kPPCDBDMARegStatus)
        return f->holdStop?kPPCDBDMAActive:((f->control&kPPCDBDMARun)?kPPCDBDMAActive:0);
    return 0;
}
static void writereg(void *p,unsigned long reg,unsigned long value)
{
    DMAFake *f=p;
    if(reg==kPPCDBDMARegCommandPtr) f->pointer=value;
    if(reg==kPPCDBDMARegControl) {
        f->control=(f->control&~(value>>16))|(value&(value>>16));
        if((value&kPPCDBDMARun) && (value>>16)&kPPCDBDMARun) ++f->starts;
    }
}
static unsigned long now(void *p) {return ++((DMAFake *)p)->now;}
static PPCDBDMAStatus publish(void *p,void *v,unsigned long n)
{
    DMAFake *f=p;(void)v;(void)n;
    ++f->published;return f->cacheError?kPPCDBDMACoherency:kPPCDBDMAOK;
}
static PPCDBDMAStatus barrier(void *p) {(void)p;return kPPCDBDMAOK;}
static ScreamerStatus platform(void *p,int ready) {(void)p;(void)ready;return kScreamerOK;}
static void setup(ScreamerRuntime *r,ScreamerMachineConfig *c,ScreamerRuntimeOps *ops)
{
    ScreamerCodec codec;
    unsigned int i;
    FixtureInit(&fixture);FixtureCodecInit(&fixture,&codec);
    CHECK(ScreamerDiscover(&fixture.reader,3,c)==kScreamerOK);
    memset(ops,0,sizeof(*ops));ops->codec=codec.ops;ops->setPlatform=platform;
    for(i=0;i<2;++i) {
        memset(&dma[i],0,sizeof(dma[i]));
        ops->storage[i].logical=(void *)(((size_t)dma[i].desc+15)&~(size_t)15);
        ops->storage[i].scratch=(void *)(((size_t)dma[i].scratch+15)&~(size_t)15);
        ops->storage[i].physical=0x100000UL+i*4096UL;
        ops->storage[i].bytes=ops->storage[i].scratchBytes=4096;
        ops->dma[i].context=ops->dma[i].registerContext=ops->dma[i].coherencyContext=&dma[i];
        ops->dma[i].translate=translate;ops->dma[i].readRegister=readreg;
        ops->dma[i].writeRegister=writereg;ops->dma[i].now=now;
        ops->dma[i].publish=publish;ops->dma[i].invalidate=publish;ops->dma[i].barrier=barrier;
    }
    CHECK(ScreamerRuntimeInitialize(r,c,ops,5000)==kScreamerOK);
}
static void complete(PPCDBDMARing *r,unsigned long index,unsigned int residual,unsigned int status)
{
    unsigned long v=((unsigned long)status<<16)|residual;
    unsigned char *p=r->descriptors+index*16+12;
    p[0]=(unsigned char)v;p[1]=(unsigned char)(v>>8);p[2]=(unsigned char)(v>>16);p[3]=(unsigned char)(v>>24);
}
int main(void)
{
    ScreamerRuntime r;ScreamerMachineConfig c;ScreamerRuntimeOps ops;
    unsigned int periods,i,before;
    setup(&r,&c,&ops);
    CHECK(ScreamerStart(&r,kScreamerStreamOutput,dma[1].audio,8192,4096,44100,5000)==kScreamerOK);
    CHECK(dma[1].published>0 && dma[1].starts==1);
    CHECK(r.rings[1].dataDescriptorCount==3);
    before=fixture.commandWrites;
    CHECK(ScreamerStart(&r,kScreamerStreamInput,dma[0].audio,8192,4096,22050,5000)==kScreamerBusy);
    CHECK(fixture.commandWrites==before && dma[1].starts==1);
    CHECK(ScreamerStart(&r,kScreamerStreamInput,dma[0].audio,8192,4096,44100,5000)==kScreamerOK);
    complete(&r.rings[1],0,0,kPPCDBDMAActive);
    CHECK(ScreamerCaptureCompletions(&r,kScreamerStreamOutput,&periods)==kScreamerOK && periods==0);
    complete(&r.rings[1],1,0,kPPCDBDMAActive);
    CHECK(ScreamerCaptureCompletions(&r,kScreamerStreamOutput,&periods)==kScreamerOK && periods==1);
    complete(&r.rings[1],2,0,kPPCDBDMAActive);
    CHECK(ScreamerCaptureCompletions(&r,kScreamerStreamOutput,&periods)==kScreamerOK && periods==1);
    for(i=0;i<3;++i) complete(&r.rings[1],i,0,kPPCDBDMAActive);
    CHECK(ScreamerCaptureCompletions(&r,kScreamerStreamOutput,&periods)==kScreamerOK && periods==2);
    CHECK(ScreamerCaptureCompletions(&r,kScreamerStreamOutput,&periods)==kScreamerOK && periods==0);
    CHECK(ScreamerStop(&r,kScreamerStreamInput,5000)==kScreamerOK);
    CHECK(r.streams[1].running);
    dma[1].holdStop=1;
    CHECK(ScreamerStop(&r,kScreamerStreamOutput,10)==kScreamerTimeout);
    CHECK(r.streams[1].buffer==dma[1].audio && r.streams[1].needsQuiesce);
    setup(&r,&c,&ops);dma[1].unmappable=1;
    CHECK(ScreamerStart(&r,kScreamerStreamOutput,dma[1].audio,8192,4096,44100,5000)==kScreamerInvalid);
    CHECK(dma[1].starts==0);
    setup(&r,&c,&ops);dma[1].cacheError=1;
    CHECK(ScreamerStart(&r,kScreamerStreamOutput,dma[1].audio,8192,4096,44100,5000)!=kScreamerOK);
    CHECK(dma[1].starts==0);
    setup(&r,&c,&ops);
    CHECK(ScreamerStart(&r,kScreamerStreamOutput,dma[1].audio,8192,4096,44100,5000)==kScreamerOK);
    complete(&r.rings[1],0,1025,kPPCDBDMAActive);
    CHECK(ScreamerCaptureCompletions(&r,kScreamerStreamOutput,&periods)==kScreamerFault);
    CHECK(r.faulted);
    printf("runtime: %u checks, %u failures\n",checks,failures);
    return failures!=0;
}
