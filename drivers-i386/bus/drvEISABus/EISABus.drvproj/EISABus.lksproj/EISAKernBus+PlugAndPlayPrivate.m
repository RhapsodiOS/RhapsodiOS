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
 * EISAKernBus+PlugAndPlayPrivate.m
 * Private PnP Methods Category Implementation
 */

#import "EISAKernBus+PlugAndPlay.h"
#import "EISAKernBus+PlugAndPlayPrivate.h"
#import "PnPBios.h"
#import "PnPDeviceResources.h"
#import "PnPLogicalDevice.h"
#import "PnPResources.h"
#import "bios.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/IODeviceDescription.h>
#import <libkern/libkern.h>
#import <objc/HashTable.h>
#import <string.h>

/* Global PnP device table and card count */
HashTable *pnpDeviceTable = NULL;
unsigned int maxPnPCard = 0;

/* Global PnP read port */
unsigned short pnpReadPort = 0;

/* Global PnP BIOS instance */
id pnpBios = nil;

/* External functions */
extern char *configTableLookupServerAttribute(const char *serverName, const char *attributeName);

/* Forward declarations */
static BOOL getCardConfig(unsigned int csn, void *buffer, unsigned int *length);
static BOOL getDeviceCfg(unsigned char csn, int logicalDevice, void *buffer, unsigned int *size);

@implementation EISAKernBus (PlugAndPlayPrivate)

/*
 * Find a PnP card with matching ID, serial number, and logical device
 * Searches through the PnP device table for a card matching the given criteria
 * Returns the matching card or nil if not found
 */
- findCardWithID:(unsigned int)cardID
          Serial:(unsigned int)serialNum
   LogicalDevice:(int)logicalDevice
{
    unsigned int cardNum;
    id card;
    unsigned int cardIDCheck;
    unsigned int serialCheck;
    id deviceList;
    unsigned int deviceCount;

    /* Start at card 1 */
    cardNum = 1;

    /* Check if we have any PnP cards */
    if (maxPnPCard == 0) {
        return nil;
    }

    /* Search through all PnP cards */
    do {
        /* Get card from device table by card number */
        card = [pnpDeviceTable valueForKey:(void *)cardNum];

        /* Check if ID matches */
        cardIDCheck = [card ID];
        if (cardID == cardIDCheck) {
            /* Check if serial number matches */
            serialCheck = [card serialNumber];
            if (serialNum == serialCheck) {
                /* Check if logical device number is within range */
                deviceList = [card deviceList];
                deviceCount = [deviceList count];

                if ((unsigned int)logicalDevice < deviceCount) {
                    /* Found matching card with valid logical device */
                    return card;
                }
            }
        }

        cardNum++;
    } while (cardNum <= maxPnPCard);

    /* Not found */
    return nil;
}

/*
 * Deactivate logical devices on a card
 * Disables all logical devices on the specified PnP card
 * Uses ISA PnP register programming sequence
 */
- (void)deactivateLogicalDevices:(id)device
{
    unsigned char csn;
    unsigned int deviceCount;
    unsigned int i;
    unsigned char lfsr;
    int j;
    id deviceList;

    /* ISA PnP Initiation Sequence */
    /* Send two consecutive writes of 0x00 to address port */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0xa79));

    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0x279));

    /* Send Initiation Key (32 writes using LFSR sequence) */
    /* Start with seed value 0x6a */
    lfsr = 0x6a;
    for (j = 0; j < 0x20; j++) {
        __asm__ volatile("outb %b0,%w1" : : "a"(lfsr), "d"(0x279));

        /* LFSR computation: next = (current >> 1) | ((current ^ (current & 2) >> 1) << 7) */
        lfsr = (lfsr >> 1) | (((lfsr ^ ((lfsr & 2) >> 1)) << 7) & 0x80);
    }

    /* Get Card Select Number from device */
    csn = [device csn];

    /* Wake card with CSN (register 0x03) */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)3), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"(csn), "d"(0xa79));

    /* Get device list count */
    deviceList = [device deviceList];
    deviceCount = [deviceList count];

    /* Deactivate each logical device */
    for (i = 0; i < deviceCount; i++) {
        /* Select logical device number (register 0x07) */
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)7), "d"(0x279));
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)i), "d"(0xa79));

        /* Deactivate device (register 0x30, write 0) */
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0x30), "d"(0x279));
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0xa79));

        /* Clear all PnP configuration registers for this device */
        clearPnPConfigRegisters();
    }

    /* Wait for Key (register 0x02, value 0x02) */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0xa79));
}

