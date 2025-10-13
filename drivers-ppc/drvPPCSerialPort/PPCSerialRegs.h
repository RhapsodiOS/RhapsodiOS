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
 * PPCSerialRegs.h - Zilog 8530 SCC Register Definitions
 *
 * Based on the Zilog Z8530 Serial Communications Controller
 * Used in PowerMac systems for serial ports
 */

#ifndef _PPC_SERIAL_REGS_H
#define _PPC_SERIAL_REGS_H

/* ========== SCC Register Offsets ========== */

/* Channel A and B register offsets */
#define SCC_R_CMD_A             0x02    /* Channel A command */
#define SCC_R_DATA_A            0x03    /* Channel A data */
#define SCC_R_CMD_B             0x00    /* Channel B command */
#define SCC_R_DATA_B            0x01    /* Channel B data */

/* ========== Write Registers ========== */

/* WR0 - Command Register */
#define WR0_REG_MASK            0x07    /* Register select mask */
#define WR0_CMD_MASK            0x38    /* Command mask */
#define WR0_CMD_NULL            0x00    /* Null command */
#define WR0_CMD_POINT_HIGH      0x08    /* Point to upper half */
#define WR0_CMD_RST_EXT         0x10    /* Reset external/status interrupts */
#define WR0_CMD_SEND_ABORT      0x18    /* Send abort (SDLC) */
#define WR0_CMD_INT_NEXT_RX     0x20    /* Enable int on next RX character */
#define WR0_CMD_RST_TX_INT      0x28    /* Reset TX interrupt pending */
#define WR0_CMD_ERR_RESET       0x30    /* Error reset */
#define WR0_CMD_RST_IUS         0x38    /* Reset highest IUS */
#define WR0_RST_RX_CRC          0x40    /* Reset RX CRC checker */
#define WR0_RST_TX_CRC          0x80    /* Reset TX CRC generator */
#define WR0_RST_TX_UND          0xC0    /* Reset TX underrun/EOM latch */

/* WR1 - Interrupt and Transfer Mode */
#define WR1_EXT_INT_EN          0x01    /* External interrupt enable */
#define WR1_TX_INT_EN           0x02    /* TX interrupt enable */
#define WR1_PARITY_SPECIAL      0x04    /* Parity is special condition */
#define WR1_RX_INT_DISABLE      0x00    /* RX interrupts disabled */
#define WR1_RX_INT_FIRST        0x08    /* RX interrupt on first character */
#define WR1_RX_INT_ALL_PARITY   0x10    /* RX interrupt on all, parity affects vector */
#define WR1_RX_INT_ALL          0x18    /* RX interrupt on all characters */
#define WR1_WAIT_DMA_REQ_RX     0x20    /* Wait/DMA request on RX */
#define WR1_WAIT_DMA_FN_TX      0x40    /* Wait/DMA request function for TX */
#define WR1_WAIT_DMA_EN         0x80    /* Wait/DMA request enable */

/* WR2 - Interrupt Vector (Channel B only) */
/* Interrupt vector is written to this register */

/* WR3 - Receive Parameters and Control */
#define WR3_RX_ENABLE           0x01    /* RX enable */
#define WR3_SYNC_CHAR_LOAD_INH  0x02    /* Sync character load inhibit */
#define WR3_ADDRESS_SEARCH      0x04    /* Address search mode (SDLC) */
#define WR3_RX_CRC_ENABLE       0x08    /* RX CRC enable */
#define WR3_ENTER_HUNT          0x10    /* Enter hunt mode */
#define WR3_AUTO_ENABLES        0x20    /* Auto enables */
#define WR3_RX_5_BITS           0x00    /* RX 5 bits/character */
#define WR3_RX_7_BITS           0x40    /* RX 7 bits/character */
#define WR3_RX_6_BITS           0x80    /* RX 6 bits/character */
#define WR3_RX_8_BITS           0xC0    /* RX 8 bits/character */

