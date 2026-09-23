/*
 * E100Regs.h - Intel 8255x registers, command blocks and EEPROM layout.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see LICENSE.
 *
 * "SDM" is Intel's 8255x 10/100 Mbps Ethernet Controller Family Open
 * Source Software Developer Manual, rev 1.0. Values the SDM does not give
 * (the EEPROM word map, the PHY word bits) follow FreeBSD's if_fxpreg.h and
 * say so.
 *
 * Plain C89: tests/ compiles this on the build guest.
 */
#ifndef E100REGS_H
#define E100REGS_H

/* Control/status registers, as offsets into the I/O BAR (SDM Table 11) */
#define E100_SCB_STATUS         0x00    /* byte: CU and RU state          */
#define E100_SCB_STATACK        0x01    /* byte: causes; write 1s to ack  */
#define E100_SCB_CMD            0x02    /* byte: CU and RU commands       */
#define E100_SCB_INTR           0x03    /* byte: interrupt mask           */
#define E100_SCB_GENPTR         0x04    /* long: general pointer          */
#define E100_PORT               0x08    /* long: PORT interface           */
#define E100_EECTL              0x0E    /* word: EEPROM control           */
#define E100_MDICTL             0x10    /* long: MDI control              */

/* SCB status byte (SDM 6.3.2.1) */
#define E100_CUS_MASK           0xC0    /* 00 = CU idle                   */

/* STAT/ACK byte */
#define E100_STAT_CX            0x80    /* CB with the I bit completed    */
#define E100_STAT_FR            0x40    /* frame received                 */
#define E100_STAT_CNA           0x20    /* CU left the active state       */
#define E100_STAT_RNR           0x10    /* RU left the ready state        */

/* SCB command byte: CU command in bits 7:4, RU command in bits 2:0 */
#define E100_CUC_NOP            0x00
#define E100_CUC_START          0x10
#define E100_CUC_RESUME         0x20
#define E100_CUC_DUMP_ADDR      0x40    /* load dump counters address     */
#define E100_CUC_LOAD_BASE      0x60
#define E100_CUC_DUMP_RESET     0x70    /* dump and reset counters        */
#define E100_RUC_START          0x01
#define E100_RUC_LOAD_BASE      0x06

/* Interrupt control byte */
#define E100_INTR_MASK_ALL      0x01    /* M: masks every source          */

/* PORT opcodes (SDM 6.3.3) */
#define E100_PORT_SOFTWARE_RESET        0x00000000UL
#define E100_PORT_SELECTIVE_RESET       0x00000002UL

/* EEPROM control word (SDM 6.3.4) */
#define E100_EE_SK              0x01
#define E100_EE_CS              0x02
#define E100_EE_DI              0x04
#define E100_EE_DO              0x08
#define E100_EE_OP_READ         0x6     /* 110b, sent most significant first */

/* EEPROM word map (FreeBSD if_fxpreg.h) */
#define E100_EEPROM_COMPAT      0x03
#define E100_EEPROM_CONTROLLER  0x05    /* high byte 1 means an 82557     */
#define E100_EEPROM_PHY         0x06
#define E100_EEPROM_ID          0x0A
#define E100_EEPROM_WORDS_KEPT  0x0B    /* words 0..0x0A are all we use   */
#define E100_EEPROM_SUM         0xBABA  /* sum of every word, checksum too */

#define E100_COMPAT_RXBUG_FIXED 0x0003  /* both set: 82557 lockup fixed   */
#define E100_PHY_ADDR_MASK      0x001F
#define E100_PHY_DEVICE_MASK    0x3F00
#define E100_PHY_SERIAL_ONLY    0x8000  /* 82503 serial interface, no MII */
#define E100_ID_STANDBY         0x0002  /* Dynamic Standby enabled        */

/* MDI control register (SDM 6.3.5) */
#define E100_MDI_OP_WRITE       0x04000000UL
#define E100_MDI_OP_READ        0x08000000UL
#define E100_MDI_READY          0x10000000UL
#define E100_MDI_PHY_SHIFT      21
#define E100_MDI_REG_SHIFT      16

