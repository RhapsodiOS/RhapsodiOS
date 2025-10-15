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
 * parplay.c
 *    Play back a soundfile compressed with parpak.  Simulates what sndplay
 *    will do.
 *
 *    Usage: parplay [-t] <soundfile>
 *
 *	-t	Timestamp decompression and display results
 */
 
#import <stdio.h>
#import <stdlib.h>
#import <strings.h>
#import <SoundKit/sound.h>
#import <sys/time_stamp.h>
#import "parlib.h"

// This doesn't appear to be in any system header file
kern_return_t kern_timestamp(struct tsval *tsp);

main(int argc, char *argv[])
{
    SNDSoundStruct *inSound;
    int serr, stampTimes = FALSE;
    FILE *soundfp;
    char *soundfile;
    unsigned timeStamp;
    struct tsval timeStruct;
    
    if (argc == 3) {
        if (strcmp(argv[1], "-t") != 0) {
            fprintf(stderr, "Usage: %s [-t] <soundfile>\n", argv[0]);
	    exit(1);
	}
	stampTimes = TRUE;
	soundfile = argv[2];
    } else if (argc == 2) {
        soundfile = argv[1];
    } else {
	fprintf(stderr, "Usage: %s [-t] <soundfile>\n", argv[0]);
	exit(1);
    }
    if ((soundfp = fopen(soundfile, "r")) == NULL) {
        fprintf(stderr, "%s: Cannot open soundfile: %s\n", argv[0], soundfile);
	exit(1);
    }
    
    // Uncompress and read in the soundfile
    if (stampTimes) {
        kern_timestamp(&timeStruct);
	timeStamp = timeStruct.low_val;
    }
    if (unparpack(soundfp, &inSound) == -1) {
        fprintf(stderr, "%s: Cannot decompress soundfile: %s\n", argv[0], soundfile);
	exit(1);
    }
    if (stampTimes)
        kern_timestamp(&timeStruct);
    
    // Play the uncompressed sound
    if (serr = SNDStartPlaying(inSound, 0, 0, 0, SND_NULL_FUN, SND_NULL_FUN)) {
	fprintf(stderr, "%s: %s\n", argv[0], SNDSoundError(serr));
	exit(1);
    }
    SNDWait(0);
    
    if (stampTimes)
	printf("Decompression time: %f seconds\n",
	       ((float)(timeStruct.low_val - timeStamp)) / 1000000.0);
}

