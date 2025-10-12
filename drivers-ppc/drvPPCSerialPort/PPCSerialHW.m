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

/**
 * PPCSerialHW.m - Hardware support for PowerPC SCC Serial Port
 */

#import "PPCSerialPort.h"
#import "PPCSerialRegs.h"
#import <kernserv/prototypes.h>

@implementation PPCSerialPort (Hardware)

/*
 * Read SCC register
 */
- (UInt8) readReg : (UInt8) reg
{
    volatile UInt8 *cmdReg;
    volatile UInt8 *dataReg;

    if (channel == SCC_CHANNEL_A) {
        cmdReg = (volatile UInt8 *)(baseAddress + SCC_R_CMD_A);
        dataReg = (volatile UInt8 *)(baseAddress + SCC_R_DATA_A);
    } else {
        cmdReg = (volatile UInt8 *)(baseAddress + SCC_R_CMD_B);
        dataReg = (volatile UInt8 *)(baseAddress + SCC_R_DATA_B);
    }

    if (reg != 0) {
        *cmdReg = reg;
        eieio();
    }

    return *cmdReg;
}

/*
 * Write SCC register
 */
- (void) writeReg : (UInt8) reg value : (UInt8) value
{
    volatile UInt8 *cmdReg;

    if (channel == SCC_CHANNEL_A) {
        cmdReg = (volatile UInt8 *)(baseAddress + SCC_R_CMD_A);
    } else {
        cmdReg = (volatile UInt8 *)(baseAddress + SCC_R_CMD_B);
    }

    *cmdReg = reg;
    eieio();
    *cmdReg = value;
    eieio();
}

/*
 * Read data register
 */
- (UInt8) readData
{
    volatile UInt8 *dataReg;

    if (channel == SCC_CHANNEL_A) {
        dataReg = (volatile UInt8 *)(baseAddress + SCC_R_DATA_A);
    } else {
        dataReg = (volatile UInt8 *)(baseAddress + SCC_R_DATA_B);
    }

    return *dataReg;
}

/*
 * Write data register
 */
- (void) writeData : (UInt8) data
{
    volatile UInt8 *dataReg;

    if (channel == SCC_CHANNEL_A) {
        dataReg = (volatile UInt8 *)(baseAddress + SCC_R_DATA_A);
    } else {
        dataReg = (volatile UInt8 *)(baseAddress + SCC_R_DATA_B);
    }

    *dataReg = data;
    eieio();
}

/*
 * Reset SCC
 */
- (void) resetSCC
{
    /* Issue hardware reset */
    [self writeReg:9 value:WR9_FORCE_HDWR_RESET];
    IODelay(100);

    /* Reset this channel */
    if (channel == SCC_CHANNEL_A) {
        [self writeReg:9 value:WR9_CH_A_RESET];
    } else {
        [self writeReg:9 value:WR9_CH_B_RESET];
    }
    IODelay(10);

    /* Clear interrupt pending */
    [self writeReg:0 value:WR0_CMD_RST_EXT];
    [self writeReg:0 value:WR0_CMD_RST_TX_INT];
    [self writeReg:0 value:WR0_CMD_ERR_RESET];
}

/*
 * Configure SCC
 */
