/*
 * IntelAC97Driver.m
 *
 * Intel AC'97 Audio Driver for RhapsodiOS
 * Supports Intel ICH, ICH2, ICH3, ICH4, ICH5 and compatible chipsets
 *
 * Based on the Intel ICH AC'97 specification and NetBSD's auich driver
 *
 * Copyright (c) 2025
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/directDevice.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/i386/PCI.h>
#import <driverkit/interruptMsg.h>
#import <kernserv/prototypes.h>
#import <kernserv/sched_prim.h>
#import <kernserv/i386/spl.h>

#import "IntelAC97Driver.h"
#import "ICHAC97Controller.h"
#import "ac97var.h"
#import "ac97reg.h"

#ifndef PCI_COMMAND_IO_ENABLE
#define PCI_COMMAND_IO_ENABLE     0x0001
#define PCI_COMMAND_MEM_ENABLE    0x0002
#define PCI_COMMAND_MASTER_ENABLE 0x0004
#endif

#define ICH97_PCI_BASE_IO(x) ((unsigned int)((x) & ~3UL))

/* PCI Vendor/Device IDs for Intel ICH chipsets */
#define PCI_VENDOR_INTEL                0x8086

#define PCI_DEVICE_INTEL_82801AA_AC97   0x2415  /* ICH */
#define PCI_DEVICE_INTEL_82801AB_AC97   0x2425  /* ICH0 */
#define PCI_DEVICE_INTEL_82801BA_AC97   0x2445  /* ICH2 */
#define PCI_DEVICE_INTEL_82801CA_AC97   0x2485  /* ICH3 */
#define PCI_DEVICE_INTEL_82801DB_AC97   0x24C5  /* ICH4 */
#define PCI_DEVICE_INTEL_82801EB_AC97   0x24D5  /* ICH5 */
#define PCI_DEVICE_INTEL_82801FB_AC97   0x266E  /* ICH6 */
#define PCI_DEVICE_INTEL_6300ESB_AC97   0x25A6  /* 6300ESB */
#define PCI_DEVICE_INTEL_82801GB_AC97   0x27DE  /* ICH7 */

/* ICH Register offsets - Native Audio Bus Master (NABM) */
#define ICH_REG_PI_BDBAR                0x00    /* PCM In Buffer Descriptor BAR */
#define ICH_REG_PI_CIV                  0x04    /* PCM In Current Index Value */
#define ICH_REG_PI_LVI                  0x05    /* PCM In Last Valid Index */
#define ICH_REG_PI_SR                   0x06    /* PCM In Status Register */
#define ICH_REG_PI_PICB                 0x08    /* PCM In Position In Current Buffer */
#define ICH_REG_PI_PIV                  0x0A    /* PCM In Prefetch Index Value */
#define ICH_REG_PI_CR                   0x0B    /* PCM In Control Register */

#define ICH_REG_PO_BDBAR                0x10    /* PCM Out Buffer Descriptor BAR */
#define ICH_REG_PO_CIV                  0x14    /* PCM Out Current Index Value */
#define ICH_REG_PO_LVI                  0x15    /* PCM Out Last Valid Index */
#define ICH_REG_PO_SR                   0x16    /* PCM Out Status Register */
#define ICH_REG_PO_PICB                 0x18    /* PCM Out Position In Current Buffer */
#define ICH_REG_PO_PIV                  0x1A    /* PCM Out Prefetch Index Value */
#define ICH_REG_PO_CR                   0x1B    /* PCM Out Control Register */

#define ICH_REG_MC_BDBAR                0x20    /* Mic In Buffer Descriptor BAR */
#define ICH_REG_MC_CIV                  0x24    /* Mic In Current Index Value */
#define ICH_REG_MC_LVI                  0x25    /* Mic In Last Valid Index */
#define ICH_REG_MC_SR                   0x26    /* Mic In Status Register */
#define ICH_REG_MC_PICB                 0x28    /* Mic In Position In Current Buffer */
#define ICH_REG_MC_PIV                  0x2A    /* Mic In Prefetch Index Value */
#define ICH_REG_MC_CR                   0x2B    /* Mic In Control Register */

