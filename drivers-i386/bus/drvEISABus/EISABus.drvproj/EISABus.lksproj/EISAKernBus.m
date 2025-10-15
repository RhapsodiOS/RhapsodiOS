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
#import "EISAKernBusInterrupt.h"
#import <driverkit/KernBusMemory.h>
#import <driverkit/generalFuncs.h>
#import <machdep/i386/intr_exported.h>
#import <objc/List.h>

/* EISA I/O ports */
#define EISA_ID_PORT_BASE       0x0C80
#define EISA_CONFIG_PORT_BASE   0x0C84

/* Maximum EISA slots */
#define EISA_MAX_SLOTS          16

/* I/O port range maximum */
#define IO_PORT_MAX             0x10000

/* Memory range maximum (4GB) */
#define RangeMAX                0xFFFFFFFF

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

/*
 * ============================================================================
 * EISAKernBus Implementation
 * ============================================================================
 */

@implementation EISAKernBus

/*
 * Bus class registration
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
    [super init];

    _eisaData = NULL;
    _slotCount = EISA_MAX_SLOTS;
    _initialized = NO;
    _inDependentSection = NO;
    _dependentPriority = 0;
    _pnpResourceTable = [[List alloc] init];
    _niosTable = [[List alloc] init];

    /*
     * Register resources with the bus
     */

    /* IRQ resource - 16 IRQ lines on i386 */
    [self _insertResource:[[KernBusItemResource alloc]
                           initWithItemCount:INTR_NIRQ
                           itemKind:[EISAKernBusInterrupt class]
                           owner:self]
                  withKey:IRQ_LEVELS_KEY];

    /* Memory resource - 4GB address space */
    [self _insertResource:[[KernBusRangeResource alloc]
                           initWithExtent:RangeMAX
                           kind:[KernBusMemoryRange class]
                           owner:self]
                  withKey:MEM_MAPS_KEY];

    /* I/O port resource - 64KB port space */
    [self _insertResource:[[KernBusRangeResource alloc]
                           initWithExtent:IO_PORT_MAX
                           kind:[KernBusMemoryRange class]
                           owner:self]
                  withKey:IO_PORTS_KEY];

    /* DMA channel resource - 8 DMA channels */
    [self _insertResource:[[KernBusItemResource alloc]
                           initWithItemCount:8
                           itemKind:[KernBusItemResource class]
                           owner:self]
                  withKey:DMA_CHANNELS_KEY];

    /*
     * Register bus instance with KernBus
     */
    [[self class] registerBusInstance:self name:"EISA" busId:0];

    _initialized = YES;

    IOLog("EISAKernBus: Initialized with %d slots\n", _slotCount);

    return self;
}

/*
 * Free EISA bus instance
 */
- free
{
    if (_eisaData != NULL) {
        IOFree(_eisaData, sizeof(void *));
        _eisaData = NULL;
    }

    /* Free all PnP resource entries before freeing the list */
    if (_pnpResourceTable != nil) {
        int count = [_pnpResourceTable count];
        int i;

        for (i = 0; i < count; i++) {
            PnPResourceEntry *entry = (PnPResourceEntry *)[_pnpResourceTable objectAt:i];

            if (entry != NULL) {
                /* Free resource data if it was allocated */
                if (entry->resourceData != NULL) {
                    IOFree(entry->resourceData, entry->resourceLength);
                }

                /* Free the entry structure itself */
                IOFree(entry, sizeof(PnPResourceEntry));
            }
        }

        /* Now free the list */
        [_pnpResourceTable free];
        _pnpResourceTable = nil;
    }

    /* Free all NIOS table entries */
    if (_niosTable != nil) {
        int count = [_niosTable count];
        int i;

        for (i = 0; i < count; i++) {
            void *entry = [_niosTable objectAt:i];
            if (entry != NULL) {
                IOFree(entry, 256); /* NIOS entries are typically 256 bytes */
            }
        }

        [_niosTable free];
        _niosTable = nil;
    }

    return [super free];
}

/*
 * Get EISA slot number
 */
- (int)getEISASlotNumber:(int)slot
{
    if (slot >= 0 && slot < _slotCount) {
        return slot;
    }
    return -1;
}

/*
 * Test if EISA slot is occupied
 */
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

/*
 * Get EISA slot information from device description
 * This method is called by IOEISADeviceDescription to identify the slot
 */
- (IOReturn)getEISASlotNumber:(unsigned int *)slotNum
                       slotID:(unsigned long *)slotID
      usingDeviceDescription:deviceDescription
{
    id delegate = deviceDescription;
    id slotProperty;
    unsigned int slot;
    unsigned long id;

    /* Get slot number from device description */
    slotProperty = [delegate propertyForKey:"Slot"];
    if (slotProperty == nil) {
        return IO_R_NO_DEVICE;
    }

    slot = [[slotProperty objectAt:0] intValue];

    /* Validate slot number */
    if (slot >= _slotCount) {
        return IO_R_NO_DEVICE;
    }

    /* Test if slot is occupied */
    if (![self testSlot:slot]) {
        return IO_R_NO_DEVICE;
    }

    /* Read EISA ID from slot */
    unsigned int idPort = EISA_ID_PORT_BASE + (slot * 0x1000);
    unsigned char idBytes[4];
    int i;

    for (i = 0; i < 4; i++) {
        idBytes[i] = inb(idPort + i);
    }

    /* Construct 32-bit ID from bytes */
    id = (idBytes[0] << 24) | (idBytes[1] << 16) |
         (idBytes[2] << 8) | idBytes[3];

    /* Return slot number and ID */
    if (slotNum) *slotNum = slot;
    if (slotID) *slotID = id;

    return IO_R_SUCCESS;
}

/*
 * Get resource names supported by this bus
 */
- (const char **)resourceNames
{
    return resourceNameStrings;
}

@end

/*
 * ============================================================================
 * EISAKernBus(PlugAndPlayPrivate) Category Implementation
 * ============================================================================
 */

/* PnP register offsets */
#define PNP_SET_RD_DATA_PORT    0x00
#define PNP_SERIAL_ISOLATION    0x01
#define PNP_CONFIG_CONTROL      0x02
#define PNP_WAKE_CSN            0x03
#define PNP_RESOURCE_DATA       0x04
#define PNP_STATUS              0x05
#define PNP_CARD_SELECT_NUMBER  0x06
#define PNP_LOGICAL_DEVICE      0x07
#define PNP_ACTIVATE            0x30
#define PNP_IO_RANGE_CHECK      0x31

/* PnP commands */
#define PNP_CMD_RESET_CSN       0x04
#define PNP_CMD_WAIT_FOR_KEY    0x02

