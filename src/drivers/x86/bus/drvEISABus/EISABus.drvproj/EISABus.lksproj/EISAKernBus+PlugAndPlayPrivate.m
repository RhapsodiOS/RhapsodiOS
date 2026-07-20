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
#import "PnPResource.h"
#import "PnPDependentResources.h"
#import "pnpMemory.h"
#import "pnpIOPort.h"
#import "pnpIRQ.h"
#import "pnpDMA.h"
#import "bios.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/ioPorts.h>
#import <driverkit/KernDeviceDescription.h>
#import <driverkit/IODeviceDescription.h>
#import <libkern/libkern.h>
#import <objc/HashTable.h>
#import <objc/List.h>
#import <stdio.h>
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
BOOL getCardConfig(unsigned int csn, void *buffer, unsigned int *length);
BOOL getDeviceCfg(unsigned char csn, int logicalDevice, void *buffer, unsigned int *size);

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

/**
 * Send the ISAPnP initiation key.
 *
 * Sending the key causes all ISAPnP cards that are currently in the
 * Wait for Key state to transition into the Sleep state.
 *
 */
static void pnp_send_key(void)
{
    unsigned char lfsr;
    int i;

    /* Sleep 1ms to allow card to wake up */
    IODelay(1000);

    /* Two writes of 0x00 to address port */
    pnp_write_address ( 0x00 );
	pnp_write_address ( 0x00 );

    /* Send 32-byte initiation key using LFSR */
    lfsr = PNP_LFSR_SEED;
    for (i = 0; i < 32; i++) {
        pnp_write_address ( lfsr );
        lfsr = pnp_lfsr_next(lfsr, 0);
    }
}

/**
 * Compute PnP identifier checksum
 */
static unsigned char pnp_checksum(unsigned char *data)
{
	int i, j;
	unsigned char checksum = PNP_LFSR_SEED;
	unsigned char byte, bit;

	for (i = 0; i < 8; i++) {
        byte = data[i];
        for (j = 0; j < 8; j++) {
            bit = (byte >> j) & 0x01;
            checksum = (checksum >> 1) | 
                       (((checksum ^ (checksum >> 1) ^ bit) & 0x01) << 7);
        }
    }
    return checksum;
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
    id deviceList;

    /* Send PnP initiation key */
    pnp_send_key();

    /* Get Card Select Number from device */
    csn = [device csn];

    /* Wake card with CSN (register 0x03) */
    pnp_wake(csn);

    /* Get device list count */
    deviceList = [device deviceList];
    deviceCount = [deviceList count];

    /* Deactivate each logical device */
    for (i = 0; i < deviceCount; i++) {
        /* Select logical device number (register 0x07) */
        pnp_logicaldevice(i);

        /* Deactivate device (register 0x30, write 0) */
        pnp_write_byte(PNP_ACTIVATE, 0);

        /* Clear all PnP configuration registers for this device */
        clearPnPConfigRegisters();
    }

    /* Wait for Key (register 0x02, value 0x02) */
    pnp_wait_for_key();
}

/**
 * Try isolating PnP cards at the current read port.
 *
 * @ret \>0		Number of PnP cards found
 * @ret 0		There are no PnP cards in the system
 * @ret \<0		A conflict was detected; try a new read port
 *
 * The state diagram on page 18 (PDF page 24) of the PnP ISA spec
 * gives the best overview of what happens here.
 *
 */