#define ICH_REG_GLOB_CNT                0x2C    /* Global Control */
#define ICH_REG_GLOB_STA                0x30    /* Global Status */
#define ICH_REG_ACC_SEMA                0x34    /* Access Semaphore */

/* Control Register bits */
#define ICH_CR_RPBM                     0x01    /* Run/Pause Bus Master */
#define ICH_CR_RR                       0x02    /* Reset Registers */
#define ICH_CR_LVBIE                    0x04    /* Last Valid Buffer Interrupt Enable */
#define ICH_CR_FEIE                     0x08    /* FIFO Error Interrupt Enable */
#define ICH_CR_IOCE                     0x10    /* Interrupt On Completion Enable */

/* Status Register bits */
#define ICH_SR_DCH                      0x01    /* DMA Controller Halted */
#define ICH_SR_CELV                     0x02    /* Current Equals Last Valid */
#define ICH_SR_LVBCI                    0x04    /* Last Valid Buffer Completion Interrupt */
#define ICH_SR_BCIS                     0x08    /* Buffer Completion Interrupt Status */
#define ICH_SR_FIFOE                    0x10    /* FIFO Error */

/* Global Status bits */
#define ICH_GLOB_STA_GSCI               0x00000001  /* GPI Status Change Interrupt */
#define ICH_GLOB_STA_MIINT              0x00000002  /* Modem In Interrupt */
#define ICH_GLOB_STA_MOINT              0x00000004  /* Modem Out Interrupt */
#define ICH_GLOB_STA_PIINT              0x00000020  /* PCM In Interrupt */
#define ICH_GLOB_STA_POINT              0x00000040  /* PCM Out Interrupt */
#define ICH_GLOB_STA_MINT               0x00000080  /* Mic In Interrupt */
#define ICH_GLOB_STA_PCR                0x00000100  /* Primary Codec Ready */
#define ICH_GLOB_STA_SCR                0x00000200  /* Secondary Codec Ready */
#define ICH_GLOB_STA_S2CR               0x00100000  /* Secondary 2 Codec Ready */
#define ICH_GLOB_STA_MD3                0x00020000  /* Modem Power Down Semaphore */
#define ICH_GLOB_STA_AD3                0x00010000  /* Audio Power Down Semaphore */
#define ICH_GLOB_STA_RCS                0x00008000  /* Read Completion Status */

/* Buffer Descriptor */
struct ich_buffer_desc {
    unsigned int    buffer_addr;    /* Physical address of buffer */
    unsigned int    control;        /* Length and control bits */
};

#define ICH_BD_IOC                      0x80000000  /* Interrupt on Completion */
#define ICH_BD_BUP                      0x40000000  /* Buffer Underrun Policy */

/* Number of buffer descriptors */
#define ICH_BD_COUNT                    32
#define ICH_BD_SIZE                     (ICH_BD_COUNT * sizeof(struct ich_buffer_desc))

struct ich97_driver_state {
    ICHAC97Controller controller;
    struct ac97_codec_state codec;
    IOInterruptHandler oldHandler;
    simple_lock_t lock;
    BOOL ioAudioInitialized;
    BOOL interruptRegistered;
    BOOL mixerRangeRegistered;
    BOOL busMasterRangeRegistered;
    BOOL codecAttached;
    unsigned int bufVirt;
    unsigned int lastService;
};

static struct ich97_driver_state *activeInterruptState;

static unsigned char kernel_read8(void *context, unsigned int port)
{
    (void)context;
    return inb((IOEISAPortAddress)port);
}

static unsigned short kernel_read16(void *context, unsigned int port)
{
    (void)context;
    return inw((IOEISAPortAddress)port);
}

