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
 * PCMCIAKernBus Parsing Category Implementation
 */

#import "PCMCIAKernBusParsing.h"
#import "PCMCIATuple.h"
#import "PCMCIAConfigEntry.h"
#import <objc/List.h>
#import <driverkit/IODevice.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/generalFuncs.h>
#import <libkern/libkern.h>
#import <string.h>

/*
 * Global default configuration entry
 * Used as template when "default" flag is set in config entry
 */
static id _defaultConfigEntry = nil;

/*
 * Forward declarations for tuple parser functions
 */
static void _parse_VERS_1(int verbose, id description, void *data, unsigned int length);
static void _parse_CONFIG(int verbose, id description, void *data, unsigned int length);
static void _parse_CFTABLE_ENTRY(int verbose, id description, void *data, unsigned int length);
static void _parse_MANFID(int verbose, id description, void *data, unsigned int length);
static void _parse_FUNCID(int verbose, id description, void *data, unsigned int length);

/*
 * Helper function to add a single string to device description
 * Allocates memory for the string and adds it to description
 */
static void _addString(id description, char *string, const char *key)
{
    char *buffer;
    unsigned int length;
    char *ptr;

    /* Calculate string length (manual strlen) */
    length = 0xffffffff;
    ptr = string;
    while (length != 0) {
        length--;
        if (*ptr == '\0') {
            break;
        }
        ptr++;
    }

    /* Allocate buffer and copy string */
    buffer = (char *)IOMalloc(~length);
    strcpy(buffer, string);

    /* Add to description */
    [description setString:buffer forKey:key];
}

/*
 * Helper function to add formatted strings to device description
 * Formats and adds multiple values to the description
 */
static void _addStrings(id description, char *format, int base,
                       int *values, int count, const char **keys)
{
    char buffer[256];
    int i;

    for (i = 0; i < count; i++) {
        /* Format the value */
        sprintf(buffer, format, values[i]);

        /* Add to description */
        _addString(description, buffer, keys[i]);
    }
}

/*
 * Tuple parser dispatch table
 * Maps tuple codes to parser functions
 */
typedef struct {
    unsigned char code;
    void (*handler)(int verbose, id description, void *data, unsigned int length);
} TupleParserEntry;

static TupleParserEntry tupleParserTable[] = {
    { 0x15, _parse_VERS_1 },        /* VERS_1 - Version 1 product info */
    { 0x1A, _parse_CONFIG },         /* CONFIG - Configuration tuple */
    { 0x1B, _parse_CFTABLE_ENTRY },  /* CFTABLE_ENTRY - Config table entry */
    { 0x20, _parse_MANFID },         /* MANFID - Manufacturer identification */
    { 0x21, _parse_FUNCID },         /* FUNCID - Function identification */
    { 0x00, NULL }                   /* Terminator */
};

/*
 * Parse VERS_1 tuple (0x15)
 * Version 1 product information tuple
 */
static void _parse_VERS_1(int verbose, id description, void *data, unsigned int length)
{
    unsigned char *ptr = (unsigned char *)data;
    unsigned char *endPtr;
    unsigned char *strPtr;
    char *currentStr;
    const char *keys[2];
    unsigned int values[2];
    char c;

    keys[0] = "PCMCIA_TPLLV1_MAJOR";
    keys[1] = "PCMCIA_TPLLV1_MINOR";

    /* Skip tuple code and link */
    ptr += 2;

    /* Read major and minor version */
    values[0] = ptr[0];
    values[1] = ptr[1];

    if (verbose) {
        IOLog("Version 1 tuple\n");
        IOLog("Major version: %d, Minor version: %d\n", values[0], values[1]);
    }

    /* Add version numbers */
    _addStrings(description, "%d", 16, (int *)values, 2, keys);

    /* Calculate end pointer */
    endPtr = (unsigned char *)((int)data + length);

    /* Parse manufacturer string */
    currentStr = (char *)(ptr + 2);
    c = *currentStr;
    strPtr = (unsigned char *)currentStr;

    /* Scan to end of string */
    while (c != '\0') {
        if (endPtr <= strPtr || *strPtr == 0xFF) {
            if (*strPtr != '\0') goto skip_mfr;
            break;
        }
        strPtr++;
        c = *strPtr;
    }

    if (verbose) {
        IOLog("Manufacturer: %s\n", currentStr);
    }

    [description setString:currentStr forKey:"PCMCIA_TPLLV1_INFO_MFR"];

skip_mfr:
    /* Parse product string */
    strPtr++;
    currentStr = (char *)strPtr;
    c = *strPtr;

    while (c != '\0') {
        if (endPtr <= strPtr || *strPtr == 0xFF) {
            if (*strPtr != '\0') goto skip_prod;
            break;
        }
        strPtr++;
        c = *strPtr;
    }

    if (verbose) {
        IOLog("Product: %s\n", currentStr);
    }

    [description setString:currentStr forKey:"PCMCIA_TPLLV1_INFO_PROD"];

skip_prod:
    /* Parse additional info string 1 */
    strPtr++;
    currentStr = (char *)strPtr;
    c = *strPtr;

    while (c != '\0') {
        if (endPtr <= strPtr || *strPtr == 0xFF) {
            if (*strPtr != '\0') goto skip_addl1;
            break;
        }
        strPtr++;
        c = *strPtr;
    }

    if (verbose) {
        IOLog("Additional info 1: %s\n", currentStr);
    }

    [description setString:currentStr forKey:"PCMCIA_TPLLV1_INFO_ADDL_1"];

skip_addl1:
    /* Parse additional info string 2 */
    strPtr++;
    currentStr = (char *)strPtr;
    c = *strPtr;

    while (c != '\0') {
        if (endPtr <= strPtr || *strPtr == 0xFF) {
            if (*strPtr != '\0') return;
            break;
        }
        strPtr++;
        c = *strPtr;
    }

    if (verbose) {
        IOLog("Additional info 2: %s\n", currentStr);
    }

    [description setString:currentStr forKey:"PCMCIA_TPLLV1_INFO_ADDL_2"];
}

