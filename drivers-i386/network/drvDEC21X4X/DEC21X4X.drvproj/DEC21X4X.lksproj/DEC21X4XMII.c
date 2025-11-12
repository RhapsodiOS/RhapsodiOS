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
 * DEC21X4XMII.c
 * MII (Media Independent Interface) routines for DEC 21x4x Ethernet driver
 */

#include "DEC21X4X.h"

// PHY register reserved bits masks
// Used to preserve reserved bits when writing to PHY registers
static const unsigned short PhyRegsReservedBitsMasks[PHY_REGS_COUNT] = {
    0x0000,  // Reg 0: Control register - no reserved bits
    0x0000,  // Reg 1: Status register - read-only
    0x0000,  // Reg 2: PHY ID 1 - read-only
    0x0000,  // Reg 3: PHY ID 2 - read-only
    0x0000,  // Reg 4: Auto-negotiation advertisement
    0x0000,  // Reg 5: Auto-negotiation link partner ability
    0x0000,  // Reg 6: Auto-negotiation expansion
    0x0000,  // Reg 7: Auto-negotiation next page
    0x0000,  // Reg 8: Reserved
    0x0000,  // Reg 9: 1000Base-T control
    0x0000,  // Reg 10: 1000Base-T status
    0x0000,  // Reg 11: Reserved
    0x0000,  // Reg 12: Reserved
    0x0000,  // Reg 13: Reserved
    0x0000,  // Reg 14: Reserved
    0x0000   // Reg 15: Extended status
};

// Admin control conversion table
// Maps admin control commands to MII control register bits
static const unsigned int _AdminControlConversionTable[] = {
    0x8000,  // 0: Reset PHY
    0x1000,  // 1: Enable auto-negotiation
    0x0000,  // 2: Disable
    0x4000,  // 3: Loopback
    0x0000,  // 4: Power down (bits cleared separately)
    0x0000,  // 5: Isolate (bits cleared separately)
    0x0000   // 6: Restore (value restored from saved state)
};

/*
 * FindAndInitMiiPhys
 * Find and initialize all MII PHYs on the bus
 *
 * Parameters:
 *   adapter - Adapter info structure
 *
 * Returns:
 *   1 if at least one PHY was found and initialized, 0 otherwise
 *
 * Scans all 32 possible PHY addresses (0-31) looking for valid PHYs.
 * Allocates PHY structure if needed, initializes function pointers,
 * and attempts to initialize each PHY found.
 */
int FindAndInitMiiPhys(int adapter)
{
    BOOL retryFromZero;
    char initSuccess;
    int phyAddress;
    void *phyStructure;
    int currentPhyIndex;

    phyAddress = 0;
    retryFromZero = TRUE;

    // Get PHY structure pointer location
    // Array at offset 0x22c, indexed by value at offset 500 (0x1f4)
    currentPhyIndex = *(int *)(adapter + 500);

    // Allocate PHY structure if not already allocated
    if (*(int *)(adapter + 0x22c + currentPhyIndex * 4) == 0) {
        phyStructure = IOMalloc(0x80);
        *(void **)(adapter + 0x22c + currentPhyIndex * 4) = phyStructure;

        if (*(int *)(adapter + 0x22c + currentPhyIndex * 4) == 0) {
            // Allocation failed
            return 0;
        }
    }

    // Initialize PHY function pointers
    InitPhyInfoEntries(*(int *)(adapter + 0x22c + currentPhyIndex * 4));

    // Scan all PHY addresses (0-31)
    while (TRUE) {
        if (phyAddress > 0x1f) {
            // No PHY found after scanning all addresses - free memory
            IOFree(*(void **)(adapter + 0x22c + currentPhyIndex * 4), 0x80);
            *(int *)(adapter + 0x22c + currentPhyIndex * 4) = 0;
            return 0;
        }

        // Store PHY address at offset 2 in PHY structure
        *(short *)(*(int *)(adapter + 0x22c + currentPhyIndex * 4) + 2) =
            (short)phyAddress;

        // Try to initialize PHY at this address
        initSuccess = MiiPhyInit(adapter,
                                   *(int *)(adapter + 0x22c + currentPhyIndex * 4));

        if (initSuccess != 0) {
            // PHY found and initialized successfully
            break;
        }

        // Check if we should retry from address 0
        // Flag at offset 0x1ea indicates retry capability
        if ((*(char *)(adapter + 0x1ea) == 0) || (!retryFromZero)) {
            // Continue to next address
            phyAddress = phyAddress + 1;
        }
        else {
            // First pass failed, retry from address 0
            retryFromZero = FALSE;
            phyAddress = 0;
        }
    }

    // PHY found - increment PHY count at offset 0x224
    *(short *)(adapter + 0x224) = *(short *)(adapter + 0x224) + 1;

    return 1;
}

/*
 * FindMiiPhyDevice
 * Find and read MII PHY registers
 *
 * Parameters:
 *   adapter - Adapter info structure
 *   phyAddr - PHY structure pointer
 *
 * Returns:
 *   TRUE if PHY found and status register is non-zero
 *
 * Reads PHY registers 0-31 and stores them in the PHY structure.
 * Combines registers 2 and 3 to form the 32-bit PHY ID.
 * Different PHY types require different numbers of readable registers.
 */
