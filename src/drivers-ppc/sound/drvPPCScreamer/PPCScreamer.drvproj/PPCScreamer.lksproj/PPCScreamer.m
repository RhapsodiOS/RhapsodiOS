/* Copyright (c) 2026 RhapsodiOS Project. */
#import "PPCScreamer.h"
#include "TASTime.h"
#include "ScreamerPCM.h"
#include <string.h>
#include <limits.h>
#include <bsd/dev/audioTypes.h>
#ifndef SCREAMER_ADAPTER_TEST
#import <driverkit/IOAudioPrivate.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/KernLock.h>
#import <machkit/NXLock.h>
#import <driverkit/ppc/IODBDMA.h>
#import <machdep/ppc/PEDAVBus.h>
#import <machdep/ppc/pmap.h>
#import <vm/vm_kern.h>
#import <kernserv/ns_timer.h>
#include "ScreamerTree.h"
extern msg_return_t msg_send_from_kernel(msg_header_t *,msg_option_t,msg_timeout_t);
@interface Object (ScreamerAudioChannel)
- (BOOL)isRead;
- (void)freeDescriptors;
@end

static NXLock *ownerLock;
static PPCScreamer *owner;
static unsigned long nextToken;
static void screamer_poll(void *argument);
static void screamer_arm_locked(PPCScreamer *self,unsigned long ms)
{
    if(owner!=self || self->interruptClosing || self->interruptSuspended || nextToken==~0UL) return;
    if(self->timerToken) (void)ns_untimeout((func)screamer_poll,(void *)self->timerToken);
    self->timerToken=++nextToken;
    ns_timeout((func)screamer_poll,(void *)self->timerToken,(ns_time_t)ms*1000000UL,CALLOUT_PRI_THREAD);
}
static void screamer_arm(PPCScreamer *self,unsigned long ms)
{ [ownerLock lock];screamer_arm_locked(self,ms);[ownerLock unlock]; }
static unsigned long screamer_now(void *context)
{
    ns_time_t time;
    (void)context;IOGetTimestamp(&time);
    return TASTimeNormalize((unsigned long)(time/1000000UL));
}
static unsigned long screamer_deadline(PPCScreamer *self)
{
    unsigned long deadline=screamer_now(self);
    (void)TASTimeAdd(deadline,5000,&deadline);return deadline;
}
static void screamer_sleep(void *context,unsigned long ms)
{ (void)context;IOSleep((unsigned int)ms); }
static void screamer_barrier(void *context) {(void)context;__asm__ volatile("sync");eieio();}
static ScreamerStatus screamer_read(void *context,unsigned int offset,unsigned int *value)
{
    PPCScreamer *self=context;
    if(!self->registers[0] || offset>0x40 || (offset&3)) return kScreamerInvalid;
    *value=ReadSwap32(self->registers[0],offset);eieio();return kScreamerOK;
}
static ScreamerStatus screamer_irq_write(void *context,unsigned int offset,unsigned int value)
{
    PPCScreamer *self=context;
    if(!self->registers[0] || offset>0x40 || (offset&3)) return kScreamerInvalid;
    WriteSwap32(self->registers[0],offset,value);eieio();return kScreamerOK;
}
static ScreamerStatus screamer_write(void *context,unsigned int offset,unsigned int value)
{
    PPCScreamer *self=context;
    ScreamerStatus status;
    if(offset==0) [self->interruptLock acquire];
    status=screamer_irq_write(context,offset,value);
    if(offset==0) [self->interruptLock release];
    return status;
}
static ScreamerStatus screamer_platform(void *context,int enabled)
{
    PPCScreamer *self=context;
    return PEDAVBusSetState(self->machineConfig.controllerBase,
        enabled?kPEDAVBusReady:kPEDAVBusOff)==KERN_SUCCESS?kScreamerOK:kScreamerIOError;
}
static ScreamerStatus screamer_amplifier(void *context,int enabled)
{
    PPCScreamer *self=context;
    return PEDAVBusSetAmplifier(self->machineConfig.controllerBase,(unsigned int)enabled)==KERN_SUCCESS?kScreamerOK:kScreamerIOError;
}
static ScreamerStatus screamer_input_mux(void *context,unsigned int value)
{
    PPCScreamer *self=context;
    return PEDAVBusSetInputMux(self->machineConfig.controllerBase,value)==KERN_SUCCESS?kScreamerOK:kScreamerIOError;
}
static PPCDBDMAStatus screamer_translate(void *context,const void *address,
    unsigned long *physical,unsigned long *contiguous)
{
    vm_offset_t result;
    (void)context;
    if(IOPhysicalFromVirtual(IOVmTaskSelf(),(vm_offset_t)address,&result)!=IO_R_SUCCESS)
        return kPPCDBDMAUnmappable;
    *physical=result;*contiguous=PAGE_SIZE-((unsigned long)address&(PAGE_SIZE-1));
    return kPPCDBDMAOK;
}
static unsigned long screamer_dma_read(void *context,unsigned long reg)
{ return reg==kPPCDBDMARegStatus?IOGetDBDMAChannelStatus((IODBDMAChannelRegisters *)context):0; }
static void screamer_dma_write(void *context,unsigned long reg,unsigned long value)
{
    if(reg==kPPCDBDMARegControl) {IOSetDBDMAChannelControl((IODBDMAChannelRegisters *)context,value);}
    else if(reg==kPPCDBDMARegCommandPtr) {IOSetDBDMACommandPtr((IODBDMAChannelRegisters *)context,value);}
}
static int screamer_ring_address(PPCScreamer *self,void *address,unsigned long bytes)
{
    unsigned int i;
    unsigned long base,a=(unsigned long)address;
    for(i=0;i<2;++i) {
        base=(unsigned long)self->ringPages[i];
        if(base && a>=base && a-base<PAGE_SIZE && bytes<=PAGE_SIZE-(a-base)) return 1;
    }
    return 0;
}
static PPCDBDMAStatus screamer_publish(void *context,void *address,unsigned long bytes)
{
    if(!screamer_ring_address(context,address,bytes)) flush_cache_v((vm_offset_t)address,bytes);
    screamer_barrier(context);return kPPCDBDMAOK;
}
static PPCDBDMAStatus screamer_invalidate(void *context,void *address,unsigned long bytes)
{
    if(!screamer_ring_address(context,address,bytes)) invalidate_cache_v((vm_offset_t)address,bytes);
    screamer_barrier(context);return kPPCDBDMAOK;
}
static PPCDBDMAStatus screamer_dma_barrier(void *context)
{ screamer_barrier(context);return kPPCDBDMAOK; }

