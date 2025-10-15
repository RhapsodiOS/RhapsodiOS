/*
 * Copyright (c) 2025 RhapsodiOS Project
 *
 * AWACS Audio Driver Implementation for PowerMac/PowerBook
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/ppc/IOTreeDevice.h>
#import <driverkit/ppc/IODBDMA.h>
#import <kernserv/prototypes.h>
#import <machdep/ppc/proc_reg.h>

#import "PPCAwacsDriver.h"
#import "awacs.h"

static const char codecDeviceName[] = "PPCAwacs";
static const char codecDeviceKind[] = "Audio";

static struct awacs_state *s = NULL;
static IOInterruptHandler oldHandlerOut = NULL;
static IOInterruptHandler oldHandlerIn = NULL;

@implementation PPCAwacsDriver

/*
 * Probe and initialize new instance
 */
+ (BOOL)probe:deviceDescription
{
    PPCAwacsDriver *dev;

    dev = [self alloc];
    if (dev == nil)
        return NO;

    return ([dev initFromDeviceDescription:deviceDescription] != nil);
}

/*
 * Initialize new instance from device description
 */
- initFromDeviceDescription:deviceDescription
{
    IOReturn irtn;
    IOApertureInfo apertures[8];
    UInt32 numApertures = 8;
    IOPhysicalAddress descPhys;
    IOVirtualAddress descVirt;
    int i;

    /* Verify this is an AWACS device */
    if (![deviceDescription match:"device_type" location:"sound"]) {
        IOLog("%s: Not a sound device\n", DRV_TITLE);
        return nil;
    }

    /* Allocate control structure */
    s = (struct awacs_state *)IOMalloc(sizeof(*s));
    if (!s) {
        IOLog("%s: Failed to allocate state structure\n", DRV_TITLE);
        return nil;
    }
    bzero(s, sizeof(*s));
    s->magic = AWACS_MAGIC;

    /* Get hardware resources from device tree */
    irtn = [(IOTreeDevice *)deviceDescription getApertures:apertures
                                                     items:&numApertures];
    if (irtn != IO_R_SUCCESS || numApertures < 1) {
        IOLog("%s: Failed to get apertures\n", DRV_TITLE);
        IOFree(s, sizeof(*s));
        return nil;
    }

    /* Map the sound chip registers */
    s->iobase = apertures[0].logical;

    /* Map DBDMA channels */
    s->dma_out_base = s->iobase + AWACS_DMA_OUT;
    s->dma_in_base = s->iobase + AWACS_DMA_IN;

    IOLog("%s: Found AWACS sound chip\n", DRV_TITLE);
    IOLog("%s: I/O Base: 0x%lx\n", DRV_TITLE, (unsigned long)s->iobase);

    /* Allocate DBDMA descriptor memory for output */
    s->dma_out.numfrags = AWACS_DMA_NUM_BUFFERS * 4;  /* 8 descriptors */
    irtn = IOAllocatePhysicallyContiguousMemory(
        s->dma_out.numfrags * sizeof(IODBDMADescriptor),
        0,
        &descVirt,
        &descPhys);
    if (irtn != IO_R_SUCCESS) {
        IOLog("%s: Failed to allocate DMA output descriptors\n", DRV_TITLE);
        IOFree(s, sizeof(*s));
        return nil;
    }
    s->dma_out.desc = (IODBDMADescriptor *)descVirt;
    s->dma_out.desc_phys = descPhys;

    /* Allocate DBDMA descriptor memory for input */
    s->dma_in.numfrags = AWACS_DMA_NUM_BUFFERS * 4;
    irtn = IOAllocatePhysicallyContiguousMemory(
        s->dma_in.numfrags * sizeof(IODBDMADescriptor),
        0,
        &descVirt,
        &descPhys);
    if (irtn != IO_R_SUCCESS) {
        IOLog("%s: Failed to allocate DMA input descriptors\n", DRV_TITLE);
        IOFreePhysicallyContiguousMemory(
            (IOVirtualAddress *)&s->dma_out.desc,
            s->dma_out.numfrags * sizeof(IODBDMADescriptor));
        IOFree(s, sizeof(*s));
        return nil;
    }
    s->dma_in.desc = (IODBDMADescriptor *)descVirt;
    s->dma_in.desc_phys = descPhys;

    /* Get interrupts from device tree */
    /* For AWACS, we typically have one interrupt for output */
    s->irq_out = 0;  /* Will be set by device description */
    s->irq_in = 0;

    /* Initialize default audio settings */
    s->sample_rate = 44100;
    s->channels = 2;
    s->format = 16;
    s->vol_left = 8;
    s->vol_right = 8;
    s->muted = NO;
    s->output_port = AWACS_CTL_SPEAKER;
    s->input_source = AWACS_INPUT_LINE;
    s->input_gain_left = 8;
    s->input_gain_right = 8;

    /* Initialize IOAudio superclass */
    if (![super initFromDeviceDescription:deviceDescription]) {
        IOLog("%s: Failed on [super init]\n", DRV_TITLE);
        IOFreePhysicallyContiguousMemory(
            (IOVirtualAddress *)&s->dma_out.desc,
            s->dma_out.numfrags * sizeof(IODBDMADescriptor));
        IOFreePhysicallyContiguousMemory(
            (IOVirtualAddress *)&s->dma_in.desc,
            s->dma_in.numfrags * sizeof(IODBDMADescriptor));
        IOFree(s, sizeof(*s));
        return nil;
    }

    _awacs_private = s;

    return self;
}

