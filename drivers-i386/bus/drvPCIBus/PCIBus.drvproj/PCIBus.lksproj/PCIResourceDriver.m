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
 * PCIResourceDriver.m
 * PCI Resource Driver Implementation
 */

#import "PCIResourceDriver.h"
#import "pci.h"
#import "PCIKernBus.h"

#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/KernBus.h>
#import <string.h>
#import <stdlib.h>
#import <stdio.h>

/*
 * PCI parameter prefixes
 */
static const char *pciPrefixes[] = {
    "PCI_Maximums(",
    "PCI_ConfigSpace(",
    "PCI_ConfigReg(",
    "PCI_Name(",
    "PCI_",
    "PCI_ID(",
    NULL
};

/*
 * Helper function prototypes
 */
static IOReturn Get_Maximums(unsigned int *count, char *values);
static IOReturn Get_ConfigSpace(unsigned int *count, char *values,
                                unsigned int dev, unsigned int func, unsigned int bus);
static IOReturn Get_ConfigReg(unsigned int *count, char *values, unsigned int reg,
                              unsigned int dev, unsigned int func, unsigned int bus);
static IOReturn LookForID(unsigned long idValue, char *nameBuffer,
                          char *values, unsigned int *count);
static IOReturn Set_ConfigSpace(unsigned int count, char *values,
                                unsigned int dev, unsigned int func, unsigned int bus);
static void Set_ConfigReg(unsigned int count, char *values, unsigned int reg,
                          unsigned int dev, unsigned int func, unsigned int bus);

/*
 * ============================================================================
 * PCIResourceDriver Implementation
 * ============================================================================
 */

@implementation PCIResourceDriver

/*
 * Probe for PCI bus presence
 * Returns YES if PCI is available and driver can be initialized
 */
+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    id pciBus;
    id driver;

    /* Lookup PCI bus instance */
    pciBus = [KernBus lookupBusInstanceWithName:"PCI" busId:0];
    if (pciBus != nil) {
        /* Check if PCI is present */
        if ([pciBus isPCIPresent]) {
            /* Try to allocate and initialize driver */
            driver = [[PCIResourceDriver alloc] initFromDeviceDescription:deviceDescription];
            if (driver != nil) {
                return YES;
            }
        }
    }

    return NO;
}

/*
 * Get character values for a parameter
 */
- (IOReturn)getCharValues:(char *)values
             forParameter:(IOParameterName)parameterName
                    count:(unsigned int *)count
{
    id pciBus;
    char *parsedStr = NULL;
    unsigned int prefixIndex = 0;
    unsigned int dev = 0, func = 0, bus = 0, reg = 0;
    unsigned int maxDev, maxBus;
    unsigned long idValue;

    if (count == NULL || *count == 0) {
        return [super getCharValues:values forParameter:parameterName count:count];
    }

    /* Lookup PCI bus instance */
    pciBus = [KernBus lookupBusInstanceWithName:"PCI" busId:0];

    /* Try to match parameter name against known PCI prefixes */
    for (prefixIndex = 0; prefixIndex < 6; prefixIndex++) {
        parsedStr = PCIParsePrefix((char *)pciPrefixes[prefixIndex], (char *)parameterName);
        if (parsedStr != NULL) {
            break;
        }
    }

    /* Get max device and bus numbers from PCI bus */
    maxDev = [pciBus maxDevNum];
    maxBus = [pciBus maxBusNum];

    switch (prefixIndex) {
    case 0:  /* PCI_Maximums( */
        if (*count > 1) {
            return Get_Maximums(count, values);
        }
        break;

    case 1:  /* PCI_ConfigSpace( */
        if (*count > 3) {
            if (PCIParseKeys(parsedStr, (unsigned long *)&dev, &func, &bus, NULL)) {
                if (dev <= maxDev && func < 8 && bus <= maxBus) {
                    return Get_ConfigSpace(count, values, dev, func, bus);
                }
            }
        }
        break;

    case 2:  /* PCI_ConfigReg( */
        if (*count > 3) {
            if (PCIParseKeys(parsedStr, (unsigned long *)&dev, &func, &bus, &reg)) {
                if (dev <= maxDev && func < 8 && bus <= maxBus && reg < 256) {
                    return Get_ConfigReg(count, values, reg, dev, func, bus);
                }
            }
        }
        break;

    case 3:  /* PCI_Name( */
        /* Clear name buffer */
        _nameBufferLen = 0;
        bzero(_nameBuffer, sizeof(_nameBuffer));

        /* Parse closing parenthesis */
        parsedStr = PCIParsePrefix("PCI)", parsedStr);
        if (parsedStr == NULL) {
            return IO_R_INVALID_ARG;
        }
        /* Fall through to case 4 */

    case 4:  /* PCI_ */
        /* Copy name from parsedStr to buffer */
        while (parsedStr < (char *)parameterName + 64 &&
               *parsedStr != '\0' &&
               _nameBufferLen < 511) {
            _nameBuffer[_nameBufferLen++] = *parsedStr++;
        }
        _nameBuffer[_nameBufferLen] = '\0';

        /* Copy to output */
        strncpy(values, _nameBuffer, *count);
        return IO_R_SUCCESS;

    case 5:  /* PCI_ID( */
        if (*count >= 80) {
            if (_nameBuffer[0] == '\0') {
                return IO_R_INVALID_ARG;
            }
            idValue = strtoul(parsedStr, &parsedStr, 0);
            return LookForID(idValue, _nameBuffer, values, count);
        }
        break;

    default:
        /* No match - call super implementation */
        return [super getCharValues:values forParameter:parameterName count:count];
    }

    return IO_R_INVALID_ARG;
}