static int ScreamerReadDescription(id description,ScreamerMachineConfig *config)
{
    ScreamerTree tree;
    ScreamerPropertyReader reader;
    ScreamerDeliveredResources delivered;
    IORange *ranges;
    unsigned int *interrupts,i;
    PEDAVBusInfo info;
    if(!screamer_tree_description(&tree,description) ||
        screamer_tree_identity(&tree)!=kScreamerIdentityScreamer ||
        [description numMemoryRanges]!=3 || [description numInterrupts]!=3) return 0;
    ranges=[description memoryRangeList];interrupts=[description interruptList];
    if(!ranges || !interrupts) return 0;
    memset(&delivered,0,sizeof(delivered));delivered.rangeCount=delivered.interruptCount=3;
    /* IOTreeDevice applies the historical bit-number XOR after PE mapping. */
    delivered.interruptXor=0x18U;
    for(i=0;i<3;++i) {
        delivered.ranges[i].address=ranges[i].start;delivered.ranges[i].length=ranges[i].size;
        delivered.interrupts[i]=interrupts[i];
    }
    reader.context=&tree;reader.nodeCount=tree.count;reader.getProperty=screamer_tree_property;
    reader.getParent=screamer_tree_parent;reader.delivered=&delivered;
    if(ScreamerDiscover(&reader,tree.candidate,config)!=kScreamerOK) return 0;
    return PEDAVBusGetInfo(config->controllerBase,&info)==KERN_SUCCESS && info.family==config->platformFamily &&
        ((config->profile.powerKind!=7 && config->profile.powerKind!=10) || (info.capabilities&kPEDAVBusAmplifierGPIO)) &&
        (config->profile.muxKind!=9 || (info.capabilities&kPEDAVBusInputMux));
}