/* WR4 - TX/RX Miscellaneous Parameters and Modes */
#define WR4_PARITY_EN           0x01    /* Parity enable */
#define WR4_PARITY_EVEN         0x02    /* Even parity (0=odd) */
#define WR4_SYNC_MODE_MASK      0x0C    /* Sync mode mask */
#define WR4_SYNC_8BIT           0x00    /* 8-bit sync character */
#define WR4_SYNC_16BIT          0x04    /* 16-bit sync character */
#define WR4_SDLC_MODE           0x08    /* SDLC mode */
#define WR4_EXT_SYNC            0x0C    /* External sync mode */
#define WR4_STOP_BITS_MASK      0x0C    /* Stop bits mask */
#define WR4_SYNC_MODE           0x00    /* Sync modes enable */
#define WR4_1_STOP              0x04    /* 1 stop bit */
#define WR4_1_5_STOP            0x08    /* 1.5 stop bits */
#define WR4_2_STOP              0x0C    /* 2 stop bits */
#define WR4_X1_CLK              0x00    /* x1 clock mode */
#define WR4_X16_CLK             0x40    /* x16 clock mode */
#define WR4_X32_CLK             0x80    /* x32 clock mode */
#define WR4_X64_CLK             0xC0    /* x64 clock mode */

/* WR5 - Transmit Parameters and Controls */
#define WR5_TX_CRC_EN           0x01    /* TX CRC enable */
#define WR5_RTS                 0x02    /* RTS */
#define WR5_SDLC_CRC16          0x04    /* SDLC/CRC-16 */
#define WR5_TX_ENABLE           0x08    /* TX enable */
#define WR5_SEND_BREAK          0x10    /* Send break */
#define WR5_TX_5_BITS           0x00    /* TX 5 bits */
#define WR5_TX_7_BITS           0x20    /* TX 7 bits */
#define WR5_TX_6_BITS           0x40    /* TX 6 bits */
#define WR5_TX_8_BITS           0x60    /* TX 8 bits */
#define WR5_DTR                 0x80    /* DTR */

/* WR6 - Sync Characters or SDLC Address Field */
/* Sync character or address */

/* WR7 - Sync Character or SDLC Flag */
/* Sync character or SDLC flag */

/* WR9 - Master Interrupt Control and Reset */
#define WR9_VIS                 0x01    /* Vector includes status */
#define WR9_NV                  0x02    /* No vector */
#define WR9_DLC                 0x04    /* Disable lower chain */
#define WR9_MIE                 0x08    /* Master interrupt enable */
#define WR9_STATUS_HI           0x10    /* Status high */
#define WR9_NO_RESET            0x00    /* No reset */
#define WR9_CH_B_RESET          0x40    /* Channel B reset */
#define WR9_CH_A_RESET          0x80    /* Channel A reset */
#define WR9_FORCE_HDWR_RESET    0xC0    /* Force hardware reset */

/* WR10 - Miscellaneous Transmitter/Receiver Control Bits */
#define WR10_6BIT_SYNC          0x01    /* 6-bit sync */
#define WR10_LOOP_MODE          0x02    /* Loop mode */
#define WR10_ABORT_UNDERRUN     0x04    /* Abort on underrun */
#define WR10_MARK_IDLE          0x08    /* Mark idle */
#define WR10_GO_ACTIVE_ON_POLL  0x10    /* Go active on poll */
#define WR10_NRZ                0x00    /* NRZ encoding */
#define WR10_NRZI               0x20    /* NRZI encoding */
#define WR10_FM1                0x40    /* FM1 encoding */
#define WR10_FM0                0x60    /* FM0 encoding */
#define WR10_CRC_PRESET         0x80    /* CRC preset I/O */

/* WR11 - Clock Mode Control */
#define WR11_TRXC_OUT_XTAL      0x00    /* TRxC output = XTAL */
#define WR11_TRXC_OUT_TX_CLK    0x01    /* TRxC output = TX clock */
#define WR11_TRXC_OUT_BRG       0x02    /* TRxC output = BRG */
#define WR11_TRXC_OUT_DPLL      0x03    /* TRxC output = DPLL */
#define WR11_TX_CLK_RTXC        0x00    /* TX clock = RTxC pin */
#define WR11_TX_CLK_TRXC        0x08    /* TX clock = TRxC pin */
#define WR11_TX_CLK_BRG         0x10    /* TX clock = BRG */
#define WR11_TX_CLK_DPLL        0x18    /* TX clock = DPLL */
#define WR11_RX_CLK_RTXC        0x00    /* RX clock = RTxC pin */
#define WR11_RX_CLK_TRXC        0x20    /* RX clock = TRxC pin */
#define WR11_RX_CLK_BRG         0x40    /* RX clock = BRG */
#define WR11_RX_CLK_DPLL        0x60    /* RX clock = DPLL */
#define WR11_RTXC_XTAL          0x80    /* RTxC = XTAL */

/* WR12 - Lower Byte of Baud Rate Generator Time Constant */
/* Time constant low byte */

