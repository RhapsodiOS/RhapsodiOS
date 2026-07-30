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
#import "IdeVIA.h"

//#define DEBUG

#ifndef MIN
#define MIN(a,b)    ((a) < (b) ? (a) : (b))
#endif  MIN

#ifndef MAX
#define MAX(a,b)    ((a) > (b) ? (a) : (b))
#endif  MAX

/* Per-chip capabilities. Modes are ATA mode NUMBERS. */
typedef struct {
	unsigned long id;
	const char   *name;
	unsigned char maxPIO;    /* 4 for all these parts */
	unsigned char maxMWDMA;  /* 2, or ATA_MODE_NUM_NONE */
	unsigned char maxUDMA;   /* per chip, or ATA_MODE_NUM_NONE */
	unsigned int  flags;     /* CHIP_FLAG_HAS_IDECONFIG for ICH */
} intelChip_t;

static const intelChip_t intelChips[] = {
	{ 0x12308086, "PIIX",   4, 2, ATA_MODE_NUM_NONE, 0 },
	{ 0x70108086, "PIIX3",  4, 2, ATA_MODE_NUM_NONE, 0 },
	{ 0x71118086, "PIIX4",  4, 2, 2, 0 },
	{ 0x71128086, "PIIX4E", 4, 2, 2, 0 },
	{ 0x71138086, "PIIX4M", 4, 2, 2, 0 },
	{ 0x24218086, "ICH0",   4, 2, 2, CHIP_FLAG_HAS_IDECONFIG },
	{ 0x24118086, "ICH",    4, 2, 4, CHIP_FLAG_HAS_IDECONFIG },
	{ 0x244A8086, "ICH2-M", 4, 2, 5, CHIP_FLAG_HAS_IDECONFIG },
	{ 0x244B8086, "ICH2",   4, 2, 5, CHIP_FLAG_HAS_IDECONFIG },
	{ 0x248A8086, "ICH3-M", 4, 2, 5, CHIP_FLAG_HAS_IDECONFIG },
	{ 0x248B8086, "ICH3",   4, 2, 5, CHIP_FLAG_HAS_IDECONFIG },
	{ 0x24CA8086, "ICH4-M", 4, 2, 5, CHIP_FLAG_HAS_IDECONFIG },
	{ 0x24CB8086, "ICH4",   4, 2, 5, CHIP_FLAG_HAS_IDECONFIG },
	{ 0, 0, 0, 0, 0, 0 }
};

static const intelChip_t *intelLookup(unsigned long id)
{
	const intelChip_t *c;
	for (c = intelChips; c->id != 0; c++)
		if (c->id == id) return c;
	return NULL;
}

static BOOL intelMatch(id deviceDescription, unsigned long pciID, unsigned char progIf,
	ideChipCaps_t *out)
{
	const intelChip_t *c = intelLookup(pciID);
	(void)deviceDescription;
	if (c == NULL) return NO;
	out->maxPIO   = c->maxPIO;
	out->maxMWDMA = c->maxMWDMA;
	out->maxUDMA  = c->maxUDMA;
	out->flags    = c->flags | ((progIf & PCI_IDE_BUSMASTER) ? CHIP_FLAG_BUSMASTER : 0);
	out->privateData = 0;
	return YES;
}

static void intelSetTiming(id self, void *drives)
{
	IOPCIConfigSpace configSpace;
	[self getPCIConfigSpace:&configSpace];
	[self PIIXComputePCIConfigSpace:&configSpace forDrives:(driveInfo_t *)drives];
	[self setPCIConfigSpace:&configSpace];
}

static void intelResetTiming(id self)
{
	[self PIIXInit];
	[self PIIXResetTimings:[self deviceDescription]];
}

static BOOL intelDetectCable(id self)
{
	return [self PIIXDetect80WireCable:[self deviceDescription]];
}

const ideChipsetOps_t ideIntelOps = {
	"Intel PIIX/ICH",
	intelMatch,
	intelSetTiming,
	intelResetTiming,
	intelDetectCable
};

