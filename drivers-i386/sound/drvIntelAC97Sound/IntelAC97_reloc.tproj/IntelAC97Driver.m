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
#import "ac97var.h"
#import "ac97reg.h"

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

/* ICH Register offsets - Mixer (NAMBAR) */
#define ICH_MIXER_RESET                 AC97_REG_RESET

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

/* Global Control bits */
#define ICH_GLOB_CNT_GIE                0x00000001  /* GPI Interrupt Enable */
#define ICH_GLOB_CNT_COLD               0x00000002  /* AC97 Cold Reset */
#define ICH_GLOB_CNT_WARM               0x00000004  /* AC97 Warm Reset */
#define ICH_GLOB_CNT_SHUT               0x00000008  /* AC97 Shutoff */
#define ICH_GLOB_CNT_PRIE               0x00000010  /* PCM In Resume Interrupt Enable */
#define ICH_GLOB_CNT_SRIE               0x00000020  /* Secondary Resume Interrupt Enable */
#define ICH_GLOB_CNT_MRIE               0x00000040  /* Mic Resume Interrupt Enable */

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

/* ICH Hardware State */
struct ich_state {
    unsigned int    magic;

    /* Hardware resources */
    unsigned int    nambar;         /* Native Audio Mixer BAR */
    unsigned int    nabmbar;        /* Native Audio Bus Master BAR */
    unsigned int    irq;

    /* PCI Info */
    unsigned short  vendor;
    unsigned short  device;
    unsigned char   revision;

    /* AC97 Codec */
    struct ac97_codec_state *codec;

    /* DMA Buffers */
    struct ich_buffer_desc  *bdl_output;    /* Buffer Descriptor List for output */
    unsigned int            bdl_output_phys;
    struct ich_buffer_desc  *bdl_input;     /* Buffer Descriptor List for input */
    unsigned int            bdl_input_phys;

    /* Playback state */
    unsigned int    out_buffer_phys;
    unsigned int    out_buffer_size;
    unsigned int    out_fragment_size;
    unsigned int    out_lvi;                /* Last Valid Index */
    unsigned int    out_civ;                /* Current Index Value */
    BOOL            out_running;

    /* Record state */
    unsigned int    in_buffer_phys;
    unsigned int    in_buffer_size;
    BOOL            in_running;

    /* Locking */
    simple_lock_t   lock;
};

#define ICH_MAGIC                       0x49434800  /* "ICH\0" */

static struct ich_state     *s = NULL;
static IOInterruptHandler   oldHandler = NULL;

/* Forward declarations */
static unsigned short ich_codec_read(void *host_priv, unsigned char reg);
static void ich_codec_write(void *host_priv, unsigned char reg, unsigned short val);
static void ich_codec_reset(void *host_priv);
static int ich_init_codec(struct ich_state *s);
static void ich_reset_channels(struct ich_state *s);

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
 * initFromDeviceDescription: - Initialize instance
 */
