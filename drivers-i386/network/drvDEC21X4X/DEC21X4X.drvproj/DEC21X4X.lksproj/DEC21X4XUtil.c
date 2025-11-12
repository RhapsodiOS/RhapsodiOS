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
 * DEC21X4XUtil.c
 * Utility and support routines for DEC 21x4x Ethernet driver
 */

#include "DEC21X4X.h"

// Global variables
BOOL mediaSupported = NO;

// Lookup Tables

// CRC32 lookup table
// Used for calculating CRC32 checksums for multicast MAC address filtering
#define CRC_TABLE_SIZE 256
const unsigned int CrcTable[CRC_TABLE_SIZE] = {
    0x00000000, 0x77073096, 0xee0e612c, 0x990951ba,
    0x076dc419, 0x706af48f, 0xe963a535, 0x9e6495a3,
    0x0edb8832, 0x79dcb8a4, 0xe0d5e91e, 0x97d2d988,
    0x09b64c2b, 0x7eb17cbd, 0xe7b82d07, 0x90bf1d91,
    0x1db71064, 0x6ab020f2, 0xf3b97148, 0x84be41de,
    0x1adad47d, 0x6ddde4eb, 0xf4d4b551, 0x83d385c7,
    0x136c9856, 0x646ba8c0, 0xfd62f97a, 0x8a65c9ec,
    0x14015c4f, 0x63066cd9, 0xfa0f3d63, 0x8d080df5,
    0x3b6e20c8, 0x4c69105e, 0xd56041e4, 0xa2677172,
    0x3c03e4d1, 0x4b04d447, 0xd20d85fd, 0xa50ab56b,
    0x35b5a8fa, 0x42b2986c, 0xdbbbc9d6, 0xacbcf940,
    0x32d86ce3, 0x45df5c75, 0xdcd60dcf, 0xabd13d59,
    0x26d930ac, 0x51de003a, 0xc8d75180, 0xbfd06116,
    0x21b4f4b5, 0x56b3c423, 0xcfba9599, 0xb8bda50f,
    0x2802b89e, 0x5f058808, 0xc60cd9b2, 0xb10be924,
    0x2f6f7c87, 0x58684c11, 0xc1611dab, 0xb6662d3d,
    0x76dc4190, 0x01db7106, 0x98d220bc, 0xefd5102a,
    0x71b18589, 0x06b6b51f, 0x9fbfe4a5, 0xe8b8d433,
    0x7807c9a2, 0x0f00f934, 0x9609a88e, 0xe10e9818,
    0x7f6a0dbb, 0x086d3d2d, 0x91646c97, 0xe6635c01,
    0x6b6b51f4, 0x1c6c6162, 0x856530d8, 0xf262004e,
    0x6c0695ed, 0x1b01a57b, 0x8208f4c1, 0xf50fc457,
    0x65b0d9c6, 0x12b7e950, 0x8bbeb8ea, 0xfcb9887c,
    0x62dd1ddf, 0x15da2d49, 0x8cd37cf3, 0xfbd44c65,
    0x4db26158, 0x3ab551ce, 0xa3bc0074, 0xd4bb30e2,
    0x4adfa541, 0x3dd895d7, 0xa4d1c46d, 0xd3d6f4fb,
    0x4369e96a, 0x346ed9fc, 0xad678846, 0xda60b8d0,
    0x44042d73, 0x33031de5, 0xaa0a4c5f, 0xdd0d7cc9,
    0x5005713c, 0x270241aa, 0xbe0b1010, 0xc90c2086,
    0x5768b525, 0x206f85b3, 0xb966d409, 0xce61e49f,
    0x5edef90e, 0x29d9c998, 0xb0d09822, 0xc7d7a8b4,
    0x59b33d17, 0x2eb40d81, 0xb7bd5c3b, 0xc0ba6cad,
    0xedb88320, 0x9abfb3b6, 0x03b6e20c, 0x74b1d29a,
    0xead54739, 0x9dd277af, 0x04db2615, 0x73dc1683,
    0xe3630b12, 0x94643b84, 0x0d6d6a3e, 0x7a6a5aa8,
    0xe40ecf0b, 0x9309ff9d, 0x0a00ae27, 0x7d079eb1,
    0xf00f9344, 0x8708a3d2, 0x1e01f268, 0x6906c2fe,
    0xf762575d, 0x806567cb, 0x196c3671, 0x6e6b06e7,
    0xfed41b76, 0x89d32be0, 0x10da7a5a, 0x67dd4acc,
    0xf9b9df6f, 0x8ebeeff9, 0x17b7be43, 0x60b08ed5,
    0xd6d6a3e8, 0xa1d1937e, 0x38d8c2c4, 0x4fdff252,
    0xd1bb67f1, 0xa6bc5767, 0x3fb506dd, 0x48b2364b,
    0xd80d2bda, 0xaf0a1b4c, 0x36034af6, 0x41047a60,
    0xdf60efc3, 0xa867df55, 0x316e8eef, 0x4669be79,
    0xcb61b38c, 0xbc66831a, 0x256fd2a0, 0x5268e236,
    0xcc0c7795, 0xbb0b4703, 0x220216b9, 0x5505262f,
    0xc5ba3bbe, 0xb2bd0b28, 0x2bb45a92, 0x5cb36a04,
    0xc2d7ffa7, 0xb5d0cf31, 0x2cd99e8b, 0x5bdeae1d,
    0x9b64c2b0, 0xec63f226, 0x756aa39c, 0x026d930a,
    0x9c0906a9, 0xeb0e363f, 0x72076785, 0x05005713,
    0x95bf4a82, 0xe2b87a14, 0x7bb12bae, 0x0cb61b38,
    0x92d28e9b, 0xe5d5be0d, 0x7cdcefb7, 0x0bdbdf21,
    0x86d3d2d4, 0xf1d4e242, 0x68ddb3f8, 0x1fda836e,
    0x81be16cd, 0xf6b9265b, 0x6fb077e1, 0x18b74777,
    0x88085ae6, 0xff0f6a70, 0x66063bca, 0x11010b5c,
    0x8f659eff, 0xf862ae69, 0x616bffd3, 0x166ccf45,
    0xa00ae278, 0xd70dd2ee, 0x4e048354, 0x3903b3c2,
    0xa7672661, 0xd06016f7, 0x4969474d, 0x3e6e77db,
    0xaed16a4a, 0xd9d65adc, 0x40df0b66, 0x37d83bf0,
    0xa9bcae53, 0xdebb9ec5, 0x47b2cf7f, 0x30b5ffe9,
    0xbdbdf21c, 0xcabac28a, 0x53b39330, 0x24b4a3a6,
    0xbad03605, 0xcdd70693, 0x54de5729, 0x23d967bf,
    0xb3667a2e, 0xc4614ab8, 0x5d681b02, 0x2a6f2b94,
    0xb40bbe37, 0xc30c8ea1, 0x5a05df1b, 0x2d02ef8d
};

// Medium/Media type name strings
// Used for logging and displaying media types
const char *MediumString[MEDIUM_STRING_COUNT] = {
    "10BaseT",           // Index 0
    "10Base2",           // Index 1: BNC
    "10Base5",           // Index 2: AUI
    "100BaseTX",         // Index 3
    "10BaseT_FD",        // Index 4: 10Base-T Full Duplex
    "100BaseTX_FD",      // Index 5: 100Base-TX Full Duplex
    "100BaseT4",         // Index 6
    "100BaseFX",         // Index 7: Fiber
    "100BaseFX_FD",      // Index 8: Fiber Full Duplex
    "Mii10BaseT",        // Index 9: MII 10Base-T
    "Mii10BaseT_FD",     // Index 10: MII 10Base-T Full Duplex
    "Mii10Base2",        // Index 11: MII BNC
    "Mii10Base5",        // Index 12: MII AUI
    "Mii100BaseTX",      // Index 13: MII 100Base-TX
    "Mii100BaseTX_FD",   // Index 14: MII 100Base-TX Full Duplex
    "Mii100BaseT4",      // Index 15: MII 100Base-T4
    "Mii100BaseFX",      // Index 16: MII Fiber
    "Mii100BaseFX_FD"    // Index 17: MII Fiber Full Duplex
};

// Connection type values (13 entries)
// Maps connection types used internally
const unsigned int _ConnectionType[] = {
    0x0900,  // Entry 0
    0x0100,  // Entry 1
    0x0000,  // Entry 2
    0x0204,  // Entry 3
    0x0400,  // Entry 4
    0x0200,  // Entry 5
    0x0000,  // Entry 6
    0x0800,  // Entry 7
    0x0900,  // Entry 8
    0x0300,  // Entry 9
    0x0205,  // Entry 10
    0x0600,  // Entry 11
    0x0700,  // Entry 12
    0x0208   // Entry 13
};

// Connector name strings
const char *connectorTable[CONNECTOR_TABLE_COUNT] = {
    "AutoSense",           // Index 0
    "AutoSense No Nway",   // Index 1
    "TP",                  // Index 2: Twisted Pair (10Base-T)
    "TP_FD",               // Index 3: TP Full Duplex
    "10Base2",             // Index 4: BNC
    "10Base5",             // Index 5: AUI
    "100BaseTX",           // Index 6
    "100BaseTX_FD",        // Index 7: 100Base-TX Full Duplex
    "100BaseT4",           // Index 8
    "100BaseFX",           // Index 9: Fiber
    "100BaseFX_FD",        // Index 10: Fiber Full Duplex
    "MII"                  // Index 11: MII connector
};

// Connector to media type mapping
// Maps connector table index to media type value
const unsigned int connectorMediaMap[CONNECTOR_MEDIA_MAP_COUNT] = {
    0x0900,  // AutoSense
    0x0800,  // AutoSense No Nway
    0x0100,  // TP (10Base-T)
    0x0200,  // TP Full Duplex
    0x0000,  // 10Base2 (BNC)
    0x0204,  // 10Base5 (AUI)
    0x0400,  // 100BaseTX
    0x0300,  // 100BaseTX Full Duplex
    0x0205,  // 100BaseT4
    0x0600,  // 100BaseFX (Fiber)
    0x0700,  // 100BaseFX Full Duplex
    0x0208   // MII
};

// MII PHY Admin Control conversion table (7 entries)
// Maps admin control values to MII register values
const unsigned short _AdminControlConversionTable[] = {
    0x8000,  // Entry 0: Reset
    0x0000,  // Entry 1
    0x0400,  // Entry 2: Auto-negotiate enable
    0x0800,  // Entry 3: Power down
    0x0000,  // Entry 4
    0x0100,  // Entry 5: Isolate
    0x0000   // Entry 6
};

// Media bit table
// Bit masks for different media types
const unsigned short MediaBitTable[MEDIA_BIT_TABLE_COUNT] = {
    0x0000,  // Entry 0
    0x0000,  // Entry 1
    0x0000,  // Entry 2
    0x0000,  // Entry 3
    0x0000,  // Entry 4
    0x0000,  // Entry 5
    0x0000,  // Entry 6
    0x0000,  // Entry 7
    0x0000,  // Entry 8
    0x0800,  // Entry 9: 10Base-T
    0x1000,  // Entry 10: 10Base-T Full Duplex
    0x0000,  // Entry 11
    0x0000,  // Entry 12
    0x2000,  // Entry 13: 100Base-TX
    0x4000,  // Entry 14: 100Base-TX Full Duplex
    0x8000,  // Entry 15: 100Base-T4
    0x0000,  // Entry 16
    0x0000   // Entry 17
};

// Media type to MII type conversion table
// Converts driver media type index to MII-specific media type
const unsigned short ConvertMediaTypeToMiiType[MEDIA_TO_MII_TYPE_COUNT] = {
    0x0009,  // Entry 0
    0x000b,  // Entry 1
    0x000c,  // Entry 2
    0x000d,  // Entry 3
    0x020a,  // Entry 4
    0x020e,  // Entry 5
    0x000f,  // Entry 6
    0x0010,  // Entry 7
    0x0211   // Entry 8
};

// Media to command conversion table (18 entries)
// Converts media type to CSR6 command register values
const unsigned short MediaToCommandConversionTable[] = {
    0x0000,  // Entry 0
    0x0000,  // Entry 1
    0x0000,  // Entry 2
    0x2000,  // Entry 3: Port Select
    0x0100,  // Entry 4
    0x2100,  // Entry 5
    0x2000,  // Entry 6
    0x2000,  // Entry 7
    0x2100,  // Entry 8
    0x0000,  // Entry 9
    0x0100,  // Entry 10: Full Duplex
    0x0000,  // Entry 11
    0x0000,  // Entry 12
    0x2000,  // Entry 13
    0x2100,  // Entry 14
    0x2000,  // Entry 15
    0x2000,  // Entry 16
    0x2100   // Entry 17
};

// Media to N-Way conversion table (18 entries)
// Converts media type to N-Way auto-negotiation advertisement values
const unsigned short MediaToNwayConversionTable[] = {
    0x0020,  // Entry 0
    0x0000,  // Entry 1
    0x0000,  // Entry 2
    0x0080,  // Entry 3: 10Base-T
    0x0040,  // Entry 4: 10Base-T Full Duplex
    0x0100,  // Entry 5: 100Base-TX
    0x0200,  // Entry 6: 100Base-TX Full Duplex
    0x0080,  // Entry 7
    0x0100,  // Entry 8
    0x0020,  // Entry 9
    0x0040,  // Entry 10
    0x0000,  // Entry 11
    0x0000,  // Entry 12
    0x0080,  // Entry 13
    0x0100,  // Entry 14
    0x0200,  // Entry 15
    0x0080,  // Entry 16
    0x0100   // Entry 17
};

// Media to status conversion table (18 entries)
// Converts media type to expected status register values
const unsigned short MediaToStatusConversionTable[] = {
    0x0800,  // Entry 0
    0x0000,  // Entry 1
    0x0000,  // Entry 2
    0x2000,  // Entry 3
    0x1000,  // Entry 4
    0x4000,  // Entry 5
    0x8000,  // Entry 6
    0x2000,  // Entry 7
    0x4000,  // Entry 8
    0x0800,  // Entry 9
    0x1000,  // Entry 10
    0x0000,  // Entry 11
    0x0000,  // Entry 12
    0x2000,  // Entry 13
    0x4000,  // Entry 14
    0x8000,  // Entry 15
    0x2000,  // Entry 16
    0x0000   // Entry 17
};

int CheckConnectionSupport(void *adapter, int connection)
{
    return 0;
}

int ConvertConnectionToControl(int connection)
{
    return 0;
}

int ConvertMediaTypeToNwayLocalAbility(int mediaType)
{
    return 0;
}

int ConvertNwayToConnectionType(int nway)
{
    return 0;
}

unsigned int CRC32(unsigned char *data, int length)
{
    return 0;
}

int DC21040Parser(void *adapter)
{
    return 0;
}

void DC2104InitializeSiaRegisters(void *adapter)
{
}

int DC2114Sense100BaseTxLink(void *adapter)
{
    return 0;
}

int DC21X4AutoSense(void *adapter)
{
    return 0;
}

void DC21X4DisableInterrupt(void *adapter)
{
}

void DC21X4DisableNway(void *adapter)
{
}

int DC21X4DynamicAutoSense(void *adapter)
{
    return 0;
}

void DC21X4EnableInterrupt(void *adapter)
{
}

void DC21X4EnableNway(void *adapter)
{
}

void DC21X4IndicateMediaStatus(void *adapter, int status)
{
}

void DC21X4InitializeGepRegisters(void *adapter)
{
}

void DC21X4InitializeMediaRegisters(void *adapter)
{
}

int DC21X4MediaDetect(void *adapter)
{
    return 0;
}

int DC21X4ParseExtendedBlock(void *adapter, unsigned char *block)
{
    return 0;
}

int DC21X4ParseFixedBlock(void *adapter, unsigned char *block)
{
    return 0;
}

int DC21X4ParseSRom(void *adapter)
{
    return 0;
}

int DC21X4PhyInit(void *adapter)
{
    return 0;
}

void DC21X4SetPhyConnection(void *adapter, int connection)
{
}

void DC21X4SetPhyControl(void *adapter, int control)
{
}

int DC21X4StartAdapter(void *adapter)
{
    return 0;
}

void DC21X4StartAutoSenseTimer(void *adapter, int timeout)
{
}

void DC21X4StartTimer(void *adapter, int timeout)
{
}

void DC21X4StopAdapter(void *adapter)
{
}

void DC21X4StopAutoSenseTimer(void *adapter)
{
}

void DC21X4StopReceiverAndTransmitter(void *adapter)
{
}

int DC21X4SwitchMedia(void *adapter, int mediaType)
{
    return 0;
}

void DC21X4WriteGepRegister(void *adapter, int value)
{
}

int GetBroadcomPhyConnectionType(void *adapter)
{
    return 0;
}

const char *getDriverName(void)
{
    return "DEC21X4X";
}

void HandleBroadcomMediaChangeFrom10To100(void *adapter)
{
}

void HandleGepInterrupt(void *adapter)
{
}

void HandleLinkChangeInterrupt(void *adapter)
{
}

void HandleLinkFailInterrupt(void *adapter)
{
}

void HandleLinkPassInterrupt(void *adapter)
{
}

void InitPhyInfoEntries(void *adapter)
{
}

void mediaTimeoutOccurred(void *adapter)
{
}

void scheduleFunc(void *adapter, void *func, int timeout)
{
    // Schedule a callback function with timeout in milliseconds
    // Convert timeout from milliseconds to nanoseconds (multiply by 1000000)
    // Last parameter 4 is the priority level
    ns_timeout(adapter, func, (long long)timeout * 1000000, 4);
}

void SelectNonMiiPort(void *adapter)
{
    unsigned int newCsr6;
    unsigned int currentCsr6;
    int connectionIndex;
    unsigned int connectionBits;
    unsigned short csr6Port;

    // TODO: Get current CSR6 value from offset 0x68
    currentCsr6 = *(unsigned int *)(adapter + 0x68);

    // TODO: Get connection index from offset 0x84
    connectionIndex = *(int *)(adapter + 0x84);

    // TODO: Get connection-specific bits from table at offset 0xd8
    // Each connection has a 0x20-byte entry
    connectionBits = *(unsigned int *)((connectionIndex * 0x20) + 0xd8 + (int)adapter);

    // Clear specific CSR6 bits and OR in connection-specific bits
    // Mask 0xfc333dff clears various control bits
    newCsr6 = (currentCsr6 & 0xfc333dff) | connectionBits;

    // Check if critical bits changed (bits 21, 22, 9)
    if ((newCsr6 & 0x600200) != (currentCsr6 & 0x600200)) {
        // Stop receiver and transmitter before changing
        DC21X4StopReceiverAndTransmitter(adapter);
    }

    // TODO: Store updated CSR6 value at offset 0x68
    *(unsigned int *)(adapter + 0x68) = newCsr6;

    // TODO: Get CSR6 port from offset 0x24
    csr6Port = *(unsigned short *)(adapter + 0x24);

    // Write CSR6 value to hardware
    outl(csr6Port, newCsr6);

    // Initialize media-specific registers
    DC21X4InitializeMediaRegisters(adapter, 0);

    // Indicate media status for specific connection types
    if ((connectionIndex < 3) && (connectionIndex > 0)) {
        DC21X4IndicateMediaStatus(adapter, 1);
    }
}

