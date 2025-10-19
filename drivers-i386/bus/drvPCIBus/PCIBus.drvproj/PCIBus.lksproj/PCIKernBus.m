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
 * PCIKernBus.m
 * PCI Kernel Bus Driver Implementation
 */

#import "PCIKernBus.h"
#import "pci.h"

#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/KernBusMemory.h>
#import <machdep/i386/intr_internal.h>

#import <string.h>

/*
 * Private category for internal PCI configuration methods
 */
@interface PCIKernBus (Private)
- (BOOL)test_M1;
- (BOOL)test_M2;
- (unsigned long)Method1:(unsigned char)address
                  device:(unsigned char)device
                function:(unsigned char)function
                     bus:(unsigned char)bus
                    data:(unsigned long)data
                   write:(char)write;
- (unsigned long)Method2:(unsigned char)address
                  device:(unsigned char)device
                function:(unsigned char)function
                     bus:(unsigned char)bus
                    data:(unsigned long)data
                   write:(char)write;
@end

/* PCI Configuration Space Registers */
#define PCI_CONFIG_VENDOR_ID    0x00
#define PCI_CONFIG_DEVICE_ID    0x02
#define PCI_CONFIG_COMMAND      0x04
#define PCI_CONFIG_STATUS       0x06
#define PCI_CONFIG_CLASS_CODE   0x08
#define PCI_CONFIG_HEADER_TYPE  0x0E

/* PCI I/O Ports (Intel architecture) */
#define PCI_CONFIG_ADDRESS      0x0CF8
#define PCI_CONFIG_DATA         0x0CFC

/*
 * Resource keys
 */
#define IO_PORTS_KEY        "I/O Ports"
#define MEM_MAPS_KEY        "Memory Maps"
#define IRQ_LEVELS_KEY      "IRQ Levels"
#define DMA_CHANNELS_KEY    "DMA Channels"

/*
 * ============================================================================
 * PCIKernBus Implementation
 * ============================================================================
 */

@implementation PCIKernBus

+ initialize
{
    [self registerBusClass:self name:"PCI"];
    return self;
}

- init
{
    unsigned int pciConfigData;
    unsigned int subsystemId;
    unsigned char bus, dev, func;
    const char *bios16Str, *bios32Str, *cm1Str, *cm2Str, *sc1Str, *sc2Str;

    /* Initialize instance variables from configuration data */
    /* TODO: Read these from PCI BIOS if available */
    _maxBusNum = 0;  /* Default to single bus, could be read from BIOS */
    _maxDevNum = 0;  /* Will be set based on config mechanism */
    _pciVersionMajor = 2;  /* PCI 2.x */
    _pciVersionMinor = 1;
    _bios16Present = YES;  /* Assume BIOS present for now */
    _bios32Present = NO;
    _reserved = NULL;

    /* Initialize feature flags - will be detected */
    _configMech1 = NO;
    _configMech2 = NO;
    _specialCycle1 = NO;
    _specialCycle2 = NO;

    /* Test for configuration mechanisms */
    if (!_configMech1 && !_configMech2 && _bios16Present) {
        _configMech1 = [self test_M1];
        if (!_configMech1) {
            _configMech2 = [self test_M2];
        }
    }

    /* If still no mechanism found, try detecting directly */
    if (!_configMech1 && !_configMech2) {
        _configMech1 = [self test_M1];
        if (!_configMech1) {
            _configMech2 = [self test_M2];
        }
    }

    /* Set max device number based on configuration mechanism */
    if (_configMech1) {
        _maxDevNum = 0x1f;  /* Mechanism 1 supports 32 devices (0-31) */
    } else if (_configMech2) {
        _maxDevNum = 0xf;   /* Mechanism 2 supports 16 devices (0-15) */
    }

    /* Verify PCI is present */
    if (![self isPCIPresent]) {
        return [self free];
    }

    /* Build feature strings for logging */
    bios16Str = _bios16Present ? "BIOS16 " : "";
    bios32Str = _bios32Present ? "BIOS32 " : "";
    cm1Str = _configMech1 ? "CM1 " : "";
    cm2Str = _configMech2 ? "CM2 " : "";
    sc1Str = _specialCycle1 ? "SC1 " : "";
    sc2Str = _specialCycle2 ? "SC2 " : "";

    IOLog("PCI Ver=%x.%02x BusCount=%d Features=[ %s%s%s%s%s%s]\n",
          _pciVersionMajor, _pciVersionMinor, _maxBusNum + 1,
          bios16Str, bios32Str, cm1Str, cm2Str, sc1Str, sc2Str);

    /* Scan all PCI devices */
    for (bus = 0; bus <= _maxBusNum; bus++) {
        for (dev = 0; dev <= _maxDevNum; dev++) {
            for (func = 0; func < 8; func++) {
                /* Read vendor/device ID */
                if ([self getRegister:0 device:dev function:func bus:bus
                              data:(unsigned long *)&pciConfigData] != IO_R_SUCCESS) {
                    continue;
                }

                /* Check if device exists */
                if ((short)pciConfigData == -1 || (short)pciConfigData == 0) {
                    continue;
                }

                /* Read subsystem ID at offset 0x2C */
                [self getRegister:0x2C device:dev function:func bus:bus
                          data:(unsigned long *)&subsystemId];

                if (subsystemId == 0) {
                    IOLog("Found PCI 2.0 device: ID=0x%08x at Dev=%d Func=%d Bus=%d\n",
                          pciConfigData, dev, func, bus);
                } else {
                    IOLog("Found PCI 2.1 device: ID=0x%08x/0x%08x at Dev=%d Func=%d Bus=%d\n",
                          pciConfigData, subsystemId, dev, func, bus);
                }

                /* Check header type to see if this is a multi-function device */
                [self getRegister:0x0C device:dev function:func bus:bus
                          data:(unsigned long *)&pciConfigData];

                /* If not multi-function (bit 23 clear), don't check other functions */
                if ((pciConfigData & 0x800000) == 0) {
                    break;
                }
            }
        }
    }

    /* Register with the bus system */
    [self setBusId:0];
    [[self class] registerBusInstance:self name:"PCI" busId:[self busId]];

    printf("PCI bus support enabled\n");

    return [super init];
}

