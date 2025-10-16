/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.0 (the 'License').  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License."
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 *      performsound.c - recording and playback of sound.
 *      Written for release 1.0 by Lee Boynton
 *
 *      Release 2.0/2.1 version by Mike Minnick (mtm)
 *      Release 3.0/3.1 version by Julius Smith (jos)
 *      Release 3.3 version by Rakesh Dubey (rkd)
 *      Copyright 1988-94 NeXT, Inc.  All rights reserved.
 *
 *      Modification History: (Moved to bottom of page)
 */

#ifdef SHLIB
#include "shlib.h"
#endif SHLIB

#define TRY_SQUELCH 0           /* see also convertsound.c */
#define LIBSYS_VERSION          /* flag to ATC and resampling code */

#import <libc.h>
#import <c.h>
#import <mach/mach.h>
#import <mach/mach_init.h>
#import <mach/cthreads.h>
#import <stdlib.h>
#import <math.h>
#import <string.h>
#import <kern/time_stamp.h>
#import <servers/netname.h>

#import "utilsound.h"
#import "filesound.h"
#import "sounddriver.h"
#import "_sounddriver.h"
#import "accesssound.h"
#import "performsound.h"
#import "editsound.h"           /* for SNDCopySound() */
#import "_compression.h"
#import "_atcsound.h"
#import "_convertsound.h"

static int arch_cpu_type;       /* cf. /NextDeveloper/Headers/mach/machine.h */
static int arch_cpu_subtype;
// static int arch_cpu_speed;
static int arch_dsp_exists;
static int rateShift=0,makeMono=0,deviceSupportsMono=0; /* not reentrant */

static float *ATCBandGains = 0;
static int *ATCBandGainsDSP = 0;

static mutex_t q_lock = 0;
static condition_t q_changed=0;


#import "black_boxes.c"

static unsigned char *data_pointer(SNDSoundStruct *s)
{
    return (char *)s + s->dataLocation;
}

/*
 * Timeouts
 */
#define REPLY_TIMEOUT (500)
#define SETUP_DELAY (5000)              /* must handle potential kernel pageins */
#define SHUTDOWN_DELAY (250)
#define MIN_PREEMPT_DUR (300)
#define REPLY_BACKLOG (15)              /* about 3 per committed performance */
#define DSP_COMMANDS_SEND_TIMEOUT (1000)
#define DSP_COMMANDS_REPLY_TIMEOUT (2000)
#define COMPRESSED_IN_REPLY_TIMEOUT (1000)
#define BLACK_BOX_SEND_TIMEOUT (1000)

/*
 * Performance modes. 'OUT' modes are for playing, 'IN' modes for recording.
 * Note that all play options should be either "direct" or "thru DSP or direct"
 * or "unsupported" by release 3.1.
 */
                                          /* Play options for 3.0 */
#define MODE_NONE                       0 /* can't play it */
#define MODE_DIRECT_OUT                 1 /* Stereo, LINEAR_16, 22 or 44KHz */
#define MODE_MULAW_8KHZ_OUT             2 /* thru DSP or direct */
#define MODE_INDIRECT_OUT               3 /* direct only */
#define MODE_SQUELCH_OUT                4 /* thru DSP only */
#define MODE_MONO_OUT                   5 /* thru DSP or direct */
#define MODE_MONO_BYTE_OUT              6 /* thru DSP or direct */
#define MODE_CODEC_OUT                  7 /* thru DSP or direct */
#define MODE_DSP_CORE_OUT               8 /* thru DSP only */
#define MODE_ENCAPSULATED_DSP_DATA_OUT  9       /* not used */
#define MODE_DSP_DATA_OUT               10      /* not used */
#define MODE_COMPRESSED_OUT             11 /* thru DSP only */
#define MODE_DSP_COMMANDS_OUT           12 /* thru DSP only */
#define MODE_DSP_SSI_OUT                13 /* thru DSP only - no soundout */
#define MODE_DSP_SSI_COMPRESSED_OUT     14 /* thru DSP only - no soundout */
#define MODE_RESAMPLE_OUT               15 /* thru DSP or direct */
#define MODE_FLOAT_OUT                  16 /* direct only */
#define MODE_DOUBLE_OUT                 17 /* direct only */
#define MODE_MULAW_OUT                  18 /* direct only */
#define MODE_LINEAR_8_OUT               19 /* direct only */

#define IS_PLAY_MODE(mode) (mode < 256)
#define IS_RECORD_MODE(mode) (mode >= 256)

#define MODE_MULAW_8_IN                 256
#define MODE_LINEAR_8_IN                257
#define MODE_LINEAR_16_IN               258
#define MODE_DSP_DATA_IN                259
#define MODE_COMPRESSED_IN              260
#define MODE_DSP_MONO22_IN              261

/*
 * Driver priorities used by this file
 */
#define HI_PRI SNDDRIVER_MED_PRIORITY
#define LO_PRI SNDDRIVER_LOW_PRIORITY

extern int kern_timestamp();

typedef struct {
    int size;
    int (*black_box)(thread_args *targs);
    port_t stream_port;
    port_t reply_port;
    int tag;
    thread_args *thread_args;   /* _compression.h */
    struct mutex outputBlockSem;
    struct condition outputBlockCond;
    int outputBlockCount;
} black_box_struct;

/*
 * The performance queue structure
 */
typedef struct _PerfReq {
    struct _PerfReq *prev;
    struct _PerfReq *next;
    int id;
    SNDSoundStruct *sound;
    SNDSoundStruct sndInfo;
    SNDNotificationFun beginFun;
    SNDNotificationFun endFun;
    int tag;
    int priority;
    int preempt;
    int mode;
    int access;
    short status;
    short err;
    int prevFilter;
    int dspOptions;
    int recordFD;
    int startTime;
    int duration;
    port_t dev_port;
    port_t owner_port;
    port_t perf_port;
    void *work_ptr;
    char *work_block_ptr;
    int work_count;
    int work_block_count;
    black_box_struct *bbargs;
    boolean_t convertMulaw_8;		/* Make it a bitfield */
    boolean_t convertMulaw_16;
    boolean_t convert16_8;
    boolean_t convertStereo_To_Mono;
    boolean_t canPlayDirect;
} PerfReq;

static PerfReq *findRequestForTag(int tag);

#define NULL_REQUEST ((PerfReq *)0)

#define STATUS_FREE 0
#define STATUS_WAITING 1
#define STATUS_PENDING 2
#define STATUS_ACTIVE 3
#define STATUS_ABORTED 4

/* This function should stay in sync with the one in convertsound.c */
static int _findDSPcore(char *name, SNDSoundStruct **s)
{
    static SNDSoundStruct *lastCore=0;
    static char *lastName = NULL;
    char buf[1024];
    int err;

    if (lastName && !strcmp(lastName,name)) {
        *s = lastCore;
        err = SND_ERR_NONE;
    } else {
#ifdef DEBUG
        strcpy(buf,name);       /* Get dsp code from current directory */
#else
        strcpy(buf,"/usr/lib/sound/");
        strcat(buf,name);
#endif
        strcat(buf,".snd");
        err = SNDReadSoundfile(buf,s);
#ifdef DEBUG
        if (err) {              /* No such DSP code in current directory */
            strcpy(buf,"/usr/lib/sound/");
            strcat(buf,name);
            strcat(buf,".snd");
            err = SNDReadSoundfile(buf,s);
        }
#endif
        if (!err) {
            if (lastCore) SNDFree(lastCore);
            lastCore = *s;
            if (lastName)
              free(lastName);
            lastName = malloc(strlen(name)+1);
            strcpy(lastName,name);
        }
    }
    return err;
}

static char s_active_dsp_core[64];
static port_t s_active_dsp_cmd_port = 0;

void _SNDGetActiveDSPCore(char **dspcore,port_t *command_port)
{
    *dspcore = s_active_dsp_core;
    *command_port = s_active_dsp_cmd_port;
}

static int findDSPcore(char *name, SNDSoundStruct **s)
{
    int err = 0;
    if (arch_cpu_type != CPU_TYPE_MC680x0)
      return -1;
    err = _findDSPcore(name,s);
    if (!err)
      strcpy(s_active_dsp_core,name);
#ifdef DEBUG
    fprintf(stderr,"Active DSP core set to %s\n",s_active_dsp_core);
#endif
    return err;
}

static void sleep_msec(int msec)
{
    port_t x;
    msg_header_t msg;
    int err = port_allocate(task_self(), &x);
    msg.msg_local_port = x;
    msg.msg_size = sizeof(msg_header_t);
    err = msg_receive(&msg, RCV_TIMEOUT, msec);
    port_deallocate(task_self(), x);
}

static int msec_timestamp()
{
    int msec;
    struct tsval now;
    
    kern_timestamp(&now);
    /*
     * This was the old way:
     * usec = (double)now.low_val + ((double)now.high_val * 65536.0 * 65536.0);
     * msec = (int)(usec / 1000.0);
     */
    msec = now.low_val / 1000;
    return msec;
}

static int calc_duration(int mode, SNDSoundStruct *s)
{
    double samp_count;
    
#ifdef DEBUG
    printf("Duration timeout disabled\n");
    return 1000*60*5;
#endif DEBUG

    if (mode == MODE_COMPRESSED_IN) {
        samp_count = (double)SNDBytesToSamples(s->dataSize, s->channelCount,
                                               SND_FORMAT_LINEAR_16);
    } else
        samp_count = (double)SNDSampleCount(s);
    if (s->samplingRate && (samp_count > 0.))
        return (int)((samp_count * 1000.) / (double)s->samplingRate);
    else
        return 0;
}

static int calc_sample_count_from_ms(SNDSoundStruct *s, int milliseconds)
{
    if (s->samplingRate)
        return (int)((double)s->samplingRate * (double)milliseconds / 1000.);
    else
        return 0;
}

static int calc_ms_from_sample_count(SNDSoundStruct *s, int sampleCount)
{
    double samp_count = (double)sampleCount;
    if (s->samplingRate && samp_count > 0.)
        return (int)((samp_count * 1000.) / (double)s->samplingRate);
    else
        return 0;
}

static int calc_play_mode(SNDSoundStruct *s)
{
    int mode = MODE_NONE;
    if (!s || (s->magic != SND_MAGIC))
        return MODE_NONE;
    switch (s->dataFormat) {
      case SND_FORMAT_LINEAR_16:
      case SND_FORMAT_EMPHASIZED:
        if (s->samplingRate == SND_RATE_LOW || 
            s->samplingRate == SND_RATE_HIGH) {
            if (s->channelCount == 2)
                mode = MODE_DIRECT_OUT;
            else if (s->channelCount == 1)
                mode = MODE_MONO_OUT;
#ifndef ppc 
        } else if ((s->samplingRate == (int)(floor(SND_RATE_CODEC))) &&
                   s->channelCount == 1) {
            mode = MODE_CODEC_OUT;
#endif
        } else mode = MODE_RESAMPLE_OUT;
        break;
      case SND_FORMAT_MULAW_8:
        if (s->samplingRate == (int)(floor(SND_RATE_CODEC)))
          mode = MODE_MULAW_8KHZ_OUT;
        else 
          mode = MODE_MULAW_OUT;
        break;
      case SND_FORMAT_MULAW_SQUELCH:
        if (s->channelCount == 1) {
            if (s->samplingRate == (int)(floor(SND_RATE_CODEC)))
                mode = MODE_SQUELCH_OUT;
        }
        break;
      case SND_FORMAT_LINEAR_8:
        if (s->channelCount == 1)
          mode = MODE_MONO_BYTE_OUT;
        else
          mode = MODE_LINEAR_8_OUT;
        break;
      case SND_FORMAT_FLOAT:
        mode = MODE_FLOAT_OUT;
        break;
      case SND_FORMAT_DOUBLE:
        mode = MODE_DOUBLE_OUT;
        break;
      case SND_FORMAT_INDIRECT:
        mode = MODE_INDIRECT_OUT;
        break;
      case SND_FORMAT_DSP_CORE:
        if ( (s->channelCount == 2) && 
            (s->samplingRate == SND_RATE_LOW || 
             s->samplingRate == SND_RATE_HIGH) )
            mode = MODE_DSP_CORE_OUT;
        break;
      case SND_FORMAT_COMPRESSED:
      case SND_FORMAT_COMPRESSED_EMPHASIZED:
        if ((s->samplingRate == SND_RATE_LOW || 
             s->samplingRate == SND_RATE_HIGH) &&
            (s->channelCount == 1 || s->channelCount == 2))
            mode = MODE_COMPRESSED_OUT;
        break;
      case SND_FORMAT_DSP_COMMANDS:
        if ( (s->channelCount == 2) && 
            (s->samplingRate == SND_RATE_LOW || 
             s->samplingRate == SND_RATE_HIGH) )
            mode = MODE_DSP_COMMANDS_OUT;
        break;
      default:
        break;
    }
    return mode;
}

static int calc_dsp_play_mode(SNDSoundStruct *s)
{
    int mode = MODE_NONE;
    if (!s || (s->magic != SND_MAGIC))
        return 0;
    switch (s->dataFormat) {
      case SND_FORMAT_LINEAR_16:
      case SND_FORMAT_EMPHASIZED:
      case SND_FORMAT_DSP_DATA_16:
        /*
         * Device must interpret data so channel count
         * and sample rate are not checked.
         */
        mode = MODE_DSP_SSI_OUT;
        break;
      case SND_FORMAT_COMPRESSED:
      case SND_FORMAT_COMPRESSED_EMPHASIZED:
        /*
         * DSP compression code interprets this data so
         * we must check the channel count.
         */
        if (s->channelCount == 1 || s->channelCount == 2)
            mode = MODE_DSP_SSI_COMPRESSED_OUT;
        break;
      default:
        break;
    }
    return mode;
}

static int calc_indirect_mode(SNDSoundStruct *s)
{
    SNDSoundStruct **iBlock = (SNDSoundStruct **)s->dataLocation;
    if (iBlock && *iBlock)
        return (calc_play_mode(*iBlock));
    else
        return MODE_NONE;
}

static int calc_record_mode(SNDSoundStruct *s)
{
    if (!s || (s->magic != SND_MAGIC))
        return 0;
    switch (s->dataFormat) {
      case SND_FORMAT_MULAW_8:
        return MODE_MULAW_8_IN;
        break;
      case SND_FORMAT_LINEAR_8:
        return MODE_LINEAR_8_IN;
        break;
      case SND_FORMAT_LINEAR_16:
        return MODE_LINEAR_16_IN;
        break;
      case SND_FORMAT_DSP_DATA_16:
        if (s->samplingRate == SND_RATE_LOW &&
            s->channelCount == 1)
            return MODE_DSP_MONO22_IN;
        else
            /*
             * User is free to interpret data in any way, so
             * channel count and sampling rate are not checked.
             */
            return MODE_DSP_DATA_IN;
      case SND_FORMAT_COMPRESSED:
      case SND_FORMAT_COMPRESSED_EMPHASIZED:
        if (s->channelCount == 1 || s->channelCount == 2)
            return MODE_COMPRESSED_IN;
        break;
      default:
        break;
    }
    return MODE_NONE;
}


static int calc_record_nsamples(PerfReq *pr)
{
    int err, count, width;
    char *p;
    err = SNDGetDataPointer(pr->sound,&p,&count,&width);
    if (err) return 0;
    return pr->sound->dataSize / (width * pr->sound->channelCount);
}

static int calc_play_nsamples(PerfReq *pr)
{
    int delta, count, max_count;
    int now = msec_timestamp();
    
    if (pr->status == STATUS_PENDING || pr->status == STATUS_WAITING) return 0;
    if (pr->status != STATUS_ACTIVE) return -1;
    max_count = SNDSampleCount(pr->sound);
    delta = now - pr->startTime;
    count = calc_sample_count_from_ms(pr->sound,delta);
    return (count > max_count)? max_count : count;
}

static int modeOptimizable(int mode, int last_mode, 
                           SNDSoundStruct *s, SNDSoundStruct *last_s)
{
    switch (mode) {
      case MODE_MULAW_8KHZ_OUT:
      case MODE_MULAW_8_IN:
      case MODE_LINEAR_8_IN:
      case MODE_LINEAR_16_IN:
      case MODE_MONO_BYTE_OUT:
      case MODE_LINEAR_8_OUT:
      case MODE_CODEC_OUT:
      case MODE_DSP_SSI_OUT:
      case MODE_DIRECT_OUT:
      case MODE_MONO_OUT:
      case MODE_FLOAT_OUT:
      case MODE_DOUBLE_OUT:
      case MODE_MULAW_OUT:
      case MODE_DSP_DATA_IN:
        return (mode == last_mode &&
                s->samplingRate == last_s->samplingRate &&
                s->channelCount == last_s->channelCount);
      case MODE_COMPRESSED_IN:
        /* FIXME: must also check compression subheader parameters */
        return (mode == last_mode &&
                s->channelCount == last_s->channelCount);
      case MODE_DSP_MONO22_IN:
        return (mode == last_mode &&
                s->samplingRate == last_s->samplingRate &&
                s->channelCount == last_s->channelCount);
      case MODE_DSP_COMMANDS_OUT:
      case MODE_DSP_CORE_OUT:
      case MODE_DSP_SSI_COMPRESSED_OUT:
      case MODE_COMPRESSED_OUT:
      case MODE_RESAMPLE_OUT:
      default:
        return 0;
    }
}

static int calc_access(int mode)
{
    /*
     * dsp_access is set if the DSP exists at all.
     * The DSP can still turn out to be busy at perform time.
     * A failure return from SNDAcquire() is used to detect DSP busy.
     *
     * FIXME: this is based on host_self(), not the destination host.
     */
    int dsp_access = (arch_dsp_exists ? SND_ACCESS_DSP : 0);

    /*
     * FIXME: MODE_INDIRECT_OUT always sets SND_ACCESS_DSP
     * (if arch_dsp_exists).
     */
    if (IS_PLAY_MODE(mode)) {
        if (mode == MODE_DIRECT_OUT ||
            mode == MODE_FLOAT_OUT ||
            mode == MODE_DOUBLE_OUT ||
            mode == MODE_LINEAR_8_OUT || mode == MODE_MULAW_OUT)
          return SND_ACCESS_OUT;
        else if (mode == MODE_DSP_SSI_OUT ||
                 mode == MODE_DSP_SSI_COMPRESSED_OUT)
          return dsp_access;
        else
          return (SND_ACCESS_OUT | dsp_access);
    } else {
        if (mode == MODE_MULAW_8_IN || mode == MODE_LINEAR_8_IN ||
            mode == MODE_LINEAR_16_IN)
          return SND_ACCESS_IN;
        else if (mode == MODE_DSP_DATA_IN || mode == MODE_COMPRESSED_IN ||
                 mode == MODE_DSP_MONO22_IN)
          return dsp_access;
        else
          return (SND_ACCESS_IN | dsp_access); /* at least TRY for DSP */
    }
    return 0;
}


static int play_configure_simplifications(int mode, int access, 
                                          SNDSoundStruct *s,
                                          int *rateShiftP, int *makeMonoP)
