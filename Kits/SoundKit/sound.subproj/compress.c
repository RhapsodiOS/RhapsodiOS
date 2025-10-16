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
 * compress.c
 *	This file is included by convertsound.c!!!!
 *
 * Modification History:
 *	08/10/90/mtm	Added max timeout.
 *	08/15/90/mtm	Restrict encode length to 256, disable timeout for debug.
 *	09/28/90/mtm	Send correct data size to DSP for compression (bug #7909).
 *	10/01/90/mtm	Don't copy sound (bug #10005).
 *	10/11/90/mtm	Only pad to dma size (real fix for bug #10011).
 *	10/10/91/jos	Hacked in ATC case. bitFaithful -> method type
 *      10/12/91/jos    Added ATC_STREAM_AWAIT_TIMEOUT
 *	03/15/92/jos	Copy cached DSP core files since they get freed.
 */

#define	COMPRESS_STREAM_AWAIT_TIMEOUT 1000
#define	ATC_STREAM_AWAIT_TIMEOUT 1000000000
#define	COMPRESS_MAX_TIMEOUTS 5
#define COMPRESS_READ_TAG 1
#define COMPRESS_WRITE_TAG 2
#define FLUSH_TAG 3

#import <mach/cthreads.h>	/* for pressing on without DSP */
#import "_compression.h"
#import "_atcsound.h"

static float *ATCBandGains = 0;
static int *ATCBandGainsDSP = 0;
static float *ATCBandThresholds = 0;
static int *ATCBandThresholdsDSP = 0;
static short *flush_buf;

/* Modes */
enum {
    MODE_COMPRESS,
    MODE_DECOMPRESS
  };

static void hf3_true(void *arg, u_int mask, u_int flags, u_int registers)
/* called when hf3 is set */
{
    compress_info_t *info = (compress_info_t *)arg;
    int err;
    info->aborted++;
    if (registers & SNDDRIVER_ISR_HF2)
      fprintf(stderr,"hf3_true: hf2 => DSP aborted during ATC compression\n");
    err=snddriver_stream_control(info->read_port,COMPRESS_READ_TAG,
				 SNDDRIVER_AWAIT_STREAM);
#ifdef DEBUG
    fprintf(stderr,"hf3_true: aborting read stream\n");
    if (err)
      fprintf(stderr,"hf3_true: could not request read stream abort\n");
#endif
}

static void atc_write_completed(void *arg, int tag)
    /* Called when the input to the DSP has been written. */
{
    compress_info_t *info = (compress_info_t *)arg;
    int err = 0;
    
#ifdef DEBUG
    fprintf(stderr,"%s write done.\n",(tag==FLUSH_TAG? "Flush" : "Data"));
#endif
    if (info->mode == MODE_COMPRESS) {
	
#ifdef DEBUG
	fprintf(stderr,"Requesting HF3 notice (ATC compression)\n");
#endif
	err = snddriver_dspcmd_req_condition(info->cmd_port,
					     SNDDRIVER_ISR_HF3,
					     SNDDRIVER_ISR_HF3,
					     SNDDRIVER_LOW_PRIORITY,
					     info->reply_port);
#ifdef DEBUG
	if (err)
	  fprintf(stderr,"atc_write_completed: could not request HF3 alert\n");
#endif
    }

#ifdef DEBUG
    fprintf(stderr,"Enqueing flush buffer\n");
#endif
	
    /* Use vm_allocate() to get page alignment and initial zeros */
#define FLUSH_BUF_SIZE (vm_page_size)
    err = vm_allocate(task_self(),
		      (pointer_t *)&flush_buf,FLUSH_BUF_SIZE,1);
    /* enqueue the flush region request */
    err = snddriver_stream_start_writing(info->write_port,
					 (void *)flush_buf,
					 FLUSH_BUF_SIZE/2,
					 FLUSH_TAG,
					 0,1 /* dealloc when done */,
					 0,1 /* completed */,
					 0,0,0,0, info->reply_port);
#ifdef DEBUG
    if (err)
      fprintf(stderr,
	      "Could not send sound compression DSP flush buffer\n");
#endif
    
#if 1

    /* Must add one extra region to make sure stream thread is alive
       if race not fixed in DSP driver re. stream management (in Tracker) */

	err = vm_allocate(task_self(),
			  (pointer_t *)&flush_buf,FLUSH_BUF_SIZE,1);
#ifdef DEBUG
    if (err)
      fprintf(stderr,
	      "Could not send sound compression DSP flush buffer\n");
#endif

	/* enqueue the flush region request */
	err = snddriver_stream_start_writing(info->write_port,
					     (void *)flush_buf,
					     FLUSH_BUF_SIZE/2,
					     FLUSH_TAG,
					     0,1 /* dealloc when done */,
					     0,1 /* completed */,
					     0,0,0,0, info->reply_port);
#ifdef DEBUG
    if (err)
      fprintf(stderr,
	      "Could not send sound compression DSP flush buffer\n");
#endif

#endif

    if (info->mode == MODE_DECOMPRESS && tag==FLUSH_TAG && !info->read_done) {
	/* Something went wrong.  Probably a truncated compressed file. */
	err = snddriver_stream_control(info->read_port, COMPRESS_READ_TAG, 
				       SNDDRIVER_AWAIT_STREAM);	/* for reply */
	info->aborted++;
	fprintf(stderr,"ATC decompression aborted. Truncated input file?\n");
    }
}



static int atc_final_compress_read(void *arg, int tag, void *p, int bytes_read)
{
    compress_info_t *info = (compress_info_t *)arg;
    int err;
    int rcount = 1;
    int dsp_read_count;
    int dsp_bytes_read;

    info->read_done++;

    err = snddriver_dsp_read(info->cmd_port,&dsp_read_count,&rcount,4,
			     SNDDRIVER_MED_PRIORITY);
    dsp_bytes_read = dsp_read_count * 2;
#ifdef DEBUG
    if (err)
      fprintf(stderr,"Cannot read DSP read count\n");
    else
      fprintf(stderr,"DSP says %d bytes\n",dsp_bytes_read);
#endif

    err = -SND_MAGIC;	/* flag to reset DSP message buffer */
    err = snddriver_dsp_read_messages(info->cmd_port,0,&err,0,0);

    return dsp_bytes_read;
}



static void atc_read_completed(void *arg, int tag, void *p, int bytes_read)
{
    compress_info_t *info = (compress_info_t *)arg;
    int size,err;
    void *p0 = p;
    
#ifdef DEBUG
    fprintf(stderr,"atc_read_completed: read done. %d bytes\n",bytes_read);
#endif
    
    if (info->aborted && (info->mode == MODE_COMPRESS))
      size = atc_final_compress_read(arg,tag,p,bytes_read);
    else {
	size = (bytes_read > info->remaining_bytes) ? 
	  info->remaining_bytes : bytes_read;

#if 0
	/*** FIXME: Can only use await for final compress read since 
	  abort replies do not work with awaits and since
	  the final region would not be distinguishable from
	  reads in front of it using multiple awaits. ***/
	err = snddriver_stream_control(info->read_port, tag, 
				       SNDDRIVER_AWAIT_STREAM);
#endif
    }

    info->read_count += size;
    info->remaining_bytes -= size;

    if (info->read_count == size)  { /* skip header part of DSP data */
	int adj;
	if (info->mode == MODE_COMPRESS) {
	    /* DSP does not send back header+subheader - FIXME */
	    info->read_ptr += info->sound_header_size 
	      + sizeof(SNDCompressionSubheader);
	} else {		/* MODE_DECOMPRESS */
	    adj = info->sound_header_size + sizeof(SNDCompressionSubheader);
	    p += adj;
	    size -= adj;
	    info->read_count -= adj; /* determines output file size */
	    /* FIXME - install header here */
	    info->read_ptr += info->sound_header_size; /* no subheader */
	}
    }

    /*
     * FIXME: We can use vm_copy() if we install the output header
     * here rather than earlier.  Saves a copy.
     */
    memmove((void *)info->read_ptr, p, size);
    info->read_ptr += size;

    err = vm_deallocate(task_self(),(pointer_t)p0,bytes_read);

    if (info->remaining_bytes <= 0 || info->aborted) /* decompr may abort */
      info->read_done++;
}


#if 0
/*** Sound driver bug: If an "await" is pending on a stream,
  an abort reply is never sent. We therefore set abort flag and
  do an await rather than an abort in hf3_true() ***/
static void atc_read_aborted(void *arg, int tag)
{
    compress_info_t *info = (compress_info_t *)arg;
    info->aborted++;
#ifdef DEBUG
    fprintf(stderr,"atc_read_aborted\n");
#endif
}
#endif

static void compress_read_data(void *arg, int tag, void *p, int bytes_read)
    /*
     * Copy the returned buffer into the sound and request the next
     * buffer using stream control.  If compressing, abort stream when
     * data representing all samples has been received.
     */
{
    compress_info_t *info = (compress_info_t *)arg;
    int size, err;
    int count, code, numBits;
    int numSamples = 0;
    
    size = (bytes_read > info->remaining_bytes) ? 
      info->remaining_bytes : bytes_read;

    if (info->read_count == 0)	{
	/* FIXME: Change DSP code to send header and subheader.
	   Then install header here and use vm_copy() instead of memmove */
	info->read_ptr += info->sound_header_size 
	  + sizeof(SNDCompressionSubheader);
	info->block_ptr = info->read_ptr;
	/* DSP does not send back a header */
    }

    memmove((void *)info->read_ptr, p, size);
    
    info->read_ptr += size;
    info->read_count += size;
    info->remaining_bytes -= size;
    if (info->remaining_bytes <= 0)
      info->read_done = 1;

    if (info->mode == MODE_COMPRESS) {
	numSamples = info->subheader.originalSize / 2;
	/*
	 * Note: dataSize gets truncated leaving a hole of unused
	 * but allocated memory in the sound.  This hole of course goes
	 * away if you write the compressed sound to a file.
	 */
	while (info->read_ptr > info->block_ptr) {
	    if (((info->block_count) * info->subheader.encodeLength) 
		>= numSamples) {
		info->read_count -= (info->read_ptr - info->block_ptr);
		if (info->read_count > info->subheader.originalSize) {
		    info->read_count = info->subheader.originalSize;
#ifdef DEBUG
		    printf("Sound could not be compressed\n");
#endif
		}
		info->read_done = 1;
		break;
	    }
	    code = *info->block_ptr++;
	    numBits = *info->block_ptr++;
	    if ((unsigned)code >= NUM_ENCODES || (unsigned)numBits > 16) {
#ifdef DEBUG
		printf("BOGUS!! block=%d, code=%d, numBits=%d\n",
		       info->block_count, code, numBits);
#endif
		info->read_done = 1;
		break;
	    }
	    
	    count=bytesInBlock(code,numBits,info->subheader.encodeLength);
	    if (count & 1)
	      count++;	/* pad to short */
	    info->block_ptr += count;
	    info->block_count++;
	}
    }
    /*
     * Tell the driver to send us data as soon as possible.
     * Normally we get one DMA buffer each time.
     */
    err = snddriver_stream_control(info->read_port, tag, 
				   SNDDRIVER_AWAIT_STREAM);
    err = vm_deallocate(task_self(),(pointer_t)p,bytes_read);
}


static int compressDSP(SNDSoundStruct *s1, SNDSoundStruct **s2,
		       int comprType, int dropBits)
    /*
     * Compress or decompress on DSP depending on mode of s1.
     * Largely a rip-off of SNDRunDSP().
     */
{
    static SNDSoundStruct *decompressCore = NULL;
    static SNDSoundStruct *compressCore = NULL;
    
    static SNDSoundStruct *decompressAtcCore = NULL;
    static SNDSoundStruct *compressAtcCore = NULL;
    static msg_header_t *reply_msg = 0;
    
#if 0
    /* Currently, compress.asm has a max encode length of 256 */
    static const short bestEncodeLength[] = {
	64,	/* shift 0 - currently not used */
	64,	/* shift 1 - currently not used */
	128,	/* shift 2 - currently not used */
	128,	/* shift 3 - currently not used */
	256,	/* shift 4 */
	256,	/* shift 5 */
	512,	/* shift 6 */
	512,	/* shift 7 */
	512	/* shift 8 */
      };
#endif
    
    SNDSoundStruct *core = 0;
    int err, protocol = 0;
    int priority = 1, preempt = 0, low_water = 32*1024, high_water = 32*1024;
    port_t dev_port=PORT_NULL, owner_port=PORT_NULL;
    port_t read_port, write_port, reply_port;
    int bufsize;
    int dmaBytes = MAX(ATC_DMA_BUFFER_SIZE,COMPRESS_DMASIZE) * 2;
    int headerSizeShorts, encodeLen, encodeSize;
    int negotiation_timeout = -1;
    compress_info_t info;
    int timeoutCount = 0;
    int dspInSize,dspOutSize;
    snddriver_handlers_t handlers = { &info, 0, 0, 0,
					0, 0, 0, 0,
					compress_read_data };
    snddriver_handlers_t atc_handlers = { &info, 0, 0, atc_write_completed, 
					    0 /* FIXME: atc_read_aborted */, 
					    0, 0, 0, 
					    atc_read_completed,hf3_true};
    void *write_ptr;
    int write_count, write_width;
    int read_count, read_width;
    SNDCompressionSubheader *subheader = NULL;
    int dspcinfo[4];
    
    int (*thread_func)(thread_args *targs) = 0;
	
#if sparc
// Alignment handling code in kernel to be turned on
	// Turning on alignment handling for this process
	asm("	t	6;");


#endif sparc
    
    if (s1->dataFormat == SND_FORMAT_COMPRESSED ||
	s1->dataFormat == SND_FORMAT_COMPRESSED_EMPHASIZED)
      info.mode = MODE_DECOMPRESS;
    else if (s1->dataFormat == SND_FORMAT_LINEAR_16 ||
	     s1->dataFormat == SND_FORMAT_EMPHASIZED)
      info.mode = MODE_COMPRESS;
    else {
	SNDSoundStruct s,*sp = &s;
	bcopy((char *)&s,(char *)s1,sizeof(SNDSoundStruct));
	s.dataFormat = SND_FORMAT_LINEAR_16;
	err = SNDConvertSound(s1,&sp);
	if (err)
	  return SND_ERR_BAD_FORMAT;
	else
	  s1 = sp;
    }    
    write_ptr = (void *)s1;
    write_width = read_width = 2;

    headerSizeShorts = s1->dataLocation / 2; /* sent to DSP */
    
    /*
     * A note on "headers".
     * The official "header" never includes the subheader.
     * A subheader (for compressed files), is counted as part of the
     * data (by sndinfo, etc.).  Thus dataLocation actually points
     * to the beginning of the subheader if there is one.
     * Because of DMA alignment considerations, all headers are sent to
     * and received from the DSP.  (The DSP zeros or skips them on input.)
     * Therefore, sizes below pertaining to DSP data include all headers.
     * The general rule is that data to and from the DSP should always be
     * page aligned.  That way we can avoid copies.
     */
    if (info.mode == MODE_DECOMPRESS) {
	if (s1->dataSize <= sizeof(SNDCompressionSubheader))
	  return SND_ERR_BAD_SIZE;
	subheader = (SNDCompressionSubheader *)data_pointer(s1);
	comprType = subheader->method; /* so comprType is valid either way */
	/* DSP works on page aligned data always */
	dspInSize = s1->dataSize + s1->dataLocation; /* subhdr is in data */
	dspOutSize = subheader->originalSize 
	  + s1->dataLocation + sizeof(SNDCompressionSubheader);
	err = vm_allocate(task_self(), (pointer_t *)s2,dspOutSize,1);
	if (err != KERN_SUCCESS) return SND_ERR_CANNOT_ALLOC;

	/*
	 * We can set up the output header now because the header part
	 * of the data from the DSP will be discarded in the DMA read
	 * complete routine.
	 */
	memmove(*s2, s1, s1->dataLocation);
	(*s2)->dataSize = 0;
	(*s2)->dataFormat = 
	  (s1->dataFormat == SND_FORMAT_COMPRESSED_EMPHASIZED ?
	   SND_FORMAT_EMPHASIZED : SND_FORMAT_LINEAR_16);

	/*
	 * Set up the info struct which is passed to the DMA completion
	 * handlers.
	 */
	info.read_count = 0;	/* raw count of bytes read BEFORE discard */
	info.read_ptr = (char *)(*s2); /* pointer to whole slab of sound */
	info.remaining_bytes = dspOutSize;
	info.sound_header_size = s1->dataLocation;
	info.aborted = 0;

	/*
	 * Set up DMA buffer size and DSP code to use.
	 */
	if (comprType == SND_CFORMAT_ATC) {
	    bufsize = ATC_DMA_BUFFER_SIZE;
	    info.timeout = ATC_STREAM_AWAIT_TIMEOUT;
	    if (!decompressAtcCore) {
		SNDSoundStruct *tempCore;
		err = findDSPcore("hostdecompressatc", &tempCore);
		if (err) return err;
		/* Must copy since findDSPcore() will free tempCore
		   if next called with a different name. One could
		   argue that findDSPcore should never free a core
		   and that the user is responsible for freeing.  In that
		   case, findDSPcore must be changed to COPY its saved
		   core every time it is used (since the user knows no
		   better than to free it after each use). In this case,
		   the numerous uses in performsound.c need to free their
		   cores */
		SNDCopySound(&decompressAtcCore,tempCore);
	    }
	    core = decompressAtcCore;
	} else {		/* non-ATC compressed format */
	    bufsize = COMPRESS_DMASIZE;
	    info.timeout = COMPRESS_STREAM_AWAIT_TIMEOUT;
	    if (!decompressCore) {
		SNDSoundStruct *tempCore;
		err = findDSPcore("hostdecompress", &tempCore);
		if (err) return err;
		/* Must copy since findDSPcore() will free tempCore
		   if next called with a different name. */
		SNDCopySound(&decompressCore,tempCore);
	    }
	    core = decompressCore;
	}
	dmaBytes = bufsize * 2;

    } else {	/* MODE_COMPRESS */
	int sizePH;
	if (comprType == SND_CFORMAT_ATC) {
	    info.timeout = ATC_STREAM_AWAIT_TIMEOUT;
	    if (!compressAtcCore) {
		SNDSoundStruct *tempCore;
		err = findDSPcore("hostcompressatc", &tempCore);
		if (err) return err;
		/* Must copy since findDSPcore() will free next call */
		SNDCopySound(&compressAtcCore,tempCore);
	    }
	    core = compressAtcCore;
	    /*
	     * dataSize must be a multiple of the coder internal block size
	     */
	    bufsize = ATC_DMA_BUFFER_SIZE; /* shorts */
	    encodeLen = bufsize;
	} else {
	    info.timeout = COMPRESS_STREAM_AWAIT_TIMEOUT;
	    if (!compressCore) {
		SNDSoundStruct *tempCore;
		err = findDSPcore("hostcompress", &tempCore);
		if (err) return err;
		/* Must copy since findDSPcore() will free next call */
		SNDCopySound(&compressCore,tempCore);
	    }
	    core = compressCore;
	    /*
	     * dataSize must be a multiple of the encode length.
	     */
	    bufsize = COMPRESS_DMASIZE;
	    encodeLen = PARPACK_ENCODE_LENGTH; /*bestEncodeLength[dropBits];*/
	}
	dmaBytes = bufsize * sizeof(short);
	encodeSize = encodeLen * s1->channelCount * write_width; /*bytes*/
	sizePH = s1->dataSize + s1->dataLocation; /* header sent */
	dspInSize = (sizePH / encodeSize) * encodeSize;
	if (dspInSize < sizePH) {
	    int n;
	    unsigned char *cp = ((char *)s1) + sizePH;
	    dspInSize += encodeSize; /* Allow final partial buffer */
	    n = dspInSize - sizePH; /* Length of residual to be compressed */
	    while(n--)
	      *cp++ = 0;	/* Make sure residual is zero */
	}
	if (dspInSize <= 0)
	  return SND_ERR_BAD_SIZE;

	dspOutSize = dspInSize + vm_page_size; /* worst case compr + page */

	err = vm_allocate(task_self(), (pointer_t *)s2, dspOutSize, 1);
	if (err != KERN_SUCCESS) {
	    err = SND_ERR_CANNOT_ALLOC;
	    goto err_exit;
	}

	/*
	 * Set up output header. FIXME: should do this into rcvd DSP data.
	 */
	memmove(*s2, s1, s1->dataLocation);	/* copy header and info */
	(*s2)->dataSize = sizeof(SNDCompressionSubheader);
	(*s2)->dataFormat = (s1->dataFormat == SND_FORMAT_EMPHASIZED ?
			     SND_FORMAT_COMPRESSED_EMPHASIZED : 
			     SND_FORMAT_COMPRESSED);
	subheader = (SNDCompressionSubheader *)data_pointer(*s2);
	subheader->originalSize = s1->dataSize;
	subheader->method = comprType;
	if (comprType != SND_CFORMAT_ATC)
	  dropBits = MIN(8,MAX(4,dropBits));
	subheader->numDropped = dropBits;
	subheader->encodeLength = encodeLen;
	subheader->reserved = 0;
	info.subheader = *subheader;
	info.sound_header_size = (*s2)->dataLocation;
	info.read_ptr = (char *)(*s2);
	info.block_ptr = info.read_ptr;
	info.block_count = 0;
	info.read_count = 0;
	info.remaining_bytes = dspInSize;
	info.aborted = 0;
    }				/* MODE_COMPRESS */

    if (!reply_msg)
      reply_msg = (msg_header_t *)malloc(MSG_SIZE_MAX);
    err = SNDAcquire(SND_ACCESS_DSP, priority, preempt, negotiation_timeout,
		     NULL_NEGOTIATION_FUN, (void *)0,
		     &dev_port, &owner_port);
    if (err) goto no_dsp;
    
    err = snddriver_get_dsp_cmd_port(dev_port,owner_port,
				     &info.cmd_port);
    if (err) goto kerr_exit;

    err = -SND_MAGIC;	/* flag to reset DSP message buffer */
    err = snddriver_dsp_read_messages(info.cmd_port,0,&err,0,0);

    /*
     * Do DSP-initiated DMA in both directions (see dspsounddi.asm).
     */
    err = snddriver_stream_setup(dev_port, owner_port,
    				 SNDDRIVER_DMA_STREAM_FROM_DSP,
				 bufsize, read_width,
				 low_water, high_water,
				 &protocol, &read_port);
    if (err) goto kerr_exit;
    info.read_port = read_port;
    err = snddriver_stream_setup(dev_port, owner_port,
    				 SNDDRIVER_DMA_STREAM_TO_DSP,
				 bufsize, write_width, 
				 low_water, high_water,
				 &protocol, &write_port);
    if (err) goto kerr_exit;
    err = snddriver_dsp_protocol(dev_port, owner_port, protocol);
    if (err) goto kerr_exit;
    
    err = port_allocate(task_self(),&reply_port);
    if (err) goto kerr_exit;
    
    
    /* 
     * DMA must start on a page boundry so we send the whole sound,
     * including the header.  The DSP is passed the number of bytes
     * to ignore (the header size). Also, bump write_count up to next 
     * dma size multiple for dma to the dsp.  This memory exists because 
     * either map_fd() vm_allocate() was used to create the sound and 
     * therefore has memory up to the next page size. 
     */
    
    read_count = dspOutSize / read_width;
    if (read_count % dmaBytes)
      read_count = (read_count + dmaBytes) & ~(dmaBytes - 1);

    err = snddriver_stream_start_reading(read_port, 0, read_count, 
					 COMPRESS_READ_TAG,
					 0,1,1,0,0,0, reply_port);
    if (err) goto kerr_exit;
    
    err = SNDBootDSP(dev_port,owner_port,core);
    if (err) goto err_exit;
    /*
     * Send parameters to the DSP.
     */
    err = snddriver_dsp_write(info.cmd_port,&bufsize,1,4,
			      SNDDRIVER_MED_PRIORITY);
    err = snddriver_dsp_write(info.cmd_port,&headerSizeShorts,1,4,
			      SNDDRIVER_MED_PRIORITY);
    err = snddriver_dsp_write(info.cmd_port,&s1->channelCount,1,4,
			      SNDDRIVER_MED_PRIORITY);

    if (err) goto err_exit;

    if (info.mode == MODE_COMPRESS) {
	dspcinfo[0] = comprType;
	dspcinfo[1] = subheader->numDropped;
	dspcinfo[2] = subheader->encodeLength;
	dspcinfo[3] = s1->channelCount;
	err = snddriver_dsp_write(info.cmd_port,dspcinfo,4,4,
				  SNDDRIVER_MED_PRIORITY);
	if (err) goto err_exit;
	if (comprType == SND_CFORMAT_ATC) {
	    int bufCount = dspInSize / dmaBytes;
	    if (bufCount * dmaBytes != dspInSize)
	      bufCount++;
	    err = snddriver_dsp_write(info.cmd_port,&bufCount,1,4,
				      SNDDRIVER_MED_PRIORITY);
	    if (err) goto err_exit;
	    if (ATCBandThresholds == 0) {
		ATCBandThresholds = _SNDGetATCSTP();
		ATCBandThresholdsDSP = (int *)malloc(ATC_NBANDS * sizeof(int));
	    }
	    floatToDSPFix24(ATC_NBANDS,ATCBandThresholds,
			    ATCBandThresholdsDSP);
	    err = snddriver_dsp_write(info.cmd_port,
				      ATCBandThresholdsDSP,ATC_NBANDS,4,
				      SNDDRIVER_MED_PRIORITY);
	}
    } else {			/* MODE_DECOMPRESS */
	if (comprType == SND_CFORMAT_ATC) {
	    if (ATCBandGains == 0) {
		ATCBandGains = _SNDGetATCEGP();
		ATCBandGainsDSP = (int *)malloc(ATC_NBANDS * sizeof(int));
	    }
	    floatToUnsignedDSPFix24(ATC_NBANDS,ATCBandGains,ATCBandGainsDSP);
	    err = snddriver_dsp_write(info.cmd_port,ATCBandGainsDSP,ATC_NBANDS,
				      4,SNDDRIVER_MED_PRIORITY);
	}
    }

    info.write_port = write_port;
    info.reply_port = reply_port;

    write_count = dspInSize / write_width;
    if (write_count % dmaBytes)
      write_count = (write_count + dmaBytes) & ~(dmaBytes - 1);
    
    err = snddriver_stream_start_writing(write_port,
    					 write_ptr,
					 write_count,
					 COMPRESS_WRITE_TAG,
					 0,0,
					 0,1 /* completed */,
					 0,0,0,0, reply_port);
    if (err) goto kerr_exit;

    if (comprType != SND_CFORMAT_ATC) /* FIXME: need abort to work w awaits */
      err = snddriver_stream_control(read_port, COMPRESS_READ_TAG, 
				     SNDDRIVER_AWAIT_STREAM);
    if (err != KERN_SUCCESS)
      goto kerr_exit;
    
    info.read_done = 0;
    while (!info.read_done) {
	reply_msg->msg_size = MSG_SIZE_MAX;
	reply_msg->msg_local_port = reply_port;
	err = msg_receive(reply_msg, RCV_TIMEOUT, info.timeout);
	if (err == RCV_TIMED_OUT) {
	    if (++timeoutCount > COMPRESS_MAX_TIMEOUTS) {
#ifdef DEBUG
		fprintf(stderr, "Request timed out\n");
#endif
		(*s2)->dataSize = info.read_count;
		goto normal_exit;
	    }
	    if (comprType != SND_CFORMAT_ATC) /* FIXME */
	      err = snddriver_stream_control(read_port, COMPRESS_READ_TAG,
					     SNDDRIVER_AWAIT_STREAM);
	    if (err != KERN_SUCCESS)
	      goto kerr_exit;
	} else if (err != KERN_SUCCESS)
	  goto kerr_exit;
	else {
	    if (comprType == SND_CFORMAT_ATC)
	      err = snddriver_reply_handler(reply_msg,&atc_handlers);
	    else
	      err = snddriver_reply_handler(reply_msg,&handlers);
	    if (err != KERN_SUCCESS) goto kerr_exit;
	    timeoutCount = 0;
	}
    }
    (*s2)->dataSize = info.read_count;

 normal_exit:
    err = SNDRelease(SND_ACCESS_DSP,dev_port,owner_port);
    return err;
 kerr_exit:
    (*s2)->dataSize = info.read_count;
    SNDRelease(SND_ACCESS_DSP,dev_port,owner_port);
#ifdef DEBUG
    fprintf(stderr,"compress.c: exiting on kernel error %d\n",err);
#endif
    return SND_ERR_KERNEL;
 err_exit:
    (*s2)->dataSize = info.read_count;
    SNDRelease(SND_ACCESS_DSP,dev_port,owner_port);
    return err;

/* --------------------- No DSP: Call Replacement Versions ---------------- */
    
 no_dsp:
     /* DSP not available. Do it in C. */

#ifdef DEBUG
    fprintf(stderr, "\nCalling black-box thread for method %d\n",
	    comprType);
#endif
    /*
     * Thread function
     */
    switch(comprType) {
    case SND_CFORMAT_BITS_DROPPED:
    case SND_CFORMAT_BIT_FAITHFUL:
	thread_func = (info.mode == MODE_DECOMPRESS ?
		       _snd_old_decompression_thread :
		       _snd_old_compression_thread);
	break;
    case SND_CFORMAT_ATC:
	thread_func = (info.mode == MODE_DECOMPRESS ?
		       _snd_atd_thread :
		       _snd_atc_thread);
	break;
    }

    /*
     * Thread arguments
     */
  {
      thread_args targs;

      targs.inPtr = (short *)(((char *)s1)+s1->dataLocation);
      targs.outPtr = (short *)(((char *)(*s2))+(*s2)->dataLocation);
      targs.inBlockSize = s1->dataSize;
      targs.outBlockSize	/* round up to next multiple of frame size */
	= ((int)((subheader->originalSize-1)/ATC_FRAME_SIZE)+1)*ATC_FRAME_SIZE;
      /* Note: since vm_allocate() always allocates whole pages, and since
	 ATC_FRAME_SIZE is a power of 2 less than one page, rounding up cannot
	 overflow the allocated output buffer. */
      targs.outBlockSizeMax = targs.outBlockSize;
      targs.sound = s1;
      targs.makeMono = 0;
      targs.rateShift = 0;
      if (info.mode == MODE_COMPRESS && comprType != SND_CFORMAT_ATC) {
	  dspcinfo[0] = comprType;
	  dspcinfo[1] = subheader->numDropped;
	  dspcinfo[2] = subheader->encodeLength;
	  dspcinfo[3] = s1->channelCount;
	  targs.parameters = dspcinfo;
      } else targs.parameters = 0;
      targs.firstBlock = TRUE;
      targs.lastBlock = TRUE;
      targs.discontiguous = FALSE;
      
      err = (*thread_func)(&targs);		/* viola! */

      if (info.mode == MODE_DECOMPRESS) {
	  if (targs.outBlockSize < subheader->originalSize) {
#ifdef DEBUG
	      fprintf(stderr,"compress.c: ATC decompression returned %d bytes "
		      "while original size is %d bytes\n",targs.outBlockSize,
		      subheader->originalSize);
#endif
	      /* FIXME: this seems to happen often in the stereo case */
	      (*s2)->dataSize = targs.outBlockSize;
	  } else {
	      (*s2)->dataSize = subheader->originalSize;
	  }
      } else {
	  (*s2)->dataSize = targs.outBlockSize;
      }
  }
    if (err)
      goto err_exit;
    info.read_count = info.remaining_bytes;
    info.remaining_bytes = 0;
    info.read_done = 1;
    return SND_ERR_NONE;
}
