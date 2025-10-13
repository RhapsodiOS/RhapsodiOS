/*
 * Copyright (c) 2025 RhapsodiOS Project
 *
 * Burgundy Hardware Control Implementation
 *
 * Based on Linux burgundy.c by Takashi Iwai
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
#import "burgundy.h"

/* Sample rate table - Burgundy supports standard audio rates */
static struct burgundy_rate burgundy_rates[] = {
    { 44100, 0 },
    { 48000, 1 },
    { 32000, 2 },
    { 22050, 3 },
    { 24000, 4 },
    { 16000, 5 },
    { 11025, 6 },
    {  8000, 7 },
    {     0, 0 }
};

/*
 * Busy wait for Burgundy codec to be ready
 */
static void burgundy_busy_wait(struct burgundy_state *s)
{
    volatile unsigned int *codec_status;
    unsigned int timeout = 1000;

    if (!s || !s->iobase)
        return;

    codec_status = (volatile unsigned int *)(s->iobase + BURGUNDY_CODEC_STATUS);

    while (timeout--) {
        eieio();
        if ((*codec_status & 0x01) == 0)
            break;
        IODelay(10);
    }
}

/*
 * Write a byte value to a Burgundy codec register
 */
void burgundy_write_byte(struct burgundy_state *s, unsigned int reg,
                         unsigned int val)
{
    volatile unsigned int *codec_ctrl;
    unsigned int cmd;

    if (!s || !s->iobase)
        return;

    burgundy_busy_wait(s);

    codec_ctrl = (volatile unsigned int *)(s->iobase + BURGUNDY_CODEC_CTRL);
    cmd = (reg << 12) | (val & 0xFF);

    eieio();
    *codec_ctrl = cmd;
    eieio();

    burgundy_busy_wait(s);
}

/*
 * Write a word (32-bit) value to a Burgundy codec register
 */
void burgundy_write_word(struct burgundy_state *s, unsigned int reg,
                         unsigned int val)
{
    volatile unsigned int *codec_ctrl;
    unsigned int cmd;

    if (!s || !s->iobase)
        return;

    burgundy_busy_wait(s);

    codec_ctrl = (volatile unsigned int *)(s->iobase + BURGUNDY_CODEC_CTRL);

    /* Write high byte */
    cmd = (reg << 12) | ((val >> 24) & 0xFF);
    eieio();
    *codec_ctrl = cmd;
    eieio();

    /* Write mid-high byte */
    cmd = (reg << 12) | ((val >> 16) & 0xFF);
    eieio();
    *codec_ctrl = cmd;
    eieio();

    /* Write mid-low byte */
    cmd = (reg << 12) | ((val >> 8) & 0xFF);
    eieio();
    *codec_ctrl = cmd;
    eieio();

    /* Write low byte */
    cmd = (reg << 12) | (val & 0xFF);
    eieio();
    *codec_ctrl = cmd;
    eieio();

    burgundy_busy_wait(s);
}

/*
 * Read a byte value from a Burgundy codec register
 */
unsigned int burgundy_read_byte(struct burgundy_state *s, unsigned int reg)
{
    volatile unsigned int *codec_ctrl;
    volatile unsigned int *codec_status;
    unsigned int cmd, val;

    if (!s || !s->iobase)
        return 0;

    burgundy_busy_wait(s);

    codec_ctrl = (volatile unsigned int *)(s->iobase + BURGUNDY_CODEC_CTRL);
    codec_status = (volatile unsigned int *)(s->iobase + BURGUNDY_CODEC_STATUS);

    /* Send read command */
    cmd = (reg << 12) | 0x100;  /* Set read bit */
    eieio();
    *codec_ctrl = cmd;
    eieio();

    burgundy_busy_wait(s);

    eieio();
    val = *codec_status & 0xFF;
    eieio();

    return val;
}

/*
 * Read a word (32-bit) value from a Burgundy codec register
 */
unsigned int burgundy_read_word(struct burgundy_state *s, unsigned int reg)
{
    unsigned int val = 0;

    if (!s)
        return 0;

    val = burgundy_read_byte(s, reg) << 24;
    val |= burgundy_read_byte(s, reg) << 16;
    val |= burgundy_read_byte(s, reg) << 8;
    val |= burgundy_read_byte(s, reg);

    return val;
}