/*
 * Decide on rateShift (0, 1, or 2) and makeMono (0 or 1) as a function
 * of the play mode and the hardware we can use for the performance.
 *
 * This routine must be called after initiate_performance() (which calls
 * SNDAcquire() to lock down all hardware resources we ultimately get)
 * and before play_configure_direct() which sets up the output stream
 * for the duration of the performance (setting output sampling 
 * rate and some day channel count).
 */
{
    int hiRate = ((s->samplingRate == SND_RATE_HIGH) ? 1 : 0);
    int stereo = ((s->channelCount == 2) ? 1 : 0);

    switch(mode) {
    case MODE_COMPRESSED_OUT:
        if(((SNDCompressionSubheader *)(((char *)s)+s->dataLocation))->method 
           == SND_CFORMAT_ATC) {
            if (arch_cpu_type==CPU_TYPE_I386) {
                *rateShiftP = (hiRate ? 1 : 0);
                *makeMonoP = (stereo ? 1 : 0);
            } else if (arch_cpu_type==CPU_TYPE_MC680x0) {
                *rateShiftP = (hiRate ? 1 : 0);
                *makeMonoP = (stereo ? 1 : 0);
            } /* else assume the machine can handle it (88k, 601, etc.) */
        } else
            *rateShiftP = *makeMonoP = 0;
        break;
    case MODE_RESAMPLE_OUT:
      {
          double rateOut;
          rateOut = (double) (s->samplingRate > SND_RATE_LOW+1 ? 
                              SND_RATE_HIGH : SND_RATE_LOW);
          
          *makeMonoP = 0;       /* FIXME: resampling should support this */
          if (arch_cpu_type==CPU_TYPE_MC680x0 && !(access & SND_ACCESS_DSP)) {
              /* FIXME: rateShift may not be necessary for Turbo, e.g. */
              *rateShiftP = ((rateOut == SND_RATE_HIGH) ? 1 : 0);
              /* rateOut reduced to SND_RATE_LOW */
          } else if (arch_cpu_type==CPU_TYPE_I386) {
              *rateShiftP = ((rateOut == SND_RATE_HIGH) ? 2 : 1);
              /* rateOut reduced to SND_RATE_LOW_PC */
          } /* else assume the machine can handle it (88k, 601, etc.) */
      }
        break;
    default:                    /* do nothing => no simplifications */
        break;
    }
#ifdef DEBUG
    fprintf(stderr,"rateShift = %d, makeMono = %d\n",*rateShiftP,*makeMonoP);
#endif
    return 0;
}

static int play_configure_dsp_core(SNDSoundStruct *core, int dmasize, int rate,
                                   port_t dev_port, port_t owner_port,
                                   port_t *cmd_port)
    /* dspcores wait for the bufsize to be sent to them before starting */
{
    int protocol = 0;
    int config, err;
    port_t stream_port;
    
    if (rate > SND_RATE_LOW)
        config = SNDDRIVER_STREAM_DSP_TO_SNDOUT_44;
    else
        config = SNDDRIVER_STREAM_DSP_TO_SNDOUT_22;
    err = snddriver_stream_setup(dev_port, owner_port,
                                 config,
                                 dmasize,
                                 2,
                                 24*1024,
                                 32*1024,
                                 &protocol,
                                 &stream_port);
    if (err != KERN_SUCCESS) return err;
    err = snddriver_dsp_protocol(dev_port,owner_port,protocol);
    if (err != KERN_SUCCESS) return err;
    err = SNDBootDSP(dev_port, owner_port, core); /* does *not* autorun! */
    if (err != KERN_SUCCESS) return err;
    err = snddriver_get_dsp_cmd_port(dev_port,owner_port,cmd_port);
    s_active_dsp_cmd_port = *cmd_port;
    return err;
}

static int play_configure_dsp_data(SNDSoundStruct *core, int dmasize,
                                   int width, int rate,
                                   int low_water, int high_water,
                                   port_t dev_port, port_t owner_port,
                                   port_t *stream_port)
{
    int protocol = 0;
    int config, err;
    port_t cmd_port;
    
    if (rate > SND_RATE_LOW)
        config = SNDDRIVER_STREAM_THROUGH_DSP_TO_SNDOUT_44;
    else
        config = SNDDRIVER_STREAM_THROUGH_DSP_TO_SNDOUT_22;
    err = snddriver_stream_setup(dev_port, owner_port,
                                 config,
                                 dmasize,
                                 width,
                                 low_water,
                                 high_water,
                                 &protocol,
                                 stream_port);
    if (err != KERN_SUCCESS) return err;
    err = snddriver_dsp_protocol(dev_port,owner_port,protocol);
    if (err != KERN_SUCCESS) return err;
    err = SNDBootDSP(dev_port, owner_port, core);
    err = snddriver_get_dsp_cmd_port(dev_port, owner_port, &cmd_port);
    if  (err != KERN_SUCCESS) return err;
    s_active_dsp_cmd_port = cmd_port;
    err = snddriver_dsp_write(cmd_port,&dmasize,1,4,HI_PRI);
    return err? SND_ERR_CANNOT_PLAY : SND_ERR_NONE;
}

static int play_configure_dma_dsp_data(SNDSoundStruct *core, int dmasize,
                                   int width, int rate,
                                   int low_water, int high_water,
                                   port_t dev_port, port_t owner_port,
                                   port_t *stream_port)
{
    int protocol = 0;
    int config, err;
    port_t cmd_port;
    
    if (rate > SND_RATE_LOW)
        config = SNDDRIVER_DMA_STREAM_THROUGH_DSP_TO_SNDOUT_44;
    else
        config = SNDDRIVER_DMA_STREAM_THROUGH_DSP_TO_SNDOUT_22;
    err = snddriver_stream_setup(dev_port, owner_port,
                                 config,
                                 dmasize,
                                 width,
                                 low_water,
                                 high_water,
                                 &protocol,
                                 stream_port);
    if (err != KERN_SUCCESS) return err;
    err = snddriver_dsp_protocol(dev_port,owner_port,protocol);
    if (err != KERN_SUCCESS) return err;
    err = SNDBootDSP(dev_port, owner_port, core);
    err = snddriver_get_dsp_cmd_port(dev_port, owner_port, &cmd_port);
    if  (err != KERN_SUCCESS) return err;
    s_active_dsp_cmd_port = cmd_port;
    err = snddriver_dsp_write(cmd_port,&dmasize,1,4,HI_PRI);
    return err? SND_ERR_CANNOT_PLAY : SND_ERR_NONE;
}

static int play_configure_dsp_commands(int dmasize,
                                       int width, int rate,
                                       int low_water, int high_water,
                                       port_t dev_port, port_t owner_port,
                                       port_t *stream_port)
{
    int protocol = SNDDRIVER_DSP_PROTO_DSPMSG;
    int config, err;
    port_t cmd_port;
    
    if (rate > SND_RATE_LOW)
        config = SNDDRIVER_STREAM_DSP_TO_SNDOUT_44;
    else
        config = SNDDRIVER_STREAM_DSP_TO_SNDOUT_22;
    err = snddriver_stream_setup(dev_port, owner_port,
                                 config,
                                 dmasize,
                                 width,
                                 low_water,
                                 high_water,
                                 &protocol,
                                 stream_port);
    if (err != KERN_SUCCESS) return err;
    err = snddriver_dsp_protocol(dev_port,owner_port,protocol);
    if (err != KERN_SUCCESS) return err;
    err = snddriver_get_dsp_cmd_port(dev_port, owner_port, &cmd_port);
    if  (err != KERN_SUCCESS) return err;
    s_active_dsp_cmd_port = cmd_port;
    err = snddriver_dsp_reset(cmd_port, HI_PRI);
    return err? SND_ERR_CANNOT_PLAY : SND_ERR_NONE;
}

static int play_configure_dsp_ssi(SNDSoundStruct *core, int dmasize,
                                  int width, int rate,
                                  int low_water, int high_water,
                                  port_t dev_port, port_t owner_port,
                                  port_t *stream_port)
{
    int protocol = 0;
    int config, err;
    port_t cmd_port;
    
    config = SNDDRIVER_DMA_STREAM_TO_DSP;
    err = snddriver_stream_setup(dev_port, owner_port,
                                 config,
                                 dmasize,
                                 width,
                                 low_water,
                                 high_water,
                                 &protocol,
                                 stream_port);
    if (err != KERN_SUCCESS) return err;
    err = snddriver_dsp_protocol(dev_port,owner_port,protocol);
    if (err != KERN_SUCCESS) return err;
    err = SNDBootDSP(dev_port, owner_port, core);
    if (err) return SND_ERR_CANNOT_PLAY;
    err = snddriver_get_dsp_cmd_port(dev_port, owner_port, &cmd_port);
    if  (err != KERN_SUCCESS) return err;
    s_active_dsp_cmd_port = cmd_port;
    err = snddriver_dsp_write(cmd_port,&dmasize,1,4,HI_PRI);
    return err? SND_ERR_CANNOT_PLAY : SND_ERR_NONE;
}

static int play_configure_direct(int rate, port_t dev_port,
                                 port_t owner_port, port_t *stream_port)
{
    int protocol = 0;
    int config, err;
    int dmasize = vm_page_size / 2;
    
    /*
     * The old stream setup interface does not support mono.
     */
    deviceSupportsMono = FALSE;

    if (rate > SND_RATE_LOW)
        config = SNDDRIVER_STREAM_TO_SNDOUT_44;
    else
        config = SNDDRIVER_STREAM_TO_SNDOUT_22;
    err = snddriver_stream_setup(dev_port, owner_port,
                                 config,
                                 dmasize,
                                 2,
                                 256*1024,
                                 512*1024,
                                 &protocol,
                                 stream_port);
    return err;
}

static int play_configure_direct_generic(int width, port_t dev_port,
                                         port_t owner_port,
                                         port_t *stream_port)
{
    int protocol = 0;
    int dmasize = vm_page_size / 2;

    return snddriver_stream_setup(dev_port, owner_port,
                                  SNDDRIVER_STREAM_TO_SNDOUT_GENERIC,
                                  dmasize,
                                  width,
                                  256*1024,
                                  512*1024,
                                  &protocol,
                                  stream_port);
}

static boolean_t ratePresent(int srate, int all_rates, int low_rate,
                             int high_rate)
{
    if ((all_rates & SOUNDDRIVER_STREAM_FORMAT_RATE_CONTINUOUS) &&
        (srate >= low_rate) && (srate <= high_rate))
        return TRUE;

    if (srate >= 8000 && srate <= 8013)
        return (all_rates & SOUNDDRIVER_STREAM_FORMAT_RATE_8000 ?
                TRUE : FALSE);

    switch (srate) {
      case 11025:
        return (all_rates & SOUNDDRIVER_STREAM_FORMAT_RATE_11025 ?
                TRUE : FALSE);
      case 16000:
        return (all_rates & SOUNDDRIVER_STREAM_FORMAT_RATE_16000 ?
                TRUE : FALSE);
      case 22050:
        return (all_rates & SOUNDDRIVER_STREAM_FORMAT_RATE_22050 ?
                TRUE : FALSE);
      case 32000:
        return (all_rates & SOUNDDRIVER_STREAM_FORMAT_RATE_32000 ?
                TRUE : FALSE);
      case 44100:
        return (all_rates & SOUNDDRIVER_STREAM_FORMAT_RATE_44100 ?
                TRUE : FALSE);
      case 48000:
        return (all_rates & SOUNDDRIVER_STREAM_FORMAT_RATE_48000 ?
                TRUE : FALSE);
      default:
        return FALSE;
    }
}

static boolean_t set_sndout_format(int mode, SNDSoundStruct *s,
                                   port_t dev_port, port_t owner_port,
                                   boolean_t *convertMulaw_8,
                                   boolean_t *convertMulaw_16,
                                   boolean_t *convert16_8,
                                   boolean_t *convertStereo_To_Mono,
				   boolean_t *result)
{
    int srate, save_srate, encoding, chans, low_rate, high_rate;
    kern_return_t err;
    int ret = TRUE;
    
    *convertMulaw_8 = *convertMulaw_16 = FALSE;
    *convert16_8 = *convertStereo_To_Mono = FALSE;      
    
    makeMono = deviceSupportsMono = FALSE;
    rateShift = 0;

    err = snddriver_get_sndout_formats(dev_port, &srate, &low_rate,
                                       &high_rate, &encoding, &chans);    
    if (err)
        return FALSE;

    /*
     * Do we need stereo to mono conversion? 
     */
    if ((s->channelCount == 2) && (chans == 1))
        *convertStereo_To_Mono = TRUE;
    else if ((s->channelCount == 1) && (chans == 2))
#ifdef ppc
        return FALSE;
#else
    	chans = 1;
#endif
	
/*      
    if (s->channelCount <= 0 || s->channelCount > chans)
        return FALSE;
    chans = s->channelCount;
*/      

   /* Tell black_box thread not to convert mono to stereo */
    if (chans == 1)
        deviceSupportsMono = TRUE;

    if (!ratePresent(s->samplingRate, srate, low_rate, high_rate))
        return FALSE;
    save_srate = srate;
    srate = s->samplingRate;
    
    switch (mode) {
      case MODE_MULAW_OUT:
      case MODE_MULAW_8KHZ_OUT:
        if (encoding & SOUNDDRIVER_STREAM_FORMAT_ENCODING_MULAW_8) {
            encoding = SOUNDDRIVER_STREAM_FORMAT_ENCODING_MULAW_8;
        } else if (encoding & SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_16) {
            encoding = SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_16;
            *convertMulaw_16 = TRUE;
            ret = FALSE;
        } else if (encoding & SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_8) {
            encoding = SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_8;
            *convertMulaw_8 = TRUE;
            ret = FALSE;
        } else
            return FALSE;
        break;
      case MODE_MONO_BYTE_OUT:
      case MODE_LINEAR_8_OUT:
        if (!(encoding & SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_8))	{
            // default is linear 16
	    encoding = SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_16;
            ret = FALSE;
	} else	{ 
	    encoding = SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_8;
        }
	break;
      case MODE_DIRECT_OUT:
        if (encoding & SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_16)    {
            encoding = SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_16;
        } else if (encoding & SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_8) {
            *convert16_8 = TRUE;
            ret = FALSE;
        } else
            return FALSE;
        break;
      case MODE_MONO_OUT:
      case MODE_CODEC_OUT:
      case MODE_RESAMPLE_OUT:
        if (encoding & SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_16)    {
            encoding = SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_16;
        } else if (encoding & SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_8) {
            *convert16_8 = TRUE;
            ret = FALSE;
        } else
            return FALSE;
        break;
      case MODE_COMPRESSED_OUT:
        if (!(encoding & SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_16))	{
	    *result = FALSE;
            return FALSE;
	}
        encoding = SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_16;
        if(((SNDCompressionSubheader *)(((char *)s)+s->dataLocation))->method 
           == SND_CFORMAT_ATC) {
            if (arch_cpu_type==CPU_TYPE_I386) {
                if (srate == 44100) {
                    if (!ratePresent(22050, save_srate, low_rate, high_rate))
                        return FALSE;
                    srate = 22050;
                    rateShift = 1;
                }
                if (chans == 2) {
                    chans = 1;
                    makeMono = deviceSupportsMono = TRUE;
                }
            } else
                return FALSE;
        }
        break;
      default:
        return FALSE;
    }

    err = snddriver_set_sndout_format(dev_port, owner_port,
                                      srate, encoding, chans);
    if (err)
        return FALSE;
    else
        return ret;
}

typedef struct {                /* keep in sync with dsp library DSPObject.c */
    int sampleCount;
    int dspBufSize;
    int soundoutBufSize;
    int reserved;
} commandsSubHeader;

/* DMA buffer sizes to DSP in 16-bit words */
#define DECOMPRESS_DMA_SIZE     2048
#define RESAMPLE_DMA_SIZE       1024
#define ATC_DMA_SIZE            ATC_DMA_BUFFER_SIZE

