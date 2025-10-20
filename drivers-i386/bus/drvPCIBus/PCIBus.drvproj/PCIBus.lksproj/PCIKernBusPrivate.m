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
