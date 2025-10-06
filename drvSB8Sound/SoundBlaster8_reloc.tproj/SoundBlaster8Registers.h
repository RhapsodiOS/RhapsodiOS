/*
 * Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved. 
 *
 * HISTORY
 * 4-Mar-94    Rakesh Dubey at NeXT
 *      Created. 
 */

/*
 * The default base address is 0x220. Adresses depend upon the flavor of
 * sound card and are not software selectable. 
 */

/* 
 *  SB 1.5 and earlier : 16 bytes at 0x210 to 0x260
 *  SB 2.0 : 16 bytes at 0x220 and 0x240
 *  SB Pro : 24 bytes at 0x220 and 0x240
 */
#define SB_BASE_ADDRESS_1                       0x0210
#define SB_BASE_ADDRESS_2                       0x0220
#define SB_BASE_ADDRESS_3                       0x0230
#define SB_BASE_ADDRESS_4                       0x0240
#define SB_BASE_ADDRESS_5                       0x0250
#define SB_BASE_ADDRESS_6                       0x0260

/*
 * DSP register offsets. 
 */
#define SB_DSP_RESET_OFFSET                     0x06    /* write only */
#define SB_DSP_READ_DATA_OFFSET                 0x0a    /* read only */
#define SB_DSP_WRITE_DATA_OR_COMMAND_OFFSET     0x0c    /* write */


/*
 * These two indicate whether the DSP is busy and whether the result is
 * available from DSP (if any). Success is indicated by bit 7 of the
 * appropriate register getting set and reset respectively.
 */
#define SB_DSP_WRITE_BUFFER_STATUS_OFFSET       0x0c    /* read */
#define SB_DSP_DATA_AVAILABLE_STATUS_OFFSET     0x0e    /* read only */

/*
 * DSP Command list. SB SDK advises to wait for 3.3us after an address write
 * and 23us after a data write. 
 */

#define SB_ADDRESS_WRITE_DELAY                  10
#define SB_DATA_WRITE_DELAY                     25
#define SB_DATA_READ_DELAY              	10

/* 
 * Set the sampling rate. There are many limitations depending upon the
 * flavor of card and transfer mode. 
 */
#define DC_SET_TIME_CONSTANT                   0x40

/*
 * Speaker control. Speaker must be off while doing input. 
 */
#define DC_TURN_ON_SPEAKER                      0xd1
#define DC_TURN_OFF_SPEAKER                     0xd3
#define DC_GET_SPEAKER_STATUS                   0xd8

/*
 * Request low speed DMA transfer. 
 */
#define DC_START_LS_DMA_DAC_8                   0x14
#define DC_START_LS_DMA_ADC_8                   0x24

/*
 * Request high speed DMA transfer. 
 */
#define DC_SET_BLOCK_SIZE                       0x48

#define DC_START_HS_DMA_DAC_8                   0x91
#define DC_START_HS_DMA_ADC_8                   0x99

/*
 * DSP side other DMA control commands. 
 */
#define DC_HALT_DMA                             0xd0

/*
 * Not used. 
 */
#define DC_CONTINUE_DMA                         0xd4
#define DC_SEND_SILENCE                         0x80
#define DC_PIO_ADC_8                            0x20	/* Programmed I/O */
#define DC_PIO_DAC_8                            0x10

/*
 * Other transfer modes for output. Currently unsupported.
 */
#define DC_START_LS_DMA_DAC_2                   0x16
#define DC_START_LS_DMA_DAC_2_6                 0x76
#define DC_START_LS_DMA_DAC_4                   0x74

/*
 * Other miscelleaneous DSP Coomands. 
 */
#define DC_GET_VERSION                          0xe1
#define DC_INVERT_BYTE                          0xe0

/*
 * Record mode control (available only for SBPro) 
 */
#define DC_RECORD_IN_MONO                       0xa0
#define DC_RECORD_IN_STEREO                     0xa8

/*
 * Note: Mixer is available in SB Pro model only. 
 */

/*
 * Mixer register offsets. 
 */
#define SB_MIXER_ADDRESS_OFFSET                 0x04
#define SB_MIXER_DATA_OFFSET                    0x05

/*
 * Mixer Commands for setting volume. 
 */
#define MC_MASTER_VOLUME                        0x22
#define MC_FM_VOLUME                            0x26
#define MC_CD_VOLUME                            0x28
#define MC_LINE_VOLUME                          0x2e
#define MC_VOC_VOLUME                           0x04
#define MC_MICROPHONE_VOLUME                    0x0a

