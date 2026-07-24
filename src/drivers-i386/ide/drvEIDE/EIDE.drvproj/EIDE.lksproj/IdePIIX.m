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
 * Copyright 1997-1998 by Apple Computer, Inc., All rights reserved.
 * Copyright 1994-1997 NeXT Software, Inc., All rights reserved.
 *
 * IdePIIX.m - PIIX/PCI specific ATA controller initialization module. 
 *
 * 23-Jan-1998 Joe Liu at Apple
 *  Added support for PIIX/PIIX3/PIIX4 PCI IDE controllers.
 *
 * 05-Apr-1995	Rakesh Dubey at NeXT
 *	Fixed some bugs in PCI support.
 * 03-Oct-1994 	Rakesh Dubey at NeXT
 *      Created. 
 */

#import "IdeCnt.h"
#import "IdePIIX.h"
#import "IdeCntCmds.h"
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <string.h>
#import <stdio.h>
#import "PIIX.h"
#import "PIIXTiming.h"
#import "IdeShared.h"
#import "IdeBMIDE.h"

//#define DEBUG

#ifndef MIN
#define MIN(a,b)    ((a) < (b) ? (a) : (b))
#endif  MIN

#ifndef MAX
#define MAX(a,b)    ((a) > (b) ? (a) : (b))
#endif  MAX

@implementation IdeController(PIIX)

/*
 * Method: probePCIController
 *
 * Purpose:
 * Probe the existence of a supported PCI chipset, then proceed to
 * record the PCI IDE controller found.
 *
 * Note:
 * This is called before [super init...], and so we use the class version
 * of getPCIdevice method calls.
 *
 */
- (BOOL) probePCIController:(IOPCIDeviceDescription *)devDesc
{
    unsigned char 	devNum, funcNum, busNum;
    const char 		*value;
	const char		*deviceName;
	IOConfigTable 	*configTable;
    IOReturn 		rtn;
    const id self_class = [self class];

	/*
	 * Initialize PCI ivars.
	 */
	_controllerID = PCI_ID_NONE;
	_ideChannel   = PCI_CHANNEL_OTHER;
	_busMaster    = NO;
	bzero((char *)&_prdTable, sizeof(_prdTable));
	
	/*
	 * Make sure we are dealing with a PCI config table by reading the
	 * BUS_TYPE key.
	 */
    configTable = [devDesc configTable];
    value = [configTable valueForStringKey:BUS_TYPE];
    if (!value || strcmp(value, "PCI") != 0) {
		// Not PCI, return YES to continue probing for non PCI controllers.
		return YES;
    }
    
	/*
	 * Read PCI config space for VendorID and DeviceID.
	 */
    rtn = [devDesc getPCIdevice:&devNum function:&funcNum bus:&busNum];
    if (rtn != IO_R_SUCCESS) {
    	IOLog("%s: Unsupported PCI hardware\n", [self name]);
		return NO;
    }
    rtn = [self_class getPCIConfigData:&_controllerID atRegister:0x00
		withDeviceDescription:devDesc];
    if (rtn != IO_R_SUCCESS)	{
    	IOLog("%s: PCI config space access error %d\n", [self name], rtn);
		return NO;
    }	  

	switch (_controllerID) {
		case PCI_ID_PIIX:
			deviceName = "PIIX";
			break;
		case PCI_ID_PIIX3:
			deviceName = "PIIX3";
			break;
		case PCI_ID_PIIX4:
			deviceName = "PIIX4";
			break;
		case PCI_ID_PIIX4E:
			deviceName = "PIIX4E";
			break;
		case PCI_ID_PIIX4M:
			deviceName = "PIIX4M";
			break;
		default:
			IOLog("%s: Unknown PCI IDE controller (0x%08lx)\n",
				[self name], _controllerID);
			_controllerID = PCI_ID_NONE;
			return NO;
	}

	/*
	 * Report the PCI controller found.
	 */
	IOLog("%s: %s PCI IDE Controller at Dev:%d Func:%d Bus:%d\n",
		[self name], deviceName, devNum, funcNum, busNum);

	/*
	 * At this point, we are certain that we are dealing with a
	 * Intel PIIX class controller.
	 */
	return ([self PIIXInitController:devDesc]);
}

