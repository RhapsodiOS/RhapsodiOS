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
 * Beep.h - PC Speaker Sound Driver Interface
 *
 * This driver provides basic sound output functionality using the PC speaker
 * (Intel 8254 PIT Channel 2).
 */

#ifndef _BEEP_H
#define _BEEP_H

#import <driverkit/IOAudio.h>
#import <driverkit/NXSoundParameterTags.h>

/* Beep sequence structure - 16 bytes total */
typedef struct {
    char *name;            /* offset 0 - style name */
    int noteCount;         /* offset 4 - number of notes to play */
    int freqMultiplier;    /* offset 8 - frequency multiplier */
    int freqDivisor;       /* offset 12 - frequency divisor */
} BeepSequence;

@interface Beep : IOAudio
{
@private
    /* Instance variables - actual offsets determined by IOAudio base class */
    /* _pitCommand at offset 0x185 */
    /* _defaultFrequency at offset 0x188 */
    /* _defaultDuration at offset 0x18c */
    /* _beepSequence at offset 0x190 */
    unsigned char _pitCommand;        /* PIT command byte (0xB6) */
    unsigned int _defaultFrequency;   /* Default frequency in Hz */
    unsigned int _defaultDuration;    /* Default duration in ms */
    BeepSequence *_beepSequence;      /* Pointer to beep sequence */
}

/* Initialization and lifecycle */
- initFromDeviceDescription:deviceDescription;
- (BOOL)reset;

/* Sound output */
- (IOReturn)beep;

/* IODevice parameter methods */
- (IOReturn)getIntValues:(unsigned *)parameterArray
            forParameter:(IOParameterName)parameterName
                   count:(unsigned *)count;

- (IOReturn)getCharValues:(unsigned char *)parameterArray
             forParameter:(IOParameterName)parameterName
                    count:(unsigned *)count;

- (IOReturn)setIntValues:(unsigned *)parameterArray
            forParameter:(IOParameterName)parameterName
                   count:(unsigned)count;

- (IOReturn)setCharValues:(unsigned char *)parameterArray
             forParameter:(IOParameterName)parameterName
                    count:(unsigned)count;

/* IOAudio private methods (overridden) */
- (BOOL)_channelWillAddStream;
- (void)_getSupportedParameters:(NXSoundParameterTag *)list
                          count:(unsigned int *)numParameters
                      forObject:anObject;

@end

#endif /* _BEEP_H */
