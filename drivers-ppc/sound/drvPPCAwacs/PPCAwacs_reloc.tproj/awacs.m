/*
 * Copyright (c) 2025 RhapsodiOS Project
 *
 * AWACS Hardware Control Implementation
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <kernserv/prototypes.h>
#import <driverkit/ppc/IODBDMA.h>
#import <machdep/ppc/proc_reg.h>
#import "awacs.h"

/* Sample rate table */
static struct awacs_rate awacs_rates[] = {
    { 44100, AWACS_RATE_44100 },
    { 29400, AWACS_RATE_29400 },
    { 22050, AWACS_RATE_22050 },
    { 17640, AWACS_RATE_17640 },
    { 14700, AWACS_RATE_14700 },
    { 11025, AWACS_RATE_11025 },
    {  8820, AWACS_RATE_8820  },
    {  7350, AWACS_RATE_7350  },
    {     0, 0 }
};

/*
 * Write a value to an AWACS codec register
 */
void awacs_write_codec(struct awacs_state *s, int reg, int val)
{
    volatile unsigned int *codec_ctrl;
    unsigned int cmd;
    int i;

    if (!s || !s->iobase)
        return;

    codec_ctrl = (volatile unsigned int *)(s->iobase + AWACS_CODEC_CTRL);
    cmd = AWACS_MAKE_CODEC_CMD(reg, val);

    /* Write command */
    eieio();
    *codec_ctrl = cmd;
    eieio();

    /* Wait for codec to accept command (simple delay) */
    for (i = 0; i < 1000; i++) {
        eieio();
        IODelay(1);
    }
}

/*
 * Read AWACS codec status register
 */
unsigned int awacs_read_status(struct awacs_state *s)
{
    volatile unsigned int *codec_status;

    if (!s || !s->iobase)
        return 0;

    codec_status = (volatile unsigned int *)(s->iobase + AWACS_CODEC_STATUS);

    eieio();
    return *codec_status;
}

/*
 * Set volume/attenuation
 */
void awacs_set_volume(struct awacs_state *s, int left, int right)
{
    if (!s)
        return;

    /* Clamp values */
    if (left < AWACS_ATTN_MIN) left = AWACS_ATTN_MIN;
    if (left > AWACS_ATTN_MAX) left = AWACS_ATTN_MAX;
    if (right < AWACS_ATTN_MIN) right = AWACS_ATTN_MIN;
    if (right > AWACS_ATTN_MAX) right = AWACS_ATTN_MAX;

    s->vol_left = left;
    s->vol_right = right;

    /* Write to codec - attenuation is inverted (0 = max, 15 = min) */
    awacs_write_codec(s, AWACS_CODEC_ATTN_L, AWACS_ATTN_MAX - left);
    awacs_write_codec(s, AWACS_CODEC_ATTN_R, AWACS_ATTN_MAX - right);
}

/*
 * Set sample rate
 */
void awacs_set_rate(struct awacs_state *s, unsigned int rate)
{
    int i;
    unsigned int rate_val = AWACS_RATE_44100;

    if (!s)
        return;

    /* Find closest matching rate */
    for (i = 0; awacs_rates[i].rate != 0; i++) {
        if (awacs_rates[i].rate == rate) {
            rate_val = awacs_rates[i].value;
            break;
        }
    }

    s->sample_rate = rate;

    /* Set rate in control register */
    awacs_write_codec(s, AWACS_CODEC_CONTROL,
                     AWACS_CONTROL_RECALIBRATE | rate_val);
}

/*
 * Set output port (headphones, speaker, line out)
 */
void awacs_set_output_port(struct awacs_state *s, unsigned int port)
{
    volatile unsigned int *sound_ctrl;

    if (!s || !s->iobase)
        return;

    sound_ctrl = (volatile unsigned int *)(s->iobase + AWACS_SOUND_CTRL);

    eieio();
    *sound_ctrl = (*sound_ctrl & ~AWACS_CTL_PORT_MASK) | port;
    eieio();

    s->output_port = port;
}

/*
 * Set input source (CD, Line, Microphone)
 */
