/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/**
 * BeepTypes.h - Type definitions for PC speaker sound driver
 */

#ifndef _BEEP_TYPES_H
#define _BEEP_TYPES_H

#import <sys/types.h>

/* ========== Sound Configuration ========== */
typedef struct {
    UInt32          defaultFrequency;   /* Default frequency */
    UInt32          defaultDuration;    /* Default duration */
} SoundConfig;

/* ========== IOKit Return Codes ========== */
/* Extended return codes for sound operations */
#define SOUND_IO_R_SUCCESS       0       /* Success */
#define SOUND_IO_R_BUSY          (-1)    /* Speaker busy */
#define SOUND_IO_R_INVALID_FREQ  (-2)    /* Invalid frequency */
#define SOUND_IO_R_INVALID_DUR   (-3)    /* Invalid duration */
#define SOUND_IO_R_DISABLED      (-4)    /* Sound disabled */

#endif /* _BEEP_TYPES_H */
