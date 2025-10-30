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
 * EISAKernBus.m
 * EISA Kernel Bus Implementation
 */

#import "EISAKernBus.h"
#import "EISAKernBus+PlugAndPlay.h"
#import "EISAKernBus+PlugAndPlayPrivate.h"
#import "EISAKernBusInterrupt.h"
#import "eisa.h"
#import <driverkit/KernBusMemory.h>
#import <driverkit/KernDeviceDescription.h>
#import <driverkit/IOConfigTable.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <machdep/i386/intr_exported.h>
#import <machdep/i386/io_inline.h>
#import <objc/objc.h>
#import <string.h>
#import <stdlib.h>
#import <stdio.h>

/* Forward declarations for undocumented IOConfigTable methods */
@interface IOConfigTable (UndocumentedMethods)
+ newForConfigData:(const char *)configData;
@end

/* External functions in the Kernel */
extern const char *findBootConfigString(int index);

/* External variables */
extern unsigned short pnpReadPort;

/* PnP BIOS entry point variables */
extern unsigned short PnPEntry_biosCodeSelector;
extern unsigned int PnPEntry_biosCodeOffset;
extern unsigned short kernDataSel;

/* EISA I/O ports */
#define EISA_ID_PORT_BASE       0x0C80
#define EISA_CONFIG_PORT_BASE   0x0C84

/* Maximum EISA slots */
#define EISA_MAX_SLOTS          16

/* I/O port range maximum */
#define IO_PORT_MAX             0x10000

/* Memory range maximum (4GB) */
#define MEM_RANGE_MAX           0xFFFFFFFF

/* Resource key names */
#define IO_PORTS_KEY            "I/O Ports"
#define MEM_MAPS_KEY            "Memory Maps"
#define IRQ_LEVELS_KEY          "IRQ Levels"
#define DMA_CHANNELS_KEY        "DMA Channels"

/*
 * Resource names for EISA bus
 */
static const char *resourceNameStrings[] = {
    IRQ_LEVELS_KEY,
    MEM_MAPS_KEY,
    IO_PORTS_KEY,
    DMA_CHANNELS_KEY,
    NULL
};

@implementation EISAKernBus

/*
 * Class initialization
 * Called once when the class is first loaded
 * Registers the EISA bus class with the kernel
 */
+ initialize
{
    [self registerBusClass:self name:"EISA"];
    return self;
}

/*
 * Initialize EISA bus instance
 */
- init
{
    id resource;
    id resourceClass;
    int busId;

    /* Call superclass init */
    [super init];

    _eisaData = NULL;
    _slotCount = EISA_MAX_SLOTS;
    _initialized = NO;

    /* Check if PnP support is available (from PlugAndPlay category) */
    if ([self respondsTo:@selector(initializePnP)]) {
        _initialized = (BOOL)[self initializePnP];
    }

    /* Register IRQ resource - 16 IRQ lines */
    resourceClass = [objc_getClass("EISAKernBusInterrupt") class];
    resource = [[[objc_getClass("KernBusItemResource") alloc]
                 initWithItemCount:16
                          itemKind:resourceClass
                             owner:self] init];
    [self _insertResource:resource withKey:IRQ_LEVELS_KEY];

    /* Register DMA channel resource - 8 DMA channels */
    resourceClass = [objc_getClass("EISAKernBusDMAChannel") class];
    resource = [[[objc_getClass("KernBusItemResource") alloc]
                 initWithItemCount:8
                          itemKind:resourceClass
                             owner:self] init];
    [self _insertResource:resource withKey:DMA_CHANNELS_KEY];

    /* Register memory resource - Full 4GB address space (extent 0-0 means full range) */
    resourceClass = [objc_getClass("KernBusMemoryRange") class];
    resource = [[[objc_getClass("KernBusRangeResource") alloc]
                 initWithExtent:(Range){0, 0}
                           kind:resourceClass
                          owner:self] init];
    [self _insertResource:resource withKey:MEM_MAPS_KEY];

    /* Register I/O port resource - 64KB port space (0x0000-0xFFFF) */
    resourceClass = [objc_getClass("EISAKernBusPortRange") class];
    resource = [[[objc_getClass("KernBusRangeResource") alloc]
                 initWithExtent:(Range){0, IO_PORT_MAX}
                           kind:resourceClass
                          owner:self] init];
    [self _insertResource:resource withKey:IO_PORTS_KEY];

    /* Set bus ID and register with KernBus system */
    [self setBusId:0];
    busId = [self busId];
    [[self class] registerBusInstance:self name:"EISA" busId:busId];
    [self init];

    IOLog("ISA/EISA bus support enabled\n");

    return self;
}

/*
 * Free EISA bus instance
 */
