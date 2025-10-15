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
 *	editsound.h
 *	Copyright 1988-89 NeXT, Inc.
 *
 */

#import "soundstruct.h"
#import "sounderror.h"

int SNDCopySound(SNDSoundStruct **s1, SNDSoundStruct *s2);
int SNDCopySamples(SNDSoundStruct **s1, SNDSoundStruct *s2,
		   int startSample, int sampleCount);
/*
 * Copy a segment of the sound s2 (specified by offset samples from the
 * beginning and running for count samples), into a newly allocated
 * SNDSoundStruct; s1 is set to point at the new SNDSoundStruct. 
 * The NSDCopySound function copies the entire sound, and works for
 * any type of sound, including dsp sounds.
 * An error code is returned. s2 is unaffected by this operation.
 */

int SNDInsertSamples(SNDSoundStruct *s1, SNDSoundStruct *s2, int startSample);
/*
 * Insert a copy of the sound s2 into the sound s1 at a position specified by 
 * offset. This operation may leave s1 fragmented; s2 is unaffected.
 */

int SNDDeleteSamples(SNDSoundStruct *s, int startSample, int sampleCount);
/*
 * Delete the segment of the sound s specified by startSample samples from 
 * the beginning and running for sampleCount samples. This operation may
 * leave s fragmented. The memory occupied by the segment of sound is freed.
 */

int SNDCompactSamples(SNDSoundStruct **s1, SNDSoundStruct *s2);
/*
 * Create a new sound s1 as a compacted version of the the sound s2.
 * Compaction eliminates the fragmentation caused by
 * insertion and deletion. An error code is returned.
 */