static int play_configure(int mode, SNDSoundStruct *s,port_t dev_port,
                          port_t owner_port, port_t *play_port,
                          int dspOptions, int *required_accessP,
                          boolean_t *canPlayDirect,
                          boolean_t *convertMulaw_8,
                          boolean_t *convertMulaw_16,
                          boolean_t *convert16_8,
                          boolean_t *convertStereo_To_Mono)
{
    int err;
    int rate = s->samplingRate;
    int dmasize = vm_page_size / 2;
    int headerSize, timeIncrement;
    SNDSoundStruct *core, **iBlock;
    port_t cmd_port;
    boolean_t result;
    commandsSubHeader *subheader;
    SNDCompressionSubheader *compressionsubheader 
      = (SNDCompressionSubheader *)data_pointer(s);

    result = TRUE;	/* Assume we can either play it directly or convert */

    *canPlayDirect = set_sndout_format(mode, s, dev_port, owner_port,
                                       convertMulaw_8, convertMulaw_16,
                                       convert16_8, convertStereo_To_Mono,
				       &result);

    /* We can not play this sound. */
    if (result == FALSE)
    	return KERN_FAILURE;
	
    switch (mode) {
      case MODE_MULAW_OUT:
        if (*canPlayDirect || *convertMulaw_8 || *convertMulaw_16)
            return play_configure_direct_generic((*convertMulaw_16 ? 2 : 1),
                                                 dev_port,owner_port,
                                                 play_port);
        else
            return play_configure_direct(rate,dev_port,owner_port, play_port);
      case MODE_LINEAR_8_OUT:
        if (*canPlayDirect)
            return play_configure_direct_generic(1,
                                                 dev_port,owner_port,
                                                 play_port);
        else
            return play_configure_direct_generic(2,
                                                 dev_port,owner_port,
                                                 play_port);
      case MODE_DIRECT_OUT:
        if (*canPlayDirect || *convert16_8)
            return play_configure_direct_generic((*canPlayDirect ? 2 : 1), 
                dev_port, owner_port, play_port);
        else
            return play_configure_direct(rate,dev_port,owner_port, play_port);
      case MODE_FLOAT_OUT:
      case MODE_DOUBLE_OUT:
        if (*canPlayDirect)
            return play_configure_direct_generic(2,dev_port,owner_port,
                                                 play_port);
        else
            return play_configure_direct(rate,dev_port,owner_port, play_port);
      case MODE_MULAW_8KHZ_OUT:
        if (s->channelCount == 1)
          err = findDSPcore("mulawcodec",&core);
        else
          err = findDSPcore("mulawcodec2",&core);
        if (err)
          *required_accessP &= ~SND_ACCESS_DSP; /* No DSP version */
        if (*required_accessP & SND_ACCESS_DSP)
          return play_configure_dsp_data(core,dmasize,1,rate,48*1024,64*1024,
                                         dev_port,owner_port,play_port);
        else if (*canPlayDirect || *convertMulaw_16 || *convertMulaw_8)
            return play_configure_direct_generic((*convertMulaw_16 ? 2 : 1),
                                                 dev_port,owner_port,
                                                 play_port);
        else
            return play_configure_direct(rate,dev_port,owner_port,play_port);
      case MODE_INDIRECT_OUT:
        iBlock = (SNDSoundStruct **)s->dataLocation;
        if (iBlock && *iBlock)
            return play_configure(calc_play_mode(*iBlock), *iBlock,
                                  dev_port,owner_port,play_port,dspOptions,
                                  required_accessP,canPlayDirect,
                                  convertMulaw_8,convertMulaw_16,
                                  convert16_8, convertStereo_To_Mono);
        return SND_ERR_UNKNOWN;
      case MODE_SQUELCH_OUT:
#if TRY_SQUELCH
        err = findDSPcore("mulawcodecsquelch",&core);
        if (err != SND_ERR_NONE) return SND_ERR_CANNOT_CONFIGURE;
        return play_configure_dsp_data(core,dmasize,1,rate,48*1024,64*1024,
                                       dev_port,owner_port,play_port);
#else
#ifdef DEBUG
        fprintf(stderr,"*** Squelch format is broken and DISABLED!!!\n");
#endif
        /*** FIXME: dspEncodeSquelch:SNDRunDSP walks over stack 
         so playing the format has never been tested! ***/
        return SND_ERR_NOT_IMPLEMENTED;
#endif TRY_SQUELCH
      case MODE_MONO_OUT:
        err = findDSPcore("mono",&core);
        if (err)
          *required_accessP &= ~SND_ACCESS_DSP; /* No DSP version */
        if (*required_accessP & SND_ACCESS_DSP)
          return play_configure_dsp_data(core,dmasize,2,rate,512*1024,768*1024,
                                         dev_port,owner_port,play_port);
        else if (*canPlayDirect || *convert16_8)
            return play_configure_direct_generic(
                (*canPlayDirect ? 2 : 1), dev_port, owner_port, play_port);
        else
            return play_configure_direct(rate,dev_port,owner_port,play_port);
      case MODE_MONO_BYTE_OUT:
        err = findDSPcore("monobyte",&core);
        if (err)
          *required_accessP &= ~SND_ACCESS_DSP; /* No DSP version */
        if (*required_accessP & SND_ACCESS_DSP)
          return play_configure_dsp_data(core,dmasize,1,rate,64*1024,96*1024,
                                         dev_port,owner_port,play_port);
        else if (*canPlayDirect)
            return play_configure_direct_generic(1,dev_port,owner_port,
                                                 play_port);
        else
            return play_configure_direct_generic(2,
                                                 dev_port,owner_port,
                                                 play_port);
      case MODE_CODEC_OUT:
        err = findDSPcore("codec",&core);
        if (err)
          *required_accessP &= ~SND_ACCESS_DSP; /* No DSP version */
        if (*required_accessP & SND_ACCESS_DSP)
          return play_configure_dsp_data(core,dmasize,2,rate,48*1024,64*1024,
                                         dev_port,owner_port,play_port);
        else if (*canPlayDirect || *convert16_8)
            return play_configure_direct_generic(
                (*canPlayDirect ? 2 : 1), dev_port, owner_port, play_port);
        else
            return play_configure_direct(rate,dev_port,owner_port,play_port);
      case MODE_DSP_CORE_OUT:
        /* dmasize = get_dmasize_from_header */
        return play_configure_dsp_core(s,dmasize,rate,
                                       dev_port,owner_port,play_port);
      case MODE_COMPRESSED_OUT:
        if (!(*required_accessP & SND_ACCESS_DSP)) {
            if (*canPlayDirect) {
                return play_configure_direct_generic(2,dev_port,owner_port,
                                                     play_port);
            } else {
                play_configure_simplifications(mode,*required_accessP,s,
                                               &rateShift,&makeMono);
                rate >>= rateShift;
                /* FIXME: channel count (1 or 2) should also be passed with */
                /* rate if (makeMono) channelCount = 1; */
                return play_configure_direct(rate,dev_port,owner_port,
                                             play_port);
            }
        }
        /* else decompression using the DSP */
        if (compressionsubheader->method == SND_CFORMAT_ATC) {
            dmasize = ATC_DMA_SIZE; /* 16-bit words */
            err = findDSPcore("sndoutdecompressatc",&core);
        } else {
            dmasize = DECOMPRESS_DMA_SIZE; /* 16-bit words */
            err = findDSPcore("sndoutdecompress",&core);
        }
        if (err != SND_ERR_NONE)
          return SND_ERR_CANNOT_CONFIGURE;
        err = play_configure_dma_dsp_data(core,dmasize,2,rate,48*1024,64*1024,
                                          dev_port,owner_port,play_port);
        if (err != SND_ERR_NONE) return SND_ERR_CANNOT_CONFIGURE;
        err = snddriver_get_dsp_cmd_port(dev_port, owner_port, &cmd_port);
        if  (err != KERN_SUCCESS) return err;
        /*
         * DMA must start on a page boundry so the whole sound is sent -
         * tell the dsp how many words to ignore (the sound header).
         * play_configure_dma_dsp_data() has already written the dma buf size.
         */
        headerSize = (s->dataLocation % vm_page_size ) / 2;
        err = snddriver_dsp_write(cmd_port,&headerSize,1,4,HI_PRI);
        if  (err != KERN_SUCCESS) return err;

        err = snddriver_dsp_write(cmd_port,&s->channelCount,1,4,HI_PRI);
        if  (err != KERN_SUCCESS) return err;

        if (compressionsubheader->method == SND_CFORMAT_ATC) {
            if (ATCBandGains == 0) {
                ATCBandGains = _SNDGetATCEGP();
                ATCBandGainsDSP = (int *)malloc(ATC_NBANDS * sizeof(int));
            }
            floatToUnsignedDSPFix24(ATC_NBANDS,ATCBandGains,ATCBandGainsDSP);

            err = snddriver_dsp_write(cmd_port,ATCBandGainsDSP,ATC_NBANDS,
                                      4,HI_PRI);
        }
        if  (err != KERN_SUCCESS) return err;
        return SND_ERR_NONE;

      case MODE_RESAMPLE_OUT:
        /* Look for resample cores now since they may not make release */
        if (s->channelCount == 1)
          err = findDSPcore("resample1",&core);
        else
          err = findDSPcore("resample2",&core);
        if (err)
          *required_accessP &= ~SND_ACCESS_DSP; /* No DSP version */
        if (!(*required_accessP & SND_ACCESS_DSP)) {
            if (*canPlayDirect || *convert16_8)
                return play_configure_direct_generic(
                    (*canPlayDirect ? 2 : 1), dev_port, owner_port, play_port);
            else {
                /* cthread feeds play_port */
                play_configure_simplifications(mode,*required_accessP,s,
                                               &rateShift,&makeMono);
                rate = (s->samplingRate > SND_RATE_LOW ? 
                        SND_RATE_HIGH : SND_RATE_LOW);
                rate >>= rateShift;
                /* FIXME: channel count (1 or 2) should also be passed
                   with rate */
                /* if (makeMono) channelCount = 1; */
                return play_configure_direct(rate,dev_port,owner_port,
                                             play_port);
            }
        } else {
            err = play_configure_dma_dsp_data(core,dmasize,2,rate,
                                              48*1024,64*1024,
                                              dev_port,owner_port,play_port);
            if (err != SND_ERR_NONE) return SND_ERR_CANNOT_CONFIGURE;
            err = snddriver_get_dsp_cmd_port(dev_port, owner_port, &cmd_port);
            if  (err != KERN_SUCCESS) return err;
            /*
             * DMA must start on a page boundry so the whole sound is sent -
             * tell the dsp how many words to ignore (the sound header).
             */
            dmasize = RESAMPLE_DMA_SIZE; /* FIXME: ignored by resample.asm */
            headerSize = (s->dataLocation % vm_page_size) / 2;
            err = snddriver_dsp_write(cmd_port,&headerSize,1,4,HI_PRI);
            if  (err != KERN_SUCCESS) return err;
            err = snddriver_dsp_write(cmd_port,&s->channelCount,1,4,HI_PRI);
            if  (err != KERN_SUCCESS) return err;
            /*
             * Always resample to 44K for playback.
             */
            timeIncrement = (int)(((double)(1<<19)) * 
                                  (((double)s->samplingRate)/SND_RATE_HIGH) 
                                  + 0.5);
            err = snddriver_dsp_write(cmd_port,&timeIncrement,1,4,HI_PRI);
            if  (err != KERN_SUCCESS) return err;
            return SND_ERR_NONE;
        }
    case MODE_DSP_COMMANDS_OUT:
        subheader = (commandsSubHeader *)((char *)s + s->dataLocation);
        dmasize = subheader->dspBufSize;
        /* FIXME: should set soundout dma size from subheader */
        return play_configure_dsp_commands(dmasize,2,rate,0,0,
                                           dev_port,owner_port,play_port);
    case MODE_DSP_SSI_OUT:
        dmasize = 1024;
        err = findDSPcore("ssiplay",&core);
        if (err != SND_ERR_NONE) return SND_ERR_CANNOT_CONFIGURE;
        err = play_configure_dsp_ssi(core,dmasize,2,rate,48*1024,64*1024,
                                     dev_port,owner_port,play_port);
        if (err != SND_ERR_NONE) return SND_ERR_CANNOT_CONFIGURE;
        err = snddriver_get_dsp_cmd_port(dev_port, owner_port, &cmd_port);
        if  (err != KERN_SUCCESS) return err;
        err = snddriver_dsp_write(cmd_port,&dspOptions,1,4,HI_PRI);
        if  (err != KERN_SUCCESS) return err;
        return SND_ERR_NONE;
      case MODE_DSP_SSI_COMPRESSED_OUT:
        dmasize = DECOMPRESS_DMA_SIZE;
        /* FIXME: currently not implemented */
        err = findDSPcore("ssidecompress",&core);
        if (err != SND_ERR_NONE) return SND_ERR_CANNOT_CONFIGURE;
        err = play_configure_dsp_ssi(core,dmasize,2,rate,48*1024,64*1024,
                                     dev_port,owner_port,play_port);
        if (err != SND_ERR_NONE) return SND_ERR_CANNOT_CONFIGURE;
        err = snddriver_get_dsp_cmd_port(dev_port, owner_port, &cmd_port);
        if  (err != KERN_SUCCESS) return err;
        err = snddriver_dsp_write(cmd_port,&dspOptions,1,4,HI_PRI);
        if  (err != KERN_SUCCESS) return err;
        err = snddriver_dsp_write(cmd_port,&s->channelCount,1,4,HI_PRI);
        if  (err != KERN_SUCCESS) return err;
        return SND_ERR_NONE;
      case MODE_ENCAPSULATED_DSP_DATA_OUT:
      case MODE_DSP_DATA_OUT:
      default:
        return SND_ERR_BAD_CONFIGURATION;
    }
}

#define DSP_LOW_WATER           (512*1024)
#define DSP_HIGH_WATER          (768*1024)
#define OTHER_LOW_WATER         (512*1024)
#define OTHER_HIGH_WATER        (768*1024)
#define CODEC_LOW_WATER         (48*1024)
#define CODEC_HIGH_WATER        (64*1024)
#define DSP_DMA_SIZE            (vm_page_size/2)
#define DSP_MONO22_DMA_SIZE     1024    /* hard-coded in derecord22m.asm */
#define CODEC_DMA_SIZE          256
#define OTHER_DMA_SIZE          (vm_page_size/2)
#define COMPRESS_DMA_SIZE       512

static int record_configure(int mode, SNDSoundStruct *s,port_t dev_port, 
                            port_t owner_port, port_t *record_port,
                            boolean_t *convertMulaw_8,
                            boolean_t *convertMulaw_16,
                            boolean_t *convert16_8,
                            boolean_t *convertStereo_To_Mono)
{
    int err, protocol = 0;
    SNDSoundStruct *core;
    int srate, encoding, chans, low_rate, high_rate;
    int width = 1;
    int dma_size, low_water, high_water;
    
    switch (mode) {
      case MODE_MULAW_8_IN:
      case MODE_LINEAR_8_IN:
        err = snddriver_get_sndin_formats(dev_port, &srate, &low_rate,
                                          &high_rate, &encoding, &chans);
        if (err) {
            /* We must be talking to a 3.0 machine */
            if (mode == MODE_MULAW_8_IN &&
                s->channelCount == 1 &&
                s->samplingRate == (int)(floor(SND_RATE_CODEC)))
                err = snddriver_stream_setup(dev_port, owner_port,
                                             SNDDRIVER_STREAM_FROM_SNDIN,
                                             CODEC_DMA_SIZE,
                                             1,
                                             CODEC_LOW_WATER,
                                             CODEC_HIGH_WATER,
                                             &protocol,
                                             record_port);
        }
        if (err) return SND_ERR_CANNOT_CONFIGURE;
        if (s->channelCount <= 0 || s->channelCount > chans)
            return SND_ERR_CANNOT_CONFIGURE;
        chans = s->channelCount;
        if (!ratePresent(s->samplingRate, srate, low_rate, high_rate))
            return SND_ERR_CANNOT_CONFIGURE;
        srate = s->samplingRate;
        if (mode == MODE_LINEAR_8_IN) {
            if (!(encoding & SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_8))
                return SND_ERR_CANNOT_CONFIGURE;
            encoding = SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_8;
        } else if (mode == MODE_MULAW_8_IN) {
            if (encoding & SOUNDDRIVER_STREAM_FORMAT_ENCODING_MULAW_8)
                encoding = SOUNDDRIVER_STREAM_FORMAT_ENCODING_MULAW_8;
            else if (encoding & SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_16) {
                /* ask for linear and convert to mulaw in thread */
                *convertMulaw_16 = TRUE;
                encoding = SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_16;
                width = 2;
            } else if (encoding &
                       SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_8) {
                *convertMulaw_8 = TRUE;
                encoding = SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_8;
            } else
                return SND_ERR_CANNOT_CONFIGURE;
        }
        err = snddriver_set_sndin_format(dev_port, owner_port,
                                         srate, encoding, chans);
        if (err) return SND_ERR_CANNOT_CONFIGURE;
        if ((srate == (int)(floor(SND_RATE_CODEC))) &&
            (chans == 1) &&
            ((encoding == SOUNDDRIVER_STREAM_FORMAT_ENCODING_MULAW_8) ||
             (encoding == SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_8))) {
            dma_size = CODEC_DMA_SIZE;
            low_water = CODEC_LOW_WATER;
            high_water = CODEC_HIGH_WATER;
        } else {
            dma_size = OTHER_DMA_SIZE;
            low_water = OTHER_LOW_WATER;
            high_water = OTHER_HIGH_WATER;
        }
        err = snddriver_stream_setup(dev_port, owner_port,
                                     SNDDRIVER_STREAM_FROM_SNDIN_GENERIC,
                                     dma_size,
                                     width,
                                     low_water,
                                     high_water,
                                     &protocol,
                                     record_port);
        return err? SND_ERR_CANNOT_CONFIGURE : SND_ERR_NONE;
      case MODE_LINEAR_16_IN:
        err = snddriver_get_sndin_formats(dev_port, &srate, &low_rate,
                                          &high_rate, &encoding, &chans);
        if (err) return SND_ERR_CANNOT_CONFIGURE;
        if (s->channelCount <= 0 || s->channelCount > chans)
            return SND_ERR_CANNOT_CONFIGURE;
        chans = s->channelCount;
        if (!ratePresent(s->samplingRate, srate, low_rate, high_rate))
            return SND_ERR_CANNOT_CONFIGURE;
        srate = s->samplingRate;
        if (!(encoding & SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_16))
            return SND_ERR_CANNOT_CONFIGURE;
        encoding = SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_16;
        err = snddriver_set_sndin_format(dev_port, owner_port,
                                         srate, encoding, chans);
        if (err) return SND_ERR_CANNOT_CONFIGURE;
        err = snddriver_stream_setup(dev_port, owner_port,
                                     SNDDRIVER_STREAM_FROM_SNDIN_GENERIC,
                                     OTHER_DMA_SIZE,
                                     2,
                                     OTHER_LOW_WATER,
                                     OTHER_HIGH_WATER,
                                     &protocol,
                                     record_port);
        return err? SND_ERR_CANNOT_CONFIGURE : SND_ERR_NONE;
      case MODE_DSP_DATA_IN:
        err = snddriver_stream_setup(dev_port, owner_port,
                                     SNDDRIVER_STREAM_FROM_DSP,
                                     DSP_DMA_SIZE,
                                     2,
                                     DSP_LOW_WATER,
                                     DSP_HIGH_WATER,
                                     &protocol,
                                     record_port);
        if (err) return SND_ERR_CANNOT_CONFIGURE;
        err = snddriver_dsp_protocol(dev_port,owner_port,protocol);
        if (err) return SND_ERR_CANNOT_CONFIGURE;
        err = findDSPcore("dsprecord",&core);
        if (err) return SND_ERR_CANNOT_CONFIGURE;
        err = SNDBootDSP(dev_port,owner_port,core);
        return err? SND_ERR_CANNOT_CONFIGURE : SND_ERR_NONE;
      case MODE_COMPRESSED_IN:
        err = snddriver_stream_setup(dev_port, owner_port,
                                     SNDDRIVER_STREAM_FROM_DSP,
                                     COMPRESS_DMA_SIZE,
                                     2,
                                     DSP_LOW_WATER,
                                     DSP_HIGH_WATER,
                                     &protocol,
                                     record_port);
        if (err) return SND_ERR_CANNOT_CONFIGURE;
        err = snddriver_dsp_protocol(dev_port,owner_port,protocol);
        if (err) return SND_ERR_CANNOT_CONFIGURE;
        err = findDSPcore("ssicompress",&core);
        if (err) return SND_ERR_CANNOT_CONFIGURE;
        err = SNDBootDSP(dev_port,owner_port,core);
        return err? SND_ERR_CANNOT_CONFIGURE : SND_ERR_NONE;
      case MODE_DSP_MONO22_IN:
        err = snddriver_stream_setup(dev_port, owner_port,
                                     SNDDRIVER_STREAM_FROM_DSP,
                                     DSP_MONO22_DMA_SIZE,
                                     2,
                                     DSP_LOW_WATER,
                                     DSP_HIGH_WATER,
                                     &protocol,
                                     record_port);
        if (err) return SND_ERR_CANNOT_CONFIGURE;
        err = snddriver_dsp_protocol(dev_port,owner_port,protocol);
        if (err) return SND_ERR_CANNOT_CONFIGURE;
        err = findDSPcore("derecord22m",&core);
        if (err) return SND_ERR_CANNOT_CONFIGURE;
        err = SNDBootDSP(dev_port,owner_port,core);
        return err? SND_ERR_CANNOT_CONFIGURE : SND_ERR_NONE;
      default:
        return SND_ERR_BAD_CONFIGURATION;
    }
}

/*
 * Low level performance support
 */

static int s_kill_black_box_thread;
static mutex_t thread_lock;

#ifdef CHECK_DATA
static SNDSoundStruct *ckSound = 0;
static short *ckPtr = 0;
static int ckCount = 0;
#endif CHECK_DATA

#ifdef MEASURE_SPEED

/************************ Time stamping utilities *************************/

static struct timeval s_timeval; /* used for time-stamping */
/* static struct timezone s_timezone; (not used) */
static int s_prvtime = 0;
static int s_curtime = 0;
static int s_deltime = 0;

static inline int getTime(void) 
/*
 * Returns the time in microseconds since it was last called.
 */
{
    gettimeofday(&s_timeval, NULL /* &s_timezone (2K of junk) */);
    s_curtime = (s_timeval.tv_sec & (long)0x7FF)*1000000 
      + s_timeval.tv_usec;
    if (s_prvtime == 0)
      s_deltime = 0;
    else
      s_deltime = s_curtime - s_prvtime;
    s_prvtime = s_curtime;
    return(s_deltime);
}
    
#endif MEASURE_SPEED

#define MAX_SBUF		64

static mutex_t thread_lock_new;	// TEST
    