void awacs_set_input_source(struct awacs_state *s, unsigned int source)
{
    unsigned int ctrl_val;

    if (!s)
        return;

    /* Validate input source */
    if (source != AWACS_INPUT_CD &&
        source != AWACS_INPUT_LINE &&
        source != AWACS_INPUT_MICROPHONE) {
        source = AWACS_INPUT_LINE;  /* Default to line input */
    }

    s->input_source = source;

    /* Read current control register value (we'll use recalibrate as base) */
    ctrl_val = AWACS_CONTROL_RECALIBRATE;

    /* Get current rate setting */
    for (int i = 0; awacs_rates[i].rate != 0; i++) {
        if (awacs_rates[i].rate == s->sample_rate) {
            ctrl_val |= awacs_rates[i].value;
            break;
        }
    }

    /* Clear input mask and set new input source */
    ctrl_val = (ctrl_val & ~AWACS_INPUT_MASK) | source;

    /* Write to control register */
    awacs_write_codec(s, AWACS_CODEC_CONTROL, ctrl_val);
}

/*
 * Set input gain (0-15 for each channel)
 */
void awacs_set_input_gain(struct awacs_state *s, int left, int right)
{
    if (!s)
        return;

    /* Clamp values */
    if (left < 0) left = 0;
    if (left > 15) left = 15;
    if (right < 0) right = 0;
    if (right > 15) right = 15;

    s->input_gain_left = left;
    s->input_gain_right = right;

    /* The input gain is set in the upper 4 bits of the attenuation registers */
    /* when used for input (this is simplified - actual implementation may vary) */
    /* For now, we'll store these for future use with input recording */
}

/*
 * Mute or unmute the speaker
 */
void awacs_set_speaker_mute(struct awacs_state *s, BOOL mute)
{
    unsigned int val = 0;

    if (!s)
        return;

    if (mute)
        val = AWACS_MUTE_SPEAKER;

    awacs_write_codec(s, AWACS_CODEC_SPEAKERS, val);
}

/*
 * Mute or unmute the headphones
 */
void awacs_set_headphone_mute(struct awacs_state *s, BOOL mute)
{
    unsigned int val = 0;

    if (!s)
        return;

    if (mute)
        val = AWACS_MUTE_HEADPHONE;

    awacs_write_codec(s, AWACS_CODEC_HEADPHONES, val);
}

/*
 * Reset AWACS chip
 */
void awacs_reset_chip(struct awacs_state *s)
{
    volatile unsigned int *sound_ctrl;

    if (!s || !s->iobase)
        return;

    sound_ctrl = (volatile unsigned int *)(s->iobase + AWACS_SOUND_CTRL);

    /* Stop sound chip */
    eieio();
    *sound_ctrl &= ~AWACS_CTL_RUN;
    eieio();

    IODelay(1000);

    /* Start sound chip */
    eieio();
    *sound_ctrl |= AWACS_CTL_RUN;
    eieio();

    IODelay(1000);
}

/*
 * Initialize AWACS chip to default state
 */
void awacs_init_chip(struct awacs_state *s)
{
    if (!s)
        return;

    awacs_reset_chip(s);

    /* Set default sample rate */
    awacs_set_rate(s, 44100);

    /* Set default volume (mid-level) */
    awacs_set_volume(s, 8, 8);

    /* Set default output to speaker */
    awacs_set_output_port(s, AWACS_CTL_SPEAKER);

    /* Unmute speakers and headphones */
    awacs_set_speaker_mute(s, NO);
    awacs_set_headphone_mute(s, NO);

    /* Set default input source to line */
    awacs_set_input_source(s, AWACS_INPUT_LINE);

    /* Set default input gain */
    awacs_set_input_gain(s, 8, 8);
}

/*
 * Setup output DMA
 */
