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
/* private makefile for compression */

/*
 * Define compression block sizes.
 * The maximum compression ratio at present is 256, and it occurs 
 * in the ATC compression format for silent frames.  (Each 256-sample
 * frame is represented as a single short.)  Therefore, the output block
 * size must be at least 256 times the input block size.  These
 * sizes are used by performsound.c and convertsound.c (cf. compress.c).
 * They are the sizes of the regions enqueued (not the DMA buffer size,
 * which cannot exceed one page).
 */

#define DECOMPRESSION_IN_BLOCK_SIZE 8192
#define DECOMPRESSION_OUT_BLOCK_SIZE (256 * DECOMPRESSION_IN_BLOCK_SIZE \
				      + ATC_FRAME_SIZE)
/* The extra frame is to provide room for overlap-add. See black_boxes.c. */

/* DSP DMA buffer size in 16-bit words for all compression types. */
#define	COMPRESS_DMASIZE 2048	/* Used in compress.c.
				   Must be compatible with 
				   hostdecompress.asm,
				   hostcompress.asm,
				   hostdecompressatc.asm, and 
				   hostcompressatc.asm. */

#define	PARPACK_ENCODE_LENGTH 256 /* Samples/channel. Used in compress.c */

typedef struct {
    int	mode;			/* MODE_COMPRESS or MODE_DECOMPRESS */
    char *read_ptr;		/* running pointer through input data */
    int read_count;		/* number of bytes read up to now */
    int	remaining_bytes;	/* number of bytes left to read */
    int read_done;
    char *block_ptr;		/* only used by bit-faithful and drop-bits */
    int block_count;		/* only used by bit-faithful and drop-bits */
    SNDCompressionSubheader subheader;
    int sound_header_size;
    port_t cmd_port;		/* Sound/DSP driver Mach ports */
    port_t read_port;
    port_t write_port;
    port_t reply_port;
    int aborted;
    int timeout;
} compress_info_t;

typedef struct {
    short *inPtr;
    short *outPtr;
    int inBlockSize;		/* bytes */
    int outBlockSize;
    int outBlockSizeMax;
    SNDSoundStruct *sound;
    int makeMono;
    int rateShift;
    void *parameters;
    boolean_t firstBlock;	/* TRUE on first call */
    boolean_t lastBlock;	/* TRUE on last call, if known */
    boolean_t discontiguous;	/* TRUE if inPtr != inPtrPrev + inBlockSize */
} thread_args;

/* Parallel micro-algorithm codes */
enum {
    NULL_ENCODE,
    XOR_ENCODE,
    D1_ENCODE,
    D2_ENCODE,
    D3_ENCODE,
    D4_ENCODE,
    D3_11_ENCODE,
    D3_22_ENCODE,
    D4_222_ENCODE,
    D4_343_ENCODE,
    D4_101_ENCODE,
    NUM_ENCODES
    };

static int bytesInBlock(int code, int numBits, int encodeLength)
//  Returns the number of bytes required to encode a block using numBits per sample.
{
    int tokenbytes=0, packshorts=0;
    
    switch (code) {
	case NULL_ENCODE: tokenbytes = 0; packshorts = encodeLength; break;
	case XOR_ENCODE: tokenbytes = 2; packshorts = encodeLength-1; break;
	case D1_ENCODE: tokenbytes = 2; packshorts = encodeLength-1; break;
	case D2_ENCODE: tokenbytes = 4; packshorts = encodeLength-2; break;
	case D3_ENCODE: tokenbytes = 6; packshorts = encodeLength-3; break;
	case D4_ENCODE: tokenbytes = 8; packshorts = encodeLength-4; break;
	case D3_11_ENCODE: tokenbytes = 6; packshorts = encodeLength-3; break;
	case D3_22_ENCODE: tokenbytes = 6; packshorts = encodeLength-3; break;
	case D4_222_ENCODE: tokenbytes = 8; packshorts = encodeLength-4; break;
	case D4_343_ENCODE: tokenbytes = 8; packshorts = encodeLength-4; break;
	case D4_101_ENCODE: tokenbytes = 8; packshorts = encodeLength-4; break;
    }
    return(tokenbytes + (numBits*packshorts+7)/8);
}