/*
 * Parse CONFIG tuple (0x1A)
 * Configuration tuple - defines configuration registers
 */
static void _parse_CONFIG(int verbose, id description, void *data, unsigned int length)
{
    unsigned char *ptr = (unsigned char *)data;
    unsigned char sizeByte;
    unsigned char *dataPtr;
    unsigned int radrSize, rmskSize;
    unsigned int registerAddress = 0;
    unsigned char registerMask[16];
    const char *key = "PCMCIA_TPCC_RADR";
    int i;

    if (verbose) {
        IOLog("Configuration tuple\n");
    }

    /* Skip tuple code and link */
    ptr += 2;

    /* Read TPCC_RASZ (size byte) */
    sizeByte = *ptr++;

    /* Skip TPCC_LAST (last config index) - at ptr[0] but not used here */
    dataPtr = ptr + 1;

    /* Calculate field sizes from size byte */
    radrSize = (sizeByte & 0x03) + 1;      /* Bits 0-1: RADR size - 1 */
    rmskSize = ((sizeByte >> 2) & 0x0f) + 1; /* Bits 2-5: RMSK size - 1 */

    /* Read TPCC_RADR (configuration register base address) */
    for (i = 0; i < radrSize && i < 4; i++) {
        registerAddress |= (*dataPtr++) << (i * 8);
    }

    if (verbose) {
        IOLog("Config register base address: 0x%x\n", registerAddress);
    }

    /* Read TPCC_RMSK (register presence mask) */
    bzero(registerMask, sizeof(registerMask));
    for (i = 0; i < rmskSize && i < 16; i++) {
        registerMask[i] = *dataPtr++;
    }

    if (verbose && rmskSize > 0) {
        IOLog("Register mask present (%d bytes)\n", rmskSize);
    }

    /* Add register address to device description */
    _addStrings(description, "%d", 10, &registerAddress, 1, &key);
}

/*
 * Parse CFTABLE_ENTRY tuple (0x1B)
 * Configuration table entry - describes one configuration option
 */