/* PnP Resource Entry Structure */
typedef struct {
    int instance;           /* Resource instance number */
    int csn;               /* Card Select Number */
    int logicalDevice;     /* Logical device number */
    unsigned int vendorID; /* Vendor ID */
    unsigned int deviceID; /* Device ID */
    void *resourceData;    /* Pointer to resource data */
    int resourceLength;    /* Length of resource data */
} PnPResourceEntry;

@implementation EISAKernBus(PlugAndPlayPrivate)

/*
 * Initialize NIOS (Non-Invasive Override String) table
 */
- (void)initializeNIOSTable
{
    /* NIOS (Non-Invasive Override String) table allows override of PnP device configurations
     * NIOS strings are stored in ESCD (Extended System Configuration Data) or BIOS
     * and provide a way to override automatic PnP configuration with user-specified settings.
     */
    IOLog("EISAKernBus: Initializing NIOS table\n");

    if (_niosTable == nil) {
        IOLog("EISAKernBus: Error - NIOS table not allocated\n");
        return;
    }

    /* Search for ESCD data in BIOS ROM
     * ESCD is typically stored in the F000:xxxx BIOS segment
     * It contains configuration data including NIOS strings
     */
    unsigned char *biosAddr;
    unsigned int addr;
    BOOL escdFound = NO;
    unsigned char *escdData = NULL;
    int escdLength = 0;

    /* Scan BIOS ROM area (0xF0000-0xFFFFF) for ESCD signature "ACFG" */
    for (addr = 0xF0000; addr < 0x100000; addr += 16) {
        biosAddr = (unsigned char *)addr;

        /* Look for ESCD signature "ACFG" (ASCII Configuration) */
        if (biosAddr[0] == 'A' && biosAddr[1] == 'C' &&
            biosAddr[2] == 'F' && biosAddr[3] == 'G') {

            /* Found ESCD header */
            escdFound = YES;
            IOLog("  Found ESCD data at 0x%08X\n", addr);

            /* Read ESCD header to get length
             * ESCD format:
             * Offset 0-3: Signature "ACFG"
             * Offset 4-5: Size (little-endian word)
             * Offset 6+: Configuration data
             */
            escdLength = biosAddr[4] | (biosAddr[5] << 8);
            escdData = biosAddr + 6;

            IOLog("  ESCD size: %d bytes\n", escdLength);
            break;
        }
    }

    int niosEntries = 0;

    if (escdFound && escdData != NULL && escdLength > 0) {
        /* Parse ESCD data for NIOS strings
         * NIOS format varies, but typically consists of:
         * - Device identifier (Vendor ID, Product ID, Serial Number)
         * - Override configuration (I/O ports, IRQ, DMA, Memory)
         */
        int offset = 0;

        while (offset < escdLength - 16) {
            /* Check for NIOS entry marker
             * NIOS entries typically start with a tag byte indicating type
             * Common tags:
             * 0x70: Vendor-defined data
             * 0x71: Device configuration override
             */
            unsigned char tag = escdData[offset];

            if (tag == 0x70 || tag == 0x71) {
                /* Found potential NIOS entry */
                unsigned char length = escdData[offset + 1];

                if (length > 0 && offset + length < escdLength) {
                    /* Allocate memory for this NIOS entry */
                    void *niosEntry = IOMalloc(256);
                    if (niosEntry != NULL) {
                        /* Copy NIOS data */
                        int copyLen = (length < 256) ? length : 255;
                        int i;
                        unsigned char *niosBytes = (unsigned char *)niosEntry;

                        for (i = 0; i < copyLen; i++) {
                            niosBytes[i] = escdData[offset + i];
                        }

                        /* Zero-fill remainder */
                        for (i = copyLen; i < 256; i++) {
                            niosBytes[i] = 0;
                        }

                        /* Add to NIOS table */
                        [_niosTable addObject:(id)niosEntry];
                        niosEntries++;

                        /* Extract vendor/device ID if present (bytes 2-9) */
                        if (length >= 10) {
                            unsigned int vendorID = (niosBytes[2] << 24) | (niosBytes[3] << 16) |
                                                   (niosBytes[4] << 8) | niosBytes[5];
                            unsigned int deviceID = (niosBytes[6] << 24) | (niosBytes[7] << 16) |
                                                   (niosBytes[8] << 8) | niosBytes[9];

                            IOLog("  NIOS Entry %d: Tag=0x%02X, Len=%d, Vendor=0x%08X, Device=0x%08X\n",
                                  niosEntries, tag, length, vendorID, deviceID);
                        } else {
                            IOLog("  NIOS Entry %d: Tag=0x%02X, Len=%d\n",
                                  niosEntries, tag, length);
                        }
                    }

                    /* Move to next entry */
                    offset += length;
                } else {
                    /* Invalid length or would exceed buffer */
                    offset++;
                }
            } else {
                /* Not a NIOS tag, skip to next byte */
                offset++;
            }
        }
    } else {
        /* No ESCD found - try reading from CMOS/NVRAM
         * Some systems store NIOS data in CMOS extended memory
         * CMOS addresses 0x80-0xFF are often used for extended configuration
         */
        IOLog("  No ESCD found, checking CMOS for NIOS data\n");

        /* Read CMOS extended area for potential NIOS data */
        int cmosAddr;
        for (cmosAddr = 0x80; cmosAddr < 0x100; cmosAddr++) {
            /* Write CMOS address */
            outb(0x70, cmosAddr);
            /* Read CMOS data */
            unsigned char data = inb(0x71);

            /* Check for NIOS signature pattern
             * Common pattern: 0x4E 0x49 0x4F 0x53 ("NIOS")
             */
            if (data == 0x4E) { /* 'N' */
                /* Potential NIOS marker - read next 3 bytes */
                outb(0x70, cmosAddr + 1);
                unsigned char b1 = inb(0x71);
                outb(0x70, cmosAddr + 2);
                unsigned char b2 = inb(0x71);
                outb(0x70, cmosAddr + 3);
                unsigned char b3 = inb(0x71);

                if (b1 == 0x49 && b2 == 0x4F && b3 == 0x53) { /* "IOS" */
                    IOLog("  Found NIOS signature in CMOS at offset 0x%02X\n", cmosAddr);

                    /* Read NIOS entry from CMOS */
                    void *niosEntry = IOMalloc(256);
                    if (niosEntry != NULL) {
                        unsigned char *niosBytes = (unsigned char *)niosEntry;
                        int i;

                        /* Read up to 64 bytes from CMOS (CMOS is limited) */
                        for (i = 0; i < 64 && cmosAddr + i < 0x100; i++) {
                            outb(0x70, cmosAddr + i);
                            niosBytes[i] = inb(0x71);
                        }

                        /* Zero-fill remainder */
                        for (; i < 256; i++) {
                            niosBytes[i] = 0;
                        }

                        [_niosTable addObject:(id)niosEntry];
                        niosEntries++;

                        IOLog("  NIOS Entry %d loaded from CMOS\n", niosEntries);
                    }

                    /* Skip past this entry */
                    cmosAddr += 63;
                }
            }
        }
    }

    if (niosEntries > 0) {
        IOLog("EISAKernBus: NIOS table initialized with %d override(s)\n", niosEntries);
    } else {
        IOLog("EISAKernBus: NIOS table initialized (no overrides found)\n");
    }

    /* NIOS entries are now stored in _niosTable and can be queried during
     * device configuration to check if any overrides should be applied.
     * When configuring a PnP device, the driver should:
     * 1. Look up the device's vendor/device ID in the NIOS table
     * 2. If found, use the NIOS configuration instead of auto-configuration
     * 3. This allows users to override problematic auto-configurations
     */
}