/*
 * Send ISA PnP initiation sequence with LFSR key
 */
static void sendPnPInitiationKey(void)
{
    unsigned char lfsr;
    int i;

    /* Reset sequence */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)4), "d"(0xa79));

    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0xa79));

    /* Two writes of 0x00 to address port */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0x279));

    /* Send 32-byte initiation key using LFSR */
    lfsr = 0x6a;
    for (i = 0; i < 0x20; i++) {
        __asm__ volatile("outb %b0,%w1" : : "a"(lfsr), "d"(0x279));
        lfsr = (lfsr >> 1) | (((lfsr ^ ((lfsr & 2) >> 1)) << 7) & 0x80);
    }
}

/*
 * Configure PnP read port and isolate cards
 */
static int isolateCardsWithReadPort(unsigned short readPort)
{
    int cardNum;
    BOOL result;

    /* Set config control (register 0x02 = 0x01) */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)1), "d"(0xa79));

    /* Sleep 5ms */
    IOSleep(5);

    /* Wake CSN 0 (all cards) */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)3), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0xa79));

    /* Set read port address (register 0x00, write port>>2) */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)(readPort >> 2)), "d"(0xa79));

    /* Isolate cards starting from CSN 1 */
    cardNum = 1;
    while (1) {
        result = isolateCard(cardNum);
        if (result != YES) {
            break;
        }
        cardNum++;
    }

    /* Return count of cards found (cardNum - 1) */
    if (cardNum > 1) {
        return cardNum - 1;
    }
    return 0;
}

/*
 * Initialize PnP without BIOS support
 * Performs manual ISA PnP card enumeration
 */
- (BOOL)initializeNoBIOS
{
    char *configPort;
    unsigned short readPort;
    int cardsFound;
    size_t strLen;
    char *p;

    /* Initialize card count */
    maxPnPCard = 0;

    /* Try to get PnP read port from config table */
    configPort = configTableLookupServerAttribute("EISABus", "PnP Read Port");

    if (configPort == NULL) {
        /* No config attribute - auto-scan for read port */
        /* Try read ports from 0x203 to 0x277 in steps of 4 */
        readPort = 0x203;

        do {
            /* Send PnP initiation sequence */
            sendPnPInitiationKey();

            /* Try to isolate cards with this read port */
            cardsFound = isolateCardsWithReadPort(readPort);

            maxPnPCard = cardsFound;

            /* If we found cards, we're done */
            if (cardsFound != 0) {
                pnpReadPort = readPort;
                break;
            }

            /* Try next read port */
            readPort += 4;
        } while (readPort < 0x278);
    }
    else {
        /* Use specified read port from config */
        readPort = (unsigned short)strtol(configPort, NULL, 0);
        pnpReadPort = readPort;

        /* Free the config string */
        strLen = 0;
        p = configPort;
        while (*p != '\0') {
            p++;
            strLen++;
        }
        IOFree(configPort, strLen + 1);

        /* Send PnP initiation sequence */
        sendPnPInitiationKey();

        /* Isolate cards with specified read port */
        cardsFound = isolateCardsWithReadPort(readPort);

        maxPnPCard = cardsFound;
    }

    /* Send Wait for Key to complete */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0xa79));

    /* Return YES if we found any cards */
    return (maxPnPCard != 0);
}

/*
 * Initialize PnP subsystem
 * Tries to use PnP BIOS if available, otherwise falls back to manual enumeration
 */
