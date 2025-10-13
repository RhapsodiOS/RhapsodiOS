/*
 * Copyright (c) 2025 RhapsodiOS Project
 *
 * Burgundy Sound Chip Hardware Definitions
 * for PowerMac and iMac systems
 *
 * Based on Linux burgundy.h by Takashi Iwai
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

#ifndef _BURGUNDY_H_
#define _BURGUNDY_H_

/* Burgundy Sound Control Register offsets */
#define BURGUNDY_SOUND_CTRL        0x00
#define BURGUNDY_CODEC_CTRL        0x10
#define BURGUNDY_CODEC_STATUS      0x20
#define BURGUNDY_CLIP_COUNT        0x30
#define BURGUNDY_BYTE_SWAP         0x40

/* DBDMA channel offsets from sound base */
#define BURGUNDY_DMA_OUT           0x08000  /* Output DBDMA */
#define BURGUNDY_DMA_IN            0x08100  /* Input DBDMA */

/* Burgundy Register Address Masks */
#define MASK_ADDR_BURGUNDY_INPBOOST     (0x10 << 12)
#define MASK_ADDR_BURGUNDY_INPSEL21     (0x11 << 12)
#define MASK_ADDR_BURGUNDY_INPSEL3      (0x12 << 12)

#define MASK_ADDR_BURGUNDY_GAINCH1      (0x13 << 12)
#define MASK_ADDR_BURGUNDY_GAINCH2      (0x14 << 12)
#define MASK_ADDR_BURGUNDY_GAINCH3      (0x15 << 12)
#define MASK_ADDR_BURGUNDY_GAINCH4      (0x16 << 12)

#define MASK_ADDR_BURGUNDY_VOLCH1       (0x20 << 12)
#define MASK_ADDR_BURGUNDY_VOLCH2       (0x21 << 12)
#define MASK_ADDR_BURGUNDY_VOLCH3       (0x22 << 12)
#define MASK_ADDR_BURGUNDY_VOLCH4       (0x23 << 12)

#define MASK_ADDR_BURGUNDY_CAPTURESELECTS   (0x24 << 12)
#define MASK_ADDR_BURGUNDY_OUTPUTSELECTS    (0x25 << 12)

#define MASK_ADDR_BURGUNDY_VOLMIX01     (0x2D << 12)
#define MASK_ADDR_BURGUNDY_VOLMIX23     (0x2E << 12)
#define MASK_ADDR_BURGUNDY_VOLMIX45     (0x2F << 12)
#define MASK_ADDR_BURGUNDY_VOLMIX67     (0x30 << 12)

#define MASK_ADDR_BURGUNDY_MASTER_VOLUME    (0x38 << 12)

#define MASK_ADDR_BURGUNDY_OUTPUTENABLES    (0x3A << 12)

#define MASK_ADDR_BURGUNDY_ATTENSPEAKER     (0x3B << 12)
#define MASK_ADDR_BURGUNDY_ATTENLINEOUT     (0x3C << 12)
#define MASK_ADDR_BURGUNDY_ATTENHP          (0x3D << 12)

/* Default Values for iMac */
#define DEF_BURGUNDY_INPSEL21_IMAC      0xAA
#define DEF_BURGUNDY_INPSEL3_IMAC       0x0A

/* Default Values for PowerMac */
#define DEF_BURGUNDY_INPSEL21_PMAC      0x55
#define DEF_BURGUNDY_INPSEL3_PMAC       0x05

/* Default Gain Values */
#define DEF_BURGUNDY_GAINCD         0x33
#define DEF_BURGUNDY_GAINLINE       0x44
#define DEF_BURGUNDY_GAINMIC        0x44
#define DEF_BURGUNDY_GAINMODEM      0x00

/* Default Volume Values (0xDB = 0 dB) */
#define DEF_BURGUNDY_VOLCD          0xCCCCCCCC
#define DEF_BURGUNDY_VOLLINE        0xCCCCCCCC
#define DEF_BURGUNDY_VOLMIC         0xCCCCCCCC
#define DEF_BURGUNDY_VOLMODEM       0xCCCCCCCC

/* Output Select Values */
#define DEF_BURGUNDY_OUTPUTSELECTS  0x010F01FF
#define DEF_BURGUNDY_OUTPUTENABLES  0x0A

/* Speaker Attenuation */
#define BURGUNDY_ATTENSPEAKER_ENABLE    0x01

/* Headphone Detection - iMac */
#define BURGUNDY_HPDETECT_IMAC_UPPER    0x08
#define BURGUNDY_HPDETECT_IMAC_LOWER    0x80

/* Headphone Detection - PowerMac G3 Desktop */
#define BURGUNDY_HPDETECT_PMAC_BACK     0x04
#define BURGUNDY_HPDETECT_PMAC_FRONT    0x08
#define BURGUNDY_HPDETECT_PMAC_LOWER    0x80

