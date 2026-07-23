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
 *	filesound.h
 *	Copyright 1988-89 NeXT, Inc.
 *
 */

#import "soundstruct.h"
#import "sounderror.h"

int SNDReadSoundfile(char *path, SNDSoundStruct **s);
int SNDRead(int fd, SNDSoundStruct **s);
/*
 * Read the specified file, setting "s" to point at the newly allocated 
 * SNDSoundStruct. SNDRead takes a unix file descriptor, whereas 
 * SNDReadSoundfile takes a complete unix pathname; the two routines are 
 * otherwise identical.
 * An error code is returned; if an error occurs, "s" is undefined.
 * If there is no error, the "s" is set and should eventually be deallocated 
 * with SNDFree().
 */

int SNDWriteSoundfile(char *path, SNDSoundStruct *s);
int SNDWrite(int fd, SNDSoundStruct *s);
/*
 * Write the specified file to contain "s". SNDWrite takes a unix
 * file descriptor to specify the file, whereas SNDWriteSoundfile takes
 * a complete pathname; the two routines are otherwise identical.
 * If the sound is fragmented from editing, it is written out in a
 * non-fragmented manner (the next read of the file will result in a
 * non-fragmented sound).
 * An error code is returned.
 */

int SNDReadHeader(int fd, SNDSoundStruct **s);
/*
 * Read the header portion of the specified file descriptor, setting "s"
 * to point at the newly allocated SNDSoundStruct.
 * The structure will have no raw data, though the dataLocation field
 * will be contain the offset to it as if it were there (this defines the 
 * extent of the header). An error code is returned and, if nonzero, "s" is
 * set to nil.
 * If there is no error, the "s" is set and should eventually be deallocated 
 * with SNDFree().
 */

int SNDWriteHeader(int fd, SNDSoundStruct *s);
/*
 * Write the header implied by "s" to the already opened file descriptor.
 * An error code is returned.
 */

int SNDReadDSPfile(char *path, SNDSoundStruct **s, char *info);
/*
 * Parse a Motorola load file (".lod" extension), and create a sound structure
 * to correspond to it. The info string (optionally null) is put into the
 * header.
 */


