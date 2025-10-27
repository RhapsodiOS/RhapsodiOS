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
 * EISAResourceDriver.m
 * EISA Resource Driver Implementation
 */

#import "EISAResourceDriver.h"
#import "EISAKernBus.h"
#import "EISAKernBus+PlugAndPlay.h"
#import "PnPDeviceResources.h"
#import "eisa.h"
#import <driverkit/KernBus.h>
#import <driverkit/IODevice.h>
#import <libkern/libkern.h>
#import <machdep/i386/io_inline.h>
#import <stdio.h>
#import <string.h>

/* Parameter name keys */
static const char *keys[] = {
    "Slot(",           /* 0 - Read slot info */
    "Function(",       /* 1 - Read function info */
    "Register(",       /* 2 - Read PnP register */
    "Write(",          /* 3 - Write to PnP register */
    "Config(",         /* 4 - Read PnP config */
    "Port(",           /* 5 - Read I/O port */
    "Out(",            /* 6 - Write to I/O port */
    "IDs(",            /* 7 - Parse ID prefix */
    "",                /* 8 - continuation of IDs */
    "Instance(",       /* 9 - Lookup by instance */
    "Device(",         /* 10 - Read device config */
    "Node("            /* 11 - Read system node */
};

@implementation EISAResourceDriver

/*
 * Probe method - called to determine if driver can handle a device
 * This is a class method that attempts to create an instance
 * Returns YES if the driver can handle the device, NO otherwise
 */
+ (BOOL)probe:deviceDescription
{
    id instance;
    id result;

    /* Try to allocate and initialize an instance with the device description */
    instance = [EISAResourceDriver alloc];
    result = [instance initFromDeviceDescription:deviceDescription];

    /* Check if initialization succeeded */
    if (result == nil) {
        return NO;
    }

    return YES;
}

/*
 * Initialize from device description
 */
- initFromDeviceDescription:deviceDescription
{
    id result;

    /* Call superclass initialization */
    result = [super initFromDeviceDescription:deviceDescription];

    if (result != nil) {
        /* Set device name and kind */
        [self setName:"EISA0"];
        [self setDeviceKind:"Bus"];

        /* Register the device */
        [self registerDevice];

        /* Setup boot flag */
        [self setupBootFlag];
    }

    return result;
}

/*
 * Get character values for parameter
 */
