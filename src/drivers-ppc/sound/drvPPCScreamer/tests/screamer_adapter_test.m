/* Run with the period Objective-C runtime; hardware is injected. */
#import "screamer_adapter_shim.h"
#import "../PPCScreamer.drvproj/PPCScreamer.lksproj/PPCScreamer.h"
#include "screamer_fixtures.h"
#include "../PPCScreamer.drvproj/PPCScreamer.lksproj/ScreamerTree.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static IOTreeDevice *treeNodes[5];
@implementation IOTreeDevice
+ findForIndex:(UInt32)i {return i<5?treeNodes[i]:nil;}
- parent {return parent;}
- propertyTable {return self;}
- getDevicePath:(char *)path maxLength:(int)length useAlias:(BOOL)alias
{ if(length<16) return nil;sprintf(path,"/node%u",node);return self; }
- (IOReturn)getProperty:(const char *)name flags:(unsigned long)flags value:(void **)value length:(ByteCount *)length
{
    ScreamerBytes b;
    ScreamerFixture *f=fixture;
    if(!f->reader.getProperty(f,node,name,&b)) return 1;
    *value=(void *)b.bytes;*length=b.length;return 0;
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
- (BOOL)_setParameter:(NXSoundParameterTag)t toInt:(int)v forObject:(id)o
{ if(t==NX_SoundStreamSamplingRate) {[o setSamplingRate:v];return YES;} return NO; }
- (int)_intValueForParameter:(NXSoundParameterTag)t forObject:(id)o {return -1;}
- (void)_getSupportedParameters:(NXSoundParameterTag *)p count:(unsigned int *)n forObject:(id)o {*n=0;}
- (BOOL)_getValues:(NXSoundParameterTag *)p count:(unsigned int *)n forParameter:(NXSoundParameterTag)t forObject:(id)o {*n=0;return NO;}
@end
@implementation TestStream
- init {rate=44100;return self;}
- (unsigned int)samplingRate {return rate;}
- (void)setSamplingRate:(unsigned int)v {rate=v;}
@end
@implementation TestLock
- lock {return self;}
- unlock {return self;}
@end

int main(void)
{
    ScreamerFixture f;
    ScreamerMachineConfig c;
    ScreamerCodec codec;
    PPCScreamer *a;
    TestStream *stream;
    NXSoundParameterTag values[64];
    unsigned int n,i,writes;
    int old;
    ScreamerTree tree;
    FixtureInit(&f);assert(ScreamerDiscover(&f.reader,3,&c)==kScreamerOK);
    for(i=0;i<5;++i) {treeNodes[i]=[IOTreeDevice new];treeNodes[i]->fixture=&f;treeNodes[i]->node=i+1;}
    treeNodes[3]->parent=treeNodes[2];
    /* A second, unrelated controller must never influence the candidate. */
    FixtureSetProperty(&f,5,"model","burgundy",9);
    assert(screamer_tree_description(&tree,treeNodes[2]));
    assert(tree.candidate==3);
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
    FixtureSetProperty(&f,4,"model","screamer",9);
    assert(screamer_tree_identity(&tree)==kScreamerIdentityConflict);
    FixtureCodecInit(&f,&codec);
    assert(ScreamerCodecInitialize(&codec,&c,5000)==kScreamerOK);
    a=[[PPCScreamer alloc] init];a->operationLock=[TestLock new];
    a->machineConfig=c;a->runtime.config=c;a->runtime.codec=codec;
    a->runtime.initialized=1;a->runtime.power=kScreamerPowerReady;
    a->runtime.routeKnown=1;a->runtime.applied.input=kScreamerInputLine;
    a->runtime.desired=a->runtime.applied;
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
    puts("Screamer adapter: format rejection, inherited dispatch, controls and readback passed");
    return 0;
}