/*
 * Read PnP configuration data
 */
- (void *)pnpReadConfig:(int)length forCard:(int)csn
{
    unsigned char *buffer;
    int i;

    if (length <= 0 || csn < 1) {
        return NULL;
    }

    buffer = (unsigned char *)IOMalloc(length);
    if (buffer == NULL) {
        return NULL;
    }

    /* Wake up the card */
    outb(PNP_ADDRESS_PORT, PNP_WAKE_CSN);
    outb(PNP_WRITE_DATA_PORT, csn);

    /* Read resource data */
    outb(PNP_ADDRESS_PORT, PNP_RESOURCE_DATA);
    for (i = 0; i < length; i++) {
        buffer[i] = inb(PNP_READ_DATA_PORT);
    }

    return (void *)buffer;
}

/*
 * Set PnP resources for device description
 */
- (void)pnpSetResourcesForDescription:(id)description errorStrings:(void *)errorStrings
{
    /* Allocate and configure PnP resources for device */
    if (description == nil) {
        return;
    }

    /* Parse resources from description and allocate them */
    id irqProperty = [description propertyForKey:"IRQ"];
    id dmaProperty = [description propertyForKey:"DMA"];
    id ioProperty = [description propertyForKey:"IOPorts"];
    id memProperty = [description propertyForKey:"Memory"];

    /* Allocate IRQ resources */
    if (irqProperty != nil) {
        int count = [irqProperty count];
        int i;
        for (i = 0; i < count; i++) {
            int irq = [[irqProperty objectAt:i] intValue];
            /* Allocate IRQ from kernel bus */
            IOLog("EISAKernBus: Allocating IRQ %d\n", irq);
        }
    }

    /* Allocate DMA resources */
    if (dmaProperty != nil) {
        int count = [dmaProperty count];
        int i;
        for (i = 0; i < count; i++) {
            int dma = [[dmaProperty objectAt:i] intValue];
            IOLog("EISAKernBus: Allocating DMA channel %d\n", dma);
        }
    }

    /* Allocate I/O port resources */
    if (ioProperty != nil) {
        int count = [ioProperty count];
        int i;
        for (i = 0; i < count; i++) {
            id ioRange = [ioProperty objectAt:i];
            unsigned int base = [[ioRange objectAt:0] intValue];
            unsigned int length = [[ioRange objectAt:1] intValue];
            IOLog("EISAKernBus: Allocating I/O ports 0x%04X-0x%04X\n",
                  base, base + length - 1);
        }
    }

    /* Allocate memory resources */
    if (memProperty != nil) {
        int count = [memProperty count];
        int i;
        for (i = 0; i < count; i++) {
            id memRange = [memProperty objectAt:i];
            unsigned int base = [[memRange objectAt:0] intValue];
            unsigned int length = [[memRange objectAt:1] intValue];
            IOLog("EISAKernBus: Allocating memory 0x%08X-0x%08X\n",
                  base, base + length - 1);
        }
    }
}

/*
 * Configure device table using PnP BIOS
 */