static void screamer_poll(void *argument)
{
    unsigned long token=(unsigned long)argument;
    msg_header_t message;
    [ownerLock lock];
    if(owner && token==owner->timerToken && !owner->interruptClosing && !owner->interruptSuspended) {
        memset(&message,0,sizeof(message));message.msg_size=sizeof(message);
        message.msg_remote_port=IOConvertPort([owner interruptPort],IO_KernelIOTask,IO_Kernel);
        message.msg_id=IO_DEVICE_INTERRUPT_MSG;
        (void)msg_send_from_kernel(&message,SEND_TIMEOUT,0);
        screamer_arm_locked(owner,250);
    }
    [ownerLock unlock];
}
#else
static unsigned long screamer_deadline(PPCScreamer *self)
{ unsigned long d=self->runtime.codec.ops.nowMS(self->runtime.codec.ops.context);TASTimeAdd(d,5000,&d);return d; }
#endif
static void screamer_irq(void *identity,void *state,void *argument,unsigned int local)
{
    PPCScreamer *self=argument;
    ScreamerRuntimeOps ops=self->runtime.ops;
    [self->interruptLock acquire];
    if(!self->interruptClosing && !self->interruptSuspended) {
#ifndef SCREAMER_ADAPTER_TEST
        ops.codec.writeLE32=screamer_irq_write;
#endif
        (void)ScreamerAcknowledgeInterrupt(&ops,local,&self->pendingIRQs);
        IOSendInterrupt(identity,state,IO_DEVICE_INTERRUPT_MSG);
    }
    [self->interruptLock release];
}
static void screamer_codec_irq(void *i,void *s,void *a) {screamer_irq(i,s,a,0);}
static void screamer_output_irq(void *i,void *s,void *a) {screamer_irq(i,s,a,1);}
static void screamer_input_irq(void *i,void *s,void *a) {screamer_irq(i,s,a,2);}

static int screamer_input(NXSoundParameterTag tag,ScreamerInput *input)
{
    if(tag==NX_SoundDeviceMicIn || tag==NX_SoundDeviceAnalogInputSource_Microphone) *input=kScreamerInputMic;
    else if(tag==NX_SoundDeviceLineIn || tag==NX_SoundDeviceAnalogInputSource_LineIn) *input=kScreamerInputLine;
    else if(tag==NX_SoundDeviceCDIn) *input=kScreamerInputCD;
    else return 0;
    return 1;
}
static NXSoundParameterTag screamer_input_tag(ScreamerInput input)
{ return input==kScreamerInputMic?NX_SoundDeviceMicIn:(input==kScreamerInputLine?NX_SoundDeviceLineIn:NX_SoundDeviceCDIn); }

