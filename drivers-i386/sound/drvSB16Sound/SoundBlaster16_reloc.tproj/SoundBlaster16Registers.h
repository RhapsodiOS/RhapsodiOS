/*
 * Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved.
 * Copyright (c) 2025 RhapsodiOS Project. All rights reserved.
 *
 * HISTORY
 * 6-Oct-25    Created for Sound Blaster 16, AWE32, AWE64 support
 */

/*
 * SB16 base addresses - same as SB8 but with extended functionality
 * SB16: 16 bytes at 0x220, 0x240, 0x260, 0x280
 */
#define SB16_BASE_ADDRESS_1                     0x0220
#define SB16_BASE_ADDRESS_2                     0x0240
#define SB16_BASE_ADDRESS_3                     0x0260
#define SB16_BASE_ADDRESS_4                     0x0280

/*
 * DSP register offsets - compatible with SB8
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
 * SB16 Mixer Registers (new addresses for newer cards)
 */
#define MC16_RESET                              0x00
#define MC16_MASTER_VOLUME                      0x22
#define MC16_VOICE_VOLUME                       0x04
#define MC16_FM_VOLUME                          0x26
#define MC16_CD_VOLUME                          0x28
#define MC16_LINE_VOLUME                        0x2e
#define MC16_MIC_VOLUME                         0x0a
#define MC16_PC_SPEAKER_VOLUME                  0x3b
#define MC16_OUTPUT_CONTROL                     0x3c
#define MC16_INPUT_CONTROL_LEFT                 0x3d
#define MC16_INPUT_CONTROL_RIGHT                0x3e
#define MC16_INPUT_GAIN_LEFT                    0x3f
#define MC16_INPUT_GAIN_RIGHT                   0x40
#define MC16_OUTPUT_GAIN_LEFT                   0x41
#define MC16_OUTPUT_GAIN_RIGHT                  0x42
#define MC16_AGC                                0x43
#define MC16_TREBLE_LEFT                        0x44
#define MC16_TREBLE_RIGHT                       0x45
#define MC16_BASS_LEFT                          0x46
#define MC16_BASS_RIGHT                         0x47
#define MC16_IRQ_SELECT                         0x80
#define MC16_DMA_SELECT                         0x81
#define MC16_IRQ_STATUS                         0x82

/*
 * CT1745 Mixer Registers (old addresses for compatibility)
 * Used for hardware detection
 */
#define CT1745_MASTER_VOLUME_LEFT               0x30
#define CT1745_MASTER_VOLUME_RIGHT              0x31
#define CT1745_VOICE_VOLUME_LEFT                0x32
#define CT1745_VOICE_VOLUME_RIGHT               0x33
#define CT1745_FM_VOLUME_LEFT                   0x34
#define CT1745_FM_VOLUME_RIGHT                  0x35
#define CT1745_CD_VOLUME_LEFT                   0x36
#define CT1745_CD_VOLUME_RIGHT                  0x37
#define CT1745_LINE_VOLUME_LEFT                 0x38
#define CT1745_LINE_VOLUME_RIGHT                0x39
#define CT1745_MIC_VOLUME                       0x3a

/*
 * DSP Commands - 8-bit transfers
 */
#define DC16_SET_TIME_CONSTANT                  0x40
#define DC16_SET_SAMPLE_RATE_OUTPUT             0x41
#define DC16_SET_SAMPLE_RATE_INPUT              0x42

/*
 * Speaker control
 */
#define DC16_TURN_ON_SPEAKER                    0xd1
#define DC16_TURN_OFF_SPEAKER                   0xd3
#define DC16_GET_SPEAKER_STATUS                 0xd8

/*
 * 8-bit DMA commands (legacy compatibility)
 */
#define DC16_START_8BIT_DMA_DAC                 0xc0
#define DC16_START_8BIT_DMA_ADC                 0xc8
#define DC16_PAUSE_8BIT_DMA                     0xd0
#define DC16_CONTINUE_8BIT_DMA                  0xd4
#define DC16_EXIT_8BIT_AUTO_DMA                 0xda

/*
 * 16-bit DMA commands
 */
#define DC16_START_16BIT_DMA_DAC                0xb0
#define DC16_START_16BIT_DMA_ADC                0xb8
#define DC16_PAUSE_16BIT_DMA                    0xd5
#define DC16_CONTINUE_16BIT_DMA                 0xd6
#define DC16_EXIT_16BIT_AUTO_DMA                0xd9