int sendPacket(void *adapter, void *packet, int length)
{
    id driverInstance;

    // TODO: Get driver instance from offset 0x278
    driverInstance = *(id *)(adapter + 0x278);

    // Call the driver's sendPacket:length: method via objc_msgSend
    return objc_msgSend(driverInstance,
                        @selector(sendPacket:length:),
                        packet,
                        length);
}

void SetMacConnection(void *adapter)
{
    unsigned short mediaBit;
    unsigned int csr6Value;
    unsigned char currentMediaIndex;
    int chipRevision;
    unsigned short phyMediaSupport;
    int phyIndex;
    unsigned short csr6Port;

    // TODO: Get current media index from offset 0x1f8
    currentMediaIndex = *(unsigned char *)(adapter + 0x1f8);

    // Get media bit from MediaBitTable
    mediaBit = MediaBitTable[currentMediaIndex];

    if (mediaBit != 0) {
        // TODO: Get current CSR6 value from offset 0x68
        csr6Value = *(unsigned int *)(adapter + 0x68);

        // TODO: Check if MII PHY present at offset 0x1f0
        if ((*(char *)(adapter + 0x1f0) == 0) || ((mediaBit & 0x6000) != 0)) {
            // No MII or media is 100Base-TX/T4 - set both transmit threshold bits
            csr6Value = csr6Value | 0xc0000;
        }
        else {
            // MII present - set one threshold bit, clear the other
            csr6Value = (csr6Value & 0xfffbffff) | 0x80000;
        }

        // TODO: Get PHY index from offset 500
        phyIndex = *(int *)(adapter + 500);

        // TODO: Get PHY media support from PHY structure at offset 0x23c
        phyMediaSupport = *(unsigned short *)((phyIndex * 0x30) + 0x23c + (int)adapter);

        // Check if PHY supports this media or MII not present
        if (((phyMediaSupport & mediaBit) != 0) || (*(char *)(adapter + 0x1f0) != 0)) {
            // Check for full duplex media (bits 12, 14)
            if ((mediaBit & 0x5000) == 0) {
                // Half duplex - clear full duplex bit (bit 9)
                csr6Value = csr6Value & 0xfffffdff;
            }
            else {
                // Full duplex - set full duplex bit (bit 9)
                csr6Value = csr6Value | 0x200;
            }

            // Check for 10Mbps media (bits 11, 12)
            if ((mediaBit & 0x1800) == 0) {
                // TODO: Get scrambler disable bits from offsets 0x6c and 0x70
                // 10Mbps - clear port select, apply scrambler disable
                csr6Value = (csr6Value & ~(*(unsigned int *)(adapter + 0x6c) | 0x400000)) |
                           *(unsigned int *)(adapter + 0x70);
            }
            else {
                // 100Mbps - set port select (bit 22), apply scrambler enable
                csr6Value = (csr6Value & ~*(unsigned int *)(adapter + 0x70)) |
                           0x400000 | *(unsigned int *)(adapter + 0x6c);
            }
        }

        // Indicate media status to network layer
        DC21X4IndicateMediaStatus(adapter, 0);

        // Check if critical bits changed (bits 21, 22, 9)
        if ((csr6Value & 0x600200) != (*(unsigned int *)(adapter + 0x68) & 0x600200)) {
            // Stop receiver and transmitter before changing
            DC21X4StopReceiverAndTransmitter(adapter);
        }

        // TODO: Get chip revision from offset 0x54
        chipRevision = *(int *)(adapter + 0x54);

        // Special initialization for DC21143 variants
        if ((chipRevision == 0x191011) || (chipRevision == 0xff1011)) {
            DC2104InitializeSiaRegisters(adapter);
        }

        // TODO: Store updated CSR6 value at offset 0x68
        *(unsigned int *)(adapter + 0x68) = csr6Value;

        // TODO: Get CSR6 port from offset 0x24
        csr6Port = *(unsigned short *)(adapter + 0x24);

        // Write CSR6 value to hardware
        outl(csr6Port, csr6Value);

        // Delay 5 microseconds
        IODelay(5);

        // Initialize GEP registers
        DC21X4InitializeGepRegisters(adapter, 1);
    }
}

void SRomLocalAdvertisement(void *adapter, unsigned char mediaType)
{
    // Set SROM local advertisement bits based on media type
    // Updates adapter info at offsets 0x5c and 0x60

    switch (mediaType) {
    case 0:
        // Media type 0
        // Set bit 6 in byte at offset 0x5c (0x40)
        *(unsigned char *)(adapter + 0x5c) |= 0x40;
        // Set bit 21 in dword at offset 0x60 (0x200000)
        *(unsigned int *)(adapter + 0x60) |= 0x200000;
        break;

    case 3:
        // Media type 3: 100BaseTX
        // Set bits 16 and 19 in dword at offset 0x5c (0x810000)
        *(unsigned int *)(adapter + 0x5c) |= 0x810000;
        // Set bit 23 in dword at offset 0x60 (0x800000)
        *(unsigned int *)(adapter + 0x60) |= 0x800000;
        break;

    case 4:
        // Media type 4: 10BaseT Full Duplex
        // Set bits 6 and 9 in word at offset 0x5c (0x240)
        *(unsigned int *)(adapter + 0x5c) |= 0x240;
        // Set bit 22 in dword at offset 0x60 (0x400000)
        *(unsigned int *)(adapter + 0x60) |= 0x400000;
        break;

    case 5:
        // Media type 5: 100BaseTX Full Duplex
        // Set bits 9, 17, and 19 in dword at offset 0x5c (0x820200)
        *(unsigned int *)(adapter + 0x5c) |= 0x820200;
        // Set bit 24 in dword at offset 0x60 (0x1000000)
        *(unsigned int *)(adapter + 0x60) |= 0x1000000;
        break;

    case 6:
        // Media type 6: 100BaseT4
        // Set bits 18 and 19 in dword at offset 0x5c (0x840000)
        *(unsigned int *)(adapter + 0x5c) |= 0x840000;
        // Set bit 25 in dword at offset 0x60 (0x2000000)
        *(unsigned int *)(adapter + 0x60) |= 0x2000000;
        break;

    default:
        // Unknown media type - do nothing
        break;
    }
}

void SwitchMediumToTpNway(void *adapter)
{
    unsigned int timerHandle;

    // TODO: Get timer handle from offset 0x220
    timerHandle = *(unsigned int *)(adapter + 0x220);

    // If timer is running, stop it
    if (timerHandle != 0) {
        DC21X4StopAutoSenseTimer(adapter);
    }

    // Switch to TP (10Base-T) media with N-Way auto-negotiation (0x100)
    DC21X4SwitchMedia(adapter, 0x100);

    // TODO: Clear field at offset 0x218
    *(unsigned int *)(adapter + 0x218) = 0;

    // TODO: Set field at offset 0x20c to 0x28 (40 decimal)
    *(unsigned int *)(adapter + 0x20c) = 0x28;

    // TODO: Set timer handle at offset 0x220 to 6
    *(unsigned int *)(adapter + 0x220) = 6;

    // Start timer with 100ms timeout
    DC21X4StartTimer(adapter, 100);
}

void unscheduleFunc(void *adapter, void *function)
{
    // Cancel a previously scheduled timer callback
    // Wrapper around ns_untimeout system call
    ns_untimeout(adapter, function);
}

int VerifyChecksum(unsigned char *srom, int length)
{
    unsigned int checksum;
    unsigned int index;
    unsigned short word;
    unsigned short storedChecksum;

    // Calculate checksum over first 3 words (6 bytes) of SROM
    checksum = 0;
    index = 0;

    do {
        // Multiply checksum by 2 (left shift with carry)
        checksum = checksum * 2;

        // If > 0xffff, subtract 0xffff (modulo arithmetic)
        if (checksum > 0xffff) {
            checksum = checksum - 0xffff;
        }

        // Read next word (big-endian: high byte at lower address)
        word = (srom[index * 2] << 8) | srom[index * 2 + 1];

        // Add word to checksum
        checksum = checksum + word;

        // If > 0xffff, subtract 0xffff
        if (checksum > 0xffff) {
            checksum = checksum - 0xffff;
        }

        index++;
    } while (index < 3);

    // If >= 0xffff, set to 0
    if (checksum > 0xfffe) {
        checksum = 0;
    }

    // Get stored checksum at offset 6 (byte-swapped)
    storedChecksum = (srom[6] << 8) | srom[7];

    // Compare computed checksum (byte-swapped) with stored checksum
    // Byte-swap the computed checksum for comparison
    return storedChecksum == ((checksum << 8) | (checksum >> 8));
}

/*
 * mediaTimeoutOccurred
 * Handle media timeout event - performs dynamic auto-sense
 *
 * Parameters:
 *   adapter - Adapter info structure
 */
void mediaTimeoutOccurred(int adapter)
{
    void *driverObject;

    // Get driver object from offset 0x278
    driverObject = *(void **)(adapter + 0x278);

    // Reserve debugger lock before modifying state
    objc_msgSend(driverObject, "reserveDebuggerLock");

    // Perform dynamic auto-sense
    DC21X4DynamicAutoSense(0, adapter, 0, 0);

    // Release debugger lock
    objc_msgSend(driverObject, "releaseDebuggerLock");
}

/*
 * HandleLinkPassInterrupt
 * Handle Link Pass interrupt for various chip types
 *
 * Parameters:
 *   adapter - Adapter info structure
 *   csrValue - Pointer to CSR status value (bit 27 will be cleared)
 *
 * This function handles link state changes for different chip revisions
 * and manages the auto-sense state machine.
 */
void HandleLinkPassInterrupt(int adapter, unsigned int *csrValue)
{
    unsigned int chipRevision;
    unsigned int mediaState;
    int connectionIndex;
    unsigned short csrReadValue;
    unsigned int maskedValue;
    int targetConnectionIndex;
    int timerState;

    // Clear Link Pass interrupt bit (bit 27)
    *csrValue = *csrValue & 0xf7ffffff;

    // Get chip revision from offset 0x54
    chipRevision = *(unsigned int *)(adapter + 0x54);

    // Handle specific chip revisions (DC21140/DC21142/DC21143)
    if ((chipRevision == 0x191011) || (chipRevision == 0x141011) || (chipRevision == 0xff1011)) {
        // Get media state from offset 0x260
        mediaState = *(unsigned int *)(adapter + 0x260);

        if (mediaState == 2) {
            // State 2: Link check in progress
            if (*(char *)(adapter + 4) != 0) {
                // Auto-sense enabled
                if (*(int *)(adapter + 0x220) != 0) {
                    DC21X4StopAutoSenseTimer(adapter);
                }
                // Set timer state to 3
                *(int *)(adapter + 0x220) = 3;
                DC21X4StartTimer(adapter, 1000);
                return;
            }

            // Check current connection
            if (*(int *)(adapter + 0x84) == 0) {
                if (*(char *)(adapter + 0x1e6) != 0) {
                    // Flag at 0x1e8
                    *(char *)(adapter + 0x1e8) = 1;
                    return;
                }
                DC21X4IndicateMediaStatus(adapter, 1);
                return;
            }

            // Check bit 3 of byte at offset 0x79
            if ((*(unsigned char *)(adapter + 0x79) & 8) == 0) {
                return;
            }

            if ((*(int *)(adapter + 0x220) != 0) && (*(char *)(adapter + 0x1e6) == 0)) {
                DC21X4StopAutoSenseTimer(adapter);
            }

            DC21X4SwitchMedia(adapter, 0);
        }
        else if (mediaState < 3) {
            if (mediaState == 1) {
                // State 1: Link up
                if (*(int *)(adapter + 0x220) == 6) {
                    return;
                }

                if ((*(int *)(adapter + 0x84) == 0) && (*(char *)(adapter + 0x1f1) == 0)) {
                    DC21X4IndicateMediaStatus(adapter, 1);
                }
                else {
                    SwitchMediumToTpNway(adapter);
                }

                // Clear flag at 0x1f1
                *(char *)(adapter + 0x1f1) = 0;
                return;
            }

            // State 0: Link down - common handler
            goto handle_link_down;
        }
        else if (mediaState == 3) {
            // State 3: Auto-sense active
            if (*(char *)(adapter + 4) == 0) {
                // Auto-sense disabled
                if (*(int *)(adapter + 0x84) == 0) {
                    return;
                }
                DC21X4SwitchMedia(adapter, 0);
                DC21X4IndicateMediaStatus(adapter, 1);
                return;
            }

            // Auto-sense enabled - check timer
            if (*(int *)(adapter + 0x220) != 0) {
                DC21X4StopAutoSenseTimer(adapter);
            }

            // Read CSR at offset 0x3c
            csrReadValue = inw(*(unsigned short *)(adapter + 0x3c));

            connectionIndex = *(int *)(adapter + 0x84);

            if ((short)csrReadValue < 0) {
                // Bit 15 set - check media type bits
                maskedValue = csrReadValue & *(unsigned int *)(adapter + 0x60);

                if ((maskedValue & 0x2000000) != 0) {
                    // 100BaseTX full-duplex
                    targetConnectionIndex = 6;
                    timerState = 5;
                }
                else if ((maskedValue & 0x1000000) != 0) {
                    // 100BaseTX
                    targetConnectionIndex = 5;
                    timerState = 5;
                }
                else if ((maskedValue & 0x800000) != 0) {
                    // 10BaseT full-duplex
                    targetConnectionIndex = 3;
                    timerState = 5;
                }
                else if ((maskedValue & 0x600000) != 0) {
                    // 10BaseT or another mode
                    if (*(int *)(adapter + 0x84) != 0) {
                        targetConnectionIndex = 0;
                        timerState = 2;
                    }
                    else {
                        targetConnectionIndex = 4;
                        goto set_timer;
                    }
                }
                else {
                    // No valid connection
                    targetConnectionIndex = 0xff;
                    goto check_connection_change;
                }

                // Set timer
                *(int *)(adapter + 0x220) = timerState;
                DC21X4StartTimer(adapter, (timerState == 2) ? 5000 : 1000);
            }
            else if ((csrReadValue & 2) == 0) {
                // Bit 1 clear
                targetConnectionIndex = 3;
            }
            else {
                // Bit 1 set
                if (*(int *)(adapter + 0x84) != 0) {
                    targetConnectionIndex = 0;
                    timerState = 2;
                    goto set_timer;
                }
                DC21X4IndicateMediaStatus(adapter, 1);
            }

set_timer:
check_connection_change:
            // Switch media if connection changed
            if (*(int *)(adapter + 0x84) != targetConnectionIndex) {
                DC21X4SwitchMedia(adapter, targetConnectionIndex);
            }
            return;
        }
        else {
            // Other states - common handler
handle_link_down:
            if (*(int *)(adapter + 0x84) == 0) {
                if (*(char *)(adapter + 0x1e6) != 0) {
                    *(char *)(adapter + 0x1e8) = 1;
                    return;
                }
            }
            DC21X4IndicateMediaStatus(adapter, 1);
        }
    }
    else {
        // Other chip revisions - just indicate media status
        DC21X4IndicateMediaStatus(adapter, 1);
    }
}

/*
 * HandleLinkFailInterrupt
 * Handle Link Fail interrupt for various chip types
 *
 * Parameters:
 *   adapter - Adapter info structure
 *   csrValue - Pointer to CSR status value (bits will be cleared)
 *
 * This function handles link failure events and manages media switching
 * and auto-sense timers.
 */
void HandleLinkFailInterrupt(int adapter, unsigned int *csrValue)
{
    unsigned char flagValue;
    unsigned int chipRevision;
    unsigned int mediaState;
    unsigned int csrReadValue;

    // If non-MII port (connection index != 0), return
    if (*(int *)(adapter + 0x84) != 0) {
        return;
    }

    // Check if PHY is present flag at offset 0x1e6
    if (*(char *)(adapter + 0x1e6) != 0) {
        // Set PHY control to restore (command 6)
        DC21X4SetPhyControl(adapter, 6);
    }

    // Get chip revision from offset 0x54
    chipRevision = *(unsigned int *)(adapter + 0x54);

    // Handle DC21040 (revision 0x21011)
    if (chipRevision == 0x21011) {
        DC21X4IndicateMediaStatus(adapter, 0);
        // Clear link pass and link fail interrupt bits (bits 27 and 4)
        *csrValue = *csrValue & 0xf7ffffef;
        DC21X4StartAutoSenseTimer(adapter, 3000);
        return;
    }

    // Handle DC21140/DC21142/DC21143
    if (chipRevision < 0x141012) {
        return;  // Unknown revision
    }

    if ((chipRevision != 0x141011) && (chipRevision != 0x191011) && (chipRevision != 0xff1011)) {
        return;  // Not a supported chip for this handler
    }

    // Clear flag at offset 0x1e8
    *(char *)(adapter + 0x1e8) = 0;

    // Get media state from offset 0x260
    mediaState = *(unsigned int *)(adapter + 0x260);

    if (mediaState == 2) {
        // State 2: Link check in progress
        DC21X4IndicateMediaStatus(adapter, 0);
        // Clear link pass and link fail interrupt bits
        *csrValue = *csrValue & 0xf7ffffef;

        // Check bit 3 of byte at offset 0x79
        if ((*(unsigned char *)(adapter + 0x79) & 8) != 0) {
            goto setup_timer;
        }

        // Check auto-sense flag at offset 4
        flagValue = *(unsigned char *)(adapter + 4);
    }
    else if (mediaState < 3) {
        if (mediaState == 1) {
            // State 1: Link up - now failed
            DC21X4IndicateMediaStatus(adapter, 0);
            *csrValue = *csrValue & 0xf7ffffef;

            // Check flag at offset 0x1eb
            if (*(char *)(adapter + 0x1eb) != 0) {
                return;
            }

            // Check auto-sense enabled
            if (*(char *)(adapter + 4) == 0) {
                return;
            }

            SwitchMediumToTpNway(adapter);
            return;
        }

        // State 0 or other - fall through
        DC21X4IndicateMediaStatus(adapter, 0);
        *csrValue = *csrValue & 0xf7ffffef;

        // Check bit 3 of byte at offset 0x79
        if ((*(unsigned char *)(adapter + 0x79) & 8) != 0) {
            DC21X4SwitchMedia(adapter, 0xff);
            return;
        }

        // Check bit 0 of byte at offset 0x79
        flagValue = *(unsigned char *)(adapter + 0x79) & 1;
    }
    else if (mediaState == 3) {
        // State 3: Auto-sense active
        // Read CSR at offset 0x3c
        csrReadValue = inw(*(unsigned short *)(adapter + 0x3c));

        // Check bit 0 of offset 0x79 and CSR bits
        if (((*(unsigned char *)(adapter + 0x79) & 1) != 0) &&
            ((csrReadValue & 0x7000) != 0x1000)) {
            return;
        }

        DC21X4IndicateMediaStatus(adapter, 0);
        *csrValue = *csrValue & 0xf7ffffef;

        // Check bit 3 of byte at offset 0x79
        if ((*(unsigned char *)(adapter + 0x79) & 8) != 0) {
            DC21X4SwitchMedia(adapter, 0xff);
            return;
        }

        // Check bit 0 of byte at offset 0x79
        flagValue = *(unsigned char *)(adapter + 0x79) & 1;
    }
    else {
        // Unknown state
        DC21X4IndicateMediaStatus(adapter, 0);
        *csrValue = *csrValue & 0xf7ffffef;

        // Check bit 3 of byte at offset 0x79
        if ((*(unsigned char *)(adapter + 0x79) & 8) != 0) {
            DC21X4SwitchMedia(adapter, 0xff);
            return;
        }

        flagValue = *(unsigned char *)(adapter + 0x79) & 1;
    }

    // If flag is not set, return
    if (flagValue == 0) {
        return;
    }

setup_timer:
    // Stop existing timer if active
    if (*(int *)(adapter + 0x220) != 0) {
        DC21X4StopAutoSenseTimer(adapter);
    }

    // Set timer state to 2
    *(int *)(adapter + 0x220) = 2;

    // Start 5 second timer
    DC21X4StartTimer(adapter, 5000);
}