static int pnp_try_isolate ( void ) {
	struct pnp_identifier identifier;
	unsigned int i, j;
	unsigned int seen_55aa, seen_life;
	unsigned int csn = 0;
	unsigned short data;
	unsigned char byte;
    int s;

	IOLog( "PnP: attempting isolation at read port 0x%x\n", pnpReadPort );

    /* BLOCK INTERRUPTS */
    s = splhigh();

	/* Global Reset Sequence */
    pnp_send_key(); 
    pnp_reset_all_cards();
    IODelay(2000); /* 2ms wait */

    /* Wait for Key State */
    pnp_send_key();
    pnp_wait_for_key();
    IODelay(2000);

    /* CSN Reset (Preps for isolation) */
    pnp_send_key();
    pnp_reset_csn();
    IODelay(2000);   

	/* Wake Cards */
    pnp_send_key(); /* Send Key AGAIN (Redundancy for slow cards) */
    pnp_wake(0x00);
	
	/* Set Read Port */
    pnp_set_read_port();
    IODelay(2000); /* Wait 2ms for bus to settle */

	while ( 1 ) {

		/* Initiate serial isolation */
		pnp_serialisolation ();
		IODelay(1000);

		/* Read identifier serially via the PnP read port. */
		memset ( &identifier, 0, sizeof ( identifier ) );
		seen_55aa = seen_life = 0;

        /* Read 9 Bytes (8 ID + 1 Checksum) */
		for ( i = 0 ; i < 9 ; i++ ) {
			byte = 0;
			for ( j = 0 ; j < 8 ; j++ ) {
                /* Read 0x55 / 0xAA pair */
				data = pnp_read_data ();
				IODelay(250);
				data = ( data << 8 ) | pnp_read_data ();
				IODelay(250);

				if (  data != 0xffff ) {
					seen_life++;
					if ( data == 0x55aa ) {
						byte |= (1 << j);
						seen_55aa++;
					}
				}
			}
			( (char *) &identifier )[i] = byte;
		}

        /* Did we see any valid PnP headers? */
        if ( ! seen_55aa ) {
            if ( csn == 0 && seen_life ) {
                /* Noisy bus (Legacy conflict), skip this read port */
                csn = -1; 
            }
            break;
        }

		/* If the checksum was invalid stop here */
		if ( identifier.checksum != pnp_checksum((unsigned char *)&identifier) ) {
			IOLog("PnP: Checksum Failed on Port 0x%x. ID: %02x %02x %02x...\n", 
                  pnpReadPort, ((char*)&identifier)[0], ((char*)&identifier)[1], ((char*)&identifier)[2]);        
			csn = -1;
			break;
		}

		/* Give the device a CSN */
		csn++;
		IOLog( "PnP: found card %s, assigning CSN %hhx\n", pnp_id_string ( identifier.vendor_id, identifier.prod_id ), csn );
    
		pnp_write_csn ( csn );
		IODelay(1000);

		/* Send this card back to Sleep and force all cards
		 * without a CSN into Isolation state
		 */
		pnp_wake ( 0x00 );
		IODelay(1000);
	}

	/* Place all cards in Wait for Key state */
	pnp_wait_for_key();

    /* Restore Interrupts */
    splx(s);

	return csn;
}

/*
 * Initialize PnP without BIOS support
 * Performs manual ISA PnP card enumeration
 */
- (BOOL)initializeNoBIOS
{
    IOLog("PnP: initializeNoBIOS - starting manual PnP enumeration\n");

    /* Initialize card count */
    maxPnPCard = 0;

    /* Try to isolate cards with different read ports */
    for ( pnpReadPort = PNP_READ_PORT_MIN ;
        pnpReadPort <= PNP_READ_PORT_MAX ;
        pnpReadPort += PNP_READ_PORT_STEP ) {
        int cardsFound;
        
        /* Avoid problematic locations such as the NE2000
         * probe space
         */
        if ( ( pnpReadPort >= 0x280 ) && ( pnpReadPort <= 0x380 ) )
            continue;

        /* Try to isolate cards at this read port */
        cardsFound = pnp_try_isolate();
        
        /* Accumulate card count (ignore negative values which indicate conflicts) */
        if ( cardsFound > 0 ) {
            maxPnPCard += cardsFound;
        }
    }

    /* log the result of the enumeration */
    if (maxPnPCard == 0) {
        IOLog("PnP: No PnP cards found during auto-scan\n");
    } else {
        IOLog("PnP: successfully enumerated %d card%s\n",
              maxPnPCard, (maxPnPCard == 1) ? "" : "s");
    }

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
    void *configData;
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

    IOLog("PnP: Initializing Plug and Play support\n");

    /* raynorpat: this is broken at the moment, so we'll just return the NoPnPBIOS case */
#if 0
    /* Try to initialize PnP BIOS */
    pnpBios = [[PnPBios alloc] init];
    if (pnpBios == nil) {
        IOLog("PnP: Plug and Play support not found\n");

        /* No BIOS support - fall back to manual enumeration */
        result = [self initializeNoBIOS];
        if (result == NO) {
            return NO;
        }
    } else {      
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

            /* Fall back to manual enumeration (which does its own setup and returns) */
            result = [self initializeNoBIOS];
            return result;
        }

        /* BIOS call succeeded - extract configuration from result */
        maxPnPCard = *((unsigned char *)configData + 1);
        pnpReadPort = *((unsigned short *)configData + 1);

        IOLog("PnP: Plug and Play support enabled\n");
    }
#else
    result = [self initializeNoBIOS];
    if (result == NO) {
        return NO;
    }