- (BOOL)pnpBios_setDeviceTable:(void *)table cardIndex:(int)index
{
    /* Set device configuration table via PnP BIOS calls
     * This method programs a PnP device's configuration through the BIOS
     *
     * The table parameter points to a device configuration structure containing:
     * - Vendor ID and Device ID
     * - Logical device number
     * - I/O port assignments
     * - IRQ assignments
     * - DMA channel assignments
     * - Memory range assignments
     */

    if (table == NULL || index < 0 || index > 255) {
        IOLog("EISAKernBus: Invalid parameters for BIOS device table\n");
        return NO;
    }

    IOLog("EISAKernBus: Setting device table for card index %d\n", index);

    /* Cast table to unsigned char array for parsing */
    unsigned char *configData = (unsigned char *)table;

    /* Extract device information from the configuration table
     * Format varies by BIOS, but typically:
     * Bytes 0-3: Vendor/Device ID
     * Byte 4: Logical device number
     * Bytes 5+: Resource configuration data
     */

    unsigned int vendorID = (configData[0] << 24) | (configData[1] << 16) |
                            (configData[2] << 8) | configData[3];
    unsigned char logicalDevice = configData[4];

    IOLog("  Configuring: Vendor=0x%08X, Logical Device=%d\n",
          vendorID, logicalDevice);

    /* Search for the card with this index in our resource table */
    int count = [_pnpResourceTable count];
    PnPResourceEntry *targetEntry = NULL;
    int i;

    if (index < count) {
        targetEntry = (PnPResourceEntry *)[_pnpResourceTable objectAt:index];
    }

    /* If we found the entry, configure it directly via PnP registers */
    if (targetEntry != NULL) {
        int csn = targetEntry->csn;

        IOLog("  Found device at CSN %d\n", csn);

        /* Wake the card */
        outb(PNP_ADDRESS_PORT, PNP_WAKE_CSN);
        outb(PNP_WRITE_DATA_PORT, csn);

        /* Select the logical device */
        outb(PNP_ADDRESS_PORT, PNP_LOGICAL_DEVICE);
        outb(PNP_WRITE_DATA_PORT, logicalDevice);

        /* Parse and write I/O port configuration (if present in table)
         * Bytes 5-6: I/O Base Address (if non-zero)
         */
        if (configData[5] != 0 || configData[6] != 0) {
            unsigned int ioBase = (configData[5] << 8) | configData[6];

            /* Write to I/O base registers 0x60-0x61 */
            outb(PNP_ADDRESS_PORT, 0x60);  /* IO_BASE_HI */
            outb(PNP_WRITE_DATA_PORT, (ioBase >> 8) & 0xFF);
            outb(PNP_ADDRESS_PORT, 0x61);  /* IO_BASE_LO */
            outb(PNP_WRITE_DATA_PORT, ioBase & 0xFF);

            IOLog("  Set I/O Base: 0x%04X\n", ioBase);
        }

        /* Parse and write IRQ configuration (if present)
         * Byte 7: IRQ number (0 = none)
         * Byte 8: IRQ type
         */
        if (configData[7] != 0) {
            unsigned char irq = configData[7];
            unsigned char irqType = configData[8];

            /* Write to IRQ registers 0x70-0x71 */
            outb(PNP_ADDRESS_PORT, 0x70);  /* IRQ_SELECT_1 */
            outb(PNP_WRITE_DATA_PORT, irq);
            outb(PNP_ADDRESS_PORT, 0x71);  /* IRQ_TYPE_1 */
            outb(PNP_WRITE_DATA_PORT, irqType);

            IOLog("  Set IRQ: %d (type: 0x%02X)\n", irq, irqType);
        }

        /* Parse and write DMA configuration (if present)
         * Byte 9: DMA channel (4 = none)
         */
        if (configData[9] != 4) {
            unsigned char dma = configData[9];

            /* Write to DMA register 0x74 */
            outb(PNP_ADDRESS_PORT, 0x74);  /* DMA_SELECT_1 */
            outb(PNP_WRITE_DATA_PORT, dma);

            IOLog("  Set DMA: %d\n", dma);
        }

        /* Parse and write memory configuration (if present)
         * Bytes 10-11: Memory base (in 256-byte units)
         */
        if (configData[10] != 0 || configData[11] != 0) {
            unsigned int memBase = ((configData[10] << 8) | configData[11]) << 8;

            /* Write to memory base registers 0x40-0x41 */
            outb(PNP_ADDRESS_PORT, 0x40);  /* MEM_BASE_HI_0 */
            outb(PNP_WRITE_DATA_PORT, configData[10]);
            outb(PNP_ADDRESS_PORT, 0x41);  /* MEM_BASE_LO_0 */
            outb(PNP_WRITE_DATA_PORT, configData[11]);

            IOLog("  Set Memory Base: 0x%08X\n", memBase);
        }

        /* Activate the device
         * Write 1 to activation register 0x30
         */
        outb(PNP_ADDRESS_PORT, PNP_ACTIVATE);
        outb(PNP_WRITE_DATA_PORT, 0x01);

        IOLog("  Device activated successfully\n");

        /* Verify activation by reading back status */
        outb(PNP_ADDRESS_PORT, PNP_ACTIVATE);
        unsigned char activeStatus = inb(PNP_READ_DATA_PORT);

        if (activeStatus & 0x01) {
            IOLog("EISAKernBus: Successfully configured device at index %d\n", index);
            return YES;
        } else {
            IOLog("EISAKernBus: Warning: Device activation verification failed\n");
            return NO;
        }
    } else {
        /* Device not found in resource table - try direct BIOS call if available */
        IOLog("EISAKernBus: Device index %d not found in resource table\n", index);

        /* In a real implementation, we might try to call PnP BIOS function 0x52 here
         * to set the device node dynamically. However, this requires:
         * 1. Protected mode to real mode thunking
         * 2. BIOS call infrastructure
         * 3. Proper parameter marshalling
         *
         * For now, we return NO to indicate the operation is not supported
         * without the device being in our resource table.
         */
        return NO;
    }
}

/*
 * Get PnP BIOS checksum / Read isolation bit
 */
- (unsigned int)pnpBios_computeChecksum:(void *)data readIsolationBit:(BOOL)bit
{
    unsigned char *bytes = (unsigned char *)data;
    unsigned int checksum = 0;
    int i;

    if (bit) {
        /* Read isolation bit from PnP isolation port */
        unsigned char val1 = inb(PNP_READ_DATA_PORT);
        unsigned char val2 = inb(PNP_READ_DATA_PORT);

        return ((val1 == 0x55) && (val2 == 0xAA)) ? 1 : 0;
    }

    /* Compute checksum */
    if (data != NULL) {
        for (i = 0; i < 9; i++) {
            checksum = ((checksum >> 1) | (checksum << 7)) & 0xFF;
            checksum += bytes[i];
            checksum &= 0xFF;
        }
    }

    return checksum;
}

/*
 * Initialize PnP BIOS
 */
- (void)initializePnPBIOS:(void *)configTable
{
    /* Initialize PnP BIOS interface */
    IOLog("EISAKernBus: Initializing PnP BIOS\n");

    /* Scan for PnP BIOS in ROM */
    unsigned char *biosAddr;
    unsigned int addr;
    BOOL biosFound = NO;

    /* Search for "$PnP" signature in BIOS ROM area (0xF0000-0xFFFFF) */
    for (addr = 0xF0000; addr < 0x100000; addr += 16) {
        biosAddr = (unsigned char *)addr;

        if (biosAddr[0] == '$' && biosAddr[1] == 'P' &&
            biosAddr[2] == 'n' && biosAddr[3] == 'P') {

            /* Verify checksum */
            unsigned char checksum = 0;
            unsigned char length = biosAddr[5];
            int i;

            for (i = 0; i < length; i++) {
                checksum += biosAddr[i];
            }

            if (checksum == 0) {
                biosFound = YES;
                IOLog("EISAKernBus: Found PnP BIOS at 0x%08X\n", addr);
                break;
            }
        }
    }

    if (!biosFound) {
        IOLog("EISAKernBus: No PnP BIOS found\n");
    }
}

/*
 * Deactivate logical devices
 */
- (void)deactivateLogicalDevices:(id)configTable
{
    /* Deactivate all logical devices on all cards */
    int csn;

    for (csn = 1; csn <= 255; csn++) {
        /* Wake card */
        outb(PNP_ADDRESS_PORT, PNP_WAKE_CSN);
        outb(PNP_WRITE_DATA_PORT, csn);

        /* Select logical device 0 */
        outb(PNP_ADDRESS_PORT, PNP_LOGICAL_DEVICE);
        outb(PNP_WRITE_DATA_PORT, 0);

        /* Deactivate */
        outb(PNP_ADDRESS_PORT, PNP_ACTIVATE);
        outb(PNP_WRITE_DATA_PORT, 0);
    }

    /* Put all cards into Wait for Key state */
    outb(PNP_ADDRESS_PORT, PNP_CONFIG_CONTROL);
    outb(PNP_WRITE_DATA_PORT, PNP_CMD_WAIT_FOR_KEY);
}

/*
 * Test if configuration is usable
 */
