/*
 * ac97reg.h
 *
 * AC97 (Audio Codec '97) register definitions
 * Based on Intel's Audio Codec '97 specification Rev 2.3
 * Also references NetBSD's ac97reg.h implementation
 *
 * Copyright (c) 2025
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 */

#ifndef _AC97REG_H_
#define _AC97REG_H_

/*
 * AC'97 Standard Register Set
 */
#define AC97_REG_RESET                  0x00    /* Reset Register */
#define AC97_REG_MASTER_VOLUME          0x02    /* Master Volume */
#define AC97_REG_AUX_OUT_VOLUME         0x04    /* Auxillary Out Volume (headphone) */
#define AC97_REG_MONO_VOLUME            0x06    /* Mono Volume */
#define AC97_REG_MASTER_TONE            0x08    /* Master Tone (bass & treble) */
#define AC97_REG_PCBEEP_VOLUME          0x0a    /* PC Beep Volume */
#define AC97_REG_PHONE_VOLUME           0x0c    /* Phone Volume */
#define AC97_REG_MIC_VOLUME             0x0e    /* Mic Volume */
#define AC97_REG_LINEIN_VOLUME          0x10    /* Line In Volume */
#define AC97_REG_CD_VOLUME              0x12    /* CD Volume */
#define AC97_REG_VIDEO_VOLUME           0x14    /* Video Volume */
#define AC97_REG_AUX_VOLUME             0x16    /* Aux In Volume */
#define AC97_REG_PCMOUT_VOLUME          0x18    /* PCM Out Volume */
#define AC97_REG_RECORD_SELECT          0x1a    /* Record Select Control */
#define AC97_REG_RECORD_GAIN            0x1c    /* Record Gain */
#define AC97_REG_RECORD_GAIN_MIC        0x1e    /* Record Gain Mic */
#define AC97_REG_GENERAL_PURPOSE        0x20    /* General Purpose */
#define AC97_REG_3D_CONTROL             0x22    /* 3D Control */
#define AC97_REG_AUDIO_INT_PAGING       0x24    /* Audio Interrupt & Paging */
#define AC97_REG_POWERDOWN              0x26    /* Powerdown Control/Status */

/* Extended Audio Registers (AC'97 2.0+) */
#define AC97_REG_EXT_AUDIO_ID           0x28    /* Extended Audio ID */
#define AC97_REG_EXT_AUDIO_CTRL         0x2a    /* Extended Audio Status and Control */
#define AC97_REG_PCM_FRONT_DAC_RATE     0x2c    /* PCM Front DAC Rate */
#define AC97_REG_PCM_SURR_DAC_RATE      0x2e    /* PCM Surround DAC Rate */
#define AC97_REG_PCM_LFE_DAC_RATE       0x30    /* PCM LFE DAC Rate */
#define AC97_REG_PCM_LR_ADC_RATE        0x32    /* PCM L/R ADC Rate */
#define AC97_REG_PCM_MIC_ADC_RATE       0x34    /* PCM Mic ADC Rate */
#define AC97_REG_CENTER_LFE_MASTER      0x36    /* Center + LFE Master Volume */
#define AC97_REG_SURR_MASTER            0x38    /* Surround Master Volume */
#define AC97_REG_SPDIF_CONTROL          0x3a    /* S/PDIF Control */

/* Modem Registers (AC'97 2.2+) */
#define AC97_REG_EXT_MODEM_ID           0x3c    /* Extended Modem ID */
#define AC97_REG_EXT_MODEM_CTRL         0x3e    /* Extended Modem Status and Control */

/* Vendor Reserved: 0x5a - 0x7a */

/* Vendor ID Registers */
#define AC97_REG_VENDOR_ID1             0x7c    /* Vendor ID1 */
#define AC97_REG_VENDOR_ID2             0x7e    /* Vendor ID2 */

/*
 * Volume Control Bit Definitions
 */
#define AC97_MUTE                       0x8000  /* Mute bit */
#define AC97_MICBOOST                   0x0040  /* Mic +20dB boost */
#define AC97_LEFTVOL_MASK               0x3f00  /* Left volume mask */
#define AC97_RIGHTVOL_MASK              0x003f  /* Right volume mask */
#define AC97_LEFTVOL_SHIFT              8       /* Left volume shift */
#define AC97_RIGHTVOL_SHIFT             0       /* Right volume shift */

