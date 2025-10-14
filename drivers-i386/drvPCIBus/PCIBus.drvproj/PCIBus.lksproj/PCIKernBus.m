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
#import "PCIKernBusInterrupt.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/KernBusMemory.h>
#import <driverkit/KernBusInterruptPrivate.h>
#import <machdep/i386/intr_internal.h>

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

static const char *resourceNameStrings[] = {
    IRQ_LEVELS_KEY,
    DMA_CHANNELS_KEY,
    MEM_MAPS_KEY,
    IO_PORTS_KEY,
    NULL
};

+ initialize
{
    [self registerBusClass:self name:"PCI"];
    return self;
}

- init
{
    if ([super init] == nil) {
        return nil;
    }

    _pciData = NULL;
    _initialized = NO;

    /* Verify PCI is present before continuing */
    if (![self isPCIPresent]) {
        IOLog("PCIKernBus: Initialization failed - PCI not detected\n");
        [super free];
        return nil;
    }

    /* Register IRQ resources (16 IRQs on i386) */
    [self _insertResource:[[KernBusItemResource alloc]
                           initWithItemCount:INTR_NIRQ
                           itemKind:[PCIKernBusInterrupt class]
                           owner:self]
                  withKey:IRQ_LEVELS_KEY];

    /* Register memory map resources */
    [self _insertResource:[[KernBusRangeResource alloc]
                           initWithExtent:RangeMAX
                           kind:[KernBusMemoryRange class]
                           owner:self]
                  withKey:MEM_MAPS_KEY];

    /* Register I/O port resources (64K ports on i386) */
    [self _insertResource:[[KernBusRangeResource alloc]
                           initWithExtent:0x10000
                           kind:[KernBusMemoryRange class]
                           owner:self]
                  withKey:IO_PORTS_KEY];

    _initialized = YES;

    /* Register with the kernel bus system */
    [[self class] registerBusInstance:self name:"PCI" busId:0];

    IOLog("PCIKernBus: Initialized and registered\n");

    return self;
}

- free
{
    /* Check if resources are still active */
    if ([self areResourcesActive]) {
        return self;
    }

    /* Free resources */
    [[self _deleteResourceWithKey:IRQ_LEVELS_KEY] free];
    [[self _deleteResourceWithKey:MEM_MAPS_KEY] free];
    [[self _deleteResourceWithKey:IO_PORTS_KEY] free];

    if (_pciData != NULL) {
        IOFree(_pciData, sizeof(void *));
        _pciData = NULL;
    }

    return [super free];
}

/*
 * Return array of resource names
 */
- (const char **)resourceNames
{
    return resourceNameStrings;
}

/*
 * PCI presence detection
 */

- (BOOL)isPCIPresent
{
    unsigned int value;

    /* Try to access PCI configuration mechanism #1 */
    /* Save the current CONFIG_ADDRESS value */
    unsigned int savedAddress = inl(PCI_CONFIG_ADDRESS);

    /* Write a test pattern to CONFIG_ADDRESS */
    outl(PCI_CONFIG_ADDRESS, 0x80000000);

    /* Read it back */
    value = inl(PCI_CONFIG_ADDRESS);

    /* Restore original value */
    outl(PCI_CONFIG_ADDRESS, savedAddress);

    /* If we read back what we wrote, PCI is present */
    if (value == 0x80000000) {
        /* Additional verification: try to read vendor ID from bus 0, device 0 */
        unsigned int vendorId = [self configRead:0 device:0 function:0
                                         offset:PCI_CONFIG_VENDOR_ID width:2];

        /* Valid vendor IDs are not 0x0000 or 0xFFFF */
        if (vendorId != 0x0000 && vendorId != 0xFFFF) {
            IOLog("PCIKernBus: PCI bus detected (Vendor ID: 0x%04x)\n", vendorId);
            return YES;
        }
    }

    IOLog("PCIKernBus: No PCI bus detected\n");
    return NO;
}

/*
 * PCI configuration space access
 */

- (unsigned int)configAddress:(unsigned int)offset device:(unsigned int)dev
                      function:(unsigned int)func bus:(unsigned int)bus
{
    unsigned int address;

    /* Build PCI configuration address for mechanism #1 */
    /* Bit 31: Enable bit (must be 1)
     * Bits 23-16: Bus number
     * Bits 15-11: Device number
     * Bits 10-8: Function number
     * Bits 7-2: Register offset (DWORD aligned)
     * Bits 1-0: Must be 0 (DWORD alignment)
     */
    address = 0x80000000 |
              ((bus & 0xFF) << 16) |
              ((dev & 0x1F) << 11) |
              ((func & 0x07) << 8) |
              (offset & 0xFC);

    return address;
}