BOOL FindMiiPhyDevice(void *adapter, int phyAddr)
{
    char success;
    unsigned short regIndex;
    unsigned int regIndex32;
    unsigned short regValue;

    // Read first 2 registers (control and status)
    regIndex = 0;
    do {
        // Read register using function pointer at offset 0x6c
        success = (*(char (**)(void *, int, unsigned short, unsigned short *))(phyAddr + 0x6c))
                    (adapter, phyAddr, regIndex, &regValue);

        if (success == 0) {
            return FALSE;
        }

        // Store at offset 0xc + register_index * 2
        *(unsigned short *)(phyAddr + 0xc + (unsigned int)regIndex * 2) = regValue;
        regIndex = regIndex + 1;
    } while (regIndex < 2);

    // Try to read registers 2-3 (PHY ID)
    if (regIndex < 4) {
        do {
            success = (*(char (**)(void *, int, unsigned int, unsigned short *))(phyAddr + 0x6c))
                        (adapter, phyAddr, (unsigned int)regIndex, &regValue);

            if (success == 0) {
                break;
            }

            *(unsigned short *)(phyAddr + 0xc + (unsigned int)regIndex * 2) = regValue;
            regIndex = regIndex + 1;
        } while (regIndex < 4);

        if (regIndex <= 3) {
            goto check_minimum_registers;
        }
    }

    // Combine registers 2 and 3 into 32-bit PHY ID at offset 4
    // Register 2 at offset 0x10 (0xc + 2*2), register 3 at offset 0x12 (0xc + 3*2)
    *(unsigned int *)(phyAddr + 4) =
        ((unsigned int)(*(unsigned short *)(phyAddr + 0x10)) << 16) |
        (unsigned int)(*(unsigned short *)(phyAddr + 0x12));

check_minimum_registers:
    // Read remaining registers 4-31
    regIndex32 = 4;
    do {
        regIndex = (unsigned short)regIndex32;
        success = (*(char (**)(void *, int, unsigned int, unsigned short *))(phyAddr + 0x6c))
                    (adapter, phyAddr, regIndex32, &regValue);

        if (success == 0) {
            break;
        }

        *(unsigned short *)(phyAddr + 0xc + regIndex32 * 2) = regValue;
        regIndex = regIndex + 1;
        regIndex32 = (unsigned int)regIndex;
    } while (regIndex < 0x20);

    // Check PHY ID and verify minimum readable registers
    if ((*(int *)(phyAddr + 4) == 0x3e00000) || (*(int *)(phyAddr + 4) == 0x20005c00)) {
        // Broadcom or Level One PHY - need all 32 registers
        if (regIndex > 0x1f) {
            goto check_status_register;
        }
    }
    else {
        // Other PHY - need at least registers 0-7
        if ((regIndex > 5) && (regIndex > 6)) {
check_status_register:
            // Return true if status register (reg 1 at offset 0xe) is non-zero
            return *(short *)(phyAddr + 0xe) != 0;
        }
    }

    return FALSE;
}

/*
 * GetBroadcomPhyConnectionType
 * Get connection type for Broadcom PHY
 *
 * Parameters:
 *   adapter - Adapter info structure
 *   phyAddr - PHY structure pointer
 *   connectionType - Output pointer for connection type
 *
 * Returns:
 *   TRUE if connection type was successfully determined
 *
 * Reads Broadcom-specific register 0x10 to determine speed,
 * then determines duplex from control register.
 */
int GetBroadcomPhyConnectionType(void *adapter, int phyAddr, unsigned short *connectionType)
{
    char success;
    unsigned short resultValue;
    unsigned char regLowByte;
    unsigned char regHighByte;

    // Read Broadcom auxiliary status register (register 0x10)
    success = (*(char (**)(void *, int, int, unsigned char *))(phyAddr + 0x6c))
                (adapter, phyAddr, 0x10, &regLowByte);

    if ((success != 0) && ((regHighByte & 1) != 0)) {
        // Read control register (register 0)
        success = (*(char (**)(void *, int, int, int))(phyAddr + 0x6c))
                    (adapter, phyAddr, 0, phyAddr + 0xc);

        if (success != 0) {
            // Check bit 1 of register 0x10 (speed bit)
            if ((regLowByte & 2) == 0) {
                // 10Mbps
                resultValue = 9;  // MII 10BaseT half-duplex

                // Check duplex bit (bit 0) in control register at offset 0xd
                if ((*(unsigned char *)(phyAddr + 0xd) & 1) != 0) {
                    resultValue = 0x20a;  // MII 10BaseT full-duplex
                }

                *connectionType = resultValue;
            }
            else {
                // 100Mbps
                *connectionType = 0xf;  // 100BaseTX
            }

            // Check if N-Way enabled (bit 4 of control register)
            if ((*(unsigned char *)(phyAddr + 0xd) & 0x10) != 0) {
                // Add N-Way flag (0x900)
                *connectionType = *connectionType | 0x900;
            }

            return 1;
        }
    }

    return 0;
}

/*
 * HandleBroadcomMediaChangeFrom10To100
 * Handle Broadcom PHY media change from 10Mbps to 100Mbps
 *
 * Parameters:
 *   adapter - Adapter info structure
 *   phyAddr - PHY structure pointer
 *
 * Detects when Broadcom PHY transitions from 10Mbps to 100Mbps
 * and resets the PHY if needed.
 */
void HandleBroadcomMediaChangeFrom10To100(void *adapter, int phyAddr)
{
    unsigned short auxStatusReg;

    // Read Broadcom auxiliary status register (register 0x10)
    (*(void (**)(void *, int, int, unsigned short *))(phyAddr + 0x6c))
        (adapter, phyAddr, 0x10, &auxStatusReg);

    // Check if register changed and both bits 8 and 1 are now set (0x102)
    // Also check that bit 1 was previously clear in saved value at offset 0x2c
    if ((*(unsigned short *)(phyAddr + 0x2c) != auxStatusReg) &&
        ((auxStatusReg & 0x102) == 0x102) &&
        ((*(unsigned char *)(phyAddr + 0x2c) & 2) == 0)) {
        // Media changed from 10 to 100 - reset PHY
        // Call AdminControl with reset command (0)
        (*(void (**)(void *, int, int))(phyAddr + 0x68))
            (adapter, phyAddr, 0);

        // Write control register back (register 0)
        (*(void (**)(void *, int, int, unsigned short))(phyAddr + 0x70))
            (adapter, phyAddr, 0, *(unsigned short *)(phyAddr + 0xc));
    }

    // Save new auxiliary status value at offset 0x2c
    *(unsigned short *)(phyAddr + 0x2c) = auxStatusReg;
}

/*
 * InitPhyInfoEntries
 * Initialize PHY structure function pointers
 *
 * Parameters:
 *   phyAddr - PHY structure pointer
 *
 * Sets up all function pointers in the PHY structure to point to
 * the appropriate MII PHY management functions.
 */