- (BOOL)initializePnP
{
    char *pnpConfig;
    char pnpEnabled;
    size_t strLen;
    char *p;
    int biosResult;
    int configData;
    void *configBuffer;
    unsigned int csn;
    unsigned int bufferSize;
    BOOL result;
    id deviceResources;
    unsigned int deviceID;
    unsigned int serialNum;
    char vendorStr[8];
    const char *errorStr;

    /* Error string table for BIOS error codes */
    static const char *biosErrors[] = {
        "SUCCESS",                          /* 0x00 */
        "not supported",                    /* 0x81 */
        "invalid function",                 /* 0x82 */
        "function not supported",           /* 0x83 */
        "invalid parameter",                /* 0x84 */
        "set failed",                       /* 0x85 */
        "events not supported",             /* 0x86 */
        "hardware error",                   /* 0x87 */
        "invalid CSN",                      /* 0x88 */
        "can't set CSN",                    /* 0x89 */
        "buffer too small",                 /* 0x8a */
        "no ISA PnP cards",                 /* 0x8b */
        "unable to determine dock status",  /* 0x8c */
        "config change failed (docked)",    /* 0x8d */
        "config change failed (too many)"   /* 0x8e */
    };

    /* Check if PnP is disabled in config table */
    pnpConfig = configTableLookupServerAttribute("EISABus", "PnP");
    if (pnpConfig != NULL) {
        pnpEnabled = *pnpConfig;

        /* Free the config string */
        strLen = 0;
        p = pnpConfig;
        while (*p != '\0') {
            p++;
            strLen++;
        }
        IOFree(pnpConfig, strLen + 1);

        /* Check if disabled */
        if ((pnpEnabled == 'n') || (pnpEnabled == 'N')) {
            IOLog("PnP: Plug and Play support disabled\n");
            return NO;
        }
    }

    IOLog("PnP: Plug and Play support enabled\n");

    /* Try to initialize PnP BIOS */
    pnpBios = [[PnPBios alloc] init];

    if (pnpBios == nil) {
        /* No BIOS support - fall back to manual enumeration */
        result = [self initializeNoBIOS];
        if (result == NO) {
            return NO;
        }
    }
    else {
        /* BIOS available - get PnP configuration */
        biosResult = [pnpBios getPnPConfig:&configData];

        if (biosResult != 0) {
            /* BIOS call failed */
            if ((biosResult >= 0x81) && (biosResult <= 0x8f)) {
                errorStr = biosErrors[biosResult - 0x81 + 1];
            }
            else {
                errorStr = "unknown error code";
            }

            IOLog("PnP: getPnPConfig returned 0x%x '%s'\n", biosResult, errorStr);
            [pnpBios free];
            pnpBios = nil;
            return NO;
        }

        /* Extract configuration from result */
        maxPnPCard = *((unsigned char *)&configData + 1);
        pnpReadPort = *((unsigned short *)&configData + 1);

        IOLog("PnP: Plug and Play BIOS present\n");
    }

    /* Log configuration */
    IOLog("PnP: read port 0x%x, max csn %d\n", pnpReadPort, maxPnPCard);

    if (maxPnPCard == 0) {
        return NO;
    }

    /* Set read port in PnPDeviceResources class */
    [PnPDeviceResources setReadPort:pnpReadPort];

    /* Create device table */
    pnpDeviceTable = [[HashTable alloc] initKeyDesc:"i"];

    /* Allocate buffer for card configuration (2048 bytes) */
    configBuffer = IOMalloc(0x800);
    if (configBuffer == NULL) {
        IOLog("PnP: IOMalloc PNP_CONFIG_BUFSIZE failed\n");
        return NO;
    }

    /* Enumerate all cards */
    for (csn = 1; csn <= maxPnPCard; csn++) {
        /* Get card configuration */
        bufferSize = 0x800;
        result = getCardConfig(csn, configBuffer, &bufferSize);

        if (result == NO) {
            IOLog("PnP: couldn't get card configuration for card %d\n", csn);
            continue;
        }

        /* Create PnPDeviceResources from configuration buffer */
        deviceResources = [[PnPDeviceResources alloc] initForBuf:configBuffer
                                                           Length:bufferSize
                                                              CSN:csn];
        if (deviceResources == nil) {
            IOLog("PnP: PnPDeviceResources:initForBuf:Length failed\n");
            IOFree(configBuffer, 0x800);
            return NO;
        }

        /* Get device ID and serial number */
        deviceID = [deviceResources ID];
        serialNum = [deviceResources serialNumber];

        /* Convert device ID to vendor string (3 letters + 4 hex digits) */
        vendorStr[0] = ((deviceID >> 26) & 0x1f) + 0x40;  /* Letter 1 */
        vendorStr[1] = ((deviceID >> 21) & 0x1f) + 0x40;  /* Letter 2 */
        vendorStr[2] = ((deviceID >> 16) & 0x1f) + 0x40;  /* Letter 3 */
        sprintf(&vendorStr[3], "%04x", deviceID & 0xffff); /* 4 hex digits */
        vendorStr[7] = '\0';

        /* Log device information */
        IOLog("PnP: csn %d: %s s/n 0x%08x\n", [deviceResources csn], vendorStr, serialNum);

        /* Add to device table */
        [pnpDeviceTable insertKey:(void *)csn value:deviceResources];

        /* Deactivate logical devices on this card */
        [self deactivateLogicalDevices:deviceResources];
    }

    /* Free configuration buffer */
    IOFree(configBuffer, 0x800);

    return YES;
}

