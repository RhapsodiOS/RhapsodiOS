/*
 * RivaFBPower.m -- Power management support
 */

#import "RivaFB.h"
#import <driverkit/generalFuncs.h>
#include <stdio.h>

/* Power management parameter names */
#define IO_DISPLAY_POWER_PARAM "IODisplayPowerState"

/* Power states */
typedef enum {
    RIVA_POWER_ON = 0,      /* Display fully powered */
    RIVA_POWER_STANDBY = 1, /* Display in standby */
    RIVA_POWER_SUSPEND = 2, /* Display suspended */
    RIVA_POWER_OFF = 3      /* Display powered off */
} RivaPowerState;

@implementation RivaFB (Power)

/*
 * Get power management parameters
 */
- (IOReturn)getIntValues: (unsigned int *)parameterArray
            forParameter: (IOParameterName)parameterName
                   count: (unsigned int *)count
{
    if (strcmp(parameterName, IO_DISPLAY_POWER_PARAM) == 0) {
        if (*count < 1) {
            return IO_R_INVALID_ARG;
        }
        /* Return current power state (always on for now) */
        parameterArray[0] = RIVA_POWER_ON;
        *count = 1;
        return IO_R_SUCCESS;
    }

    /* Pass to superclass for other parameters */
    return [super getIntValues:parameterArray
                  forParameter:parameterName
                         count:count];
}

/*
 * Set power management parameters
 */
- (IOReturn)setIntValues: (unsigned int *)parameterArray
            forParameter: (IOParameterName)parameterName
                   count: (unsigned int)count
{
    RivaPowerState newState;

    if (strcmp(parameterName, IO_DISPLAY_POWER_PARAM) == 0) {
        if (count < 1) {
            return IO_R_INVALID_ARG;
        }

        newState = (RivaPowerState)parameterArray[0];

        switch (newState) {
            case RIVA_POWER_ON:
                RivaLog("RivaFB: Power ON\n");
                [self powerOn];
                break;

            case RIVA_POWER_STANDBY:
                RivaLog("RivaFB: Power STANDBY\n");
                [self powerStandby];
                break;

            case RIVA_POWER_SUSPEND:
                RivaLog("RivaFB: Power SUSPEND\n");
                [self powerSuspend];
                break;

            case RIVA_POWER_OFF:
                RivaLog("RivaFB: Power OFF\n");
                [self powerOff];
                break;

            default:
                RivaLog("RivaFB: Unknown power state %d\n", newState);
                return IO_R_INVALID_ARG;
        }

        return IO_R_SUCCESS;
    }

    /* Pass to superclass for other parameters */
    return [super setIntValues:parameterArray
                  forParameter:parameterName
                         count:count];
}

/*
 * Power on the display
 */
- (void)powerOn
{
    CARD32 config;

    /* Enable CRTC */
    config = [self readReg: NV_PCRTC_OFFSET + NV_PCRTC_CONFIG];
    config |= 0x00000001;  /* Enable bit */
    [self writeReg: NV_PCRTC_OFFSET + NV_PCRTC_CONFIG value: config];

    /* Enable RAMDAC */
    config = [self readReg: NV_PRAMDAC_OFFSET + NV_PRAMDAC_GENERAL_CONTROL];
    config &= ~NV_PRAMDAC_GENERAL_CONTROL_VGA_STATE;
    config |= NV_PRAMDAC_GENERAL_CONTROL_PIXMIX_ON;
    [self writeReg: NV_PRAMDAC_OFFSET + NV_PRAMDAC_GENERAL_CONTROL value: config];

    /* Restore cursor if it was enabled */
    if (cursorEnabled) {
        [self showCursor: YES];
    }

    RivaLog("RivaFB: Display powered on\n");
}

/*
 * Put display in standby mode (DPMS suspend)
 */
- (void)powerStandby
{
    CARD8 sr1;

    /* Hide cursor */
    if (cursorEnabled) {
        [self showCursor: NO];
    }

    /* Program VGA sequencer for standby */
    /* Turn off screen (SR1 bit 5 = 1) */
    [self writeVGA: VGA_SEQ_INDEX value: 0x01];
    sr1 = [self readVGA: VGA_SEQ_DATA];
    sr1 |= 0x20;  /* Screen off */
    [self writeVGA: VGA_SEQ_DATA value: sr1];

    RivaLog("RivaFB: Display in standby\n");
}

/*
 * Suspend the display (DPMS suspend)
 */
- (void)powerSuspend
{
    /* Same as standby for now */
    [self powerStandby];
    RivaLog("RivaFB: Display suspended\n");
}

/*
 * Power off the display
 */
- (void)powerOff
{
    CARD32 config;

    /* Hide cursor */
    if (cursorEnabled) {
        [self showCursor: NO];
    }

    /* Disable RAMDAC output */
    config = [self readReg: NV_PRAMDAC_OFFSET + NV_PRAMDAC_GENERAL_CONTROL];
    config |= NV_PRAMDAC_GENERAL_CONTROL_VGA_STATE;
    [self writeReg: NV_PRAMDAC_OFFSET + NV_PRAMDAC_GENERAL_CONTROL value: config];

    /* Disable CRTC */
    config = [self readReg: NV_PCRTC_OFFSET + NV_PCRTC_CONFIG];
    config &= ~0x00000001;  /* Disable bit */
    [self writeReg: NV_PCRTC_OFFSET + NV_PCRTC_CONFIG value: config];

    RivaLog("RivaFB: Display powered off\n");
}

@end
