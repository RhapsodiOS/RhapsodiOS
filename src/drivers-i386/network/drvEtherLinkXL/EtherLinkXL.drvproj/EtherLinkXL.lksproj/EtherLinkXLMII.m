/*
 * EtherLinkXLMII.m
 * 3Com EtherLink XL Network Driver - MII (Media Independent Interface) Support
 */

#import "EtherLinkXL.h"
#import <driverkit/generalFuncs.h>

/* MII Register Definitions */
#define MII_CONTROL             0x00
#define MII_STATUS              0x01
#define MII_PHY_ID1             0x02
#define MII_PHY_ID2             0x03
#define MII_AUTONEG_ADV         0x04
#define MII_AUTONEG_LINK        0x05

/* MII Control Register Bits */
#define MII_CONTROL_RESET       0x8000
#define MII_CONTROL_LOOPBACK    0x4000
#define MII_CONTROL_SPEED       0x2000
#define MII_CONTROL_AUTONEG     0x1000
#define MII_CONTROL_POWERDOWN   0x0800
#define MII_CONTROL_ISOLATE     0x0400
#define MII_CONTROL_RESTART_AN  0x0200
#define MII_CONTROL_DUPLEX      0x0100
#define MII_CONTROL_COLLISION   0x0080

/* MII Status Register Bits */
#define MII_STATUS_100T4        0x8000
#define MII_STATUS_100TX_FD     0x4000
#define MII_STATUS_100TX_HD     0x2000
#define MII_STATUS_10T_FD       0x1000
#define MII_STATUS_10T_HD       0x0800
#define MII_STATUS_AUTONEG_DONE 0x0020
#define MII_STATUS_REMOTE_FAULT 0x0010
#define MII_STATUS_AUTONEG_ABLE 0x0008
#define MII_STATUS_LINK_UP      0x0004
#define MII_STATUS_JABBER       0x0002
#define MII_STATUS_EXTENDED     0x0001

/* Register Window Commands */
#define CMD_SELECT_WINDOW_4     0x0804

/* Register Offsets */
#define REG_COMMAND             0x0E
#define REG_MII_DATA            0x08

/* MII Data Register Bits */
#define MII_DATA_CLOCK          0x01
#define MII_DATA_WRITE_ENABLE   0x04
#define MII_DATA_READ_BIT       0x02

/* MII Read/Write Command Bits */
#define MII_CMD_READ            0x60000000  /* Read command: 0b0110 */
#define MII_CMD_WRITE           0x50000000  /* Write command: 0b0101 */
#define SELECT_MII_WINDOW        do { \
    if (window != 4) { \
        outw(ioBase + REG_COMMAND, CMD_SELECT_WINDOW_4); \
        window = 4; \
    } \
} while (0)

@implementation EtherLinkXL(EtherLinkXLMII)

/*
 * Read a single bit from MII interface
 * This implements the MII bit-bang protocol for reading
 */
- (int)miiReadBit
{
    unsigned short miiStatus;

    /* Ensure we're in window 4 */
    SELECT_MII_WINDOW;

    /* Clock low, write disabled */
    outw(ioBase + REG_MII_DATA, 0);
    IODelay(1);

    /* Clock high, write disabled */
    SELECT_MII_WINDOW;
    outw(ioBase + REG_MII_DATA, MII_DATA_CLOCK);
    IODelay(1);

    /* Clock low, write disabled */
    SELECT_MII_WINDOW;
    outw(ioBase + REG_MII_DATA, 0);
    IODelay(1);

    /* Read data bit */
    SELECT_MII_WINDOW;
    miiStatus = inw(ioBase + REG_MII_DATA);

    /* Extract and return bit 1 */
    return (miiStatus >> 1) & 1;
}

/*
 * Read a word from MII register
 * Returns YES on success, NO on failure
 */
- (BOOL)miiReadWord:(unsigned short *)value reg:(unsigned short)reg phy:(unsigned short)phy
{
    int turnaroundBit;
    unsigned short result;
    int i;
    int bit;

    /* Send 32-bit preamble (all 1's) */
    [self miiWrite:0xFFFFFFFF size:32];

    /* Send read command:
     * [phy address (5 bits)] [reg address (5 bits)] [read command 0b0110 (4 bits)]
     * Total: 14 bits
     */
    [self miiWrite:((phy & 0x1F) << 23) | MII_CMD_READ | ((reg & 0x1F) << 18) size:14];

    /* Read turnaround bit (should be 0 for valid response) */
    turnaroundBit = [self miiReadBit];

    /* Read 16 data bits */
    result = 0;
    for (i = 0; i < 16; i++) {
        bit = [self miiReadBit];
        result = (result << 1) | bit;
    }

    /* Store result if pointer provided */
    if (value != NULL) {
        *value = result;
    }

    /* Read final turnaround bit */
    [self miiReadBit];

    /* Return success if turnaround bit was 0 */
    return (turnaroundBit == 0);
}

/*
 * Write value to MII interface
 * Writes the specified number of bits from value (MSB first)
 */
