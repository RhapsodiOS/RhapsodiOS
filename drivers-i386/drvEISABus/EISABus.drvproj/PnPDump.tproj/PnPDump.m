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
 * PnPDump.m
 * Plug and Play Device Dump Utility
 *
 * This tool enumerates and displays Plug and Play device configurations
 * for both EISA and ISA PnP devices.
 */

#import <objc/Object.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import "PnPDeviceResources.h"

/* EISA I/O Ports */
#define EISA_ID_PORT_BASE       0x0C80
#define EISA_CONFIG_PORT_BASE   0x0C84
#define EISA_MAX_SLOTS          16

/* PnP I/O Ports */
#define PNP_ADDRESS_PORT    0x279
#define PNP_WRITE_DATA_PORT 0xA79
#define PNP_READ_PORT       0x203

/* PnP Configuration Registers */
#define PNP_SET_RD_DATA_PORT    0x00
#define PNP_SERIAL_ISOLATION    0x01
#define PNP_CONFIG_CONTROL      0x02
#define PNP_WAKE_CSN            0x03
#define PNP_RESOURCE_DATA       0x04
#define PNP_STATUS              0x05
#define PNP_CARD_SELECT_NUM     0x06
#define PNP_LOGICAL_DEVICE_NUM  0x07

/* PnP Commands */
#define PNP_WAIT_FOR_KEY        0x02
#define PNP_RESET_CSN           0x04

/* Global variables */
static unsigned char gReadPort = PNP_READ_PORT >> 2;
static int gVerbose = 0;
static int gShowEISA = 1;
static int gShowISAPnP = 1;

/*
 * Low-level I/O functions (would normally use kernel I/O functions)
 */
static inline void outb(unsigned short port, unsigned char val)
{
    __asm__ volatile("outb %0, %1" : : "a"(val), "Nd"(port));
}

static inline unsigned char inb(unsigned short port)
{
    unsigned char val;
    __asm__ volatile("inb %1, %0" : "=a"(val) : "Nd"(port));
    return val;
}

static void delay(int microseconds)
{
    volatile int i;
    for (i = 0; i < microseconds * 10; i++) {
        inb(0x80);  /* I/O delay */
    }
}

/*
 * PnP ID Decoding
 */

static void decodePnPID(unsigned int id, char *buffer, int bufsize)
{
    /* PnP EISA ID format:
     * Bits 31-26: First character (A-Z)
     * Bits 25-21: Second character (A-Z)
     * Bits 20-16: Third character (A-Z)
     * Bits 15-0: Product ID (hex)
     */
    unsigned char byte0 = (id >> 24) & 0xFF;
    unsigned char byte1 = (id >> 16) & 0xFF;
    unsigned char byte2 = (id >> 8) & 0xFF;
    unsigned char byte3 = id & 0xFF;

    char c1 = ((byte0 >> 2) & 0x1F) + 'A' - 1;
    char c2 = (((byte0 & 0x03) << 3) | ((byte1 >> 5) & 0x07)) + 'A' - 1;
    char c3 = (byte1 & 0x1F) + 'A' - 1;
    unsigned short prodId = (byte3 << 8) | byte2;

    snprintf(buffer, bufsize, "%c%c%c%04X", c1, c2, c3, prodId);
}

/*
 * EISA Bus Enumeration
 */

