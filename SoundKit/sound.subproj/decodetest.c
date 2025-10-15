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
 * test jig for decoding run-length encoded data into 8 khz codec data 
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

main (int argc, char *argv[])
{
    int err;
    SNDSoundStruct *s1, *s2;
    SNDSoundStruct s3 = {
	SND_MAGIC, 0, 0, 
	SND_FORMAT_MULAW_8, (int)SND_RATE_CODEC, 1, "" };

    check_error(argc != 3);
    
    printf("converting file %s\n",argv[1]);
    err = SNDReadSoundfile(argv[1],&s1);
    check_error(err);
    s2 = &s3;
    err = SNDConvertSound(s1,&s2);
    check_error(err);
    err = SNDWriteSoundfile(argv[2],s2);
    check_error(err);
    exit(0);
}


