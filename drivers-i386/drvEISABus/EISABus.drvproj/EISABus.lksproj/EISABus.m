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
 * EISABus.m
 * EISA Bus Driver Implementation
 */

#import "EISABus.h"
#import "EISAKernBus.h"
#import "EISAKernBusPlugAndPlay.h"
#import "PnPResources.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

/* EISA I/O ports */
#define EISA_ID_PORT_BASE       0x0C80
#define EISA_CONFIG_PORT_BASE   0x0C84

/* Maximum EISA slots */
#define EISA_MAX_SLOTS          16

/* Global kernel bus instance */
static EISAKernBus *gEISAKernBus = nil;

/* PnP I/O ports */
#define PNP_ADDRESS_PORT        0x279
#define PNP_WRITE_DATA_PORT     0xA79
#define PNP_READ_DATA_PORT      0x203
#define PNP_ISOLATION_PORT      0x279

/*
 * ============================================================================
 * EISAKernBus Implementation
 * ============================================================================
 */

@implementation EISAKernBus

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    return YES;
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    int i;

    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    _eisaData = NULL;
    _slotCount = EISA_MAX_SLOTS;
    _initialized = NO;

    /* Initialize IRQ and I/O port tracking */
    for (i = 0; i < 16; i++) {
        _irqLevels[i] = 0;
    }
    for (i = 0; i < 8; i++) {
        _ioPortRanges[i] = 0;
    }

    [self setName:"EISAKernBus"];
    [self setDeviceKind:"EISAKernBus"];

    gEISAKernBus = self;
    _initialized = YES;

    IOLog("EISAKernBus: Initialized with %d slots\n", _slotCount);

    return self;
}

- free
{
    if (gEISAKernBus == self) {
        gEISAKernBus = nil;
    }

    if (_eisaData != NULL) {
        IOFree(_eisaData, sizeof(void *));
        _eisaData = NULL;
    }

    return [super free];
}

- (int)getEISASlotNumber:(int)slot
{
    if (slot >= 0 && slot < _slotCount) {
        return slot;
    }
    return -1;
}

- (BOOL)testSlot:(int)slot
{
    unsigned int idPort;
    unsigned char idByte;

    if (slot < 0 || slot >= _slotCount) {
        return NO;
    }

    /* Calculate ID port for this slot */
    idPort = EISA_ID_PORT_BASE + (slot * 0x1000);

    /* Read ID byte - if 0xFF, slot is empty */
    idByte = inb(idPort);

    return (idByte != 0xFF);
}

- (void *)allocateResourcesForDevice:(IODeviceDescription *)description
{
    /* Allocate and return resource structure for device */
    return NULL;
}

- (void)freeResourcesForDevice:(void *)resources
{
    if (resources != NULL) {
        IOFree(resources, sizeof(void *));
    }
}

@end

/*
 * ============================================================================
 * PnP Resource Classes Implementation
 * ============================================================================
 */

@implementation PnPArgStack

- init
{
    [super init];
    _stackData = NULL;
    _depth = 0;
    return self;
}

- free
{
    if (_stackData != NULL) {
        IOFree(_stackData, sizeof(void *));
        _stackData = NULL;
    }
    return [super free];
}

- (BOOL)push:(void *)data
{
    _depth++;
    return YES;
}

- (void *)pop
{
    if (_depth > 0) {
        _depth--;
    }
    return NULL;
}

- (int)depth
{
    return _depth;
}

@end

@implementation PnPBios

- init
{
    [super init];
    _biosData = NULL;
    _biosAddress = 0xF0000;
    return self;
}

- free
{
    if (_biosData != NULL) {
        IOFree(_biosData, sizeof(void *));
        _biosData = NULL;
    }
    return [super free];
}

- (BOOL)detectBios
{
    /* Scan BIOS area for PnP signature */
    return NO;
}

- (void *)getBiosData
{
    return _biosData;
}

@end

@implementation PnPDependentResources

- init
{
    [super init];
    _resources = NULL;
    _count = 0;
    return self;
}

- free
{
    if (_resources != NULL) {
        IOFree(_resources, sizeof(void *));
        _resources = NULL;
    }
    return [super free];
}