- (void) configureSCC
{
    UInt16 timeConstant;
    UInt8 wr3, wr4, wr5;

    /* Calculate baud rate time constant */
    timeConstant = (clockRate / (2 * baudRate * 16)) - 2;

    /* Configure WR4 - clock mode, stop bits, parity */
    wr4 = WR4_X16_CLK;  /* x16 clock mode */

    if (stopBits == 2) {
        wr4 |= WR4_2_STOP;
    } else {
        wr4 |= WR4_1_STOP;
    }

    switch (parity) {
        case PARITY_EVEN:
            wr4 |= WR4_PARITY_EN | WR4_PARITY_EVEN;
            break;
        case PARITY_ODD:
            wr4 |= WR4_PARITY_EN;
            break;
        default:
            break;
    }

    [self writeReg:4 value:wr4];

    /* Configure WR3 - receiver */
    wr3 = WR3_RX_ENABLE;
    switch (dataBits) {
        case 5: wr3 |= WR3_RX_5_BITS; break;
        case 6: wr3 |= WR3_RX_6_BITS; break;
        case 7: wr3 |= WR3_RX_7_BITS; break;
        case 8: wr3 |= WR3_RX_8_BITS; break;
    }
    [self writeReg:3 value:wr3];

    /* Configure WR5 - transmitter */
    wr5 = WR5_TX_ENABLE | WR5_RTS | WR5_DTR;
    switch (dataBits) {
        case 5: wr5 |= WR5_TX_5_BITS; break;
        case 6: wr5 |= WR5_TX_6_BITS; break;
        case 7: wr5 |= WR5_TX_7_BITS; break;
        case 8: wr5 |= WR5_TX_8_BITS; break;
    }
    [self writeReg:5 value:wr5];

    /* Configure baud rate generator */
    [self writeReg:12 value:(timeConstant & 0xFF)];
    [self writeReg:13 value:((timeConstant >> 8) & 0xFF)];

    /* Configure WR11 - clock sources */
    [self writeReg:11 value:(WR11_TX_CLK_BRG | WR11_RX_CLK_BRG | WR11_TRXC_OUT_BRG)];

    /* Configure WR14 - enable BRG */
    [self writeReg:14 value:WR14_BRG_ENABLE];

    /* Configure WR1 - interrupts */
    [self writeReg:1 value:(WR1_RX_INT_ALL | WR1_TX_INT_EN | WR1_EXT_INT_EN)];
}

/*
 * Enable interrupts
 */
- (void) enableInterrupts
{
    /* Enable master interrupt */
    [self writeReg:9 value:WR9_MIE];

    /* Enable specific interrupts */
    [self writeReg:15 value:(WR15_CTS_IE | WR15_DCD_IE | WR15_BREAK_ABORT_IE)];
}

/*
 * Disable interrupts
 */
- (void) disableInterrupts
{
    /* Disable master interrupt */
    [self writeReg:9 value:0];

    /* Disable specific interrupts */
    [self writeReg:1 value:0];
    [self writeReg:15 value:0];
}

/*
 * Trigger TX interrupt
 */
- (void) triggerTxInterrupt
{
    /* Enable TX interrupt if data available */
    if (txCount > 0) {
        UInt8 wr1 = WR1_RX_INT_ALL | WR1_TX_INT_EN | WR1_EXT_INT_EN;
        [self writeReg:1 value:wr1];
    }
}

/*
 * Set DTR
 */
- (IOReturn) setDTR : (BOOL) state
{
    UInt8 wr5 = [self readReg:5];

    if (state) {
        wr5 |= WR5_DTR;
    } else {
        wr5 &= ~WR5_DTR;
    }

    [self writeReg:5 value:wr5];
    dtrState = state;

    return IO_R_SUCCESS;
}

/*
 * Set RTS
 */
- (IOReturn) setRTS : (BOOL) state
{
    UInt8 wr5 = [self readReg:5];

    if (state) {
        wr5 |= WR5_RTS;
    } else {
        wr5 &= ~WR5_RTS;
    }

    [self writeReg:5 value:wr5];
    rtsState = state;

    return IO_R_SUCCESS;
}

/*
 * Flush TX buffer
 */
- (IOReturn) flushTxBuffer
{
    [txLock lock];
    txHead = txTail = txCount = 0;
    [txLock unlock];
    return IO_R_SUCCESS;
}

/*
 * Flush RX buffer
 */
- (IOReturn) flushRxBuffer
{
    [rxLock lock];
    rxHead = rxTail = rxCount = 0;
    [rxLock unlock];

    /* Reset receiver */
    [self writeReg:0 value:WR0_CMD_ERR_RESET];

    return IO_R_SUCCESS;
}

@end
