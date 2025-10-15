/*
 * Copyright (c) 2025 RhapsodiOS Project
 *
 * Burgundy Audio Driver Implementation for PowerMac/iMac
 *
 * Based on the AWACS driver structure and Linux burgundy.c
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

#import "PPCBurgundyDriver.h"
#import "burgundy.h"

static const char codecDeviceName[] = "PPCBurgundy";
static const char codecDeviceKind[] = "Audio";

static struct burgundy_state *s = NULL;
static IOInterruptHandler oldHandlerOut = NULL;
static IOInterruptHandler oldHandlerIn = NULL;

@implementation PPCBurgundyDriver

/*
 * Probe and initialize new instance
 */
+ (BOOL)probe:deviceDescription
{
    PPCBurgundyDriver *dev;

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
    const char *compatible;

    /* Verify this is a sound device */
    if (![deviceDescription match:"device_type" location:"sound"]) {
        IOLog("%s: Not a sound device\n", DRV_TITLE);
        return nil;
    }

    /* Check if this is a Burgundy-compatible device */
    if (![deviceDescription match:"compatible" location:"burgundy"]) {
        /* Also check for specific model names */
        if (![deviceDescription match:"name" location:"burgundy"]) {
            IOLog("%s: Not a Burgundy sound device\n", DRV_TITLE);
            return nil;
        }
    }

    /* Allocate control structure */
    s = (struct burgundy_state *)IOMalloc(sizeof(*s));
    if (!s) {
        IOLog("%s: Failed to allocate state structure\n", DRV_TITLE);
        return nil;
    }
    bzero(s, sizeof(*s));
    s->magic = BURGUNDY_MAGIC;

    /* Determine if this is an iMac or PowerMac */
    compatible = [deviceDescription compatibleString];
    if (compatible && strstr(compatible, "imac")) {
        s->is_imac = YES;
        IOLog("%s: Detected iMac model\n", DRV_TITLE);
    } else {
        s->is_imac = NO;
        IOLog("%s: Detected PowerMac model\n", DRV_TITLE);
    }

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
    s->dma_out_base = s->iobase + BURGUNDY_DMA_OUT;
    s->dma_in_base = s->iobase + BURGUNDY_DMA_IN;

    IOLog("%s: Found Burgundy sound chip\n", DRV_TITLE);
    IOLog("%s: I/O Base: 0x%lx\n", DRV_TITLE, (unsigned long)s->iobase);

    /* Allocate DBDMA descriptor memory for output */
    s->dma_out.numfrags = BURGUNDY_DMA_NUM_BUFFERS * 4;  /* 8 descriptors */
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
    s->dma_in.numfrags = BURGUNDY_DMA_NUM_BUFFERS * 4;
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
    s->irq_out = 0;  /* Will be set by device description */
    s->irq_in = 0;

    /* Initialize default audio settings */
    s->sample_rate = 44100;
    s->channels = 2;
    s->format = 16;
    s->master_vol_left = 0xCC;
    s->master_vol_right = 0xCC;
    s->muted = NO;
    s->output_port = BURGUNDY_OUTPUT_INTERN;
    s->input_source = BURGUNDY_INPUT_LINE;

    /* Initialize input gains */
    s->input_gain[0] = DEF_BURGUNDY_GAINCD;
    s->input_gain[1] = DEF_BURGUNDY_GAINLINE;
    s->input_gain[2] = DEF_BURGUNDY_GAINMIC;
    s->input_gain[3] = DEF_BURGUNDY_GAINMODEM;

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

    _burgundy_private = s;

    return self;
}

/*
 * Free driver resources
 */
- free
{
    if (s) {
        /* Stop any ongoing DMA */
        burgundy_stop_dma_out(s);
        burgundy_stop_dma_in(s);

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

    /* Initialize Burgundy chip */
    burgundy_init_chip(s);

    /* Detect headphone and adjust output accordingly */
    [self detectHeadphoneConnection];

    return YES;
}

/*
 * Create DMA buffer - for Burgundy we use DBDMA
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
        burgundy_setup_dma_in(s, physAddr, numBytes);
    else
        burgundy_setup_dma_out(s, physAddr, numBytes);

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
        burgundy_start_dma_out(s);
    } else {
        burgundy_start_dma_in(s);
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
        burgundy_stop_dma_out(s);
    else
        burgundy_stop_dma_in(s);

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
    s->sample_rate = rate;
    /* Burgundy sample rate is typically controlled via I2S clocking */
    /* Implementation would go here for rate switching */
}

/*
 * Accept continuous sampling rates
 */
- (BOOL)acceptsContinuousSamplingRates
{
    return NO;  /* Burgundy has fixed rates */
}

/*
 * Get sampling rate range
 */
- (void)getSamplingRatesLow:(int *)lowRate
                       high:(int *)highRate
{
    *lowRate = 8000;
    *highRate = 48000;
}

/*
 * Get available sampling rates
 */
- (void)getSamplingRates:(int *)rates
                   count:(unsigned int *)numRates
{
    rates[0] = 8000;
    rates[1] = 11025;
    rates[2] = 16000;
    rates[3] = 22050;
    rates[4] = 24000;
    rates[5] = 32000;
    rates[6] = 44100;
    rates[7] = 48000;
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

    /* Convert from NeXT scale to Burgundy scale */
    /* NeXT: 0 to 43 (0 = max, 43 = min) */
    /* Burgundy: 0 to 255 (0 = max, 255 = min) */
    left = (left * 255) / 43;
    right = (right * 255) / 43;

    if (mute) {
        burgundy_set_volume(s, 255, 255);
        burgundy_set_speaker_attenuation(s, 255);
        burgundy_set_headphone_attenuation(s, 255);
    } else {
        burgundy_set_volume(s, left, right);

        /* Adjust output based on headphone connection */
        if ([self isHeadphoneConnected]) {
            burgundy_set_speaker_attenuation(s, 255);  /* Mute speaker */
            burgundy_set_headphone_attenuation(s, 0);  /* Enable headphones */
        } else {
            burgundy_set_speaker_attenuation(s, 0);    /* Enable speaker */
            burgundy_set_headphone_attenuation(s, 255); /* Mute headphones */
        }
    }

    return self;
}

/*
 * Update output mute
 */
- (void)updateOutputMute
{
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

    /* Convert from NeXT scale to Burgundy scale */
    /* NeXT: 0 to 43 (0 = min, 43 = max) */
    /* Burgundy: 0 to 255 (0 = min, 255 = max) */
    left = (left * 255) / 43;
    right = (right * 255) / 43;

    /* Set gain for current input source */
    /* For stereo input, we set both channels to the same source */
    burgundy_set_gain(s, s->input_source, (left + right) / 2);

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
    if (source >= 4)
        return;

    burgundy_set_input_select(s, source);
}

/*
 * Get input source
 */
- (unsigned int)getInputSource
{
    return s->input_source;
}

/*
 * Detect headphone connection
 */
- (void)detectHeadphoneConnection
{
    unsigned int connected = burgundy_detect_headphone(s);

    if (connected) {
        IOLog("%s: Headphones connected\n", DRV_TITLE);
        /* Update output routing */
        [self updateOutputAttenuation];
    } else {
        IOLog("%s: Using internal speaker\n", DRV_TITLE);
        /* Update output routing */
        [self updateOutputAttenuation];
    }
}

/*
 * Check if headphones are connected
 */
- (BOOL)isHeadphoneConnected
{
    return (burgundy_detect_headphone(s) != 0);
}

@end
