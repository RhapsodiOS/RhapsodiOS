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
 * DEC21x4Init.m
 * Initialization routines for DEC 21x4x Ethernet driver
 */

#import "DEC21X4X.h"
#import <driverkit/generalFuncs.h>

@implementation DEC21142(DEC21x4Init)

- (BOOL)_initAdapter
{
    BOOL linkDetected = YES;
    void *adapterInfo = self->Adapter;
    unsigned int chipRevision;
    unsigned int *word;
    unsigned char *byte;
    unsigned int mediaMode;
    BOOL miiLink;
    unsigned int i;

    word = (unsigned int *)adapterInfo;
    byte = (unsigned char *)adapterInfo;
    if (word[35] > 0) {
        for (i = 0; i < word[35]; i++) {
            IODelay(5);
            DC21X4WriteGepRegister(adapterInfo,
                                   ((unsigned short *)adapterInfo)[72 + i]);
        }
    }

    [self _initRegisters];

    if (byte[485]) {
        byte[490] = NO;
        byte[486] = DC21X4PhyInit(adapterInfo);
        chipRevision = word[21];
        if (!byte[495] && byte[486] &&
            (chipRevision == CHIP_REV_DC21142 || chipRevision == 0xff1011)) {
            word[127] &= 0xf7ffefef;
            word[128] &= 0xf7ffefef;
        }
    }

    chipRevision = word[21];
    mediaMode = word[152];
    switch (chipRevision) {
    case 0x141011:
        word[29] = 100000;
        word[54] |= word[27] | 0x80020000;
        word[62] |= word[27] | 0x80020000;
        word[70] |= word[27] | 0x80020000;
        if (word[30] == 516) word[30] = 512;
        if (byte[121] & 1) DC21X4EnableNway(adapterInfo);
        if (byte[121] & 8) {
            word[60] |= 0xf038;
            word[68] |= 0xf038;
            word[33] = (byte[124] & 2) ? 1 : 2;
        } else {
            word[33] = byte[120];
            word[31] &= 1U << word[33];
        }
        if (byte[121] & 2) {
            word[54] |= 0x200;
            word[52] = 32573;
            byte[484] = YES;
        } else if (byte[121] & 4) {
            word[52] = 20287;
        }
        break;

    case 0x91011:
        word[29] = 100000;
        word[54] |= word[27] | 0x80020000;
        word[62] |= word[27] | 0x80020000;
        word[70] |= word[27] | 0x80020000;
        if (word[30] == 516) {
            word[30] = 512;
            word[52] = 65533;
            word[54] |= 0x200;
            byte[484] = YES;
        } else {
            if (byte[121] & 4) word[52] = 53247;
        }
        word[33] = byte[120];
        word[31] &= 1U << word[33];
        break;

    case CHIP_REV_DC21040:
        word[29] = 100000;
        word[54] |= word[27] | 0x80020000;
        word[62] |= word[27] | 0x80020000;
        word[70] |= word[27] | 0x80020000;
        if (word[30] == 516) {
            word[30] = 512;
            word[52] = 65533;
            word[54] |= 0x200;
            byte[484] = YES;
        } else if (byte[121] & 4) {
            word[52] = 53247;
        }
        word[33] = byte[120];
        word[31] &= 1U << word[33];
        break;

    case CHIP_REV_DC21142:
    case 0xff1011:
        word[54] |= word[27] | 0x82420000;
        word[86] |= word[27] | 0x82420000;
        word[62] |= word[27] | 0x82420000;
        word[70] |= word[27] | 0x82420000;
        word[78] |= 0x82020000;
        word[94] |= 0x82020000;
        word[102] |= 0x82020000;
        word[110] |= 0x82020000;
        word[118] |= 0x82020000;
        word[54] |= 0x01000000;
        word[86] |= 0x01000000;
        word[62] |= 0x01000000;
        word[70] |= 0x01000000;
        word[78] |= 0x02080000;
        word[94] |= 0x02080000;
        word[110] |= 0x02080000;
        word[118] |= 0x02080000;
        if (byte[121] & 2) {
            word[54] |= 0x200;
            word[86] |= 0x200;
            word[94] |= 0x200;
            word[118] |= 0x200;
            byte[484] = YES;
        }
        if (byte[121] & 8) {
            word[29] = 100000;
        } else {
            word[33] = byte[120];
            word[31] &= 1U << word[33];
            word[29] = (byte[32 * word[33] + 219] & 1) ? 100000 : 1000000;
        }
        break;

    default:
        IOLog("Unknown adapter - initializeAdapter failed\n");
        break;
    }

    if (byte[486]) {
        if (byte[496] && (byte[505] & 8)) {
            word[126] &= 0xff00;
            byte[504] |= 9;
            word[33] = 0;
        }
        byte[486] = DC21X4SetPhyConnection(adapterInfo);
    } else if (word[31] == 0) {
        IOLog("Warning: unsupported media\n");
    }
    word[26] |= word[8 * word[33] + 54];
    word[154] = word[153];
    if (byte[484]) word[154] &= 0xfffff3ff;

    [self _startTransmit];
    if (![self _setAddressFiltering:YES]) {
        return NO;
    }

    if (mediaMode == 3 || !byte[486]) {
        DC21X4StopReceiverAndTransmitter(adapterInfo);
        outl(self->ioBase + CSR6_OPMODE, word[26] & 0xffffdffd);
        IODelay(1000);
        DC21X4InitializeMediaRegisters(adapterInfo, 0);
    }

    byte[497] = YES;
    DC21X4StartAdapter(adapterInfo);
    if (mediaMode != 3) {
        if (!byte[486]) {
            if (!byte[496] || (byte[124] & 6))
                linkDetected = DC21X4MediaDetect(adapterInfo);
        } else {
            miiLink = DC21X4MiiAutoDetect(adapterInfo);
            if (!byte[486] || (!miiLink && word[31] != 0)) {
                if (!byte[496] || (byte[124] & 6))
                    linkDetected = DC21X4MediaDetect(adapterInfo);
            }
        }
        if (linkDetected && word[136] == 0)
            DC21X4StartAutoSenseTimer(adapterInfo, 6000);
    }
    byte[498] = NO;

    return 1;
}