- (IOReturn)getCharValues:(unsigned char *)parameterArray
             forParameter:(IOParameterName)parameterName
                    count:(unsigned int *)count
{
    id busInstance;
    unsigned int keyIndex;
    char *parsePtr;
    char *originalPtr;
    long slot, function, value;
    unsigned int portValue;
    unsigned short portAddr;
    char readByte;
    unsigned int copySize;
    unsigned int len;
    char localBuffer[320];

    /* Look up the EISA bus instance */
    busInstance = [KernBus lookupBusInstanceWithName:"EISA" busId:0];

    /* Find which key matches the parameter name */
    keyIndex = 0;
    parsePtr = NULL;

    do {
        parsePtr = EISAParsePrefix((char *)keys[keyIndex], (char *)parameterName);
        if (parsePtr != NULL) {
            break;
        }
        keyIndex++;
    } while (keyIndex < 12);

    /* Handle each parameter type */
    switch (keyIndex) {
    case 0: /* Slot( */
        slot = strtol(parsePtr, &parsePtr, 0);
        if (*count > 15 && getEISASlotInfo(slot, parameterArray)) {
            *count = 16;
            return IO_R_SUCCESS;
        }
        break;

    case 1: /* Function( */
        slot = strtol(parsePtr, &parsePtr, 0);
        /* Skip non-digit characters */
        while (*parsePtr != '\0' && *parsePtr < '0') {
            parsePtr++;
        }
        function = strtol(parsePtr, &parsePtr, 0);
        if (getEISAFunctionInfo(slot, function, localBuffer)) {
            copySize = *count;
            if (copySize > 0x140) {
                copySize = 0x140;
            }
            bcopy(localBuffer, parameterArray, copySize);
            *count = copySize;
            return IO_R_SUCCESS;
        }
        break;

    case 2: /* Register( */
        value = strtol(parsePtr, &parsePtr, 0);
        if (*count != 1) {
            return IO_R_INVALID_ARG;
        }
        readByte = [busInstance readPnPRegister:(value & 0xFF)];
        *parameterArray = readByte;
        return IO_R_SUCCESS;

    case 4: /* Config( */
        slot = strtol(parsePtr, &parsePtr, 0);
        readByte = [busInstance readPnPConfig:parameterArray length:count forCard:slot];
        if (readByte == 0) {
            return IO_R_INVALID_ARG;
        }
        return IO_R_SUCCESS;

    case 5: /* Port( */
        slot = strtol(parsePtr, &parsePtr, 0);
        portAddr = (unsigned short)slot;

        if (*count == 1) {
            readByte = inb(portAddr);
            *parameterArray = readByte;
            return IO_R_SUCCESS;
        } else if (*count == 2) {
            portValue = inw(portAddr);
            *(unsigned short *)parameterArray = (unsigned short)portValue;
            return IO_R_SUCCESS;
        } else if (*count == 4) {
            portValue = inw(portAddr);
            *(unsigned int *)parameterArray = portValue & 0xFFFF;
            return IO_R_SUCCESS;
        }
        return IO_R_INVALID_ARG;

    case 7: /* IDs( - parse EISA or PnP prefix */
        _bufferLength = 0;
        bzero(_idBuffer, 512);

        originalPtr = EISAParsePrefix("EISA)", parsePtr);
        if (originalPtr == NULL) {
            parsePtr = EISAParsePrefix("PnP)", parsePtr);
            if (parsePtr == NULL) {
                return IO_R_INVALID;
            }
            _isEISA = NO;
        } else {
            _isEISA = YES;
            parsePtr = originalPtr;
        }
        /* Fall through to case 8 */

    case 8: /* Continue building ID string */
        while (parsePtr < parameterName + 64 && *parsePtr != '\0' && _bufferLength < 0x1FF) {
            _idBuffer[_bufferLength] = *parsePtr;
            _bufferLength++;
            parsePtr++;
        }
        _idBuffer[_bufferLength] = '\0';
        strncpy((char *)parameterArray, _idBuffer, *count);
        return IO_R_SUCCESS;

    case 9: /* Instance( */
        if (*count < 80) {
            return IO_R_INVALID_ARG;
        }

        if (_idBuffer[0] != '\0') {
            unsigned long instance = strtoul(parsePtr, &parsePtr, 0);

            if (_isEISA) {
                return LookForEISAID((int)instance, _idBuffer, (char *)parameterArray, count);
            } else {
                /* PnP lookup */
                unsigned int logicalDevice;
                PnPDeviceResources *deviceResources = [busInstance lookForPnPIDs:_idBuffer
                                                                         Instance:instance
                                                                    LogicalDevice:&logicalDevice];
                if (deviceResources != nil) {
                    unsigned long serialNum = (unsigned long)[deviceResources serialNumber];
                    unsigned long idValue = (unsigned long)[deviceResources ID];

                    sprintf((char *)parameterArray, "Card:0x%lx Serial:0x%lx Logical:0x%x",
                            idValue, serialNum, logicalDevice);

                    /* Calculate string length */
                    len = 0;
                    while (parameterArray[len] != '\0' && len < *count) {
                        len++;
                    }
                    *count = len;
                    return IO_R_SUCCESS;
                }
                *count = 0;
            }
        }
        return IO_R_INVALID;

    case 10: /* Device( */
        slot = strtol(parsePtr, &parsePtr, 0);
        function = strtol(parsePtr, &parsePtr, 0);
        readByte = [busInstance readPnPDeviceCfg:parameterArray
                                          length:count
                                         forCard:slot
                                andLogicalDevice:function];
        if (readByte == 0) {
            return IO_R_INVALID_ARG;
        }
        return IO_R_SUCCESS;

    case 11: /* Node( */
        slot = strtol(parsePtr, &parsePtr, 0);
        if (parsePtr == NULL) {
            return IO_R_INVALID_ARG;
        }
        readByte = [busInstance readSystemNode:parameterArray length:count forNode:slot];
        if (readByte != 1) {
            return IO_R_INVALID_ARG;
        }
        return IO_R_SUCCESS;

    default:
        /* Unknown parameter - call superclass */
        return [super getCharValues:parameterArray forParameter:parameterName count:count];
    }

    /* Cases that break end up here - parameter not found */
    *count = 0;
    return IO_R_INVALID_ARG;
}