static int enumerateEISADevices(void)
{
    int slot;
    int deviceCount = 0;
    unsigned char id[4];
    unsigned char configData[320];
    int i;

    printf("\n=== EISA Bus Devices ===\n\n");

    for (slot = 0; slot < EISA_MAX_SLOTS; slot++) {
        unsigned int idPort = EISA_ID_PORT_BASE + (slot * 0x1000);
        unsigned int configPort = EISA_CONFIG_PORT_BASE + (slot * 0x1000);

        /* Read 4-byte EISA ID */
        for (i = 0; i < 4; i++) {
            id[i] = inb(idPort + i);
        }

        /* Check if slot is empty (ID = 0xFF or 0x00) */
        if (id[0] == 0xFF || id[0] == 0x00) {
            continue;
        }

        /* Construct 32-bit EISA ID */
        unsigned int eisaID = (id[0] << 24) | (id[1] << 16) |
                              (id[2] << 8) | id[3];

        char idStr[16];
        decodePnPID(eisaID, idStr, sizeof(idStr));

        printf("EISA Slot %d:\n", slot);
        printf("  Device ID: %s (0x%08X)\n", idStr, eisaID);
        printf("  Raw ID bytes: %02X %02X %02X %02X\n",
               id[0], id[1], id[2], id[3]);

        /* Read EISA configuration data */
        for (i = 0; i < 320; i++) {
            configData[i] = inb(configPort + i);
        }

        /* Display configuration info */
        printf("  Revision: %d\n", configData[0x04]);
        printf("  Type/Config: 0x%02X\n", configData[0x05]);

        /* Parse I/O ports (offsets 0x08-0x1F, 7 entries max) */
        printf("  I/O Ports:\n");
        int ioCount = 0;
        for (i = 0; i < 7; i++) {
            unsigned int offset = 0x08 + (i * 2);
            unsigned int ioBase = (configData[offset] << 8) | configData[offset + 1];
            if (ioBase != 0 && ioBase != 0xFFFF) {
                printf("    Port %d: 0x%04X-0x%04X (16 bytes)\n",
                       ioCount++, ioBase, ioBase + 15);
            }
        }
        if (ioCount == 0) {
            printf("    (none)\n");
        }

        /* Parse IRQs */
        printf("  IRQs:\n");
        int irqCount = 0;
        if (configData[0x04] != 0 && configData[0x04] != 0xFF) {
            unsigned int irq = configData[0x04] & 0x0F;
            if (irq < 16) {
                printf("    IRQ %d\n", irq);
                irqCount++;
            }
        }
        if (configData[0x05] != 0 && configData[0x05] != 0xFF) {
            unsigned int irq = configData[0x05] & 0x0F;
            if (irq < 16) {
                printf("    IRQ %d\n", irq);
                irqCount++;
            }
        }
        if (irqCount == 0) {
            printf("    (none)\n");
        }

        /* Parse DMA channels */
        printf("  DMA Channels:\n");
        int dmaCount = 0;
        if (configData[0x06] != 0xFF && (configData[0x06] & 0x07) < 8) {
            printf("    DMA %d\n", configData[0x06] & 0x07);
            dmaCount++;
        }
        if (configData[0x07] != 0xFF && (configData[0x07] & 0x07) < 8) {
            printf("    DMA %d\n", configData[0x07] & 0x07);
            dmaCount++;
        }
        if (dmaCount == 0) {
            printf("    (none)\n");
        }

        if (gVerbose) {
            /* Dump raw configuration data */
            printf("  Raw Configuration Data:\n");
            for (i = 0; i < 320; i += 16) {
                printf("    %04X:", i);
                int j;
                for (j = 0; j < 16 && i + j < 320; j++) {
                    printf(" %02X", configData[i + j]);
                }
                printf("\n");
            }
        }

        printf("\n");
        deviceCount++;
    }

    if (deviceCount == 0) {
        printf("  No EISA devices found\n\n");
    }

    return deviceCount;
}

/*
 * PnP Protocol Functions
 */

static void pnpSendKey(void)
{
    static const unsigned char key[32] = {
        0x6a, 0xb5, 0xda, 0xed, 0xf6, 0xfb, 0x7d, 0xbe,
        0xdf, 0x6f, 0x37, 0x1b, 0x0d, 0x86, 0xc3, 0x61,
        0xb0, 0x58, 0x2c, 0x16, 0x8b, 0x45, 0xa2, 0xd1,
        0xe8, 0x74, 0x3a, 0x9d, 0xce, 0xe7, 0x73, 0x39
    };
    int i;

    /* Send initiation key */
    outb(PNP_ADDRESS_PORT, 0x00);
    outb(PNP_ADDRESS_PORT, 0x00);

    for (i = 0; i < 32; i++) {
        outb(PNP_ADDRESS_PORT, key[i]);
    }
}

static void pnpWaitForKey(void)
{
    outb(PNP_ADDRESS_PORT, PNP_CONFIG_CONTROL);
    outb(PNP_WRITE_DATA_PORT, PNP_WAIT_FOR_KEY);
}

static void pnpResetCSN(void)
{
    outb(PNP_ADDRESS_PORT, PNP_CONFIG_CONTROL);
    outb(PNP_WRITE_DATA_PORT, PNP_RESET_CSN);
}

static void pnpSetReadPort(unsigned char port)
{
    gReadPort = port;
    outb(PNP_ADDRESS_PORT, PNP_SET_RD_DATA_PORT);
    outb(PNP_WRITE_DATA_PORT, port);
}

static void pnpWriteAddress(unsigned char addr)
{
    outb(PNP_ADDRESS_PORT, addr);
}

static void pnpWriteData(unsigned char data)
{
    outb(PNP_WRITE_DATA_PORT, data);
}

static unsigned char pnpReadData(void)
{
    return inb(gReadPort << 2);
}

static void pnpWakeCSN(unsigned char csn)
{
    pnpWriteAddress(PNP_WAKE_CSN);
    pnpWriteData(csn);
}

static void pnpSelectLogicalDevice(unsigned char ldn)
{
    pnpWriteAddress(PNP_LOGICAL_DEVICE_NUM);
    pnpWriteData(ldn);
}