void awacs_setup_dma_out(struct awacs_state *s, IOPhysicalAddress addr,
                         unsigned int size)
{
    volatile IODBDMAChannelRegisters *dma;
    IODBDMADescriptor *desc;
    int i;

    if (!s || !s->dma_out_base || !s->dma_out.desc)
        return;

    dma = (volatile IODBDMAChannelRegisters *)s->dma_out_base;
    desc = s->dma_out.desc;

    s->dma_out.buffer_phys = addr;
    s->dma_out.buffer_size = size;
    s->dma_out.fragsize = size / s->dma_out.numfrags;

    /* Create DBDMA descriptor list */
    for (i = 0; i < s->dma_out.numfrags; i++) {
        IOPhysicalAddress frag_addr = addr + (i * s->dma_out.fragsize);

        /* Create descriptor for this fragment */
        IOMakeDBDMADescriptor(&desc[i],
                             kdbdmaOutputMore,
                             kdbdmaKeyStream0,
                             kdbdmaIntAlways,
                             kdbdmaBranchNever,
                             kdbdmaWaitNever,
                             s->dma_out.fragsize,
                             frag_addr);
    }

    /* Make last descriptor loop back to first */
    IOSetCCCmdDep(&desc[s->dma_out.numfrags - 1], s->dma_out.desc_phys);

    s->dma_out.ready = YES;
}

/*
 * Setup input DMA
 */
void awacs_setup_dma_in(struct awacs_state *s, IOPhysicalAddress addr,
                        unsigned int size)
{
    volatile IODBDMAChannelRegisters *dma;
    IODBDMADescriptor *desc;
    int i;

    if (!s || !s->dma_in_base || !s->dma_in.desc)
        return;

    dma = (volatile IODBDMAChannelRegisters *)s->dma_in_base;
    desc = s->dma_in.desc;

    s->dma_in.buffer_phys = addr;
    s->dma_in.buffer_size = size;
    s->dma_in.fragsize = size / s->dma_in.numfrags;

    /* Create DBDMA descriptor list */
    for (i = 0; i < s->dma_in.numfrags; i++) {
        IOPhysicalAddress frag_addr = addr + (i * s->dma_in.fragsize);

        IOMakeDBDMADescriptor(&desc[i],
                             kdbdmaInputMore,
                             kdbdmaKeyStream0,
                             kdbdmaIntAlways,
                             kdbdmaBranchNever,
                             kdbdmaWaitNever,
                             s->dma_in.fragsize,
                             frag_addr);
    }

    /* Make last descriptor loop back to first */
    IOSetCCCmdDep(&desc[s->dma_in.numfrags - 1], s->dma_in.desc_phys);

    s->dma_in.ready = YES;
}

/*
 * Start output DMA
 */
void awacs_start_dma_out(struct awacs_state *s)
{
    volatile IODBDMAChannelRegisters *dma;

    if (!s || !s->dma_out_base || !s->dma_out.ready)
        return;

    dma = (volatile IODBDMAChannelRegisters *)s->dma_out_base;

    if (!s->dma_out.running) {
        IODBDMAReset(dma);
        IOSetDBDMACommandPtr(dma, s->dma_out.desc_phys);
        IODBDMAStart(dma, s->dma_out.desc);
        s->dma_out.running = YES;
    }
}

/*
 * Start input DMA
 */
void awacs_start_dma_in(struct awacs_state *s)
{
    volatile IODBDMAChannelRegisters *dma;

    if (!s || !s->dma_in_base || !s->dma_in.ready)
        return;

    dma = (volatile IODBDMAChannelRegisters *)s->dma_in_base;

    if (!s->dma_in.running) {
        IODBDMAReset(dma);
        IOSetDBDMACommandPtr(dma, s->dma_in.desc_phys);
        IODBDMAStart(dma, s->dma_in.desc);
        s->dma_in.running = YES;
    }
}

/*
 * Stop output DMA
 */
void awacs_stop_dma_out(struct awacs_state *s)
{
    volatile IODBDMAChannelRegisters *dma;

    if (!s || !s->dma_out_base)
        return;

    dma = (volatile IODBDMAChannelRegisters *)s->dma_out_base;

    if (s->dma_out.running) {
        IODBDMAStop(dma);
        s->dma_out.running = NO;
    }
}

/*
 * Stop input DMA
 */
void awacs_stop_dma_in(struct awacs_state *s)
{
    volatile IODBDMAChannelRegisters *dma;

    if (!s || !s->dma_in_base)
        return;

    dma = (volatile IODBDMAChannelRegisters *)s->dma_in_base;

    if (s->dma_in.running) {
        IODBDMAStop(dma);
        s->dma_in.running = NO;
    }
}