#endif

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
- (id)allocateResources:(id)resources
                  Using:(id)depFunction
     DependentFunction:(id)function
           Description:(id)description
{
    KernDeviceDescription *desc = (KernDeviceDescription *)description;
    PnPResource *functionMemory, *functionPort;
    PnPResource *resourcesDMA, *resourcesIRQ;
    PnPResource *depFunctionMemory, *depFunctionPort;
    PnPResource *resourcesMemory, *resourcesPort;
    int resourcesMemoryCount, depFunctionMemoryCount, functionMemoryCount;
    int resourcesPortCount, depFunctionPortCount, functionPortCount;
    int resourcesIRQCount, resourcesDMACount;
    int memoryCount, portCount;
    void *memoryArray, *portArray, *irqArray, *dmaArray;
    int i;
    unsigned int base, length;
    id result;
    pnpMemory *memObj, *memLenObj;
    pnpIOPort *portObj, *portLenObj;

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
            memObj = [[resourcesMemory list] objectAt:i];
            base = [memObj min_base];

            /* Get length from depFunction, using function memory */
            memLenObj = [depFunctionMemory objectAt:i Using:functionMemory];
            length = [memLenObj length];

            /* Store base and length in array */
            ((unsigned int *)memoryArray)[i * 2] = base;
            ((unsigned int *)memoryArray)[i * 2 + 1] = length;
        }

        /* Allocate ranges in device description */
        result = [desc allocateRanges:memoryArray
                             numRanges:memoryCount
                                forKey:"Memory Maps"];
        if (result == nil) {
            IOLog("PnP: allocateRanges:numRanges:%d forKey:'%s' returns nil\n",
                  memoryCount, "Memory Maps");
            return nil;
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
            portObj = [[resourcesPort list] objectAt:i];
            base = [portObj min_base];

            /* Get length from depFunction, using function port */
            portLenObj = [depFunctionPort objectAt:i Using:functionPort];
            length = [portLenObj length];

            /* Store base and length in array (masked to 16 bits for ports) */
            ((unsigned int *)portArray)[i * 2] = base & 0xffff;
            ((unsigned int *)portArray)[i * 2 + 1] = length & 0xffff;
        }

        /* Allocate ranges in device description */
        result = [desc allocateRanges:portArray
                             numRanges:portCount
                                forKey:"I/O Ports"];
        if (result == nil) {
            IOLog("PnP: allocateRanges:numRanges:%d forKey:'%s' returns nil\n",
                  portCount, "I/O Ports");
            return nil;
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
            pnpIRQ *irqObj = [[resourcesIRQ list] objectAt:i];
            int *irqsPtr = [irqObj irqs];

            /* Dereference pointer to get IRQ value */
            ((unsigned int *)irqArray)[i] = *irqsPtr;
        }

        /* Allocate items in device description */
        result = [desc allocateItems:irqArray
                            numItems:resourcesIRQCount
                              forKey:"IRQ Levels"];
        if (result == nil) {
            IOLog("PnP: allocateItems:numItems:%d forKey:'%s' returns nil\n",
                  resourcesIRQCount, "IRQ Levels");
            return nil;
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
            pnpDMA *dmaObj = [[resourcesDMA list] objectAt:i];
            int *dmaChannelsPtr = [dmaObj dmaChannels];

            /* Dereference pointer to get DMA channel value */
            ((unsigned int *)dmaArray)[i] = *dmaChannelsPtr;
        }

        /* Allocate items in device description */
        result = [desc allocateItems:dmaArray
                            numItems:resourcesDMACount
                              forKey:"DMA Channels"];
        if (result == nil) {
            IOLog("PnP: allocateItems:numItems:%d forKey:'%s' returns nil\n",
                  resourcesDMACount, "DMA Channels");
            return nil;
        }

        IOFree(dmaArray, resourcesDMACount * 4);
    }

    /* Success - return the description object */
    return description;
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
- (id)pnpSetResourcesForDescription:(id)description
{
    const char *location;
    const char *p;
    const char *serverName;
    const char *instance;
    const char *autoDetectIDs;
    PnPDeviceResources *card;
    unsigned int cardID;
    unsigned int serialNum;
    unsigned int logicalDevice;
    PnPResources *resources;
    PnPLogicalDevice *logicalDeviceObj;
    const char *deviceName;
    const char *cardDeviceName;
    PnPDependentResources *depFunction;
    BOOL found;
    unsigned char csn;
    List *deviceList;
    KernDeviceDescription *desc = (KernDeviceDescription *)description;

    card = nil;
    cardID = 0;
    serialNum = 0;
    logicalDevice = 0;

    /* Get Location string from device description */
    location = [desc stringForKey:"Location"];
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
        instance = [desc stringForKey:"Instance"];
        if (instance != NULL) {
            int instanceNum = strtol(instance, NULL, 0);
            autoDetectIDs = [desc stringForKey:"Auto Detect IDs"];
            card = [self lookForPnPIDs:autoDetectIDs Instance:instanceNum LogicalDevice:&logicalDevice];
        }
    }

    /* If we still couldn't find the card, log error and fail */
    if (card == nil) {
        serverName = [desc stringForKey:"Server Name"];
        if (serverName == NULL) {
            serverName = "<unknown>";
        }
        location = [desc stringForKey:"Location"];
        instance = [desc stringForKey:"Instance"];
        IOLog("PnP: could not find card for driver '%s' location '%s' instance %s\n",
              serverName, location ? location : "", instance ? instance : "");
        return nil;
    }

    /* Create PnPResources object from device description */
    resources = [[PnPResources alloc] initFromDeviceDescription:desc];
    if (resources == nil) {
        IOLog("PnP: PnPResources initFromDeviceDescription failed\n");
        return nil;
    }

    /* Get the logical device object */
    deviceList = [card deviceList];
    logicalDeviceObj = [deviceList objectAt:logicalDevice];

    /* Get device name for logging */
    deviceName = (const char *)[logicalDeviceObj deviceName];
    if (deviceName == NULL) {
        deviceName = "";
    }
    cardDeviceName = (const char *)[card deviceName];
    IOLog("PnP: configuring %s %s\n", cardDeviceName ? cardDeviceName : "", deviceName);

    /* Find matching dependent function configuration */
    found = [logicalDeviceObj findMatchingDependentFunction:&depFunction
                                                   ForConfig:resources];
    if (!found) {
        IOLog("PnP: could not find a matching configuration for %s %s\n",
              cardDeviceName ? cardDeviceName : "", deviceName);

        /* Send Wait for Key */
        pnp_wait_for_key();

        [resources free];
        return nil;
    }

    /* ===== ISA PnP Programming Sequence ===== */

    pnp_send_key();

    /* Get Card Select Number */
    csn = [card csn];

    /* Wake card (register 0x03) */
    pnp_wake(csn);

    /* Select logical device (register 0x07) */
    pnp_logicaldevice(logicalDevice);

    /* Deactivate device (register 0x30 = 0) */
    pnp_write_byte(PNP_ACTIVATE, 0);

    /* Clear all PnP configuration registers */
    clearPnPConfigRegisters();

    /* Configure the device resources */
    [[logicalDeviceObj resources] configure:resources Using:depFunction];

    /* Set device control register (register 0x31 = 0) */
    pnp_write_byte(PNP_IORANGECHECK, 0);

    /* Activate device (register 0x30 = 1) */
    pnp_write_byte(PNP_ACTIVATE, 1);

    /* Send Wait for Key */
    pnp_wait_for_key();

    /* Free resources object */
    [resources free];

    return self;
}

