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
static unsigned int platformOffs,platformUnsafe,validBuffers,platformConflict,platformOwned,dmaWrites;
static unsigned int amplifier,amplifierWrites,amplifierUnsafe;
static unsigned int muxWrites,muxValue,muxFail;
static unsigned long muxTimes[8];
static ScreamerStatus set_mux(void *p,unsigned int value)
{
    (void)p;
    if(muxWrites<8) muxTimes[muxWrites]=fixture.now;
    ++muxWrites;
    if(muxFail) return kScreamerIOError;
    muxValue=value;return kScreamerOK;
}
static ScreamerStatus set_amplifier(void *p,int enabled)
{
    (void)p;++amplifierWrites;
    if(!enabled && ((fixture.hardware[1]&0x680U)!=0x280U ||
        ((dma[0].control|dma[1].control)&kPPCDBDMARun))) ++amplifierUnsafe;
    amplifier=(unsigned int)enabled;return kScreamerOK;
}
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
    ++dmaWrites;
    if(!platformOwned) ++platformUnsafe;
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
static ScreamerStatus platform(void *p,int ready)
{
    (void)p;
    if(ready && platformConflict) return kScreamerBusy;
    platformOwned=(unsigned int)ready;
    if(!ready) {
        ++platformOffs;
        if((dma[0].control|dma[1].control)&kPPCDBDMARun) ++platformUnsafe;
    }
    return kScreamerOK;
}
static int buffer_valid(void *p,ScreamerStream stream,void *buffer,unsigned long bytes)
{ (void)p;return (validBuffers&(1U<<stream)) && buffer==dma[stream].audio && bytes==8192; }
static void setup(ScreamerRuntime *r,ScreamerMachineConfig *c,ScreamerRuntimeOps *ops)
{
    ScreamerCodec codec;
    unsigned int i;
    FixtureInit(&fixture);FixtureCodecInit(&fixture,&codec);
    platformOffs=platformUnsafe=0;validBuffers=3;
    CHECK(ScreamerDiscover(&fixture.reader,3,c)==kScreamerOK);
    memset(ops,0,sizeof(*ops));ops->codec=codec.ops;ops->setPlatform=platform;ops->bufferValid=buffer_valid;
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
    unsigned int periods,i,before,phase,wakeWrites;
    unsigned int serviced[2];
    ScreamerControls controls,applied;
    setup(&r,&c,&ops);
    fixture.regs[0]=0x7111U;fixture.irqContext=1;
    before=fixture.commandWrites;i=0;
    CHECK(ScreamerAcknowledgeInterrupt(&ops,0,&i)==kScreamerOK);
    CHECK(i==1 && fixture.regs[0]==0x7111U && fixture.commandWrites==before);
    CHECK(fixture.irqViolations==0);
    CHECK(ScreamerAcknowledgeInterrupt(&ops,3,&i)==kScreamerInvalid && i==1);
    CHECK(ScreamerAcknowledgeInterrupt(&ops,1,&i)==kScreamerOK && i==3);
    fixture.irqContext=0;
    CHECK(ScreamerStart(&r,kScreamerStreamOutput,dma[1].audio,8192,4096,44100,5000)==kScreamerOK);
    CHECK(dma[1].published>0 && dma[1].starts==1);
    CHECK(r.rings[1].dataDescriptorCount==3);
    before=fixture.commandWrites;
    CHECK(ScreamerStart(&r,kScreamerStreamInput,dma[0].audio,8192,4096,22050,5000)==kScreamerBusy);
    CHECK(fixture.commandWrites==before && dma[1].starts==1);
    CHECK(ScreamerStart(&r,kScreamerStreamInput,dma[0].audio,8192,4096,44100,5000)==kScreamerOK);
    controls=r.desired;controls.input=kScreamerInputCD;before=fixture.writeCalls;
    CHECK(ScreamerApplyControls(&r,&controls,5000)==kScreamerBusy);
    CHECK(fixture.writeCalls==before && r.desired.input==kScreamerInputLine);
    complete(&r.rings[1],0,0,kPPCDBDMAActive);
    CHECK(ScreamerCaptureCompletions(&r,kScreamerStreamOutput,&periods)==kScreamerOK && periods==0);
    complete(&r.rings[1],1,0,kPPCDBDMAActive);
    CHECK(ScreamerCaptureCompletions(&r,kScreamerStreamOutput,&periods)==kScreamerOK && periods==1);
    complete(&r.rings[1],2,0,kPPCDBDMAActive);
    CHECK(ScreamerCaptureCompletions(&r,kScreamerStreamOutput,&periods)==kScreamerOK && periods==1);
    for(i=0;i<3;++i) complete(&r.rings[1],i,0,kPPCDBDMAActive);
    complete(&r.rings[0],0,0,kPPCDBDMAActive);complete(&r.rings[0],1,0,kPPCDBDMAActive);
    CHECK(ScreamerServiceDeferred(&r,5000,serviced)==kScreamerOK && serviced[1]==2 && serviced[0]==1);
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
    setup(&r,&c,&ops);
    controls=r.desired;controls.userMuted=0;
    controls.attenuation[0]=2;controls.attenuation[1]=9;
    controls.gain[0]=7;controls.gain[1]=4;
    CHECK(ScreamerApplyControls(&r,&controls,5000)==kScreamerOK);
    CHECK(fixture.hardware[0]==0x474 && fixture.hardware[2]==0x89);
    CHECK((fixture.hardware[1]&0x280)==0x200);
    applied=r.applied;before=fixture.commandWrites;
    controls.input=kScreamerInputMic;
    CHECK(ScreamerApplyControls(&r,&controls,5000)==kScreamerUnsupported);
    CHECK(fixture.commandWrites==before && r.applied.input==applied.input);
    controls=applied;
    CHECK(ScreamerObserveJack(&r,4,100,r.generation)==kScreamerOK);
    CHECK(ScreamerObserveJack(&r,0,102,r.generation)==kScreamerOK);
    CHECK(ScreamerObserveJack(&r,4,103,r.generation)==kScreamerOK);
    CHECK(ScreamerObserveJack(&r,4,107,r.generation)==kScreamerOK);
    CHECK(!r.routePending && !r.headphone);
    CHECK(ScreamerObserveJack(&r,4,108,r.generation)==kScreamerOK);
    CHECK(r.routePending && fixture.commandWrites==before);
    CHECK(ScreamerServiceDeferred(&r,5000,serviced)==kScreamerOK);
    CHECK(r.headphone && (fixture.hardware[1]&0x280)==0x80);
    CHECK(r.applied.input==kScreamerInputLine && r.applied.attenuation[0]==2);
    controls.userMuted=1;
    CHECK(ScreamerApplyControls(&r,&controls,5000)==kScreamerOK);
    CHECK(ScreamerObserveJack(&r,0,200,r.generation)==kScreamerOK);
    CHECK(ScreamerObserveJack(&r,0,205,r.generation)==kScreamerOK);
    CHECK(ScreamerServiceDeferred(&r,5000,serviced)==kScreamerOK);
    CHECK(!r.headphone && (fixture.hardware[1]&0x280)==0x280);
    CHECK(r.applied.userMuted && r.applied.attenuation[1]==9);
    before=fixture.commandWrites;
    CHECK(ScreamerObserveJack(&r,4,300,r.generation-1)==kScreamerClosed);
    CHECK(fixture.commandWrites==before);
    r.closing=1;before=fixture.writeCalls;
    CHECK(ScreamerServiceDeferred(&r,5000,serviced)==kScreamerClosed && !serviced[0] && !serviced[1]);
    CHECK(fixture.writeCalls==before);
    r.closing=0;
    controls.attenuation[0]=4;fixture.failWrite=fixture.writeCalls+3;
    CHECK(ScreamerApplyControls(&r,&controls,5000)==kScreamerIOError);
    CHECK(r.faulted && r.applied.attenuation[0]==2);
    setup(&r,&c,&ops);r.power=kScreamerPowerSuspended;
    before=fixture.commandWrites;
    CHECK(ScreamerApplyControls(&r,&r.desired,5000)==kScreamerBusy);
    CHECK(fixture.commandWrites==before);
    setup(&r,&c,&ops);
    controls=r.desired;controls.userMuted=0;controls.attenuation[0]=2;controls.gain[1]=9;
    CHECK(ScreamerApplyControls(&r,&controls,5000)==kScreamerOK);
    CHECK(ScreamerStart(&r,kScreamerStreamOutput,dma[1].audio,8192,4096,44100,5000)==kScreamerOK);
    CHECK(ScreamerSetPower(&r,kScreamerPowerSuspended,5000)==kScreamerOK);
    CHECK(platformOffs==1 && !platformUnsafe && !r.streams[1].running);
    CHECK(r.desired.attenuation[0]==2 && r.desired.gain[1]==9 && !r.desired.userMuted);
    fixture.sense=4;
    CHECK(ScreamerSetPower(&r,kScreamerPowerReady,5000)==kScreamerOK);
    CHECK(r.streams[1].running && dma[1].starts==2 && r.headphone);
    CHECK(r.applied.attenuation[0]==2 && r.applied.gain[1]==9 && (fixture.hardware[1]&0x280)==0x80);
    before=fixture.writeCalls;
    CHECK(ScreamerSetPower(&r,kScreamerPowerReady,5000)==kScreamerOK && fixture.writeCalls==before);
    CHECK(ScreamerSetPower(&r,(ScreamerPowerState)99,5000)==kScreamerInvalid);
    CHECK(ScreamerSetPower(&r,kScreamerPowerOff,5000)==kScreamerOK);
    validBuffers=0;
    CHECK(ScreamerSetPower(&r,kScreamerPowerReady,5000)==kScreamerOK && !r.streams[1].running && dma[1].starts==2);
    CHECK(ScreamerBeginClose(&r,5000)==kScreamerOK && r.closing && r.power==kScreamerPowerOff);
    before=fixture.writeCalls;
    CHECK(ScreamerServiceDeferred(&r,5000,serviced)==kScreamerClosed && fixture.writeCalls==before);
    setup(&r,&c,&ops);
    CHECK(ScreamerStart(&r,kScreamerStreamOutput,dma[1].audio,8192,4096,44100,5000)==kScreamerOK);
    dma[1].holdStop=1;
    CHECK(ScreamerSetPower(&r,kScreamerPowerSuspended,5000)==kScreamerTimeout);
    CHECK(!platformOffs && r.streams[1].needsQuiesce && r.power==kScreamerPowerReady);
    setup(&r,&c,&ops);
    CHECK(ScreamerSetPower(&r,kScreamerPowerSuspended,5000)==kScreamerOK);
    fixture.readyAt=6000;
    CHECK(ScreamerSetPower(&r,kScreamerPowerReady,5000)==kScreamerTimeout);
    CHECK(r.faulted && !r.streams[0].running && !r.streams[1].running && !dma[0].starts && !dma[1].starts);
    setup(&r,&c,&ops);
    CHECK(ScreamerSetPower(&r,kScreamerPowerSuspended,5000)==kScreamerOK);
    before=fixture.writeCalls;
    CHECK(ScreamerSetPower(&r,kScreamerPowerReady,5000)==kScreamerOK);
    wakeWrites=fixture.writeCalls-before;
    for(phase=1;phase<=wakeWrites;++phase) {
        setup(&r,&c,&ops);
        CHECK(ScreamerSetPower(&r,kScreamerPowerSuspended,5000)==kScreamerOK);
        fixture.failWrite=fixture.writeCalls+phase;
        CHECK(ScreamerSetPower(&r,kScreamerPowerReady,5000)==kScreamerIOError);
        CHECK(r.faulted && !dma[0].starts && !dma[1].starts);
    }
    setup(&r,&c,&ops);FixtureSawtooth(&fixture);
    CHECK(ScreamerDiscover(&fixture.reader,3,&c)==kScreamerOK);
    ops.setAmplifier=set_amplifier;amplifier=amplifierWrites=amplifierUnsafe=0;
    CHECK(ScreamerRuntimeInitialize(&r,&c,&ops,5000)==kScreamerOK);
    CHECK(amplifier==1 && amplifierWrites==1 && fixture.now>=1057);
    CHECK((fixture.hardware[1]&0x680U)==0x680U && c.profile.powerKind==7);
    CHECK(ScreamerSetPower(&r,kScreamerPowerSuspended,5000)==kScreamerOK);
    CHECK(!amplifier && !amplifierUnsafe && amplifierWrites==2);
    CHECK(ScreamerSetPower(&r,kScreamerPowerReady,5000)==kScreamerOK);
    CHECK(amplifier && amplifierWrites==3 && (fixture.hardware[1]&0x400U));
    setup(&r,&c,&ops);dma[1].holdStop=1;
    CHECK(ScreamerQuiesceHardware(&ops,100)==kScreamerTimeout);
    CHECK(!platformOffs && !dma[0].starts && !dma[1].starts);
    dma[1].holdStop=0;
    CHECK(ScreamerQuiesceHardware(&ops,5000)==kScreamerOK);
    setup(&r,&c,&ops);dma[1].holdStop=1;
    before=fixture.writeCalls;
    CHECK(ScreamerRuntimeInitialize(&r,&c,&ops,5000)==kScreamerTimeout);
    CHECK(fixture.writeCalls==before && r.faulted && r.initialized);
    CHECK(ScreamerBeginClose(&r,5000)==kScreamerTimeout && !platformOffs);
    dma[1].holdStop=0;platformConflict=1;dmaWrites=0;before=fixture.writeCalls;
    CHECK(ScreamerRuntimeInitialize(&r,&c,&ops,5000)==kScreamerBusy);
    CHECK(!dmaWrites && fixture.writeCalls==before);
    platformConflict=0;
    setup(&r,&c,&ops);fixture.regs[0]|=0x800U;i=0;
    CHECK(ScreamerAcknowledgeInterrupt(&ops,0,&i)==kScreamerOK);
    CHECK((i&0x800U)!=0);
    CHECK(ScreamerStart(&r,kScreamerStreamOutput,dma[1].audio,8192,4096,44100,5000)==kScreamerOK);
    complete(&r.rings[1],0,0,kPPCDBDMAActive);
    CHECK(ScreamerServiceInterrupt(&r,i,5000,serviced)==kScreamerFault);
    CHECK(r.faulted && !r.streams[1].running && !serviced[0] && !serviced[1]);
    setup(&r,&c,&ops);FixturePismo(&fixture);
    CHECK(ScreamerDiscover(&fixture.reader,3,&c)==kScreamerOK);
    ops.setAmplifier=set_amplifier;amplifier=amplifierWrites=0;
    CHECK(ScreamerRuntimeInitialize(&r,&c,&ops,5000)==kScreamerOK);
    CHECK(amplifier==1 && fixture.sleeps[0]==80 && fixture.sleeps[1]==200);
    CHECK(fixture.traceCommand[0]==0x1280U && fixture.traceTime[0]==80);
    CHECK(fixture.traceTime[1]>=280 && (fixture.hardware[1]&0xc00U)==0);
    CHECK(r.desired.input==kScreamerInputMic && fixture.hardware[0]==0x800U);
    CHECK(ScreamerSetPower(&r,kScreamerPowerSuspended,5000)==kScreamerOK);
    CHECK(!amplifier && (fixture.hardware[1]&0x400U)!=0);
    CHECK(ScreamerSetPower(&r,kScreamerPowerReady,5000)==kScreamerOK);
    CHECK(amplifier && (fixture.hardware[1]&0xc00U)==0);
    setup(&r,&c,&ops);FixtureLombard(&fixture);
    CHECK(ScreamerDiscover(&fixture.reader,3,&c)==kScreamerOK);
    ops.setInputMux=set_mux;muxWrites=muxValue=muxFail=0;
    CHECK(ScreamerRuntimeInitialize(&r,&c,&ops,5000)==kScreamerOK);
    CHECK(fixture.sleeps[0]==10 && muxWrites==2 && muxValue==1);
    CHECK(muxTimes[1]-muxTimes[0]==2 && fixture.now>=muxTimes[1]+320);
    controls=r.desired;controls.gain[0]=3;before=muxWrites;
    CHECK(ScreamerApplyControls(&r,&controls,5000)==kScreamerOK && muxWrites==before);
    controls.input=kScreamerInputCD;
    CHECK(ScreamerApplyControls(&r,&controls,5000)==kScreamerOK);
    CHECK(muxValue==0 && (fixture.hardware[0]&0xe00U)==0x200U);
    muxFail=1;controls.input=kScreamerInputMic;
    CHECK(ScreamerApplyControls(&r,&controls,5000)==kScreamerIOError);
    CHECK(r.faulted && r.applied.input==kScreamerInputCD);
    muxFail=0;
    setup(&r,&c,&ops);FixtureIMac(&fixture,"PowerMac2,1",0);
    CHECK(ScreamerDiscover(&fixture.reader,3,&c)==kScreamerOK);
    ops.setAmplifier=set_amplifier;
    CHECK(ScreamerRuntimeInitialize(&r,&c,&ops,5000)==kScreamerOK);
    controls=r.desired;controls.userMuted=0;
    CHECK(ScreamerApplyControls(&r,&controls,5000)==kScreamerOK);
    CHECK((fixture.hardware[1]&0xa80U)==0x200U);
    CHECK(ScreamerObserveJack(&r,2,100,r.generation)==kScreamerOK);
    CHECK(ScreamerObserveJack(&r,2,105,r.generation)==kScreamerOK);
    CHECK(ScreamerServiceDeferred(&r,5000,serviced)==kScreamerOK);
    CHECK(r.headphone==2 && (fixture.hardware[1]&0xa80U)==0xa00U);
    CHECK(ScreamerObserveJack(&r,1,200,r.generation)==kScreamerOK);
    CHECK(ScreamerObserveJack(&r,1,205,r.generation)==kScreamerOK);
    CHECK(ScreamerServiceDeferred(&r,5000,serviced)==kScreamerOK);
    CHECK(r.headphone==1 && (fixture.hardware[1]&0xa80U)==0x880U);
    CHECK(ScreamerObserveJack(&r,6,300,r.generation)==kScreamerOK);
    CHECK(ScreamerObserveJack(&r,6,305,r.generation)==kScreamerOK);
    CHECK(ScreamerServiceDeferred(&r,5000,serviced)==kScreamerOK);
    CHECK(r.headphone==2 && (fixture.hardware[1]&0xa80U)==0xa00U);
    setup(&r,&c,&ops);FixtureIMac(&fixture,"PowerMac2,2",1);
    CHECK(ScreamerDiscover(&fixture.reader,3,&c)==kScreamerOK);
    ops.setAmplifier=set_amplifier;
    CHECK(ScreamerRuntimeInitialize(&r,&c,&ops,5000)==kScreamerOK);
    controls=r.desired;controls.userMuted=0;
    CHECK(ScreamerApplyControls(&r,&controls,5000)==kScreamerOK);
    CHECK((fixture.hardware[1]&0xa80U)==0xa00U);
    CHECK(ScreamerObserveJack(&r,4,100,r.generation)==kScreamerOK);
    CHECK(ScreamerObserveJack(&r,4,105,r.generation)==kScreamerOK);
    CHECK(ScreamerServiceDeferred(&r,5000,serviced)==kScreamerOK);
    CHECK((fixture.hardware[1]&0xa80U)==0x200U);
    printf("runtime: %u checks, %u failures\n",checks,failures);
    return failures!=0;
}
