/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER@
 */

/*
 * Copyright (c) 1998-1999 by Apple Computer, Inc., All rights reserved.
 *
 * MII/PHY support methods for UniN Ethernet.
 * It is general enough to work with most MII/PHYs.
 *
 * HISTORY
 *
 */
#import "UniNEnetPrivate.h"

/*
 * MII Register definitions
 */
#define MII_CONTROL             0
#define MII_STATUS              1
#define MII_ID0                 2
#define MII_ID1                 3

/* MII Control register bits */
#define MII_CONTROL_RESET               0x8000
#define MII_CONTROL_AUTONEG_ENABLE      0x1000
#define MII_CONTROL_ISOLATE             0x0400
#define MII_CONTROL_RESTART_NEGOTIATION 0x0200

/* MII Auto-negotiation advertisement register */
#define MII_ADVERTISEMENT               4
#define MII_ADVERT_100BASE_TX_FD        0x0100
#define MII_ADVERT_100BASE_TX           0x0080
#define MII_ADVERT_10BASE_T_FD          0x0040
#define MII_ADVERT_10BASE_T             0x0020
#define MII_ADVERT_CSMA_CD              0x0001
#define MII_ADVERT_ALL_SPEEDS           (MII_ADVERT_100BASE_TX_FD | MII_ADVERT_100BASE_TX | \
                                         MII_ADVERT_10BASE_T_FD | MII_ADVERT_10BASE_T)

/* MII Status register bits */
#define MII_STATUS_LINK_STATUS          0x0004
#define MII_STATUS_NEGOTIATION_COMPLETE 0x0020

/* UniN Ethernet MII Management register (format: size in upper 16 bits, offset in lower 16 bits) */
#define kMIIMgmt                0x0004620C
#define kMIIMgmt_DataMask       0x0000FFFF
#define kMIIMgmt_WriteOp        0x50000000
#define kMIIMgmt_ReadOp         0x60000000
#define kMIIMgmt_WriteMask      0x00020000
#define kMIIMgmt_Busy           0x00010000
#define kMIIMgmt_RegAddrShift   18
#define kMIIMgmt_PhyAddrShift   23

#define MII_MAX_POLL_CYCLES     20
#define MII_POLL_DELAY_uS       10
#define MII_LINK_TIMEOUT_MS     5000
#define MII_LINK_DELAY_MS       20
#define MII_RESET_TIMEOUT_MS    100
#define MII_RESET_DELAY_MS      10
#define MII_MAX_PHY             32

@implementation UniNEnet(MII)

/*-------------------------------------------------------------------------
 *
 * Read from MII/PHY registers.
 *
 *-------------------------------------------------------------------------*/

- (BOOL)miiReadWord:(unsigned short *)dataPtr reg:(unsigned short)reg phy:(unsigned char)phy
{
    u_int32_t command;
    u_int32_t status;
    u_int32_t poll_count = 0;

    // Build the MII read command
    command = kMIIMgmt_ReadOp |                               // 0x60000000
              kMIIMgmt_WriteMask |                            // 0x00020000
              ((u_int32_t)phy << kMIIMgmt_PhyAddrShift) |     // PHY address << 23
              ((u_int32_t)reg << kMIIMgmt_RegAddrShift);      // Register << 18

    // Write the command to the MII management register
    WriteUniNRegister(ioBaseEnet, kMIIMgmt, command);

    // Poll for completion
    do {
        status = ReadUniNRegister(ioBaseEnet, kMIIMgmt);
        if ((status & kMIIMgmt_Busy) != 0) {
            // Operation completed, extract data
            if (dataPtr) {
                *dataPtr = (u_int16_t)(status & kMIIMgmt_DataMask);
            }
            return YES;
        }
        IODelay(MII_POLL_DELAY_uS);
        poll_count++;
    } while (poll_count < MII_MAX_POLL_CYCLES);

    return NO;  // Timeout
}

/*-------------------------------------------------------------------------
 *
 * Write to MII/PHY registers.
 *
 *-------------------------------------------------------------------------*/

- (BOOL)miiWriteWord:(unsigned short)data reg:(unsigned short)reg phy:(unsigned char)phy
{
    u_int32_t command;
    u_int32_t status;
    u_int32_t poll_count = 0;

    // Build the MII write command
    command = kMIIMgmt_WriteOp |                              // 0x50000000
              kMIIMgmt_WriteMask |                            // 0x00020000
              ((u_int32_t)phy << kMIIMgmt_PhyAddrShift) |     // PHY address << 23
              ((u_int32_t)reg << kMIIMgmt_RegAddrShift) |     // Register << 18
              (data & kMIIMgmt_DataMask);                     // Data

    // Write the command to the MII management register
    WriteUniNRegister(ioBaseEnet, kMIIMgmt, command);

    // Poll for completion
    do {
        status = ReadUniNRegister(ioBaseEnet, kMIIMgmt);
        if ((status & kMIIMgmt_Busy) != 0) {
            return YES;  // Operation completed
        }
        IODelay(MII_POLL_DELAY_uS);
        poll_count++;
    } while (poll_count < MII_MAX_POLL_CYCLES);

    return NO;  // Timeout
}

/*-------------------------------------------------------------------------
 *
 * Reset the PHY chip.
 *
 *-------------------------------------------------------------------------*/

