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
 * Beep.m - PC Speaker Sound Driver Implementation
 */

#import "Beep.h"

#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IODeviceMaster.h>
#import <driverkit/IOConfigTable.h>
#import <kernserv/prototypes.h>
#import <objc/objc-runtime.h>
#import <machdep/i386/io_inline.h>
#import <machdep/i386/timer.h>
#import <machdep/i386/timer_inline.h>
#import <libkern/libkern.h>

/* Forward declaration of IOAudio private method */
@interface IOAudio (Private)
- _outputChannel;
@end

/* PC Speaker hardware registers */
#define PPI_PORT_B      0x61

/* PPI Port B bits */
#define PPI_SPEAKER_ENABLE  0x03

/* Frequency limits */
#define MIN_FREQUENCY   20
#define MAX_FREQUENCY   20000

/* Device name and kind, published through setName: and setDeviceKind: */
static char beepDeviceName[] = "Beep";
static char beepDeviceKind[] = "Audio";

/* Default beep sequences - NULL terminated array */
BeepSequence defaultBeepSequences[] = {
    /* Plain style: single note, no pitch change */
    { "Plain", 1, 1, 1 },
    /* Blip style: two notes, frequency ratio 3:4 (perfect fourth down) */
    { "Blip", 2, 3, 4 },
    /* Up style: 8-note ascending sequence, frequency ratio 17:16 (slightly sharp) */
    { "Up", 8, 17, 16 },
    /* Down style: 8-note descending sequence, frequency ratio 15:16 (slightly flat) */
    { "Down", 8, 15, 16 },
    /* Octave style: 2-note sequence, octave jump (frequency ratio 2:1) */
    { "Octave", 2, 2, 1 },
    /* NULL terminator */
    { NULL, 0, 0, 0 }
};

/* Convert style string to index */
static int stringToStyle(const char *styleStr)
{
    size_t nameLen;
    BeepSequence *seq;

    if (styleStr == NULL)
        return -1;

    /* Calculate length of input string */
    nameLen = strlen(styleStr);

    /* Iterate through all beep sequences */
    for (seq = defaultBeepSequences; seq->name != NULL; seq++) {
        /* Compare using strncmp with calculated length */
        if (strncmp(seq->name, styleStr, nameLen) == 0) {
            return (int)(seq - defaultBeepSequences);
        }
    }

    /* Style not found */
    return -1;
}

@implementation Beep

/* ========== Initialization and Lifecycle ========== */

+ (BOOL)probe:deviceDescription
{
    id instance;

    /*
     * No hardware probing: the PC speaker is assumed present. The instance
     * is deliberately not freed when initialization fails, matching the
     * reference driver.
     */
    instance = [self alloc];

    if (instance == nil)
        return NO;

    return [instance initFromDeviceDescription:deviceDescription] != nil;
}

- initFromDeviceDescription:deviceDescription
{
    id configTable;
    const char *durationStr;
    const char *frequencyStr;
    const char *styleStr;
    int styleIndex;

    /* Call superclass initializer */
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Get config table */
    configTable = [deviceDescription configTable];

    /* Read config values */
    durationStr = [configTable valueForStringKey:"Duration"];
    frequencyStr = [configTable valueForStringKey:"Frequency"];
    styleStr = [configTable valueForStringKey:"Style"];

    /* Set default beep sequence */
    currentBeepSequence = defaultBeepSequences;

    /* Set duration (default 100 ms if not specified) */
    if (durationStr == NULL) {
        duration = 100;
    } else {
        duration = strtol(durationStr, NULL, 10);
        [configTable freeString:durationStr];
    }

    /* Set frequency (default 880 Hz if not specified) */
    if (frequencyStr == NULL) {
        frequency = 880;  /* 0x370 */
    } else {
        frequency = strtol(frequencyStr, NULL, 10);
        [configTable freeString:frequencyStr];
    }

    /* Set beep sequence based on style */
    if (styleStr != NULL) {
        styleIndex = stringToStyle(styleStr);
        if (styleIndex >= 0) {
            currentBeepSequence = &defaultBeepSequences[styleIndex];
        }
    }

    return self;
}