/*
 * Initialize from device description
 */
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    id result;

    result = [super initFromDeviceDescription:deviceDescription];
    if (result != nil) {
        IOLog("PCI bus support enabled\n");
        [self setName:"PCI0"];
        [self setDeviceKind:"Bus"];
        [self registerDevice];
    }

    return result;
}

/*
 * Set character values for a parameter
 */
- (IOReturn)setCharValues:(unsigned char *)values
             forParameter:(IOParameterName)parameterName
                    count:(unsigned int)count
{
    id pciBus;
    char *parsedStr = NULL;
    unsigned int prefixIndex = 0;
    unsigned int dev = 0, func = 0, bus = 0, reg = 0;
    unsigned int maxDev, maxBus;

    if (count == 0) {
        return [super setCharValues:values forParameter:parameterName count:count];
    }

    /* Lookup PCI bus instance */
    pciBus = [KernBus lookupBusInstanceWithName:"PCI" busId:0];

    /* Try to match parameter name against known PCI prefixes */
    for (prefixIndex = 0; prefixIndex < 6; prefixIndex++) {
        parsedStr = PCIParsePrefix((char *)pciPrefixes[prefixIndex], (char *)parameterName);
        if (parsedStr != NULL) {
            break;
        }
    }

    /* Get max device and bus numbers from PCI bus */
    maxDev = [pciBus maxDevNum];
    maxBus = [pciBus maxBusNum];

    switch (prefixIndex) {
    case 1:  /* PCI_ConfigSpace( */
        if (count > 3) {
            if (PCIParseKeys(parsedStr, (unsigned long *)&dev, &func, &bus, NULL)) {
                if (dev <= maxDev && func < 8 && bus <= maxBus) {
                    return Set_ConfigSpace(count, (char *)values, dev, func, bus);
                }
            }
        }
        return IO_R_INVALID_ARG;

    case 2:  /* PCI_ConfigReg( */
        if (count > 3) {
            if (PCIParseKeys(parsedStr, (unsigned long *)&dev, &func, &bus, &reg)) {
                if (dev <= maxDev && func < 8 && bus <= maxBus && reg < 256) {
                    Set_ConfigReg(count, (char *)values, reg, dev, func, bus);
                    return IO_R_SUCCESS;
                }
            }
        }
        return IO_R_INVALID_ARG;

    default:
        /* No match or unsupported operation - call super */
        return [super setCharValues:values forParameter:parameterName count:count];
    }
}

@end

/*
 * ============================================================================
 * Helper Functions
 * ============================================================================
 */

static IOReturn Get_Maximums(unsigned int *count, char *values)
{
    id pciBus;
    unsigned char maxBusNum, maxDevNum;

    /* Lookup PCI bus instance */
    pciBus = [KernBus lookupBusInstanceWithName:"PCI" busId:0];

    /* Set count to 2 (returning 2 values) */
    *count = 2;

    /* Get maximums from PCI bus */
    maxBusNum = [pciBus maxBusNum];
    maxDevNum = [pciBus maxDevNum];

    /* Store in values array */
    values[0] = maxDevNum;  /* Max device number */
    values[1] = maxBusNum;  /* Max bus number */

    return IO_R_SUCCESS;
}

static IOReturn Get_ConfigSpace(unsigned int *count, char *values,
                                unsigned int dev, unsigned int func, unsigned int bus)
{
    id pciBus;
    IOReturn result;
    unsigned int offset;

    /* Lookup PCI bus instance */
    pciBus = [KernBus lookupBusInstanceWithName:"PCI" busId:0];

    /* Align count to DWORD boundary (mask off lower 2 bits) */
    *count = *count & 0xFFFC;

    /* Limit to 256 bytes */
    if (*count > 256) {
        *count = 256;
    }

    /* Read config space 4 bytes at a time */
    for (offset = 0; offset < *count; offset += 4) {
        result = [pciBus getRegister:(unsigned char)(offset & 0xFF)
                              device:(unsigned char)dev
                            function:(unsigned char)func
                                 bus:(unsigned char)bus
                                data:(unsigned long *)(values + offset)];

        if (result != IO_R_SUCCESS) {
            return result;
        }
    }

    return IO_R_SUCCESS;
}