/*
 * Set master volume/attenuation
 */
void burgundy_set_volume(struct burgundy_state *s, int left, int right)
{
    unsigned int vol;

    if (!s)
        return;

    /* Clamp values to valid range (0-255) */
    if (left < 0) left = 0;
    if (left > 255) left = 255;
    if (right < 0) right = 0;
    if (right > 255) right = 255;

    s->master_vol_left = left;
    s->master_vol_right = right;

    /* Burgundy uses 16-bit values, left in high word, right in low word */
    vol = (left << 24) | (right << 16);

    burgundy_write_word(s, MASK_ADDR_BURGUNDY_MASTER_VOLUME >> 12, vol);
}

/*
 * Set gain for a specific input channel
 */
void burgundy_set_gain(struct burgundy_state *s, unsigned int channel,
                       unsigned int gain)
{
    unsigned int reg;

    if (!s || channel >= 4)
        return;

    /* Clamp gain to valid range */
    if (gain > 255)
        gain = 255;

    s->input_gain[channel] = gain;

    /* Select the appropriate gain register */
    switch (channel) {
        case 0:
            reg = MASK_ADDR_BURGUNDY_GAINCH1 >> 12;
            break;
        case 1:
            reg = MASK_ADDR_BURGUNDY_GAINCH2 >> 12;
            break;
        case 2:
            reg = MASK_ADDR_BURGUNDY_GAINCH3 >> 12;
            break;
        case 3:
            reg = MASK_ADDR_BURGUNDY_GAINCH4 >> 12;
            break;
        default:
            return;
    }

    burgundy_write_byte(s, reg, gain);
}

/*
 * Set input source selection
 */
void burgundy_set_input_select(struct burgundy_state *s, unsigned int input)
{
    unsigned int inpsel21, inpsel3;

    if (!s)
        return;

    s->input_source = input;

    /* Set input selection based on model type */
    if (s->is_imac) {
        inpsel21 = DEF_BURGUNDY_INPSEL21_IMAC;
        inpsel3 = DEF_BURGUNDY_INPSEL3_IMAC;
    } else {
        inpsel21 = DEF_BURGUNDY_INPSEL21_PMAC;
        inpsel3 = DEF_BURGUNDY_INPSEL3_PMAC;
    }

    burgundy_write_byte(s, MASK_ADDR_BURGUNDY_INPSEL21 >> 12, inpsel21);
    burgundy_write_byte(s, MASK_ADDR_BURGUNDY_INPSEL3 >> 12, inpsel3);
}

/*
 * Set output selection
 */
void burgundy_set_output_select(struct burgundy_state *s, unsigned int output)
{
    if (!s)
        return;

    s->output_port = output;

    burgundy_write_word(s, MASK_ADDR_BURGUNDY_OUTPUTSELECTS >> 12,
                        DEF_BURGUNDY_OUTPUTSELECTS);
    burgundy_write_byte(s, MASK_ADDR_BURGUNDY_OUTPUTENABLES >> 12,
                        DEF_BURGUNDY_OUTPUTENABLES);
}

/*
 * Set speaker attenuation
 */
void burgundy_set_speaker_attenuation(struct burgundy_state *s,
                                      unsigned int atten)
{
    if (!s)
        return;

    /* Burgundy speaker attenuation is 8-bit */
    if (atten > 255)
        atten = 255;

    burgundy_write_byte(s, MASK_ADDR_BURGUNDY_ATTENSPEAKER >> 12, atten);
}

/*
 * Set headphone attenuation
 */
void burgundy_set_headphone_attenuation(struct burgundy_state *s,
                                        unsigned int atten)
{
    if (!s)
        return;

    /* Burgundy headphone attenuation is 8-bit */
    if (atten > 255)
        atten = 255;

    burgundy_write_byte(s, MASK_ADDR_BURGUNDY_ATTENHP >> 12, atten);
}

/*
 * Set line out attenuation
 */