- (BOOL)reset
{
    /* Set device name */
    [self setName:beepDeviceName];

    /* Set device kind */
    [self setDeviceKind:beepDeviceKind];

    /* Build the PIT control byte (0xB6) field by field */
    timer.bcd = 0;
    timer.mode = TIMER_SQWAVEMODE;
    timer.rw = TIMER_CTL_RW_BOTH;
    timer.sel = TIMER_CNT2_SEL;

    return YES;
}

/* ========== Sound Output ========== */

- (void)beep
{
    unsigned char savedPortB;
    BeepSequence *seq;
    int noteCount;
    int freqMult;
    int freqDiv;
    unsigned int timeout;
    int currentFreq;
    unsigned short pitDivisor;
    int i;
    extern int hz;  /* system clock frequency */

    /* Check if output is muted */
    if ([self isOutputMuted]) {
        return;
    }

    /* Check if frequency and duration are valid */
    if (frequency == 0 || duration == 0) {
        return;
    }

    /* Save current port B value */
    savedPortB = inb(PPI_PORT_B);

    /* Get beep sequence parameters */
    seq = currentBeepSequence;
    noteCount = seq->noteCount;
    freqMult = seq->freqMultiplier;
    freqDiv = seq->freqDivisor;

    /* Calculate timeout in ticks: (duration_ms * hz) / (noteCount * 1000) */
    timeout = (duration * hz) / (noteCount * 1000);

    /* Start with default frequency */
    currentFreq = frequency;

    /* Play each note in the sequence */
    for (i = 0; i < noteCount; i++) {
        /* Calculate PIT divisor for current frequency */
        pitDivisor = TIMER_CONSTANT / (currentFreq > 0 ? currentFreq : 1);

        /* Program the 8254 PIT */
        timer_set_ctl(timer);
        timer_write(TIMER_CNT2_SEL, pitDivisor);

        /* Enable speaker on first note */
        if (i == 0) {
            outb(PPI_PORT_B, savedPortB | PPI_SPEAKER_ENABLE);
        }

        /* Wait for note duration, in ticks */
        assert_wait(0, 0);
        thread_set_timeout(timeout);
        thread_block();

        /* Calculate next frequency: (freqMult * currentFreq) / freqDiv */
        if (i < noteCount - 1) {
            currentFreq = (freqMult * currentFreq) / freqDiv;
        }
    }

    /* Disable speaker - restore original port value */
    outb(PPI_PORT_B, savedPortB);
}

/* ========== IODevice Parameter Methods ========== */

- (IOReturn)getIntValues:(unsigned *)parameterArray
            forParameter:(IOParameterName)parameterName
                   count:(unsigned *)count
{
    unsigned int maxLen;
    int styleIndex;

    if (parameterArray == NULL || count == NULL) {
        return IO_R_INVALID_ARG;
    }

    /* Get max length (default to 512 if count is 0) */
    maxLen = *count;
    if (maxLen == 0) {
        maxLen = 0x200;  /* 512 */
    }

    /* Check for "Frequency" parameter */
    if (strcmp(parameterName, "Frequency") == 0) {
        parameterArray[0] = frequency;
        *count = 1;
        return IO_R_SUCCESS;
    }

    /* Check for "Duration" parameter */
    if (strcmp(parameterName, "Duration") == 0) {
        parameterArray[0] = duration;
        *count = 1;
        return IO_R_SUCCESS;
    }

    /* Check for "Style" parameter */
    if (strcmp(parameterName, "Style") == 0) {
        /* Calculate style index: (currentBeepSequence - defaultBeepSequences) */
        styleIndex = (currentBeepSequence - defaultBeepSequences);
        parameterArray[0] = styleIndex;
        *count = 1;
        return IO_R_SUCCESS;
    }

    /* Delegate to superclass for standard parameters */
    return [super getIntValues:parameterArray
                  forParameter:parameterName
                         count:&maxLen];
}