- free
{
    id resource;

    /* Only free if resources are not active (not in use) */
    if ([self areResourcesActive]) {
        /* Resources still in use - cannot free */
        return self;
    }

    /* Delete and free IRQ resource */
    resource = [self _deleteResourceWithKey:IRQ_LEVELS_KEY];
    [resource free];

    /* Delete and free DMA channel resource */
    resource = [self _deleteResourceWithKey:DMA_CHANNELS_KEY];
    [resource free];

    /* Delete and free memory resource */
    resource = [self _deleteResourceWithKey:MEM_MAPS_KEY];
    [resource free];

    /* Delete and free I/O port resource */
    resource = [self _deleteResourceWithKey:IO_PORTS_KEY];
    [resource free];

    /* Free EISA data if allocated */
    if (_eisaData != NULL) {
        IOFree(_eisaData, sizeof(void *));
        _eisaData = NULL;
    }

    /* Call superclass free */
    return [super free];
}

/*
 * Get EISA slot information from device description
 * This method is called by IOEISADeviceDescription to identify the slot
 */
- (IOReturn)getEISASlotNumber:(unsigned int *)slotNum
                       slotID:(unsigned long *)slotID
      usingDeviceDescription:deviceDescription
{
    id configTable;
    const char *busType;
    const char *autoDetectIDs;
    const char *location;
    const char *instance;
    unsigned int foundSlot = 0;
    unsigned int foundID = 0;
    BOOL foundDevice = NO;
    int instanceNum = 0;
    int compareResult;

    /* Get config table from device description */
    configTable = [deviceDescription configTable];

    /* Get "Bus Type" property */
    busType = [configTable valueForStringKey:"Bus Type"];
    if (busType == NULL) {
        return IO_R_NO_DEVICE;
    }

    /* Check if bus type is "EISA" */
    compareResult = strncmp("EISA", busType, 5);
    [configTable freeString:busType];

    if (compareResult != 0) {
        /* Not an EISA device */
        return IO_R_NO_DEVICE;
    }

    /* Get "Auto Detect IDs" property */
    autoDetectIDs = [configTable valueForStringKey:"Auto Detect IDs"];
    if (autoDetectIDs == NULL) {
        return IO_R_NO_DEVICE;
    }

    /* Try to get specific location first */
    location = [configTable valueForStringKey:"Location"];
    if (location != NULL) {
        /* Check if location starts with "Slot " */
        if (strlen(location) > 6 && strncmp("Slot ", location, 5) == 0) {
            /* Parse slot number */
            char *endPtr;
            foundSlot = strtol(location + 5, &endPtr, 0);

            if (foundSlot < EISA_MAX_SLOTS) {
                /* Test this specific slot */
                foundDevice = testSlotForID(foundSlot, &foundID, autoDetectIDs);
            }
        }

        [configTable freeString:location];
    }

    /* If we found the device at a specific location, return it */
    if (foundDevice) {
        [configTable freeString:autoDetectIDs];

        if (slotNum) *slotNum = foundSlot;
        if (slotID) *slotID = foundID;

        return IO_R_SUCCESS;
    }

    /* No specific location - search by instance */
    instance = [configTable valueForStringKey:"Instance"];
    if (instance != NULL) {
        char *endPtr;
        instanceNum = strtol(instance, &endPtr, 0);
        [configTable freeString:instance];
    }

    /* Scan all slots looking for matching devices */
    for (foundSlot = 0; foundSlot < EISA_MAX_SLOTS; foundSlot++) {
        if (testSlotForID(foundSlot, &foundID, autoDetectIDs)) {
            /* Found a matching device */
            if (instanceNum <= 0) {
                /* This is the instance we want */
                [configTable freeString:autoDetectIDs];

                if (slotNum) *slotNum = foundSlot;
                if (slotID) *slotID = foundID;

                return IO_R_SUCCESS;
            }

            /* Not the right instance yet, keep looking */
            instanceNum--;
        }
    }

    /* Device not found */
    [configTable freeString:autoDetectIDs];
    return IO_R_NO_DEVICE;
}

/*
 * Test if EISA slot matches given IDs
 * Returns YES if slot is occupied and matches IDs, NO otherwise
 */
- (BOOL)testIDs:(const char *)ids slot:(unsigned int)slot
{
    BOOL result;

    /* Call helper function to test the slot */
    result = testSlotForID(slot, NULL, ids);

    return result;
}

/*
 * Get resource names supported by this bus
 */
- (const char **)resourceNames
{
    return resourceNameStrings;
}

/*
 * Allocate resources for device description
 */
