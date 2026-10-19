/* Run with the period Objective-C runtime; hardware is injected. */
#import "screamer_adapter_shim.h"
#import "../PPCScreamer.drvproj/PPCScreamer.lksproj/PPCScreamer.h"
#include "screamer_fixtures.h"
#include "../PPCScreamer.drvproj/PPCScreamer.lksproj/ScreamerTree.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static IOTreeDevice *treeNodes[5];
typedef struct {IOTreeDevice *parent;unsigned int next;} TestIterator;
int DTLookupEntry(const DTEntry start,const char *path,DTEntry *entry)
{*entry=(DTEntry)treeNodes[0];return kSuccess;}
int DTCreateEntryIterator(const DTEntry entry,DTEntryIterator *iterator)
{TestIterator *it=calloc(1,sizeof(*it));it->parent=(id)entry;*iterator=(DTEntryIterator)it;return kSuccess;}
int DTDisposeEntryIterator(DTEntryIterator iterator) {free(iterator);return kSuccess;}
int DTIterateEntries(DTEntryIterator iterator,DTEntry *entry)
{
    TestIterator *it=(TestIterator *)iterator;
    ScreamerFixture *f=it->parent->fixture;
    while(it->next<5) {
        IOTreeDevice *node=treeNodes[it->next++];
        if(f->parents[node->node]==it->parent->node) {*entry=(DTEntry)node;return kSuccess;}
    }
    *entry=0;return kIterationDone;
}
int DTGetProperty(const DTEntry entry,const char *name,void **value,int *length)
{
    IOTreeDevice *node=(id)entry;ScreamerBytes b;ScreamerFixture *f=node->fixture;
    if(!f->reader.getProperty(f,node->node,name,&b)) return kError;
    *value=(void *)b.bytes;*length=b.length;return kSuccess;
}
static unsigned int notifications,inputServices,outputServices;
static unsigned int negotiatedRate=44100,negotiatedEncoding=0,negotiatedChannels=2;
static ScreamerStatus test_platform(void *context,int ready) {return kScreamerOK;}
static unsigned long test_dma_read(void *context,unsigned long reg) {return 0;}
static void test_dma_write(void *context,unsigned long reg,unsigned long value) {}
static unsigned long test_dma_now(void *context) {return ((ScreamerFixture *)context)->now;}
static PPCDBDMAStatus test_dma_barrier(void *context) {return kPPCDBDMAOK;}
void IOSendInterrupt(void *identity,void *state,unsigned int message) {++notifications;}
@implementation IOTreeDevice
+ findForIndex:(UInt32)i {return i<3?treeNodes[i]:nil;}
- parent {return parent;}
- getRef {return self;}
- propertyTable {return self;}
- getDevicePath:(char *)path maxLength:(int)length useAlias:(BOOL)alias
{ if(length<16) return nil;sprintf(path,"/node%u",node);return self; }
- (IOReturn)getProperty:(const char *)name flags:(unsigned long)flags value:(void **)value length:(ByteCount *)length
{
    ScreamerBytes b;
    ScreamerFixture *f=fixture;
    if(!f->reader.getProperty(f,node,name,&b)) return 1;
    if(flags&kReferenceProperty) *value=(void *)b.bytes;
    else if(*length) memcpy(*value,b.bytes,*length<b.length?*length:b.length);
    *length=b.length;return 0;
}
@end