/*
 * HandleLinkChangeInterrupt
 * Handle Link Change interrupt (for 21142/21143)
 *
 * Parameters:
 *   adapter - Adapter info structure
 *
 * This function handles link state changes detected by the chip
 * and switches media or indicates status accordingly.
 */
void HandleLinkChangeInterrupt(int adapter)
{
    unsigned int csrValue;
    BOOL linkUp;
    unsigned int targetConnection;

    // Read CSR at offset 0x3c
    csrValue = inw(*(unsigned short *)(adapter + 0x3c));

    // Extract bit 1 (link status)
    linkUp = (csrValue & 2) != 0;

    // Get media state from offset 0x260
    if (*(int *)(adapter + 0x260) == 3) {
        // State 3: Auto-sense active
        // Clear flag at offset 0x1e8
        *(char *)(adapter + 0x1e8) = 0;

        // Check timer state - if 4 or 5, return
        if ((unsigned int)(*(int *)(adapter + 0x220) - 4) < 2) {
            return;
        }

        // If no link, return
        if (!linkUp) {
            return;
        }

        // Stop auto-sense timer
        if (*(int *)(adapter + 0x220) != 0) {
            DC21X4StopAutoSenseTimer(adapter);
        }

        // Switch to invalid connection (will auto-detect)
        targetConnection = 0xff;
    }
    else {
        // Check bit 3 of byte at offset 0x79
        if ((*(unsigned char *)(adapter + 0x79) & 8) == 0) {
            // Simple link status indication
            DC21X4IndicateMediaStatus(adapter, linkUp);
            return;
        }

        // Complex media switching
        if (!linkUp) {
            // Link down
            if (*(int *)(adapter + 0x84) == 3) {
                // Currently on connection 3 - indicate link up?
                DC21X4IndicateMediaStatus(adapter, TRUE);
                return;
            }
            // Switch to connection 3
            targetConnection = 3;
        }
        else {
            // Link up - switch to invalid (auto-detect)
            targetConnection = 0xff;
        }
    }

    // Switch media
    DC21X4SwitchMedia(adapter, targetConnection);
}

/*
 * HandleGepInterrupt
 * Handle GEP (General Purpose Port) interrupt
 *
 * Parameters:
 *   adapter - Adapter info structure
 *
 * This function handles GEP interrupts which can indicate PHY
 * link changes or other hardware events.
 */
void HandleGepInterrupt(int adapter)
{
    char phyInitSuccess;
    unsigned int gepValue;
    int currentPhyIndex;
    unsigned int interruptMask;

    // Read GEP register at CSR offset 0x48 (CSR15)
    gepValue = inw(*(unsigned short *)(adapter + 0x48));

    // Get current PHY index from offset 500 (0x1f4)
    currentPhyIndex = *(int *)(adapter + 500);

    // Get interrupt mask from PHY-specific structure
    // Structure is 0x30 bytes per PHY, mask at offset 0x25c in adapter + PHY offset
    interruptMask = *(unsigned int *)((currentPhyIndex * 0x30) + 0x25c + adapter);

    // Check if any relevant GEP bits are set
    if (((gepValue & interruptMask) != 0) && (*(char *)(adapter + 0x1e5) != 0)) {
        // Indicate link down
        DC21X4IndicateMediaStatus(adapter, 0);

        // Reinitialize PHY
        phyInitSuccess = DC21X4PhyInit(adapter);
        *(char *)(adapter + 0x1e6) = phyInitSuccess;

        if (phyInitSuccess != 0) {
            // PHY initialized successfully
            // Check if manual media mode and MII 10BaseT supported
            if ((*(char *)(adapter + 0x1f0) != 0) &&
                ((*(unsigned char *)(adapter + 0x1f9) & 8) != 0)) {
                // Clear upper byte and set to 9 (MII 10BaseT)
                *(unsigned int *)(adapter + 0x1f8) = *(unsigned int *)(adapter + 0x1f8) & 0xff00;
                *(unsigned char *)(adapter + 0x1f8) = *(unsigned char *)(adapter + 0x1f8) | 9;
                *(int *)(adapter + 0x84) = 0;
            }

            // Set PHY connection
            DC21X4SetPhyConnection(adapter);

            // Check if N-Way should be disabled
            if ((*(char *)(adapter + 0x1e7) != 0) &&
                ((*(unsigned char *)(adapter + 0x79) & 1) != 0)) {
                DC21X4DisableNway(adapter);
            }

            // Start auto-sense timer (100ms)
            DC21X4StartAutoSenseTimer(adapter, 100);
        }
    }
}

/*
 * getDriverName
 * Get driver name string
 *
 * Parameters:
 *   adapter - Adapter info structure
 *
 * Returns:
 *   Driver name string (const char *)
 *
 * Retrieves the driver name from the driver object using Objective-C
 * message passing.
 */
const char *getDriverName(int adapter)
{
    void *driverObject;

    // Get driver object from offset 0x278
    driverObject = *(void **)(adapter + 0x278);

    // Send "name" message to driver object
    return (const char *)objc_msgSend(driverObject, "name");
}

/*
 * DC21X4WriteGepRegister
 * Write to GEP (General Purpose Port) register
 *
 * Parameters:
 *   adapter - Adapter info structure
 *   value - Value to write to GEP register
 *
 * Returns:
 *   Combined 64-bit value (implementation detail)
 *
 * Writes to the GEP register with chip-specific handling.
 * DC21142/DC21143 use CSR15 at offset 0x48, other chips use CSR12 at offset 0x3c.
 */
unsigned long long DC21X4WriteGepRegister(int adapter, unsigned int value)
{
    int chipRevision;
    unsigned int combinedValue;
    unsigned short portAddress;
    unsigned int writeValue;

    // Get chip revision from offset 0x54
    chipRevision = *(int *)(adapter + 0x54);

    // Check if DC21142 or DC21143
    if ((chipRevision == 0x191011) || (chipRevision == 0xff1011)) {
        // DC21142/DC21143 specific handling
        // Delay 100 microseconds
        IODelay(100);

        // Combine lower 16 bits from offset 0x58 with value shifted left 16 bits
        combinedValue = (unsigned int)(*(unsigned short *)(adapter + 0x58)) | (value << 16);

        // Store combined value back to offset 0x58
        *(unsigned int *)(adapter + 0x58) = combinedValue;

        // Get CSR15 port address (offset 0x48)
        portAddress = *(unsigned short *)(adapter + 0x48);

        writeValue = combinedValue;
    }
    else {
        // Other chip revisions
        // Get CSR12 port address (offset 0x3c)
        portAddress = *(unsigned short *)(adapter + 0x3c);

        writeValue = value;
    }

    // Write to hardware register
    outl(portAddress, writeValue);

    // LOCK/UNLOCK mechanism - appears to be for debugging/profiling
    // Increments global counter under lock
    // TODO: LOCK();
    // TODO: __xxx.92 = __xxx.92 + 1;
    // TODO: UNLOCK();

    // Return combined 64-bit value (port address in upper 32 bits, value in lower 32 bits)
    return ((unsigned long long)portAddress << 32) | writeValue;
}

/*
 * DC21X4SwitchMedia
 * Switch to a different media/connection type
 *
 * Parameters:
 *   adapter - Adapter info structure
 *   connectionType - Target connection type (0-6, 0xff for auto, 0x100 for AUI)
 *
 * Returns:
 *   CSR6 register value or status
 *
 * This is the main media switching function that handles all chip variants
 * and connection types. It configures the appropriate registers for the
 * selected media type.
 */
unsigned int DC21X4SwitchMedia(unsigned int adapter, unsigned int connectionType)
{
    BOOL enableAutoSense;
    unsigned int returnValue;
    int connectionOffset;
    unsigned int chipRevision;
    unsigned int loopCount;
    unsigned int csrReadValue;
    unsigned int miiConnectionType;
    unsigned int duplexFlag;
    unsigned char autoSenseFlag;

    autoSenseFlag = 0;
    duplexFlag = 0;
    enableAutoSense = FALSE;

    // Indicate media status change
    returnValue = DC21X4IndicateMediaStatus(adapter, 0);

    // Handle auto-detect (0xff) with single media type
    if ((connectionType == 0xff) &&
        ((*(unsigned int *)(adapter + 0x7c) & 7) == 1)) {
        connectionType = 0;
    }

    // Get chip revision
    chipRevision = *(unsigned int *)(adapter + 0x54);

    // Handle DC21040 (revision 0x91011)
    if (chipRevision == 0x91011) {
        // Clear and set connection-specific CSR6 bits
        *(unsigned int *)(adapter + 0x68) = *(unsigned int *)(adapter + 0x68) & 0xfc333dff;
        *(unsigned int *)(adapter + 0x68) =
            *(unsigned int *)(adapter + 0x68) |
            *(unsigned int *)((connectionType * 0x20) + 0xd8 + adapter);

        // Store connection type
        *(unsigned int *)(adapter + 0x84) = connectionType;

        // Write to CSR12 (SIA status register)
        outl(*(unsigned short *)(adapter + 0x3c),
             *(unsigned int *)((connectionType * 0x20) + 200 + adapter));

        // Write CSR6
        outl(*(unsigned short *)(adapter + 0x24), *(unsigned int *)(adapter + 0x68));

        // Delay loop (200 * 1000 microseconds = 200ms)
        loopCount = 0;
        do {
            IODelay(1000);
            loopCount = loopCount + 1;
        } while (loopCount < 200);

        // Read CSR12 and check for link
        csrReadValue = inl(*(unsigned short *)(adapter + 0x3c));
        connectionOffset = *(int *)(adapter + 0x84) * 0x20;

        enableAutoSense =
            ((*(unsigned int *)(connectionOffset + 0xe0 + adapter) &
              (csrReadValue ^ *(unsigned int *)(connectionOffset + 0xdc + adapter))) != 0);

        goto indicate_status;
    }

    // Handle DC21142/DC21143 with MII PHY
    if ((chipRevision == 0x191011) || (chipRevision == 0xff1011)) {
        if (*(char *)(adapter + 0x1e6) != 0) {
            // PHY present - convert connection type to MII type
            miiConnectionType = ConvertMediaTypeToMiiType[connectionType & 0xff] |
                                (connectionType & 0xff00);

            // Check if MII connection is supported
            returnValue = MiiGenCheckConnection(adapter, miiConnectionType);

            if ((char)returnValue != 0) {
                // Supported - set up MII connection
                *(unsigned int *)(adapter + 0x84) = connectionType;
                *(unsigned int *)(adapter + 0x1f8) = miiConnectionType;

                DC21X4SetPhyConnection(adapter);
                DC21X4StartAutoSenseTimer(adapter, 7000);
                return returnValue;
            }
        }

        // No PHY or not supported - use non-MII port
        enableAutoSense = TRUE;
    }
    else if (chipRevision != 0x141011) {
        // Unknown chip revision
        return returnValue;
    }
    else {
        // DC21140 - use non-MII port
        enableAutoSense = TRUE;
    }

    // Handle specific connection types
    if (connectionType == 4) {
        // 10Base2 (BNC)
        duplexFlag = 0x200;
        goto setup_connection_type_4;
    }

    if ((int)connectionType < 5) {
        if (connectionType == 1) {
            // 10Base5 (AUI)
            autoSenseFlag = *(unsigned char *)(adapter + 0x7c) & 4;
        }
        else if ((int)connectionType < 2) {
            if (connectionType == 0) {
                // 10BaseT
                goto setup_connection_type_4;
            }
        }
        else if (connectionType == 2) {
            // 10BaseT alternative
            autoSenseFlag = *(unsigned char *)(adapter + 0x7c) & 2;
        }
        else if (connectionType == 3) {
            // Full-duplex
            goto setup_connection_type_3_5_6;
        }

        goto setup_other_connection;
    }

    if (connectionType != 6) {
        if ((int)connectionType > 5) {
            if (connectionType == 0xff) {
                // Auto-detect based on supported media mask
                csrReadValue = *(unsigned int *)(adapter + 0x7c) & 6;

                if (csrReadValue == 4) {
                    connectionType = 2;
                }
                else if (csrReadValue < 5) {
                    if (csrReadValue != 2) {
                        // MII PHY handling
                        if (*(char *)(adapter + 0x1e6) == 0) {
                            return returnValue;
                        }
                        DC21X4StartAutoSenseTimer(adapter, 7000);
                        return returnValue;
                    }
                    connectionType = 1;
                }
                else {
                    if (csrReadValue != 6) {
                        if (*(char *)(adapter + 0x1e6) == 0) {
                            return returnValue;
                        }
                        DC21X4StartAutoSenseTimer(adapter, 7000);
                        return returnValue;
                    }

                    // Check CSR12 bit 9 to determine connection
                    csrReadValue = inw(*(unsigned short *)(adapter + 0x3c));
                    connectionType = 1;
                    if ((csrReadValue & 0x200) != 0) {
                        connectionType = 2;
                    }
                    autoSenseFlag = 1;
                }
            }
            else if (connectionType == 0x100) {
                // AUI loopback mode
                *(int *)(adapter + 0x84) = 0;
                *(char *)(adapter + 0x1eb) = 1;

                DC21X4StopReceiverAndTransmitter(adapter);

                // Set loopback bits
                *(unsigned char *)(adapter + 0xd0) =
                    *(unsigned char *)(adapter + 0xd0) | 0xc0;

                DC2104InitializeSiaRegisters(adapter);

                // Clear loopback bits
                *(unsigned int *)(adapter + 0xd0) =
                    *(unsigned int *)(adapter + 0xd0) & 0xffffff3f;

                // Enable full-duplex
                returnValue = *(unsigned int *)(adapter + 0x68) | 0x200;
                *(unsigned int *)(adapter + 0x68) = returnValue;

                outl(*(unsigned short *)(adapter + 0x24), returnValue);
                return returnValue;
            }

            goto setup_other_connection;
        }

        // Connection type 5
        duplexFlag = 0x200;
        connectionType = connectionType & 0xff;
    }

setup_connection_type_3_5_6:
    if (enableAutoSense) {
        DC21X4StopReceiverAndTransmitter(adapter);

        // Configure CSR6 for new connection
        *(unsigned int *)(adapter + 0x68) = *(unsigned int *)(adapter + 0x68) & 0xfc333dff;
        connectionOffset = connectionType * 0x20;
        *(unsigned int *)(adapter + 0x68) =
            *(unsigned int *)(adapter + 0x68) | duplexFlag |
            *(unsigned int *)(connectionOffset + 0xd8 + adapter);

        // Write GEP control registers
        DC21X4WriteGepRegister(adapter,
                               *(unsigned int *)(connectionOffset + 0xc4 + adapter));
        DC21X4WriteGepRegister(adapter,
                               *(unsigned int *)(connectionOffset + 200 + adapter));

        // Write CSR13 (SIA connectivity)
        outl(*(unsigned short *)(adapter + 0x40), 0);

        // Delay 10ms
        for (loopCount = 0; loopCount < 10; loopCount++) {
            IODelay(1000);
        }

        // Write CSR14 (SIA transmit/receive)
        outl(*(unsigned short *)(adapter + 0x44),
             *(unsigned int *)((connectionType * 0x20) + 0xd0 + adapter));

        // Write CSR15 (SIA general/watchdog timer)
        returnValue = (*(unsigned int *)(adapter + 0x58) & 0xffff0000) |
                     (unsigned int)(*(unsigned short *)((connectionType * 0x20) + 0xd4 + adapter));
        *(unsigned int *)(adapter + 0x58) = returnValue;
        outl(*(unsigned short *)(adapter + 0x48), returnValue);

        // Write CSR6 with receiver/transmitter stopped
        outl(*(unsigned short *)(adapter + 0x24),
             *(unsigned int *)(adapter + 0x68) & 0xffffdffd);

        // Delay 1ms
        IODelay(1000);

        // Enable receiver/transmitter
        returnValue = *(unsigned int *)(adapter + 0x68);
        outl(*(unsigned short *)(adapter + 0x24), returnValue);
    }

    *(unsigned int *)(adapter + 0x84) = connectionType;

    // Check if in specific timer state
    if (*(int *)(adapter + 0x220) == 5) {
        return returnValue;
    }

    enableAutoSense = TRUE;
    goto indicate_status;

setup_connection_type_4:
    if (enableAutoSense) {
        DC21X4StopReceiverAndTransmitter(adapter);

        *(unsigned int *)(adapter + 0x68) = *(unsigned int *)(adapter + 0x68) & 0xfc333dff;
        connectionOffset = connectionType * 0x20;
        *(unsigned int *)(adapter + 0x68) =
            *(unsigned int *)(adapter + 0x68) | duplexFlag |
            *(unsigned int *)(connectionOffset + 0xd8 + adapter);

        DC21X4WriteGepRegister(adapter,
                               *(unsigned int *)(connectionOffset + 0xc4 + adapter));
        DC21X4WriteGepRegister(adapter,
                               *(unsigned int *)(connectionOffset + 200 + adapter));

        outl(*(unsigned short *)(adapter + 0x24),
             *(unsigned int *)(adapter + 0x68) & 0xffffdffd);

        IODelay(1000);
    }

    *(unsigned int *)(adapter + 0x84) = connectionType;
    returnValue = DC2104InitializeSiaRegisters(adapter);

    if (!enableAutoSense) {
        return returnValue;
    }

    outl(*(unsigned short *)(adapter + 0x24), *(unsigned int *)(adapter + 0x68));
    return *(unsigned int *)(adapter + 0x68);

setup_other_connection:
    if (enableAutoSense) {
        *(unsigned int *)(adapter + 0x68) = *(unsigned int *)(adapter + 0x68) & 0xfc333dff;
        connectionOffset = connectionType * 0x20;
        *(unsigned int *)(adapter + 0x68) =
            *(unsigned int *)(adapter + 0x68) |
            *(unsigned int *)(connectionOffset + 0xd8 + adapter);

        DC21X4WriteGepRegister(adapter,
                               *(unsigned int *)(connectionOffset + 0xc4 + adapter));
        DC21X4WriteGepRegister(adapter,
                               *(unsigned int *)(connectionOffset + 200 + adapter));

        outl(*(unsigned short *)(adapter + 0x24), *(unsigned int *)(adapter + 0x68));
    }

    *(unsigned int *)(adapter + 0x84) = connectionType;
    DC2104InitializeSiaRegisters(adapter);
    returnValue = DC21X4IndicateMediaStatus(adapter, 1);

    if ((autoSenseFlag == 0) && (*(char *)(adapter + 0x1e6) == 0)) {
        return returnValue;
    }

    // Clear auto-sense counters
    *(int *)(adapter + 0x210) = 0;
    *(int *)(adapter + 0x214) = 0;

    // Start auto-sense timer
    if (*(char *)(adapter + 0x1e6) != 0) {
        DC21X4StartAutoSenseTimer(adapter, 7000);
    }
    else {
        DC21X4StartAutoSenseTimer(adapter, 3000);
    }

    return returnValue;

indicate_status:
    returnValue = DC21X4IndicateMediaStatus(adapter, enableAutoSense);
    return returnValue;
}

