/*
 * Copyright (c) 2025 RhapsodiOS Project
 *
 * AWACS (Apple Wavetable Audio Chip Set) Hardware Definitions
 * for PowerMac and PowerBook systems
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

#ifndef _AWACS_H_
#define _AWACS_H_

/* AWACS Sound Control Register offsets */
#define AWACS_SOUND_CTRL        0x00
#define AWACS_CODEC_CTRL        0x10
#define AWACS_CODEC_STATUS      0x20
#define AWACS_CLIP_COUNT        0x30
#define AWACS_BYTE_SWAP         0x40

/* DBDMA channel offsets from sound base */
#define AWACS_DMA_OUT           0x08000  /* Output DBDMA */
#define AWACS_DMA_IN            0x08100  /* Input DBDMA */

/* Sound Control Register bits */
#define AWACS_CTL_RUN           0x00000020  /* Sound chip running */
#define AWACS_CTL_PORT_MASK     0x00000700  /* Port select mask */
#define AWACS_CTL_HEADPHONES    0x00000000  /* Headphones */
#define AWACS_CTL_SPEAKER       0x00000100  /* Internal speaker */
#define AWACS_CTL_LINEOUT       0x00000200  /* Line out */

/* AWACS Codec Register Numbers */
#define AWACS_CODEC_CONTROL     0
#define AWACS_CODEC_SPEAKERS    1
#define AWACS_CODEC_HEADPHONES  2
#define AWACS_CODEC_ATTN_L      4
#define AWACS_CODEC_ATTN_R      5
#define AWACS_CODEC_ATTN_MONO   6

/* AWACS Control Register bits */
#define AWACS_CONTROL_LOOPTHRU      0x00000040
#define AWACS_CONTROL_RECALIBRATE   0x00000004

/* AWACS Input Source Selection (in CODEC_CONTROL register) */
#define AWACS_INPUT_CD              0x00000200
#define AWACS_INPUT_LINE            0x00000400
#define AWACS_INPUT_MICROPHONE      0x00000800
#define AWACS_INPUT_MASK            0x00000E00

/* AWACS Mute bits (in speaker/headphone registers) */
#define AWACS_MUTE_SPEAKER          0x00000080
#define AWACS_MUTE_HEADPHONE        0x00000200

/* AWACS Input gain/attenuation registers */
#define AWACS_INPUT_GAIN_SHIFT      4
#define AWACS_INPUT_GAIN_MASK       0x000000F0

/* Sample Rate constants */
#define AWACS_RATE_44100        0x00000000
#define AWACS_RATE_29400        0x00000001
#define AWACS_RATE_22050        0x00000002
#define AWACS_RATE_17640        0x00000003
#define AWACS_RATE_14700        0x00000004
#define AWACS_RATE_11025        0x00000005
#define AWACS_RATE_8820         0x00000006
#define AWACS_RATE_7350         0x00000007

/* Attenuation constants (0 = max volume, 15 = mute) */
#define AWACS_ATTN_MIN          0
#define AWACS_ATTN_MAX          15

/* Buffer sizes */
#define AWACS_DMA_BUFFER_SIZE   (32 * 1024)
#define AWACS_DMA_NUM_BUFFERS   2

/* AWACS register access macros */
#define AWACS_CODEC_ADDR(reg)   (((reg) & 0x7) << 12)
#define AWACS_CODEC_DATA(data)  ((data) & 0xFFF)
#define AWACS_MAKE_CODEC_CMD(reg, data) \
    (AWACS_CODEC_ADDR(reg) | AWACS_CODEC_DATA(data) | 0x00010000)

/* Sample rate table entry */
struct awacs_rate {
    unsigned int rate;
    unsigned int value;
};

/* AWACS DMA buffer descriptor */
struct awacs_dmabuf {
    IODBDMADescriptor   *desc;          /* DBDMA descriptor list */
    IOPhysicalAddress   desc_phys;      /* Physical address of descriptors */
    void                *buffer;        /* Audio data buffer */
    IOPhysicalAddress   buffer_phys;    /* Physical address of buffer */
    unsigned int        buffer_size;    /* Size of buffer */
    unsigned int        fragsize;       /* Fragment size for interrupts */
    unsigned int        numfrags;       /* Number of fragments */
    BOOL                ready;          /* Buffer ready */
    BOOL                running;        /* DMA running */
};

/* AWACS state structure */
struct awacs_state {
    unsigned int            magic;

    /* Hardware resources */
    IOLogicalAddress        iobase;         /* Base address of sound chip */
    IOLogicalAddress        dma_out_base;   /* Output DBDMA channel */
    IOLogicalAddress        dma_in_base;    /* Input DBDMA channel */
    unsigned int            irq_out;        /* Output interrupt */
    unsigned int            irq_in;         /* Input interrupt */

    /* DMA buffers */
    struct awacs_dmabuf     dma_out;        /* Output DMA buffer */
    struct awacs_dmabuf     dma_in;         /* Input DMA buffer */

    /* Audio settings */
    unsigned int            sample_rate;
    unsigned int            channels;       /* 1 = mono, 2 = stereo */
    unsigned int            format;         /* 8 or 16 bit */

    /* Volume/attenuation */
    unsigned int            vol_left;
    unsigned int            vol_right;
    BOOL                    muted;

    /* Input settings */
    unsigned int            input_source;
    unsigned int            input_gain_left;
    unsigned int            input_gain_right;

    /* Current output port */
    unsigned int            output_port;

    /* Lock for concurrent access */
    void                    *lock;
};

#define AWACS_MAGIC     0x41574143  /* 'AWAC' */

/* Function prototypes for AWACS hardware control */
void awacs_write_codec(struct awacs_state *s, int reg, int val);
int awacs_read_codec(struct awacs_state *s, int reg);
void awacs_set_volume(struct awacs_state *s, int left, int right);
void awacs_set_rate(struct awacs_state *s, unsigned int rate);
void awacs_set_output_port(struct awacs_state *s, unsigned int port);
void awacs_set_input_source(struct awacs_state *s, unsigned int source);
void awacs_set_input_gain(struct awacs_state *s, int left, int right);
void awacs_set_speaker_mute(struct awacs_state *s, BOOL mute);
void awacs_set_headphone_mute(struct awacs_state *s, BOOL mute);
unsigned int awacs_read_status(struct awacs_state *s);
void awacs_reset_chip(struct awacs_state *s);
void awacs_init_chip(struct awacs_state *s);

void awacs_setup_dma_out(struct awacs_state *s, IOPhysicalAddress addr,
                         unsigned int size);
void awacs_setup_dma_in(struct awacs_state *s, IOPhysicalAddress addr,
                        unsigned int size);
void awacs_start_dma_out(struct awacs_state *s);
void awacs_start_dma_in(struct awacs_state *s);
void awacs_stop_dma_out(struct awacs_state *s);
void awacs_stop_dma_in(struct awacs_state *s);

#endif /* _AWACS_H_ */