- (BOOL)addResource:(void *)resource
{
    _count++;
    return YES;
}

- (void *)getResource:(int)index
{
    return NULL;
}

- (int)count
{
    return _count;
}

@end

@implementation PnPInterruptResource

- init
{
    [super init];
    _irqMask = 0;
    _flags = 0;
    return self;
}

- free
{
    return [super free];
}

- (void)setIRQMask:(unsigned int)mask
{
    _irqMask = mask;
}

- (unsigned int)irqMask
{
    return _irqMask;
}

- (void)setFlags:(unsigned char)flags
{
    _flags = flags;
}

- (unsigned char)flags
{
    return _flags;
}

@end

@implementation PnPIOPortResource

- init
{
    [super init];
    _minBase = 0;
    _maxBase = 0;
    _alignment = 0;
    _length = 0;
    _flags = 0;
    return self;
}

- free
{
    return [super free];
}

- (void)setMinBase:(unsigned int)base
{
    _minBase = base;
}

- (void)setMaxBase:(unsigned int)base
{
    _maxBase = base;
}

- (void)setAlignment:(unsigned char)align
{
    _alignment = align;
}

- (void)setLength:(unsigned char)len
{
    _length = len;
}

- (void)setFlags:(unsigned char)flags
{
    _flags = flags;
}

- (unsigned int)minBase
{
    return _minBase;
}

- (unsigned int)maxBase
{
    return _maxBase;
}

- (unsigned char)alignment
{
    return _alignment;
}

- (unsigned char)length
{
    return _length;
}

- (unsigned char)flags
{
    return _flags;
}

@end

@implementation PnPMemoryResource

- init
{
    [super init];
    _minBase = 0;
    _maxBase = 0;
    _alignment = 0;
    _length = 0;
    _flags = 0;
    return self;
}

- free
{
    return [super free];
}

- (void)setMinBase:(unsigned int)base
{
    _minBase = base;
}

- (void)setMaxBase:(unsigned int)base
{
    _maxBase = base;
}

- (void)setAlignment:(unsigned int)align
{
    _alignment = align;
}

- (void)setLength:(unsigned int)len
{
    _length = len;
}

- (void)setFlags:(unsigned char)flags
{
    _flags = flags;
}

- (unsigned int)minBase
{
    return _minBase;
}

- (unsigned int)maxBase
{
    return _maxBase;
}

- (unsigned int)alignment
{
    return _alignment;
}

- (unsigned int)length
{
    return _length;
}

- (unsigned char)flags
{
    return _flags;
}

@end

@implementation PnPDMAResource

- init
{
    [super init];
    _channelMask = 0;
    _flags = 0;
    return self;
}

- free
{
    return [super free];
}

- (void)setChannelMask:(unsigned char)mask
{
    _channelMask = mask;
}

- (unsigned char)channelMask
{
    return _channelMask;
}

- (void)setFlags:(unsigned char)flags
{
    _flags = flags;
}

- (unsigned char)flags
{
    return _flags;
}

@end

/*
 * ============================================================================
 * EISAKernBusPlugAndPlay Implementation
 * ============================================================================
 */

@implementation EISAKernBusPlugAndPlay

+ (BOOL)probe:(IODeviceDescription *)deviceDescription
{
    return YES;
}

- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        return nil;
    }

    _pnpData = NULL;
    _initialized = NO;
    _isolationPort = PNP_ISOLATION_PORT;
    _addressPort = PNP_ADDRESS_PORT;
    _writeDataPort = PNP_WRITE_DATA_PORT;
    _readDataPort = PNP_READ_DATA_PORT;
    _csn = 0;

    [self setName:"EISAKernBusPlugAndPlay"];
    [self setDeviceKind:"EISAKernBusPlugAndPlay"];

    return self;
}

- free
{
    if (_pnpData != NULL) {
        IOFree(_pnpData, sizeof(void *));
        _pnpData = NULL;
    }

    return [super free];
}

- (BOOL)initiatePnP
{
    /* Send initiation key sequence */
    int i;
    unsigned char key[32];

    /* Generate initiation key */
    key[0] = 0x6A;
    for (i = 1; i < 32; i++) {
        key[i] = ((key[i-1] >> 1) | (key[i-1] << 7)) & 0xFF;
    }

    /* Send key sequence */
    for (i = 0; i < 32; i++) {
        outb(_addressPort, key[i]);
    }

    _initialized = YES;
    return YES;
}