static void _parse_CFTABLE_ENTRY(int verbose, id description, void *data, unsigned int length)
{
    unsigned char *ptr = (unsigned char *)data;
    unsigned char indexByte, featureByte;
    id configEntry;
    id entryList;
    int i, j;

    if (verbose) {
        IOLog("Configuration table entry tuple\n");
    }

    /* Skip tuple code and link */
    ptr += 2;

    /* Parse index byte */
    indexByte = *ptr++;

    if (verbose) {
        IOLog("Index %d %s\n", indexByte & 0x3f,
              (indexByte & 0x40) ? "(default)" : "");
    }

    /* Create or copy config entry */
    if ((indexByte & 0x40) == 0 && _defaultConfigEntry != nil) {
        /* Copy from default */
        configEntry = [_defaultConfigEntry copy];
    } else {
        /* Allocate new entry */
        configEntry = [[PCMCIAConfigEntry alloc] init];
    }

    /* Save as default if flag set */
    if (indexByte & 0x40) {
        _defaultConfigEntry = configEntry;
    }

    /* Set config index */
    *(unsigned int *)((char *)configEntry + 0x04) = indexByte & 0x3f;

    /* Parse interface type if present */
    if (indexByte & 0x80) {
        unsigned char interfaceByte = *ptr++;
        if (verbose) {
            IOLog("Interface type: %d\n", interfaceByte & 0xf);
        }
        *(unsigned int *)((char *)configEntry + 0x08) = (indexByte >> 7);
    }

    /* Parse feature selection byte */
    featureByte = *ptr++;

    /* Parse power descriptors if present */
    if (featureByte & 0x03) {
        const char *powerNames[] = { "Vcc", "Vpp1", "Vpp2" };
        const char *paramNames[] = {
            "Nominal V", "Min V", "Max V", "Static I", "Avg I", "Peak I", "Power down I"
        };

        if (verbose) {
            IOLog("Power data present\n");
        }

        for (i = 0; i < (featureByte & 0x03); i++) {
            unsigned char paramSelect = *ptr++;

            if (verbose) {
                IOLog("  %s power entry\n", powerNames[i]);
            }

            /* Parse each parameter that's present */
            for (j = 0; j < 7; j++) {
                if (paramSelect & (1 << j)) {
                    if (verbose) {
                        IOLog("   %s parameter\n", paramNames[j]);
                    }
                    /* Skip parameter bytes (variable length with extension bit) */
                    while (*ptr & 0x80) {
                        ptr++;
                    }
                    ptr++;
                }
            }
        }
    }

    /* Parse timing descriptors if present */
    if (featureByte & 0x04) {
        unsigned char timingByte = *ptr++;

        if (verbose) {
            IOLog("Timing data present: (0x%02x) ", timingByte);
        }

        /* Wait timing */
        if ((timingByte & 0x03) != 0x03) {
            if (verbose) {
                IOLog("wait ");
            }
            while (*ptr & 0x80) {
                ptr++;
            }
            ptr++;
        }

        /* Ready timing */
        if ((timingByte & 0x1c) != 0x1c) {
            if (verbose) {
                IOLog("ready ");
            }
            while (*ptr & 0x80) {
                ptr++;
            }
            ptr++;
        }

        /* Reserved timing */
        if ((timingByte & 0xe0) != 0xe0) {
            if (verbose) {
                IOLog("reserved ");
            }
            while (*ptr & 0x80) {
                ptr++;
            }
            ptr++;
        }

        if (verbose) {
            IOLog("\n");
        }
    }

    /* Parse I/O descriptors if present */
    if (featureByte & 0x08) {
        unsigned char ioByte = *ptr++;

        if (verbose) {
            IOLog("I/O data present\n");
            IOLog("Address lines decoded: %d\n", ioByte & 0x1f);
            IOLog("8-bit xfers: %d  16-bit xfers: %d\n",
                  (ioByte >> 5) & 1, (ioByte >> 6) & 1);
        }

        *(unsigned int *)((char *)configEntry + 0x6c) = ioByte & 0x1f;
        *(unsigned char *)((char *)configEntry + 0x70) = (ioByte >> 5) & 1;
        *(unsigned char *)((char *)configEntry + 0x71) = (ioByte >> 6) & 1;

        /* Parse I/O ranges if present */
        if (ioByte & 0x80) {
            unsigned char rangeByte = *ptr++;
            int rangeCount = (rangeByte & 0x0f) + 1;
            int addrSize = (rangeByte >> 4) & 3;
            int lenSize = (rangeByte >> 6) & 3;

            if (addrSize == 3) addrSize = 4;
            if (lenSize == 3) lenSize = 4;

            *(int *)((char *)configEntry + 0x74) = rangeCount;

            for (i = 0; i < rangeCount; i++) {
                unsigned int addr = 0, len = 0;

                /* Read address */
                for (j = 0; j < addrSize; j++) {
                    addr |= (*ptr++) << (j * 8);
                }

                if (verbose) {
                    IOLog("I/O range start: 0x%x\n", addr);
                }

                /* Read length */
                for (j = 0; j < lenSize; j++) {
                    len |= (*ptr++) << (j * 8);
                }

                if (verbose) {
                    IOLog("I/O range length: 0x%x\n", len + 1);
                }

                *(unsigned int *)((char *)configEntry + 0x78 + i * 8) = addr;
                *(unsigned int *)((char *)configEntry + 0x7c + i * 8) = len + 1;
            }
        }
    }

    /* Parse IRQ descriptors if present */
    if (featureByte & 0x10) {
        unsigned char irqByte = *ptr++;

        if (verbose) {
            IOLog("IRQ data present\n");
            IOLog("Flags: %s %s %s\n",
                  (irqByte & 0x20) ? "level" : "",
                  (irqByte & 0x40) ? "pulse" : "",
                  (irqByte & 0x80) ? "share" : "");
        }

        *(unsigned char *)((char *)configEntry + 0xf8) = 1;
        *(unsigned char *)((char *)configEntry + 0xfb) = (irqByte >> 5) & 1;
        *(unsigned char *)((char *)configEntry + 0xfa) = (irqByte >> 6) & 1;
        *(unsigned char *)((char *)configEntry + 0xf9) = (irqByte >> 7);

        if (irqByte & 0x10) {
            /* IRQ mask present */
            unsigned int irqMask = *(unsigned short *)ptr;
            ptr += 2;

            *(unsigned int *)((char *)configEntry + 0x100) = irqMask;

            if (verbose) {
                IOLog("IRQs supported:\n");
                for (i = 0; i < 16; i++) {
                    if (irqMask & (1 << i)) {
                        IOLog("%d ", i);
                    }
                }
                IOLog("\n");
            }
        } else {
            /* Single IRQ */
            unsigned int irqNum = irqByte & 0x0f;

            if (verbose) {
                IOLog("IRQ supported: %d\n", irqNum);
            }

            *(unsigned int *)((char *)configEntry + 0x100) = 1 << irqNum;
        }
    }

    /* Parse memory descriptors if present */
    if (featureByte & 0x60) {
        unsigned char memType = (featureByte >> 5) & 3;

        if (verbose) {
            IOLog("Memory data present\n");
        }

        if (memType == 1) {
            /* Single length descriptor */
            unsigned short length = *(unsigned short *)ptr;
            ptr += 2;

            if (verbose) {
                IOLog("(single length)\nbase address 0x%x, length 0x%x\n",
                      0, length << 8);
            }

            *(unsigned int *)((char *)configEntry + 0x104) = 1;
            *(unsigned char *)((char *)configEntry + 0x114) = 1;
            *(unsigned int *)((char *)configEntry + 0x108) = 0;
            *(unsigned int *)((char *)configEntry + 0x10c) = length << 8;
            *(unsigned int *)((char *)configEntry + 0x110) = 0;

        } else if (memType == 2) {
            /* Length and address descriptor */
            unsigned short length = *(unsigned short *)ptr;
            unsigned short address = *(unsigned short *)(ptr + 2);
            ptr += 4;

            *(unsigned int *)((char *)configEntry + 0x104) = 1;
            *(unsigned char *)((char *)configEntry + 0x114) = 0;
            *(unsigned int *)((char *)configEntry + 0x110) = address << 8;
            *(unsigned int *)((char *)configEntry + 0x108) = address << 8;
            *(unsigned int *)((char *)configEntry + 0x10c) = length << 8;

            if (verbose) {
                IOLog("(single length and address)\nbase address 0x%x, length 0x%x\n",
                      address << 8, length << 8);
            }

        } else if (memType == 3) {
            /* Multiple descriptors */
            unsigned char descByte = *ptr++;
            int descCount = (descByte & 0x07) + 1;
            int lenBytes = (descByte >> 3) & 3;
            int addrBytes = (descByte >> 5) & 3;

            if (verbose) {
                IOLog("(%d descriptor(s), %d length byte(s) and %d addr byte(s))\n",
                      descCount, lenBytes, addrBytes);
            }

            *(unsigned int *)((char *)configEntry + 0x104) = descCount;

            for (i = 0; i < descCount; i++) {
                unsigned int len = 0, cardAddr = 0, hostAddr = 0;

                /* Read length */
                for (j = 0; j < lenBytes; j++) {
                    len |= (*ptr++) << (j * 8);
                }

                /* Read card address */
                for (j = 0; j < addrBytes; j++) {
                    cardAddr |= (*ptr++) << (j * 8);
                }

                *(unsigned int *)((char *)configEntry + 0x110 + i * 0x10) = cardAddr << 8;
                *(unsigned int *)((char *)configEntry + 0x10c + i * 0x10) = len << 8;

                if (verbose) {
                    IOLog("base address 0x%x, length 0x%x ", cardAddr << 8, len << 8);
                }

                /* Read host address if present */
                if (descByte & 0x80) {
                    for (j = 0; j < addrBytes; j++) {
                        hostAddr |= (*ptr++) << (j * 8);
                    }

                    *(unsigned int *)((char *)configEntry + 0x108 + i * 0x10) = hostAddr << 8;
                    *(unsigned char *)((char *)configEntry + 0x114 + i * 0x10) = 0;

                    if (verbose) {
                        IOLog("host address 0x%x", hostAddr << 8);
                    }
                } else {
                    *(unsigned int *)((char *)configEntry + 0x108 + i * 0x10) = 0;
                    *(unsigned char *)((char *)configEntry + 0x114 + i * 0x10) = 1;
                }

                if (verbose) {
                    IOLog("\n");
                }
            }
        } else {
            /* memType == 0 - no memory windows */
            *(unsigned int *)((char *)configEntry + 0x104) = 0;
        }
    }

    /* Parse miscellaneous features if present */
    if (featureByte & 0x80) {
        unsigned char miscByte = *ptr++;

        if (verbose) {
            IOLog("Misc data present\n");
            IOLog("max twins = %d\n", miscByte & 7);
            IOLog("Flags: %s %s %s\n",
                  (miscByte & 0x08) ? "audio" : "",
                  (miscByte & 0x10) ? "ronly" : "",
                  (miscByte & 0x20) ? "powerDown" : "");
        }

        /* Skip extension bytes */
        while (miscByte & 0x80) {
            ptr++;
            miscByte = *ptr;
        }
    }

    /* Get or create config entry list */
    entryList = [description resourcesForKey:"PCMCIA_TPCE_LIST"];
    if (entryList == nil) {
        entryList = [[List alloc] init];
        [description setResources:entryList forKey:"PCMCIA_TPCE_LIST"];
    }

    /* Add config entry to list */
    [entryList addObject:configEntry];
}