- free
{
    if (_reserved != NULL) {
        IOFree(_reserved, sizeof(void *));
        _reserved = NULL;
    }

    return [super free];
}


/*
 * PCI presence detection
 * Checks if any PCI configuration mechanism is available
 * This checks bytes at offset 0x19, 0x1a, 0x1b (configMech1, configMech2, specialCycle1)
 */

- (BOOL)isPCIPresent
{
    /* Check if any configuration mechanism is present */
    /* The decompiled code checks: (*(uint *)(this + 0x18) & 0xffff00) != 0 */
    /* This is equivalent to checking if configMech1, configMech2, or specialCycle1 is set */
    return (_configMech1 || _configMech2 || _specialCycle1);
}

/*
 * PCI configuration space access
 */

- (IOReturn)configAddress:(id)deviceDescription
                   device:(unsigned char *)devNum
                 function:(unsigned char *)funNum
                      bus:(unsigned char *)busNum
{
    id configTable;
    const char *busTypeStr;
    const char *locationStr;
    const char *instanceStr;
    char *autoDetectIDs;
    unsigned long dev = 0;
    unsigned int func = 0, busNum_local = 0;
    unsigned long instance = 0;
    unsigned int headerType;
    BOOL locationFound = NO;

    /* Get the config table from device description */
    configTable = [deviceDescription configTable];

    /* Check Bus Type */
    busTypeStr = [configTable valueForStringKey:"Bus Type"];
    if (busTypeStr != NULL) {
        /* Verify this is a PCI device (compare first 4 chars) */
        if (strncmp(busTypeStr, "PCI", 4) != 0) {
            [configTable freeString:busTypeStr];
            return IO_R_NO_DEVICE;
        }
        [configTable freeString:busTypeStr];

        /* Check for Auto Detect IDs */
        autoDetectIDs = (char *)[configTable valueForStringKey:"Auto Detect IDs"];
        if (autoDetectIDs != NULL) {
            /* Try to get location string */
            locationStr = [configTable valueForStringKey:"Location"];
            if (locationStr != NULL && *locationStr != '\0') {
                /* Parse the location string using PCIParseKeys */
                if (PCIParseKeys((char *)locationStr, &dev, &func, &busNum_local, NULL)) {
                    /* Validate parsed values */
                    if (dev <= _maxDevNum && func < 8 && busNum_local <= _maxBusNum) {
                        /* Test if device with these IDs exists at this location */
                        if ([self testIDs:(unsigned int *)autoDetectIDs
                                      dev:(unsigned int)dev fun:func bus:busNum_local]) {
                            locationFound = YES;
                        }
                    }
                }
                [configTable freeString:locationStr];
            }

            /* If location was found, return it */
            if (locationFound) {
                [configTable freeString:autoDetectIDs];
                if (devNum) *devNum = (unsigned char)dev;
                if (funNum) *funNum = (unsigned char)func;
                if (busNum) *busNum = (unsigned char)busNum_local;
                return IO_R_SUCCESS;
            }

            /* Try to get instance number */
            instanceStr = [configTable valueForStringKey:"Instance"];
            if (instanceStr != NULL) {
                instance = strtoul(instanceStr, NULL, 0);
                [configTable freeString:instanceStr];
            }

            /* Scan all PCI devices to find matching IDs */
            for (busNum_local = 0; busNum_local <= _maxBusNum; busNum_local++) {
                for (dev = 0; dev <= _maxDevNum; dev++) {
                    for (func = 0; func < 8; func++) {
                        /* Test if this device matches the auto-detect IDs */
                        if ([self testIDs:(unsigned int *)autoDetectIDs
                                      dev:(unsigned int)dev fun:func bus:busNum_local]) {
                            /* Found a matching device */
                            if (instance == 0) {
                                /* This is the instance we're looking for */
                                [configTable freeString:autoDetectIDs];
                                if (devNum) *devNum = (unsigned char)dev;
                                if (funNum) *funNum = (unsigned char)func;
                                if (busNum) *busNum = (unsigned char)busNum_local;
                                return IO_R_SUCCESS;
                            }
                            /* Decrement instance counter and keep looking */
                            instance--;
                        }

                        /* Check if this is a multi-function device */
                        [self getRegister:0x0C device:(unsigned char)dev function:func bus:busNum_local
                                     data:(unsigned long *)&headerType];

                        /* If not multi-function (bit 23 clear), skip remaining functions */
                        if ((headerType & 0x800000) == 0) {
                            break;
                        }
                    }
                }
            }

            [configTable freeString:autoDetectIDs];
        }
    }

    return IO_R_NO_DEVICE;
}