- initFromDeviceDescription:deviceDescription
{
    IOReturn            irtn;
    IOPCIConfigSpace    configSpace;
    IORange             portRange[2];
    unsigned long       *basePtr = 0;
    unsigned long       regLong;
    int                 i;

    /* Get PCI configuration space */
    bzero(&configSpace, sizeof(IOPCIConfigSpace));
    if ((irtn = [IODirectDevice getPCIConfigSpace:&configSpace
                        withDeviceDescription:deviceDescription])) {
        IOLog("%s: Can't get PCI config space (%s)\n",
              DRV_TITLE, [IODirectDevice stringFromReturn:irtn]);
        return nil;
    }

    /* Allocate driver state */
    s = IOMalloc(sizeof(*s));
    bzero(s, sizeof(*s));
    s->magic = ICH_MAGIC;
    s->vendor = configSpace.VendorID;
    s->device = configSpace.DeviceID;
    s->revision = configSpace.RevisionID;

    /* Initialize lock */
    s->lock = simple_lock_alloc();
    simple_lock_init(s->lock);

    /* Check if this is a supported Intel AC97 controller */
    if (s->vendor != PCI_VENDOR_INTEL) {
        IOLog("%s: Not an Intel device (0x%04x)\n", DRV_TITLE, s->vendor);
        return nil;
    }

    switch (s->device) {
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
        IOLog("%s: Unsupported Intel device (0x%04x)\n", DRV_TITLE, s->device);
        return nil;
    }

    /* Read I/O base addresses */
    basePtr = configSpace.BaseAddress;
    s->nambar = 0;  /* Mixer BAR */
    s->nabmbar = 0; /* Bus Master BAR */

    for (i = 0; i < PCI_NUM_BASE_ADDRESS; i++) {
        if (basePtr[i] & PCI_BASE_IO_BIT) {
            if (s->nambar == 0)
                s->nambar = PCI_BASE_IO(basePtr[i]);
            else if (s->nabmbar == 0)
                s->nabmbar = PCI_BASE_IO(basePtr[i]);
        }
    }

    /* Get IRQ */
    s->irq = configSpace.InterruptLine;

    if (!s->nambar || !s->nabmbar || !s->irq) {
        IOLog("%s: No I/O ports or IRQ found\n", DRV_TITLE);
        IOLog("%s: NAMBAR=0x%x NABMBAR=0x%x IRQ=%d\n",
              DRV_TITLE, s->nambar, s->nabmbar, s->irq);
        return nil;
    }

    IOLog("%s: NAMBAR at 0x%x, NABMBAR at 0x%x, IRQ %d\n",
          DRV_TITLE, s->nambar, s->nabmbar, s->irq);

    /* Register interrupt and port ranges */
    irtn = [deviceDescription setInterruptList:&(s->irq) num:1];
    if (irtn) {
        IOLog("%s: Can't set interrupt list (%s)\n",
              DRV_TITLE, [IODirectDevice stringFromReturn:irtn]);
        return nil;
    }

    portRange[0].start = s->nambar;
    portRange[0].size = 256;
    portRange[1].start = s->nabmbar;
    portRange[1].size = 64;
    irtn = [deviceDescription setPortRangeList:portRange num:2];
    if (irtn) {
        IOLog("%s: Can't set port range list (%s)\n",
              DRV_TITLE, [IODirectDevice stringFromReturn:irtn]);
        return nil;
    }

    /* Enable bus mastering */
    if ((irtn = [IODirectDevice getPCIConfigData:&regLong atRegister:0x04
                        withDeviceDescription:deviceDescription]) ||
        (irtn = [IODirectDevice setPCIConfigData:(regLong | PCI_COMMAND_MASTER_ENABLE)
                        atRegister:0x04
                        withDeviceDescription:deviceDescription])) {
        IOLog("%s: Can't enable bus mastering (%s)\n",
              DRV_TITLE, [IODirectDevice stringFromReturn:irtn]);
        return nil;
    }

    /* Initialize IOAudio */
    if (![super initFromDeviceDescription:deviceDescription]) {
        IOLog("%s: Failed on [super init]\n", DRV_TITLE);
        return nil;
    }

    return self;
}

/*
 * free - Free driver resources
 */
- free
{
    [self releaseInterrupt:0];
    [self releasePortRange:0];
    [self releasePortRange:1];

    if (s) {
        if (s->codec) {
            IOFree(s->codec, sizeof(struct ac97_codec_state));
        }
        if (s->bdl_output) {
            /* Free buffer descriptor lists */
            IOFree(s->bdl_output, ICH_BD_SIZE);
        }
        if (s->bdl_input) {
            IOFree(s->bdl_input, ICH_BD_SIZE);
        }
        simple_lock_free(s->lock);
        IOFree(s, sizeof(*s));
    }

    return [super free];
}

/*
 * reset - Reset hardware
 */
