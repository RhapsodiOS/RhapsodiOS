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
 * DEC21x4SRom.m
 * Serial ROM reading routines for DEC 21x4x Ethernet driver
 */

#import "DEC21X4X.h"
#import <driverkit/generalFuncs.h>

@implementation DEC21142(DEC21x4SRom)

- (BOOL)parseSROM
{
    void *adapterInfo;
    unsigned int chipRevision;
    void *sromBuffer;
    BOOL parseSuccess;
    unsigned int wordIndex;
    unsigned short basePort;
    unsigned char sromAddressBits;
    unsigned int bitIndex;
    unsigned short csr9Port;
    unsigned int addressBit;
    unsigned short dataWord;
    int bitCount;
    unsigned int readValue;
    unsigned int mediaIndex;
    unsigned int supportedMediaMask;
    int phyIndex;
    int miiMediaIndex;
    BOOL miiPhyPresent;
    BOOL phyValid;
    unsigned short phyMediaSupport;
    unsigned short mediaBit;
    const char *driverName;
    const char *mediumName;

    // TODO: Get adapterInfo from offset 0x334
    adapterInfo = self->Adapter;

    chipRevision = *(unsigned int *)((char *)adapterInfo + 0x54);

    // Special case: DC21040 doesn't have real SROM, fake it
    if (chipRevision == 0x21011) {
        driverName = getDriverName(adapterInfo);
        IOLog("%s: Faking SROM data for 21040\n", driverName);
        parseSuccess = DC21040Parser(adapterInfo);
    }
    else {
        // Allocate buffer for SROM data (128 bytes = 0x80)
        sromBuffer = IOMalloc(0x80);
        if (sromBuffer == NULL) {
            IOLog("%s: Unable to allocate memory for SROM\n", [self name]);
            return NO;
        }

        basePort = self->ioBase;

        sromAddressBits = self->sromAddressBits;

        // Read 64 words (128 bytes) from SROM
        for (wordIndex = 0; wordIndex < 0x40; wordIndex++) {
            // CSR9 is at base + 0x48
            csr9Port = basePort + 0x48;

            // Send START condition (EEPROM 93C46 protocol)
            // This is a specific bit sequence to start SROM read
            outw(csr9Port, 0x4800);
            IODelay(250);  // 0xfa microseconds

            outw(csr9Port, 0x4801);
            IODelay(250);

            outw(csr9Port, 0x4803);
            IODelay(250);

            outw(csr9Port, 0x4801);
            IODelay(250);

            outw(csr9Port, 0x4805);
            IODelay(250);

            outw(csr9Port, 0x4807);
            IODelay(250);

            outw(csr9Port, 0x4805);
            IODelay(250);

            outw(csr9Port, 0x4805);
            IODelay(250);

            outw(csr9Port, 0x4807);
            IODelay(250);

            outw(csr9Port, 0x4805);
            IODelay(250);

            outw(csr9Port, 0x4801);
            IODelay(250);

            outw(csr9Port, 0x4803);
            IODelay(250);

            outw(csr9Port, 0x4801);
            IODelay(250);

            // Clock in address bits (MSB first)
            for (bitIndex = 0; bitIndex < sromAddressBits; bitIndex++) {
                // Extract bit from address (MSB first)
                addressBit = (wordIndex >> ((sromAddressBits - bitIndex) - 1)) & 1;

                if (addressBit < 2) {
                    addressBit = addressBit << 2;  // Shift to bit 2 position

                    outw(csr9Port, addressBit | 0x4801);
                    IODelay(250);

                    outw(csr9Port, addressBit | 0x4803);
                    IODelay(250);

                    outw(csr9Port, addressBit | 0x4801);
                    IODelay(250);
                }
                else {
                    IOLog("bogus data in clock_in_bit\n");
                }
            }

            // Clock out 16 data bits
            dataWord = 0;
            for (bitCount = 0; bitCount < 0x10; bitCount++) {
                outw(csr9Port, 0x4803);
                IODelay(250);

                readValue = inw(csr9Port);
                IODelay(250);

                outw(csr9Port, 0x4801);
                IODelay(250);

                // Extract bit 3 and shift into result
                dataWord = (dataWord * 2) | ((readValue >> 3) & 1);
            }

            // Store word in buffer
            ((unsigned short *)sromBuffer)[wordIndex] = dataWord;
        }

        // Parse the SROM data
        parseSuccess = DC21X4ParseSRom(adapterInfo, sromBuffer);

        // Free the buffer
        IOFree(sromBuffer, 0x80);
    }

    if (!parseSuccess) {
        IOLog("%s: Error while parsing SRom!\n", [self name]);
        return NO;
    }

    // Log all supported media types from SROM
    supportedMediaMask = *(unsigned int *)((char *)adapterInfo + 0x7c);

    for (mediaIndex = 0; mediaIndex < MEDIUM_STRING_COUNT; mediaIndex++) {
        if ((supportedMediaMask >> mediaIndex) & 1) {
            mediumName = MediumString[mediaIndex];
            IOLog("%s: SROM Medium: %s\n", [self name], mediumName);
        }
    }

    // Log PHY media support if MII PHY is present
    miiPhyPresent = *((unsigned char *)adapterInfo + 0x1e5);

    if (miiPhyPresent) {
        // Check only first PHY (phyIndex < 1)
        for (phyIndex = 0; phyIndex < 1; phyIndex++) {
            // PHY structure starts at offset 0x230, each entry is 0x30 bytes
            phyValid = *((unsigned char *)adapterInfo + 0x230 + (phyIndex * 0x30));

            if (phyValid) {
                // Check all 18 MII media types
                for (miiMediaIndex = 0; miiMediaIndex < MEDIUM_STRING_COUNT; miiMediaIndex++) {
                    phyMediaSupport = *(unsigned short *)((char *)adapterInfo + 0x23c + (phyIndex * 0x30));

                    mediaBit = MediaBitTable[miiMediaIndex];

                    if ((mediaBit & phyMediaSupport) != 0) {
                        mediumName = MediumString[miiMediaIndex];
                        IOLog("%s: SROM PHY%d Medium: %s\n", [self name], phyIndex, mediumName);
                    }
                }
            }
        }
    }

    self->MediaCapableSaved = supportedMediaMask;

    return YES;
}

@end