static unsigned int kernel_read32(void *context, unsigned int port)
{
    (void)context;
    return inl((IOEISAPortAddress)port);
}

static void kernel_write8(void *context, unsigned int port, unsigned char value)
{
    (void)context;
    outb((IOEISAPortAddress)port, value);
}

static void kernel_write16(void *context, unsigned int port, unsigned short value)
{
    (void)context;
    outw((IOEISAPortAddress)port, value);
}

static void kernel_write32(void *context, unsigned int port, unsigned int value)
{
    (void)context;
    outl((IOEISAPortAddress)port, value);
}

static void kernel_delay(void *context, unsigned int microseconds)
{
    (void)context;
    IODelay(microseconds);
}

static unsigned short ich97_codec_read(void *host_priv, unsigned char reg)
{
    return ICHAC97CodecRead((ICHAC97Controller *)host_priv, (ICHAC97UInt8)reg);
}

static void ich97_codec_write(void *host_priv, unsigned char reg, unsigned short val)
{
    ICHAC97CodecWrite((ICHAC97Controller *)host_priv, (ICHAC97UInt8)reg,
                      (ICHAC97UInt16)val);
}

static void ich97_codec_reset(void *host_priv)
{
    (void)host_priv;
}

static void ich97_apply_initial_output(IntelAC97Driver *self)
{
    if (self->state == nil)
        return;

    ac97_apply_output(&self->state->codec,
                      [self outputAttenuationLeft],
                      [self outputAttenuationRight],
                      1);
}

static void clearInterrupts(void)
{
    struct ich97_driver_state *st = activeInterruptState;

    if (st == nil)
        return;

    simple_lock(st->lock);
    ICHAC97ServiceInterrupt(&st->controller);
    simple_unlock(st->lock);
}

static void clearInt(void *identity, void *handlerState, unsigned int arg)
{
    struct ich97_driver_state *st = activeInterruptState;
    unsigned int service;

    if (st == nil) {
        IOEnableInterrupt(identity);
        return;
    }

    simple_lock(st->lock);
    service = ICHAC97ServiceInterrupt(&st->controller);
    simple_unlock(st->lock);

    if (service & kICHAC97ServiceOutput) {
        if (st->oldHandler)
            (*st->oldHandler)(identity, handlerState, arg);
    }

    IOEnableInterrupt(identity);
}

@implementation IntelAC97Driver

/*
 * probe: - Probe and initialize device
 */
+ (BOOL)probe:deviceDescription
{
    IntelAC97Driver *dev;

    dev = [self alloc];
    if (dev == nil)
        return NO;

    return ([dev initFromDeviceDescription:deviceDescription] != nil);
}

/*
 * ich97_release_state - Idempotent teardown of instance state
 */
- (void)ich97_release_state
{
    if (state == nil)
        return;

    if (state->controller.nabmbar != 0)
        ICHAC97StopPlayback(&state->controller);

    if (activeInterruptState == state)
        activeInterruptState = nil;

    if (state->interruptRegistered)
        [self releaseInterrupt:0];
    if (state->mixerRangeRegistered)
        [self releasePortRange:0];
    if (state->busMasterRangeRegistered)
        [self releasePortRange:1];

    if (state->controller.playback.bdl != nil) {
        IOFree(state->controller.playback.bdl, ICH_BD_SIZE);
        state->controller.playback.bdl = nil;
    }

    if (state->lock != nil)
        simple_lock_free(state->lock);

    IOFree(state, sizeof(*state));
    state = nil;
}

/*
 * initFromDeviceDescription: - Initialize instance
 */
