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
#import <libkern/libkern.h>

/* Forward declaration of IOAudio private method */
@interface IOAudio (Private)
- _outputChannel;
@end

/* PC Speaker hardware registers */
#define PIT_CONTROL     0x43
#define PIT_COUNTER2    0x42
#define PPI_PORT_B      0x61

/* PIT commands */
#define PIT_CMD_COUNTER2_LOHI_MODE3  0xB6

/* PPI Port B bits */
#define PPI_SPEAKER_ENABLE  0x03

/* Frequency limits */
#define MIN_FREQUENCY   20
#define MAX_FREQUENCY   20000
#define PIT_FREQUENCY   1193182
#define PIT_DIVISOR(freq)  (PIT_FREQUENCY / (freq))

/* Default beep sequences - NULL terminated array */
static BeepSequence defaultBeepSequences[] = {
    /* Blip style: single short beep */
    { "Blip", 1, 1, 1 },
    /* Plain style: simple two-tone, frequency ratio 3:4 (perfect fifth down) */
    { "Plain", 2, 3, 4 },
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
    int index;

    if (styleStr == NULL)
        return -1;

    /* Calculate length of input string */
    nameLen = strlen(styleStr);

    /* Iterate through all beep sequences */
    index = 0;
    for (seq = defaultBeepSequences; seq->name != NULL; seq++, index++) {
        /* Compare using strncmp with calculated length */
        if (strncmp(seq->name, styleStr, nameLen) == 0) {
            return index;
        }
    }

    /* Style not found */
    return -1;
}

@implementation Beep

/* ========== Initialization and Lifecycle ========== */

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

    /* Initialize PIT command byte */
    _pitCommand = PIT_CMD_COUNTER2_LOHI_MODE3;

    /* Set default beep sequence */
    _beepSequence = defaultBeepSequences;

    /* Set duration (default 100 ms if not specified) */
    if (durationStr == NULL) {
        _defaultDuration = 100;
    } else {
        _defaultDuration = strtol(durationStr, NULL, 10);
        [configTable freeString:durationStr];
    }

    /* Set frequency (default 880 Hz if not specified) */
    if (frequencyStr == NULL) {
        _defaultFrequency = 880;  /* 0x370 */
    } else {
        _defaultFrequency = strtol(frequencyStr, NULL, 10);
        [configTable freeString:frequencyStr];
    }

    /* Set beep sequence based on style */
    if (styleStr != NULL) {
        styleIndex = stringToStyle(styleStr);
        if (styleIndex >= 0) {
            _beepSequence = &defaultBeepSequences[styleIndex];
        }
    }

    /* Set device location */
    [self setLocation:"PC Speaker"];

    /* Initialize device and build PIT command byte */
    [self reset];

    IOLog("Beep: Initialized (default: %d Hz, %d ms)\n",
          _defaultFrequency, _defaultDuration);

    return self;
}

- (BOOL)reset
{
    /* Set device name */
    [self setName:"Beep"];

    /* Set device kind */
    [self setDeviceKind:"Audio"];

    /* Build PIT command byte (0xB6) through bit operations */
    _pitCommand &= 0xfe;  /* Clear bit 0 */
    _pitCommand &= 0xf1;  /* Clear bits 1-3 */
    _pitCommand |= 0x06;  /* Set bits 1-2 (access mode: lobyte/hibyte) */
    _pitCommand |= 0x30;  /* Set bits 4-5 (mode 3: square wave) */
    _pitCommand &= 0x3f;  /* Clear bits 6-7 */
    _pitCommand |= 0x80;  /* Set bit 7 (counter 2) */
    /* Result: 0xB6 = 10110110 binary */

    return YES;
}

/* ========== Sound Output ========== */

