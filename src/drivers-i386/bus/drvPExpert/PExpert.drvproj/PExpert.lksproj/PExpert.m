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
 * PExpert.m
 * i386 platform expert.
 *
 * One loadable, PExpert_reloc, carries every i386 bus driver.  The kernel
 * probes one "Bus Class" per config table, so this class stands in front
 * of the buses: probeBus: brings each of them up in turn, and the
 * "Class Names" of the same table register the EISA0, PCI0 and PCMCIA0
 * resource devices that Configure.app and driverLoader talk to.
 */

#import "PExpert.h"
#import "eisa/EISAKernBus.h"
#import "pci/PCIKernBus.h"
#import "pcmcia/PCMCIAKernBus.h"

#import <driverkit/KernBus.h>
#import <driverkit/IOConfigTable.h>
#import <driverkit/generalFuncs.h>
#import <string.h>
#import <stdlib.h>

/* Kernel-private IOConfigTable constructor and the booter's table list */
@interface IOConfigTable (UndocumentedMethods)
+ newForConfigData:(const char *)configData;
@end

extern const char *findBootConfigString(int index);

/*
 * Ports decoded by the motherboard's own controllers: the two 8237 DMA
 * controllers, the two 8259 interrupt controllers, the 8254 timer, the
 * CMOS RTC, the DMA page registers and port 92.  IRQ 2 is the 8259
 * cascade line.  Apple's EISABus table claimed these through its EISA0
 * device; with one table shared by every resource driver they cannot
 * live there (the second driver's allocation would fail), so the
 * platform expert claims them on the EISA bus directly.
 */
static const Range motherboardPorts[] = {
    { 0x00, 0x10 },	/* DMA controller 1 */
    { 0x20, 0x02 },	/* interrupt controller 1 */
    { 0x40, 0x0c },	/* timer */
    { 0x70, 0x02 },	/* CMOS RTC */
    { 0x81, 0x0f },	/* DMA page registers */
    { 0x92, 0x01 },	/* port 92 */
    { 0xc0, 0x10 },	/* DMA controller 2 */
};

#define MOTHERBOARD_IRQ		2

@implementation PExpert

/*
 * Bring one bus up.  probeBus: on a KernBus subclass allocates and
 * initializes the bus, and the bus registers itself under `name` if the
 * hardware is there; so whether it is there is read back from KernBus.
 */
+ (BOOL)bringUp:busClass named:(const char *)name withTable:configTable
{
    [busClass probeBus:configTable];

    if ([KernBus lookupBusInstanceWithName:(char *)name busId:0] == nil) {
	IOLog("PExpert: no %s bus\n", name);
	return NO;
    }
    return YES;
}

+ (void)reserveMotherboardResources
{
    id eisaBus, ports, irqs;
    unsigned int i;

    eisaBus = [KernBus lookupBusInstanceWithName:"EISA" busId:0];
    if (eisaBus == nil)
	return;

    ports = [eisaBus _lookupResourceWithKey:"I/O Ports"];
    for (i = 0; i < sizeof(motherboardPorts) / sizeof(motherboardPorts[0]); i++) {
	if ([ports reserveRange:motherboardPorts[i]] == nil) {
	    IOLog("PExpert: could not reserve ports 0x%x-0x%x\n",
		  motherboardPorts[i].base,
		  motherboardPorts[i].base + motherboardPorts[i].length - 1);
	}
    }

    irqs = [eisaBus _lookupResourceWithKey:"IRQ Levels"];
    if ([irqs reserveItem:MOTHERBOARD_IRQ] == nil)
	IOLog("PExpert: could not reserve IRQ %d\n", MOTHERBOARD_IRQ);
}

/*
 * Order matters.  EISA is the kernel's default bus and PCI hands its
 * resource allocation to it, so EISA comes up first and the motherboard's
 * resources are claimed before any other bus or driver can ask for them.
 *
 * To add a bus: give it a directory beside eisa/, pci/ and pcmcia/, list
 * its sources in the Makefile, add its resource driver to "Class Names"
 * in Default.table, and add a line here.
 */
+ (BOOL)probeBus:configTable
{
    BOOL up = NO;

    if ([self bringUp:[EISAKernBus class] named:"EISA" withTable:configTable])
	up = YES;
    [self reserveMotherboardResources];

    if ([self bringUp:[PCIKernBus class] named:"PCI" withTable:configTable])
	up = YES;
    if ([self bringUp:[PCMCIAKernBus class] named:"PCMCIA" withTable:configTable])
	up = YES;

    return up;
}

@end

/*
 * Walk the booter's config tables for the one whose "Server Name" is ours
 * and whose "Instance" is `instance`, and copy out `key`.
 */
char *PExpertServerAttribute(int instance, const char *key)
{
    int index;
    const char *configData;
    id configTable;
    const char *serverName, *instanceString, *value;
    char *result = NULL;
    BOOL found = NO;

    for (index = 1; !found; index++) {
	configData = findBootConfigString(index);
	if (configData == NULL)
	    break;

	configTable = [IOConfigTable newForConfigData:configData];
	serverName = [configTable valueForStringKey:"Server Name"];
	instanceString = [configTable valueForStringKey:"Instance"];

	if (serverName != NULL
	    && strcmp(serverName, PEXPERT_SERVER_NAME) == 0
	    && (instanceString != NULL ? strtol(instanceString, NULL, 0) : 0) == instance) {
	    found = YES;
	    value = [configTable valueForStringKey:key];
	    if (value != NULL) {
		result = (char *)IOMalloc(strlen(value) + 1);
		if (result != NULL)
		    strcpy(result, value);
		[configTable freeString:value];
	    }
	}

	if (serverName != NULL)
	    [configTable freeString:serverName];
	if (instanceString != NULL)
	    [configTable freeString:instanceString];
	[configTable free];
    }

    return result;
}
