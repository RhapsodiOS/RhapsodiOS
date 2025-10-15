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
 * rfiletest.c
 *	Test SNDStartRecordingFile().
 * 	Usage:  rfiletest [options...] seconds file ...
 *      Options:
 *	none	record from codec
 * 	-d	record from dsp
 * 	-2	record from dsp at 22K mono
 * 	-c	record from dsp compressed
 *	-2c	record from dsp compressed at 22K mono
 * 	-b	record from dsp compressed, bit faithful
 */
#import "sound.h"

#define	SECONDS	5.0
#define USAGE "Usage: rfiletest [-d | -2 | -c | -2c | -b] seconds file\n"

main (int argc, char *argv[])
{
    SNDSoundStruct *s;
    int err;
    int startArg = 1;
    int dspData = FALSE;
    int compress = FALSE;
    int bitfaithful = FALSE;
    int mono22 = FALSE;
    float seconds;

    if (argc < 3) {
	printf(USAGE);
	exit(1);
    }
    if ((strcmp(argv[1],"-d") == 0) || (strcmp(argv[1],"-2") == 0)) {
	if (argc < 4) {
	    printf(USAGE);
	    exit(0);
	}
        dspData = TRUE;
	if (strcmp(argv[1],"-2") == 0)
	    mono22 = TRUE;
	startArg = 2;
    } else if ((strcmp(argv[1],"-c") == 0) || (strcmp(argv[1],"-b") == 0) ||
	       (strcmp(argv[1],"-2c") == 0)) {
	if (argc < 4) {
	    printf(USAGE);
	    exit(0);
	}
        compress = TRUE;
	if (strcmp(argv[1],"-b") == 0)
	    bitfaithful = TRUE;
	else if (strcmp(argv[1],"-2c") == 0)
	    mono22 = TRUE;
	startArg = 2;
    }
    seconds = atof(argv[startArg++]);

    if (dspData) {
	if (mono22)
	    err = SNDAlloc(&s, seconds*SND_RATE_LOW*2,
			   SND_FORMAT_DSP_DATA_16,SND_RATE_LOW,1,0);
	else
	    err = SNDAlloc(&s, seconds*SND_RATE_HIGH*2*2,
			   SND_FORMAT_DSP_DATA_16,SND_RATE_HIGH,2,0);
    } else if (compress) {
	int method,dropBits;
	if (mono22) {
	    err = SNDAlloc(&s, seconds*SND_RATE_LOW*2,
			   SND_FORMAT_COMPRESSED,SND_RATE_LOW,1,0);
	    err = SNDSetCompressionOptions(s,0,4);
	    err = SNDGetCompressionOptions(s,&method,&dropBits);
	} else {
	    err = SNDAlloc(&s, seconds*SND_RATE_HIGH*2*2,
			   SND_FORMAT_COMPRESSED,SND_RATE_HIGH,2,0);
	    err = SNDSetCompressionOptions(s,bitfaithful,4);
	    err = SNDGetCompressionOptions(s,&method,&dropBits);
	}
	printf("Compression options: bitFaithful=%d, dropBits=%d\n",
	       method,dropBits);
    } else
	err = SNDAlloc(&s, seconds*SND_RATE_CODEC,
		       SND_FORMAT_MULAW_8,SND_RATE_CODEC,1,0);
    if (err) printf("cannot allocate space...\n");
    
    printf("recording...\n");
    err = SNDStartRecordingFile(argv[startArg], s, 1, 0, 0, 0, 0);
    if (err)
	printf("%s\n", SNDSoundError(err));
    SNDWait(0);
    SNDFree(s);

    /* FIXME: hack header to SND_FORMAT_LINEAR_16 if dspData */
    exit(0);
}
