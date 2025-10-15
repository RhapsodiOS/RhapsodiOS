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
 * BeepDriver.h - PC Speaker Sound Driver Interface
 *
 * This driver provides basic sound output functionality using the PC speaker
 * (Intel 8254 PIT Channel 2).
 */

#ifndef _BEEP_DRIVER_H
#define _BEEP_DRIVER_H

#import <driverkit/i386/IODevice.h>
#import <driverkit/i386/IODirectDevice.h>
#import "BeepTypes.h"
#import "PCSpeakerRegs.h"

@interface BeepDriver : IODirectDevice
{
    /* Hardware state */
    Boolean             _speakerActive;     /* Speaker currently on */
    UInt32              _currentFrequency;  /* Current frequency (Hz) */

    /* Configuration */
    SoundConfig         _config;            /* Configuration */

    /* Thread safety */
    id                  _lock;              /* Access lock */
}

/* ========== Driver Lifecycle ========== */

/**
 * Probe for PC speaker hardware
 */
+ (BOOL) probe : (IODeviceDescription *) deviceDescription;

/**
 * Initialize the driver instance
 */
- initFromDeviceDescription : (IODeviceDescription *) deviceDescription;

/**
 * Free the driver
 */
- free;

/* ========== Sound Output Methods ========== */

/**
 * Play a tone at specified frequency and duration
 *
 * @param frequency Frequency in Hz (20-20000)
 * @param duration Duration in milliseconds
 * @return IO_R_SUCCESS on success, error code otherwise
 */
- (IOReturn) playTone : (UInt32) frequency duration : (UInt32) duration;

/**
 * Play a default beep (800 Hz, 250ms)
 *
 * @return IO_R_SUCCESS on success
 */
- (IOReturn) beep;

/**
 * Start a continuous tone at specified frequency
 *
 * @param frequency Frequency in Hz
 * @return IO_R_SUCCESS on success
 */
- (IOReturn) startTone : (UInt32) frequency;

/**
 * Stop the current tone
 *
 * @return IO_R_SUCCESS on success
 */
- (IOReturn) stopTone;

/* ========== Configuration Methods ========== */

/**
 * Set default frequency and duration
 *
 * @param frequency Default frequency in Hz
 * @param duration Default duration in milliseconds
 * @return IO_R_SUCCESS on success
 */
- (IOReturn) setDefaults : (UInt32) frequency duration : (UInt32) duration;

/**
 * Get current configuration
 *
 * @param config Pointer to configuration structure to fill
 * @return IO_R_SUCCESS on success
 */
- (IOReturn) getConfiguration : (SoundConfig *) config;

@end

/* ========== Private/Internal Methods ========== */

@interface BeepDriver (Private)

/**
 * Program the 8254 PIT for the specified frequency
 */
- (void) _programPIT : (UInt32) frequency;

/**
 * Enable the PC speaker
 */
- (void) _enableSpeaker;

/**
 * Disable the PC speaker
 */
- (void) _disableSpeaker;

/**
 * Validate frequency is in acceptable range
 */
- (BOOL) _validateFrequency : (UInt32) frequency;

@end

/* ========== Public C API Functions ========== */

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Driver probe entry point for kernel loader
 * @param deviceDescription Device description from IOKit
 * @return 0 on success, -1 on failure
 */
int Beep_probe(IODeviceDescription *deviceDescription);

/**
 * Get driver version string
 * @return Version string
 */
const char *Beep_version(void);

/**
 * Get driver name string
 * @return Driver name
 */
const char *Beep_name(void);

/**
 * Play system beep (callable from kernel)
 */
void Beep_systemBeep(void);

/**
 * Play tone with specified frequency and duration (callable from kernel)
 * @param frequency Frequency in Hz
 * @param duration Duration in milliseconds
 */
void Beep_playTone(UInt32 frequency, UInt32 duration);

#ifdef __cplusplus
}
#endif

#endif /* _BEEP_DRIVER_H */
