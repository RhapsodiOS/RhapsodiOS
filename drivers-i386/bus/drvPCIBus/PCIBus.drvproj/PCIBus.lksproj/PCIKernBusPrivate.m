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
 * PCIKernBusPrivate.m
 * PCIKernBus Private Category Implementation
 */

#import "PCIKernBusPrivate.h"
#import "pci.h"

#import <driverkit/i386/ioPorts.h>

/* PCI I/O Ports (Intel architecture) */
#define PCI_CONFIG_ADDRESS      0x0CF8
#define PCI_CONFIG_DATA         0x0CFC

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
    unsigned int testAddress;
    unsigned int verifyAddress;
    unsigned int dataValue;

    /* Test PCI Configuration Mechanism #1 */
    /* Try different device addresses to find a valid PCI device */
    testAddress = 0x80000000;

    while (testAddress <= 0x8000FFFF) {
        /* Write test address to CONFIG_ADDRESS */
        outl(PCI_CONFIG_ADDRESS, testAddress);

        /* Verify address was written correctly */
        verifyAddress = inl(PCI_CONFIG_ADDRESS);

        if (verifyAddress == testAddress) {
            /* Read from CONFIG_DATA */
            dataValue = inl(PCI_CONFIG_DATA);

            /* Check if we got a valid device (not 0xFFFFFFFF or 0x00000000) */
            if (dataValue != 0xFFFFFFFF && dataValue != 0x00000000) {
                /* Found a valid device - Mechanism #1 is present */
                outl(PCI_CONFIG_ADDRESS, 0);
                return YES;
            }
        }

        /* Try next device address (increment by 0x800) */
        testAddress += 0x800;
    }

    /* No valid devices found */
    outl(PCI_CONFIG_ADDRESS, 0);
    return NO;
}

/*
 * Test for PCI Configuration Mechanism #2
 */
- (BOOL)test_M2
{
    unsigned char cseValue;
    unsigned char verifyCSE;
    unsigned char verifyForward;
    unsigned short configPort;
    unsigned int dataValue;

    /* Test PCI Configuration Mechanism #2 */
    /* Write CSE value (0xF0) to port 0xCF8 */
    outb(0xCF8, 0xF0);

    /* Verify CSE was written correctly */
    verifyCSE = inb(0xCF8);

    if (verifyCSE == 0xF0) {
        /* Write 0 to Forward Register (0xCFA) */
        outb(0xCFA, 0);

        /* Verify Forward Register was written correctly */
        verifyForward = inb(0xCFA);

        if (verifyForward == 0) {
            /* Try to find a valid device in configuration space */
            /* Scan ports from 0xC000 to 0xCFFF */
            for (configPort = 0xC000; configPort < 0xD000; configPort += 0x100) {
                dataValue = inl(configPort);

                /* Check if we got a valid device (not 0xFFFFFFFF or 0x00000000) */
                if (dataValue != 0xFFFFFFFF && dataValue != 0x00000000) {
                    /* Found a valid device - Mechanism #2 is present */
                    outb(0xCF8, 0);
                    return YES;
                }
            }

            /* No valid devices found */
            outb(0xCF8, 0);
        }
    }

    /* Mechanism #2 not present */
    outb(0xCF8, 0);
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