/*
 * Parse MANFID tuple (0x20)
 * Manufacturer identification tuple
 */
static void _parse_MANFID(int verbose, id description, void *data, unsigned int length)
{
    unsigned char *ptr = (unsigned char *)data;
    const char *keys[2];
    unsigned int values[2];

    keys[0] = "PCMCIA_TPLMID_MANF";
    keys[1] = "PCMCIA_TPLMID_CARD";

    /* Skip tuple code and link */
    ptr += 2;

    /* Read manufacturer code (16-bit, little-endian) */
    values[0] = *(unsigned short *)ptr;

    /* Read card ID (16-bit, little-endian) */
    values[1] = *(unsigned short *)(ptr + 2);

    if (verbose) {
        IOLog("Manufacturer ID tuple\n");
        IOLog("Manufacturer code: 0x%04x\n", values[0]);
        IOLog("Card ID: 0x%04x\n", values[1]);
    }

    /* Add both values as hex strings */
    _addStrings(description, "%04x", 16, (int *)values, 2, keys);
}

/*
 * Parse FUNCID tuple (0x21)
 * Function identification tuple
 */
static void _parse_FUNCID(int verbose, id description, void *data, unsigned int length)
{
    unsigned char *ptr = (unsigned char *)data;
    unsigned char functionCode;
    char buffer[16];

    /* Skip tuple code and link */
    ptr += 2;

    /* Read function code */
    functionCode = *ptr;

    if (verbose) {
        IOLog("Function ID tuple\n");
        IOLog("Function code: %d\n", functionCode);
    }

    /* Format as decimal string */
    sprintf(buffer, "%d", functionCode);

    /* Add to description */
    _addString(description, buffer, "PCMCIA_TPLFID_FUNCTION");
}