static any_t black_box_thread(any_t args)
{
    int err = 0, ssize, count = 0;
    black_box_struct *bbargs = (black_box_struct *)args;
    SNDSoundStruct *sstruct = bbargs->thread_args->sound;
    thread_args *targs = bbargs->thread_args;
    int inBlockSize = targs->inBlockSize; /* bytes */
    int enq_count = 0;
    boolean_t paused = FALSE;
    boolean_t notify;
    PerfReq *pr;
    
    int i;
    struct	{
	short *outSoundBuf;
	int outBufSize;
	boolean_t allocated;
    } sbuf[MAX_SBUF];
    int outBufCount = 0;
    void *bufAddress;
    
    /* safe enqueue count (in bytes) before starting dma */
#define BIG_DMA_SIZE    	vm_page_size
#define BIG_DMA_COUNT   	8
#define MIN_ENQ_COUNT   	(BIG_DMA_SIZE * BIG_DMA_COUNT)

#define BB_OUTPUT_NOTIFY_COUNT	16

    mutex_lock(q_lock);

    pr = findRequestForTag( bbargs->tag );
    if ( pr == NULL )
    {
         mutex_unlock(q_lock);
         goto Preempt_exit;
    }
    pr->bbargs = bbargs;

    mutex_unlock(q_lock);

    mutex_init( &bbargs->outputBlockSem );
    condition_init ( &bbargs->outputBlockCond );
    bbargs->outputBlockCount = 0;

    targs->lastBlock = FALSE;
    targs->firstBlock = TRUE;
    targs->discontiguous = FALSE; /* We have all input data in one array */

    for (i=0; i < MAX_SBUF; i++)	{
    	sbuf[i].allocated = FALSE;
    }
    
#ifdef DEBUG
    fprintf(stderr, "inBlockSize %d outBlockSize %d\n",
    	inBlockSize, targs->outBlockSize);
#endif DEBUG
    
    while (count < bbargs->size) { /* bytes */
#ifdef MEASURE_SPEED
        getTime();
#endif MEASURE_SPEED
		
	err = vm_allocate(task_self(), (pointer_t *)(&bufAddress), 
			targs->outBlockSize, 1);
	targs->outPtr = bufAddress;
	sbuf[outBufCount].outSoundBuf = bufAddress;
	sbuf[outBufCount].outBufSize = targs->outBlockSize;
	sbuf[outBufCount].allocated = TRUE;
	outBufCount++;
	if (outBufCount == MAX_SBUF)
	    outBufCount = 0;
	
#ifdef DEBUG
	fprintf(stderr, "Alloctated %d bytes at %x\n", targs->outBlockSize,
			 targs->outPtr);
#endif DEBUG
	
        /*
         * Process one block and send it to output.
         */
        if (s_kill_black_box_thread)
          break;
        if ((count+inBlockSize) >= bbargs->size) {
            targs->inBlockSize = inBlockSize = bbargs->size - count;
            targs->lastBlock = TRUE;
        }

        err = (*(bbargs->black_box))(targs);
			
        if (err || s_kill_black_box_thread)
          goto bbt_exit;

        /* 
         * Convert mono to stereo.  
         * FIXME: use mono stream to driver instead. This is a waste.
         */
        if ((sstruct->channelCount == 1 || targs->makeMono) &&
             !deviceSupportsMono) {
            short *outPtrSrc, *outPtrDst, temp;
            int i, nSamps = targs->outBlockSize / sizeof(short);
            outPtrDst = targs->outPtr + 2*nSamps - 1;
            outPtrSrc = targs->outPtr +   nSamps - 1;
            for (i=0; i<nSamps; i++) {
                temp = *outPtrSrc--;
                *outPtrDst-- = temp;
                *outPtrDst-- = temp;
            }
            targs->outBlockSize *= 2;
        }

        mutex_lock(thread_lock);

#ifdef CHECK_DATA
        if (!ckSound) {
            int err,s,w;
            SNDCompressionSubheader *subheader;
            subheader = (SNDCompressionSubheader *)((char *)sstruct
                                                    + sstruct->dataLocation);
            s = subheader->originalSize * sizeof(short);
            if (sstruct->channelCount == 1)
              s *= 2;
            err = SNDAlloc(&ckSound,s,SND_FORMAT_LINEAR_16,
                           sstruct->samplingRate,2,4);
            if (err)
              fprintf(stderr,"SNDAlloc err %d\n",err);
            err = SNDGetDataPointer(ckSound,&(char *)ckPtr,&s,&w);
            if (err)
              fprintf(stderr,"SNDGetDataPointer err %d\n",err);
        }
        for (ckCount = 0; ckCount < targs->outBlockSize/2; ckCount++) {
            *ckPtr++ = targs->outPtr[ckCount];
        }
#endif CHECK_DATA

        if (targs->firstBlock) {
            snddriver_stream_control(bbargs->stream_port,bbargs->tag,
                                     SNDDRIVER_PAUSE_STREAM);
            paused = TRUE;
        }

        notify = FALSE;
        mutex_lock( &bbargs->outputBlockSem );
        if ( targs->lastBlock )
        {
            notify = TRUE;
            bbargs->outputBlockCount = 0;
        }
        else if ( ++bbargs->outputBlockCount == BB_OUTPUT_NOTIFY_COUNT )
        {
            notify = TRUE;
        }            
        mutex_unlock( &bbargs->outputBlockSem );        

        err = snddriver_stream_start_writing(bbargs->stream_port,
                                             (void *)targs->outPtr,
                                             targs->outBlockSize/2, /*shorts*/
                                             bbargs->tag,
                                             0,0,
                                             targs->firstBlock,
                                             notify,
                                             0,0,0,0,
                                             bbargs->reply_port);
	enq_count += targs->outBlockSize;
        if (paused && ((enq_count >= MIN_ENQ_COUNT) || targs->lastBlock)) {
            snddriver_stream_control(bbargs->stream_port,bbargs->tag,
                                     SNDDRIVER_RESUME_STREAM);
            paused = FALSE;
        }
        
        mutex_unlock(thread_lock);
        targs->firstBlock = FALSE;

        if (err) {
#ifdef DEBUG
            fprintf(stderr,"performsound: snddriver_stream_start_writing() "
                    "returns error %d\n",err);
#endif DEBUG
            if (err != 0)
              err = 0; /* Keep going on spurious replies */
        }

        /* FIXME: if stream aborted or term'd, set s_kill_black_box_thread */
        /* Can this happen?  Does user have stream_port as handle? */

        count += inBlockSize;
        ((char *)(targs->inPtr)) += inBlockSize;

        mutex_lock( &bbargs->outputBlockSem );
        while ( !paused && (bbargs->outputBlockCount == 2*BB_OUTPUT_NOTIFY_COUNT-1) )
        {
           condition_wait( &bbargs->outputBlockCond, &bbargs->outputBlockSem );
        }
        mutex_unlock( &bbargs->outputBlockSem );        
        
    bbt_exit:
        if (err || s_kill_black_box_thread)
          break;

#ifdef MEASURE_SPEED
        getTime();
        fprintf(stderr,"black_box_thread: "
                "Time to process %f seconds of sound = %f seconds\n",
                ((double)(targs->outBlockSize/4)) / 
                ((double)sstruct->samplingRate),
                ((double)s_deltime) / 1000000.0);
#endif MEASURE_SPEED

    }

#ifdef DEBUG
    if (err)
      fprintf(stderr,"performsound: black-box thread died on error %d\n",err);
#endif DEBUG

    for (i=0; i < MAX_SBUF; i++)	{
    	if (sbuf[i].allocated == FALSE)
		continue;
	
	err = vm_deallocate(task_self(), 
		(pointer_t)(sbuf[i].outSoundBuf), sbuf[i].outBufSize);
		
#ifdef DEBUG
	fprintf(stderr, "Dealloctated %d bytes at %x\n", 
			 sbuf[i].outBufSize,
			 sbuf[i].outSoundBuf);
#endif DEBUG
    }
    	
    ssize = sstruct->dataLocation + sstruct->dataSize;
    vm_deallocate(task_self(), (pointer_t)sstruct, ssize); /* sound copy */

    mutex_lock( q_lock );
    condition_clear( &bbargs->outputBlockCond );
    mutex_clear( &bbargs->outputBlockSem );    
    pr->bbargs = 0;
    mutex_unlock( q_lock );

Preempt_exit: ;

    if (bbargs->thread_args->parameters)
        free(bbargs->thread_args->parameters);
    free(bbargs->thread_args);
    free(bbargs);
    
#ifdef CHECK_DATA
    fprintf(stderr,"performsound.c: replaying sound to see if it's ok...\n");
    mutex_lock(thread_lock);
    ckSound->samplingRate >>= targs->rateShift;
    SNDStartPlaying(ckSound,1234,0,0,0,0);
// causes deadlock:    SNDWait(1234);
// lack causes leak:   SNDFree(ckSound);
    mutex_unlock(thread_lock);
#endif CHECK_DATA

    cthread_exit(0);
    
    return NULL;
}

static int play_black_box(int tag, 
                          SNDSoundStruct *s, 
                          int inBlockSize,
                          int outBlockSize,
                          int (*fn)(),
                          void *parameters,
                          port_t stream_port,
                          port_t reply_port)
{
    black_box_struct *bbargs;
    thread_args *targs;
    SNDSoundStruct *sCopy;
    int err;
    
    /* 
     * General allocation: All state needed by the thread is allocated
     * here and passed to the thread.  The thread is responsible for 
     * deallocating everything on exit.  Thus, anything permanently 
     * allocated here is deallocated in black_box_thread() when the 
     * thread finishes.  FIXME: Need mutex around deallocation?
     */
    if (s->dataFormat == SND_FORMAT_INDIRECT)
        err = SNDCompactSamples(&sCopy, s);
    else
        err = SNDCopySound(&sCopy,s); /* user may free s at any time */
    if (err)
      return SND_ERR_KERNEL;

    if (err)
      return SND_ERR_KERNEL;
    
    bbargs = (black_box_struct *)malloc(sizeof(black_box_struct));
    targs = (thread_args *)malloc(sizeof(thread_args));
    if (!bbargs || !targs)
      return SND_ERR_KERNEL;
    
    bbargs->size = sCopy->dataSize;
    bbargs->black_box = fn;
    bbargs->stream_port = stream_port;
    bbargs->reply_port = reply_port;
    bbargs->tag = tag;

    targs->inPtr = (short *) ((char *)sCopy + sCopy->dataLocation);
    targs->inBlockSize = inBlockSize; /* bytes */
    targs->outBlockSize = outBlockSize; /* computed by thread each block */
    targs->outBlockSizeMax = outBlockSize;
    targs->sound = sCopy;               /* for misc info */
    targs->makeMono = makeMono;
    targs->rateShift = rateShift;
    targs->parameters = parameters;

    bbargs->thread_args = targs;

    s_kill_black_box_thread = FALSE; /* should be in thread state targs */
    
    mutex_lock(thread_lock_new);	// TEST
    cthread_detach(cthread_fork(black_box_thread, (any_t)bbargs));
    //cthread_join(cthread_fork(black_box_thread, (any_t)bbargs));
    mutex_unlock(thread_lock_new);	// TEST
    
    return SND_ERR_NONE;
}

/*
 * This is temporary till we fix ATC/old sytle compression problems and can
 * use the regular play_black_box() code. The new play_box_code tickles
 * compression problems which are basically due to the fact that the
 * tags->outBlockSize is too little. This causes memory exceptions later on.
 * This must get fixed since playback of any compressed sound file can cause
 * a crash. 
 */

/*
 * Not exactly.   There's a static pointer in the black box thread that
 * is accessed by other threads.    This indeed causes memory exceptions.
 * The following extern helps manage an array of input pointers to avoid
 * the collision between threads.  - pcd 9/94
 */
extern int free_soundPtr ();

static any_t black_box_thread_comp(any_t args)
{
    int err = 0, ssize, count = 0;
    black_box_struct *bbargs = (black_box_struct *)args;
    SNDSoundStruct *sstruct = bbargs->thread_args->sound;
    thread_args *targs = bbargs->thread_args;
    int inBlockSize = targs->inBlockSize; /* bytes */
    int enq_count = 0;
    boolean_t paused = FALSE;

    /* safe enqueue count (in bytes) before starting dma */
#define BIG_DMA_SIZE	vm_page_size
#define BIG_DMA_COUNT	8
#define MIN_ENQ_COUNT	(BIG_DMA_SIZE * BIG_DMA_COUNT)

    targs->lastBlock = FALSE;
    targs->firstBlock = TRUE;
    targs->discontiguous = FALSE; /* We have all input data in one array */

    while (count < bbargs->size) { /* bytes */
#ifdef MEASURE_SPEED
	getTime();
#endif MEASURE_SPEED
	/*
	 * Process one block and send it to output.
	 */
	if (s_kill_black_box_thread) {
	  break;
	}
	if ((count+inBlockSize) >= bbargs->size) {
	    targs->inBlockSize = inBlockSize = bbargs->size - count;
	    targs->lastBlock = TRUE;
	}

	err = (*(bbargs->black_box))(targs);

	if (err || s_kill_black_box_thread) {
	  goto bbt_exit;
	}

	/* 
	 * Convert mono to stereo.  
	 * FIXME: use mono stream to driver instead. This is a waste.
	 */
	if ((sstruct->channelCount == 1 || targs->makeMono) &&
             !deviceSupportsMono) {
	    short *outPtrSrc, *outPtrDst, temp;
	    int i, nSamps = targs->outBlockSize / sizeof(short);
	    outPtrDst = targs->outPtr + 2*nSamps - 1;
	    outPtrSrc = targs->outPtr +   nSamps - 1;
	    for (i=0; i<nSamps; i++) {
		temp = *outPtrSrc--;
		*outPtrDst-- = temp;
		*outPtrDst-- = temp;
	    }
	    targs->outBlockSize *= 2;
	}

	mutex_lock(thread_lock);

#ifdef CHECK_DATA
	if (!ckSound) {
	    int err,s,w;
	    SNDCompressionSubheader *subheader;
	    subheader = (SNDCompressionSubheader *)((char *)sstruct
						    + sstruct->dataLocation);
	    s = subheader->originalSize * sizeof(short);
	    if (sstruct->channelCount == 1)
	      s *= 2;
	    err = SNDAlloc(&ckSound,s,SND_FORMAT_LINEAR_16,
			   sstruct->samplingRate,2,4);
	    if (err)
	      fprintf(stderr,"SNDAlloc err %d\n",err);
	    err = SNDGetDataPointer(ckSound,&(char *)ckPtr,&s,&w);
	    if (err)
	      fprintf(stderr,"SNDGetDataPointer err %d\n",err);
	}
	for (ckCount = 0; ckCount < targs->outBlockSize/2; ckCount++) {
	    *ckPtr++ = targs->outPtr[ckCount];
	}
#endif CHECK_DATA

	if (targs->firstBlock) {
	    snddriver_stream_control(bbargs->stream_port,bbargs->tag,
				     SNDDRIVER_PAUSE_STREAM);
	    paused = TRUE;
	}

	err = snddriver_stream_start_writing(bbargs->stream_port,
					     (void *)targs->outPtr,
					     targs->outBlockSize/2, /*shorts*/
					     bbargs->tag,
					     0,0,
					     targs->firstBlock,
					     targs->lastBlock,
					     0,0,0,0,
					     bbargs->reply_port);
	enq_count += targs->outBlockSize;
	if (paused && ((enq_count >= MIN_ENQ_COUNT) || targs->lastBlock)) {
	    snddriver_stream_control(bbargs->stream_port,bbargs->tag,
				     SNDDRIVER_RESUME_STREAM);
	    paused = FALSE;
	}

	mutex_unlock(thread_lock);
	targs->firstBlock = FALSE;
	if (err) {
#ifdef DEBUG
	    fprintf(stderr,"performsound: snddriver_stream_start_writing() "
		    "returns error %d\n",err);
#endif
	    if (err > 0)
	      err = 0; /* Keep going on spurious replies */
	}

	/* FIXME: if stream aborted or term'd, set s_kill_black_box_thread */
	/* Can this happen?  Does user have stream_port as handle? */

        count += inBlockSize;
	((char *)(targs->inPtr)) += inBlockSize;
    bbt_exit:
	if (err || s_kill_black_box_thread) {
	  break;
	}
#ifdef MEASURE_SPEED
	getTime();
	fprintf(stderr,"black_box_thread: "
		"Time to process %f seconds of sound = %f seconds\n",
		((double)(targs->outBlockSize/4)) / 
		((double)sstruct->samplingRate),
		((double)s_deltime) / 1000000.0);
#endif MEASURE_SPEED
    }

#ifdef DEBUG
    if (err)
      fprintf(stderr,"performsound: black-box thread died on error %d\n",err);
#endif

    ssize = sstruct->dataLocation + sstruct->dataSize;
    vm_deallocate(task_self(),(pointer_t)sstruct,ssize); /* sound copy */
    vm_deallocate(task_self(),(pointer_t)bbargs->thread_args->outPtr,
		  bbargs->thread_args->outBlockSizeMax);
    if (bbargs->thread_args->parameters)
	free(bbargs->thread_args->parameters);
    free(bbargs->thread_args);
    free(bbargs);
#ifdef CHECK_DATA
    fprintf(stderr,"performsound.c: replaying sound to see if it's ok...\n");
    mutex_lock(thread_lock);
    ckSound->samplingRate >>= targs->rateShift;
    SNDStartPlaying(ckSound,1234,0,0,0,0);
// causes deadlock:    SNDWait(1234);
// lack causes leak:   SNDFree(ckSound);
    mutex_unlock(thread_lock);
#endif
    if (!targs->lastBlock) {
	err = free_soundPtr ((int *)sstruct); /* Set err for debug if needed */
    }
    cthread_exit(0);
    return NULL;
}

static int play_black_box_comp(int tag, 
			  SNDSoundStruct *s, 
			  int inBlockSize,
			  int outBlockSize,
			  int (*fn)(),
			  void *parameters,
			  port_t stream_port,
			  port_t reply_port)
{
    black_box_struct *bbargs;
    thread_args *targs;
    short *outSoundBuf = 0;
    SNDSoundStruct *sCopy;
    int err;
    
    /* 
     * General allocation: All state needed by the thread is allocated
     * here and passed to the thread.  The thread is responsible for 
     * deallocating everything on exit.  Thus, anything permanently 
     * allocated here is deallocated in black_box_thread() when the 
     * thread finishes.  FIXME: Need mutex around deallocation?
     */
    if (s->dataFormat == SND_FORMAT_INDIRECT)
	err = SNDCompactSamples(&sCopy, s);
    else
	err = SNDCopySound(&sCopy,s); /* user may free s at any time */
    if (err)
      return SND_ERR_KERNEL;

    err = vm_allocate(task_self(), (pointer_t *)(&outSoundBuf), 
		      outBlockSize,1);
    if (err)
      return SND_ERR_KERNEL;
    
    bbargs = (black_box_struct *)malloc(sizeof(black_box_struct));
    targs = (thread_args *)malloc(sizeof(thread_args));
    if (!bbargs || !targs)
      return SND_ERR_KERNEL;
    
    bbargs->size = sCopy->dataSize;
    bbargs->black_box = fn;
    bbargs->stream_port = stream_port;
    bbargs->reply_port = reply_port;
    bbargs->tag = tag;

    targs->inPtr = (short *) ((char *)sCopy + sCopy->dataLocation);
    targs->outPtr = outSoundBuf;
    targs->inBlockSize = inBlockSize; /* bytes */
    targs->outBlockSize = outBlockSize;	/* computed by thread each block */
    targs->outBlockSizeMax = outBlockSize;
    targs->sound = sCopy;		/* for misc info */
    targs->makeMono = makeMono;
    targs->rateShift = rateShift;
    targs->parameters = parameters;

    bbargs->thread_args = targs;

    s_kill_black_box_thread = FALSE; /* should be in thread state targs */
    cthread_detach(cthread_fork(black_box_thread_comp, (any_t)bbargs));
    return SND_ERR_NONE;
}


static int play_samples(int tag, SNDSoundStruct *s, port_t stream_port,
                        port_t reply_port)
{
    int err, size, width, totalSize, headerSize, pages;
    int dmaBytes;
    int flushBytes = 0;
    char *p = (char *)s;

    if (s->dataFormat == SND_FORMAT_LINEAR_16   ||
        s->dataFormat == SND_FORMAT_DSP_DATA_16 ||
        s->dataFormat == SND_FORMAT_EMPHASIZED  ||
        s->dataFormat == SND_FORMAT_COMPRESSED  ||
        s->dataFormat == SND_FORMAT_COMPRESSED_EMPHASIZED) {
        width = 2;
        size = s->dataSize >> 1;
    } else {
        width = 1;
        size = s->dataSize;
    }
    /*
     * Formats that use DMA writes to DSP send the sound header with the
     * data because the buffer must be page-aligned.  The total size must
     * be bumped to the next dma size.  This is OK because the sound was
     * created with either vm_allocate() or map_fd() and therefore has
     * memory up to the next page size.
     */
    if (s->dataFormat == SND_FORMAT_COMPRESSED ||
        s->dataFormat == SND_FORMAT_COMPRESSED_EMPHASIZED) {
        SNDCompressionSubheader *compressionsubheader 
          = (SNDCompressionSubheader *)data_pointer(s);
        headerSize = s->dataLocation;
        if (headerSize >= vm_page_size) {
            pages = headerSize / vm_page_size;
            headerSize -= pages * vm_page_size;
            p += pages * vm_page_size;
        }
        if (compressionsubheader->method == SND_CFORMAT_ATC) {
            dmaBytes = ATC_DMA_SIZE * 2;
            flushBytes = 2*vm_page_size;
        } else {
            flushBytes = 0;
            dmaBytes = DECOMPRESS_DMA_SIZE * 2;
        }
        totalSize = s->dataSize + headerSize;
        if (totalSize % dmaBytes) /* round up to multiple of dma buffer size */
          totalSize = (totalSize + dmaBytes) & ~(dmaBytes - 1);
        size = totalSize / 2;   /* 16-bit samples */
    } else
      p += s->dataLocation;
    if (!size) return SND_ERR_CANNOT_PLAY;

    err = snddriver_stream_start_writing(stream_port,
                                         (void *)p,
                                         size,
                                         tag,
                                         0,0,
                                         1,(flushBytes==0 ? 1 : 0),
                                         0,0,0,0,
                                         reply_port);
    if (flushBytes != 0) {
        unsigned char *zeros;

        if (err)
          return SND_ERR_CANNOT_PLAY;

        vm_allocate(task_self(),(vm_address_t *)&zeros, flushBytes, TRUE);

        err = snddriver_stream_start_writing(stream_port,
                                             (void *)zeros,
                                             flushBytes>>1 /* shorts */,
                                             tag,
                                             0, 1 /* auto-deallocate */,
                                             1,1,
                                             0,0,0,0,
                                             reply_port);
    }
    return (err ? SND_ERR_CANNOT_PLAY : SND_ERR_NONE);
}