- (void)_initRegisters
{
    void *adapterInfo = self->Adapter;
    unsigned int chipRevision;
    unsigned int chipStep;
    unsigned int busMode;
    IOPhysicalAddress physAddr;
    IOReturn ret;

    chipRevision = *(unsigned int *)((char *)adapterInfo + 0x54);
    chipStep = *(unsigned char *)((char *)adapterInfo + 8);

    // Stop the adapter
    DC21X4StopAdapter(adapterInfo);

    // For DC21140, write CSR6 and stop again
    if (chipRevision == 0x91011) {
        outl(self->ioBase + CSR6_OPMODE,
             *(unsigned int *)((char *)adapterInfo + 0x68) & 0xffffdffd);
        DC21X4StopAdapter(adapterInfo);
    }

    // Setup bus mode register (CSR0) based on chip revision
    busMode = 0;
    if (chipRevision == CHIP_REV_DC21040 || chipRevision == 0x141011 ||
        (chipRevision == 0x91011 && (chipStep & 0xf0) == 0x10)) {
        busMode = 0x1000;  // Additional cache alignment
    }

    // Write bus mode register
    outl(self->ioBase + CSR0_BUS_MODE,
         (busMode & 0xfe5f3fff) | 0x01a04000);

    // Get physical address of RX descriptor ring
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)self->rxRing, &physAddr);
    if (ret != IO_R_SUCCESS) {
        IOLog("%s: IOPhysicalFromVirtual() error\n", [self name]);
        return;
    }
    
    // Write RX descriptor list base address (CSR3)
    outl(self->ioBase + CSR3_RX_LIST_BASE, physAddr);

    // Get physical address of TX descriptor ring
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)self->txRing, &physAddr);
    if (ret != IO_R_SUCCESS) {
        IOLog("%s: IOPhysicalFromVirtual() error\n", [self name]);
        return;
    }
    
    // Write TX descriptor list base address (CSR4)
    outl(self->ioBase + CSR4_TX_LIST_BASE, physAddr);

    // For DC21040, initialize SIA register
    if (chipRevision == CHIP_REV_DC21040) {
        // Write 0 to SIA CSR13
        outl(self->ioBase + CSR13_SIA_CONNECTIVITY, 0);
    }
}