/*
 * Get configuration for a specific card and logical device
 * Reads the hardware configuration registers for a specific logical device
 * and creates a PnPResources object representing the current configuration
 */
- getConfigForCard:(id)card LogicalDevice:(int)logicalDevice
{
    unsigned int size;
    void *buffer;
    BOOL success;
    id resources;
    unsigned char csn;

    /* Allocate buffer for logical device configuration (0x4e bytes) */
    size = 0x4e;
    buffer = IOMalloc(0x4e);
    if (buffer == NULL) {
        IOLog("PnP: failed to allocate ldev_p\n");
        return nil;
    }

    /* Get Card Select Number from card object */
    csn = [card csn];

    /* Read device configuration registers from hardware */
    success = getDeviceCfg(csn, logicalDevice, buffer, &size);
    if (!success) {
        IOLog("PnP: getDeviceCfg csn %d ldev %d failed\n", csn, logicalDevice);
        IOFree(buffer, 0x4e);
        return nil;
    }

    /* Create PnPResources object from register data */
    resources = [[PnPResources alloc] initFromRegisters:buffer];

    /* Free the temporary buffer */
    IOFree(buffer, size);

    return resources;
}

/*
 * Allocate resources for a device
 * Allocates memory, I/O port, IRQ, and DMA resources based on the
 * resource descriptors and adds them to the device description
 */