- (IOReturn)configAddress:(id)delegate device:(unsigned char *)devNum
                 function:(unsigned char *)funNum bus:(unsigned char *)busNum
{
    const char *locationStr;
    unsigned int busValue = 0, devValue = 0, funcValue = 0;
    int matched;

    /* Validate delegate */
    if (delegate == nil) {
        return IO_R_INVALID_ARG;
    }

    /* Try to get the location string from the delegate */
    /* The delegate should be an IODeviceDescription or similar */
    if ([delegate respondsToSelector:@selector(location)]) {
        locationStr = [delegate location];

        if (locationStr != NULL) {
            /* Parse location string in format "bus:device.function" or "device.function" */
            matched = sscanf(locationStr, "%u:%u.%u", &busValue, &devValue, &funcValue);

            if (matched == 3) {
                /* Successfully parsed bus:device.function */
                if (devNum) *devNum = (unsigned char)devValue;
                if (funNum) *funNum = (unsigned char)funcValue;
                if (busNum) *busNum = (unsigned char)busValue;
                return IO_R_SUCCESS;
            }

            /* Try parsing without bus number (device.function format) */
            matched = sscanf(locationStr, "%u.%u", &devValue, &funcValue);

            if (matched == 2) {
                /* Successfully parsed device.function, assume bus 0 */
                if (devNum) *devNum = (unsigned char)devValue;
                if (funNum) *funNum = (unsigned char)funcValue;
                if (busNum) *busNum = 0;
                return IO_R_SUCCESS;
            }
        }
    }

    /* Try to extract from properties if location string parsing failed */
    if ([delegate respondsToSelector:@selector(getProperty:length:)]) {
        unsigned int length;
        unsigned int *value;

        /* Try PCIBusNumber property */
        length = sizeof(unsigned int);
        value = (unsigned int *)[delegate getProperty:"PCIBusNumber" length:&length];
        if (value != NULL && length == sizeof(unsigned int)) {
            busValue = *value;
        } else {
            busValue = 0; /* Default to bus 0 */
        }

        /* Try PCIDeviceNumber property */
        length = sizeof(unsigned int);
        value = (unsigned int *)[delegate getProperty:"PCIDeviceNumber" length:&length];
        if (value != NULL && length == sizeof(unsigned int)) {
            devValue = *value;
        } else {
            return IO_R_NO_DEVICE;
        }

        /* Try PCIFunctionNumber property */
        length = sizeof(unsigned int);
        value = (unsigned int *)[delegate getProperty:"PCIFunctionNumber" length:&length];
        if (value != NULL && length == sizeof(unsigned int)) {
            funcValue = *value;
        } else {
            funcValue = 0; /* Default to function 0 */
        }

        /* Successfully extracted from properties */
        if (devNum) *devNum = (unsigned char)devValue;
        if (funNum) *funNum = (unsigned char)funcValue;
        if (busNum) *busNum = (unsigned char)busValue;
        return IO_R_SUCCESS;
    }

    /* Unable to extract PCI address from delegate */
    return IO_R_NO_DEVICE;
}

- (unsigned int)configRead:(unsigned int)bus device:(unsigned int)dev
                  function:(unsigned int)func offset:(unsigned int)offset width:(int)width
{
    unsigned int address;
    unsigned int value = 0xFFFFFFFF;

    /* Build PCI configuration address */
    address = [self configAddress:offset device:dev function:func bus:bus];

    /* Write address to CONFIG_ADDRESS register */
    outl(PCI_CONFIG_ADDRESS, address);

    /* Read data from CONFIG_DATA register */
    switch (width) {
        case 1:
            value = inb(PCI_CONFIG_DATA + (offset & 3));
            break;
        case 2:
            value = inw(PCI_CONFIG_DATA + (offset & 2));
            break;
        case 4:
            value = inl(PCI_CONFIG_DATA);
            break;
    }

    return value;
}

- (void)configWrite:(unsigned int)bus device:(unsigned int)dev
           function:(unsigned int)func offset:(unsigned int)offset
              width:(int)width value:(unsigned int)value
{
    unsigned int address;

    /* Build PCI configuration address */
    address = [self configAddress:offset device:dev function:func bus:bus];

    /* Write address to CONFIG_ADDRESS register */
    outl(PCI_CONFIG_ADDRESS, address);

    /* Write data to CONFIG_DATA register */
    switch (width) {
        case 1:
            outb(PCI_CONFIG_DATA + (offset & 3), value);
            break;
        case 2:
            outw(PCI_CONFIG_DATA + (offset & 2), value);
            break;
        case 4:
            outl(PCI_CONFIG_DATA, value);
            break;
    }
}

/*
 * High-level register access (KernBus interface)
 */