- (IOReturn)getCharValues:(char *)parameterArray
             forParameter:(IOParameterName)parameterName
                    count:(unsigned *)count
{
    unsigned int maxLen;
    const char *styleName;
    size_t nameLen;
    BeepSequence *seq;
    size_t totalLen;

    /* Get max length (default to 512 if count is 0) */
    maxLen = *count;
    if (maxLen == 0) {
        maxLen = 0x200;  /* 512 bytes */
    }

    /* Check for "Style" parameter */
    if (strcmp(parameterName, "Style") == 0) {
        /* Return current style name */
        styleName = currentBeepSequence->name;
        nameLen = strlen(styleName);

        /* Limit to available space */
        if (maxLen <= nameLen) {
            nameLen = maxLen - 1;
        }

        *count = nameLen + 1;
        strncpy(parameterArray, styleName, nameLen);
        parameterArray[nameLen] = '\0';

        return IO_R_SUCCESS;
    }

    /* Check for "AllStyles" parameter */
    if (strcmp(parameterName, "AllStyles") == 0) {
        /* Return all available style names separated by spaces */
        *count = 0;

        /* Iterate through all sequences */
        for (seq = defaultBeepSequences; seq->name != NULL; seq++) {
            styleName = seq->name;
            nameLen = strlen(styleName);

            /* Check if this will fit */
            totalLen = nameLen;
            if (*count + totalLen >= maxLen) {
                totalLen = (maxLen - *count) - 1;
            }

            /* Add space separator (except for first item) */
            if (seq != defaultBeepSequences && (*count + 2 <= maxLen)) {
                parameterArray[*count] = ' ';
                *count = *count + 1;
            }

            /* Copy style name */
            strncpy(parameterArray + *count, styleName, totalLen);
            *count = *count + totalLen;
        }

        /* NULL terminate */
        parameterArray[*count] = '\0';
        *count = *count + 1;

        return IO_R_SUCCESS;
    }

    /* Delegate to superclass for other parameters */
    return [super getCharValues:parameterArray
                   forParameter:parameterName
                          count:count];
}

- (IOReturn)setIntValues:(unsigned *)parameterArray
            forParameter:(IOParameterName)parameterName
                   count:(unsigned)count
{
    if (parameterArray == NULL) {
        return IO_R_INVALID_ARG;
    }

    /* Check for "Frequency" parameter */
    if (strcmp(parameterName, "Frequency") == 0) {
        frequency = parameterArray[0];
        return IO_R_SUCCESS;
    }

    /* Check for "Duration" parameter */
    if (strcmp(parameterName, "Duration") == 0) {
        duration = parameterArray[0];
        return IO_R_SUCCESS;
    }

    /* Check for "Style" parameter (by index) */
    if (strcmp(parameterName, "Style") == 0) {
        /* Validate style index (max 4, meaning indices 0-4) */
        if (parameterArray[0] > 4) {
            return 0xfffffd39;  /* -711 - invalid parameter error */
        }

        /* Set beep sequence to selected style */
        currentBeepSequence = &defaultBeepSequences[parameterArray[0]];

        return IO_R_SUCCESS;
    }

    /* Delegate to superclass for standard parameters */
    return [super setIntValues:parameterArray
                  forParameter:parameterName
                         count:count];
}

- (IOReturn)setCharValues:(char *)parameterArray
             forParameter:(IOParameterName)parameterName
                    count:(unsigned)count
{
    int styleIndex;

    /* Check for "Style" parameter */
    if (strcmp(parameterName, "Style") == 0) {
        /* Convert style name to index */
        styleIndex = stringToStyle(parameterArray);

        if (styleIndex < 0) {
            /* Invalid style name */
            return 0xfffffd39;  /* -711 - invalid parameter error */
        }

        /* Set beep sequence to selected style */
        currentBeepSequence = &defaultBeepSequences[styleIndex];

        return IO_R_SUCCESS;
    }

    /* Delegate to superclass for other parameters */
    return [super setCharValues:parameterArray
                   forParameter:parameterName
                          count:count];
}

/* ========== IOAudio Private Methods (Overridden) ========== */

- (BOOL)_channelWillAddStream
{
    /* Beep when someone tries to add a stream */
    [self beep];

    /* But don't allow the stream to be added */
    return NO;
}

- (void)_getSupportedParameters:(NXSoundParameterTag *)list
                          count:(unsigned int *)numParameters
                      forObject:anObject
{
    id outputChannel;

    /* Initialize count to 0 */
    *numParameters = 0;

    /* Get the output channel */
    outputChannel = [self _outputChannel];

    /* Check if this is the output channel */
    if ([anObject isEqual:outputChannel]) {
        /* For output channel, support mute speaker parameter */
        list[0] = NX_SoundDeviceMuteSpeaker;
        *numParameters = 1;
    }
}

@end
