/*
 * VoodooVSAFBPower.m -- Power management (DPMS) for 3Dfx Voodoo3 driver
 *
 * Copyright (c) 2025 RhapsodiOS Project
 * All rights reserved.
 *
 * Implements VESA DPMS (Display Power Management Signaling) support
 */

#import "VoodooVSAFB.h"

@implementation VoodooVSAFB (Power)

/*
 * DPMS (Display Power Management Signaling) States:
 * - On: Full operation
 * - Standby: Blanked, minimal power
 * - Suspend: More power savings than standby
 * - Off: Maximum power savings
 */

/*
 * Set DPMS power state
 */
- (IOReturn) setDPMSState: (int)state
{
	CARD32 vidProcCfg;
	CARD32 dacMode;

	VSALog("VoodooVSAFB: Setting DPMS state to %d\n", state);

	vidProcCfg = [self readRegister: SST_VIDPROCCFG];
	dacMode = [self readRegister: SST_DACMODE];

	switch (state) {
		case DPMS_STATE_ON:
			/* Full power - enable video processor and DAC */
			vidProcCfg |= SST_VIDCFG_VIDPROC_ENABLE;
			vidProcCfg |= SST_VIDCFG_DESK_ENABLE;
			dacMode &= ~SST_DACMODE_BLANK;

			[self writeRegister: SST_VIDPROCCFG value: vidProcCfg];
			[self writeRegister: SST_DACMODE value: dacMode];

			/* Restore PLL if it was disabled */
			if (powerState != DPMS_STATE_ON) {
				[self initializePLL: savedPixelClock];
			}

			VSALog("VoodooVSAFB: Display powered on\n");
			break;

		case DPMS_STATE_STANDBY:
			/* Standby - blank display but keep sync signals */
			dacMode |= SST_DACMODE_BLANK;
			[self writeRegister: SST_DACMODE value: dacMode];

			VSALog("VoodooVSAFB: Display in standby mode\n");
			break;

		case DPMS_STATE_SUSPEND:
			/* Suspend - disable video processor, blank DAC */
			vidProcCfg &= ~SST_VIDCFG_VIDPROC_ENABLE;
			dacMode |= SST_DACMODE_BLANK;

			[self writeRegister: SST_VIDPROCCFG value: vidProcCfg];
			[self writeRegister: SST_DACMODE value: dacMode];

			VSALog("VoodooVSAFB: Display suspended\n");
			break;

		case DPMS_STATE_OFF:
			/* Off - maximum power savings */
			vidProcCfg &= ~SST_VIDCFG_VIDPROC_ENABLE;
			vidProcCfg &= ~SST_VIDCFG_DESK_ENABLE;
			dacMode |= SST_DACMODE_BLANK;

			[self writeRegister: SST_VIDPROCCFG value: vidProcCfg];
			[self writeRegister: SST_DACMODE value: dacMode];

			/* Save pixel clock for restoration */
			savedPixelClock = currentPixelClock;

			VSALog("VoodooVSAFB: Display powered off\n");
			break;

		default:
			IOLog("VoodooVSAFB: Invalid DPMS state %d\n", state);
			return IO_R_INVALID_ARG;
	}

	powerState = state;
	return IO_R_SUCCESS;
}

/*
 * Get current DPMS power state
 */
- (int) getDPMSState
{
	return powerState;
}

/*
 * Check if display is blanked
 */
- (BOOL) isDisplayBlanked
{
	CARD32 dacMode = [self readRegister: SST_DACMODE];
	return (dacMode & SST_DACMODE_BLANK) ? YES : NO;
}

/*
 * Blank display (simple blanking without full DPMS)
 */
- (void) blankDisplay: (BOOL)blank
{
	CARD32 dacMode = [self readRegister: SST_DACMODE];

	if (blank) {
		dacMode |= SST_DACMODE_BLANK;
		VSALog("VoodooVSAFB: Display blanked\n");
	} else {
		dacMode &= ~SST_DACMODE_BLANK;
		VSALog("VoodooVSAFB: Display unblanked\n");
	}

	[self writeRegister: SST_DACMODE value: dacMode];
}

/*
 * Save display state before suspend
 */
- (void) saveDisplayState
{
	VSALog("VoodooVSAFB: Saving display state\n");

	/* Save critical registers */
	savedVidProcCfg = [self readRegister: SST_VIDPROCCFG];
	savedDACMode = [self readRegister: SST_DACMODE];
	savedPLLCtrl0 = [self readRegister: SST_PLLCTRL0];
	savedPLLCtrl1 = [self readRegister: SST_PLLCTRL1];
	savedVGAInit0 = [self readRegister: SST_VGAINIT0];
	savedDesktopAddr = [self readRegister: SST_VIDDESKTOPSTARTADDR];
	savedDesktopStride = [self readRegister: SST_VIDDESKTOPOVERLAYSTRIDE];
	savedScreenSize = [self readRegister: SST_VIDSCREENSIZE];

	displayStateSaved = YES;
}

/*
 * Restore display state after resume
 */
- (void) restoreDisplayState
{
	if (!displayStateSaved) {
		IOLog("VoodooVSAFB: No saved state to restore\n");
		return;
	}

	VSALog("VoodooVSAFB: Restoring display state\n");

	/* Restore PLL first */
	[self writeRegister: SST_PLLCTRL0 value: savedPLLCtrl0];
	[self writeRegister: SST_PLLCTRL1 value: savedPLLCtrl1];
	IOSleep(10);  /* Wait for PLL to stabilize */

	/* Restore VGA init */
	[self writeRegister: SST_VGAINIT0 value: savedVGAInit0];

	/* Restore video timing */
	[self writeRegister: SST_VIDSCREENSIZE value: savedScreenSize];
	[self writeRegister: SST_VIDDESKTOPSTARTADDR value: savedDesktopAddr];
	[self writeRegister: SST_VIDDESKTOPOVERLAYSTRIDE value: savedDesktopStride];

	/* Restore DAC mode */
	[self writeRegister: SST_DACMODE value: savedDACMode];

	/* Restore video processor config last */
	[self writeRegister: SST_VIDPROCCFG value: savedVidProcCfg];

	VSALog("VoodooVSAFB: Display state restored\n");
}

/*
 * Enter power-saving mode (for system sleep)
 */
- (IOReturn) enterPowerSaveMode
{
	VSALog("VoodooVSAFB: Entering power save mode\n");

	[self saveDisplayState];
	[self setDPMSState: DPMS_STATE_OFF];

	return IO_R_SUCCESS;
}

/*
 * Exit power-saving mode (for system wake)
 */
- (IOReturn) exitPowerSaveMode
{
	VSALog("VoodooVSAFB: Exiting power save mode\n");

	[self restoreDisplayState];
	[self setDPMSState: DPMS_STATE_ON];

	return IO_R_SUCCESS;
}

@end