void InitPhyInfoEntries(int phyAddr)
{
    // Initialize all PHY function pointers
    *(void (**)(void *, int))(phyAddr + 0x50) = MiiPhyInit;
    *(void (**)(int, unsigned short *))(phyAddr + 0x54) = MiiPhyGetCapabilities;
    *(int (**)(void *, int, unsigned short, unsigned short))(phyAddr + 0x58) = MiiPhySetConnectionType;
    *(int (**)(void *, int, unsigned short *))(phyAddr + 0x5c) = MiiPhyGetConnectionType;
    *(int (**)(void *, int, unsigned short *))(phyAddr + 0x60) = MiiPhyGetConnectionStatus;
    *(void (**)(int, int, unsigned int))(phyAddr + 0x68) = MiiPhyAdminControl;
    *(void (**)(void *, int, unsigned int *))(phyAddr + 100) = MiiPhyAdminStatus;
    *(char (**)(void *, int, int, unsigned short *))(phyAddr + 0x6c) = MiiPhyReadRegister;
    *(void (**)(void *, int, int, unsigned short))(phyAddr + 0x70) = MiiPhyWriteRegister;
    *(void (**)(void *, int, unsigned short *))(phyAddr + 0x74) = MiiPhyNwayGetLocalAbility;
    *(void (**)(void *, int, unsigned short))(phyAddr + 0x78) = MiiPhyNwaySetLocalAbility;
    *(void (**)(void *, int, unsigned short *))(phyAddr + 0x7c) = MiiPhyNwayGetPartnerAbility;
}

/*
 * MiiGenGetConnection
 * Generic MII get connection - gets connection status then connection type
 *
 * Parameters:
 *   adapter - Adapter info structure
 *   connectionType - Output pointer for connection type
 *
 * Returns:
 *   Success/failure
 */
int MiiGenGetConnection(int adapter, unsigned short *connectionType)
{
    char success;
    int phyAddr;

    // Get PHY structure pointer
    phyAddr = *(int *)(adapter + 0x22c + *(int *)(adapter + 500) * 4);

    // First check connection status (function pointer at offset 0x60)
    success = (*(char (**)(int, int, unsigned short *))(phyAddr + 0x60))
                (adapter, phyAddr, connectionType);

    if (success == 0) {
        // Connection status failed - return 0xffff
        *connectionType = 0xffff;
        return 0;
    }
    else {
        // Connection status OK - now get connection type
        // Get PHY structure pointer again
        phyAddr = *(int *)(adapter + 0x22c + *(int *)(adapter + 500) * 4);

        // Get connection type (function pointer at offset 0x5c)
        success = (*(char (**)(int, int, unsigned short *))(phyAddr + 0x5c))
                    (adapter, phyAddr, connectionType);

        return (int)success;
    }
}

/*
 * MiiGenGetCapabilities
 * Generic MII get capabilities - returns accumulated capabilities
 *
 * Parameters:
 *   adapter - Adapter info structure
 *
 * Returns:
 *   Capabilities bitmap from adapter offset 0x226
 */
unsigned short MiiGenGetCapabilities(int adapter)
{
    // Return accumulated capabilities at offset 0x226
    return *(unsigned short *)(adapter + 0x226);
}

/*
 * MiiGenCheckConnection
 * Generic MII check connection support
 *
 * Parameters:
 *   adapter - Adapter info structure
 *   connectionType - Connection type to check
 *
 * Returns:
 *   TRUE if connection type is supported
 */
int MiiGenCheckConnection(int adapter, unsigned short connectionType)
{
    char success;
    int phyAddr;

    // Get PHY structure pointer
    phyAddr = *(int *)(adapter + 0x22c + *(int *)(adapter + 500) * 4);

    // Check if connection type is supported
    success = CheckConnectionSupport(phyAddr, connectionType);

    return (int)success;
}

/*
 * MiiGenAdminStatus
 * Generic MII admin status - delegates to PHY-specific function
 *
 * Parameters:
 *   adapter - Adapter info structure
 *   status - Output pointer for status value
 */
void MiiGenAdminStatus(int adapter, unsigned int status)
{
    int phyAddr;

    // Get PHY structure pointer
    phyAddr = *(int *)(adapter + 0x22c + *(int *)(adapter + 500) * 4);

    // Call PHY-specific AdminStatus function (offset 100 = 0x64)
    (*(void (**)(int, int, unsigned int))(phyAddr + 100))
        (adapter, phyAddr, status);
}

/*
 * MiiGenAdminControl
 * Generic MII admin control - delegates to PHY-specific function and updates state
 *
 * Parameters:
 *   adapter - Adapter info structure
 *   control - Control command (0-6)
 *
 * Returns:
 *   1 for valid commands, 0 for invalid
 *
 * Control commands:
 *   0 - Reset PHY
 *   1 - Enable auto-negotiation
 *   2 - Disable
 *   3 - Loopback
 *   4 - Power down
 *   5 - Isolate
 *   6 - Restore
 */
unsigned int MiiGenAdminControl(int adapter, unsigned short control)
{
    int phyAddr;

    // Get PHY structure pointer
    phyAddr = *(int *)(adapter + 0x22c + *(int *)(adapter + 500) * 4);

    // Call PHY-specific AdminControl function (offset 0x68)
    (*(void (**)(int, int, unsigned short))(phyAddr + 0x68))
        (adapter, phyAddr, control);

    // Update adapter state based on control command
    switch (control) {
    case 0:  // Reset
    case 1:  // Enable auto-negotiation
    case 4:  // Power down
    case 5:  // Isolate
    case 6:  // Restore
        // Store current PHY index at offset 0x228
        *(unsigned short *)(adapter + 0x228) = *(unsigned short *)(adapter + 500);
        break;

    case 2:  // Disable
    case 3:  // Loopback
        // Set PHY index to 0xff (invalid/disabled)
        *(unsigned short *)(adapter + 0x228) = 0xff;
        break;

    default:
        // Invalid command
        return 0;
    }

    return 1;
}

/*
 * MiiFreeResources
 * Free MII PHY structure memory
 *
 * Parameters:
 *   adapter - Adapter info structure
 */
void MiiFreeResources(int adapter)
{
    int phyAddr;

    // Get PHY structure pointer
    phyAddr = *(int *)(adapter + 0x22c + *(int *)(adapter + 500) * 4);

    if (phyAddr != 0) {
        // Free PHY structure (size 0x80 = 128 bytes)
        IOFree((void *)phyAddr, 0x80);

        // Clear PHY pointer
        *(int *)(adapter + 0x22c + *(int *)(adapter + 500) * 4) = 0;
    }
}