/* MII registers and bits (IEEE 802.3 clause 22; register 16 is SDM 7.5) */
#define MII_BMCR                0
#define MII_BMSR                1
#define MII_PHYID1              2
#define MII_PHYID2              3
#define MII_ANAR                4
#define MII_ANLPAR              5
#define MII_INTEL_STATUS        16
#define BMCR_AUTONEG            0x1000
#define BMCR_RESTART_AUTONEG    0x0200
#define BMSR_AUTONEG_DONE       0x0020
#define BMSR_LINK               0x0004
#define ANLPAR_100FD            0x0100
#define ANLPAR_100TX            0x0080
#define ANLPAR_10FD             0x0040
#define ANLPAR_10               0x0020
#define INTEL_STATUS_100        0x0002
#define INTEL_STATUS_FD         0x0001
#define INTEL_PHYID1            0x02A8  /* OUI 00AA00 (SDM 7.5)           */

/*
 * Command block header (SDM 6.4.2). Dword 0 is status in its low half and
 * command in its high half, which on the little-endian i386 is the order
 * of the two shorts in memory.
 */
typedef struct {
    volatile unsigned short     status;
    volatile unsigned short     command;
    volatile unsigned long      link;
} E100CBHeader;

#define E100_CB_C               0x8000  /* status: complete               */
#define E100_CB_OK              0x2000  /* status: no error               */
#define E100_CB_EL               0x8000  /* command: end of list           */
#define E100_CB_S               0x4000  /* command: suspend after this CB */
#define E100_CB_SF              0x0008  /* command: flexible mode (SDM 6.4.2.5) */
#define E100_CB_NOP             0x0000
#define E100_CB_IAS             0x0001
#define E100_CB_CONFIGURE       0x0002
#define E100_CB_MCAS            0x0003
#define E100_CB_XMIT            0x0004

#define E100_NO_LINK            0xFFFFFFFFUL
#define E100_MAX_FRAME          1514    /* the chip appends the CRC       */

/* Transmit CB in flexible mode, with one TBD (SDM 6.4.2.5): tbdArray is
 * the physical address of the TBD, byteCount is 0 because the data comes
 * from the TBD, and tbdNumber is 1. */
typedef struct {
    E100CBHeader                hdr;
    volatile unsigned long      tbdArray;       /* physical address of the TBD */
    volatile unsigned short     byteCount;      /* 0: data comes from the TBD */
    volatile unsigned char      threshold;      /* units of 8 bytes       */
    volatile unsigned char      tbdNumber;      /* 1                      */
    unsigned char               data[E100_MAX_FRAME];
} E100TxCB;

/* TBD dword 1 (SDM 6.4.2.5): 13:0 count, bit 16 EL (last TBD) */
#define E100_TBD_EL              0x00010000UL

#define E100_CONFIG_BYTES       22

typedef struct {
    E100CBHeader                hdr;
    unsigned char               bytes[E100_CONFIG_BYTES];
} E100ConfigCB;

typedef struct {
    E100CBHeader                hdr;
    unsigned char               addr[6];
} E100IaCB;

#define E100_MAX_MCAST          32

typedef struct {
    E100CBHeader                hdr;
    volatile unsigned short     byteCount;      /* 6 per address          */
    unsigned char               addr[E100_MAX_MCAST * 6];
} E100McastCB;

/* Receive frame descriptor, simplified mode (SDM 6.4.3.1) */
#define E100_RFD_BUF            1520

typedef struct {
    volatile unsigned short     status;
    volatile unsigned short     command;
    volatile unsigned long      link;
    volatile unsigned long      rbdPointer;     /* unused: E100_NO_LINK   */
    volatile unsigned short     actualCount;    /* 13:0 count, F, EOF     */
    volatile unsigned short     size;
    unsigned char               data[E100_RFD_BUF];
} E100Rfd;

#define E100_RFD_C              0x8000
#define E100_RFD_OK             0x2000
#define E100_RFD_ERRORS         0x0F80  /* CRC, align, no-res, overrun, short */
#define E100_RFD_EL             0x8000
#define E100_RFD_COUNT_MASK     0x3FFF

/* Statistics dump (SDM 6.3.2.4), indexed in dwords */
#define E100_STAT_TX_GOOD       0
#define E100_STAT_TX_MAXCOL     1
#define E100_STAT_TX_LATECOL    2
#define E100_STAT_TX_UNDERRUN   3
#define E100_STAT_TX_LOSTCRS    4
#define E100_STAT_TX_TOTALCOL   8
#define E100_STAT_RX_GOOD       9
#define E100_STAT_RX_CRC        10
#define E100_STAT_RX_ALIGN      11
#define E100_STAT_RX_RESOURCE   12
#define E100_STAT_RX_OVERRUN    13
#define E100_STAT_RX_SHORT      15
#define E100_STATS_DWORDS       21      /* the largest layout, completion too */
#define E100_DUMP_RESET_DONE    0x0000A007UL

#endif
