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
#import <stdio.h>
#import <SoundKit/sound.h>

void check_error(int err) {
    if (err) {
	fprintf(stderr, "sound error (%d): %s\n", err, SNDSoundError(err));
	exit(1);
    }
}

void main(int argc, char **argv)
{
    int err;
    SNDSoundStruct *sound;
    char *data;
    int size, width;

    if (argc < 3) {
	fprintf(stderr, "usage: swaptest {infile outfile}\n");
	exit(1);
    }

    err = SNDReadSoundfile(argv[1], &sound);
    check_error(err);

    err = SNDGetDataPointer(sound, &data, &size, &width);
    check_error(err);

    printf("in   bytes: 0x%x 0x%x 0x%x 0x%x\n",
	   data[8]&0xff, data[9]&0xff, data[10]&0xff, data[11]&0xff);

    err = SNDSwapSoundToHost(data, data, SNDSampleCount(sound),
			     sound->channelCount, sound->dataFormat);
    check_error(err);

    // bogus for float and double
    printf("host bytes: 0x%x 0x%x 0x%x 0x%x\n",
	   data[8]&0xff, data[9]&0xff, data[10]&0xff, data[11]&0xff);

    err = SNDSwapHostToSound(data, data, SNDSampleCount(sound),
			     sound->channelCount, sound->dataFormat);
    check_error(err);

    printf("out  bytes: 0x%x 0x%x 0x%x 0x%x\n",
	   data[8]&0xff, data[9]&0xff, data[10]&0xff, data[11]&0xff);

    err = SNDWriteSoundfile(argv[2], sound);
    check_error(err);
}


#if 0
// version that uses different memory for copy.
void main(int argc, char **argv)
{
    int err;
    SNDSoundStruct *in, *host, *out;
    char *inPtr, *hostPtr, *outPtr;
    int size, width;

    if (argc < 3) {
	fprintf(stderr, "usage: swaptest {infile outfile}\n");
	exit(1);
    }

    err = SNDReadSoundfile(argv[1], &in);
    check_error(err);

    err = SNDCopySound(&host, in);
    check_error(err);
    err = SNDCopySound(&out, in);
    check_error(err);

    err = SNDGetDataPointer(in, &inPtr, &size, &width);
    check_error(err);
    err = SNDGetDataPointer(host, &hostPtr, &size, &width);
    check_error(err);
    err = SNDGetDataPointer(out, &outPtr, &size, &width);
    check_error(err);

    printf("in   bytes: 0x%x 0x%x 0x%x 0x%x\n",
	   inPtr[8]&0xff, inPtr[9]&0xff, inPtr[10]&0xff, inPtr[11]&0xff);

    err = SNDSwapSoundToHost(hostPtr, inPtr, SNDSampleCount(in),
			     in->channelCount, in->dataFormat);
    check_error(err);

    printf("host bytes: 0x%x 0x%x 0x%x 0x%x\n",
	   hostPtr[8]&0xff, hostPtr[9]&0xff, hostPtr[10]&0xff,
	   hostPtr[11]&0xff);

    err = SNDSwapHostToSound(outPtr, hostPtr, SNDSampleCount(host),
			     host->channelCount, host->dataFormat);
    check_error(err);

    printf("out  bytes: 0x%x 0x%x 0x%x 0x%x\n",
	   outPtr[8]&0xff, outPtr[9]&0xff, outPtr[10]&0xff, outPtr[11]&0xff);

    err = SNDWriteSoundfile(argv[2], out);
    check_error(err);
}
#endif