/*
 * MiiGenGetConnectionStatus
 * Generic MII get connection status - delegates to PHY-specific function
 *
 * Parameters:
 *   adapter - Adapter info structure
 *   status - Output pointer for status value
 *
 * Returns:
 *   Success/failure from PHY-specific function
 */
int MiiGenGetConnectionStatus(int adapter, unsigned int status)
{
    int phyAddr;
    char success;

    // Get PHY structure pointer
    // PHY array starts at offset 0x22c, indexed by value at offset 500 (0x1f4)
    phyAddr = *(int *)(adapter + 0x22c + *(int *)(adapter + 500) * 4);

    // Call PHY-specific GetConnectionStatus function (offset 0x60)
    success = (*(char (**)(int, int, unsigned int))(phyAddr + 0x60))
                (adapter, phyAddr, status);

    return (int)success;
}

/*
 * MiiGenInit
 * Generic MII initialization - finds PHYs and gets capabilities
 *
 * Parameters:
 *   adapter - Adapter info structure
 *
 * Returns:
 *   TRUE if PHYs were found and initialized
 */
BOOL MiiGenInit(int adapter)
{
    int phyAddr;
    char success;
    unsigned short capabilities;

    // Find and initialize all MII PHYs
    success = FindAndInitMiiPhys(adapter);

    if (success != 0) {
        // Get PHY structure pointer
        // PHY array starts at offset 0x22c, indexed by value at offset 500 (0x1f4)
        phyAddr = *(int *)(adapter + 0x22c + *(int *)(adapter + 500) * 4);

        // Get PHY capabilities (function pointer at offset 0x54)
        (*(void (**)(int, unsigned short *))(phyAddr + 0x54))
            (phyAddr, &capabilities);

        // OR capabilities into adapter offset 0x226
        *(unsigned short *)(adapter + 0x226) =
            *(unsigned short *)(adapter + 0x226) | capabilities;

        // Store current PHY index at offset 0x228
        *(unsigned short *)(adapter + 0x228) = *(unsigned short *)(adapter + 500);
    }

    return success != 0;
}

/*
 * MiiGenSetConnection
 * Generic MII set connection - delegates to PHY-specific function
 *
 * Parameters:
 *   adapter - Adapter info structure
 *   param2 - Connection parameter 2
 *   param3 - Connection parameter 3
 *
 * Returns:
 *   Success/failure from PHY-specific function
 */
int MiiGenSetConnection(int adapter, unsigned short param2, unsigned short param3)
{
    int phyAddr;
    char success;

    // Get PHY structure pointer
    // PHY array starts at offset 0x22c, indexed by value at offset 500 (0x1f4)
    phyAddr = *(int *)(adapter + 0x22c + *(int *)(adapter + 500) * 4);

    // Call PHY-specific SetConnectionType function (offset 0x58)
    success = (*(char (**)(int, int, unsigned short, unsigned short))(phyAddr + 0x58))
                (adapter, phyAddr, param2, param3);

    return (int)success;
}

/*
 * MiiOutThreeState
 * Tri-state the MII data output line
 *
 * Parameters:
 *   adapter - Adapter info structure
 */
void MiiOutThreeState(int adapter)
{
    unsigned short csr9Port;

    // Get CSR9 port address (offset 0x30 in adapter info)
    csr9Port = *(unsigned short *)(adapter + 0x30);

    // Write tri-state sequence to CSR9
    // 0x42000 = data out tri-state, clock low
    outl(csr9Port, 0x42000);

    // LOCK/UNLOCK mechanism - appears to be for debugging/profiling
    // Increments global counter under lock
    // TODO: LOCK();
    // TODO: __xxx.92 = __xxx.92 + 1;
    // TODO: UNLOCK();

    IODelay(1);

    // 0x52000 = data out tri-state, clock high
    outl(csr9Port, 0x52000);

    // TODO: LOCK();
    // TODO: __xxx.92 = __xxx.92 + 1;
    // TODO: UNLOCK();

    IODelay(1);
}

int MiiPhyAdminControl(void *adapter, int phyAddr, int control)
{
    return 0;
}

int MiiPhyAdminStatus(void *adapter, int phyAddr)
{
    return 0;
}

int MiiPhyGetCapabilities(void *adapter, int phyAddr)
{
    return 0;
}

