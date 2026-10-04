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
    // TODO: This method needs access to adapter private data structure
    // The following implementation uses placeholder accessors that need to be
    // replaced with actual structure field access

    BOOL linkDetected = YES;
    void *adapterInfo = self->Adapter;

    // Write GEP sequence registers if present
    // TODO: Access gepSequenceCount and gepSequence from adapter structure
    int gepSequenceCount = 0;  // adapterInfo->gepSequenceCount
    if (gepSequenceCount > 0) {
        for (int i = 0; i < gepSequenceCount; i++) {
            IODelay(5);
            // TODO: DC21X4WriteGepRegister(adapterInfo, adapterInfo->gepSequence[i]);
        }
    }

    // Initialize registers
    [self _initRegisters];

    // Initialize MII PHY if present
    // TODO: Check adapterInfo->miiPresent flag
    BOOL miiPresent = NO;
    if (miiPresent) {
        // TODO: Set adapterInfo->phyInitialized = NO;
        BOOL phyInitOk = DC21X4PhyInit(adapterInfo);
        // TODO: adapterInfo->phyInitSuccess = phyInitOk;

        // TODO: Check chip revision and clear certain capability bits for 0x191011/0xff1011
        unsigned int chipRevision = 0;  // TODO: adapterInfo->chipRevision
        if (phyInitOk && chipRevision == 0x191011 || chipRevision == 0xff1011) {
            // TODO: Clear specific media capability bits
        }
    }

    // Configure based on chip revision
    unsigned int chipRevision = 0;  // TODO: Get from adapter structure
    unsigned int mediaCapabilities = 0;
    unsigned int mediaType = 0;
    unsigned char mediaOptions = 0;

    switch (chipRevision) {
        case 0x21011:  // DC21040
            // TODO: Set timer interval to 100ms
            // TODO: Configure media blocks with 0x80020000 flags

            if (mediaType == 0x204) {
                mediaType = 0x200;  // Change to AUI
                // TODO: Set SIA values and enable scrambler
            } else if ((mediaOptions & 0x04) != 0) {
                // TODO: Configure for BNC
            }

            // TODO: Set current media and filter capabilities
            break;

        case 0x91011:  // DC21140
            // TODO: Configure all media blocks with appropriate flags
            // TODO: Set up SIA registers for various media types

            if ((mediaOptions & 0x02) != 0) {
                // TODO: Enable scrambler for 100BaseTX
            }

            if ((mediaOptions & 0x08) == 0) {
                // TODO: Set media index from mediaType
            } else {
                // TODO: Set timer interval to 100ms
            }
            break;

        case 0x141011:  // DC21041
            // TODO: Set timer interval to 100ms
            // TODO: Configure media blocks

            if (mediaType == 0x204) {
                mediaType = 0x200;
            }

            if ((mediaOptions & 0x01) != 0) {
                DC21X4EnableNway(adapterInfo);
            }

            if ((mediaOptions & 0x08) == 0) {
                // TODO: Set media index
            } else {
                // TODO: Configure GEP for autosense
            }

            if ((mediaOptions & 0x02) != 0) {
                // TODO: Enable scrambler
            } else if ((mediaOptions & 0x04) != 0) {
                // TODO: Configure for BNC
            }
            break;

        case 0x191011:  // DC21143
        case 0xff1011:
            // TODO: Configure media blocks for 21143

            if (mediaType == 0x204) {
                mediaType = 0x200;
            }

            // TODO: Check if PHY is present and enable Nway if appropriate
            BOOL phyInitSuccess = NO;
            BOOL phyNwayCapable = NO;
            if ((mediaOptions & 0x01) != 0 && (!phyInitSuccess || !phyNwayCapable)) {
                DC21X4EnableNway(adapterInfo);
            }

            if ((mediaOptions & 0x08) == 0) {
                // TODO: Set media index from mediaType
                int mediaIndex = 0;
                if (mediaIndex == 3 || (mediaIndex >= 5 && mediaIndex <= 8)) {
                    // TODO: Set timer to 1000ms for 10BaseT
                } else {
                    // TODO: Set timer to 100ms
                }
            } else {
                // TODO: Configure GEP for autosense
                // TODO: Determine media index based on capabilities
            }

            if ((mediaOptions & 0x02) != 0) {
                // TODO: Enable scrambler
            } else if ((mediaOptions & 0x04) != 0) {
                // TODO: Configure for BNC
            }
            break;

        default:
            IOLog("Unknown adapter - initializeAdapter failed\n");
            return NO;
    }

    // Handle MII PHY connection if present
    // TODO: Check phyInitSuccess flag
    BOOL phyInitSuccess = NO;
    if (phyInitSuccess) {
        // TODO: Handle Broadcom PHY special case
        BOOL isBroadcomPhy = NO;
        unsigned char broadcomPhyOptions = 0;
        if (isBroadcomPhy && (broadcomPhyOptions & 0x08) != 0) {
            // TODO: Configure Broadcom PHY for autosense
        }

        phyInitSuccess = DC21X4SetPhyConnection(adapterInfo);
        if (!phyInitSuccess) {
            if (mediaCapabilities == 0) {
                IOLog("Warning: unsupported media\n");
            }
        }
    } else {
        if (mediaCapabilities == 0) {
            IOLog("Warning: unsupported media\n");
        }
    }

    // TODO: Merge media capabilities into opmode register
    // TODO: Copy CSR6 template to opmode

    // TODO: Check if scrambler is disabled and clear scrambler bit

    // Start transmit
    [self _startTransmit];

    // Set address filtering
    if (![self _setAddressFiltering:YES]) {
        return NO;
    }

    // Handle media mode = 3 (MII) or no PHY
    int mediaMode = 0;  // TODO: Get from adapter structure
    if (mediaMode == 3 || !phyInitSuccess) {
        DC21X4StopReceiverAndTransmitter(adapterInfo);
        // TODO: Write CSR6 with opmode & ~0x2002
        // TODO: Increment counter
        IODelay(1000);
        DC21X4InitializeMediaRegisters(adapterInfo, 0);
    }

    // TODO: Set resetInProgress flag to YES
    DC21X4StartAdapter(adapterInfo);

    // Detect link
    if (mediaMode == 3) {
        // Media mode is MII, link detected in startAdapter
    } else if (!phyInitSuccess) {
        // No PHY, do autosense
        // TODO: Check if Broadcom PHY present or media capabilities include 10BaseT/100BaseTX
        BOOL needAutosense = NO;
        if (needAutosense) {
            linkDetected = DC21X4MediaDetect(adapterInfo);
        }
    } else {
        // MII PHY present, try auto-detect
        linkDetected = DC21X4MiiAutoDetect(adapterInfo);
        if (!phyInitSuccess || (!linkDetected && mediaCapabilities != 0)) {
            // Fallback to non-MII autosense
            // TODO: Check conditions
            BOOL needAutosense = NO;
            if (needAutosense) {
                linkDetected = DC21X4MediaDetect(adapterInfo);
            }
        }
    }

    // Start autosense timer if link not detected and not already timing
    // TODO: Check timerHandle
    int timerHandle = 0;
    if (linkDetected && timerHandle == 0) {
        DC21X4StartAutoSenseTimer(adapterInfo, 6000);
    }

    // TODO: Set resetInProgress flag to NO

    return YES;
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
