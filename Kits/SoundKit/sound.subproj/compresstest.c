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
 * compresstest.c
 *	Usage: compresstest [-<n>] <infile> <outfile>
 *	If <infile> sound is in a linear format, it is ATC compressed.
 *	If <infile> sound is in a compressed format, it is decompressed.
 *	<n> is the number of bits to drop, 4-8, and implies non-bit-faithful.
 *	If <n> is 0, bit-faithful format is used.
 */
#import "sound.h"

static void usage(void)
{
    printf("usage : compresstest [-<n>] [-l] <inputFile> <outputFile>\n"
"\tIf <inputFile> is in a 16 bit linear format, it is compressed.\n"
"\tIf <inputFile> is in a compressed format, it is decompressed.\n"
"\t<n> controls the compression amount, specify as an integer 4 <= n <= 8.\n"
"\tHigher numbers give greater compression.  If <n> not specified,\n"
"\tAudio Transform Compression (ATC) is used.\n"
"\tThe -l option specifies lossless, or bit-faithful, compression.\n"
"\tThe -n option cannot be used in the lossless case.\n"
"\tDecompression of the lossless format will reproduce the original\n"
"\tsound exactly.\n");
    exit(1);
}

int check_error(int err)
{
    if (err) {
	printf("Error : %d, %s\n",err,SNDSoundError(err));
	exit(1);
    }
    return err;
}

main (int argc, char *argv[])
{
    int err;
    SNDSoundStruct *s1, *s2;
    char *infile, *outfile;
    int dropBits = 0;
    int compressionType = SND_CFORMAT_ATC;

    if (argc < 3 || argc > 4)
      usage();
    if (argc == 4) {
	if ((strlen(argv[1]) != 2) || *argv[1] != '-')
	    usage();
	if (*(argv[1]+1) == 'l')
	  compressionType = SND_CFORMAT_BIT_FAITHFUL;
	else {
	    dropBits = atoi(argv[1]+1);
	    if (dropBits < 4 || dropBits > 8)
	      usage();
	    compressionType = SND_CFORMAT_BITS_DROPPED;
	}
	infile = argv[2];
	outfile = argv[3];
    } else {
	infile = argv[1];
	outfile = argv[2];
    }
    
    err = SNDReadSoundfile(infile, &s1);
    check_error(err);
    err = SNDCompressSound(s1, &s2, compressionType, dropBits);
    check_error(err);
    err = SNDWriteSoundfile(outfile, s2);
    check_error(err);
    exit(0);
}