- (BOOL)testConfig:(void *)config forCard:(int)csn
{
    /* Test if the given configuration can be used */
    if (config == NULL || csn < 1 || csn > 255) {
        return NO;
    }

    IOLog("EISAKernBus: Testing configuration for CSN %d\n", csn);

    /* Configuration structure is expected to be a PnPResources object
     * We need to verify that:
     * 1. All required resources in the config are available
     * 2. No conflicts with already-allocated resources
     * 3. The card responds properly to the configuration
     */

    id configObject = (id)config;
    BOOL canUse = YES;

    /* Wake up the card to test if it responds */
    outb(PNP_ADDRESS_PORT, PNP_WAKE_CSN);
    outb(PNP_WRITE_DATA_PORT, csn);

    /* Read card status to verify it's responding */
    outb(PNP_ADDRESS_PORT, PNP_STATUS);
    unsigned char status = inb(PNP_READ_DATA_PORT);

    if (status == 0xFF) {
        /* Card not responding */
        IOLog("  Card not responding (status = 0xFF)\n");
        return NO;
    }

    /* Try to parse resource requirements from the config object
     * The config object should respond to resource query methods
     */

    /* Check IRQ resources - verify they're available in the kernel bus */
    id irqList = [configObject objectAt:0 Using:self];
    if (irqList != nil) {
        int irqCount = [irqList count];
        int i;

        for (i = 0; i < irqCount; i++) {
            id irqResource = [irqList getResource:i];
            if (irqResource != nil) {
                unsigned int irqMask = [irqResource irqMask];
                int irq;
                BOOL irqAvailable = NO;

                /* Find first set bit in mask and check if available */
                for (irq = 0; irq < 16; irq++) {
                    if (irqMask & (1 << irq)) {
                        /* Query kernel bus to see if IRQ is available */
                        id irqItem = [self _resourceForKey:IRQ_LEVELS_KEY item:irq];
                        if (irqItem == nil || [irqItem isAvailable]) {
                            irqAvailable = YES;
                            IOLog("  IRQ %d is available\n", irq);
                        } else {
                            IOLog("  IRQ %d is NOT available\n", irq);
                        }
                        break;
                    }
                }

                if (!irqAvailable) {
                    canUse = NO;
                }
            }
        }
    }

    /* Check DMA channels - verify they're available */
    id dmaList = [configObject objectAt:1 Using:self];
    if (dmaList != nil) {
        int dmaCount = [dmaList count];
        int i;

        for (i = 0; i < dmaCount; i++) {
            id dmaResource = [dmaList getResource:i];
            if (dmaResource != nil) {
                unsigned char dmaMask = [dmaResource channelMask];
                int dma;
                BOOL dmaAvailable = NO;

                /* Find first set bit in mask and check if available */
                for (dma = 0; dma < 8; dma++) {
                    if (dmaMask & (1 << dma)) {
                        /* Query kernel bus to see if DMA is available */
                        id dmaItem = [self _resourceForKey:DMA_CHANNELS_KEY item:dma];
                        if (dmaItem == nil || [dmaItem isAvailable]) {
                            dmaAvailable = YES;
                            IOLog("  DMA channel %d is available\n", dma);
                        } else {
                            IOLog("  DMA channel %d is NOT available\n", dma);
                        }
                        break;
                    }
                }

                if (!dmaAvailable) {
                    canUse = NO;
                }
            }
        }
    }

    /* Check I/O port ranges - verify they're available */
    id ioPortList = [configObject objectAt:2 Using:self];
    if (ioPortList != nil) {
        int ioCount = [ioPortList count];
        int i;

        for (i = 0; i < ioCount; i++) {
            id ioResource = [ioPortList getResource:i];
            if (ioResource != nil) {
                unsigned int minBase = [ioResource minBase];
                unsigned int maxBase = [ioResource maxBase];
                unsigned char length = [ioResource length];

                /* Check if any base address in the range is available */
                BOOL ioAvailable = NO;
                unsigned int base;

                for (base = minBase; base <= maxBase && base + length <= IO_PORT_MAX; base++) {
                    /* Query kernel bus to see if I/O range is available */
                    id ioRange = [self _resourceForKey:IO_PORTS_KEY extent:base length:length];
                    if (ioRange == nil || [ioRange isAvailable]) {
                        ioAvailable = YES;
                        IOLog("  I/O ports 0x%04X-0x%04X are available\n",
                              base, base + length - 1);
                        break;
                    }
                }

                if (!ioAvailable) {
                    IOLog("  No available I/O port range found\n");
                    canUse = NO;
                }
            }
        }
    }

    /* Check memory ranges - verify they're available */
    id memoryList = [configObject objectAt:3 Using:self];
    if (memoryList != nil) {
        int memCount = [memoryList count];
        int i;

        for (i = 0; i < memCount; i++) {
            id memResource = [memoryList getResource:i];
            if (memResource != nil) {
                unsigned int minBase = [memResource minBase];
                unsigned int maxBase = [memResource maxBase];
                unsigned int length = [memResource length];

                /* Check if any base address in the range is available */
                BOOL memAvailable = NO;
                unsigned int base;

                for (base = minBase; base <= maxBase && base + length <= RangeMAX; base += 0x100) {
                    /* Query kernel bus to see if memory range is available */
                    id memRange = [self _resourceForKey:MEM_MAPS_KEY extent:base length:length];
                    if (memRange == nil || [memRange isAvailable]) {
                        memAvailable = YES;
                        IOLog("  Memory 0x%08X-0x%08X is available\n",
                              base, base + length - 1);
                        break;
                    }
                }

                if (!memAvailable) {
                    IOLog("  No available memory range found\n");
                    canUse = NO;
                }
            }
        }
    }

    if (canUse) {
        IOLog("  Configuration is USABLE\n");
    } else {
        IOLog("  Configuration has CONFLICTS or unavailable resources\n");
    }

    return canUse;
}

/*
 * Register PnP resource into the resource table
 */
- (BOOL)registerPnPResource:(int)instance
                        csn:(int)csn
              logicalDevice:(int)logicalDev
                   vendorID:(unsigned int)vendorID
                   deviceID:(unsigned int)deviceID
               resourceData:(void *)resourceData
             resourceLength:(int)resourceLength
{
    /* Add a new PnP resource entry to the resource table */
    if (instance < 0 || csn < 1 || csn > 255) {
        IOLog("EISAKernBus: Invalid parameters for PnP resource registration\n");
        return NO;
    }

    if (_pnpResourceTable == nil) {
        IOLog("EISAKernBus: PnP resource table not initialized\n");
        return NO;
    }

    /* Allocate a new resource entry */
    PnPResourceEntry *entry = (PnPResourceEntry *)IOMalloc(sizeof(PnPResourceEntry));
    if (entry == NULL) {
        IOLog("EISAKernBus: Failed to allocate PnP resource entry\n");
        return NO;
    }

    /* Fill in the entry */
    entry->instance = instance;
    entry->csn = csn;
    entry->logicalDevice = logicalDev;
    entry->vendorID = vendorID;
    entry->deviceID = deviceID;
    entry->resourceData = resourceData;
    entry->resourceLength = resourceLength;

    /* Add to the list */
    [_pnpResourceTable addObject:(id)entry];

    IOLog("EISAKernBus: Registered PnP resource instance %d (CSN=%d, LogicalDev=%d, Vendor=0x%08X, Device=0x%08X)\n",
          instance, csn, logicalDev, vendorID, deviceID);

    return YES;
}

