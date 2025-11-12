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
    void *adapterInfo = NULL;  // TODO: Get adapter info structure

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
    unsigned int busMode = 0;
    unsigned int chipRevision = 0;  // TODO: Get from adapter structure
    unsigned int chipStep = 0;      // TODO: Get from adapter structure  
    void *adapterInfo = NULL;       // TODO: Get adapter info structure
    vm_address_t physAddr;
    IOReturn ret;
    
    // Stop the adapter
    DC21X4StopAdapter(adapterInfo);
    
    // For DC21140, write CSR6 and stop again
    if (chipRevision == 0x91011) {
        // TODO: Write CSR6 (opmode & ~0x2002)
        // TODO: outl(ioBaseAddr + CSR6, opmode & ~0x2002);
        DC21X4StopAdapter(adapterInfo);
    }
    
    // Setup bus mode register (CSR0) based on chip revision
    busMode = 0;
    
    if (chipRevision == 0x21011 ||          // DC21040
        chipRevision == 0x141011 ||          // DC21041
        (chipRevision == 0x91011 && (chipStep & 0xF0) == 0x10)) {  // DC21140 rev 1.x
        busMode = 0x1000;  // Additional cache alignment
    }
    
    // Write bus mode register
    // CSR0 = 0x1A04000 | busMode
    // Bits: Big/Little Endian, Cache Alignment, Burst Length, etc.
    // TODO: outl(ioBaseAddr + CSR0, 0x1A04000 | busMode);
    
    // Get physical address of RX descriptor ring
    // TODO: Use actual rxRingPhys field
    void *rxRingVirt = NULL;  // TODO: Get from adapter structure
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)rxRingVirt, &physAddr);
    if (ret != IO_R_SUCCESS) {
        IOLog("%s: IOPhysicalFromVirtual() error\n", [self name]);
        return;
    }
    
    // Write RX descriptor list base address (CSR3)
    // TODO: outl(ioBaseAddr + CSR3, physAddr);
    
    // Get physical address of TX descriptor ring
    // TODO: Use actual txRingPhys field
    void *txRingVirt = NULL;  // TODO: Get from adapter structure
    ret = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)txRingVirt, &physAddr);
    if (ret != IO_R_SUCCESS) {
        IOLog("%s: IOPhysicalFromVirtual() error\n", [self name]);
        return;
    }
    
    // Write TX descriptor list base address (CSR4)
    // TODO: outl(ioBaseAddr + CSR4, physAddr);
    
    // For DC21040, initialize SIA register
    if (chipRevision == 0x21011) {
        // Write 0 to SIA CSR13
        // TODO: outl(ioBaseAddr + SIA_CSR13, 0);
    }
}

