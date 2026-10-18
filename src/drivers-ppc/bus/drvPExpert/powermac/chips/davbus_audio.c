/* Copyright (c) 2026 RhapsodiOS Project. */
#include "davbus_audio.h"
static const PEDAVBusTransport *davbus;
#define DAVBUS_SELECT (0x80U | 0x20U | 0x02U)
#define DAVBUS_CLOCK 0x08U
#define DAVBUS_CELL 0x40U
#define I2S0_ENABLES (0x400U | 0x1000U | 0x2000U)
static int valid(const PEDAVBusTransport *t)
{
    return t && t->controllerBase && t->family==kPEDAVBusKeyLargo &&
        t->owner && t->saved && t->active && t->readFCR1 && t->writeFCR1 &&
        t->lock && t->unlock && t->barrier && t->inInterruptContext;
}
void PEDAVBusBindTransport(const PEDAVBusTransport *t)
{
    davbus=valid(t)?t:0;
}
static kern_return_t change(const PEDAVBusTransport *t,unsigned int *v,
    unsigned int clear,unsigned int set)
{
    unsigned int next=(*v&~clear)|set;
    kern_return_t status;
    if(next==*v) return KERN_SUCCESS;
    status=t->writeFCR1(t->context,next);
    t->barrier(t->context);
    if(status!=KERN_SUCCESS) return status;
    *v=t->readFCR1(t->context);
    return *v==next?KERN_SUCCESS:KERN_FAILURE;
}
kern_return_t PEDAVBusSetStateCore(const PEDAVBusTransport *t,PEDAVBusState state)
{
    unsigned int v;
    kern_return_t status=KERN_SUCCESS;
    if(!valid(t) || (state!=kPEDAVBusOff && state!=kPEDAVBusReady))
        return KERN_INVALID_ARGUMENT;
    if(t->inInterruptContext(t->context)) return KERN_INVALID_ARGUMENT;
    t->lock(t->context);
    v=t->readFCR1(t->context);
    if(*t->owner==kPEAudioMuxI2S0 || (v&I2S0_ENABLES)) {
        status=KERN_RESOURCE_SHORTAGE; goto done;
    }
    if(state==kPEDAVBusReady) {
        if(*t->owner==kPEAudioMuxDAVbus && *t->active) goto done;
        if(*t->owner==kPEAudioMuxNone) *t->saved=v&DAVBUS_SELECT;
        *t->owner=kPEAudioMuxDAVbus;
        status=change(t,&v,0x22U,0);
        if(status==KERN_SUCCESS) status=change(t,&v,0,0x80U);
        if(status==KERN_SUCCESS) status=change(t,&v,0,DAVBUS_CLOCK);
        if(status==KERN_SUCCESS) status=change(t,&v,0,DAVBUS_CELL);
        *t->active=status==KERN_SUCCESS;
    } else if(*t->owner==kPEAudioMuxDAVbus) {
        status=change(t,&v,DAVBUS_CELL,0);
        if(status==KERN_SUCCESS) status=change(t,&v,DAVBUS_CLOCK,0);
        if(status==KERN_SUCCESS) status=change(t,&v,DAVBUS_SELECT,*t->saved);
        if(status==KERN_SUCCESS) {*t->owner=kPEAudioMuxNone;*t->active=0;}
    }
done:
    t->unlock(t->context);return status;
}
kern_return_t PEDAVBusGetInfo(unsigned int base,PEDAVBusInfo *info)
{
    if(!info || !base) return KERN_INVALID_ARGUMENT;
    if(!davbus) return KERN_FAILURE;
    if(base!=davbus->controllerBase) return KERN_INVALID_ARGUMENT;
    info->family=davbus->family;
    info->capabilities=davbus->readGPIO && davbus->writeGPIO?kPEDAVBusAmplifierGPIO:0;
    return KERN_SUCCESS;
}
kern_return_t PEDAVBusSetState(unsigned int base,PEDAVBusState state)
{
    if(!base || (state!=kPEDAVBusReady && state!=kPEDAVBusOff))
        return KERN_INVALID_ARGUMENT;
    if(!davbus) return KERN_FAILURE;
    if(base!=davbus->controllerBase) return KERN_INVALID_ARGUMENT;
    return PEDAVBusSetStateCore(davbus,state);
}
kern_return_t PEDAVBusSetAmplifier(unsigned int base,unsigned int enabled)
{
    unsigned char value,expected;
    kern_return_t status;
    if(!base || enabled>1) return KERN_INVALID_ARGUMENT;
    if(!davbus || !davbus->readGPIO || !davbus->writeGPIO) return KERN_FAILURE;
    if(base!=davbus->controllerBase || davbus->inInterruptContext(davbus->context)) return KERN_INVALID_ARGUMENT;
    davbus->lock(davbus->context);
    if(*davbus->owner!=kPEAudioMuxDAVbus || !*davbus->active) status=KERN_FAILURE;
    else {
        value=davbus->readGPIO(davbus->context,0x6f);
        expected=(unsigned char)((value&~5U)|4U|enabled);
        davbus->writeGPIO(davbus->context,0x6f,expected);
        davbus->barrier(davbus->context);
        value=davbus->readGPIO(davbus->context,0x6f);
        status=(value&5U)==(expected&5U)?KERN_SUCCESS:KERN_FAILURE;
    }
    davbus->unlock(davbus->context);return status;
}