/*
 * Set character values for parameter
 */
- (IOReturn)setCharValues:(unsigned char *)parameterArray
             forParameter:(IOParameterName)parameterName
                    count:(unsigned int)count
{
    id busInstance;
    unsigned int keyIndex;
    char *parsePtr;
    unsigned int registerNum;
    long portAddr;
    unsigned short portValue16;

    /* Look up the EISA bus instance */
    busInstance = [KernBus lookupBusInstanceWithName:"EISA" busId:0];

    /* Find which key matches the parameter name */
    keyIndex = 0;
    parsePtr = NULL;

    do {
        parsePtr = EISAParsePrefix((char *)keys[keyIndex], (char *)parameterName);
        if (parsePtr != NULL) {
            break;
        }
        keyIndex++;
    } while (keyIndex < 12);

    /* Handle parameter writes based on key index */
    if (keyIndex == 3) {
        /* Write to PnP register - expects index 3 to handle register writes */
        registerNum = strtol(parsePtr, &parsePtr, 0);
        if (count == 1) {
            [busInstance writePnPRegister:(registerNum & 0xFF) value:*parameterArray];
            return IO_R_SUCCESS;
        }
    } else if (keyIndex == 6) {
        /* Write to I/O port - expects index 6 to handle port writes */
        portAddr = strtol(parsePtr, &parsePtr, 0);
        portValue16 = (unsigned short)portAddr;

        if (count == 1) {
            /* Write 1 byte */
            outb(portValue16, *parameterArray);
            return IO_R_SUCCESS;
        } else if (count == 2) {
            /* Write 2 bytes (word) */
            outw(portValue16, *(unsigned short *)parameterArray);
            return IO_R_SUCCESS;
        } else if (count == 4) {
            /* Write 4 bytes (dword) - uses 2-byte writes on i386 */
            outw(portValue16, *(unsigned short *)parameterArray);
            return IO_R_SUCCESS;
        }
    } else {
        /* Unknown parameter - call superclass */
        return [super setCharValues:parameterArray forParameter:parameterName count:count];
    }

    return IO_R_INVALID_ARG;
}

/*
 * Setup boot flag
 */
- setupBootFlag
{
    id deviceDescription;
    id configTable;
    const char *coldBootValue;

    /* Get device description */
    deviceDescription = [self deviceDescription];

    /* Get config table from device description */
    configTable = [deviceDescription configTable];

    /* Get "Cold Boot" configuration value */
    coldBootValue = [configTable valueForStringKey:"Cold Boot"];

    if (coldBootValue != NULL) {
        /* Check if cold boot is enabled (starts with 'y' or 'Y') */
        if (*coldBootValue == 'y' || *coldBootValue == 'Y') {
            /* Write 0 to BIOS boot flag location (0x472) to force cold boot */
            /* This is the PC BIOS warm boot flag - 0x0000 = cold boot, 0x1234 = warm boot */
            *(unsigned short *)0x00000472 = 0;
        }

        /* Free the string */
        [configTable freeString:coldBootValue];
    }

    return self;
}

@end