/*
 * Record Select Register Bits
 */
#define AC97_RECMUX_MIC                 0x0000  /* Microphone */
#define AC97_RECMUX_CD                  0x0101  /* CD */
#define AC97_RECMUX_VIDEO               0x0202  /* Video */
#define AC97_RECMUX_AUX                 0x0303  /* Aux In */
#define AC97_RECMUX_LINE                0x0404  /* Line In */
#define AC97_RECMUX_STEREO_MIX          0x0505  /* Stereo Mix */
#define AC97_RECMUX_MONO_MIX            0x0606  /* Mono Mix */
#define AC97_RECMUX_PHONE               0x0707  /* Phone */

/*
 * General Purpose Register Bits
 */
#define AC97_GP_LPBK                    0x0080  /* ADC/DAC Loopback mode */
#define AC97_GP_MS                      0x0100  /* Mic Select (0=Mic1, 1=Mic2) */
#define AC97_GP_MIX                     0x0200  /* Mono output select */
#define AC97_GP_RLBK                    0x0400  /* Remote Loopback */
#define AC97_GP_LLBK                    0x0800  /* Local Loopback */
#define AC97_GP_LD                      0x1000  /* Loudness (bass boost) */
#define AC97_GP_3D                      0x2000  /* 3D Enhancement */
#define AC97_GP_ST                      0x4000  /* Simulated Stereo */
#define AC97_GP_POP                     0x8000  /* PCM out path & mute */

/*
 * Powerdown Control/Status Register Bits
 */
/* Status bits */
#define AC97_PWR_MDM                    0x0010  /* Modem section ready */
#define AC97_PWR_REF                    0x0008  /* Vref is up to nominal level */
#define AC97_PWR_ANL                    0x0004  /* Analog section ready */
#define AC97_PWR_DAC                    0x0002  /* DAC section ready */
#define AC97_PWR_ADC                    0x0001  /* ADC section ready */

/* Control bits */
#define AC97_PWR_PR0                    0x0100  /* ADC and Mux powerdown */
#define AC97_PWR_PR1                    0x0200  /* DAC powerdown */
#define AC97_PWR_PR2                    0x0400  /* Output mixer powerdown (Vref still on) */
#define AC97_PWR_PR3                    0x0800  /* Output mixer powerdown (Vref off) */
#define AC97_PWR_PR4                    0x1000  /* AC-link powerdown */
#define AC97_PWR_PR5                    0x2000  /* Internal clock disable */
#define AC97_PWR_PR6                    0x4000  /* HP amp powerdown */
#define AC97_PWR_PR7                    0x8000  /* Modem off */

/* Useful power states */
#define AC97_PWR_D0                     0x0000  /* Everything on */
#define AC97_PWR_D1                     (AC97_PWR_PR0|AC97_PWR_PR1|AC97_PWR_PR4)
#define AC97_PWR_D2                     (AC97_PWR_PR0|AC97_PWR_PR1|AC97_PWR_PR2|AC97_PWR_PR3|AC97_PWR_PR4)
#define AC97_PWR_D3                     (AC97_PWR_PR0|AC97_PWR_PR1|AC97_PWR_PR2|AC97_PWR_PR3|AC97_PWR_PR4)
#define AC97_PWR_ANLOFF                 (AC97_PWR_PR2|AC97_PWR_PR3)  /* Analog section off */

/*
 * Extended Audio ID Register Bits
 */