/*
 * DC21X4StopReceiverAndTransmitter
 * Stop the receiver and transmitter
 *
 * Parameters:
 *   adapter - Adapter info structure
 *
 * Clears the Start Transmit and Start Receiver bits in CSR6
 * and waits for the controller to stop.
 */
void DC21X4StopReceiverAndTransmitter(int adapter)
{
    int loopCount;

    // Write CSR6 with receiver and transmitter stopped (clear bits 1 and 13)
    outl(*(unsigned short *)(adapter + 0x24),
         *(unsigned int *)(adapter + 0x68) & 0xffffdffd);

    // LOCK/UNLOCK mechanism - appears to be for debugging/profiling
    // TODO: LOCK();
    // TODO: __xxx.92 = __xxx.92 + 1;
    // TODO: UNLOCK();

    // Wait loop - read CSR5 (status) 50 times with 2ms delays
    loopCount = 0x31;  // 49 iterations (counts down to -1)
    do {
        // Read CSR5 status register (offset 0x20)
        inl(*(unsigned short *)(adapter + 0x20));

        // Delay 2 milliseconds
        IODelay(2000);

        loopCount = loopCount - 1;
    } while (loopCount != -1);
}

/*
 * DC21X4StopAutoSenseTimer
 * Stop the auto-sense timer
 *
 * Parameters:
 *   adapter - Adapter info structure
 *
 * Cancels any pending auto-sense timer and clears the timer state.
 */
void DC21X4StopAutoSenseTimer(int adapter)
{
    // Clear timer state
    *(int *)(adapter + 0x220) = 0;

    // Cancel scheduled timer callback
    unscheduleFunc(adapter, (void *)mediaTimeoutOccurred);

    // Clear timer active flag
    *(char *)(adapter + 0x1ee) = 0;
}

/*
 * DC21X4StopAdapter
 * Stop the adapter
 *
 * Parameters:
 *   adapter - Adapter info structure
 *
 * Indicates link down and performs a software reset of the controller.
 */
void DC21X4StopAdapter(int adapter)
{
    // Indicate media status down
    DC21X4IndicateMediaStatus(adapter, 0);

    // Write CSR0 (bus mode register) with software reset bit (bit 0)
    outl(*(unsigned short *)(adapter + 0xc), 1);

    // LOCK/UNLOCK mechanism - appears to be for debugging/profiling
    // TODO: LOCK();
    // TODO: __xxx.92 = __xxx.92 + 1;
    // TODO: UNLOCK();

    // Delay 2 milliseconds for reset to complete
    IODelay(2000);
}

/*
 * DC21X4StartTimer
 * Start a timer callback
 *
 * Parameters:
 *   adapter - Adapter info structure
 *   timeout - Timeout in milliseconds
 *
 * Schedules the media timeout callback to fire after the specified delay.
 */
void DC21X4StartTimer(int adapter, int timeout)
{
    // Schedule timer callback
    scheduleFunc(adapter, (void *)mediaTimeoutOccurred, timeout);
}

/*
 * DC21X4StartAutoSenseTimer
 * Start the auto-sense timer
 *
 * Parameters:
 *   adapter - Adapter info structure
 *   timeout - Timeout in milliseconds
 *
 * Sets the auto-sense timer state and schedules the media timeout callback.
 */
void DC21X4StartAutoSenseTimer(int adapter, int timeout)
{
    // Set timer state to 1 (active)
    *(int *)(adapter + 0x220) = 1;

    // Schedule media timeout callback
    scheduleFunc(adapter, (void *)mediaTimeoutOccurred, timeout);
}

/*
 * DC21X4StartAdapter
 * Start the adapter (enable receiver and transmitter)
 *
 * Parameters:
 *   adapter - Adapter info structure
 *
 * Returns:
 *   Combined value (implementation detail)
 *
 * Enables the receiver and transmitter by setting bits in CSR6.
 * Special handling for DC21040 with no media selected.
 */
unsigned long long DC21X4StartAdapter(int adapter)
{
    unsigned int writeValue;
    unsigned short portAddress;

    // Enable receiver and transmitter in CSR6 (set bits 1 and 13)
    *(unsigned int *)(adapter + 0x68) = *(unsigned int *)(adapter + 0x68) | 0x2002;

    // Special case: DC21040 (revision 0x21011) with no media (offset 8 == 0)
    if ((*(int *)(adapter + 0x54) == 0x21011) && (*(int *)(adapter + 8) == 0)) {
        // Write 0 to CSR13 (SIA connectivity)
        outl(*(unsigned short *)(adapter + 0x40), 0);

        // TODO: LOCK();
        // TODO: __xxx.92 = __xxx.92 + 1;
        // TODO: UNLOCK();

        // Delay 1ms
        IODelay(1000);

        // Write CSR6 with full value
        outl(*(unsigned short *)(adapter + 0x24), *(unsigned int *)(adapter + 0x68));

        // TODO: LOCK();
        // TODO: __xxx.92 = __xxx.92 + 1;
        // TODO: UNLOCK();

        // Get CSR13 port and connection-specific value
        portAddress = *(unsigned short *)(adapter + 0x40);
        writeValue = *(unsigned int *)((*(int *)(adapter + 0x84) * 0x20) + 0xcc + adapter);
    }
    else {
        // Standard case: write CSR6 with receiver/transmitter stopped first
        outl(*(unsigned short *)(adapter + 0x24),
             *(unsigned int *)(adapter + 0x68) & 0xffffdffd);

        // TODO: LOCK();
        // TODO: __xxx.92 = __xxx.92 + 1;
        // TODO: UNLOCK();

        // Delay 1ms
        IODelay(1000);

        // Get CSR6 port and full value
        portAddress = *(unsigned short *)(adapter + 0x24);
        writeValue = *(unsigned int *)(adapter + 0x68);
    }

    // Write final value to selected register
    outl(portAddress, writeValue);

    // TODO: LOCK();
    // TODO: __xxx.92 = __xxx.92 + 1;
    // TODO: UNLOCK();

    // Return combined value
    return ((unsigned long long)portAddress << 32) | writeValue;
}

/*
 * DC21X4SetPhyControl
 * Set PHY administrative control
 *
 * Parameters:
 *   adapter - Adapter info structure
 *   control - Control command (0-6)
 *
 * Simple wrapper around MiiGenAdminControl.
 */
void DC21X4SetPhyControl(void *adapter, unsigned short control)
{
    MiiGenAdminControl((int)adapter, control);
}

/*
 * DC21X4SetPhyConnection
 * Configure PHY connection
 *
 * Parameters:
 *   adapter - Adapter info structure
 *
 * Returns:
 *   Success/failure from MII connection setup
 *
 * Sets up both MAC and MII PHY for the selected connection type.
 */
int DC21X4SetPhyConnection(int adapter)
{
    char success;
    int currentPhyIndex;
    unsigned short phyFlags;

    // Configure MAC side
    SetMacConnection((void *)adapter);

    // Get current PHY index from offset 500 (0x1f4)
    currentPhyIndex = *(int *)(adapter + 500);

    // Get PHY flags from PHY-specific structure
    // Structure is 0x30 bytes per PHY, flags at offset 0x23e
    phyFlags = *(unsigned short *)((currentPhyIndex * 0x30) + 0x23e + adapter);

    // Configure MII PHY connection
    success = MiiGenSetConnection(adapter,
                                   *(unsigned int *)(adapter + 0x1f8),
                                   phyFlags);

    return (int)success;
}

/*
 * DC21X4PhyInit
 * Initialize MII PHY
 *
 * Parameters:
 *   adapter - Adapter info structure
 *
 * Returns:
 *   1 if PHY initialized successfully, 0 otherwise
 *
 * Complex PHY initialization including GEP sequence, capability detection,
 * and media type configuration.
 */
int DC21X4PhyInit(int adapter)
{
    unsigned short *phyCapabilitiesPtr;
    char initSuccess;
    char connectionCheckSuccess;
    unsigned short phyCapabilities;
    int result;
    int gepSequenceIndex;
    unsigned short combinedCapabilities;
    unsigned int miiConnectionType;
    int phyIndex;
    int currentPhyIndex;
    unsigned char manualMediaFlag;

    connectionCheckSuccess = 0;

    // Check if MII PHY present flag at offset 0x1e5
    if (*(char *)(adapter + 0x1e5) == 0) {
        return 0;
    }

    // Clear PHY reset flag
    *(char *)(adapter + 0x1e9) = 0;

    // Execute GEP initialization sequence (only one PHY supported currently)
    phyIndex = 0;
    do {
        currentPhyIndex = *(int *)(adapter + 500);

        // Check if GEP sequence count is non-zero
        if (*(int *)((currentPhyIndex * 0x30) + 0x238 + adapter) != 0) {
            // Write initial GEP value
            DC21X4WriteGepRegister(adapter,
                                   *(unsigned short *)((currentPhyIndex * 0x30) + 0x244 + adapter));

            // Execute GEP sequence
            for (gepSequenceIndex = 0;
                 gepSequenceIndex < *(int *)((*(int *)(adapter + 500) * 0x30) + 0x238 + adapter);
                 gepSequenceIndex = gepSequenceIndex + 1) {
                // Delay 10 microseconds between writes
                IODelay(10);

                // Write GEP sequence value
                DC21X4WriteGepRegister(adapter,
                    *(unsigned short *)(adapter + (gepSequenceIndex * 2) + 0x250 +
                                       (*(int *)(adapter + 500) * 0x30)));
            }
        }

        phyIndex = phyIndex + 1;
    } while (phyIndex < 1);

    // Set PHY index to 0
    *(int *)(adapter + 500) = 0;

    // Initialize MII PHY
    initSuccess = MiiGenInit(adapter);

    if (initSuccess != 0) {
        // Get PHY capabilities
        phyCapabilities = MiiGenGetCapabilities(adapter);

        // Determine MII connection type
        if (*(char *)(adapter + 0x1ed) == 0) {
            // Auto mode - default to MII 10BaseT (9)
            miiConnectionType = 9;
        }
        else {
            // Manual mode - convert media type to MII type
            unsigned char mediaType = *(unsigned char *)(adapter + 0x78);
            miiConnectionType = ConvertMediaTypeToMiiType[mediaType] |
                                (*(unsigned int *)(adapter + 0x78) & 0xff00);
        }

        // Store MII connection type
        *(unsigned int *)(adapter + 0x1f8) = miiConnectionType;

        // Check if N-Way disable should be enabled
        manualMediaFlag = 0;
        if (((*(unsigned char *)(adapter + 0x1f9) & 1) != 0) &&
            ((phyCapabilities & 8) != 0)) {
            manualMediaFlag = 1;
        }
        *(char *)(adapter + 0x1e7) = manualMediaFlag;

        // Check for DC21142/DC21143 manual media mode
        if ((*(int *)(adapter + 0x54) == 0x191011) || (*(int *)(adapter + 0x54) == 0xff1011)) {
            manualMediaFlag = 0;

            // Check if PHY capabilities match expected pattern
            if (((phyCapabilities & 0xf800) == 0x7800) &&
                ((*(unsigned short *)((*(int *)(adapter + 500) * 0x30) + 0x23c + adapter) & 0xf800) == 0x6000)) {
                manualMediaFlag = 1;
            }

            *(char *)(adapter + 0x1f0) = manualMediaFlag;
        }

        // Update PHY capabilities and supported media masks
        phyIndex = 0;
        do {
            // Get pointer to PHY capabilities
            phyCapabilitiesPtr = (unsigned short *)((phyIndex * 0x30) + 0x23c + adapter);

            // AND with detected capabilities
            *phyCapabilitiesPtr = *phyCapabilitiesPtr & phyCapabilities;

            // Check various capability bits and update media masks
            if ((*(unsigned char *)((phyIndex * 0x30) + 0x23d + adapter) & 8) != 0) {
                // 10BaseT half-duplex
                *(unsigned char *)(adapter + 0x5c) = *(unsigned char *)(adapter + 0x5c) | 0x40;
                *(unsigned int *)(adapter + 0x60) = *(unsigned int *)(adapter + 0x60) | 0x200000;
            }

            if ((*(unsigned char *)((phyIndex * 0x30) + 0x23d + adapter) & 0x10) != 0) {
                // 10BaseT full-duplex
                *(unsigned int *)(adapter + 0x5c) = *(unsigned int *)(adapter + 0x5c) | 0x240;
                *(unsigned int *)(adapter + 0x60) = *(unsigned int *)(adapter + 0x60) | 0x400000;
            }

            if ((*(unsigned char *)((phyIndex * 0x30) + 0x23d + adapter) & 0x20) != 0) {
                // 100BaseTX half-duplex
                *(unsigned int *)(adapter + 0x5c) = *(unsigned int *)(adapter + 0x5c) | 0x10000;
                *(unsigned int *)(adapter + 0x60) = *(unsigned int *)(adapter + 0x60) | 0x800000;
            }

            if ((*(unsigned char *)((phyIndex * 0x30) + 0x23d + adapter) & 0x40) != 0) {
                // 100BaseTX full-duplex
                *(unsigned int *)(adapter + 0x5c) = *(unsigned int *)(adapter + 0x5c) | 0x20200;
                *(unsigned int *)(adapter + 0x60) = *(unsigned int *)(adapter + 0x60) | 0x1000000;
            }

            if (*(short *)((phyIndex * 0x30) + 0x23c + adapter) < 0) {
                // 100BaseT4
                *(unsigned int *)(adapter + 0x5c) = *(unsigned int *)(adapter + 0x5c) | 0x40000;
                *(unsigned int *)(adapter + 0x60) = *(unsigned int *)(adapter + 0x60) | 0x2000000;
            }

            // Add MII 10BaseT capability (bit 3)
            combinedCapabilities = (phyCapabilities & 8) | *phyCapabilitiesPtr;
            *phyCapabilitiesPtr = combinedCapabilities;

            // Store in PHY structure at offset 8
            *(unsigned short *)(*(int *)(adapter + 0x22c + (phyIndex * 4)) + 8) = combinedCapabilities;

            phyIndex = phyIndex + 1;
        } while (phyIndex < 1);

        // Check if selected connection is supported
        if (initSuccess != 0) {
            connectionCheckSuccess = MiiGenCheckConnection(adapter,
                                                           *(unsigned short *)(adapter + 0x1f8));

            if (connectionCheckSuccess == 0) {
                // Not supported - power down PHY
                DC21X4SetPhyControl((void *)adapter, 4);
            }
        }
    }

    // Return success only if both init and connection check succeeded
    result = 0;
    if ((initSuccess != 0) && (connectionCheckSuccess != 0)) {
        result = 1;
    }

    return result;
}

/*
 * DC21X4ParseSRom
 * Parse Serial ROM (SROM) configuration data
 *
 * Parameters:
 *   adapter - Adapter info structure
 *   sromData - Pointer to SROM data (128 bytes)
 *
 * Returns:
 *   1 if SROM parsed successfully, 0 on error
 *
 * This is the main SROM parser that extracts network configuration,
 * media capabilities, and connection information from the serial ROM.
 */