- (BOOL)reset
{
    unsigned int glob_cnt, glob_sta;
    int timeout;

    [self setName:"IntelAC97"];
    [self setDeviceKind:"Audio"];

    /* Reset all channels */
    ich_reset_channels(s);

    /* Cold reset AC97 */
    glob_cnt = inl(s->nabmbar + ICH_REG_GLOB_CNT);
    glob_cnt &= ~ICH_GLOB_CNT_COLD;
    outl(glob_cnt, s->nabmbar + ICH_REG_GLOB_CNT);
    IODelay(1000);

    glob_cnt |= ICH_GLOB_CNT_COLD;
    outl(glob_cnt, s->nabmbar + ICH_REG_GLOB_CNT);

    /* Wait for codec ready (up to 1 second) */
    for (timeout = 0; timeout < 1000; timeout++) {
        glob_sta = inl(s->nabmbar + ICH_REG_GLOB_STA);
        if (glob_sta & ICH_GLOB_STA_PCR)
            break;
        IODelay(1000);
    }

    if (!(glob_sta & ICH_GLOB_STA_PCR)) {
        IOLog("%s: Codec ready timeout\n", DRV_TITLE);
        return NO;
    }

    IOLog("%s: Primary codec ready\n", DRV_TITLE);

    /* Initialize AC97 codec */
    if (ich_init_codec(s) < 0) {
        IOLog("%s: Failed to initialize AC97 codec\n", DRV_TITLE);
        return NO;
    }

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
    int             i;
    unsigned int    fragment_size;
    unsigned int    fragments;

    /* Get physical address */
    irtn = IOPhysicalFromVirtual(IOVmTaskSelf(), *physicalAddress, &physAddr);
    if (irtn) {
        IOLog("%s: Failed to map memory\n", DRV_TITLE);
        return NULL;
    }

    /* Calculate fragment size (must be multiple of samples) */
    fragments = ICH_BD_COUNT;
    fragment_size = numBytes / fragments;

    if (isRead) {
        s->in_buffer_phys = physAddr;
        s->in_buffer_size = numBytes;

        /* Allocate buffer descriptor list if not already done */
        if (!s->bdl_input) {
            s->bdl_input = IOMalloc(ICH_BD_SIZE);
            bzero(s->bdl_input, ICH_BD_SIZE);
            IOPhysicalFromVirtual(IOVmTaskSelf(), (unsigned int)s->bdl_input,
                                &s->bdl_input_phys);
        }

        /* Setup buffer descriptors */
        for (i = 0; i < ICH_BD_COUNT; i++) {
            s->bdl_input[i].buffer_addr = physAddr + (i * fragment_size);
            s->bdl_input[i].control = fragment_size | ICH_BD_IOC;
        }

        /* Set buffer descriptor list address */
        outl(s->bdl_input_phys, s->nabmbar + ICH_REG_PI_BDBAR);
    } else {
        s->out_buffer_phys = physAddr;
        s->out_buffer_size = numBytes;
        s->out_fragment_size = fragment_size;

        /* Allocate buffer descriptor list if not already done */
        if (!s->bdl_output) {
            s->bdl_output = IOMalloc(ICH_BD_SIZE);
            bzero(s->bdl_output, ICH_BD_SIZE);
            IOPhysicalFromVirtual(IOVmTaskSelf(), (unsigned int)s->bdl_output,
                                &s->bdl_output_phys);
        }

        /* Setup buffer descriptors */
        for (i = 0; i < ICH_BD_COUNT; i++) {
            s->bdl_output[i].buffer_addr = physAddr + (i * fragment_size);
            s->bdl_output[i].control = fragment_size | ICH_BD_IOC;
        }

        /* Set buffer descriptor list address */
        outl(s->bdl_output_phys, s->nabmbar + ICH_REG_PO_BDBAR);
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
    unsigned char   cr;

    [self updateSampleRate];

    if (isRead) {
        /* Setup PCM In */
        outb(ICH_CR_RR, s->nabmbar + ICH_REG_PI_CR);  /* Reset */
        IODelay(10);
        outb(0, s->nabmbar + ICH_REG_PI_CR);

        /* Set Last Valid Index */
        outb(ICH_BD_COUNT - 1, s->nabmbar + ICH_REG_PI_LVI);

        /* Enable interrupts and start */
        cr = ICH_CR_RPBM | ICH_CR_LVBIE | ICH_CR_IOCE;
        outb(cr, s->nabmbar + ICH_REG_PI_CR);

        s->in_running = YES;
    } else {
        /* Setup PCM Out */
        outb(ICH_CR_RR, s->nabmbar + ICH_REG_PO_CR);  /* Reset */
        IODelay(10);
        outb(0, s->nabmbar + ICH_REG_PO_CR);

        /* Set Last Valid Index */
        s->out_lvi = ICH_BD_COUNT - 1;
        outb(s->out_lvi, s->nabmbar + ICH_REG_PO_LVI);

        /* Enable interrupts and start */
        cr = ICH_CR_RPBM | ICH_CR_LVBIE | ICH_CR_IOCE;
        outb(cr, s->nabmbar + ICH_REG_PO_CR);

        s->out_running = YES;
    }

    [self enableAllInterrupts];

    return YES;
}

/*
 * stopDMAForChannel:read:
 */
- (void)stopDMAForChannel:(unsigned int)localChannel read:(BOOL)isRead
{
    if (isRead) {
        outb(0, s->nabmbar + ICH_REG_PI_CR);
        s->in_running = NO;
    } else {
        outb(0, s->nabmbar + ICH_REG_PO_CR);
        s->out_running = NO;
    }

    [self disableAllInterrupts];
}

/*
 * clearInterrupts - Clear interrupt status
 */
static void clearInterrupts(void)
{
    unsigned char   sr;

    /* Clear PCM Out status */
    sr = inb(s->nabmbar + ICH_REG_PO_SR);
    outb(sr, s->nabmbar + ICH_REG_PO_SR);

    /* Clear PCM In status */
    sr = inb(s->nabmbar + ICH_REG_PI_SR);
    outb(sr, s->nabmbar + ICH_REG_PI_SR);
}

/*
 * interruptClearFunc
 */
- (IOAudioInterruptClearFunc)interruptClearFunc
{
    return clearInterrupts;
}

/*
 * clearInt - Interrupt handler
 */
static void clearInt(void *identity, void *state, unsigned int arg)
{
    unsigned int    glob_sta;
    unsigned char   sr;

    glob_sta = inl(s->nabmbar + ICH_REG_GLOB_STA);

    /* Check if it's our interrupt */
    if (!(glob_sta & (ICH_GLOB_STA_POINT | ICH_GLOB_STA_PIINT)))
        return;

    /* Clear status */
    if (glob_sta & ICH_GLOB_STA_POINT) {
        sr = inb(s->nabmbar + ICH_REG_PO_SR);
        outb(sr, s->nabmbar + ICH_REG_PO_SR);

        if (sr & ICH_SR_BCIS) {
            /* Update current index */
            s->out_civ = inb(s->nabmbar + ICH_REG_PO_CIV);

            /* Call original handler */
            if (oldHandler)
                (*oldHandler)(identity, state, arg);
        }
    }

    if (glob_sta & ICH_GLOB_STA_PIINT) {
        sr = inb(s->nabmbar + ICH_REG_PI_SR);
        outb(sr, s->nabmbar + ICH_REG_PI_SR);
    }

    /* Re-enable interrupt */
    IOEnableInterrupt(identity);
}

/*
 * interruptOccurredForInput:forOutput:
 */
- (void)interruptOccurredForInput:(BOOL *)serviceInput
                        forOutput:(BOOL *)serviceOutput
{
    *serviceInput = NO;
    *serviceOutput = s->out_running;
}

/*
 * getHandler:level:argument:forInterrupt:
 */
- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(unsigned int *)arg
      forInterrupt:(unsigned int)localInterrupt
{
    [super getHandler:&oldHandler level:ipl argument:arg
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

    if (s->codec) {
        ac97_set_rate(s->codec, AC97_RATE_DAC, rate);
        ac97_set_rate(s->codec, AC97_RATE_ADC, rate);
    }
}

/*
 * acceptsContinuousSamplingRates
 */
- (BOOL)acceptsContinuousSamplingRates
{
    return s->codec ? s->codec->caps.vra_supported : NO;
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
    return 2;  /* Stereo */
}

/*
 * updateOutputMute
 */
- (void)updateOutputMute
{
    if (!s->codec)
        return;

    ac97_set_master_volume(s->codec,
                          s->codec->master_vol_l,
                          s->codec->master_vol_r,
                          [self isOutputMuted]);
}

/*
 * updateOutputAttenuationLeft
 */
- (void)updateOutputAttenuationLeft
{
    unsigned char left;

    if (!s->codec)
        return;

    /* Convert from NeXT attenuation to AC97 volume */
    left = ([self outputAttenuationLeft] * 31) / 13;

    ac97_set_master_volume(s->codec, left, s->codec->master_vol_r,
                          [self isOutputMuted]);
}

/*
 * updateOutputAttenuationRight
 */
- (void)updateOutputAttenuationRight
{
    unsigned char right;

    if (!s->codec)
        return;

    /* Convert from NeXT attenuation to AC97 volume */
    right = ([self outputAttenuationRight] * 31) / 13;

    ac97_set_master_volume(s->codec, s->codec->master_vol_l, right,
                          [self isOutputMuted]);
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

/*
 * AC97 codec access functions
 */

static unsigned short
ich_codec_read(void *host_priv, unsigned char reg)
{
    struct ich_state *s = (struct ich_state *)host_priv;
    return inw(s->nambar + reg);
}

static void
ich_codec_write(void *host_priv, unsigned char reg, unsigned short val)
{
    struct ich_state *s = (struct ich_state *)host_priv;
    outw(val, s->nambar + reg);
}

static void
ich_codec_reset(void *host_priv)
{
    /* Hardware reset is done elsewhere */
}

/*
 * ich_init_codec - Initialize AC97 codec
 */
static int
ich_init_codec(struct ich_state *s)
{
    struct ac97_codec_state *codec;

    /* Allocate codec structure */
    codec = IOMalloc(sizeof(struct ac97_codec_state));
    bzero(codec, sizeof(struct ac97_codec_state));

    /* Setup codec callbacks */
    codec->host_priv = s;
    codec->read_reg = ich_codec_read;
    codec->write_reg = ich_codec_write;
    codec->reset = ich_codec_reset;
    codec->host_flags = 0;

    /* Attach codec */
    if (ac97_attach(codec, AC97_CODEC_TYPE_AUDIO) < 0) {
        IOFree(codec, sizeof(struct ac97_codec_state));
        return -1;
    }

    s->codec = codec;
    return 0;
}

/*
 * ich_reset_channels - Reset all DMA channels
 */
static void
ich_reset_channels(struct ich_state *s)
{
    /* Reset PCM Out */
    outb(ICH_CR_RR, s->nabmbar + ICH_REG_PO_CR);
    IODelay(10);
    outb(0, s->nabmbar + ICH_REG_PO_CR);

    /* Reset PCM In */
    outb(ICH_CR_RR, s->nabmbar + ICH_REG_PI_CR);
    IODelay(10);
    outb(0, s->nabmbar + ICH_REG_PI_CR);

    /* Reset Mic In */
    outb(ICH_CR_RR, s->nabmbar + ICH_REG_MC_CR);
    IODelay(10);
    outb(0, s->nabmbar + ICH_REG_MC_CR);
}