- initFromDeviceDescription:deviceDescription
{
    IOReturn            irtn;
    IOPCIConfigSpace    configSpace;
    IORange             portRange[2];
    unsigned long       regLong;
    unsigned int        nambar;
    unsigned int        nabmbar;
    unsigned int        irq;
    ICHAC97IO           io;

    bzero(&configSpace, sizeof(IOPCIConfigSpace));
    if ((irtn = [IODirectDevice getPCIConfigSpace:&configSpace
                        withDeviceDescription:deviceDescription])) {
        IOLog("%s: Can't get PCI config space (%s)\n",
              DRV_TITLE, [IODirectDevice stringFromReturn:irtn]);
        return nil;
    }

    if (configSpace.VendorID != PCI_VENDOR_INTEL) {
        IOLog("%s: Not an Intel device (0x%04x)\n",
              DRV_TITLE, configSpace.VendorID);
        return nil;
    }

    switch (configSpace.DeviceID) {
    case PCI_DEVICE_INTEL_82801AA_AC97:
        IOLog("%s: Found Intel 82801AA (ICH)\n", DRV_TITLE);
        break;
    case PCI_DEVICE_INTEL_82801AB_AC97:
        IOLog("%s: Found Intel 82801AB (ICH0)\n", DRV_TITLE);
        break;
    case PCI_DEVICE_INTEL_82801BA_AC97:
        IOLog("%s: Found Intel 82801BA (ICH2)\n", DRV_TITLE);
        break;
    case PCI_DEVICE_INTEL_82801CA_AC97:
        IOLog("%s: Found Intel 82801CA (ICH3)\n", DRV_TITLE);
        break;
    case PCI_DEVICE_INTEL_82801DB_AC97:
        IOLog("%s: Found Intel 82801DB (ICH4)\n", DRV_TITLE);
        break;
    case PCI_DEVICE_INTEL_82801EB_AC97:
        IOLog("%s: Found Intel 82801EB (ICH5)\n", DRV_TITLE);
        break;
    case PCI_DEVICE_INTEL_82801FB_AC97:
        IOLog("%s: Found Intel 82801FB (ICH6)\n", DRV_TITLE);
        break;
    case PCI_DEVICE_INTEL_6300ESB_AC97:
        IOLog("%s: Found Intel 6300ESB\n", DRV_TITLE);
        break;
    case PCI_DEVICE_INTEL_82801GB_AC97:
        IOLog("%s: Found Intel 82801GB (ICH7)\n", DRV_TITLE);
        break;
    default:
        IOLog("%s: Unsupported Intel device (0x%04x)\n",
              DRV_TITLE, configSpace.DeviceID);
        return nil;
    }

    if (!(configSpace.BaseAddress[0] & PCI_BASE_IO_BIT)) {
        IOLog("%s: BAR0 is not an I/O port\n", DRV_TITLE);
        return nil;
    }
    nambar = ICH97_PCI_BASE_IO(configSpace.BaseAddress[0]);

    if (!(configSpace.BaseAddress[1] & PCI_BASE_IO_BIT)) {
        IOLog("%s: BAR1 is not an I/O port\n", DRV_TITLE);
        return nil;
    }
    nabmbar = ICH97_PCI_BASE_IO(configSpace.BaseAddress[1]);

    irq = configSpace.InterruptLine;
    if (nambar == 0 || nabmbar == 0 || irq == 0) {
        IOLog("%s: No I/O ports or IRQ found\n", DRV_TITLE);
        IOLog("%s: NAMBAR=0x%x NABMBAR=0x%x IRQ=%d\n",
              DRV_TITLE, nambar, nabmbar, irq);
        return nil;
    }

    IOLog("%s: NAMBAR at 0x%x, NABMBAR at 0x%x, IRQ %d\n",
          DRV_TITLE, nambar, nabmbar, irq);

    state = IOMalloc(sizeof(*state));
    if (state == nil) {
        IOLog("%s: Can't allocate driver state\n", DRV_TITLE);
        return nil;
    }
    bzero(state, sizeof(*state));
    state->lock = simple_lock_alloc();
    simple_lock_init(state->lock);

    irtn = [deviceDescription setInterruptList:&irq num:1];
    if (irtn) {
        IOLog("%s: Can't set interrupt list (%s)\n",
              DRV_TITLE, [IODirectDevice stringFromReturn:irtn]);
        [self ich97_release_state];
        return nil;
    }
    state->interruptRegistered = YES;

    portRange[0].start = nambar;
    portRange[0].size = 256;
    portRange[1].start = nabmbar;
    portRange[1].size = 64;
    irtn = [deviceDescription setPortRangeList:portRange num:2];
    if (irtn) {
        IOLog("%s: Can't set port range list (%s)\n",
              DRV_TITLE, [IODirectDevice stringFromReturn:irtn]);
        [self ich97_release_state];
        return nil;
    }
    state->mixerRangeRegistered = YES;
    state->busMasterRangeRegistered = YES;

    if ((irtn = [IODirectDevice getPCIConfigData:&regLong atRegister:0x04
                        withDeviceDescription:deviceDescription]) ||
        (irtn = [IODirectDevice setPCIConfigData:(regLong |
                        (PCI_COMMAND_IO_ENABLE |
                         PCI_COMMAND_MEM_ENABLE |
                         PCI_COMMAND_MASTER_ENABLE))
                        atRegister:0x04
                        withDeviceDescription:deviceDescription])) {
        IOLog("%s: Can't enable PCI command bits (%s)\n",
              DRV_TITLE, [IODirectDevice stringFromReturn:irtn]);
        [self ich97_release_state];
        return nil;
    }

    bzero(&io, sizeof(io));
    io.context = nil;
    io.read8 = kernel_read8;
    io.read16 = kernel_read16;
    io.read32 = kernel_read32;
    io.write8 = kernel_write8;
    io.write16 = kernel_write16;
    io.write32 = kernel_write32;
    io.delayUS = kernel_delay;
    ICHAC97ControllerInit(&state->controller, &io, nambar, nabmbar);

    if (activeInterruptState != nil) {
        IOLog("%s: Another instance already owns the interrupt bridge\n",
              DRV_TITLE);
        [self ich97_release_state];
        return nil;
    }

    activeInterruptState = state;

    if (![super initFromDeviceDescription:deviceDescription]) {
        IOLog("%s: Failed on [super init]\n", DRV_TITLE);
        [self ich97_release_state];
        return nil;
    }

    state->ioAudioInitialized = YES;
    ich97_apply_initial_output(self);

    return self;
}