- (IOReturn)getRegister:(unsigned char)address device:(unsigned char)devNum
               function:(unsigned char)funNum bus:(unsigned char)busNum
                   data:(unsigned long *)data
{
    if (data == NULL) {
        return IO_R_INVALID_ARG;
    }

    /* Check if device exists */
    if (![self deviceExists:busNum device:devNum function:funNum]) {
        return IO_R_NO_DEVICE;
    }

    /* Read the 32-bit register value */
    *data = [self configRead:busNum device:devNum function:funNum offset:address width:4];

    return IO_R_SUCCESS;
}

- (IOReturn)setRegister:(unsigned char)address device:(unsigned char)devNum
               function:(unsigned char)funNum bus:(unsigned char)busNum
                   data:(unsigned long)data
{
    /* Check if device exists */
    if (![self deviceExists:busNum device:devNum function:funNum]) {
        return IO_R_NO_DEVICE;
    }

    /* Write the 32-bit register value */
    [self configWrite:busNum device:devNum function:funNum offset:address width:4 value:data];

    return IO_R_SUCCESS;
}

/*
 * PCI device enumeration
 */

- (BOOL)deviceExists:(unsigned int)bus device:(unsigned int)dev function:(unsigned int)func
{
    unsigned int vendorId;

    vendorId = [self configRead:bus device:dev function:func offset:PCI_CONFIG_VENDOR_ID width:2];

    return (vendorId != 0xFFFF && vendorId != 0x0000);
}

- (BOOL)testIDs:(unsigned int *)ids dev:(unsigned int)dev fun:(unsigned int)func bus:(unsigned int)bus
{
    unsigned int vendorId, deviceId;
    unsigned int classCode, revisionId;

    if (ids == NULL) {
        return NO;
    }

    /* Check if device exists */
    if (![self deviceExists:bus device:dev function:func]) {
        return NO;
    }

    /* Read Vendor ID and Device ID (offset 0x00, 32-bit read) */
    vendorId = [self configRead:bus device:dev function:func offset:PCI_CONFIG_VENDOR_ID width:2];
    deviceId = [self configRead:bus device:dev function:func offset:PCI_CONFIG_DEVICE_ID width:2];

    /* Read Revision ID and Class Code (offset 0x08, 32-bit read) */
    revisionId = [self configRead:bus device:dev function:func offset:0x08 width:1];
    classCode = [self configRead:bus device:dev function:func offset:PCI_CONFIG_CLASS_CODE width:4];

    /* Store IDs in the array */
    ids[0] = vendorId;
    ids[1] = deviceId;
    ids[2] = revisionId;
    ids[3] = classCode >> 8;  /* Class code is in upper 24 bits */

    return YES;
}

- (int)scanBus:(unsigned int)busNum
{
    unsigned int dev, func;
    unsigned int vendorId, deviceId, classCode, headerType;
    int deviceCount = 0;

    IOLog("PCIKernBus: Scanning PCI bus %d\n", busNum);

    for (dev = 0; dev < 32; dev++) {
        for (func = 0; func < 8; func++) {
            if (![self deviceExists:busNum device:dev function:func]) {
                if (func == 0) {
                    break;  /* No device at this slot */
                }
                continue;
            }

            vendorId = [self configRead:busNum device:dev function:func
                               offset:PCI_CONFIG_VENDOR_ID width:2];
            deviceId = [self configRead:busNum device:dev function:func
                               offset:PCI_CONFIG_DEVICE_ID width:2];
            classCode = [self configRead:busNum device:dev function:func
                                offset:PCI_CONFIG_CLASS_CODE width:4];
            headerType = [self configRead:busNum device:dev function:func
                                 offset:PCI_CONFIG_HEADER_TYPE width:1];

            IOLog("  PCI %d:%d.%d - Vendor: 0x%04x, Device: 0x%04x, Class: 0x%06x\n",
                  busNum, dev, func, vendorId, deviceId, classCode >> 8);

            deviceCount++;

            /* Check if this is a multi-function device */
            if (func == 0 && !(headerType & 0x80)) {
                break;  /* Not a multi-function device */
            }
        }
    }

    return deviceCount;
}

