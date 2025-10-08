/*
 * ac97var.h
 *
 * AC97 (Audio Codec '97) interface definitions
 * Based on NetBSD's ac97var.h implementation
 *
 * Copyright (c) 2025
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

#ifndef _AC97VAR_H_
#define _AC97VAR_H_

#import "ac97reg.h"

/*
 * AC97 Codec Types
 */
#define AC97_CODEC_TYPE_AUDIO           0
#define AC97_CODEC_TYPE_MODEM           1

/*
 * Host Interface Flags
 */
typedef enum {
    AC97_HOST_INVERTED_MUTE     = 0x0001,   /* Mute logic is inverted */
    AC97_HOST_SWAPPED_CHANNELS  = 0x0002,   /* L/R channels are swapped */
    AC97_HOST_AUX_INVERTED      = 0x0004,   /* Aux In is inverted */
    AC97_HOST_DONT_READMIX      = 0x0008    /* Don't read mixer registers */
} ac97_host_flags_t;

/*
 * AC97 Codec Capabilities
 */
typedef struct {
    unsigned int    vra_supported:1;        /* Variable Rate Audio */
    unsigned int    dra_supported:1;        /* Double Rate Audio */
    unsigned int    spdif_supported:1;      /* S/PDIF output */
    unsigned int    vrm_supported:1;        /* Variable Rate Mic */
    unsigned int    surround_dac:1;         /* Surround DACs available */
    unsigned int    center_dac:1;           /* Center DAC available */
    unsigned int    lfe_dac:1;              /* LFE DAC available */
    unsigned int    bass_treble:1;          /* Bass & treble control */
    unsigned int    simulated_stereo:1;     /* Simulated stereo */
    unsigned int    headphone_out:1;        /* Headphone out control */
    unsigned int    loudness:1;             /* Loudness control */
    unsigned int    bit18_dac:1;            /* 18-bit DAC */
    unsigned int    bit20_dac:1;            /* 20-bit DAC */
    unsigned int    bit18_adc:1;            /* 18-bit ADC */
    unsigned int    bit20_adc:1;            /* 20-bit ADC */
    unsigned int    modem:1;                /* Modem codec */
} ac97_caps_t;

/*
 * AC97 Codec State
 */
struct ac97_codec_state {
    unsigned int        magic;              /* Magic number for validation */

    /* Hardware access */
    void                *host_priv;         /* Host-specific private data */
    unsigned short      (*read_reg)(void *host_priv, unsigned char reg);
    void                (*write_reg)(void *host_priv, unsigned char reg, unsigned short val);
    void                (*reset)(void *host_priv);

    /* Codec information */
    unsigned short      codec_id;           /* Codec ID from registers */
    unsigned int        vendor_id;          /* Vendor ID */
    char                vendor_name[32];    /* Vendor name string */
    char                codec_name[32];     /* Codec name string */
    ac97_caps_t         caps;               /* Codec capabilities */
    ac97_host_flags_t   host_flags;         /* Host flags */

    /* Current settings (shadow registers) */
    unsigned short      regs[AC97_REG_CNT]; /* Cached register values */

    /* Sample rate settings */
    unsigned int        dac_rate;           /* Current DAC sample rate */
    unsigned int        adc_rate;           /* Current ADC sample rate */
    unsigned int        mic_rate;           /* Current Mic ADC sample rate */

    /* Volume/mute state */
    unsigned char       master_vol_l;       /* Master volume left (0-31) */
    unsigned char       master_vol_r;       /* Master volume right (0-31) */
    unsigned int        master_mute:1;      /* Master mute */
    unsigned char       pcm_vol_l;          /* PCM volume left (0-31) */
    unsigned char       pcm_vol_r;          /* PCM volume right (0-31) */
    unsigned int        pcm_mute:1;         /* PCM mute */

    /* Feature enable flags */
    unsigned int        vra_enabled:1;      /* Variable Rate Audio enabled */
    unsigned int        dra_enabled:1;      /* Double Rate Audio enabled */
    unsigned int        spdif_enabled:1;    /* S/PDIF enabled */
    unsigned int        vrm_enabled:1;      /* Variable Rate Mic enabled */
};

/*
 * AC97 Magic number for validation
 */
#define AC97_MAGIC                      0xAC970000

/*
 * Macros to check codec capabilities
 */
#define AC97_IS_FIXED_RATE(codec)       (!(codec)->caps.vra_supported)
#define AC97_IS_4CH(codec)              ((codec)->caps.surround_dac)
#define AC97_IS_6CH(codec)              ((codec)->caps.surround_dac && (codec)->caps.lfe_dac)
#define AC97_HAS_SPDIF(codec)           ((codec)->caps.spdif_supported)

/*
 * Function Prototypes
 */

/* Initialize and attach codec */
int ac97_attach(struct ac97_codec_state *codec, int codec_type);

/* Reset codec */
void ac97_reset(struct ac97_codec_state *codec);

/* Register access */
unsigned short ac97_read(struct ac97_codec_state *codec, unsigned char reg);
void ac97_write(struct ac97_codec_state *codec, unsigned char reg, unsigned short val);

/* Mixer control */
void ac97_set_master_volume(struct ac97_codec_state *codec,
                           unsigned char left, unsigned char right, int mute);
void ac97_get_master_volume(struct ac97_codec_state *codec,
                           unsigned char *left, unsigned char *right, int *mute);
void ac97_set_pcm_volume(struct ac97_codec_state *codec,
                        unsigned char left, unsigned char right, int mute);
void ac97_get_pcm_volume(struct ac97_codec_state *codec,
                        unsigned char *left, unsigned char *right, int *mute);
void ac97_set_record_source(struct ac97_codec_state *codec, unsigned int source);
void ac97_set_record_gain(struct ac97_codec_state *codec,
                         unsigned char left, unsigned char right);

/* Sample rate control */
int ac97_set_rate(struct ac97_codec_state *codec, int which, unsigned int rate);
unsigned int ac97_get_rate(struct ac97_codec_state *codec, int which);

/* Rate selection constants */
#define AC97_RATE_DAC                   0
#define AC97_RATE_ADC                   1
#define AC97_RATE_MIC                   2

/* Codec identification */
void ac97_identify_codec(struct ac97_codec_state *codec);

/* Power management */
void ac97_power_up(struct ac97_codec_state *codec);
void ac97_power_down(struct ac97_codec_state *codec);

/* Utility functions */
int ac97_wait_ready(struct ac97_codec_state *codec, int timeout_ms);
void ac97_dump_registers(struct ac97_codec_state *codec);

#endif /* _AC97VAR_H_ */