/*
 * DMA mode bits (used with DMA commands)
 */
#define DMA_MODE_FIFO                           0x02    /* Enable FIFO */
#define DMA_MODE_AUTO_INIT                      0x04    /* Auto-initialize DMA */
#define DMA_MODE_ADC                            0x08    /* ADC (else DAC) */
#define DMA_MODE_STEREO                         0x20    /* Stereo (else mono) */
#define DMA_MODE_SIGNED                         0x10    /* Signed data (16-bit only) */

/*
 * DSP version and identification
 */
#define DC16_GET_VERSION                        0xe1
#define DC16_GET_COPYRIGHT                      0xe3

/*
 * Halt DMA
 */
#define DC16_HALT_DMA                           0xd0

/*
 * Maximum and minimum sampling rates for SB16
 */
#define SB16_MAX_SAMPLE_RATE_8BIT               45000
#define SB16_MIN_SAMPLE_RATE_8BIT               5000
#define SB16_MAX_SAMPLE_RATE_16BIT              45000
#define SB16_MIN_SAMPLE_RATE_16BIT              5000

/*
 * Volume and gain ranges
 */
#define MAX_MASTER_VOLUME_16                    0x1f    /* 5 bits per channel */
#define MAX_VOICE_VOLUME_16                     0x1f
#define MAX_INPUT_GAIN_16                       0x03    /* 2 bits per channel */
#define MAX_OUTPUT_GAIN_16                      0x03
#define MAX_TREBLE_16                           0x0f    /* 4 bits per channel */
#define MAX_BASS_16                             0x0f

/*
 * Attenuation range used by IOAudio framework (0 to -84)
 */
#define SB16_ATTENUATION_RANGE                  0x54    /* 84 decimal */

/*
 * DMA channels supported by SB16
 * Low DMA (8-bit): 0, 1, 3
 * High DMA (16-bit): 5, 6, 7
 */
#define SB16_DMA_8BIT_0                         0
#define SB16_DMA_8BIT_1                         1
#define SB16_DMA_8BIT_3                         3
#define SB16_DMA_16BIT_5                        5
#define SB16_DMA_16BIT_6                        6
#define SB16_DMA_16BIT_7                        7

/*
 * IRQ channels supported by SB16: 2, 5, 7, 10
 */
#define SB16_IRQ_2                              2
#define SB16_IRQ_5                              5
#define SB16_IRQ_7                              7
#define SB16_IRQ_10                             10

/*
 * Data format flags
 */
#define DSP_DATA_LINEAR                         0
#define DSP_DATA_COMPANDED                      1

#define DSP_MONO_MODE                           0
#define DSP_STEREO_MODE                         1

#define LEFT_CHANNEL                            0
#define RIGHT_CHANNEL                           1

#define LINE_LEVEL_INPUT                        0
#define MICROPHONE_LEVEL_INPUT                  1
#define CD_LEVEL_INPUT                          2

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
                right:5,
                rsvd1:3;
    }       reg;
    unsigned char data;
}       sb16MonoMixerRegister5bit_t;

typedef union {
    struct {
        unsigned char
                left:5,
                right:5,
                rsvd:6;
    }       reg;
    unsigned short data;
}       sb16StereoMixerRegister_t;

/*
 * Card version enumeration
 * Values match original driver implementation
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
#define INPUT_SOURCE_CD_RIGHT                   0x01
#define INPUT_SOURCE_CD_LEFT                    0x02
#define INPUT_SOURCE_LINE_RIGHT                 0x04
#define INPUT_SOURCE_LINE_LEFT                  0x08
#define INPUT_SOURCE_MIDI_RIGHT                 0x10
#define INPUT_SOURCE_MIDI_LEFT                  0x20

/* All input sources enabled (for mono recording) */
#define INPUT_SOURCE_ALL                        0x1f

/*
 * Output mixer control bits
 */
#define OUTPUT_MIX_CD                           0x01
#define OUTPUT_MIX_LINE                         0x02
#define OUTPUT_MIX_MIC                          0x04

/*
 * IRQ status register bits
 */
#define IRQ_STATUS_8BIT                         0x01
#define IRQ_STATUS_16BIT                        0x02
#define IRQ_STATUS_MPU401                       0x04