void burgundy_set_lineout_attenuation(struct burgundy_state *s,
                                      unsigned int atten)
{
    if (!s)
        return;

    /* Burgundy line out attenuation is 8-bit */
    if (atten > 255)
        atten = 255;

    burgundy_write_byte(s, MASK_ADDR_BURGUNDY_ATTENLINEOUT >> 12, atten);
}

/*
 * Detect headphone connection
 */
unsigned int burgundy_detect_headphone(struct burgundy_state *s)
{
    unsigned int status;

    if (!s)
        return 0;

    /* Read status from the appropriate register based on model */
    status = burgundy_read_byte(s, MASK_ADDR_BURGUNDY_OUTPUTENABLES >> 12);

    if (s->is_imac) {
        /* iMac headphone detection */
        return (status & BURGUNDY_HPDETECT_IMAC_UPPER) ? 1 : 0;
    } else {
        /* PowerMac headphone detection */
        return (status & BURGUNDY_HPDETECT_PMAC_FRONT) ? 1 : 0;
    }
}

/*
 * Reset Burgundy chip
 */
void burgundy_reset_chip(struct burgundy_state *s)
{
    volatile unsigned int *sound_ctrl;

    if (!s || !s->iobase)
        return;

    sound_ctrl = (volatile unsigned int *)(s->iobase + BURGUNDY_SOUND_CTRL);

    /* Stop sound chip */
    eieio();
    *sound_ctrl &= ~BURGUNDY_CTL_RUN;
    eieio();

    IODelay(1000);

    /* Start sound chip */
    eieio();
    *sound_ctrl |= BURGUNDY_CTL_RUN;
    eieio();

    IODelay(1000);
}

/*
 * Initialize Burgundy chip to default state
 */
void burgundy_init_chip(struct burgundy_state *s)
{
    if (!s)
        return;

    burgundy_reset_chip(s);

    /* Initialize input boost */
    burgundy_write_byte(s, MASK_ADDR_BURGUNDY_INPBOOST >> 12, 0x00);

    /* Initialize input selections */
    burgundy_set_input_select(s, BURGUNDY_INPUT_LINE);

    /* Initialize gains with defaults */
    burgundy_set_gain(s, 0, DEF_BURGUNDY_GAINCD);
    burgundy_set_gain(s, 1, DEF_BURGUNDY_GAINLINE);
    burgundy_set_gain(s, 2, DEF_BURGUNDY_GAINMIC);
    burgundy_set_gain(s, 3, DEF_BURGUNDY_GAINMODEM);

    /* Initialize volumes */
    burgundy_write_word(s, MASK_ADDR_BURGUNDY_VOLCH1 >> 12,
                        DEF_BURGUNDY_VOLCD);
    burgundy_write_word(s, MASK_ADDR_BURGUNDY_VOLCH2 >> 12,
                        DEF_BURGUNDY_VOLLINE);
    burgundy_write_word(s, MASK_ADDR_BURGUNDY_VOLCH3 >> 12,
                        DEF_BURGUNDY_VOLMIC);
    burgundy_write_word(s, MASK_ADDR_BURGUNDY_VOLCH4 >> 12,
                        DEF_BURGUNDY_VOLMODEM);

    /* Set master volume (mid-level) */
    burgundy_set_volume(s, 0xCC, 0xCC);

    /* Initialize output selections */
    burgundy_set_output_select(s, BURGUNDY_OUTPUT_INTERN);

    /* Initialize attenuation values */
    burgundy_set_speaker_attenuation(s, 0);
    burgundy_set_headphone_attenuation(s, 0);
    burgundy_set_lineout_attenuation(s, 0);
}

/*
 * Setup output DMA
 */
void burgundy_setup_dma_out(struct burgundy_state *s, IOPhysicalAddress addr,
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
void burgundy_setup_dma_in(struct burgundy_state *s, IOPhysicalAddress addr,
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
void burgundy_start_dma_out(struct burgundy_state *s)
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
void burgundy_start_dma_in(struct burgundy_state *s)
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
void burgundy_stop_dma_out(struct burgundy_state *s)
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
void burgundy_stop_dma_in(struct burgundy_state *s)
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