/*
 * free - Free driver resources
 */
- free
{
    [self ich97_release_state];
    return [super free];
}

/*
 * reset - Reset hardware
 */
- (BOOL)reset
{
    struct ac97_codec_state *codec;

    [self setName:"IntelAC97"];
    [self setDeviceKind:"Audio"];

    if (state == nil)
        return NO;

    if (ICHAC97ResetPlayback(&state->controller, 100) != kICHAC97Success) {
        IOLog("%s: Playback reset timeout\n", DRV_TITLE);
        return NO;
    }

    if (ICHAC97ResetLink(&state->controller, 1000) != kICHAC97Success) {
        IOLog("%s: Codec ready timeout\n", DRV_TITLE);
        return NO;
    }

    IOLog("%s: Primary codec ready\n", DRV_TITLE);

    state->codecAttached = NO;
    codec = &state->codec;
    bzero(codec, sizeof(*codec));
    codec->host_priv = &state->controller;
    codec->read_reg = ich97_codec_read;
    codec->write_reg = ich97_codec_write;
    codec->reset = ich97_codec_reset;
    codec->delay_us = kernel_delay;
    codec->delay_context = nil;
    codec->host_flags = 0;

    if (ac97_attach(codec, AC97_CODEC_TYPE_AUDIO) < 0) {
        IOLog("%s: Failed to initialize AC97 codec\n", DRV_TITLE);
        return NO;
    }

    state->codecAttached = YES;
    IOLog("%s: Attached codec %s (%s)\n", DRV_TITLE,
          codec->codec_name, codec->vendor_name);

    ich97_apply_initial_output(self);

    return YES;
}