/* ICH drive number 0..3 = (channel<<1) | (drive&1). */
static __inline__ unsigned char ichDriveNum(int channel, int unit)
{
	return (unsigned char)(((channel == PCI_CHANNEL_SECONDARY) ? 2 : 0) | (unit & 1));
}

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

	{
	unsigned long classReg;
	unsigned char progIf, subClass, baseClass;

	rtn = [self_class getPCIConfigData:&classReg atRegister:0x08
		withDeviceDescription:devDesc];
	if (rtn != IO_R_SUCCESS) {
		IOLog("%s: PCI config space access error %d\n", [self name], rtn);
		return NO;
	}
	progIf    = (classReg >>  8) & 0xff;
	subClass  = (classReg >> 16) & 0xff;
	baseClass = (classReg >> 24) & 0xff;

	if (baseClass != PCI_CLASS_MASS_STORAGE || subClass != PCI_SUBCLASS_IDE) {
		IOLog("%s: not a PCI IDE controller (class 0x%02x/0x%02x)\n",
			[self name], baseClass, subClass);
		return NO;
	}
	if (ideIntelOps.match(devDesc, _controllerID, progIf, &_chipCaps)) {
		_chipsetOps = &ideIntelOps;
	} else if (ideVIAOps.match(devDesc, _controllerID, progIf, &_chipCaps)) {
		_chipsetOps = &ideVIAOps;
	} else if (ideGenericOps.match(devDesc, _controllerID, progIf, &_chipCaps)) {
		_chipsetOps = &ideGenericOps;
		IOLog("%s: Unlisted PCI IDE (0x%08lx); using generic driver\n",
			[self name], _controllerID);
	} else {
		/* IDE-class but not bus-master: fall back to legacy PIO. */
		_chipsetOps = NULL;
		_controllerID = PCI_ID_NONE;
		IOLog("%s: PCI IDE (0x%08lx) without bus-master; legacy PIO\n",
			[self name], _controllerID);
		return YES;
	}
	IOLog("%s: %s IDE Controller at Dev:%d Func:%d Bus:%d\n",
		[self name], _chipsetOps->name, devNum, funcNum, busNum);
	return ([self PIIXInitController:devDesc]);
	}
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
	if (_chipsetOps == &ideIntelOps) {
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
	if (_chipsetOps == &ideIntelOps) {
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

	_chipCaps.flags &= ~CHIP_FLAG_BUSMASTER;
	if (_busMaster)
		_chipCaps.flags |= CHIP_FLAG_BUSMASTER;

#if 0
	IOLog("%s: PCI bus master DMA: %s\n",
		[self name], busMaster ? "Enabled" : "Disabled");
#endif

	if (_chipsetOps == &ideIntelOps) {
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
	} else {
		_has80WireCable = NO;
	}

    return YES;
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
		if (!(_chipCaps.flags & CHIP_FLAG_HAS_IDECONFIG)) {
			/* PIIX4: UDMA capped at mode 2, existing UDMATIM path. */
			if (modeDrive0 > 2) modeDrive0 = 2;
		}
		/*
		 * SDMA_TIM 2-bit cycle-time value by UDMA mode m.
		 * Verified vs. ICH datasheet 290655-003 §9.1.17:
		 *   modes 0,1,2,3,4 -> 0,1,2,1,2 . (m5 -> 1 on ICH2+.)
		 */
		{
			unsigned char utim = MIN(2 - (modeDrive0 & 1), modeDrive0);
			switch (_ideChannel) {
				case PCI_CHANNEL_PRIMARY:
					udmactl->bits.psde0 = 1;
					udmatim->bits.pct0 = utim;
					break;
				case PCI_CHANNEL_SECONDARY:
					udmactl->bits.ssde0 = 1;
					udmatim->bits.sct0 = utim;
					break;
				default:
					break;
			}
		}
	}
	idetim->bits.isp = isp;
	idetim->bits.rct = rct;
	
	/* Set timings for drive 1 (Slave drive).
	 */
	if (drv[1].transferType == IDE_TRANSFER_ULTRA_DMA) {
		if (!(_chipCaps.flags & CHIP_FLAG_HAS_IDECONFIG)) {
			/* PIIX4: UDMA capped at mode 2, existing UDMATIM path. */
			if (modeDrive1 > 2) modeDrive1 = 2;
		}
		/*
		 * SDMA_TIM 2-bit cycle-time value by UDMA mode m.
		 * Verified vs. ICH datasheet 290655-003 §9.1.17:
		 *   modes 0,1,2,3,4 -> 0,1,2,1,2 . (m5 -> 1 on ICH2+.)
		 */
		{
			unsigned char utim = MIN(2 - (modeDrive1 & 1), modeDrive1);
			switch (_ideChannel) {
				case PCI_CHANNEL_PRIMARY:
					udmactl->bits.psde1 = 1;
					udmatim->bits.pct1 = utim;
					break;
				case PCI_CHANNEL_SECONDARY:
					udmactl->bits.ssde1 = 1;
					udmatim->bits.sct1 = utim;
					break;
				default:
					break;
			}
		}
	}

	/*
	 * ICH: program the IDE_CONFIG (0x54) base-clock bits for UDMA/66
	 * and UDMA/100. IDE_CONFIG is shared between the primary and
	 * secondary channels, so read-modify-write only this channel's
	 * bits. This is done directly on the configSpace snapshot (like
	 * IDETIM/SIDETIM/UDMACTL/UDMATIM above) since the caller commits
	 * the whole snapshot back via setPCIConfigSpace: -- a separate
	 * direct PCI config access here would be clobbered by that
	 * trailing write-back.
	 */
	if (_chipCaps.flags & CHIP_FLAG_HAS_IDECONFIG) {
		int u;
		for (u = 0; u < MAX_IDE_DRIVES; u++) {
			unsigned char dn = ichDriveNum(_ideChannel, u);
			unsigned char m = ata_mode_to_num(drv[u].transferMode);
			pci_space[PIIX_IDE_CONFIG] &= ~(1 << dn);
			pci_space[PIIX_IDE_CONFIG + 1] &= ~(1 << dn);
			if (drv[u].ideInfo.type != 0 &&
				drv[u].transferType == IDE_TRANSFER_ULTRA_DMA) {
				if (m >= 3) pci_space[PIIX_IDE_CONFIG] |= (1 << dn);      /* ATA/66 (modes 3-4) */
				if (m >= 5) pci_space[PIIX_IDE_CONFIG + 1] |= (1 << dn);  /* ATA/100 (mode 5)  */
			}
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
 * modes greater than Mode 2 (ATA/33). PIIX4 provides no hardware
 * mechanism to detect cable type, so we assume a 40-wire cable
 * (UDMA limited to Mode 2). ICH and newer report cable type per
 * channel via the IDE_CONFIG register (0x54).
 */
- (BOOL) PIIXDetect80WireCable:(IOPCIDeviceDescription *)devDesc
{
	unsigned long icfg = 0;
	unsigned char mask;

	if (!(_chipCaps.flags & CHIP_FLAG_HAS_IDECONFIG))
		return NO;   /* PIIX4 has no cable report; assume 40-wire (UDMA<=2) */

	if ([[self class] getPCIConfigData:&icfg atRegister:PIIX_IDE_CONFIG
			withDeviceDescription:devDesc] != IO_R_SUCCESS)
		return NO;

	mask = (_ideChannel == PCI_CHANNEL_SECONDARY)
		? PIIX_ICFG_CABLE_SEC : PIIX_ICFG_CABLE_PRI;

	if (_ide_debug)
		IOLog("%s: IDE_CONFIG 0x%04lx cable %s\n", [self name],
			icfg & 0xffff, (icfg & mask) ? "80-wire" : "40-wire");

	return (icfg & mask) ? YES : NO;
}

@end
