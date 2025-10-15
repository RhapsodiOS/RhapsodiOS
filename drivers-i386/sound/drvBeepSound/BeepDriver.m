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
 * BeepDriver.m - PC Speaker Sound Driver Implementation
 */

#import "BeepDriver.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IODeviceMaster.h>
#import <machkit/NXLock.h>
#import <kernserv/prototypes.h>
#import <objc/objc-runtime.h>

/* Module version information */
static const char *driverVersion = "1.0";
static const char *driverName = "Beep";

@implementation BeepDriver

/* ========== Driver Lifecycle ========== */

+ (BOOL) probe : (IODeviceDescription *) deviceDescription
{
    BeepDriver *instance;

    /* PC speaker is always present on x86 systems */
    instance = [[self alloc] initFromDeviceDescription:deviceDescription];
    if (instance == nil) {
        IOLog("BeepDriver: Failed to create instance\n");
        return NO;
    }

    [instance registerDevice];
    return YES;
}

- initFromDeviceDescription : (IODeviceDescription *) deviceDescription
{
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Initialize configuration with defaults (880 Hz, 100 ms from Beep.table) */
    _config.defaultFrequency = 880;
    _config.defaultDuration = 100;

    /* Initialize state */
    _speakerActive = NO;
    _currentFrequency = 0;

    /* Create lock for thread safety */
    _lock = [[NXLock alloc] init];

    /* Ensure speaker is off initially */
    [self _disableSpeaker];

    /* Register as the system beep driver */
    _setSystemBeepDriver(self);

    IOLog("BeepDriver: Initialized (default: %d Hz, %d ms)\n",
          _config.defaultFrequency, _config.defaultDuration);

    [self setName:"Beep"];
    [self setDeviceKind:"Beep"];
    [self setLocation:"PC Speaker"];

    return self;
}

- free
{
    /* Stop any active sound */
    [self stopTone];

    /* Unregister as system beep driver if we are it */
    if (_systemBeepDriver == self) {
        _setSystemBeepDriver(nil);
    }

    /* Free lock */
    if (_lock != nil) {
        [_lock free];
        _lock = nil;
    }

    return [super free];
}

/* ========== Sound Output Methods ========== */

- (IOReturn) playTone : (UInt32) frequency duration : (UInt32) duration
{
    [_lock lock];

    /* Validate frequency */
    if (![self _validateFrequency:frequency]) {
        [_lock unlock];
        return SOUND_IO_R_INVALID_FREQ;
    }

    /* Validate duration (must be > 0) */
    if (duration == 0) {
        [_lock unlock];
        return SOUND_IO_R_INVALID_DUR;
    }

    /* Program PIT and enable speaker */
    [self _programPIT:frequency];
    [self _enableSpeaker];
    _currentFrequency = frequency;

    [_lock unlock];

    /* Sleep for duration (blocking) */
    IOSleep(duration);

    /* Disable speaker */
    [_lock lock];
    [self _disableSpeaker];
    _currentFrequency = 0;
    [_lock unlock];

    return IO_R_SUCCESS;
}

- (IOReturn) beep
{
    return [self playTone:_config.defaultFrequency duration:_config.defaultDuration];
}

- (IOReturn) startTone : (UInt32) frequency
{
    [_lock lock];

    if (![self _validateFrequency:frequency]) {
        [_lock unlock];
        return SOUND_IO_R_INVALID_FREQ;
    }

    /* Program PIT and enable speaker */
    [self _programPIT:frequency];
    [self _enableSpeaker];
    _currentFrequency = frequency;

    [_lock unlock];

    return IO_R_SUCCESS;
}

- (IOReturn) stopTone
{
    [_lock lock];

    [self _disableSpeaker];
    _currentFrequency = 0;

    [_lock unlock];

    return IO_R_SUCCESS;
}

/* ========== Configuration Methods ========== */

- (IOReturn) setDefaults : (UInt32) frequency duration : (UInt32) duration
{
    if (![self _validateFrequency:frequency]) {
        return SOUND_IO_R_INVALID_FREQ;
    }

    if (duration == 0) {
        return SOUND_IO_R_INVALID_DUR;
    }

    [_lock lock];
    _config.defaultFrequency = frequency;
    _config.defaultDuration = duration;
    [_lock unlock];

    return IO_R_SUCCESS;
}

- (IOReturn) getConfiguration : (SoundConfig *) config
{
    if (config == NULL) {
        return IO_R_INVALID_ARG;
    }

    [_lock lock];
    *config = _config;
    [_lock unlock];

    return IO_R_SUCCESS;
}

@end

/* ========== Private/Internal Methods ========== */

@implementation BeepDriver (Private)