/*
 * Other mixer commands for selecting input output type. 
 */
#define MC_RECORD_CONTROL                       0x0c
#define MC_PLAYBACK_CONTROL                     0x0e

/*
 * Actually you have only half as many settings. 
 */
#define MAX_INPUT_GAIN_LINE                     0x0f
#define MAX_INPUT_GAIN_MICROPHONE               0x07

#define MAX_MASTER_OUTPUT_VOLUME                0x0f
#define MAX_FM_OUTPUT_VOLUME                    0x0f
#define MAX_LINE_OUTPUT_VOLUME                  0x0f
#define MAX_CD_OUTPUT_VOLUME                    0x0f

#define MUTE_OUTPUT                             1
#define UNMUTE_OUTPUT                           0

#define PLAYBACK_ENABLE                         1
#define PLAYBACK_DISABLE                        0
#define CAPTURE_ENABLE                          1
#define CAPTURE_DISABLE                         0

#define ENABLE_DMA_PLAYBACK                     0
#define ENABLE_DMA_CAPTURE                      0
#define DISABLE_DMA_PLAYBACK                    1
#define DISABLE_DMA_CAPTURE                     1

#define DSP_DATA_LINEAR                       	0
#define DSP_DATA_COMPANDED                    	1

/*
 * After these sampling rates we must use the high speed part of the DSP (and
 * use different commands). 
 */
#define SB_CLASSIC_MAX_SPEED_RECORD             13000
#define SB_CLASSIC_MAX_SPEED_PLAYBACK           23000

#define SB_20_LOW_SPEED_RECORD                  15000
#define SB_20_LOW_SPEED_PLAYBACK                23000

#define SB_PRO_LOW_SPEED                        23000

/*
 * Maximum and minimum sampling rates. 
 */
#define SB_MAX_SAMPLE_RATE                      47619
#define SB_MIN_SAMPLE_RATE                      3906

#define DSP_MONO_MODE                         	0
#define DSP_STEREO_MODE                       	1

#define LEFT_CHANNEL                            0
#define RIGHT_CHANNEL                           1

#define LINE_LEVEL_INPUT                        0
#define MICROPHONE_LEVEL_INPUT                  1

#define DMA_DIRECTION_IN                        0
#define DMA_DIRECTION_OUT                       1

/*
 * Typedefs for SB Mono and stereo mixer registers. 
 */
typedef unsigned char sbMonoMixerRegister_t;

typedef union {
    struct {
        unsigned char
                right:4,
                left:4;
    }       reg;
    unsigned char data;
}       sbStereoMixerRegister_t;

/*
 * This list will grow bigger, if we decide to take advantages of different
 * cards in each of these two classes. That will be a pain though. ObS: Why
 * do we have to call old things classic? 
 */
typedef enum {
    SB_CLASSIC = 1, SB_20, SB_PRO, SB_16, SB_NONE
}       sbCardVersion_t;

typedef struct  {
        sbCardVersion_t version;
	char		*name;
        unsigned int 	majorVersion;
        unsigned int 	minorVersion;
        BOOL    	mixerPresent;
} sbCardParameters_t;


/*
 * Shadow registers for recording. Available only for SB Pro model.
 */
#define SB_RECORD_SOURCE_MIC                    0
#define SB_RECORD_SOURCE_CD                     1
#define SB_RECORD_SOURCE_LINE                   2

#define SB_RECORD_FREQ_HIGH                     1
#define SB_RECORD_FREQ_LOW                      0

#define SB_RECORD_ANFI_ON                       1
#define SB_RECORD_ANFI_OFF                      0

typedef union {
    struct {
        unsigned char
                rsvd1:1,                /* bit 0 */
                source:2, 
                highFreq:1, 
                rsvd2:1, 
                inputFilter:1, 
                rsvd3:2;                /* bit 7 */
    }       reg;
    unsigned char data;
}       sbRecordingMode_t;

/*
 * For playback. 
 */
#define SB_PLAYBACK_STEREO                      1
#define SB_PLAYBACK_MONO                        0

#define SB_PLAYBACK_DNFI_ON                     1
#define SB_PLAYBACK_DNFI_OFF                    0

typedef union {
    struct {
        unsigned char
                rsvd1:1,
                stereo:1,
                rsvd2:3,
                outputFilter:1,
                rsvd3:2;
    }       reg;
    unsigned char data;
}       sbPlaybackMode_t;
