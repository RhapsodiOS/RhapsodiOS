/*
 * Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved.
 * Copyright (c) 2025 RhapsodiOS Project. All rights reserved.
 *
 * HISTORY
 * 10-Nov-25   Created for ESS ES1x88 AudioDrive support
 *             Based on SoundBlaster16 driver
 */

/*
 * ES1x88 base addresses
 * ES1x88: 16 bytes at 0x220, 0x230, 0x240, 0x250
 */
#define ES1x88_BASE_ADDRESS_1                   0x0220
#define ES1x88_BASE_ADDRESS_2                   0x0230
#define ES1x88_BASE_ADDRESS_3                   0x0240
#define ES1x88_BASE_ADDRESS_4                   0x0250

/*
 * DSP register offsets - compatible with SB
 */
#define SB16_DSP_RESET_OFFSET                   0x06    /* write only */
#define SB16_DSP_READ_DATA_OFFSET               0x0a    /* read only */
#define SB16_DSP_WRITE_DATA_OR_COMMAND_OFFSET   0x0c    /* write */
#define SB16_DSP_WRITE_BUFFER_STATUS_OFFSET     0x0c    /* read */
#define SB16_DSP_DATA_AVAILABLE_STATUS_OFFSET   0x0e    /* read only */
#define SB16_DSP_16BIT_ACK_OFFSET               0x0f    /* read - 16-bit interrupt ack */

/*
 * DSP Command timing delays
 */
#define SB16_ADDRESS_WRITE_DELAY                10
#define SB16_DATA_WRITE_DELAY                   75
#define SB16_DATA_READ_DELAY                    10

/*
 * DSP status register bits
 */
#define SB16_DSP_BUSY_BIT                       0x80

/*
 * Mixer register offsets
 */
#define SB16_MIXER_ADDRESS_OFFSET               0x04
#define SB16_MIXER_DATA_OFFSET                  0x05

/*
 * SB16 Mixer Registers (used by inline helper functions)
 */
#define MC16_RESET                              0x00
#define MC16_MASTER_VOLUME                      0x22
#define MC16_VOICE_VOLUME                       0x04
#define MC16_FM_VOLUME                          0x26
#define MC16_CD_VOLUME                          0x28
#define MC16_LINE_VOLUME                        0x2e
#define MC16_MIC_VOLUME                         0x0a
#define MC16_INPUT_CONTROL_LEFT                 0x3d
#define MC16_INPUT_CONTROL_RIGHT                0x3e
#define MC16_INPUT_GAIN_LEFT                    0x3f
#define MC16_INPUT_GAIN_RIGHT                   0x40
#define MC16_OUTPUT_GAIN_LEFT                   0x41
#define MC16_OUTPUT_GAIN_RIGHT                  0x42
#define MC16_DMA_SELECT                         0x81

/*
 * ES1x88 Mixer Register Addresses
 * These are the actual addresses used by the ES1x88 chip
 */
#define ES_MIXER_RESET                          0x00
#define ES_MIXER_VOICE_VOLUME                   0x14
#define ES_MIXER_MIC_VOLUME                     0x1A
#define ES_MIXER_RECORD_SOURCE                  0x1C
#define ES_MIXER_MASTER_VOLUME                  0x32
#define ES_MIXER_FM_VOLUME                      0x36
#define ES_MIXER_CD_VOLUME                      0x38
#define ES_MIXER_LINE_VOLUME                    0x3E

/*
 * DSP Commands
 */
#define DC16_SET_SAMPLE_RATE_OUTPUT             0x41
#define DC16_SET_SAMPLE_RATE_INPUT              0x42
#define DC16_TURN_ON_SPEAKER                    0xd1
#define DC16_TURN_OFF_SPEAKER                   0xd3
#define DC16_PAUSE_8BIT_DMA                     0xd0
#define DC16_PAUSE_16BIT_DMA                    0xd5
#define DC16_GET_VERSION                        0xe1

/*
 * ES1x88 Extended Commands
 */
#define ES_CMD_EXTENDED_ID                      0xC6    /* Extended ID command */
#define ES_CMD_VERSION_QUERY                    0xE7    /* Version query */
#define ES_CMD_READ_REGISTER                    0xC0    /* Read ES register */
#define ES_CMD_WRITE_REGISTER                   0xC0    /* Write ES register (context dependent) */

/*
 * ES1x88 Extended Register Addresses (accessed via 0xC0 command)
 */
#define ES_REG_SAMPLE_RATE                      0xA1    /* Sample rate control */
#define ES_REG_FILTER                           0xA2    /* Filter control */
#define ES_REG_TRANSFER_COUNT_LOW               0xA4    /* Transfer count low byte */
#define ES_REG_TRANSFER_COUNT_HIGH              0xA5    /* Transfer count high byte */
#define ES_REG_OUTPUT_MODE                      0xB6    /* Output mode control */
#define ES_REG_AUDIO_CONTROL_1                  0xB7    /* Audio control 1 */
#define ES_REG_AUDIO_CONTROL_2                  0xB8    /* Audio control 2 (direction/enable) */
#define ES_REG_IRQ_CONTROL                      0xB1    /* IRQ configuration */
#define ES_REG_DMA_CONTROL                      0xB2    /* DMA configuration */
#define ES_REG_AUDIO_MODE                       0xA8    /* Audio mode (stereo/mono) */
#define ES_REG_DMA_SETUP                        0xB9    /* DMA setup */