@implementation PPCScreamer
- (void)_processDMABuffer:(void *)buffer size:(unsigned int)bytes
    read:(BOOL)read dataEncoding:(NXSoundParameterTag)encoding channelCount:(unsigned int)count
{
    unsigned int invert,mono;
    volatile ScreamerRuntime *state=&runtime;
    if(encoding!=NX_SoundStreamDataEncoding_Linear16 || count!=2) return;
    /* Queue drains can call with operationLock held. The profile is immutable;
     * committed route/input are aligned word snapshots. Live input changes
     * are refused, and an output period may use either side of a jack change. */
    invert=!read && runtime.config.profile.phaseInversion && state->headphone==0;
    mono=read && runtime.config.profile.monoMic && state->applied.input==kScreamerInputMic;
    (void)ScreamerPCMCorrect(buffer,bytes,invert,mono);
}
#ifndef SCREAMER_ADAPTER_TEST
+ initialize
{ if(self==[PPCScreamer class] && ownerLock==nil) ownerLock=[NXLock new];return [super initialize]; }
+ (BOOL)probe:(IODeviceDescription *)description
{
    ScreamerMachineConfig config;
    PPCScreamer *instance;
    if(!ScreamerReadDescription(description,&config)) return NO;
    [ownerLock lock];
    if(owner || nextToken==~0UL) {[ownerLock unlock];return NO;}
    instance=[self alloc];
    if(!instance) {[ownerLock unlock];return NO;}
    owner=instance;instance->machineConfig=config;
    [ownerLock unlock];
    instance->operationLock=[NXLock new];instance->interruptLock=[[KernLock alloc] initWithLevel:7];
    if(!instance->operationLock || !instance->interruptLock) {[instance free];return NO;}
    /* IOAudio can publish worker threads before returning failure. */
    instance->ioAudioPublished=1;
    if([instance initFromDeviceDescription:description]==nil) {[instance free];return NO;}
    screamer_arm(instance,250);
    return YES;
}
- (BOOL)reset
{
    ScreamerRuntimeOps ops;
    unsigned int i,index;
    vm_offset_t page,physical;
    if(runtime.initialized || interruptClosing) return NO;
    memset(&ops,0,sizeof(ops));ops.context=self;ops.setPlatform=screamer_platform;ops.setAmplifier=screamer_amplifier;
    ops.setInputMux=screamer_input_mux;
    ops.codec.context=self;ops.codec.readLE32=screamer_read;ops.codec.writeLE32=screamer_write;
    ops.codec.nowMS=screamer_now;ops.codec.sleepMS=screamer_sleep;ops.codec.barrier=screamer_barrier;
    for(i=0;i<3;++i) {
        if([self mapMemoryRange:i to:(vm_address_t *)&registers[i] findSpace:YES cache:IO_CacheOff]!=IO_R_SUCCESS) return NO;
        ++mapped;
    }
    for(i=0;i<2;++i) {
        page=0;
        if(kmem_alloc_wired(kernel_map,&page,PAGE_SIZE)!=KERN_SUCCESS) return NO;
        ringPages[i]=(void *)page;physical=pmap_extract(kernel_pmap,page);
        if(!physical || (physical&(PAGE_SIZE-1)) ||
            physical>~0UL-(PAGE_SIZE-1) ||
            pmap_extract(kernel_pmap,page+PAGE_SIZE-1)!=physical+PAGE_SIZE-1) return NO;
        if(!pmap_set_cache_spec(kernel_pmap,page,cache_disable)) return NO;
        scratch[i]=IOMalloc(PAGE_SIZE+15);
        if(!scratch[i]) return NO;
        ops.storage[i].logical=(void *)page;ops.storage[i].physical=physical;ops.storage[i].bytes=PAGE_SIZE;
        ops.storage[i].scratch=(void *)(((unsigned long)scratch[i]+15)&~15UL);ops.storage[i].scratchBytes=PAGE_SIZE;
        index=i==kScreamerStreamInput?2:1;
        ops.dma[i].context=self;ops.dma[i].translate=screamer_translate;ops.dma[i].registerContext=registers[index];
        ops.dma[i].readRegister=screamer_dma_read;ops.dma[i].writeRegister=screamer_dma_write;
        ops.dma[i].now=screamer_now;ops.dma[i].coherencyContext=self;
        ops.dma[i].publish=screamer_publish;ops.dma[i].invalidate=screamer_invalidate;ops.dma[i].barrier=screamer_dma_barrier;
    }
    if(ScreamerRuntimeInitialize(&runtime,&machineConfig,&ops,screamer_deadline(self))!=kScreamerOK) return NO;
    [self setDeviceKind:"PPCScreamer"];[self setUnit:0];[self setName:"PPCScreamer0"];
    for(i=0;i<3;++i) if([self enableInterrupt:i]!=IO_R_SUCCESS) return NO;
    return YES;
}
- free
{
    unsigned int i;
    [interruptLock acquire];interruptClosing=1;[interruptLock release];
    [ownerLock lock];
    if(timerToken) (void)ns_untimeout((func)screamer_poll,(void *)timerToken);
    timerToken=0;[ownerLock unlock];
    [operationLock lock];
    if(runtime.initialized) {
        if(ScreamerBeginClose(&runtime,screamer_deadline(self))!=kScreamerOK) {
            [operationLock unlock];return self;
        }
    }
    [operationLock unlock];
    for(i=0;i<3;++i) [self disableInterrupt:i];
    if(ioAudioPublished) {IOLog("PPCScreamer: quiesced; retaining IOAudio worker resources\n");return self;}
    for(i=0;i<2;++i) {
        if(ringPages[i]) {
            if(!pmap_set_cache_spec(kernel_pmap,(vm_offset_t)ringPages[i],cache_default)) return self;
            kmem_free(kernel_map,(vm_offset_t)ringPages[i],PAGE_SIZE);
            ringPages[i]=0;
        }
        if(scratch[i]) IOFree(scratch[i],PAGE_SIZE+15);
    }
    while(mapped) {--mapped;[self unmapMemoryRange:mapped from:(vm_address_t)registers[mapped]];}
    [ownerLock lock];if(owner==self) owner=nil;[ownerLock unlock];
    [operationLock free];[interruptLock free];return [super free];
}
#endif
- (BOOL)getHandler:(IOInterruptHandler *)handler level:(unsigned int *)level
    argument:(unsigned int *)argument forInterrupt:(unsigned int)interrupt
{
    if(interrupt>2) return NO;
    *handler=(IOInterruptHandler)(interrupt==0?screamer_codec_irq:
        (interrupt==1?screamer_output_irq:screamer_input_irq));
    *level=IPLDEVICE;*argument=(unsigned int)self;return YES;
}
#ifndef SCREAMER_ADAPTER_TEST
- (BOOL)startDMAForChannel:(unsigned int)channel read:(BOOL)read
    buffer:(IODMABuffer)buffer bufferSizeForInterrupts:(unsigned int)period
{
    void *address;unsigned int bytes;ScreamerStatus status;
    (void)channel;
    if(formatRejected || [self dataEncoding]!=NX_SoundStreamDataEncoding_Linear16 || [self channelCount]!=2) return NO;
    if(read) [self getInputChannelBuffer:&address size:&bytes];
    else [self getOutputChannelBuffer:&address size:&bytes];
    if(address!=buffer) return NO;
    [operationLock lock];
    status=ScreamerStart(&runtime,read?kScreamerStreamInput:kScreamerStreamOutput,
        buffer,bytes,period,[self sampleRate],screamer_deadline(self));
    [operationLock unlock];return status==kScreamerOK;
}
- (void)stopDMAForChannel:(unsigned int)channel read:(BOOL)read
{
    (void)channel;[operationLock lock];
    if(ScreamerStop(&runtime,read?kScreamerStreamInput:kScreamerStreamOutput,screamer_deadline(self))!=kScreamerOK)
        IOLog("PPCScreamer: DMA stop failed; retaining buffers\n");
    [operationLock unlock];
}
- (BOOL)isInputActive {return runtime.streams[kScreamerStreamInput].running!=0;}
- (BOOL)isOutputActive {return runtime.streams[kScreamerStreamOutput].running!=0;}
- (BOOL)_channelWillAddStream {return !runtime.closing && !runtime.faulted && runtime.power==kScreamerPowerReady;}
- (void)_stopDMAForChannel:(id)channel
{
    ScreamerStatus status;
    [operationLock lock];
    status=ScreamerStop(&runtime,[channel isRead]?kScreamerStreamInput:kScreamerStreamOutput,screamer_deadline(self));
    [operationLock unlock];
    if(status!=kScreamerOK) {IOLog("PPCScreamer: retaining queued descriptors after stop failure\n");return;}
    [channel freeDescriptors];
    if([channel isRead]) [self _setInputActive:NO];else [self _setOutputActive:NO];
    if(![self isInputActive] && ![self isOutputActive]) [self _setTimeout:IOAUDIO_MAXIMUM_TIMEOUT];
}
- (IOAudioInterruptClearFunc)interruptClearFunc {return 0;}
/* The generic implementation blocks a second channel while the first runs. */
- (void)_dataPendingOccurred:(id)channel
{
    if(([channel isRead] && [self isInputActive]) ||
        (![channel isRead] && [self isOutputActive])) return;
    (void)[self _attemptToStartDMAForChannel:channel
        channelStatus:([self isInputActive] || [self isOutputActive])];
}
- (void)_interruptOccurred
{
    unsigned int periods[2],sense,confirm,pending;ScreamerStatus status;
    [operationLock lock];
    if(runtime.closing || runtime.power!=kScreamerPowerReady) {[operationLock unlock];return;}
    [interruptLock acquire];pending=pendingIRQs;pendingIRQs=0;[interruptLock release];
    status=screamer_read(self,0x20,&sense);
    if(status==kScreamerOK) (void)ScreamerObserveJack(&runtime,sense,screamer_now(self),runtime.generation);
    confirm=runtime.jackCandidateValid && TASTimeBefore(screamer_now(self),runtime.jackDeadline);
    status=ScreamerServiceInterrupt(&runtime,pending,screamer_deadline(self),periods);
    [operationLock unlock];
    if(confirm) screamer_arm(self,5);
    if(status!=kScreamerOK) return;
    [self screamerServicePeriods:periods];
}
- (void)interruptOccurredForInput:(BOOL *)input forOutput:(BOOL *)output
{ *input=NO;*output=NO; /* Period counts are handled in _interruptOccurred. */ }
- (void)timeoutOccurred {[self _interruptOccurred];}
#endif
- (void)screamerServicePeriods:(unsigned int *)periods
{
    unsigned int i,j;
    for(i=0;i<2;++i) for(j=0;j<periods[i];++j) {
        id channel=i==kScreamerStreamInput?[self _inputChannel]:[self _outputChannel];
        if(!runtime.streams[i].running) break;
        (void)[self _attemptToStopDMAForChannel:channel];
    }
}
- (BOOL)_attemptToStartDMAForChannel:(id)channel channelStatus:(BOOL)active
{
    unsigned int previous=[self sampleRate];
    BOOL started;
    formatRejected=0;
    started=[super _attemptToStartDMAForChannel:channel channelStatus:active];
    if(!started) [super _setSampleRate:previous];
    return started;
}