- (BOOL)resetAndEnable:(BOOL)enable
{
    void *adapterInfo = self->Adapter;
    unsigned int chipRevision;
    unsigned int chipStep;
    unsigned int savedInterruptMask;
    IOReturn ret;
    unsigned int i;
    unsigned int mediaType;
    unsigned char defaultMedium;
    unsigned int *descriptorControl;
    const char *mediumName;

    chipRevision = *(unsigned int *)((char *)adapterInfo + 0x54);
    chipStep = *(unsigned char *)((char *)adapterInfo + 8);
    self->resetAndEnabled = NO;

    // Clear any pending timeouts
    [self clearTimeout];

    // Disable interrupts
    [self disableAdapterInterrupts];

    // Stop autosense timer if running
    if (*((unsigned int *)adapterInfo + 136) != 0) {
        DC21X4StopAutoSenseTimer(adapterInfo);
    }

    // Initialize setup frame descriptors (16 entries)
    for (i = 0; i < 16; i++) {
        ((unsigned int *)adapterInfo)[i + 3] =
            *(unsigned int *)adapterInfo + (8 * i);
    }

    // Setup frame descriptor control words
    descriptorControl = (unsigned int *)((char *)adapterInfo + 0x1fc);
    descriptorControl[0] = 0x0801b85b;
    descriptorControl[1] = 0x0001bfff;

    // Chip-specific descriptor flags
    if (chipRevision == CHIP_REV_DC21142) {
        descriptorControl[0] |= 0x04000000;
    } else if (chipRevision == 0xFF1011) {
        descriptorControl[1] |= 0x08000000;
        descriptorControl[0] |= 0x04000000;
    }

    // Stop the adapter
    DC21X4StopAdapter(adapterInfo);

    // Set various reset flags
    *((unsigned char *)adapterInfo + 0x1ec) = YES;
    *((unsigned char *)adapterInfo + 0x1ed) = YES;
    *((unsigned char *)adapterInfo + 0x1f2) = YES;

    // Initialize CSR template values
    *((unsigned int *)adapterInfo + 153) = 0x4f02;
    *((unsigned int *)adapterInfo + 155) = 0x48d3;

    // Initialize GEP values
    *((unsigned int *)adapterInfo + 27) = 0x4000;
    *((unsigned int *)adapterInfo + 28) = 0;

    // DC21040 special handling
    if (chipRevision == CHIP_REV_DC21040) {
        if (chipStep == 0x00 || chipStep == 0x20 || chipStep == 0x22) {
            *((unsigned int *)adapterInfo + 153) &= ~0x800;
            *((unsigned int *)adapterInfo + 27) = 0x4000;
        }
    }

    // Initialize RX ring
    if (![self _initRxRing]) {
        [self setRunning:NO];
        return NO;
    }

    // Initialize TX ring
    if (![self _initTxRing]) {
        [self setRunning:NO];
        return NO;
    }

    // Parse SROM
    if (![self parseSROM]) {
        IOLog("%s: Error while parsing SROM\n", [self name]);
        [self setRunning:NO];
        return NO;
    }

    // If not enabling, just set running and return success
    if (!enable) {
        [self setRunning:NO];
        self->resetAndEnabled = YES;
        return YES;
    }

    // Verify media support
    mediaType = *((unsigned int *)adapterInfo + 30);
    if (![self verifyMediaSupport:mediaType]) {
        // Use default medium instead
        defaultMedium = *((unsigned char *)adapterInfo + 0x80);
        mediumName = MediumString[defaultMedium];
        IOLog("%s: Unsupported medium. Using default: %s\n", [self name], mediumName);
        *((unsigned int *)adapterInfo + 30) = *((unsigned int *)adapterInfo + 32);
    }

    // Save interrupt mask and clear certain bits
    savedInterruptMask = descriptorControl[0];
    descriptorControl[0] &= 0xf7ffefef;

    // Enable all interrupts
    ret = [self enableAllInterrupts];
    if (ret != IO_R_SUCCESS) {
        IOLog("%s: Cannot enable interrupts\n", [self name]);
        [self setRunning:NO];
        return NO;
    }

    // Initialize adapter
    if (![self _initAdapter]) {
        IOLog("%s: initAdapter failed\n", [self name]);
        [self setRunning:NO];
        return NO;
    }

    // Restore interrupt mask
    descriptorControl[0] = savedInterruptMask;

    // Enable adapter interrupts
    [self enableAdapterInterrupts];

    // Set running flag
    [self setRunning:YES];
    self->resetAndEnabled = YES;

    return YES;
}

- (BOOL)verifyMediaSupport:(unsigned int)mediaType
{
    unsigned int phyIndex;
    unsigned int miiType;
    unsigned short phyMediaSupport;

    // Quick check: if bit 11 is set OR the mediaType bit is set in the mask,
    // then this media type is supported
    if ((mediaType & 0x800) != 0 ||
        ((1U << mediaType) & self->MediaCapableSaved) != 0) {
        return YES;
    }

    // Need to check MII PHY support
    if (*((unsigned char *)self->Adapter + 0x1e5) == 0) {
        return NO;
    }

    for (phyIndex = 0; phyIndex < 1; phyIndex++) {
        if (*((unsigned char *)self->Adapter + 0x230 + (phyIndex * 0x30)) == 0) {
            continue;
        }

        phyMediaSupport = *(unsigned short *)((char *)self->Adapter +
                                               0x23c + (phyIndex * 0x30));
        for (miiType = 0; miiType < MEDIA_BIT_TABLE_COUNT; miiType++) {
            if ((phyMediaSupport & MediaBitTable[miiType]) != 0 &&
                miiType == ConvertMediaTypeToMiiType[(unsigned char)mediaType]) {
                return YES;
            }
        }
    }

    return NO;
}

@end
