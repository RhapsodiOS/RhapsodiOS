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

check_error(int err)
{
    if (err) {
	printf("Error : %s\n",SNDSoundError(err));
	exit(1);
    }
    return err;
}

int begin(SNDSoundStruct *s, int tag, int err)
{
    printf("begin : %x %d %d\n",s,tag,err);
}

int end(SNDSoundStruct *s, int tag, int err)
{
    printf("end : %x %d %d\n",s,tag,err);
}

main (int argc, char *argv[])
{
    int size, err, j;
    SNDSoundStruct *s, *s2;

    check_error(argc < 2);
    
    for (j=2; j<argc; j++) {		//check that all hosts are available
	err = SNDSetHost(argv[j]);
	check_error(err);
    }

    err = SNDReadSoundfile(argv[1],&s);
    check_error(err);

    for (j=2; j<argc; j++) {
	err = SNDSetHost(argv[j]);
	check_error(err);
	err = SNDStartPlaying(s,j,2,0,begin,end);
	check_error(err);
    }
    SNDWait(0);
    exit(0);
}