@implementation IOAudio
- init { input=[Object new];output=[Object new];rate=44100;return self; }
- _inputChannel {return input;}
- _outputChannel {return output;}
- (unsigned int)sampleRate {return rate;}
- (void)_setSampleRate:(unsigned int)v {rate=v;}
- (void)_setDataEncoding:(unsigned int)v {}
- (void)_setChannelCount:(unsigned int)v {}
- (BOOL)_attemptToStopDMAForChannel:(id)channel
{if(channel==input) ++inputServices;else if(channel==output) ++outputServices;return NO;}
- (BOOL)_attemptToStartDMAForChannel:(id)channel channelStatus:(BOOL)active
{
    [self _setSampleRate:negotiatedRate];[self _setDataEncoding:negotiatedEncoding];[self _setChannelCount:negotiatedChannels];
    return [self startDMAForChannel:0 read:NO buffer:0 bufferSizeForInterrupts:4096];
}
- (BOOL)_setParameter:(NXSoundParameterTag)t toInt:(int)v forObject:(id)o
{ if(t==NX_SoundStreamSamplingRate) {[o setSamplingRate:v];return YES;} return NO; }
- (int)_intValueForParameter:(NXSoundParameterTag)t forObject:(id)o {return -1;}
- (void)_getSupportedParameters:(NXSoundParameterTag *)p count:(unsigned int *)n forObject:(id)o {*n=0;}
- (BOOL)_getValues:(NXSoundParameterTag *)p count:(unsigned int *)n forParameter:(NXSoundParameterTag)t forObject:(id)o {*n=0;return NO;}
@end
@interface AdapterDevice : PPCScreamer
@end
@implementation AdapterDevice
- (BOOL)startDMAForChannel:(unsigned int)channel read:(BOOL)read buffer:(IODMABuffer)buffer bufferSizeForInterrupts:(unsigned int)period
{ return !formatRejected; }
@end
@implementation TestStream
- init {rate=44100;return self;}
- (unsigned int)samplingRate {return rate;}
- (void)setSamplingRate:(unsigned int)v {rate=v;}
@end
@implementation TestLock
- lock {assert(!held);held=1;return self;}
- unlock {assert(held);held=0;return self;}
- (void)acquire {}
- (void)release {}
@end