static int play_resamples(int tag, SNDSoundStruct *s, port_t stream_port,
                          port_t reply_port, int required_access)
    /* Plays MODE_RESAMPLE_OUT */
{
    int err, size, totalSize, headerSize, pages;
    int dmaBytes = RESAMPLE_DMA_SIZE * 2;
    char *p = (char *)s;

    if (!(required_access & SND_ACCESS_DSP)) { /* cthread feeds stream_port */
        double rateIn, rateOut, factor;
        int inBlockSize;
        int outBlockSize;
        int cheapInterpolation = 0;
        float *parameters = (float *)malloc(sizeof(float)*2);

        rateIn = ((double) s->samplingRate);
        rateOut = (double) (s->samplingRate > SND_RATE_LOW+1 ? 
                             SND_RATE_HIGH : SND_RATE_LOW);

        if (arch_cpu_type==CPU_TYPE_MC680x0 || arch_cpu_type==CPU_TYPE_I386) {
            cheapInterpolation = 1;
        } /* else assume the machine can handle it (88k, 601, etc.) */

        factor = rateOut / rateIn;
        factor /= ((double)(1<<rateShift));
        parameters[0] = (float) factor;
        ((int *)parameters)[1] = cheapInterpolation;
        inBlockSize = vm_page_size;
        if (factor <= 1.0)
          outBlockSize = inBlockSize; /* one page */
        else
          outBlockSize = (int) ceil(inBlockSize * factor);

/* 
 * FIXME - When we can send a mono stream to the sound driver, 
 * conversion to stereo is not necessary here.
 */
        if (s->channelCount == 1 || makeMono)
          outBlockSize *= 2;    /* Make room for conversion to stereo */

        return play_black_box(tag, s, inBlockSize, outBlockSize, 
                              &resample_thread, parameters, 
                              stream_port, reply_port);
    }
    /*
     * Formats that use DMA writes to DSP send the sound header with the
     * data because the buffer must be page-aligned.  The total size must
     * be bumped to the next dma size.  This is OK because the sound was
     * created with either vm_allocate() or map_fd() and therefore has
     * memory up to the next page size.
     */
    headerSize = s->dataLocation;
    if (headerSize >= vm_page_size) {
        pages = headerSize / vm_page_size;
        headerSize -= pages * vm_page_size;
        p += pages * vm_page_size;
    }
    totalSize = s->dataSize + headerSize;
    if (totalSize % dmaBytes) {
        /* Must zero extra memory for resample filter */
        bzero(p+totalSize, dmaBytes - (totalSize % dmaBytes));
        totalSize = (totalSize + dmaBytes) & ~(dmaBytes - 1);
    }
    size = totalSize / 2;       /* 16-bit samples */
    if (!size) return SND_ERR_CANNOT_PLAY;
    
    err = snddriver_stream_start_writing(stream_port,
                                         (void *)p,
                                         size,
                                         tag,
                                         0,0,
                                         1,1,0,0,0,0,
                                         reply_port);
    return err? SND_ERR_CANNOT_PLAY : SND_ERR_NONE;
}

static int play_indirect_samples(int tag, SNDSoundStruct *s,
                                 port_t stream_port, port_t reply_port)
{
    SNDSoundStruct *s2, **iBlock = (SNDSoundStruct **)s->dataLocation;
    int err, size, width; 
    int first, last, region_count = 0;
    char *ptr;
    
    if (!*iBlock) return SND_ERR_CANNOT_PLAY;
    
    first = 1;
    last = 0;
    err = snddriver_stream_control(stream_port,tag,SNDDRIVER_PAUSE_STREAM);
    if (err) return SND_ERR_KERNEL;
    while(s2 = *iBlock++) {
        SNDGetDataPointer(s2,&ptr,&size,&width);
        region_count++;
        if (!(*iBlock)) last = 1;
        err = snddriver_stream_start_writing(stream_port,
                                             (void *)ptr,
                                             size,
                                             tag,
                                             0,0,
                                             first,last,0,0,0,0,
                                             reply_port);
        if (err) return SND_ERR_KERNEL;
        first = 0;
    }
    err = snddriver_stream_control(stream_port,tag,SNDDRIVER_RESUME_STREAM);
    return err? SND_ERR_KERNEL : SND_ERR_NONE;
}

static int play_dsp_core(int tag, SNDSoundStruct *s,
                         port_t cmd_port, port_t reply_port)
{
    int err;
    int dmasize = vm_page_size / 2;     /* FIXME: get from header of sound */
    err = snddriver_dspcmd_req_condition(cmd_port,
                                         SNDDRIVER_ISR_HF2, 0,
                                         LO_PRI, reply_port);
    if (err) return SND_ERR_CANNOT_PLAY;
    err = snddriver_dspcmd_req_condition(cmd_port,
                                         SNDDRIVER_ISR_HF2, SNDDRIVER_ISR_HF2,
                                         LO_PRI, reply_port );
    if (err != KERN_SUCCESS) return err;
    err = snddriver_dsp_write(cmd_port,&dmasize,1,4,HI_PRI);
    return err? SND_ERR_CANNOT_PLAY : SND_ERR_NONE;
}

static s_kill_dsp_commands_thread;
typedef struct {
    port_t cmd_port;
    msg_header_t *message;
    int size;
} dsp_commands_struct;

static any_t dsp_commands_thread(any_t args)
{
    int err;
    int count = 0;
    msg_header_t *msg;
    dsp_commands_struct *info;
    
    info = (dsp_commands_struct *)args;
    msg = info->message;
    while (count < info->size) {
        msg->msg_remote_port = info->cmd_port;
        msg->msg_local_port = PORT_NULL;
        err = msg_send(msg, SEND_TIMEOUT, DSP_COMMANDS_SEND_TIMEOUT);
        while (err == SEND_TIMED_OUT) {
            if (s_kill_dsp_commands_thread)
                break;
            err = msg_send(msg, SEND_TIMEOUT, DSP_COMMANDS_SEND_TIMEOUT);
        }
#ifdef DEBUG
        if (err != KERN_SUCCESS)
            printf("dsp commands thread msg_send error %d\n", err);
#endif
        if (s_kill_dsp_commands_thread)
            break;
        count += msg->msg_size;
        msg = (msg_header_t *) ((char *)msg + msg->msg_size);
    }
    free(args);
    cthread_exit(0);
    return NULL;
}


static int play_dsp_commands(int tag, SNDSoundStruct *s,
                             port_t cmd_port, port_t reply_port)
{
    dsp_commands_struct *args;
    int err;
    
    args = (dsp_commands_struct *)malloc(sizeof(dsp_commands_struct));
    if (!args)
        return SND_ERR_KERNEL;
    
    args->cmd_port = cmd_port;
    args->message = (msg_header_t *) ((char *)s + s->dataLocation +
                                      sizeof(commandsSubHeader));
    args->size = s->dataSize - sizeof(commandsSubHeader);
    s_kill_dsp_commands_thread = FALSE;
    cthread_detach(cthread_fork(dsp_commands_thread, (any_t)args));
    err = snddriver_dspcmd_req_msg(cmd_port, reply_port);
    return err? SND_ERR_CANNOT_PLAY : SND_ERR_NONE;
}

#define BIT_FAITHFUL    1               /* method=1 for bit faithful */

static int record_samples(PerfReq *pr, port_t reply_port, int dmasize)
{
    int err;
    int tag = pr->tag;
    port_t stream_port = pr->perf_port, cmd_port;
    int sampleSkip;
    SNDCompressionSubheader *subheader = NULL;

#if 0
    /* Currently, compress.asm has a max encode length of 256 */
    static const short bestEncodeLength[] = {
        64,     /* shift 0 - currently not used */
        64,     /* shift 1 - currently not used */
        128,    /* shift 2 - currently not used */
        128,    /* shift 3 - currently not used */
        256,    /* shift 4 */
        256,    /* shift 5 */
        512,    /* shift 6 */
        512,    /* shift 7 */
        512     /* shift 8 */
        };
#endif

    pr->work_ptr = (void *)((char *)pr->sound + pr->sound->dataLocation);
    pr->work_count = pr->sound->dataSize;
    if (pr->convertMulaw_16)
        pr->work_count *= 2;
    pr->sound->dataSize = 0;
    if (!pr->work_count) return SND_ERR_CANNOT_RECORD;
    if (pr->mode == MODE_COMPRESSED_IN) {
        if (pr->work_count <= sizeof(SNDCompressionSubheader))
            return SND_ERR_CANNOT_RECORD;
        subheader = (SNDCompressionSubheader *)pr->work_ptr;
        subheader->originalSize = pr->work_count;
        if (subheader->method)
            subheader->method = BIT_FAITHFUL;
        if (subheader->numDropped < 4)
            subheader->numDropped = 4;
        else if (subheader->numDropped > 8)
            subheader->numDropped = 8;
        subheader->encodeLength = 256; /*bestEncodeLength[subheader->numDropped];*/
        
        /* Max encodeLength for 22K hack is 128 */
        if ((pr->sound->samplingRate == SND_RATE_LOW) &&
            subheader->encodeLength > 128)
            subheader->encodeLength = 128;
        
        subheader->reserved = 0;

        /* Write subheader if recording to a file */
        if (pr->recordFD >= 0)
            if (write(pr->recordFD, (char *)pr->work_ptr, 
                      sizeof(SNDCompressionSubheader))
                != sizeof(SNDCompressionSubheader))
                return SND_ERR_CANNOT_WRITE;

        pr->work_ptr = (void *) ((char *)pr->work_ptr 
                                 + sizeof(SNDCompressionSubheader));
        pr->work_block_ptr = (char *)pr->work_ptr;
        pr->work_count -= sizeof(SNDCompressionSubheader);
        pr->work_block_count = 0;
        pr->sound->dataSize = sizeof(SNDCompressionSubheader);
    }
    err = snddriver_stream_start_reading(stream_port,
                                         0,
                                         ((pr->access & SND_ACCESS_DSP) ||
                                          pr->convertMulaw_16 ?
                                          pr->work_count/2 : pr->work_count),
                                         tag,
                                         1,1,0,0,0,0,
                                         reply_port);
#ifdef DEBUG
    if (err)
        printf("record_samples received error %d\n", err);
#endif
    if (err) return SND_ERR_CANNOT_RECORD;
    
    /*
     * FIXME: parameters are written even in the optimized case (dsp already
     * running).  The DSP does not read them - they queue up in the driver.
     */
    if (pr->access & SND_ACCESS_DSP) {
        err = snddriver_get_dsp_cmd_port(pr->dev_port,pr->owner_port, 
                                         &cmd_port);
        if  (err != KERN_SUCCESS) return SND_ERR_CANNOT_RECORD;
        err = snddriver_dsp_write(cmd_port,&dmasize,1,4,HI_PRI);
        if (err != KERN_SUCCESS) return SND_ERR_CANNOT_RECORD;
        if (pr->mode == MODE_COMPRESSED_IN) {
            err = snddriver_dsp_write(cmd_port,&pr->sound->channelCount,1,4,HI_PRI);
            err = snddriver_dsp_write(cmd_port,&subheader->method,1,4,HI_PRI);
            err = snddriver_dsp_write(cmd_port,&subheader->numDropped,1,4,HI_PRI);
            err = snddriver_dsp_write(cmd_port,&subheader->encodeLength,1,4,HI_PRI);
            sampleSkip = (pr->sound->samplingRate == SND_RATE_HIGH ? 2 : 4);
            err = snddriver_dsp_write(cmd_port,&sampleSkip,1,4,HI_PRI);
            if (err != KERN_SUCCESS) return SND_ERR_CANNOT_RECORD;
        }
    }
    return err? SND_ERR_CANNOT_RECORD : SND_ERR_NONE;
}


/*
 * The performance queue. Contains both play and record requests. Several
 * entries may be active at one time.
 */

static volatile PerfReq *perf_q_head = 0, *perf_q_tail = 0, *free_list = 0;
static int request_count = 0, request_max = 0, next_id = 1;

static int enqueue_perf_request(int mode,
                                SNDSoundStruct *s,
                                int tag,
                                int priority,
                                int preempt,
                                SNDNotificationFun beginFun,
                                SNDNotificationFun endFun,
                                int dspOptions, int fd)
{
    int err, i = request_max;
    PerfReq *pr, *npr;
    port_t junk_port;
    
    if (free_list) {
        for (i=0; i<request_max;i++) {
            if (free_list[i].status == STATUS_FREE)
                break;
        }
    }
    if (i == request_max) {
        int j;
        PerfReq *old_q = (PerfReq *)free_list, *new_q;
        request_max = request_max? 2*request_max : 4;
        new_q = (PerfReq *)calloc(1,request_max*sizeof(PerfReq));
        if (!new_q) {
            return SND_ERR_KERNEL;
        }
        free_list = (PerfReq *)new_q;
        pr = (PerfReq *)perf_q_head;
        j = 0;
        while (pr) {
            npr = &new_q[j];
            *npr = *pr;
            if (pr->next)
                npr->next = &new_q[j+1];
            if (pr->prev)
                npr->prev = &new_q[j-1];
            pr = pr->next;
            j++;
        }
        perf_q_head = &new_q[0];
        perf_q_tail = i? &new_q[i-1] : NULL_REQUEST;
        if (old_q)
            free(old_q);
    }
    pr = (PerfReq *)(&free_list[i]);
    pr->dev_port = PORT_NULL;
    err = SNDAcquire(0,0,0,-1,0,0,&pr->dev_port,&junk_port);
    if (err) return err;
    pr->id = next_id++;
    pr->mode = mode;
    pr->access = calc_access(mode);
    pr->sound = s;
    
    /* Copy sound header in case sound is freed in endFun */
    pr->sndInfo = *s;
    
    pr->tag = tag;
    pr->priority = priority;
    pr->preempt = preempt;
    pr->beginFun = beginFun;
    pr->endFun = endFun;
    pr->startTime = 0;
    pr->duration = calc_duration(mode, s);
    pr->status = STATUS_WAITING;
    pr->err = SND_ERR_NONE;
    pr->dspOptions = dspOptions;
    pr->recordFD = fd;
    pr->convertMulaw_8 = pr->convertMulaw_16 = FALSE;
    pr->convert16_8 = pr->convertStereo_To_Mono = FALSE;
    pr->canPlayDirect = FALSE;
    if (!perf_q_tail) {
        pr->prev = pr->next = NULL_REQUEST;
        perf_q_head = perf_q_tail = pr;
    } else {
        pr->prev = (PerfReq *)perf_q_tail;
        pr->next = NULL_REQUEST;
        perf_q_tail->next = pr;
        perf_q_tail = pr;
    }
    request_count++;
    return SND_ERR_NONE;
}

static void dequeue_perf_request(PerfReq *pr)
{
    if (perf_q_head == pr) {
        perf_q_head = pr->next;
        if (perf_q_tail == pr) perf_q_tail = NULL_REQUEST;
        if (pr->next) pr->next->prev = NULL_REQUEST;
    } else {
        pr->prev->next = pr->next;
        if (perf_q_tail == pr)
            perf_q_tail = pr->prev;
        else
            pr->next->prev = pr->prev;
    }
    request_count--;
    pr->status = STATUS_FREE;
}

static PerfReq *findRequestForAccess(int access)
{
    PerfReq *pr = (PerfReq *)perf_q_head;
    while (pr)
        if (pr->access & access)
            return pr;
        else
            pr = pr->next;
    return NULL_REQUEST;
}

static PerfReq *findRequestForTag(int tag)
{
    PerfReq *pr = (PerfReq *)perf_q_head;
    while (pr)
        if (pr->tag == tag)
            return pr;
        else
            pr = pr->next;
    return NULL_REQUEST;
}

static PerfReq *reverseFindRequestForTag(int tag)
{
    PerfReq *pr = (PerfReq *)perf_q_tail;
    while (pr)
        if (pr->tag == tag)
            return pr;
        else
            pr = pr->prev;
    return NULL_REQUEST;
}

#if 0
/* NOT CURRENTLY USED */
static PerfReq *findNextRequest(PerfReq *cur_pr, int mode, int status)
{
    PerfReq *pr = cur_pr->next;
    while (pr) {
        if ((pr->status == status) && (pr->mode  == mode))
            return pr;
        else
            pr = pr->next;
    }
    return NULL_REQUEST;
}
#endif

/*
 * Performance configuration, initiation and message reply handling
 */

static port_t reply_port = 0;
static msg_header_t *reply_msg = 0;
static int pending_count = 0;

static void terminate_performance(PerfReq *cur);

static int configure_performance(PerfReq *pr)
{
    if (IS_PLAY_MODE(pr->mode))
        return play_configure(pr->mode,pr->sound,pr->dev_port,
                              pr->owner_port,&(pr->perf_port),
                              pr->dspOptions,
                              &pr->access, &(pr->canPlayDirect),
                              &(pr->convertMulaw_8),
                              &(pr->convertMulaw_16),
                              &(pr->convert16_8),
                              &(pr->convertStereo_To_Mono));
    else
        return record_configure(pr->mode,pr->sound,pr->dev_port,
                                pr->owner_port,&(pr->perf_port),
                                &(pr->convertMulaw_8),
                                &(pr->convertMulaw_16),
                                &(pr->convert16_8),
                                &(pr->convertStereo_To_Mono));
}

static int deconfigure_performance(PerfReq *pr)
{
    int err=SND_ERR_NONE, protocol = 0;
    switch (pr->mode) {
      case MODE_DSP_CORE_OUT:
#ifdef DEBUG
        printf("Fix this leak!\n");
#endif
        break;
      default:
        s_kill_black_box_thread = TRUE; /* if any */
        /* free the stream */
        mutex_lock(thread_lock);
        err = snddriver_stream_setup(pr->dev_port, pr->owner_port,
                                     0,
                                     0,
                                     0,
                                     0,
                                     0,
                                     &protocol,
                                     &pr->perf_port); 

        pr->perf_port = PORT_NULL; /* tell black-box threads stream is gone */
        mutex_unlock(thread_lock);
        break;
    }
    return err;
}

