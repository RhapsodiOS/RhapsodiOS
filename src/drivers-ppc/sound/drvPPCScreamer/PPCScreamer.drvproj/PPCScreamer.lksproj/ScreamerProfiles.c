/* Copyright (c) 2026 RhapsodiOS Project. */
#include "ScreamerProfiles.h"
#include <string.h>
#include <limits.h>

static int token(ScreamerBytes *record, ScreamerBytes *word)
{
    unsigned int n;
    while (record->length && (record->bytes[0]==' ' || record->bytes[0]=='\t')) {
        ++record->bytes; --record->length;
    }
    if (!record->length) return 0;
    for (n=0; n<record->length && record->bytes[n]!=' ' &&
        record->bytes[n]!='\t'; ++n) {}
    word->bytes=record->bytes; word->length=n;
    record->bytes+=n; record->length-=n;
    return 1;
}
static int is(ScreamerBytes w,const char *s)
{
    return w.length==strlen(s) && !memcmp(w.bytes,s,w.length);
}
static int number(ScreamerBytes w,unsigned int *out)
{
    unsigned int i,v,d,base;
    i=v=0; base=10;
    if(w.length>2 && w.bytes[0]=='0' && w.bytes[1]=='x') {base=16;i=2;}
    if(i==w.length) return 0;
    for(;i<w.length;++i) {
        d=w.bytes[i];
        if(d>='0' && d<='9') d-='0';
        else if(d>='a' && d<='f') d=d-'a'+10;
        else if(d>='A' && d<='F') d=d-'A'+10;
        else return 0;
        if(d>=base || v>(UINT_MAX-d)/base) return 0;
        v=v*base+d;
    }
    *out=v; return 1;
}
static int value(ScreamerBytes r,const char *key,unsigned int *out)
{
    ScreamerBytes k,v;
    unsigned int matches=0;
    while(token(&r,&k)) {
        if(!token(&r,&v)) return -1;
        if(is(k,key)) {
            if(++matches>1 || !number(v,out)) return -1;
        }
    }
    return (int)matches;
}
static int model(ScreamerBytes r,const char *name)
{
    ScreamerBytes k,v;
    unsigned int count=0,matched=0;
    while(token(&r,&k)) {
        if(!token(&r,&v)) return 0;
        if(is(k,"model")) {if(++count>1) return 0;matched=(unsigned int)is(v,name);}
    }
    return count==1 && matched;
}
static unsigned int sense_bits(unsigned int bits)
{ return ((bits&1)<<3)|((bits&2)<<1)|((bits&4)>>1)|((bits&8)>>3); }
static int mic_mux(ScreamerBytes body,ScreamerProfile *p)
{
    ScreamerBytes key,word;
    unsigned int count=0,maps=0;
    if(p->micMuxMask || !model(body,"MuxProgOut") ||
        value(body,"source-map-count",&count)!=1 || count!=2) return 0;
    while(token(&body,&key)) {
        if(!token(&body,&word)) return 0;
        if(is(key,"source-map")) {
            /* Pismo's imic/modem map, as supplied by its firmware. Only
             * the analog microphone is exposed through the PCM interface. */
            if(++maps!=1 || !is(word,"696D696300000002000000006D6F646D0000000200000002")) return 0;
        }
    }
    if(maps!=1) return 0;
    p->micMuxMask=0x800U;p->micMuxValue=0;
    return 1;
}
ScreamerStatus ScreamerResolveProfile(ScreamerBytes objects,const char *machine,
    ScreamerProfile *out)
{
    ScreamerProfile p;
    ScreamerBytes record,kind,body;
    unsigned int pos,end,port,type,bits,dev,mask,match,param;
    unsigned int speaker=0,headphone=0,detect=0,inputs=0;
    unsigned int internalMic=0,muxedMic=0,external=0,speakerDetect=0;
    if(!objects.bytes || !objects.length || objects.length>16384)
        return kScreamerUnresolved;
    memset(&p,0,sizeof(p)); pos=0;
    while(pos<objects.length) {
        for(end=pos;end<objects.length && objects.bytes[end];++end) {}
        if(end==objects.length) return kScreamerInvalid;
        if(end==pos) {
            for(;pos<objects.length;++pos) if(objects.bytes[pos]) return kScreamerInvalid;
            break;
        }
        record.bytes=objects.bytes+pos; record.length=end-pos; pos=end+1;
        if(!token(&record,&kind)) return kScreamerInvalid;
        body=record;
        if(is(kind,"output")) {
            int haveMask=value(body,"device-mask",&mask);
            int haveMatch=value(body,"device-match",&match);
            if(haveMask<0 || haveMatch<0 || haveMask!=haveMatch) return kScreamerInvalid;
            if(value(body,"port-connection",&port)!=1 ||
                value(body,"port-type",&type)!=1 || (port!=1 && port!=2))
                return kScreamerUnsupported;
            if(type==0x6973706bU) {
                if(speaker++) return kScreamerUnresolved;
                p.speakerPort=port;
                if(model(body,"OutputPort")) p.speakerKind=0;
                else if(model(body,"Proj5Speaker")) p.speakerKind=5;
                else return kScreamerUnsupported;
                param=0;
                if(value(body,"param",&param)<0) return kScreamerInvalid;
                if(param>1) return kScreamerUnsupported;
                p.speakerParam=param;
                if(haveMask && (p.speakerKind==5 ? (mask!=3 || match!=3) :
                    ((mask!=2 && (strcmp(machine,"PowerBook1,1") || mask!=6)) || match!=0)))
                    return kScreamerUnsupported;
            } else if(type==0x6864706eU || type==0x6c696e65U || type==0x6573706bU) {
                if(headphone++ || !model(body,"OutputPort")) return kScreamerUnsupported;
                p.headphonePort=port;
                if(haveMask && (mask!=(type==0x6573706bU?6U:2U) ||
                    match!=(type==0x6573706bU?4U:2U))) return kScreamerUnsupported;
            } else return kScreamerUnsupported;
        } else if(is(kind,"input")) {
            if(model(body,"NoInput")) continue;
            if(value(body,"port-connection",&port)!=1 ||
                value(body,"port-type",&type)!=1) return kScreamerUnsupported;
            if(model(body,"NoRecordInput") && port==4 && type==0x70636d20U) continue;
            if((!model(body,"InputPort") && !model(body,"ExternalMic") && !model(body,"SoundIn") &&
                !model(body,"MonoMic") && !model(body,"InternalMic") &&
                !model(body,"IntMicMuxedInput") && !model(body,"MuxedInput") &&
                !model(body,"MuxedAnalogCD") && !model(body,"MuxedIntModemInput")) || port<1 || port>3)
                return kScreamerUnsupported;
            bits=port==1?0x800U:(port==2?0x400U:0x200U);
            if(type==0x696d6963U || type==0x656d6963U) dev=kScreamerInputMic;
            else if(type==0x6c696e65U || type==0x73696e6aU) dev=kScreamerInputLine;
            else if(type==0x63642020U || (type==0x6d626179U && model(body,"MuxedAnalogCD"))) dev=kScreamerInputCD;
            else if(type==0x6d6f646dU || type==0x7a767063U) continue;
            else return kScreamerUnsupported;
            if(type==0x696d6963U) {
                if(internalMic++) return kScreamerUnresolved;
                p.monoMic=1;
                muxedMic=model(body,"IntMicMuxedInput");
            } else if(dev==kScreamerInputMic && internalMic) continue;
            if(p.inputBits[dev] && type!=0x696d6963U) return kScreamerUnresolved;
            p.inputBits[dev]=bits; ++inputs;
            if(model(body,"IntMicMuxedInput") || model(body,"MuxedAnalogCD")) p.muxInputs|=1U<<dev;
        } else if(is(kind,"detect")) {
            unsigned int any=model(body,"AnyInSenseBitsDetect");
            int haveMatch=value(body,"bit-match",&match);
            if(!haveMatch) match=0;
            if(value(body,"device",&dev)!=1 ||
                value(body,"bit-mask",&mask)!=1 || !mask || (mask&~15U) ||
                haveMatch<0 || (!any && haveMatch!=1) || (match&~mask))
                return kScreamerUnsupported;
            if(dev==16 || dev==32) {
                if(!model(body,"InSenseBitsDetect")) return kScreamerUnsupported;
                continue; /* Input presence is not an output routing request. */
            }
            if(dev==1 || dev==4) {
                if(!model(body,"InSenseBitsDetect") || mask!=14 ||
                    match!=(dev==1?0U:8U)) return kScreamerUnsupported;
                if(dev==1) {if(speakerDetect++) return kScreamerInvalid;}
                else {if(external++) return kScreamerInvalid;}
                continue;
            }
            if(dev!=2) return kScreamerUnsupported;
            if(detect++) return kScreamerUnresolved;
            p.anySense=any;
            if(!p.anySense && !model(body,"InSenseBitsDetect")) return kScreamerUnsupported;
            if(p.anySense && match) return kScreamerUnsupported;
            p.headphoneMask=sense_bits(mask); p.headphoneMatch=sense_bits(match);
        } else if(is(kind,"init")) {
            if(p.initOutput || value(body,"operation",&type)!=1 || type!=2 ||
                value(body,"param",&param)!=1 || param!=1 ||
                value(body,"param-size",&bits)!=1 || bits!=4) return kScreamerUnsupported;
            p.initOutput=1;
        } else if(is(kind,"feature")) {
            if(model(body,"Proj7PowerControl")) {if(p.powerKind) return kScreamerInvalid;p.powerKind=7;}
            else if(model(body,"Proj10PowerControl")) {if(p.powerKind) return kScreamerInvalid;p.powerKind=10;}
            else if(model(body,"Proj6PowerControl")) {if(p.powerKind) return kScreamerInvalid;p.powerKind=6;}
            else if(model(body,"PhaseInversion")) {
                if(p.phaseInversion || value(body,"port-channels",&bits)!=1 || bits!=2) return kScreamerUnsupported;
                p.phaseInversion=1;
            }
            else if(!model(body,"USBSubwoofer") && !model(body,"NotifySSprockets")) return kScreamerUnsupported;
        } else if(is(kind,"mux")) {
            if(model(body,"Proj9Mux")) {
                if(p.muxKind || p.micMuxMask || strcmp(machine,"PowerBook1,1")) return kScreamerUnsupported;
                p.muxKind=9;
            } else if(p.muxKind || !mic_mux(body,&p)) return kScreamerUnsupported;
        } else return kScreamerUnsupported;
    }
    if(speaker!=1 || headphone!=1 || detect!=1 || !inputs ||
        p.speakerPort==p.headphonePort) return kScreamerUnresolved;
    if(muxedMic!=0 && !p.micMuxMask && p.muxKind!=9) return kScreamerUnresolved;
    if(p.micMuxMask && !muxedMic) return kScreamerUnresolved;
    if(external || speakerDetect) {
        if(external!=1 || speakerDetect!=1 || p.speakerKind!=5 ||
            !p.anySense || p.headphoneMask!=6 || p.speakerPort!=2 ||
            p.headphonePort!=1) return kScreamerUnresolved;
        p.frontMask=6;p.headphoneMask=7;
    }
    if(p.speakerKind==5 && !p.frontMask) return kScreamerUnresolved;
    if(p.speakerKind==5 && ((!strcmp(machine,"PowerMac2,1") && p.speakerParam!=0) ||
        ((!strcmp(machine,"PowerMac2,2") || !strcmp(machine,"PowerMac4,1")) && p.speakerParam!=1)))
        return kScreamerInvalid;
    if(p.powerKind==10 && p.initOutput) return kScreamerUnsupported;
    if(p.muxKind==9 && (p.powerKind!=6 || !muxedMic)) return kScreamerUnresolved;
    if((!strcmp(machine,"PowerMac3,1") || !strcmp(machine,"PowerMac3,2") ||
        !strcmp(machine,"PowerMac3,3")) &&
        (p.headphoneMask!=4 || p.headphoneMatch!=4 || p.anySense))
        return kScreamerInvalid;
    *out=p; return kScreamerOK;
}
void ScreamerLombardProfile(ScreamerProfile *p)
{
    /* Apple's PowerBook1,1 DeviceTreeUpdater personality supplies the
     * routing absent from its BootROM. Applicability is checked by discovery. */
    memset(p,0,sizeof(*p));
    p->headphoneMask=p->headphoneMatch=8;
    p->speakerPort=2;p->headphonePort=1;p->powerKind=6;
    p->inputBits[kScreamerInputMic]=0x800U;
    p->inputBits[kScreamerInputLine]=0x400U;
    p->inputBits[kScreamerInputCD]=0x200U;
    p->monoMic=1;p->muxKind=9;
    p->muxInputs=(1U<<kScreamerInputMic)|(1U<<kScreamerInputCD);
    p->source=1;
}