int MiiPhyGetConnectionStatus(void *adapter, int phyAddr, unsigned short *status)
{
    char success;
    unsigned short statusBits;
    unsigned short localAbility;
    unsigned short partnerAbility;
    unsigned short commonAbility;
    unsigned int phyId;
    unsigned char regData[4];

    commonAbility = 0;

    // Read control register (register 0)
    success = (*(char (**)(void *, int, int, int))(phyAddr + 0x6c))
              (adapter, phyAddr, 0, phyAddr + 0xc);

    if (success == 0) {
        *status = 0xfffd;  // Read error
        return 0;
    }

    // Read status register (register 1)
    success = (*(char (**)(void *, int, int, int))(phyAddr + 0x6c))
              (adapter, phyAddr, 1, phyAddr + 0xe);

    if (success == 0) {
        *status = 0xfffd;
        return 0;
    }

    // Check if status register is valid (not all zeros)
    if (*(short *)(phyAddr + 0xe) == 0) {
        *status = 0xfffd;
        return 0;
    }

    // TODO: Get PHY ID from offset 4
    phyId = *(unsigned int *)(phyAddr + 4);

    // Determine speed/duplex from PHY status
    if (phyId == 0x3e00000) {
        // Broadcom PHY: check if link up
        statusBits = 0x200;  // Assume link up

        // Check if N-Way enabled (bit 4 of control at offset 0xd)
        if ((*(unsigned char *)(phyAddr + 0xd) & 0x10) != 0) {
            statusBits = 0x400;  // N-Way complete
        }
    }
    else {
        // Check link status (bit 2 of status register at offset 0xe)
        if ((*(unsigned char *)(phyAddr + 0xe) & 8) == 0) {
            statusBits = 0;  // No link
        }
        else {
            // Link is up
            // Check if N-Way enabled
            if ((*(unsigned char *)(phyAddr + 0xd) & 0x10) != 0) {
                // N-Way enabled - check if complete (bit 5 of status)
                if ((*(unsigned char *)(phyAddr + 0xe) & 0x20) == 0) {
                    *status = 0x3ff;  // N-Way not complete
                    return 0;
                }
                statusBits = 0x400;  // N-Way complete
            }
            else {
                statusBits = 0x200;  // Link up, no N-Way
            }
        }
    }

    // If N-Way complete, check common abilities
    if ((phyId != 0x3e00000) && (statusBits == 0x400)) {
        // Get local and partner abilities
        (*(void (**)(void *, int, unsigned short *))(phyAddr + 0x74))
            (adapter, phyAddr, &localAbility);

        (*(void (**)(void *, int, unsigned short *))(phyAddr + 0x7c))
            (adapter, phyAddr, &partnerAbility);

        // Check for Level One PHY special handling
        if (phyId == 0x20005c00) {
            // Read vendor-specific register 0x19
            success = (*(char (**)(void *, int, int, unsigned char *))(phyAddr + 0x6c))
                      (adapter, phyAddr, 0x19, regData);

            if (success != 0) {
                // Check bit 6 to determine 100Base-TX vs 10Base-T
                if ((regData[0] & 0x40) == 0) {
                    commonAbility = localAbility & 0x80;  // 10Base-T FD
                }
                else {
                    commonAbility = localAbility & 0x20;  // 100Base-TX FD
                }
            }
        }
        else {
            // Standard: AND local and partner abilities
            commonAbility = localAbility & partnerAbility;
        }

        // If no common abilities, return error
        if (commonAbility == 0) {
            *status = 0x400;
            return 0;
        }
    }

    // Check for link established (bit 2 of status register)
    if ((*(unsigned char *)(phyAddr + 0xe) & 4) == 0) {
        // No link - re-read status register
        success = (*(char (**)(void *, int, int, int))(phyAddr + 0x6c))
                  (adapter, phyAddr, 1, phyAddr + 0xe);

        if (success == 0) {
            return 0;
        }

        // Check link status again
        if ((*(unsigned char *)(phyAddr + 0xe) & 4) == 0) {
            statusBits = 0;  // Still no link
        }
        else {
            statusBits = 2;  // Link just came up
        }
    }
    else {
        statusBits = 1;  // Link already up
    }

    *status = statusBits | (statusBits ? statusBits : 0);
    return (statusBits != 0);
}

int MiiPhyGetConnectionType(void *adapter, int phyAddr, unsigned short *connectionType)
{
    char success;
    unsigned short localAbility;
    unsigned short partnerAbility;
    unsigned short commonAbility;
    unsigned int phyId;
    unsigned char regData[2];
    unsigned short result;

    // TODO: Get PHY ID from offset 4
    phyId = *(unsigned int *)(phyAddr + 4);

    if (phyId == 0x3e00000) {
        // Broadcom PHY - use special detection
        success = GetBroadcomPhyConnectionType(adapter, phyAddr, connectionType);

        if (success == 0) {
            *connectionType = 0xffff;
            return 0;
        }

        HandleBroadcomMediaChangeFrom10To100(adapter, phyAddr);
    }
    else {
        // Check if N-Way auto-negotiation is enabled (bit 4 of control at offset 0xd)
        if ((*(unsigned char *)(phyAddr + 0xd) & 0x10) != 0) {
            // Get local and partner abilities
            (*(void (**)(void *, int, unsigned short *))(phyAddr + 0x74))
                (adapter, phyAddr, &localAbility);

            (*(void (**)(void *, int, unsigned short *))(phyAddr + 0x7c))
                (adapter, phyAddr, &partnerAbility);

            commonAbility = localAbility & partnerAbility;

            // Check for Level One PHY special case
            if ((commonAbility == 0) && (phyId == 0x20005c00)) {
                // Read vendor-specific register 0x19
                success = (*(char (**)(void *, int, int, unsigned char *))(phyAddr + 0x6c))
                          (adapter, phyAddr, 0x19, regData);

                if (success != 0) {
                    // Check bit 6 to determine speed
                    if ((regData[0] & 0x40) == 0) {
                        commonAbility = localAbility & 0x80;  // 10Base-T
                    }
                    else {
                        commonAbility = localAbility & 0x20;  // 100Base-TX
                    }
                }
            }

            if (commonAbility == 0) {
                return 0;
            }

            // Convert N-Way ability to connection type
            success = ConvertNwayToConnectionType(commonAbility, connectionType);
            return success;
        }

        // Manual mode (not N-Way)
        // Check duplex (bit 0 of control at offset 0xd)
        if ((*(unsigned char *)(phyAddr + 0xd) & 1) == 0) {
            // Half duplex
            // Check speed (bit 5 of control at offset 0xd)
            if ((*(unsigned char *)(phyAddr + 0xd) & 0x20) == 0) {
                result = 9;  // 10Base-T half duplex
            }
            else {
                // 100Mbps half duplex - check for T4 (bit 5 of status at offset 0xf)
                if ((*(unsigned char *)(phyAddr + 0xf) & 0x20) != 0) {
                    result = 0xd;  // 100Base-T4
                }
                else {
                    result = 0xf;  // 100Base-TX half duplex
                }
            }
        }
        else {
            // Full duplex
            // Check speed
            if ((*(unsigned char *)(phyAddr + 0xd) & 0x20) != 0) {
                result = 0x20e;  // 100Base-TX full duplex
            }
            else {
                result = 0x20a;  // 10Base-T full duplex
            }
        }

        *connectionType = result;
    }

    return 1;
}