/*
 * Read full card configuration data
 * Reads the PnP resource data from a card using ISA PnP protocol
 */
BOOL getCardConfig(unsigned int csn, void *buffer, unsigned int *length)
{
    unsigned char *bufPtr;
    unsigned int bytesRead;
    unsigned char regValue;

    if (csn == 0 || buffer == NULL || length == NULL) {
        return NO;
    }

    bufPtr = (unsigned char *)buffer;
    bytesRead = 0;

    /* Send PnP initiation sequence */
    pnp_send_key();

    /* Wake card with CSN (register 0x03) */
    pnp_wake(csn);

    /* Read resource data starting at register 0x04 */
    /* Resource data format: tags followed by data bytes */
    /* Read until we hit End tag (0x79) or buffer full */
    for (bytesRead = 0; bytesRead < *length; bytesRead++) {
        /* Read resource data register (0x04 + offset) */
        regValue = pnp_read_byte((unsigned char)(PNP_RESOURCEDATA + bytesRead));

        /* Store in buffer */
        bufPtr[bytesRead] = regValue;

        /*
        * Check for the PnP End Tag (0x79). If we see it, stop reading.
        */
        if (regValue == 0x79) {
            bytesRead++; // Include the end tag in the count
            break;
        }
    }

    /* Send Wait for Key */
    pnp_wait_for_key();

    /* Update length with actual bytes read */
    *length = bytesRead;

    return (bytesRead > 0) ? YES : NO;
}