- (BOOL)_resetAndEnable:(BOOL)enable
{
    void *adapterInfo = NULL;  // TODO: Get adapter info structure
    unsigned int chipRevision = 0;  // TODO: Get from adapter structure
    unsigned int chipStep = 0;      // TODO: Get from adapter structure
    unsigned int savedInterruptMask;
    BOOL success;
    
    // TODO: Clear hardwareResetInProgress flag (offset 0x182)
    // *(BOOL *)(self + 0x182) = NO;
    
    // Clear any pending timeouts
    [self clearTimeout];
    
    // Disable interrupts
    [self disableAdapterInterrupts];
    
    // Stop autosense timer if running
    // TODO: Check timerHandle at offset 0x220
    int timerHandle = 0;  // TODO: adapterInfo->timerHandle
    if (timerHandle != 0) {
        DC21X4StopAutoSenseTimer(adapterInfo);
    }
    
    // Initialize setup frame descriptors (16 entries)
    // TODO: This accesses setupFrameDescriptors array
    for (int i = 0; i < 16; i++) {
        // TODO: Set descriptor buffer addresses
        // adapterInfo->setupFrameDescriptors[i].bufferAddr = 
        //     adapterInfo->setupFrameBase + (i * 8);
    }
    
    // Setup frame descriptor control words
    // TODO: Set descriptor 0 control word at offset 0x1FC
    // *(unsigned int *)(adapterInfo + 0x1FC) = 0x0801B85B;
    // TODO: Set descriptor 1 control word at offset 0x200
    // *(unsigned int *)(adapterInfo + 0x200) = 0x0001BFFF;
    
    // Chip-specific descriptor flags
    if (chipRevision == 0x191011) {  // DC21143
        // TODO: Set bit 26 in descriptor 0
        // *(unsigned int *)(adapterInfo + 0x1FC) |= 0x04000000;
    } else if (chipRevision == 0xFF1011) {
        // TODO: Set bit 27 in descriptor 1
        // *(unsigned int *)(adapterInfo + 0x200) |= 0x08000000;
        // TODO: Set bit 26 in descriptor 0
        // *(unsigned int *)(adapterInfo + 0x1FC) |= 0x04000000;
    }
    
    // Stop the adapter
    DC21X4StopAdapter(adapterInfo);
    
    // Set various reset flags
    // TODO: Set flags at offsets 0x1EC, 0x1ED, 0x1F2
    // *(BOOL *)(adapterInfo + 0x1EC) = YES;  // txInterruptEnabled
    // *(BOOL *)(adapterInfo + 0x1ED) = YES;  // rxInterruptEnabled  
    // *(BOOL *)(adapterInfo + 0x1F2) = YES;  // resetInProgress
    
    // Initialize CSR template values
    // TODO: Set CSR6 template at offset 0x264
    // *(unsigned int *)(adapterInfo + 0x264) = 0x4F02;
    // TODO: Set CSR7 template at offset 0x26C
    // *(unsigned int *)(adapterInfo + 0x26C) = 0x48D3;
    
    // Initialize GEP values
    // TODO: Set GEP direction at offset 0x6C
    // *(unsigned int *)(adapterInfo + 0x6C) = 0x4000;
    // TODO: Set GEP data at offset 0x70
    // *(unsigned int *)(adapterInfo + 0x70) = 0;
    
    // DC21040 special handling
    if (chipRevision == 0x21011) {
        if (chipStep == 0x00 || chipStep == 0x20 || chipStep == 0x22) {
            // Clear bit 11 in CSR6 template for early revisions
            // TODO: *(unsigned int *)(adapterInfo + 0x264) &= ~0x800;
            // TODO: *(unsigned int *)(adapterInfo + 0x6C) = 0x4000;
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
    if (![self _parseSROM]) {
        IOLog("%s: Error while parsing SROM\n", [self name]);
        [self setRunning:NO];
        return NO;
    }
    
    // If not enabling, just set running and return success
    if (!enable) {
        [self setRunning:YES];
        return YES;
    }
    
    // Verify media support
    // TODO: Get mediaType from offset 0x78
    unsigned int mediaType = 0;  // TODO: *(unsigned int *)(adapterInfo + 0x78)
    if (![self _verifyMediaSupport:mediaType]) {
        // Use default medium instead
        // TODO: Get defaultMedium from offset 0x80
        unsigned char defaultMedium = 0;  // TODO: *(unsigned char *)(adapterInfo + 0x80)
        
        // TODO: Get medium name from MediumString table
        const char *mediumName = "unknown";  // TODO: MediumString[defaultMedium]
        
        IOLog("%s: Unsupported medium. Using default: %s\n", [self name], mediumName);
        
        // TODO: Set mediaType to defaultMedium
        // *(unsigned int *)(adapterInfo + 0x78) = defaultMedium;
    }
    
    // Save interrupt mask and clear certain bits
    // TODO: Get interrupt mask from offset 0x1FC
    savedInterruptMask = 0;  // TODO: *(unsigned int *)(adapterInfo + 0x1FC)
    // TODO: Clear bits in interrupt mask
    // *(unsigned int *)(adapterInfo + 0x1FC) &= 0xF7FFEFEF;
    
    // Enable all interrupts
    success = [self enableAllInterrupts];
    if (!success) {
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
    // TODO: *(unsigned int *)(adapterInfo + 0x1FC) = savedInterruptMask;
    
    // Enable adapter interrupts
    [self enableAdapterInterrupts];
    
    // Set running flag
    [self setRunning:YES];
    
    // TODO: Set hardwareResetInProgress flag (offset 0x182)
    // *(BOOL *)(self + 0x182) = YES;
    
    return YES;
}

- (BOOL)_verifyMediaSupport:(unsigned int)mediaType
{
    BOOL result;
    unsigned int phyIndex;
    int phyCount;
    void *adapterInfo;
    unsigned int supportedMediaMask;
    BOOL miiPhyPresent;
    BOOL phyValid;
    unsigned short phyMediaSupport;
    unsigned short mediaBit;
    unsigned char miiType;

    // TODO: Get adapterInfo from offset 0x334
    adapterInfo = NULL;  // TODO: *(void **)(self + 0x334)

    // TODO: Get supported media mask from offset 0x338
    supportedMediaMask = 0;  // TODO: *(unsigned int *)(self + 0x338)

    // Quick check: if bit 11 is set OR the mediaType bit is set in the mask,
    // then this media type is supported
    if ((mediaType & 0x800) != 0 ||
        (supportedMediaMask & (1 << (mediaType & 0x1f))) != 0) {
        return YES;
    }

    // Need to check MII PHY support
    // TODO: Check if MII PHY is present at offset 0x1e5 in adapterInfo
    miiPhyPresent = NO;  // TODO: *(BOOL *)(adapterInfo + 0x1e5)

    if (miiPhyPresent) {
        phyCount = 0;
        do {
            // TODO: Check if PHY entry is valid
            // PHY structure starts at offset 0x230, each entry is 0x30 bytes
            phyValid = NO;  // TODO: *(BOOL *)((phyCount * 0x30) + 0x230 + adapterInfo)

            if (phyValid) {
                phyIndex = 0;
                do {
                    // TODO: Get PHY media support bitmap at offset 0x23c
                    phyMediaSupport = 0;  // TODO: *(unsigned short *)((phyCount * 0x30) + 0x23c + adapterInfo)

                    // TODO: Get media bit from MediaBitTable
                    mediaBit = 0;  // TODO: MediaBitTable[phyIndex]

                    // Check if this media type is supported by the PHY
                    if ((mediaBit & phyMediaSupport) != 0) {
                        // TODO: Convert media type to MII type
                        miiType = 0;  // TODO: ConvertMediaTypeToMiiType[mediaType & 0xff]

                        if (phyIndex == miiType) {
                            // Found matching media support
                            return YES;
                        }
                    }

                    phyIndex++;
                } while (phyIndex < MEDIUM_STRING_COUNT);
            }

            phyCount++;
        } while (phyCount < 1);  // Only check first PHY
    }

    // Media type not supported
    return NO;
}

@end