BOOL DC21X4ParseSRom(int adapter, int *sromData)
{
    BOOL returnValue;
    unsigned short blockCount;
    unsigned char connectionType;
    unsigned int chipRevision;
    unsigned short *blockPtr;
    char checksumValid;
    short crc32Value;
    const char *driverName;
    int blockIndex;
    int connectionIndex;
    const char *errorMessage;
    unsigned char sromVersion;
    unsigned short *currentPtr;
    unsigned char infoLeafOffset;
    unsigned short infoLeafLength;
    int toshiba_id1;
    int toshiba_id2;
    unsigned char blockType;
    unsigned short capabilities;
    int connectionOffset;

    // Default connection data for various media types
    // Format appears to be: media_type, capabilities, values...
    unsigned char defaultConnectionData[] = {
        0, 8, 0x1f, 4, 0, 0x0b, 0x8e, 0,     // Entry 0
        3, 0x1b, 0x6d, 0,                     // Entry 1
        4, 3, 0x8e, 0,                        // Entry 2
        5, 0x1b, 0x6d, 0                      // Entry 3
    };

    // Toshiba OEM identifier
    toshiba_id1 = 0x30354544;  // "DE50"
    toshiba_id2 = 0x41582d30;  // "0-XA"

    blockCount = 0;
    returnValue = TRUE;
    currentPtr = (unsigned short *)defaultConnectionData;

    // Check SROM format version
    sromVersion = *(unsigned char *)((int)sromData + 0x12);

    // Verify CRC32 checksum at offset 0x7e
    crc32Value = CRC32(sromData, 0x7e);

    if ((*(short *)((int)sromData + 0x7e) != crc32Value)) {
        // Try alternate CRC location at 0x5e
        crc32Value = CRC32(sromData, 0x5e);

        if (*(short *)((int)sromData + 0x5e) != crc32Value) {
            // CRC failed - check if legacy DC21040 format
            if ((*(int *)(adapter + 0x54) != 0x91011) ||
                ((*sromData == 0 && ((short)sromData[1] == 0)) ||
                 (VerifyChecksum((unsigned char *)sromData, 0) == 0))) {
                // Invalid checksum
                driverName = getDriverName(adapter);
                errorMessage = "%s: Invalid SROM Checksum, aborting...\n";
                goto log_error;
            }

            // Legacy DC21040 SROM
            driverName = getDriverName(adapter);
            IOLog("%s: Legacy SROM found...\n", driverName);
            driverName = getDriverName(adapter);
            IOLog("%s: Network interface may not function correctly\n", driverName);

            // Copy MAC address from offset 0
            bcopy(sromData, (void *)(adapter + 0x4c), 6);

            // Clear version byte
            *(unsigned char *)((int)sromData + 0x12) = 0;
            currentPtr = (unsigned short *)defaultConnectionData;
        }
    }

    // Check for Toshiba OEM (vendor ID 0x1179, device 0x204)
    if (((short)*sromData == 0x1179) && (*(short *)((int)sromData + 2) == 0x204)) {
        *(char *)(adapter + 0x1ef) = 1;
    }

    // Handle SROM format version
    sromVersion = *(unsigned char *)((int)sromData + 0x12);

    if (sromVersion == 1) {
        goto parse_version_1_or_newer;
    }

    if (sromVersion > 1) {
        if ((sromVersion > 4) || (sromVersion < 3)) {
            // Unsupported version
            goto unsupported_version;
        }
        goto parse_version_1_or_newer;
    }

    if (sromVersion != 0) {
unsupported_version:
        driverName = getDriverName(adapter);
        IOLog("%s: Unsupported SROM format version (0x%02x)!\n", driverName, sromVersion);
        return FALSE;
    }

    // Version 0 - use default connection data
    goto setup_connection_blocks;

parse_version_1_or_newer:
    driverName = getDriverName(adapter);
    IOLog("%s: SROM format version: 0x%02x\n", driverName, sromVersion);

    // Get info leaf offset and length
    infoLeafOffset = *(unsigned char *)((int)sromData + 0x1a);
    infoLeafLength = (unsigned short)*(unsigned char *)((int)sromData + 0x1b);

    // Verify MAC address is not null
    if ((sromData[5] == 0) && ((short)sromData[6] == 0)) {
        driverName = getDriverName(adapter);
        errorMessage = "%s: NULL Network Address\n";
log_error:
        IOLog(errorMessage, driverName);
        return FALSE;
    }

    // Copy MAC address from offset 10 (0xa)
    bcopy(sromData + 5, (void *)(adapter + 0x4c), 6);

    // Set pointer to info leaf
    currentPtr = (unsigned short *)((unsigned int)infoLeafLength + (int)sromData);

setup_connection_blocks:
    // Clear supported media mask
    *(int *)(adapter + 0x7c) = 0;

    // Get chip revision
    chipRevision = *(unsigned int *)(adapter + 0x54);

    if (chipRevision == 0x141011) {
        // DC21140
        // Set up default SIA registers
        *(unsigned int *)(adapter + 0xcc) = 0xef01;
        *(unsigned int *)(adapter + 0xd0) = 0xff3f;
        *(unsigned int *)(adapter + 0xd4) = 8;
        *(unsigned int *)(adapter + 0xec) = 0xef09;
        *(unsigned int *)(adapter + 0xf0) = 0x705;
        *(unsigned int *)(adapter + 0xf4) = 6;
        *(unsigned int *)(adapter + 0x10c) = 0xef09;
        *(unsigned int *)(adapter + 0x110) = 0x705;
        *(unsigned int *)(adapter + 0x114) = 0xe;

        // Parse connection blocks
        blockCount = (unsigned short)(*(unsigned char *)((int)currentPtr + 2));
        blockPtr = (unsigned short *)((int)currentPtr + 3);

        blockIndex = 0;
        if (blockCount != 0) {
            do {
                blockType = (unsigned char)*blockPtr & 0x3f;

                if (blockType < 9) {
                    // Valid connection type - set supported media bit
                    *(unsigned int *)(adapter + 0x7c) =
                        *(unsigned int *)(adapter + 0x7c) | (1 << ((unsigned char)*blockPtr & 0x1f));

                    currentPtr = (unsigned short *)((int)blockPtr + 1);

                    // Check compact format bit
                    if ((*blockPtr & 0x40) != 0) {
                        // Extended format - 3 words of data
                        connectionOffset = (unsigned int)blockType * 0x20;
                        *(unsigned int *)(connectionOffset + 0xcc + adapter) =
                            (unsigned int)*(unsigned short *)((int)blockPtr + 1);
                        *(unsigned int *)(connectionOffset + 0xd0 + adapter) =
                            (unsigned int)*(unsigned short *)((int)blockPtr + 3);
                        *(unsigned int *)(connectionOffset + 0xd4 + adapter) =
                            (unsigned int)*(unsigned short *)((int)blockPtr + 5);
                        currentPtr = (unsigned short *)((int)blockPtr + 7);
                    }
                }
                else {
                    // Unknown block type - skip it
                    if ((*blockPtr & 0x40) == 0) {
                        currentPtr = blockPtr + 2;
                    }
                    else {
                        currentPtr = blockPtr + 8;
                    }
                }

                blockPtr = currentPtr;
                blockIndex = blockIndex + 1;
            } while (blockIndex < (int)(unsigned int)blockCount);
        }

        goto finalize_parsing;
    }

    if (chipRevision < 0x141012) {
        if (chipRevision == 0x91011) {
            // DC21040
            // Check for DE500-XA board
            if ((sromVersion < 2) && (*(int *)(adapter + 8) == 0x11)) {
                returnValue = FALSE;
                if ((toshiba_id1 == *(int *)((int)sromData + 0x1d)) &&
                    (toshiba_id2 == *(int *)((int)sromData + 0x21))) {
                    returnValue = TRUE;
                }
                *(char *)(adapter + 100) = returnValue;
            }
            else {
                // Get polarity from bit 15
                *(unsigned char *)(adapter + 100) = ((unsigned char)(*currentPtr >> 15)) ^ 1;
            }

            capabilities = (unsigned char)currentPtr[1] | 0x100;
            blockCount = (unsigned short)*(unsigned char *)((int)currentPtr + 3);
            currentPtr = currentPtr + 2;

            blockIndex = 0;
            if (blockCount != 0) {
                do {
                    if ((sromVersion < 3) || ((*currentPtr & 0x80) == 0)) {
                        DC21X4ParseFixedBlock(adapter, &currentPtr, capabilities, &connectionType);
                    }
                    else {
                        DC21X4ParseExtendedBlock(adapter, &currentPtr, capabilities, &connectionType);
                    }
                    blockIndex = blockIndex + 1;
                } while (blockIndex < (int)(unsigned int)blockCount);
            }

            goto check_primary_block;
        }
    }
    else if ((chipRevision == 0x191011) || (chipRevision == 0xff1011)) {
        // DC21142/DC21143
        if (sromVersion < 3) {
            return FALSE;
        }

        // Set up default values
        *(unsigned int *)(adapter + 0xcc) = 1;
        *(unsigned int *)(adapter + 0xd0) = 0xff3f;
        *(unsigned int *)(adapter + 0xd4) = 8;
        *(unsigned int *)(adapter + 0xec) = 9;
        *(unsigned int *)(adapter + 0xf0) = 0x705;
        *(unsigned int *)(adapter + 0xf4) = 6;
        *(unsigned int *)(adapter + 0x10c) = 9;
        *(unsigned int *)(adapter + 0x110) = 0x705;
        *(unsigned int *)(adapter + 0x114) = 0xe;

        // Get polarity from bit 15
        *(unsigned char *)(adapter + 100) = ((unsigned char)(*currentPtr >> 15)) ^ 1;

        blockCount = (unsigned short)(*(unsigned char *)((int)currentPtr + 2));
        currentPtr = (unsigned short *)((int)currentPtr + 3);

        blockIndex = 0;
        if (blockCount != 0) {
            do {
                DC21X4ParseExtendedBlock(adapter, &currentPtr, 0, &connectionType);
                blockIndex = blockIndex + 1;
            } while (blockIndex < (int)(unsigned int)blockCount);
        }

check_primary_block:
        // Check if primary block needs to be set
        if ((*(char *)(adapter + 0x65) == 0) && (*(int *)(adapter + 0x88) > 0)) {
            *(unsigned int *)(adapter + 0x80) =
                *(unsigned int *)(adapter + 0x9c + (*(int *)(adapter + 0x88) * 4));
        }

        goto finalize_parsing;
    }

    returnValue = FALSE;

finalize_parsing:
    // If single block and MII PHY not present, set default media type
    if ((blockCount == 1) && (*(int *)(adapter + 0x7c) != 0) &&
        (*(char *)(adapter + 0x1e5) == 0)) {
        *(unsigned int *)(adapter + 0x78) = *(unsigned int *)(adapter + 0x78) & 0xfffff700;
        *(unsigned int *)(adapter + 0x78) =
            *(unsigned int *)(adapter + 0x78) | (unsigned int)connectionType;
    }

    // If no supported media types, enable promiscuous mode
    if ((*(unsigned char *)(adapter + 0x7c) & 7) == 0) {
        *(unsigned int *)(adapter + 0x68) = *(unsigned int *)(adapter + 0x68) | 0x40000;
    }

    return returnValue;
}

/*
 * DC21X4ParseFixedBlock
 * Parse fixed-format (compact 4-byte) SROM connection blocks
 */
BOOL DC21X4ParseFixedBlock(void *adapter, unsigned char *blockPtr,
                            unsigned char connectionType)
{
    unsigned short blockWord0;
    unsigned short blockWord1;
    unsigned short mediaBit;
    unsigned short mediaCode;
    unsigned int tempReg;
    unsigned short gepControl;
    unsigned short gepData;
    unsigned short csr6Bits;
    unsigned short testPattern;
    unsigned short portSelect;
    BOOL isPrimary;

    // Read the two 16-bit words from the block
    blockWord0 = *(unsigned short *)blockPtr;
    blockWord1 = *(unsigned short *)(blockPtr + 2);

    // Extract media code (bits 0-5)
    mediaCode = blockWord0 & 0x3f;

    // Extract GP control value (bits 7-14)
    gepControl = (blockWord0 >> 7) & 0xff;

    // Extract GP data value (bits 0-6 of second word)
    gepData = blockWord1 & 0x7f;

    // Extract CSR6 bits (bits 7-12 of second word)
    csr6Bits = (blockWord1 >> 7) & 0x3f;

    // Check primary block flag (bit 6 of first word)
    isPrimary = (blockWord0 & 0x40) != 0;

    // Get media bit for this media type
    mediaBit = _ConnectionType[mediaCode];

    // Update supported media mask
    // TODO: *(unsigned int *)(adapter + 0x7c) |= (1 << mediaBit);
    tempReg = *(unsigned int *)(adapter + 0x7c);
    tempReg |= (1 << mediaBit);
    *(unsigned int *)(adapter + 0x7c) = tempReg;

    // If this is the primary block or matches the requested connection type
    if (isPrimary || (connectionType == mediaCode)) {
        // Store CSR6 configuration bits
        // TODO: *(unsigned short *)(adapter + 0x17c) = csr6Bits;
        *(unsigned short *)(adapter + 0x17c) = csr6Bits;

        // Store GP control value
        // TODO: *(unsigned short *)(adapter + 0x19e) = gepControl;
        *(unsigned short *)(adapter + 0x19e) = gepControl;

        // Store GP data value
        // TODO: *(unsigned short *)(adapter + 0x1a0) = gepData;
        *(unsigned short *)(adapter + 0x1a0) = gepData;

        // Extract test pattern (bit 13 of second word)
        testPattern = (blockWord1 >> 13) & 1;
        // TODO: *(unsigned char *)(adapter + 0x1a4) = testPattern;
        *(unsigned char *)(adapter + 0x1a4) = testPattern;

        // Extract port select (bits 14-15 of second word)
        portSelect = (blockWord1 >> 14) & 3;
        // TODO: *(unsigned char *)(adapter + 0x1a5) = portSelect;
        *(unsigned char *)(adapter + 0x1a5) = portSelect;

        // Store media code as default media type
        // TODO: *(unsigned char *)(adapter + 0x78) = mediaCode;
        *(unsigned char *)(adapter + 0x78) = mediaCode;
    }

    return TRUE;
}

/*
 * DC21X4ParseExtendedBlock
 * Parse extended-format (variable-length) SROM connection blocks
 */
BOOL DC21X4ParseExtendedBlock(void *adapter, unsigned char *blockPtr,
                               unsigned char connectionType, unsigned char *sromData)
{
    unsigned char blockType;
    unsigned char blockLength;
    unsigned char mediaCode;
    unsigned short mediaBit;
    unsigned int tempReg;
    unsigned char phyNumber;
    unsigned char *sequencePtr;
    unsigned char seqLength;
    int i;
    unsigned short gepValue;
    unsigned short csr13Value, csr14Value, csr15Value;
    unsigned short csr6Bits;
    BOOL isPrimary;

    // Get block type and length
    blockType = *blockPtr;
    blockLength = *(blockPtr + 1);

    // Block type determines how to parse
    switch (blockType) {
        case 0:
            // Type 0: Fixed format block (4 bytes) - delegate to fixed parser
            return DC21X4ParseFixedBlock(adapter, blockPtr + 2, connectionType);

        case 1:  // MII PHY block
        case 3:  // MII PHY block (alternate format)
            // Extract media code
            mediaCode = *(blockPtr + 3);
            mediaBit = _ConnectionType[mediaCode];

            // Update supported media mask
            tempReg = *(unsigned int *)(adapter + 0x7c);
            tempReg |= (1 << mediaBit);
            *(unsigned int *)(adapter + 0x7c) = tempReg;

            // Check if this is primary or matches requested type
            isPrimary = (*(blockPtr + 2) & 0x40) != 0;
            if (isPrimary || (connectionType == mediaCode)) {
                // Store default media type
                *(unsigned char *)(adapter + 0x78) = mediaCode;

                // Get PHY number
                phyNumber = *(blockPtr + 2) & 0x1f;
                // TODO: *(unsigned char *)(adapter + 0x1e4) = phyNumber;
                *(unsigned char *)(adapter + 0x1e4) = phyNumber;

                // Mark MII PHY as present
                // TODO: *(BOOL *)(adapter + 0x1e5) = TRUE;
                *(char *)(adapter + 0x1e5) = 1;

                // Get GP control sequence length and pointer
                seqLength = *(blockPtr + 4);
                sequencePtr = blockPtr + 5;

                // Store reset sequence
                if (seqLength > 0) {
                    // TODO: Store at adapter + 0x1f4
                    for (i = 0; i < seqLength && i < 16; i++) {
                        *(unsigned short *)(adapter + 0x1f4 + (i * 2)) =
                            *(unsigned short *)(sequencePtr + (i * 2));
                    }
                    // TODO: *(unsigned char *)(adapter + 0x1f3) = seqLength;
                    *(unsigned char *)(adapter + 0x1f3) = seqLength;
                }

                // Skip to init sequence
                sequencePtr += (seqLength * 2);
                seqLength = *sequencePtr;
                sequencePtr++;

                // Store init sequence
                if (seqLength > 0) {
                    // TODO: Store at adapter + 0x214
                    for (i = 0; i < seqLength && i < 16; i++) {
                        *(unsigned short *)(adapter + 0x214 + (i * 2)) =
                            *(unsigned short *)(sequencePtr + (i * 2));
                    }
                    // TODO: *(unsigned char *)(adapter + 0x213) = seqLength;
                    *(unsigned char *)(adapter + 0x213) = seqLength;
                }
            }
            break;

        case 2:  // Compact media block
            // Extract media code (byte 3)
            mediaCode = *(blockPtr + 3);
            mediaBit = _ConnectionType[mediaCode];

            // Update supported media mask
            tempReg = *(unsigned int *)(adapter + 0x7c);
            tempReg |= (1 << mediaBit);
            *(unsigned int *)(adapter + 0x7c) = tempReg;

            // Check if primary or matches requested type
            isPrimary = (*(blockPtr + 2) & 0x40) != 0;
            if (isPrimary || (connectionType == mediaCode)) {
                // Store default media type
                *(unsigned char *)(adapter + 0x78) = mediaCode;

                // Get CSR13-15 values
                csr13Value = *(unsigned short *)(blockPtr + 4);
                csr14Value = *(unsigned short *)(blockPtr + 6);
                csr15Value = *(unsigned short *)(blockPtr + 8);

                // TODO: Store at adapter + 0x196, 0x19a, 0x19c
                *(unsigned short *)(adapter + 0x196) = csr13Value;
                *(unsigned short *)(adapter + 0x19a) = csr14Value;
                *(unsigned short *)(adapter + 0x19c) = csr15Value;

                // Get GP control value (byte 10)
                gepValue = *(blockPtr + 10);
                // TODO: *(unsigned short *)(adapter + 0x19e) = gepValue;
                *(unsigned short *)(adapter + 0x19e) = gepValue;
            }
            break;

        case 4:  // Extended media block with auto-sense
            // Extract media code
            mediaCode = *(blockPtr + 3);
            mediaBit = _ConnectionType[mediaCode];

            // Update supported media mask
            tempReg = *(unsigned int *)(adapter + 0x7c);
            tempReg |= (1 << mediaBit);
            *(unsigned int *)(adapter + 0x7c) = tempReg;

            // Check if primary or matches requested type
            isPrimary = (*(blockPtr + 2) & 0x40) != 0;
            if (isPrimary || (connectionType == mediaCode)) {
                // Store default media type
                *(unsigned char *)(adapter + 0x78) = mediaCode;

                // Get CSR13-15 values
                csr13Value = *(unsigned short *)(blockPtr + 4);
                csr14Value = *(unsigned short *)(blockPtr + 6);
                csr15Value = *(unsigned short *)(blockPtr + 8);

                // TODO: Store at adapter + 0x196, 0x19a, 0x19c
                *(unsigned short *)(adapter + 0x196) = csr13Value;
                *(unsigned short *)(adapter + 0x19a) = csr14Value;
                *(unsigned short *)(adapter + 0x19c) = csr15Value;

                // Get CSR6 bits (bytes 10-11)
                csr6Bits = *(unsigned short *)(blockPtr + 10);
                // TODO: *(unsigned short *)(adapter + 0x17c) = csr6Bits;
                *(unsigned short *)(adapter + 0x17c) = csr6Bits;

                // Get GP control (bytes 12-13)
                gepValue = *(unsigned short *)(blockPtr + 12);
                // TODO: *(unsigned short *)(adapter + 0x19e) = gepValue;
                *(unsigned short *)(adapter + 0x19e) = gepValue;
            }
            break;

        case 5:  // Reset sequence (alternate format)
            // Get sequence length
            seqLength = *(blockPtr + 2);
            sequencePtr = blockPtr + 3;

            // Store reset sequence
            if (seqLength > 0) {
                // TODO: Store at adapter + 0x1f4
                for (i = 0; i < seqLength && i < 16; i++) {
                    *(unsigned short *)(adapter + 0x1f4 + (i * 2)) =
                        *(unsigned short *)(sequencePtr + (i * 2));
                }
                // TODO: *(unsigned char *)(adapter + 0x1f3) = seqLength;
                *(unsigned char *)(adapter + 0x1f3) = seqLength;
            }
            break;

        default:
            // Unknown block type - skip it
            return TRUE;
    }

    return TRUE;
}

/*
 * DC21X4MiiAutoSense
 * Handle MII auto-sensing with connection status monitoring
 */
int DC21X4MiiAutoSense(int adapter)
{
    BOOL shouldFallback;
    unsigned int indicateStatus;
    char connectionOk;
    unsigned short connectionType;
    char connectionStatus[2];

    shouldFallback = FALSE;
    connectionOk = MiiGenGetConnectionStatus(adapter, connectionStatus);

    // Check if MII initialization complete flag is set
    if ((*(unsigned char *)(adapter + 0x1f9) & 8) == 0) {
        goto check_connection_status;
    }
    else {
        if (connectionOk != 0) {
            // Check if connection type is valid (2)
            if (connectionStatus[0] == 2) {
                connectionOk = MiiGenGetConnection(adapter, &connectionType);
                if (connectionOk == 0) goto indicate_status;

                // If connection changed or not in active state
                if ((*(unsigned int *)(adapter + 0x1f8) != (unsigned int)connectionType) ||
                    (*(int *)(adapter + 0x204) != 2)) {
                    // Set new connection type with MII flag (bit 11)
                    *(unsigned int *)(adapter + 0x1f8) = (unsigned int)(connectionType | 0x800);
                    SetMacConnection(adapter);
                }
            }

check_connection_status:
            if (connectionOk == 0) goto indicate_status;
        }
        else {
indicate_status:
            // If in active state (1), skip indication
            if (*(int *)(adapter + 0x204) == 1) goto check_fallback;
        }
    }

    // Indicate media status based on connection
    indicateStatus = 0;
    if (connectionOk != 0) {
        indicateStatus = 2;  // Connected
    }
    DC21X4IndicateMediaStatus(adapter, indicateStatus);

check_fallback:
    // Handle fallback to non-MII port if connection lost
    if (((connectionOk == 0) && (*(int *)(adapter + 0x7c) != 0)) &&
        ((*(unsigned char *)(adapter + 0x1f9) & 8) != 0)) {

        // Check if remote fault (-3 = 0xfd)
        if (connectionStatus[0] == (char)0xfd) {
            // Clear MII ready flag
            *(unsigned char *)(adapter + 0x1e6) = 0;

            // Check if N-Way supported
            if ((*(unsigned char *)(adapter + 0x79) & 1) != 0) {
                DC21X4EnableNway(adapter);
                shouldFallback = TRUE;
            }
        }
        // Check if auto-detect flag set
        else if ((*(unsigned char *)(adapter + 0x6a) & 4) != 0) {
            shouldFallback = TRUE;
        }

        if (shouldFallback) {
            // If no 100Base support and fallback mode enabled
            if (((*(unsigned char *)(adapter + 0x7c) & 6) == 0) &&
                (*(char *)(adapter + 0x1f0) != 0)) {

                // If not already on 10Base-T (9)
                if (*(char *)(adapter + 0x1f8) != 9) {
                    *(unsigned int *)(adapter + 0x1f8) =
                        *(unsigned int *)(adapter + 0x1f8) & 0xff00;
                    *(unsigned char *)(adapter + 0x1f8) =
                        *(unsigned char *)(adapter + 0x1f8) | 9;
                    *(unsigned int *)(adapter + 0x84) = 0;
                    SetMacConnection(adapter);
                }
            }
            else {
                SelectNonMiiPort(adapter);
            }
        }
    }

    return (int)connectionOk;
}