/*
 * Read logical device configuration registers
 * Reads the current hardware configuration (0x4e bytes) for a logical device
 *
 * Based on decompiled code - reads configuration in specific register ranges:
 *   - I/O config: 0x40+ (20 bytes at offset 0x00)
 *   - Memory config: 0x76,0x80,0x90,0xA0 (36 bytes at offset 0x14)
 *   - I/O base addresses: 0x60+ (16 bytes at offset 0x38)
 *   - IRQ config: 0x70+ (4 bytes at offset 0x48)
 *   - DMA config: 0x74+ (2 bytes at offset 0x4c)
 */
BOOL getDeviceCfg(unsigned char csn, int logicalDevice, void *buffer, unsigned int *size)
{
    unsigned char *bufPtr;
    unsigned char regValue;
    unsigned char regBase;
    int i, j;

    /* Check buffer size - need at least 0x4e bytes */
    if (*size < 0x4e) {
        return NO;
    }

    bufPtr = (unsigned char *)buffer;

    /* === PnP Initialization Sequence === */

    /* Send initiation key sequence */
    pnp_send_key();

    /* Wake card with CSN (register 0x03) */
    pnp_wake(csn);

    /* Select logical device (register 0x07) */
    pnp_logicaldevice(logicalDevice);

    /* Update size to actual bytes read */
    *size = 0x4e;

    /* === Read Configuration Registers === */

    /* Read I/O configuration registers (0x40, 0x48, 0x50, 0x58) */
    /* 4 I/O ranges × 5 bytes each = 20 bytes at buffer offset 0 */
    regBase = 0x40;
    for (i = 0; i < 4; i++) {
        for (j = 0; j < 5; j++) {
            regValue = pnp_read_byte((unsigned char)(regBase + j));
            bufPtr[i * 5 + j] = regValue;
        }
        regBase += 8;  /* Next I/O range (0x40, 0x48, 0x50, 0x58) */
    }

    /* Read memory configuration registers (0x76, 0x80, 0x90, 0xA0) */
    /* 4 memory ranges × 9 bytes each = 36 bytes at buffer offset 0x14 (20) */
    for (i = 0; i < 4; i++) {
        /* Determine base register for this memory range */
        if (i == 1) {
            regBase = 0x80;
        } else if (i == 2) {
            regBase = 0x90;
        } else if (i == 3) {
            regBase = 0xA0;
        } else {
            regBase = 0x76;  /* i == 0 */
        }

        for (j = 0; j < 9; j++) {
            regValue = pnp_read_byte((unsigned char)(regBase + j));
            bufPtr[0x14 + i * 9 + j] = regValue;
        }
    }

    /* Read I/O base address registers (0x60-0x6F) */
    /* 8 I/O base addresses × 2 bytes each = 16 bytes at buffer offset 0x38 (56) */
    regBase = 0x60;
    for (i = 0; i < 8; i++) {
        for (j = 0; j < 2; j++) {
            regValue = pnp_read_byte((unsigned char)(regBase + j));
            bufPtr[0x38 + i * 2 + j] = regValue;
        }
        regBase += 2;
    }

    /* Read IRQ configuration registers (0x70, 0x72) */
    /* 2 IRQ settings × 2 bytes each = 4 bytes at buffer offset 0x48 (72) */
    regBase = 0x70;
    for (i = 0; i < 2; i++) {
        for (j = 0; j < 2; j++) {
            regValue = pnp_read_byte((unsigned char)(regBase + j));
            bufPtr[0x48 + i * 2 + j] = regValue;
        }
        regBase += 2;
    }

    /* Read DMA configuration registers (0x74, 0x75) */
    /* 2 DMA channels × 1 byte each = 2 bytes at buffer offset 0x4c (76) */
    regBase = 0x74;
    for (i = 0; i < 2; i++) {
        regValue = pnp_read_byte(regBase);
        bufPtr[0x4c + i] = regValue;
        regBase++;
    }

    /* Set default DMA values if both are 0 (disabled) */
    if (bufPtr[0x4c] == 0 && bufPtr[0x4d] == 0) {
        bufPtr[0x4c] = 4;  /* DMA channel 4 (cascade/disabled) */
        bufPtr[0x4d] = 4;
    }

    /* === Return to "Wait for Key" state === */
    pnp_wait_for_key();

    return YES;
}

@end