/*
 * High-level register access (KernBus interface)
 */

- (IOReturn)getRegister:(unsigned char)address device:(unsigned char)devNum
               function:(unsigned char)funNum bus:(unsigned char)busNum
                   data:(unsigned long *)data
{
    unsigned long result;

    /* Validate parameters */
    if (_maxBusNum < busNum || _maxDevNum < devNum || funNum > 7 || (address & 3) != 0) {
        return IO_R_INVALID_ARG;
    }

    /* Check which configuration mechanism to use */
    if (_configMech1) {
        /* Use Configuration Mechanism #1 */
        result = [self Method1:address device:devNum function:funNum bus:busNum data:0 write:0];
        *data = result;
        return IO_R_SUCCESS;
    } else if (_configMech2) {
        /* Use Configuration Mechanism #2 */
        result = [self Method2:address device:devNum function:funNum bus:busNum data:0 write:0];
        *data = result;
        return IO_R_SUCCESS;
    }

    return IO_R_NO_DEVICE;
}

- (IOReturn)setRegister:(unsigned char)address device:(unsigned char)devNum
               function:(unsigned char)funNum bus:(unsigned char)busNum
                   data:(unsigned long)data
{
    /* Validate parameters */
    if (_maxBusNum < busNum || _maxDevNum < devNum || funNum > 7 || (address & 3) != 0) {
        return IO_R_INVALID_ARG;
    }

    /* Check which configuration mechanism to use */
    if (_configMech1) {
        /* Use Configuration Mechanism #1 */
        [self Method1:address device:devNum function:funNum bus:busNum data:data write:1];
        return IO_R_SUCCESS;
    } else if (_configMech2) {
        /* Use Configuration Mechanism #2 */
        [self Method2:address device:devNum function:funNum bus:busNum data:data write:1];
        return IO_R_SUCCESS;
    }

    return IO_R_NO_DEVICE;
}