- allocateResourcesForDeviceDescription:descr
{
    const char **resourceNamePtr;
    const char *resourceName;
    const char *busType;
    id result;

    if (descr == nil) {
        return nil;
    }

    /* Iterate through all resource types and allocate them */
    resourceNamePtr = [self resourceNames];

    while (resourceNamePtr != NULL && *resourceNamePtr != NULL) {
        resourceName = *resourceNamePtr;

        /* Ask device description to allocate resources for this resource type */
        result = [descr allocateResourcesForKey:resourceName];

        if (result == 0) {
            /* Allocation failed */
            return 0;
        }

        /* Move to next resource name */
        resourceNamePtr++;
    }

    /* Check if this is a PnP device and if PnP support is enabled */
    if (_initialized) {
        busType = [descr stringForKey:"Bus Type"];

        if (busType != NULL) {
            /* Compare bus type with "PnP" (4 characters including null terminator) */
            if (strncmp(busType, "PnP", 4) == 0) {
                /* This is a PnP device - use PnP-specific resource allocation */
                if ([self respondsTo:@selector(pnpSetResourcesForDescription:)]) {
                    [self pnpSetResourcesForDescription:descr];
                }
            }
        }
    }

    return descr;
}

@end

/*
 * Look for EISA ID in system (matches original Rhapsody binary implementation)
 *
 * This function searches all EISA slots (0-15) for cards matching the specified ID list.
 * Returns information about the Nth matching instance.
 *
 * This implementation uses Objective-C method dispatch to call testIDs:slot: on the
 * EISA bus instance, matching the original Rhapsody DR2 implementation.
 *
 * Parameters:
 *   param_1: Which matching instance to find (0-based)
 *   param_2: String containing list of IDs to match against
 *   param_3: Output buffer to receive "Slot N" string
 *   param_4: Pointer to receive string length (including null terminator)
 *
 * Returns:
 *   0 on success (found)
 *   0xfffffd27 (IO_R_NO_DEVICE) if not found
 */
int LookForEISAID(int param_1, const char *param_2, char *param_3, unsigned int *param_4)
{
    char cVar1;
    id uVar2;
    int iVar3;
    unsigned int uVar4;

    /* Initialize instance counter */
    iVar3 = 0;

    /* Look up the EISA bus instance */
    uVar2 = [KernBus lookupBusInstanceWithName:"EISA" busId:0];

    /* Start scanning from slot 0 */
    uVar4 = 0;

    /* Loop through all EISA slots (0-15) */
    do {
        /* Test if this slot matches the ID list */
        cVar1 = [uVar2 testIDs:param_2 slot:uVar4];

        if (cVar1 != '\0') {
            /* Found a matching slot */
            if (param_1 == iVar3) {
                /* This is the instance we're looking for */
                sprintf(param_3, "Slot %d", uVar4);
                uVar4 = 0xffffffff;
                break;
            }
            /* Not the right instance yet, increment counter */
            iVar3 = iVar3 + 1;
        }

        /* Move to next slot */
        uVar4 = uVar4 + 1;

        /* Check if we've exceeded slot 15 */
        if (0xf < uVar4) {
            /* Not found - return error */
            *param_4 = 0;
            return 0xfffffd27;  /* IO_R_NO_DEVICE */
        }
    } while (1);

    /* Calculate string length (including null terminator) */
    /* This uses the clever trick of counting down from 0xffffffff */
    while (1) {
        uVar4 = uVar4 - 1;
        cVar1 = *param_3;
        param_3 = param_3 + 1;
        if (cVar1 == '\0') break;
        if (uVar4 == 0) break;
    }

    /* Store the string length (bitwise NOT of remaining count) */
    *param_4 = ~uVar4;

    return 0;
}

/*
 * configTableLookupServerAttribute
 * Look up an attribute for a named server in the boot configuration
 *
 * @param serverName  The name of the server to look up
 * @param attribute   The attribute key to retrieve
 * @return            Allocated string with the attribute value, or NULL if not found
 *                    Caller must free the returned string with IOFree
 */
char *configTableLookupServerAttribute(const char *serverName, const char *attribute)
{
    int found;
    const char *configData;
    id configTable;
    char *serverNameValue;
    char *attributeValue;
    char *result;
    unsigned int length;
    int configIndex;

    found = 0;
    result = NULL;
    configIndex = 1;

    /* Iterate through all boot config strings */
    while (1) {
        configData = findBootConfigString(configIndex);
        if (configData == NULL) {
            /* No more config strings */
            return result;
        }

        /* Create config table from config data */
        configTable = [IOConfigTable newForConfigData:configData];

        /* Get the "Server Name" value */
        serverNameValue = (char *)[configTable valueForStringKey:"Server Name"];

        /* Check if this is the server we're looking for */
        if (strcmp(serverNameValue, serverName) == 0) {
            found = 1;

            /* Get the requested attribute */
            attributeValue = (char *)[configTable valueForStringKey:attribute];

            if (attributeValue != NULL) {
                /* Calculate string length */
                length = strlen(attributeValue);

                /* Allocate memory for the result */
                result = (char *)IOMalloc(length + 1);

                if (result != NULL) {
                    /* Copy the string */
                    strcpy(result, attributeValue);
                }

                /* Free the temporary string returned by IOConfigTable */
                [configTable freeString:attributeValue];
            }
        }

        /* Free the server name string */
        [configTable freeString:serverNameValue];

        /* Free the config table */
        [configTable free];

        configIndex++;

        if (found) {
            return result;
        }
    }
}
