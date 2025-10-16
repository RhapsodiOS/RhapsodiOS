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
 * unparpack.c
 *    Decompress a soundfile coded using Richard Crandall's
 *    "Parallel Stream Compression" algorithms to a 16-bit, linear soundfile.
 *
 *    Usage: unparpack infile outfile
 *
 *    infile must be a soundfile with format code SND_FORMAT_COMPRESSED.
 */
 
#import <stdio.h>
#import <stdlib.h>
#import <SoundKit/sound.h>
#import "parlib.h"

main(int argc, char *argv[])
{
    SNDSoundStruct *inSound;
    int serr;
    FILE *infp;
    
    if (argc != 3) {
        fprintf(stderr, "Usage: %s infile outfile\n", argv[0]);
	exit(1);
    }
    if ((infp = fopen(argv[1], "r")) == NULL) {
        fprintf(stderr, "%s: Cannot open input file %s\n", argv[0], argv[1]);
	exit(1);
    }
    
    // Decompress
    if (unparpack(infp, &inSound) == -1) {
        fprintf(stderr, "%s: Cannot decompress sound\n", argv[0]);
	exit(1);
    }
    fclose(infp);
    
    // Write the decompressed soundfile
    if (serr = SNDWriteSoundfile(argv[2], inSound)) {
	fprintf(stderr, "%s: Cannot write output file %s\n", argv[0], argv[2]);
	fprintf(stderr, "%s: %s\n", argv[0], SNDSoundError(serr));
	exit(1);
    }
}