- (BOOL)isolateCards
{
    /* Perform PnP isolation protocol */
    return NO;
}

- (int)assignCSN:(int)logicalDevice
{
    /* Assign Card Select Number */
    return ++_csn;
}

- (BOOL)configureDevice:(int)csn logical:(int)logical
{
    /* Configure PnP device */
    return YES;
}

- (void *)readResourceData:(int)csn
{
    /* Read resource data from PnP device */
    return NULL;
}

- (void)freeResourceData:(void *)resources
{
    if (resources != NULL) {
        IOFree(resources, sizeof(void *));
    }
}

@end

/*
 * ============================================================================
 * EISABusVersion Implementation
 * ============================================================================
 */

@interface EISABusVersion : Object
{
    @private
    unsigned int _majorVersion;
    unsigned int _minorVersion;
    const char *_versionString;
}
- init;
- free;
- (unsigned int)majorVersion;
- (unsigned int)minorVersion;
- (const char *)versionString;
@end

@implementation EISABusVersion

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
 * EISAResourceDriver Implementation
 * ============================================================================
 */

@interface EISAResourceDriver : IODevice
{
    @private
    void *_resourceData;
    BOOL _initialized;
}
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription;
- free;
- (BOOL)allocateResources;
- (void)deallocateResources;
@end

@implementation EISAResourceDriver

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

    [self setName:"EISAResourceDriver"];
    [self setDeviceKind:"EISAResourceDriver"];

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

@end

/*
 * ============================================================================
 * EISABus Implementation
 * ============================================================================
 */

@implementation EISABus

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

    /* Create kernel bus instance */
    _kernBus = [[EISAKernBus alloc]
                initFromDeviceDescription:deviceDescription];
    if (_kernBus == nil) {
        IOLog("EISABus: Failed to create kernel bus instance\n");
        return nil;
    }

    /* Create version object */
    _version = [[EISABusVersion alloc] init];
    if (_version == nil) {
        IOLog("EISABus: Failed to create version object\n");
        [_kernBus free];
        return nil;
    }

    _initialized = NO;

    [self setName:"EISABus"];
    [self setDeviceKind:"EISABus"];
    [self setLocation:NULL];

    IOLog("EISABus: Initialized (Version %s)\n", [_version versionString]);

    [self registerDevice];

    return self;
}

- free
{
    if (_version != nil) {
        [_version free];
        _version = nil;
    }

    if (_kernBus != nil) {
        [_kernBus free];
        _kernBus = nil;
    }

    return [super free];
}

- (BOOL)BootDriver
{
    if (_initialized) {
        return YES;
    }

    if (_kernBus == nil) {
        IOLog("EISABus: BootDriver called without kernel bus\n");
        return NO;
    }

    /* Scan EISA slots */
    if ([self scanSlots]) {
        _initialized = YES;
        IOLog("EISABus: BootDriver completed successfully\n");
        return YES;
    }

    IOLog("EISABus: BootDriver failed to scan slots\n");
    return NO;
}

- (int)getSlotCount
{
    return EISA_MAX_SLOTS;
}

- (BOOL)scanSlots
{
    int slot;
    int deviceCount = 0;

    IOLog("EISABus: Scanning %d EISA slots\n", EISA_MAX_SLOTS);

    for (slot = 0; slot < EISA_MAX_SLOTS; slot++) {
        if ([_kernBus testSlot:slot]) {
            unsigned int idPort = EISA_ID_PORT_BASE + (slot * 0x1000);
            unsigned char id[4];
            int i;

            /* Read 4-byte ID */
            for (i = 0; i < 4; i++) {
                id[i] = inb(idPort + i);
            }

            IOLog("  EISA Slot %d: ID = %02X%02X%02X%02X\n",
                  slot, id[0], id[1], id[2], id[3]);

            deviceCount++;
        }
    }

    IOLog("EISABus: Found %d EISA device%s\n",
          deviceCount, (deviceCount == 1) ? "" : "s");

    return YES;  /* Always return success even if no devices found */
}

@end