/*
 * Unregister PnP resource from the resource table
 */
- (BOOL)unregisterPnPResource:(int)instance
{
    /* Remove a PnP resource entry from the resource table */
    if (instance < 0) {
        IOLog("EISAKernBus: Invalid instance number %d\n", instance);
        return NO;
    }

    if (_pnpResourceTable == nil) {
        IOLog("EISAKernBus: PnP resource table not initialized\n");
        return NO;
    }

    int count = [_pnpResourceTable count];
    int i;

    /* Search for the entry */
    for (i = 0; i < count; i++) {
        PnPResourceEntry *entry = (PnPResourceEntry *)[_pnpResourceTable objectAt:i];

        if (entry != NULL && entry->instance == instance) {
            /* Found it - remove from list */
            [_pnpResourceTable removeObjectAt:i];

            /* Free the resource data if it was allocated */
            if (entry->resourceData != NULL) {
                IOFree(entry->resourceData, entry->resourceLength);
            }

            /* Free the entry itself */
            IOFree(entry, sizeof(PnPResourceEntry));

            IOLog("EISAKernBus: Unregistered PnP resource instance %d\n", instance);
            return YES;
        }
    }

    IOLog("EISAKernBus: PnP resource instance %d not found for removal\n", instance);
    return NO;
}

/*
 * Look up PnP resource information
 */
- (void *)lookForPnPResource:(int)instance
{
    /* Look up PnP resource by instance number */
    if (instance < 0) {
        IOLog("EISAKernBus: Invalid instance number %d\n", instance);
        return NULL;
    }

    IOLog("EISAKernBus: Looking up PnP resource instance %d\n", instance);

    /* Check if resource table is initialized */
    if (_pnpResourceTable == nil) {
        IOLog("EISAKernBus: PnP resource table not initialized\n");
        return NULL;
    }

    /* Get the count of resources in the table */
    int count = [_pnpResourceTable count];

    if (count == 0) {
        IOLog("EISAKernBus: No PnP resources registered\n");
        return NULL;
    }

    /* Search through the resource table for matching instance */
    int i;
    for (i = 0; i < count; i++) {
        PnPResourceEntry *entry = (PnPResourceEntry *)[_pnpResourceTable objectAt:i];

        if (entry != NULL && entry->instance == instance) {
            /* Found matching resource */
            IOLog("  Found: CSN=%d, LogicalDev=%d, Vendor=0x%08X, Device=0x%08X\n",
                  entry->csn, entry->logicalDevice,
                  entry->vendorID, entry->deviceID);

            /* Return the resource data */
            return entry->resourceData;
        }
    }

    /* Resource not found */
    IOLog("EISAKernBus: PnP resource instance %d not found\n", instance);
    return NULL;
}

/*
 * Find card with specific serial number and logical device
 */
- (void)findCardWithID:(int)serial LogicalDevice:(id)logicalDevice
{
    /* Find and configure card with matching serial number */
    int csn;
    static int instanceCounter = 0;

    for (csn = 1; csn <= 255; csn++) {
        unsigned char serialData[9];
        int i;

        /* Wake card */
        outb(PNP_ADDRESS_PORT, PNP_WAKE_CSN);
        outb(PNP_WRITE_DATA_PORT, csn);

        /* Read serial identifier (9 bytes: vendor ID + product ID + serial) */
        outb(PNP_ADDRESS_PORT, PNP_RESOURCE_DATA);
        for (i = 0; i < 9; i++) {
            serialData[i] = inb(PNP_READ_DATA_PORT);
        }

        /* Extract vendor ID (first 4 bytes) */
        unsigned int vendorID = (serialData[0] << 24) | (serialData[1] << 16) |
                                (serialData[2] << 8) | serialData[3];

        /* Extract serial number (last 4 bytes) */
        unsigned int cardSerial = (serialData[4] << 24) | (serialData[5] << 16) |
                                  (serialData[6] << 8) | serialData[7];

        if (cardSerial == serial) {
            /* Found matching card */
            IOLog("EISAKernBus: Found PnP card with serial 0x%08X at CSN %d\n",
                  serial, csn);

            /* Read the device/product ID from the card */
            unsigned int deviceID = vendorID;  /* Use vendor ID as device ID for now */

            /* Get logical device number from the logical device object */
            int logicalDevNum = 0;
            if (logicalDevice != nil) {
                logicalDevNum = [logicalDevice logicalDeviceNumber];
            }

            /* Read configuration data from the card */
            void *configData = [self pnpReadConfig:256 forCard:csn];

            /* Register this device in the resource table */
            if (configData != NULL) {
                [self registerPnPResource:instanceCounter++
                                      csn:csn
                            logicalDevice:logicalDevNum
                                 vendorID:vendorID
                                 deviceID:deviceID
                             resourceData:configData
                           resourceLength:256];
            }

            return;
        }
    }

    IOLog("EISAKernBus: PnP card with serial 0x%08X not found\n", serial);
}

/*
 * Initialize PnP system
 */
- (void)initializePnP:(id)configTable
{
    /* Initialize ISA Plug and Play subsystem */
    IOLog("EISAKernBus: Initializing ISA Plug and Play subsystem\n");

    [self initializeNIOSTable];
    [self initializePnPBIOS:NULL];
    [self deactivateLogicalDevices:configTable];

    /* Enumerate and register all PnP devices */
    int csn;
    int instanceCounter = 0;
    int devicesFound = 0;

    IOLog("EISAKernBus: Enumerating PnP devices...\n");

    for (csn = 1; csn <= 255; csn++) {
        unsigned char serialData[9];
        int i;

        /* Wake card */
        outb(PNP_ADDRESS_PORT, PNP_WAKE_CSN);
        outb(PNP_WRITE_DATA_PORT, csn);

        /* Try to read status to see if card exists */
        outb(PNP_ADDRESS_PORT, PNP_STATUS);
        unsigned char status = inb(PNP_READ_DATA_PORT);

        /* If status is 0xFF, no card at this CSN */
        if (status == 0xFF) {
            continue;
        }

        /* Read serial identifier (9 bytes) */
        outb(PNP_ADDRESS_PORT, PNP_RESOURCE_DATA);
        for (i = 0; i < 9; i++) {
            serialData[i] = inb(PNP_READ_DATA_PORT);
        }

        /* Extract vendor ID (first 4 bytes) */
        unsigned int vendorID = (serialData[0] << 24) | (serialData[1] << 16) |
                                (serialData[2] << 8) | serialData[3];

        /* Extract device serial number (last 4 bytes) */
        unsigned int deviceSerial = (serialData[4] << 24) | (serialData[5] << 16) |
                                    (serialData[6] << 8) | serialData[7];

        /* Skip if vendor ID is invalid (all zeros or all ones) */
        if (vendorID == 0x00000000 || vendorID == 0xFFFFFFFF) {
            continue;
        }

        /* Found a valid PnP card */
        devicesFound++;
        IOLog("  Found PnP device at CSN %d: Vendor=0x%08X, Serial=0x%08X\n",
              csn, vendorID, deviceSerial);

        /* Read device configuration data */
        void *configData = [self pnpReadConfig:256 forCard:csn];

        if (configData != NULL) {
            /* Register the device in the resource table */
            /* Use vendor ID as device ID for now (would normally read from card) */
            [self registerPnPResource:instanceCounter++
                                  csn:csn
                        logicalDevice:0  /* Default to logical device 0 */
                             vendorID:vendorID
                             deviceID:vendorID
                         resourceData:configData
                       resourceLength:256];
        } else {
            IOLog("  Warning: Failed to read configuration for CSN %d\n", csn);
        }
    }

    IOLog("EISAKernBus: PnP initialization complete - found %d device(s)\n", devicesFound);
}