/*
 * DC21X4MiiAutoDetect
 * Perform MII auto-detection with polling for link
 */
int DC21X4MiiAutoDetect(int adapter)
{
    unsigned int indicateStatus;
    int pollCount;
    char connectionOk;
    unsigned short connectionType;
    unsigned char connectionStatus[2];

    // Get initial connection status
    connectionOk = MiiGenGetConnectionStatus(adapter, connectionStatus);

    // Indicate initial status
    indicateStatus = 0;
    if (connectionOk != 0) {
        indicateStatus = 2;  // Connected
    }
    DC21X4IndicateMediaStatus(adapter, indicateStatus);

    // If no link initially, poll for connection
    if (connectionOk == 0) {
        pollCount = 0xdac;  // 3500 attempts
        do {
            if (pollCount == 0) break;

            _IODelay(1000);  // Wait 1ms
            connectionOk = MiiGenGetConnectionStatus(adapter, connectionStatus);
            pollCount = pollCount - 1;
        } while (connectionOk == 0);
    }

    // If MII initialization complete flag is set
    if ((*(unsigned char *)(adapter + 0x1f9) & 8) != 0) {
        connectionOk = MiiGenGetConnection(adapter, &connectionType);

        // If connected and type changed
        if ((connectionOk != 0) &&
            (*(unsigned int *)(adapter + 0x1f8) != (unsigned int)(connectionType | 0x800))) {
            // Set new connection with MII flag
            *(unsigned int *)(adapter + 0x1f8) = (unsigned int)(connectionType | 0x800);
            SetMacConnection(adapter);
        }
    }

    // Indicate final status
    indicateStatus = 0;
    if (connectionOk != 0) {
        indicateStatus = 2;  // Connected
    }
    DC21X4IndicateMediaStatus(adapter, indicateStatus);

    // Handle fallback to non-MII port if needed
    if ((((connectionOk == 0) && (*(int *)(adapter + 0x7c) != 0)) &&
        ((*(unsigned char *)(adapter + 0x1f9) & 8) != 0)) &&
        ((*(char *)(adapter + 0x1f0) == 0) || ((*(unsigned char *)(adapter + 0x7c) & 6) != 0))) {
        SelectNonMiiPort(adapter);
    }

    return (int)connectionOk;
}

/*
 * DC21X4MediaDetect
 * Main media detection function for all chip variants
 */
int DC21X4MediaDetect(int adapter)
{
    int tempValue;
    BOOL shouldFallback;
    char connectionOk;
    void *packetBuffer;
    unsigned int chipRevision;
    int mediaIndex;
    int delayCount;
    unsigned int indicateStatus;
    int mediaCount;

    connectionOk = 0;
    shouldFallback = FALSE;
    chipRevision = *(unsigned int *)(adapter + 0x54);

    // Handle non-DC21140 chips
    if (chipRevision != 0x141011) {
        if (chipRevision < 0x141012) {
            // DC21040 specific handling
            if (chipRevision == 0x21011) {
                if (*(int *)(adapter + 0x84) == 0) {
                    // Read CSR12 status
                    do {
                        chipRevision = in(*(unsigned short *)(adapter + 0x3c));
                        if ((chipRevision & 4) == 0) goto indicate_and_exit;
                    } while (((chipRevision & 2) == 0) && ((chipRevision & 6) == 4));

                    // Check if 10Base-2 supported
                    if ((*(unsigned char *)(adapter + 0x79) & 8) == 0) {
                        indicateStatus = 0;
                        goto indicate_media_status;
                    }

                    // Switch to 10Base-2 mode
                    *(unsigned int *)(adapter + 0x84) = 1;
                    DC2104InitializeSiaRegisters(adapter);

                    // Wait for media initialization (at least 30 * 10ms = 300ms)
                    mediaCount = 0;
                    while (TRUE) {
                        mediaIndex = *(int *)(adapter + 0x9c);
                        if (mediaIndex < 0x1e) {
                            mediaIndex = 0x1e;
                        }
                        if (mediaIndex <= mediaCount) break;

                        delayCount = 0;
                        do {
                            _IODelay(1000);
                            delayCount = delayCount + 1;
                        } while (delayCount < 10);
                        mediaCount = mediaCount + 1;
                    }

                    // Send test packet to check connection
                    packetBuffer = (void *)_IOMalloc(0x40);
                    if (packetBuffer == (void *)0) {
                        *(unsigned int *)(adapter + 0x270) = 0;
                    }
                    else {
                        _bzero(packetBuffer, 0x40);
                        _bcopy((void *)(adapter + 0x4c), packetBuffer, 6);
                        _bcopy((void *)(adapter + 0x4c), (void *)((int)packetBuffer + 6), 6);
                        *(unsigned char *)(adapter + 499) = 1;
                        sendPacket(adapter, packetBuffer, 0x40);
                        _IOFree(packetBuffer, 0x40);
                    }

                    // Check if packet transmitted successfully
                    if ((*(short *)(adapter + 0x274) < 0) || (*(int *)(adapter + 0x270) < 1)) {
                        // No link on 10Base-2, try AUI
                        *(unsigned int *)(adapter + 0x84) = 2;
                        DC2104InitializeSiaRegisters(adapter);
                        DC21X4StartAdapter(adapter);
                    }
                }

indicate_and_exit:
                indicateStatus = 1;  // Assume connected
indicate_media_status:
                DC21X4IndicateMediaStatus(adapter, indicateStatus);
                return 0;
            }

            // DC21041 specific handling
            if (chipRevision != 0x91011) {
                return 0;
            }

            // DC21041 auto-sense logic
            if ((*(unsigned char *)(adapter + 0x79) & 8) != 0) {
                // Write GP control value
                out(*(unsigned short *)(adapter + 0x3c),
                    *(unsigned int *)(*(int *)(adapter + 0xa0) * 0x20 + 0xc4 + adapter));

                // Try all configured media types
                for (mediaIndex = *(int *)(adapter + 0x88); 0 < mediaIndex;
                     mediaIndex = mediaIndex - 1) {
                    tempValue = *(int *)(adapter + 0x9c + mediaIndex * 4);

                    if (((tempValue != 3) && (tempValue != 0)) || shouldFallback) {
                        // Configure CSR6 for this media
                        out(*(unsigned short *)(adapter + 0x24),
                            *(unsigned int *)(adapter + 0x68) & 0xfc333dff |
                            *(unsigned int *)(tempValue * 0x20 + 0xd8 + adapter));

                        // Write CSR12 value
                        out(*(unsigned short *)(adapter + 0x3c),
                            *(unsigned int *)(tempValue * 0x20 + 200 + adapter));

                        // Wait 200ms
                        delayCount = 0;
                        do {
                            _IODelay(1000);
                            delayCount = delayCount + 1;
                        } while (delayCount < 200);

                        // Check link status
                        chipRevision = in(*(unsigned short *)(adapter + 0x3c));
                        mediaCount = tempValue * 0x20;
                        connectionOk =
                            (*(unsigned int *)(mediaCount + 0xe0 + adapter) &
                            (chipRevision ^ *(unsigned int *)(mediaCount + 0xdc + adapter))) != 0;

                        if (connectionOk) {
                            // Found working media
                            *(int *)(adapter + 0x84) = tempValue;
                            *(unsigned int *)(adapter + 0x68) =
                                *(unsigned int *)(adapter + 0x68) & 0xfc333dff;
                            *(unsigned int *)(adapter + 0x68) =
                                *(unsigned int *)(adapter + 0x68) |
                                *(unsigned int *)(mediaCount + 0xd8 + adapter);
                            break;
                        }
                    }
                    else {
                        // Try 100Base-TX
                        connectionOk = DC2114Sense100BaseTxLink(adapter);
                        shouldFallback = TRUE;
                        if (connectionOk != 0) break;
                    }
                }

                DC21X4IndicateMediaStatus(adapter, connectionOk != 0);

                if (connectionOk == 0) {
                    // Fallback to default media
                    *(unsigned int *)(adapter + 0x84) = *(unsigned int *)(adapter + 0x80);
                    *(unsigned int *)(adapter + 0x68) =
                        *(unsigned int *)(adapter + 0x68) & 0xfc333dff;
                    chipRevision = *(unsigned int *)(adapter + 0x68) |
                                   *(unsigned int *)(*(int *)(adapter + 0x84) * 0x20 + 0xd8 + adapter);
                    *(unsigned int *)(adapter + 0x68) = chipRevision;
                    out(*(unsigned short *)(adapter + 0x24), chipRevision);

                    out(*(unsigned short *)(adapter + 0x3c),
                        *(unsigned int *)(*(int *)(adapter + 0x84) * 0x20 + 200 + adapter));
                }

check_loopback:
                if (*(char *)(adapter + 100) == 0) {
                    *(unsigned int *)(adapter + 0x78) =
                        *(unsigned int *)(adapter + 0x78) & 0xfffff7ff;
                }
                return 1;
            }

            // For non-auto-sense mode on DC21041
            if (*(int *)(*(int *)(adapter + 0x84) * 0x20 + 0xe0 + adapter) != 0) {
                chipRevision = in(*(unsigned short *)(adapter + 0x3c));
                mediaIndex = *(int *)(adapter + 0x84) * 0x20;
                DC21X4IndicateMediaStatus(
                    adapter,
                    (*(unsigned int *)(mediaIndex + 0xe0 + adapter) &
                    (chipRevision ^ *(unsigned int *)(mediaIndex + 0xdc + adapter))) != 0);
                goto check_loopback;
            }

            // If MII not ready, indicate link up
            if (*(char *)(adapter + 0x1e6) == 0) {
                DC21X4IndicateMediaStatus(adapter, 1);
            }

            goto return_mii_ready;
        }

        // Handle DC21142/DC21143
        if ((chipRevision != 0x191011) && (chipRevision != 0xff1011)) {
            return 0;
        }
    }

    // DC21140/DC21142/DC21143 handling
    if (*(int *)(adapter + 0x84) - 1U < 2) {
        DC21X4IndicateMediaStatus(adapter, 1);
    }

    if ((*(unsigned char *)(adapter + 0x79) & 8) != 0) {
        return 1;
    }

return_mii_ready:
    return (int)*(char *)(adapter + 0x1e6);
}

/*
 * DC21X4InitializeMediaRegisters
 * Initialize media-specific registers based on chip type
 */
void DC21X4InitializeMediaRegisters(int adapter, char usePhyInit)
{
    unsigned int chipRevision;

    chipRevision = *(unsigned int *)(adapter + 0x54);

    // DC21040 or DC21140 - use SIA registers
    if (chipRevision != 0x141011) {
        if (chipRevision < 0x141012) {
            if (chipRevision != 0x21011) {
                // DC21041 - use GEP registers
                if (chipRevision != 0x91011) {
                    return;
                }
                DC21X4InitializeGepRegisters(adapter, usePhyInit);
                return;
            }
        }
        else {
            // DC21142/DC21143 - use GEP registers
            if ((chipRevision != 0x191011) && (chipRevision != 0xff1011)) {
                return;
            }
            DC21X4InitializeGepRegisters(adapter, usePhyInit);
        }
    }

    // DC21040/DC21140 - initialize SIA registers
    DC2104InitializeSiaRegisters(adapter, 0x46d0);
}

/*
 * DC21X4InitializeGepRegisters
 * Initialize General Purpose Port registers
 */
void DC21X4InitializeGepRegisters(int adapter, char usePhyInit)
{
    int currentMedia;
    int phyIndex;
    int sequenceIndex;

    if (usePhyInit == 0) {
        // Use media-specific GEP values
        // TODO: Get GP control value from offset 0xc4 + (currentMedia * 0x20)
        DC21X4WriteGepRegister(
            adapter,
            *(unsigned int *)(*(int *)(adapter + 0x84) * 0x20 + 0xc4 + adapter));

        // TODO: Get GP data value from offset 0xc8 (200 decimal) + (currentMedia * 0x20)
        DC21X4WriteGepRegister(
            adapter,
            *(unsigned int *)(*(int *)(adapter + 0x84) * 0x20 + 200 + adapter));
    }
    else {
        // Use PHY initialization sequence
        // TODO: Get PHY index from offset 500 (0x1f4)
        phyIndex = *(int *)(adapter + 500);

        // Write initial GEP control value
        // TODO: PHY structure at offset 0x230 + (phyIndex * 0x30), control at +0x14
        DC21X4WriteGepRegister(
            adapter,
            *(unsigned short *)(phyIndex * 0x30 + 0x244 + adapter));

        // Write GEP initialization sequence
        sequenceIndex = 0;
        // TODO: Get sequence length from offset 0x234 + (phyIndex * 0x30) + 4
        if (0 < *(int *)(phyIndex * 0x30 + 0x234 + adapter)) {
            do {
                // TODO: Sequence data starts at offset 0x246 + (phyIndex * 0x30) + 0x12
                DC21X4WriteGepRegister(
                    adapter,
                    *(unsigned short *)(adapter + sequenceIndex * 2 + 0x246 + phyIndex * 0x30));
                sequenceIndex = sequenceIndex + 1;
                phyIndex = *(int *)(adapter + 500);
            } while (sequenceIndex < *(int *)(phyIndex * 0x30 + 0x234 + adapter));
        }
    }
}

/*
 * DC21X4IndicateMediaStatus
 * Indicate media link status and configure speed/duplex settings
 */
void DC21X4IndicateMediaStatus(int adapter, int linkStatus)
{
    int currentMedia;
    unsigned int csr12Value;
    const char *driverName;
    const char *duplexString;
    BOOL isFullDuplex;

    // Store current link status
    // TODO: *(int *)(adapter + 0x204) = linkStatus;
    *(int *)(adapter + 0x204) = linkStatus;

    // If status hasn't changed, return early
    // TODO: if (*(int *)(adapter + 0x208) == linkStatus) return;
    if (*(int *)(adapter + 0x208) == linkStatus) {
        return;
    }

    if (linkStatus == 1) {
        // Link PASS (non-MII)
        currentMedia = *(int *)(adapter + 0x84);

        // Check if 100Mbps media (media types 3, 5-8)
        if ((currentMedia == 3) ||
            (((2 < currentMedia && (currentMedia < 9)) && (4 < currentMedia)))) {

            // For DC21143, set specific CSR13/14 bits
            if (*(int *)(adapter + 0x54) == 0xff1011) {
                *(unsigned int *)(adapter + 0x1fc) =
                    *(unsigned int *)(adapter + 0x1fc) & 0xffffefef;
                *(unsigned int *)(adapter + 0x200) =
                    *(unsigned int *)(adapter + 0x200) & 0xffffefef;
                *(unsigned int *)(adapter + 0x1fc) =
                    *(unsigned int *)(adapter + 0x1fc) | 0x8000000;
                *(unsigned int *)(adapter + 0x200) =
                    *(unsigned int *)(adapter + 0x200) | 0x8000000;
            }
            // Set speed to 1000Mbps
            *(unsigned int *)(adapter + 0x74) = 1000000;
        }
        else {
            // 10Mbps media
            *(unsigned int *)(adapter + 0x1fc) =
                *(unsigned int *)(adapter + 0x1fc) & 0xf7ffffff;
            *(unsigned int *)(adapter + 0x200) =
                *(unsigned int *)(adapter + 0x200) & 0xf7ffffff;
            *(unsigned int *)(adapter + 0x1fc) =
                *(unsigned int *)(adapter + 0x1fc) | 0x1000;
            *(unsigned int *)(adapter + 0x200) =
                *(unsigned int *)(adapter + 0x200) | 0x1000;
            // Set speed to 100Mbps
            *(unsigned int *)(adapter + 0x74) = 100000;
        }

        // Determine full duplex setting
        if (*(char *)(adapter + 4) == 0) {
            // Use media configuration bit 9
            isFullDuplex = (BOOL)((unsigned char)(*(unsigned int *)(adapter + 0x78) >> 9) & 1);
        }
        else {
            // Read from CSR12
            csr12Value = in(*(unsigned short *)(adapter + 0x3c));

            if (*(int *)(adapter + 0x54) == 0xff1011) {
                // DC21143: check bits 20 or 24
                isFullDuplex = (csr12Value & 0x1400000) != 0;
                *(BOOL *)(adapter + 0x1e4) = isFullDuplex;

                // Media types 4-5 are always full duplex
                if (*(int *)(adapter + 0x84) - 4U < 2) {
                    isFullDuplex = TRUE;
                }
            }
            else {
                // Other chips: check bit 22
                *(unsigned char *)(adapter + 0x1e4) =
                    (unsigned char)(csr12Value >> 0x16) & 1;

                // Special case: 10Base-T with force full duplex
                if ((*(int *)(adapter + 0x84) == 0) &&
                    ((*(unsigned char *)(adapter + 0x69) & 2) != 0)) {
                    *(unsigned char *)(adapter + 0x1e4) = 1;
                }
                isFullDuplex = *(BOOL *)(adapter + 0x1e4);
            }
        }

        *(BOOL *)(adapter + 0x1e4) = isFullDuplex;

        // Log link status
        duplexString = "";
        if (*(char *)(adapter + 0x1e4) != 0) {
            duplexString = " Full_Duplex";
        }

        driverName = getDriverName(adapter);
        _IOLog("%s: %s%s Link PASS\n", driverName,
               MediumString[*(int *)(adapter + 0x84)], duplexString);
    }
    else if (linkStatus == 0) {
        // Link FAIL
        if ((*(char *)(adapter + 0x1e6) == 0) || (*(char *)(adapter + 0x1ef) != 0)) {
            // Clear bit 12, set bit 4 in CSR13/14
            *(unsigned int *)(adapter + 0x1fc) =
                *(unsigned int *)(adapter + 0x1fc) & 0xffffefff;
            *(unsigned int *)(adapter + 0x200) =
                *(unsigned int *)(adapter + 0x200) & 0xffffefff;
            *(unsigned char *)(adapter + 0x1fc) =
                *(unsigned char *)(adapter + 0x1fc) | 0x10;
            *(unsigned char *)(adapter + 0x200) =
                *(unsigned char *)(adapter + 0x200) | 0x10;

            // DC21143 specific
            if (*(int *)(adapter + 0x54) == 0xff1011) {
                *(unsigned int *)(adapter + 0x1fc) =
                    *(unsigned int *)(adapter + 0x1fc) | 0x8000000;
                *(unsigned int *)(adapter + 0x200) =
                    *(unsigned int *)(adapter + 0x200) | 0x8000000;
            }
        }

        driverName = getDriverName(adapter);
        _IOLog("%s: Link FAIL\n", driverName);
    }
    else if (linkStatus == 2) {
        // MII Link PASS
        *(unsigned int *)(adapter + 0x74) = 100000;  // Default 100Mbps
        *(unsigned char *)(adapter + 0x1e4) = 0;     // Default half duplex

        // Determine speed and duplex from MII connection type
        switch (*(unsigned char *)(adapter + 0x1f8)) {
        case 10:  // 10Base-T Full Duplex
            *(unsigned char *)(adapter + 0x1e4) = 1;
            break;
        case 0x0e:  // 100Base-TX Full Duplex
        case 0x11:  // 100Base-T4 Full Duplex
            *(unsigned char *)(adapter + 0x1e4) = 1;
            // Fall through
        case 0x0d:  // 100Base-TX
        case 0x0f:  // 100Base-T2
        case 0x10:  // 100Base-FX
            *(unsigned int *)(adapter + 0x74) = 1000000;
            break;
        }

        // Log MII link status
        duplexString = "";
        if (*(char *)(adapter + 0x1e4) != 0) {
            duplexString = " Full_Duplex";
        }

        driverName = getDriverName(adapter);
        _IOLog("%s: %s%s MiiLink PASS\n", driverName,
               MediumString[*(unsigned char *)(adapter + 0x1f8)], duplexString);
    }

    // Write interrupt mask register (CSR7) if not in MII mode or forced
    if ((*(char *)(adapter + 0x1e6) == 0) || (*(char *)(adapter + 0x1ef) != 0)) {
        out(*(unsigned short *)(adapter + 0x28), *(unsigned int *)(adapter + 0x1fc));
    }

    // Update transmit threshold based on duplex mode
    if (*(char *)(adapter + 0x1e4) == 0) {
        // Half duplex: use default threshold
        *(unsigned int *)(adapter + 0x268) = *(unsigned int *)(adapter + 0x264);
    }
    else {
        // Full duplex: clear bits 10-11 (store and forward mode)
        *(unsigned int *)(adapter + 0x268) =
            *(unsigned int *)(adapter + 0x268) & 0xfffff3ff;
    }

    // Store last indicated status
    *(int *)(adapter + 0x208) = linkStatus;
}