- (void)miiWrite:(unsigned int)value size:(unsigned int)size
{
    unsigned short dataBit;
    int i;

    for (i = 0; i < (int)size; i++) {
        /* Extract MSB and convert to data bit value (0 or 2) */
        /* The sign bit is used, multiplied by -2 gives 0 or 0xFFFE, but we only use low bits */
        dataBit = ((value & 0x80000000) ? 2 : 0);

        /* Clock low, data bit set, write enabled */
        SELECT_MII_WINDOW;
        outw(ioBase + REG_MII_DATA, dataBit | MII_DATA_WRITE_ENABLE);
        IODelay(1);

        /* Clock high, data bit set, write enabled */
        SELECT_MII_WINDOW;
        outw(ioBase + REG_MII_DATA, dataBit | MII_DATA_WRITE_ENABLE | MII_DATA_CLOCK);
        IODelay(1);

        /* Clock low, data bit set, write enabled */
        SELECT_MII_WINDOW;
        outw(ioBase + REG_MII_DATA, dataBit | MII_DATA_WRITE_ENABLE);
        IODelay(1);

        /* Shift to next bit */
        value <<= 1;
    }
}

/*
 * Write a word to MII register
 */
- (void)miiWriteWord:(unsigned short)value reg:(unsigned short)reg phy:(unsigned short)phy
{
    unsigned int command;

    /* Send 32-bit preamble (all 1's) */
    [self miiWrite:0xFFFFFFFF size:32];

    /* Build write command (32 bits total):
     * Format: [start:01] [write:01] [phy:5bits] [reg:5bits] [turnaround:10] [data:16bits]
     * The 0x5002 comes from:
     *   - Start bits: 01 (2 bits)
     *   - Write command: 01 (2 bits)
     *   - This forms 0101 at the top = 0x5
     *   - Then OR with 0x0002 for turnaround
     */
    command = ((phy & 0x1F) << 23) |    /* PHY address in bits 23-27 */
              MII_CMD_WRITE |            /* Write command 0x50000000 */
              ((reg & 0x1F) << 18) |     /* Register address in bits 18-22 */
              0x00020000 |               /* Turnaround bits */
              (value & 0xFFFF);          /* Data in bits 0-15 */

    /* Send 32-bit write command with data */
    [self miiWrite:command size:32];

    /* Read turnaround bit */
    [self miiReadBit];
}

/*
 * Reset MII device
 */
- (BOOL)resetMIIDevice:(unsigned short)phy
{
    unsigned short controlReg;
    int timeout;
    BOOL success;

    /* Read current control register value */
    success = [self miiReadWord:&controlReg reg:MII_CONTROL phy:phy];
    if (!success) {
        return NO;
    }

    /* Write control register with reset bit set (bit 15) */
    [self miiWriteWord:(controlReg | MII_CONTROL_RESET) reg:MII_CONTROL phy:phy];

    /* Wait for reset to complete (reset bit clears when done) */
    timeout = 100;  /* 100ms timeout */
    while (timeout > 0) {
        /* Read control register */
        success = [self miiReadWord:&controlReg reg:MII_CONTROL phy:phy];
        if (!success) {
            return NO;
        }

        /* Check if reset bit has cleared (bit 15) */
        if ((controlReg & MII_CONTROL_RESET) == 0) {
            return YES;
        }

        /* Sleep 10ms between polls */
        IOSleep(10);
        timeout -= 10;
    }

    /* Timeout - reset failed */
    return NO;
}

/*
 * Wait for MII auto-negotiation to complete
 */
- (BOOL)waitMIIAutoNegotiation:(unsigned short)phy
{
    unsigned short statusReg;
    int timeout;
    BOOL success;

    /* Wait for auto-negotiation to complete (bit 5 in status register) */
    timeout = 5000;  /* 5 second timeout */
    while (timeout > 0) {
        /* Read MII status register */
        success = [self miiReadWord:&statusReg reg:MII_STATUS phy:phy];
        if (!success) {
            return NO;
        }

        /* Check if auto-negotiation done bit is set (bit 5 = 0x20) */
        if ((statusReg & MII_STATUS_AUTONEG_DONE) != 0) {
            return YES;
        }

        /* Sleep 20ms between polls */
        IOSleep(20);
        timeout -= 20;
    }

    /* Timeout - auto-negotiation failed */
    return NO;
}

/*
 * Wait for MII link to come up
 */
- (BOOL)waitMIILink:(unsigned short)phy
{
    unsigned short statusReg;
    int timeout;
    BOOL success;

    /* Wait for link to come up (bit 2 in status register) */
    timeout = 5000;  /* 5 second timeout */
    while (timeout > 0) {
        /* Read MII status register */
        success = [self miiReadWord:&statusReg reg:MII_STATUS phy:phy];
        if (!success) {
            return NO;
        }

        /* Check if link up bit is set (bit 2 = 0x04) */
        if ((statusReg & MII_STATUS_LINK_UP) != 0) {
            return YES;
        }

        /* Sleep 20ms between polls */
        IOSleep(20);
        timeout -= 20;
    }

    /* Timeout - link failed to come up */
    return NO;
}

@end