/*
 * Method: initPIIXController
 *
 * Initializes the Intel PIIX IDE controller.
 */
- (BOOL) PIIXInitController:(IOPCIDeviceDescription *)devDesc
{
	piix_idetim_u	idetim;
	IOReturn 		rtn;
	unsigned long	configReg;
	const id self_class = [self class];

	/*
	 * Are we initializing the primary or the secondary channel?
	 * Set the ivar _ideChannel.
	 */
	switch ([devDesc portRangeList]->start) {
		case PIIX_P_CMD_ADDR:
			_ideChannel = PCI_CHANNEL_PRIMARY;
			break;
		case PIIX_S_CMD_ADDR:
			_ideChannel = PCI_CHANNEL_SECONDARY;
			break;
		default:
			_ideChannel = PCI_CHANNEL_OTHER;
	}
	
	/*
	 * PIIX configured on a weird location, cannot continue.
	 *
	 * NOTE:
	 * The I/O ranges does NOT show up as a I/O range in the PCI
	 * configuration space. However, the Bus-Mastering I/O range
	 * does show up at configuration space location 0x20.
	 */
	if ((_ideChannel == PCI_CHANNEL_OTHER) ||
		([devDesc portRangeList]->size != PIIX_CMD_SIZE)) {
		IOLog("%s: Invalid IDE Command Block set to 0x%x size %d\n",
			[self name],
			[devDesc portRangeList]->start,
			[devDesc portRangeList]->size);
		return NO;
	}
	
	/*
	 * Verify our IRQ assignment.
	 *
	 * PIIX hardcodes the following settings:
	 * IRQ 14 - primary channel
	 * IRQ 15 - secondary channel
	 */
	{
	unsigned int irq;
	
	irq = (_ideChannel == PCI_CHANNEL_PRIMARY) ? PIIX_P_IRQ : PIIX_S_IRQ;
	if ([devDesc interrupt] != irq) {
		IOLog("%s: Invalid IRQ: %d\n", [self name], [devDesc interrupt]);
		return NO;
	}
	}
	
	/*
	 * Check the I/O Space Enable bit in the PCI command register.
	 *
	 * This is the master enable bit for the PIIX controller.
	 */
    rtn = [self_class getPCIConfigData:&configReg atRegister:PIIX_PCICMD
		withDeviceDescription:devDesc];
    if (rtn != IO_R_SUCCESS)	{
    	IOLog("%s: PCI config space access error %d\n", [self name], rtn);
		return NO;
    }	
	if (!(configReg & 0x0001)) {
		IOLog("%s: PCI IDE controller is not enabled\n", [self name]);
		return NO;
	}
	if (configReg & 0x0004)
		_busMaster = YES;
	else
		_busMaster = NO;
	
	/*
	 * Fetch the corresponding primary/secondary IDETIM register and
	 * verify that the individual channels are enabled.
	 */
    rtn = [self_class getPCIConfigData:&configReg atRegister:PIIX_IDETIM
		withDeviceDescription:devDesc];
    if (rtn != IO_R_SUCCESS)	{
    	IOLog("%s: PCI config space access error %d\n", [self name], rtn);
		return NO;
    }
	if (_ideChannel == PCI_CHANNEL_SECONDARY)
		configReg >>= 16;	// PIIX_IDETIM + 2 for secondary channel
	idetim.word = (u_short)configReg;
	
	if (!idetim.bits.ide) {
		IOLog("%s: %s PCI IDE channel is not enabled\n",
			[self name],
			(_ideChannel == PCI_CHANNEL_PRIMARY) ? "Primary" : "Secondary");
		return NO;
	}

	/*
	 * Register and record the location of our Bus Master 
	 * interface registers.
	 */
	if (_busMaster && ([self bmRegisterRange:devDesc] == NO)) {
		IOLog("%s: Bus master I/O range registration failed\n",
			[self name]);
		_busMaster = NO;
	}

	/*
	 * Allocate a 4K-page (perhaps 8K) aligned page of memory for
	 * the PRD table.
	 */
	if (_busMaster && ([self bmInitPRDTable] == NO)) {
		IOLog("%s: cannot allocate memory for descriptor table\n",
			[self name]);
		_busMaster = NO;
	}

#if 0
	IOLog("%s: PCI bus master DMA: %s\n",
		[self name], busMaster ? "Enabled" : "Disabled");
#endif

	/*
	 * Revert to default timing.
	 */
	[self PIIXResetTimings:devDesc];

	/*
	 * Detect 80-wire cable for UDMA modes > 2
	 */
	if ((_controllerID == PCI_ID_PIIX4) ||
	    (_controllerID == PCI_ID_PIIX4E) ||
	    (_controllerID == PCI_ID_PIIX4M)) {
		_has80WireCable = [self PIIXDetect80WireCable:devDesc];
	} else {
		_has80WireCable = NO;
	}

    return YES;
}