/*
 * ES1x88 Audio Control 2 Mode Values (register 0xB8)
 */
#define ES_MODE_INPUT                           0x04    /* Input/Record mode */
#define ES_MODE_OUTPUT                          0x0E    /* Output/Playback mode */

/*
 * ES1x88 Audio Control 1 Mode Commands (register 0xB7)
 * These values are sent to configure different audio modes
 */
#define ES_AUDIO_MODE_STEREO_16BIT_CMD1         0x51    /* Stereo 16-bit command 1 */
#define ES_AUDIO_MODE_STEREO_16BIT_CMD2         0x98    /* Stereo 16-bit command 2 */
#define ES_AUDIO_MODE_STEREO_8BIT_CMD1          0x71    /* Stereo 8-bit command 1 */
#define ES_AUDIO_MODE_STEREO_8BIT_CMD2          0xBC    /* Stereo 8-bit command 2 */
#define ES_AUDIO_MODE_MONO_16BIT_CMD1           0x51    /* Mono 16-bit command 1 (same as stereo) */
#define ES_AUDIO_MODE_MONO_16BIT_CMD2           0xD0    /* Mono 16-bit command 2 */
#define ES_AUDIO_MODE_MONO_8BIT_CMD1            0x71    /* Mono 8-bit command 1 (same as stereo) */
#define ES_AUDIO_MODE_MONO_8BIT_CMD2            0xF4    /* Mono 8-bit command 2 */

/*
 * ES1x88 Output Mode Data Values (register 0xB6)
 */
#define ES_OUTPUT_MODE_16BIT                    0x80    /* 16-bit output mode */
#define ES_OUTPUT_MODE_8BIT                     0x00    /* 8-bit output mode */

/*
 * ES1x88 Audio Mode Register Bits (register 0xA8)
 */
#define ES_AUDIO_MODE_STEREO                    0x01    /* Stereo mode bit */
#define ES_AUDIO_MODE_MONO                      0x02    /* Mono mode bit */

/*
 * ES1x88 Hardware Detection Constants
 */
#define ES_DSP_READY_RESPONSE                   0xAA    /* DSP ready response after reset */
#define ES_CHIP_ID_PREFIX                       'h'     /* ES1x88 chip ID starts with 'h' (0x68) */

/*
 * ES1x88 Sample Rate Calculation Constants
 * Used for programming the sample rate register
 */
#define ES_SAMPLE_RATE_THRESHOLD                0x55F1  /* 22001 Hz threshold */
#define ES_SAMPLE_RATE_CONST_LOW                0x61184 /* Constant for rates < threshold */
#define ES_SAMPLE_RATE_CONST_HIGH               0xC236C /* Constant for rates >= threshold */
#define ES_FILTER_CONST                         0x6D40C0 /* Filter calculation constant */
#define ES_FILTER_DIVISOR                       0x21    /* 33 decimal - filter divisor */

/*
 * ES1x88 Volume and Gain Constants
 */
#define ES_VOLUME_BITS                          0x0F    /* 4 bits per channel (0-15) */
#define ES_ATTENUATION_MULTIPLIER               3       /* Attenuation formula multiplier */
#define ES_ATTENUATION_OFFSET                   252     /* 0xFC - Attenuation formula offset */
#define ES_ATTENUATION_SCALE                    5       /* Attenuation formula scale factor */
#define ES_ATTENUATION_RANGE                    84      /* 0x54 - IOAudio attenuation range (0 to -84) */

/*
 * DMA mode bits (used with DMA commands)
 */
#define DMA_MODE_STEREO                         0x20    /* Stereo (else mono) */
#define DMA_MODE_SIGNED                         0x10    /* Signed data (16-bit only) */

/*
 * DMA direction values
 */
#define DMA_DIRECTION_IN                        0
#define DMA_DIRECTION_OUT                       1
#define DMA_DIRECTION_STOPPED                   2

/*
 * Mixer register data structures for stereo controls
 */
typedef union {
    struct {
        unsigned char
                right:4,
                left:4;
    }       reg;
    unsigned char data;
}       sb16MonoMixerRegister_t;

typedef union {
    struct {
        unsigned char
                right:4,
                left:4;
    }       reg;
    unsigned char rawValue;
}       es1x88MixerRegister_t;

/*
 * Card version enumeration
 */
typedef enum {
    SB16_BASIC = 1,     /* SB16 16-bit capable */
    SB16_VIBRA = 2,     /* SB16 Vibra or compatible 16-bit */
    SB_8BIT = 3,        /* 8-bit Sound Blaster (not supported) */
    SB16_NONE = 4       /* No card detected */
}       sb16CardVersion_t;

/*
 * Card parameters structure
 */
typedef struct  {
        sb16CardVersion_t version;
        char              *name;
        unsigned int      majorVersion;
        unsigned int      minorVersion;
        BOOL              mixerPresent;
        BOOL              supports16Bit;
        BOOL              supportsAWE;
} sb16CardParameters_t;

/*
 * Input source selection bits
 */
#define INPUT_SOURCE_MIC                        0x00

/*
 * Analog input source parameter tags
 */
#define NX_SoundStreamDataAnalogSourceMicrophone  0xC8  /* 200 */
#define NX_SoundStreamDataAnalogSourceLineIn      0xC9  /* 201 */
