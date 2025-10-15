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


#import "sound.h"

#define BUF_SIZE 8192
#define BUF_MAX 8

static char *target_host;
static int buf_ptr, buf_max;
static SNDSoundStruct *buffers[BUF_MAX+1];

int begin(SNDSoundStruct *s, int tag, int err)
{
    printf("started recording buffer %d\n",tag);
}

int end(SNDSoundStruct *s, int tag, int err)
{
    if (err) printf("error while recording %d\n",tag);
    printf("completed recording buffer %d\n",tag);
    if (buf_ptr < buf_max) {
	err = SNDStartRecording(buffers[buf_ptr], buf_ptr, 5,0,begin,end);
	if (err) printf("cannot start recording %d\n",buf_ptr);
	buf_ptr++;
    }
}

main (int argc, char *argv[])
{
    int size, err, i, j;
    int x = 0;

    if (argc < 2) {
	printf("usage: chaintest file ...\n");
	exit(0);
    }
    for (j=1; j<argc; j++) {
	err = SNDAlloc(&buffers[j],BUF_SIZE,SND_FORMAT_MULAW_8,
							SND_RATE_CODEC,1,0);
	check_error(err);
    }
    buf_ptr = 3;
    buf_max = argc;
    printf("recording...\n");
    err = SNDStartRecording(buffers[1],1,2,0,begin,end);
    check_error(err);
    err = SNDStartRecording(buffers[2],2,2,0,begin,end);
    check_error(err);
    SNDWait(0);
    printf("writing...\n");
    for (j=1; j<argc; j++) {
	err = SNDWriteSoundfile(argv[j],buffers[j]);
	if (err) printf("cannot write file %s...\n", argv[j]);
    }
    exit(0);
}

check_error(int err)
{
    if (err) {
	printf("Error : %s\n",SNDSoundError(err));
	exit(1);
    }
    return err;
}



