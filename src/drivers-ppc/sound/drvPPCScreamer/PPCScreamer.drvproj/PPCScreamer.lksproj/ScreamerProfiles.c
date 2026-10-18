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
    while(token(&r,&k)) {
        if(!token(&r,&v)) return 0;
        if(is(k,"model")) return is(v,name);
    }
    return 0;
}
ScreamerStatus ScreamerResolveProfile(ScreamerBytes objects,const char *machine,
    ScreamerProfile *out)
{
    ScreamerProfile p;
    ScreamerBytes record,kind,body;
    unsigned int pos,end,port,type,bits,dev,mask,match,param;
    unsigned int speaker=0,headphone=0,detect=0,inputs=0;
    if(!objects.bytes || !objects.length || objects.length>16384)
        return kScreamerUnresolved;
    memset(&p,0,sizeof(p)); pos=0;
    while(pos<objects.length) {
        for(end=pos;end<objects.length && objects.bytes[end];++end) {}
        if(end==objects.length || end==pos) return kScreamerInvalid;
        record.bytes=objects.bytes+pos; record.length=end-pos; pos=end+1;
        if(!token(&record,&kind)) return kScreamerInvalid;
        body=record;
        if(is(kind,"output")) {
            if(value(body,"port-connection",&port)!=1 ||
                value(body,"port-type",&type)!=1 || (port!=1 && port!=3))
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
            } else if(type==0x6864706eU || type==0x6c696e65U) {
                if(headphone++ || !model(body,"OutputPort")) return kScreamerUnsupported;
                p.headphonePort=port;
            } else return kScreamerUnsupported;
        } else if(is(kind,"input")) {
            if(!model(body,"InputPort") || value(body,"port-connection",&port)!=1 ||
                value(body,"port-type",&type)!=1 || port<1 || port>3)
                return kScreamerUnsupported;
            bits=port==1?0x800U:(port==2?0x400U:0x200U);
            if(type==0x696d6963U || type==0x656d6963U) dev=kScreamerInputMic;
            else if(type==0x6c696e65U) dev=kScreamerInputLine;
            else if(type==0x63642020U) dev=kScreamerInputCD;
            else return kScreamerUnsupported;
            if(p.inputBits[dev]) return kScreamerUnresolved;
            p.inputBits[dev]=bits; ++inputs;
        } else if(is(kind,"detect")) {
            if(value(body,"device",&dev)!=1 || dev!=2 ||
                value(body,"bit-mask",&mask)!=1 || !mask || (mask&~15U) ||
                value(body,"bit-match",&match)!=1 || (match&~mask))
                return kScreamerUnsupported;
            if(detect++) return kScreamerUnresolved;
            p.anySense=model(body,"AnyInSenseBitsDetect");
            if(!p.anySense && !model(body,"InSenseBitsDetect")) return kScreamerUnsupported;
            if(p.anySense && match) return kScreamerUnsupported;
            p.headphoneMask=mask; p.headphoneMatch=match;
        } else return kScreamerUnsupported;
    }
    if(speaker!=1 || headphone!=1 || detect!=1 || !inputs ||
        p.speakerPort==p.headphonePort) return kScreamerUnresolved;
    if((!strcmp(machine,"PowerMac3,1") || !strcmp(machine,"PowerMac3,2") ||
        !strcmp(machine,"PowerMac3,3")) &&
        (p.headphoneMask!=4 || p.headphoneMatch!=4 || p.anySense))
        return kScreamerInvalid;
    *out=p; return kScreamerOK;
}