/*
 * Free driver resources
 */
- free
{
    if (s) {
        /* Stop any ongoing DMA */
        awacs_stop_dma_out(s);
        awacs_stop_dma_in(s);

        /* Free DBDMA descriptors */
        if (s->dma_out.desc) {
            IOFreePhysicallyContiguousMemory(
                (IOVirtualAddress *)&s->dma_out.desc,
                s->dma_out.numfrags * sizeof(IODBDMADescriptor));
        }
        if (s->dma_in.desc) {
            IOFreePhysicallyContiguousMemory(
                (IOVirtualAddress *)&s->dma_in.desc,
                s->dma_in.numfrags * sizeof(IODBDMADescriptor));
        }

        /* Free state structure */
        IOFree(s, sizeof(*s));
        s = NULL;
    }

    return [super free];
}

/*
 * Reset hardware and set device name
 */
- (BOOL)reset
{
    [self setName:codecDeviceName];
    [self setDeviceKind:codecDeviceKind];

    /* Initialize AWACS chip */
    awacs_init_chip(s);

    return YES;
}

/*
 * Create DMA buffer - for AWACS we use DBDMA
 */
- (IOEISADMABuffer)createDMABufferFor:(unsigned int *)physicalAddress
                               length:(unsigned int)numBytes
                                 read:(BOOL)isRead
                       needsLowMemory:(BOOL)lowerMem
                            limitSize:(BOOL)limitSize
{
    IOReturn irtn;
    unsigned int physAddr;

    /* Get physical address of buffer */
    irtn = IOPhysicalFromVirtual(IOVmTaskSelf(), *physicalAddress, &physAddr);
    if (irtn) {
        IOLog("%s: Fatal, couldn't map memory\n", DRV_TITLE);
        return NULL;
    }

    /* Setup DBDMA for the buffer */
    if (isRead)
        awacs_setup_dma_in(s, physAddr, numBytes);
    else
        awacs_setup_dma_out(s, physAddr, numBytes);

    return (IOEISADMABuffer)physAddr;
}

/*
 * Start DMA for specified channel
 */
- (BOOL)startDMAForChannel:(unsigned int)localChannel
                      read:(BOOL)isRead
                    buffer:(IOEISADMABuffer)buffer
   bufferSizeForInterrupts:(unsigned int)bufferSize
{
    unsigned int encoding;
    unsigned int mode;

    /* Get current audio settings */
    encoding = [self dataEncoding];
    mode = [self channelCount];

    /* Set format based on encoding */
    if (encoding == NX_SoundStreamDataEncoding_Linear16)
        s->format = 16;
    else if (encoding == NX_SoundStreamDataEncoding_Linear8)
        s->format = 8;

    s->channels = mode;

    /* Update sample rate */
    [self updateSampleRate];

    /* Enable interrupts */
    (void)[self enableAllInterrupts];

    /* Start DMA */
    if (!isRead) {
        awacs_start_dma_out(s);
    } else {
        awacs_start_dma_in(s);
    }

    return YES;
}

/*
 * Stop DMA for specified channel
 */
- (void)stopDMAForChannel:(unsigned int)localChannel
                     read:(BOOL)isRead
{
    if (!isRead)
        awacs_stop_dma_out(s);
    else
        awacs_stop_dma_in(s);

    (void)[self disableAllInterrupts];
}

/*
 * Clear interrupts
 */
static void clearInterrupts(void)
{
    /* DBDMA clears interrupts automatically */
    return;
}

/*
 * Return the clear function
 */
- (IOAudioInterruptClearFunc)interruptClearFunc
{
    return clearInterrupts;
}

/*
 * Interrupt handler
 */
static void handleInterrupt(void *identity, void *state, unsigned int arg)
{
    volatile IODBDMAChannelRegisters *dma;
    unsigned int status;

    if (!s)
        return;

    /* Check output DMA */
    dma = (volatile IODBDMAChannelRegisters *)s->dma_out_base;
    status = IOGetDBDMAChannelStatus(dma);

    if (status & kdbdmaActive) {
        /* Call original handler */
        if (oldHandlerOut)
            (*oldHandlerOut)(identity, state, arg);
    }

    /* Support for shared IRQs */
    IOEnableInterrupt(identity);
}