/* WR13 - Upper Byte of Baud Rate Generator Time Constant */
/* Time constant high byte */

/* WR14 - Miscellaneous Control Bits */
#define WR14_BRG_ENABLE         0x01    /* BRG enable */
#define WR14_BRG_SOURCE         0x02    /* BRG source */
#define WR14_DTR_REQ_FN         0x04    /* DTR/REQ function */
#define WR14_AUTO_ECHO          0x08    /* Auto echo */
#define WR14_LOCAL_LOOPBACK     0x10    /* Local loopback */
#define WR14_NULL               0x00    /* Null command */
#define WR14_SEARCH_MODE        0x20    /* Enter search mode */
#define WR14_RESET_MISSING_CLK  0x40    /* Reset missing clock */
#define WR14_DISABLE_DPLL       0x60    /* Disable DPLL */
#define WR14_SET_SOURCE_BRG     0x80    /* Set source = BRG */
#define WR14_SET_SOURCE_RTXC    0xA0    /* Set source = RTxC */
#define WR14_SET_FM_MODE        0xC0    /* Set FM mode */
#define WR14_SET_NRZI_MODE      0xE0    /* Set NRZI mode */

/* WR15 - External/Status Interrupt Control */
#define WR15_ZERO_COUNT_IE      0x02    /* Zero count IE */
#define WR15_DCD_IE             0x08    /* DCD IE */
#define WR15_SYNC_HUNT_IE       0x10    /* Sync/hunt IE */
#define WR15_CTS_IE             0x20    /* CTS IE */
#define WR15_TX_UNDERRUN_IE     0x40    /* TX underrun/EOM IE */
#define WR15_BREAK_ABORT_IE     0x80    /* Break/abort IE */

/* ========== Read Registers ========== */

/* RR0 - TX/RX Buffer Status and External Status */
#define RR0_RX_CHAR_AVAIL       0x01    /* RX character available */
#define RR0_ZERO_COUNT          0x02    /* Zero count */
#define RR0_TX_BUFFER_EMPTY     0x04    /* TX buffer empty */
#define RR0_DCD                 0x08    /* DCD */
#define RR0_SYNC_HUNT           0x10    /* Sync/hunt */
#define RR0_CTS                 0x20    /* CTS */
#define RR0_TX_UNDERRUN         0x40    /* TX underrun/EOM */
#define RR0_BREAK_ABORT         0x80    /* Break/abort */

/* RR1 - Special Receive Condition Status */
#define RR1_ALL_SENT            0x01    /* All sent */
#define RR1_RESIDUE_CODE_MASK   0x0E    /* Residue code mask */
#define RR1_PARITY_ERROR        0x10    /* Parity error */
#define RR1_RX_OVERRUN          0x20    /* RX overrun error */
#define RR1_CRC_FRAMING_ERROR   0x40    /* CRC/framing error */
#define RR1_END_OF_FRAME        0x80    /* End of frame (SDLC) */

/* RR2 - Interrupt Vector (Channel B) or modified vector (Channel A) */
/* Interrupt vector */

/* RR3 - Interrupt Pending Bits (Channel A only) */
#define RR3_CH_B_EXT_IP         0x01    /* Channel B ext/status IP */
#define RR3_CH_B_TX_IP          0x02    /* Channel B TX IP */
#define RR3_CH_B_RX_IP          0x04    /* Channel B RX IP */
#define RR3_CH_A_EXT_IP         0x08    /* Channel A ext/status IP */
#define RR3_CH_A_TX_IP          0x10    /* Channel A TX IP */
#define RR3_CH_A_RX_IP          0x20    /* Channel A RX IP */

/* RR8 - Receive Buffer (same as data register) */
/* Receive data */

/* RR10 - Miscellaneous Status */
#define RR10_ON_LOOP            0x02    /* On loop */
#define RR10_LOOP_SENDING       0x10    /* Loop sending */
#define RR10_TWO_CLOCKS_MISSING 0x40    /* Two clocks missing */
#define RR10_ONE_CLOCK_MISSING  0x80    /* One clock missing */

/* RR12 - Lower Byte of Baud Rate Generator Time Constant */
/* Time constant low byte (same as WR12) */

/* RR13 - Upper Byte of Baud Rate Generator Time Constant */
/* Time constant high byte (same as WR13) */

/* RR15 - External/Status Interrupt Information */
/* Same bits as WR15 */

#endif /* _PPC_SERIAL_REGS_H */