/*
 * createDMABufferFor:length:read:needsLowMemory:limitSize:
 */
- (IOEISADMABuffer)createDMABufferFor:(unsigned int *)physicalAddress
                              length:(unsigned int)numBytes
                                read:(BOOL)isRead
                      needsLowMemory:(BOOL)lowerMem
                           limitSize:(BOOL)limitSize
{
    IOReturn        irtn;
    unsigned int    physAddr;

    if (state == nil)
        return NULL;

    if (isRead)
        return NULL;

    irtn = IOPhysicalFromVirtual(IOVmTaskSelf(), *physicalAddress, &physAddr);
    if (irtn) {
        IOLog("%s: Failed to map memory\n", DRV_TITLE);
        return NULL;
    }

    state->bufVirt = *physicalAddress;
    state->controller.playback.bufferPhysical = physAddr;
    state->controller.playback.bufferBytes = numBytes;

    if (state->controller.playback.bdl == nil) {
        state->controller.playback.bdl = IOMalloc(ICH_BD_SIZE);
        if (state->controller.playback.bdl == nil) {
            IOLog("%s: Can't allocate BDL\n", DRV_TITLE);
            return NULL;
        }
        bzero(state->controller.playback.bdl, ICH_BD_SIZE);
        IOPhysicalFromVirtual(IOVmTaskSelf(),
                            (unsigned int)state->controller.playback.bdl,
                            &state->controller.playback.bdlPhysical);
    }

    return (IOEISADMABuffer)physAddr;
}

/*
 * startDMAForChannel:read:buffer:bufferSizeForInterrupts:
 */
- (BOOL)startDMAForChannel:(unsigned int)localChannel
                      read:(BOOL)isRead
                    buffer:(IOEISADMABuffer)buffer
     bufferSizeForInterrupts:(unsigned int)bufferSize
{
    int result;

    if (state == nil)
        return NO;

    if (isRead)
        return NO;

    result = ICHAC97PrepareBDL(&state->controller.playback,
                               state->controller.playback.bdl,
                               state->controller.playback.bdlPhysical,
                               state->controller.playback.bufferPhysical,
                               state->controller.playback.bufferBytes,
                               bufferSize);
    if (result != kICHAC97Success) {
        IOLog("%s: Failed to prepare BDL (%d)\n", DRV_TITLE, result);
        return NO;
    }

    ac97_set_rate(&state->codec, AC97_RATE_DAC, [self sampleRate]);

    result = ICHAC97StartPlayback(&state->controller);
    if (result != kICHAC97Success) {
        IOLog("%s: Failed to start playback (%d)\n", DRV_TITLE, result);
        return NO;
    }

    ac97_apply_output(&state->codec,
                      [self outputAttenuationLeft],
                      [self outputAttenuationRight],
                      [self isOutputMuted]);

    [self enableAllInterrupts];

    return YES;
}

/*
 * stopDMAForChannel:read:
 */
- (void)stopDMAForChannel:(unsigned int)localChannel read:(BOOL)isRead
{
    if (state == nil)
        return;

    ICHAC97StopPlayback(&state->controller);
}

/*
 * interruptClearFunc
 */
- (IOAudioInterruptClearFunc)interruptClearFunc
{
    return clearInterrupts;
}

/*
 * interruptOccurredForInput:forOutput:
 */
- (void)interruptOccurredForInput:(BOOL *)serviceInput
                        forOutput:(BOOL *)serviceOutput
{
    unsigned int service;
    unsigned int fifoErrors;

    if (state == nil) {
        *serviceInput = NO;
        *serviceOutput = NO;
        return;
    }

    service = ICHAC97ConsumeService(&state->controller);
    fifoErrors = state->controller.playback.fifoErrors;

    if ((service & kICHAC97ServiceOutputFIFOError) != 0) {
        if (fifoErrors == 1 || (fifoErrors & 0xff) == 0)
            IOLog("%s: FIFO error (count %u)\n", DRV_TITLE, fifoErrors);
    }

    *serviceInput = NO;
    *serviceOutput = (service & kICHAC97ServiceOutput) != 0;
}