- (BOOL)miiResetPHY:(unsigned char)phy
{
    u_int16_t control;
    int timeout_ms = MII_RESET_TIMEOUT_MS;

    // Write reset bit to MII control register
    [self miiWriteWord:MII_CONTROL_RESET reg:MII_CONTROL phy:phy];

    // Wait for reset to complete
    IOSleep(MII_RESET_DELAY_MS);

    // Poll for reset bit to clear
    while (timeout_ms > 0)
    {
        if ([self miiReadWord:&control reg:MII_CONTROL phy:phy] == NO)
        {
            return NO;  // Read failed
        }

        if ((control & MII_CONTROL_RESET) == 0)
        {
            break;  // Reset completed
        }

        IOSleep(MII_RESET_DELAY_MS);
        timeout_ms -= MII_RESET_DELAY_MS;
    }

    if (timeout_ms <= 0)
    {
        return NO;  // Reset timeout
    }

    // Clear the isolate bit
    if ([self miiReadWord:&control reg:MII_CONTROL phy:phy] == NO)
    {
        return NO;
    }

    control &= ~MII_CONTROL_ISOLATE;

    [self miiWriteWord:control reg:MII_CONTROL phy:phy];

    return YES;
}

/*-------------------------------------------------------------------------
 *
 * Wait for link to come up.
 *
 *-------------------------------------------------------------------------*/

- (BOOL)miiWaitForLink:(unsigned char)phy
{
    u_int16_t status;
    int timeout_ms = MII_LINK_TIMEOUT_MS;

    while (timeout_ms > 0)
    {
        // Read MII status register
        if ([self miiReadWord:&status reg:MII_STATUS phy:phy] == NO)
        {
            return NO;  // Read failed
        }

        // Check if link is up
        if ((status & MII_STATUS_LINK_STATUS) != 0)
        {
            return YES;  // Link is up
        }

        // Wait before checking again
        IOSleep(MII_LINK_DELAY_MS);
        timeout_ms -= MII_LINK_DELAY_MS;
    }

    return NO;  // Timeout - link did not come up
}

/*-------------------------------------------------------------------------
 *
 * Wait for auto-negotiation to complete.
 *
 *-------------------------------------------------------------------------*/

- (BOOL)miiWaitForAutoNegotiation:(unsigned char)phy
{
    u_int16_t status;
    int timeout_ms = MII_LINK_TIMEOUT_MS;

    while (timeout_ms > 0)
    {
        // Read MII status register
        if ([self miiReadWord:&status reg:MII_STATUS phy:phy] == NO)
        {
            return NO;  // Read failed
        }

        // Check if auto-negotiation is complete
        if ((status & MII_STATUS_NEGOTIATION_COMPLETE) != 0)
        {
            return YES;  // Auto-negotiation completed
        }

        // Wait before checking again
        IOSleep(MII_LINK_DELAY_MS);
        timeout_ms -= MII_LINK_DELAY_MS;
    }

    return NO;  // Timeout - auto-negotiation did not complete
}

/*-------------------------------------------------------------------------
 *
 * Restart auto-negotiation.
 *
 *-------------------------------------------------------------------------*/

- (void)miiRestartAutoNegotiation:(unsigned char)phy
{
    u_int16_t control;

    // Read current control register value
    [self miiReadWord:&control reg:MII_CONTROL phy:phy];

    // Set restart auto-negotiation bit
    control |= MII_CONTROL_RESTART_NEGOTIATION;

    // Write back to control register
    [self miiWriteWord:control reg:MII_CONTROL phy:phy];
}

/*-------------------------------------------------------------------------
 *
 * Find a PHY on the MII bus.
 *
 *-------------------------------------------------------------------------*/

- (BOOL)miiFindPHY:(unsigned char *)phy
{
    u_int16_t status;
    u_int16_t control;
    int i;

    *phy = 0xFF;  // Initialize to not found

    // Scan all possible PHY addresses (0-31)
    for (i = 0; i < MII_MAX_PHY; i++)
    {
        // Try to read status register (reg 1)
        if ([self miiReadWord:&status reg:MII_STATUS phy:i] == NO)
        {
            continue;  // Read failed, try next address
        }

        // Try to read control register (reg 0)
        if ([self miiReadWord:&control reg:MII_CONTROL phy:i] == NO)
        {
            continue;  // Read failed, try next address
        }

        // Check if this is a valid PHY (not all 1's)
        if ((status != 0xFFFF || control != 0xFFFF) && (*phy == 0xFF))
        {
            *phy = (unsigned char)i;  // Found a PHY, save its address
        }
    }

    return (*phy != 0xFF);  // Return YES if PHY was found
}

/*-------------------------------------------------------------------------
 *
 * Initialize the PHY.
 *
 *-------------------------------------------------------------------------*/

- (BOOL)miiInitializePHY:(unsigned char)phy
{
    u_int16_t control;
    u_int16_t advertisement;

    // Read control register and clear auto-negotiation enable bit
    [self miiReadWord:&control reg:MII_CONTROL phy:phy];
    control &= ~MII_CONTROL_AUTONEG_ENABLE;  // Clear bit 0x1000
    [self miiWriteWord:control reg:MII_CONTROL phy:phy];

    // Configure advertisement register for all speeds
    [self miiReadWord:&advertisement reg:MII_ADVERTISEMENT phy:phy];
    advertisement |= (MII_ADVERT_ALL_SPEEDS | MII_ADVERT_CSMA_CD);  // 0x5E0 | 0x0001 = 0x5E1
    [self miiWriteWord:advertisement reg:MII_ADVERTISEMENT phy:phy];

    // Enable auto-negotiation
    [self miiReadWord:&control reg:MII_CONTROL phy:phy];
    control |= MII_CONTROL_AUTONEG_ENABLE;  // Set bit 0x1000
    [self miiWriteWord:control reg:MII_CONTROL phy:phy];

    // Restart auto-negotiation
    [self miiRestartAutoNegotiation:phy];

    return YES;
}

@end