- (BOOL)allocateResources:(id)resources
                    Using:(id)depFunction
       DependentFunction:(id)function
             Description:(id)description
{
    id functionMemory, functionPort;
    id resourcesDMA, resourcesIRQ;
    id depFunctionMemory, depFunctionPort;
    id resourcesMemory, resourcesPort;
    int resourcesMemoryCount, depFunctionMemoryCount, functionMemoryCount;
    int resourcesPortCount, depFunctionPortCount, functionPortCount;
    int resourcesIRQCount, resourcesDMACount;
    int memoryCount, portCount;
    void *memoryArray, *portArray, *irqArray, *dmaArray;
    int i;
    id obj;
    unsigned int base, length;
    unsigned int *valuePtr;
    id result;

    /* Get resource objects from function parameter */
    functionMemory = [function memory];
    functionPort = [function port];

    /* Get resource objects from depFunction parameter */
    depFunctionMemory = [depFunction memory];
    depFunctionPort = [depFunction port];

    /* Get resource objects from resources parameter */
    resourcesMemory = [resources memory];
    resourcesPort = [resources port];
    resourcesDMA = [resources dma];
    resourcesIRQ = [resources irq];

    /* ===== Memory Resources ===== */
    /* Calculate counts for memory resources */
    resourcesMemoryCount = [[resourcesMemory list] count];
    depFunctionMemoryCount = [[depFunctionMemory list] count];
    functionMemoryCount = [[functionMemory list] count];

    /* Use minimum of resources count vs (depFunction + function) counts */
    memoryCount = resourcesMemoryCount;
    if ((functionMemoryCount + depFunctionMemoryCount) < resourcesMemoryCount) {
        memoryCount = functionMemoryCount + depFunctionMemoryCount;
    }

    /* Allocate memory ranges if needed */
    if (memoryCount > 0) {
        /* Allocate array of base/length pairs (8 bytes each) */
        memoryArray = IOMalloc(memoryCount * 8);

        /* Fill array with memory ranges */
        for (i = 0; i < memoryCount; i++) {
            /* Get min_base from resources memory list */
            obj = [[resourcesMemory list] objectAt:i];
            obj = [obj min_base];
            base = [obj unsignedIntValue];

            /* Get length from depFunction, using function memory */
            obj = [depFunctionMemory objectAt:i Using:functionMemory];
            obj = [obj length];
            length = [obj unsignedIntValue];

            /* Store base and length in array */
            ((unsigned int *)memoryArray)[i * 2] = base;
            ((unsigned int *)memoryArray)[i * 2 + 1] = length;
        }

        /* Allocate ranges in device description */
        result = [description allocateRanges:memoryArray
                                   numRanges:memoryCount
                                      forKey:"Memory Maps"];
        if (result == nil) {
            IOLog("PnP: allocateRanges:numRanges:%d forKey:'%s' returns nil\n",
                  memoryCount, "Memory Maps");
            return NO;
        }

        IOFree(memoryArray, memoryCount * 8);
    }

    /* ===== I/O Port Resources ===== */
    /* Calculate counts for port resources */
    resourcesPortCount = [[resourcesPort list] count];
    depFunctionPortCount = [[depFunctionPort list] count];
    functionPortCount = [[functionPort list] count];

    /* Use minimum of resources count vs (depFunction + function) counts */
    portCount = resourcesPortCount;
    if ((functionPortCount + depFunctionPortCount) < resourcesPortCount) {
        portCount = functionPortCount + depFunctionPortCount;
    }

    /* Allocate I/O port ranges if needed */
    if (portCount > 0) {
        /* Allocate array of base/length pairs (8 bytes each) */
        portArray = IOMalloc(portCount * 8);

        /* Fill array with port ranges */
        for (i = 0; i < portCount; i++) {
            /* Get min_base from resources port list */
            obj = [[resourcesPort list] objectAt:i];
            obj = [obj min_base];
            base = [obj unsignedIntValue];

            /* Get length from depFunction, using function port */
            obj = [depFunctionPort objectAt:i Using:functionPort];
            obj = [obj length];
            length = [obj unsignedIntValue];

            /* Store base and length in array (masked to 16 bits for ports) */
            ((unsigned int *)portArray)[i * 2] = base & 0xffff;
            ((unsigned int *)portArray)[i * 2 + 1] = length & 0xffff;
        }

        /* Allocate ranges in device description */
        result = [description allocateRanges:portArray
                                   numRanges:portCount
                                      forKey:"I/O Ports"];
        if (result == nil) {
            IOLog("PnP: allocateRanges:numRanges:%d forKey:'%s' returns nil\n",
                  portCount, "I/O Ports");
            return NO;
        }

        IOFree(portArray, portCount * 8);
    }

    /* ===== IRQ Resources ===== */
    resourcesIRQCount = [[resourcesIRQ list] count];
    if (resourcesIRQCount > 0) {
        /* Allocate array of IRQ values (4 bytes each) */
        irqArray = IOMalloc(resourcesIRQCount * 4);

        /* Fill array with IRQ numbers */
        for (i = 0; i < resourcesIRQCount; i++) {
            /* Get irqs pointer from resources IRQ list */
            obj = [[resourcesIRQ list] objectAt:i];
            obj = [obj irqs];
            valuePtr = (unsigned int *)[obj unsignedIntValue];

            /* Dereference pointer to get IRQ value */
            ((unsigned int *)irqArray)[i] = *valuePtr;
        }

        /* Allocate items in device description */
        result = [description allocateItems:irqArray
                                   numItems:resourcesIRQCount
                                     forKey:"IRQ Levels"];
        if (result == nil) {
            IOLog("PnP: allocateItems:numItems:%d forKey:'%s' returns nil\n",
                  resourcesIRQCount, "IRQ Levels");
            return NO;
        }

        IOFree(irqArray, resourcesIRQCount * 4);
    }

    /* ===== DMA Resources ===== */
    resourcesDMACount = [[resourcesDMA list] count];
    if (resourcesDMACount > 0) {
        /* Allocate array of DMA channel values (4 bytes each) */
        dmaArray = IOMalloc(resourcesDMACount * 4);

        /* Fill array with DMA channel numbers */
        for (i = 0; i < resourcesDMACount; i++) {
            /* Get dmaChannels pointer from resources DMA list */
            obj = [[resourcesDMA list] objectAt:i];
            obj = [obj dmaChannels];
            valuePtr = (unsigned int *)[obj unsignedIntValue];

            /* Dereference pointer to get DMA channel value */
            ((unsigned int *)dmaArray)[i] = *valuePtr;
        }

        /* Allocate items in device description */
        result = [description allocateItems:dmaArray
                                   numItems:resourcesDMACount
                                     forKey:"DMA Channels"];
        if (result == nil) {
            IOLog("PnP: allocateItems:numItems:%d forKey:'%s' returns nil\n",
                  resourcesDMACount, "DMA Channels");
            return NO;
        }

        IOFree(dmaArray, resourcesDMACount * 4);
    }

    /* Success - return the description object */
    return YES;
}

