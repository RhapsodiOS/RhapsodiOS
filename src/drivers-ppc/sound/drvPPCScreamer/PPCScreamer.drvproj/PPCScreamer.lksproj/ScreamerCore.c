/* Copyright (c) 2026 RhapsodiOS Project. */
#include "ScreamerCore.h"
#include "ScreamerProfiles.h"
#include <string.h>
#include <limits.h>
unsigned int ScreamerBE32(const unsigned char *b)
{
    return ((unsigned int)b[0]<<24)|((unsigned int)b[1]<<16)|
        ((unsigned int)b[2]<<8)|b[3];
}
static ScreamerBytes prop(const ScreamerPropertyReader *r,unsigned int n,const char *key)
{
    ScreamerBytes b;
    b.bytes=0;b.length=0;
    if(!r->getProperty(r->context,n,key,&b)) {b.bytes=0;b.length=0;}
    return b;
}
static int word(ScreamerBytes b,unsigned int *v)
{
    if(!b.bytes || b.length!=4) return 0;
    *v=ScreamerBE32(b.bytes);return 1;
}
static int cells(const ScreamerPropertyReader *r,unsigned int node,const char *key,
    unsigned int fallback,unsigned int *v)
{
    ScreamerBytes b=prop(r,node,key);
    if(!b.length) {*v=fallback;return 1;}
    return word(b,v) && (*v==1 || *v==2);
}
static int cellvalue(const unsigned char *p,unsigned int count,unsigned int *v)
{
    if(count==2 && ScreamerBE32(p)) return 0;
    *v=ScreamerBE32(p+(count-1)*4); return 1;
}
static int translate(const ScreamerPropertyReader *r,unsigned int bus,
    unsigned int *address,unsigned int length)
{
    unsigned int parent,ac,pc,sc,stride,pos,a,p,n,matches,mapped,depth;
    ScreamerBytes map;
    for(depth=0;bus && depth<16;++depth) {
        parent=r->getParent(r->context,bus);
        if(!parent) return 1;
        if(parent>r->nodeCount || !cells(r,bus,"#address-cells",2,&ac) ||
            !cells(r,parent,"#address-cells",2,&pc) ||
            !cells(r,bus,"#size-cells",1,&sc)) return 0;
        map=prop(r,bus,"ranges");
        if(!map.bytes) return 0;
        stride=(ac+pc+sc)*4;
        if(map.length%stride) return 0;
        matches=0;mapped=0;
        if(map.length) {
            for(pos=0;pos<map.length;pos+=stride) {
                if(!cellvalue(map.bytes+pos,ac,&a) ||
                    !cellvalue(map.bytes+pos+ac*4,pc,&p) ||
                    !cellvalue(map.bytes+pos+(ac+pc)*4,sc,&n)) return 0;
                if(*address>=a && *address-a<n && length<=n-(*address-a)) {
                    if(p>UINT_MAX-(*address-a)) return 0;
                    mapped=p+(*address-a);++matches;
                }
            }
            if(matches!=1) return 0;
            *address=mapped;
        }
        bus=parent;
    }
    return 0;
}
static int overlap(ScreamerRange a,ScreamerRange b)
{
    return a.address<=b.address ? b.address-a.address<a.length :
        a.address-b.address<b.length;
}
ScreamerStatus ScreamerRateCode(const ScreamerMachineConfig *c,unsigned int hz,
    unsigned int *code)
{
    static const unsigned int rates[]={44100,29400,22050,17640,14700,11025,8820,7350};
    unsigned int i,j;
    if(!c || !code || c->rateCount>8) return kScreamerInvalid;
    for(i=0;i<c->rateCount;++i) if(c->rates[i]==hz) {
        for(j=0;j<8;++j) if(rates[j]==hz) {*code=j;return kScreamerOK;}
    }
    return kScreamerUnsupported;
}
unsigned int ScreamerQuantize(unsigned int v,unsigned int maximum)
{
    unsigned int i,result=0,remainder=0;
    if(!maximum) return 0;
    if(v>=maximum) return 15;
    /* Fifteen additions avoid overflowing even for UINT_MAX domains. */
    for(i=0;i<15;++i) {
        if(remainder>=maximum-v) {remainder-=maximum-v;++result;}
        else remainder+=v;
    }
    if(remainder>=maximum/2+maximum%2) ++result;
    return result;
}
ScreamerStatus ScreamerDiscover(const ScreamerPropertyReader *r,unsigned int candidate,
    ScreamerMachineConfig *out)
{
    ScreamerMachineConfig c;
    ScreamerBytes b,model,compat;
    ScreamerIdentity id;
    unsigned int n,sound=0,count=0,bus,root,depth,ac,sc,stride,i,j,code;
    unsigned int clock=0,absolute=0,haveAbsolute=0,relative;
    if(!r || !out || !r->getProperty || !r->getParent || !r->delivered ||
        !r->nodeCount || r->nodeCount>512 || !candidate || candidate>r->nodeCount)
        return kScreamerInvalid;
    memset(&c,0,sizeof(c));
    for(n=1;n<=r->nodeCount;++n) {
        if(n!=candidate && r->getParent(r->context,n)!=candidate) continue;
        model=prop(r,n,"model");compat=prop(r,n,"compatible");
        id=ScreamerClassify(model,compat);
        if(id==kScreamerIdentityConflict || id==kScreamerIdentityOther)
            return kScreamerUnsupported;
        if(id==kScreamerIdentityScreamer) {sound=n;++count;}
    }
    if(count!=1) return kScreamerUnresolved;
    bus=r->getParent(r->context,candidate);
    if(!bus || bus>r->nodeCount) return kScreamerInvalid;
    compat=prop(r,bus,"compatible");
    /* Only the KeyLargo DAVbus platform backend is admitted initially. */
    for(i=0;i+8<=compat.length;++i)
        if((i==0 || compat.bytes[i-1]==0) &&
            !memcmp(compat.bytes+i,"keylargo",8) &&
            (i+8==compat.length || compat.bytes[i+8]==0)) clock=1;
    if(!clock) return kScreamerUnsupported;
    root=bus;
    for(depth=0;depth<16;++depth) {
        n=r->getParent(r->context,root);
        if(!n) break;
        if(n>r->nodeCount) return kScreamerInvalid;
        root=n;
    }
    if(depth==16) return kScreamerInvalid;
    model=prop(r,root,"model");
    if(!model.bytes || !model.length || model.length>=sizeof(c.machine))
        return kScreamerUnresolved;
    memcpy(c.machine,model.bytes,model.length); c.machine[model.length]=0;
    if(!cells(r,bus,"#address-cells",2,&ac) ||
        !cells(r,bus,"#size-cells",1,&sc)) return kScreamerInvalid;
    stride=(ac+sc)*4;b=prop(r,candidate,"reg");
    if(!b.bytes || b.length!=3*stride || r->delivered->rangeCount!=3 ||
        r->delivered->interruptCount!=3) return kScreamerInvalid;
    {
        ScreamerBytes a=prop(r,bus,"AAPL,address");
        if(a.length) {
            if(!word(a,&absolute)) return kScreamerInvalid;
            haveAbsolute=1;
        }
    }
    for(i=0;i<3;++i) {
        if(!cellvalue(b.bytes+i*stride,ac,&c.ranges[i].address) ||
            !cellvalue(b.bytes+i*stride+ac*4,sc,&c.ranges[i].length) ||
            c.ranges[i].length<(i?0x100U:0x44U))
            return kScreamerInvalid;
        relative=c.ranges[i].address;
        if(haveAbsolute) {
            ScreamerBytes map=prop(r,bus,"ranges");
            if(relative>UINT_MAX-absolute) return kScreamerInvalid;
            c.ranges[i].address=absolute+relative;
            if(map.length) {
                if(!translate(r,bus,&relative,c.ranges[i].length) ||
                    relative!=c.ranges[i].address) return kScreamerInvalid;
            }
        } else if(!translate(r,bus,&c.ranges[i].address,c.ranges[i].length))
            return kScreamerInvalid;
        if(
            (c.ranges[i].address&3) ||
            c.ranges[i].length-1>UINT_MAX-c.ranges[i].address)
            return kScreamerInvalid;
        if(c.ranges[i].address!=r->delivered->ranges[i].address ||
            c.ranges[i].length!=r->delivered->ranges[i].length)
            return kScreamerInvalid;
        for(j=0;j<i;++j) if(overlap(c.ranges[i],c.ranges[j])) return kScreamerInvalid;
    }
    c.controllerBase=c.ranges[0].address;
    b=prop(r,candidate,"interrupts");
    if(!b.bytes || (b.length!=12 && b.length!=24)) return kScreamerInvalid;
    stride=b.length/3;
    for(i=0;i<3;++i) {
        c.interrupts[i]=ScreamerBE32(b.bytes+i*stride);
        if(stride==8 && ScreamerBE32(b.bytes+i*stride+4)>1) return kScreamerInvalid;
        if(c.interrupts[i]!=r->delivered->interrupts[i]) return kScreamerInvalid;
        c.localInterrupts[i]=i;
        for(j=0;j<i;++j) if(c.interrupts[i]==c.interrupts[j]) return kScreamerInvalid;
    }
    b=prop(r,sound,"sample-rates");
    if(!b.bytes || !b.length || b.length%4 || b.length>32) return kScreamerInvalid;
    c.rateCount=b.length/4;
    for(i=0;i<c.rateCount;++i) c.rates[i]=ScreamerBE32(b.bytes+i*4);
    for(i=0;i<c.rateCount;++i) {
        if(ScreamerRateCode(&c,c.rates[i],&code)!=kScreamerOK) return kScreamerUnsupported;
        for(j=0;j<i;++j) if(c.rates[i]==c.rates[j]) return kScreamerInvalid;
    }
    if(ScreamerRateCode(&c,44100,&code)!=kScreamerOK) return kScreamerUnresolved;
    b=prop(r,sound,"sound-objects");
    {
        ScreamerStatus status=ScreamerResolveProfile(b,c.machine,&c.profile);
        if(status!=kScreamerOK) return status;
    }
    *out=c;return kScreamerOK;
}
