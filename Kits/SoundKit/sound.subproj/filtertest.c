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
 * filtertest.c - Lowpass filter test
 *	Try playing emphasized and non-emphasized sounds.
 */

#import "sound.h"

main (int argc, char *argv[])
{
    int err, i;
    SNDSoundStruct *s;
    int filterStatus;

    if (argc < 2) {
	printf("usage : filtertest file ...\n");
	exit(0);
    }
    
    err = SNDGetFilter(&filterStatus);
    if (err)
        printf("SNDGetFilter() returned %d\n", err);
    printf("Filter status: %d\n", filterStatus);

    printf("Turning filter on...\n");
    err = SNDSetFilter(1);
    if (err)
        printf("SNDSetFilter(1) returned %d\n", err);
    err = SNDGetFilter(&filterStatus);
    if (err)
        printf("SNDGetFilter() returned %d\n", err);
    printf("Filter status: %d\n", filterStatus);

    printf("Turning filter off...\n");
    err = SNDSetFilter(0);
    if (err)
        printf("SNDSetFilter(0) returned %d\n", err);
    err = SNDGetFilter(&filterStatus);
    if (err)
        printf("SNDGetFilter() returned %d\n", err);
    printf("Filter status: %d\n", filterStatus);

    for (i=1; i<argc; i++) {
	err = SNDReadSoundfile(argv[i],&s);
	if (err)
	    printf("filtertest : Cannot read soundfile : %s\n",argv[i]);
	else {
	    err = SNDStartPlaying(s,i,2,0,0,(SNDNotificationFun)SNDFree);
	    if (err)
		printf("filtertest : Cannot play soundfile : %s\n",argv[i]);
	}
    }
    SNDWait(0);
    
    printf("Done playing sound\n");
    err = SNDGetFilter(&filterStatus);
    if (err)
        printf("SNDGetFilter() returned %d\n", err);
    printf("Filter status: %d\n", filterStatus);
    exit(0);
}