int MiiPhyInit(void *adapter, int phyAddr)
{
    char success;
    int result;
    unsigned int phyId;

    // Try to find the MII PHY device
    success = FindMiiPhyDevice(adapter, phyAddr);

    if (success == 0) {
        return 0;
    }

    // TODO: Check flag at offset 0x1ea
    if (*(char *)(adapter + 0x1ea) == 0) {
        // First time - set flag and reset PHY
        // TODO: Set flag at offset 0x1ea to 1
        *(unsigned char *)(adapter + 0x1ea) = 1;

        // TODO: Get admin control function pointer from offset 0x68
        // Call with parameter 0 (reset)
        (*(void (**)(void *, int, int))(phyAddr + 0x68))
            (adapter, phyAddr, 0);

        // Try finding PHY again after reset
        success = FindMiiPhyDevice(adapter, phyAddr);

        if (success == 0) {
            return 0;
        }
    }

    // TODO: Get status register value from offset 0xe and mask with 0xf808
    // Store at offset 8
    *(unsigned short *)(phyAddr + 8) = *(unsigned short *)(phyAddr + 0xe) & 0xf808;

    // TODO: Get PHY ID from offset 4
    phyId = *(unsigned int *)(phyAddr + 4);

    // Special handling for Broadcom PHY
    if (phyId == 0x3e00000) {
        // TODO: Set bit 3 at offset 8
        *(unsigned char *)(phyAddr + 8) |= 8;
    }

    // TODO: Get capabilities function pointer from offset 0x74
    // Call to get capabilities, passing pointer to offset 10
    (*(void (**)(void *, int, void *))(phyAddr + 0x74))
        (adapter, phyAddr, (void *)(phyAddr + 10));

    // TODO: Get admin control function pointer from offset 0x68
    // Call with parameter 1
    (*(void (**)(void *, int, int))(phyAddr + 0x68))
        (adapter, phyAddr, 1);

    // TODO: Set valid flag at offset 0 to 1
    *(unsigned char *)phyAddr = 1;

    return 1;
}

void MiiPhyNwayGetLocalAbility(void *adapter, int phyAddr, unsigned short *ability)
{
    char success;
    unsigned int phyId;

    // TODO: Get PHY ID from offset 4
    phyId = *(unsigned int *)(phyAddr + 4);

    // Special handling for Broadcom PHY (ID 0x3e00000)
    if (phyId == 0x3e00000) {
        // TODO: Get ability from offset 8, shift right by 6
        *ability = *(unsigned short *)(phyAddr + 8) >> 6;
    }
    else {
        // TODO: Get read register function pointer from offset 0x6c
        success = (*(char (**)(void *, int, int, int))(phyAddr + 0x6c))
                  (adapter, phyAddr, 4, phyAddr + 0x14);

        if (success == 0) {
            *ability = 0;
        }
        else {
            // TODO: Mask bits 5-9 (0x3e0) from register 4 at offset 0x14
            *ability = *(unsigned short *)(phyAddr + 0x14) & 0x3e0;
        }
    }
}

void MiiPhyNwayGetPartnerAbility(void *adapter, int phyAddr, unsigned short *ability)
{
    char success;
    unsigned short maskedAbility;

    // TODO: Get read register function pointer from offset 0x6c
    success = (*(char (**)(void *, int, int, int))(phyAddr + 0x6c))
              (adapter, phyAddr, 5, phyAddr + 0x16);

    if (success == 0) {
        *ability = 0;
    }
    else {
        // TODO: Mask bits 5-9 (0x3e0) from register 5 at offset 0x16
        maskedAbility = *(unsigned short *)(phyAddr + 0x16) & 0x3e0;

        // TODO: Store masked value at offset 0x16
        *(unsigned short *)(phyAddr + 0x16) = maskedAbility;

        *ability = maskedAbility;
    }
}

void MiiPhyNwaySetLocalAbility(void *adapter, int phyAddr, unsigned short ability)
{
    unsigned int phyId;

    // TODO: Get PHY ID from offset 4
    phyId = *(unsigned int *)(phyAddr + 4);

    // Skip for Broadcom PHY (ID 0x3e00000)
    if (phyId != 0x3e00000) {
        // TODO: Store ability at offset 10
        *(unsigned short *)(phyAddr + 10) = ability;

        // TODO: Store ability | 1 at offset 0x14
        *(unsigned short *)(phyAddr + 0x14) = ability | 1;

        // TODO: Get write register function pointer from offset 0x70
        // Write to register 4 with ability | 1
        (*(void (**)(void *, int, int, unsigned short))(phyAddr + 0x70))
            (adapter, phyAddr, 4, ability | 1);
    }
}

int MiiPhyReadRegister(void *adapter, int phyAddr, int regAddr, unsigned short *value)
{
    unsigned int initialStatus;
    unsigned int readData;
    int bitIndex;
    unsigned short phyAddress;
    unsigned int readCommand;
    unsigned short csr9Port;
    unsigned short reservedBits;

    // TODO: Get PHY address from PHY info structure at offset 2
    phyAddress = *(unsigned short *)(phyAddr + 2);

    // Send 32 preamble bits (all 1s)
    WriteMii(adapter, 0xffffffff, 0x20);

    // Build MII read command (14 bits):
    // Bits 13-12: Start of frame (01 = 0x6 shifted to position)
    // Bits 11-10: Opcode (10 = read = 0x2)
    // Bits 9-5: PHY address (5 bits)
    // Bits 4-0: Register address (5 bits)
    readCommand = ((unsigned int)phyAddress << 23) |  // PHY addr at bits 28-24
                  ((unsigned int)regAddr << 18) |     // Reg addr at bits 23-19
                  0x60000000;                         // Start + Read opcode

    // Send read command (14 bits)
    WriteMii(adapter, readCommand, 0xe);

    // Tri-state the data line
    MiiOutThreeState(adapter);

    // TODO: Get CSR9 port from offset 0x30
    csr9Port = *(unsigned short *)(adapter + 0x30);

    // Read initial status
    initialStatus = inl(csr9Port);

    // Initialize read value
    *value = 0;

    // Read 16 data bits
    for (bitIndex = 0; bitIndex < 0x10; bitIndex++) {
        // Clock low
        outl(csr9Port, 0x44000);
        IODelay(1);

        // Clock high
        outl(csr9Port, 0x54000);
        IODelay(1);

        // Read data bit
        readData = inl(csr9Port);
        IODelay(1);

        // Shift in bit 19 from read data
        *value = (*value << 1) | ((readData >> 19) & 1);
    }

    // Tri-state the data line
    MiiOutThreeState(adapter);

    // Get reserved bits mask for this register
    reservedBits = PhyRegsReservedBitsMasks[regAddr];

    // Clear reserved bits in read value
    *value = *value & ~reservedBits;

    // Return true if bit 19 was low (valid data), false if high (error)
    return (initialStatus & 0x80000) == 0;
}

