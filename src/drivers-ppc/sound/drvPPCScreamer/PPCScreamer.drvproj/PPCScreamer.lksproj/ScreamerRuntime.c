/* Copyright (c) 2026 RhapsodiOS Project. */
#include "ScreamerRuntime.h"
#include "TASTime.h"
#include <string.h>
#include <limits.h>
static ScreamerStatus dma_status(PPCDBDMAStatus s)
{
    if(s==kPPCDBDMAOK) return kScreamerOK;
    if(s==kPPCDBDMATimeout) return kScreamerTimeout;
    if(s==kPPCDBDMAFault) return kScreamerFault;
    if(s==kPPCDBDMACoherency) return kScreamerIOError;
    return kScreamerInvalid;
}
static unsigned long stop_deadline(ScreamerRuntime *r,unsigned long deadline)
{
    unsigned long now,left,bounded;
    now=r->codec.ops.nowMS(r->codec.ops.context);
    if(!TASTimeRemaining(now,deadline,&left) || !left) return now;
    if(left>100 && TASTimeAdd(now,100,&bounded)) return bounded;
    return deadline;
}
static void fault(ScreamerRuntime *r)
{
    unsigned int i;
    unsigned long deadline;
    r->faulted=1;
    if(!TASTimeAdd(r->codec.ops.nowMS(r->codec.ops.context),100,&deadline)) return;
    for(i=0;i<2;++i) (void)ScreamerStop(r,(ScreamerStream)i,deadline);
    (void)ScreamerCodecWrite(&r->codec,1,r->codec.shadow[1]|0x280U,deadline);
}
ScreamerStatus ScreamerRuntimeInitialize(ScreamerRuntime *r,
    const ScreamerMachineConfig *config,const ScreamerRuntimeOps *ops,unsigned long deadline)
{
    ScreamerStatus s;
    unsigned int code,i,sense,second;
    if(!r || !config || !ops || !ops->setPlatform ||
        ScreamerRateCode(config,44100,&code)!=kScreamerOK) return kScreamerInvalid;
    memset(r,0,sizeof(*r));r->config=*config;r->ops=*ops;r->codec.ops=ops->codec;
    if(!ops->codec.nowMS || !ops->codec.readLE32 || !ops->codec.writeLE32 ||
        !ops->codec.sleepMS || !ops->codec.barrier) return kScreamerInvalid;
    s=ops->setPlatform(ops->context,1);
    if(s!=kScreamerOK) return s;
    s=ScreamerCodecInitialize(&r->codec,config,deadline);
    if(s!=kScreamerOK) {
        r->faulted=1;(void)ops->setPlatform(ops->context,0);return s;
    }
    r->desired.userMuted=1;r->desired.attenuation[0]=r->desired.attenuation[1]=15;
    for(i=0;i<kScreamerInputCount;++i) if(config->profile.inputBits[i]) break;
    if(i==kScreamerInputCount) return kScreamerUnresolved;
    r->desired.input=(ScreamerInput)i;r->applied=r->desired;
    r->power=kScreamerPowerReady;r->clockRate=44100;r->generation=1;r->initialized=1;
    s=r->codec.ops.readLE32(r->codec.ops.context,0x20,&sense);
    if(s==kScreamerOK) s=ScreamerCodecDelay(&r->codec,5,deadline);
    if(s==kScreamerOK) s=r->codec.ops.readLE32(r->codec.ops.context,0x20,&second);
    if(s!=kScreamerOK) {fault(r);return s;}
    sense&=config->profile.headphoneMask;
    second&=config->profile.headphoneMask;
    if(sense==second) {
        r->headphone=config->profile.anySense ? second!=0 :
            second==config->profile.headphoneMatch;
        r->routeKnown=1;
    }
    return ScreamerApplyControls(r,&r->desired,deadline);
}
ScreamerStatus ScreamerStart(ScreamerRuntime *r,ScreamerStream direction,
    void *buffer,unsigned long bytes,unsigned long period,unsigned int hz,unsigned long deadline)
{
    ScreamerStreamState *s,*peer;
    PPCDBDMATransition transition;
    PPCDBDMAStatus ds;
    ScreamerStatus status;
    unsigned int code;
    if(!r || direction<0 || direction>1 || !r->initialized) return kScreamerInvalid;
    if(r->closing) return kScreamerClosed;
    if(r->faulted || r->power!=kScreamerPowerReady) return kScreamerFault;
    if(!buffer || !bytes || !period || (bytes&3) || (period&3) ||
        period>bytes || bytes%period) return kScreamerInvalid;
    s=&r->streams[direction];peer=&r->streams[1-direction];
    if(s->running || s->needsQuiesce) return kScreamerBusy;
    if(ScreamerRateCode(&r->config,hz,&code)!=kScreamerOK) return kScreamerUnsupported;
    if(peer->running && peer->rate!=hz) return kScreamerBusy;
    ds=PPCDBDMABuildRing(&r->rings[direction],&r->ops.storage[direction],
        (PPCDBDMADirection)direction,buffer,bytes,period,&r->ops.dma[direction]);
    if(ds!=kPPCDBDMAOK) return dma_status(ds);
    if(!r->ops.dma[direction].publish || !r->ops.dma[direction].invalidate)
        return kScreamerInvalid;
    ds=r->ops.dma[direction].publish(r->ops.dma[direction].coherencyContext,buffer,bytes);
    if(ds==kPPCDBDMAOK && direction==kScreamerStreamInput)
        ds=r->ops.dma[direction].invalidate(r->ops.dma[direction].coherencyContext,buffer,bytes);
    if(ds!=kPPCDBDMAOK) return dma_status(ds);
    if(!peer->running) {
        status=ScreamerCodecSetRate(&r->codec,&r->config,hz,deadline);
        if(status!=kScreamerOK) {fault(r);return status;}
        r->clockRate=hz;
    }
    s->buffer=buffer;s->bytes=bytes;s->period=period;s->rate=hz;s->remainder=0;
    transition=PPCDBDMAStartRing(&r->rings[direction],&r->ops.dma[direction],deadline);
    if(transition.status!=kPPCDBDMAOK) {
        s->needsQuiesce=r->rings[direction].state==kPPCDBDMAFaulted;
        if(s->needsQuiesce || transition.sharedClockInvalidated) fault(r);
        return dma_status(transition.status);
    }
    s->running=s->needsQuiesce=1;return kScreamerOK;
}
ScreamerStatus ScreamerStop(ScreamerRuntime *r,ScreamerStream direction,
    unsigned long deadline)
{
    ScreamerStreamState *s;
    PPCDBDMATransition t;
    if(!r || direction<0 || direction>1) return kScreamerInvalid;
    s=&r->streams[direction];
    if(!s->running && !s->needsQuiesce) return kScreamerOK;
    t=PPCDBDMAStopRing(&r->rings[direction],&r->ops.dma[direction],stop_deadline(r,deadline));
    if(t.status!=kPPCDBDMAOK) {r->faulted=1;return dma_status(t.status);}
    s->running=s->needsQuiesce=0;s->remainder=0;
    return kScreamerOK;
}
ScreamerStatus ScreamerCaptureCompletions(ScreamerRuntime *r,ScreamerStream direction,
    unsigned int *periods)
{
    PPCDBDMACompletion c;
    PPCDBDMAStatus ds;
    ScreamerStreamState *s;
    unsigned long total,n;
    if(!r || !periods || direction<0 || direction>1) return kScreamerInvalid;
    *periods=0;
    if(r->closing) return kScreamerClosed;
    if(r->faulted) return kScreamerFault;
    s=&r->streams[direction];
    if(!s->running) return kScreamerOK;
    if(direction==kScreamerStreamInput) {
        ds=r->ops.dma[direction].invalidate(r->ops.dma[direction].coherencyContext,
            s->buffer,s->bytes);
        if(ds!=kPPCDBDMAOK) {fault(r);return dma_status(ds);}
    }
    ds=PPCDBDMAServiceCompletions(&r->rings[direction],&r->ops.dma[direction],&c);
    if(ds!=kPPCDBDMAOK) {fault(r);return dma_status(ds);}
    if(c.bytes>ULONG_MAX-s->remainder) {fault(r);return kScreamerFault;}
    total=s->remainder+c.bytes;n=total/s->period;
    if(n>UINT_MAX) {fault(r);return kScreamerFault;}
    s->remainder=total%s->period;*periods=(unsigned int)n;
    return kScreamerOK;
}