@implementation PCMCIAKernBus(Parsing)

/*
 * Allocate resources for description from tuple list
 */
- _allocResourcesForDescription:description fromTupleList:tupleList
{
    unsigned int count;
    unsigned int i;
    id tuple;

    /* Allocate base resources for device description */
    if ([self allocateResourcesForDeviceDescription:description] == nil) {
        return nil;
    }

    /* Parse each tuple in the list and extract resource information */
    count = [tupleList count];
    for (i = 0; i < count; i++) {
        tuple = [tupleList objectAt:i];
        [self _parseTuple:tuple intoDeviceDescription:description];
    }

    return description;
}

/*
 * Parse a single tuple into device description
 * Uses dispatch table to find appropriate parser
 */
- (void)_parseTuple:tuple intoDeviceDescription:description
{
    unsigned char code;
    TupleParserEntry *entry;
    unsigned int length;
    void *data;

    /* Get tuple code */
    code = [tuple code];

    /* Search dispatch table for matching handler */
    for (entry = tupleParserTable; entry->handler != NULL; entry++) {
        if (entry->code == code) {
            /* Found handler - get tuple data and call it */
            length = [tuple length];
            data = [tuple data];
            entry->handler(_verbose, description, data, length);
            return;
        }
    }

    /* No handler found - tuple type not supported */
}

@end