/*
 * Method: getPCIControllerCapabilities
 *
 * Return the capability of the PCI IDE controller in 'm'.
 *
 */
- (void) getPCIControllerCapabilities:(txferModes_t *)m
{
	m->mode.swdma = m->mode.mwdma = m->mode.udma = ATA_MODE_NONE;
	switch (_controllerID) {
		case PCI_ID_PIIX:
		case PCI_ID_PIIX3:
		case PCI_ID_PIIX4:
		case PCI_ID_PIIX4E:
		case PCI_ID_PIIX4M:
			m->mode.pio   = ata_mode_to_mask(ATA_MODE_4);
			if (_busMaster) {
				m->mode.mwdma = ata_mode_to_mask(ATA_MODE_2);
				if ((_controllerID == PCI_ID_PIIX4) ||
				    (_controllerID == PCI_ID_PIIX4E) ||
				    (_controllerID == PCI_ID_PIIX4M))
					m->mode.udma = ata_mode_to_mask(ATA_MODE_2);
			}
			break;
	}
}

/*
 * Get the PIO port transfer width. This refers to the width of the
 * I/O transfer on the PIO port, the IDE bus width is always 16-bits.
 *
 * All PIIX controllers are capable of 32-bit transfers on the data
 * port.
 */
- (ideTransferWidth_t) getPIOTransferWidth
{
	return (IDE_TRANSFER_32_BIT);
}

/*
 * Method: resetPCIController
 *
 * Not a true RESET, simply return the PCI controller to a quiescent state
 * and return all IDE ports to the default timing.
 */
- (void) resetPCIController
{
	switch (_controllerID) {
		case PCI_ID_PIIX:
		case PCI_ID_PIIX3:
		case PCI_ID_PIIX4:
		case PCI_ID_PIIX4E:
		case PCI_ID_PIIX4M:
			[self PIIXInit];
			[self PIIXResetTimings:[self deviceDescription]];
			break;
	}
}

/*
 * Method: PIIXResetTimings
 *
 * Purpose:
 * Revert the timing register to the default value. The transfer timing
 * is set to the compatible mode. We need to be careful to initialize the
 * register only for our current IDE channel.
 */