int main(void)
{
    unsigned char pcm[4]={0x12,0x34,0x01,0x00};
    ScreamerFixture f;
    ScreamerMachineConfig c;
    ScreamerCodec codec;
    ScreamerRuntimeOps ops;
    PPCScreamer *a;
    TestStream *stream;
    NXSoundParameterTag values[64];
    unsigned int n,i,writes;
    unsigned int level,argument,periods[2];
    IOInterruptHandler handler;
    int old;
    ScreamerTree tree;
    PMPowerState power;
    FixtureInit(&f);assert(ScreamerDiscover(&f.reader,3,&c)==kScreamerOK);
    for(i=0;i<5;++i) {treeNodes[i]=[IOTreeDevice new];treeNodes[i]->fixture=&f;treeNodes[i]->node=i+1;}
    /* Native parents are bus objects; the sound child is not published. */
    treeNodes[3]->parent=[Object new];
    /* A second, unrelated controller must never influence the candidate. */
    FixtureSetProperty(&f,5,"model","burgundy",9);
    f.parents[5]=1;
    assert(screamer_tree_description(&tree,treeNodes[2]));
    assert(tree.nodes[tree.candidate-1]==(DTEntry)treeNodes[2]);
    assert(screamer_tree_identity(&tree)==kScreamerIdentityScreamer);
    for(i=0;i<2;++i) {
        unsigned int owners=0,j;
        for(j=0;j<2;++j) {
            ScreamerIdentity identity=screamer_tree_identity(&tree);
            if((j^i)==0) owners+=identity==kScreamerIdentityScreamer;
            else owners+=identity!=kScreamerIdentityScreamer && identity!=kScreamerIdentityConflict;
        }
        assert(owners==1);
    }
    FixtureSetProperty(&f,4,"compatible","vendor,codec\0screamer",22);
    assert(screamer_tree_identity(&tree)==kScreamerIdentityScreamer);
    FixtureSetProperty(&f,4,"model","awacs",6);
    FixtureSetProperty(&f,4,"compatible","awacs",6);
    assert(screamer_tree_identity(&tree)==kScreamerIdentityOther);
    FixtureSetProperty(&f,4,"model","burgundy",9);
    FixtureSetProperty(&f,4,"compatible","screamer",9);
    assert(screamer_tree_identity(&tree)==kScreamerIdentityConflict);
    FixtureCodecInit(&f,&codec);
    assert(ScreamerCodecInitialize(&codec,&c,5000)==kScreamerOK);
    a=[[AdapterDevice alloc] init];a->operationLock=[TestLock new];a->interruptLock=[TestLock new];
    a->machineConfig=c;a->runtime.config=c;a->runtime.codec=codec;
    a->runtime.initialized=1;a->runtime.power=kScreamerPowerReady;
    a->runtime.clockRate=44100;
    a->runtime.routeKnown=1;a->runtime.applied.input=kScreamerInputLine;
    a->runtime.desired=a->runtime.applied;
    a->runtime.ops.codec=codec.ops;
    assert([a getHandler:&handler level:&level argument:&argument forInterrupt:0]);
    assert(level==IPLDEVICE && argument==(unsigned int)a);
    f.irqContext=1;f.regs[0]=0x7111;writes=f.writeCalls;
    ((void (*)(void *,void *,void *))handler)(0,0,a);
    assert(f.writeCalls==writes+1 && !f.irqViolations && notifications==1);
    assert([a getHandler:&handler level:&level argument:&argument forInterrupt:1]);
    ((void (*)(void *,void *,void *))handler)(0,0,a);
    assert(f.writeCalls==writes+1 && notifications==2);
    a->interruptClosing=1;
    ((void (*)(void *,void *,void *))handler)(0,0,a);
    assert(notifications==2 && f.writeCalls==writes+1);
    assert(![a getHandler:&handler level:&level argument:&argument forInterrupt:3]);
    a->interruptClosing=0;f.irqContext=0;
    a->runtime.streams[0].running=a->runtime.streams[1].running=1;
    periods[0]=1;periods[1]=2;[a screamerServicePeriods:periods];
    assert(inputServices==1 && outputServices==2);
    writes=f.writeCalls;
    assert([a _setParameter:NX_SoundDeviceAnalogInputSource toInt:NX_SoundDeviceCDIn forObject:[a _inputChannel]]==NO);
    assert(f.writeCalls==writes && a->runtime.applied.input==kScreamerInputLine);
    a->runtime.streams[1].running=0;
    assert([a _setParameter:NX_SoundDeviceAnalogInputSource toInt:NX_SoundDeviceCDIn forObject:[a _inputChannel]]==NO);
    assert(f.writeCalls==writes && a->runtime.desired.input==kScreamerInputLine);
    a->runtime.streams[0].running=a->runtime.streams[1].running=0;
    negotiatedRate=22050;negotiatedEncoding=3;
    assert(![a _attemptToStartDMAForChannel:[a _outputChannel] channelStatus:NO]);
    assert([a sampleRate]==44100 && a->runtime.clockRate==44100);
    negotiatedEncoding=0;negotiatedChannels=1;
    assert(![a _attemptToStartDMAForChannel:[a _outputChannel] channelStatus:NO] && [a sampleRate]==44100);
    negotiatedChannels=2;negotiatedRate=44100;
    assert([a _attemptToStartDMAForChannel:[a _outputChannel] channelStatus:NO]);
    stream=[TestStream new];
    assert([a _setParameter:NX_SoundStreamSamplingRate toInt:48000 forObject:stream]==NO);
    assert([stream samplingRate]==44100 && [a sampleRate]==44100);
    a->runtime.streams[0].running=1;a->runtime.streams[0].rate=44100;
    assert([a _setParameter:NX_SoundStreamSamplingRate toInt:22050 forObject:stream]==NO);
    assert([stream samplingRate]==44100 && [a sampleRate]==44100);
    a->runtime.streams[0].running=0;
    old=[a _intValueForParameter:NX_SoundDeviceAnalogInputSource forObject:[a _inputChannel]];
    writes=f.writeCalls;
    assert([a _setParameter:NX_SoundDeviceAnalogInputSource toInt:999 forObject:[a _inputChannel]]==NO);
    assert(f.writeCalls==writes);
    assert([a _intValueForParameter:NX_SoundDeviceAnalogInputSource forObject:[a _inputChannel]]==old);
    [a _getValues:values count:&n forParameter:NX_SoundDeviceAnalogInputSource forObject:[a _inputChannel]];
    assert(n==2 && values[0]==NX_SoundDeviceLineIn && values[1]==NX_SoundDeviceCDIn);
    [a _getSupportedParameters:values count:&n forObject:[a _inputChannel]];
    for(i=0;i<n;++i) assert(values[i]!=NX_SoundDeviceMicIn);
    old=[a _intValueForParameter:NX_SoundDeviceInputGainLeft forObject:[a _inputChannel]];
    f.failWrite=f.writeCalls+1;
    assert([a _setParameter:NX_SoundDeviceInputGainLeft toInt:16384 forObject:[a _inputChannel]]==NO);
    assert([a _intValueForParameter:NX_SoundDeviceInputGainLeft forObject:[a _inputChannel]]==old);
    FixtureCodecInit(&f,&codec);memset(&ops,0,sizeof(ops));ops.codec=codec.ops;ops.setPlatform=test_platform;
    for(i=0;i<2;++i) {
        ops.dma[i].context=&f;ops.dma[i].readRegister=test_dma_read;
        ops.dma[i].writeRegister=test_dma_write;ops.dma[i].now=test_dma_now;
        ops.dma[i].barrier=test_dma_barrier;
    }
    assert(ScreamerRuntimeInitialize(&a->runtime,&c,&ops,5000)==kScreamerOK);
    assert([a setPowerState:(PMPowerState)99]==IO_R_INVALID_ARG);
    assert([a getPowerState:&power]==IO_R_SUCCESS && power==PM_READY);
    assert([a setPowerState:PM_SUSPENDED]==IO_R_SUCCESS && a->interruptSuspended);
    assert([a getPowerState:&power]==IO_R_SUCCESS && power==PM_SUSPENDED);
    f.writeDelay=120;
    assert([a setPowerState:PM_READY]==IO_R_SUCCESS && !a->interruptSuspended);
    f.writeDelay=0;
    writes=f.writeCalls;
    assert([a setPowerState:PM_READY]==IO_R_SUCCESS && f.writeCalls==writes);
    f.failWrite=f.writeCalls+1;
    assert([a setPowerState:PM_SUSPENDED]==IO_R_IO);
    assert([a getPowerState:&power]==IO_R_SUCCESS && power==PM_READY);
    a->runtime.config.profile.phaseInversion=1;a->runtime.headphone=0;
    [a _processDMABuffer:pcm size:4 read:NO dataEncoding:NX_SoundStreamDataEncoding_Linear16 channelCount:2];
    assert(pcm[0]==0x12 && pcm[1]==0x34 && pcm[2]==0xff && pcm[3]==0);
    a->runtime.headphone=2;
    [a _processDMABuffer:pcm size:4 read:NO dataEncoding:NX_SoundStreamDataEncoding_Linear16 channelCount:2];
    assert(pcm[2]==0xff && pcm[3]==0);
    a->runtime.config.profile.monoMic=1;a->runtime.applied.input=kScreamerInputMic;
    /* setPowerState drains capture descriptors while holding this lock. */
    [a->operationLock lock];
    [a _processDMABuffer:pcm size:4 read:YES dataEncoding:NX_SoundStreamDataEncoding_Linear16 channelCount:2];
    [a->operationLock unlock];
    assert(pcm[2]==0x12 && pcm[3]==0x34);
    puts("Screamer adapter: format rejection, inherited dispatch, controls and readback passed");
    return 0;
}