- (void *)allocateResourceDescriptionForDevice:(unsigned int)bus
                                        device:(unsigned int)dev
                                      function:(unsigned int)func
{
    IODeviceDescription *deviceDescription;
    unsigned int vendorId, deviceId, classCode, revisionId;
    unsigned int headerType, subsystemVendor, subsystemDevice;
    unsigned int bar[6];
    unsigned int interruptLine, interruptPin;
    char locationString[64];
    char nameString[128];
    int i;

    /* Check if device exists */
    if (![self deviceExists:bus device:dev function:func]) {
        return NULL;
    }

    /* Read device identification */
    vendorId = [self configRead:bus device:dev function:func offset:PCI_CONFIG_VENDOR_ID width:2];
    deviceId = [self configRead:bus device:dev function:func offset:PCI_CONFIG_DEVICE_ID width:2];
    revisionId = [self configRead:bus device:dev function:func offset:0x08 width:1];
    classCode = [self configRead:bus device:dev function:func offset:PCI_CONFIG_CLASS_CODE width:4];
    headerType = [self configRead:bus device:dev function:func offset:PCI_CONFIG_HEADER_TYPE width:1];

    /* Read subsystem IDs (offset 0x2C for type 0 headers) */
    if ((headerType & 0x7F) == 0x00) {
        subsystemVendor = [self configRead:bus device:dev function:func offset:0x2C width:2];
        subsystemDevice = [self configRead:bus device:dev function:func offset:0x2E width:2];
    } else {
        subsystemVendor = 0;
        subsystemDevice = 0;
    }

    /* Read Base Address Registers (BARs) */
    for (i = 0; i < 6; i++) {
        bar[i] = [self configRead:bus device:dev function:func offset:0x10 + (i * 4) width:4];
    }

    /* Read interrupt configuration */
    interruptLine = [self configRead:bus device:dev function:func offset:0x3C width:1];
    interruptPin = [self configRead:bus device:dev function:func offset:0x3D width:1];

    /* Create device description */
    deviceDescription = [IODeviceDescription new];
    if (deviceDescription == nil) {
        return NULL;
    }

    /* Set location string (bus:device.function format) */
    sprintf(locationString, "%d:%d.%d", bus, dev, func);
    [deviceDescription setLocation:locationString];

    /* Set device name based on class code */
    sprintf(nameString, "PCI%04X,%04X", vendorId, deviceId);
    [deviceDescription setName:nameString];

    /* Set device properties */
    [deviceDescription setProperty:"PCIVendorID" value:(void *)(unsigned long)vendorId length:sizeof(unsigned int)];
    [deviceDescription setProperty:"PCIDeviceID" value:(void *)(unsigned long)deviceId length:sizeof(unsigned int)];
    [deviceDescription setProperty:"PCIRevisionID" value:(void *)(unsigned long)revisionId length:sizeof(unsigned int)];
    [deviceDescription setProperty:"PCIClassCode" value:(void *)(unsigned long)(classCode >> 8) length:sizeof(unsigned int)];
    [deviceDescription setProperty:"PCIHeaderType" value:(void *)(unsigned long)headerType length:sizeof(unsigned int)];

    if (subsystemVendor != 0 || subsystemDevice != 0) {
        [deviceDescription setProperty:"PCISubsystemVendorID" value:(void *)(unsigned long)subsystemVendor length:sizeof(unsigned int)];
        [deviceDescription setProperty:"PCISubsystemID" value:(void *)(unsigned long)subsystemDevice length:sizeof(unsigned int)];
    }

    /* Set bus/device/function properties */
    [deviceDescription setProperty:"PCIBusNumber" value:(void *)(unsigned long)bus length:sizeof(unsigned int)];
    [deviceDescription setProperty:"PCIDeviceNumber" value:(void *)(unsigned long)dev length:sizeof(unsigned int)];
    [deviceDescription setProperty:"PCIFunctionNumber" value:(void *)(unsigned long)func length:sizeof(unsigned int)];

    /* Process and set BAR resources */
    for (i = 0; i < 6; i++) {
        if (bar[i] != 0 && bar[i] != 0xFFFFFFFF) {
            char barName[32];
            sprintf(barName, "PCIBAR%d", i);

            if (bar[i] & 0x1) {
                /* I/O Space BAR */
                unsigned int ioBase = bar[i] & 0xFFFFFFFC;
                [deviceDescription setProperty:barName value:(void *)(unsigned long)ioBase length:sizeof(unsigned int)];
            } else {
                /* Memory Space BAR */
                unsigned int memBase = bar[i] & 0xFFFFFFF0;
                unsigned int memType = (bar[i] >> 1) & 0x3;

                [deviceDescription setProperty:barName value:(void *)(unsigned long)memBase length:sizeof(unsigned int)];

                /* Handle 64-bit BARs */
                if (memType == 0x2 && i < 5) {
                    /* This is a 64-bit BAR, skip next BAR */
                    i++;
                }
            }
        }
    }

    /* Set interrupt properties if present */
    if (interruptPin != 0) {
        [deviceDescription setProperty:"PCIInterruptLine" value:(void *)(unsigned long)interruptLine length:sizeof(unsigned int)];
        [deviceDescription setProperty:"PCIInterruptPin" value:(void *)(unsigned long)interruptPin length:sizeof(unsigned int)];
    }

    IOLog("PCIKernBus: Allocated device description for %04x:%04x at %s\n",
          vendorId, deviceId, locationString);

    return deviceDescription;
}

@end