/*
 * Helper: Skip whitespace in string
 */
static const char *skipWhitespace(const char *str)
{
    while (*str == ' ' || *str == '\t' || *str == '\n' || *str == '\r') {
        str++;
    }
    return str;
}

/*
 * Helper: Parse PnP vendor ID from string (format: "ABC1234")
 * Returns vendor ID in standard PnP format, or 0 on error
 */
static unsigned int parseVendorID(const char *str, const char **endPtr)
{
    unsigned char c1, c2, c3;
    unsigned int vendorID;
    long hexValue;
    char *end;

    /* Check minimum length (7 characters: 3 letters + 4 hex digits) */
    if (strlen(str) < 7) {
        return 0;
    }

    /* Check that first 3 characters are uppercase letters (0x40-0x5f range) */
    c1 = str[0];
    c2 = str[1];
    c3 = str[2];

    if (((c1 & 0xc0) != 0x40) || ((c2 & 0xc0) != 0x40) || ((c3 & 0xc0) != 0x40)) {
        return 0;
    }

    /* Parse 4 hex digits after the letters */
    hexValue = strtol(str + 3, &end, 16);
    if (end != str + 7) {
        return 0;
    }

    /* Encode vendor ID: 3 letters (5 bits each) + 4 hex digits (16 bits) */
    vendorID = (((unsigned int)(c1 & 0x1f)) << 26) |
               (((unsigned int)(c2 & 0x1f)) << 21) |
               (((unsigned int)(c3 & 0x1f)) << 16) |
               ((unsigned int)hexValue & 0xffff);

    if (endPtr != NULL) {
        *endPtr = str + 7;
    }

    return vendorID;
}

/*
 * Set PnP resources from device description
 * Configures a PnP device based on information in the device description
 */