static int perform(PerfReq *pr, port_t reply_port, int required_access)
{
    int err;
    port_t cmd_port;
    int real_mode;

    if (pr->mode == MODE_INDIRECT_OUT) {
        real_mode = calc_indirect_mode(pr->sound);
        /*
         * The following modes may call play_black_box(),
         * which handles the indirect format.
         */
        if (!(real_mode == MODE_COMPRESSED_OUT ||
              real_mode == MODE_MULAW_8KHZ_OUT ||
              real_mode == MODE_MONO_OUT ||
              real_mode == MODE_FLOAT_OUT ||
              real_mode == MODE_DOUBLE_OUT ||
              real_mode == MODE_MULAW_OUT ||
              real_mode == MODE_LINEAR_8_OUT ||
              real_mode == MODE_MONO_BYTE_OUT))
            real_mode = MODE_INDIRECT_OUT;
    } else
        real_mode = pr->mode;

    /* Turn on the lowpass filter if playing an emphasized sound */
    if (IS_PLAY_MODE(real_mode) &&
        (real_mode != MODE_DSP_SSI_OUT) &&
        (real_mode != MODE_DSP_SSI_COMPRESSED_OUT) &&
        (pr->sound->dataFormat == SND_FORMAT_EMPHASIZED ||
         pr->sound->dataFormat == SND_FORMAT_COMPRESSED_EMPHASIZED)) {
        err = SNDGetFilter(&pr->prevFilter);
        if (err) return err;
        err = SNDSetFilter(1);
        if (err) return err;
    }
    
    switch (real_mode) {
    case MODE_COMPRESSED_OUT:
        if (!(required_access & SND_ACCESS_DSP)) {
            return 
              play_black_box_comp(pr->tag,pr->sound,
                             DECOMPRESSION_IN_BLOCK_SIZE, /* _compression.h */
                             DECOMPRESSION_OUT_BLOCK_SIZE,
                             ((((SNDCompressionSubheader *)
                                (((char *)pr->sound) 
                                 + pr->sound->dataLocation))->method 
                               == SND_CFORMAT_ATC) ? 
                              &_snd_atd_thread :
                              &_snd_old_decompression_thread),
                             0, 
                             pr->perf_port, reply_port);
        } else {
            if (pr->mode == MODE_INDIRECT_OUT)
                return play_indirect_samples(pr->tag,pr->sound,
                                             pr->perf_port,reply_port);
            else
                return play_samples(pr->tag,pr->sound,
                                    pr->perf_port,reply_port);
        }
    case MODE_MULAW_8KHZ_OUT:
        if (!(required_access & SND_ACCESS_DSP) && !pr->canPlayDirect) {
            if (pr->convertMulaw_8) {
		if (pr->convertStereo_To_Mono)
		    return play_black_box(pr->tag,pr->sound,
					(8*(vm_page_size *
					pr->sound->channelCount)),
					(8*(vm_page_size *
					pr->sound->channelCount)),
					&mulaw_stereo_to_byte_soundout_thread,
					0, pr->perf_port, reply_port);
		 else
		    return play_black_box(pr->tag,pr->sound,
					(8*(vm_page_size *
					pr->sound->channelCount)),
					(8*(vm_page_size *
					pr->sound->channelCount) * 2),
					&mulaw_to_byte_soundout_thread,
					0, pr->perf_port, reply_port);
            } else if (pr->convertMulaw_16) {
                return 
                    play_black_box(pr->tag,pr->sound,
                                   (8*(vm_page_size *
                                    pr->sound->channelCount) >> 1),
                                   (8*vm_page_size * pr->sound->channelCount),
                                   &mulaw_to_soundout_thread,
                                   0, pr->perf_port, reply_port);
            } else {
                _snd_init_upsamplecodec_thread();
                return 
                    play_black_box(pr->tag,pr->sound,
                             (vm_page_size >> 4), /* 8b mono 8kHz (1/4 sec) */
                             vm_page_size,        /* -> 16b 2ch 22kHz (11x) */
                             &_snd_upsamplecodec_thread,
                             0, pr->perf_port, reply_port);
            }
        } else {
            if (pr->mode == MODE_INDIRECT_OUT)
                return play_indirect_samples(pr->tag,pr->sound,
                                             pr->perf_port,reply_port);
            else
                return play_samples(pr->tag,pr->sound,
                                    pr->perf_port,reply_port);
        }
    case MODE_DIRECT_OUT:
        if (pr->convert16_8)    {
            if (pr->convertStereo_To_Mono)
                return play_black_box(pr->tag,pr->sound,
                                        (8*(vm_page_size *
                                        pr->sound->channelCount)),
                                        (8*(vm_page_size *
                                        pr->sound->channelCount) >> 1),
                                        &soundout_to_mono_linear8_thread,
                                        0, pr->perf_port, reply_port);
            else
                return play_black_box(pr->tag,pr->sound,
                                        (8*(vm_page_size *
                                        pr->sound->channelCount)),
                                        (8*(vm_page_size *
                                        pr->sound->channelCount)),
                                        &soundout_to_linear8_thread,
                                        0, pr->perf_port, reply_port);
        } else
            return play_samples(pr->tag,pr->sound,pr->perf_port,reply_port);
    case MODE_SQUELCH_OUT:
        return play_samples(pr->tag,pr->sound,pr->perf_port,reply_port);
    case MODE_MONO_OUT:
        if (pr->convert16_8)    {
            return play_black_box(pr->tag,pr->sound,
                                  (8*(vm_page_size *
                                   pr->sound->channelCount)),
                                  (8*(vm_page_size *
                                   pr->sound->channelCount)),
                                  &soundout_to_linear8_thread,
                                  0, pr->perf_port, reply_port);
        } else if (!(required_access & SND_ACCESS_DSP) && !pr->canPlayDirect) {
            return play_black_box(pr->tag,pr->sound,
                                  (vm_page_size >> 1),
                                  vm_page_size,
                                  &mono_to_stereo_thread,
                                  0, pr->perf_port, reply_port);
        } else {
            if (pr->mode == MODE_INDIRECT_OUT)
                return play_indirect_samples(pr->tag,pr->sound,
                                             pr->perf_port,reply_port);
            else
                return play_samples(pr->tag,pr->sound,
                                    pr->perf_port,reply_port);
        }
    case MODE_FLOAT_OUT:
        return play_black_box(pr->tag,pr->sound,
                              (vm_page_size * sizeof(float) 
                               * pr->sound->channelCount) / (sizeof(short)<<1),
                              vm_page_size,
                              &float_to_soundout_thread,
                              0, pr->perf_port, reply_port);
    case MODE_DOUBLE_OUT:
        return play_black_box(pr->tag,pr->sound,
                              (vm_page_size * sizeof(double)
                              * pr->sound->channelCount) / (sizeof(short)<<1),
                              vm_page_size,
                              &double_to_soundout_thread,
                              0, pr->perf_port, reply_port);
    case MODE_MULAW_OUT:
        if (pr->canPlayDirect) {
            if (pr->mode == MODE_INDIRECT_OUT)
                return play_indirect_samples(pr->tag,pr->sound,
                                             pr->perf_port,reply_port);
            else
                return play_samples(pr->tag,pr->sound,
                                    pr->perf_port,reply_port);
        } else if (pr->convertMulaw_8) {
	    if (pr->convertStereo_To_Mono)
		return play_black_box(pr->tag,pr->sound,
					(8*(vm_page_size *
					pr->sound->channelCount)),
					(8*(vm_page_size *
					pr->sound->channelCount)),
					&mulaw_stereo_to_byte_soundout_thread,
					0, pr->perf_port, reply_port);
	    else
		return play_black_box(pr->tag,pr->sound,
					(8*(vm_page_size *
					pr->sound->channelCount)),
					(8*(vm_page_size *
					pr->sound->channelCount) * 2),
					&mulaw_to_byte_soundout_thread,
					0, pr->perf_port, reply_port);
        } else {
            return play_black_box(pr->tag,pr->sound,
                                  (8*(vm_page_size *
                                   pr->sound->channelCount) >> 1),
                                  (8*vm_page_size * pr->sound->channelCount),
                                  &mulaw_to_soundout_thread,
                                  0, pr->perf_port, reply_port);
        }
    case MODE_LINEAR_8_OUT:
        if (pr->canPlayDirect)  {
            if (pr->mode == MODE_INDIRECT_OUT)
                return play_indirect_samples(pr->tag,pr->sound,
                                             pr->perf_port,reply_port);
            else if (pr->convertStereo_To_Mono)
                return play_black_box(pr->tag,pr->sound,
                                        (8*(vm_page_size *
                                        pr->sound->channelCount)),
                                        (8*(vm_page_size *
					pr->sound->channelCount)),
                                        &stereo_8_mono_8_thread,
                                        0, pr->perf_port, reply_port);
            else
                return play_samples(pr->tag,pr->sound,
                                    pr->perf_port,reply_port);
        } else {
            return play_black_box(pr->tag,pr->sound,
                                  (8*(vm_page_size *
                                   pr->sound->channelCount) >> 2),
                                  (8*vm_page_size),
                                  &linear8_to_soundout_thread,
                                  0, pr->perf_port, reply_port);
        }
    case MODE_MONO_BYTE_OUT:
        if (!(required_access & SND_ACCESS_DSP) && !pr->canPlayDirect) {
            return 
              play_black_box(pr->tag,pr->sound,
                             (8*(vm_page_size * pr->sound->channelCount) >> 1),
                             (8*(vm_page_size * pr->sound->channelCount)),
                             &linear8_to_soundout_thread,
                             0, pr->perf_port, reply_port);
        } else {
            if (pr->mode == MODE_INDIRECT_OUT)
                return play_indirect_samples(pr->tag,pr->sound,
                                             pr->perf_port,reply_port);
            else
                return play_samples(pr->tag,pr->sound,
                                    pr->perf_port,reply_port);
        }
    case MODE_CODEC_OUT:
        if (pr->convert16_8)    {
            return play_black_box(pr->tag,pr->sound,
                                  (8*(vm_page_size *
                                   pr->sound->channelCount)),
                                  (8*(vm_page_size *
                                   pr->sound->channelCount) * 2),
                                  &soundout_to_linear8_thread,
                                  0, pr->perf_port, reply_port);
        } else
            return play_samples(pr->tag,pr->sound,pr->perf_port,reply_port);
    case MODE_DSP_SSI_OUT:
    case MODE_DSP_SSI_COMPRESSED_OUT:
        return play_samples(pr->tag,pr->sound,pr->perf_port,reply_port);
    case MODE_RESAMPLE_OUT:
        if (pr->canPlayDirect)  {
            return play_samples(pr->tag,pr->sound, pr->perf_port,reply_port);
        } else if (pr->convert16_8)     {
            if (pr->convertStereo_To_Mono)
                return play_black_box(pr->tag,pr->sound,
                                        (8*(vm_page_size *
                                        pr->sound->channelCount)),
                                        (8*(vm_page_size *
                                        pr->sound->channelCount)/2),
                                        &soundout_to_mono_linear8_thread,
                                        0, pr->perf_port, reply_port);
            else 
                return play_black_box(pr->tag,pr->sound,
                                        (8*(vm_page_size *
                                        pr->sound->channelCount)),
                                        (8*(vm_page_size *
                                        pr->sound->channelCount)),
                                        &soundout_to_linear8_thread,
                                        0, pr->perf_port, reply_port);
        } else
            return play_resamples(pr->tag,pr->sound,pr->perf_port,reply_port,
                                  required_access);
    case MODE_INDIRECT_OUT:
        return play_indirect_samples(pr->tag,pr->sound,
                                     pr->perf_port,reply_port);
    case MODE_MULAW_8_IN:
    case MODE_LINEAR_8_IN:
    case MODE_LINEAR_16_IN:
    case MODE_DSP_DATA_IN:
        return record_samples(pr,reply_port,DSP_DMA_SIZE);
    case MODE_DSP_MONO22_IN:
        return record_samples(pr,reply_port,DSP_MONO22_DMA_SIZE);
    case MODE_COMPRESSED_IN:
        return record_samples(pr,reply_port,COMPRESS_DMA_SIZE);
    case MODE_DSP_CORE_OUT:
        err = play_dsp_core(pr->tag,pr->sound,pr->perf_port,reply_port);
        return err;
    case MODE_DSP_COMMANDS_OUT:
        err = snddriver_get_dsp_cmd_port(pr->dev_port, pr->owner_port,
                                         &cmd_port);
        if  (err != KERN_SUCCESS) return err;
        return play_dsp_commands(pr->tag,pr->sound,cmd_port,reply_port);
    default:
        break;
    }
    return SND_ERR_NONE;
}

static int flush_performance(PerfReq *pr)
{
    int err, mode = pr->mode;
    port_t cmd_port;
    
    if (mode == MODE_INDIRECT_OUT)
        mode = calc_indirect_mode(pr->sound);
    switch (mode) {
      case MODE_SQUELCH_OUT:
      case MODE_MULAW_8KHZ_OUT:
      case MODE_MONO_OUT:
      case MODE_MONO_BYTE_OUT:
      case MODE_CODEC_OUT:
      case MODE_COMPRESSED_OUT:
      case MODE_DSP_COMMANDS_OUT:
      case MODE_RESAMPLE_OUT:
        err = snddriver_get_dsp_cmd_port(pr->dev_port, pr->owner_port,
                                         &cmd_port);
        if  (err != KERN_SUCCESS) return err;
        err = snddriver_dsp_set_flags(cmd_port, SNDDRIVER_ICR_HF0, 
                                      SNDDRIVER_ICR_HF0, HI_PRI);
        if  (err != KERN_SUCCESS) return err;
        sleep_msec(250); /* wait for dma to drain */
        break;
      case MODE_DSP_CORE_OUT:
        err = snddriver_dsp_set_flags(pr->perf_port,
                                      SNDDRIVER_ICR_HF0, 
                                      SNDDRIVER_ICR_HF0, HI_PRI);
        if  (err != KERN_SUCCESS) return err;
        sleep_msec(250); /* wait for dma to drain */
      default:
        break;
    }
    
    /* Note: you cannot look at pr->sound here because it may have
       been SNDFree()ed by endFun */
    
    /* Return lowpass filter to previous state if finished playing an emphasized sound */
    if (IS_PLAY_MODE(pr->mode) &&
        (pr->mode != MODE_DSP_SSI_OUT) &&
        (pr->mode != MODE_DSP_SSI_COMPRESSED_OUT) &&
        (pr->sndInfo.dataFormat == SND_FORMAT_EMPHASIZED ||
         pr->sndInfo.dataFormat == SND_FORMAT_COMPRESSED_EMPHASIZED)) {
        err = SNDSetFilter(pr->prevFilter);
        if (err) return err;
    }
    
    return SND_ERR_NONE;
}

static void recover_pending_requests(PerfReq *pr, int mode)
{
    while (pr) {
        if (pr->status == STATUS_PENDING && pr->mode == mode)
            pr->status = STATUS_WAITING;
        pr = pr->next;
    }
}

static int access_in_use(PerfReq *pr, int required_access, port_t dev_port)
{
    while (pr) {
        if (pr->access & required_access && pr->dev_port == dev_port)
            return 1;
        pr = pr->prev;
    }
    return 0;
}

static int initiate_performance()
{
    PerfReq *pr = (PerfReq *)perf_q_head;
    int required_access, err;
    port_t required_port;
    
    while (1) {
        while (pr && pr->status != STATUS_WAITING)
            pr = pr->next;
        if (!pr) return SND_ERR_NONE; /* nothing to do */
        
        required_access = pr->access;
        required_port = pr->dev_port;
        if (access_in_use(pr->prev,required_access,required_port)) {
            PerfReq *prev = pr->prev;
            while (prev && ((required_access != prev->access) ||
                            (required_port != prev->dev_port)))
                prev = prev->prev;
            if (!prev || !modeOptimizable(pr->mode, prev->mode, 
                                          pr->sound, prev->sound) ||
                (pending_count*3 > REPLY_BACKLOG))
                return SND_ERR_NONE;
            pr->perf_port = prev->perf_port;
            pr->owner_port = prev->owner_port;
            pr->convertMulaw_8 = prev->convertMulaw_8;
            pr->convertMulaw_16 = prev->convertMulaw_16;
            pr->convert16_8 = prev->convert16_8;
            pr->convertStereo_To_Mono = prev->convertStereo_To_Mono;
            pr->canPlayDirect = prev->canPlayDirect;
            pr->status = STATUS_PENDING;
            pr->startTime = msec_timestamp();
            err = perform(pr, reply_port,required_access);
            if (err) {
                pr->err = err;
                pr->status = STATUS_ACTIVE;
#ifdef DEBUG
                printf("err %d in initiate_performance\n", err);
#endif
                return err;
            } else
                pending_count++;
        } else {
            err = SNDAcquire(required_access, pr->priority, pr->preempt,
                             -1, (SNDNegotiationFun)0, (void *)0,
                             &pr->dev_port, &pr->owner_port);
            if (err != SND_ERR_NONE) { /* Sound or DSP not available */
                SNDSoundStruct *s = pr->sound;
                SNDCompressionSubheader *subheader;

                if (! (required_access & SND_ACCESS_DSP) )
                  return err;   /* sound-out not available ... no hope */

                /* 
                 * DSP not available... see if we can run without it 
                 */

                switch (pr->mode) {
                case MODE_COMPRESSED_OUT:
                    if (s->dataFormat != SND_FORMAT_COMPRESSED)
                      return err;
                    subheader = (SNDCompressionSubheader *)data_pointer(s);
                    break;
                case MODE_MONO_OUT:
                case MODE_MONO_BYTE_OUT:
                case MODE_LINEAR_8_OUT:
                case MODE_MULAW_8KHZ_OUT:
                case MODE_RESAMPLE_OUT:
                    break;
                default:
                    return err; /* FIXME: make more play modes run w/o DSP */
                }

                required_access &= ~SND_ACCESS_DSP;
                pr->access = required_access;
                err = SNDAcquire(required_access, pr->priority, pr->preempt,
                                 -1, (SNDNegotiationFun)0, (void *)0,
                                 &pr->dev_port, &pr->owner_port);
                if (err != SND_ERR_NONE) 
                  return err;   /* sound-out not available */
            }
            pr->status = STATUS_PENDING;
            pr->startTime = msec_timestamp();
            err = configure_performance(pr);
            if (err != KERN_SUCCESS) {
                pr->err = err = SND_ERR_CANNOT_CONFIGURE;
                pr->status = STATUS_ACTIVE;
                return err;
            } else {
                err = perform(pr, reply_port, pr->access);
                if (err) {
                    deconfigure_performance(pr);
                    pr->err = err;
                    pr->status = STATUS_ACTIVE;
                    return err;
                } else
                    pending_count++;
            }
        }
    }
}

static int can_preempt(int mode, int priority)
{
    PerfReq *pr = (PerfReq *)perf_q_head;
    int required_access = calc_access(mode);
    int pri = priority + 1;
    while (pr) {
        if ((pr->access & required_access) && (pr->priority > pri))
            return 0;
        pr = pr->next;
    }
    return 1;
}

static void preempt_requests(int mode)
{
    SNDSoundStruct *s;
    SNDNotificationFun fun;
    PerfReq *pr = (PerfReq *)perf_q_head;
    int err, tag, required_access = calc_access(mode);
    while (pr) {
        if (pr->access & required_access) {
            if (pr->status == STATUS_ACTIVE) {
                if (pr->duration > MIN_PREEMPT_DUR) {
                    recover_pending_requests(pr->next,pr->mode);
                    pr->err = SND_ERR_ABORTED;
                    err = deconfigure_performance(pr);
                    err = SNDRelease(pr->access, pr->dev_port, pr->owner_port);
                    s_active_dsp_core[0] = '\0';
                    s_active_dsp_cmd_port = PORT_NULL;
                    pending_count = 0;
                    fun = pr->endFun;
                    s = pr->sound;
                    tag = pr->tag;
                    dequeue_perf_request(pr);
                    mutex_unlock(q_lock);
                    if (fun)
                        (*fun)(s,tag,SND_ERR_ABORTED);
                    mutex_lock(q_lock);
                }
            } else {
                fun = pr->endFun;
                s = pr->sound;
                tag = pr->tag;
                if (pr->status == STATUS_PENDING) {
                    pending_count--;
                    if (!pending_count)
                        err = deconfigure_performance(pr);
                }
                dequeue_perf_request(pr);
                mutex_unlock(q_lock);
                if (fun)
                    (*fun)(s,tag,SND_ERR_ABORTED);
                mutex_lock(q_lock);
            }
        }
        pr = pr->next;
    }
}    