- (void) _programPIT : (UInt32) frequency
{
    UInt32 divisor;
    UInt8 lowByte, highByte;

    /* Calculate divisor from frequency */
    divisor = PIT_DIVISOR(frequency);

    /* Clamp to valid range */
    if (divisor < MIN_DIVISOR) {
        divisor = MIN_DIVISOR;
    }
    if (divisor > MAX_DIVISOR) {
        divisor = MAX_DIVISOR;
    }

    /* Split into bytes */
    lowByte = divisor & 0xFF;
    highByte = (divisor >> 8) & 0xFF;

    /* Send control word to PIT */
    /* Select counter 2, access mode lo/hi, mode 3 (square wave), binary */
    outb(PIT_CONTROL, PIT_CMD_COUNTER2_LOHI_MODE3);

    /* Send divisor (low byte, then high byte) */
    outb(PIT_COUNTER2, lowByte);
    outb(PIT_COUNTER2, highByte);
}

- (void) _enableSpeaker
{
    UInt8 portValue;

    /* Read current PPI Port B value */
    portValue = inb(PPI_PORT_B);

    /* Set timer 2 gate and speaker data bits */
    portValue |= PPI_SPEAKER_ENABLE;

    /* Write back to port */
    outb(PPI_PORT_B, portValue);

    _speakerActive = YES;
}

- (void) _disableSpeaker
{
    UInt8 portValue;

    /* Read current PPI Port B value */
    portValue = inb(PPI_PORT_B);

    /* Clear timer 2 gate and speaker data bits */
    portValue &= ~PPI_SPEAKER_ENABLE;

    /* Write back to port */
    outb(PPI_PORT_B, portValue);

    _speakerActive = NO;
}

- (BOOL) _validateFrequency : (UInt32) frequency
{
    return (frequency >= MIN_FREQUENCY && frequency <= MAX_FREQUENCY);
}

@end

/* ========== Kernel Module Entry Points ========== */

/**
 * Driver probe entry point for kernel loader
 */
int Beep_probe(IODeviceDescription *deviceDescription)
{
    return [BeepDriver probe:deviceDescription] ? 0 : -1;
}

/**
 * Get driver version string
 */
const char *Beep_version(void)
{
    return driverVersion;
}

/**
 * Get driver name string
 */
const char *Beep_name(void)
{
    return driverName;
}

/* ========== Utility Functions ========== */

/* Global driver instance for system beep */
static BeepDriver *_systemBeepDriver = nil;

/**
 * Set the system beep driver instance
 * Called internally when driver is initialized
 */
static void _setSystemBeepDriver(BeepDriver *driver)
{
    _systemBeepDriver = driver;
}

/**
 * Play system beep (callable from kernel)
 */
void Beep_systemBeep(void)
{
    if (_systemBeepDriver != nil) {
        [_systemBeepDriver beep];
    } else {
        /* Fallback: directly program the speaker if no driver instance */
        UInt32 divisor = PIT_DIVISOR(BEEP_DEFAULT_FREQ);
        UInt8 portValue;

        /* Program PIT */
        outb(PIT_CONTROL, PIT_CMD_COUNTER2_LOHI_MODE3);
        outb(PIT_COUNTER2, divisor & 0xFF);
        outb(PIT_COUNTER2, (divisor >> 8) & 0xFF);

        /* Enable speaker */
        portValue = inb(PPI_PORT_B);
        portValue |= PPI_SPEAKER_ENABLE;
        outb(PPI_PORT_B, portValue);

        /* Wait for default duration */
        IOSleep(DURATION_SHORT);

        /* Disable speaker */
        portValue = inb(PPI_PORT_B);
        portValue &= ~PPI_SPEAKER_ENABLE;
        outb(PPI_PORT_B, portValue);
    }
}

/**
 * Play tone (callable from kernel)
 */
void Beep_playTone(UInt32 frequency, UInt32 duration)
{
    if (_systemBeepDriver != nil) {
        [_systemBeepDriver playTone:frequency duration:duration];
    } else {
        /* Fallback: directly program the speaker if no driver instance */
        UInt32 divisor;
        UInt8 portValue;

        /* Validate frequency */
        if (frequency < MIN_FREQUENCY || frequency > MAX_FREQUENCY) {
            return;
        }

        divisor = PIT_DIVISOR(frequency);

        /* Program PIT */
        outb(PIT_CONTROL, PIT_CMD_COUNTER2_LOHI_MODE3);
        outb(PIT_COUNTER2, divisor & 0xFF);
        outb(PIT_COUNTER2, (divisor >> 8) & 0xFF);

        /* Enable speaker */
        portValue = inb(PPI_PORT_B);
        portValue |= PPI_SPEAKER_ENABLE;
        outb(PPI_PORT_B, portValue);

        /* Wait for duration */
        if (duration > 0) {
            IOSleep(duration);
        }

        /* Disable speaker */
        portValue = inb(PPI_PORT_B);
        portValue &= ~PPI_SPEAKER_ENABLE;
        outb(PPI_PORT_B, portValue);
    }
}