- (BOOL)pnpSetResourcesForDescription:(id)description
{
    const char *location;
    const char *p;
    const char *serverName;
    const char *instance;
    const char *autoDetectIDs;
    id card;
    unsigned int cardID;
    unsigned int serialNum;
    unsigned int logicalDevice;
    id resources;
    id logicalDeviceObj;
    const char *deviceName;
    const char *cardDeviceName;
    id depFunction;
    BOOL found;
    unsigned char csn;
    unsigned char lfsr;
    int i;

    card = nil;
    cardID = 0;
    serialNum = 0;
    logicalDevice = 0;

    /* Get Location string from device description */
    location = [description stringForKey:"Location"];
    if (location != NULL) {
        /* Parse Location string format: "Card: <id> Serial: <serial> Logical: <device>" */

        /* Skip leading whitespace */
        p = skipWhitespace(location);

        /* Look for "Card:" prefix */
        if (strncmp(p, "Card", 4) == 0 && p[4] == ':') {
            p += 5;  /* Skip "Card:" */
            p = skipWhitespace(p);

            /* Try to parse as number first */
            cardID = strtoul(p, (char **)&p, 0);

            /* If result is 0, try parsing as vendor ID (e.g., "ABC1234") */
            if (cardID == 0) {
                p = skipWhitespace(p);
                cardID = parseVendorID(p, &p);
            }

            if (p != NULL && cardID != 0) {
                /* Look for "Serial:" */
                p = skipWhitespace(p);
                if (strncmp(p, "Serial", 6) == 0 && p[6] == ':') {
                    p += 7;  /* Skip "Serial:" */
                    p = skipWhitespace(p);
                    serialNum = strtoul(p, (char **)&p, 0);

                    if (p != NULL) {
                        /* Look for "Logical:" */
                        p = skipWhitespace(p);
                        if (strncmp(p, "Logical", 7) == 0 && p[7] == ':') {
                            p += 8;  /* Skip "Logical:" */
                            p = skipWhitespace(p);
                            logicalDevice = strtoul(p, (char **)&p, 0);

                            if (p != NULL) {
                                /* Find the card */
                                card = [self findCardWithID:cardID
                                                     Serial:serialNum
                                              LogicalDevice:logicalDevice];
                            }
                        }
                    }
                }
            }
        }
    }

    /* If Location parsing failed, try alternative method */
    if (card == nil) {
        instance = [description stringForKey:"Instance"];
        if (instance != NULL) {
            int instanceNum = strtol(instance, NULL, 0);
            autoDetectIDs = [description stringForKey:"Auto Detect IDs"];
            card = [self lookForPnPIDs:autoDetectIDs Instance:instanceNum LogicalDevice:&logicalDevice];
        }
    }

    /* If we still couldn't find the card, log error and fail */
    if (card == nil) {
        serverName = [description stringForKey:"Server Name"];
        if (serverName == NULL) {
            serverName = "<unknown>";
        }
        location = [description stringForKey:"Location"];
        instance = [description stringForKey:"Instance"];
        IOLog("PnP: could not find card for driver '%s' location '%s' instance %s\n",
              serverName, location ? location : "", instance ? instance : "");
        return NO;
    }

    /* Create PnPResources object from device description */
    resources = [[PnPResources alloc] initFromDeviceDescription:description];
    if (resources == nil) {
        IOLog("PnP: PnPResources initFromDeviceDescription failed\n");
        return NO;
    }

    /* Get the logical device object */
    logicalDeviceObj = [[card deviceList] objectAt:logicalDevice];

    /* Get device name for logging */
    deviceName = [logicalDeviceObj deviceName];
    if (deviceName == NULL) {
        deviceName = "";
    }
    cardDeviceName = [card deviceName];
    IOLog("PnP: configuring %s %s\n", cardDeviceName ? cardDeviceName : "", deviceName);

    /* Find matching dependent function configuration */
    found = [logicalDeviceObj findMatchingDependentFunction:&depFunction
                                                        For:resources];
    if (!found) {
        IOLog("PnP: could not find a matching configuration for %s %s\n",
              cardDeviceName ? cardDeviceName : "", deviceName);

        /* Send Wait for Key */
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0x279));
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0xa79));

        [resources free];
        return NO;
    }

    /* ===== ISA PnP Programming Sequence ===== */

    /* Reset and Wait for Key */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0xa79));

    /* Two writes of 0x00 to address port */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0x279));

    /* Send 32-byte initiation key using LFSR */
    lfsr = 0x6a;
    for (i = 0; i < 0x20; i++) {
        __asm__ volatile("outb %b0,%w1" : : "a"(lfsr), "d"(0x279));
        lfsr = (lfsr >> 1) | (((lfsr ^ ((lfsr & 2) >> 1)) << 7) & 0x80);
    }

    /* Get Card Select Number */
    csn = [card csn];

    /* Wake card (register 0x03) */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)3), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"(csn), "d"(0xa79));

    /* Select logical device (register 0x07) */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)7), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)logicalDevice), "d"(0xa79));

    /* Deactivate device (register 0x30 = 0) */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0x30), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0xa79));

    /* Clear all PnP configuration registers */
    clearPnPConfigRegisters();

    /* Configure the device resources */
    [[logicalDeviceObj resources] configure:resources Using:depFunction];

    /* Set device control register (register 0x31 = 0) */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0x31), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0xa79));

    /* Activate device (register 0x30 = 1) */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0x30), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)1), "d"(0xa79));

    /* Send Wait for Key */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0xa79));

    /* Free resources object */
    [resources free];

    return YES;
}