/*
 * getHandler:level:argument:forInterrupt:
 */
- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(unsigned int *)arg
      forInterrupt:(unsigned int)localInterrupt
{
    if (state == nil)
        return NO;

    [super getHandler:&state->oldHandler level:ipl argument:arg
         forInterrupt:localInterrupt];

    *handler = clearInt;
    return YES;
}

/*
 * timeoutOccurred
 */
- (void)timeoutOccurred
{
    IOLog("%s: Timeout waiting for interrupt\n", DRV_TITLE);
}

/*
 * updateSampleRate
 */
- (void)updateSampleRate
{
    unsigned int rate = [self sampleRate];

    if (state != nil && state->codecAttached) {
        ac97_set_rate(&state->codec, AC97_RATE_DAC, rate);
        ac97_set_rate(&state->codec, AC97_RATE_ADC, rate);
    }
}

/*
 * acceptsContinuousSamplingRates
 */
- (BOOL)acceptsContinuousSamplingRates
{
    if (state == nil || !state->codecAttached)
        return NO;

    return state->codec.caps.vra_supported;
}

/*
 * getSamplingRatesLow:high:
 */
- (void)getSamplingRatesLow:(int *)lowRate high:(int *)highRate
{
    *lowRate = AC97_RATE_MIN;
    *highRate = AC97_RATE_MAX;
}

/*
 * getSamplingRates:count:
 */
- (void)getSamplingRates:(int *)rates count:(unsigned int *)numRates
{
    rates[0] = 8000;
    rates[1] = 11025;
    rates[2] = 16000;
    rates[3] = 22050;
    rates[4] = 32000;
    rates[5] = 44100;
    rates[6] = 48000;
    *numRates = 7;
}

/*
 * getDataEncodings:count:
 */
- (void)getDataEncodings:(NXSoundParameterTag *)encodings
                   count:(unsigned int *)numEncodings
{
    encodings[0] = NX_SoundStreamDataEncoding_Linear16;
    *numEncodings = 1;
}

/*
 * channelCountLimit
 */
- (unsigned int)channelCountLimit
{
    return 2;
}

/*
 * updateOutputMute
 */
- (void)updateOutputMute
{
    BOOL mute;

    if (state == nil || !state->codecAttached)
        return;

    mute = [self isOutputMuted] || !state->controller.playback.running;

    ac97_set_master_volume(&state->codec,
                          state->codec.master_vol_l,
                          state->codec.master_vol_r,
                          mute);
}

/*
 * updateOutputAttenuationLeft
 */
- (void)updateOutputAttenuationLeft
{
    unsigned char left;
    BOOL mute;

    if (state == nil || !state->codecAttached)
        return;

    left = ([self outputAttenuationLeft] * 31) / 13;
    mute = [self isOutputMuted] || !state->controller.playback.running;

    ac97_set_master_volume(&state->codec, left, state->codec.master_vol_r,
                          mute);
}

/*
 * updateOutputAttenuationRight
 */
- (void)updateOutputAttenuationRight
{
    unsigned char right;
    BOOL mute;

    if (state == nil || !state->codecAttached)
        return;

    right = ([self outputAttenuationRight] * 31) / 13;
    mute = [self isOutputMuted] || !state->controller.playback.running;

    ac97_set_master_volume(&state->codec, state->codec.master_vol_l, right,
                          mute);
}

/*
 * updateInputGainLeft
 */
- (void)updateInputGainLeft
{
    /* Not implemented yet */
}

/*
 * updateInputGainRight
 */
- (void)updateInputGainRight
{
    /* Not implemented yet */
}

@end