int MiiPhySetConnectionType(void *adapter, int phyAddr, int connection, unsigned short param4)
{
    char supported;
    int result;
    unsigned short controlValue;
    void (*setAbilityFunc)(void *, int, unsigned short);
    void (*writeRegFunc)(void *, int, int, unsigned short);
    unsigned int phyId;

    controlValue = connection;

    // Check if this connection type is supported
    supported = CheckConnectionSupport(phyAddr, connection);

    if (supported == 0) {
        return 0;
    }

    // Convert connection type to control register value
    ConvertConnectionToControl(phyAddr, &controlValue);

    // TODO: Get current control value from offset 0xc and preserve bits 10-11 (0xc00)
    *(unsigned short *)(phyAddr + 0xc) = *(unsigned short *)(phyAddr + 0xc) & 0xc00;

    // TODO: OR in new control value
    *(unsigned short *)(phyAddr + 0xc) = *(unsigned short *)(phyAddr + 0xc) | controlValue;

    // If auto-negotiation enabled (bit 12)
    if ((controlValue & 0x1000) != 0) {
        // TODO: Get function pointer from offset 0x78
        setAbilityFunc = *(void (**)(void *, int, unsigned short))(phyAddr + 0x78);

        // Call set local ability function
        (*setAbilityFunc)(adapter, phyAddr, param4);
    }

    // TODO: Get write register function pointer from offset 0x70
    writeRegFunc = *(void (**)(void *, int, int, unsigned short))(phyAddr + 0x70);

    // TODO: Write control register (register 0) with control value from offset 0xc
    (*writeRegFunc)(adapter, phyAddr, 0, *(unsigned short *)(phyAddr + 0xc));

    // TODO: Clear reset bit (bit 9) in control value
    *(unsigned short *)(phyAddr + 0xc) = *(unsigned short *)(phyAddr + 0xc) & 0xfdff;

    // TODO: Get PHY ID from offset 4
    phyId = *(unsigned int *)(phyAddr + 4);

    // Special handling for Broadcom PHY (ID 0x3e00000)
    if (phyId == 0x3e00000) {
        HandleBroadcomMediaChangeFrom10To100(adapter, phyAddr);
    }

    return 1;
}

void MiiPhyWriteRegister(void *adapter, int phyAddr, int regAddr, int value)
{
    unsigned short reservedBits;
    unsigned short phyAddress;
    unsigned int writeCommand;

    // Get reserved bits mask for this register
    reservedBits = PhyRegsReservedBitsMasks[regAddr];

    // TODO: Get PHY address from PHY info structure at offset 2
    phyAddress = *(unsigned short *)(phyAddr + 2);

    // Send 32 preamble bits (all 1s)
    WriteMii(adapter, 0xffffffff, 0x20);

    // Build MII write command:
    // Bits 31-28: Start of frame (0101 = 0x5)
    // Bits 27-26: Opcode (01 = write = 0x1)
    // Bits 25-21: PHY address (5 bits)
    // Bits 20-16: Register address (5 bits)
    // Bits 15-0: Data to write (with reserved bits masked)
    writeCommand = ((unsigned int)phyAddress << 23) |    // PHY addr at bits 25-21
                   ((unsigned int)regAddr << 18) |        // Reg addr at bits 20-16
                   0x50020000 |                           // Start + Write opcode + turnaround
                   (unsigned int)(value & ~reservedBits); // Data with reserved bits cleared

    // Send write command (32 bits)
    WriteMii(adapter, writeCommand, 0x20);

    // Tri-state the data line
    MiiOutThreeState(adapter);
}

int DC21X4MiiAutoDetect(void *adapter)
{
    return 0;
}

int DC21X4MiiAutoSense(void *adapter)
{
    return 0;
}

void WriteMii(void *adapter, int data, int count)
{
    unsigned short csr9Port;
    unsigned int bitValue;

    // Get CSR9 port address (offset 0x30 in adapter info)
    // TODO: csr9Port = *(unsigned short *)(adapter + 0x30);
    csr9Port = 0;  // TODO

    // Write each bit MSB first
    if (count > 0) {
        do {
            // Extract bit 14 from data and shift to bit 17 position
            bitValue = (data >> 14) & 0x20000;

            // Write bit value with clock low (0x2000 base)
            // The CONCAT22 in decompiled code combines the upper word with 0x2000
            outl(csr9Port, (bitValue & 0x30000) | 0x2000);

            // Delay 1 microsecond
            IODelay(1);

            // Write bit value with clock high (0x12000 = 0x10000 | 0x2000)
            outl(csr9Port, bitValue | 0x12000);

            // Delay 1 microsecond
            IODelay(1);

            // Shift data left by 1 (next bit)
            data = data << 1;

            // Decrement bit count
            count--;
        } while (count > 0);
    }
}

/*
 * MiiPhyGetCapabilities
 * Get PHY capabilities from PHY structure
 *
 * Parameters:
 *   phyAddr - PHY structure pointer
 *   capabilities - Output pointer for capabilities value
 */
void MiiPhyGetCapabilities(int phyAddr, unsigned short *capabilities)
{
    // Get capabilities from offset 8 in PHY structure
    // This is the masked status register capabilities
    *capabilities = *(unsigned short *)(phyAddr + 8);
}

/*
 * MiiPhyAdminStatus
 * Get PHY administrative status by reading control register
 *
 * Parameters:
 *   adapter - Adapter info structure
 *   phyAddr - PHY structure pointer
 *   status - Output pointer for status value
 *
 * Status values:
 *   0 - Isolated
 *   1 - Normal operation
 *   2 - Loopback
 *   3 - Reset
 */
void MiiPhyAdminStatus(void *adapter, int phyAddr, unsigned int *status)
{
    unsigned short controlRegister;
    short retryCount;
    BOOL success;

    controlRegister = 0;
    retryCount = 2;

    // Read PHY control register (reg 0) with retry
    do {
        // Call read register function pointer at offset 0x6c
        (*(char (**)(void *, int, int, unsigned short *))(phyAddr + 0x6c))
            (adapter, phyAddr, 0, &controlRegister);

        if (controlRegister != 0) {
            break;
        }

        success = retryCount != 0;
        retryCount = retryCount - 1;
    } while (success);

    // Decode control register value to admin status
    if (controlRegister == 0x800) {
        // Loopback bit set
        *status = 3;
    }
    else if (controlRegister < 0x801) {
        if (controlRegister == 0x400) {
            // Isolate bit set
            *status = 2;
            return;
        }
        // Normal operation
        *status = 1;
    }
    else if (controlRegister == 0x8000) {
        // Reset bit set
        *status = 0;
        return;
    }
    else {
        // Default to normal operation
        *status = 1;
    }
}