/*
 * DC21X4EnableNway
 * Enable N-Way auto-negotiation for supported chip variants
 */
void DC21X4EnableNway(int adapter)
{
    char nwayCapable;
    unsigned int chipRevision;
    unsigned int boardRevision;
    unsigned int csr6Bits;

    chipRevision = *(unsigned int *)(adapter + 0x54);

    if (chipRevision == 0x191011) {
        // DC21142
        boardRevision = *(unsigned int *)(adapter + 8);
        if ((0x11 < boardRevision) || (boardRevision < 0x10)) {
            goto enable_sia_nway;
        }
        nwayCapable = *(char *)(adapter + 0x1ec);
        goto check_nway_capable;
    }
    else if (chipRevision > 0x191011) {
        // DC21143
        if (chipRevision != 0xff1011) {
            return;
        }

        // Mark N-Way enabled
        *(unsigned char *)(adapter + 4) = 1;

        // Check if 10Base-T supported (bit 0 of media mask)
        if ((*(unsigned char *)(adapter + 0x7c) & 1) != 0) {
            // N-Way mode 3
            *(unsigned int *)(adapter + 0x260) = 3;

            // Clear media type byte
            *(unsigned int *)(adapter + 0x78) =
                *(unsigned int *)(adapter + 0x78) & 0xffffff00;
            *(unsigned int *)(adapter + 0x78) = *(unsigned int *)(adapter + 0x78);

            // Update CSR13 values for media types 0-2
            // Mask CSR6 bits and add 0x80
            csr6Bits = *(unsigned int *)(adapter + 0x5c) & 0xff7ffdff | 0x80;
            *(unsigned int *)(adapter + 0xd0) =
                *(unsigned int *)(adapter + 0xd0) | csr6Bits;  // Media 0 CSR13
            *(unsigned int *)(adapter + 0xf0) =
                *(unsigned int *)(adapter + 0xf0) | csr6Bits;  // Media 1 CSR13
            *(unsigned int *)(adapter + 0x110) =
                *(unsigned int *)(adapter + 0x110) | csr6Bits;  // Media 2 CSR13

            // Update CSR6 values for media types 0-2 and base
            // Extract bits 0x800200 from CSR6
            csr6Bits = *(unsigned int *)(adapter + 0x5c) & 0x800200;
            *(unsigned int *)(adapter + 0xd8) =
                *(unsigned int *)(adapter + 0xd8) | csr6Bits;  // Media 0 CSR6
            *(unsigned int *)(adapter + 0xf8) =
                *(unsigned int *)(adapter + 0xf8) | csr6Bits;  // Media 1 CSR6
            *(unsigned int *)(adapter + 0x118) =
                *(unsigned int *)(adapter + 0x118) | csr6Bits;  // Media 2 CSR6
            *(unsigned int *)(adapter + 0x178) =
                *(unsigned int *)(adapter + 0x178) | csr6Bits;  // Base CSR6

            // Update CSR6 for media types 3-4
            // Extract bit 0x800000 from CSR6
            csr6Bits = *(unsigned int *)(adapter + 0x5c) & 0x800000;
            *(unsigned int *)(adapter + 0x138) =
                *(unsigned int *)(adapter + 0x138) | csr6Bits;  // Media 3 CSR6
            *(unsigned int *)(adapter + 0x198) =
                *(unsigned int *)(adapter + 0x198) | csr6Bits;  // Media 4 CSR6
            return;
        }

        goto disable_nway;
    }
    else if (chipRevision != 0x141011) {
        // Not a supported chip
        return;
    }

    // DC21140 handling
    boardRevision = *(unsigned int *)(adapter + 8);
    if (boardRevision < 0x10) {
enable_sia_nway:
        // SIA-based N-Way (mode 2)
        *(unsigned char *)(adapter + 4) = 1;
        *(unsigned int *)(adapter + 0x260) = 2;

        // Set bits 6-7 (0xc0) in CSR13 for media types 0-2
        *(unsigned char *)(adapter + 0xd0) =
            *(unsigned char *)(adapter + 0xd0) | 0xc0;  // Media 0 CSR13
        *(unsigned char *)(adapter + 0xf0) =
            *(unsigned char *)(adapter + 0xf0) | 0xc0;  // Media 1 CSR13
        *(unsigned char *)(adapter + 0x110) =
            *(unsigned char *)(adapter + 0x110) | 0xc0;  // Media 2 CSR13

        // Set bit 9 (0x200) in CSR6 for media types 0-2
        *(unsigned int *)(adapter + 0xd8) =
            *(unsigned int *)(adapter + 0xd8) | 0x200;  // Media 0 CSR6
        *(unsigned int *)(adapter + 0xf8) =
            *(unsigned int *)(adapter + 0xf8) | 0x200;  // Media 1 CSR6
        *(unsigned int *)(adapter + 0x118) =
            *(unsigned int *)(adapter + 0x118) | 0x200;  // Media 2 CSR6
        return;
    }

    if (boardRevision > 0x11) {
        // Board revision 0x20
        if (boardRevision != 0x20) goto enable_sia_nway;
        nwayCapable = *(char *)(adapter + 0x1ec);
        goto check_nway_capable;
    }

check_nway_capable:
    if (nwayCapable != 0) {
        // N-Way mode 1
        *(unsigned char *)(adapter + 4) = 1;
        *(unsigned int *)(adapter + 0x260) = 1;
        return;
    }

    // Disable N-Way
    *(unsigned char *)(adapter + 4) = 0;
disable_nway:
    *(unsigned int *)(adapter + 0x260) = 0;
}

/*
 * DC21X4EnableInterrupt
 * Enable interrupts by writing to CSR7 (interrupt mask register)
 */
void DC21X4EnableInterrupt(int adapter)
{
    // Write interrupt mask register
    // TODO: *(unsigned int *)(adapter + 0x1fc) contains the interrupt mask
    // TODO: *(unsigned short *)(adapter + 0x28) is CSR7 port address
    out(*(unsigned short *)(adapter + 0x28), *(unsigned int *)(adapter + 0x1fc));
}

/*
 * DC21X4DynamicAutoSense
 * Handle dynamic auto-sensing with MII and non-MII fallback
 */
void DC21X4DynamicAutoSense(void *timerArg, int adapter)
{
    unsigned int timerDelay;
    char miiLinkOk;
    char continueAutoSense;

    miiLinkOk = 0;
    continueAutoSense = 1;

    // Try MII auto-sense if conditions are met
    if (((*(char *)(adapter + 0x1e6) != 0) &&  // MII ready flag
         (*(int *)(adapter + 0x260) != 3)) &&   // Not in N-Way mode 3
        (*(char *)(adapter + 0x1e9) == 0)) {    // Not disabled flag
        miiLinkOk = DC21X4MiiAutoSense(adapter);
    }

    // Handle PHY re-initialization if needed
    if (*(char *)(adapter + 0x1e8) != 0) {
        // Clear re-init flag
        *(unsigned char *)(adapter + 0x1e8) = 0;

        if (miiLinkOk != 0) goto schedule_timer;

        // Force PHY reset
        timerDelay = 4;  // Reset command
        if ((*(unsigned char *)(adapter + 0x69) & 2) != 0) {
            timerDelay = 5;  // Full duplex reset
        }
        DC21X4SetPhyControl(adapter, timerDelay);
        DC21X4IndicateMediaStatus(adapter, 1);
    }

    // Try non-MII auto-sense if MII failed and media supported
    if ((miiLinkOk == 0) && (*(int *)(adapter + 0x7c) != 0)) {
        continueAutoSense = DC21X4AutoSense(adapter);
    }

schedule_timer:
    // Restart timer if auto-sensing should continue
    if (continueAutoSense != 0) {
        timerDelay = 3000;  // 3 second default
        if (*(char *)(adapter + 0x1e6) != 0) {
            timerDelay = 7000;  // 7 seconds if MII ready
        }
        DC21X4StartAutoSenseTimer(adapter, timerDelay);
    }
}

/*
 * DC21X4DisableNway
 * Disable N-Way auto-negotiation for all chip variants
 */
void DC21X4DisableNway(int adapter)
{
    unsigned int chipRevision;

    // Clear N-Way flags
    *(unsigned char *)(adapter + 4) = 0;
    *(unsigned int *)(adapter + 0x260) = 0;

    chipRevision = *(unsigned int *)(adapter + 0x54);

    if (chipRevision != 0x191011) {
        if (chipRevision > 0x191011) {
            // DC21143
            if (chipRevision != 0xff1011) {
                return;
            }
            // Clear bit 7 (0x80) in CSR13 for media types 0-2
            *(unsigned int *)(adapter + 0xd0) =
                *(unsigned int *)(adapter + 0xd0) & 0xffffff7f;
            *(unsigned int *)(adapter + 0xf0) =
                *(unsigned int *)(adapter + 0xf0) & 0xffffff7f;
            *(unsigned int *)(adapter + 0x110) =
                *(unsigned int *)(adapter + 0x110) & 0xffffff7f;
            goto clear_csr6_bit;
        }

        // DC21140
        if (chipRevision != 0x141011) {
            return;
        }
    }

    // DC21140/DC21142 - Clear bits 6-7 (0xc0) in CSR13 for media types 0-2
    *(unsigned int *)(adapter + 0xd0) =
        *(unsigned int *)(adapter + 0xd0) & 0xffffff3f;
    *(unsigned int *)(adapter + 0xf0) =
        *(unsigned int *)(adapter + 0xf0) & 0xffffff3f;
    *(unsigned int *)(adapter + 0x110) =
        *(unsigned int *)(adapter + 0x110) & 0xffffff3f;

clear_csr6_bit:
    // Clear bit 9 (0x200) in CSR6 for media types 0-2
    *(unsigned int *)(adapter + 0xd8) =
        *(unsigned int *)(adapter + 0xd8) & 0xfffffdff;
    *(unsigned int *)(adapter + 0xf8) =
        *(unsigned int *)(adapter + 0xf8) & 0xfffffdff;
    *(unsigned int *)(adapter + 0x118) =
        *(unsigned int *)(adapter + 0x118) & 0xfffffdff;
}

/*
 * DC21X4DisableInterrupt
 * Disable all interrupts by writing 0 to CSR7
 */
void DC21X4DisableInterrupt(int adapter)
{
    // Write 0 to interrupt mask register (CSR7)
    out(*(unsigned short *)(adapter + 0x28), 0);
}

/*
 * DC21X4AutoSense
 * Complex auto-sensing state machine for media detection
 */
