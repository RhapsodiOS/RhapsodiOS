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
 * parpack.c
 *    Compress a 16 bit, linear soundfile using Richard Crandall's
 *    "Parallel Stream Compression" algorithms.  Supports any number of
 *    channels.
 *
 *    Usage: parpack [-{4..8}bdmsv] infile outfile
 *
 *	-{4..8} Number of least significant bits to drop before compressing, default 4
 *	-b      Bit-faithful, save dropped bits for exact decompression
 *	-d      Down-sample 44.1KHz to 22.5KHz before compressing
 *	-m      Convert multi-channel (e.g. stereo) to mono before compressing
 *	-s      Suppress compression (down-sample and/or convert to mono only)
 *	-v      Verbose, display algorithms statistics
 *
 *    Outfile is written with header dataFormat SND_FORMAT_COMPRESSED.
 */
 
#import <stdio.h>
#import <stdlib.h>
#import <SoundKit/sound.h>
#import "parlib.h"

static char *programName;	// For error messages

static void usage(void)
//  Display usage message to stderr
{
    fprintf(stderr, "Usage: %s [-{4..8}bdmsv] infile outfile\n", programName);
    fprintf(stderr, "       -{4..8} Number of least significant bits\n");
    fprintf(stderr, "               to drop before compressing, default 4\n");
    fprintf(stderr, "       -b      Bit-faithful, save dropped bits\n");
    fprintf(stderr, "               for exact decompression\n");
    fprintf(stderr, "       -d      Down-sample 44.1KHz to 22.5KHz\n");
    fprintf(stderr, "               before compressing\n");
    fprintf(stderr, "       -m      Convert multi-channel (e.g. stereo)\n");
    fprintf(stderr, "               to mono before compressing\n");
    fprintf(stderr, "       -s      Suppress compression (down-sample\n");
    fprintf(stderr, "               and/or convert to mono only)\n");
    fprintf(stderr, "       -v      Verbose, display algorithms statistics\n");
}

static void convertToMono(SNDSoundStruct **multiSound)
//  Convert a 16-bit linear multi-channel sound to mono by mixing (averaging) samples.
//  multiSound is reallocated as needed.
{
    SNDSoundStruct *monoSound;
    int channelCount, sampleCount, serr, i, j;
    short *multiData, *monoData;
    int aSample;
    
    if ((channelCount = (*multiSound)->channelCount) != 1) {
        sampleCount = ((*multiSound)->dataSize / sizeof(short)) / channelCount;
        if (serr = SNDAlloc(&monoSound, sampleCount * sizeof(short),
                            SND_FORMAT_LINEAR_16, (*multiSound)->samplingRate,
			    1, 4)) {
	    fprintf(stderr, "%s: %s\n", programName, SNDSoundError(serr));
	    exit(1);
	}
	multiData = (short *) (((char *)(*multiSound)) + (*multiSound)->dataLocation);
	monoData = (short *) (((char *)monoSound) + monoSound->dataLocation);
	for (i = 0; i < sampleCount; i++) {
	    aSample = 0;
	    for (j = 0; j < channelCount; j++)
		aSample += *multiData++;
	    aSample += aSample & 1;		// Round up if odd
	    *monoData++ = aSample / channelCount;
	}
	*multiSound = monoSound;
    }
}

static void convertTo22K(SNDSoundStruct **highSound)
//  Convert 16-bit linear 44.1KHz to 16-bit linear 22.5KHz.
//  highSound is reallocated as needed.
//  Each sample is multiplied by 0.6 to make up for the amplitude boost
//  applied by SNDConvertSound().
{
    SNDSoundStruct *lowSound;
    int serr, i;
    short *data;
    
    if ((*highSound)->samplingRate != SND_RATE_LOW) {
        if (serr = SNDAlloc(&lowSound, 0, SND_FORMAT_LINEAR_16,
                            SND_RATE_LOW, (*highSound)->channelCount, 4)) {
	    fprintf(stderr, "%s: %s\n", programName, SNDSoundError(serr));
	    exit(1);
	}
	// De-boost amplitude
	data = (short *) ((char *)*highSound + (*highSound)->dataLocation);
	for (i = 0; i < (*highSound)->dataSize / sizeof(short); i++)
	    data[i] = (short) (0.6 * (float)data[i]);
	    
	if (serr = SNDConvertSound(*highSound, &lowSound)) {
	    fprintf(stderr, "%s: %s\n", programName, SNDSoundError(serr));
	    exit(1);
	}
        SNDFree(*highSound);
        *highSound = lowSound;
    }
}
    
main(int argc, char *argv[])
{
    SNDSoundStruct *inSound;
    int bitFaithful = FALSE, verbose = FALSE;
    int makeMono = FALSE, downSample = FALSE;
    int suppressCompression = FALSE;
    char *infile, *outfile, *s;
    int serr, dropBits = 4;
    FILE *outfp;
    
    // Get options
    programName = argv[0];
    while (--argc > 0 && (*++argv)[0] == '-')
        for (s = argv[0]+1; *s != '\0'; s++)
	    switch (*s) {
	        case '4': case '5': case '6': case '7': case '8':
		    dropBits = *s - '0';
		    break;
	        case 'b':
		    bitFaithful = TRUE;
		    break;
	        case 'd':
		    downSample = TRUE;
		    break;
	        case 'm':
		    makeMono = TRUE;
		    break;
	        case 's':
		    suppressCompression = TRUE;
		    break;
		case 'v':
		    verbose = TRUE;
		    break;
		default:
        	    fprintf(stderr, "%s: illegal option %c\n", programName, *s);
		    usage();
		    exit(1);
		    break;
		}
    if (argc != 2) {
        usage();
	exit(1);
    } else {
        infile = argv[0];
	outfile = argv[1];
	if (!suppressCompression)
	    if ((outfp = fopen(outfile, "w")) == NULL) {
		fprintf(stderr, "%s: Cannot open output file %s\n", programName,
			        outfile);
		exit(1);
	    }
    }
    
    // Read in the uncompressed soundfile
    if (serr = SNDReadSoundfile(infile, &inSound)) {
        fprintf(stderr, "%s: Cannot read input file %s\n", programName, infile);
	fprintf(stderr, "%s: %s\n", programName, SNDSoundError(serr));
	exit(1);
    }
    if (inSound->dataFormat != SND_FORMAT_LINEAR_16) {
        fprintf(stderr, "%s: Only SND_FORMAT_LINEAR_16 is supported\n", programName);
	exit(1);
    }
    
    // Convert to mono and down-sample if requested
    if (makeMono)
        convertToMono(&inSound);
    if (downSample)
        convertTo22K(&inSound);
	
    // Compress and write soundfile
    if (!suppressCompression) {
        parDropBits(dropBits);
	parVerbose(verbose);
	if (parpack(outfp, inSound, bitFaithful) == -1) {
            fprintf(stderr, "%s: Cannot compress sound\n", programName);
	    exit(1);
	}
    } else if (makeMono || convertTo22K) {
	if (serr = SNDWriteSoundfile(outfile, inSound)) {
            fprintf(stderr, "%s: Cannot write output file %s\n", programName, outfile);
	    fprintf(stderr, "%s: %s\n", programName, SNDSoundError(serr));
	    exit(1);
	}
    }
}