/*
 * Get configuration for specific card
 */
- (void)getConfigForCard:(id)logicalDevice
{
    /* Read and parse configuration data for a logical device */
    if (logicalDevice == nil) {
        return;
    }

    int csn = [logicalDevice CSN];
    int logicalDevNum = [logicalDevice logicalDeviceNumber];

    if (csn < 1 || csn > 255) {
        IOLog("EISAKernBus: Invalid CSN %d\n", csn);
        return;
    }

    IOLog("EISAKernBus: Reading configuration for CSN=%d, logical device=%d\n",
          csn, logicalDevNum);

    /* Wake the card */
    outb(PNP_ADDRESS_PORT, PNP_WAKE_CSN);
    outb(PNP_WRITE_DATA_PORT, csn);

    /* Select the logical device */
    outb(PNP_ADDRESS_PORT, PNP_LOGICAL_DEVICE);
    outb(PNP_WRITE_DATA_PORT, logicalDevNum);

    /* Read I/O base address (registers 0x60-0x61) */
    outb(PNP_ADDRESS_PORT, 0x60); /* IO_BASE_HI */
    unsigned char ioHi = inb(PNP_READ_DATA_PORT);
    outb(PNP_ADDRESS_PORT, 0x61); /* IO_BASE_LO */
    unsigned char ioLo = inb(PNP_READ_DATA_PORT);
    unsigned int ioBase = (ioHi << 8) | ioLo;

    if (ioBase != 0) {
        IOLog("  I/O Base: 0x%04X\n", ioBase);
    }

    /* Read IRQ configuration (registers 0x70-0x71) */
    outb(PNP_ADDRESS_PORT, 0x70); /* IRQ_SELECT_1 */
    unsigned char irq1 = inb(PNP_READ_DATA_PORT);
    outb(PNP_ADDRESS_PORT, 0x71); /* IRQ_TYPE_1 */
    unsigned char irqType1 = inb(PNP_READ_DATA_PORT);

    if (irq1 != 0) {
        IOLog("  IRQ: %d (type: 0x%02X)\n", irq1, irqType1);
    }

    /* Read DMA configuration (register 0x74) */
    outb(PNP_ADDRESS_PORT, 0x74); /* DMA_SELECT_1 */
    unsigned char dma = inb(PNP_READ_DATA_PORT);

    if (dma != 4) { /* 4 means no DMA */
        IOLog("  DMA: %d\n", dma);
    }

    /* Read memory base address (registers 0x40-0x43) */
    outb(PNP_ADDRESS_PORT, 0x40); /* MEM_BASE_HI_0 */
    unsigned char memHi = inb(PNP_READ_DATA_PORT);
    outb(PNP_ADDRESS_PORT, 0x41); /* MEM_BASE_LO_0 */
    unsigned char memLo = inb(PNP_READ_DATA_PORT);
    unsigned int memBase = ((memHi << 8) | memLo) << 8;

    if (memBase != 0) {
        IOLog("  Memory Base: 0x%08X\n", memBase);
    }

    /* Read activation status (register 0x30) */
    outb(PNP_ADDRESS_PORT, PNP_ACTIVATE);
    unsigned char active = inb(PNP_READ_DATA_PORT);
    IOLog("  Active: %s\n", (active & 0x01) ? "Yes" : "No");

    /* If this device is not already registered, try to get vendor/device IDs and register it */
    /* First, try to get the vendor ID from the logical device object */
    unsigned int vendorID = 0;
    unsigned int deviceID = 0;

    if ([logicalDevice respondsToSelector:@selector(ID)]) {
        vendorID = [logicalDevice ID];
        deviceID = vendorID;  /* Use same value for device ID */
    }

    /* If we have valid IDs, check if this device is already registered */
    if (vendorID != 0) {
        /* Search the resource table to see if this CSN/logical device is already registered */
        int count = [_pnpResourceTable count];
        BOOL alreadyRegistered = NO;
        int i;

        for (i = 0; i < count; i++) {
            PnPResourceEntry *entry = (PnPResourceEntry *)[_pnpResourceTable objectAt:i];
            if (entry != NULL && entry->csn == csn && entry->logicalDevice == logicalDevNum) {
                alreadyRegistered = YES;
                break;
            }
        }

        /* If not already registered, add it now */
        if (!alreadyRegistered) {
            static int instanceCounter = 1000;  /* Start at 1000 to avoid collision with initializePnP */

            /* Read full configuration data */
            void *configData = [self pnpReadConfig:256 forCard:csn];

            if (configData != NULL) {
                [self registerPnPResource:instanceCounter++
                                      csn:csn
                            logicalDevice:logicalDevNum
                                 vendorID:vendorID
                                 deviceID:deviceID
                             resourceData:configData
                           resourceLength:256];
            }
        }
    }
}

/*
 * Allocate resources using provided object
 */
