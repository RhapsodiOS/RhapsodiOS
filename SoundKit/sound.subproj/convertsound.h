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
 *	convertsound.h
 *	Copyright 1988-89 NeXT, Inc.
 *
 */

#import "soundstruct.h"
#import "sounderror.h"

unsigned char SNDMulaw(short n);
short SNDiMulaw(unsigned char m);
/*
 * Routines to convert from 8 bit mulaw sound to/from 16 linear sound.
 * SNDMulaw returns the mulaw value for the given 16 bit linear value,
 * and SNDiMulaw returns the 16 bit linear value for the given mulaw value.
 */

int SNDConvertSound(SNDSoundStruct *s1, SNDSoundStruct **s2);
/*
 * Routine to convert the sound specified by s1 into a new sound designated
 * by the header s2, which identifies the resultant data format, channel count,
 * and sampling rate. If the dataSize in s2 is non-zero, then the s2's data 
 * contains optional arguments for the conversion (these arguments are
 * conversion-specific). A new SNDSoundStruct is created which contains the
 * converted sound, and s2 is set to point at it. An error code is returned.
 */

int SNDRunDSP(SNDSoundStruct *core,
		  char *write_ptr,
		  int write_count,
		  int write_width,
		  int write_buf_size,
		  char **read_ptr,
		  int *read_count,
		  int read_width,
		  int negotiation_timeout,
		  int flush_timeout,
		  int conversion_timeout);
/*
 * This generic routine runs the DSP program represented by core, streaming
 * the specified input data to it, and collecting the output data into a
 * buffer that is returned in read_ptr, with a size returned in read_size.
 * The dsp program should implement the 'Complex DMA mode' in its output.
 * See /NextDeveloper/Examples/DSP/SoundDSPDriver for examples.
 */

int SNDCompressSound(SNDSoundStruct *s1, SNDSoundStruct **s2,
		     int compressionType, int dropBits);
/*
 * If the data format of sound s1 is SND_FORMAT_COMPRESSED
 * or SND_FORMAT_COMPRESSED_EMPHASIZED, the sound
 * is decompressed into s2.  If s1 is SND_FORMAT_LINEAR_16 or 
 * SND_FORMAT_EMPHASIZED, the sound is compressed into s2.
 * The compressionType and dropBits parameters are used when compressing.
 * There are currently three compress formats supported by NeXT system
 * software:
 *   SND_CFORMAT_BITS_DROPPED	- low bits removed for lossy compression
 *   SND_CFORMAT_BIT_FAITHFUL	- lossless compression
 *   SND_CFORMAT_ATC  	        - audio transform compression (lossy)
 * (constants defined in /usr/include/sound/soundstructs.h).
 * If the compression is lossless,
 * the recorded sound can be decompressed exactly back to its original samples.
 * Otherwise the decompressed sound will have some degradation.  The dropBits
 * parameter specifies the number of bits to right shift off of each sample
 * before compressing for the dropped-bits compression type.  DropBits
 * ranges from 4 to 8 bits, with higher numbers giving more compression 
 * but less fidelity.  A typical value is 4.  In bit faithful mode, dropBits
 * may affect the amount of compression, but decompression will still be
 * exact.  For type ATC, dropBits has no effect at present, but in the 
 * future it may affect the compression quality such that dropBits = 0 
 * gives maximum quality, and dropBits = 8 would give maximum compression.
 * CompressionType defaults to SND_CFORMAT_ATC and dropBits defaults to 0.
 * A new SNDSoundStruct is created which contains the converted sound, and
 * s2 is set to point at it. An error code is returned.
 */