static int doNotStart = 0;

static int start_performance(int mode, SNDSoundStruct *s, int tag,
                             int priority, int preempt, 
                             SNDNotificationFun beginFun,
                             SNDNotificationFun endFun,
                             int dspOptions, int fd)
{
    int err;
    mutex_lock(q_lock);
    if (findRequestForTag(tag)) {
        mutex_unlock(q_lock);
        return SND_ERR_BAD_TAG;
    }
    if (preempt) {
        if (can_preempt(mode,priority))
            preempt_requests(mode);
        else {
            mutex_unlock(q_lock);
            return SND_ERR_CANNOT_PLAY;
        }
    }
    err = enqueue_perf_request(mode,s,tag,priority,preempt,beginFun,endFun,dspOptions,fd);
    if (!err && !doNotStart) {
        err = initiate_performance();
        if (err) {
            PerfReq *pr = findRequestForTag(tag);
            if (pr) dequeue_perf_request(pr);
        }
    }
    mutex_unlock(q_lock);
    return err;
}

static void terminate_performance(PerfReq *cur)
{
    PerfReq *next = NULL_REQUEST;
    int err = SND_ERR_NONE;
    
    if (cur->status == STATUS_WAITING)
        dequeue_perf_request(cur);
    else {
        if (!cur->err) {
            next = cur->next;
            while (next) {
                if (next->dev_port == cur->dev_port &&
                    next->mode == cur->mode &&
                    (next->status == STATUS_PENDING ||
                     next->status == STATUS_WAITING) )
                    break;
                else
                    next = next->next;
            }
        }
        
        /* Note: you cannot look at cur->sound here because it may have
           been SNDFree()ed by endFun */
        
        /* Also, there must be at least 2 pending requests to optimize */
        
        if (!next || (pending_count == 1) ||
            !modeOptimizable(next->mode, cur->mode, next->sound, &cur->sndInfo)) {
            if (!cur->err)
                flush_performance(cur);
            err = deconfigure_performance(cur);
            err = SNDRelease(cur->access, cur->dev_port, cur->owner_port);
            s_active_dsp_core[0] = '\0';
            s_active_dsp_cmd_port = PORT_NULL;
            pending_count = 1;
        }
        dequeue_perf_request(cur);
        pending_count--;
        if (perf_q_head)
            err = initiate_performance();
    }
#ifdef DEBUG
    if (err)
        printf("Error %d in terminate_performance\n", err);
#endif
}

static void stop_performance(int tag, int err)
{
    PerfReq *pr;
    SNDNotificationFun fun;
    SNDSoundStruct *s;
    
    mutex_lock(q_lock);
    pr = findRequestForTag(tag);
    if (!pr) {
        mutex_unlock(q_lock);
        return;
    }
    switch (pr->mode) {
      case MODE_MULAW_8_IN:
      case MODE_LINEAR_8_IN:
      case MODE_LINEAR_16_IN:
      case MODE_DSP_DATA_IN:
      case MODE_DSP_MONO22_IN:
      case MODE_COMPRESSED_IN:
        pr->status = STATUS_ABORTED;
        pr->err = SND_ERR_ABORTED;
        if (err != SND_ERR_TIMEOUT) {
            while (pr && pr->status != STATUS_FREE) {
                condition_wait(q_changed,q_lock);
                pr = findRequestForTag(tag);
            }
            mutex_unlock(q_lock);
        } else {
            recover_pending_requests(pr->next,pr->mode);
            terminate_performance(pr);
            fun = pr->endFun;
            s = pr->sound;
            mutex_unlock(q_lock);
            if (fun)
                (*fun)(s,tag,err);
            condition_signal(q_changed);
        }
        break;
      case MODE_DSP_COMMANDS_OUT:
        s_kill_dsp_commands_thread = TRUE;
        /* fall through */
      default:
        pr->err = err;
        recover_pending_requests(pr->next,pr->mode);
        /*
         * Abort stream so soundout stops fast.
         */
        snddriver_stream_control(pr->perf_port,pr->tag,
                                 SNDDRIVER_ABORT_STREAM);
        /*
         * Force soundout to stop.  This is necessary if access has
         * been reserved because SNDRelease() will not deallocate owner port
         * (which is the usual way of stopping soundout).
         */
        if (pr->access & SND_ACCESS_OUT)
            SNDReset(pr->access, pr->dev_port, pr->owner_port);
        terminate_performance(pr);
        fun = pr->endFun;
        s = pr->sound;
        mutex_unlock(q_lock);
        if (fun)
            (*fun)(s,tag,err);
        condition_signal(q_changed);
        break;
    }
}

static void performance_ended(void *junk, int tag);

static void check_performance()
    /* take action on one thing maximum per call */
{
    static int start_delay = 10;
    SNDNotificationFun fun;
    SNDSoundStruct *s;
    int err, now = msec_timestamp(), tag=0;
    int reply_timeout;
    PerfReq *pr;
    int nsamples = 0;

    mutex_lock(q_lock);
    pr = (PerfReq *)perf_q_head;
    while (pr) {
        if (pr->status == STATUS_ACTIVE) {
            start_delay = 10;
            if (pr->mode == MODE_DSP_COMMANDS_OUT)
                reply_timeout = DSP_COMMANDS_REPLY_TIMEOUT;
            else if (pr->mode == MODE_COMPRESSED_IN)
                reply_timeout = COMPRESSED_IN_REPLY_TIMEOUT;
            else
                reply_timeout = REPLY_TIMEOUT;
            if ((now - pr->startTime - reply_timeout) > pr->duration) {
                tag = pr->tag;
#ifdef DEBUG
                printf("Active request timed out : %d\n",tag);
                printf(" ...duration = %d, start time = %d, now = %d\n",
                       pr->duration, pr->startTime, now );
                /* printf("Active request termination disabled\n");
                return; */
#endif
                /* NOTE: this call actually returns the number of bytes
                   processed, not the number of samples */
                err = snddriver_stream_nsamples(pr->perf_port, &nsamples);
#ifdef DEBUG    
                if (err)
                    printf("snddriver_stream_nsamples returned error %d\n", err);
#endif
                /* This works around dsp/driver endgame problems */
                if (!err && (nsamples >= pr->sound->dataSize)) {
#ifdef DEBUG
                    printf("performance ended normally since "
                           "nsamples >= dataSize\n");
#endif
                    mutex_unlock(q_lock);
                    performance_ended(NULL, tag);
                    return;
                }
                pr->err = SND_ERR_TIMEOUT;
                pr->status = STATUS_ABORTED;
                mutex_unlock(q_lock);
                stop_performance(tag, SND_ERR_TIMEOUT);
                return;
            } else if (IS_RECORD_MODE(pr->mode)) {
                err = snddriver_stream_control(pr->perf_port,pr->tag,
                                               SNDDRIVER_AWAIT_STREAM);
            }
        } else if (pr->status == STATUS_PENDING && pr == perf_q_head) {
            if (!start_delay--) {
                start_delay = 10;
                tag = pr->tag;
#ifdef DEBUG
                printf("Pending request timed out : %d\n",tag);
                /*printf("Pending request termination disabled\n");
                return;*/
#endif
                pr->err = SND_ERR_TIMEOUT;
                mutex_unlock(q_lock);
                stop_performance(tag, SND_ERR_TIMEOUT);
                return;
            }
        } else if (pr->status == STATUS_ABORTED) {
            start_delay = 10;
            fun = pr->endFun;
            err = pr->err;
            s = pr->sound;
#ifdef DEBUG
            printf("Aborted request removed : %d\n",tag);
#endif
            recover_pending_requests(pr->next,pr->mode);
            terminate_performance(pr);
            mutex_unlock(q_lock);
            if (fun)
                (*fun)(s,tag,err);
            condition_signal(q_changed);
            return;
        }
        pr = pr->next;
    }
    mutex_unlock(q_lock);
}


static void performance_started(void *junk, int tag)
{
    PerfReq *pr;
    int delay_of_first_buffer;
    int err, now;
    SNDNotificationFun fun;
    SNDSoundStruct *s;
    int dmasize = vm_page_size / 2;
    
    mutex_lock(q_lock);
    pr = findRequestForTag(tag);
    if (!pr || pr->status == STATUS_ABORTED) {
        mutex_unlock(q_lock);
        return;
    }
    delay_of_first_buffer = calc_ms_from_sample_count(pr->sound,dmasize);
    pr->status = STATUS_ACTIVE;
    now = msec_timestamp();
    /*
     * This was used at one time:
     * pr->startTime = now - delay_of_first_buffer;
     */
    pr->startTime = now;
#ifdef DEBUG
    /*printf("perf %d started at %d\n",tag,now);*/
#endif
    if (IS_RECORD_MODE(pr->mode)) {
        err = snddriver_stream_control(pr->perf_port,pr->tag,
                                       SNDDRIVER_AWAIT_STREAM);
    }
    fun = pr->beginFun;
    err = pr->err;
    s = pr->sound;
    mutex_unlock(q_lock);
    if (fun)
        (*fun)(s,tag,err);
}

static void performance_ended(void *junk, int tag)
{
    PerfReq *pr;
    int err;
    SNDNotificationFun fun;
    SNDSoundStruct *s;
    
    mutex_lock(q_lock);
    pr = findRequestForTag(tag);
    if (!pr) {
        mutex_unlock(q_lock);
        return;
    }

    if ( pr->bbargs && pr->bbargs->outputBlockCount )
    {
        mutex_lock( &pr->bbargs->outputBlockSem );
        pr->bbargs->outputBlockCount -= BB_OUTPUT_NOTIFY_COUNT;
        condition_signal( &pr->bbargs->outputBlockCond );
        mutex_unlock( &pr->bbargs->outputBlockSem );
        mutex_unlock(q_lock);
        return;
    }
#ifdef DEBUG
    /*printf("perf %d ended at %d (started at %d)\n",tag,msec_timestamp(),pr->startTime);*/
#endif
    if (pr->recordFD >= 0) {
        lseek(pr->recordFD, 0L, 0);
        pr->err = SNDWriteHeader(pr->recordFD, pr->sound);
    }
    fun = pr->endFun;
    err = pr->err;
    s = pr->sound;
    doNotStart=1;
#if 1
    mutex_unlock(q_lock);
    if (fun)
        (*fun)(s,tag,err);      /* FIXME: Move this after terminate_perf? */
    mutex_lock(q_lock);
    pr = findRequestForTag(tag);
    if (pr)
      terminate_performance(pr);
#else                           /* App's Sound delegate never gets the didPlay: message */
#warning Experimental change to move endFun after terminate_performance
    pr = findRequestForTag(tag);
    terminate_performance(pr);
    mutex_unlock(q_lock);
    if (fun)
        (*fun)(s,tag,err);      /* FIXME: Move this after terminate_perf? */
    mutex_lock(q_lock);
#endif
    doNotStart=0;
    mutex_unlock(q_lock);
    condition_signal(q_changed);
}

static void performance_read_data(void *junk, int tag, void *p, int i)
{
    char *ptr;
    int remaining_bytes, size, err, done = 0;
    PerfReq *pr;
    SNDCompressionSubheader *subheader = NULL;
    int count, code, numBits;
    int numSamples = 0;
#ifdef DEBUG
    static int curTag = 0;
#endif
    
    mutex_lock(q_lock);
    pr = findRequestForTag(tag);
    if (pr && pr->status) {
        switch (pr->mode) {
          case MODE_COMPRESSED_IN:
            subheader = (SNDCompressionSubheader *)((char *)pr->sound
                                                 + pr->sound->dataLocation);
            numSamples = subheader->originalSize/2;
            /* Fall through */
          case MODE_MULAW_8_IN:
          case MODE_LINEAR_8_IN:
          case MODE_LINEAR_16_IN:
          case MODE_DSP_DATA_IN:
          case MODE_DSP_MONO22_IN:
#ifdef DEBUG
            if (curTag && (curTag != tag)) {
                printf("Lost data for tag %d\n", curTag);
                /*pause();*/
            }
            curTag = tag;
#endif
            ptr = (char *)pr->work_ptr;
            remaining_bytes = pr->work_count;
            size = (i > remaining_bytes)? remaining_bytes : i;

            if (pr->convertMulaw_16) {
                int j, count = size/2;
                short *src = (short *)p, tmp;
                char *dest = ptr;
                for (j = 0; j < count; j++) {
                    tmp = NXSwapBigShortToHost(*src++);
                    *dest++ = SNDMulaw(tmp);
                }
                if (pr->recordFD >= 0) {
                    if (write(pr->recordFD, ptr, count) != count)
                        pr->err = SND_ERR_CANNOT_WRITE;
                }
                ptr += count;
                remaining_bytes -= size;
                pr->sound->dataSize += count;
            } else if (pr->convertMulaw_8) {
                _SNDLinear8ToMulaw(ptr, p, size);
                if (pr->recordFD >= 0) {
                    if (write(pr->recordFD, ptr, size) != size)
                        pr->err = SND_ERR_CANNOT_WRITE;
                }
                remaining_bytes -= size;
                pr->sound->dataSize += size;
                ptr += size;
            } else {
                if (pr->recordFD >= 0) {
                    if (write(pr->recordFD, (char *)p, size) != size)
                        pr->err = SND_ERR_CANNOT_WRITE;
                } else {
                    memmove(ptr,p,size);
                    ptr += size;
                }
                remaining_bytes -= size;
                pr->sound->dataSize += size;
            }
            pr->work_ptr = (void *)ptr;
            pr->work_count = remaining_bytes;
            done = (pr->status == STATUS_ABORTED || !remaining_bytes);
#ifdef ppc  
	    if ( pr->status == STATUS_ABORTED )
	      {
		snddriver_stream_control(pr->perf_port,pr->tag,
					 SNDDRIVER_ABORT_STREAM);
	      }
#endif	    

            /* FIXME: for compressed to work with recording to file, you have
               keep state about where you are rather that using pointers.
               This would work fine for the non-compressed case too. */

            if (pr->mode == MODE_COMPRESSED_IN) {
                /*
                 * Note: dataSize gets truncated leaving a hole of unused
                 * but allocated memory in the sound.  This hole of course goes
                 * away if you write the compressed sound to a file.
                 */
                while (ptr > pr->work_block_ptr) {
                    if (((pr->work_block_count-1) * subheader->encodeLength) >=
                        numSamples) {
                        pr->sound->dataSize -= ptr - pr->work_block_ptr;
                        if (pr->sound->dataSize > subheader->originalSize) {
                            pr->sound->dataSize = subheader->originalSize;
#ifdef DEBUG
                            printf("Sound could not be compressed\n");
#endif
                        }
                        done = TRUE;
                        break;
                    }
                    code = *pr->work_block_ptr++;
                    numBits = *pr->work_block_ptr++;
                    if ((unsigned)code >= NUM_ENCODES || (unsigned)numBits > 16) {
#ifdef DEBUG
                        printf("BOGUS!! block=%d, code=%d, numBits=%d\n",
                               pr->work_block_count, code, numBits);
#endif
                        done = TRUE;
                        break;
                    }
                    
                    count = bytesInBlock(code, numBits, subheader->encodeLength);
                    if (count & 1)
                        count++;        /* pad to short */
                    pr->work_block_ptr += count;
                    pr->work_block_count++;
                }
            }
            err = snddriver_stream_control(pr->perf_port,pr->tag,
                                           SNDDRIVER_AWAIT_STREAM);
            break;
          default:
            break;
        }    
    }
    err = vm_deallocate(task_self(),(pointer_t)p,i);
    mutex_unlock(q_lock);
    if (done) {
#ifdef DEBUG
        curTag = 0;
#endif
        performance_ended(junk,tag);
    }
}

static void performance_condition_true(void *junk, u_int mask, u_int bits,
                                       u_int value)
{
    PerfReq *pr;
    int tag;
    
    mutex_lock(q_lock);
    pr = findRequestForAccess(SND_ACCESS_DSP);
    if (pr) {
        tag = pr->tag;
        switch (pr->status) {
          case STATUS_ACTIVE:
            mutex_unlock(q_lock);
            performance_ended(junk,tag);
            return;
          case STATUS_PENDING:
            mutex_unlock(q_lock);
            performance_started(junk,tag);
            return;
        }
    }
    mutex_unlock(q_lock);
}

#define OPCODE_MASK     0xf0000
#define OPCODE_IDLE     0xf0000
#define OPCODE_PEEK0    0xd0000

static void performance_dsp_message(void *junk, int *data, int size)
{
    PerfReq *pr;
    int tag, i, opcode, err;
    int gotIdle = FALSE, gotPeek0 = FALSE;
    port_t cmd_port;
    
    mutex_lock(q_lock);
    pr = findRequestForAccess(SND_ACCESS_DSP);
    if (pr) {
        tag = pr->tag;
        for (i = 0; i < size; i++) {
            opcode = data[i] & OPCODE_MASK;
            if (opcode == OPCODE_IDLE)
                gotIdle = TRUE;
            else if (opcode == OPCODE_PEEK0)
                gotPeek0 = TRUE;
        }
        err = snddriver_get_dsp_cmd_port(pr->dev_port, pr->owner_port,
                                         &cmd_port);
#ifdef DEBUG
        if (err) printf("snddriver_get_dsp_cmd_port returned %d\n", err);
#endif
        switch (pr->status) {
          case STATUS_ACTIVE:
            mutex_unlock(q_lock);
            if (gotPeek0)
                performance_ended(junk,tag);
            else {
                err = snddriver_dspcmd_req_msg(cmd_port, reply_port);
#ifdef DEBUG
                if (err) printf("snddriver_dspcmd_req_msg returned %d\n", err);
#endif
            }
            return;
          case STATUS_PENDING:
            mutex_unlock(q_lock);
            if (gotIdle)
                performance_started(junk,tag);
            err = snddriver_dspcmd_req_msg(cmd_port, reply_port);
#ifdef DEBUG
            if (err) printf("snddriver_dspcmd_req_msg returned %d\n", err);
#endif
            return;
        }
    }
    mutex_unlock(q_lock);
}

static any_t perform_reply_thread(any_t args)
{
    snddriver_handlers_t handlers = {
        (void *)0, 0, 
        performance_started,
        performance_ended,
        0, 0, 0, 0, 
        performance_read_data,
        performance_condition_true,
        performance_dsp_message,
        0 };
    int err;
    while (1) {
        reply_msg->msg_size = MSG_SIZE_MAX;
        reply_msg->msg_local_port = reply_port;
        err = msg_receive(reply_msg, RCV_TIMEOUT, REPLY_TIMEOUT);
        if (err == KERN_SUCCESS) {
            err = snddriver_reply_handler(reply_msg,&handlers);
        } else if (err == RCV_TIMED_OUT) {
            check_performance();
        } else {
#ifdef DEBUG
            printf("perform_reply_thread msg_receive error : %d\n",err);
#endif
        }
    }
    return NULL;
}

#ifndef KERNEL_PRIVATE
#define KERNEL_PRIVATE /* required */
#endif
// #import <bsd/sys/table.h>
// extern table();