ScreamerStatus ScreamerApplyControls(ScreamerRuntime *r,const ScreamerControls *controls,
    unsigned long deadline)
{
    ScreamerControls next;
    ScreamerStatus status;
    unsigned int reg,atten,route,port,input,i;
    if(!r || !controls || !r->initialized) return kScreamerInvalid;
    if(r->closing) return kScreamerClosed;
    if(r->faulted) return kScreamerFault;
    if(r->power!=kScreamerPowerReady) return kScreamerBusy;
    next=*controls;
    if(next.input<0 || next.input>=kScreamerInputCount ||
        !r->config.profile.inputBits[next.input]) return kScreamerUnsupported;
    if(next.userMuted!=0 && next.userMuted!=1) return kScreamerInvalid;
    for(i=0;i<2;++i) if(next.gain[i]>15 || next.attenuation[i]>15) return kScreamerInvalid;
    if(!next.userMuted && !r->routeKnown && !r->routePending) return kScreamerBusy;
    route=r->routePending?r->pendingHeadphone:r->headphone;
    reg=(r->codec.shadow[1]&~0x40U)|0x280U;
    r->desired=next;
    status=ScreamerCodecWrite(&r->codec,1,reg,deadline);
    input=(r->codec.shadow[0]&~0xeffU)|r->config.profile.inputBits[next.input]|
        (next.gain[0]<<4)|next.gain[1];
    if(status==kScreamerOK) status=ScreamerCodecWrite(&r->codec,0,input,deadline);
    atten=(next.attenuation[0]<<6)|next.attenuation[1];
    if(status==kScreamerOK) status=ScreamerCodecWrite(&r->codec,2,atten,deadline);
    if(status==kScreamerOK) status=ScreamerCodecWrite(&r->codec,4,atten,deadline);
    if(r->config.profile.speakerKind==5) {
        reg&=~0x800U;
        if(route != r->config.profile.speakerParam) reg|=0x800U;
        if(status==kScreamerOK) status=ScreamerCodecWrite(&r->codec,1,reg,deadline);
    }
    if(status==kScreamerOK) status=ScreamerCodecDelay(&r->codec,5,deadline);
    port=route?r->config.profile.headphonePort:r->config.profile.speakerPort;
    if(!next.userMuted) reg&=~(port==1?0x200U:0x80U);
    if(status==kScreamerOK) status=ScreamerCodecWrite(&r->codec,1,reg,deadline);
    if(status!=kScreamerOK) {fault(r);return status;}
    r->applied=next;r->headphone=route;
    if(r->routePending) r->routeKnown=1;
    r->routePending=0;
    return kScreamerOK;
}
ScreamerStatus ScreamerObserveJack(ScreamerRuntime *r,unsigned int sense,
    unsigned long now,unsigned long generation)
{
    unsigned int plugged;
    unsigned long left;
    if(!r || !r->initialized) return kScreamerInvalid;
    if(r->closing || generation!=r->generation) return kScreamerClosed;
    if(r->faulted) return kScreamerFault;
    if(r->power!=kScreamerPowerReady) return kScreamerBusy;
    plugged=r->config.profile.anySense ? (sense&r->config.profile.headphoneMask)!=0 :
        (sense&r->config.profile.headphoneMask)==r->config.profile.headphoneMatch;
    if(!r->jackCandidateValid || plugged!=r->jackCandidate) {
        r->jackCandidate=plugged;r->jackCandidateValid=1;
        if(!TASTimeAdd(now,5,&r->jackDeadline)) return kScreamerTimeout;
        return kScreamerOK;
    }
    if(TASTimeBefore(now,r->jackDeadline)) return kScreamerOK;
    if(!TASTimeDue(now,r->jackDeadline) &&
        !TASTimeRemaining(now,r->jackDeadline,&left)) return kScreamerTimeout;
    if(!r->routeKnown || plugged!=r->headphone) {
        r->pendingHeadphone=plugged;r->routePending=1;
    }
    return kScreamerOK;
}
ScreamerStatus ScreamerServiceDeferred(ScreamerRuntime *r,unsigned long deadline,
    unsigned int periods[2])
{
    ScreamerStatus status;
    unsigned int i;
    if(!r || !periods) return kScreamerInvalid;
    periods[0]=periods[1]=0;
    if(r->closing) return kScreamerClosed;
    if(r->faulted) return kScreamerFault;
    if(r->power!=kScreamerPowerReady) return kScreamerBusy;
    if(r->routePending) {
        status=ScreamerApplyControls(r,&r->desired,deadline);
        if(status!=kScreamerOK) return status;
    }
    for(i=0;i<2;++i) {
        status=ScreamerCaptureCompletions(r,(ScreamerStream)i,&periods[i]);
        if(status!=kScreamerOK) return status;
    }
    return kScreamerOK;
}