/*
 * Read full card configuration data
 * Reads the PnP resource data from a card using ISA PnP protocol
 */
static BOOL getCardConfig(unsigned int csn, void *buffer, unsigned int *length)
{
    unsigned char *bufPtr;
    unsigned int bytesRead;
    unsigned char regValue;
    unsigned char lfsr;
    int i;

    if (csn == 0 || buffer == NULL || length == NULL) {
        return NO;
    }

    bufPtr = (unsigned char *)buffer;
    bytesRead = 0;

    /* Send PnP initiation sequence */
    /* Reset and Wait for Key */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0xa79));

    /* Two writes of 0x00 to address port */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0x279));

    /* Send 32-byte initiation key using LFSR */
    lfsr = 0x6a;
    for (i = 0; i < 0x20; i++) {
        __asm__ volatile("outb %b0,%w1" : : "a"(lfsr), "d"(0x279));
        lfsr = (lfsr >> 1) | (((lfsr ^ ((lfsr & 2) >> 1)) << 7) & 0x80);
    }

    /* Wake card with CSN (register 0x03) */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)3), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)csn), "d"(0xa79));

    /* Read resource data starting at register 0x04 */
    /* Resource data format: tags followed by data bytes */
    /* Read until we hit End tag (0x79) or buffer full */
    for (bytesRead = 0; bytesRead < *length; bytesRead++) {
        /* Select resource data register (0x04 + offset) */
        __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)(0x04 + bytesRead)), "d"(0x279));

        /* Read value from PnP read port */
        __asm__ volatile("inb %w1,%b0" : "=a"(regValue) : "d"(pnpReadPort));

        /* Store in buffer */
        bufPtr[bytesRead] = regValue;

        /* Check for End tag (small item tag 0x78-0x79) */
        if (bytesRead == 0 && (regValue == 0x79 || regValue == 0x78)) {
            bytesRead = 1;
            break;
        }
    }

    /* Send Wait for Key */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0xa79));

    /* Update length with actual bytes read */
    *length = bytesRead;

    return (bytesRead > 0) ? YES : NO;
}

/*
 * Read logical device configuration registers
 * Reads the current hardware configuration (0x4e bytes) for a logical device
 */
static BOOL getDeviceCfg(unsigned char csn, int logicalDevice, void *buffer, unsigned int *size)
{
    unsigned char *bufPtr;
    unsigned char regNum;
    unsigned char regValue;
    unsigned char lfsr;
    int i;

    if (csn == 0 || buffer == NULL || size == NULL) {
        return NO;
    }

    bufPtr = (unsigned char *)buffer;

    /* Send PnP initiation sequence */
    /* Reset and Wait for Key */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0xa79));

    /* Two writes of 0x00 to address port */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)0), "d"(0x279));

    /* Send 32-byte initiation key using LFSR */
    lfsr = 0x6a;
    for (i = 0; i < 0x20; i++) {
        __asm__ volatile("outb %b0,%w1" : : "a"(lfsr), "d"(0x279));
        lfsr = (lfsr >> 1) | (((lfsr ^ ((lfsr & 2) >> 1)) << 7) & 0x80);
    }

    /* Wake card with CSN (register 0x03) */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)3), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)csn), "d"(0xa79));

    /* Select logical device (register 0x07) */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)7), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)logicalDevice), "d"(0xa79));

    /* Read 0x4e bytes of configuration registers */
    /* Registers 0x30-0x7F (device configuration registers) */
    for (i = 0; i < 0x4e; i++) {
        regNum = 0x30 + i;

        /* Select register */
        __asm__ volatile("outb %b0,%w1" : : "a"(regNum), "d"(0x279));

        /* Read value from PnP read port */
        __asm__ volatile("inb %w1,%b0" : "=a"(regValue) : "d"(pnpReadPort));

        /* Store in buffer */
        bufPtr[i] = regValue;
    }

    /* Send Wait for Key */
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0x279));
    __asm__ volatile("outb %b0,%w1" : : "a"((unsigned char)2), "d"(0xa79));

    /* Update size */
    *size = 0x4e;

    return YES;
}

@end