static void set_arch_cpu_type(void)
{
    host_t              host = host_self();
    kern_return_t       err;
    unsigned            size;
    struct host_basic_info hi;
    char                *family, *name;
    unsigned char       cpuClk;
    size = sizeof(struct host_basic_info) / sizeof(int);
    err = host_info(host, HOST_BASIC_INFO, (void *)&hi, &size);
    if (err != KERN_SUCCESS) {
        bzero(&hi, sizeof(struct host_basic_info));
        family = ""; name = "";
#ifdef DEBUG
        printf("host_info returns error code %d\n", err);
#endif
    }
    slot_name(hi.cpu_type, hi.cpu_subtype, &family, &name);
#ifndef TBL_NeXT_CPU_REV2
    /* TBL_NeXT_CPU_REV2 is not defined as of Thunder2K */
    cpuClk = 33;
#else
//    err = table(TBL_NeXT_CPU_REV2, 0, (char *)&cpuClk, 1, sizeof(cpuClk));
#endif
//  printf("%d MHz %s, family %s\n", cpuClk, name, family); 
    arch_cpu_type = hi.cpu_type; /* Family name, cf. <mach/machine.h> */
    arch_cpu_subtype = hi.cpu_subtype; /* Specific processor name */
//    arch_cpu_speed = cpuClk;    /* MHz */
    arch_dsp_exists = (arch_cpu_type == CPU_TYPE_MC680x0);
}

static int initialize()
{
    int err;
    static int initialized=0;
    if (initialized) return 0;
    initialized = 1;
    thread_lock = mutex_alloc();
    mutex_init(thread_lock);

    thread_lock_new = mutex_alloc();	// TEST
    mutex_init(thread_lock_new);	// TEST

    q_lock = mutex_alloc();
    mutex_init(q_lock);
    q_changed = condition_alloc();
    condition_init(q_changed);
    err = port_allocate(task_self(),&reply_port);
    if (err != KERN_SUCCESS)  return SND_ERR_KERNEL;
    err = port_set_backlog(task_self(),reply_port,REPLY_BACKLOG);
    if (err != KERN_SUCCESS)  return SND_ERR_KERNEL;
    reply_msg = (msg_header_t *)malloc(MSG_SIZE_MAX);
    if (!reply_msg)  return SND_ERR_KERNEL;
    cthread_fork(perform_reply_thread, (any_t)NULL);
    set_arch_cpu_type();
    return SND_ERR_NONE;
}

int getRecordingRate( int *rate )
{
    int 	srate, encoding, chans, low_rate, high_rate;
    int 	err;
    port_t	dev_port=PORT_NULL, owner_port=PORT_NULL;

    do
    {
        if ( err = initialize() )
            continue;

        if ( err = SNDAcquire(0,0,0,-1,0,0,&dev_port,&owner_port) ) 
            continue;

        if ( err = snddriver_get_sndin_formats(dev_port, &srate, &low_rate,
                                          &high_rate, &encoding, &chans) ) 
           continue;

       *rate = (low_rate > 22050) ? 44100 : 22050;
    }
    while ( 0 );

    return err;
}


/*
 * Exported routines
 */

int SNDStartPlaying(SNDSoundStruct *s, int tag, int priority, int preempt,
                    SNDNotificationFun beginFun, SNDNotificationFun endFun)
{
    int err, mode;
    
    if (err = initialize())
        return err;
    mode = calc_play_mode(s);
    if (!mode)
        return SND_ERR_CANNOT_PLAY;
    err = start_performance(mode,s,tag,priority,preempt,beginFun,endFun,0,-1);
    return err;
}

int SNDStartPlayingDSP(SNDSoundStruct *s, int tag, int priority, int preempt,
                       SNDNotificationFun beginFun, SNDNotificationFun endFun,
                       int playOptions)
{
    int err, mode;
    
    if (err = initialize())
        return err;
    mode = calc_dsp_play_mode(s);
    if (!mode)
        return SND_ERR_CANNOT_PLAY;
    err = start_performance(mode,s,tag,priority,preempt,beginFun,endFun,playOptions,-1);
    return err;
}

int SNDStop(int tag)
{
    int err = initialize();
    
    if (err) return err;
    if (!tag)
        return SND_ERR_BAD_TAG; /* FIXME: zero tag should stop everything? */
    stop_performance(tag,SND_ERR_ABORTED);
    return SND_ERR_NONE;
}

int SNDWait(int tag)
{
    int err = initialize();
    
    if (err) return err;
    mutex_lock(q_lock);
    if (tag) {
        PerfReq *pr = reverseFindRequestForTag(tag);
        if (pr)
            while (pr && pr->status != STATUS_FREE) {
                condition_wait(q_changed,q_lock);
                pr = reverseFindRequestForTag(tag);
            }
    } else {
        if (perf_q_head && request_count)
            while (perf_q_head)
                condition_wait(q_changed,q_lock);
    }
    mutex_unlock(q_lock);
    return err;
}

int SNDStartRecording(SNDSoundStruct *s, int tag, int priority, int preempt,
                      SNDNotificationFun beginFun, SNDNotificationFun endFun)
{
    int err, mode;
    
    if (err = initialize())
        return err;
    mode = calc_record_mode(s);
    if (!mode)
        return SND_ERR_CANNOT_RECORD;
    err = start_performance(mode,s,tag,priority,preempt,beginFun,endFun,0,-1);
    return err;
}

int SNDStartRecordingFile(char *fileName, SNDSoundStruct *s,
                          int tag, int priority, int preempt,
                          SNDNotificationFun beginFun, SNDNotificationFun endFun)
{
    int err, mode, fd;
    
    if (err = initialize())
        return err;

    /* NOTE: When recording from the dsp the soundfile will retain the
       SND_FORMAT_DSP_DATA_16 format.  The format must be changed to
       SND_FORMAT_LINEAR_16 to be played back. */

    /* NOTE: s->dataSize must specify the number of bytes to record, but the
       sound does not have to have this memory allocated.  If recording compressed,
       enough data must be allocated for the compression subheader.  In fact, you
       should call SNDAlloc() to get the default compression parameters.
       (This is bogus since we don't export the subheader size.) */

    /* Actually, you should probably do the normal SNAlloc() with the dataSize you
       want and let vm get allocated - there is almost no overhead if you don't
       write to it.  You can then SNDFree() the sound after recording is done. */

    mode = calc_record_mode(s);
    if (!mode)
        return SND_ERR_CANNOT_RECORD;
    if ((fd = creat(fileName, 0644)) == -1)
        return SND_ERR_BAD_FILENAME;
    if (err = SNDWriteHeader(fd, s))
        return err;
    err = start_performance(mode,s,tag,priority,preempt,beginFun,endFun,0,fd);
    return err;
}

int SNDSamplesProcessed(int tag)
{
    int samples = -1;
    int err = initialize();
    
    if (err) return err;
    mutex_lock(q_lock);
    if (tag) {
        PerfReq *pr = findRequestForTag(tag);
        if (pr) {
            if (IS_RECORD_MODE(pr->mode))
                samples = calc_record_nsamples(pr);
            else
                samples = calc_play_nsamples(pr);
        }
    }
    mutex_unlock(q_lock);
    return samples;
}

int SNDModifyPriority(int tag, int new_priority)
{
    int err = initialize();
    
    if (err) return err;
    err = SND_ERR_BAD_TAG;
    mutex_lock(q_lock);
    if (tag) {
        PerfReq *pr = findRequestForTag(tag);
        if (pr) {
            pr->priority = new_priority;
            err = SND_ERR_NONE;
        }
    }
    mutex_unlock(q_lock);
    return err;
}

int SNDSetVolume(int left, int right)
{
    port_t dev_port=PORT_NULL, owner_port;
    int err;
    if (err = initialize())
        return err;
    err = SNDAcquire(0,0,0,-1,0,0,&dev_port,&owner_port);
    if (err) return err;
    err = snddriver_set_volume(dev_port,left,right);
    if (err)
        return (err == RCV_TIMED_OUT || err == SEND_TIMED_OUT)? 
            SND_ERR_TIMEOUT : SND_ERR_KERNEL;
    else
        return SND_ERR_NONE;
}

int SNDGetVolume(int *left, int *right)
{
    port_t dev_port=PORT_NULL, owner_port;
    int err;
    if (err = initialize())
        return err;
    err = SNDAcquire(0,0,0,-1,0,0,&dev_port,&owner_port);
    if (err) return err;
    err = snddriver_get_volume(dev_port,left,right);
    if (err)
        return (err == RCV_TIMED_OUT || err == SEND_TIMED_OUT)? 
            SND_ERR_TIMEOUT : SND_ERR_KERNEL;
    else
        return SND_ERR_NONE;
}

int SNDSetMute(int speakerOn)
{
    port_t dev_port=PORT_NULL, owner_port;
    int err;
    boolean_t speaker, lowpass, zerofill;
    if (err = initialize())
        return err;
    err = SNDAcquire(0,0,0,-1,0,0,&dev_port,&owner_port);
    if (err) return err;
    err = snddriver_get_device_parms(dev_port,&speaker,&lowpass,&zerofill);
    if (err)
        return (err == RCV_TIMED_OUT || err == SEND_TIMED_OUT)? 
            SND_ERR_TIMEOUT : SND_ERR_KERNEL;
    if ((speakerOn && speaker) || (!speakerOn && !speaker))
        return SND_ERR_NONE;
    err = snddriver_set_device_parms(dev_port,!speaker, lowpass, zerofill);
    if (err)
        return (err == RCV_TIMED_OUT || err == SEND_TIMED_OUT)? 
            SND_ERR_TIMEOUT : SND_ERR_KERNEL;
    return SND_ERR_NONE;
}

int SNDGetMute(int *speakerOn)
{
    port_t dev_port=PORT_NULL, owner_port;
    int err;
    boolean_t speaker, lowpass, zerofill;
    if (err = initialize())
        return err;
    err = SNDAcquire(0,0,0,-1,0,0,&dev_port,&owner_port);
    if (err) return err;
    err = snddriver_get_device_parms(dev_port,&speaker,&lowpass,&zerofill);
    if (err)
        return (err == RCV_TIMED_OUT || err == SEND_TIMED_OUT)? 
            SND_ERR_TIMEOUT : SND_ERR_KERNEL;
    *speakerOn = speaker? 1:0;
    return SND_ERR_NONE;
}

int SNDSetCompressionOptions(SNDSoundStruct *s, int comprType, int dropBits)
{
    SNDCompressionSubheader *subheader = NULL;
    
    if (!s || (s->magic != SND_MAGIC))
        return SND_ERR_NOT_SOUND;
    if (s->dataFormat != SND_FORMAT_COMPRESSED &&
        s->dataFormat != SND_FORMAT_COMPRESSED_EMPHASIZED)
        return SND_ERR_BAD_FORMAT;
    if (s->dataSize < sizeof(SNDCompressionSubheader))
        return SND_ERR_BAD_SIZE;
    subheader = (SNDCompressionSubheader *)((char *)s + s->dataLocation);
    subheader->method = comprType;
    subheader->numDropped = dropBits;
    return SND_ERR_NONE;
}

int SNDGetCompressionOptions(SNDSoundStruct *s, int *comprType, int *dropBits)
{
    SNDCompressionSubheader *subheader = NULL;
    
    if (!s || (s->magic != SND_MAGIC))
        return SND_ERR_NOT_SOUND;
    if (s->dataFormat != SND_FORMAT_COMPRESSED &&
        s->dataFormat != SND_FORMAT_COMPRESSED_EMPHASIZED)
        return SND_ERR_BAD_FORMAT;
    if (s->dataSize < sizeof(SNDCompressionSubheader))
        return SND_ERR_BAD_SIZE;
    subheader = (SNDCompressionSubheader *)((char *)s + s->dataLocation);
    *comprType = subheader->method;
    *dropBits = subheader->numDropped;
    return SND_ERR_NONE;
}

int SNDUpdateDSPParameter(int value)
{
    /* FIXME */
    return SND_ERR_NOT_IMPLEMENTED;
}

int SNDSetFilter(int filterOn)
{
    port_t dev_port=PORT_NULL, owner_port;
    int err;
    boolean_t speaker, lowpass, zerofill;
    if (err = initialize())
        return err;
    err = SNDAcquire(0,0,0,-1,0,0,&dev_port,&owner_port);
    if (err) return err;
    err = snddriver_get_device_parms(dev_port,&speaker,&lowpass,&zerofill);
    if (err)
        return (err == RCV_TIMED_OUT || err == SEND_TIMED_OUT)? 
            SND_ERR_TIMEOUT : SND_ERR_KERNEL;
    if ((filterOn && lowpass) || (!filterOn && !lowpass))
        return SND_ERR_NONE;
    err = snddriver_set_device_parms(dev_port, speaker, !lowpass, zerofill);
    if (err)
        return (err == RCV_TIMED_OUT || err == SEND_TIMED_OUT)? 
            SND_ERR_TIMEOUT : SND_ERR_KERNEL;
    return SND_ERR_NONE;
}

int SNDGetFilter(int *filterOn)
{
    port_t dev_port=PORT_NULL, owner_port;
    int err;
    boolean_t speaker, lowpass, zerofill;
    if (err = initialize())
        return err;
    err = SNDAcquire(0,0,0,-1,0,0,&dev_port,&owner_port);
    if (err) return err;
    err = snddriver_get_device_parms(dev_port,&speaker,&lowpass,&zerofill);
    if (err)
        return (err == RCV_TIMED_OUT || err == SEND_TIMED_OUT)? 
            SND_ERR_TIMEOUT : SND_ERR_KERNEL;
    *filterOn = lowpass ? 1 : 0;
    return SND_ERR_NONE;
}


int SNDVerifyPlayable(SNDSoundStruct *s)
{
    int mode = calc_play_mode(s);

    if (mode == MODE_NONE || mode == MODE_DSP_CORE_OUT)
      return SND_ERR_CANNOT_PLAY;

#if !TRY_SQUELCH
    /*FIXME: MULAW SQUELCH DISABLED */
    if (mode == MODE_SQUELCH_OUT)
      return SND_ERR_CANNOT_PLAY;
#endif

    if (arch_cpu_type == CPU_TYPE_MC680x0) {
        if (mode == MODE_RESAMPLE_OUT) /* FIXME if DSP resample core done */
          return SND_ERR_CANNOT_PLAY;
        if (s->channelCount == 2)
          if (mode == MODE_FLOAT_OUT ||
              mode == MODE_DOUBLE_OUT)
            return SND_ERR_CANNOT_PLAY;
    }     

    return SND_ERR_NONE;        /* Good luck! */
}         

/***************************************************************************/
/*      Modification History:
 *      02/15/90/mtm    Added support for SND_FORMAT_COMPRESSED.
 *                      Check for mode optimizable in terminate_performance().
 *                      Call terminate_performance() before endFun in
 *                      performance_ended().
 *      03/20/90/mtm    Pass dma size to play_configure_dsp_data().
 *      03/21/90/mtm    Added support for SND_FORMAT_DSP_COMMANDS
 *      04/02/90/mtm    Added support for compressed recording from DSP
 *      04/06/90/mtm    Added stubs for playing on DSP, setting compression
 *                      options, writing a DSP parameter value, and
 *                      getting and setting the filter state.
 *      04/09/90/mtm    #include <mach_init.h>
 *      04/10/90/mtm    Implement SND{Set,Get}Filter() and
 *                      SND{Set,Get}CompressionOptions().  Implement playback
 *                      of emphasized sounds.
 *      04/11/90/mtm    Added #import <stdlib.h> per OS request.
 *      04/16/90/mtm    Support for playing back on DSP.
 *      04/30/90/mtm    Use multiple read requests rather that stream
 *                      awaits during recording.
 *      05/08/90/mtm    Move endFun call back before terminate_performance() 
 *			call in performance_ended(). Save sound header in pr 
 *			field for use after endFun called (which may have freed 
 *			sound).
 *      05/11/90/mtm    Implement 22K mono recording from DSP.
 *                      Send sampleSkip=4 to DSP for 22K compression hack.
 *      05/17/90/mtm    Fix recording bug that caused called
 *                      performance_started() to be called multiple times.
 *      05/18/90/mtm    Revert back to using stream control during recording
 *                      so that the SoundKit's SoundMeter works, i.e,
 *                      SNDSamplesProcessed() is acurate.
 *      05/23/90/mtm    Use multiple read request rather than stream control
 *                      FOR MODE_COMPRESSED_IN ONLY to get around driver bug
 *                      that results in missing data with dspsoundssi.asm.
 *      05/24/90/mtm    Initialize free list structs in enqueue_perf_request.
 *      05/25/90/mtm    Bit-faithful bits no longer sent in separate buffer.
 *                      Made MODE_COMPRESSED_IN optimizable, and don't send
 *                      numSamples to DSP in this mode.
 *      05/29/90/mtm    Release resource in terminate_performance() when only
 *                      one request left in queue.
 *      05/30/90/mtm    Back to stream control for compressed case now that
 *                      sound driver split stream bug fixed.
 *      06/11/90/mtm    DMA streaming for ssiplay.
 *      06/12/90/mtm    Truncate floats to ints using floor.
 *      06/14/90/mtm    Support dsp-initiated dma to the dsp for ssiplay and
 *                      decompression.
 *      06/16/90/mtm    Pad compressed recording to decompression dma size.
 *      07/10/90/mtm    Call SNDReset() to stop soundout in stop_performance().
 *      07/17/90/mtm    SNDDRIVER_DSP_PROTO_SIMPLE now hard-coded as 0.
 *                      SNDDRIVER_DSP_PROTO_HOSTMSG now 
 *			SNDDRIVER_DSP_PROTO_DSPMSG.
 *      07/18/90/mtm    Get rid of static array in findDSPCore() and move 
 *			static array to const in record_samples().
 *                      Change compress.snd to ssicompress.snd.
 *                      Change decompress.snd to sndoutdecompress.snd.
 *      06/29/90/mtm    Implement SNDStartRecordingFile().
 *      08/08/90/mtm    Add sample rate conversion support.
 *      08/13/90/mtm    Verify sample rate and channel count for DSP commands 
 *			playback.
 *      09/28/90/mtm    Fix 22K mono compression (bug #9881).
 *      10/01/90/mtm    Dont' allow chained playback of compressed sounds (bug 
 *			#7909).
 *      10/01/90/mtm    Don't pad compression, bump dma to the dsp count
 *                      to vm_page_size (bug #10005).
 *      10/02/90/mtm    Check for request_count in SNDWait() (bug #10024).
 *      10/03/90/mtm    Take headerSize mod vm_page_size for dma to the dsp 
 *			(bug #7912).
 *      10/04/90/mtm    Don't generate timeout error if stream_nsamples OK (bug 
 *			#10011).
 *      10/08/90/mtm    Use different cores for mono and stereo resample (bug 
 *			#10407).
 *      10/11/90/mtm    Only pad decompression to dma size
 *                      (real fix for bug #10011).
 *      10/24/90/mtm    Allow recordFD to be 0 (bug #11450).
 *      10/02/91/mtm    Import location changes.
 *      10/11/91/jos    Hacked in ATC compression format.
 *                      ATC is a new compression option like bit-faithful.
 *      01/27/92/jos    initiate_performance() now tries to go on without DSP
 *                      if the DSP is not available.  Several C threads,
 *                      referred to as "black boxes," now exist for several
 *                      cases: simple format and sampling-rate conversion,
 *                      CODEC playback, and mono-to-stereo conversion or vv.
 *      03/06/92/jos    C version of ATC decompression. 
 *                      Happy birthday Michelangelo.
 *      11/18/92/jos    Added set_arch_cpu_type().
 *                      Mode COMPRESSED_OUT no longer returns error if no DSP.
 *                      Mode RESAMPLE_OUT no longer returns error if no DSP.
 *                          Black box cthread will do simple linear interp.
 *      02/22/93/jos    Added support for remaining compression formats.
 *
 *	03/15/94/rkd	Added support for 8-bit mono playback using black box 
 *			threads (the function play_black_box_8). The entire 
 *			data is converted before playback. The standard routine 
 *			works fine only for 16-bit end data. There is some 
 *			dependency on "block sizes" sent down to kernel and 
 *			also in playback throttleing. This needs to be fixed 
 *			before we can do on-the-fly conversions. Also did some 
 *			clean up.
 *	04/13/94/rkd	8-bit mono playback now does on the fly conversions. 	
 *			Fixed some other bugs. Removed play_black_box_8() which 
 *			was not a real solution.
 *
 */