- (IOReturn)getPowerState:(PMPowerState *)state
{
    if(!state) return IO_R_INVALID_ARG;
    [operationLock lock];*state=currentPowerState;[operationLock unlock];return IO_R_SUCCESS;
}
- (IOReturn)setPowerState:(PMPowerState)state
{
    ScreamerStatus status;
    unsigned int i;
    if(state!=PM_READY && state!=PM_STANDBY && state!=PM_SUSPENDED && state!=PM_OFF) return IO_R_INVALID_ARG;
    [operationLock lock];
    [interruptLock acquire];interruptSuspended=1;[interruptLock release];
#ifndef SCREAMER_ADAPTER_TEST
    for(i=0;i<3;++i) [self disableInterrupt:i];
    [ownerLock lock];
    if(timerToken) (void)ns_untimeout((func)screamer_poll,(void *)timerToken);
    timerToken=0;[ownerLock unlock];
#else
    (void)i;
#endif
    status=ScreamerSetPower(&runtime,(ScreamerPowerState)state,screamer_deadline(self));
    if(status==kScreamerOK) {
        currentPowerState=state;
#ifndef SCREAMER_ADAPTER_TEST
        if(state!=PM_READY) {
            /* IOAudio exposes no queue-position/lifetime token for resume.
             * Clients restart queues; saved DMA pointers cannot prove that
             * the next framework descriptor is buffer zero. */
            [[self _inputChannel] freeDescriptors];[[self _outputChannel] freeDescriptors];
            [self _setInputActive:NO];[self _setOutputActive:NO];
        }
#endif
    }
    if(status==kScreamerOK && state==PM_READY) {
        [interruptLock acquire];interruptSuspended=0;[interruptLock release];
#ifndef SCREAMER_ADAPTER_TEST
        for(i=0;i<3;++i) [self enableInterrupt:i];
        screamer_arm(self,250);
#endif
    }
    [operationLock unlock];return status==kScreamerOK?IO_R_SUCCESS:IO_R_IO;
}
- (IOReturn)getPowerManagement:(PMPowerManagementState *)state
{ if(!state) return IO_R_INVALID_ARG;*state=PM_ENABLED;return IO_R_SUCCESS; }
- (IOReturn)setPowerManagement:(PMPowerManagementState)state
{ return state==PM_ENABLED || state==PM_DISABLED?IO_R_SUCCESS:IO_R_INVALID_ARG; }
- (BOOL)_setParameter:(NXSoundParameterTag)tag toInt:(int)value forObject:(id)object
{
    ScreamerControls controls;
    ScreamerStatus status;
    ScreamerInput input;
    unsigned int code;
    int handled=1;
    [operationLock lock];controls=runtime.desired;
    if(object==[self _inputChannel]) {
        switch(tag) {
        case NX_SoundDeviceInputGainStereo:
        case NX_SoundDeviceInputGainLeft:
        case NX_SoundDeviceInputGainRight:
            if(value<0 || value>32768) goto rejected;
            code=ScreamerQuantize((unsigned int)value,32768);
            if(tag!=NX_SoundDeviceInputGainRight) controls.gain[0]=code;
            if(tag!=NX_SoundDeviceInputGainLeft) controls.gain[1]=code;
            break;
        case NX_SoundDeviceAnalogInputSource:
            if(!screamer_input((NXSoundParameterTag)value,&input)) goto rejected;
            controls.input=input;break;
        case NX_SoundDeviceMicIn:case NX_SoundDeviceLineIn:case NX_SoundDeviceCDIn:
            if(value!=1 || !screamer_input(tag,&input)) goto rejected;
            controls.input=input;break;
        case NX_SoundDeviceAux1In:case NX_SoundDeviceAux2In:goto rejected;
        default:handled=0;break;
        }
    } else if(object==[self _outputChannel]) {
        switch(tag) {
        case NX_SoundDeviceOutputAttenuationStereo:
        case NX_SoundDeviceOutputAttenuationLeft:
        case NX_SoundDeviceOutputAttenuationRight:
            if(value>0 || value< -45) goto rejected;
            code=ScreamerQuantize((unsigned int)-value,45);
            if(tag!=NX_SoundDeviceOutputAttenuationRight) controls.attenuation[0]=code;
            if(tag!=NX_SoundDeviceOutputAttenuationLeft) controls.attenuation[1]=code;
            break;
        case NX_SoundDeviceMuteSpeaker:case NX_SoundDeviceMuteHeadphone:case NX_SoundDeviceMuteLineOut:
            if(value!=0 && value!=1) goto rejected;
            controls.userMuted=value;break;
        case NX_SoundDeviceOutputLoudness:case NX_SoundDeviceDeemphasize:goto rejected;
        default:handled=0;break;
        }
    } else {
        handled=0;
        if(tag==NX_SoundStreamSamplingRate) {
            if(value<=0 || ScreamerRateCode(&machineConfig,(unsigned int)value,&code)!=kScreamerOK ||
                ((runtime.streams[0].running || runtime.streams[1].running) && (unsigned int)value!=runtime.clockRate)) goto rejected;
        } else if(tag==NX_SoundStreamDataEncoding && value!=NX_SoundStreamDataEncoding_Linear16) goto rejected;
        else if(tag==NX_SoundStreamChannelCount && value!=2) goto rejected;
    }
    if(!handled) {[operationLock unlock];return [super _setParameter:tag toInt:value forObject:object];}
    status=ScreamerApplyControls(&runtime,&controls,screamer_deadline(self));
    [operationLock unlock];return status==kScreamerOK;
rejected:
    [operationLock unlock];return NO;
}
- (int)_intValueForParameter:(NXSoundParameterTag)tag forObject:(id)object
{
    ScreamerControls controls;
    [operationLock lock];controls=runtime.applied;[operationLock unlock];
    if(object==[self _inputChannel]) {
        if(tag==NX_SoundDeviceAnalogInputSource) return screamer_input_tag(controls.input);
        if(tag==NX_SoundDeviceInputGainLeft || tag==NX_SoundDeviceInputGainStereo) return (int)((controls.gain[0]*32768U+7)/15);
        if(tag==NX_SoundDeviceInputGainRight) return (int)((controls.gain[1]*32768U+7)/15);
        if(tag==NX_SoundDeviceMicIn || tag==NX_SoundDeviceLineIn || tag==NX_SoundDeviceCDIn)
            return tag==screamer_input_tag(controls.input);
    } else if(object==[self _outputChannel]) {
        if(tag==NX_SoundDeviceOutputAttenuationLeft || tag==NX_SoundDeviceOutputAttenuationStereo) return -(int)controls.attenuation[0]*3;
        if(tag==NX_SoundDeviceOutputAttenuationRight) return -(int)controls.attenuation[1]*3;
        if(tag==NX_SoundDeviceMuteSpeaker || tag==NX_SoundDeviceMuteHeadphone || tag==NX_SoundDeviceMuteLineOut) return controls.userMuted;
    }
    return [super _intValueForParameter:tag forObject:object];
}
- (void)_getSupportedParameters:(NXSoundParameterTag *)list count:(unsigned int *)count forObject:(id)object
{
    static NXSoundParameterTag in[]={NX_SoundDeviceBufferSize,NX_SoundDeviceBufferCount,NX_SoundDeviceDetectPeaks,
        NX_SoundDeviceInputGainStereo,NX_SoundDeviceInputGainLeft,NX_SoundDeviceInputGainRight,NX_SoundDeviceAnalogInputSource};
    static NXSoundParameterTag out[]={NX_SoundDeviceBufferSize,NX_SoundDeviceBufferCount,NX_SoundDeviceDetectPeaks,
        NX_SoundDeviceMuteSpeaker,NX_SoundDeviceMuteHeadphone,NX_SoundDeviceOutputAttenuationStereo,
        NX_SoundDeviceOutputAttenuationLeft,NX_SoundDeviceOutputAttenuationRight};
    unsigned int i;
    NXSoundParameterTag *source;
    if(object!=[self _inputChannel] && object!=[self _outputChannel]) {
        [super _getSupportedParameters:list count:count forObject:object];return;
    }
    source=object==[self _inputChannel]?in:out;
    *count=object==[self _inputChannel]?sizeof(in)/sizeof(in[0]):sizeof(out)/sizeof(out[0]);
    if(list) for(i=0;i<*count;++i) list[i]=source[i];
}
- (BOOL)_getValues:(NXSoundParameterTag *)list count:(unsigned int *)count forParameter:(NXSoundParameterTag)tag forObject:(id)object
{
    unsigned int i;
    if(object==[self _inputChannel] && tag==NX_SoundDeviceAnalogInputSource) {
        *count=0;
        for(i=0;i<kScreamerInputCount;++i) if(machineConfig.profile.inputBits[i]) {
            if(list) list[*count]=screamer_input_tag((ScreamerInput)i);
            ++*count;
        }
        return YES;
    }
    if(tag==NX_SoundStreamDataEncoding) {
        *count=1;if(list) list[0]=NX_SoundStreamDataEncoding_Linear16;return YES;
    }
    return [super _getValues:list count:count forParameter:tag forObject:object];
}
- (unsigned int)channelCount {return 2;}
- (unsigned int)channelCountLimit {return 2;}
- (BOOL)acceptsContinuousSamplingRates {return NO;}
- (void)getSamplingRates:(int *)rates count:(unsigned int *)count
{ unsigned int i;*count=machineConfig.rateCount;if(rates) for(i=0;i<*count;++i) rates[i]=machineConfig.rates[i]; }
- (void)getSamplingRatesLow:(int *)low high:(int *)high
{
    unsigned int i;*low=*high=44100;
    for(i=0;i<machineConfig.rateCount;++i) {
        if((int)machineConfig.rates[i]<*low) *low=machineConfig.rates[i];
        if((int)machineConfig.rates[i]>*high) *high=machineConfig.rates[i];
    }
}
- (void)getDataEncodings:(NXSoundParameterTag *)encodings count:(unsigned int *)count
{ *count=1;if(encodings) encodings[0]=NX_SoundStreamDataEncoding_Linear16; }
- (void)_setSampleRate:(unsigned int)rate
{
    unsigned int code;
    if(ScreamerRateCode(&machineConfig,rate,&code)==kScreamerOK &&
        (!(runtime.streams[0].running || runtime.streams[1].running) || rate==runtime.clockRate))
        [super _setSampleRate:rate];
    else formatRejected=1;
}
- (void)_setDataEncoding:(unsigned int)encoding
{ if(encoding==_NXAUDIO_FORMAT_LINEAR_16) [super _setDataEncoding:encoding];else formatRejected=1; }
- (void)_setChannelCount:(unsigned int)count
{ if(count==2) [super _setChannelCount:count];else formatRejected=1; }
#ifndef SCREAMER_ADAPTER_TEST
- (void)_initAudioHardwareSettings
{
    [super _setSampleRate:44100];
    [super _setDataEncoding:_NXAUDIO_FORMAT_LINEAR_16];
    [super _setChannelCount:2];
    /* Runtime initialized both channels muted. */
}
- (unsigned int)inputGainLeft {return (unsigned int)[self _intValueForParameter:NX_SoundDeviceInputGainLeft forObject:[self _inputChannel]];}
- (unsigned int)inputGainRight {return (unsigned int)[self _intValueForParameter:NX_SoundDeviceInputGainRight forObject:[self _inputChannel]];}
- (int)outputAttenuationLeft {return [self _intValueForParameter:NX_SoundDeviceOutputAttenuationLeft forObject:[self _outputChannel]];}
- (int)outputAttenuationRight {return [self _intValueForParameter:NX_SoundDeviceOutputAttenuationRight forObject:[self _outputChannel]];}
- (BOOL)isOutputMuted {return [self _intValueForParameter:NX_SoundDeviceMuteSpeaker forObject:[self _outputChannel]]!=0;}
- (void)screamerSet:(NXSoundParameterTag)tag value:(int)value input:(BOOL)input
{
    if(![self _setParameter:tag toInt:value forObject:input?[self _inputChannel]:[self _outputChannel]])
        IOLog("PPCScreamer: control %u rejected; retaining applied report\n",(unsigned int)tag);
}
- (void)_setInputGainLeft:(unsigned int)value {[self screamerSet:NX_SoundDeviceInputGainLeft value:(int)value input:YES];}
- (void)_setInputGainRight:(unsigned int)value {[self screamerSet:NX_SoundDeviceInputGainRight value:(int)value input:YES];}
- (void)_setOutputAttenuationLeft:(int)value {[self screamerSet:NX_SoundDeviceOutputAttenuationLeft value:value input:NO];}
- (void)_setOutputAttenuationRight:(int)value {[self screamerSet:NX_SoundDeviceOutputAttenuationRight value:value input:NO];}
- (void)_setOutputMute:(BOOL)value {[self screamerSet:NX_SoundDeviceMuteSpeaker value:value input:NO];}
- (void)_setAnalogInputSource:(NXSoundParameterTag)value {[self screamerSet:NX_SoundDeviceAnalogInputSource value:value input:YES];}
- (void)setAnalogInputSource:(NXSoundParameterTag)value {[self _setAnalogInputSource:value];}
- (void)setInput:(NXSoundParameterTag)tag enable:(BOOL)enable {[self screamerSet:tag value:enable input:YES];}
- (void)setOutput:(NXSoundParameterTag)tag enable:(BOOL)enable {(void)tag;[self _setOutputMute:!enable];}
#endif
@end