- (void) PIIXResetTimings:(IOPCIDeviceDescription *)devDesc
{
	union {
		u_long dword;
		struct {
			piix_idetim_u pri;
			piix_idetim_u sec;
		} tim;
	} timings;

    IOReturn rtn;
	u_long udma;

	/*
	 * Read the PIIX_IDETIM register.
	 */	
	rtn = [[self class] getPCIConfigData:&timings.dword
		atRegister:PIIX_IDETIM
		withDeviceDescription:devDesc];
    if (rtn != IO_R_SUCCESS)
		return;

	/*
	 * Read both PIIX_UDMACTL and PIIX_UDMATIM register.
	 */
	rtn = [[self class] getPCIConfigData:&udma atRegister:PIIX_UDMACTL
		withDeviceDescription:devDesc];

	/*
	 * Set compatible timing.
	 * Disable UDDMA and set its timing registers to the slowest mode.
	 */	
	switch (_ideChannel) {
		case PCI_CHANNEL_PRIMARY:
			timings.tim.pri.word &= 0x8000;
			udma &= 0xffccfffc;
			break;
		case PCI_CHANNEL_SECONDARY:
			timings.tim.sec.word &= 0x8000;
			udma &= 0xccfffff3;
			break;
		default:
			return;
	}
	
	/*
	 * Write the modified PCI config space registers back.
	 */
	[[self class] setPCIConfigData:timings.dword atRegister:PIIX_IDETIM
		withDeviceDescription:devDesc];
	[[self class] setPCIConfigData:udma atRegister:PIIX_UDMACTL
		withDeviceDescription:devDesc];
}

/*
 * Method: PIIXReportTimings:slaveTiming:isPrimary:
 *
 * Purpose:
 * Log the drive timings set in the two PIIX timing registers.
 * The units for the values are in PCI clocks.
 */
- (void) PIIXReportTimings:(piix_idetim_u)tim
              slaveTiming:(piix_sidetim_u)stim
                isPrimary:(BOOL)primary
{
	if (!_ide_debug)
		return;

	IOLog("%s: Drive 0: ISP:%d Clks RCT:%d Clks\n",
		[self name],
		PIIX_ISP_TO_CLK(tim.bits.isp),
		PIIX_RCT_TO_CLK(tim.bits.rct));
#if 0
	IOLog("%s: Drive 0 Fast timing DMA only: %s\n", [self name],
		tim.bits.dte0 ? "on" : "off");
	IOLog("%s: Drive 0 Prefetch and Posting: %s\n", [self name],
		tim.bits.ppe0 ? "on" : "off");
	IOLog("%s: Drive 0 IORDY sample enable : %s\n", [self name],
		tim.bits.ie0 ? "on" : "off");
	IOLog("%s: Drive 0 Fast timing enable  : %s\n", [self name],
		tim.bits.time0 ? "on" : "off");
#endif 0
	IOLog("%s: Drive 1: ISP:%d Clks RCT:%d Clks\n", [self name],
		tim.bits.sitre ?
			(primary ?
				PIIX_ISP_TO_CLK(stim.bits.pisp1) : 
				PIIX_ISP_TO_CLK(stim.bits.sisp1)) : 
			PIIX_ISP_TO_CLK(tim.bits.isp),
		tim.bits.sitre ?
			(primary ?
				PIIX_RCT_TO_CLK(stim.bits.prct1) :
				PIIX_RCT_TO_CLK(stim.bits.srct1)) :
			PIIX_RCT_TO_CLK(tim.bits.rct));
#if 0
	IOLog("%s: Drive 1 Fast timing DMA only: %s\n", [self name],
		tim.bits.dte1 ? "on" : "off");
	IOLog("%s: Drive 1 Prefetch and Posting: %s\n", [self name],
		tim.bits.ppe1 ? "on" : "off");
	IOLog("%s: Drive 1 IORDY sample enable : %s\n", [self name],
		tim.bits.ie1 ? "on" : "off");
	IOLog("%s: Drive 1 Fast timing enable  : %s\n", [self name],
		tim.bits.time1 ? "on" : "off");
#endif 0
}

/*
 * Method: setPCIControllerCapabilities
 *
 * Purpose:
 * Based on the transfer modes and types for both IDE drives, setup the
 * controller to support those modes.
 *
 */
