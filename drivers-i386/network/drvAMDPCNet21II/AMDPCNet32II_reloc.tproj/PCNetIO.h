#define RDP32 0x10
#define RDP16 0x10

#define RAP16 0x12
#define RAP32 0x14

#define RST16 0x14
#define RST32 0x18

#define BDP16 0x14
#define BDP32 0x1c

/* Control and Status Register Addresses */
#define LANCE_CSR0   0   /* Controller Status Register */
#define LANCE_CSR1   1   /* Initialization Block Address (Lower) */
#define LANCE_CSR2   2   /* Initialization Block Address (Upper) */
#define LANCE_CSR3   3   /* Interrupt Masks and Deferral Control */
#define LANCE_CSR4   4   /* Test and Features Control */
#define LANCE_CSR5   5   /* Extended Control and Interrupt */
#define LANCE_CSR8   8   /* Logical Address Filter 0 */
#define LANCE_CSR9   9   /* Logical Address Filter 1 */
#define LANCE_CSR10 10   /* Logical Address Filter 2 */
#define LANCE_CSR11 11   /* Logical Address Filter 3 */
#define LANCE_CSR15 15   /* Mode */
#define LANCE_CSR58 58  
#define LANCE_CSR88 88   /* Chip ID Register (Lower) */
#define LANCE_CSR89 89   /* Chip ID Register (Upper) */

#define LANCE_BCR2   2   /* Bus Configuration Register 2 */

/* Control and Status Register 0 (CSR0) */
#define LANCE_CSR0_ERR       0x8000 /* Error Occurred */
#define LANCE_CSR0_BABL      0x4000 /* Transmitter Timeout Error */
#define LANCE_CSR0_CERR      0x2000 /* Collision Error */
#define LANCE_CSR0_MISS      0x1000 /* Missed Frame */
#define LANCE_CSR0_MERR      0x0800 /* Memory Error */
#define LANCE_CSR0_RINT      0x0400 /* Receive Interrupt */
#define LANCE_CSR0_TINT      0x0200 /* Transmit Interrupt */
#define LANCE_CSR0_IDON      0x0100 /* Initialization Done */
#define LANCE_CSR0_INTR      0x0080 /* Interrupt Flag */
#define LANCE_CSR0_IENA      0x0040 /* Interrupt Enable */
#define LANCE_CSR0_RXON      0x0020 /* Receive On */
#define LANCE_CSR0_TXON      0x0010 /* Transmit On */
#define LANCE_CSR0_TDMD      0x0008 /* Transmit Demand */
#define LANCE_CSR0_STOP      0x0004 /* Stop */
#define LANCE_CSR0_STRT      0x0002 /* Start */
#define LANCE_CSR0_INIT      0x0001 /* Init */

/* Control and Status Register 3 (CSR3) */
/*                           0x8000    Reserved */
#define LANCE_CSR3_BABLM     0x4000 /* Babble Mask */
/*                           0x2000    Reserved */
#define LANCE_CSR3_MISSM     0x1000 /* Missed Frame Mask */
#define LANCE_CSR3_MERRM     0x0800 /* Memory Error Mask */
#define LANCE_CSR3_RINTM     0x0400 /* Receive Interrupt Mask */
#define LANCE_CSR3_TINTM     0x0200 /* Transmit Interrupt Mask */
#define LANCE_CSR3_IDONM     0x0100 /* Initialization Done Mask */
/*                           0x0080    Reserved */
#define LANCE_CSR3_DXSUFLO   0x0040 /* Disable Transmit Stop on Underflow */
#define LANCE_CSR3_LAPPEN    0x0020 /* Look Ahead Packet Processing Enable */
#define LANCE_CSR3_DXMT2PD   0x0010 /* Disable Transmit Two Part Deferral */
#define LANCE_CSR3_EMBA      0x0008 /* Enable Modified Back-off Algorithm */
#define LANCE_CSR3_BSWP      0x0004 /* Byte Swap */
/*                           0x0002    Reserved
 *                           0x0001    Reserved */


#define LANCE_CSR5_SPND  0x0001 /* Suspsend */

#define LANCE_CSR15_PROM 0x8000 /* Promiscious mode */