- (BOOL)testIDs:(unsigned int *)ids dev:(unsigned int)dev fun:(unsigned int)func bus:(unsigned int)bus
{
    const char *idStr = (const char *)ids;
    char *prevPtr = NULL;
    char *ptr;
    unsigned int vendorDeviceID = 0;
    unsigned int subsystemID = 0;
    unsigned long primaryID, primaryMask;
    unsigned long subsystemIDValue, subsystemMask;

    /* Read vendor/device ID from register 0 */
    [self getRegister:0 device:dev function:func bus:bus data:(unsigned long *)&vendorDeviceID];

    /* Check if device exists (vendor ID not 0xFFFF or 0x0000) */
    if ((short)vendorDeviceID == -1 || (short)vendorDeviceID == 0 || *idStr == '\0') {
        return NO;
    }

    ptr = (char *)idStr;

    /* Parse ID string and match against device */
    while (*ptr != '\0') {
        /* Detect infinite loop */
        if (ptr == prevPtr) {
            return NO;
        }
        prevPtr = ptr;

        /* Skip whitespace */
        if (*ptr == ' ' || *ptr == '\t') {
            ptr++;
            primaryID = 0;
            primaryMask = 0;
            continue;
        }

        /* Parse primary ID (vendor/device) */
        primaryID = strtoul(ptr, &ptr, 0);

        /* Check for mask */
        if (*ptr == '&') {
            ptr++;
            primaryMask = strtoul(ptr, &ptr, 0);
        } else {
            primaryMask = 0xFFFFFFFF;
        }

        /* Check for subsystem ID */
        if (*ptr == ':') {
            /* Read subsystem vendor/device ID from register 0x2C */
            [self getRegister:0x2C device:dev function:func bus:bus
                         data:(unsigned long *)&subsystemID];

            ptr++;
            subsystemIDValue = strtoul(ptr, &ptr, 0);

            /* Check for subsystem mask */
            if (*ptr == '&') {
                ptr++;
                subsystemMask = strtoul(ptr, &ptr, 0);
            } else {
                subsystemMask = 0xFFFFFFFF;
            }
        } else {
            subsystemIDValue = 0;
            subsystemMask = 0;
        }

        /* Compare IDs with masks */
        if ((primaryMask & vendorDeviceID) == (primaryID & primaryMask)) {
            if ((subsystemMask & subsystemID) == (subsystemIDValue & subsystemMask)) {
                return YES;
            }
        }
    }

    return NO;
}

/*
 * PCI bus and device limits
 */

- (unsigned int)maxBusNum
{
    return _maxBusNum;
}

- (unsigned int)maxDevNum
{
    return _maxDevNum;
}

/*
 * Resource allocation for device
 */

- (IOReturn)allocateResourcesForDeviceDescription:(id)deviceDescription
{
    unsigned char bus, dev, func;
    unsigned int bar[6];
    unsigned int interruptLine, interruptPin;
    IOReturn result;
    int i;

    if (deviceDescription == nil) {
        return IO_R_INVALID_ARG;
    }

    /* Extract bus/device/function from device description */
    result = [self configAddress:deviceDescription device:&dev function:&func bus:&bus];
    if (result != IO_R_SUCCESS) {
        return result;
    }

    /* Verify device exists */
    if (![self deviceExists:bus device:dev function:func]) {
        return IO_R_NO_DEVICE;
    }

    /* Read Base Address Registers (BARs) for resource requirements */
    for (i = 0; i < 6; i++) {
        bar[i] = [self configRead:bus device:dev function:func offset:0x10 + (i * 4) width:4];

        if (bar[i] != 0 && bar[i] != 0xFFFFFFFF) {
            if (bar[i] & 0x1) {
                /* I/O Space BAR - allocate from I/O port resources */
                unsigned int ioBase = bar[i] & 0xFFFFFFFC;
                /* TODO: Allocate I/O port range from resource pool */
                IOLog("PCIKernBus: Device %d:%d.%d requires I/O space at 0x%x\n",
                      bus, dev, func, ioBase);
            } else {
                /* Memory Space BAR - allocate from memory resources */
                unsigned int memBase = bar[i] & 0xFFFFFFF0;
                unsigned int memType = (bar[i] >> 1) & 0x3;

                IOLog("PCIKernBus: Device %d:%d.%d requires memory space at 0x%x\n",
                      bus, dev, func, memBase);

                /* Handle 64-bit BARs */
                if (memType == 0x2 && i < 5) {
                    i++; /* Skip next BAR as it's part of the 64-bit address */
                }
            }
        }
    }

    /* Read interrupt configuration */
    interruptPin = [self configRead:bus device:dev function:func offset:0x3D width:1];

    if (interruptPin != 0) {
        interruptLine = [self configRead:bus device:dev function:func offset:0x3C width:1];

        /* Allocate interrupt resources */
        if (interruptLine < INTR_NIRQ) {
            IOLog("PCIKernBus: Device %d:%d.%d requires IRQ %d (pin %d)\n",
                  bus, dev, func, interruptLine, interruptPin);
            /* TODO: Mark IRQ as allocated in resource pool */
        }
    }

    return IO_R_SUCCESS;
}

@end

/*
 * ============================================================================
 * PCIKernBus (Private) Category Implementation
 * ============================================================================
 */

@implementation PCIKernBus (Private)

/*
 * Test for PCI Configuration Mechanism #1
 */