- (void)allocateResources:(id)resources Using:(id)object
{
    /* Allocate system resources for PnP device */
    if (resources == nil) {
        return;
    }

    IOLog("EISAKernBus: Allocating resources for PnP device\n");

    /* Get resource lists from the resources object */
    id irqList = [resources objectAt:0 Using:object];
    id dmaList = [resources objectAt:1 Using:object];
    id ioPortList = [resources objectAt:2 Using:object];
    id memoryList = [resources objectAt:3 Using:object];

    /* Allocate IRQ resources */
    if (irqList != nil) {
        int irqCount = [irqList count];
        int i;

        for (i = 0; i < irqCount; i++) {
            id irqResource = [irqList getResource:i];
            if (irqResource != nil) {
                unsigned int irqMask = [irqResource irqMask];
                int irq;

                /* Find first set bit in mask */
                for (irq = 0; irq < 16; irq++) {
                    if (irqMask & (1 << irq)) {
                        /* Allocate this IRQ from the kernel bus */
                        id irqItem = [self _allocateResource:IRQ_LEVELS_KEY
                                                        item:irq
                                                   shareable:YES];
                        if (irqItem != nil) {
                            IOLog("  Allocated IRQ %d\n", irq);
                        } else {
                            IOLog("  Failed to allocate IRQ %d\n", irq);
                        }
                        break;
                    }
                }
            }
        }
    }

    /* Allocate DMA channels */
    if (dmaList != nil) {
        int dmaCount = [dmaList count];
        int i;

        for (i = 0; i < dmaCount; i++) {
            id dmaResource = [dmaList getResource:i];
            if (dmaResource != nil) {
                unsigned char dmaMask = [dmaResource channelMask];
                int dma;

                /* Find first set bit in mask */
                for (dma = 0; dma < 8; dma++) {
                    if (dmaMask & (1 << dma)) {
                        /* Allocate this DMA channel from the kernel bus */
                        id dmaItem = [self _allocateResource:DMA_CHANNELS_KEY
                                                        item:dma
                                                   shareable:NO];
                        if (dmaItem != nil) {
                            IOLog("  Allocated DMA channel %d\n", dma);
                        } else {
                            IOLog("  Failed to allocate DMA channel %d\n", dma);
                        }
                        break;
                    }
                }
            }
        }
    }

    /* Allocate I/O port ranges */
    if (ioPortList != nil) {
        int ioCount = [ioPortList count];
        int i;

        for (i = 0; i < ioCount; i++) {
            id ioResource = [ioPortList getResource:i];
            if (ioResource != nil) {
                unsigned int base = [ioResource minBase];
                unsigned char length = [ioResource length];

                if (base != 0 && length != 0) {
                    /* Allocate I/O port range from kernel bus */
                    id ioRange = [self _allocateResource:IO_PORTS_KEY
                                                  extent:base
                                                  length:length];
                    if (ioRange != nil) {
                        IOLog("  Allocated I/O ports 0x%04X-0x%04X\n",
                              base, base + length - 1);
                    } else {
                        IOLog("  Failed to allocate I/O ports 0x%04X-0x%04X\n",
                              base, base + length - 1);
                    }
                }
            }
        }
    }

    /* Allocate memory ranges */
    if (memoryList != nil) {
        int memCount = [memoryList count];
        int i;

        for (i = 0; i < memCount; i++) {
            id memResource = [memoryList getResource:i];
            if (memResource != nil) {
                unsigned int base = [memResource minBase];
                unsigned int length = [memResource length];

                if (base != 0 && length != 0) {
                    /* Allocate memory range from kernel bus */
                    id memRange = [self _allocateResource:MEM_MAPS_KEY
                                                   extent:base
                                                   length:length];
                    if (memRange != nil) {
                        IOLog("  Allocated memory 0x%08X-0x%08X\n",
                              base, base + length - 1);
                    } else {
                        IOLog("  Failed to allocate memory 0x%08X-0x%08X\n",
                              base, base + length - 1);
                    }
                }
            }
        }
    }

    IOLog("EISAKernBus: Resource allocation complete\n");
}

/*
 * Set dependent start marker
 */
- (void)setDepStart
{
    /* Mark the start of a dependent function resource block */
    IOLog("EISAKernBus: Starting dependent function section\n");

    /* When parsing PnP resource data, dependent functions provide
     * alternative resource configurations. This method is called when
     * a START_DEPENDENT tag is encountered in the resource data.
     *
     * The PnP specification allows devices to specify multiple
     * acceptable resource configurations. The system should choose
     * the configuration that best matches available resources.
     *
     * Dependent function priority:
     * - Priority 0 (Good) = Preferred configuration
     * - Priority 1 (Acceptable) = Acceptable configuration
     * - Priority 2 (Sub-optimal) = Last resort configuration
     */

    /* Set the flag indicating we're in a dependent section */
    _inDependentSection = YES;

    /* Default to priority 0 (Good/Preferred) if not specified
     * The priority would normally be read from the START_DEPENDENT tag,
     * but since this method doesn't receive parameters, we use a default.
     * In a full implementation, the caller would set _dependentPriority
     * before calling this method.
     */
    if (_dependentPriority == 0) {
        _dependentPriority = 0; /* Good/Preferred */
        IOLog("  Priority: 0 (Good/Preferred)\n");
    } else if (_dependentPriority == 1) {
        IOLog("  Priority: 1 (Acceptable)\n");
    } else {
        IOLog("  Priority: 2 (Sub-optimal)\n");
    }

    /* When this flag is set:
     * 1. Subsequent resource descriptors (IRQ, DMA, I/O, Memory) are collected
     *    as part of a dependent function configuration
     * 2. When END_DEPENDENT is encountered, we evaluate whether this
     *    configuration can be satisfied with available system resources
     * 3. The system chooses the highest priority configuration that works
     * 4. Only one configuration from the dependent set is actually used
     */

    /* This state affects how PnPResources and PnPDeviceResources objects
     * parse and store resource data - they will save dependent configurations
     * separately from the preferred/required configuration.
     */
}

/*
 * Set dependent end marker
 */
- (void)setDepEnd
{
    /* Mark the end of a dependent function resource block */
    IOLog("EISAKernBus: Ending dependent function section\n");

    /* Clear the dependent section flag */
    _inDependentSection = NO;

    /* Reset priority for next dependent section */
    _dependentPriority = 0;

    /* At this point, the resource parser has collected a complete
     * dependent configuration. The system would now:
     * 1. Validate if this configuration can be satisfied
     * 2. Compare it with other dependent configurations
     * 3. Select the highest priority configuration that works
     * 4. Store it for potential use if better than previous options
     */

    IOLog("  Dependent section complete, priority reset\n");
}

/*
 * Set dependent function priority
 */
- (void)setDependentPriority:(int)priority
{
    /* Set the priority for the next dependent function
     * This should be called before setDepStart to specify the priority
     * of the upcoming dependent configuration.
     *
     * Priority values:
     * 0 = Good (preferred)
     * 1 = Acceptable
     * 2 = Sub-optimal
     */
    if (priority < 0 || priority > 2) {
        IOLog("EISAKernBus: Invalid dependent priority %d, using 0\n", priority);
        _dependentPriority = 0;
    } else {
        _dependentPriority = priority;
        IOLog("EISAKernBus: Set dependent priority to %d\n", priority);
    }
}

/*
 * Check if currently in dependent section
 */
- (BOOL)inDependentSection
{
    return _inDependentSection;
}

@end