- (BOOL) setPCIControllerCapabilitiesForDrives:(driveInfo_t *)drives
{
	IOPCIConfigSpace configSpace;

	if (_controllerID == PCI_ID_NONE)
		return NO;

	[self getPCIConfigSpace:&configSpace];

	switch (_controllerID) {
		case PCI_ID_PIIX:
		case PCI_ID_PIIX3:
		case PCI_ID_PIIX4:
		case PCI_ID_PIIX4E:
		case PCI_ID_PIIX4M:
			[self PIIXComputePCIConfigSpace:&configSpace forDrives:drives];
			break;
		default:
			return NO;
	}

	[self setPCIConfigSpace:&configSpace];
    return YES;
}

/*
 * Method: computePCIConfigSpaceForPIIX:modes:
 *
 * Purpose:
 * Set the IDETIM and the SIDETIM IDE timing registers based on the
 * PIO modes supported by the two drives on the IDE channel.
 */
- (void) PIIXComputePCIConfigSpace:(IOPCIConfigSpace *)configSpace
		forDrives:(driveInfo_t *)drv
{
	u_char *pci_space = (u_char *)configSpace;
    piix_idetim_u	*idetim;
	piix_sidetim_u  *sidetim;
	piix_udmactl_u	*udmactl;
	piix_udmatim_u  *udmatim;
	unsigned char	modeDrive0;
	unsigned char	modeDrive1;
	u_char 			isp, rct;

	if (MAX_IDE_DRIVES != 2)
		return;
	
	switch (_ideChannel) {
		case PCI_CHANNEL_PRIMARY:
			idetim = (piix_idetim_u	*)&pci_space[PIIX_IDETIM];
			break;
		case PCI_CHANNEL_SECONDARY:
			idetim = (piix_idetim_u	*)&pci_space[PIIX_IDETIM_S];
			break;
		default:
			IOLog("%s: PIIX: Unknown IDE channel\n", [self name]);
			return;
	}
	sidetim = (piix_sidetim_u *)&pci_space[PIIX_SIDETIM];
	udmactl = (piix_udmactl_u *)&pci_space[PIIX_UDMACTL];
	udmatim = (piix_udmatim_u *)&pci_space[PIIX_UDMATIM];

	modeDrive0 = ata_mode_to_num(drv[0].transferMode);
	modeDrive1 = ata_mode_to_num(drv[1].transferMode);
	
	/* Enable slave timing if timings are different and
	 * a slave device is present.
	 */
	idetim->bits.sitre = 0;
	isp = PIIXGetISPForMode(modeDrive0, drv[0].transferType);
	rct = PIIXGetRCTForMode(modeDrive0, drv[0].transferType);
	
	if ((PIIXGetCycleForMode(modeDrive0, drv[0].transferType) != 
		PIIXGetCycleForMode(modeDrive1, drv[1].transferType)) &&
		(drv[1].ideInfo.type != 0)) {
		if (_controllerID == PCI_ID_PIIX) {
			/* Do not have the luxury of separate timing register for
			 * drive 0 and drive 1. Use the minimum of the two PIO modes.
			 * Or, the max of the two timings.
			 */
			isp = MAX(PIIXGetISPForMode(modeDrive0, drv[0].transferType),
				      PIIXGetISPForMode(modeDrive1, drv[1].transferType));
			rct = MAX(PIIXGetRCTForMode(modeDrive0, drv[0].transferType),
				      PIIXGetRCTForMode(modeDrive1, drv[1].transferType));			
		}
		else
			idetim->bits.sitre = 1;		// enable slave timing
	}
	
	/*
	 * Reset all performance tuning bits and disable UDMA.
	 */
	idetim->word &= 0xc000;
	switch (_ideChannel) {
		case PCI_CHANNEL_PRIMARY:
			udmactl->bits.psde0 = 0;
			udmactl->bits.psde1 = 0;
			break;
		default:
			udmactl->bits.ssde0 = 0;
			udmactl->bits.ssde1 = 0;
	}

	/*
	 * Set the timings for drive 0 (master).
	 */
	if (drv[0].ideInfo.type == 0) {
		IOLog("%s: Drive 0 is not present\n", [self name]);
		return;
	}

	/*
	 * Set timings for Drive 0 (Master drive).
	 */
	if (drv[0].transferType == IDE_TRANSFER_ULTRA_DMA) {
		if (modeDrive0 > 2) modeDrive0 = 2;
		switch (_ideChannel) {
			case PCI_CHANNEL_PRIMARY:
				udmactl->bits.psde0 = 1;
				udmatim->bits.pct0 = modeDrive0;
				break;
			case PCI_CHANNEL_SECONDARY:
				udmactl->bits.ssde0 = 1;
				udmatim->bits.sct0 = modeDrive0;
				break;
			default:
				break;
		}
	}
	idetim->bits.isp = isp;
	idetim->bits.rct = rct;
	
	/* Set timings for drive 1 (Slave drive).
	 */
	if (drv[1].transferType == IDE_TRANSFER_ULTRA_DMA) {
		if (modeDrive1 > 2) modeDrive1 = 2;
		switch (_ideChannel) {
			case PCI_CHANNEL_PRIMARY:
				udmactl->bits.psde1 = 1;
				udmatim->bits.pct1 = modeDrive1;
				break;
			case PCI_CHANNEL_SECONDARY:
				udmactl->bits.ssde1 = 1;
				udmatim->bits.sct1 = modeDrive1;
				break;
			default:
				break;
		}
	}
	if (idetim->bits.sitre) {
		isp = PIIXGetISPForMode(modeDrive1, drv[1].transferType);
		rct = PIIXGetRCTForMode(modeDrive1, drv[1].transferType);	
		if (_ideChannel == PCI_CHANNEL_PRIMARY) {
			sidetim->bits.pisp1 = isp;
			sidetim->bits.prct1 = rct;
		}
		else {
			sidetim->bits.sisp1 = isp;
			sidetim->bits.srct1 = rct;
		}
	}

	/*
	 * Enable fast timings. Turn on IORDY sampling always?
	 */
	idetim->bits.time0 = 1;
	idetim->bits.ppe0  = 1;
	idetim->bits.ie0   = 1;
	if (drv[1].ideInfo.type != 0) {
		idetim->bits.time1 = 1;
		idetim->bits.ppe1  = 1;
		idetim->bits.ie1   = 1;
	}

	/*
	 * For DMA, disable fast timing for PIO.
	 */
	if (drv[0].transferType != IDE_TRANSFER_PIO)
		idetim->bits.dte0 = 1;
	if (drv[1].transferType != IDE_TRANSFER_PIO)
		idetim->bits.dte1 = 1;

	[self PIIXReportTimings:*idetim slaveTiming:*sidetim 
		isPrimary:(_ideChannel == PCI_CHANNEL_PRIMARY)];

	return;
}

/*
 * Method: PIIXInit
 *
 * Purpose:
 * Initializes the PIIX controller.
 */
- (void) PIIXInit
{
	return (bmStopDMA(_bmRegs));
}

/*
 * Method: PIIXDetect80WireCable
 *
 * Purpose:
 * Detect the presence of an 80-wire cable. This is required for UDMA
 * modes greater than Mode 2 (ATA/33). Unfortunately, PIIX4 does not
 * provide a hardware mechanism to detect cable type. We assume a
 * 40-wire cable by default for safety.
 *
 * Note:
 * Some BIOS implementations may set a bit in a vendor-specific register,
 * but this is not standardized across all PIIX4 implementations.
 * Later chipsets (ICH and newer) provide proper cable detection via
 * the UDMA Control Register.
 *
 * For now, we conservatively assume 40-wire cable, which limits UDMA
 * to Mode 2 (33 MB/s). Users can potentially override this via a
 * configuration option if needed.
 */
- (BOOL) PIIXDetect80WireCable:(IOPCIDeviceDescription *)devDesc
{
	if (_ide_debug) {
		IOLog("%s: Cable detection: assuming 40-wire cable (UDMA limited to Mode 2)\n",
			[self name]);
	}
	return NO;
}

@end