- (BOOL)test_M1
{
    unsigned int savedAddress, testValue;

    /* Test PCI Configuration Mechanism #1 */
    savedAddress = inl(PCI_CONFIG_ADDRESS);
    outl(PCI_CONFIG_ADDRESS, 0x80000000);
    testValue = inl(PCI_CONFIG_ADDRESS);
    outl(PCI_CONFIG_ADDRESS, savedAddress);

    return (testValue == 0x80000000);
}

/*
 * Test for PCI Configuration Mechanism #2
 */
- (BOOL)test_M2
{
    unsigned char savedCSE, savedForward;

    /* Test PCI Configuration Mechanism #2 */
    /* This mechanism uses ports 0xCF8 (CSE) and 0xCFA (Forward Register) */
    savedCSE = inb(0xCF8);
    savedForward = inb(0xCFA);

    /* Try to enable mechanism #2 */
    outb(0xCF8, 0x00);
    outb(0xCFA, 0x00);

    /* Check if we can read/write the registers */
    if (inb(0xCF8) == 0x00 && inb(0xCFA) == 0x00) {
        /* Restore original values */
        outb(0xCF8, savedCSE);
        outb(0xCFA, savedForward);
        return YES;
    }

    /* Restore original values */
    outb(0xCF8, savedCSE);
    outb(0xCFA, savedForward);
    return NO;
}

/*
 * PCI Configuration Mechanism #1 - Access method
 * Uses I/O ports 0xCF8 (CONFIG_ADDRESS) and 0xCFC (CONFIG_DATA)
 */
- (unsigned long)Method1:(unsigned char)address
                  device:(unsigned char)device
                function:(unsigned char)function
                     bus:(unsigned char)bus
                    data:(unsigned long)data
                   write:(char)write
{
    unsigned int configAddress;
    unsigned int readValue;
    unsigned int verifyAddress;

    /* Build PCI configuration address for mechanism #1 */
    configAddress = 0x80000000 |
                    ((unsigned int)(address & 0xFC)) |
                    ((unsigned int)(device & 0x1F) << 11) |
                    ((unsigned int)(function & 0x07) << 8) |
                    ((unsigned int)bus << 16);

    /* Write the configuration address to CONFIG_ADDRESS port (0xCF8) */
    outl(PCI_CONFIG_ADDRESS, configAddress);

    /* Verify the address was written correctly */
    verifyAddress = inl(PCI_CONFIG_ADDRESS);

    if (verifyAddress == configAddress) {
        if (write) {
            /* Write data to CONFIG_DATA port (0xCFC) */
            outl(PCI_CONFIG_DATA, data);
        }
        /* Read data from CONFIG_DATA port (0xCFC) */
        readValue = inl(PCI_CONFIG_DATA);
    } else {
        /* Address verification failed */
        readValue = 0xFFFFFFFF;
    }

    /* Clear CONFIG_ADDRESS */
    outl(PCI_CONFIG_ADDRESS, 0);

    return readValue;
}

/*
 * PCI Configuration Mechanism #2 - Access method
 * Uses I/O ports 0xCF8 (CSE), 0xCFA (Forward Register), and 0xC000-0xCFFF (Config Space)
 */
- (unsigned long)Method2:(unsigned char)address
                  device:(unsigned char)device
                function:(unsigned char)function
                     bus:(unsigned char)bus
                    data:(unsigned long)data
                   write:(char)write
{
    unsigned char cseValue;
    unsigned char verifyCse;
    unsigned char verifyBus;
    unsigned short configPort;
    unsigned long readValue = 0xFFFFFFFF;

    /* Calculate CSE (Configuration Space Enable) value */
    /* CSE format: 0xF0 | (bus * 2) */
    cseValue = 0xF0 | (bus * 2);

    /* Write to CSE register (0xCF8) */
    outb(0xCF8, cseValue);

    /* Verify CSE was written correctly */
    verifyCse = inb(0xCF8);

    if (verifyCse == cseValue) {
        /* Write bus number to Forward Register (0xCFA) */
        outb(0xCFA, bus);

        /* Verify bus number was written correctly */
        verifyBus = inb(0xCFA);

        if (verifyBus == bus) {
            /* Calculate configuration space port */
            /* Port format: 0xC000 | ((function & 0xF) << 8) | (address & 0xFC) */
            configPort = 0xC000 | ((unsigned short)(function & 0x0F) << 8) | (address & 0xFC);

            if (write) {
                /* Write data to configuration space port */
                outl(configPort, data);
            }

            /* Read data from configuration space port */
            readValue = inl(configPort);
        }

        /* Clear Forward Register */
        outb(0xCFA, 0);
    }

    /* Clear CSE register */
    outb(0xCF8, 0);

    return readValue;
}

@end
