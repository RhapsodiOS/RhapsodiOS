/*
 * DECchip2104xRegisters.h
 * DEC 21040/21041 Ethernet Controller Register Definitions
 */

#ifndef _DECCHIP2104XREGISTERS_H
#define _DECCHIP2104XREGISTERS_H

/* CSR (Control/Status Register) offsets */
#define CSR0_BUS_MODE           0x00
#define CSR1_TX_POLL_DEMAND     0x08
#define CSR1_TX_POLL            0x08  /* Alias */
#define CSR2_RX_POLL_DEMAND     0x10
#define CSR3_RX_LIST_BASE       0x18
#define CSR3_RX_LIST            0x18  /* Alias */
#define CSR4_TX_LIST_BASE       0x20
#define CSR4_TX_LIST            0x20  /* Alias */
#define CSR5_STATUS             0x28
#define CSR6_COMMAND            0x30
#define CSR7_INTERRUPT_MASK     0x38
#define CSR8_MISSED_FRAMES      0x40
#define CSR9_BOOT_ROM           0x48
#define CSR11_TIMER             0x58
#define CSR12_SIA_STATUS        0x60
#define CSR13_SIA_CONNECTIVITY  0x68
#define CSR14_SIA_TX_RX         0x70
#define CSR15_SIA_GENERAL       0x78

/* CSR0 - Bus Mode Register bits */
#define CSR0_SWR    0x00000001  /* Software Reset */
#define CSR0_BAR    0x00000002  /* Bus Arbitration */
#define CSR0_DSL    0x0000007C  /* Descriptor Skip Length */
#define CSR0_BLE    0x00000080  /* Big/Little Endian */
#define CSR0_PBL    0x00003F00  /* Programmable Burst Length */
#define CSR0_CAL    0x0000C000  /* Cache Alignment */
#define CSR0_TAP    0x000E0000  /* Transmit Automatic Polling */
#define CSR0_DBO    0x00100000  /* Descriptor Byte Ordering */

/* CSR5 - Status Register bits */
#define CSR5_TI     0x00000001  /* Transmit Interrupt */
#define CSR5_TPS    0x00000002  /* Transmit Process Stopped */
#define CSR5_TU     0x00000004  /* Transmit Buffer Unavailable */
#define CSR5_TJT    0x00000008  /* Transmit Jabber Timeout */
#define CSR5_UNF    0x00000020  /* Transmit Underflow */
#define CSR5_RI     0x00000040  /* Receive Interrupt */
#define CSR5_RU     0x00000080  /* Receive Buffer Unavailable */
#define CSR5_RPS    0x00000100  /* Receive Process Stopped */
#define CSR5_RWT    0x00000200  /* Receive Watchdog Timeout */
#define CSR5_ETI    0x00000400  /* Early Transmit Interrupt */
#define CSR5_FBE    0x00002000  /* Fatal Bus Error */
#define CSR5_ERI    0x00004000  /* Early Receive Interrupt */
#define CSR5_AIS    0x00008000  /* Abnormal Interrupt Summary */
#define CSR5_NIS    0x00010000  /* Normal Interrupt Summary */
#define CSR5_RS     0x000E0000  /* Receive Process State */
#define CSR5_TS     0x00700000  /* Transmit Process State */
#define CSR5_EB     0x03800000  /* Error Bits */

/* CSR6 - Command Register bits */
#define CSR6_HP     0x00000001  /* Hash/Perfect Filter Mode */
#define CSR6_SR     0x00000002  /* Start/Stop Receive */
#define CSR6_HO     0x00000004  /* Hash Only Filtering Mode */
#define CSR6_PB     0x00000008  /* Pass Bad Frames */
#define CSR6_IF     0x00000010  /* Inverse Filtering */
#define CSR6_SB     0x00000020  /* Start/Stop Backoff Counter */
#define CSR6_PR     0x00000040  /* Promiscuous Mode */
#define CSR6_PM     0x00000080  /* Pass All Multicast */
#define CSR6_FKD    0x00000100  /* Flaky Oscillator Disable */
#define CSR6_FD     0x00000200  /* Full Duplex Mode */
#define CSR6_OM     0x00000C00  /* Operating Mode */
#define CSR6_FC     0x00001000  /* Force Collision */
#define CSR6_ST     0x00002000  /* Start/Stop Transmission */
#define CSR6_TR     0x0000C000  /* Threshold Control Bits */
#define CSR6_CA     0x00020000  /* Capture Effect Enable */
#define CSR6_PS     0x00040000  /* Port Select */
#define CSR6_HBD    0x00080000  /* Heartbeat Disable */
#define CSR6_IMM    0x00100000  /* Immediate Mode */
#define CSR6_SF     0x00200000  /* Store and Forward */
#define CSR6_TTM    0x00400000  /* Transmit Threshold Mode */
#define CSR6_PCS    0x00800000  /* PCS Function */
#define CSR6_SCR    0x01000000  /* Scrambler Mode */

/* Descriptor status bits */
#define DESC_OWN    0x80000000  /* Descriptor owned by controller */

#endif /* _DECCHIP2104XREGISTERS_H */