/*
 * PnP Isolation Protocol
 */

static int pnpIsolationProtocol(unsigned char *deviceId, unsigned int *serialNumber)
{
    int i, j;
    unsigned char checksum = 0x6a;
    unsigned char bit, byte;

    /* Start isolation */
    pnpWriteAddress(PNP_SERIAL_ISOLATION);

    /* Read 72 bits: 9 bytes (device ID + vendor ID + checksum) */
    for (i = 0; i < 9; i++) {
        byte = 0;
        for (j = 0; j < 8; j++) {
            /* Read bit pair */
            bit = pnpReadData();

            /* Delay */
            delay(250);

            if (bit == 0x55) {
                /* Both bits set - conflict or end of isolation */
                return 0;
            }

            byte >>= 1;
            if (bit & 0x01) {
                byte |= 0x80;
            }
        }

        if (i < 8) {
            if (i < 4) {
                ((unsigned char *)deviceId)[i] = byte;
            } else {
                ((unsigned char *)serialNumber)[i - 4] = byte;
            }
            checksum = (checksum >> 1) | ((checksum ^ byte) << 7);
        } else {
            /* Verify checksum */
            if (checksum != byte) {
                if (gVerbose) {
                    printf("    Checksum error: expected 0x%02X, got 0x%02X\n",
                           checksum, byte);
                }
                return 0;
            }
        }
    }

    return 1;
}

/*
 * ISA PnP Device Enumeration
 */

static int enumerateISAPnPDevices(void)
{
    int csn = 1;
    int deviceCount = 0;
    unsigned char deviceId[4];
    unsigned int serialNumber;
    unsigned char resourceData[4096];
    int resourceLen;

    printf("\n=== ISA Plug and Play Devices ===\n\n");

    /* Initialize PnP */
    pnpSendKey();
    pnpResetCSN();
    delay(2000);
    pnpSendKey();
    pnpSetReadPort(PNP_READ_PORT >> 2);

    /* Enumerate devices */
    while (csn <= 255) {
        memset(deviceId, 0, sizeof(deviceId));
        serialNumber = 0;

        /* Try isolation */
        if (!pnpIsolationProtocol(deviceId, &serialNumber)) {
            break;
        }

        /* Assign CSN */
        pnpWriteAddress(PNP_CARD_SELECT_NUM);
        pnpWriteData(csn);

        unsigned int pnpID = *(unsigned int *)deviceId;
        char idStr[16];
        decodePnPID(pnpID, idStr, sizeof(idStr));

        printf("ISA PnP Card %d (CSN=%d):\n", deviceCount + 1, csn);
        printf("  Device ID: %s (0x%08X)\n", idStr, pnpID);
        printf("  Serial Number: 0x%08X\n", serialNumber);
        printf("  Raw ID bytes: %02X %02X %02X %02X\n",
               deviceId[0], deviceId[1], deviceId[2], deviceId[3]);

        /* Wake up the card and read resource data */
        pnpWakeCSN(csn);
        pnpSelectLogicalDevice(0);

        /* Read resource data */
        pnpWriteAddress(PNP_RESOURCE_DATA);

        resourceLen = 0;
        while (resourceLen < sizeof(resourceData)) {
            unsigned char tag = pnpReadData();
            resourceData[resourceLen++] = tag;

            /* Check for END tag */
            if ((tag & 0x78) == 0x78) {
                break;
            }

            /* Read tag data */
            if (tag & 0x80) {
                /* Large tag */
                if (resourceLen + 2 < sizeof(resourceData)) {
                    resourceData[resourceLen++] = pnpReadData();
                    resourceData[resourceLen++] = pnpReadData();
                    int len = resourceData[resourceLen-2] | (resourceData[resourceLen-1] << 8);

                    int i;
                    for (i = 0; i < len && resourceLen < sizeof(resourceData); i++) {
                        resourceData[resourceLen++] = pnpReadData();
                    }
                }
            } else {
                /* Small tag */
                int len = tag & 0x07;
                int i;
                for (i = 0; i < len && resourceLen < sizeof(resourceData); i++) {
                    resourceData[resourceLen++] = pnpReadData();
                }
            }
        }

        /* Parse and display resources */
        PnPDeviceResources *resources = [[PnPDeviceResources alloc] init];
        [resources setDeviceId:pnpID];
        [resources setSerialNumber:serialNumber];
        [resources parseResourceData:resourceData length:resourceLen];

        /* Display parsed resources */
        int i;
        PnPResourceData *res;

        printf("  Resources:\n");

        /* I/O Ports */
        int ioCount = [resources getIOPortCount];
        if (ioCount > 0) {
            printf("    I/O Ports:\n");
            for (i = 0; i < ioCount; i++) {
                res = [resources getIOPort:i];
                printf("      Port %d: 0x%04X-0x%04X (length=%d, decode=%s)\n",
                       i, res->ioBase, res->ioBase + res->ioLength - 1,
                       res->ioLength,
                       res->decode ? "16-bit" : "10-bit");
            }
        }

        /* IRQs */
        int irqCount = [resources getIRQCount];
        if (irqCount > 0) {
            printf("    IRQs:\n");
            for (i = 0; i < irqCount; i++) {
                res = [resources getIRQ:i];
                unsigned int irqMask = res->irqMask[0] | (res->irqMask[1] << 8);
                int irq;
                for (irq = 0; irq < 16; irq++) {
                    if (irqMask & (1 << irq)) {
                        printf("      IRQ %d (%s, %s)\n",
                               irq,
                               (res->info & 0x02) ? "level" : "edge",
                               (res->info & 0x01) ? "high" : "low");
                    }
                }
            }
        }

        /* DMA */
        int dmaCount = [resources getDMACount];
        if (dmaCount > 0) {
            printf("    DMA Channels:\n");
            for (i = 0; i < dmaCount; i++) {
                res = [resources getDMA:i];
                unsigned char dmaMask = res->dmaChannel;
                int dma;
                for (dma = 0; dma < 8; dma++) {
                    if (dmaMask & (1 << dma)) {
                        printf("      DMA %d (type=0x%02X)\n", dma, res->info);
                    }
                }
            }
        }

        /* Memory */
        int memCount = [resources getMemoryRangeCount];
        if (memCount > 0) {
            printf("    Memory Ranges:\n");
            for (i = 0; i < memCount; i++) {
                res = [resources getMemoryRange:i];
                printf("      Memory %d: 0x%08X-0x%08X (length=0x%X)\n",
                       i, res->memBase, res->memBase + res->memLength - 1,
                       res->memLength);
            }
        }

        if (gVerbose && resourceLen > 0) {
            /* Dump raw resource data */
            printf("  Raw Resource Data (%d bytes):\n", resourceLen);
            for (i = 0; i < resourceLen; i += 16) {
                printf("    %04X:", i);
                int j;
                for (j = 0; j < 16 && i + j < resourceLen; j++) {
                    printf(" %02X", resourceData[i + j]);
                }
                printf("\n");
            }
        }

        [resources free];

        printf("\n");
        deviceCount++;
        csn++;

        /* Move to next isolation */
        pnpWaitForKey();
        pnpSendKey();
    }

    if (deviceCount == 0) {
        printf("  No ISA PnP devices found\n\n");
    }

    /* Return all cards to Wait For Key state */
    pnpWaitForKey();

    return deviceCount;
}