/*
 * MiiPhyAdminControl
 * Control PHY administrative state
 *
 * Parameters:
 *   adapter - Adapter info structure
 *   phyAddr - PHY structure pointer
 *   control - Control command (0-6)
 *
 * Control commands:
 *   0 - Reset PHY
 *   1 - Enable auto-negotiation
 *   2 - Disable
 *   3 - Loopback
 *   4 - Power down
 *   5 - Isolate
 *   6 - Restore saved state
 */
void MiiPhyAdminControl(int adapter, int phyAddr, unsigned int control)
{
    BOOL bVar1;
    int iteration;
    int statusResult;
    unsigned short newControlValue;

    statusResult = 0;

    // Handle special control commands
    if (control > 3) {
        if (control < 6) {
            // Commands 4 and 5: Power down or Isolate
            // Save current control register to offset 0x4c
            *(unsigned short *)(phyAddr + 0x4c) = *(unsigned short *)(phyAddr + 0xc);

            // Clear auto-negotiation and speed bits (mask 0xceff)
            *(unsigned short *)(phyAddr + 0xc) = *(unsigned short *)(phyAddr + 0xc) & 0xceff;

            // Set flag at adapter offset 0x1e9
            *(unsigned char *)(adapter + 0x1e9) = 1;

            goto apply_control;
        }
        if (control == 6) {
            // Command 6: Restore saved state
            // Restore control register from offset 0x4c
            *(unsigned short *)(phyAddr + 0xc) = *(unsigned short *)(phyAddr + 0x4c);

            // Clear flag at adapter offset 0x1e9
            *(unsigned char *)(adapter + 0x1e9) = 0;

            goto apply_control;
        }
    }

    // For commands 0-3: Clear specific bits (mask 0x73ff)
    // This clears reset, loopback, power down, isolate bits
    *(unsigned short *)(phyAddr + 0xc) = *(unsigned short *)(phyAddr + 0xc) & 0x73ff;

apply_control:
    // Get base control value and OR with conversion table value
    newControlValue = *(unsigned short *)(phyAddr + 0xc) |
                      *(unsigned short *)(&_AdminControlConversionTable + control * 4);

    // Write to PHY control register (reg 0) using function pointer at offset 0x70
    (*(void (**)(int, int, int, unsigned short))(phyAddr + 0x70))
        (adapter, phyAddr, 0, newControlValue);

    // If reset command (control == 0), poll until status is non-zero
    if (control == 0) {
        iteration = 1;
        do {
            // Call admin status function pointer at offset 100 (0x64)
            (*(void (**)(int, int, int *))(phyAddr + 100))
                (adapter, phyAddr, &statusResult);

            if (statusResult != 0) {
                return;
            }

            bVar1 = iteration < 10000;
            iteration = iteration + 1;
        } while (bVar1);
    }
}

/*
 * ConvertNwayToConnectionType
 * Convert N-Way negotiation result to connection type
 */
BOOL ConvertNwayToConnectionType(unsigned short nwayResult, unsigned short *connectionType)
{
    // Check for 100Base-TX Full Duplex (bit 8)
    if ((nwayResult & 0x100) == 0) {
        // Check for 100Base-T4 (bit 9)
        if ((nwayResult & 0x200) == 0) {
            // Check for 10Base-T Full Duplex (bit 7)
            if ((char)nwayResult < 0) {
                *connectionType = 0x90d;  // 10Base-T Full Duplex
            }
            // Check for 10Base-T Half Duplex (bit 6)
            else if ((nwayResult & 0x40) == 0) {
                // Check for 10Base-T (bit 5)
                if ((nwayResult & 0x20) == 0) {
                    return FALSE;  // No valid connection
                }
                *connectionType = 0x909;  // 10Base-T
            }
            else {
                *connectionType = 0xb0a;  // 10Base-T Full Duplex (alternate)
            }
        }
        else {
            *connectionType = 0x90f;  // 100Base-T4
        }
    }
    else {
        *connectionType = 0xb0e;  // 100Base-TX Full Duplex
    }

    return TRUE;
}

/*
 * ConvertMediaTypeToNwayLocalAbility
 * Convert media type to N-Way local ability advertisement bits
 */
void ConvertMediaTypeToNwayLocalAbility(unsigned char mediaType, unsigned short *nwayAbility)
{
    // Lookup in conversion table
    *nwayAbility = MediaToNwayConversionTable[mediaType];
}

/*
 * ConvertConnectionToControl
 * Convert connection type to PHY control register value
 */
void ConvertConnectionToControl(int phyStructure, unsigned short *connectionType)
{
    unsigned short originalType;

    originalType = *connectionType;

    // Lookup control bits from conversion table
    *connectionType = MediaToCommandConversionTable[(unsigned char)*connectionType];

    // Check if MII or full duplex mode (bits 8 or 0 in high byte)
    if ((originalType >> 8 & 9) != 0) {
        // Check PHY ID - if not Broadcom (0x3e00000), enable autonegotiation
        // TODO: PHY ID at offset 4 in PHY structure
        if (*(int *)(phyStructure + 4) != 0x3e00000) {
            *connectionType = *connectionType | 0x200;  // Enable auto-negotiation
        }
        *connectionType = *connectionType | 0x1000;  // Set speed bit
    }
}

/*
 * CheckConnectionSupport
 * Check if connection type is supported by PHY
 */
unsigned short CheckConnectionSupport(int phyStructure, unsigned short connectionType)
{
    // Check if MII mode (bit 11) or full duplex (bit 8)
    if ((connectionType & 0x900) == 0) {
        // Use status conversion table
        // TODO: PHY capabilities at offset 8 in PHY structure
        unsigned short statusBits = MediaToStatusConversionTable[connectionType & 0xff];
        unsigned short phyCapabilities = *(unsigned short *)(phyStructure + 8);
        return (unsigned short)((statusBits & phyCapabilities) != 0);
    }

    // For MII mode, check bit 3 of capabilities
    return *(unsigned short *)(phyStructure + 8) >> 3 & 1;
}
