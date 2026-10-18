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

/*
 * PowerSupply.m - redundant power supply monitor.
 *
 * Matches the "redundant-power-supply" device tree node.  The supply
 * raises interrupt 36 when one of its units fails; the handler masks
 * the interrupt and clears gPowerSupplyGood, which hw.powersupply
 * reports.  gPowerSupplyGood stays -1 when no such supply is present.
 *
 * HISTORY
 *
 * 17 Oct 2026
 *	Reconstructed from the Mac OS X Server 1.2v3 (5.6) mach_kernel.
 */

#import <driverkit/IODirectDevice.h>
#import <machdep/ppc/interrupts.h>
#import <machdep/ppc/machspl.h>

#define POWER_SUPPLY_INTERRUPT	36

@interface PowerSupply : IODirectDevice
@end

int gPowerSupplyGood = -1;

void
PowerSupplyHandler(int device, void *ssp, void *arg)
{
	pmac_disable_irq(POWER_SUPPLY_INTERRUPT);
	gPowerSupplyGood = 0;
}

@implementation PowerSupply

+ (BOOL)probe:deviceDescription
{
	return [[self alloc] initFromDeviceDescription:deviceDescription] != nil;
}

- initFromDeviceDescription:deviceDescription
{
	gPowerSupplyGood = 1;
	[self setName:"PowerSupply"];
	[self registerDevice];
	pmac_register_int(pmac_int_to_number(POWER_SUPPLY_INTERRUPT), SPLBIO,
			  PowerSupplyHandler, 0);
	return self;
}

@end