static IOReturn Get_ConfigReg(unsigned int *count, char *values, unsigned int reg,
                              unsigned int dev, unsigned int func, unsigned int bus)
{
    id pciBus;
    IOReturn result;

    /* Lookup PCI bus instance */
    pciBus = [KernBus lookupBusInstanceWithName:"PCI" busId:0];

    /* Read the config register */
    result = [pciBus getRegister:(unsigned char)reg
                          device:(unsigned char)dev
                        function:(unsigned char)func
                             bus:(unsigned char)bus
                            data:(unsigned long *)values];

    if (result == IO_R_SUCCESS) {
        /* Set count to 4 (returning 4 bytes) */
        *count = 4;
    }

    return result;
}

static IOReturn LookForID(unsigned long idValue, char *nameBuffer,
                          char *values, unsigned int *count)
{
    id pciBus;
    unsigned int bus, dev, func;
    unsigned int maxBus, maxDev;
    unsigned long vendorDeviceID;
    unsigned long headerType;
    int instanceCounter = 0;
    char *ptr;
    unsigned int strLen;

    /* Lookup PCI bus instance */
    pciBus = [KernBus lookupBusInstanceWithName:"PCI" busId:0];

    /* Scan all PCI devices */
    for (bus = 0; ; bus++) {
        maxBus = [pciBus maxBusNum];
        if (bus > maxBus) {
            /* Not found */
            *count = 0;
            return IO_R_INVALID_ARG;
        }

        maxDev = [pciBus maxDevNum];
        for (dev = 0; dev <= maxDev; dev++) {
            for (func = 0; func < 8; func++) {
                /* Read vendor/device ID */
                [pciBus getRegister:0
                            device:(unsigned char)dev
                          function:(unsigned char)func
                               bus:(unsigned char)bus
                              data:&vendorDeviceID];

                /* Mask to vendor ID (lower 16 bits) */
                vendorDeviceID = vendorDeviceID & 0xFFFF;

                /* Check if device exists */
                if (vendorDeviceID != 0xFFFF && vendorDeviceID != 0) {
                    /* Test if this device matches the ID pattern */
                    if ([pciBus testIDs:(unsigned int *)nameBuffer
                                    dev:dev
                                    fun:func
                                    bus:bus]) {
                        /* Found matching device */
                        if (idValue == instanceCounter) {
                            /* This is the instance we're looking for */
                            sprintf(values, "Dev:%d Func:%d Bus:%d", dev, func, bus);

                            /* Calculate string length */
                            strLen = 0xFFFFFFFF;
                            ptr = values;
                            while (1) {
                                strLen--;
                                if (*ptr == '\0') break;
                                ptr++;
                                if (strLen == 0) break;
                            }
                            *count = ~strLen;

                            return IO_R_SUCCESS;
                        }
                        instanceCounter++;
                    }

                    /* Check if multi-function device */
                    [pciBus getRegister:0x0C
                                device:(unsigned char)dev
                              function:(unsigned char)func
                                   bus:(unsigned char)bus
                                  data:&headerType];

                    /* If not multi-function (bit 23 clear), skip remaining functions */
                    if ((headerType & 0x800000) == 0) {
                        break;
                    }
                }
            }
        }
    }
}

static IOReturn Set_ConfigSpace(unsigned int count, char *values,
                                unsigned int dev, unsigned int func, unsigned int bus)
{
    id pciBus;
    IOReturn result;
    unsigned int offset;
    unsigned int alignedCount;

    /* Lookup PCI bus instance */
    pciBus = [KernBus lookupBusInstanceWithName:"PCI" busId:0];

    /* Align count to DWORD boundary (mask off lower 2 bits) */
    alignedCount = count & 0xFFFC;

    /* Limit to 256 bytes */
    if (alignedCount > 256) {
        alignedCount = 256;
    }

    /* Write config space 4 bytes at a time */
    offset = 0;
    if (alignedCount != 0) {
        do {
            result = [pciBus setRegister:(unsigned char)(offset & 0xFF)
                                  device:(unsigned char)dev
                                function:(unsigned char)func
                                     bus:(unsigned char)bus
                                    data:*(unsigned long *)(values + offset)];

            if (result != IO_R_SUCCESS) {
                return result;
            }

            offset += 4;
        } while (offset < alignedCount);
    }

    return IO_R_SUCCESS;
}

static void Set_ConfigReg(unsigned int count, char *values, unsigned int reg,
                          unsigned int dev, unsigned int func, unsigned int bus)
{
    id pciBus;

    /* Lookup PCI bus instance */
    pciBus = [KernBus lookupBusInstanceWithName:"PCI" busId:0];

    /* Write the config register */
    [pciBus setRegister:(unsigned char)reg
                 device:(unsigned char)dev
               function:(unsigned char)func
                    bus:(unsigned char)bus
                   data:*(unsigned long *)values];

    return;
}
