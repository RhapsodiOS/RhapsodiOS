/* Copyright (c) 2026 RhapsodiOS Project. */
#include "ScreamerCodec.h"
#include "TASTime.h"
static int valid(const ScreamerCodec *c)
{
    return c && c->ops.readLE32 && c->ops.writeLE32 && c->ops.nowMS &&
        c->ops.sleepMS && c->ops.barrier;
}
static ScreamerStatus remaining(ScreamerCodec *c,unsigned long deadline,unsigned long *left)
{
    return TASTimeRemaining(c->ops.nowMS(c->ops.context),deadline,left) && *left ?
        kScreamerOK:kScreamerTimeout;
}
ScreamerStatus ScreamerCodecDelay(ScreamerCodec *c,unsigned long ms,unsigned long deadline)
{
    unsigned long left;
    if(!valid(c)) return kScreamerInvalid;
    if(remaining(c,deadline,&left)!=kScreamerOK || ms>=left) return kScreamerTimeout;
    c->ops.sleepMS(c->ops.context,ms);
    return remaining(c,deadline,&left);
}
static ScreamerStatus waitmask(ScreamerCodec *c,unsigned int reg,
    unsigned int mask,unsigned int expected,unsigned long deadline)
{
    unsigned long phase,left;
    unsigned int v;
    ScreamerStatus s;
    if(remaining(c,deadline,&left)!=kScreamerOK) return kScreamerTimeout;
    if(left>1000) {
        if(!TASTimeAdd(c->ops.nowMS(c->ops.context),1000,&phase)) return kScreamerTimeout;
    } else phase=deadline;
    for(;;) {
        if(remaining(c,phase,&left)!=kScreamerOK) return kScreamerTimeout;
        s=c->ops.readLE32(c->ops.context,reg,&v);
        if(s!=kScreamerOK) return s;
        c->ops.barrier(c->ops.context);
        if((v&mask)==expected) return kScreamerOK;
        c->ops.sleepMS(c->ops.context,1);
    }
}
ScreamerStatus ScreamerCodecWrite(ScreamerCodec *c,unsigned int reg,
    unsigned int payload,unsigned long deadline)
{
    ScreamerStatus s;
    if(!valid(c) || reg>7 || reg==3 || payload>0xfff) return kScreamerInvalid;
    s=waitmask(c,0x20,1U<<22,1U<<22,deadline);
    if(s!=kScreamerOK) return s;
    s=c->ops.writeLE32(c->ops.context,0x10,(reg<<12)|payload);
    if(s!=kScreamerOK) return s;
    c->ops.barrier(c->ops.context);
    s=waitmask(c,0x10,0x01000000U,0,deadline);
    if(s==kScreamerOK) {c->shadow[reg]=payload;c->validMask|=1U<<reg;}
    else c->validMask&=~(1U<<reg);
    return s;
}
ScreamerStatus ScreamerCodecRead(ScreamerCodec *c,unsigned int reg,
    unsigned int *payload,unsigned long deadline)
{
    ScreamerStatus s;
    unsigned int v,i;
    if(!payload || reg>7 || reg==3) return kScreamerInvalid;
    for(i=0;i<2;++i) {
        s=ScreamerCodecWrite(c,7,1U|(reg<<1),deadline);
        if(s!=kScreamerOK) return s;
    }
    s=c->ops.readLE32(c->ops.context,0x20,&v);
    if(s==kScreamerOK) {*payload=(v>>4)&0xfff;c->shadow[reg]=*payload;c->validMask|=1U<<reg;}
    return s;
}
ScreamerStatus ScreamerCodecSetRate(ScreamerCodec *c,const ScreamerMachineConfig *config,
    unsigned int hz,unsigned long deadline)
{
    unsigned int code,next;
    unsigned long left;
    ScreamerStatus s;
    if(!valid(c)) return kScreamerInvalid;
    s=ScreamerRateCode(config,hz,&code);
    if(s!=kScreamerOK) return s;
    if(remaining(c,deadline,&left)!=kScreamerOK) return kScreamerTimeout;
    next=(c->soundControl&~0x700U)|(code<<8);
    s=c->ops.writeLE32(c->ops.context,0,next);
    c->ops.barrier(c->ops.context);
    if(s==kScreamerOK) c->soundControl=next;
    return s;
}
ScreamerStatus ScreamerCodecInitialize(ScreamerCodec *c,const ScreamerMachineConfig *config,
    unsigned long deadline)
{
    static const unsigned int regs[]={0,1,2,4,5,6,7};
    static const unsigned int values[]={0,0x280,0x3cf,0x3cf,0x3cf,0,0};
    unsigned int i;
    unsigned long left;
    ScreamerStatus s;
    if(!valid(c) || !config) return kScreamerInvalid;
    if(remaining(c,deadline,&left)!=kScreamerOK) return kScreamerTimeout;
    s=c->ops.writeLE32(c->ops.context,0x40,0);
    if(s!=kScreamerOK) return s;
    c->soundControl=0x11;
    s=ScreamerCodecSetRate(c,config,44100,deadline);
    if(s!=kScreamerOK) return s;
    for(i=0;i<sizeof(regs)/sizeof(regs[0]);++i) {
        s=ScreamerCodecWrite(c,regs[i],values[i],deadline);
        if(s!=kScreamerOK) return s;
    }
    s=ScreamerCodecDelay(c,750,deadline);
    if(s!=kScreamerOK) return s;
    s=ScreamerCodecWrite(c,1,0x284,deadline);
    if(s!=kScreamerOK) return s;
    s=ScreamerCodecDelay(c,2,deadline);
    if(s!=kScreamerOK) return s;
    s=waitmask(c,0x20,1U<<22,1U<<22,deadline);
    if(s!=kScreamerOK) return s;
    return ScreamerCodecWrite(c,1,0x280,deadline);
}
ScreamerStatus ScreamerCodecSetPower(ScreamerCodec *c,ScreamerPowerState state,
    unsigned long deadline)
{
    unsigned int next;
    ScreamerStatus s;
    if(!valid(c) || !(c->validMask&(1U<<6)) ||
        state<kScreamerPowerReady || state>kScreamerPowerOff) return kScreamerInvalid;
    s=ScreamerCodecWrite(c,1,c->shadow[1]|0x280U,deadline);
    if(s!=kScreamerOK) return s;
    next=c->shadow[6]&~0x43U;
    if(state==kScreamerPowerStandby) next|=2;
    else if(state!=kScreamerPowerReady) next|=0x41;
    s=ScreamerCodecWrite(c,6,next,deadline);
    if(s!=kScreamerOK) return s;
    return ScreamerCodecDelay(c,5,deadline);
}
