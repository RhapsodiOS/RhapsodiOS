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
 * playtest.c
 *
 *	Modification History:
 *	04/16/90/mtm	Added -d switch.
 */

#import "sound.h"

main (int argc, char *argv[])
{
    int size, err, i;
    SNDSoundStruct *s;
    int playDSP = FALSE;
    int startArg = 1;

    if (argc < 2) {
	printf("usage : playtest [-d] file ...\n");
	exit(0);
    }
    if (strcmp(argv[1],"-d") == 0) {
	if (argc < 3) {
	    printf("usage : playtest [-d] file ...\n");
	    exit(0);
	}
        playDSP = TRUE;
	startArg = 2;
    }
    for (i=startArg; i<argc; i++) {
	err = SNDReadSoundfile(argv[i],&s);
	if (err)
	    printf("playtest : Cannot read soundfile : %s\n",argv[i]);
	else {
	    if (playDSP)
	        err = SNDStartPlayingDSP(s,i,2,0,0,(SNDNotificationFun)SNDFree,
		/* SND_DSP_RECEIVE_CLOCK/*| SND_DSP_RECEIVE_FRAME_SYNC*/
					 0);
	    else
	        err = SNDStartPlaying(s,i,2,0,0,(SNDNotificationFun)SNDFree);
	    if (err)
		printf("playtest : Cannot play soundfile : %s\n",argv[i]);
	}
    }
    SNDWait(0);
    exit(0);
}