- (IOReturn)beep
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
        return IO_R_SUCCESS;
    }

    /* Check if frequency and duration are valid */
    if (_defaultFrequency == 0 || _defaultDuration == 0) {
        return IO_R_SUCCESS;
    }

    /* Save current port B value */
    savedPortB = inb(PPI_PORT_B);

    /* Get beep sequence parameters */
    seq = _beepSequence;
    noteCount = seq->noteCount;
    freqMult = seq->freqMultiplier;
    freqDiv = seq->freqDivisor;

    /* Calculate timeout in ticks: (duration_ms * hz) / (noteCount * 1000) */
    timeout = (_defaultDuration * hz) / (noteCount * 1000);

    /* Start with default frequency */
    currentFreq = _defaultFrequency;

    /* Play each note in the sequence */
    for (i = 0; i < noteCount; i++) {
        /* Calculate PIT divisor for current frequency */
        if (currentFreq > 0) {
            pitDivisor = PIT_FREQUENCY / currentFreq;
        } else {
            pitDivisor = 0x34cf;  /* fallback value */
        }

        /* Program the 8254 PIT */
        outb(PIT_CONTROL, _pitCommand);
        outb(PIT_COUNTER2, (unsigned char)(pitDivisor & 0xFF));
        outb(PIT_COUNTER2, (unsigned char)(pitDivisor >> 8));

        /* Enable speaker on first note */
        if (i == 0) {
            outb(PPI_PORT_B, savedPortB | PPI_SPEAKER_ENABLE);
        }

        /* Wait for note duration using kernel sleep */
        IOSleep(timeout * 1000 / hz);

        /* Calculate next frequency: (freqMult * currentFreq) / freqDiv */
        if (i < noteCount - 1) {
            currentFreq = (freqMult * currentFreq) / freqDiv;
        }
    }

    /* Disable speaker - restore original port value */
    outb(PPI_PORT_B, savedPortB);

    return IO_R_SUCCESS;
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
        parameterArray[0] = _defaultFrequency;
        *count = 1;
        return IO_R_SUCCESS;
    }

    /* Check for "Duration" parameter */
    if (strcmp(parameterName, "Duration") == 0) {
        parameterArray[0] = _defaultDuration;
        *count = 1;
        return IO_R_SUCCESS;
    }

    /* Check for "Style" parameter */
    if (strcmp(parameterName, "Style") == 0) {
        /* Calculate style index: (_beepSequence - defaultBeepSequences) / sizeof(BeepSequence) */
        styleIndex = (_beepSequence - defaultBeepSequences);
        parameterArray[0] = styleIndex;
        *count = 1;
        return IO_R_SUCCESS;
    }

    /* Delegate to superclass for standard parameters */
    return [super getIntValues:parameterArray
                  forParameter:parameterName
                         count:&maxLen];
}

- (IOReturn)getCharValues:(unsigned char *)parameterArray
             forParameter:(IOParameterName)parameterName
                    count:(unsigned *)count
{
    unsigned int maxLen;
    const char *styleName;
    size_t nameLen;
    BeepSequence *seq;
    size_t totalLen;
    BOOL firstItem;

    /* Get max length (default to 512 if count is 0) */
    maxLen = *count;
    if (maxLen == 0) {
        maxLen = 0x200;  /* 512 bytes */
    }

    /* Check for "Style" parameter */
    if (strcmp(parameterName, "Style") == 0) {
        /* Return current style name */
        styleName = _beepSequence->name;
        nameLen = strlen(styleName);

        /* Limit to available space */
        if (maxLen <= nameLen) {
            nameLen = maxLen - 1;
        }

        *count = nameLen + 1;
        strncpy((char *)parameterArray, styleName, nameLen);
        parameterArray[nameLen] = '\0';

        return IO_R_SUCCESS;
    }

    /* Check for "AllStyles" parameter */
    if (strcmp(parameterName, "AllStyles") == 0) {
        /* Return all available style names separated by spaces */
        *count = 0;
        firstItem = YES;

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
            if (!firstItem && (*count + 2 <= maxLen)) {
                parameterArray[*count] = ' ';
                *count = *count + 1;
            }

            /* Copy style name */
            strncpy((char *)(parameterArray + *count), styleName, totalLen);
            *count = *count + totalLen;

            firstItem = NO;
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
        _defaultFrequency = parameterArray[0];
        return IO_R_SUCCESS;
    }

    /* Check for "Duration" parameter */
    if (strcmp(parameterName, "Duration") == 0) {
        _defaultDuration = parameterArray[0];
        return IO_R_SUCCESS;
    }

    /* Check for "Style" parameter (by index) */
    if (strcmp(parameterName, "Style") == 0) {
        /* Validate style index (max 4, meaning indices 0-4) */
        if (parameterArray[0] > 4) {
            return 0xfffffd39;  /* -711 - invalid parameter error */
        }

        /* Set beep sequence to selected style */
        _beepSequence = &defaultBeepSequences[parameterArray[0]];

        return IO_R_SUCCESS;
    }

    /* Delegate to superclass for standard parameters */
    return [super setIntValues:parameterArray
                  forParameter:parameterName
                         count:count];
}

- (IOReturn)setCharValues:(unsigned char *)parameterArray
             forParameter:(IOParameterName)parameterName
                    count:(unsigned)count
{
    int styleIndex;

    /* Check for "Style" parameter */
    if (strcmp(parameterName, "Style") == 0) {
        /* Convert style name to index */
        styleIndex = stringToStyle((const char *)parameterArray);

        if (styleIndex < 0) {
            /* Invalid style name */
            return 0xfffffd39;  /* -711 - invalid parameter error */
        }

        /* Set beep sequence to selected style */
        _beepSequence = &defaultBeepSequences[styleIndex];

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
