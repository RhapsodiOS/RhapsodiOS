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
 * PCIBus.m
 * PCI Bus Driver Implementation
 */

#import "PCIBus.h"
#import "PCIKernelServer.h"
#import "PCIBusVersion.h"
#import "PCIResourceDriver.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/interruptMsg.h>

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

/* Global kernel server instance */
static PCIKernelServerInstance *gPCIKernelServer = nil;

/*
 * ============================================================================
 * PCIKernelServerInstance Implementation
 * ============================================================================
 */

@implementation PCIKernelServerInstance

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    return YES;
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    _pciData = NULL;
    _initialized = NO;

    [self setName:"PCIKernelServer"];
    [self setDeviceKind:"PCIKernelServer"];

    gPCIKernelServer = self;
    _initialized = YES;

    IOLog("PCIKernelServer: Initialized\n");

    return self;
}

- free
{
    if (gPCIKernelServer == self) {
        gPCIKernelServer = nil;
    }

    if (_pciData != NULL) {
        IOFree(_pciData, sizeof(void *));
        _pciData = NULL;
    }

    return [super free];
}

/*
 * PCI configuration space access
 */

- (unsigned int)configRead:(unsigned int)bus device:(unsigned int)dev
                  function:(unsigned int)func offset:(unsigned int)offset width:(int)width
{
    unsigned int address;
    unsigned int value = 0xFFFFFFFF;

    /* Build PCI configuration address */
    address = 0x80000000 |
              (bus << 16) |
              (dev << 11) |
              (func << 8) |
              (offset & 0xFC);

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
    address = 0x80000000 |
              (bus << 16) |
              (dev << 11) |
              (func << 8) |
              (offset & 0xFC);

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
 * PCI device enumeration
 */

- (BOOL)deviceExists:(unsigned int)bus device:(unsigned int)dev function:(unsigned int)func
{
    unsigned int vendorId;

    vendorId = [self configRead:bus device:dev function:func offset:PCI_CONFIG_VENDOR_ID width:2];

    return (vendorId != 0xFFFF && vendorId != 0x0000);
}

- (int)scanBus:(unsigned int)busNum
{
    unsigned int dev, func;
    unsigned int vendorId, deviceId, classCode, headerType;
    int deviceCount = 0;

    IOLog("PCIKernelServer: Scanning PCI bus %d\n", busNum);

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
    /* Allocate and return resource description for device */
    /* This would normally create an IODeviceDescription */
    return NULL;
}

@end

/*
 * ============================================================================
 * PCIBusVersion Implementation
 * ============================================================================
 */

@implementation PCIBusVersion

- init
{
    [super init];

    _majorVersion = 5;
    _minorVersion = 1;
    _versionString = "5.01";

    return self;
}

- free
{
    return [super free];
}

- (unsigned int)majorVersion
{
    return _majorVersion;
}

- (unsigned int)minorVersion
{
    return _minorVersion;
}

- (const char *)versionString
{
    return _versionString;
}

@end

/*
 * ============================================================================
 * PCIResourceDriver Implementation
 * ============================================================================
 */

@implementation PCIResourceDriver

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    return YES;
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    _resourceData = NULL;
    _initialized = NO;

    [self setName:"PCIResourceDriver"];
    [self setDeviceKind:"PCIResourceDriver"];

    return self;
}

- free
{
    if (_resourceData != NULL) {
        IOFree(_resourceData, sizeof(void *));
        _resourceData = NULL;
    }

    return [super free];
}

- (BOOL)allocateResources
{
    /* Allocate resources for PCI device */
    _initialized = YES;
    return YES;
}

- (void)deallocateResources
{
    if (_resourceData != NULL) {
        IOFree(_resourceData, sizeof(void *));
        _resourceData = NULL;
    }
    _initialized = NO;
}

- (BOOL)configureDevice
{
    return YES;
}

- (void *)getResourceDescription
{
    return _resourceData;
}

@end

/*
 * ============================================================================
 * PCIBus Implementation
 * ============================================================================
 */

@implementation PCIBus

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    if ([deviceDescription isKindOf:[IODeviceDescription class]]) {
        return YES;
    }
    return NO;
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    /* Create kernel server instance */
    _kernelServer = [[PCIKernelServerInstance alloc]
                     initFromDeviceDescription:deviceDescription];
    if (_kernelServer == nil) {
        IOLog("PCIBus: Failed to create kernel server instance\n");
        return nil;
    }

    /* Create version object */
    _version = [[PCIBusVersion alloc] init];
    if (_version == nil) {
        IOLog("PCIBus: Failed to create version object\n");
        [_kernelServer free];
        return nil;
    }

    _initialized = NO;

    [self setName:"PCIBus"];
    [self setDeviceKind:"PCIBus"];
    [self setLocation:NULL];

    IOLog("PCIBus: Initialized (Version %s)\n", [_version versionString]);

    [self registerDevice];

    return self;
}

- free
{
    if (_version != nil) {
        [_version free];
        _version = nil;
    }

    if (_kernelServer != nil) {
        [_kernelServer free];
        _kernelServer = nil;
    }

    return [super free];
}

/*
 * Boot driver initialization - called during boot
 */
- (BOOL)BootDriver
{
    if (_initialized) {
        return YES;
    }

    if (_kernelServer == nil) {
        IOLog("PCIBus: BootDriver called without kernel server\n");
        return NO;
    }

    /* Scan PCI buses */
    if ([self scanBuses]) {
        _initialized = YES;
        IOLog("PCIBus: BootDriver completed successfully\n");
        return YES;
    }

    IOLog("PCIBus: BootDriver failed to scan buses\n");
    return NO;
}

/*
 * PCI bus operations
 */

- (int)getBusCount
{
    /* In a real implementation, this would detect the number of PCI buses */
    /* For now, we assume a single PCI bus */
    return 1;
}

- (BOOL)scanBuses
{
    int busCount;
    int bus;
    int totalDevices = 0;

    busCount = [self getBusCount];

    IOLog("PCIBus: Scanning %d PCI bus%s\n",
          busCount, (busCount == 1) ? "" : "es");

    for (bus = 0; bus < busCount; bus++) {
        int deviceCount = [_kernelServer scanBus:bus];
        totalDevices += deviceCount;
    }

    IOLog("PCIBus: Found %d PCI device%s\n",
          totalDevices, (totalDevices == 1) ? "" : "s");

    return (totalDevices > 0);
}

@end