/*
 * Main entry point
 */

int main(int argc, char *argv[])
{
    int eisaCount = 0;
    int pnpCount = 0;
    int i;

    /* Parse arguments */
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--verbose") == 0) {
            gVerbose = 1;
        } else if (strcmp(argv[i], "-e") == 0 || strcmp(argv[i], "--eisa-only") == 0) {
            gShowEISA = 1;
            gShowISAPnP = 0;
        } else if (strcmp(argv[i], "-p") == 0 || strcmp(argv[i], "--pnp-only") == 0) {
            gShowEISA = 0;
            gShowISAPnP = 1;
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            printf("PnPDump - EISA and ISA Plug and Play Device Enumeration Tool\n\n");
            printf("Usage: %s [options]\n\n", argv[0]);
            printf("Options:\n");
            printf("  -v, --verbose     Enable verbose output (show raw data)\n");
            printf("  -e, --eisa-only   Show only EISA devices\n");
            printf("  -p, --pnp-only    Show only ISA PnP devices\n");
            printf("  -h, --help        Display this help message\n\n");
            printf("This tool requires root privileges to access I/O ports.\n\n");
            return 0;
        }
    }

    printf("======================================\n");
    printf("   PnPDump - Device Enumeration Tool\n");
    printf("======================================\n");

    /* Enumerate EISA devices */
    if (gShowEISA) {
        eisaCount = enumerateEISADevices();
    }

    /* Enumerate ISA PnP devices */
    if (gShowISAPnP) {
        pnpCount = enumerateISAPnPDevices();
    }

    /* Summary */
    printf("======================================\n");
    printf("Summary:\n");
    if (gShowEISA) {
        printf("  EISA devices found: %d\n", eisaCount);
    }
    if (gShowISAPnP) {
        printf("  ISA PnP devices found: %d\n", pnpCount);
    }
    printf("  Total devices: %d\n", eisaCount + pnpCount);
    printf("======================================\n");

    return 0;
}