int DC21X4AutoSense(unsigned int adapter)
{
    unsigned char linkStatus;
    unsigned int chipRevision;
    unsigned short csr12Port;
    unsigned int csr12Value;
    int currentMedia;
    int mediaIndex;
    unsigned int *csrPtr;
    BOOL mediaChanged;
    unsigned int csr12Status;
    int autosenseState;
    int countdown;
    BOOL isFullDuplex;
    int newMedia;

    chipRevision = *(unsigned int *)(adapter + 0x54);

    // Handle non-DC21140/DC21142/DC21143 chips first
    if (chipRevision != 0x141011) {
        if (chipRevision > 0x141011) {
            if ((chipRevision != 0x191011) && (chipRevision != 0xff1011)) {
                return 1;
            }
            goto handle_dc21140_family;
        }

        // DC21040 handling
        if (chipRevision == 0x21011) {
            if (*(int *)(adapter + 0x204) != 0) {
                return 0;
            }
            csr12Value = in(*(unsigned short *)(adapter + 0x3c));
            if ((csr12Value & 4) != 0) {
                return 1;
            }
            goto indicate_link_and_exit;
        }

        // DC21041 handling
        if (chipRevision != 0x91011) {
            return 1;
        }

        // Check if media has link status test defined
        if (*(int *)(*(int *)(adapter + 0x84) * 0x20 + 0xe0 + adapter) != 0) {
            // If not in auto-sense mode and MII ready, skip
            if (((*(unsigned char *)(adapter + 0x79) & 8) == 0) &&
                (*(char *)(adapter + 0x1e6) != 0)) {
                return 1;
            }

            // Read CSR12 and check link status
            csr12Status = in(*(unsigned short *)(adapter + 0x3c));
            mediaIndex = *(int *)(adapter + 0x84) * 0x20;
            linkStatus = (*(unsigned int *)(mediaIndex + 0xe0 + adapter) &
                         (csr12Status ^ *(unsigned int *)(mediaIndex + 0xdc + adapter))) != 0;

            DC21X4IndicateMediaStatus(adapter, linkStatus);

            if ((*(unsigned char *)(adapter + 0x79) & 8) == 0) {
                return 1;
            }

            // Try all configured media types
            mediaIndex = *(int *)(adapter + 0x88);
            if (0 < mediaIndex) {
                do {
                    csr12Value = *(unsigned int *)(adapter + 0x9c + mediaIndex * 4);

                    if (*(int *)(adapter + 0x204) == 0) {
                        DC21X4SwitchMedia(adapter, csr12Value);
                        csr12Status = in(*(unsigned short *)(adapter + 0x3c));
                    }
                } while (((*(unsigned int *)(csr12Value * 0x20 + 0xe0 + adapter) &
                          (csr12Status ^ *(unsigned int *)(csr12Value * 0x20 + 0xdc + adapter))) == 0) &&
                        (mediaIndex = mediaIndex - 1, 0 < mediaIndex));

                if (0 < mediaIndex) {
                    mediaChanged = *(unsigned int *)(adapter + 0x84) != csr12Value;
                    goto check_media_change;
                }
            }

            // Fall back to default media
            csr12Value = *(unsigned int *)(adapter + 0x80);
            mediaChanged = FALSE;
            if ((*(char *)(adapter + 0x65) != 0) &&
                (*(unsigned int *)(adapter + 0x84) != csr12Value)) {
                mediaChanged = TRUE;
            }

check_media_change:
            if (!mediaChanged) {
                return 1;
            }

            DC21X4SwitchMedia(adapter, csr12Value);
            in(*(unsigned short *)(adapter + 0x3c));
            return 1;
        }

indicate_link_pass:
        DC21X4IndicateMediaStatus(adapter, 1);
        goto return_mii_status;
    }

handle_dc21140_family:
    // DC21140/DC21142/DC21143 auto-sense state machine
    if ((*(unsigned char *)(adapter + 0x79) & 8) == 0) {
        goto return_mii_status;
    }

    // Check disable flag
    if (*(char *)(adapter + 0x1ee) != 0) {
        *(unsigned char *)(adapter + 0x1ee) = 0;
        return 0;
    }

    // State machine at offset 0x220
    autosenseState = *(int *)(adapter + 0x220);

    switch (autosenseState) {
    case 0:
        // Initial state - continue to default handler
        break;

    case 1:
        // Check if on 10Base-T (media 0)
        if (*(int *)(adapter + 0x84) == 0) {
            return 1;
        }

check_100base_switching:
        // Check if both 100Base-TX and 100Base-T4 supported
        if ((*(unsigned int *)(adapter + 0x7c) & 6) == 6) {
            csr12Value = in(*(unsigned short *)(adapter + 0x3c));

            // Check link status or counters
            if ((((csr12Value & 0x100) == 0) ||
                (3 < *(unsigned int *)(adapter + 0x210))) ||
                (3 < *(unsigned int *)(adapter + 0x214))) {

                // Toggle between media 1 and 2
                mediaIndex = 1;
                if (*(int *)(adapter + 0x84) == 1) {
                    mediaIndex = 2;
                }
                *(int *)(adapter + 0x84) = mediaIndex;

                // Write CSR15
                out(*(unsigned short *)(adapter + 0x48),
                    *(unsigned int *)(mediaIndex * 0x20 + 0xd4 + adapter));

                *(unsigned int *)(adapter + 0x210) = 0;
                *(unsigned int *)(adapter + 0x214) = 0;
            }

            // Write CSR12
            out(*(unsigned short *)(adapter + 0x3c), 0x100);
        }
        return 1;

    case 2:
        // Switch to auto-detect
        *(unsigned int *)(adapter + 0x220) = 0;
        if ((*(unsigned char *)(adapter + 0x79) & 8) != 0) {
            DC21X4SwitchMedia(adapter, 0xff);
        }
        break;

    case 3:
        // Check for 10Base-T link
        *(unsigned int *)(adapter + 0x220) = 0;
        csr12Value = in(*(unsigned short *)(adapter + 0x3c));

        if ((csr12Value & 0x7004) != 0x5000) {
            // No 10Base-T link
            if (*(int *)(adapter + 0x84) != 0) {
                goto check_100base_switching;
            }

            if ((*(unsigned char *)(adapter + 0x79) & 8) == 0) {
                return 0;
            }
            goto switch_to_autodetect;
        }

        // Have 10Base-T link
        if (*(int *)(adapter + 0x84) == 0) {
            goto indicate_link_pass;
        }

        // Schedule state 2 after 5 seconds
        *(unsigned int *)(adapter + 0x220) = 2;
        DC21X4StartTimer(adapter, 5000);
        csrPtr = (unsigned int *)adapter;
        goto switch_to_media_0;

    case 4:
        // Check CSR12 for link
        *(unsigned int *)(adapter + 0x220) = 0;
        csr12Value = in(*(unsigned short *)(adapter + 0x3c));

        if ((csr12Value & 0x7004) == 0x5000) {
            DC21X4IndicateMediaStatus(adapter, 1);
            goto return_mii_status;
        }

        linkStatus = *(unsigned char *)(adapter + 0x79);
        goto check_autosense_enabled;

    case 5:
        // Check CSR12 bit 1
        *(unsigned int *)(adapter + 0x220) = 0;
        csr12Value = in(*(unsigned short *)(adapter + 0x3c));

        if ((csr12Value & 2) == 0) {
            DC21X4IndicateMediaStatus(adapter, 1);
            goto return_mii_status;
        }

        linkStatus = *(unsigned char *)(adapter + 0x79);
check_autosense_enabled:
        if ((linkStatus & 8) == 0) {
return_mii_status:
            return (int)*(char *)(adapter + 0x1e6);
        }

switch_to_autodetect:
        csrPtr = (unsigned int *)0xff;
switch_to_media_0:
        DC21X4SwitchMedia(adapter, (unsigned int)csrPtr);
        break;

    case 6:
        // N-Way negotiation monitoring
        countdown = *(int *)(adapter + 0x20c);
        *(int *)(adapter + 0x20c) = countdown - 1;

        if (countdown == 0) {
            goto nway_failed;
        }

        csr12Value = in(*(unsigned short *)(adapter + 0x3c));
        csr12Status = csr12Value & 0x7000;

        if (csr12Status == 0x4000) {
save_csr12:
            *(unsigned int *)(adapter + 0x21c) = csr12Value;
restart_timer_100ms:
            DC21X4StartTimer(adapter, 100);
        }
        else {
            if (csr12Status < 0x4001) {
                if (csr12Status == 0x3000) goto save_csr12;
                goto restart_timer_100ms;
            }

            if (csr12Status != 0x5000) {
                goto restart_timer_100ms;
            }

            // Link pass detected
            if ((short)csr12Value < 0) {
                // Analyze N-Way results
                if (*(int *)(adapter + 0x21c) == 0) {
                    *(unsigned int *)(adapter + 0x20c) = 0x28;
                    goto restart_nway;
                }

                if ((*(unsigned int *)(adapter + 0x21c) & 0x1f0000) != 0x10000) {
nway_failed:
                    newMedia = 0xff;
                    goto setup_media;
                }

                if ((*(unsigned char *)(adapter + 0x21e) & 0x40) == 0) {
                    if ((*(unsigned char *)(adapter + 0x21e) & 0x20) != 0) {
                        newMedia = 0;
                        goto setup_media;
                    }
                    goto nway_failed;
                }

                newMedia = 0;
                isFullDuplex = TRUE;
setup_media:
                *(unsigned int *)(adapter + 0x220) = 0;
                *(unsigned int *)(adapter + 0x21c) = 0;

                DC21X4StopReceiverAndTransmitter(adapter);

                if (isFullDuplex) {
                    *(unsigned int *)(adapter + 0x68) =
                        *(unsigned int *)(adapter + 0x68) | 0x200;
                }
                else {
                    *(unsigned int *)(adapter + 0x68) =
                        *(unsigned int *)(adapter + 0x68) & 0xfffffdff;
                }

                *(unsigned char *)(adapter + 0x1eb) = 0;

                if (newMedia == 0xff) {
                    DC21X4SwitchMedia(adapter, 0xff);
                    out(*(unsigned short *)(adapter + 0x24),
                        *(unsigned int *)(adapter + 0x68));
                    return 0;
                }

                // Reset CSR13
                out(*(unsigned short *)(adapter + 0x40), 0);
                _IODelay(10000);

                out(*(unsigned short *)(adapter + 0x24),
                    *(unsigned int *)(adapter + 0x68));

                if (isFullDuplex) {
                    *(char **)(adapter + 0xd0) = "\n";
                }
                else {
                    *(char **)(adapter + 0xd0) =
                        "%s: Invalid IRQ level (%d) assigned by PCI BIOS\n";
                }

                // Write SIA registers
                if ((*(int *)(adapter + 0x54) == 0x191011) ||
                    (*(int *)(adapter + 0x54) == 0xff1011)) {
                    csr12Value = *(unsigned int *)(adapter + 0x58) & 0xffff0000 |
                                (unsigned int)*(unsigned short *)(
                                    *(int *)(adapter + 0x84) * 0x20 + 0xd4 + adapter);
                    *(unsigned int *)(adapter + 0x58) = csr12Value;
                    csr12Port = *(unsigned short *)(adapter + 0x48);
                }
                else {
                    csr12Port = *(unsigned short *)(adapter + 0x48);
                    csr12Value = *(unsigned int *)(
                        *(int *)(adapter + 0x84) * 0x20 + 0xd4 + adapter);
                }

                out(csr12Port, csr12Value);
                out(*(unsigned short *)(adapter + 0x44),
                    *(unsigned int *)(adapter + 0xd0));
                out(*(unsigned short *)(adapter + 0x40),
                    *(unsigned int *)(adapter + 0xcc));

indicate_link_and_exit:
                DC21X4IndicateMediaStatus(adapter, 1);
                return 0;
            }

            // Increment link pass counter
            *(int *)(adapter + 0x218) = *(int *)(adapter + 0x218) + 1;

            if (1 < *(int *)(adapter + 0x218)) {
                newMedia = 0;
                isFullDuplex = FALSE;
                goto setup_media;
            }

            // Go to state 7 after 500ms
            *(unsigned int *)(adapter + 0x220) = 7;
            DC21X4StartTimer(adapter, 500);
        }
        break;

    case 7:
        // Restart N-Way negotiation
        *(unsigned int *)(adapter + 0x20c) = 0x28;
        *(unsigned int *)(adapter + 0x21c) = 0;

restart_nway:
        out(*(unsigned short *)(adapter + 0x3c), 0x1000);
        *(unsigned int *)(adapter + 0x220) = 6;
        goto restart_timer_100ms;

    default:
        return 1;
    }

    return 0;
}

/*
 * DC2114Sense100BaseTxLink
 * Sense 100Base-TX link on DC21140 family chips
 */
BOOL DC2114Sense100BaseTxLink(int adapter)
{
    int outerRetries;
    unsigned int csr6Value;
    unsigned int csr12Value;
    int requiredStability;
    int innerCounter;
    int watchdogCount;
    int linkStartCount;
    BOOL linkDetected;
    BOOL checkRevision;
    BOOL exitInnerLoop;
    unsigned int timerCount;
    unsigned int csr12Status;
    BOOL linkStable;
    int checkLoops;

    outerRetries = 4;
    linkDetected = FALSE;

    // Disable watchdog timer interrupt (bit 11)
    out(*(unsigned short *)(adapter + 0x28),
        *(unsigned int *)(adapter + 0x1fc) & 0xfffff7ff);

    // Prepare CSR6 value (clear mode bits, use media 3 settings without PS bit)
    csr6Value = *(unsigned int *)(adapter + 0x68) & 0xfc333dff |
                *(unsigned int *)(adapter + 0x138) & 0xfeffffff;

    // Determine timer count based on CSR6 bit 2
    timerCount = 0xc;  // 12
    if ((*(unsigned char *)(adapter + 0xda) & 4) != 0) {
        timerCount = 3;
    }

    do {
        outerRetries--;
        if ((outerRetries < 0) || (linkDetected != FALSE)) {
            // Re-enable watchdog timer interrupt
            out(*(unsigned short *)(adapter + 0x20), 0x800);
            out(*(unsigned short *)(adapter + 0x28),
                *(unsigned int *)(adapter + 0x1fc));
            return linkDetected;
        }

        // Check board revision
        checkRevision = *(int *)(adapter + 8) != 0x11;
        innerCounter = 1;
        exitInnerLoop = FALSE;

        while (!exitInnerLoop) {
            // Determine stability requirement based on board revision
            requiredStability = 400;
            if (checkRevision) {
                requiredStability = 2;
            }
            watchdogCount = requiredStability * 3;

            // Try 100Base-TX (media 3) if supported
            if ((*(unsigned char *)(adapter + 0x7c) & 8) != 0) {
                // Configure CSR6
                csr12Value = csr6Value;
                if (checkRevision) {
                    csr12Value = csr6Value | 0x1000000;  // Set PS bit
                }
                out(*(unsigned short *)(adapter + 0x24), csr12Value);

                // Write CSR12
                out(*(unsigned short *)(adapter + 0x3c),
                    *(unsigned int *)(adapter + 0x128));

                linkStartCount = 0;
                watchdogCount = 0;

                // Start watchdog timer (CSR11)
                out(*(unsigned short *)(adapter + 0x38), 0x1001e);

                // Monitor link stability
                if ((watchdogCount != 0xffffffff) && (linkDetected == FALSE)) {
                    do {
                        // Check for watchdog timeout
                        csr12Status = in(*(unsigned short *)(adapter + 0x20));
                        if ((csr12Status & 0x800) != 0) {
                            // Clear watchdog timeout bit
                            out(*(unsigned short *)(adapter + 0x20), 0x800);
                            watchdogCount++;
                        }

                        // Check CSR12 link status
                        csr12Status = in(*(unsigned short *)(adapter + 0x3c));
                        if ((*(unsigned int *)(adapter + 0x140) &
                            (csr12Status ^ *(unsigned int *)(adapter + 0x13c))) == 0) {
                            // No link
                            linkStartCount = 0;
                        }
                        else if (linkStartCount == 0) {
                            // Link just appeared
                            linkStartCount = watchdogCount + 1;
                        }
                        else {
                            // Check if link stable for required duration
                            linkDetected = requiredStability <= watchdogCount - linkStartCount;
                        }
                    } while ((watchdogCount < (requiredStability * 3 + 1)) &&
                            (linkDetected == FALSE));
                }

                // Stop watchdog timer
                out(*(unsigned short *)(adapter + 0x38), 0);

                // Clear watchdog timeout status
                out(*(unsigned short *)(adapter + 0x20), 0x800);

                if (linkDetected != FALSE) {
                    // Found stable 100Base-TX link
                    *(unsigned int *)(adapter + 0x84) = 3;
                    *(unsigned int *)(adapter + 0x68) =
                        *(unsigned int *)(adapter + 0x68) & 0xfc333dff;
                    csr12Value = *(unsigned int *)(adapter + 0x68) |
                                *(unsigned int *)(adapter + 0x138);
                    *(unsigned int *)(adapter + 0x68) = csr12Value;

                    if (!checkRevision) {
                        out(*(unsigned short *)(adapter + 0x24), csr12Value);
                    }
                    break;
                }
            }

            // Try 10Base-T (media 0) if 100Base-TX failed
            if ((*(unsigned char *)(adapter + 0x7c) & 1) == 0) {
check_exit:
                if (linkDetected != FALSE) goto cleanup_and_continue;

                if (innerCounter != 0) {
                    if (!checkRevision) {
                        outerRetries = 0;
                        break;
                    }
                    checkRevision = FALSE;
                    innerCounter = 2;
                }
            }
            else {
                // Configure for 10Base-T
                out(*(unsigned short *)(adapter + 0x24),
                    *(unsigned int *)(adapter + 0x68) & 0xfc333dff |
                    *(unsigned int *)(adapter + 0xd8));

                // Write CSR12
                out(*(unsigned short *)(adapter + 0x3c),
                    *(unsigned int *)(adapter + 200));

                // Start watchdog timer
                out(*(unsigned short *)(adapter + 0x38),
                    (watchdogCount >> 1) * timerCount);

                if (linkDetected == FALSE) {
                    do {
                        checkLoops = 0;
                        linkStable = TRUE;

                        // Check link status twice for stability
                        do {
                            csr12Status = in(*(unsigned short *)(adapter + 0x3c));
                            linkDetected = FALSE;

                            if ((linkStable != FALSE) &&
                                ((*(unsigned int *)(adapter + 0xe0) &
                                 (csr12Status ^ *(unsigned int *)(adapter + 0xdc))) != 0)) {
                                linkDetected = TRUE;
                            }
                            linkStable = linkDetected;
                            checkLoops++;
                        } while (checkLoops < 2);

                        // Check watchdog timeout
                        csr12Status = in(*(unsigned short *)(adapter + 0x20));
                    } while (((csr12Status & 0x800) == 0) && (linkDetected == FALSE));

                    goto check_exit;
                }

cleanup_and_continue:
                // Stop watchdog timer
                out(*(unsigned short *)(adapter + 0x38), 0);

                // Clear watchdog timeout
                out(*(unsigned short *)(adapter + 0x20), 0x800);

                if (innerCounter == 0) {
                    // Found 10Base-T link
                    *(unsigned int *)(adapter + 0x84) = 0;
                    *(unsigned int *)(adapter + 0x68) =
                        *(unsigned int *)(adapter + 0x68) & 0xfc333dff;
                    *(unsigned int *)(adapter + 0x68) =
                        *(unsigned int *)(adapter + 0x68) | *(unsigned int *)(adapter + 0xd8);
                }
                else {
                    linkDetected = FALSE;
                }
            }

            if (innerCounter == 0) break;
            innerCounter--;
            exitInnerLoop = linkDetected != FALSE;
        }
    } while (TRUE);
}

/*
 * DC2104InitializeSiaRegisters
 * Initialize Serial Interface Adapter registers for DC21040/DC21140/DC21142/DC21143
 */
void DC2104InitializeSiaRegisters(int adapter, unsigned int resetValue)
{
    int chipRevision;
    unsigned short csr15Port;
    unsigned int csr15Value;
    unsigned int currentMedia;
    unsigned int delayCount;

    // Reset CSR13 (SIA Connectivity)
    out(*(unsigned short *)(adapter + 0x40), 0);

    // Wait 10ms (2 * 5ms)
    delayCount = 0;
    do {
        _IODelay(5000);
        delayCount++;
    } while (delayCount < 2);

    chipRevision = *(int *)(adapter + 0x54);

    // Get current media index
    currentMedia = *(int *)(adapter + 0x84);

    if ((chipRevision == 0x191011) || (chipRevision == 0xff1011)) {
        // DC21142/DC21143: CSR15 is 32-bit, lower 16 bits from media config
        csr15Value = *(unsigned int *)(adapter + 0x58) & 0xffff0000 |
                    (unsigned int)*(unsigned short *)(currentMedia * 0x20 + 0xd4 + adapter);
        *(unsigned int *)(adapter + 0x58) = csr15Value;
        csr15Port = *(unsigned short *)(adapter + 0x48);
    }
    else {
        // DC21040/DC21140: CSR15 value from media config
        csr15Port = *(unsigned short *)(adapter + 0x48);
        csr15Value = *(unsigned int *)(currentMedia * 0x20 + 0xd4 + adapter);
    }

    // Write CSR15 (SIA General Register)
    out(csr15Port, csr15Value);

    // Write CSR14 (SIA Transmit/Receive Register)
    out(*(unsigned short *)(adapter + 0x44),
        *(unsigned int *)(currentMedia * 0x20 + 0xd0 + adapter));

    // Write CSR13 (SIA Connectivity Register)
    out(*(unsigned short *)(adapter + 0x40),
        *(unsigned int *)(currentMedia * 0x20 + 0xcc + adapter));
}

/*
 * DC21040Parser
 * Parse SROM data for DC21040 chip (which doesn't have real SROM)
 */
BOOL DC21040Parser(int adapter)
{
    BOOL validChecksum;
    unsigned char sromByte;
    int readAttempts;
    int readValue;
    int remainingAttempts;
    BOOL readSuccess;
    unsigned int byteIndex;
    unsigned char sromBuffer[0x48];
    unsigned int macAddress;
    short macAddress2;

    // DC21040 supports 10Base-T, 10Base-2, and AUI (media types 0, 1, 2)
    *(unsigned int *)(adapter + 0x7c) = 7;

    // Reset CSR9 (Boot ROM/SROM Address)
    out(*(unsigned short *)(adapter + 0x30), 0);

    // Read 32 bytes from SROM
    byteIndex = 0;
    do {
        readAttempts = 0x32;  // 50 attempts

        // Wait for SROM read ready
        do {
            _IODelay(1000);
            readValue = in(*(unsigned short *)(adapter + 0x30));
            remainingAttempts = readAttempts;

            if (readValue >= 0) break;  // Bit 31 clear = ready

            remainingAttempts = readAttempts - 1;
            readSuccess = 0 < readAttempts;
            readAttempts = remainingAttempts;
        } while (readSuccess);

        if (remainingAttempts < 1) {
            goto return_failure;
        }

        sromByte = (unsigned char)readValue;
        sromBuffer[byteIndex] = sromByte;
        byteIndex++;
    } while (byteIndex < 0x20);

    // Check if SROM is valid
    macAddress = *(unsigned int *)sromBuffer;
    macAddress2 = *(short *)&sromBuffer[4];

    if ((macAddress == 0) && (macAddress2 == 0)) {
        // Empty SROM - assume valid
        *(unsigned char *)(adapter + 0x52) = 0;
    }
    else if ((macAddress & 0xffffff) == 0x95c000) {
        // Known vendor prefix (DEC)
        *(unsigned char *)(adapter + 0x52) = 1;
    }
    else {
        // Verify checksum
        validChecksum = VerifyChecksum(sromBuffer);
        *(unsigned char *)(adapter + 0x52) = validChecksum;
    }

    if (*(char *)(adapter + 0x52) == 0) {
return_failure:
        return FALSE;
    }

    // Copy MAC address
    _bcopy(sromBuffer, (void *)(adapter + 0x4c), 6);

    // Setup media 0 configuration (10Base-T)
    *(unsigned int *)(adapter + 0xcc) = 0x00008f01;  // CSR13
    *(unsigned int *)(adapter + 0xd0) = 0x0000ffff;  // CSR14
    *(unsigned int *)(adapter + 0xd4) = 0x00000000;  // CSR15

    // Setup media 1 configuration (10Base-2/BNC)
    *(unsigned int *)(adapter + 0xec) = 0x0000ef09;  // CSR13
    *(unsigned int *)(adapter + 0xf0) = 0x00000705;  // CSR14
    *(unsigned int *)(adapter + 0xf4) = 0x00000006;  // CSR15

    // Setup media 2 configuration (AUI)
    *(unsigned int *)(adapter + 0x10c) = 0x00008f09;  // CSR13
    *(unsigned int *)(adapter + 0x110) = 0x00000705;  // CSR14
    *(unsigned int *)(adapter + 0x114) = 0x00000006;  // CSR15

    return TRUE;
}

/*
 * CRC32
 * Calculate CRC32 checksum using lookup table
 */
unsigned int CRC32(unsigned char *data, int length)
{
    unsigned int crc;

    crc = 0xffffffff;

    while (length = length - 1, length != -1) {
        crc = crc >> 8 ^ CrcTable[(unsigned char)((unsigned char)crc ^ *data)];
        data = data + 1;
    }

    return ~crc;
}