#define AC97_EXT_AUDIO_VRA              0x0001  /* Variable Rate Audio */
#define AC97_EXT_AUDIO_DRA              0x0002  /* Double Rate Audio */
#define AC97_EXT_AUDIO_SPDIF            0x0004  /* S/PDIF */
#define AC97_EXT_AUDIO_VRM              0x0008  /* Variable Rate Mic ADC */
#define AC97_EXT_AUDIO_DSA_MASK         0x0030  /* DAC Slot Assignment mask */
#define AC97_EXT_AUDIO_DSA_SHIFT        4
#define AC97_EXT_AUDIO_SPSA_MASK        0x00c0  /* S/PDIF Slot Assignment mask */
#define AC97_EXT_AUDIO_SPSA_SHIFT       6
#define AC97_EXT_AUDIO_CDAC             0x0040  /* PCM Center DAC available */
#define AC97_EXT_AUDIO_SDAC             0x0080  /* PCM Surround DACs available */
#define AC97_EXT_AUDIO_LDAC             0x0100  /* PCM LFE DAC available */
#define AC97_EXT_AUDIO_AMAP             0x0200  /* Slot/DAC mappings are swappable */
#define AC97_EXT_AUDIO_REV_MASK         0x0c00  /* AC'97 revision mask */
#define AC97_EXT_AUDIO_REV_SHIFT        10
#define AC97_EXT_AUDIO_REV_21           0x0000  /* AC'97 2.1 */
#define AC97_EXT_AUDIO_REV_22           0x0400  /* AC'97 2.2 */
#define AC97_EXT_AUDIO_REV_23           0x0800  /* AC'97 2.3 */

/*
 * Extended Audio Control Register Bits
 */
#define AC97_EXT_CTRL_VRA               0x0001  /* Enable Variable Rate Audio */
#define AC97_EXT_CTRL_DRA               0x0002  /* Enable Double Rate Audio */
#define AC97_EXT_CTRL_SPDIF             0x0004  /* Enable S/PDIF */
#define AC97_EXT_CTRL_VRM               0x0008  /* Enable Variable Rate Mic */
#define AC97_EXT_CTRL_SPSA_MASK         0x0030  /* S/PDIF Slot Assignment */
#define AC97_EXT_CTRL_SPSA_SHIFT        4
#define AC97_EXT_CTRL_CDAC              0x0040  /* PCM Center DAC is enabled */
#define AC97_EXT_CTRL_SDAC              0x0080  /* PCM Surround DACs are enabled */
#define AC97_EXT_CTRL_LDAC              0x0100  /* PCM LFE DAC is enabled */
#define AC97_EXT_CTRL_AMAP              0x0200  /* Map Slot to DAC Accordingly */
#define AC97_EXT_CTRL_MADC              0x0400  /* Mic ADC is enabled */

/*
 * S/PDIF Control Register Bits
 */
#define AC97_SPDIF_V                    0x0001  /* Validity (0=valid) */
#define AC97_SPDIF_DRS                  0x0004  /* Double Rate S/PDIF */
#define AC97_SPDIF_SPSR_MASK            0x0030  /* S/PDIF Sample Rate */
#define AC97_SPDIF_SPSR_SHIFT           4
#define AC97_SPDIF_SPSR_44K             0x0000  /* 44.1 kHz */
#define AC97_SPDIF_SPSR_48K             0x0020  /* 48 kHz */
#define AC97_SPDIF_SPSR_32K             0x0030  /* 32 kHz */
#define AC97_SPDIF_L                    0x0040  /* Generation Level */
#define AC97_SPDIF_CC_MASK              0x7f00  /* Category Code */
#define AC97_SPDIF_CC_SHIFT             8

/*
 * Sample Rate Ranges
 */
#define AC97_RATE_MIN                   4000    /* Minimum sample rate */
#define AC97_RATE_MAX                   48000   /* Maximum sample rate */
#define AC97_RATE_DEFAULT               48000   /* Default sample rate */

/* Extended Modem ID bits */
#define AC97_EXT_MODEM_ID_LINE1         0x0001
#define AC97_EXT_MODEM_ID_LINE2         0x0002
#define AC97_EXT_MODEM_ID_HSET          0x0004
#define AC97_EXT_MODEM_ID_CID1          0x0008
#define AC97_EXT_MODEM_ID_CID2          0x0010
#define AC97_EXT_MODEM_ID_GPIO          0x0020

/* Codec IDs - Vendor specific */
#define AC97_VENDOR_ID_MASK             0xffffff00
#define AC97_CODEC_ID(vendor, id)       ((vendor) << 8 | (id))

/* Total number of defined registers */
#define AC97_REG_CNT                    64

#endif /* _AC97REG_H_ */