/* Output Bits */
#define BURGUNDY_OUTPUT_LEFT        0x02
#define BURGUNDY_OUTPUT_RIGHT       0x04
#define BURGUNDY_OUTPUT_INTERN      0x10
#define BURGUNDY_OUTPUT_LINEOUT     0x20
#define BURGUNDY_OUTPUT_HEADPHONES  0x08

/* Volume Offset for dB calculation */
#define BURGUNDY_VOLUME_OFFSET      155

/* Sound Control Register bits */
#define BURGUNDY_CTL_RUN            0x00000020  /* Sound chip running */
#define BURGUNDY_CTL_PORT_MASK      0x00000700  /* Port select mask */
#define BURGUNDY_CTL_HEADPHONES     0x00000000  /* Headphones */
#define BURGUNDY_CTL_SPEAKER        0x00000100  /* Internal speaker */
#define BURGUNDY_CTL_LINEOUT        0x00000200  /* Line out */

/* Input Source Selection */
#define BURGUNDY_INPUT_CD           0
#define BURGUNDY_INPUT_LINE         1
#define BURGUNDY_INPUT_MICROPHONE   2
#define BURGUNDY_INPUT_MODEM        3

/* Buffer sizes */
#define BURGUNDY_DMA_BUFFER_SIZE    (32 * 1024)
#define BURGUNDY_DMA_NUM_BUFFERS    2

/* Burgundy register access macros */
#define BURGUNDY_CODEC_ADDR(reg)    (((reg) & 0x7F) << 12)
#define BURGUNDY_CODEC_DATA(data)   ((data) & 0xFFF)
#define BURGUNDY_MAKE_CODEC_CMD(reg, data) \
    (BURGUNDY_CODEC_ADDR(reg) | BURGUNDY_CODEC_DATA(data) | 0x00100000)

/* Sample rate table entry */
struct burgundy_rate {
    unsigned int rate;
    unsigned int value;
};

/* Burgundy DMA buffer descriptor */
struct burgundy_dmabuf {
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

/* Burgundy state structure */
struct burgundy_state {
    unsigned int            magic;

    /* Hardware resources */
    IOLogicalAddress        iobase;         /* Base address of sound chip */
    IOLogicalAddress        dma_out_base;   /* Output DBDMA channel */
    IOLogicalAddress        dma_in_base;    /* Input DBDMA channel */
    unsigned int            irq_out;        /* Output interrupt */
    unsigned int            irq_in;         /* Input interrupt */

    /* DMA buffers */
    struct burgundy_dmabuf  dma_out;        /* Output DMA buffer */
    struct burgundy_dmabuf  dma_in;         /* Input DMA buffer */

    /* Audio settings */
    unsigned int            sample_rate;
    unsigned int            channels;       /* 1 = mono, 2 = stereo */
    unsigned int            format;         /* 8 or 16 bit */

    /* Volume/attenuation */
    unsigned int            master_vol_left;
    unsigned int            master_vol_right;
    BOOL                    muted;

    /* Input settings */
    unsigned int            input_source;
    unsigned int            input_gain[4];  /* Gain for 4 input channels */

    /* Current output port */
    unsigned int            output_port;

    /* Model type (iMac vs PowerMac) */
    BOOL                    is_imac;

    /* Lock for concurrent access */
    void                    *lock;
};

#define BURGUNDY_MAGIC  0x42555247  /* 'BURG' */

/* Function prototypes for Burgundy hardware control */
void burgundy_write_byte(struct burgundy_state *s, unsigned int reg,
                         unsigned int val);
void burgundy_write_word(struct burgundy_state *s, unsigned int reg,
                         unsigned int val);
unsigned int burgundy_read_byte(struct burgundy_state *s, unsigned int reg);
unsigned int burgundy_read_word(struct burgundy_state *s, unsigned int reg);

void burgundy_set_volume(struct burgundy_state *s, int left, int right);
void burgundy_set_gain(struct burgundy_state *s, unsigned int channel,
                       unsigned int gain);
void burgundy_set_input_select(struct burgundy_state *s, unsigned int input);
void burgundy_set_output_select(struct burgundy_state *s, unsigned int output);
void burgundy_set_speaker_attenuation(struct burgundy_state *s,
                                      unsigned int atten);
void burgundy_set_headphone_attenuation(struct burgundy_state *s,
                                        unsigned int atten);
void burgundy_set_lineout_attenuation(struct burgundy_state *s,
                                      unsigned int atten);
unsigned int burgundy_detect_headphone(struct burgundy_state *s);

void burgundy_reset_chip(struct burgundy_state *s);
void burgundy_init_chip(struct burgundy_state *s);

void burgundy_setup_dma_out(struct burgundy_state *s, IOPhysicalAddress addr,
                            unsigned int size);
void burgundy_setup_dma_in(struct burgundy_state *s, IOPhysicalAddress addr,
                           unsigned int size);
void burgundy_start_dma_out(struct burgundy_state *s);
void burgundy_start_dma_in(struct burgundy_state *s);
void burgundy_stop_dma_out(struct burgundy_state *s);
void burgundy_stop_dma_in(struct burgundy_state *s);

#endif /* _BURGUNDY_H_ */