/*
 * Interrupt occurred
 */
- (void)interruptOccurredForInput:(BOOL *)serviceInput
                        forOutput:(BOOL *)serviceOutput
{
    *serviceOutput = NO;
    *serviceInput = NO;

    /* Check if we should service output */
    if (s->dma_out.running) {
        *serviceOutput = YES;
    }

    /* Check if we should service input */
    if (s->dma_in.running) {
        *serviceInput = YES;
    }
}

/*
 * Get interrupt handler
 */
- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(unsigned int *)arg
      forInterrupt:(unsigned int)localInterrupt
{
    /* Get original handler */
    [super getHandler:&oldHandlerOut
                level:ipl
             argument:arg
         forInterrupt:localInterrupt];

    /* Set our handler */
    *handler = handleInterrupt;

    return YES;
}

/*
 * Timeout occurred
 */
- (void)timeoutOccurred
{
    IOLog("%s: Timeout waiting for interrupt\n", DRV_TITLE);
}

/*
 * Update sample rate
 */
- (void)updateSampleRate
{
    unsigned int rate = [self sampleRate];
    awacs_set_rate(s, rate);
}

/*
 * Accept continuous sampling rates
 */
- (BOOL)acceptsContinuousSamplingRates
{
    return NO;  /* AWACS has fixed rates */
}

/*
 * Get sampling rate range
 */
- (void)getSamplingRatesLow:(int *)lowRate
                       high:(int *)highRate
{
    *lowRate = 7350;
    *highRate = 44100;
}

/*
 * Get available sampling rates
 */
- (void)getSamplingRates:(int *)rates
                   count:(unsigned int *)numRates
{
    rates[0] = 7350;
    rates[1] = 8820;
    rates[2] = 11025;
    rates[3] = 14700;
    rates[4] = 17640;
    rates[5] = 22050;
    rates[6] = 29400;
    rates[7] = 44100;
    *numRates = 8;
}

/*
 * Get data encodings
 */
- (void)getDataEncodings:(NXSoundParameterTag *)encodings
                   count:(unsigned int *)numEncodings
{
    encodings[0] = NX_SoundStreamDataEncoding_Linear8;
    encodings[1] = NX_SoundStreamDataEncoding_Linear16;
    *numEncodings = 2;
}

/*
 * Channel count limit
 */
- (unsigned int)channelCountLimit
{
    return 2;  /* Stereo */
}

/*
 * Update output attenuation
 */
- updateOutputAttenuation
{
    unsigned int left = [self outputAttenuationLeft];
    unsigned int right = [self outputAttenuationRight];
    BOOL mute = [self isOutputMuted];

    /* Convert from NeXT scale to AWACS scale */
    /* NeXT: 0 to 43 (0 = max, 43 = min) */
    /* AWACS: 0 to 15 (0 = max, 15 = min) */
    left = (left * 15) / 43;
    right = (right * 15) / 43;

    if (mute) {
        awacs_set_volume(s, AWACS_ATTN_MAX, AWACS_ATTN_MAX);
    } else {
        awacs_set_volume(s, 15 - left, 15 - right);
    }

    return self;
}

/*
 * Update output mute
 */
- (void)updateOutputMute
{
    BOOL mute = [self isOutputMuted];

    /* Mute both speakers and headphones when output is muted */
    awacs_set_speaker_mute(s, mute);
    awacs_set_headphone_mute(s, mute);

    /* Also update attenuation */
    [self updateOutputAttenuation];
}

/*
 * Update left output attenuation
 */
- (void)updateOutputAttenuationLeft
{
    [self updateOutputAttenuation];
}

/*
 * Update right output attenuation
 */
- (void)updateOutputAttenuationRight
{
    [self updateOutputAttenuation];
}

/*
 * Update input gain
 */
- updateInputGain
{
    unsigned int left = [self inputGainLeft];
    unsigned int right = [self inputGainRight];

    /* Convert from NeXT scale to AWACS scale */
    /* NeXT: 0 to 43 (0 = min, 43 = max) */
    /* AWACS: 0 to 15 (0 = min, 15 = max) */
    left = (left * 15) / 43;
    right = (right * 15) / 43;

    awacs_set_input_gain(s, left, right);

    return self;
}

/*
 * Update left input gain
 */
- (void)updateInputGainLeft
{
    [self updateInputGain];
}

/*
 * Update right input gain
 */
- (void)updateInputGainRight
{
    [self updateInputGain];
}

/*
 * Set input source
 */
- (void)setInputSource:(unsigned int)source
{
    awacs_set_input_source(s, source);
}

/*
 * Get input source
 */
- (unsigned int)getInputSource
{
    return s->input_source;
}

@end
