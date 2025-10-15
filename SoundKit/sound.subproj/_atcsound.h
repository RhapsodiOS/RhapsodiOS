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
 * Constants pertaining to Audio Transform Compression (ATC)
 */

#import "atcsound.h"
#import "atc_c/atc.h"
#import <c.h>

#define ATC_DMA_BUFFER_SIZE (1024)
#define ATC_CTHREAD_BUFFER_SIZE (8192)
#define ATC_MAX_GAIN (16.0)

/* The following must stay in synch with the relevant atc.h constants */
#define ATC_MAX_COMPRESSED_FRAME_SIZE (182)	/* (16+40*4+256+256*4)/8 */

/* The following can obviously go away */
#define ATC_TRANSFORM_SIZE FRAME_SIZE /* atc.h (512 is likely) */
#define ATC_NBANDS 40 		/* Must stay in synch with NCB in cb.h */

static inline void floatToDSPFix24(int n, float *f, int *d)
{
    int i;
    for (i=0;i<n;i++)
      d[i] = MIN(((1<<23)-1),(int)(f[i] * ((float)(1<<23))));
}

#define FLOAT_TO_UNSIGNED_DSPFIX24(x) (MIN(((1<<24)-1),(int)((x)*((float)(1<<24)))))

static inline void floatToUnsignedDSPFix24(int n, float *f, int *d)
{
    int i;
    for (i=0;i<n;i++)
      d[i] = MIN(((1<<24)-1),(int)(f[i] * ((float)(1<<24))));
}

float *_SNDGetATCEGP(void);
float *_SNDGetATCSTP(void);
